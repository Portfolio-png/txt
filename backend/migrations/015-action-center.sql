CREATE TABLE IF NOT EXISTS deleted_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  table_name TEXT NOT NULL,
  record_id INTEGER NOT NULL,
  data_json TEXT NOT NULL,
  deleted_at TEXT NOT NULL,
  deleted_by TEXT
);
