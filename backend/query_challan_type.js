const sqlite3 = require('sqlite3');
const db = new sqlite3.Database('paper.db');
db.all("SELECT id, type, status FROM delivery_challans WHERE id IN (10, 11)", (err, rows) => {
  if (err) console.error(err);
  console.log(JSON.stringify(rows, null, 2));
});
