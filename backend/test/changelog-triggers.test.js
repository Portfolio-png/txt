'use strict';

const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// Every write must record that it happened.
//
// The changelog is what a local read replica replays, so its coverage is the
// hard ceiling on what such a replica can keep truthful. An audit found ~174
// mutation sites across these tables and ~13 logging — about 7% — with four of
// those calls naming a table that does not exist and an event type the CHECK
// constraint rejects, so they had never written a row at all.
//
// The fix is triggers rather than 174 remembered call sites, and the property
// worth testing is exactly the one that makes triggers the right answer: a
// write nobody told to log still gets logged. Every statement below goes
// straight at the database, with no application code in the path.

const REPLICATED = [
  'materials', 'item_variation_nodes', 'order_items', 'order_headers',
  'delivery_challan_items', 'delivery_challans', 'items', 'units',
  'groups', 'pipeline_templates', 'pipeline_runs', 'machines',
  'dies', 'clients', 'vendors', 'departments', 'inventory_stock_positions',
];

async function boot(prefix) {
  const tempDir = mkdtempSync(path.join(tmpdir(), prefix));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'changelog@paper.test';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  return backend;
}

/// The primary key column, whatever it is called.
async function primaryKeyOf(backend, table) {
  const columns = await backend.all(`PRAGMA table_info(${table})`);
  const pk = columns.find((column) => column.pk > 0);
  return pk ? pk.name : null;
}

/// Copies an existing row back into its own table under a new key.
///
/// Cloning rather than composing a fixture per table: seventeen tables have
/// seventeen different sets of NOT NULLs and foreign keys, and a test that
/// hand-builds each one tests the fixtures as much as the triggers. A copy of a
/// row the seed already accepted satisfies every constraint by construction.
async function cloneRow(backend, table, pk) {
  const columns = await backend.all(`PRAGMA table_info(${table})`);
  const names = columns.map((column) => column.name).filter((name) => name !== pk);
  if (!names.length) return null;

  const source = await backend.get(`SELECT * FROM ${table} LIMIT 1`);
  if (!source) return null;

  // Columns under a UNIQUE index have to differ, or the copy collides with the
  // row it came from — materials.barcode, challan_no, order_no and friends.
  const unique = new Set();
  for (const index of await backend.all(`PRAGMA index_list(${table})`)) {
    if (!index.unique) continue;
    for (const part of await backend.all(`PRAGMA index_info(${index.name})`)) {
      if (part.name && part.name !== pk) unique.add(part.name);
    }
  }
  const probe = `probe-${Date.now()}-${Math.floor(Math.random() * 100000)}`;
  const valueFor = (name) => {
    const original = source[name];
    if (!unique.has(name)) return original;
    if (typeof original === 'string') return `${original}-${probe}`;
    if (typeof original === 'number') return original + 1_000_000 + Math.floor(Math.random() * 100000);
    return probe;
  };

  const list = names.map((name) => `"${name}"`).join(', ');
  const holes = names.map(() => '?').join(', ');
  // A text key has to be given a value; an integer key can autoincrement.
  const isTextKey = typeof source[pk] === 'string';
  if (isTextKey) {
    const value = `${source[pk]}-changelog-probe`;
    await backend.run(
      `INSERT INTO ${table} ("${pk}", ${list}) VALUES (?, ${holes})`,
      [value, ...names.map(valueFor)],
    );
    return value;
  }
  const result = await backend.run(
    `INSERT INTO ${table} (${list}) VALUES (${holes})`,
    names.map(valueFor),
  );
  return result.lastID;
}

