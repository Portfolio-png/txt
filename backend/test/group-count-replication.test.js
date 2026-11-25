const assert = require('node:assert/strict');
const path = require('node:path');
const test = require('node:test');
const { makeTempDir } = require('./helpers/temp-dir');

// A group's "N items" is derived from items, so a change to an item has to be
// announced on its GROUP too, or every replica keeps the old count. Found
// 2026-11-25: a rivet added to Rivets, and Rivets still read "0 items" in the
// app while its own window listed the rivet. The fix is three derived triggers
// (migrations/041), which initDb now makes sure of on every boot.

async function boot() {
  const tempDir = makeTempDir('paper-group-count-');
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  return backend;
}

async function groupAnnouncements(backend, sinceId) {
  const rows = await backend.all(
    "SELECT record_id FROM changelog WHERE table_name = 'groups' AND id > ? ORDER BY id",
    [sinceId],
  );
  return rows.map((row) => Number(row.record_id));
}

async function lastChangelogId(backend) {
  return Number((await backend.get('SELECT COALESCE(MAX(id), 0) AS id FROM changelog')).id);
}

test('adding, moving, archiving and deleting an item announces its group', async () => {
  const backend = await boot();
  const rivets = await backend.get("SELECT id, unit_id FROM groups WHERE system_key = 'raw_materials.rivets'");
  const springs = await backend.get("SELECT id FROM groups WHERE system_key = 'raw_materials.springs'");
  const now = new Date().toISOString();

  let mark = await lastChangelogId(backend);
  const { lastID: itemId } = await backend.run(
    `INSERT INTO items (name, display_name, group_id, unit_id, created_at, updated_at)
     VALUES ('Copper Rivet 3 X 1 / 2 X 2 Flat', 'Copper Rivet 3 X 1 / 2 X 2 Flat', ?, ?, ?, ?)`,
    [rivets.id, rivets.unit_id, now, now],
  );
  assert.ok((await groupAnnouncements(backend, mark)).includes(rivets.id), 'added: its group');

  mark = await lastChangelogId(backend);
  await backend.run('UPDATE items SET group_id = ? WHERE id = ?', [springs.id, itemId]);
  const moved = await groupAnnouncements(backend, mark);
  assert.ok(moved.includes(springs.id) && moved.includes(rivets.id), 'moved: both groups');

  mark = await lastChangelogId(backend);
  await backend.run("UPDATE items SET name = 'renamed' WHERE id = ?", [itemId]);
  assert.deepEqual(await groupAnnouncements(backend, mark), [], 'a rename does not touch the count');

  mark = await lastChangelogId(backend);
  await backend.run('UPDATE items SET is_archived = 1 WHERE id = ?', [itemId]);
  assert.deepEqual(await groupAnnouncements(backend, mark), [springs.id], 'archived: its group');

  mark = await lastChangelogId(backend);
  await backend.run('DELETE FROM items WHERE id = ?', [itemId]);
  assert.deepEqual(await groupAnnouncements(backend, mark), [springs.id], 'deleted: its group');
});

test('a changelog trigger missing from an existing database comes back at boot', async () => {
  const backend = await boot();
  await backend.run('DROP TRIGGER IF EXISTS trg_derived_items_groups_ai');
  assert.equal(
    (await backend.get("SELECT COUNT(*) AS n FROM sqlite_master WHERE name = 'trg_derived_items_groups_ai'")).n,
    0,
  );
  await backend.initDb();
  assert.equal(
    (await backend.get("SELECT COUNT(*) AS n FROM sqlite_master WHERE name = 'trg_derived_items_groups_ai'")).n,
    1,
  );
});
