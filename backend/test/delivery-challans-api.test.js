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
    assert.ok(
      challanItemColumns.some((column) => column.name === 'note'),
      'expected delivery challan line note column',
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
            note: 'Dispatch after QC clearance',
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
    const savedLine = await backend.get(
      'SELECT id, note FROM delivery_challan_items WHERE challan_id = ? LIMIT 1',
      [created.id],
    );
    assert.equal(savedLine.note, 'Dispatch after QC clearance');

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
      referenceType: 'manual-receipt',
      referenceId: 'SEED-RECEIVE-1',
      actor,
    });

    const preIssuePosition = await backend.get(
      `
      SELECT on_hand_qty
      FROM inventory_stock_positions
      WHERE material_barcode = ? AND location_id = ? AND lot_code = ?
      `,
      [material.barcode, 'Dispatch Bay', material.barcode],
    );
    assert.equal(Number(preIssuePosition?.on_hand_qty || 0), 50);

    const issued = await backend.issueDeliveryChallan(created.id, actor);
    assert.equal(issued.status, 'issued');

    const issuedMovement = await backend.get(
      `
      SELECT *
      FROM inventory_movements
      WHERE source_challan_id = ? AND source_challan_type = 'delivery'
      ORDER BY created_at ASC, id ASC
      LIMIT 1
      `,
      [created.id],
    );
    assert.ok(issuedMovement, 'expected delivery issue movement');
    assert.equal(issuedMovement.movement_type, 'issue');
    assert.equal(issuedMovement.reference_type, 'challan');
    assert.equal(issuedMovement.reference_id, String(created.id));
    assert.equal(Number(issuedMovement.primary_qty || 0), 10);
    assert.equal(String(issuedMovement.uom || ''), 'pcs');

    const issuedPosition = await backend.get(
      `
      SELECT on_hand_qty
      FROM inventory_stock_positions
      WHERE material_barcode = ? AND location_id = ? AND lot_code = ?
      `,
      [material.barcode, 'Dispatch Bay', material.barcode],
    );
    assert.equal(Number(issuedPosition?.on_hand_qty || 0), 40);

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

    const clientStatement = await backend.buildClientStatementReport({
      challanIds: [issued.challan_no],
    });
    assert.equal(clientStatement.summary.challanCount, 1);
    assert.equal(clientStatement.rows.length, 1);
    assert.equal(clientStatement.rows[0].challanNo, issued.challan_no);
    assert.ok(clientStatement.rows[0].itemName.includes(order.item_name));
    assert.equal(clientStatement.rows[0].note, 'Dispatch after QC clearance');
    assert.equal(clientStatement.rows[0].quantityPcs, 10);
    assert.equal(clientStatement.rows[0].weight, 2.5);

    await assert.rejects(
      () => backend.buildClientStatementReport({ challanIds: [] }),
      /At least one challan number is required/,
    );
    await assert.rejects(
      () => backend.buildClientStatementReport({ challanIds: ['DC-MISSING'] }),
      /Unknown challan number/,
    );

    const cancelled = await backend.cancelDeliveryChallan(created.id, actor);
    assert.equal(cancelled.status, 'cancelled');

    const reversedPosition = await backend.get(
      `
      SELECT on_hand_qty
      FROM inventory_stock_positions
      WHERE material_barcode = ? AND location_id = ? AND lot_code = ?
      `,
      [material.barcode, 'Dispatch Bay', material.barcode],
    );
    assert.equal(Number(reversedPosition?.on_hand_qty || 0), 50);

    const deliveryMovementCount = await backend.get(
      `
      SELECT COUNT(*) AS count
      FROM inventory_movements
      WHERE source_challan_id = ? AND source_challan_type = 'delivery'
      `,
      [created.id],
    );
    assert.equal(Number(deliveryMovementCount?.count || 0), 2);

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

    await backend.createInvoice({
      clientId: order.client_id,
      clientName: order.client_name,
      gstin: '',
      invoiceDate: '2026-05-05',
      lines: [
        {
          orderId: order.id,
          challanId: created.id,
          challanItemId: savedLine.id,
          itemId: order.item_id,
          variationLeafNodeId: order.variation_leaf_node_id || 0,
          itemName: order.item_name,
          hsnCode: '',
          quantity: 10,
          unitPrice: 12,
          cgstRate: 9,
          sgstRate: 9,
        },
      ],
    });
    await backend.buildReconciliationReport();
    await backend.resetAndSeedDemoData();
    const invoiceRowsAfterReset = await backend.get(
      'SELECT COUNT(*) AS count FROM invoice_lines',
    );
    const wasteRowsAfterReset = await backend.get(
      'SELECT COUNT(*) AS count FROM reconciliation_waste_audit',
    );
    assert.equal(Number(invoiceRowsAfterReset.count || 0), 0);
    assert.equal(Number(wasteRowsAfterReset.count || 0), 0);
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

    const materialBeforeIssue = await backend.ensureMaterialForItemSelection({
      itemId: seededOrder.item_id,
      variationLeafNodeId: seededOrder.variation_leaf_node_id || 0,
      actor,
    });
    assert.equal(Number(materialBeforeIssue.on_hand_qty || 0), 0);
    assert.equal(Number(materialBeforeIssue.available_to_promise_qty || 0), 0);
    assert.equal(Number(materialBeforeIssue.reserved_qty || 0), 0);

    const preIssuePositionCount = await backend.get(
      `
      SELECT COUNT(*) AS count
      FROM inventory_stock_positions
      WHERE material_barcode = ?
      `,
      [materialBeforeIssue.barcode],
    );
    assert.equal(Number(preIssuePositionCount?.count || 0), 0);

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
    assert.equal(movement.reference_id, String(created.id));
    assert.equal(Number(movement.primary_qty || 0), 25);
    assert.equal(String(movement.uom || ''), 'pcs');

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

    await assert.rejects(
      () =>
        backend.applyInventoryMovement({
          barcode: material.barcode,
          movementType: 'receive',
          qty: 5,
          toLocationId: location,
          actor,
        }),
      /Receive movements require challan provenance or a manual reference/,
    );
  } finally {
    await backend.closeDb();
  }
});