/// The smallest row a table will accept.
///
/// Needed for the seven tables the demo seed leaves empty. Foreign keys are
/// relaxed for the probe: the point is whether the trigger fires, not whether a
/// synthetic row is referentially sensible, and requiring a valid graph would
/// mean hand-building fixtures for tables whose shape is irrelevant here.
async function minimalRow(backend, table, pk) {
  const columns = await backend.all(`PRAGMA table_info(${table})`);
  const required = columns.filter(
    (column) => column.name !== pk && column.notnull === 1 && column.dflt_value === null,
  );
  const value = (column) => {
    const type = String(column.type || '').toUpperCase();
    if (type.includes('INT')) return 0;
    if (type.includes('REAL') || type.includes('NUM') || type.includes('DEC')) return 0;
    return `probe-${Date.now()}`;
  };

  await backend.run('PRAGMA foreign_keys = OFF');
  try {
    if (!required.length) {
      const result = await backend.run(`INSERT INTO ${table} DEFAULT VALUES`);
      return result.lastID;
    }
    const list = required.map((column) => `"${column.name}"`).join(', ');
    const holes = required.map(() => '?').join(', ');
    const result = await backend.run(
      `INSERT INTO ${table} (${list}) VALUES (${holes})`,
      required.map(value),
    );
    return result.lastID;
  } catch (_) {
    return null;
  } finally {
    await backend.run('PRAGMA foreign_keys = ON');
  }
}

test('every replicated table logs its own writes, with no application code involved', async (t) => {
  const backend = await boot('paper-changelog-');
  t.after(async () => {
    await backend.closeDb();
  });

  const untested = [];

  for (const table of REPLICATED) {
    const pk = await primaryKeyOf(backend, table);
    assert.ok(pk, `${table} has a primary key to identify rows by`);

    const existing = await backend.get(`SELECT COUNT(*) AS c FROM ${table}`);

    // --- INSERT ---
    const before = await backend.get('SELECT COALESCE(MAX(id), 0) AS head FROM changelog');
    const clonedId = existing.c
        ? await cloneRow(backend, table, pk)
        : await minimalRow(backend, table, pk);
    if (clonedId === null) {
      untested.push(table);
      continue;
    }

    let logged = await backend.all(
      'SELECT table_name, record_id, event_type FROM changelog WHERE id > ? ORDER BY id',
      [before.head],
    );
    let mine = logged.filter((row) => row.table_name === table);
    assert.equal(mine.length, 1, `${table}: one INSERT logged, got ${JSON.stringify(mine)}`);
    assert.equal(mine[0].event_type, 'INSERT');
    assert.equal(String(mine[0].record_id), String(clonedId), `${table}: logged the new row's key`);

    // --- UPDATE ---
    const beforeUpdate = await backend.get('SELECT COALESCE(MAX(id), 0) AS head FROM changelog');
    await backend.run(`UPDATE ${table} SET "${pk}" = "${pk}" WHERE "${pk}" = ?`, [clonedId]);
    logged = await backend.all(
      'SELECT table_name, record_id, event_type FROM changelog WHERE id > ? ORDER BY id',
      [beforeUpdate.head],
    );
    mine = logged.filter((row) => row.table_name === table);
    assert.equal(mine.length, 1, `${table}: one UPDATE logged`);
    assert.equal(mine[0].event_type, 'UPDATE');

    // --- DELETE ---
    const beforeDelete = await backend.get('SELECT COALESCE(MAX(id), 0) AS head FROM changelog');
    await backend.run(`DELETE FROM ${table} WHERE "${pk}" = ?`, [clonedId]);
    logged = await backend.all(
      'SELECT table_name, record_id, event_type FROM changelog WHERE id > ? ORDER BY id',
      [beforeDelete.head],
    );
    mine = logged.filter((row) => row.table_name === table);
    assert.equal(mine.length, 1, `${table}: one DELETE logged`);
    assert.equal(mine[0].event_type, 'DELETE');
    assert.equal(String(mine[0].record_id), String(clonedId), `${table}: logged the removed row's key`);
  }

  // Stated rather than silently skipped: a table with no seeded rows is not
  // evidence that its triggers work.
  assert.deepEqual(untested, [], `these tables had no row to clone: ${untested.join(', ')}`);
});

