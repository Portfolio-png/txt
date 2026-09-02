const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

const barcodes = require('../kernel/barcodes');

// One code space over every entity, so a scanner gun resolves whatever it is
// pointed at without knowing in advance what that is.
//
// The case that motivated it: a probe asked the old lookup for `CHD-3533-01` —
// a barcode sitting in `materials` — and got *404, "Barcode not found in
// database."*, the identical answer it gave to `DOES-NOT-EXIST-123`. It joined
// `piece_barcodes` and nothing else, so a real barcode and a fictional one were
// the same answer.

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
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
  return { backend, server, baseUrl, headers: { Authorization: `Bearer ${token}` } };
}

// --- the codec, which nothing else can be right without ---------------------

test('a code round-trips, and an id containing dashes survives it', () => {
  for (const [type, id] of [
    ['ORD', '123457'],
    ['EMP', '12'],
    ['MAT', 'PAR-1786976524312-4696'],
    ['DC', 'SU-DEL-001'],
  ]) {
    const code = barcodes.encode(type, id);
    const back = barcodes.decode(code);
    assert.equal(back.type, type, code);
    assert.equal(back.id, id, code);
    assert.equal(back.checkValid, true, code);
  }
});

test('a misread digit is caught rather than resolving to another record', () => {
  // The reason a check character earns its place: once one code space covers
  // everything, ORD-000093 and ORD-000098 are both valid codes for different
  // real orders, and without a check the wrong one resolves silently.
  const good = barcodes.encode('ORD', '000093');
  const misread = good.replace('93-', '98-');
  assert.equal(barcodes.decode(good).checkValid, true);
  assert.equal(barcodes.decode(misread).checkValid, false);
});

test('two transposed characters are caught', () => {
  // Weighted by position for this: an unweighted sum is blind to transposition,
  // which is the commonest slip after a single wrong character.
  const good = barcodes.encode('EMP', '1234');
  const swapped = good.replace('1234', '1243');
  assert.equal(barcodes.decode(good).checkValid, true);
  assert.equal(barcodes.decode(swapped).checkValid, false);
});

test('a code with no check character still reads, marked unverified', () => {
  // What a hand-typed code, or one off a label printed before this existed,
  // looks like. Refusing it would be worse than accepting it unverified.
  const decoded = barcodes.decode('ORD-123457');
  assert.equal(decoded.type, 'ORD');
  assert.equal(decoded.id, '123457');
  assert.equal(decoded.hasCheck, false);
});

test('a code that was never ours decodes to nothing', () => {
  assert.equal(barcodes.decode('DOES-NOT-EXIST'), null);
  assert.equal(barcodes.decode('CHD-3533-01'), null, 'a legacy material code is not structured');
  assert.equal(barcodes.decode(''), null);
});

test('a derived code cannot be allocated twice', () => {
  // The property the minted scheme does not have: a probe measured PAR-/CHD-
  // colliding in 41% of workspaces by 100 parents. Derived from a primary key,
  // the same input is the same code and different inputs differ.
  const seen = new Set();
  for (let id = 1; id <= 5000; id += 1) seen.add(barcodes.encode('EMP', String(id)));
  assert.equal(seen.size, 5000, 'every id produced a distinct code');
  assert.equal(barcodes.encode('EMP', '42'), barcodes.encode('EMP', '42'), 'and it is stable');
});

// --- the resolver -----------------------------------------------------------

