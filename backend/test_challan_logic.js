const sqlite3 = require('sqlite3');
const db = new sqlite3.Database('paper.db');
const get = (query, params = []) => new Promise((resolve, reject) => {
  db.get(query, params, (err, row) => err ? reject(err) : resolve(row));
});
const all = (query, params = []) => new Promise((resolve, reject) => {
  db.all(query, params, (err, rows) => err ? reject(err) : resolve(rows));
});
async function main() {
  const challanId = 11;
  const items = await all("SELECT * FROM delivery_challan_items WHERE challan_id = ?", [challanId]);
  console.log("items[0].variation_leaf_node_id:", items[0].variation_leaf_node_id);
}
main();
