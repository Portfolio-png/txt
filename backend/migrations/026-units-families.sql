-- 1. unit_groups extensions
ALTER TABLE unit_groups ADD COLUMN dimension TEXT;
ALTER TABLE unit_groups ADD COLUMN base_unit_id INTEGER;

-- 2. units extensions
ALTER TABLE units ADD COLUMN conversion_type TEXT NOT NULL DEFAULT 'linear';
ALTER TABLE units ADD COLUMN precision INTEGER;

-- 3. unit_conversion_points table
CREATE TABLE IF NOT EXISTS unit_conversion_points (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  unit_id INTEGER NOT NULL REFERENCES units(id) ON DELETE CASCADE,
  point_key TEXT NOT NULL,
  base_value REAL NOT NULL,
  UNIQUE(unit_id, point_key)
);

CREATE INDEX IF NOT EXISTS idx_unit_conversion_points_unit_id ON unit_conversion_points(unit_id);

-- 4. transaction line snapshots (ERP Historical Accuracy)
ALTER TABLE order_items ADD COLUMN factor_to_primary_at_creation REAL NOT NULL DEFAULT 1;
ALTER TABLE delivery_challan_items ADD COLUMN factor_to_primary_at_creation REAL NOT NULL DEFAULT 1;
