const { Database } = require('sqlite3').verbose();
const db = new Database('paper.db');

const ITEM_NAMES = [
  'iPhone 15',
  'MacBook Pro',
  'Nike Air Max',
  'Classic T-Shirt',
  "Levi's 501 Jeans",
  'Samsung Galaxy S24',
  'Sony WH-1000XM5',
  'Apple Watch Series 9',
  'Nintendo Switch',
  'Kindle Paperwhite'
];

const VARIATIONS = [
  { name: 'Black', code: 'BLK' },
  { name: 'White', code: 'WHT' },
  { name: 'Blue', code: 'BLU' },
  { name: 'Yellow', code: 'YEL' },
  { name: 'Green', code: 'GRN' },
  { name: 'Pink', code: 'PNK' },
  { name: 'Red', code: 'RED' },
  { name: 'Purple', code: 'PUR' },
  { name: 'Orange', code: 'ORG' },
  { name: 'Silver', code: 'SLV' },
];

const groupId = 353;
const unitId = 259;

db.serialize(() => {
  ITEM_NAMES.forEach(name => {
    db.run(
      "INSERT INTO items (name, display_name, group_id, unit_id, quantity, naming_format, available_for_purchase, created_at, updated_at) VALUES (?, ?, ?, ?, ?, '', 1, datetime('now'), datetime('now'))",
      [name, name, groupId, unitId, 100],
      function (err) {
        if (err) return console.error(err);
        const itemId = this.lastID;
        
        db.run(
          "INSERT INTO item_variation_nodes (item_id, parent_node_id, kind, name, display_name, position, code, created_at, updated_at) VALUES (?, NULL, 'property', 'Color', 'Color', 0, '', datetime('now'), datetime('now'))",
          [itemId],
          function (err) {
            if (err) return console.error(err);
            const parentId = this.lastID;
            
            VARIATIONS.forEach((v, idx) => {
              db.run(
                "INSERT INTO item_variation_nodes (item_id, parent_node_id, kind, name, display_name, position, code, created_at, updated_at) VALUES (?, ?, 'value', ?, ?, ?, ?, datetime('now'), datetime('now'))",
                [itemId, parentId, v.name, v.name, idx, v.code]
              );
            });
          }
        );
        console.log(`Seeded item: ${name}`);
      }
    );
  });
});

console.log('Seeding items in background...');
