const fs = require('fs');
const path = require('path');
const sqlite3 = require('sqlite3').verbose();

// Must match server.js so migrations run against the same database the server
// actually serves (default backend/paper.db, overridable via DB_PATH).
const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'paper.db');
const MIGRATIONS_DIR = path.join(__dirname, 'migrations');

async function runMigrations() {
  return new Promise((resolve, reject) => {
    const db = new sqlite3.Database(DB_PATH, (err) => {
      if (err) return reject(err);
    });

    db.serialize(() => {
      // 1. Ensure migrations table exists
      db.run(`
        CREATE TABLE IF NOT EXISTS _migrations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT UNIQUE NOT NULL,
          applied_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      `, (err) => {
        if (err) return reject(err);
      });

      // 2. Fetch applied migrations
      db.all(`SELECT name FROM _migrations`, async (err, rows) => {
        if (err) return reject(err);
        
        const applied = new Set(rows.map(r => r.name));
        
        // 3. Read migration files
        if (!fs.existsSync(MIGRATIONS_DIR)) {
          fs.mkdirSync(MIGRATIONS_DIR, { recursive: true });
        }
        
        const files = fs.readdirSync(MIGRATIONS_DIR)
          .filter(f => f.endsWith('.sql') || f.endsWith('.js'))
          .sort(); // Crucial to maintain order e.g. 001-init.sql, 002-alter.sql

        for (const file of files) {
          if (!applied.has(file)) {
            console.log(`Applying migration: ${file}`);
            const filePath = path.join(MIGRATIONS_DIR, file);
            
            try {
              if (file.endsWith('.sql')) {
                const sql = fs.readFileSync(filePath, 'utf8');
                await new Promise((res, rej) => {
                  db.exec(sql, (execErr) => {
                    if (execErr) {
                      // Tolerate a column that already exists — some migrations
                      // re-add columns that initDb's CREATE TABLE already defines,
                      // so the desired end state (column present) is already met.
                      // Treat as applied instead of aborting the whole boot.
                      if (/duplicate column name/i.test(execErr.message || '')) {
                        console.warn(`Migration ${file}: ${execErr.message} — column already present, skipping.`);
                        res();
                      } else {
                        rej(execErr);
                      }
                    } else {
                      res();
                    }
                  });
                });
              } else if (file.endsWith('.js')) {
                const migration = require(filePath);
                await migration.up(db);
              }

              // Record as applied
              await new Promise((res, rej) => {
                db.run(`INSERT INTO _migrations (name) VALUES (?)`, [file], (insertErr) => {
                  if (insertErr) rej(insertErr);
                  else res();
                });
              });
              
              console.log(`Migration ${file} applied successfully.`);
            } catch (migrationErr) {
              console.error(`Migration ${file} failed:`, migrationErr);
              db.close();
              return reject(migrationErr);
            }
          }
        }
        
        db.close((closeErr) => {
          if (closeErr) return reject(closeErr);
          resolve();
        });
      });
    });
  });
}

if (require.main === module) {
  runMigrations()
    .then(() => {
      console.log('All migrations checked/applied.');
      process.exit(0);
    })
    .catch((err) => {
      console.error('Migration runner failed:', err);
      process.exit(1);
    });
}

module.exports = { runMigrations };
