const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const crypto = require('crypto');
const dbPath = path.join(__dirname, '../paper.db');
const db = new sqlite3.Database(dbPath);

function hashPassword(password) {
  return crypto.createHash('sha256').update(password).digest('hex');
}

db.serialize(() => {
  db.get("SELECT id, name FROM employees WHERE name = 'test_empl'", (err, emp) => {
    if (!emp) {
      console.log("Employee 'test_empl' not found.");
      return;
    }
    const pin = "1234";
    const email = "test_empl@paper.local";
    const now = new Date().toISOString();
    const passHash = hashPassword("password123");
    
    db.run(
      "INSERT INTO users (name, email, password_hash, role, is_active, created_at, updated_at, mobile_pin) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      [emp.name, email, passHash, 'user', 1, now, now, pin],
      function (err) {
        if (err) {
          console.error(err);
          return;
        }
        const userId = this.lastID;
        db.run("UPDATE employees SET user_id = ?, email = ? WHERE id = ?", [userId, email, emp.id], (err) => {
          if (err) console.error(err);
          else console.log(`Created login for test_empl. PIN: ${pin}`);
        });
      }
    );
  });
});
