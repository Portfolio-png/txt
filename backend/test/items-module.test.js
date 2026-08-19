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
        {
          kind: 'property',
          name: 'Sheets',
          inputType: 'Numeric',
          numericMin: 1,
          numericMax: 40,
          children: [],
        },
      ],
    });
    if (itemCreate.status !== 201) throw new Error("FAIL: " + JSON.stringify(itemCreate.body));
    const itemId = itemCreate.body.item.id;
    assert.equal(itemCreate.body.item.variationTree.length, 2);

    // Numeric properties carry the range the item editor captured.
    const numericNode = itemCreate.body.item.variationTree.find(
      (node) => node.name === 'Sheets',
    );
    assert.equal(numericNode.inputType, 'Numeric');
    assert.equal(numericNode.numericMin, 1);
    assert.equal(numericNode.numericMax, 40);

    // A range is only meaningful on Numeric properties — Text keeps null bounds.
    const textNode = itemCreate.body.item.variationTree.find(
      (node) => node.name === 'Color',
    );
    assert.equal(textNode.numericMin, null);
    assert.equal(textNode.numericMax, null);

    // An inverted range is rejected at the border.
    const badRange = await sendJson('POST', '/api/items', {
      name: 'Evacuation Test Item Bad Range',
      groupId,
      unitId,
      variationTree: [
        {
          kind: 'property',
          name: 'Sheets',
          inputType: 'Numeric',
          numericMin: 40,
          numericMax: 1,
          children: [],
        },
      ],
    });
    assert.equal(badRange.status, 400);

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

    // --- basic items: spawned variants keep their base, and carry their own
    // --- sample baseline ---
    const variantCreate = await sendJson('POST', '/api/items', {
      name: 'Evacuation Test Item - Black',
      groupId,
      unitId,
      baseItemId: itemId,
      variationTree: [],
    });
    assert.equal(variantCreate.status, 201);
    const variantId = variantCreate.body.item.id;
    assert.equal(variantCreate.body.item.baseItemId, itemId);
    assert.equal(variantCreate.body.item.penPaperBaseline, null);

    // The item editor's update payload omits baseItemId; the variant must stay
    // attached to its base rather than graduating into a base item.
    const variantRename = await sendJson('PATCH', `/api/items/${variantId}`, {
      name: 'Evacuation Test Item - Black',
      displayName: 'Evacuation Test Item - Black',
      groupId,
      unitId,
    });
    assert.equal(variantRename.status, 200);
    assert.equal(variantRename.body.item.baseItemId, itemId);

    const sampleBaseline = {
      isGranular: true,
      keyEfficiencyBenchmark: 88,
      baselineOutputRate: 12.5,
      baselineScrapRate: 4.2,
      notes: 'Trial batch #7',
      stageReconciliations: [
        {
          stageId: 'stage-1',
          stageName: 'Raw Preparation',
          inputKg: 100,
          outputKg: 90,
          scrapKg: 5,
          rejectionKg: 3,
          weightLossKg: 2,
          notes: '',
        },
      ],
    };
    const withSample = await sendJson('PATCH', `/api/items/${variantId}`, {
      name: 'Evacuation Test Item - Black',
      groupId,
      unitId,
      penPaperBaseline: sampleBaseline,
    });
    assert.equal(withSample.status, 200);
    assert.deepEqual(withSample.body.item.penPaperBaseline, sampleBaseline);

    // Omitting the field preserves the record; an explicit null clears it.
    const untouched = await sendJson('PATCH', `/api/items/${variantId}`, {
      name: 'Evacuation Test Item - Black',
      groupId,
      unitId,
    });
    assert.equal(untouched.status, 200);
    assert.deepEqual(untouched.body.item.penPaperBaseline, sampleBaseline);

    const cleared = await sendJson('PATCH', `/api/items/${variantId}`, {
      name: 'Evacuation Test Item - Black',
      groupId,
      unitId,
      penPaperBaseline: null,
    });
    assert.equal(cleared.status, 200);
    assert.equal(cleared.body.item.penPaperBaseline, null);

    // Renaming a variant must not strip the rest of it. The border preserves
    // fields that are ABSENT, but the Dart client's UpdateItemRequest.toJson
    // always emits `attachments`, `machineIds`, `dieIds` and `photoUrl` — so a
    // sparse UpdateItemInput sends empty ones and really does clear them.
    // Hence the rename round-trips every field off the existing item.
    const dressed = await sendJson('PATCH', `/api/items/${variantId}`, {
      name: 'Evacuation Test Item - Black',
      groupId,
      unitId,
      photoUrl: 'https://example.test/black.png',
      cadFileKey: 'cad/black.step',
      cadFileName: 'black.step',
      attachments: [
        { label: 'Spec', objectKey: 'docs/black.pdf', fileName: 'black.pdf' },
      ],
    });
    assert.equal(dressed.status, 200);
    assert.equal(dressed.body.item.attachments.length, 1);

    const renamed = await sendJson('PATCH', `/api/items/${variantId}`, {
      name: 'Evacuation Test Item - BLK',
      displayName: 'Evacuation Test Item - BLK',
      groupId,
      unitId,
      photoUrl: dressed.body.item.photoUrl,
      cadFileKey: dressed.body.item.cadFileKey,
      cadFileName: dressed.body.item.cadFileName,
      attachments: dressed.body.item.attachments.map((entry) => ({
        label: entry.label,
        objectKey: entry.objectKey,
        fileName: entry.fileName,
      })),
    });
    assert.equal(renamed.status, 200);
    assert.equal(renamed.body.item.name, 'Evacuation Test Item - BLK');
    assert.equal(renamed.body.item.photoUrl, 'https://example.test/black.png');
    assert.equal(renamed.body.item.cadFileKey, 'cad/black.step');
    assert.equal(renamed.body.item.attachments.length, 1);
    assert.equal(renamed.body.item.baseItemId, itemId);

    // Omitting a field preserves it — that is the border's contract.
    const omitted = await sendJson('PATCH', `/api/items/${variantId}`, {
      name: 'Evacuation Test Item - BLK',
      groupId,
      unitId,
    });
    assert.equal(omitted.status, 200);
    assert.equal(omitted.body.item.attachments.length, 1);
    assert.equal(omitted.body.item.photoUrl, 'https://example.test/black.png');

    // But sending them EMPTY clears them, which is what a sparse
    // UpdateItemInput serialises to. This is the trap the rename avoids.
    const emptied = await sendJson('PATCH', `/api/items/${variantId}`, {
      name: 'Evacuation Test Item - BLK',
      groupId,
      unitId,
      photoUrl: '',
      attachments: [],
    });
    assert.equal(emptied.status, 200);
    assert.deepEqual(emptied.body.item.attachments, []);
    assert.equal(emptied.body.item.photoUrl, null);

    // Deleting a variant must take its memberships with it. The delete runs
    // over a connection with foreign_keys = OFF, so the declared ON DELETE
    // CASCADE does not fire — a leftover set line shows as a nameless ghost
    // that still counts, and makes the whole set unsaveable.
    const doomed = await sendJson('POST', '/api/items', {
      name: 'Evacuation Doomed Variant',
      groupId,
      unitId,
      baseItemId: itemId,
      variationTree: [],
    });
    assert.equal(doomed.status, 201);
    const doomedId = doomed.body.item.id;

    const assigned = await sendJson('POST', `/api/groups/${comboGroupId}/items`, {
      itemIds: [doomedId],
    });
    assert.equal(assigned.status, 201, JSON.stringify(assigned.body));

    const setCreate = await sendJson('POST', '/api/inventory/sets', {
      name: 'Evacuation Kit',
      lines: [{ itemId: doomedId, variationLeafNodeId: 0, quantity: 2 }],
    });
    assert.equal(setCreate.status, 201, JSON.stringify(setCreate.body));
    const setId = setCreate.body.set?.id;
    assert.ok(setId, 'expected the created set id');

    const removed = await sendJson('DELETE', `/api/items/${doomedId}`);
    assert.equal(removed.status, 200);

    const setsAfter = await getJson('/api/inventory/sets');
    assert.equal(setsAfter.status, 200);
    const kit = (setsAfter.body.sets ?? []).find((entry) => entry.id === setId);
    assert.ok(kit, 'set should still exist');
    assert.deepEqual(kit.lines, [], 'deleted item must not leave a ghost line');
    assert.equal(kit.totalItemCount, 0);

    const itemAfterDelete = await getJson(`/api/items/${doomedId}`);
    assert.equal(itemAfterDelete.status, 404);

    // The combination group must not keep a phantom member either.
    const comboMembers = await getJson(`/api/groups/${comboGroupId}/items`);
    assert.equal(comboMembers.status, 200);
    assert.ok(
      !(comboMembers.body.itemIds ?? []).includes(doomedId),
      'deleted item must not stay in the combination group',
    );

    // A variant may be manufactured on its own route: its default pipeline is
    // seeded from the base item but is not tied to it afterwards.
    const baseWithPipeline = await sendJson('PATCH', `/api/items/${itemId}`, {
      name: 'Evacuation Test Item',
      groupId,
      unitId,
      defaultPipelineId: 'pipeline-base-route',
    });
    assert.equal(baseWithPipeline.status, 200);
    assert.equal(baseWithPipeline.body.item.defaultPipelineId, 'pipeline-base-route');

    const variantOwnPipeline = await sendJson('PATCH', `/api/items/${variantId}`, {
      name: 'Evacuation Test Item - Black',
      groupId,
      unitId,
      defaultPipelineId: 'pipeline-variant-route',
    });
    assert.equal(variantOwnPipeline.status, 200);
    assert.equal(
      variantOwnPipeline.body.item.defaultPipelineId,
      'pipeline-variant-route',
    );
    assert.equal(variantOwnPipeline.body.item.baseItemId, itemId);

    // The base is untouched by the variant diverging.
    const baseAfter = await getJson(`/api/items/${itemId}`);
    assert.equal(baseAfter.body.item.defaultPipelineId, 'pipeline-base-route');

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