test('scanning resolves every kind of entity through one endpoint', async () => {
  const { backend, server, baseUrl, headers } = await boot('paper-scan-', 'scan@paper.local');
  try {
    // Only what this seed actually contains. Which tables the demo fills varies
    // by scenario, and a test that assumes one is testing the seed rather than
    // the resolver.
    const pick = async (sql, type, idColumn, label) => {
      const row = await backend.get(sql);
      return row ? [type, String(row[idColumn]), label] : null;
    };
    const cases = (
      await Promise.all([
        pick('SELECT * FROM clients LIMIT 1', 'CLI', 'id', 'Client'),
        pick('SELECT * FROM vendors LIMIT 1', 'VEN', 'id', 'Vendor'),
        pick('SELECT * FROM machines LIMIT 1', 'MCH', 'id', 'Machine'),
        pick('SELECT * FROM items LIMIT 1', 'ITM', 'id', 'Item'),
        pick('SELECT * FROM groups LIMIT 1', 'GRP', 'id', 'Group'),
        pick('SELECT * FROM employees LIMIT 1', 'EMP', 'id', 'Person'),
        pick('SELECT * FROM order_headers LIMIT 1', 'ORD', 'order_no', 'Order'),
        pick('SELECT * FROM pipeline_templates LIMIT 1', 'PLN', 'id', 'Pipeline'),
      ])
    ).filter(Boolean);
    assert.ok(cases.length >= 4, 'the seed offers enough kinds to be worth checking');

    for (const [type, id, label] of cases) {
      const code = barcodes.encode(type, id);
      const response = await fetch(`${baseUrl}/api/scan/${encodeURIComponent(code)}`, { headers });
      const body = await response.json();
      assert.equal(response.status, 200, `${label}: ${JSON.stringify(body)}`);
      assert.equal(body.scan.entity.type, type);
      assert.equal(body.scan.entity.id, id);
      assert.equal(body.scan.entity.typeLabel, label);
      assert.equal(body.scan.resolution.via, 'structured');
      assert.equal(body.scan.resolution.checkValid, true);
      assert.ok(body.scan.entity.title, 'something readable to show');
    }
  } finally {
    await closeServer(server);
  }
});

test('a real material barcode no longer answers like a fictional one', async () => {
  const { backend, server, baseUrl, headers } = await boot('paper-scan2-', 'scan2@paper.local');
  try {
    const material = await backend.get('SELECT barcode FROM materials LIMIT 1');
    assert.ok(material, 'the seed has stock');

    // Exactly the probe's case: a barcode that exists in `materials`, asked of
    // the endpoint that used to search only `piece_barcodes`.
    const real = await fetch(
      `${baseUrl}/api/barcode/lookup?code=${encodeURIComponent(material.barcode)}`,
      { headers },
    );
    const realBody = await real.json();
    assert.equal(real.status, 200, JSON.stringify(realBody));
    assert.equal(realBody.scan.found, true);
    assert.equal(realBody.scan.entity.type, 'MAT');
    assert.equal(
      realBody.scan.resolution.via,
      'legacy-code',
      'found by falling back to the code already printed on the label',
    );

    // And nonsense still fails — but now says something different.
    const nonsense = await fetch(`${baseUrl}/api/barcode/lookup?code=DOES-NOT-EXIST-123`, { headers });
    assert.equal(nonsense.status, 404);

    // The distinction the old lookup could not draw: shaped like ours but
    // naming nothing, versus never ours at all. They need different answers.
    const ghost = await fetch(
      `${baseUrl}/api/scan/${encodeURIComponent(barcodes.encode('ORD', '999999'))}`,
      { headers },
    );
    const ghostBody = await ghost.json();
    assert.equal(ghost.status, 404);
    assert.equal(ghostBody.scan.resolution.looksLikeOurs, true);
    const alien = await fetch(`${baseUrl}/api/scan/DOES-NOT-EXIST-123`, { headers });
    assert.equal((await alien.json()).scan.resolution.looksLikeOurs, false);
  } finally {
    await closeServer(server);
  }
});

test('a delivery code does not resolve a reception challan', async () => {
  const { backend, server, baseUrl, headers } = await boot('paper-scan3-', 'scan3@paper.local');
  try {
    const reception = await backend.get(
      "SELECT challan_no FROM delivery_challans WHERE type = 'reception' LIMIT 1",
    );
    if (!reception) return; // nothing seeded to check

    const asReception = await fetch(
      `${baseUrl}/api/scan/${encodeURIComponent(barcodes.encode('RC', reception.challan_no))}`,
      { headers },
    );
    assert.equal(asReception.status, 200);

    // Same table, told apart by type. Scanning it with the outward prefix must
    // not quietly hand back an inward challan.
    const asDelivery = await fetch(
      `${baseUrl}/api/scan/${encodeURIComponent(barcodes.encode('DC', reception.challan_no))}`,
      { headers },
    );
    const body = await asDelivery.json();
    assert.notEqual(
      body.scan.entity && body.scan.entity.type,
      'DC',
      'a reception challan must not resolve as a delivery',
    );
  } finally {
    await closeServer(server);
  }
});

