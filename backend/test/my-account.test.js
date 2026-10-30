const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// Your own Account & Access, from the profile: your trail, your sessions and
// your password are yours, whatever your permissions say about other people's.

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
    server.on('error', reject);
  });
}

test('your own account: trail, sessions and password', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-my-account-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'me@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const base = `http://127.0.0.1:${port}`;

  const login = async (email, password, platform = 'desktop') => {
    const response = await fetch(`${base}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Client-Platform': platform },
      body: JSON.stringify({ email, password }),
    });
    return response.json();
  };
  const call = async (token, method, url, body) => {
    const response = await fetch(`${base}${url}`, {
      method,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: response.status, body: await response.json() };
  };

  try {
    const owner = await login('me@paper.local', 'OwnerPass1234');
    assert.equal((await call(owner.token, 'POST', '/api/users', {
      name: 'Floor User', email: 'floor@paper.local', password: 'WorkerPass1234',
    })).status, 201);

    const floor = await login('floor@paper.local', 'WorkerPass1234');
    assert.ok(!floor.user.permissions.includes('audit.read'), 'staff have no audit.read');

    // Their own trail: yes. Someone else's: still audit.read.
    const own = await call(floor.token, 'GET', `/api/track/actor/${floor.user.id}`);
    assert.equal(own.status, 200);
    assert.ok(Array.isArray(own.body.events));
    assert.equal((await call(floor.token, 'GET', `/api/track/actor/${owner.user.id}`)).status, 403);
    assert.equal((await call(owner.token, 'GET', `/api/track/actor/${floor.user.id}`)).status, 200);

    // Their own sessions, each saying which kind of device, and which is this one.
    await login('floor@paper.local', 'WorkerPass1234', 'mobile');
    const sessions = await call(floor.token, 'GET', '/api/auth/sessions');
    assert.equal(sessions.status, 200);
    const live = sessions.body.sessions.filter((s) => !s.revokedAt);
    assert.deepEqual(live.map((s) => s.clientPlatform).sort(), ['desktop', 'mobile']);
    assert.ok(live.some((s) => s.id === sessions.body.currentSessionId), 'this device is marked');

    // Their own password: the current one is asked for.
    const wrong = await call(floor.token, 'PATCH', '/api/me/password', {
      currentPassword: 'NotMyPassword1', newPassword: 'NewWorker5678x',
    });
    assert.equal(wrong.status, 401);
    const right = await call(floor.token, 'PATCH', '/api/me/password', {
      currentPassword: 'WorkerPass1234', newPassword: 'NewWorker5678x',
    });
    assert.equal(right.status, 200);
    assert.ok((await login('floor@paper.local', 'NewWorker5678x')).token, 'the new password signs in');
  } finally {
    server.closeAllConnections?.();
    await new Promise((resolve) => server.close(() => resolve()));
  }
});
