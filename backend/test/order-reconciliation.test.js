const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// The statement belongs on the order: the order is the only thing that knows
// what was asked for and how much of it has been met, and a delivery challan is
// already raised acknowledging one.
//
// Assembling it needs no new columns — every link is already on a table. This
// seeds the whole chain by hand and walks it, which is the only way to know the
// traversal is right, because in a real workspace the middle of the chain is
// empty: stock has to be assigned to a run for an order to be able to say what
// went into it, and that has barely ever happened.
//
//   reception challan → inventory movement → material
//        → run_barcode_inputs → pipeline_run
//            ← order_pipeline_assignments ← order_item
//                → delivery_challan_items → delivery challan
//        → stage_reconciliations (scrap)

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

test('an order can account for what it consumed, made and shipped', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-order-recon-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'recon@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;
  const { run, get, all } = backend;

  try {
    const loginResponse = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'recon@paper.local',
        password: 'OwnerPass1234',
      }),
    });
    const { token } = await loginResponse.json();
    const authHeaders = { Authorization: `Bearer ${token}` };
    const now = new Date().toISOString();
    const ORDER_NO = 'RECON-1';

    // --- the order ---------------------------------------------------------
    const item = await get('SELECT * FROM items LIMIT 1');
    const unit = await get('SELECT * FROM units LIMIT 1');
    const client = await get('SELECT * FROM clients LIMIT 1');
    // An order is its header; the lines hang off it by order_no.
    await run(
      `INSERT INTO order_headers (order_no, client_id, created_at, updated_at)
       VALUES (?, ?, ?, ?)`,
      [ORDER_NO, client.id, now, now],
    );
    const orderInsert = await run(
      `INSERT INTO order_items
        (order_no, client_id, client_name, item_id, item_name, quantity,
         unit_id, unit_name, unit_symbol, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'open', ?, ?)`,
      [ORDER_NO, client.id, 'Acme Ltd', item.id, item.name, 100, unit.id,
        unit.name, unit.symbol, now, now],
    );
    const orderItemId = orderInsert.lastID;

    // --- material comes in on a reception challan --------------------------
    const receptionInsert = await run(
      `INSERT INTO delivery_challans
        (challan_no, date, customer_name, status, type, vendor_name,
         created_at, updated_at)
       VALUES (?, ?, '', 'issued', 'reception', 'Steel Supplier', ?, ?)`,
      ['RECON-REC-1', '2026-08-01', now, now],
    );
    const receptionId = receptionInsert.lastID;

    const BARCODE = 'RECON-SHEET-1';
    await run(
      `INSERT INTO materials (barcode, name, type, kind, unit_id, on_hand_qty,
                              material_class, created_at)
       VALUES (?, 'Recon Sheet', 'steel', 'parent', ?, 500, 'raw_material', ?)`,
      [BARCODE, unit.id, now],
    );
    await run(
      `INSERT INTO inventory_movements
        (material_barcode, movement_type, qty, primary_qty, uom,
         source_challan_id, source_challan_type, created_at)
       VALUES (?, 'in', 500, 500, 'kg', ?, 'reception', ?)`,
      [BARCODE, receptionId, now],
    );

    // --- a run, made for this order, that consumed that stock --------------
    const template = await get('SELECT * FROM pipeline_templates LIMIT 1');
    const RUN_ID = 'recon-run-1';
    await run(
      `INSERT INTO pipeline_runs (id, template_id, template_version, name,
                                  status, created_at)
       VALUES (?, ?, 1, 'Recon Run', 'completed', ?)`,
      [RUN_ID, template.id, now],
    );
    await run(
      `INSERT INTO order_pipeline_assignments
        (order_item_id, pipeline_run_id, allocated_quantity, created_at)
       VALUES (?, ?, 100, ?)`,
      [orderItemId, RUN_ID, now],
    );
    await run(
      `INSERT INTO run_barcode_inputs
        (id, run_id, node_id, barcode, material_id, material_payload_json)
       VALUES ('recon-input-1', ?, 'node-1', ?, '1', '{}')`,
      [RUN_ID, BARCODE],
    );
    await run(
      `INSERT INTO stage_reconciliations
        (run_id, node_id, allotted, output, leftover, scrap, updated_at)
       VALUES (?, 'node-1', 500, 430, 20, 50, ?)`,
      [RUN_ID, now],
    );

    // --- and what shipped against the order --------------------------------
    const deliveryInsert = await run(
      `INSERT INTO delivery_challans
        (challan_no, date, customer_name, status, type, order_id, order_no,
         created_at, updated_at)
       VALUES (?, ?, 'Acme Ltd', 'issued', 'delivery', ?, ?, ?, ?)`,
      ['RECON-DEL-1', '2026-08-10', orderItemId, ORDER_NO, now, now],
    );
    await run(
      `INSERT INTO delivery_challan_items
        (challan_id, order_item_id, item_id, line_no, particulars,
         quantity_pcs, weight, production_run_id, created_at, updated_at)
       VALUES (?, ?, ?, 1, 'Recon Part', 90, 430, ?, ?, ?)`,
      [deliveryInsert.lastID, orderItemId, item.id, RUN_ID, now, now],
    );

    // --- walk it -----------------------------------------------------------
    const response = await fetch(
      `${baseUrl}/api/orders/${ORDER_NO}/reconciliation`,
      { headers: authHeaders },
    );
    const body = await response.json();
    assert.equal(response.status, 200, JSON.stringify(body));
    const data = body.data;

    assert.equal(data.orderNo, ORDER_NO);
    assert.equal(data.clientName, 'Acme Ltd');
    assert.equal(data.lines.length, 1);
    assert.equal(data.lines[0].quantity, 100);

    // In: reached through consumption, not by the reception naming the order —
    // material arrives into stock, and only being consumed ties it to an order.
    assert.equal(data.receipts.length, 1, JSON.stringify(data.receipts));
    assert.equal(data.receipts[0].challanNo, 'RECON-REC-1');
    assert.equal(data.receipts[0].vendorName, 'Steel Supplier');
    assert.equal(data.receipts[0].quantity, 500);

    // Made: the run, and what it turned that material into.
    assert.equal(data.runs.length, 1);
    assert.equal(data.runs[0].runId, RUN_ID);
    assert.equal(data.totals.allotted, 500);
    assert.equal(data.totals.output, 430);
    assert.equal(data.totals.scrap, 50);
    assert.equal(data.totals.leftover, 20);

    // Out: the challan, its date, and the quantity on it.
    assert.equal(data.deliveries.length, 1);
    assert.equal(data.deliveries[0].challanNo, 'RECON-DEL-1');
    assert.equal(data.deliveries[0].date, '2026-08-10');
    assert.equal(data.deliveries[0].lines[0].quantityPcs, 90);
    assert.equal(data.deliveries[0].lines[0].productionRunId, RUN_ID);
    assert.equal(data.totals.deliveredPcs, 90);
    assert.equal(data.totals.receivedQty, 500);

    // The walk reached everything it should have.
    assert.equal(data.coverage.inboundTraceable, true);
    assert.deepEqual(data.coverage.untracedBarcodes, []);
    assert.equal(data.coverage.runsFound, 1);
    assert.equal(data.coverage.deliveriesLinked, 1);
  } finally {
    await closeServer(server);
  }
});

