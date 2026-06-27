/**
 * Enhancement 2 — Combination Groups for variant sets.
 *
 * Adds:
 *  - groups.group_structure : 'hierarchical' (existing nestable groups, default)
 *    or 'combination' (flat groups that hold a curated list of item variants).
 *  - groups.description      : optional free-text, captured when a combination
 *    group is created from the variant spawning workflow.
 *  - group_item_memberships  : many-to-many join enabling DUAL MEMBERSHIP. An
 *    item keeps its primary hierarchical group via items.group_id and may also
 *    belong to one or more combination groups through this table. Adding a
 *    combination membership never touches items.group_id, so the item's
 *    hierarchical placement is preserved.
 *
 * Written as a JS migration so the column additions are idempotent (SQLite has
 * no ALTER TABLE ... ADD COLUMN IF NOT EXISTS), keeping it safe to apply on
 * databases where a newer server build may already have added a column via the
 * runtime ensureColumnExists() helper.
 */

function tableInfo(db, table) {
  return new Promise((resolve, reject) => {
    db.all(`PRAGMA table_info(${table})`, (err, rows) => {
      if (err) return reject(err);
      resolve(rows || []);
    });
  });
}

function exec(db, sql) {
  return new Promise((resolve, reject) => {
    db.exec(sql, (err) => (err ? reject(err) : resolve()));
  });
}

async function addColumnIfMissing(db, table, column, definition) {
  const columns = await tableInfo(db, table);
  if (!columns.some((c) => c.name === column)) {
    await exec(db, `ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
  }
}

async function up(db) {
  await addColumnIfMissing(
    db,
    'groups',
    'group_structure',
    "TEXT NOT NULL DEFAULT 'hierarchical'",
  );
  await addColumnIfMissing(db, 'groups', 'description', "TEXT NOT NULL DEFAULT ''");

  await exec(
    db,
    `
    CREATE TABLE IF NOT EXISTS group_item_memberships (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(group_id, item_id)
    );
    CREATE INDEX IF NOT EXISTS idx_group_item_memberships_group
      ON group_item_memberships(group_id);
    CREATE INDEX IF NOT EXISTS idx_group_item_memberships_item
      ON group_item_memberships(item_id);
    `,
  );
}

module.exports = { up };
