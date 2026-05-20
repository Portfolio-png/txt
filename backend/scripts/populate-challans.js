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

const all = (query, params = []) => {
  return new Promise((resolve, reject) => {
    db.all(query, params, (err, rows) => {
      if (err) reject(err);
      else resolve(rows);
    });
  });
};

async function populateChallans() {
  try {
    const items = await all('SELECT id, name FROM items LIMIT 10;');
    const vendors = await all('SELECT id, name FROM vendors LIMIT 10;');
    const clients = await all('SELECT id, name FROM clients LIMIT 10;');

    if (items.length === 0) {
      console.warn('No items found. Please add some items first.');
      return;
    }

    console.log(`Found ${items.length} items, ${vendors.length} vendors, ${clients.length} clients.`);

    const now = new Date().toISOString();

    for (let i = 1; i <= 5; i++) {
      // Delivery Challan
      let clientName = clients.length > 0 ? clients[i % clients.length].name : `Client ${i}`;
      let deliveryChallanNo = `DC-TEST-${Date.now()}-${i}`;
      
      const dcResult = await run(`
        INSERT INTO delivery_challans 
        (challan_no, date, customer_name, type, status, created_at, updated_at) 
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `, [deliveryChallanNo, now, clientName, 'delivery', 'draft', now, now]);

      console.log(`Created delivery challan ${deliveryChallanNo}`);

      // Add items
      for (let j = 0; j < 3; j++) {
        let item = items[(i + j) % items.length];
        await run(`
          INSERT INTO delivery_challan_items
          (challan_id, item_id, line_no, particulars, quantity_pcs, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        `, [dcResult.lastID, item.id, j + 1, item.name, (j + 1) * 10, now, now]);
      }

      // Reception Challan
      let vendorId = vendors.length > 0 ? vendors[i % vendors.length].id : null;
      let vendorName = vendors.length > 0 ? vendors[i % vendors.length].name : `Vendor ${i}`;
      let receptionChallanNo = `RC-TEST-${Date.now()}-${i}`;

      const rcResult = await run(`
        INSERT INTO delivery_challans 
        (challan_no, date, customer_name, vendor_id, vendor_name, type, status, created_at, updated_at) 
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `, [receptionChallanNo, now, '', vendorId, vendorName, 'reception', 'draft', now, now]);

      console.log(`Created reception challan ${receptionChallanNo}`);

      // Add items
      for (let j = 0; j < 2; j++) {
        let item = items[(i + j + 2) % items.length];
        await run(`
          INSERT INTO delivery_challan_items
          (challan_id, item_id, line_no, particulars, quantity_pcs, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        `, [rcResult.lastID, item.id, j + 1, item.name, (j + 1) * 5, now, now]);
      }
    }

    console.log('Successfully populated challans!');
  } catch (error) {
    console.error('Error populating challans:', error);
  } finally {
    db.close();
  }
}

populateChallans();
