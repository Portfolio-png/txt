const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

test('delivery challans create issue and preserve company profile snapshot', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-delivery-challans-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  try {
    await backend.resetAndSeedDemoData();
    const challanItemColumns = await backend.all("PRAGMA table_info(delivery_challan_items)");
    assert.equal(
      challanItemColumns.find((column) => column.name === 'quantity_pcs')?.type,
      'REAL',
    );
    assert.equal(
      challanItemColumns.find((column) => column.name === 'weight')?.type,
      'REAL',
    );
    const actor = { id: 1, name: 'Delivery Tester', role: 'admin' };

    const profile = await backend.getActiveCompanyProfile();
    assert.equal(profile.company_name, 'Shree Ganesh Metal Works');
    const orders = await backend.getOrders();
    assert.ok(orders.length > 0, 'expected seeded orders for challan creation');
    const order = orders[0];

    const created = await backend.saveDeliveryChallan(
      {
        order_id: order.id,
        date: '2026-05-04',
        location: 'Dispatch Bay',
        notes: '',
        items: [
          {
            order_item_id: order.id,
            quantity_pcs: '10',
            weight: '2.5',
          },
        ],
      },
      actor,
      { user: actor },
    );
    assert.match(created.challan_no, /^DC-/);
    assert.equal(created.type, 'delivery');
    assert.equal(created.order_id, order.id);
    assert.equal(created.location, 'Dispatch Bay');
    assert.equal(created.customer_name, order.client_name);
    assert.equal(created.status, 'draft');
    const aggregated = await backend.get(
      `
      SELECT
        SUM(quantity_pcs) AS total_qty,
        SUM(weight) AS total_weight
      FROM delivery_challan_items
      WHERE challan_id = ?
      `,
      [created.id],
    );
    assert.equal(Number(aggregated.total_qty || 0), 10);
    assert.equal(Number(aggregated.total_weight || 0), 2.5);

    const material = await backend.ensureMaterialForItemSelection({
      itemId: order.item_id,
      variationLeafNodeId: order.variation_leaf_node_id || 0,
      actor,
    });
    await backend.applyInventoryMovement({
      barcode: material.barcode,
      movementType: 'receive',
      qty: 50,
      toLocationId: 'Dispatch Bay',
      actor,
    });

    const issued = await backend.issueDeliveryChallan(created.id, actor);
    assert.equal(issued.status, 'issued');

    await backend.saveCompanyProfile({
      company_name: 'Changed Company',
      mobile: '1',
    });

    const issuedRow = await backend.get(
      'SELECT company_profile_snapshot FROM delivery_challans WHERE id = ?',
      [created.id],
    );
    const snapshot = JSON.parse(issuedRow.company_profile_snapshot);
    assert.equal(snapshot.company_name, 'Shree Ganesh Metal Works');

    const empty = await backend.saveDeliveryChallan(
      { order_id: order.id, date: '2026-05-04', location: 'Dispatch Bay', items: [] },
      actor,
      { user: actor },
    );
    await assert.rejects(
      () => backend.issueDeliveryChallan(empty.id, actor),
      /Add at least one line item before issuing challan/,
    );

    const zeroMeasure = await backend.saveDeliveryChallan(
      {
        order_id: order.id,
        date: '2026-05-04',
        location: 'Dispatch Bay',
        items: [
          {
            order_item_id: order.id,
            quantity_pcs: '0',
            weight: '0',
          },
        ],
      },
      actor,
      { user: actor },
    );
    await assert.rejects(
      () => backend.issueDeliveryChallan(zeroMeasure.id, actor),
      /Enter Qty \/ Pcs or Weight/,
    );

    await assert.rejects(
      () =>
        backend.saveDeliveryChallan(
          {
            order_id: order.id,
            date: '2026-05-04',
            location: 'Dispatch Bay',
            items: [
              {
                order_item_id: order.id,
                quantity_pcs: '-1',
                weight: '',
              },
            ],
          },
          actor,
          { user: actor },
        ),
      /Invalid challan quantity/,
    );
  } finally {
    await backend.closeDb();
  }
});

