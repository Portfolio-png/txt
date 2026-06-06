const fs = require('fs');
let code = fs.readFileSync('server.js', 'utf8');

// Replace table name in SQL queries
code = code.replace(/\bFROM orders\b/g, 'FROM order_items');
code = code.replace(/\bJOIN orders\b/g, 'JOIN order_items');
code = code.replace(/\bUPDATE orders\b/g, 'UPDATE order_items');
code = code.replace(/\bINTO orders\b/g, 'INTO order_items');
code = code.replace(/\borders\./g, 'order_items.');
code = code.replace(/\bCREATE TABLE IF NOT EXISTS orders\b/g, 'CREATE TABLE IF NOT EXISTS order_items');

// Rename delivery_challan_orders
code = code.replace(/\bdelivery_challan_orders\b/g, 'delivery_challan_order_items');

// Rename order_po_documents references? Let's leave order_po_documents as is, or replace orders(id)
code = code.replace(/\borders\(id\)/g, 'order_items(id)');

// Replace API endpoints?
// app.get('/api/orders') -> We STILL WANT /api/orders.
// So we DO NOT replace '/api/orders'.

// Save changes
fs.writeFileSync('server.js', code);
console.log('Refactoring complete.');
