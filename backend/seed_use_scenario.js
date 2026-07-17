const sqlite3 = require('sqlite3');
const db = new sqlite3.Database('paper.db');

db.serialize(() => {
  // Fix available for purchase
  db.run('UPDATE items SET available_for_purchase = 1', (err) => {
    if (err) console.error(err);
    else console.log('Updated items to be available for purchase');
  });

  // Find a variation_leaf_node_id to insert stock
  db.all('SELECT item_id, id FROM item_variation_nodes WHERE kind = "value" LIMIT 5', (err, rows) => {
    if (err) {
      console.error(err);
      return;
    }
    
    rows.forEach(row => {
      db.run(
        'INSERT OR IGNORE INTO variation_stock (item_id, variation_leaf_node_id, quantity, location_id, variation_path_label) VALUES (?, ?, 100, "MAIN", "Seeded Stock")',
        [row.item_id, row.id],
        (err) => {
          if (err) console.error(err);
          else console.log(`Seeded stock for item_id ${row.item_id}`);
        }
      );
      
      // Also update the quantity if it already exists
      db.run(
        'UPDATE variation_stock SET quantity = 100 WHERE item_id = ? AND variation_leaf_node_id = ?',
        [row.item_id, row.id]
      );
    });
  });
});
