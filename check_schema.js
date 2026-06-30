const sqlite3 = require('sqlite3').verbose();
const db = new sqlite3.Database('backend/paper.db');
db.all("SELECT sql FROM sqlite_master WHERE type='table' AND name LIKE '%challan%'", (err, rows) => {
  if (err) console.error(err);
  else rows.forEach(r => console.log(r.sql + '\n'));
  db.close();
});
