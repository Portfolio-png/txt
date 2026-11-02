const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// A company's documents: named files of any kind (a PDF, a picture, a
// spreadsheet) kept on a client or a contractor beside its photos — but never
// one of them. Taken from the PC, or asked of the phone by name.

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
    server.on('error', reject);
  });
}

const sha = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');

test('a company keeps named documents of any kind, apart from its logo', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-company-documents-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_UPLOAD_DIR = path.join(tempDir, 'uploads');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'docs@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete process.env.PAPER_S3_BUCKET_NAME;
  delete process.env.S3_BUCKET;

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const base = `http://127.0.0.1:${port}`;

  const token = (await (await fetch(`${base}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Client-Platform': 'desktop' },
    body: JSON.stringify({ email: 'docs@paper.local', password: 'OwnerPass1234' }),
  })).json()).token;
  const call = async (method, url, body) => {
    const response = await fetch(`${base}${url}`, {
      method,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: response.status, body: await response.json() };
  };
  /// intent -> PUT to the local store -> complete, as the app does it.
  const upload = async ({ entityType, entityId, bytes, fileName, contentType, documentTitle, uploadType }) => {
    const intent = await call('POST', '/api/assets/upload-intent', {
      uploadType: uploadType || 'PARTY_DOCUMENT',
      entityType,
      entityId,
      fileName,
      contentType,
      sizeBytes: bytes.length,
      sha256: sha(bytes),
      documentTitle,
    });
    if (intent.status >= 400) return intent;
    if (intent.body.intent.alreadyUploaded) return { status: 200, body: { asset: intent.body.intent.asset } };
    const { upload: target } = intent.body.intent;
    const put = await fetch(target.uploadUrl, { method: 'PUT', headers: target.headers, body: bytes });
    assert.equal(put.status, 200, `stored: ${await put.text()}`);
    return call('POST', '/api/assets/upload-complete', {
      uploadSessionId: target.uploadSessionId,
      objectKey: target.objectKey,
    });
  };
  const documentsOf = async (entityType, entityId) =>
    (await call('GET', `/api/assets/documents?entityType=${entityType}&entityId=${entityId}`)).body.documents;

  try {
    const createdClient = await call('POST', '/api/clients', { name: 'Kapoor Papers', gstNumber: '27KPRPA9876Q1Z2', address: 'Pune' });
    const client = createdClient.body.client;
    assert.ok(client?.id, JSON.stringify(createdClient.body));

    // A PDF, named by the user.
    const pdf = Buffer.from('%PDF-1.4\n% a GST certificate\n%%EOF\n');
    const made = await upload({
      entityType: 'client', entityId: client.id, bytes: pdf,
      fileName: 'gst.pdf', contentType: 'application/pdf', documentTitle: '  GST   certificate ',
    });
    assert.equal(made.status, 200, JSON.stringify(made.body));
    assert.equal(made.body.asset.documentTitle, 'GST certificate');
    assert.equal(made.body.asset.isPrimary, false, 'a document is never the picture');

    let docs = await documentsOf('client', client.id);
    assert.deepEqual(docs.map((d) => [d.documentTitle, d.contentType, d.fileName]), [
      ['GST certificate', 'application/pdf', 'gst.pdf'],
    ]);

    // Served as a PDF, inline, and not sniffed.
    const served = await fetch(docs[0].readUrl);
    assert.equal(served.status, 200);
    assert.equal(served.headers.get('content-type'), 'application/pdf');
    assert.equal(served.headers.get('x-content-type-options'), 'nosniff');
    assert.match(served.headers.get('content-disposition'), /^inline; filename="gst.pdf"/);
    assert.equal(Buffer.from(await served.arrayBuffer()).toString(), pdf.toString());

    // The logo did not move: no photo, no logo_url, nothing primary.
    assert.equal((await call('GET', `/api/clients/${client.id}`)).body.client?.logoUrl || '', '');
    const primary = await call('POST', '/api/assets/primary', { entityType: 'client', entityIds: [client.id] });
    assert.deepEqual(primary.body.photos, {});
    assert.equal(
      (await call('PATCH', `/api/assets/${made.body.asset.id}/primary`)).status,
      400,
      'a document cannot be made the photo',
    );

    // A real logo afterwards is still the logo, and is not listed as a document.
    const png = Buffer.from('89504e470d0a1a0a0000000d49484452', 'hex');
    const logo = await upload({
      entityType: 'client', entityId: client.id, bytes: png,
      fileName: 'logo.png', contentType: 'image/png', uploadType: 'PARTY_IMAGE',
    });
    assert.equal(logo.body.asset.isPrimary, true);
    assert.equal((await documentsOf('client', client.id)).length, 1);

    // The same file under a second name is a second document; under the same
    // name it is the one already there.
    const copy = await upload({
      entityType: 'client', entityId: client.id, bytes: pdf,
      fileName: 'gst.pdf', contentType: 'application/pdf', documentTitle: 'GST (copy for bank)',
    });
    assert.notEqual(copy.body.asset.id, made.body.asset.id);
    const same = await upload({
      entityType: 'client', entityId: client.id, bytes: pdf,
      fileName: 'gst.pdf', contentType: 'application/pdf', documentTitle: 'GST certificate',
    });
    assert.equal(same.body.asset.id, made.body.asset.id);

    // Anything at all: a spreadsheet is stored, and served as a download.
    const sheet = Buffer.from('PK\u0003\u0004 not really a workbook');
    const xlsx = await upload({
      entityType: 'client', entityId: client.id, bytes: sheet, fileName: 'rates.xlsx',
      contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      documentTitle: 'Rate card',
    });
    assert.equal(xlsx.status, 200, JSON.stringify(xlsx.body));
    const rateCard = (await documentsOf('client', client.id)).find((d) => d.documentTitle === 'Rate card');
    const download = await fetch(rateCard.readUrl);
    assert.equal(download.headers.get('content-type'), 'application/octet-stream');
    assert.match(download.headers.get('content-disposition'), /^attachment; filename="rates.xlsx"/);

    // Newest first.
    assert.deepEqual((await documentsOf('client', client.id)).map((d) => d.documentTitle), [
      'Rate card', 'GST (copy for bank)', 'GST certificate',
    ]);

    // What is refused: no name, too big, a kind of record without documents.
    const noName = await call('POST', '/api/assets/upload-intent', {
      entityType: 'client', entityId: client.id, fileName: 'x.pdf', contentType: 'application/pdf',
      sizeBytes: 10, sha256: sha(Buffer.from('x')), documentTitle: '   ',
    });
    assert.equal(noName.status, 400);
    assert.match(noName.body.error, /name/);
    const tooBig = await call('POST', '/api/assets/upload-intent', {
      entityType: 'client', entityId: client.id, fileName: 'x.pdf', contentType: 'application/pdf',
      sizeBytes: 26 * 1024 * 1024, sha256: sha(Buffer.from('y')), documentTitle: 'Huge',
    });
    assert.equal(tooBig.status, 400);
    assert.match(tooBig.body.error, /25 MB/);
    assert.equal((await call('POST', '/api/assets/upload-intent', {
      entityType: 'die', entityId: 1, fileName: 'x.pdf', contentType: 'application/pdf',
      sizeBytes: 10, sha256: sha(Buffer.from('z')), documentTitle: 'Drawing',
    })).status, 400);
    // A photo upload is still images only.
    assert.equal((await call('POST', '/api/assets/upload-intent', {
      uploadType: 'PARTY_IMAGE', entityType: 'client', entityId: client.id, fileName: 'x.pdf',
      contentType: 'application/pdf', sizeBytes: 10, sha256: sha(Buffer.from('w')),
    })).status, 400);

    // Rename, then remove.
    const renamed = await call('PATCH', `/api/assets/${copy.body.asset.id}/title`, { title: 'GST for bank' });
    assert.equal(renamed.status, 200);
    assert.equal(renamed.body.document.documentTitle, 'GST for bank');
    assert.equal((await call('PATCH', `/api/assets/${copy.body.asset.id}/title`, { title: '' })).status, 400);
    assert.equal(
      (await call('PATCH', `/api/assets/${logo.body.asset.id}/title`, { title: 'Logo' })).status,
      404,
      'a photo is not renamed into a document',
    );
    assert.equal((await call('DELETE', `/api/assets/${copy.body.asset.id}`)).status, 200);
    assert.deepEqual((await documentsOf('client', client.id)).map((d) => d.documentTitle), [
      'Rate card', 'GST certificate',
    ]);
    assert.equal(
      (await call('POST', '/api/assets/primary', { entityType: 'client', entityIds: [client.id] })).body.photos[client.id].assetId,
      logo.body.asset.id,
      'removing a document leaves the logo alone',
    );

    // A contractor keeps its own.
    const contractor = (await call('POST', `/api/clients/${client.id}/sub-contractors`, { name: 'Shinde Works' })).body.subContractor;
    assert.ok(contractor?.id);
    const contract = await upload({
      entityType: 'sub_contractor', entityId: contractor.id, bytes: Buffer.from('%PDF-1.4 contract'),
      fileName: 'contract.pdf', contentType: 'application/pdf', documentTitle: 'Job-work contract',
    });
    assert.equal(contract.status, 200, JSON.stringify(contract.body));
    assert.deepEqual((await documentsOf('sub_contractor', contractor.id)).map((d) => d.documentTitle), ['Job-work contract']);
    assert.equal((await documentsOf('client', client.id)).length, 2, 'the client\'s are its own');

    // Asked of the phone by name: one job per document name, not per company.
    const askGst = await call('POST', '/api/photo-requests', {
      entityType: 'client', entityId: client.id, documentTitle: 'Visiting card',
    });
    assert.equal(askGst.status, 201);
    assert.equal(askGst.body.request.documentTitle, 'Visiting card');
    assert.deepEqual(askGst.body.request.details, {
      kind: 'Document',
      title: 'Visiting card',
      lines: [
        { label: 'Company', value: 'Kapoor Papers' },
        { label: 'GST', value: '27KPRPA9876Q1Z2' },
      ],
    });
    const askOther = await call('POST', '/api/photo-requests', {
      entityType: 'client', entityId: client.id, documentTitle: 'Factory gate',
    });
    assert.equal(askOther.status, 201, 'a second document is a second job');
    const askAgain = await call('POST', '/api/photo-requests', {
      entityType: 'client', entityId: client.id, documentTitle: 'Visiting card',
    });
    assert.equal(askAgain.status, 200);
    assert.equal(askAgain.body.request.id, askGst.body.request.id);
    const askLogo = await call('POST', '/api/photo-requests', { entityType: 'client', entityId: client.id });
    assert.equal(askLogo.status, 201, 'the logo is its own job');
    assert.equal(askLogo.body.request.details.kind, 'Company logo');
    const askContractor = await call('POST', '/api/photo-requests', {
      entityType: 'sub_contractor', entityId: contractor.id, documentTitle: 'Shop photo',
    });
    assert.equal(askContractor.status, 201);
    assert.deepEqual(askContractor.body.request.details.lines.map((l) => l.label), ['Contractor', 'For']);
    assert.equal((await call('POST', '/api/photo-requests', {
      entityType: 'die', entityId: 1, documentTitle: 'Drawing',
    })).status, 400);

    const pending = (await call('GET', '/api/photo-requests')).body.requests;
    assert.deepEqual(
      pending.map((r) => [r.entityType, r.documentTitle]),
      [['client', 'Visiting card'], ['client', 'Factory gate'], ['client', null], ['sub_contractor', 'Shop photo']],
    );
  } finally {
    server.closeAllConnections?.();
    await new Promise((resolve) => server.close(() => resolve()));
  }
});
