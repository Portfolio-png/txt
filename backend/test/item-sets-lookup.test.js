const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// Which sets hold a part, asked from the part's side.
//
// Nothing else answers it: /usage covers orders, challans, BOM requirements,
// materials and group links, and set lines are in none of them. One row per
// LINE, because a set can hold the same part at two variations and each is its
// own line with its own quantity.

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
    server.on('error', reject);
  });
}

function closeServer(server) {
  return new Promise((resolve, reject) =>
    server.close((error) => (error ? reject(error) : resolve())),
  );
}

test('a part reports the sets that hold it, one row per line', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-item-sets-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'item-sets@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const { token } = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'item-sets@paper.local',
        password: 'OwnerPass1234',
      }),
    }).then((r) => r.json());
    const headers = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    };

    const items = await fetch(`${baseUrl}/api/items`, { headers }).then((r) => r.json());
    // A part with a variation tree, so one set can hold two of its leaves.
    const varied = items.items.find(
      (item) => !item.isArchived && (item.variationTree || []).length > 0,
    );
    assert.ok(varied, 'the seed has an item with variations');
    const leaves = [];
    const walk = (nodes) => {
      for (const node of nodes || []) {
        if (node.kind === 'value' && (node.children || []).length === 0) leaves.push(node.id);
        walk(node.children);
      }
    };
    walk(varied.variationTree);
    assert.ok(leaves.length >= 2, 'and at least two leaves to file');

    const plain = items.items.find(
      (item) => !item.isArchived && (item.variationTree || []).length === 0,
    ) || varied;

    const made = await fetch(`${baseUrl}/api/inventory/sets`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        name: 'Lookup Kit',
        groupId: varied.groupId,
        lines: [
          { itemId: varied.id, variationLeafNodeId: leaves[0], quantity: 2, position: 0 },
          { itemId: varied.id, variationLeafNodeId: leaves[1], quantity: 5, position: 1 },
        ],
      }),
    }).then((r) => r.json());
    assert.ok(made.set, JSON.stringify(made));
    await backend.run("UPDATE inventory_sets SET photo_url = 'https://example.test/kit.png' WHERE id = ?", [
      made.set.id,
    ]);

    const rows = await fetch(`${baseUrl}/api/items/${varied.id}/sets`, { headers })
      .then((r) => r.json())
      .then((body) => body.sets);

    const mine = rows.filter((row) => row.setId === made.set.id);
    assert.equal(mine.length, 2, 'one row per line, not per set');
    assert.deepEqual(
      mine.map((row) => row.quantity).sort((a, b) => a - b),
      [2, 5],
    );
    assert.ok(mine.every((row) => row.setLineCount === 2), 'the SET\'s line count');
    assert.ok(mine.every((row) => row.photoUrl === 'https://example.test/kit.png'));
    assert.ok(mine.every((row) => row.groupId === varied.groupId));
    assert.ok(
      mine.every((row) => row.variationPathLabel && row.variationPathLabel !== 'Base item'),
      'each row names the variation it is filed at',
    );

    // A production-minted set is history with a stock ledger behind it, not
    // something to hand-edit from a part.
    await backend.run(
      `INSERT INTO inventory_sets (name, created_at, updated_at, origin_run_id, origin_node_id, produced_at, is_temporary)
       VALUES ('Temporary · Run', ?, ?, 'run-9', 'node-9', ?, 1)`,
      [new Date().toISOString(), new Date().toISOString(), new Date().toISOString()],
    );
    const tempSet = await backend.get("SELECT id FROM inventory_sets WHERE origin_run_id = 'run-9'");
    await backend.run(
      'INSERT INTO inventory_set_lines (set_id, item_id, variation_leaf_node_id, quantity, position) VALUES (?, ?, NULL, 1, 0)',
      [tempSet.id, plain.id],
    );
    const plainRows = await fetch(`${baseUrl}/api/items/${plain.id}/sets`, { headers })
      .then((r) => r.json())
      .then((body) => body.sets);
    assert.ok(
      !plainRows.some((row) => row.setId === tempSet.id),
      'run output is not offered as membership',
    );

    // An item nobody filed, and an item that does not exist, both answer with
    // an empty list rather than an error.
    const none = await fetch(`${baseUrl}/api/items/999999/sets`, { headers }).then((r) => r.json());
    assert.equal(none.success, true);
    assert.deepEqual(none.sets, []);
  } finally {
    await closeServer(server);
    await backend.closeDb();
  }
});