test('the custody ledger is append-only, enforced by the database', async () => {
  const { backend, server } = await boot('paper-scan4-', 'scan4@paper.local');
  try {
    await backend.run(
      `INSERT INTO barcode_ledger (event_id, subject_barcode, event_type, actor_name, created_at)
       VALUES ('evt-test-1', 'MAT-TEST-1', 'INWARD_RECEIVED', 'Probe', datetime('now'))`,
    );

    // A provenance record that can be edited after the fact proves nothing
    // about the past. Enforced in the schema, not by convention.
    await assert.rejects(
      () => backend.run("UPDATE barcode_ledger SET notes = 'x' WHERE event_id = 'evt-test-1'"),
      /append-only/,
    );
    await assert.rejects(
      () => backend.run("DELETE FROM barcode_ledger WHERE event_id = 'evt-test-1'"),
      /append-only/,
    );

    const row = await backend.get(
      "SELECT notes FROM barcode_ledger WHERE event_id = 'evt-test-1'",
    );
    assert.equal(row.notes, '', 'the row survived the attempt, unchanged');

    // A deliberate workspace reset is the one operation allowed past the
    // trigger — leaving provenance for records that no longer exist would be
    // dangling claims rather than history. What must not happen is the window
    // outliving the reset that opened it.
    await backend.resetAndSeedDemoData();
    await backend.run(
      `INSERT INTO barcode_ledger (event_id, subject_barcode, event_type, created_at)
       VALUES ('evt-test-2', 'MAT-TEST-2', 'INWARD_RECEIVED', datetime('now'))`,
    );
    await assert.rejects(
      () => backend.run("DELETE FROM barcode_ledger WHERE event_id = 'evt-test-2'"),
      /append-only/,
      'the reset put back the protection it had to drop',
    );
  } finally {
    await closeServer(server);
  }
});

test('custody events reach the scan that asks for them', async () => {
  const { backend, server, baseUrl, headers } = await boot('paper-scan5-', 'scan5@paper.local');
  try {
    const client = await backend.get('SELECT * FROM clients LIMIT 1');
    const code = barcodes.encode('CLI', String(client.id));

    await backend.run(
      `INSERT INTO barcode_ledger
        (event_id, subject_barcode, event_type, actor_name, metrics_json, created_at)
       VALUES ('evt-c-1', ?, 'CLIENT_DELIVERED', 'Dispatch', '{"weightKg":12.5}', datetime('now'))`,
      [code],
    );

    const response = await fetch(`${baseUrl}/api/scan/${encodeURIComponent(code)}`, { headers });
    const body = await response.json();
    assert.equal(response.status, 200);
    assert.equal(body.scan.custody.length, 1);
    assert.equal(body.scan.custody[0].eventType, 'CLIENT_DELIVERED');
    assert.equal(body.scan.custody[0].actor, 'Dispatch');
    assert.equal(body.scan.custody[0].metrics.weightKg, 12.5);
  } finally {
    await closeServer(server);
  }
});

