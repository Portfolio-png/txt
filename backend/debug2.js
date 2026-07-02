const test = require('node:test');
const { app } = require('./server.js');
const backend = require('./server.js');
test('debug2', async () => {
  await backend.resetAndSeedDemoData();
  const actor = { id: 1, name: 'Admin' };
  const activeOrders = await backend.all('SELECT * FROM order_items WHERE is_archived = 0 AND variation_leaf_node_id IS NOT NULL');
  const order = activeOrders.find(o => o.status === 'production') || activeOrders[0];
  const material = await backend.ensureMaterialForItemSelection({ itemId: order.item_id, variationLeafNodeId: order.variation_leaf_node_id, actor });
  console.log('Material linked items:', material.linked_item_id, material.linked_variation_leaf_node_id);
  await backend.applyInventoryMovement({
    barcode: material.barcode,
    movementType: 'receive',
    qty: 10,
    toLocationId: 'Dispatch Bay',
    referenceType: 'manual-receipt',
    referenceId: 'SNAPSHOT-SEED-1',
    actor,
  });
  const stock = await backend.get('SELECT * FROM variation_stock');
  console.log('Stock:', stock);
});
