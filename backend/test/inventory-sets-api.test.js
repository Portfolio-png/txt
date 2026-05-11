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

test('inventory sets can be created, merged, listed, rejected, and deleted', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-inventory-sets-'));
  const dbPath = path.join(tempDir, 'paper.db');
  process.env.DB_PATH = dbPath;
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'sets-owner@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'SetsOwner1234';

  const backend = loadFreshBackend();

  try {
    await backend.resetAndSeedDemoData();
    const itemRows = await backend.getItemsWithUsage();
    const firstRow = itemRows.find((entry) => !entry.is_archived);
    const secondRow = itemRows.find(
      (entry) => !entry.is_archived && entry.id !== firstRow?.id,
    );
    assert.ok(firstRow, 'expected first active item');
    assert.ok(secondRow, 'expected second active item');
    const firstItem = await backend.rowToItemDto(firstRow);
    const secondItem = await backend.rowToItemDto(secondRow);
    const firstLeaf = findFirstLeafVariation(firstItem.variationTree || []);
    const secondLeaf = findFirstLeafVariation(secondItem.variationTree || []);
    assert.ok(firstLeaf, 'expected first leaf variation');
    assert.ok(secondLeaf, 'expected second leaf variation');

    const { server, port } = await listen(backend.app);
    const baseUrl = `http://127.0.0.1:${port}`;

    try {
      const owner = await login(
        baseUrl,
        'sets-owner@paper.local',
        'SetsOwner1234',
      );

      const created = await postJson(
        baseUrl,
        '/api/inventory/sets',
        owner.token,
        {
          name: 'Starter Pack',
          lines: [
            {
              itemId: firstItem.id,
              variationLeafNodeId: firstLeaf.id,
              quantity: 2,
              position: 0,
            },
            {
              itemId: firstItem.id,
              variationLeafNodeId: firstLeaf.id,
              quantity: 3,
              position: 1,
            },
            {
              itemId: secondItem.id,
              variationLeafNodeId: secondLeaf.id,
              quantity: 5,
              position: 2,
            },
          ],
        },
      );
      assert.equal(created.status, 201);
      assert.equal(created.body.set.name, 'Starter Pack');
      assert.equal(created.body.set.totalItemCount, 10);
      assert.equal(created.body.set.lines.length, 2);
      assert.equal(created.body.set.lines[0].quantity, 5);

      const list = await getJson(baseUrl, '/api/inventory/sets', owner.token);
      assert.equal(list.status, 200);
      assert.equal(list.body.sets.length, 1);
      assert.equal(list.body.sets[0].name, 'Starter Pack');
      assert.equal(list.body.sets[0].totalItemCount, 10);

      const invalid = await postJson(
        baseUrl,
        '/api/inventory/sets',
        owner.token,
        {
          name: 'Broken Pack',
          lines: [
            {
              itemId: firstItem.id,
              variationLeafNodeId: secondLeaf.id,
              quantity: 1,
              position: 0,
            },
          ],
        },
      );
  assert.equal(invalid.status, 400);
  assert.match(
    invalid.body.error,
    /does not belong to the selected item|variation leaf|selected variation path is not valid for this item/i,
  );

      const deleted = await requestJson(
        baseUrl,
        `/api/inventory/sets/${created.body.set.id}`,
        'DELETE',
        owner.token,
        null,
      );
      assert.equal(deleted.status, 200);

      const afterDelete = await getJson(
        baseUrl,
        '/api/inventory/sets',
        owner.token,
      );
      assert.equal(afterDelete.status, 200);
      assert.equal(afterDelete.body.sets.length, 0);
    } finally {
      await closeServer(server);
    }
  } finally {
    await backend.closeDb();
  }
});