test('all 51 triggers exist, so no table is quietly unreplicated', async (t) => {
  const backend = await boot('paper-changelog-exist-');
  t.after(async () => {
    await backend.closeDb();
  });

  const rows = await backend.all(
    "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'trg_changelog_%'",
  );
  const present = new Set(rows.map((row) => row.name));

  const missing = [];
  for (const table of REPLICATED) {
    for (const suffix of ['ai', 'au', 'ad']) {
      const name = `trg_changelog_${table}_${suffix}`;
      if (!present.has(name)) missing.push(name);
    }
  }
  assert.deepEqual(missing, [], `missing triggers: ${missing.join(', ')}`);
  assert.equal(present.size, REPLICATED.length * 3);
});

test('a wipe removes the triggers and puts them back', async (t) => {
  // Protection a reset removes and does not restore is protection that stops
  // existing after the first reset.
  const backend = await boot('paper-changelog-reset-');
  t.after(async () => {
    await backend.closeDb();
  });

  // resetAndSeedDemoData wipes and reseeds, which is the path that drops the
  // triggers — the same one a factory reset takes.
  await backend.resetAndSeedDemoData();
  const rows = await backend.all(
    "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'trg_changelog_%'",
  );
  assert.equal(
    rows.length,
    REPLICATED.length * 3,
    'every changelog trigger is back after a factory reset',
  );

  const derived = await backend.all(
    "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'trg_derived_%'",
  );
  assert.ok(
    derived.length > 0,
    'and so are the derived-field triggers — restoring one family without the '
      + 'other would leave derived values silently stale after the first reset',
  );

  // And they work afterwards, which is the thing that actually matters.
  const before = await backend.get('SELECT COALESCE(MAX(id), 0) AS head FROM changelog');
  const stamp = new Date().toISOString();
  await backend.run(
    "INSERT INTO clients (name, created_at, updated_at) VALUES ('Post Reset Co', ?, ?)",
    [stamp, stamp],
  );
  const after = await backend.all(
    "SELECT table_name, event_type FROM changelog WHERE id > ? AND table_name = 'clients'",
    [before.head],
  );
  assert.equal(after.length, 1);
  assert.equal(after[0].event_type, 'INSERT');
});

test('a write nobody announced still reaches a listening client', async (t) => {
  // The half triggers cannot do on their own. A trigger writes the changelog
  // but cannot notify Node, so the live stream tails the table instead of being
  // emitted alongside each write. Without this, a trigger-only change would sit
  // in the log until somebody reconnected — correct, but not realtime, and the
  // whole point of the changelog is that Machine B sees Machine A's edit.
  const backend = await boot('paper-changelog-push-');
  t.after(async () => {
    await backend.closeDb();
  });

  const seen = [];
  const listener = (event) => seen.push(event);
  backend.changeEmitter.on('table-change', listener);
  t.after(() => backend.changeEmitter.off('table-change', listener));

  // Straight at the database: no route, no logChange, nothing that knows a
  // notification is expected.
  await backend.run(
    "UPDATE materials SET name = name || '' WHERE id = (SELECT MIN(id) FROM materials)",
  );
  await backend.drainChangelog();

  const materials = seen.filter((event) => event.table === 'materials');
  assert.equal(materials.length, 1, `delivered: ${JSON.stringify(seen)}`);
  assert.equal(materials[0].eventType, 'UPDATE');
  assert.ok(Number(materials[0].id) > 0, 'carries the cursor position to resume from');
});

test('draining twice does not deliver the same change twice', async (t) => {
  // A client that received an event and then received it again would refetch
  // for nothing; one that advanced its cursor past an undelivered event would
  // miss it forever. The cursor is what separates those.
  const backend = await boot('paper-changelog-once-');
  t.after(async () => {
    await backend.closeDb();
  });

  const seen = [];
  const listener = (event) => seen.push(event);
  backend.changeEmitter.on('table-change', listener);
  t.after(() => backend.changeEmitter.off('table-change', listener));

  await backend.run(
    "UPDATE clients SET name = name || '' WHERE id = (SELECT MIN(id) FROM clients)",
  );
  await backend.drainChangelog();
  const afterFirst = seen.length;
  await backend.drainChangelog();

  assert.equal(seen.length, afterFirst, 'the second drain had nothing new to say');
});

