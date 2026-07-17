const { Database } = require('sqlite3').verbose();
const db = new Database('paper.db');

const itemsData = [
  {
    itemName: 'Switch Action Dolly',
    props: [
      { name: 'Action Dolly Amp', value: '5 Amp', code: '5A' },
      { name: 'Action Patti Number', value: '11', code: '11' },
      { name: 'Action Dabbi Number', value: '1', code: '1' },
      { name: 'Action Dolly Alloy', value: 'Brass', code: 'BR' },
      { name: 'Action Dolly Contact', value: '1 Way', code: '1W' },
      { name: 'Action Dolly Type', value: 'Dolly', code: 'AD' },
      { name: 'Action Dolly Rivet Type', value: 'Copper Rivet', code: 'CR' },
      { name: 'Action Dolly Plating', value: 'Without Plating', code: 'WP' }
    ]
  },
  {
    itemName: 'Switch Action Rocker',
    props: [
      { name: 'Action Rocker Amp', value: '5 Amp', code: '5A' },
      { name: 'Action Rocker Name', value: 'Modular', code: 'MOD' },
      { name: 'Action Rocker Alloy', value: 'Brass', code: 'BR' },
      { name: 'Action Rocker Contact', value: '1 Way Zula', code: '1W' },
      { name: 'Action Rocker Rivet Type', value: 'Copper Rivet', code: 'CR' },
      { name: 'Action Rocker Plating', value: 'Silver', code: 'SP' }
    ]
  },
  {
    itemName: 'Socket',
    props: [
      { name: 'Socket Amp', value: '10 Amp', code: '10A' },
      { name: 'Socket Name', value: 'Modular', code: 'MOD' },
      { name: 'Socket Alloy', value: 'Brass', code: 'BR' },
      { name: 'Socket Type', value: 'Socket Face', code: 'SF' },
      { name: 'Socket Plating', value: 'Silver', code: 'SP' }
    ]
  },
  {
    itemName: 'Cutout',
    props: [
      { name: 'Cutout Amp', value: '63 Amp', code: '63A' },
      { name: 'Cutout Alloy', value: 'Brass', code: 'BR' },
      { name: 'Cutout Type', value: 'Cutout U Part', code: 'CU' },
      { name: 'Cutout Plating', value: 'Nickel', code: 'NK' }
    ]
  },
  {
    itemName: 'Coutout Kitkat',
    props: [
      { name: 'Kitkat Name', value: 'Roma Kitkat', code: 'ROMA' },
      { name: 'Kitkat Alloy', value: 'Brass', code: 'BR' },
      { name: 'Kitkat Type', value: 'Base Part', code: 'CKB' },
      { name: 'Kitkat Plating', value: 'Nickel', code: 'NK' }
    ]
  },
  {
    itemName: 'Multiplug',
    props: [
      { name: 'Multiplug Amp', value: '5 Amp', code: '5A' },
      { name: 'Multiplug Name', value: 'New Multiplug', code: 'NEW' },
      { name: 'Multiplug Alloy', value: 'Brass', code: 'BR' },
      { name: 'Multiplug Type', value: 'Face Live', code: 'MPF' },
      { name: 'Multiplug Plating', value: 'Without Plating', code: 'WPL' }
    ]
  },
  {
    itemName: 'Double Pole Contact',
    props: [
      { name: 'DP Contact Size', value: '8.0 MM', code: '8MM' },
      { name: 'DP Contact Alloy', value: 'Copper', code: 'CP' },
      { name: 'DP Contact Type', value: 'Double Pole Big Contact', code: 'DPBC' },
      { name: 'DP Contact Plating', value: 'Silver', code: 'SP' }
    ]
  },
  {
    itemName: 'Double Pole Rocker',
    props: [
      { name: 'DP Rocker Amp', value: '15 Amp', code: '15A' },
      { name: 'DP Rocker Name', value: 'Penta Double Pole', code: 'PENTA' },
      { name: 'DP Rocker Alloy', value: 'Brass', code: 'BR' },
      { name: 'DP Rocker Type', value: '1 Way Zula', code: '1W' },
      { name: 'DP Rocker Rivet Type', value: 'Bimetal Rivet', code: 'BMR' },
      { name: 'DP Rocker Plating', value: 'Without Plating', code: 'WPL' }
    ]
  },
  {
    itemName: 'Double Pole Stand',
    props: [
      { name: 'DP Stand Amp', value: '15 Amp', code: '15A' },
      { name: 'DP Stand Name', value: 'Penta Double Pole', code: 'PENTA' },
      { name: 'DP Stand Alloy', value: 'Copper', code: 'CP' },
      { name: 'DP Stand Type', value: 'Stand', code: 'DPST' },
      { name: 'DP Stand Plating', value: 'Without Plating', code: 'WPL' }
    ]
  },
  {
    itemName: 'Double Pole Rivet Part',
    props: [
      { name: 'DP Rivet Part Amp', value: '15 Amp', code: '15A' },
      { name: 'DP Rivet Part Name', value: 'Nice', code: 'NICE' },
      { name: 'DP Rivet Part Alloy', value: 'Brass', code: 'BR' },
      { name: 'DP Rivet Part Type', value: 'Rivet Part', code: 'DPRP' },
      { name: 'DP Rivet Part', value: 'Bimetal Rivet', code: 'BMR' }
    ]
  },
  {
    itemName: 'Double Pole Fuse',
    props: [
      { name: 'DP Fuse Size', value: '8.0 MM', code: '8MM' },
      { name: 'DP Fuse Alloy', value: 'Brass', code: 'BR' },
      { name: 'DP Fuse Type', value: 'Double Pole Fuse Wire', code: 'DPF' },
      { name: 'DP Fuse Plating', value: 'Silver', code: 'SP' }
    ]
  },
  {
    itemName: 'Double Pole Dabbi',
    props: [
      { name: 'DP Dabbi No', value: '1 No', code: '1' },
      { name: 'DP Dabbi Alloy', value: 'Mild Steel', code: 'MS' },
      { name: 'DP Dabbi Type', value: 'Double Pole Dabbi', code: 'DPD' },
      { name: 'DP Dabbi Plating', value: 'Navrang', code: 'NV' }
    ]
  },
  {
    itemName: 'Double Pole Febric',
    props: [
      { name: 'DP Febric Name', value: 'GM', code: 'GM' },
      { name: 'DP Febric Type', value: 'Double Pole Febric', code: 'DPRF' }
    ]
  }
];

