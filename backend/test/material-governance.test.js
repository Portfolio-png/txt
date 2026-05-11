const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

function loadFreshBackend() {
  const backendPath = require.resolve('../server.js');
  delete require.cache[backendPath];
  return require('../server.js');
}

test('group governance persists and can be updated without recreating material', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-governance-'));
  const dbPath = path.join(tempDir, 'paper.db');
  process.env.DB_PATH = dbPath;

  const backend = loadFreshBackend();

  try {
    await backend.resetAndSeedDemoData();
    const items = await backend.getItemsWithUsage();
    assert.ok(items.length >= 3, 'expected seeded items for governance test');
    const selectedItemIds = items.slice(0, 3).map((item) => item.id);

    const created = await backend.createParentWithChildren({
      name: 'Governance Demo Group',
      type: 'Item Group',
      numberOfChildren: 0,
      unit: 'Pieces',
      groupMode: 'item_group_authoring',
      inheritanceEnabled: true,
      selectedItemIds,
      propertyDrafts: [
        {
          name: 'Material',
          inputType: 'Text',
          mandatory: false,
          sourceType: 'inherited_item',
          state: 'active',
          overrideLocked: false,
          hasTypeConflict: false,
          sources: selectedItemIds.map((itemId) => ({ itemId })),
        },
        {
          name: 'material',
          inputType: 'Text',
          mandatory: false,
          sourceType: 'inherited_item',
          state: 'active',
          overrideLocked: false,
          hasTypeConflict: false,
          sources: [{ itemId: selectedItemIds[0] }],
        },
        {
          name: 'Density',
          inputType: 'Number',
          mandatory: true,
          sourceType: 'manual',
          state: 'active',
          overrideLocked: false,
          hasTypeConflict: false,
          sources: [],
        },
      ],
    });

    const materialRow = await backend.getMaterialRowByBarcode(created.barcode);
    assert.ok(materialRow, 'expected created parent material row');
    assert.equal(materialRow.group_mode, 'item_group_authoring');
    assert.equal(materialRow.inheritance_enabled, 1);

    const initialConfig = await backend.getMaterialGroupGovernance(materialRow.id);
    assert.deepEqual(initialConfig.selectedItemIds, selectedItemIds);
    assert.equal(initialConfig.propertyDrafts.length, 2, 'expected deduped property rows');
    assert.ok(
      initialConfig.propertyDrafts.some((draft) => draft.propertyKey === 'material'),
      'expected normalized material property key',
    );

    await backend.updateMaterialGroupConfiguration(created.barcode, {
      groupMode: 'item_group_authoring',
      inheritanceEnabled: true,
      selectedItemIds,
      discardedPropertyKeys: [],
      propertyDrafts: [
        {
          name: 'Material',
          inputType: 'Text',
          mandatory: false,
          sourceType: 'inherited_item',
          state: 'unlinked',
          overrideLocked: false,
          hasTypeConflict: false,
          sources: selectedItemIds.map((itemId) => ({ itemId })),
        },
        {
          name: 'Density',
          inputType: 'Number',
          mandatory: true,
          sourceType: 'manual',
          state: 'overridden',
          overrideLocked: true,
          hasTypeConflict: false,
          sources: [{ itemId: selectedItemIds[0] }],
        },
      ],
    });

    const updatedConfig = await backend.getMaterialGroupGovernance(materialRow.id);
    const materialDraft = updatedConfig.propertyDrafts.find(
      (draft) => draft.propertyKey === 'material',
    );
    const densityDraft = updatedConfig.propertyDrafts.find(
      (draft) => draft.propertyKey === 'density',
    );
    assert.ok(materialDraft, 'expected material draft to exist');
    assert.ok(densityDraft, 'expected density draft to exist');
    assert.equal(materialDraft.state, 'unlinked');
    assert.equal(densityDraft.state, 'overridden');
    assert.equal(densityDraft.overrideLocked, true);
    assert.deepEqual(updatedConfig.selectedItemIds, selectedItemIds);
  } finally {
    await backend.closeDb();
  }
});

