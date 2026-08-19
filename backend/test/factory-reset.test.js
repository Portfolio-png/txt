const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// The nuke: POST /api/admin/factory-reset. Its own temp DB, because the last
// assertion genuinely wipes everything.

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

async function postJson(baseUrl, pathName, token, body) {
  const response = await fetch(`${baseUrl}${pathName}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body ?? {}),
  });
  return { status: response.status, body: await response.json() };
}

async function getJson(baseUrl, pathName, token) {
  const response = await fetch(`${baseUrl}${pathName}`, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  return { status: response.status, body: await response.json() };
}

test('factory reset is super_admin only and needs the confirmation phrase', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-factory-reset-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'owner@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const owner = (
      await postJson(baseUrl, '/api/auth/login', null, {
        email: 'owner@paper.local',
        password: 'OwnerPass1234',
      })
    ).body;
    assert.equal(owner.user.role, 'super_admin');

    // An admin — not a super admin — must not be able to nuke the workspace.
    const adminCreate = await postJson(baseUrl, '/api/admins', owner.token, {
      name: 'Ops Admin',
      email: 'ops@paper.local',
      password: 'TeamPass1234',
    });
    assert.equal(adminCreate.status, 201);
    const admin = (
      await postJson(baseUrl, '/api/auth/login', null, {
        email: 'ops@paper.local',
        password: 'TeamPass1234',
      })
    ).body;
    assert.equal(admin.user.role, 'admin');

    const adminAttempt = await postJson(
      baseUrl,
      '/api/admin/factory-reset',
      admin.token,
      { confirm: 'FACTORY RESET' },
    );
    assert.equal(adminAttempt.status, 403);

    // Unauthenticated is rejected too.
    const anonAttempt = await postJson(
      baseUrl,
      '/api/admin/factory-reset',
      null,
      { confirm: 'FACTORY RESET' },
    );
    assert.equal(anonAttempt.status, 401);

    // Super admin, but no confirmation phrase: refused, nothing deleted.
    const noConfirm = await postJson(
      baseUrl,
      '/api/admin/factory-reset',
      owner.token,
      {},
    );
    assert.equal(noConfirm.status, 400);
    const wrongConfirm = await postJson(
      baseUrl,
      '/api/admin/factory-reset',
      owner.token,
      { confirm: 'factory reset' },
    );
    assert.equal(wrongConfirm.status, 400);

    // Still intact after the refused attempts.
    const itemsBefore = await getJson(baseUrl, '/api/items', owner.token);
    assert.equal(itemsBefore.status, 200);
    assert.ok(
      itemsBefore.body.items.length > 0,
      'demo seed should have left items behind',
    );

    // The real thing.
    const nuke = await postJson(
      baseUrl,
      '/api/admin/factory-reset',
      owner.token,
      { confirm: 'FACTORY RESET' },
    );
    assert.equal(nuke.status, 200);
    assert.equal(nuke.body.success, true);

    // Every business row is gone, and the super admin was re-bootstrapped so
    // the workspace is still reachable.
    const after = (
      await postJson(baseUrl, '/api/auth/login', null, {
        email: 'owner@paper.local',
        password: 'OwnerPass1234',
      })
    ).body;
    assert.ok(after.token, 'super admin must survive a factory reset');
    const itemsAfter = await getJson(baseUrl, '/api/items', after.token);
    assert.equal(itemsAfter.status, 200);
    assert.deepEqual(itemsAfter.body.items, []);

    // The admin account is gone with everything else.
    const adminAfter = await postJson(baseUrl, '/api/auth/login', null, {
      email: 'ops@paper.local',
      password: 'TeamPass1234',
    });
    assert.equal(adminAfter.status, 401);
  } finally {
    await closeServer(server);
  }
});
