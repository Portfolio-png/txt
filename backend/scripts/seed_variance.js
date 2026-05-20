const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const fs = require('fs');

const DB_PATH = path.join(__dirname, '../paper.db');

if (!fs.existsSync(DB_PATH)) {
  console.error(`Database file not found at ${DB_PATH}`);
  process.exit(1);
}

const db = new sqlite3.Database(DB_PATH, (error) => {
  if (error) {
    console.error('Failed to open database:', error);
    process.exit(1);
  }
});

const run = (query, params = []) => {
  return new Promise((resolve, reject) => {
    db.run(query, params, function (err) {
      if (err) reject(err);
      else resolve(this);
    });
  });
};

const get = (query, params = []) => {
  return new Promise((resolve, reject) => {
    db.get(query, params, (err, row) => {
      if (err) reject(err);
      else resolve(row);
    });
  });
};

async function seedVarianceData() {
  try {
    const now = new Date().toISOString();
    console.log('Seeding diverse test data for visual verification...');

    // 1. Ensure/create clients
    const clientsData = [
      { name: 'Alpha Builders' },
      { name: 'Beta Industries' },
      { name: 'Delta Services' }
    ];
    const clients = {};
    for (const c of clientsData) {
      let row = await get('SELECT * FROM clients WHERE name = ?', [c.name]);
      if (!row) {
        await run('INSERT INTO clients (name, created_at, updated_at) VALUES (?, ?, ?)', [c.name, now, now]);
        row = await get('SELECT * FROM clients WHERE name = ?', [c.name]);
      }
      clients[c.name] = row;
    }

    // 2. Ensure/create vendor
    let vendor = await get('SELECT * FROM vendors WHERE name = ?', ['Gamma Supplies']);
    if (!vendor) {
      await run('INSERT INTO vendors (name, created_at, updated_at) VALUES (?, ?, ?)', ['Gamma Supplies', now, now]);
      vendor = await get('SELECT * FROM vendors WHERE name = ?', ['Gamma Supplies']);
    }

    // 3. Ensure/create item
    let item = await get('SELECT * FROM items LIMIT 1');
    if (!item) {
      await run('INSERT INTO items (name, display_name, group_id, created_at, updated_at) VALUES (?, ?, 1, ?, ?)', ['Kraft Paper 180GSM', 'Kraft Paper 180GSM', now, now]);
      item = await get('SELECT * FROM items LIMIT 1');
    }

    // --- Scenario 1: Client A (Alpha Builders) - Manage Stocks On, 10% Waste ---
    const clientA = clients['Alpha Builders'];
    const orderANo = `ORD-ALPHA-${Date.now()}`;
    const orderAResult = await run(`
      INSERT INTO orders (order_no, client_id, client_name, item_id, unit_price, status, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `, [orderANo, clientA.id, clientA.name, item.id, 120.0, 'confirmed', now, now]);
    const orderAId = orderAResult.lastID;

    // Reception: 200 kg
    const rcAResult = await run(`
      INSERT INTO delivery_challans (challan_no, type, date, status, material_owner_client_id, material_owner_client_name, maintain_stocks, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)
    `, [`RC-ALPHA-${Date.now()}`, 'reception', now, 'issued', clientA.id, clientA.name, now, now]);
    await run(`
      INSERT INTO delivery_challan_items (challan_id, item_id, particulars, weight, quantity_pcs, created_at, updated_at)
      VALUES (?, ?, ?, 200.0, 2000, ?, ?)
    `, [rcAResult.lastID, item.id, item.name, now, now]);

    // Delivery: 180 kg (linked to order)
    const dcAResult = await run(`
      INSERT INTO delivery_challans (challan_no, type, date, status, customer_name, order_id, order_no, maintain_stocks, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
    `, [`DC-ALPHA-${Date.now()}`, 'delivery', now, 'issued', clientA.name, orderAId, orderANo, now, now]);
    await run(`
      INSERT INTO delivery_challan_items (challan_id, order_item_id, item_id, particulars, weight, quantity_pcs, created_at, updated_at)
      VALUES (?, ?, ?, ?, 180.0, 1800, ?, ?)
    `, [dcAResult.lastID, orderAId, item.id, item.name, now, now]);


    // --- Scenario 2: Client B (Beta Industries) - Manage Stocks Off ---
    const clientB = clients['Beta Industries'];
    const dcBResult = await run(`
      INSERT INTO delivery_challans (challan_no, type, date, status, customer_name, maintain_stocks, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, 0, ?, ?)
    `, [`DC-BETA-${Date.now()}`, 'delivery', now, 'issued', clientB.name, now, now]);
    await run(`
      INSERT INTO delivery_challan_items (challan_id, item_id, particulars, weight, quantity_pcs, created_at, updated_at)
      VALUES (?, ?, ?, 150.0, 1500, ?, ?)
    `, [dcBResult.lastID, item.id, item.name, now, now]);


    // --- Scenario 3: Vendor C (Gamma Supplies) - Reception Challan ---
    await run(`
      INSERT INTO delivery_challans (challan_no, type, date, status, vendor_id, vendor_name, maintain_stocks, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)
    `, [`RC-GAMMA-${Date.now()}`, 'reception', now, 'issued', vendor.id, vendor.name, now, now]);


    // --- Scenario 4: Client D (Delta Services) - Manage Stocks On with Paid/Unpaid Invoices ---
    const clientD = clients['Delta Services'];
    const orderDNo = `ORD-DELTA-${Date.now()}`;
    const orderDResult = await run(`
      INSERT INTO orders (order_no, client_id, client_name, item_id, unit_price, status, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `, [orderDNo, clientD.id, clientD.name, item.id, 100.0, 'confirmed', now, now]);
    const orderDId = orderDResult.lastID;

    // Delivery 1 (Will be fully Billed & Paid)
    const dcD1Result = await run(`
      INSERT INTO delivery_challans (challan_no, type, date, status, customer_name, order_id, order_no, maintain_stocks, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
    `, [`DC-DELTA-PAID-${Date.now()}`, 'delivery', now, 'issued', clientD.name, orderDId, orderDNo, now, now]);
    const dcD1Id = dcD1Result.lastID;
    const dcItem1Result = await run(`
      INSERT INTO delivery_challan_items (challan_id, order_item_id, item_id, particulars, weight, quantity_pcs, created_at, updated_at)
      VALUES (?, ?, ?, ?, 120.0, 1200, ?, ?)
    `, [dcD1Id, orderDId, item.id, item.name, now, now]);
    const dcItem1Id = dcItem1Result.lastID;

    // Delivery 2 (Will be fully Billed & Unpaid/Issued)
    const dcD2Result = await run(`
      INSERT INTO delivery_challans (challan_no, type, date, status, customer_name, order_id, order_no, maintain_stocks, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
    `, [`DC-DELTA-UNPAID-${Date.now()}`, 'delivery', now, 'issued', clientD.name, orderDId, orderDNo, now, now]);
    const dcD2Id = dcD2Result.lastID;
    const dcItem2Result = await run(`
      INSERT INTO delivery_challan_items (challan_id, order_item_id, item_id, particulars, weight, quantity_pcs, created_at, updated_at)
      VALUES (?, ?, ?, ?, 80.0, 800, ?, ?)
    `, [dcD2Id, orderDId, item.id, item.name, now, now]);
    const dcItem2Id = dcItem2Result.lastID;

    // Create Invoice 1 (PAID)
    const inv1No = `INV-PAID-${Date.now()}`;
    const inv1Result = await run(`
      INSERT INTO invoice_headers (invoice_no, client_id, client_name, status, invoice_date, total_quantity, taxable_value, cgst_amount, sgst_amount, total_amount, created_at, updated_at)
      VALUES (?, ?, ?, 'paid', ?, 120.0, 12000.0, 1080.0, 1080.0, 14160.0, ?, ?)
    `, [inv1No, clientD.id, clientD.name, now, now, now]);
    const inv1Id = inv1Result.lastID;
    await run(`
      INSERT INTO invoice_lines (invoice_id, order_id, challan_id, challan_item_id, item_id, item_name, quantity, unit_price, taxable_value, cgst_rate, sgst_rate, cgst_amount, sgst_amount, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, 120.0, 100.0, 12000.0, 9.0, 9.0, 1080.0, 1080.0, ?, ?)
    `, [inv1Id, orderDId, dcD1Id, dcItem1Id, item.id, item.name, now, now]);

    // Create Invoice 2 (UNPAID / ISSUED)
    const inv2No = `INV-UNPAID-${Date.now()}`;
    const inv2Result = await run(`
      INSERT INTO invoice_headers (invoice_no, client_id, client_name, status, invoice_date, total_quantity, taxable_value, cgst_amount, sgst_amount, total_amount, created_at, updated_at)
      VALUES (?, ?, ?, 'issued', ?, 80.0, 8000.0, 720.0, 720.0, 9440.0, ?, ?)
    `, [inv2No, clientD.id, clientD.name, now, now, now]);
    const inv2Id = inv2Result.lastID;
    await run(`
      INSERT INTO invoice_lines (invoice_id, order_id, challan_id, challan_item_id, item_id, item_name, quantity, unit_price, taxable_value, cgst_rate, sgst_rate, cgst_amount, sgst_amount, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, 80.0, 100.0, 8000.0, 9.0, 9.0, 720.0, 720.0, ?, ?)
    `, [inv2Id, orderDId, dcD2Id, dcItem2Id, item.id, item.name, now, now]);

    console.log('Diverse seed data loaded successfully!');
  } catch (error) {
    console.error('Failed to seed data:', error);
  } finally {
    db.close();
  }
}

seedVarianceData();
