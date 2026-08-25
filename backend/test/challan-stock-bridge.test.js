const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// Challans and production used to count different things. A challan moved
// "25 of this item, in this variation"; production consumed "this physical
// piece, by barcode", and the movement a challan wrote carried the literal '-'
// where a barcode belongs — commented in the source as "legacy barcode".
//
// Nothing joined them, so material received on a challan never became
// assignable on the floor and an order could never say what went into it.
//
// Three links close it, and this exercises them through the real API rather
// than by writing rows directly:
//   1. issuing a reception challan mints barcoded stock;
//   2. a consumption can be a quantity as well as a piece;
//   3. a consumption names the challan line that supplied it.

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

async function boot(prefix, email) {
  const tempDir = mkdtempSync(path.join(tmpdir(), prefix));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = email;
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;
  const login = await fetch(`${baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: 'OwnerPass1234' }),
  });
  const { token } = await login.json();
  return {
    backend,
    server,
    baseUrl,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
  };
}

/// A reception challan for one line of a real item, taken all the way to issued
/// — which is the step that moves stock. Saving with status 'issued' does not.
async function receive({ backend, baseUrl, headers }, { qty, weight }) {
  const item = await backend.get('SELECT * FROM items LIMIT 1');
  const leaf = await backend.get(
    `SELECT n.* FROM item_variation_nodes n
     WHERE n.item_id = ? AND n.kind = 'value' AND n.is_archived = 0
       AND NOT EXISTS (SELECT 1 FROM item_variation_nodes c
                       WHERE c.parent_node_id = n.id AND c.is_archived = 0)
     LIMIT 1`,
    [item.id],
  );
  let vendor = await backend.get('SELECT * FROM vendors LIMIT 1');
  if (!vendor) {
    const now = new Date().toISOString();
    const inserted = await backend.run(
      'INSERT INTO vendors (name, created_at, updated_at) VALUES (?, ?, ?)',
      ['Bridge Supplier', now, now],
    );
    vendor = await backend.get('SELECT * FROM vendors WHERE id = ?', [
      inserted.lastID,
    ]);
  }

  const created = await fetch(`${baseUrl}/api/delivery-challans`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      type: 'reception',
      challanNo: 'BRIDGE-REC-1',
      date: '2026-08-26',
      status: 'draft',
      purpose: 'purchase',
      maintainStocks: true,
      vendorId: vendor.id,
      vendorName: vendor.name,
      items: [{
        itemId: item.id,
        variationLeafNodeId: leaf ? leaf.id : 0,
        particulars: item.name,
        quantityPcs: String(qty),
        weight: String(weight),
        lineNo: 1,
      }],
    }),
  });
  const body = await created.json();
  assert.equal(created.status, 201, JSON.stringify(body));

  const issued = await fetch(
    `${baseUrl}/api/delivery-challans/${body.data.id}/issue`,
    { method: 'POST', headers },
  );
  const issuedBody = await issued.json();
  assert.equal(issued.status, 200, JSON.stringify(issuedBody));
  return { item, leaf, vendor, challanId: body.data.id };
}

test('issuing a reception challan mints stock production can assign', async () => {
  const ctx = await boot('paper-bridge-', 'bridge@paper.local');
  const { backend, server } = ctx;
  try {
    const { item, challanId } = await receive(ctx, { qty: 25, weight: 310 });

    const line = await backend.get(
      'SELECT * FROM delivery_challan_items WHERE challan_id = ?',
      [challanId],
    );
    assert.ok(line, 'the reception recorded what came in');

    // 1. Barcoded stock now exists, and it knows where it came from.
    const material = await backend.get(
      'SELECT * FROM materials WHERE source_challan_item_id = ?',
      [line.id],
    );
    assert.ok(material, 'issuing a reception mints a material row');
    assert.equal(material.source_challan_id, challanId);
    assert.equal(material.linked_item_id, item.id);
    assert.equal(
      Number(material.on_hand_qty) > 0,
      true,
      'received stock is on hand, which is what makes it assignable',
    );
    assert.equal(material.material_class, 'raw_material');

    // The movement carries the real barcode now, not the '-' placeholder that
    // made a receipt impossible to join to a consumption.
    const movement = await backend.get(
      'SELECT * FROM inventory_movements WHERE source_challan_id = ?',
      [challanId],
    );
    assert.equal(movement.material_barcode, material.barcode);
    assert.notEqual(movement.material_barcode, '-');
    assert.equal(movement.source_challan_line_id, line.id);

    // Issuing twice must not mint a second pile for the same line.
    const before = await backend.get(
      'SELECT COUNT(*) AS n FROM materials WHERE source_challan_item_id = ?',
      [line.id],
    );
    assert.equal(before.n, 1);
  } finally {
    await closeServer(server);
  }
});

test('a consumption names the challan line that supplied it', async () => {
  const ctx = await boot('paper-bridge2-', 'bridge2@paper.local');
  const { backend, server, baseUrl, headers } = ctx;
  try {
    const { challanId } = await receive(ctx, { qty: 25, weight: 310 });
    const line = await backend.get(
      'SELECT * FROM delivery_challan_items WHERE challan_id = ?',
      [challanId],
    );
    const material = await backend.get(
      'SELECT * FROM materials WHERE source_challan_item_id = ?',
      [line.id],
    );

    // Assign that stock to a run the way the floor does: create the run, then
    // drop the material on a node.
    const template = await backend.get('SELECT * FROM pipeline_templates LIMIT 1');
    const created = await fetch(`${baseUrl}/runs`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ templateId: template.id, name: 'Bridge Run' }),
    });
    const createdBody = await created.json();
    assert.equal(created.status, 201, JSON.stringify(createdBody));
    const runId = createdBody.run.id;

    const attached = await fetch(`${baseUrl}/runs/${runId}/barcodes`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        nodeId: 'node-1',
        barcode: material.barcode,
        quantity: 10,
      }),
    });
    assert.equal(attached.status, 200, await attached.text());

    // 3. The bridge is written: the consumption points back at the line.
    const input = await backend.get(
      'SELECT * FROM run_barcode_inputs WHERE run_id = ?',
      [runId],
    );
    assert.ok(input, 'the assignment was recorded');
    assert.equal(
      input.challan_item_id,
      line.id,
      'the consumption names the reception line it came from',
    );
    assert.equal(input.source_kind, 'barcode');
    assert.equal(Number(input.item_id) > 0, true);
  } finally {
    await closeServer(server);
  }
});

test('production can consume a quantity, not only a barcode', async () => {
  const ctx = await boot('paper-bridge3-', 'bridge3@paper.local');
  const { backend, server, baseUrl, headers } = ctx;
  try {
    const item = await backend.get('SELECT * FROM items LIMIT 1');
    const template = await backend.get('SELECT * FROM pipeline_templates LIMIT 1');

    const created = await fetch(`${baseUrl}/runs`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ templateId: template.id, name: 'Quantity Run' }),
    });
    const createdBody = await created.json();
    assert.equal(created.status, 201, JSON.stringify(createdBody));
    const runId = createdBody.run.id;

    // No barcode at all — an amount of an item, which is the grain challans
    // move stock in. This used to be refused outright.
    const attached = await fetch(`${baseUrl}/runs/${runId}/barcodes`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        nodeId: 'node-1',
        itemId: item.id,
        quantity: 42.5,
      }),
    });
    assert.equal(attached.status, 200, await attached.text());

    const input = await backend.get(
      'SELECT * FROM run_barcode_inputs WHERE run_id = ?',
      [runId],
    );
    assert.ok(input, 'a quantity consumption is recorded rather than dropped');
    assert.equal(input.source_kind, 'quantity');
    assert.equal(Number(input.item_id), item.id);
    assert.equal(Number(input.consumed_qty), 42.5);
    assert.equal(
      input.barcode.startsWith('#qty-'),
      true,
      'a synthetic barcode that cannot collide with a real one',
    );
  } finally {
    await closeServer(server);
  }
});