test('document-only challans issue without inventory movements', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-typewriter-challans-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  try {
    await backend.resetAndSeedDemoData();
    const actor = { id: 1, name: 'Typewriter Tester', role: 'admin' };

    const created = await backend.saveDeliveryChallan(
      {
        type: 'delivery',
        maintain_stocks: false,
        customer_name: 'Walk-in Customer',
        customer_gstin: '27TYPE1234F1Z5',
        date: '2026-05-04',
        location: 'Front Desk',
        items: [
          {
            particulars: 'Unlisted printed stationery line',
            hsn_code: '4901',
            quantity_pcs: '12',
            weight: '',
          },
        ],
      },
      actor,
      { user: actor },
    );

    assert.equal(Number(created.maintain_stocks), 0);
    assert.equal(created.customer_name, 'Walk-in Customer');
    assert.equal(created.order_id, null);

    const savedLine = await backend.get(
      `
      SELECT order_item_id, item_id, variation_leaf_node_id, particulars
      FROM delivery_challan_items
      WHERE challan_id = ?
      LIMIT 1
      `,
      [created.id],
    );
    assert.equal(savedLine.order_item_id, null);
    assert.equal(savedLine.item_id, null);
    assert.equal(Number(savedLine.variation_leaf_node_id || 0), 0);
    assert.equal(savedLine.particulars, 'Unlisted printed stationery line');

    const issued = await backend.issueDeliveryChallan(created.id, actor);
    assert.equal(issued.status, 'issued');

    const movementCount = await backend.get(
      'SELECT COUNT(*) AS count FROM inventory_movements WHERE source_challan_id = ?',
      [created.id],
    );
    assert.equal(Number(movementCount.count || 0), 0);

    const cancelled = await backend.cancelDeliveryChallan(created.id, actor);
    assert.equal(cancelled.status, 'cancelled');

    const movementCountAfterCancel = await backend.get(
      'SELECT COUNT(*) AS count FROM inventory_movements WHERE source_challan_id = ?',
      [created.id],
    );
    assert.equal(Number(movementCountAfterCancel.count || 0), 0);

    await assert.rejects(
      () =>
        backend.saveDeliveryChallan(
          {
            type: 'delivery',
            maintain_stocks: false,
            date: '2026-05-04',
            location: 'Front Desk',
            items: [
              {
                particulars: '',
                quantity_pcs: '0',
                weight: '',
              },
            ],
          },
          actor,
          { user: actor },
        ).then((draft) => backend.issueDeliveryChallan(draft.id, actor)),
      /Enter item text and Qty \/ Pcs or Weight/,
    );
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

test('delivery challans allow unique manual numbers and reject duplicates', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-delivery-manual-no-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  try {
    await backend.resetAndSeedDemoData();
    const actor = { id: 1, name: 'Manual No Tester', role: 'admin' };
    const order = (await backend.getOrders())[0];

    const created = await backend.saveDeliveryChallan(
      {
        challan_no: '  DC-MANUAL-001  ',
        order_id: order.id,
        order_ids: [order.id],
        date: '2026-05-04',
        location: 'Dispatch Bay',
        items: [
          {
            order_item_id: order.id,
            quantity_pcs: '5',
            weight: '',
          },
        ],
      },
      actor,
      { user: actor },
    );
    assert.equal(created.challan_no, 'DC-MANUAL-001');

    await assert.rejects(
      () =>
        backend.saveDeliveryChallan(
          {
            challan_no: 'DC-MANUAL-001',
            order_id: order.id,
            order_ids: [order.id],
            date: '2026-05-05',
            location: 'Dispatch Bay',
            items: [
              {
                order_item_id: order.id,
                quantity_pcs: '2',
                weight: '',
              },
            ],
          },
          actor,
          { user: actor },
        ),
      /Challan number \[DC-MANUAL-001\] is already in use\./,
    );
  } finally {
    await backend.closeDb();
  }
});

test('delivery challans support multiple selected orders from the same client', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-delivery-multi-order-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  try {
    await backend.resetAndSeedDemoData();
    const actor = { id: 1, name: 'Multi Order Tester', role: 'admin' };
    const orders = await backend.getOrders();
    const byClient = new Map();
    for (const order of orders) {
      const clientId = Number(order.client_id || 0);
      const existing = byClient.get(clientId) || [];
      existing.push(order);
      byClient.set(clientId, existing);
    }
    const orderGroup = [...byClient.values()].find((group) => group.length >= 2);
    assert.ok(orderGroup, 'expected at least two seeded orders for the same client');
    const selectedOrders = orderGroup.slice(0, 2);

    const created = await backend.saveDeliveryChallan(
      {
        order_id: selectedOrders[0].id,
        order_ids: selectedOrders.map((order) => order.id),
        date: '2026-05-06',
        location: 'Dispatch Bay',
        items: selectedOrders.map((order, index) => ({
          order_item_id: order.id,
          item_id: order.item_id,
          variation_leaf_node_id: order.variation_leaf_node_id || 0,
          quantity_pcs: String(index + 1),
          weight: '',
        })),
      },
      actor,
      { user: actor },
    );

    assert.equal(created.customer_name, selectedOrders[0].client_name);

    const storedLinks = await backend.all(
      'SELECT order_id FROM delivery_challan_orders WHERE challan_id = ? ORDER BY order_id ASC',
      [created.id],
    );
    assert.deepEqual(
      storedLinks.map((row) => Number(row.order_id)),
      selectedOrders.map((order) => order.id).sort((a, b) => a - b),
    );
  } finally {
    await backend.closeDb();
  }
});

