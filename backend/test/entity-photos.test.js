const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { mkdtempSync, existsSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// Photos for a company, a person and a part, with no S3 bucket configured.
// Uploads were S3-only and answered 503 without one; now a folder on this
// machine stands in, behind the same intent → PUT → complete → read flow and
// with signed URLs an <img> can load.

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => {
      resolve({ server, port: server.address().port });
    });
    server.on('error', reject);
  });
}

function closeServer(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}

// A real 1x1 PNG.
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64',
);

test('a logo and a person\'s photo store and read back without S3', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-photos-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_UPLOAD_DIR = path.join(tempDir, 'uploads');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'photos@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete process.env.PAPER_S3_BUCKET_NAME;
  delete process.env.S3_BUCKET;

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const base = `http://127.0.0.1:${port}`;
  // The signed URLs name the configured public address; the test server is
  // on a random port, so only their path and query are used.
  const local = (url) => {
    const parsed = new URL(url);
    return `${base}${parsed.pathname}${parsed.search}`;
  };

  try {
    const { token } = await fetch(`${base}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'photos@paper.local', password: 'OwnerPass1234' }),
    }).then((r) => r.json());
    const headers = { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` };
    const call = async (method, url, body) => {
      const response = await fetch(`${base}${url}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      return { status: response.status, body: await response.json() };
    };

    const client = (await call('POST', '/api/clients', { name: 'Logo Co' })).body.client;
    const person = (
      await call('POST', `/api/clients/${client.id}/contacts`, {
        name: 'Ravi',
        designation: 'Purchase',
      })
    ).body.contact;

    const sha256 = crypto.createHash('sha256').update(PNG).digest('hex');
    async function upload(entityType, entityId, fileName) {
      const intent = await call('POST', '/api/assets/upload-intent', {
        uploadType: 'PARTY_IMAGE',
        entityType,
        entityId,
        fileName,
        contentType: 'image/png',
        sizeBytes: PNG.length,
        sha256,
        isPrimary: true,
      });
      assert.equal(intent.status, 201, JSON.stringify(intent.body));
      const { uploadUrl, uploadSessionId, objectKey } = intent.body.intent.upload;
      const put = await fetch(local(uploadUrl), {
        method: 'PUT',
        headers: { 'Content-Type': 'image/png' },
        body: PNG,
      });
      assert.equal(put.status, 200);
      const done = await call('POST', '/api/assets/upload-complete', {
        uploadSessionId,
        objectKey,
      });
      assert.equal(done.status, 200, JSON.stringify(done.body));
      return { ...done.body.asset, uploadUrl, objectKey };
    }

    const logo = await upload('client', client.id, 'logo.png');
    assert.ok(existsSync(path.join(tempDir, 'uploads', logo.objectKey)));
    const fetched = await fetch(local(logo.readUrl));
    assert.equal(fetched.status, 200);
    assert.equal(fetched.headers.get('content-type'), 'image/png');
    assert.deepEqual(Buffer.from(await fetched.arrayBuffer()), PNG);

    const photo = await upload('party_contact', person.id, 'ravi.png');
    assert.ok(photo.readUrl);

    // Many at once, for a table of thumbnails.
    const logos = await call('POST', '/api/assets/primary', {
      entityType: 'client',
      entityIds: [client.id, 999999],
    });
    assert.equal(logos.status, 200);
    assert.deepEqual(Object.keys(logos.body.photos), [String(client.id)]);
    assert.equal(logos.body.photos[client.id].assetId, logo.id);

    // A tampered or expired link is refused; so is a key that climbs out.
    const bad = new URL(logo.readUrl);
    bad.searchParams.set('sig', '0'.repeat(64));
    assert.equal((await fetch(local(bad.toString()))).status, 403);
    const old = new URL(logo.readUrl);
    old.searchParams.set('exp', '1');
    assert.equal((await fetch(local(old.toString()))).status, 403);
    const climb = await fetch(`${base}/api/assets/local/..%2F..%2Fpaper.db?exp=9999999999&sig=x`);
    assert.ok([400, 403].includes(climb.status), `got ${climb.status}`);

    // Only images are stored, even behind a valid link.
    const text = await fetch(local(logo.uploadUrl), {
      method: 'PUT',
      headers: { 'Content-Type': 'text/plain' },
      body: 'not a picture',
    });
    assert.equal(text.status, 415);

    // Removed, it is no longer the company's logo.
    assert.equal((await call('DELETE', `/api/assets/${logo.id}`)).status, 200);
    const after = await call('POST', '/api/assets/primary', {
      entityType: 'client',
      entityIds: [client.id],
    });
    assert.deepEqual(after.body.photos, {});
  } finally {
    await closeServer(server);
    delete process.env.PAPER_UPLOAD_DIR;
  }
});
