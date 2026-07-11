CREATE TABLE IF NOT EXISTS sub_contractors (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  notes TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

ALTER TABLE order_headers ADD COLUMN sub_contractor_id INTEGER REFERENCES sub_contractors(id);
ALTER TABLE order_items ADD COLUMN sub_contractor_id INTEGER REFERENCES sub_contractors(id);