test('reception challans issue and cancel with vendor-linked stock provenance', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-reception-challans-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  try {
    await backend.resetAndSeedDemoData();
    const actor = { id: 1, name: 'Reception Tester', role: 'admin' };
    const vendor = await backend.saveVendor({
      name: 'Supplier A',
      gstNumber: '27ABCDE1234F1Z5',
      phone: '9999999999',
    });
    const seededOrder = (await backend.getOrders())[0];
    assert.ok(seededOrder, 'expected seeded order to source a valid item selection');
    const location = 'Inbound Dock';

    const created = await backend.saveDeliveryChallan(
      {
        type: 'reception',
        date: '2026-05-04',
        location,
        vendor_id: vendor.id,
        source_reference: 'GRN-101',
        items: [
          {
            item_id: seededOrder.item_id,
            variation_leaf_node_id: seededOrder.variation_leaf_node_id || 0,
            quantity_pcs: '25',
            weight: '',
          },
        ],
      },
      actor,
      { user: actor },
    );

    assert.match(created.challan_no, /^RC-/);
    assert.equal(created.type, 'reception');
    assert.equal(created.vendor_id, vendor.id);
    assert.equal(created.location, location);

    const receptionList = await backend.listDeliveryChallans({ type: 'reception' });
    assert.ok(
      receptionList.some((challan) => challan.id === created.id),
      'expected reception challan in type-filtered list',
    );

    const issued = await backend.issueDeliveryChallan(created.id, actor);
    assert.equal(issued.status, 'issued');

    const movement = await backend.get(
      `
      SELECT *
      FROM inventory_movements
      WHERE source_challan_id = ? AND source_challan_type = 'reception'
      ORDER BY created_at ASC, id ASC
      LIMIT 1
      `,
      [created.id],
    );
    const material = await backend.getMaterialRowByBarcode(movement.material_barcode);
    assert.ok(material, 'expected linked material after reception issue');
    assert.equal(movement.movement_type, 'receive');
    assert.equal(movement.reference_type, 'challan');
    assert.equal(movement.reference_id, created.challan_no);

    const issuedPosition = await backend.get(
      `
      SELECT on_hand_qty
      FROM inventory_stock_positions
      WHERE material_barcode = ? AND location_id = ? AND lot_code = ?
      `,
      [material.barcode, location, material.barcode],
    );
    assert.equal(Number(issuedPosition?.on_hand_qty || 0), 25);

    const cancelled = await backend.cancelDeliveryChallan(created.id, actor);
    assert.equal(cancelled.status, 'cancelled');

    const reversedPosition = await backend.get(
      `
      SELECT on_hand_qty
      FROM inventory_stock_positions
      WHERE material_barcode = ? AND location_id = ? AND lot_code = ?
      `,
      [material.barcode, location, material.barcode],
    );
    assert.equal(Number(reversedPosition?.on_hand_qty || 0), 0);

    const reversalCount = await backend.get(
      `
      SELECT COUNT(*) AS count
      FROM inventory_movements
      WHERE source_challan_id = ? AND source_challan_type = 'reception'
      `,
      [created.id],
    );
    assert.equal(Number(reversalCount.count || 0), 2);
  } finally {
    await backend.closeDb();
  }
});

test('reception challans reject archived vendors and list filters stay scoped', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-challan-filters-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  try {
    await backend.resetAndSeedDemoData();
    const actor = { id: 1, name: 'Filter Tester', role: 'admin' };
    const seededOrder = (await backend.getOrders())[0];
    assert.ok(seededOrder, 'expected seeded order for challan setup');

    const archivedVendor = await backend.saveVendor({
      name: 'Archived Supplier',
      gstNumber: '27ARCH1234F1Z5',
    });
    await backend.run('UPDATE vendors SET is_archived = 1 WHERE id = ?', [
      archivedVendor.id,
    ]);

    await assert.rejects(
      () =>
        backend.saveDeliveryChallan(
          {
            type: 'reception',
            date: '2026-05-04',
            location: 'Inbound Dock',
            vendor_id: archivedVendor.id,
            source_reference: 'GRN-ARCHIVED',
            items: [
              {
                item_id: seededOrder.item_id,
                variation_leaf_node_id: seededOrder.variation_leaf_node_id || 0,
                quantity_pcs: '5',
                weight: '',
              },
            ],
          },
          actor,
          { user: actor },
        ),
      /Select an active vendor before saving reception challan/,
    );

    const activeVendor = await backend.saveVendor({
      name: 'Active Supplier',
      gstNumber: '27ACTIVE1234F1Z5',
    });
    const reception = await backend.saveDeliveryChallan(
      {
        type: 'reception',
        date: '2026-05-04',
        location: 'Inbound Dock',
        vendor_id: activeVendor.id,
        source_reference: 'GRN-ACTIVE',
        items: [
          {
            item_id: seededOrder.item_id,
            variation_leaf_node_id: seededOrder.variation_leaf_node_id || 0,
            quantity_pcs: '8',
            weight: '',
          },
        ],
      },
      actor,
      { user: actor },
    );

    const delivery = await backend.saveDeliveryChallan(
      {
        order_id: seededOrder.id,
        date: '2026-05-04',
        location: 'Dispatch Bay',
        items: [
          {
            order_item_id: seededOrder.id,
            quantity_pcs: '3',
            weight: '',
          },
        ],
      },
      actor,
      { user: actor },
    );

    const receptionOnly = await backend.listDeliveryChallans({
      type: 'reception',
    });
    assert.ok(receptionOnly.some((challan) => challan.id === reception.id));
    assert.ok(receptionOnly.every((challan) => challan.type === 'reception'));

    const activeVendorOnly = await backend.listDeliveryChallans({
      type: 'reception',
      vendorId: activeVendor.id,
    });
    assert.deepEqual(activeVendorOnly.map((challan) => challan.id), [
      reception.id,
    ]);

    const deliveryOnly = await backend.listDeliveryChallans({
      type: 'delivery',
    });
    assert.ok(deliveryOnly.some((challan) => challan.id === delivery.id));
    assert.ok(deliveryOnly.every((challan) => challan.type === 'delivery'));
  } finally {
    await backend.closeDb();
  }
});
