const sqlite3 = require('sqlite3');
const db = new sqlite3.Database('f:/Rutu/txt/backend/data/paper.db');

db.all("SELECT name, sql FROM sqlite_master WHERE type='table' AND sql LIKE '%groups_old_migration%';", (err, rows) => {
  if (err) console.error(err);
  console.log(rows);
});