test('effective schema applies discarded inherited keys and item save snapshots resolved schema', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-governance-schema-'));
  const dbPath = path.join(tempDir, 'paper.db');
  process.env.DB_PATH = dbPath;

  const backend = loadFreshBackend();

  try {
    await backend.resetAndSeedDemoData();
    const units = await backend.getUnitsWithUsage();
    const primaryUnit = units.find((unit) => !unit.is_archived);
    assert.ok(primaryUnit, 'expected an active unit for schema snapshot test');

    const root = await backend.createParentWithChildren({
      name: 'Root Governed Group',
      type: 'Group',
      numberOfChildren: 0,
      unitId: primaryUnit.id,
      unit: primaryUnit.display_label,
      groupMode: 'standalone_group',
      inheritanceEnabled: true,
      propertyDrafts: [
        {
          name: 'Material',
          propertyKey: 'material',
          inputType: 'Text',
          mandatory: false,
          sourceType: 'manual',
          state: 'active',
          overrideLocked: false,
          hasTypeConflict: false,
          sources: [],
        },
      ],
      discardedPropertyKeys: [],
    });
    assert.ok(root.linkedGroupId, 'expected root group link to be created');

    const child = await backend.createParentWithChildren({
      name: 'Child Governed Group',
      type: 'Group',
      numberOfChildren: 0,
      parentGroupId: root.linkedGroupId,
      unitId: primaryUnit.id,
      unit: primaryUnit.display_label,
      groupMode: 'nested_group',
      inheritanceEnabled: true,
      propertyDrafts: [
        {
          name: 'Density',
          propertyKey: 'density',
          inputType: 'Number',
          mandatory: true,
          sourceType: 'manual',
          state: 'active',
          overrideLocked: false,
          hasTypeConflict: false,
          unitSymbol: 'mm',
          unitLabel: 'Millimetre',
          sources: [],
        },
      ],
      discardedPropertyKeys: ['material'],
    });
    assert.ok(child.linkedGroupId, 'expected child group link to be created');

    const effectiveSchema = await backend.getEffectiveSchema(child.linkedGroupId);
    assert.deepEqual(
      effectiveSchema.lineageGroupIds.slice(-2),
      [root.linkedGroupId, child.linkedGroupId],
    );
    assert.equal(
      effectiveSchema.propertyDrafts.some((draft) => draft.propertyKey === 'material'),
      false,
      'discarded inherited property should be masked out of effective schema',
    );
    const densityDraft = effectiveSchema.propertyDrafts.find((draft) => draft.propertyKey === 'density');
    assert.ok(densityDraft, 'expected child-local density property in effective schema');
    assert.equal(densityDraft.inputType, 'Number');
    assert.equal(densityDraft.unitSymbol, 'mm');

    const item = await backend.saveItem({
      name: 'Schema Snapshot Item',
      alias: 'SNAP-01',
      displayName: 'Schema Snapshot Item / SNAP-01',
      quantity: 10,
      groupId: child.linkedGroupId,
      unitId: primaryUnit.id,
      variationTree: [
        {
          kind: 'property',
          name: 'Density',
          children: [
            {
              kind: 'value',
              name: '120',
              displayName: 'Density: 120',
              children: [],
            },
          ],
        },
        {
          kind: 'property',
          name: 'Finish',
          children: [
            {
              kind: 'value',
              name: 'Gloss',
              displayName: 'Finish: Gloss',
              children: [],
            },
          ],
        },
      ],
    });

    const propertySchema = await backend.getItemPropertySchema(item.id);
    assert.ok(
      propertySchema.some((entry) => entry.propertyKey === 'density'),
      'item schema should snapshot inherited group property',
    );
    assert.ok(
      propertySchema.some((entry) => entry.propertyKey === 'finish'),
      'item schema should also include top-level item variation properties',
    );
    assert.equal(
      propertySchema.some((entry) => entry.propertyKey === 'material'),
      false,
      'discarded parent property should not leak into item schema snapshot',
    );
  } finally {
    await backend.closeDb();
  }
});

