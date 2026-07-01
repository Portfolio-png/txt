const fs = require('fs');

const path = 'f:/Rutu/txt/backend/server.js';
let content = fs.readFileSync(path, 'utf8');

const targetExists = "await ensureColumnExists('materials', 'custom_variation_values_json', 'TEXT');";
if (content.includes(targetExists) && !content.includes("ensureColumnExists('order_items', 'custom_variation_values_json', 'TEXT');")) {
  content = content.replace(
    targetExists,
    `${targetExists}\n  await ensureColumnExists('order_items', 'custom_variation_values_json', 'TEXT');`
  );
}

// And update the insert query in saveOrder!
const insertOrderItemsTarget = `
        INSERT INTO order_items (
          order_no, client_id, client_name, po_number, client_code, item_id, item_name,
          variation_leaf_node_id, variation_path_label, variation_path_node_ids_json, quantity,
          unit_id, unit_name, unit_symbol, unit_price, total_invoiced_qty, status,
          custom_variation_values_json,
          created_at, updated_at, start_date, end_date
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
`;

// Wait, the current file ALREADY has custom_variation_values_json in the INSERT?
// Let's check my earlier output:
// "custom_variation_values_json,\n created_at, updated_at, start_date, end_date\n )"
// Ah, it has 22 placeholders: (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
// Let's count them:
// order_no (1), client_id (2), client_name (3), po_number (4), client_code (5), item_id (6), item_name (7),
// variation_leaf_node_id (8), variation_path_label (9), variation_path_node_ids_json (10), quantity (11),
// unit_id (12), unit_name (13), unit_symbol (14), unit_price (15), total_invoiced_qty (16), status (17),
// custom_variation_values_json (18),
// created_at (19), updated_at (20), start_date (21), end_date (22)
// This is exactly 22! So `saveOrder` already HAS custom_variation_values_json in the INSERT?
// Wait, I saw it in my `Get-Content`! But was it there?
// Let's check:
// YES, it WAS there in `Get-Content` output earlier!
// Wait! If it's already there, why did it fail?
// Because the column `custom_variation_values_json` was not created in `order_items`!
// So just adding `ensureColumnExists` is enough.

fs.writeFileSync(path, content, 'utf8');
console.log('Patched server.js again for order_items');
