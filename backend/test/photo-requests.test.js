const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// The desktop asks the phone to take a photo: a click on a photo slot files a
// request for the person who clicked, their phone (logged in as them at the
// same time) lists it with the record's details, takes the photo through the
// ordinary asset routes, and closes the job. Both screens hear about it live.

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
    server.on('error', reject);
  });
}

function closeServer(server) {
  return new Promise((resolve) => {
    server.closeAllConnections?.();
    server.close(() => resolve());
  });
}

/// Reads an SSE stream into a list of {event, data} custom events.
function watch(base, token) {
  const controller = new AbortController();
  const seen = [];
  const done = (async () => {
    try {
      const response = await fetch(`${base}/api/events`, {
        headers: { Authorization: `Bearer ${token}` },
        signal: controller.signal,
      });
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';
      for (;;) {
        const { value, done: end } = await reader.read();
        if (end) break;
        buffer += decoder.decode(value, { stream: true });
        let cut;
        while ((cut = buffer.indexOf('\n\n')) >= 0) {
          const block = buffer.slice(0, cut);
          buffer = buffer.slice(cut + 2);
          if (!block.includes('event: custom-event')) continue;
          const line = block.split('\n').find((l) => l.startsWith('data: '));
          if (line) seen.push(JSON.parse(line.slice(6)));
        }
      }
    } catch (_) {
      // aborted
    }
  })();
  return { seen, stop: async () => { controller.abort(); await done; } };
}

const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

