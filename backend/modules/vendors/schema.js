'use strict';

// ---------------------------------------------------------------------------
// The vendors module's tables, as initDb in server.js created them until
// 2026-11-19: the same statements, in the same order, moved here whole.
// `ensureColumnExists` adds a column an older file lacks.
// ---------------------------------------------------------------------------

const { ensureColumnExists: ensureColumn } = require('../../kernel/schema-kit');

async function createSchema({ run, all, get }) {
  const ensureColumnExists = (table, column, definition) => ensureColumn({ run, all }, table, column, definition);

  // --- Tables whose shape an older file may need rebuilt (moved 2026-11-19,
  // B37). Their rebuild, CREATE, columns and indexes run here in the order
  // they stood in initDb; triggers, data backfills and seeds stay there.
  try { await run("ALTER TABLE vendors ADD COLUMN logo_url TEXT DEFAULT ''"); } catch(e){}
  try { await run("ALTER TABLE vendors ADD COLUMN photo_url TEXT DEFAULT ''"); } catch(e){}

  await run(`
    CREATE TABLE IF NOT EXISTS vendors (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      alias TEXT DEFAULT '',
      gst_number TEXT DEFAULT '',
      address TEXT DEFAULT '',
      contact_name TEXT DEFAULT '',
      phone TEXT DEFAULT '',
      email TEXT DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      supplies_raw_material INTEGER NOT NULL DEFAULT 0,
      does_outsourcing INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await ensureColumnExists('vendors', 'alias', "TEXT DEFAULT ''");
  await ensureColumnExists('vendors', 'gst_number', "TEXT DEFAULT ''");
  await ensureColumnExists('vendors', 'address', "TEXT DEFAULT ''");
  await ensureColumnExists('vendors', 'contact_name', "TEXT DEFAULT ''");
  await ensureColumnExists('vendors', 'phone', "TEXT DEFAULT ''");
  await ensureColumnExists('vendors', 'email', "TEXT DEFAULT ''");
  await ensureColumnExists('vendors', 'is_archived', 'INTEGER NOT NULL DEFAULT 0');
  // What a vendor is for (2026-11-24): raw material, outsourced work, or
  // both. Ticks on the vendor form; an older vendor is neither until ticked.
  await ensureColumnExists('vendors', 'supplies_raw_material', 'INTEGER NOT NULL DEFAULT 0');
  await ensureColumnExists('vendors', 'does_outsourcing', 'INTEGER NOT NULL DEFAULT 0');
}

module.exports = { createSchema };
