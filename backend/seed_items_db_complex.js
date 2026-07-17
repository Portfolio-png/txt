const { Database } = require('sqlite3').verbose();
const db = new Database('paper.db');

const ITEM_NAMES = [];
for (let i = 1; i <= 10; i++) {
  ITEM_NAMES.push(`Custom Multi-Prop Item ${i}`);
}

const PROPERTIES = [
  { name: 'Color', values: [{ name: 'Black', code: 'BLK' }, { name: 'White', code: 'WHT' }] },
  { name: 'Size', values: [{ name: 'Small', code: 'S' }, { name: 'Large', code: 'L' }] },
  { name: 'Material', values: [{ name: 'Plastic', code: 'PL' }, { name: 'Metal', code: 'MT' }] },
  { name: 'Battery', values: [{ name: 'Standard', code: 'ST' }, { name: 'Extended', code: 'EX' }] },
  { name: 'Storage', values: [{ name: '128GB', code: '128' }, { name: '256GB', code: '256' }] },
  { name: 'RAM', values: [{ name: '8GB', code: '8' }, { name: '16GB', code: '16' }] },
  { name: 'Connectivity', values: [{ name: 'WiFi', code: 'WF' }, { name: 'Cellular', code: 'CELL' }] },
  { name: 'Warranty', values: [{ name: '1 Year', code: '1Y' }, { name: '2 Year', code: '2Y' }] },
  { name: 'Screen', values: [{ name: 'OLED', code: 'OL' }, { name: 'LCD', code: 'LC' }] },
  { name: 'OS', values: [{ name: 'iOS', code: 'IO' }, { name: 'Android', code: 'AN' }] },
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
        
        PROPERTIES.forEach((prop, propIdx) => {
          db.run(
            "INSERT INTO item_variation_nodes (item_id, parent_node_id, kind, name, display_name, position, code, created_at, updated_at) VALUES (?, NULL, 'property', ?, ?, ?, '', datetime('now'), datetime('now'))",
            [itemId, prop.name, prop.name, propIdx],
            function (err) {
              if (err) return console.error(err);
              const parentId = this.lastID;
              
              prop.values.forEach((v, valIdx) => {
                db.run(
                  "INSERT INTO item_variation_nodes (item_id, parent_node_id, kind, name, display_name, position, code, created_at, updated_at) VALUES (?, ?, 'value', ?, ?, ?, ?, datetime('now'), datetime('now'))",
                  [itemId, parentId, v.name, v.name, valIdx, v.code]
                );
              });
            }
          );
        });
        
        console.log(`Seeded item: ${name} with 10 properties and codes.`);
      }
    );
  });
});

console.log('Seeding complex items in background...');
