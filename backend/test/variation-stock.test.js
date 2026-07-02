const assert = require('node:assert/strict');
const test = require('node:test');
const backend = require('../server.js');

test('Variation Stock API', async (t) => {
  await t.test('setup', async () => {
    await backend.resetAndSeedDemoData();
    await backend.run("INSERT INTO material_groups (id, name) VALUES (999, 'Test Group') ON CONFLICT DO NOTHING");
    await backend.run("INSERT INTO items (id, name, group_id, unit_id) VALUES (1, 'Test Item', 999, 1) ON CONFLICT DO NOTHING");
    await backend.run("INSERT INTO variation_tree_nodes (id, item_id, name) VALUES (1, 1, 'Leaf') ON CONFLICT DO NOTHING");
  });

  await t.test('aggregates stock on reception challan issue', async () => {
    await backend.run("INSERT INTO delivery_challans (id, challan_no, type, date, status, created_at, updated_at) VALUES (999, 'REC-999', 'reception', '2023-01-01', 'draft', '2023-01-01T00:00:00Z', '2023-01-01T00:00:00Z')");
    await backend.run("INSERT INTO delivery_challan_items (challan_id, item_id, variation_leaf_node_id, quantity_pcs, created_at, updated_at) VALUES (999, 1, 1, 50, '2023-01-01T00:00:00Z', '2023-01-01T00:00:00Z')");
    await backend.issueDeliveryChallan(999, { id: 1, name: 'Admin' });
    const stock = await backend.get("SELECT quantity FROM variation_stock WHERE item_id = 1 AND variation_leaf_node_id = 1");
    assert.ok(stock);
    assert.strictEqual(stock.quantity, 50);
  });

  await t.test('decrements stock on delivery challan issue', async () => {
    await backend.run("INSERT INTO variation_stock (item_id, variation_leaf_node_id, quantity, location_id) VALUES (1, 1, 100, 'MAIN') ON CONFLICT DO UPDATE SET quantity = 100");
    await backend.run("INSERT INTO delivery_challans (id, challan_no, type, date, status, created_at, updated_at) VALUES (998, 'DEL-998', 'delivery', '2023-01-01', 'draft', '2023-01-01T00:00:00Z', '2023-01-01T00:00:00Z')");
    await backend.run("INSERT INTO delivery_challan_items (challan_id, item_id, variation_leaf_node_id, quantity_pcs, created_at, updated_at) VALUES (998, 1, 1, 30, '2023-01-01T00:00:00Z', '2023-01-01T00:00:00Z')");
    await backend.issueDeliveryChallan(998, { id: 1, name: 'Admin' });
    const stock = await backend.get("SELECT quantity FROM variation_stock WHERE item_id = 1 AND variation_leaf_node_id = 1");
    assert.ok(stock);
    assert.strictEqual(stock.quantity, 70);
  });

  await t.test('prevents delivery challan from driving stock negative', async () => {
    await backend.run("INSERT INTO variation_stock (item_id, variation_leaf_node_id, quantity, location_id) VALUES (1, 1, 10, 'MAIN') ON CONFLICT DO UPDATE SET quantity = 10");
    await backend.run("INSERT INTO delivery_challans (id, challan_no, type, date, status, created_at, updated_at) VALUES (997, 'DEL-997', 'delivery', '2023-01-01', 'draft', '2023-01-01T00:00:00Z', '2023-01-01T00:00:00Z')");
    await backend.run("INSERT INTO delivery_challan_items (challan_id, item_id, variation_leaf_node_id, quantity_pcs, created_at, updated_at) VALUES (997, 1, 1, 50, '2023-01-01T00:00:00Z', '2023-01-01T00:00:00Z')");
    try {
      await backend.issueDeliveryChallan(997, { id: 1, name: 'Admin' });
      assert.fail('Should have thrown an error due to negative stock');
    } catch (e) {
      assert.ok(e.message.includes('Insufficient stock'), e.message);
    }
  });

  await t.test('reverts stock accurately when a challan is cancelled', async () => {
    await backend.run("INSERT INTO variation_stock (item_id, variation_leaf_node_id, quantity, location_id) VALUES (1, 1, 100, 'MAIN') ON CONFLICT DO UPDATE SET quantity = 100");
    await backend.run("INSERT INTO delivery_challans (id, challan_no, type, date, status, created_at, updated_at) VALUES (996, 'DEL-996', 'delivery', '2023-01-01', 'draft', '2023-01-01T00:00:00Z', '2023-01-01T00:00:00Z')");
    await backend.run("INSERT INTO delivery_challan_items (challan_id, item_id, variation_leaf_node_id, quantity_pcs, created_at, updated_at) VALUES (996, 1, 1, 40, '2023-01-01T00:00:00Z', '2023-01-01T00:00:00Z')");
    await backend.issueDeliveryChallan(996, { id: 1, name: 'Admin' });
    let stock = await backend.get("SELECT quantity FROM variation_stock WHERE item_id = 1 AND variation_leaf_node_id = 1");
    assert.strictEqual(stock.quantity, 60);
    await backend.cancelDeliveryChallan(996, { id: 1, name: 'Admin' });
    stock = await backend.get("SELECT quantity FROM variation_stock WHERE item_id = 1 AND variation_leaf_node_id = 1");
    assert.strictEqual(stock.quantity, 100);
  });
});