test('the desktop queues a photo, the same user\'s phone takes it', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-photo-requests-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_UPLOAD_DIR = path.join(tempDir, 'uploads');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'phone@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete process.env.PAPER_S3_BUCKET_NAME;
  delete process.env.S3_BUCKET;

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const base = `http://127.0.0.1:${port}`;

  const login = async (email, password, platform) => {
    const response = await fetch(`${base}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Client-Platform': platform },
      body: JSON.stringify({ email, password }),
    });
    return (await response.json()).token;
  };
  const call = async (token, method, url, body) => {
    const response = await fetch(`${base}${url}`, {
      method,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: response.status, body: await response.json() };
  };
  const watchers = [];

  try {
    // One person, two devices: the phone login must not end the desktop's.
    const desktop = await login('phone@paper.local', 'OwnerPass1234', 'desktop');
    const phone = await login('phone@paper.local', 'OwnerPass1234', 'mobile');
    assert.equal((await call(desktop, 'GET', '/api/auth/me')).status, 200, 'desktop still signed in');
    assert.equal((await call(phone, 'GET', '/api/auth/me')).status, 200, 'phone signed in');

    const made = await call(desktop, 'POST', '/api/dies', {
      toolCode: 'CDHH1', dieType: 'cutting', madeBy: 'Ashok Dies', rackNo: 'R-12', status: 'Active', ownership: 'Owned',
    });
    const die = made.body.die;
    assert.ok(die?.id, `die created: ${made.status} ${JSON.stringify(made.body)}`);

    const desktopStream = watch(base, desktop);
    const phoneStream = watch(base, phone);
    watchers.push(desktopStream, phoneStream);
    await pause(300);

    // Filed from the desktop, with where the slot sits.
    const created = await call(desktop, 'POST', '/api/photo-requests', {
      entityType: 'die', entityId: Number(die.id), context: 'for part HH1',
    });
    assert.equal(created.status, 201);
    const request = created.body.request;
    assert.equal(request.status, 'pending');
    assert.deepEqual(request.details, {
      kind: 'Die',
      title: 'CDHH1',
      lines: [
        { label: 'Type', value: 'Cutting' },
        { label: 'Made by', value: 'Ashok Dies' },
        { label: 'Kept', value: 'Rack R-12' },
      ],
    });

    // A second click on the same slot is the same job.
    const again = await call(desktop, 'POST', '/api/photo-requests', { entityType: 'die', entityId: Number(die.id) });
    assert.equal(again.status, 200);
    assert.equal(again.body.request.id, request.id);

    // The phone lists it, details and context included.
    const pending = await call(phone, 'GET', '/api/photo-requests?status=pending');
    assert.equal(pending.status, 200);
    assert.deepEqual(pending.body.requests.map((r) => [r.id, r.context]), [[request.id, 'for part HH1']]);
    assert.equal(pending.body.requests[0].details.title, 'CDHH1');

    // The phone heard about it live.
    await pause(300);
    assert.ok(
      phoneStream.seen.some((e) => e.event === 'photo_requests_changed'),
      'the phone gets photo_requests_changed',
    );

    // It closes, and only once.
    const complete = await call(phone, 'POST', `/api/photo-requests/${request.id}/complete`, { assetId: 0 });
    assert.equal(complete.status, 200);
    assert.equal((await call(phone, 'POST', `/api/photo-requests/${request.id}/complete`, {})).status, 409);
    assert.deepEqual((await call(phone, 'GET', '/api/photo-requests')).body.requests, []);

    // Skip and cancel close it the same way.
    const second = (await call(desktop, 'POST', '/api/photo-requests', { entityType: 'die', entityId: Number(die.id) })).body.request;
    assert.equal((await call(phone, 'POST', `/api/photo-requests/${second.id}/skip`)).status, 200);
    const third = (await call(desktop, 'POST', '/api/photo-requests', { entityType: 'die', entityId: Number(die.id) })).body.request;
    assert.equal((await call(desktop, 'DELETE', `/api/photo-requests/${third.id}`)).status, 200);

    // A record that is not there, or a kind that has no photo.
    assert.equal((await call(desktop, 'POST', '/api/photo-requests', { entityType: 'die', entityId: 999999 })).status, 404);
    assert.equal((await call(desktop, 'POST', '/api/photo-requests', { entityType: 'order', entityId: 1 })).status, 400);

    // Another person: cannot see, close or be told about someone else's jobs,
    // and cannot ask for a photo of a record they may not change.
    assert.equal((await call(desktop, 'POST', '/api/users', {
      name: 'Floor User', email: 'floor@paper.local', password: 'WorkerPass1234',
    })).status, 201);
    const floorId = (await call(desktop, 'GET', '/api/users')).body.users.find((u) => u.email === 'floor@paper.local').id;
    await call(desktop, 'PATCH', `/api/users/${floorId}/permissions`, {
      overrides: [{ key: 'dies.update', allowed: false }],
    });
    const floor = await login('floor@paper.local', 'WorkerPass1234', 'desktop');
    const floorStream = watch(base, floor);
    watchers.push(floorStream);
    await pause(300);

    const fourth = (await call(desktop, 'POST', '/api/photo-requests', { entityType: 'die', entityId: Number(die.id) })).body.request;
    await pause(300);
    assert.deepEqual((await call(floor, 'GET', '/api/photo-requests')).body.requests, []);
    assert.equal((await call(floor, 'POST', `/api/photo-requests/${fourth.id}/skip`)).status, 404);
    assert.ok(
      !floorStream.seen.some((e) => e.event === 'photo_requests_changed'),
      'another user is not told about someone else\'s queue',
    );
    assert.equal(
      (await call(floor, 'POST', '/api/photo-requests', { entityType: 'die', entityId: Number(die.id) })).status,
      403,
    );

    // A second desktop login still ends the first.
    await login('phone@paper.local', 'OwnerPass1234', 'desktop');
    assert.equal((await call(desktop, 'GET', '/api/auth/me')).status, 401, 'the older desktop session ended');
    assert.equal((await call(phone, 'GET', '/api/auth/me')).status, 200, 'the phone stayed signed in');
  } finally {
    for (const w of watchers) await w.stop();
    await closeServer(server);
  }
});

test('every photo upload is announced, so open screens re-read it', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-asset-changed-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_UPLOAD_DIR = path.join(tempDir, 'uploads');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'announce@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete process.env.PAPER_S3_BUCKET_NAME;
  delete process.env.S3_BUCKET;

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const base = `http://127.0.0.1:${port}`;
  const seen = [];
  const listener = (payload) => seen.push(payload);
  backend.changeEmitter?.on('custom-event', listener);
  try {
    assert.ok(backend.changeEmitter, 'server exports its change emitter');
    const { token } = await fetch(`${base}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'announce@paper.local', password: 'OwnerPass1234' }),
    }).then((r) => r.json());
    const headers = { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` };
    const client = await fetch(`${base}/api/clients`, {
      method: 'POST', headers, body: JSON.stringify({ name: 'Announce Co' }),
    }).then((r) => r.json());
    const person = await fetch(`${base}/api/clients/${client.client.id}/contacts`, {
      method: 'POST', headers, body: JSON.stringify({ name: 'Ravi' }),
    }).then((r) => r.json());

    const png = Buffer.from(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      'base64',
    );
    const sha256 = require('node:crypto').createHash('sha256').update(png).digest('hex');
    const intent = await fetch(`${base}/api/assets/upload-intent`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        uploadType: 'PARTY_IMAGE', entityType: 'party_contact', entityId: person.contact.id,
        fileName: 'ravi.png', contentType: 'image/png', sizeBytes: png.length, sha256, isPrimary: true,
      }),
    }).then((r) => r.json());
    const upload = intent.intent.upload;
    const put = new URL(upload.uploadUrl);
    await fetch(`${base}${put.pathname}${put.search}`, { method: 'PUT', headers: upload.headers, body: png });
    const done = await fetch(`${base}/api/assets/upload-complete`, {
      method: 'POST', headers, body: JSON.stringify({ uploadSessionId: upload.uploadSessionId, objectKey: upload.objectKey }),
    });
    assert.equal(done.status, 200);
    assert.ok(
      seen.some((e) => e.event === 'asset_changed'
        && e.data.entityType === 'party_contact'
        && e.data.entityId === Number(person.contact.id)),
      'a person\'s photo announces asset_changed',
    );
  } finally {
    backend.changeEmitter?.off('custom-event', listener);
    await closeServer(server);
  }
});
