/**
 * Enhancement 3 — Measurable property values with unit assignment.
 *
 * Adds to the variation tree (item_variation_nodes):
 *  - is_measurable : on PROPERTY nodes — when 1, the property's value leaves
 *    carry a physical quantity + unit (e.g. "100 g").
 *  - unit_id       : on VALUE (leaf) nodes — the unit intrinsic to that specific
 *    variation value. Nullable; only set for leaves under a measurable property.
 *
 * And a junction listing the units allowed for a measurable property, used to
 * populate the unit dropdowns in the variation creation / on-the-fly flows:
 *  - property_value_units(property_node_id -> unit_id)
 *
 * JS migration so column adds are idempotent (no ALTER ... ADD COLUMN IF NOT
 * EXISTS in SQLite), matching migration 002's style.
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
    'item_variation_nodes',
    'is_measurable',
    'INTEGER NOT NULL DEFAULT 0',
  );
  await addColumnIfMissing(db, 'item_variation_nodes', 'unit_id', 'INTEGER');

  await exec(
    db,
    `
    CREATE TABLE IF NOT EXISTS property_value_units (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      property_node_id INTEGER NOT NULL REFERENCES item_variation_nodes(id) ON DELETE CASCADE,
      unit_id INTEGER NOT NULL REFERENCES units(id),
      created_at TEXT NOT NULL,
      UNIQUE(property_node_id, unit_id)
    );
    CREATE INDEX IF NOT EXISTS idx_property_value_units_property
      ON property_value_units(property_node_id);
    `,
  );
}

module.exports = { up };