test('challan templates persist mappings and generate overprint pdf', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-challan-templates-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  try {
    await backend.resetAndSeedDemoData();
    const actor = { id: 1, name: 'Template Tester', role: 'admin' };
    const order = (await backend.getOrders())[0];
    assert.ok(order, 'expected seeded order for template test');

    const challan = await backend.saveDeliveryChallan(
      {
        order_id: order.id,
        order_ids: [order.id],
        date: '2026-05-07',
        location: 'Dispatch Bay',
        items: [
          {
            order_item_id: order.id,
            item_id: order.item_id,
            variation_leaf_node_id: order.variation_leaf_node_id || 0,
            quantity_pcs: '3',
            weight: '',
          },
        ],
      },
      actor,
      { user: actor },
    );

    const first = await backend.saveChallanTemplate({
      name: 'Old Client Layout',
      partyType: 'client',
      partyId: order.client_id,
      challanType: 'delivery',
      backgroundObjectKey: 'templates/old.png',
      canvasWidth: 1240,
      canvasHeight: 1754,
      mappings: [
        {
          fieldKey: 'challan_no',
          xPercent: 0.1,
          yPercent: 0.1,
          fontSize: 10,
        },
      ],
    });
    const second = await backend.saveChallanTemplate({
      name: 'Active Client Layout',
      partyType: 'client',
      partyId: order.client_id,
      challanType: 'delivery',
      backgroundObjectKey: 'templates/active.png',
      canvasWidth: 1240,
      canvasHeight: 1754,
      stockSize: 'A5',
      paperSize: 'A4',
      nUpLayout: 2,
      mappings: [
        {
          fieldKey: 'challan_no',
          xPercent: 0.1,
          yPercent: 0.1,
          fontSize: 10,
          widthMm: 55,
          heightMm: 16,
        },
        {
          fieldType: 'STATIC',
          fieldKey: 'static_authorized_signatory',
          fieldValue: 'Authorized Signatory',
          xPercent: 0.72,
          yPercent: 0.88,
          fontSize: 10,
          alignment: 'center',
          textColor: 'blue',
          maxWidthMm: 52,
          widthMm: 52,
          heightMm: 16,
        },
        {
          fieldType: 'TABLE',
          fieldKey: 'item_particulars',
          fieldValue: JSON.stringify({
            columns: [
              { fieldKey: 'item_particulars', xMm: 0 },
              { fieldKey: 'hsn', xMm: 72 },
              { fieldKey: 'qty_pcs', xMm: 102 },
              { fieldKey: 'weight', xMm: 124 },
              { fieldKey: 'note', xMm: 0 },
            ],
            printNotes: true,
          }),
          xMm: 12,
          yMm: 84,
          xPercent: 0.08,
          yPercent: 0.4,
          fontSize: 9,
          widthMm: 120,
          heightMm: 60,
          minFontSize: 6,
          minRows: 2,
          maxRows: 1,
          tableHeightMm: 60,
          rowHeightMm: 7,
        },
      ],
    });

    const templates = await backend.listChallanTemplates({
      partyType: 'client',
      partyId: order.client_id,
      challanType: 'delivery',
    });
    const oldTemplate = templates.find((template) => template.id === first.id);
    const activeTemplate = templates.find((template) => template.id === second.id);
    assert.equal(oldTemplate.isActive, false);
    assert.equal(activeTemplate.isActive, true);
    assert.equal(activeTemplate.stockSize, 'A5');
    assert.equal(activeTemplate.paperSize, 'A4');
    assert.equal(activeTemplate.nUpLayout, 2);
    assert.equal(activeTemplate.mappings.length, 3);
    const staticMapping = activeTemplate.mappings.find(
      (mapping) => mapping.fieldKey === 'static_authorized_signatory',
    );
    assert.equal(staticMapping.fieldType, 'STATIC');
    assert.equal(staticMapping.fieldValue, 'Authorized Signatory');
    assert.equal(staticMapping.textColor, 'blue');
    assert.equal(staticMapping.maxWidthMm, 52);
    assert.equal(staticMapping.widthMm, 52);
    assert.equal(
      activeTemplate.mappings.find((mapping) => mapping.fieldKey === 'item_particulars').maxRows,
      1,
    );
    assert.equal(
      activeTemplate.mappings.find((mapping) => mapping.fieldKey === 'item_particulars').minRows,
      2,
    );
    const tableMapping = activeTemplate.mappings.find(
      (mapping) => mapping.fieldKey === 'item_particulars',
    );
    assert.equal(tableMapping.fieldType, 'TABLE');
    assert.deepEqual(
      JSON.parse(tableMapping.fieldValue).columns.map((column) => column.fieldKey),
      ['item_particulars', 'hsn', 'qty_pcs', 'weight', 'note'],
    );
    assert.equal(tableMapping.xMm, 12);
    assert.equal(tableMapping.yMm, 84);

    const templateRow = await backend.get(
      'SELECT * FROM challan_templates WHERE id = ?',
      [second.id],
    );
    const pdf = await backend.generateChallanTemplatePdf({
      challanRow: challan,
      templateRow,
      mode: 'overprint',
    });
    assert.ok(Buffer.isBuffer(pdf));
    assert.equal(pdf.slice(0, 4).toString(), '%PDF');

    const testPrint = await backend.generateChallanTemplatePdf({
      challanRow: null,
      challanDtoOverride: {
        ...backend.buildTemplateTestChallanDto(1),
      },
      templateRow,
      mode: 'digital',
    });
    assert.ok(Buffer.isBuffer(testPrint));
    assert.equal(testPrint.slice(0, 4).toString(), '%PDF');

    const maxPrint = await backend.generateChallanTemplatePdf({
      challanRow: null,
      challanDtoOverride: {
        ...backend.buildTemplateTestChallanDto(8),
      },
      templateRow,
      mode: 'digital',
    });
    assert.ok(Buffer.isBuffer(maxPrint));
    assert.equal(maxPrint.slice(0, 4).toString(), '%PDF');
    const fullTableMappings = activeTemplate.mappings.map((mapping) =>
      mapping.fieldKey === 'item_particulars'
        ? {
            ...mapping,
            fieldType: 'TABLE',
            fieldValue: JSON.stringify({
              columns: [
                { fieldKey: 'item_particulars', xMm: 0 },
                { fieldKey: 'hsn', xMm: 72 },
                { fieldKey: 'qty_pcs', xMm: 102 },
                { fieldKey: 'weight', xMm: 124 },
                { fieldKey: 'note', xMm: 0 },
              ],
              printNotes: true,
            }),
          }
        : mapping,
    );
    const overridePrint = await backend.generateChallanTemplatePdf({
      challanRow: null,
      challanDtoOverride: {
        ...backend.buildTemplateTestChallanDto(8),
      },
      templateSnapshot: {
        ...activeTemplate,
        mappings: fullTableMappings,
      },
      mode: 'digital',
    });
    assert.ok(Buffer.isBuffer(overridePrint));
    assert.equal(overridePrint.slice(0, 4).toString(), '%PDF');
    assert.equal(backend.buildTemplateTestChallanDto(1).items.length, 1);
    assert.equal(backend.buildTemplateTestChallanDto(8).items.length, 8);
  } finally {
    await backend.closeDb();
  }
});

