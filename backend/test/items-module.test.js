const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// Integration coverage for the items module routes (modules/items/routes.js)
// after their verbatim evacuation from server.js — every moved route gets at
// least one request, plus the log-only contract guard's alert feed.

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

test('items module routes work end-to-end after evacuation', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-items-module-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'items-owner@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const loginResponse = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'items-owner@paper.local',
        password: 'OwnerPass1234',
      }),
    });
    const { token } = await loginResponse.json();
    assert.ok(token, 'expected a login token');
    const authHeaders = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    };
    const getJson = async (p) => {
      const r = await fetch(`${baseUrl}${p}`, { headers: authHeaders });
      return { status: r.status, body: await r.json() };
    };
    const sendJson = async (method, p, payload) => {
      const r = await fetch(`${baseUrl}${p}`, {
        method,
        headers: authHeaders,
        body: payload === undefined ? undefined : JSON.stringify(payload),
      });
      return { status: r.status, body: await r.json() };
    };

    // --- groups: list + create hierarchical + create combination ---
    const groupList = await getJson('/api/groups');
    assert.equal(groupList.status, 200);
    assert.ok(groupList.body.groups.length >= 1, 'expected seeded groups');

    const unitId = groupList.body.groups.find((g) => g.unitId)?.unitId;
    assert.ok(unitId, 'expected a seeded group with a unit');

    const groupCreate = await sendJson('POST', '/api/groups', {
      name: 'Evacuation Test Group',
      unitId,
    });
    assert.equal(groupCreate.status, 201);
    const groupId = groupCreate.body.group.id;

    const comboCreate = await sendJson('POST', '/api/groups', {
      name: 'Evacuation Combo Group',
      groupStructure: 'combination',
    });
    assert.equal(comboCreate.status, 201);
    const comboGroupId = comboCreate.body.group.id;

    const groupPatch = await sendJson('PATCH', `/api/groups/${groupId}`, {
      name: 'Evacuation Test Group Renamed',
      unitId,
    });
    assert.equal(groupPatch.status, 200);
    assert.equal(groupPatch.body.group.name, 'Evacuation Test Group Renamed');

    const effectiveSchema = await getJson(`/api/groups/${groupId}/effective-schema`);
    assert.equal(effectiveSchema.status, 200);

    // --- items: create with variation tree + conversions ---
    const unitsList = await getJson('/api/units');
    const secondaryUnit = unitsList.body.units.find((u) => u.id !== unitId);
    const itemCreate = await sendJson('POST', '/api/items', {
      name: 'Evacuation Test Item',
      alias: 'ETI',
      groupId,
      unitId,
      unitConversions: secondaryUnit
        ? [{ unitId: secondaryUnit.id, factorToPrimary: 10 }]
        : [],
      variationTree: [
        {
          kind: 'property',
          name: 'Color',
          children: [
            { kind: 'value', name: 'Black', children: [] },
            { kind: 'value', name: 'White', children: [] },
          ],
        },
      ],
    });
    if (itemCreate.status !== 201) throw new Error("FAIL: " + JSON.stringify(itemCreate.body));
    const itemId = itemCreate.body.item.id;
    assert.equal(itemCreate.body.item.variationTree.length, 1);

    const itemGet = await getJson(`/api/items/${itemId}`);
    assert.equal(itemGet.status, 200);
    assert.equal(itemGet.body.item.name, 'Evacuation Test Item');

    const itemList = await getJson('/api/items');
    assert.equal(itemList.status, 200);
    assert.ok(itemList.body.items.some((i) => i.id === itemId));

    const itemUsage = await getJson(`/api/items/${itemId}/usage`);
    assert.equal(itemUsage.status, 200);

    const itemAssets = await getJson(`/api/items/${itemId}/assets`);
    assert.equal(itemAssets.status, 200);
    assert.deepEqual(itemAssets.body.assets, []);

    const itemPatch = await sendJson('PATCH', `/api/items/${itemId}`, {
      name: 'Evacuation Test Item',
      alias: 'ETI-2',
      groupId,
      unitId,
    });
    assert.equal(itemPatch.status, 200);
    assert.equal(itemPatch.body.item.alias, 'ETI-2');

    const shortCode = await sendJson('PUT', `/api/items/${itemId}/short-code`, {
      shortCode: 'EV-01',
    });
    assert.equal(shortCode.status, 200);
    assert.equal(shortCode.body.item.shortCode, 'EV-01');

    // --- combination group membership ---
    const assign = await sendJson('POST', `/api/groups/${comboGroupId}/items`, {
      itemIds: [itemId],
    });
    assert.equal(assign.status, 201);
    assert.equal(assign.body.assignedCount, 1);

    const members = await getJson(`/api/groups/${comboGroupId}/items`);
    assert.equal(members.status, 200);
    assert.deepEqual(members.body.itemIds, [itemId]);

    // --- group reassignment (dedicated relocate route) ---
    const otherGroup = groupList.body.groups.find(
      (g) => g.id !== groupId && g.groupStructure !== 'combination' && g.unitId,
    );
    if (otherGroup) {
      const relocate = await sendJson('PATCH', `/api/items/${itemId}/group`, {
        groupId: otherGroup.id,
      });
      assert.equal(relocate.status, 200);
      assert.equal(relocate.body.item.groupId, otherGroup.id);
    }

    // --- log-only contract guard: bad payload passes, alert is filed ---
    const guarded = await sendJson('POST', '/api/items', {
      name: 'Guarded Item',
      groupId,
      unitId,
      quantity: 'not-a-number',
    });
    assert.equal(guarded.status, 400, 'contract guard must reject bad payload');
    const alerts = await getJson('/api/kernel/guard-alerts');
    assert.equal(alerts.status, 200);
    assert.ok(
      alerts.body.alerts.some(
        (a) =>
          a.route === 'POST /api/items' &&
          (a.details.problems || []).some((p) => p.path === 'item.quantity'),
      ),
      'expected a guard alert for the malformed quantity',
    );

    // --- territory report exposes items port metering ---
    const territory = await getJson('/api/kernel/territory');
    assert.equal(territory.status, 200);
    const itemsModule = territory.body.territory.modules.items;
    assert.ok(itemsModule.runtime, 'expected items runtime block in territory');
    assert.ok(
      typeof itemsModule.runtime.portCalls['stock.applyDelta'] === 'number',
      'expected per-port call counters',
    );

    // --- deletes ---
    const itemDelete = await sendJson('DELETE', `/api/items/${itemId}`);
    assert.equal(itemDelete.status, 200);
    const goneItem = await getJson(`/api/items/${itemId}`);
    assert.equal(goneItem.status, 404);

    const comboDelete = await sendJson('DELETE', `/api/groups/${comboGroupId}`);
    assert.equal(comboDelete.status, 200);
  } finally {
    await closeServer(server);
    await backend.closeDb?.();
  }
});