test('materials parent create persists structured schema and effective-schema endpoint returns inherited lineage', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-governance-http-'));
  const dbPath = path.join(tempDir, 'paper.db');
  process.env.DB_PATH = dbPath;
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'schema-owner@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'SchemaOwner1234';

  const backend = loadFreshBackend();

  try {
    await backend.resetAndSeedDemoData();
    const units = await backend.getUnitsWithUsage();
    const primaryUnit = units.find((unit) => !unit.is_archived);
    assert.ok(primaryUnit, 'expected active unit');

    const root = await backend.createParentWithChildren({
      name: 'HTTP Root Group',
      type: 'Group',
      numberOfChildren: 0,
      unitId: primaryUnit.id,
      unit: primaryUnit.display_label,
      groupMode: 'standalone_group',
      inheritanceEnabled: true,
      propertyDrafts: [
        {
          name: 'Material',
          propertyKey: 'material',
          inputType: 'Text',
          mandatory: false,
          sourceType: 'manual',
          state: 'active',
          overrideLocked: false,
          hasTypeConflict: false,
          sources: [],
        },
      ],
      discardedPropertyKeys: [],
    });
    assert.ok(root.linkedGroupId, 'expected linked group for root');

    const seededItems = await backend.getItemsWithUsage();
    const seedItem = seededItems.find((item) => !item.is_archived);
    assert.ok(seedItem, 'expected an active seed item');

    const { server, port } = await listen(backend.app);
    const baseUrl = `http://127.0.0.1:${port}`;
    try {
      const owner = await login(
        baseUrl,
        'schema-owner@paper.local',
        'SchemaOwner1234',
      );

      const createResponse = await postJson(
        baseUrl,
        '/api/materials/parent',
        owner.token,
        {
          name: 'HTTP Child Group',
          type: 'Group',
          numberOfChildren: 1,
          unitId: primaryUnit.id,
          unit: primaryUnit.display_label,
          parentGroupId: root.linkedGroupId,
          groupMode: 'nested_group',
          inheritanceEnabled: true,
          selectedItemIds: [seedItem.id],
          propertyDrafts: [
            {
              name: 'Density',
              propertyKey: 'density',
              inputType: 'Number',
              mandatory: true,
              sourceType: 'manual',
              state: 'active',
              overrideLocked: false,
              hasTypeConflict: false,
              unitSymbol: 'mm',
              unitLabel: 'Millimetre',
              sources: [],
            },
          ],
          discardedPropertyKeys: ['material'],
          notes: 'Created from inventory modal test',
        },
      );
      assert.equal(createResponse.status, 201);
      assert.ok(createResponse.body.material?.linkedGroupId);

      const createdGovernance = await backend.getMaterialGroupGovernance(
        createResponse.body.material.id,
      );
      assert.deepEqual(createdGovernance.selectedItemIds, [seedItem.id]);
      assert.deepEqual(createdGovernance.discardedPropertyKeys, ['material']);
      assert.ok(
        createdGovernance.propertyDrafts.some(
          (draft) =>
            draft.propertyKey === 'density' && draft.inputType === 'Number',
        ),
        'expected density draft to persist as structured governance',
      );

      const schemaResponse = await getJson(
        baseUrl,
        `/api/groups/${createResponse.body.material.linkedGroupId}/effective-schema`,
        owner.token,
      );
      assert.equal(schemaResponse.status, 200);
      assert.deepEqual(
        schemaResponse.body.schema.lineageGroupIds.slice(-2),
        [root.linkedGroupId, createResponse.body.material.linkedGroupId],
      );
      assert.equal(
        schemaResponse.body.schema.propertyDrafts.some(
          (draft) => draft.propertyKey === 'material',
        ),
        false,
      );
      assert.ok(
        schemaResponse.body.schema.propertyDrafts.some(
          (draft) => draft.propertyKey === 'density',
        ),
      );
    } finally {
      await closeServer(server);
    }
  } finally {
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

async function listen(app) {
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  return { server, port: address.port };
}

async function closeServer(server) {
  await new Promise((resolve, reject) =>
    server.close((error) => (error ? reject(error) : resolve())),
  );
}

async function getJson(baseUrl, pathname, token) {
  return requestJson(baseUrl, pathname, 'GET', token, null);
}

async function postJson(baseUrl, pathname, token, body) {
  return requestJson(baseUrl, pathname, 'POST', token, JSON.stringify(body));
}

async function requestJson(baseUrl, pathname, method, token, body) {
  const target = new URL(pathname, baseUrl);
  const headers = { Accept: 'application/json' };
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }
  if (body != null) {
    headers['Content-Type'] = 'application/json';
    headers['Content-Length'] = Buffer.byteLength(body);
  }
  const response = await fetch(target, { method, headers, body });
  const text = await response.text();
  return {
    status: response.status,
    body: text ? JSON.parse(text) : null,
  };
}
