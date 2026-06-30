const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const dbPath = path.join(__dirname, '..', 'paper.db');
const db = new sqlite3.Database(dbPath);

const run = (query, params = []) => new Promise((resolve, reject) => db.run(query, params, function(err) { if (err) reject(err); else resolve(this); }));
const get = (query, params = []) => new Promise((resolve, reject) => db.get(query, params, (err, row) => { if (err) reject(err); else resolve(row); }));

async function runTests() {
  console.log('--- Running Portal API Tests ---');
  try {
    await run('BEGIN TRANSACTION');
    
    const now = new Date().toISOString();
    const portalUserRes = await run('INSERT INTO portal_users (client_id, email, password_hash) VALUES (1, ?, ?)', 
      ['portal@example.com', 'hash']);
    
    const portalUserId = portalUserRes.lastID;
    console.log('SUCCESS: Created Portal User');

    const cartRes = await run('INSERT INTO portal_carts (portal_user_id, item_id, quantity) VALUES (?, 1, 5)', [portalUserId]);
    console.log('SUCCESS: Added item to Portal Cart');

    await run('ROLLBACK');
    console.log('--- Portal Tests Passed ---\\n');
  } catch (error) {
    await run('ROLLBACK').catch(() => {});
    console.error('PORTAL TESTS FAILED:', error);
    process.exit(1);
  }
}

runTests().then(() => db.close());
