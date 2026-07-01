const sqlite3 = require('sqlite3');
const db = new sqlite3.Database('paper.db');
db.all("SELECT * FROM item_variation_nodes WHERE item_id = 8", (err, rows) => {
  if (err) console.error(err);
  console.log(JSON.stringify(rows, null, 2));
});
