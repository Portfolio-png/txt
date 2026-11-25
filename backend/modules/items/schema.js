'use strict';

// ---------------------------------------------------------------------------
// The items module's tables, as initDb in server.js created them until
// 2026-11-19: the same statements, in the same order, moved here whole.
// `ensureColumnExists` adds a column an older file lacks. Tables this module
// owns that a rebuild in server.js still reshapes are not here yet.
//
//   group_item_memberships
//   item_attachments
//   item_bom_lines
//   item_dies
//   item_machines
//   item_property_schema
//   item_unit_conversions
//   item_variation_dimensions
//   item_variation_nodes
//   item_variation_values
//   item_variations
// ---------------------------------------------------------------------------

const { ensureColumnExists: ensureColumn } = require('../../kernel/schema-kit');

async function createSchema({ run, all, get }) {
  const ensureColumnExists = (table, column, definition) => ensureColumn({ run, all }, table, column, definition);
  await run(`
    CREATE TABLE IF NOT EXISTS group_item_memberships (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(group_id, item_id)
    );
  `);

  await run('CREATE INDEX IF NOT EXISTS idx_group_item_memberships_group ON group_item_memberships(group_id)');

  await run('CREATE INDEX IF NOT EXISTS idx_group_item_memberships_item ON group_item_memberships(item_id)');

  await run(`
    CREATE TABLE IF NOT EXISTS item_unit_conversions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      unit_id INTEGER NOT NULL REFERENCES units(id),
      factor_to_primary REAL NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(item_id, unit_id)
    )
  `);

  await run(
    'CREATE INDEX IF NOT EXISTS idx_item_unit_conversions_item_id ON item_unit_conversions(item_id)',
  );

  // Extra named files on an item master, beyond the photo and the CAD file.
  // Same rule as cad_file_key: the permanent object key is stored, never a
  // presigned URL.
  await run(`
    CREATE TABLE IF NOT EXISTS item_attachments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      label TEXT NOT NULL DEFAULT '',
      object_key TEXT NOT NULL,
      file_name TEXT NOT NULL DEFAULT '',
      position INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(
    'CREATE INDEX IF NOT EXISTS idx_item_attachments_item_id ON item_attachments(item_id)',
  );

  await run(`
    CREATE TABLE IF NOT EXISTS item_machines (
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      machine_id INTEGER NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      PRIMARY KEY (item_id, machine_id)
    )
  `);

  // Who a part was developed for, ONE ROW PER COMPANY (2026-11-24): a part is
  // often quoted to several. Each deal has its own quotation, people and
  // recorded time; the development cost stays one figure on the item. The
  // flat items.developed_for_* columns and item_deal_contacts mirror the FIRST
  // deal (position 0), so every reader written for one deal keeps working.
  await run(`
    CREATE TABLE IF NOT EXISTS item_deals (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      kind TEXT NOT NULL DEFAULT 'client',
      client_id INTEGER,
      sub_contractor_id INTEGER,
      quotation_amount REAL,
      at TEXT,
      position INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
  `);
  await run('CREATE INDEX IF NOT EXISTS idx_item_deals_item ON item_deals(item_id, position)');
  await run(`
    CREATE TABLE IF NOT EXISTS item_deal_people (
      deal_id INTEGER NOT NULL REFERENCES item_deals(id) ON DELETE CASCADE,
      contact_id INTEGER NOT NULL,
      PRIMARY KEY (deal_id, contact_id)
    )
  `);

  // A raw-material item's spec (a rivet's dimensions …), one row per item;
  // see modules/items/rivets.js. spec_key makes the same spec twice
  // impossible; code is the shop's own code for it, unique when given.
  await run(`
    CREATE TABLE IF NOT EXISTS raw_material_specs (
      item_id INTEGER PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
      form_key TEXT NOT NULL,
      spec_key TEXT NOT NULL,
      code TEXT NOT NULL DEFAULT '',
      values_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);
  await run(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_raw_material_specs_spec ON raw_material_specs(form_key, spec_key)',
  );
  await run(
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_raw_material_specs_code ON raw_material_specs(form_key, code COLLATE NOCASE) WHERE code != ''",
  );

  // What a vendor charges for an item. Integer micro-rupees, so a rivet at
  // ₹0.035 a piece is exact; basis is piece, hundred, thousand or kg. The
  // vendor is asked of the vendors module, not joined.
  await run(`
    CREATE TABLE IF NOT EXISTS item_vendor_prices (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      vendor_id INTEGER NOT NULL,
      price_micro_rupees INTEGER NOT NULL CHECK (price_micro_rupees >= 0),
      basis TEXT NOT NULL DEFAULT 'piece',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(item_id, vendor_id, basis)
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS item_dies (
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      die_id INTEGER NOT NULL REFERENCES dies(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      PRIMARY KEY (item_id, die_id)
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS item_property_schema (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      property_key TEXT NOT NULL,
      display_name TEXT NOT NULL,
      input_type TEXT NOT NULL DEFAULT 'Text',
      mandatory INTEGER NOT NULL DEFAULT 0,
      unit_id INTEGER,
      unit_symbol TEXT,
      unit_label TEXT,
      source_type TEXT NOT NULL DEFAULT 'manual',
      source_group_id INTEGER,
      source_group_name TEXT,
      source_item_ids_json TEXT NOT NULL DEFAULT '[]',
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(item_id, property_key)
    )
  `);

  await run(
    'CREATE INDEX IF NOT EXISTS idx_item_property_schema_item_id ON item_property_schema(item_id)',
  );
  // In the order every read asks for, so a part's schema — or the whole list's
  // (Docs/benchmarks/2026-11-constrained-network-results.md) — is read off the
  // index without a sort.
  await run(
    'CREATE INDEX IF NOT EXISTS idx_item_property_schema_item_order ON item_property_schema(item_id, sort_order, id)',
  );

  await run(`
    CREATE TABLE IF NOT EXISTS item_bom_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      material_barcode TEXT NOT NULL,
      material_name TEXT DEFAULT '',
      quantity_per_unit REAL NOT NULL DEFAULT 1,
      wastage_percent REAL NOT NULL DEFAULT 0,
      unit_id INTEGER REFERENCES units(id),
      unit_symbol TEXT DEFAULT '',
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(item_id, material_barcode)
    )
  `);

  await run(
    'CREATE INDEX IF NOT EXISTS idx_item_bom_lines_item_id ON item_bom_lines(item_id, sort_order ASC, id ASC)',
  );

  await run(`
    CREATE TABLE IF NOT EXISTS item_variations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      name TEXT NOT NULL DEFAULT '',
      alias TEXT DEFAULT '',
      display_name TEXT NOT NULL,
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS item_variation_dimensions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      position INTEGER NOT NULL DEFAULT 0
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS item_variation_values (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      variation_id INTEGER NOT NULL REFERENCES item_variations(id) ON DELETE CASCADE,
      dimension_id INTEGER NOT NULL REFERENCES item_variation_dimensions(id) ON DELETE CASCADE,
      value TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS item_variation_nodes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      parent_node_id INTEGER REFERENCES item_variation_nodes(id) ON DELETE CASCADE CHECK (parent_node_id IS NULL OR parent_node_id > 0),
      kind TEXT NOT NULL,
      name TEXT NOT NULL,
      code TEXT NOT NULL DEFAULT '',
      display_name TEXT NOT NULL DEFAULT '',
      position INTEGER NOT NULL DEFAULT 0,
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await ensureColumnExists('item_unit_conversions', 'factor_to_primary', 'REAL NOT NULL DEFAULT 1');

  await ensureColumnExists('item_variations', 'alias', "TEXT DEFAULT ''");

  await ensureColumnExists('item_variations', 'display_name', "TEXT DEFAULT ''");

  await ensureColumnExists('item_variation_nodes', 'code', "TEXT NOT NULL DEFAULT ''");

  await ensureColumnExists('item_variation_nodes', 'name_join', "TEXT NOT NULL DEFAULT ''");
  // Every read of a part's tree is by item_id, and there was no index on it:
  // opening one part scanned every node of every part, and the item list
  // scanned and sorted them all.
  await run(
    'CREATE INDEX IF NOT EXISTS idx_item_variation_nodes_item ON item_variation_nodes(item_id, is_archived, parent_node_id, position)',
  );

  await ensureColumnExists('item_variation_nodes', 'input_type', "TEXT NOT NULL DEFAULT 'Text'");

  // Bootstrap parity with migration 035: a value node under a Material property
  // points at the material type it stands for, so the id travels with the
  // selection instead of only its name.
  await ensureColumnExists('item_variation_nodes', 'material_type_id', 'INTEGER');

  // Allowed range for 'Numeric' properties (migrations/028). NULL = unbounded.
  await ensureColumnExists('item_variation_nodes', 'numeric_min', 'REAL');

  await ensureColumnExists('item_variation_nodes', 'numeric_max', 'REAL');

  // --- Tables whose shape an older file may need rebuilt (moved 2026-11-19,
  // B37). Their rebuild, CREATE, columns and indexes run here in the order
  // they stood in initDb; triggers, data backfills and seeds stay there.
  try { await run("ALTER TABLE items ADD COLUMN default_pipeline_id TEXT DEFAULT NULL"); } catch(e){}
  try { await run("ALTER TABLE items ADD COLUMN base_item_id INTEGER REFERENCES items(id) ON DELETE CASCADE"); } catch(e){}

  // Migration for groups table to remove unit_id NOT NULL constraint
  try {
    // 1. Recover from a half-migrated state if a previous run crashed
    const tables = await all("SELECT name FROM sqlite_master WHERE type='table' AND name IN ('groups', 'groups_old_migration')");
    const hasGroups = tables.some(t => t.name === 'groups');
    const hasOldGroups = tables.some(t => t.name === 'groups_old_migration');

    if (hasOldGroups) {
      if (hasGroups) {
        // The migration finished creating 'groups' but crashed before dropping 'groups_old_migration'
        await run('DROP TABLE groups_old_migration');
        console.log('Cleaned up lingering groups_old_migration table from previous run.');
      } else {
        // The migration renamed 'groups' to 'groups_old_migration' but crashed before creating the new 'groups'
        await run('ALTER TABLE groups_old_migration RENAME TO groups');
        console.log('Recovered groups table from an interrupted migration run.');
      }
    }

    // 2. Perform the actual migration
    const tableInfo = await all("PRAGMA table_info(groups)");
    const unitIdCol = tableInfo.find(c => c.name === 'unit_id');
    if (unitIdCol && unitIdCol.notnull === 1) {
      console.log('Migrating groups table to remove NOT NULL constraint on unit_id...');
      // FK enforcement off so drop order doesn't matter (parents before children is fine)
      await run('PRAGMA foreign_keys = OFF');
      // legacy_alter_table = ON stops the RENAME from rewriting other tables'
      // FK references to `groups` into `groups_old_migration` (which would
      // dangle once the temp table is dropped).
      await run('PRAGMA legacy_alter_table = ON');
      await run('BEGIN TRANSACTION');
      await run('ALTER TABLE groups RENAME TO groups_old_migration');
      await run(`
        CREATE TABLE groups (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          group_type TEXT NOT NULL DEFAULT 'item',
          parent_group_id INTEGER REFERENCES groups(id),
          unit_id INTEGER REFERENCES units(id),
          is_archived INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      `);
      await run('INSERT INTO groups (id, name, parent_group_id, unit_id, is_archived, created_at, updated_at) SELECT id, name, parent_group_id, unit_id, is_archived, created_at, updated_at FROM groups_old_migration');
      await run('DROP TABLE groups_old_migration');
      await run('COMMIT');
      await run('PRAGMA legacy_alter_table = OFF');
      await run('PRAGMA foreign_keys = ON');
      console.log('Successfully migrated groups table.');
    }
  } catch (err) {
    await run('ROLLBACK').catch(() => {});
    await run('PRAGMA legacy_alter_table = OFF').catch(() => {});
    await run('PRAGMA foreign_keys = ON');
    console.error('Migration failed:', err);
  }

  // An item's stock. With variations it is kept per variation leaf. An item with
  // none keeps one figure for the whole item, under leaf 0, which is why the
  // leaf is not a foreign key: 0 names no node. A real leaf is checked on the
  // way in by assertValidStockVariationLeaf (the only write path), and a
  // trigger below removes a leaf's stock rows when the leaf is deleted.
  const variationStockColumns = `
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE CHECK (item_id > 0),
      variation_leaf_node_id INTEGER NOT NULL DEFAULT 0 CHECK (variation_leaf_node_id >= 0),
      quantity REAL NOT NULL DEFAULT 0 CHECK (quantity >= 0),
      location_id TEXT DEFAULT 'MAIN',
      variation_path_label TEXT DEFAULT '',
      variation_path_node_ids_json TEXT NOT NULL DEFAULT '[]',
      custom_variation_values_json TEXT DEFAULT '{}',
      updated_at TEXT DEFAULT (datetime('now')),
      UNIQUE(item_id, variation_leaf_node_id, location_id)`;
  await run(`CREATE TABLE IF NOT EXISTS variation_stock (${variationStockColumns})`);
  // A database made before whole-item stock still has the table that refuses
  // leaf 0. A CHECK cannot be altered in SQLite, so the table is rebuilt once
  // and its rows carried over. Nothing references this table.
  const oldStockTable = await get(
    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'variation_stock'",
  );
  // Two older shapes refuse leaf 0, and a database can have either: a CHECK that
  // the leaf is above zero, or the leaf as a foreign key into
  // item_variation_nodes (0 names no node). Some databases have only the second.
  const oldStockSql = String(oldStockTable?.sql || '');
  const leafColumn = (oldStockSql.match(/variation_leaf_node_id[^,]*/i) || [''])[0];
  if (/>\s*0/.test(leafColumn) || /REFERENCES\s+item_variation_nodes/i.test(leafColumn)) {
    const have = new Set((await all('PRAGMA table_info(variation_stock)')).map((c) => c.name));
    const carried = [
      'id', 'item_id', 'variation_leaf_node_id', 'quantity', 'location_id',
      'variation_path_label', 'variation_path_node_ids_json', 'custom_variation_values_json', 'updated_at',
    ].filter((name) => have.has(name)).join(', ');
    // Dropped first, and created again further down with the table's other
    // triggers.
    await run('DROP TRIGGER IF EXISTS trg_variation_stock_leaf_gone');
    // Rows are parked in a plain copy, the table is dropped and made again
    // under its own name, and the rows are put back. No rename: SQLite checks
    // every trigger in the schema on a rename, and on a database still being
    // built (an empty one, part-way through this function) some of them name
    // tables that do not exist yet.
    // One transaction: either the table is the new one with every row in it,
    // or nothing happened. A stop half-way must not leave the rows parked in a
    // table nothing reads.
    await run('BEGIN IMMEDIATE');
    try {
      await run('DROP TABLE IF EXISTS variation_stock_parked');
      await run(`CREATE TABLE variation_stock_parked AS SELECT ${carried} FROM variation_stock`);
      await run('DROP TABLE variation_stock');
      await run(`CREATE TABLE variation_stock (${variationStockColumns})`);
      await run(`INSERT INTO variation_stock (${carried}) SELECT ${carried} FROM variation_stock_parked`);
      await run('DROP TABLE variation_stock_parked');
      await run('COMMIT');
    } catch (error) {
      await run('ROLLBACK').catch(() => {});
      throw error;
    }
    console.log('Rebuilt variation_stock: an item with no variations can now hold stock.');
  }

  await run(`
    CREATE TABLE IF NOT EXISTS groups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      group_type TEXT NOT NULL DEFAULT 'item',
      group_structure TEXT NOT NULL DEFAULT 'hierarchical',
      description TEXT NOT NULL DEFAULT '',
      parent_group_id INTEGER REFERENCES groups(id),
      unit_id INTEGER REFERENCES units(id),
      is_archived INTEGER NOT NULL DEFAULT 0,
      system_key TEXT DEFAULT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      alias TEXT DEFAULT '',
      short_code TEXT DEFAULT '',
      display_name TEXT NOT NULL,
      quantity REAL NOT NULL DEFAULT 0,
      group_id INTEGER NOT NULL REFERENCES groups(id),
      unit_id INTEGER NOT NULL REFERENCES units(id),
      is_archived INTEGER NOT NULL DEFAULT 0,
      default_pipeline_id TEXT DEFAULT NULL,
      base_item_id INTEGER REFERENCES items(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await ensureColumnExists('groups', 'group_type', "TEXT NOT NULL DEFAULT 'item'");
  // Enhancement 2: combination groups (flat variant sets) + optional description.
  await ensureColumnExists('groups', 'group_structure', "TEXT NOT NULL DEFAULT 'hierarchical'");
  await ensureColumnExists('groups', 'description', "TEXT NOT NULL DEFAULT ''");
  // Per-group override of the item-form section layout (JSON). NULL means the
  // creating user's own default applies.
  await ensureColumnExists('groups', 'item_form_sections', 'TEXT DEFAULT NULL');
  // A group the app itself ships — Raw Materials and its Rivets / Springs —
  // carries a stable key. The seed finds it by this key, not its name, so a
  // wipe brings back the same group and code keyed to it (the rivet form) never
  // depends on spelling. NULL on every group a user makes. See
  // modules/items/system-groups.js.
  await ensureColumnExists('groups', 'system_key', 'TEXT DEFAULT NULL');
  await run(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_groups_system_key ON groups(system_key) WHERE system_key IS NOT NULL',
  );

  await ensureColumnExists('items', 'photo_url', 'TEXT DEFAULT NULL');
  // Single CAD / drawing file attached to the item master. The S3 object key is
  // stored — never a presigned URL, which would expire — so the attachment lives
  // until someone clears it; read URLs are minted on demand. The original file
  // name is kept alongside so the UI can label it instead of showing the key.
  await ensureColumnExists('items', 'cad_file_key', 'TEXT DEFAULT NULL');
  await ensureColumnExists('items', 'cad_file_name', "TEXT DEFAULT ''");
  // The client this item was developed for, so it can be listed under them.
  await ensureColumnExists('items', 'developed_for_client_id', 'INTEGER');

  await ensureColumnExists('items', 'quantity', 'REAL NOT NULL DEFAULT 0');
  await ensureColumnExists('items', 'naming_format', "TEXT NOT NULL DEFAULT ''");
  // Whether this item can be ordered as a purchase (reception) line on the
  // mobile Purchase-challan flow. Curated per item in the desktop item editor.
  await ensureColumnExists('items', 'available_for_purchase', 'INTEGER NOT NULL DEFAULT 0');
  // Per-item sample baseline (migrations/029). Separate from the pipeline
  // template's copy, which every item on that template would otherwise share.
  await ensureColumnExists('items', 'pen_paper_baseline_json', 'TEXT');
  await ensureColumnExists('items', 'blank_width_mm', 'REAL DEFAULT 0');
  await ensureColumnExists('items', 'blank_height_mm', 'REAL DEFAULT 0');
  // The number a part was issued and the code derived from it (migrations/045).
  // NULL part_no means never stamped; '' part_code means no code, which the
  // unique index deliberately ignores.
  await ensureColumnExists('items', 'part_no', 'INTEGER');
  await ensureColumnExists('items', 'part_code', "TEXT NOT NULL DEFAULT ''");

  // A part recorded with one deal before item_deals existed gets that deal as
  // its first row, people included. Once only: a part that has any deal row is
  // left alone. Guarded, because an empty database reaches this before the
  // developed_for columns exist.
  try {
    const now = new Date().toISOString();
    await run(
      `INSERT INTO item_deals (item_id, kind, client_id, sub_contractor_id, quotation_amount, at, position, created_at)
       SELECT items.id, items.developed_for_kind, items.developed_for_client_id,
              items.developed_for_sub_contractor_id, items.developed_for_quotation_amount,
              items.developed_for_at, 0, COALESCE(items.developed_for_at, ?)
       FROM items
       WHERE items.developed_for_kind IN ('client', 'contractor')
         AND NOT EXISTS (SELECT 1 FROM item_deals d WHERE d.item_id = items.id)`,
      [now],
    );
    await run(
      `INSERT OR IGNORE INTO item_deal_people (deal_id, contact_id)
       SELECT d.id, idc.contact_id
       FROM item_deals d
       JOIN item_deal_contacts idc ON idc.item_id = d.item_id
       WHERE d.position = 0
         AND NOT EXISTS (SELECT 1 FROM item_deal_people p WHERE p.deal_id = d.id)`,
    );
  } catch (_) {
    // Columns not there yet: nothing recorded to carry over.
  }

  await ensureColumnExists('variation_stock', 'variation_path_label', "TEXT DEFAULT ''");
  await ensureColumnExists('variation_stock', 'variation_path_node_ids_json', "TEXT NOT NULL DEFAULT '[]'");
  await ensureColumnExists('variation_stock', 'custom_variation_values_json', "TEXT DEFAULT '{}'");
  await ensureColumnExists('groups', 'group_type', "TEXT NOT NULL DEFAULT 'item'");
}

module.exports = { createSchema };
