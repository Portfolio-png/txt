const sqlite3 = require('sqlite3');
const db = new sqlite3.Database('paper.db');
db.all("SELECT * FROM item_variation_nodes", (err, rows) => {
  console.log(JSON.stringify(rows, null, 2));
});