test('challan templates reject stock and sheet combinations that do not fit', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-challan-template-invalid-layout-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  try {
    await backend.resetAndSeedDemoData();
    const order = (await backend.getOrders())[0];
    await assert.rejects(
      () =>
        backend.saveChallanTemplate({
          name: 'Invalid Layout',
          partyType: 'client',
          partyId: order.client_id,
          challanType: 'delivery',
          backgroundObjectKey: 'templates/invalid.png',
          canvasWidth: 1240,
          canvasHeight: 1754,
          stockSize: 'A3',
          paperSize: 'A4',
          nUpLayout: 2,
          mappings: [
            {
              fieldKey: 'challan_no',
              xPercent: 0.1,
              yPercent: 0.1,
              fontSize: 10,
            },
          ],
        }),
      /does not fit on A4 with 2-up layout/i,
    );
  } finally {
    await backend.closeDb();
  }
});

test('challan templates default stock size to paper size for older payloads', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-challan-template-stock-fallback-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  try {
    await backend.resetAndSeedDemoData();
    const order = (await backend.getOrders())[0];
    const template = await backend.saveChallanTemplate({
      name: 'Fallback Layout',
      partyType: 'client',
      partyId: order.client_id,
      challanType: 'delivery',
      backgroundObjectKey: 'templates/fallback.png',
      canvasWidth: 1240,
      canvasHeight: 1754,
      paperSize: 'A4',
      nUpLayout: 1,
      mappings: [
        {
          fieldKey: 'challan_no',
          xPercent: 0.1,
          yPercent: 0.1,
          fontSize: 10,
        },
      ],
    });

    assert.equal(template.paperSize, 'A4');
    assert.equal(template.stockSize, 'A4');
    assert.equal(template.nUpLayout, 1);

    const templateRow = await backend.get(
      'SELECT * FROM challan_templates WHERE id = ?',
      [template.id],
    );
    assert.equal(templateRow.paper_size, 'A4');
    assert.equal(templateRow.stock_size, 'A4');
  } finally {
    await backend.closeDb();
  }
});