test('a full cycle leaves a readable custody trail', async () => {
  // The point of the whole thing: receive material, issue it to a run, and then
  // scan the material and be told its story — where it came from, on what
  // paperwork, who moved it, and what it went into.
  //
  // Driven through the real API rather than by writing ledger rows, because a
  // ledger that only fills when a test fills it proves nothing.
  const { backend, server, baseUrl, headers } = await boot('paper-cycle-', 'cycle@paper.local');
  const json = { ...headers, 'Content-Type': 'application/json' };
  try {
    const item = await backend.get('SELECT * FROM items LIMIT 1');
    const leaf = await backend.get(
      `SELECT n.* FROM item_variation_nodes n
       WHERE n.item_id = ? AND n.kind = 'value' AND n.is_archived = 0
         AND NOT EXISTS (SELECT 1 FROM item_variation_nodes c
                         WHERE c.parent_node_id = n.id AND c.is_archived = 0)
       LIMIT 1`,
      [item.id],
    );
    const now = new Date().toISOString();
    const vendorInsert = await backend.run(
      'INSERT INTO vendors (name, created_at, updated_at) VALUES (?, ?, ?)',
      ['Ledger Supplier', now, now],
    );

    // --- receive ---------------------------------------------------------
    const created = await fetch(`${baseUrl}/api/delivery-challans`, {
      method: 'POST',
      headers: json,
      body: JSON.stringify({
        type: 'reception',
        challanNo: 'LEDGER-REC-1',
        date: '2026-08-26',
        status: 'draft',
        purpose: 'purchase',
        maintainStocks: true,
        vendorId: vendorInsert.lastID,
        vendorName: 'Ledger Supplier',
        items: [{
          itemId: item.id,
          variationLeafNodeId: leaf ? leaf.id : 0,
          particulars: item.name,
          quantityPcs: '40',
          weight: '500',
          lineNo: 1,
        }],
      }),
    });
    const createdBody = await created.json();
    assert.equal(created.status, 201, JSON.stringify(createdBody));

    const issued = await fetch(
      `${baseUrl}/api/delivery-challans/${createdBody.data.id}/issue`,
      { method: 'POST', headers: json },
    );
    assert.equal(issued.status, 200, await issued.text());

    const line = await backend.get(
      'SELECT * FROM delivery_challan_items WHERE challan_id = ?',
      [createdBody.data.id],
    );
    const material = await backend.get(
      'SELECT * FROM materials WHERE source_challan_item_id = ?',
      [line.id],
    );
    assert.ok(material, 'receiving minted barcoded stock');

    // --- issue it to a run ------------------------------------------------
    const template = await backend.get('SELECT * FROM pipeline_templates LIMIT 1');
    const runCreated = await fetch(`${baseUrl}/runs`, {
      method: 'POST',
      headers: json,
      body: JSON.stringify({ templateId: template.id, name: 'Ledger Run' }),
    });
    const runBody = await runCreated.json();
    assert.equal(runCreated.status, 201, JSON.stringify(runBody));

    const attached = await fetch(`${baseUrl}/runs/${runBody.run.id}/barcodes`, {
      method: 'POST',
      headers: json,
      body: JSON.stringify({ nodeId: 'node-1', barcode: material.barcode, quantity: 15 }),
    });
    assert.equal(attached.status, 200, await attached.text());

    // --- scan the material and read its story -----------------------------
    const code = barcodes.encode('MAT', material.barcode);
    const scan = await fetch(`${baseUrl}/api/scan/${encodeURIComponent(code)}`, { headers });
    const scanBody = await scan.json();
    assert.equal(scan.status, 200, JSON.stringify(scanBody));
    assert.equal(scanBody.scan.entity.type, 'MAT');

    const events = scanBody.scan.custody.map((e) => e.eventType);
    assert.ok(
      events.includes('INWARD_RECEIVED'),
      `expected an arrival in the trail, got ${JSON.stringify(events)}`,
    );
    assert.ok(
      events.includes('ISSUED_TO_PIPELINE'),
      `expected a departure to the floor, got ${JSON.stringify(events)}`,
    );

    // Oldest first: a custody trail read out of order is not a trail.
    const times = scanBody.scan.custody.map((e) => e.at);
    assert.deepEqual(times, [...times].sort(), 'events come back in the order they happened');

    // The arrival names the paperwork it came in on.
    const arrival = scanBody.scan.custody.find((e) => e.eventType === 'INWARD_RECEIVED');
    assert.equal(arrival.documentBarcode, barcodes.encode('RC', 'LEDGER-REC-1'));
    assert.equal(arrival.metrics.qty > 0, true);

    // The departure names what it went into.
    const departure = scanBody.scan.custody.find((e) => e.eventType === 'ISSUED_TO_PIPELINE');
    assert.deepEqual(departure.children, [barcodes.encode('RUN', runBody.run.id)]);
    assert.equal(departure.metrics.qty, 15);

    // And scanning the reception challan itself reaches the same event, because
    // the trail is indexed by everything it mentions rather than by one subject.
    const challanScan = await fetch(
      `${baseUrl}/api/scan/${encodeURIComponent(barcodes.encode('RC', 'LEDGER-REC-1'))}`,
      { headers },
    );
    const challanBody = await challanScan.json();
    assert.equal(challanScan.status, 200, JSON.stringify(challanBody));
    assert.equal(challanBody.scan.entity.type, 'RC');
  } finally {
    await closeServer(server);
  }
});