const groupId = 353;
const unitId = 259;

async function runQuery(query, params = []) {
  return new Promise((resolve, reject) => {
    db.run(query, params, function (err) {
      if (err) reject(err);
      else resolve(this);
    });
  });
}

async function runAll(query, params = []) {
  return new Promise((resolve, reject) => {
    db.all(query, params, function (err, rows) {
      if (err) reject(err);
      else resolve(rows);
    });
  });
}

async function seed() {
  // Find items to delete (the ones seeded in last script)
  const itemNames = itemsData.map(i => i.itemName);
  for (const name of itemNames) {
     const rows = await runAll("SELECT id FROM items WHERE name = ?", [name]);
     for (const row of rows) {
       await runQuery("DELETE FROM item_variation_nodes WHERE item_id = ?", [row.id]);
       await runQuery("DELETE FROM items WHERE id = ?", [row.id]);
       console.log(`Deleted old item ${name} with id ${row.id}`);
     }
  }

  for (const item of itemsData) {
    const itemRes = await runQuery(
      "INSERT INTO items (name, display_name, group_id, unit_id, quantity, naming_format, available_for_purchase, created_at, updated_at) VALUES (?, ?, ?, ?, ?, '', 1, datetime('now'), datetime('now'))",
      [item.itemName, item.itemName, groupId, unitId, 100]
    );
    const itemId = itemRes.lastID;
    
    // Create parallel top-level properties and their single value
    for (let i = 0; i < item.props.length; i++) {
      const prop = item.props[i];
      
      const propRes = await runQuery(
        "INSERT INTO item_variation_nodes (item_id, parent_node_id, kind, name, display_name, position, code, created_at, updated_at) VALUES (?, NULL, 'property', ?, ?, ?, '', datetime('now'), datetime('now'))",
        [itemId, prop.name, prop.name, i]
      );
      
      const propId = propRes.lastID;
      
      await runQuery(
        "INSERT INTO item_variation_nodes (item_id, parent_node_id, kind, name, display_name, position, code, created_at, updated_at) VALUES (?, ?, 'value', ?, ?, 0, ?, datetime('now'), datetime('now'))",
        [itemId, propId, prop.value, prop.value, prop.code]
      );
    }
    
    console.log(`Seeded item: ${item.itemName} with parallel properties.`);
  }
}

db.serialize(() => {
  seed().then(() => {
    console.log('Done!');
  }).catch(e => {
    console.error(e);
  });
});
