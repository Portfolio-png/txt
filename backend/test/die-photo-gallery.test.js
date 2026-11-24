const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const http = require('node:http');
const path = require('node:path');
const test = require('node:test');
const { makeTempDir } = require('./helpers/temp-dir');

// A die's photos, up to five, as a part's are (2026-11-24): every upload is
// kept, the gallery reads them in order, one PUT sets the order and the main
// one, and the server holds the limit.

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
    server.on('error', reject);
  });
}

const photoBytes = (n) => Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.from(`die photo ${n}`)]);
const thumbBytes = (n) => Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.from(`die thumb ${n}`)]);
const sha = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');

test('a die keeps up to five photos, read and arranged through its own routes', async () => {
  const tempDir = makeTempDir('paper-die-gallery-');
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_UPLOAD_DIR = path.join(tempDir, 'uploads');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'die-gallery@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete process.env.PAPER_S3_BUCKET_NAME;
  delete process.env.S3_BUCKET;
  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const base = `http://127.0.0.1:${port}`;
  const local = (url) => {
    const parsed = new URL(url);
    return `${base}${parsed.pathname}${parsed.search}`;
  };
  try {
    const { token } = await fetch(`${base}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'die-gallery@paper.local', password: 'OwnerPass1234' }),
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

    const made = await call('POST', '/api/dies', { name: 'Gallery Die', toolCode: 'GD-1', status: 'Active', ownership: 'Owned' });
    assert.equal(made.status, 200, JSON.stringify(made.body));
    const dieId = Number(made.body.die.id);

    const intentFor = (n) => call('POST', '/api/assets/upload-intent', {
      uploadType: 'DIE_IMAGE',
      entityType: 'die',
      entityId: dieId,
      fileName: `die-${n}.jpg`,
      contentType: 'image/jpeg',
      sizeBytes: photoBytes(n).length,
      sha256: sha(photoBytes(n)),
      isPrimary: false,
      thumbnail: { sizeBytes: thumbBytes(n).length, sha256: sha(thumbBytes(n)) },
      width: 1200,
      height: 900,
    });
    async function upload(n) {
      const intent = await intentFor(n);
      assert.equal(intent.status, 201, JSON.stringify(intent.body));
      const { upload: slot } = intent.body.intent;
      for (const [url, body] of [[slot.uploadUrl, photoBytes(n)], [slot.thumbnail.uploadUrl, thumbBytes(n)]]) {
        const put = await fetch(local(url), { method: 'PUT', headers: { 'Content-Type': 'image/jpeg' }, body });
        assert.equal(put.status, 200);
      }
      const done = await call('POST', '/api/assets/upload-complete', {
        uploadSessionId: slot.uploadSessionId,
        objectKey: slot.objectKey,
      });
      assert.equal(done.status, 200, JSON.stringify(done.body));
      return done.body.asset;
    }

    for (let n = 1; n <= 5; n += 1) await upload(n);
    const listed = await call('GET', `/api/dies/${dieId}/photos`);
    assert.equal(listed.status, 200, JSON.stringify(listed.body));
    assert.equal(listed.body.photos.length, 5, 'every upload kept, not replaced');
    assert.equal(listed.body.limit, 5);

    const sixth = await intentFor(6);
    assert.equal(sixth.status, 409, 'the server holds the limit');
    assert.match(sixth.body.error, /A die keeps up to 5 photos/);

    const ids = listed.body.photos.map((p) => p.id);
    const reversed = [...ids].reverse();
    const arranged = await call('PUT', `/api/dies/${dieId}/photos`, { order: reversed, primaryId: reversed[0] });
    assert.equal(arranged.status, 200, JSON.stringify(arranged.body));
    assert.deepEqual(arranged.body.photos.map((p) => p.id), reversed);
    assert.equal(arranged.body.photos.find((p) => p.isPrimary).id, reversed[0]);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await backend.closeDb();
  }
});
