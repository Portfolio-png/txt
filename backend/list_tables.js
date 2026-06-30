const sqlite3 = require('sqlite3');
const db = new sqlite3.Database('f:/Rutu/txt/backend/paper.db');
db.all("SELECT sql FROM sqlite_master WHERE type='table' AND name IN ('employees', 'order_headers', 'users')", (err, rows) => {
  if (err) console.error(err);
  rows.forEach(r => console.log(r.sql));
});
