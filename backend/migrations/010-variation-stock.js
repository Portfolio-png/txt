exports.up = async (db) => {
  const exec = (sql) => new Promise((resolve, reject) => db.exec(sql, err => {
    if (err && err.message.includes('duplicate column name')) return resolve();
    if (err) return reject(err);
    resolve();
  }));

  // 1. Add new columns to inventory_movements for variation-level tracking
  await exec(`
    ALTER TABLE inventory_movements ADD COLUMN item_id INTEGER;
  `);
  await exec(`
    ALTER TABLE inventory_movements ADD COLUMN variation_leaf_node_id INTEGER;
  `);

  // 2. Create the variation_stock table
  await exec(`
    CREATE TABLE IF NOT EXISTS variation_stock (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      variation_leaf_node_id INTEGER NOT NULL REFERENCES item_variation_nodes(id) ON DELETE CASCADE,
      quantity REAL NOT NULL DEFAULT 0 CHECK (quantity >= 0),
      location_id TEXT DEFAULT 'MAIN',
      updated_at TEXT DEFAULT (datetime('now')),
      UNIQUE(item_id, variation_leaf_node_id, location_id)
    );
  `);

  // 3. Seed data by aggregating from existing inventory_stock_positions and materials
  await exec(`
    INSERT INTO variation_stock (item_id, variation_leaf_node_id, quantity, location_id)
    SELECT
      m.linked_item_id,
      IFNULL(m.linked_variation_leaf_node_id, 0),
      SUM(isp.on_hand_qty),
      isp.location_id
    FROM inventory_stock_positions isp
    JOIN materials m ON isp.material_barcode = m.barcode
    WHERE m.linked_item_id IS NOT NULL
    GROUP BY m.linked_item_id, IFNULL(m.linked_variation_leaf_node_id, 0), isp.location_id
    HAVING SUM(isp.on_hand_qty) > 0
    ON CONFLICT(item_id, variation_leaf_node_id, location_id) DO UPDATE SET
      quantity = quantity + excluded.quantity,
      updated_at = datetime('now');
  `);
};
