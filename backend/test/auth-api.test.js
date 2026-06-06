const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

function loadBackend() {
  delete require.cache[require.resolve('../server.js')];
  return require('../server.js');
}

test('auth roles and delete approval workflow', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-auth-api-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'primary@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  const backend = loadBackend();
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const unauthCreate = await fetch(`${baseUrl}/api/units`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'Box', symbol: 'box' }),
    });
    assert.equal(unauthCreate.status, 401);

    const owner = await login(baseUrl, 'primary@paper.local', 'OwnerPass1234');
    assert.equal(owner.user.role, 'super_admin');
    const ownerSessions = await getJson(baseUrl, '/api/auth/sessions', owner.token);
    assert.equal(ownerSessions.status, 200);
    assert.ok(ownerSessions.body.sessions.length >= 1);

    const badLogin = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'primary@paper.local',
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
        email: 'ops@paper.local',
        password: 'TeamPass1234',
      },
    );
    assert.equal(adminResponse.status, 201);
    const weakPasswordUser = await postJson(baseUrl, '/api/users', owner.token, {
      name: 'Weak Password User',
      email: 'weak@paper.local',
      password: 'password',
    });
    assert.equal(weakPasswordUser.status, 400);

    const admin = await login(baseUrl, 'ops@paper.local', 'TeamPass1234');
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
        password: 'OtherPass1234',
      },
    );
    assert.equal(adminCannotCreateAdmin.status, 403);

    const userResponse = await postJson(
      baseUrl,
      '/api/users',
      admin.token,
      {
        name: 'Floor User',
        email: 'floor@paper.local',
        password: 'WorkerPass1234',
      },
    );
    assert.equal(userResponse.status, 201);

    const user = await login(baseUrl, 'floor@paper.local', 'WorkerPass1234');
    assert.equal(user.user.role, 'user');
    const userSessions = await getJson(baseUrl, '/api/auth/sessions', user.token);
    assert.equal(userSessions.status, 200);
    assert.ok(userSessions.body.sessions.length >= 1);
    const templatesList = await getJson(baseUrl, '/api/permission-templates', admin.token);
    assert.equal(templatesList.status, 200);
    const configManagerTemplate = templatesList.body.templates.find(
      (template) => template.name === 'Configurator Manager',
    );
    assert.ok(configManagerTemplate?.id, 'expected Configurator Manager template');
    const assignTemplate = await patchJson(
      baseUrl,
      `/api/users/${user.user.id}/permission-templates`,
      admin.token,
      { templateIds: [configManagerTemplate.id] },
    );
    assert.equal(assignTemplate.status, 200);
    const userCanCreateUnitViaTemplate = await postJson(
      baseUrl,
      '/api/units',
      user.token,
      {
        name: 'Template Unit',
        symbol: 'TU',
      },
    );
    assert.equal(userCanCreateUnitViaTemplate.status, 201);

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
    const ownerRevokesAdminInventoryRead = await patchJson(
      baseUrl,
      `/api/users/${admin.user.id}/permissions`,
      owner.token,
      {
        overrides: [{ key: 'inventory.read', allowed: false }],
      },
    );
    assert.equal(ownerRevokesAdminInventoryRead.status, 200);
    const adminCannotReadInventory = await getJson(baseUrl, '/api/materials', admin.token);
    assert.equal(adminCannotReadInventory.status, 403);
    const ownerRestoresAdminInventoryRead = await patchJson(
      baseUrl,
      `/api/users/${admin.user.id}/permissions`,
      owner.token,
      {
        overrides: [{ key: 'inventory.read', allowed: true }],
      },
    );
    assert.equal(ownerRestoresAdminInventoryRead.status, 200);

    const resetUserPassword = await fetch(
      `${baseUrl}/api/users/${user.user.id}/password`,
      {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${admin.token}`,
        },
        body: JSON.stringify({ newPassword: 'ShiftPass4567' }),
      },
    );
    assert.equal(resetUserPassword.status, 200);
    const oldUserTokenAfterReset = await getJson(baseUrl, '/api/materials', user.token);
    assert.equal(oldUserTokenAfterReset.status, 401);
    const userAfterReset = await login(baseUrl, 'floor@paper.local', 'ShiftPass4567');

    const resetAdminPassword = await fetch(
      `${baseUrl}/api/users/${admin.user.id}/password`,
      {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${admin.token}`,
        },
        body: JSON.stringify({ newPassword: 'OpsPass4567' }),
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
        password: 'GuardPass1234',
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
      password: 'GuardPass1234',
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
    assert.equal(approve.body.request.reviewedNote, '');

    const exportAuditAsAdmin = await getText(
      baseUrl,
      '/api/auth/events/export',
      admin.token,
    );
    assert.equal(exportAuditAsAdmin.status, 200);
    assert.match(exportAuditAsAdmin.body, /event_type/);
    const exportAuditAsUser = await getText(
      baseUrl,
      '/api/auth/events/export',
      user.token,
    );
    assert.equal(exportAuditAsUser.status, 401);

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

test('clear-data preserves auth state and reset-demo-data rebuilds seeded workspace', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-auth-reset-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'owner@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'Qz79Luma4821';

  const backend = loadBackend();
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const owner = await login(baseUrl, 'owner@paper.local', 'Qz79Luma4821');

    const workerResponse = await postJson(baseUrl, '/api/users', owner.token, {
      name: 'Warehouse User',
      email: 'warehouse@paper.local',
      password: 'M7vL2pQa91xz',
    });
    assert.equal(workerResponse.status, 201);
    const workerId = workerResponse.body.user.id;

    const permissionOverride = await patchJson(
      baseUrl,
      `/api/users/${workerId}/permissions`,
      owner.token,
      {
        overrides: [{ key: 'inventory.delete', allowed: false }],
      },
    );
    assert.equal(permissionOverride.status, 200);

    const material = await backend.createParentWithChildren({
      name: 'Clear Data Material',
      type: 'Raw Material',
      unit: 'Kg',
      numberOfChildren: 0,
    });
    const now = new Date().toISOString();
    await backend.run(
      'INSERT INTO scan_history (barcode, scanned_at) VALUES (?, ?)',
      [material.barcode, now],
    );
    await backend.run(
      `
      INSERT INTO material_activity (
        barcode, event_type, event_label, event_description, actor, created_at
      ) VALUES (?, ?, ?, ?, ?, ?)
      `,
      [
        material.barcode,
        'manual-test',
        'Manual test event',
        'Created for clear-data verification.',
        'test',
        now,
      ],
    );

    await backend.saveUnit({
      name: 'Clear Length Base',
      symbol: 'clb',
      notes: '',
      unitGroupName: 'Clear Length',
      conversionFactor: 1,
    });
    await backend.saveUnit({
      name: 'Clear Length Derived',
      symbol: 'cld',
      notes: '',
      unitGroupName: 'Clear Length',
      conversionFactor: 100,
    });

    const deleteRequest = await postJson(
      baseUrl,
      '/api/delete-requests',
      owner.token,
      {
        entityType: 'material',
        entityId: material.barcode,
        entityLabel: material.name,
        reason: 'Clear/reset verification',
      },
    );
    assert.equal(deleteRequest.status, 201);

    const authUsersBefore = await backend.get(
      'SELECT COUNT(*) AS count FROM users',
    );
    const authSessionsBefore = await backend.get(
      'SELECT COUNT(*) AS count FROM auth_sessions',
    );
    const authEventsBefore = await backend.get(
      'SELECT COUNT(*) AS count FROM auth_events',
    );
    const overridesBefore = await backend.get(
      'SELECT COUNT(*) AS count FROM user_permission_overrides',
    );
    const deleteRequestsBefore = await backend.get(
      'SELECT COUNT(*) AS count FROM delete_requests',
    );
    const unitGroupsBefore = await backend.get(
      'SELECT COUNT(*) AS count FROM unit_groups',
    );
    assert.ok(Number(unitGroupsBefore.count || 0) > 0);

    const clearResponse = await postJson(
      baseUrl,
      '/api/admin/clear-data',
      owner.token,
      {},
    );
    assert.equal(clearResponse.status, 200);

    const meAfterClear = await getJson(baseUrl, '/api/auth/me', owner.token);
    assert.equal(meAfterClear.status, 200);
    assert.equal(meAfterClear.body.user.email, 'owner@paper.local');

    const authUsersAfter = await backend.get(
      'SELECT COUNT(*) AS count FROM users',
    );
    const authSessionsAfter = await backend.get(
      'SELECT COUNT(*) AS count FROM auth_sessions',
    );
    const authEventsAfter = await backend.get(
      'SELECT COUNT(*) AS count FROM auth_events',
    );
    const overridesAfter = await backend.get(
      'SELECT COUNT(*) AS count FROM user_permission_overrides',
    );
    const deleteRequestsAfter = await backend.get(
      'SELECT COUNT(*) AS count FROM delete_requests',
    );
    assert.equal(authUsersAfter.count, authUsersBefore.count);
    assert.equal(authSessionsAfter.count, authSessionsBefore.count);
    assert.ok(
      Number(authEventsAfter.count || 0) >= Number(authEventsBefore.count || 0),
    );
    assert.equal(overridesAfter.count, overridesBefore.count);
    assert.equal(deleteRequestsAfter.count, deleteRequestsBefore.count);

    const materialsAfterClear = await backend.get(
      'SELECT COUNT(*) AS count FROM materials',
    );
    const clientsAfterClear = await backend.get(
      'SELECT COUNT(*) AS count FROM clients',
    );
    const itemsAfterClear = await backend.get(
      'SELECT COUNT(*) AS count FROM items',
    );
    const ordersAfterClear = await backend.get(
      'SELECT COUNT(*) AS count FROM order_items',
    );
    const scanHistoryAfterClear = await backend.get(
      'SELECT COUNT(*) AS count FROM scan_history',
    );
    const materialActivityAfterClear = await backend.get(
      'SELECT COUNT(*) AS count FROM material_activity',
    );
    const unitGroupsAfterClear = await backend.get(
      'SELECT COUNT(*) AS count FROM unit_groups',
    );
    assert.equal(materialsAfterClear.count, 0);
    assert.equal(clientsAfterClear.count, 0);
    assert.equal(itemsAfterClear.count, 0);
    assert.equal(ordersAfterClear.count, 0);
    assert.equal(scanHistoryAfterClear.count, 0);
    assert.equal(materialActivityAfterClear.count, 0);
    assert.equal(unitGroupsAfterClear.count, 0);

    const primaryUnit = await backend.get(
      "SELECT * FROM units WHERE name = 'Primary Unit' AND symbol = '-'",
    );
    const primaryGroup = await backend.get(
      "SELECT * FROM groups WHERE name = 'Primary Group'",
    );
    assert.ok(primaryUnit, 'expected primary unit baseline after clear');
    assert.ok(primaryGroup, 'expected primary group baseline after clear');

    await backend.saveClient({
      name: 'Dirty Client',
      alias: 'Dirty',
      gstNumber: '',
      address: '',
    });
    await backend.createParentWithChildren({
      name: 'Dirty Material',
      type: 'Raw Material',
      unit: 'Kg',
      numberOfChildren: 0,
    });

    const resetResponse = await postJson(
      baseUrl,
      '/api/admin/reset-demo-data',
      owner.token,
      {},
    );
    assert.equal(resetResponse.status, 200);

    const dirtyClientAfterReset = await backend.get(
      'SELECT * FROM clients WHERE lower(name) = lower(?)',
      ['Dirty Client'],
    );
    const dirtyMaterialAfterReset = await backend.get(
      'SELECT * FROM materials WHERE lower(name) = lower(?)',
      ['Dirty Material'],
    );
    assert.equal(dirtyClientAfterReset == null, true);
    assert.equal(dirtyMaterialAfterReset == null, true);

    const seededClients = await backend.getClientsWithUsage();
    const seededOrders = await backend.getOrders();
    const seededItems = await backend.getItemsWithUsage();
    const seededMaterials = await backend.all('SELECT * FROM materials');
    assert.ok(seededClients.length >= 3, 'expected demo clients after reset');
    assert.ok(seededItems.length >= 2, 'expected demo items after reset');
    assert.ok(seededOrders.length >= 1, 'expected demo orders after reset');
    assert.ok(
      seededMaterials.length >= 1,
      'expected demo materials after reset',
    );
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

async function getText(baseUrl, pathName, token) {
  const response = await fetch(`${baseUrl}${pathName}`, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  return { status: response.status, body: await response.text() };
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
