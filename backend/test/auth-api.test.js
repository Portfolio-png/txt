const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

test('auth roles and delete approval workflow', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-auth-api-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'owner@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass123';

  const backend = require('../server.js');
  await backend.initDb();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const unauthCreate = await fetch(`${baseUrl}/api/units`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'Box', symbol: 'box' }),
    });
    assert.equal(unauthCreate.status, 401);

    const owner = await login(baseUrl, 'owner@paper.local', 'OwnerPass123');
    assert.equal(owner.user.role, 'super_admin');
    const ownerSessions = await getJson(baseUrl, '/api/auth/sessions', owner.token);
    assert.equal(ownerSessions.status, 200);
    assert.ok(ownerSessions.body.sessions.length >= 1);

    const badLogin = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'owner@paper.local',
        password: 'wrong-password',
      }),
    });
    assert.equal(badLogin.status, 401);

    const adminResponse = await postJson(
      baseUrl,
      '/api/admins',
      owner.token,
      {
        name: 'Ops Admin',
        email: 'admin@paper.local',
        password: 'AdminPass123',
      },
    );
    assert.equal(adminResponse.status, 201);

    const admin = await login(baseUrl, 'admin@paper.local', 'AdminPass123');
    assert.equal(admin.user.role, 'admin');
    const adminPermissionCatalogDenied = await getJson(
      baseUrl,
      '/api/permissions',
      admin.token,
    );
    assert.equal(adminPermissionCatalogDenied.status, 403);

    const grantAdminPermissionMgmt = await patchJson(
      baseUrl,
      `/api/users/${admin.user.id}/permissions`,
      owner.token,
      {
        overrides: [{ key: 'users.manage_permissions', allowed: true }],
      },
    );
    assert.equal(grantAdminPermissionMgmt.status, 200);

    const adminPermissionCatalogAllowed = await getJson(
      baseUrl,
      '/api/permissions',
      admin.token,
    );
    assert.equal(adminPermissionCatalogAllowed.status, 200);
    assert.ok(adminPermissionCatalogAllowed.body.permissions.length >= 1);

    const adminCannotCreateAdmin = await postJson(
      baseUrl,
      '/api/admins',
      admin.token,
      {
        name: 'Second Admin',
        email: 'admin2@paper.local',
        password: 'AdminPass123',
      },
    );
    assert.equal(adminCannotCreateAdmin.status, 403);

    const userResponse = await postJson(
      baseUrl,
      '/api/users',
      admin.token,
      {
        name: 'Floor User',
        email: 'user@paper.local',
        password: 'UserPass123',
      },
    );
    assert.equal(userResponse.status, 201);

    const user = await login(baseUrl, 'user@paper.local', 'UserPass123');
    assert.equal(user.user.role, 'user');
    const userSessions = await getJson(baseUrl, '/api/auth/sessions', user.token);
    assert.equal(userSessions.status, 200);
    assert.ok(userSessions.body.sessions.length >= 1);

    const adminEscalationAttempt = await patchJson(
      baseUrl,
      `/api/users/${user.user.id}/permissions`,
      admin.token,
      {
        overrides: [{ key: 'users.create_admin', allowed: true }],
      },
    );
    assert.equal(adminEscalationAttempt.status, 403);

    const ownerRevokesAdminDelete = await patchJson(
      baseUrl,
      `/api/users/${admin.user.id}/permissions`,
      owner.token,
      {
        overrides: [{ key: 'inventory.delete', allowed: false }],
      },
    );
    assert.equal(ownerRevokesAdminDelete.status, 200);

    const resetUserPassword = await fetch(
      `${baseUrl}/api/users/${user.user.id}/password`,
      {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${admin.token}`,
        },
        body: JSON.stringify({ newPassword: 'UserPass456' }),
      },
    );
    assert.equal(resetUserPassword.status, 200);
    const oldUserTokenAfterReset = await getJson(baseUrl, '/api/materials', user.token);
    assert.equal(oldUserTokenAfterReset.status, 401);
    const userAfterReset = await login(baseUrl, 'user@paper.local', 'UserPass456');

    const resetAdminPassword = await fetch(
      `${baseUrl}/api/users/${admin.user.id}/password`,
      {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${admin.token}`,
        },
        body: JSON.stringify({ newPassword: 'AdminPass456' }),
      },
    );
    assert.equal(resetAdminPassword.status, 403);

    const lockoutTarget = await postJson(
      baseUrl,
      '/api/users',
      admin.token,
      {
        name: 'Lockout User',
        email: 'lockout@paper.local',
        password: 'LockoutPass123',
      },
    );
    assert.equal(lockoutTarget.status, 201);
    for (let attempt = 0; attempt < 5; attempt += 1) {
      const failed = await postJson(baseUrl, '/api/auth/login', null, {
        email: 'lockout@paper.local',
        password: 'wrong-password',
      });
      assert.equal(failed.status, 401);
    }
    const lockedLogin = await postJson(baseUrl, '/api/auth/login', null, {
      email: 'lockout@paper.local',
      password: 'LockoutPass123',
    });
    assert.equal(lockedLogin.status, 423);

    const materials = await getJson(baseUrl, '/api/materials', userAfterReset.token);
    const material = materials.body.materials[0];
    assert.ok(material?.barcode, 'expected seeded material');

    const directDelete = await fetch(
      `${baseUrl}/api/materials/${material.barcode}`,
      {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${userAfterReset.token}` },
      },
    );
    assert.equal(directDelete.status, 403);

    const adminDirectDeleteWithoutPermission = await fetch(
      `${baseUrl}/api/materials/${material.barcode}`,
      {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${admin.token}` },
      },
    );
    assert.equal(adminDirectDeleteWithoutPermission.status, 403);

    const requestDelete = await postJson(
      baseUrl,
      '/api/delete-requests',
      userAfterReset.token,
      {
        entityType: 'material',
        entityId: material.barcode,
        entityLabel: material.name,
        reason: 'Duplicate row',
      },
    );
    assert.equal(requestDelete.status, 201);

    const logoutResponse = await postJson(
      baseUrl,
      '/api/auth/logout',
      userAfterReset.token,
      {},
    );
    assert.equal(logoutResponse.status, 200);
    const revokedByLogout = await getJson(baseUrl, '/api/materials', userAfterReset.token);
    assert.equal(revokedByLogout.status, 401);

    const pending = await getJson(
      baseUrl,
      '/api/delete-requests?status=pending',
      admin.token,
    );
    assert.equal(pending.status, 200);
    assert.ok(pending.body.requests.length >= 1);

    const approve = await postJson(
      baseUrl,
      `/api/delete-requests/${requestDelete.body.request.id}/approve`,
      admin.token,
      {},
    );
    assert.equal(approve.status, 200);
    assert.equal(approve.body.request.status, 'approved');

    const deletedLookup = await getJson(
      baseUrl,
      `/api/materials/${material.barcode}`,
      admin.token,
    );
    assert.equal(deletedLookup.status, 404);
  } finally {
    await closeServer(server);
    await backend.closeDb();
  }
});

async function login(baseUrl, email, password) {
  const response = await postJson(baseUrl, '/api/auth/login', null, {
    email,
    password,
  });
  assert.equal(response.status, 200);
  return response.body;
}

async function postJson(baseUrl, pathName, token, body) {
  const response = await fetch(`${baseUrl}${pathName}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
  return { status: response.status, body: await response.json() };
}

async function patchJson(baseUrl, pathName, token, body) {
  const response = await fetch(`${baseUrl}${pathName}`, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
  return { status: response.status, body: await response.json() };
}

async function getJson(baseUrl, pathName, token) {
  const response = await fetch(`${baseUrl}${pathName}`, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  return { status: response.status, body: await response.json() };
}

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