test('an order says what it could not trace rather than reporting zero', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-order-recon-gap-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'recon2@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;
  const { run, get } = backend;

  try {
    const loginResponse = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'recon2@paper.local',
        password: 'OwnerPass1234',
      }),
    });
    const { token } = await loginResponse.json();
    const authHeaders = { Authorization: `Bearer ${token}` };
    const now = new Date().toISOString();
    const ORDER_NO = 'RECON-2';

    const item = await get('SELECT * FROM items LIMIT 1');
    const unit = await get('SELECT * FROM units LIMIT 1');
    const client = await get('SELECT * FROM clients LIMIT 1');
    // An order is its header; the lines hang off it by order_no.
    await run(
      `INSERT INTO order_headers (order_no, client_id, created_at, updated_at)
       VALUES (?, ?, ?, ?)`,
      [ORDER_NO, client.id, now, now],
    );
    const orderInsert = await run(
      `INSERT INTO order_items
        (order_no, client_id, client_name, item_id, item_name, quantity,
         unit_id, unit_name, unit_symbol, status, created_at, updated_at)
       VALUES (?, ?, 'Beta Ltd', ?, ?, 40, ?, ?, ?, 'open', ?, ?)`,
      [ORDER_NO, client.id, item.id, item.name, unit.id, unit.name,
        unit.symbol, now, now],
    );
    const orderItemId = orderInsert.lastID;

    // A run that consumed stock which was never received on a challan — made
    // in inventory directly, which is exactly the shape of the seeded stock in
    // a real workspace.
    const template = await get('SELECT * FROM pipeline_templates LIMIT 1');
    const RUN_ID = 'recon-run-2';
    await run(
      `INSERT INTO pipeline_runs (id, template_id, template_version, name,
                                  status, created_at)
       VALUES (?, ?, 1, 'Orphan Run', 'completed', ?)`,
      [RUN_ID, template.id, now],
    );
    await run(
      `INSERT INTO order_pipeline_assignments
        (order_item_id, pipeline_run_id, allocated_quantity, created_at)
       VALUES (?, ?, 40, ?)`,
      [orderItemId, RUN_ID, now],
    );
    await run(
      `INSERT INTO run_barcode_inputs
        (id, run_id, node_id, barcode, material_id, material_payload_json)
       VALUES ('recon-input-2', ?, 'node-1', 'ORPHAN-STOCK-1', '1', '{}')`,
      [RUN_ID],
    );

    const response = await fetch(
      `${baseUrl}/api/orders/${ORDER_NO}/reconciliation`,
      { headers: authHeaders },
    );
    const body = await response.json();
    assert.equal(response.status, 200, JSON.stringify(body));
    const data = body.data;

    // Nothing came back on the inbound side — but the report distinguishes
    // "no material was received" from "we cannot say what was received", which
    // is the difference between a fact and a hole.
    assert.equal(data.receipts.length, 0);
    assert.equal(data.totals.receivedQty, 0);
    assert.deepEqual(data.coverage.untracedBarcodes, ['ORPHAN-STOCK-1']);
    assert.equal(
      data.coverage.consumedBarcodes,
      1,
      'stock was consumed, it just cannot be traced to a receipt',
    );
  } finally {
    await closeServer(server);
  }
});

test('an unknown order is a 404, not an empty statement', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-order-recon-404-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'recon3@paper.local';
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
        email: 'recon3@paper.local',
        password: 'OwnerPass1234',
      }),
    });
    const { token } = await loginResponse.json();
    const response = await fetch(
      `${baseUrl}/api/orders/NOPE-9999/reconciliation`,
      { headers: { Authorization: `Bearer ${token}` } },
    );
    assert.equal(response.status, 404);
  } finally {
    await closeServer(server);
  }
});