test('a change is announced on the row it is VISIBLE on, not only where it happened', async (t) => {
  // The dangerous class, and the reason 040 alone is not enough.
  //
  // Several things the UI shows are derived from a different table than the row
  // carrying them. rowToItemDto reads EIGHT other tables. Change one of those
  // and the displayed value goes stale while the carrying row never changes —
  // so no 040 trigger fires, no delta is sent, and a replica serves the old
  // value indefinitely. That is invisible from inside the app.
  const backend = await boot('paper-derived-');
  t.after(async () => {
    await backend.closeDb();
  });

  const head = async () => {
    const row = await backend.get('SELECT COALESCE(MAX(id), 0) AS h FROM changelog');
    return row.h;
  };
  const announced = async (afterId, table) => backend.all(
    'SELECT record_id FROM changelog WHERE id > ? AND table_name = ?',
    [afterId, table],
  );

  // 1. A variation node edit must announce its ITEM: the tree is nested inside
  //    the item payload (server.js:2814), so the item's copy is now wrong.
  const node = await backend.get('SELECT id, item_id FROM item_variation_nodes LIMIT 1');
  assert.ok(node, 'the seed has a variation node');
  let mark = await head();
  await backend.run('UPDATE item_variation_nodes SET name = name WHERE id = ?', [node.id]);
  let rows = await announced(mark, 'items');
  assert.ok(
    rows.some((row) => Number(row.record_id) === Number(node.item_id)),
    'editing a variation announces the item that embeds it',
  );

  // 2. A run completing must announce the ORDER LINE it is assigned to: the
  //    line's status is COALESCEd from its runs, so it changed without the
  //    order_items row changing.
  const assignment = await backend.get(
    'SELECT order_item_id, pipeline_run_id FROM order_pipeline_assignments LIMIT 1',
  );
  assert.ok(assignment, 'the seed assigns a run to an order line');
  mark = await head();
  await backend.run("UPDATE pipeline_runs SET status = 'completed' WHERE id = ?", [
    assignment.pipeline_run_id,
  ]);
  rows = await announced(mark, 'order_items');
  assert.ok(
    rows.some((row) => Number(row.record_id) === Number(assignment.order_item_id)),
    'a run completing announces the order line whose status it decides',
  );

  // 3. A challan line must announce its CHALLAN: lineCount, totalQty and
  //    totalWeight on the list row are summed from the lines.
  const stamp = '2026-08-29T00:00:00.000Z';
  const item = await backend.get('SELECT id FROM items LIMIT 1');
  const challan = await backend.run(
    `INSERT INTO delivery_challans (challan_no, date, customer_name, type, status,
                                    maintain_stocks, created_at, updated_at)
     VALUES ('DERIVED-DC-1', ?, 'C', 'delivery', 'draft', 0, ?, ?)`,
    [stamp, stamp, stamp],
  );
  mark = await head();
  await backend.run(
    `INSERT INTO delivery_challan_items (
       challan_id, line_no, particulars, quantity_pcs, weight, item_id,
       variation_leaf_node_id, variation_path_node_ids_json, sheet_weights_json,
       created_at, updated_at, factor_to_primary_at_creation
     ) VALUES (?, 1, 'L', 3, 0, ?, 0, '[]', '[]', ?, ?, 1)`,
    [challan.lastID, item.id, stamp, stamp],
  );
  rows = await announced(mark, 'delivery_challans');
  assert.ok(
    rows.some((row) => Number(row.record_id) === Number(challan.lastID)),
    'adding a line announces the challan whose totals it changes',
  );
});

