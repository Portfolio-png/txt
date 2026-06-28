/**
 * Internal challans — a free-text purpose for assets moving within the company
 * (production consumption, transfers). The existing `purpose` column is an
 * enum (trading | manufacturing | jobWork) used by delivery/reception challans,
 * so a separate nullable free-text column is added instead of overloading it.
 *
 * Idempotent JS migration (no ALTER ... ADD COLUMN IF NOT EXISTS in SQLite).
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
    'delivery_challans',
    'internal_purpose',
    "TEXT NOT NULL DEFAULT ''",
  );
}

module.exports = { up };
