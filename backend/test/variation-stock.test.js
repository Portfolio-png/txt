const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

test('variation stock aggregates challan and inventory movement flows', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-variation-stock-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'stock-owner@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  let server = null;

  try {
    await backend.resetAndSeedDemoData();
    const actor = { id: 1, name: 'Stock Tester', role: 'admin' };
    const location = 'Variation Bay';
    const order = (await backend.getOrders()).find(
      (entry) => entry.item_id && entry.variation_leaf_node_id,
    );
    assert.ok(order, 'expected a seeded order with an item variation leaf');

    const vendor = await backend.saveVendor({
      name: 'Variation Supplier',
      gstNumber: '27ABCDE1234F1Z5',
      phone: '9999999999',
    });

    const reception = await backend.saveDeliveryChallan(
      {
        type: 'reception',
        date: '2026-07-02',
        location,
        vendor_id: vendor.id,
        source_reference: 'VAR-GRN-1',
        items: [
          {
            item_id: order.item_id,
            variation_leaf_node_id: order.variation_leaf_node_id,
            quantity_pcs: '50',
            weight: '',
          },
        ],
      },
      actor,
      { user: actor },
    );

    await backend.issueDeliveryChallan(reception.id, actor);
    let stock = await getStock(
      backend,
      order.item_id,
      order.variation_leaf_node_id,
      location,
    );
    assert.equal(stock, 50);

    const delivery = await backend.saveDeliveryChallan(
      {
        order_id: order.id,
        date: '2026-07-03',
        location,
        notes: '',
        items: [
          {
            order_item_id: order.id,
            quantity_pcs: '20',
            weight: '',
          },
        ],
      },
      actor,
      { user: actor },
    );

    await backend.issueDeliveryChallan(delivery.id, actor);
    stock = await getStock(backend, order.item_id, order.variation_leaf_node_id, location);
    assert.equal(stock, 30);

    const insufficient = await backend.saveDeliveryChallan(
      {
        order_id: order.id,
        date: '2026-07-04',
        location,
        notes: '',
        items: [
          {
            order_item_id: order.id,
            quantity_pcs: '500',
            weight: '',
          },
        ],
      },
      actor,
      { user: actor },
    );
    await assert.rejects(
      () => backend.issueDeliveryChallan(insufficient.id, actor),
      /Insufficient stock/,
    );
    stock = await getStock(backend, order.item_id, order.variation_leaf_node_id, location);
    assert.equal(stock, 30);

    await backend.cancelDeliveryChallan(delivery.id, actor);
    stock = await getStock(backend, order.item_id, order.variation_leaf_node_id, location);
    assert.equal(stock, 50);

    const material = await backend.ensureMaterialForItemSelection({
      itemId: order.item_id,
      variationLeafNodeId: order.variation_leaf_node_id,
      actor,
    });
    await backend.applyInventoryMovement({
      barcode: material.barcode,
      movementType: 'receive',
      qty: 5,
      toLocationId: location,
      referenceType: 'manual-receipt',
      referenceId: 'VAR-RECEIPT-1',
      actor,
    });
    const movement = await backend.get(
      `
      SELECT item_id, variation_leaf_node_id
      FROM inventory_movements
      WHERE reference_type = 'manual-receipt' AND reference_id = 'VAR-RECEIPT-1'
      LIMIT 1
      `,
    );
    assert.equal(Number(movement.item_id), Number(order.item_id));
    assert.equal(
      Number(movement.variation_leaf_node_id),
      Number(order.variation_leaf_node_id),
    );
    stock = await getStock(backend, order.item_id, order.variation_leaf_node_id, location);
    assert.equal(stock, 55);

    ({ server } = await listen(backend.app));
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const owner = await login(baseUrl, 'stock-owner@paper.local', 'OwnerPass1234');
    const response = await getJson(baseUrl, '/api/inventory/stock', owner.token);
    assert.equal(response.status, 200);
    assert.equal(response.body.success, true);
    const endpointRow = response.body.stock.find(
      (entry) =>
        Number(entry.item_id) === Number(order.item_id) &&
        Number(entry.variation_leaf_node_id) === Number(order.variation_leaf_node_id) &&
        entry.location_id === location,
    );
    assert.ok(endpointRow, 'expected endpoint to include the variation stock row');
    assert.equal(Number(endpointRow.unit_id) > 0, true);
    assert.equal(Array.isArray(endpointRow.variation_path_node_ids), true);
    assert.equal(Array.isArray(endpointRow.variation_path), true);
    assert.ok(endpointRow.variation_path.length > 0, 'expected ordered variation path');
    assert.equal(
      endpointRow.variation_path.at(-1).node_id,
      order.variation_leaf_node_id,
    );

    const groups = await backend.getGroupsWithUsage();
    const units = await backend.getUnitsWithUsage();
    const group = groups.find((entry) => !entry.is_archived);
    const unit = units.find((entry) => !entry.is_archived);
    assert.ok(group, 'expected a group for cascade test item');
    assert.ok(unit, 'expected a unit for cascade test item');
    const cascadeItemRow = await backend.saveItem({
      name: 'Variation Stock Cascade Item',
      displayName: 'Variation Stock Cascade Item',
      quantity: 1,
      groupId: group.id,
      unitId: unit.id,
      variationTree: [
        {
          kind: 'property',
          name: 'Color',
          children: [{ kind: 'value', name: 'Blue' }],
        },
      ],
    });
    const cascadeItem = await backend.rowToItemDto(cascadeItemRow);
    const cascadeLeaf = findFirstLeafVariation(cascadeItem.variationTree);
    assert.ok(cascadeLeaf, 'expected cascade test item to have a leaf variation');
    await backend.run(
      `
      INSERT INTO variation_stock (
        item_id, variation_leaf_node_id, quantity, location_id
      ) VALUES (?, ?, 12, 'MAIN')
      `,
      [cascadeItem.id, cascadeLeaf.id],
    );
    await backend.run('DELETE FROM items WHERE id = ?', [cascadeItem.id]);
    const cascadeStock = await backend.get(
      'SELECT COUNT(*) AS count FROM variation_stock WHERE item_id = ?',
      [cascadeItem.id],
    );
    assert.equal(Number(cascadeStock.count || 0), 0);
  } finally {
    if (server) {
      await closeServer(server);
    }
    await backend.closeDb();
  }
});

async function getStock(backend, itemId, variationLeafNodeId, locationId) {
  const row = await backend.get(
    `
    SELECT quantity
    FROM variation_stock
    WHERE item_id = ? AND variation_leaf_node_id = ? AND location_id = ?
    `,
    [itemId, variationLeafNodeId, locationId],
  );
  return Number(row?.quantity || 0);
}

function findFirstLeafVariation(nodes, currentPath = []) {
  for (const node of nodes || []) {
    const nextPath = node.kind === 'value' ? [...currentPath, node.id] : currentPath;
    if (node.kind === 'value' && (!node.children || node.children.length === 0)) {
      return { id: node.id, path: nextPath };
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

async function postJson(baseUrl, pathname, token, body) {
  const response = await fetch(`${baseUrl}${pathname}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
  return { status: response.status, body: await response.json() };
}

async function getJson(baseUrl, pathname, token) {
  const response = await fetch(`${baseUrl}${pathname}`, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  return { status: response.status, body: await response.json() };
}

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => resolve({ server }));
    server.on('error', reject);
  });
}

function closeServer(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}