test('cancelling a challan gives the quantity back to its order lines', async (t) => {
  // An order line shows total_delivered_qty summed over its dispatched lines,
  // but only from challans that are not cancelled. So cancelling one changes
  // what every order line it touched displays, while writing no
  // delivery_challan_items row and no order_items row.
  //
  // The symptom users notice: "delivered 300 of 500" that never gives the 300
  // back after the dispatch is cancelled.
  const backend = await boot('paper-cancel-');
  t.after(async () => {
    await backend.closeDb();
  });

  const stamp = '2026-08-29T00:00:00.000Z';
  const orderLine = await backend.get('SELECT id, item_id FROM order_items LIMIT 1');
  const challan = await backend.run(
    `INSERT INTO delivery_challans (challan_no, date, customer_name, type, status,
                                    maintain_stocks, created_at, updated_at)
     VALUES ('CANCEL-DC-1', ?, 'C', 'delivery', 'issued', 0, ?, ?)`,
    [stamp, stamp, stamp],
  );
  await backend.run(
    `INSERT INTO delivery_challan_items (
       challan_id, line_no, particulars, quantity_pcs, weight, item_id, order_item_id,
       variation_leaf_node_id, variation_path_node_ids_json, sheet_weights_json,
       created_at, updated_at, factor_to_primary_at_creation
     ) VALUES (?, 1, 'L', 5, 0, ?, ?, 0, '[]', '[]', ?, ?, 1)`,
    [challan.lastID, orderLine.item_id, orderLine.id, stamp, stamp],
  );

  const before = await backend.get('SELECT COALESCE(MAX(id), 0) AS h FROM changelog');
  await backend.run("UPDATE delivery_challans SET status = 'cancelled' WHERE id = ?", [
    challan.lastID,
  ]);

  const announced = await backend.all(
    "SELECT record_id FROM changelog WHERE id > ? AND table_name = 'order_items'",
    [before.h],
  );
  assert.ok(
    announced.some((row) => Number(row.record_id) === Number(orderLine.id)),
    'the order line whose delivered quantity just changed is announced',
  );
});

test('a client can catch up from a position, and is told when it cannot', async (t) => {
  // The endpoint a replica calls at launch. The SSE stream replays too, but a
  // client catching up wants a request that ends rather than a connection it
  // must decide when to stop reading.
  const { mkdtempSync: mk } = require('node:fs');
  const http = require('node:http');
  const backend = await boot('paper-changes-');
  const server = http.createServer(backend.app);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => {
    await new Promise((resolve) => server.close(resolve));
    await backend.closeDb();
  });
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  const login = await fetch(`${baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'changelog@paper.test', password: 'OwnerPass1234' }),
  });
  const headers = { Authorization: `Bearer ${(await login.json()).token}` };

  await backend.run("UPDATE items SET name = name WHERE id = (SELECT MIN(id) FROM items)");

  const page = await (await fetch(`${baseUrl}/api/changes?since=0&limit=5`, { headers })).json();
  assert.equal(page.success, true);
  assert.equal(page.changes.length, 5, 'the limit is honoured');
  assert.equal(page.hasMore, true, 'and it says there is more rather than looking complete');
  assert.deepEqual(
    Object.keys(page.changes[0]).sort(),
    ['event_type', 'id', 'record_id', 'table_name'],
    'the shape the client parses',
  );

  // Paging forward reaches the end and says so.
  const head = page.head;
  const last = await (await fetch(`${baseUrl}/api/changes?since=${head}`, { headers })).json();
  assert.equal(last.changes.length, 0);
  assert.equal(last.hasMore, false);

  // The floor is what lets a client notice its cursor has fallen off the end.
  // Replaying from the oldest surviving row would silently skip everything in
  // between; knowing the floor means it can take a fresh snapshot instead.
  assert.ok(page.oldestAvailable > 0, 'the oldest surviving position is stated');
  assert.ok(page.head >= page.oldestAvailable);
});
