const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

test('orders persistence functions create, list, and update lifecycle', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-orders-api-'));
  const dbPath = path.join(tempDir, 'paper.db');
  process.env.DB_PATH = dbPath;

  const backend = require('../server.js');

  try {
    await backend.initDb();

    const seededClients = await backend.getClientsWithUsage();
    const seededItems = await backend.getItemsWithUsage();
    const seededOrders = await backend.getOrders();
    const seededUnits = await backend.getUnitsWithUsage();
    assert.ok(seededUnits.length >= 4, 'expected seeded mock units');
    assert.ok(seededClients.length >= 3, 'expected seeded mock clients');
    assert.ok(seededItems.length >= 2, 'expected seeded mock items');
    assert.ok(seededOrders.length >= 4, 'expected seeded mock orders');

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

    const created = await backend.saveOrder({
      orderNo: 'ORD-DB-001',
      clientId: client.id,
      clientName: client.name,
      poNumber: 'PO-DB-77',
      clientCode: client.alias,
      itemId: item.id,
      itemName: item.displayName,
      variationLeafNodeId: leaf.id,
      variationPathLabel: leaf.displayName,
      variationPathNodeIds: leaf.path,
      quantity: 12,
      status: 'inProgress',
      startDate: '2026-04-04T00:00:00.000Z',
      endDate: '2026-04-10T00:00:00.000Z',
    });

    const createdDto = backend.rowToOrderDto
        ? backend.rowToOrderDto(created)
        : created;
    assert.equal(createdDto.orderNo, 'ORD-DB-001');
    assert.equal(createdDto.status, 'inProgress');
    assert.equal(createdDto.quantity, 12);

    const listedRows = await backend.getOrders();
    assert.equal(listedRows.length, seededOrders.length + 1);
    assert.ok(
      listedRows.some(
        (entry) =>
          entry.order_no === 'ORD-DB-001' && entry.variation_leaf_node_id === leaf.id,
      ),
    );

    const updated = await backend.updateOrderLifecycle({
      id: created.id,
      status: 'completed',
      startDate: '2026-04-05T00:00:00.000Z',
      endDate: '2026-04-12T00:00:00.000Z',
    });
    const updatedDto = backend.rowToOrderDto ? backend.rowToOrderDto(updated) : updated;
    assert.equal(updatedDto.status, 'completed');
    assert.equal(updatedDto.endDate, '2026-04-12T00:00:00.000Z');
  } finally {
    await backend.closeDb();
  }
});

function findFirstLeafVariation(nodes, currentPath = []) {
  for (const node of nodes) {
    const nextPath = [...currentPath, node.id];
    if (node.kind === 'value' && (!node.children || node.children.length === 0)) {
      return { id: node.id, displayName: node.displayName, path: nextPath };
    }
    const nested = findFirstLeafVariation(node.children || [], nextPath);
    if (nested) {
      return nested;
    }
  }
  return null;
}
