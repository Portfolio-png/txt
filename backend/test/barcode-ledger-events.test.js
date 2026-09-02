'use strict';

const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

const barcodes = require('../kernel/barcodes');

// The custody ledger is only worth having if the events actually fire. Three
// existed (INWARD_RECEIVED, DISPATCH_PACKED, ISSUED_TO_PIPELINE) and the trail
// stopped at the factory door: a finished piece could not be walked back to the
// material it was cut from, and a challan could not say whether it was billed.
//
// These drive the real routes rather than calling recordLedgerEvent directly,
// because the risk was never that the ledger cannot store an event — it is that
// the emit sits in a branch nothing reaches, or in one that runs twice.

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
  return {
    backend,
    server,
    baseUrl,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  };
}

/// Every event recorded against a code, in order.
async function ledgerFor(backend, code) {
  return backend.all(
    `SELECT event_type, subject_barcode, parent_barcodes_json, child_barcodes_json,
            order_barcode, metrics_json, notes
     FROM barcode_ledger
     WHERE subject_barcode = ?
        OR parent_barcodes_json LIKE '%' || ? || '%'
        OR child_barcodes_json LIKE '%' || ? || '%'
     ORDER BY id ASC`,
    [code, code, code],
  );
}

async function eventsOfType(backend, type) {
  return backend.all(
    'SELECT * FROM barcode_ledger WHERE event_type = ? ORDER BY id ASC',
    [type],
  );
}

test('LOCATION_MOVED: a transfer is recorded, and nothing else is', async (t) => {
  const ctx = await boot('paper-ledger-move-', 'ledger-move@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const material = await ctx.backend.get(
    "SELECT barcode, unit FROM materials WHERE barcode IS NOT NULL AND TRIM(barcode) != '' LIMIT 1",
  );
  assert.ok(material, 'the seed has at least one material to move');

  // Put stock somewhere first, so the transfer has something to move.
  await ctx.backend.applyInventoryMovement({
    barcode: material.barcode,
    movementType: 'receive',
    qty: 10,
    toLocationId: 'MAIN',
    actor: 'Test',
    referenceType: 'test-fixture',
    referenceId: 'seed-stock',
  });

  const afterReceive = await eventsOfType(ctx.backend, 'LOCATION_MOVED');
  assert.equal(
    afterReceive.length,
    0,
    'a receive is not a move — it is already told by the event that caused it, '
      + 'and saying it twice in an append-only table cannot be undone',
  );

  await ctx.backend.applyInventoryMovement({
    barcode: material.barcode,
    movementType: 'transfer',
    qty: 4,
    fromLocationId: 'MAIN',
    toLocationId: 'BAY-3',
    actor: 'Ramesh',
  });

  const moves = await eventsOfType(ctx.backend, 'LOCATION_MOVED');
  assert.equal(moves.length, 1, 'exactly one event per transfer, not one per position row');
  assert.equal(moves[0].subject_barcode, barcodes.encode('MAT', material.barcode));
  assert.equal(moves[0].actor_name, 'Ramesh');

  const metrics = JSON.parse(moves[0].metrics_json);
  // Locations are strings, not records, so there is no LOC barcode to point at.
  // Recording both ends as what they actually are beats inventing an entity.
  assert.equal(metrics.from, 'MAIN');
  assert.equal(metrics.to, 'BAY-3');
  assert.equal(Number(metrics.qty), 4);
});

test('LOCATION_MOVED: consuming stock into a run does not also log a move', async (t) => {
  // The regression this guards: applyInventoryMovementCore is called from
  // several places, including the ISSUED_TO_PIPELINE path. An unguarded emit
  // there would double-narrate every issue.
  const ctx = await boot('paper-ledger-move2-', 'ledger-move2@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const material = await ctx.backend.get(
    "SELECT barcode FROM materials WHERE barcode IS NOT NULL AND TRIM(barcode) != '' LIMIT 1",
  );
  await ctx.backend.applyInventoryMovement({
    barcode: material.barcode,
    movementType: 'receive',
    qty: 20,
    toLocationId: 'MAIN',
    actor: 'Test',
    referenceType: 'test-fixture',
    referenceId: 'seed-stock',
  });
  for (const movementType of ['consume', 'adjust', 'reserve', 'release']) {
    await ctx.backend
      .applyInventoryMovement({
        barcode: material.barcode,
        movementType,
        qty: 1,
        actor: 'Test',
      })
      .catch(() => {});
  }
  assert.deepEqual(await eventsOfType(ctx.backend, 'LOCATION_MOVED'), []);
});