test('challan templates render A4 stock on A3 sheet at 2-up', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-challan-template-a4-on-a3-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  try {
    await backend.resetAndSeedDemoData();
    const order = (await backend.getOrders())[0];
    const template = await backend.saveChallanTemplate({
      name: 'A4 on A3 Layout',
      partyType: 'client',
      partyId: order.client_id,
      challanType: 'delivery',
      backgroundObjectKey: 'templates/a4-on-a3.png',
      canvasWidth: 1240,
      canvasHeight: 1754,
      stockSize: 'A4',
      paperSize: 'A3',
      nUpLayout: 2,
      mappings: [
        {
          fieldKey: 'challan_no',
          xPercent: 0.1,
          yPercent: 0.1,
          fontSize: 10,
        },
        {
          fieldType: 'TABLE',
          fieldKey: 'item_particulars',
          fieldValue: JSON.stringify({
            columns: [
              { fieldKey: 'item_particulars', xMm: 0 },
              { fieldKey: 'hsn', xMm: 72 },
              { fieldKey: 'qty_pcs', xMm: 102 },
              { fieldKey: 'weight', xMm: 124 },
            ],
          }),
          xMm: 16,
          yMm: 118,
          xPercent: 0.08,
          yPercent: 0.4,
          fontSize: 9,
          widthMm: 120,
          heightMm: 60,
          tableHeightMm: 60,
          rowHeightMm: 7,
        },
      ],
    });

    assert.equal(template.stockSize, 'A4');
    assert.equal(template.paperSize, 'A3');
    assert.equal(template.nUpLayout, 2);

    const templateRow = await backend.get(
      'SELECT * FROM challan_templates WHERE id = ?',
      [template.id],
    );
    const pdf = await backend.generateChallanTemplatePdf({
      challanRow: null,
      challanDtoOverride: backend.buildTemplateTestChallanDto(),
      templateRow,
      mode: 'digital',
    });
    assert.ok(Buffer.isBuffer(pdf));
    assert.equal(pdf.slice(0, 4).toString(), '%PDF');
  } finally {
    await backend.closeDb();
  }
});

