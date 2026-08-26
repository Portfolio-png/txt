const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// "Steel / MS" was one row doing two jobs. On a shop floor it is called MS, so
// that is what the list says now.
//
// The interesting part is not the rename but what it must not break: variation
// values point at a material type **by id**. A delete-and-reinsert would leave
// every value that named it pointing at nothing, which the app draws as
// "Material missing" on items that were perfectly fine. So the migration renames
// in place, and this proves the links survive.

async function boot(prefix, email) {
  const tempDir = mkdtempSync(path.join(tmpdir(), prefix));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = email;
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  return backend;
}

test('the material list offers MS and no longer offers Steel / MS', async () => {
  const backend = await boot('paper-ms-', 'ms@paper.local');

  const ms = await backend.get(
    "SELECT * FROM material_types WHERE name = 'MS' COLLATE NOCASE",
  );
  assert.ok(ms, 'MS is in the list');
  assert.equal(Number(ms.density_g_cm3), 7.85, 'mild steel is 7.85 g/cm³');
  assert.equal(ms.category, 'metal');

  const old = await backend.get(
    "SELECT * FROM material_types WHERE name = 'Steel / MS' COLLATE NOCASE",
  );
  assert.equal(old, undefined, 'Steel / MS is gone');

  // One row, not two: the rename must not have left a duplicate behind.
  const count = await backend.get(
    "SELECT COUNT(*) AS n FROM material_types WHERE name = 'MS' COLLATE NOCASE",
  );
  assert.equal(count.n, 1);
});

test('a variation value linked to the old row still resolves after the rename', async () => {
  // The case the rename exists to protect. Simulated by putting the old row
  // back, pointing a variation value at it, and running the migration again —
  // which is what an existing database looks like when it upgrades.
  const backend = await boot('paper-ms-link-', 'ms2@paper.local');

  const now = new Date().toISOString();
  await backend.run(
    `INSERT INTO material_types (name, density_g_cm3, category, notes, created_at, updated_at)
     VALUES ('Steel / MS', 7.85, 'metal', 'legacy row', ?, ?)`,
    [now, now],
  );
  const legacy = await backend.get(
    "SELECT * FROM material_types WHERE name = 'Steel / MS' COLLATE NOCASE",
  );

  const item = await backend.get('SELECT * FROM items LIMIT 1');
  const node = await backend.run(
    `INSERT INTO item_variation_nodes
      (item_id, parent_node_id, kind, name, code, display_name, input_type,
       name_join, position, material_type_id, is_archived, created_at, updated_at)
     VALUES (?, NULL, 'value', 'Mild Steel', 'MS', 'Mild Steel', 'Text', '',
             0, ?, 0, ?, ?)`,
    [item.id, legacy.id, now, now],
  );

  // Re-run the migration the way an upgrade would.
  const sql = require('node:fs').readFileSync(
    path.join(__dirname, '..', 'migrations', '037-material-ms.sql'),
    'utf8',
  );
  for (const statement of sql.split(';')) {
    if (statement.trim().replace(/^--.*$/gm, '').trim()) {
      await backend.run(statement);
    }
  }

  // The value still points at a material type, and that type is MS.
  const linked = await backend.get(
    `SELECT mt.name, mt.density_g_cm3
     FROM item_variation_nodes n
     JOIN material_types mt ON mt.id = n.material_type_id
     WHERE n.id = ?`,
    [node.lastID],
  );
  assert.ok(linked, 'the link survived — it did not become "Material missing"');
  assert.equal(linked.name, 'MS');
  assert.equal(Number(linked.density_g_cm3), 7.85, 'and still weighs the same');

  const leftovers = await backend.get(
    "SELECT COUNT(*) AS n FROM material_types WHERE name = 'Steel / MS' COLLATE NOCASE",
  );
  assert.equal(leftovers.n, 0, 'no Steel / MS left behind');
});
