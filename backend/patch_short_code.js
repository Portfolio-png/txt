const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const db = new sqlite3.Database(path.join(__dirname, 'paper.db'));

db.serialize(() => {
  db.run("ALTER TABLE items ADD COLUMN short_code TEXT DEFAULT ''", (err) => {
    if (err) {
      if (err.message.includes('duplicate column name')) {
        console.log("Column 'short_code' already exists.");
      } else {
        console.error("Error adding column:", err.message);
      }
    } else {
      console.log("Successfully added 'short_code' column to 'items' table.");
    }
  });
});
db.close();