test('issued challans freeze template snapshots and image mappings persist', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-challan-template-snapshot-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  try {
    await backend.resetAndSeedDemoData();
    const actor = { id: 1, name: 'Snapshot Tester', role: 'admin' };
    const order = (await backend.getOrders())[0];
    assert.ok(order, 'expected seeded order for snapshot test');

    const template = await backend.saveChallanTemplate({
      name: 'Snapshot Layout',
      partyType: 'client',
      partyId: order.client_id,
      challanType: 'delivery',
      backgroundObjectKey: 'templates/snapshot.png',
      canvasWidth: 1240,
      canvasHeight: 1754,
      stockSize: 'A4',
      paperSize: 'A3',
      nUpLayout: 2,
      mappings: [
        {
          fieldType: 'DYNAMIC',
          fieldKey: 'challan_no',
          xPercent: 0.12,
          yPercent: 0.08,
          fontSize: 10,
        },
        {
          fieldType: 'IMAGE',
          fieldKey: 'static_stamp_signature',
          assetObjectKey: 'templates/stamps/signature.png',
          assetWidthPx: 400,
          assetHeightPx: 120,
          imageWidthMm: 30,
          imageHeightMm: 9,
          lockAspectRatio: true,
          xPercent: 0.74,
          yPercent: 0.84,
        },
      ],
    });
    assert.equal(template.mappings.length, 2);
    const imageMapping = template.mappings.find((mapping) => mapping.fieldType === 'IMAGE');
    assert.ok(imageMapping, 'expected image mapping to persist');
    assert.equal(imageMapping.assetObjectKey, 'templates/stamps/signature.png');
    assert.equal(imageMapping.lockAspectRatio, true);

    const challan = await backend.saveDeliveryChallan(
      {
        order_id: order.id,
        order_ids: [order.id],
        date: '2026-05-07',
        location: 'Dispatch Bay',
        items: [
          {
            order_item_id: order.id,
            item_id: order.item_id,
            variation_leaf_node_id: order.variation_leaf_node_id || 0,
            quantity_pcs: '3',
            weight: '',
          },
        ],
      },
      actor,
      { user: actor },
    );

    const material = await backend.ensureMaterialForItemSelection({
      itemId: order.item_id,
      variationLeafNodeId: order.variation_leaf_node_id || 0,
      actor,
    });
    await backend.applyInventoryMovement({
      barcode: material.barcode,
      movementType: 'receive',
      qty: 10,
      toLocationId: 'Dispatch Bay',
      referenceType: 'manual-receipt',
      referenceId: 'SNAPSHOT-SEED-1',
      actor,
    });

    await backend.issueDeliveryChallan(challan.id, actor);
    const issuedRow = await backend.get(
      'SELECT template_snapshot_json FROM delivery_challans WHERE id = ?',
      [challan.id],
    );
    const snapshot = JSON.parse(issuedRow.template_snapshot_json);
    assert.equal(snapshot.name, 'Snapshot Layout');
    assert.equal(snapshot.stockSize, 'A4');
    assert.equal(snapshot.paperSize, 'A3');
    assert.equal(snapshot.nUpLayout, 2);
    assert.equal(snapshot.mappings.length, 2);
    assert.equal(snapshot.mappings[0].xPercent, 0.12);
    assert.equal(snapshot.mappings[1].fieldType, 'IMAGE');
    assert.equal(snapshot.mappings[1].assetObjectKey, 'templates/stamps/signature.png');

    await backend.saveChallanTemplate({
      id: template.id,
      name: 'Snapshot Layout v2',
      partyType: 'client',
      partyId: order.client_id,
      challanType: 'delivery',
      backgroundObjectKey: 'templates/snapshot.png',
      canvasWidth: 1240,
      canvasHeight: 1754,
      mappings: [
        {
          fieldType: 'DYNAMIC',
          fieldKey: 'challan_no',
          xPercent: 0.42,
          yPercent: 0.18,
          fontSize: 10,
        },
      ],
    }, template.id);

    const unchangedSnapshotRow = await backend.get(
      'SELECT template_snapshot_json FROM delivery_challans WHERE id = ?',
      [challan.id],
    );
    const unchangedSnapshot = JSON.parse(unchangedSnapshotRow.template_snapshot_json);
    assert.equal(unchangedSnapshot.mappings.length, 2);
    assert.equal(unchangedSnapshot.mappings[0].xPercent, 0.12);
  } finally {
    await backend.closeDb();
  }
});

