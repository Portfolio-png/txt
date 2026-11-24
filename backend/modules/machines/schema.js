'use strict';

// ---------------------------------------------------------------------------
// The machines module's tables, as initDb in server.js created them until
// 2026-11-19: the same statements, in the same order, moved here whole.
// `ensureColumnExists` adds a column an older file lacks.
// ---------------------------------------------------------------------------

const { ensureColumnExists: ensureColumn } = require('../../kernel/schema-kit');

async function createSchema({ run, all, get }) {
  const ensureColumnExists = (table, column, definition) => ensureColumn({ run, all }, table, column, definition);

  // --- Tables whose shape an older file may need rebuilt (moved 2026-11-19,
  // B37). Their rebuild, CREATE, columns and indexes run here in the order
  // they stood in initDb; triggers, data backfills and seeds stay there.
  await run(`
    CREATE TABLE IF NOT EXISTS machines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      asset_id TEXT NOT NULL UNIQUE,
      barcode TEXT NOT NULL DEFAULT '',
      primary_photo_url TEXT,
      group_id INTEGER REFERENCES groups(id),
      make_model TEXT,
      serial_number TEXT,
      location TEXT,
      installation_date TEXT,
      status TEXT NOT NULL,
      report_output_per_hour REAL,
      setup_minutes REAL,
      labor_count REAL,
      power_kw REAL,
      report_notes TEXT NOT NULL DEFAULT '',
      custom_properties TEXT NOT NULL DEFAULT '[]',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);
  // Machine barcode: unique system-generated scan code (defaults to asset_id
  // when unset, minted on create/update below).
  await ensureColumnExists('machines', 'barcode', "TEXT NOT NULL DEFAULT ''");
  // D.O.M. as a date, picked on a calendar (2026-11-24): 'YYYY-MM-DD'. Its
  // year is kept in manufactured_year too, which everything older reads.
  await ensureColumnExists('machines', 'manufactured_on', 'TEXT');

  await ensureColumnExists('machines', 'report_output_per_hour', 'REAL');
  await ensureColumnExists('machines', 'setup_minutes', 'REAL');
  await ensureColumnExists('machines', 'labor_count', 'REAL');
  await ensureColumnExists('machines', 'power_kw', 'REAL');
  await ensureColumnExists('machines', 'report_notes', "TEXT NOT NULL DEFAULT ''");
}

module.exports = { createSchema };
