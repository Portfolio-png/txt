const sqlite3 = require('sqlite3');
const db = new sqlite3.Database('paper.db');
db.serialize(() => {
  db.run("BEGIN TRANSACTION");
  
  // Find challans 10 and 11 movements
  db.all("SELECT * FROM inventory_movements WHERE source_type = 'delivery_challan' AND source_id IN (10, 11)", (err, rows) => {
    if (err) console.error(err);
    rows.forEach(row => {
      // Reverse them
      const reversalType = row.movement_type === 'receive' ? 'issue' : 'receive';
      db.run(
        `INSERT INTO inventory_movements (material_barcode, movement_type, qty, primary_qty, secondary_qty, primary_uom, secondary_uom, source_type, source_id, notes, created_at, created_by)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [row.material_barcode, reversalType, row.qty, row.primary_qty, row.secondary_qty, row.primary_uom, row.secondary_uom, 'correction', row.source_id, 'Reversing challan for fix', new Date().toISOString(), 'System']
      );
      // Update stock
      const qtyChange = reversalType === 'receive' ? row.qty : -row.qty;
      db.run(`UPDATE inventory_stock_positions SET on_hand_qty = on_hand_qty + ? WHERE material_barcode = ?`, [qtyChange, row.material_barcode]);
    });
  });

  // Cancel the challans
  db.run("UPDATE delivery_challans SET status = 'cancelled' WHERE id IN (10, 11)");
  
  db.run("COMMIT", (err) => {
    if (err) console.error("Error committing:", err);
    else console.log("Successfully reversed and cancelled challans 10 and 11");
  });
});
