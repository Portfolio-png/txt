const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const fs = require('fs');

const dbPath = path.join(__dirname, '../paper.db');
if (!fs.existsSync(dbPath)) {
  console.log('Database not found, nothing to migrate.');
  process.exit(0);
}

const db = new sqlite3.Database(dbPath);

db.serialize(() => {
  db.run('BEGIN TRANSACTION');

  db.run(`
    CREATE TABLE IF NOT EXISTS groups_new (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      group_type TEXT NOT NULL DEFAULT 'item',
      parent_group_id INTEGER REFERENCES groups_new(id),
      unit_id INTEGER REFERENCES units(id),
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  db.run(`
    INSERT INTO groups_new (id, name, group_type, parent_group_id, unit_id, is_archived, created_at, updated_at)
    SELECT id, name, group_type, parent_group_id, unit_id, is_archived, created_at, updated_at
    FROM groups
  `);

  db.run('DROP TABLE groups');
  db.run('ALTER TABLE groups_new RENAME TO groups');

  db.run('COMMIT', (err) => {
    if (err) {
      console.error('Migration failed:', err);
      process.exit(1);
    } else {
      console.log('Migration successful: removed NOT NULL from groups.unit_id');
      process.exit(0);
    }
  });
});