test('delivery challans accept completed production runs and cancellations keep reversal provenance', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-production-run-handoff-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  try {
    await backend.resetAndSeedDemoData();
    const actor = { id: 1, name: 'Production Tester', role: 'admin' };
    const runs = await backend.listCompletedProductionRuns({ search: 'RUN-', limit: 20 });
    assert.ok(runs.length > 0, 'expected seeded completed production runs');
    const run = runs[0];
    const orders = await backend.getOrders();
    const matchingOrder = orders.find(
      (order) =>
        Number(order.item_id || 0) === run.itemId &&
        Number(order.variation_leaf_node_id || 0) === run.variationLeafNodeId,
    );
    assert.ok(matchingOrder, 'expected matching seeded order for completed run');

    const material = await backend.ensureMaterialForItemSelection({
      itemId: run.itemId,
      variationLeafNodeId: run.variationLeafNodeId,
      actor,
    });
    await backend.applyInventoryMovement({
      barcode: material.barcode,
      movementType: 'receive',
      qty: 25,
      toLocationId: 'Dispatch Bay',
      referenceType: 'manual-receipt',
      referenceId: 'PRODUCTION-SEED-1',
      actor,
    });

    const challan = await backend.saveDeliveryChallan(
      {
        order_id: matchingOrder.id,
        order_ids: [matchingOrder.id],
        date: '2026-05-08',
        location: 'Dispatch Bay',
        items: [
          {
            production_run_id: run.id,
            item_id: run.itemId,
            variation_leaf_node_id: run.variationLeafNodeId,
            quantity_pcs: '4',
            weight: '',
          },
        ],
      },
      actor,
      { user: actor },
    );

    const savedLine = await backend.get(
      'SELECT production_run_id FROM delivery_challan_items WHERE challan_id = ? LIMIT 1',
      [challan.id],
    );
    assert.equal(Number(savedLine.production_run_id || 0), run.id);

    await backend.issueDeliveryChallan(challan.id, actor);
    const originalMovement = await backend.get(
      `
      SELECT *
      FROM inventory_movements
      WHERE source_challan_id = ? AND source_challan_type = 'delivery' AND reference_type = 'challan'
      ORDER BY created_at ASC, id ASC
      LIMIT 1
      `,
      [challan.id],
    );
    assert.ok(originalMovement, 'expected issue movement for production-run-backed challan');

    await backend.cancelDeliveryChallan(challan.id, actor);
    const reversalMovement = await backend.get(
      `
      SELECT *
      FROM inventory_movements
      WHERE source_challan_id = ? AND source_challan_type = 'delivery' AND reference_type = 'challan-cancellation'
      ORDER BY created_at DESC, id DESC
      LIMIT 1
      `,
      [challan.id],
    );
    assert.ok(reversalMovement, 'expected cancellation movement');
    assert.equal(reversalMovement.reason_code, 'challan_cancel_reversal');
    assert.equal(String(reversalMovement.reverses_movement_id || ''), String(originalMovement.id));
  } finally {
    await backend.closeDb();
  }
});

test('delivery challans reject mixed-client multi-order selections', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-delivery-mixed-client-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  try {
    await backend.resetAndSeedDemoData();
    const actor = { id: 1, name: 'Mixed Client Tester', role: 'admin' };
    const orders = await backend.getOrders();
    const first = orders[0];
    const second = orders.find(
      (order) => Number(order.client_id || 0) !== Number(first.client_id || 0),
    );
    assert.ok(second, 'expected seeded orders from a different client');

    await assert.rejects(
      () =>
        backend.saveDeliveryChallan(
          {
            order_id: first.id,
            order_ids: [first.id, second.id],
            date: '2026-05-06',
            location: 'Dispatch Bay',
            items: [
              {
                order_item_id: first.id,
                item_id: first.item_id,
                variation_leaf_node_id: first.variation_leaf_node_id || 0,
                quantity_pcs: '1',
                weight: '',
              },
            ],
          },
          actor,
          { user: actor },
        ),
      /Delivery challans can only include orders from the same client\./,
    );
  } finally {
    await backend.closeDb();
  }
});