test('INVOICED: billing a challan closes its story, once per challan', async (t) => {
  const ctx = await boot('paper-ledger-inv-', 'ledger-inv@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  // The demo seed carries no challans, so make one. Inserted directly because
  // what is under test is the billing emit, not how a challan comes to exist —
  // the emit reads the challan row and nothing about its history.
  const now = new Date().toISOString();
  const inserted = await ctx.backend.run(
    `INSERT INTO delivery_challans (challan_no, date, customer_name, type, status, created_at, updated_at)
     VALUES ('LEDG-DC-1', ?, 'Ledger Client', 'delivery', 'issued', ?, ?)`,
    [now, now, now],
  );
  const challan = await ctx.backend.get(
    'SELECT id, challan_no, type FROM delivery_challans WHERE id = ?',
    [inserted.lastID],
  );
  assert.ok(challan, 'there is a challan to bill');

  // Two lines against ONE challan. A five-line invoice is one billing event,
  // and the ledger cannot be de-duplicated after the fact.
  const response = await fetch(`${ctx.baseUrl}/api/invoices`, {
    method: 'POST',
    headers: ctx.headers,
    body: JSON.stringify({
      clientId: null,
      lines: [
        { challanId: challan.id, particulars: 'Line one', quantity: 1, rate: 100 },
        { challanId: challan.id, particulars: 'Line two', quantity: 2, rate: 50 },
      ],
    }),
  });
  const body = await response.json();
  assert.equal(response.status, 201, JSON.stringify(body));
  const created = body.data;

  const invoiced = await eventsOfType(ctx.backend, 'INVOICED');
  assert.equal(invoiced.length, 1, 'once per distinct challan, not once per line');
  assert.equal(
    invoiced[0].subject_barcode,
    barcodes.encode('DC', challan.challan_no),
    'the challan is the subject: an invoice is not a thing anyone holds and scans',
  );
  assert.equal(JSON.parse(invoiced[0].metrics_json).invoiceNo, created.invoiceNo);

  // And it shows up when you scan the challan, which is the whole point.
  const trail = await ledgerFor(ctx.backend, barcodes.encode('DC', challan.challan_no));
  assert.ok(trail.some((event) => event.event_type === 'INVOICED'));
});

test('STAGE_PROCESSED: reconciling a stage records it, re-saving it does not', async (t) => {
  const ctx = await boot('paper-ledger-stage-', 'ledger-stage@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const run = await ctx.backend.get('SELECT id FROM pipeline_runs LIMIT 1');
  assert.ok(run, 'the seed has a pipeline run');

  const post = (metrics) =>
    fetch(`${ctx.baseUrl}/runs/${run.id}/node-metrics`, {
      method: 'PUT',
      headers: ctx.headers,
      body: JSON.stringify({ nodeId: 'node-1', metrics }),
    });

  // What the Stage Reconciliation dialog sends: the whole booking, with times.
  const booking = (overrides) => ({
    allotted: 10,
    output: 9,
    scrap: 1,
    remaining: 0,
    inputTime: '2026-08-26T08:00:00.000Z',
    outputTime: '2026-08-26T11:00:00.000Z',
    ...overrides,
  });

  assert.equal((await post(booking({}))).status, 200);
  let events = await eventsOfType(ctx.backend, 'STAGE_PROCESSED');
  assert.equal(events.length, 1);
  assert.equal(events[0].subject_barcode, barcodes.encode('RUN', run.id));
  assert.equal(JSON.parse(events[0].metrics_json).revised, false);

  // Opening the dialog, looking, and saving without changing anything is not a
  // shop-floor event. stage_reconciliations is an UPSERT and converges to one
  // row; the ledger cannot, so an unguarded emit would leave a permanent
  // "processed again" every time someone glanced at it.
  assert.equal((await post(booking({}))).status, 200);
  events = await eventsOfType(ctx.backend, 'STAGE_PROCESSED');
  assert.equal(events.length, 1, 'a re-save that changes nothing writes nothing');

  // A genuine correction IS a real thing that happened, so it is kept — and
  // marked, so the trail reads as a revision rather than as a second stage.
  assert.equal((await post(booking({ output: 8, scrap: 2 }))).status, 200);
  events = await eventsOfType(ctx.backend, 'STAGE_PROCESSED');
  assert.equal(events.length, 2, 'a corrected number is worth recording');
  assert.equal(JSON.parse(events[1].metrics_json).revised, true);
  assert.equal(Number(JSON.parse(events[1].metrics_json).scrap), 2);
  assert.match(events[1].notes, /revised/i);
});

test('STAGE_PROCESSED: typing one number into an unworked stage claims nothing', async (t) => {
  // Two clients PUT to this route. The reconciliation dialog sends the whole
  // booking with timestamps; the inline metric box sends a single key and never
  // a time. Treating the second as a stage being processed would write, into a
  // table that cannot be corrected, that a stage nobody has run was worked.
  const ctx = await boot('paper-ledger-stage2-', 'ledger-stage2@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const run = await ctx.backend.get('SELECT id FROM pipeline_runs LIMIT 1');
  const post = (metrics) =>
    fetch(`${ctx.baseUrl}/runs/${run.id}/node-metrics`, {
      method: 'PUT',
      headers: ctx.headers,
      body: JSON.stringify({ nodeId: 'node-7', metrics }),
    });

  assert.equal((await post({ output: 4 })).status, 200);
  assert.deepEqual(
    await eventsOfType(ctx.backend, 'STAGE_PROCESSED'),
    [],
    'an inline edit before the stage was ever booked is not a stage being processed',
  );

  // But once the stage IS booked, correcting one of its numbers is a real
  // revision of a real booking, and that is worth keeping.
  assert.equal(
    (await post({
      allotted: 10,
      output: 9,
      scrap: 1,
      inputTime: '2026-08-26T08:00:00.000Z',
      outputTime: '2026-08-26T11:00:00.000Z',
    })).status,
    200,
  );
  assert.equal((await eventsOfType(ctx.backend, 'STAGE_PROCESSED')).length, 1);

  assert.equal((await post({ scrap: 3 })).status, 200);
  const events = await eventsOfType(ctx.backend, 'STAGE_PROCESSED');
  assert.equal(events.length, 2);
  assert.equal(JSON.parse(events[1].metrics_json).revised, true);
});

test('a completed run books its output under a code unique to THAT run', async (t) => {
  // The bug this guards was measured on the real database: `run_code` was
  // derived from the first eight characters of the pipeline run id, and 68 of
  // 72 runs began `run-ord-`. They all collapsed to one code. Because
  // `production_runs.run_code` is UNIQUE, the first run to finish took it and
  // the `if (!exists)` check silently swallowed the other 67 — real goods
  // finished with no production_runs row at all.
  //
  // It also made the MFG barcode a lie: one code naming 68 different runs'
  // output, in a ledger that cannot be corrected afterwards.
  //
  // The demo seed carries the same trap: `demo-dolly-run-active` and
  // `demo-dolly-run-queued` share the prefix `demo-dol`.
  const ctx = await boot('paper-ledger-runcode-', 'ledger-runcode@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const template = await ctx.backend.get(
    "SELECT * FROM pipeline_templates WHERE id = 'dolly'",
  );
  const nodes = JSON.parse(template.nodes_json || '[]');
  assert.ok(nodes.length, 'the dolly template has nodes');

  // Make the run's declared output resolve to a real item, or the completion
  // block is skipped entirely and this test passes vacuously.
  const outputNode = nodes.find((node) => !node.isIntermediate) || nodes[nodes.length - 1];
  const outputName = outputNode.outputs && outputNode.outputs[0];
  assert.ok(outputName, 'the output node names something');
  const item = await ctx.backend.get('SELECT id FROM items LIMIT 1');
  await ctx.backend.run('UPDATE items SET name = ? WHERE id = ?', [outputName, item.id]);

  const runIds = ['demo-dolly-run-active', 'demo-dolly-run-queued'];
  assert.equal(
    new Set(runIds.map((id) => id.substring(0, 8))).size,
    1,
    'the two runs really do share an eight-character prefix — the trap is live',
  );

  for (const runId of runIds) {
    for (const node of nodes) {
      // The final node returns 500, and that is a SEPARATE, PRE-EXISTING bug,
      // confirmed still present with these changes stashed: the completion path
      // calls getItemSelectionSnapshot, which throws "Client, item, and
      // variation values are required" whenever the output item has no leaf
      // variation node — and no item in the demo seed has one. It is not
      // swallowed here to be tidy; it is the reason OUTPUT_MINTED cannot fire
      // yet, and the run_code rows are written before the throw, which is
      // exactly what this test needs to see.
      await fetch(`${ctx.baseUrl}/runs/${runId}/node-status`, {
        method: 'PUT',
        headers: ctx.headers,
        body: JSON.stringify({ nodeId: node.id, status: 'done' }),
      });
    }
  }

  const minted = await ctx.backend.all(
    "SELECT run_code FROM production_runs WHERE run_code LIKE 'RUN-DEMO-DOLLY%' ORDER BY run_code",
  );
  assert.equal(minted.length, 2, 'both runs booked their output; neither was swallowed');
  assert.equal(
    new Set(minted.map((row) => row.run_code)).size,
    2,
    'and under codes that tell them apart',
  );

  // Under the old rule both would have been RUN-DEMO-DOL, so state that
  // directly rather than trusting the count above to mean what it should.
  const oldRule = runIds.map((id) => `RUN-${id.substring(0, 8).toUpperCase()}`);
  assert.equal(new Set(oldRule).size, 1, 'the old derivation really did collide');

  // Each code is a valid barcode naming its own run, which is what lets a
  // scanned finished piece reach the run that made it.
  for (const row of minted) {
    const decoded = barcodes.decode(barcodes.encode('MFG', row.run_code));
    assert.equal(decoded.checkValid, true);
    assert.equal(decoded.id, row.run_code.toUpperCase());
  }
});

test('reseeding the demo data writes no custody at all', async (t) => {
  // The one that would have poisoned everything. issueDeliveryChallan carries
  // the INWARD_RECEIVED / DISPATCH_PACKED emit, and the scenario seeders call
  // it five times to build a plausible-looking workspace. Every reseed was
  // pouring invented history into a table whose triggers forbid UPDATE and
  // DELETE — so it could never be cleaned out again.
  //
  // A trail that is part fiction is worse than no trail, because people act on
  // it: this is the record someone consults when a client returns a defective
  // part.
  const ctx = await boot('paper-ledger-seed-', 'ledger-seed@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  await ctx.backend.resetAndSeedDemoData();
  const afterSeed = await ctx.backend.all('SELECT event_type FROM barcode_ledger');
  assert.deepEqual(
    afterSeed,
    [],
    'seeded history is not custody: nobody carried those goods anywhere',
  );
});

test('a dispatch is one event, however many lines it has', async (t) => {
  // The subject of DISPATCH_PACKED is the challan, which is the same challan
  // for every line — so emitting inside the per-line loop wrote a twelve-line
  // consignment twelve times, each row identical but for its metrics. That is
  // not twelve happenings, and an append-only table cannot be tidied later.
  const ctx = await boot('paper-ledger-dispatch-', 'ledger-dispatch@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const item = await ctx.backend.get('SELECT id, name FROM items LIMIT 1');
  const now = new Date().toISOString();
  const inserted = await ctx.backend.run(
    `INSERT INTO delivery_challans (challan_no, date, customer_name, type, status, maintain_stocks, created_at, updated_at)
     VALUES ('LEDG-DC-MULTI', ?, 'Ledger Client', 'delivery', 'draft', 0, ?, ?)`,
    [now, now, now],
  );
  const challanId = inserted.lastID;
  for (let line = 0; line < 4; line += 1) {
    await ctx.backend.run(
      `INSERT INTO delivery_challan_items (
         challan_id, line_no, particulars, quantity_pcs, weight, item_id,
         variation_leaf_node_id, variation_path_node_ids_json, sheet_weights_json,
         created_at, updated_at, factor_to_primary_at_creation
       ) VALUES (?, ?, ?, ?, 0, ?, 0, '[]', '[]', ?, ?, 1)`,
      [challanId, line + 1, `Line ${line + 1}`, 3, item.id, now, now],
    );
  }

  await ctx.backend.issueDeliveryChallan(challanId, { id: null, name: 'Dispatcher' });

  const packed = await eventsOfType(ctx.backend, 'DISPATCH_PACKED');
  assert.equal(packed.length, 1, 'four lines, one consignment, one event');
  // A document-only challan still dispatches goods; it just does not track
  // stock. Custody is about who had the thing, not about inventory bookkeeping.
  const metrics = JSON.parse(packed[0].metrics_json);
  assert.equal(metrics.lineCount, 4, 'and the lines are not lost — they are summarised');
  assert.equal(Number(metrics.totalQty), 12);
});

test('a dispatch names the run that made the goods, closing the walk', async (t) => {
  // The hinge of the whole trail, and the hole that made everything upstream
  // unreachable. A dispatch used to record an item id and a variation — a CLASS
  // of goods — so scanning a delivered piece reached "some of this kind of
  // thing" and stopped. The run that made it, the material it was cut from and
  // the vendor it came from were all unreachable from the customer end, which is
  // the end complaints arrive at.
  const ctx = await boot('paper-ledger-walk-', 'ledger-walk@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const item = await ctx.backend.get('SELECT id FROM items LIMIT 1');
  const produced = await ctx.backend.get(
    'SELECT id, run_code FROM production_runs LIMIT 1',
  );
  assert.ok(produced, 'the seed has a production run to have made the goods');

  const now = new Date().toISOString();
  const inserted = await ctx.backend.run(
    `INSERT INTO delivery_challans (challan_no, date, customer_name, type, status, maintain_stocks, created_at, updated_at)
     VALUES ('LEDG-DC-WALK', ?, 'Ledger Client', 'delivery', 'draft', 0, ?, ?)`,
    [now, now, now],
  );
  const challanId = inserted.lastID;
  await ctx.backend.run(
    `INSERT INTO delivery_challan_items (
       challan_id, line_no, particulars, quantity_pcs, weight, item_id,
       production_run_id, variation_leaf_node_id, variation_path_node_ids_json,
       sheet_weights_json, created_at, updated_at, factor_to_primary_at_creation
     ) VALUES (?, 1, 'Finished frames', 5, 0, ?, ?, 0, '[]', '[]', ?, ?, 1)`,
    [challanId, item.id, produced.id, now, now],
  );

  await ctx.backend.issueDeliveryChallan(challanId, { id: null, name: 'Dispatcher' });

  const [packed] = await eventsOfType(ctx.backend, 'DISPATCH_PACKED');
  assert.ok(packed, 'the consignment was recorded');

  const parents = JSON.parse(packed.parent_barcodes_json);
  const mfg = barcodes.encode('MFG', produced.run_code);
  assert.ok(
    parents.includes(mfg),
    `the dispatch names the run that made the goods (${mfg}) — got ${JSON.stringify(parents)}`,
  );

  // And the walk closes: scanning the MFG code off a delivered piece reaches
  // this dispatch, because loadCustody matches parents as well as subjects.
  const trail = await ledgerFor(ctx.backend, mfg);
  assert.ok(
    trail.some((event) => event.event_type === 'DISPATCH_PACKED'),
    'the run that made the piece can be walked forward to where it went',
  );

  // A line with no run link is recorded as unlinked rather than silently
  // looking the same as a linked one.
  assert.equal(JSON.parse(packed.metrics_json).linesWithProductionRun, 1);
});

test('a completed run mints its output and says what it made', async (t) => {
  // Until this worked, OUTPUT_MINTED had never fired even once. Completing a run
  // asked for `item_variation_nodes WHERE kind = 'leaf'` — a kind this table has
  // never held, it stores only 'property' and 'value' — so the leaf id stayed 0,
  // resolveOrderVariationSelection threw, and the whole request 500'd. No run
  // could finish and no finished goods ever entered inventory.
  const ctx = await boot('paper-ledger-mint-', 'ledger-mint@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const template = await ctx.backend.get(
    "SELECT * FROM pipeline_templates WHERE id = 'dolly'",
  );
  const nodes = JSON.parse(template.nodes_json || '[]');
  const outputNode = nodes.find((node) => !node.isIntermediate) || nodes[nodes.length - 1];
  const outputName = outputNode.outputs && outputNode.outputs[0];

  // The variation produced is known only from the order line the run is
  // assigned to, so give it one — which is also the realistic case.
  const orderLine = await ctx.backend.get(
    'SELECT id, item_id, variation_leaf_node_id FROM order_items WHERE variation_leaf_node_id > 0 LIMIT 1',
  );
  assert.ok(orderLine, 'the seed has an order line naming a variation');
  await ctx.backend.run('UPDATE items SET name = ? WHERE id = ?', [outputName, orderLine.item_id]);
  await ctx.backend.run(
    'INSERT INTO order_pipeline_assignments (order_item_id, pipeline_run_id) VALUES (?, ?)',
    [orderLine.id, 'demo-dolly-run-active'],
  );

  for (const node of nodes) {
    const response = await fetch(`${ctx.baseUrl}/runs/demo-dolly-run-active/node-status`, {
      method: 'PUT',
      headers: ctx.headers,
      body: JSON.stringify({ nodeId: node.id, status: 'done' }),
    });
    assert.equal(response.status, 200, `${node.id}: ${await response.text()}`);
  }

  const [minted] = await eventsOfType(ctx.backend, 'OUTPUT_MINTED');
  assert.ok(minted, 'finishing a run records that something came into being');
  assert.equal(
    minted.subject_barcode,
    barcodes.encode('MFG', 'RUN-DEMO-DOLLY-RUN-ACTIVE'),
    'named for the run that made it, not for a truncated prefix',
  );

  const children = JSON.parse(minted.child_barcodes_json);
  assert.equal(children.length, 1, 'the lot it produced is the child');

  const lot = await ctx.backend.get(
    "SELECT barcode, name FROM materials WHERE barcode LIKE 'LOT-%' LIMIT 1",
  );
  assert.ok(lot, 'the finished goods actually entered inventory');
  assert.notEqual(
    lot.name,
    'Finished Good',
    'the lot is named for what it is — this read snapshot.fullName, which the '
      + 'snapshot does not have, so every lot was literally called "Finished Good"',
  );

  const parents = JSON.parse(minted.parent_barcodes_json);
  assert.ok(parents.includes(barcodes.encode('RUN', 'demo-dolly-run-active')));
});

test('a run whose output variation is unknowable completes without minting a guess', async (t) => {
  // The stage really did finish, so the run must complete. But nothing can say
  // WHICH variation was produced when the run is not tied to an order line, and
  // minting against a guess would put a wrong fact into inventory and name it
  // permanently in a ledger that cannot be corrected. Not minting is
  // recoverable; a mislabelled lot is not.
  const ctx = await boot('paper-ledger-nomint-', 'ledger-nomint@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const template = await ctx.backend.get(
    "SELECT * FROM pipeline_templates WHERE id = 'dolly'",
  );
  const nodes = JSON.parse(template.nodes_json || '[]');
  const outputNode = nodes.find((node) => !node.isIntermediate) || nodes[nodes.length - 1];
  // An item with variations, and deliberately NO order assignment.
  const withVariations = await ctx.backend.get(
    "SELECT DISTINCT item_id FROM item_variation_nodes WHERE kind = 'property' LIMIT 1",
  );
  await ctx.backend.run('UPDATE items SET name = ? WHERE id = ?', [
    outputNode.outputs[0],
    withVariations.item_id,
  ]);

  for (const node of nodes) {
    const response = await fetch(`${ctx.baseUrl}/runs/demo-dolly-run-queued/node-status`, {
      method: 'PUT',
      headers: ctx.headers,
      body: JSON.stringify({ nodeId: node.id, status: 'done' }),
    });
    assert.equal(response.status, 200, 'the run still completes — the work was done');
  }

  const finished = await ctx.backend.get(
    "SELECT status FROM pipeline_runs WHERE id = 'demo-dolly-run-queued'",
  );
  assert.equal(finished.status, 'completed');
  assert.deepEqual(
    await eventsOfType(ctx.backend, 'OUTPUT_MINTED'),
    [],
    'and nothing was invented about what it produced',
  );
});

test('scanning a storage location says what is on it', async (t) => {
  // Places are the one type with no record behind them: a location is a
  // free-text string on a stock position, a floor is one on a machine. Before
  // this, scanning a sticker on a rack said "nothing here carries that code",
  // which is indistinguishable from scanning something foreign.
  const ctx = await boot('paper-ledger-loc-', 'ledger-loc@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const material = await ctx.backend.get(
    "SELECT barcode FROM materials WHERE TRIM(COALESCE(barcode,'')) != '' LIMIT 1",
  );
  await ctx.backend.applyInventoryMovement({
    barcode: material.barcode,
    movementType: 'receive',
    qty: 12,
    toLocationId: 'MAIN',
    actor: 'Test',
    referenceType: 'test-fixture',
    referenceId: 'seed-stock',
  });

  const code = barcodes.encode('LOC', 'MAIN');
  const response = await fetch(`${ctx.baseUrl}/api/scan/${encodeURIComponent(code)}`, {
    headers: ctx.headers,
  });
  assert.equal(response.status, 200);
  const scan = (await response.json()).scan;
  assert.equal(scan.found, true, 'a rack resolves');
  assert.equal(scan.entity.type, 'LOC');
  assert.equal(scan.entity.title, 'MAIN');

  // Being told "this is a rack" would be worse than not resolving. What makes
  // the scan worth doing is what is on it.
  const labels = scan.facts.map((fact) => fact.label);
  assert.ok(labels.includes('Distinct materials here'), JSON.stringify(labels));
  assert.ok(labels.includes('Total on hand'));
});

test('a floor name with spaces still resolves from its code', async (t) => {
  // The trap that makes places different from every other type: a barcode
  // strips whitespace, so 'Cutting bay' travels as CUTTINGBAY. A column compare
  // would never match it, and the code would encode and decode perfectly and
  // then find nothing — the most confusing failure available.
  const ctx = await boot('paper-ledger-flr-', 'ledger-flr@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  // The demo seed carries no machines, so stand one on a floor whose name has a
  // space in it — which is how they are actually named in the live database
  // ('Cutting bay', 'Assembly line 1', 'Rack A1').
  const stamp = new Date().toISOString();
  await ctx.backend.run(
    `INSERT INTO machines (name, asset_id, status, location, custom_properties,
                           report_notes, barcode, created_at, updated_at)
     VALUES ('Press 3', 'AST-9001', 'idle', 'Cutting bay', '{}', '', 'MCH-TEST-1', ?, ?)`,
    [stamp, stamp],
  );

  const floor = await ctx.backend.get(
    "SELECT DISTINCT location FROM machines WHERE location LIKE '% %' LIMIT 1",
  );
  assert.ok(floor, 'there is a floor whose name contains a space');
  assert.ok(floor.location.includes(' '), `${floor.location} has a space in it`);

  const code = barcodes.encode('FLR', floor.location);
  assert.ok(!code.includes(' '), 'the code carries no space');

  const response = await fetch(`${ctx.baseUrl}/api/scan/${encodeURIComponent(code)}`, {
    headers: ctx.headers,
  });
  const scan = (await response.json()).scan;
  assert.equal(scan.found, true, `${code} should reach ${floor.location}`);
  assert.equal(scan.entity.title, floor.location, 'and reports the name as stored, spaces and all');
  assert.ok(scan.facts.some((fact) => fact.label === 'Machines here'));
});

test('a move is visible when you scan the place it moved to', async (t) => {
  // A location is never a subject, a parent or a child — a rack does not
  // descend from anything — so without matching location_barcode a scanned rack
  // resolved and then showed an empty history, which reads as "nothing ever
  // happened here" rather than "this view cannot see it".
  const ctx = await boot('paper-ledger-locmove-', 'ledger-locmove@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const material = await ctx.backend.get(
    "SELECT barcode FROM materials WHERE TRIM(COALESCE(barcode,'')) != '' LIMIT 1",
  );
  await ctx.backend.applyInventoryMovement({
    barcode: material.barcode,
    movementType: 'receive',
    qty: 20,
    toLocationId: 'MAIN',
    actor: 'Test',
    referenceType: 'test-fixture',
    referenceId: 'seed-stock',
  });
  await ctx.backend.applyInventoryMovement({
    barcode: material.barcode,
    movementType: 'transfer',
    qty: 6,
    fromLocationId: 'MAIN',
    toLocationId: 'RACK B2',
    actor: 'Ramesh',
  });

  const code = barcodes.encode('LOC', 'RACK B2');
  const trail = await ctx.backend.all(
    `SELECT event_type FROM barcode_ledger
     WHERE subject_barcode = ? OR parent_barcodes_json LIKE '%' || ? || '%'
        OR child_barcodes_json LIKE '%' || ? || '%' OR location_barcode = ?`,
    [code, code, code, code],
  );
  assert.ok(
    trail.some((event) => event.event_type === 'LOCATION_MOVED'),
    'the rack knows what arrived on it',
  );
});

test('CUSTOMER_RETURN: goods coming back are recorded on the piece and the order', async (t) => {
  // The question the whole ledger exists to answer. `order_returns`' own schema
  // comment calls itself the trigger for the backward QC lineage trace, and it
  // recorded nothing at all.
  const ctx = await boot('paper-ledger-return-', 'ledger-return@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const order = await ctx.backend.get('SELECT order_no FROM order_headers LIMIT 1');
  assert.ok(order, 'the seed has an order');
  const piece = barcodes.encode('MFG', 'RUN-DEMO-DOLLY-RUN-ACTIVE');

  const response = await fetch(
    `${ctx.baseUrl}/api/orders/${encodeURIComponent(order.order_no)}/returns`,
    {
      method: 'POST',
      headers: ctx.headers,
      body: JSON.stringify({
        quantity: 2,
        unit: 'pcs',
        reasonCode: 'defect',
        defectDescription: 'Cracked at the weld',
        returnedBarcode: piece,
      }),
    },
  );
  assert.equal(response.status, 201, await response.text());

  const [returned] = await eventsOfType(ctx.backend, 'CUSTOMER_RETURN');
  assert.ok(returned, 'the return was recorded');
  assert.equal(
    returned.subject_barcode,
    piece,
    'the subject is the piece someone is holding, not the paperwork',
  );
  assert.equal(JSON.parse(returned.metrics_json).pieceIdentified, true);
  assert.match(returned.notes, /Cracked at the weld/);

  // Reachable from BOTH ends. The order is a parent, not merely orderBarcode:
  // loadCustody matches subject, parents and children, so a code that appears
  // only in orderBarcode is invisible to a scan of the order.
  const fromOrder = await ledgerFor(ctx.backend, barcodes.encode('ORD', order.order_no));
  assert.ok(
    fromOrder.some((event) => event.event_type === 'CUSTOMER_RETURN'),
    'scanning the order shows that something came back',
  );
  const fromPiece = await ledgerFor(ctx.backend, piece);
  assert.ok(fromPiece.some((event) => event.event_type === 'CUSTOMER_RETURN'));
});

test('CUSTOMER_RETURN: a return with no scanned piece says so rather than pretending', async (t) => {
  const ctx = await boot('paper-ledger-return2-', 'ledger-return2@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const order = await ctx.backend.get('SELECT order_no FROM order_headers LIMIT 1');
  const response = await fetch(
    `${ctx.baseUrl}/api/orders/${encodeURIComponent(order.order_no)}/returns`,
    {
      method: 'POST',
      headers: ctx.headers,
      body: JSON.stringify({ quantity: 1, reasonCode: 'damaged' }),
    },
  );
  assert.equal(response.status, 201);

  const [returned] = await eventsOfType(ctx.backend, 'CUSTOMER_RETURN');
  assert.equal(
    returned.subject_barcode,
    barcodes.encode('ORD', order.order_no),
    'with no piece to hang it on, the order carries it',
  );
  // "Returned without a code" and "returned a piece we can trace" must not look
  // the same to a reader.
  assert.equal(JSON.parse(returned.metrics_json).pieceIdentified, false);
});

test('ISSUED_TO_PIPELINE: issuing by quantity is custody too', async (t) => {
  // Only the SKU branch of this route ever emitted. A shop that issues 40kg off
  // a coil — which is how a sheet-metal shop actually works — left no trace
  // between the reception and the run.
  const ctx = await boot('paper-ledger-qty-', 'ledger-qty@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const item = await ctx.backend.get('SELECT id FROM items LIMIT 1');
  const post = await fetch(`${ctx.baseUrl}/runs/demo-dolly-run-active/barcodes`, {
    method: 'POST',
    headers: ctx.headers,
    body: JSON.stringify({ itemId: item.id, quantity: 40, nodeId: 'dolly-cut' }),
  });
  assert.equal(post.status, 200, await post.text());

  const [issued] = await eventsOfType(ctx.backend, 'ISSUED_TO_PIPELINE');
  assert.ok(issued, 'issuing by quantity leaves a trace');
  assert.equal(
    issued.subject_barcode,
    barcodes.encode('ITM', String(item.id)),
    'the subject is the item — the "#qty-…" sentinel is a row id, not a thing '
      + 'anyone can scan, and encoding it would put a permanently dead code in '
      + 'the ledger',
  );
  const metrics = JSON.parse(issued.metrics_json);
  assert.equal(Number(metrics.qty), 40);
  assert.equal(metrics.sourceKind, 'quantity');
  assert.ok(
    JSON.parse(issued.child_barcodes_json).includes(
      barcodes.encode('RUN', 'demo-dolly-run-active'),
    ),
    'and it names the run it went into',
  );
});

test('ISSUED_TO_PIPELINE: a vendor sheet carries its whole origin into the run', async (t) => {
  // The richest custody moment in the codebase, and it recorded nothing. This
  // branch already holds the vendor, the reception challan and the exact
  // physical sheet — its own comment says it exists so a run traces back to the
  // original vendor sheet — and it wrote straight into run_barcode_inputs
  // without a word to the ledger.
  const ctx = await boot('paper-ledger-sheet-', 'ledger-sheet@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const stamp = new Date().toISOString();
  // The demo seed carries no vendors, so make the one this sheet came from.
  let vendor = await ctx.backend.get('SELECT id, name FROM vendors LIMIT 1');
  if (!vendor) {
    const made = await ctx.backend.run(
      "INSERT INTO vendors (name, created_at, updated_at) VALUES ('Acme Steel', ?, ?)",
      [stamp, stamp],
    );
    vendor = { id: made.lastID, name: 'Acme Steel' };
  }
  const item = await ctx.backend.get('SELECT id FROM items LIMIT 1');

  const challan = await ctx.backend.run(
    `INSERT INTO delivery_challans (challan_no, date, customer_name, type, status,
                                    vendor_id, vendor_name, maintain_stocks, created_at, updated_at)
     VALUES ('LEDG-RC-SHEET', ?, '', 'reception', 'issued', ?, ?, 0, ?, ?)`,
    [stamp, vendor.id, vendor.name, stamp, stamp],
  );
  const line = await ctx.backend.run(
    `INSERT INTO delivery_challan_items (
       challan_id, line_no, particulars, quantity_pcs, weight, item_id,
       variation_leaf_node_id, variation_path_node_ids_json, sheet_weights_json,
       created_at, updated_at, factor_to_primary_at_creation
     ) VALUES (?, 1, 'Steel sheet', 1, 25, ?, 0, '[]', '[]', ?, ?, 1)`,
    [challan.lastID, item.id, stamp, stamp],
  );
  await ctx.backend.run(
    `INSERT INTO piece_barcodes (challan_item_id, parent_code, child_code, weight, created_at)
     VALUES (?, 'SHEET-PARENT-1', 'SHEET-CHILD-1', 25, ?)`,
    [line.lastID, stamp],
  );

  const response = await fetch(`${ctx.baseUrl}/runs/demo-dolly-run-active/barcodes`, {
    method: 'POST',
    headers: ctx.headers,
    body: JSON.stringify({ barcode: 'SHEET-CHILD-1', nodeId: 'dolly-cut' }),
  });
  assert.equal(response.status, 200, await response.text());

  const [issued] = await eventsOfType(ctx.backend, 'ISSUED_TO_PIPELINE');
  assert.ok(issued, 'consuming a vendor sheet leaves a trace');
  assert.equal(
    issued.subject_barcode,
    barcodes.encode('DCL', String(line.lastID)),
    'the subject is the challan line the sheet was received under',
  );
  assert.ok(
    JSON.parse(issued.parent_barcodes_json).includes(
      barcodes.encode('VEN', String(vendor.id)),
    ),
    'and the walk reaches the vendor — the outside world',
  );
  assert.ok(
    JSON.parse(issued.child_barcodes_json).includes(
      barcodes.encode('RUN', 'demo-dolly-run-active'),
    ),
  );

  const metrics = JSON.parse(issued.metrics_json);
  assert.equal(metrics.sourceKind, 'sheet');
  assert.equal(Number(metrics.weightKg), 25);
  // Verbatim: this is the code physically on the sheet, the one someone reads
  // back off it when the trail is in question.
  assert.equal(metrics.pieceParentCode, 'SHEET-PARENT-1');
  assert.equal(metrics.receptionChallanNo, 'LEDG-RC-SHEET');
});

test('a standalone run mints what its operator said it was making', async (t) => {
  // A run building stock has no order line to say which variation it produces,
  // so it declined to mint rather than guess. An operator starting one usually
  // does know — there was simply nowhere to write it down.
  const ctx = await boot('paper-ledger-target-', 'ledger-target@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const template = await ctx.backend.get("SELECT * FROM pipeline_templates WHERE id = 'dolly'");
  const nodes = JSON.parse(template.nodes_json || '[]');
  const outputNode = nodes.find((node) => !node.isIntermediate) || nodes[nodes.length - 1];
  const orderLine = await ctx.backend.get(
    'SELECT item_id, variation_leaf_node_id, variation_path_label FROM order_items WHERE variation_leaf_node_id > 0 LIMIT 1',
  );
  await ctx.backend.run('UPDATE items SET name = ? WHERE id = ?', [
    outputNode.outputs[0],
    orderLine.item_id,
  ]);

  // Created with a stated target and deliberately NO order assignment.
  const created = await fetch(`${ctx.baseUrl}/runs`, {
    method: 'POST',
    headers: ctx.headers,
    body: JSON.stringify({
      templateId: 'dolly',
      name: 'Stock build',
      outputVariationLeafNodeId: orderLine.variation_leaf_node_id,
      outputVariationPathLabel: orderLine.variation_path_label || '',
    }),
  });
  const createdBody = await created.json();
  assert.equal(created.status, 201, JSON.stringify(createdBody));
  const runId = createdBody.run.id;

  const assignments = await ctx.backend.all(
    'SELECT 1 FROM order_pipeline_assignments WHERE pipeline_run_id = ?',
    [runId],
  );
  assert.equal(assignments.length, 0, 'this run answers to no order line');

  for (const node of nodes) {
    const response = await fetch(`${ctx.baseUrl}/runs/${runId}/node-status`, {
      method: 'PUT',
      headers: ctx.headers,
      body: JSON.stringify({ nodeId: node.id, status: 'done' }),
    });
    assert.equal(response.status, 200, await response.text());
  }

  const [minted] = await eventsOfType(ctx.backend, 'OUTPUT_MINTED');
  assert.ok(minted, 'a stated target is enough to mint against');
  assert.equal(
    JSON.parse(minted.metrics_json).variationLeafNodeId,
    orderLine.variation_leaf_node_id,
    'and it minted the variation the operator named, not an arbitrary one',
  );
});

test('an order line outranks the run\'s own stated target', async (t) => {
  // Both can be present. The order line wins because it is what was actually
  // promised to a customer; the run's target is one person's intent at the
  // machine.
  const ctx = await boot('paper-ledger-rank-', 'ledger-rank@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const template = await ctx.backend.get("SELECT * FROM pipeline_templates WHERE id = 'dolly'");
  const nodes = JSON.parse(template.nodes_json || '[]');
  const outputNode = nodes.find((node) => !node.isIntermediate) || nodes[nodes.length - 1];
  const orderLine = await ctx.backend.get(
    'SELECT id, item_id, variation_leaf_node_id FROM order_items WHERE variation_leaf_node_id > 0 LIMIT 1',
  );
  await ctx.backend.run('UPDATE items SET name = ? WHERE id = ?', [
    outputNode.outputs[0],
    orderLine.item_id,
  ]);

  const created = await fetch(`${ctx.baseUrl}/runs`, {
    method: 'POST',
    headers: ctx.headers,
    body: JSON.stringify({
      templateId: 'dolly',
      orderItemId: orderLine.id,
      // A different, wrong target. The order line must win.
      outputVariationLeafNodeId: 999999,
      outputVariationPathLabel: 'Wrong variation',
    }),
  });
  const runId = (await created.json()).run.id;

  for (const node of nodes) {
    await fetch(`${ctx.baseUrl}/runs/${runId}/node-status`, {
      method: 'PUT',
      headers: ctx.headers,
      body: JSON.stringify({ nodeId: node.id, status: 'done' }),
    });
  }

  const [minted] = await eventsOfType(ctx.backend, 'OUTPUT_MINTED');
  assert.ok(minted);
  assert.equal(
    JSON.parse(minted.metrics_json).variationLeafNodeId,
    orderLine.variation_leaf_node_id,
    'the promise to the customer, not the note at the machine',
  );
});

test('a dispatched line names the lot, closing the circle to the vendor', async (t) => {
  // The whole point of the ledger, walked end to end. A run mints a lot every
  // time it completes, so `production_run_id` alone says "made by run 42" — not
  // which physical thing is in the customer's hands, which is what a defect
  // report starts by scanning.
  const ctx = await boot('paper-ledger-dispatch-', 'ledger-dispatch@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const stamp = new Date().toISOString();
  const template = await ctx.backend.get("SELECT * FROM pipeline_templates WHERE id = 'dolly'");
  const nodes = JSON.parse(template.nodes_json || '[]');
  const outputNode = nodes.find((node) => !node.isIntermediate) || nodes[nodes.length - 1];
  const orderLine = await ctx.backend.get(
    'SELECT id, item_id, variation_leaf_node_id FROM order_items WHERE variation_leaf_node_id > 0 LIMIT 1',
  );
  await ctx.backend.run('UPDATE items SET name = ? WHERE id = ?', [
    outputNode.outputs[0],
    orderLine.item_id,
  ]);
  await ctx.backend.run(
    'INSERT INTO order_pipeline_assignments (order_item_id, pipeline_run_id) VALUES (?, ?)',
    [orderLine.id, 'demo-dolly-run-active'],
  );

  // Make something.
  for (const node of nodes) {
    const response = await fetch(`${ctx.baseUrl}/runs/demo-dolly-run-active/node-status`, {
      method: 'PUT',
      headers: ctx.headers,
      body: JSON.stringify({ nodeId: node.id, status: 'done' }),
    });
    assert.equal(response.status, 200);
  }
  const lot = await ctx.backend.get("SELECT barcode FROM materials WHERE barcode LIKE 'LOT-%' LIMIT 1");
  assert.ok(lot, 'the run produced a lot');
  // Named explicitly: the seed already carries four production_runs from orders,
  // and LIMIT 1 would pick one of those, which no pipeline run ever produced.
  const productionRun = await ctx.backend.get(
    'SELECT id, run_code FROM production_runs WHERE run_code = ?',
    [barcodes.normalize('RUN-DEMO-DOLLY-RUN-ACTIVE')],
  );
  assert.ok(productionRun, 'and a production_runs row naming it');

  // Ship it. The line names the run; the lot is derived from it.
  const challan = await ctx.backend.run(
    `INSERT INTO delivery_challans (challan_no, date, customer_name, type, status, maintain_stocks, created_at, updated_at)
     VALUES ('LEDG-DC-LOT', ?, 'Ledger Client', 'delivery', 'draft', 0, ?, ?)`,
    [stamp, stamp, stamp],
  );
  const line = await ctx.backend.run(
    `INSERT INTO delivery_challan_items (
       challan_id, line_no, particulars, quantity_pcs, weight, item_id, production_run_id,
       variation_leaf_node_id, variation_path_node_ids_json, sheet_weights_json,
       created_at, updated_at, factor_to_primary_at_creation
     ) VALUES (?, 1, 'Finished goods', 5, 0, ?, ?, ?, '[]', '[]', ?, ?, 1)`,
    [challan.lastID, orderLine.item_id, productionRun.id, orderLine.variation_leaf_node_id, stamp, stamp],
  );

  await ctx.backend.issueDeliveryChallan(challan.lastID, { id: null, name: 'Dispatcher' });

  // The lot is now a recorded fact about the dispatch, not something re-derived
  // later against data that has since moved on.
  const shipped = await ctx.backend.get(
    'SELECT lot_code, material_barcode FROM delivery_challan_items WHERE id = ?',
    [line.lastID],
  );
  assert.equal(shipped.lot_code, lot.barcode, 'the line remembers which lot went out');
  assert.equal(shipped.material_barcode, lot.barcode);

  const [packed] = await eventsOfType(ctx.backend, 'DISPATCH_PACKED');
  assert.ok(packed, 'issuing recorded a dispatch');
  const parents = JSON.parse(packed.parent_barcodes_json);
  assert.ok(
    parents.includes(barcodes.encode('MAT', lot.barcode)),
    `the specific lot is named: ${JSON.stringify(parents)}`,
  );
  assert.equal(JSON.parse(packed.metrics_json).linesWithLot, 1);

  // And now the walk that all of this exists for: from the thing the customer
  // is holding, back to the run that made it, in one hop each.
  const fromLot = await ledgerFor(ctx.backend, barcodes.encode('MAT', lot.barcode));
  const seen = fromLot.map((event) => event.event_type);
  assert.ok(seen.includes('DISPATCH_PACKED'), `scanning the lot shows where it went: ${seen}`);
  assert.ok(seen.includes('OUTPUT_MINTED'), `and where it came from: ${seen}`);
});

test('the ledger stays append-only even as the new events land', async (t) => {
  // The triggers are the only thing making the trail trustworthy. New write
  // paths are exactly when a well-meaning UPDATE gets added.
  const ctx = await boot('paper-ledger-guard-', 'ledger-guard@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const material = await ctx.backend.get(
    "SELECT barcode FROM materials WHERE barcode IS NOT NULL AND TRIM(barcode) != '' LIMIT 1",
  );
  await ctx.backend.applyInventoryMovement({
    barcode: material.barcode,
    movementType: 'receive',
    qty: 5,
    toLocationId: 'MAIN',
    actor: 'Test',
    referenceType: 'test-fixture',
    referenceId: 'seed-stock',
  });
  await ctx.backend.applyInventoryMovement({
    barcode: material.barcode,
    movementType: 'transfer',
    qty: 2,
    fromLocationId: 'MAIN',
    toLocationId: 'BAY-9',
    actor: 'Test',
  });

  const [event] = await eventsOfType(ctx.backend, 'LOCATION_MOVED');
  assert.ok(event, 'there is an event to try to tamper with');

  await assert.rejects(
    () => ctx.backend.run("UPDATE barcode_ledger SET notes = 'edited' WHERE id = ?", [event.id]),
    /append-only/,
  );
  await assert.rejects(
    () => ctx.backend.run('DELETE FROM barcode_ledger WHERE id = ?', [event.id]),
    /append-only/,
  );
});
