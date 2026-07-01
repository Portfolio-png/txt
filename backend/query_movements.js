const sqlite3 = require('sqlite3');
const db = new sqlite3.Database('paper.db');
db.all("SELECT id, material_barcode, qty, source_challan_id FROM inventory_movements", (err, rows) => {
  if (err) console.error(err);
  console.log(JSON.stringify(rows, null, 2));
});
