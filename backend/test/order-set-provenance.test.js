const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// An order expands a set into ordinary item lines rather than pointing at the
// set, so that editing the set can never rewrite a placed order. The cost is
// that nothing said those lines were ever one thing. These columns are that
// memory: dead labels, snapshotted at order time.
test('order lines remember the set they were expanded from', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-order-set-prov-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'prov-owner@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'ProvOwner1234';

  const backendPath = require.resolve('../server.js');
  delete require.cache[backendPath];
  const backend = require('../server.js');

  try {
    await backend.resetAndSeedDemoData();

    const columns = await backend.all('PRAGMA table_info(order_items)');
    for (const name of [
      'source_set_id',
      'source_set_name',
      'source_set_multiplier',
    ]) {
      assert.equal(
        columns.some((column) => column.name === name),
        true,
        `order_items must expose ${name}`,
      );
    }

    const clientRow = (await backend.getClientsWithUsage()).find(
      (entry) => !entry.is_archived,
    );
    assert.ok(clientRow, 'expected an active seeded client');
    const client = backend.rowToClientDto(clientRow);

    const itemRows = await backend.getItemsWithUsage();
    const itemRow = itemRows.find((entry) => !entry.is_archived);
    assert.ok(itemRow, 'expected an active seeded item');
    const item = await backend.rowToItemDto(itemRow);
    const leaf = findFirstLeafVariation(item.variationTree || []);
    assert.ok(leaf, 'expected a seeded leaf variation path');

    const { server, port } = await listen(backend.app);
    const baseUrl = `http://127.0.0.1:${port}`;

    try {
      const owner = await login(
        baseUrl,
        'prov-owner@paper.local',
        'ProvOwner1234',
      );

      const line = {
        clientId: client.id,
        clientName: client.name,
        poNumber: 'PO-PROV-1',
        clientCode: client.alias,
        itemId: item.id,
        itemName: item.displayName,
        variationLeafNodeId: leaf.id,
        variationPathLabel: leaf.displayName,
        variationPathNodeIds: leaf.path,
      };

      // A line expanded from a set carries the set's name and multiplier.
      const created = await postJson(baseUrl, '/api/orders', owner.token, {
        ...line,
        orderNo: 'ORD-PROV-1',
        quantity: 6,
        status: 'notStarted',
        sourceSetId: 42,
        sourceSetName: 'Starter Pack',
        sourceSetMultiplier: 3,
      });
      assert.equal(created.status, 201);
      assert.equal(created.body.order.sourceSetId, 42);
      assert.equal(created.body.order.sourceSetName, 'Starter Pack');
      assert.equal(created.body.order.sourceSetMultiplier, 3);

      // Merging more quantity onto that line must not erase where it came
      // from, even when the incoming line names no set.
      const merged = await postJson(baseUrl, '/api/orders', owner.token, {
        ...line,
        orderNo: 'ORD-PROV-1',
        quantity: 4,
        status: 'notStarted',
      });
      assert.equal(merged.status, 200);
      assert.equal(merged.body.merged, true);
      assert.equal(merged.body.order.quantity, 10);
      assert.equal(
        merged.body.order.sourceSetName,
        'Starter Pack',
        'a merge must not wipe the provenance already recorded',
      );
      assert.equal(merged.body.order.sourceSetMultiplier, 3);

      // A hand-picked line claims no set — the columns must stay empty rather
      // than inheriting anything.
      const plain = await postJson(baseUrl, '/api/orders', owner.token, {
        ...line,
        orderNo: 'ORD-PROV-2',
        poNumber: 'PO-PROV-2',
        quantity: 2,
        status: 'notStarted',
      });
      assert.equal(plain.status, 201);
      assert.equal(plain.body.order.sourceSetId, null);
      assert.equal(plain.body.order.sourceSetName, '');
      assert.equal(plain.body.order.sourceSetMultiplier, 0);

      // And it survives a re-read, not just the create response.
      const listed = await getJson(baseUrl, '/api/orders', owner.token);
      assert.equal(listed.status, 200);
      const reread = (listed.body.orders || []).find(
        (entry) => entry.orderNo === 'ORD-PROV-1',
      );
      assert.ok(reread, 'expected ORD-PROV-1 in the list');
      assert.equal(reread.sourceSetName, 'Starter Pack');
      assert.equal(reread.sourceSetMultiplier, 3);
    } finally {
      await closeServer(server);
    }
  } finally {
    await backend.closeDatabase?.();
  }
});

function findFirstLeafVariation(nodes, currentPath = []) {
  for (const node of nodes) {
    const nextPath =
      node.kind === 'value' ? [...currentPath, node.id] : [...currentPath];
    if (node.kind === 'value' && (!node.children || node.children.length === 0)) {
      return {
        id: node.id,
        displayName: node.displayName || node.name,
        path: nextPath,
      };
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
  return { server, port: server.address().port };
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
  return { status: response.status, body: text ? JSON.parse(text) : null };
}