test('inventory sets reject mixed valid and invalid lines without partial save', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-inventory-sets-strict-'));
  const dbPath = path.join(tempDir, 'paper.db');
  process.env.DB_PATH = dbPath;
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'sets-strict@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'SetsStrict1234';

  const backend = loadFreshBackend();

  try {
    await backend.resetAndSeedDemoData();
    const itemRows = await backend.getItemsWithUsage();
    const firstRow = itemRows.find((entry) => !entry.is_archived);
    assert.ok(firstRow, 'expected active item');
    const firstItem = await backend.rowToItemDto(firstRow);
    const firstLeaf = findFirstLeafVariation(firstItem.variationTree || []);
    assert.ok(firstLeaf, 'expected orderable leaf');

    const { server, port } = await listen(backend.app);
    const baseUrl = `http://127.0.0.1:${port}`;

    try {
      const owner = await login(
        baseUrl,
        'sets-strict@paper.local',
        'SetsStrict1234',
      );

      const invalid = await postJson(
        baseUrl,
        '/api/inventory/sets',
        owner.token,
        {
          name: 'Mixed Pack',
          lines: [
            {
              itemId: firstItem.id,
              variationLeafNodeId: firstLeaf.id,
              quantity: 2,
              position: 0,
            },
            {
              itemId: firstItem.id,
              variationLeafNodeId: firstLeaf.id,
              quantity: 0,
              position: 1,
            },
          ],
        },
      );

      assert.equal(invalid.status, 400);
      assert.match(invalid.body.error, /set line 2|quantity greater than 0/i);

      const list = await getJson(baseUrl, '/api/inventory/sets', owner.token);
      assert.equal(list.status, 200);
      assert.equal(list.body.sets.length, 0);
    } finally {
      await closeServer(server);
    }
  } finally {
    await backend.closeDb();
  }
});

test('inventory sets allow base items with no variation leaf', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-inventory-sets-base-'));
  const dbPath = path.join(tempDir, 'paper.db');
  process.env.DB_PATH = dbPath;
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'sets-base@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'SetsBase1234';

  const backend = loadFreshBackend();

  try {
    await backend.resetAndSeedDemoData();
    const groupRows = await backend.getGroupsWithUsage();
    const unitRows = await backend.getUnitsWithUsage();
    const groupRow = groupRows.find((entry) => !entry.is_archived);
    const unitRow = unitRows.find((entry) => !entry.is_archived);
    assert.ok(groupRow, 'expected active group');
    assert.ok(unitRow, 'expected active unit');
    const baseItem = await backend.saveItem({
      name: 'Base Set Item',
      displayName: 'Base Set Item',
      groupId: groupRow.id,
      unitId: unitRow.id,
      variationTree: [],
    });

    const { server, port } = await listen(backend.app);
    const baseUrl = `http://127.0.0.1:${port}`;

    try {
      const owner = await login(
        baseUrl,
        'sets-base@paper.local',
        'SetsBase1234',
      );

      const created = await postJson(
        baseUrl,
        '/api/inventory/sets',
        owner.token,
        {
          name: 'Base Item Pack',
          lines: [
            {
              itemId: baseItem.id,
              variationLeafNodeId: 0,
              quantity: 4,
              position: 0,
            },
          ],
        },
      );
      assert.equal(created.status, 201);
      assert.equal(created.body.set.lines.length, 1);
      assert.equal(created.body.set.lines[0].variationLeafNodeId, 0);
      assert.equal(created.body.set.lines[0].variationPathLabel, 'Base item');
      assert.equal(created.body.set.lines[0].quantity, 4);
    } finally {
      await closeServer(server);
    }
  } finally {
    await backend.closeDb();
  }
});

function findFirstLeafVariation(nodes, currentPath = []) {
  for (const node of nodes || []) {
    const nextPath =
      node.kind === 'value' ? [...currentPath, node.id] : currentPath;
    if (node.kind === 'value' && (!node.children || node.children.length === 0)) {
      return { ...node, path: nextPath };
    }
    const nested = findFirstLeafVariation(node.children || [], nextPath);
    if (nested) {
      return nested;
    }
  }
  return null;
}

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
