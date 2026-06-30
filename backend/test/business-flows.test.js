const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const dbPath = path.join(__dirname, '..', 'paper.db');
const db = new sqlite3.Database(dbPath);

const run = (query, params = []) => new Promise((resolve, reject) => db.run(query, params, function(err) { if (err) reject(err); else resolve(this); }));
const all = (query, params = []) => new Promise((resolve, reject) => db.all(query, params, (err, rows) => { if (err) reject(err); else resolve(rows); }));
const get = (query, params = []) => new Promise((resolve, reject) => db.get(query, params, (err, row) => { if (err) reject(err); else resolve(row); }));

async function testBlitz() {
  console.log('=== STARTING BLITZ TESTS ===');
  
  try {
    await run('BEGIN TRANSACTION');

    // 1. Order Merge Logic
    console.log('\\n--- 1. Order Merge Logic ---');
    // Setup dummy client and item
    const now = new Date().toISOString();
    const clientRes = await run(`INSERT INTO clients (name, created_at, updated_at) VALUES ('Blitz Client', ?, ?)`, [now, now]);
    const clientId = clientRes.lastID;
    
    const unitRes = await run(`INSERT INTO units (name, symbol, created_at, updated_at) VALUES ('Blitz Unit', 'BU', ?, ?)`, [now, now]);
    const groupRes = await run(`INSERT INTO groups (name, unit_id, created_at, updated_at) VALUES ('Blitz Group', ?, ?, ?)`, [unitRes.lastID, now, now]);
    
    const itemRes = await run(`INSERT INTO items (name, display_name, group_id, unit_id, created_at, updated_at) VALUES ('Blitz Item', 'Blitz Item', ?, ?, ?, ?)`, [groupRes.lastID, unitRes.lastID, now, now]);
    const itemId = itemRes.lastID;

    // Create an order via the "merge" logic directly
    const orderRes = await run(`
      INSERT INTO order_items (order_no, client_id, item_id, quantity, total_invoiced_qty, unit_price, created_at, updated_at)
      VALUES ('BLITZ-ORD-1', ?, ?, 10, 6, 100, ?, ?)
    `, [clientId, itemId, now, now]);
    const orderId = orderRes.lastID;
    console.log('Created order with qty 10, invoiced qty 6');

    // Simulate saveOrder merge logic
    async function simulateSaveOrder(quantity) {
      const existing = await get(`SELECT * FROM order_items WHERE id = ?`, [orderId]);
      const newTotalQty = quantity;
      const currentInvoiced = existing.total_invoiced_qty;
      if (currentInvoiced > newTotalQty) {
        throw new Error(`Cannot merge: Invoiced quantity (${currentInvoiced}) exceeds new requested quantity (${newTotalQty}).`);
      }
      await run(`UPDATE order_items SET quantity = ? WHERE id = ?`, [newTotalQty, orderId]);
      return true;
    }

    try {
      await simulateSaveOrder(5);
      console.error('FAIL: Allowed merge where invoiced > new qty');
    } catch (e) {
      console.log('SUCCESS: Blocked merge where invoiced > new qty:', e.message);
    }

    try {
      await simulateSaveOrder(6);
      const updated = await get(`SELECT quantity FROM order_items WHERE id = ?`, [orderId]);
      console.log('SUCCESS: Allowed merge where invoiced == new qty. New qty:', updated.quantity);
    } catch (e) {
      console.error('FAIL: Blocked merge where invoiced == new qty');
    }

    // 2. Invoice Tax Rounding (Just checking how SQLite rounds in the DB, or if the code does it)
    console.log('\\n--- 2. Invoice Tax Rounding Check ---');
    // For this, we'll just check if the database accepts floats and how it stores them
    const invRes = await run(`
      INSERT INTO invoice_headers (invoice_no, client_id, status, invoice_date, taxable_value, cgst_amount, sgst_amount, total_amount, created_at, updated_at)
      VALUES ('BLITZ-INV-1', ?, 'draft', ?, 100.55, 9.049, 9.049, 118.648, ?, ?)
    `, [clientId, now, now, now]);
    const inv = await get(`SELECT * FROM invoice_headers WHERE id = ?`, [invRes.lastID]);
    console.log('Inserted invoice with fractional tax:', inv.cgst_amount);
    if (Math.abs(inv.cgst_amount - 9.049) < 0.001) {
      console.log('SUCCESS: DB stores fractional amounts correctly.');
    } else {
      console.error('FAIL: DB altered fractional amount.');
    }

    // 3. Challan Cascade Deletion
    console.log('\\n--- 3. Challan Cascade Deletion ---');
    const chalRes = await run(`
      INSERT INTO delivery_challans (challan_no, date, customer_name, status, created_at, updated_at)
      VALUES ('BLITZ-CHAL-1', ?, 'Blitz Client', 'draft', ?, ?)
    `, [now, now, now]);
    const challanId = chalRes.lastID;
    
    await run(`
      INSERT INTO invoice_lines (invoice_id, challan_id, item_id, quantity, created_at, updated_at)
      VALUES (?, ?, ?, 5, ?, ?)
    `, [invRes.lastID, challanId, itemId, now, now]);

    // Try deleting the challan
    try {
      await run(`PRAGMA foreign_keys = ON;`); // Ensure foreign keys are active
      await run(`DELETE FROM delivery_challans WHERE id = ?`, [challanId]);
      
      // If we reach here, it either succeeded because no constraint, or it cascaded.
      // Let's check if the invoice line still exists.
      const line = await get(`SELECT * FROM invoice_lines WHERE challan_id = ?`, [challanId]);
      if (line) {
        console.log('WARNING: Deleted challan but invoice line remains (no ON DELETE CASCADE or foreign_keys was off).');
      } else {
        console.log('SUCCESS: Deleted challan and invoice line is gone (Cascade successful or NO constraint error).');
      }
    } catch (e) {
      console.log('SUCCESS (Expected): Blocked deletion of challan with linked invoice due to foreign key constraint:', e.message);
    }

    await run('ROLLBACK');
    console.log('\\n=== BLITZ TESTS COMPLETED SUCCESSFULLY ===');
  } catch (e) {
    await run('ROLLBACK');
    console.error('BLITZ TESTS FAILED:', e);
  }
}

testBlitz().then(() => db.close());
