-- Material types, so a sheet can be weighed without anyone putting it on a
-- scale.
--
-- Distinct from the existing `materials` table, which holds barcoded physical
-- stock — this sheet, from this supplier, on this rack. Steel is a type; the
-- steel on rack 3 is stock. Conflating them would mean re-entering a density
-- on every sheet that arrives.
--
-- Sheet planning already knows a sheet's volume: width × height × thickness,
-- with the trim and the blade accounted for. What it could not know is what the
-- sheet is made of, and therefore what it weighs. Density supplies exactly that
-- one missing number:
--
--     volume (cm³) × density (g/cm³) ÷ 1000 = weight (kg)
--
-- And weight is what everything downstream is priced and moved by: material is
-- bought per kilogram, scrap is sold per kilogram, and a challan is weighed.
--
-- Densities are in g/cm³ because that is how a materials table is written and
-- how anyone checking these values will look them up. Alloys vary by grade —
-- these are the common published figures, and every one is editable, because a
-- shop's own brass is whatever their supplier ships rather than whatever a
-- handbook says.
CREATE TABLE IF NOT EXISTS material_types (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  density_g_cm3 REAL NOT NULL DEFAULT 0,
  category TEXT NOT NULL DEFAULT 'metal',
  notes TEXT DEFAULT '',
  is_archived INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- One row per material name: two "Brass" rows with different densities is a
-- question nobody can answer at the moment they need the weight.
CREATE UNIQUE INDEX IF NOT EXISTS idx_material_types_name
  ON material_types(name COLLATE NOCASE);

-- The starting catalogue. INSERT OR IGNORE so a shop that has already edited
-- its own densities keeps them when this runs again.
INSERT OR IGNORE INTO material_types (name, density_g_cm3, category, notes) VALUES
  ('Steel / MS',      7.85,  'metal',   'Mild steel, the common shop default'),
  ('Stainless Steel', 7.90,  'metal',   '304 is nearer 8.00, 430 nearer 7.70'),
  ('Aluminium',       2.70,  'metal',   ''),
  ('Brass',           8.50,  'metal',   'Varies 8.40-8.70 by grade'),
  ('Copper',          8.96,  'metal',   ''),
  ('Bronze',          8.80,  'metal',   'Varies 8.70-8.90 by grade'),
  ('Cast Iron',       7.20,  'metal',   'Grey iron; ductile runs nearer 7.10'),
  ('Acrylic',         1.18,  'plastic', 'PMMA'),
  ('Beryllium',       1.85,  'metal',   ''),
  ('Chrome',          7.19,  'metal',   'Chromium'),
  ('Columbium',       8.57,  'metal',   'Also called niobium'),
  ('Duralumin',       2.79,  'metal',   'Aluminium-copper alloy'),
  ('Glass',           2.50,  'other',   'Soda-lime; varies 2.40-2.80'),
  ('Gold',            19.32, 'metal',   ''),
  ('Lead',            11.34, 'metal',   ''),
  ('Magnesium',       1.74,  'metal',   ''),
  ('Mercury',         13.53, 'other',   'Liquid at room temperature'),
  ('Molybdenum',      10.22, 'metal',   ''),
  ('Nickel',          8.90,  'metal',   ''),
  ('Nylon',           1.15,  'plastic', 'Nylon 6/6'),
  ('PB / Gunmetal',   8.80,  'metal',   'Phosphor bronze / gunmetal'),
  ('Platinum',        21.45, 'metal',   ''),
  ('Polycarbonate',   1.20,  'plastic', ''),
  ('Polyethylene',    0.95,  'plastic', 'HDPE; LDPE is nearer 0.92'),
  ('Polypropylene',   0.90,  'plastic', ''),
  ('Potassium',       0.86,  'metal',   ''),
  ('PVDF',            1.78,  'plastic', ''),
  ('Silver',          10.49, 'metal',   ''),
  ('Tantalum',        16.65, 'metal',   ''),
  ('Teflon',          2.20,  'plastic', 'PTFE'),
  ('Tin',             7.31,  'metal',   ''),
  ('Titanium',        4.51,  'metal',   ''),
  ('Tungsten',        19.25, 'metal',   ''),
  ('Water',           1.00,  'other',   'The reference every density is against'),
  ('Zinc',            7.14,  'metal',   ''),
  ('Zirconium',       6.52,  'metal',   '');
