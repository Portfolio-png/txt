const sqlite3 = require('sqlite3');
const db = new sqlite3.Database('paper.db');
db.all("SELECT id, barcode, name, linked_item_id, linked_variation_leaf_node_id FROM materials", (err, rows) => {
  if (err) console.error(err);
  console.log(JSON.stringify(rows, null, 2));
});