test('reconciliation report persists invoice tax, conversion, client material, and waste audit', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-reconciliation-report-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  try {
    await backend.resetAndSeedDemoData();
    const actor = { id: 1, name: 'Report Tester', role: 'admin' };
    const order = (await backend.getOrders())[0];
    assert.ok(order, 'expected seeded order');
    const vendor = await backend.saveVendor({
      name: 'Client Material Gate',
      gstNumber: '27CLIENTMAT1Z5',
      phone: '9999999999',
    });

    await backend.saveConversionOverride({
      itemId: order.item_id,
      variationLeafNodeId: order.variation_leaf_node_id || 0,
      conversionRatio: 2.5,
      toUnitLabel: 'sheets',
    });
    const overrides = await backend.listConversionOverrides();
    assert.equal(overrides[0].conversionRatio, 2.5);

    const reception = await backend.saveDeliveryChallan(
      {
        type: 'reception',
        vendor_id: vendor.id,
        date: '2026-05-10',
        location: 'Report Dock',
        material_owner_client_id: order.client_id,
        material_owner_client_name: order.client_name,
        material_owner_gstin: '27REPORTCLIENT1Z5',
        items: [
          {
            item_id: order.item_id,
            variation_leaf_node_id: order.variation_leaf_node_id || 0,
            quantity_pcs: '',
            weight: '100',
          },
        ],
      },
      actor,
      { user: actor },
    );
    await backend.issueDeliveryChallan(reception.id, actor);

    const delivery = await backend.saveDeliveryChallan(
      {
        type: 'delivery',
        order_ids: [order.id],
        date: '2026-05-11',
        location: 'Report Dock',
        items: [
          {
            order_item_id: order.id,
            quantity_pcs: '50',
            weight: '20',
          },
        ],
      },
      actor,
      { user: actor },
    );
    await backend.issueDeliveryChallan(delivery.id, actor);
    const deliveryLine = await backend.get(
      'SELECT * FROM delivery_challan_items WHERE challan_id = ? LIMIT 1',
      [delivery.id],
    );

    const invoice = await backend.createInvoice({
      clientId: order.client_id,
      clientName: order.client_name,
      gstin: '27REPORTCLIENT1Z5',
      lines: [
        {
          orderId: order.id,
          challanId: delivery.id,
          challanItemId: deliveryLine.id,
          itemId: order.item_id,
          variationLeafNodeId: order.variation_leaf_node_id || 0,
          itemName: order.item_name,
          hsnCode: '4805',
          quantity: 45,
          unitPrice: 10,
          cgstRate: 9,
          sgstRate: 9,
        },
      ],
    });
    assert.equal(invoice.totalQuantity, 45);
    assert.equal(invoice.cgstAmount, 40.5);
    assert.equal(invoice.sgstAmount, 40.5);

    const report = await backend.buildReconciliationReport();
    assert.equal(report.internalAuditor.length, 1);
    const auditorRow = report.internalAuditor[0];
    assert.equal(auditorRow.dcNumber, delivery.challan_no);
    assert.equal(auditorRow.totalDispatchedWeightKg, 20);
    assert.equal(auditorRow.convertedUnits, 50);
    assert.equal(auditorRow.invoicedQuantity, 45);
    assert.equal(auditorRow.status, 'Attention Required');
    assert.equal(auditorRow.cgst, 40.5);
    assert.equal(auditorRow.sgst, 40.5);
    assert.equal(report.clientStatement.length, 1);
    assert.equal(report.clientStatement[0].materialReceivedInputKg, 100);
    assert.equal(report.clientStatement[0].totalFinishedUnitsDelivered, 50);
    assert.equal(report.clientStatement[0].netBalanceMaterialRemainingKg, 80);
    const wasteRows = await backend.listWasteAuditRows();
    assert.equal(wasteRows.length, 1);
    assert.equal(wasteRows[0].wasteWeightKg, 80);
  } finally {
    await backend.closeDb();
  }
});
