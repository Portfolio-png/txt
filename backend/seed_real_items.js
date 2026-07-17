const { Database } = require('sqlite3').verbose();
const db = new Database('paper.db');

const itemsData = [
  {
    itemName: 'Switch Action Dolly',
    props: [
      { name: 'Action Dolly Amp', value: '5 Amp' },
      { name: 'Action Patti Number', value: '11' },
      { name: 'Action Dabbi Number', value: '1' },
      { name: 'Action Dolly Alloy', value: 'Brass' },
      { name: 'Action Dolly Contact', value: '1 Way' },
      { name: 'Action Dolly Type', value: 'Dolly' },
      { name: 'Action Dolly Rivet Type', value: 'Copper Rivet' },
      { name: 'Action Dolly Plating', value: 'Without Plating' }
    ],
    valueName: '5 Amp 11+1 Brass 1 Way Dolly With Copper Rivet (Without Plating)',
    valueCode: 'AD-5A-11+1-BR-1W-CR-WP'
  },
  {
    itemName: 'Switch Action Rocker',
    props: [
      { name: 'Action Rocker Amp', value: '5 Amp' },
      { name: 'Action Rocker Name', value: 'Modular' },
      { name: 'Action Rocker Alloy', value: 'Brass' },
      { name: 'Action Rocker Contact', value: '1 Way Zula' },
      { name: 'Action Rocker Rivet Type', value: 'Copper Rivet' },
      { name: 'Action Rocker Plating', value: 'Silver' }
    ],
    valueName: '5 Amp Modular Brass 1 Way Zula With Copper Rivet (Silver)',
    valueCode: 'AR-5A-MOD-BR-1W-CR-SP'
  },
  {
    itemName: 'Socket',
    props: [
      { name: 'Socket Amp', value: '10 Amp' },
      { name: 'Socket Name', value: 'Modular' },
      { name: 'Socket Alloy', value: 'Brass' },
      { name: 'Socket Type', value: 'Socket Face' },
      { name: 'Socket Plating', value: 'Silver' }
    ],
    valueName: '10 Amp Modular Brass Socket Face (Silver)',
    valueCode: 'SF-10A-MOD-BR-SP'
  },
  {
    itemName: 'Cutout',
    props: [
      { name: 'Cutout Amp', value: '63 Amp' },
      { name: 'Cutout Alloy', value: 'Brass' },
      { name: 'Cutout Type', value: 'Cutout U Part' },
      { name: 'Cutout Plating', value: 'Nickel' }
    ],
    valueName: '63 Amp Brass Cutout U Part (Nickel)',
    valueCode: 'CU-63A-BR-NK'
  },
  {
    itemName: 'Coutout Kitkat',
    props: [
      { name: 'Kitkat Name', value: 'Roma Kitkat' },
      { name: 'Kitkat Alloy', value: 'Brass' },
      { name: 'Kitkat Type', value: 'Base Part' },
      { name: 'Kitkat Plating', value: 'Nickel' }
    ],
    valueName: 'Roma Kitkat Br Base Part (Nickel)',
    valueCode: 'CKB-ROMA-BR-NK'
  },
  {
    itemName: 'Multiplug',
    props: [
      { name: 'Multiplug Amp', value: '5 Amp' },
      { name: 'Multiplug Name', value: 'New Multiplug' },
      { name: 'Multiplug Alloy', value: 'Brass' },
      { name: 'Multiplug Type', value: 'Face Live' },
      { name: 'Multiplug Plating', value: 'Without Plating' }
    ],
    valueName: '5 Amp New Multiplug Br Socket Face Live (Without Plating)',
    valueCode: 'MPF-5A-NEW-BR-WPL'
  },
  {
    itemName: 'Double Pole Contact',
    props: [
      { name: 'DP Contact Size', value: '8.0 MM' },
      { name: 'DP Contact Alloy', value: 'Copper' },
      { name: 'DP Contact Type', value: 'Double Pole Big Contact' },
      { name: 'DP Contact Plating', value: 'Silver' }
    ],
    valueName: '8.0 MM Copper Double Pole Big Contact (Silver)',
    valueCode: 'DPBC-8MM-CP-SP'
  },
  {
    itemName: 'Double Pole Rocker',
    props: [
      { name: 'DP Rocker Amp', value: '15 Amp' },
      { name: 'DP Rocker Name', value: 'Penta Double Pole' },
      { name: 'DP Rocker Alloy', value: 'Brass' },
      { name: 'DP Rocker Type', value: '1 Way Zula' },
      { name: 'DP Rocker Rivet Type', value: 'Bimetal Rivet' },
      { name: 'DP Rocker Plating', value: 'Without Plating' }
    ],
    valueName: '15 Amp Penta Double Pole Brass 1 Way Zula With Bimetal Rivet (Without Plating)',
    valueCode: 'DPR-15A-PENTA-BR-1W-BMR-WPL'
  },
  {
    itemName: 'Double Pole Stand',
    props: [
      { name: 'DP Stand Amp', value: '15 Amp' },
      { name: 'DP Stand Name', value: 'Penta Double Pole' },
      { name: 'DP Stand Alloy', value: 'Copper' },
      { name: 'DP Stand Type', value: 'Stand' },
      { name: 'DP Stand Plating', value: 'Without Plating' }
    ],
    valueName: '15 Amp Penta Double Pole Cop Stand (Without Plating)',
    valueCode: 'DPST-15A-PENTA-CP-WPL'
  },
  {
    itemName: 'Double Pole Rivet Part',
    props: [
      { name: 'DP Rivet Part Amp', value: '15 Amp' },
      { name: 'DP Rivet Part Name', value: 'Nice' },
      { name: 'DP Rivet Part Alloy', value: 'Brass' },
      { name: 'DP Rivet Part Type', value: 'Rivet Part' },
      { name: 'DP Rivet Part', value: 'Bimetal Rivet' }
    ],
    valueName: '15 Amp Nice Brass Rivet Part With Bimetal Rivet',
    valueCode: 'DPRP-15A-NICE-BR-BMR'
  },
  {
    itemName: 'Double Pole Fuse',
    props: [
      { name: 'DP Fuse Size', value: '8.0 MM' },
      { name: 'DP Fuse Alloy', value: 'Brass' },
      { name: 'DP Fuse Type', value: 'Double Pole Fuse Wire' },
      { name: 'DP Fuse Plating', value: 'Silver' }
    ],
    valueName: '8.0 MM Brass Double Pole Fuse Wire (Silver)',
    valueCode: 'DPF-8MM-BR-SP'
  },
  {
    itemName: 'Double Pole Dabbi',
    props: [
      { name: 'DP Dabbi No', value: '1 No' },
      { name: 'DP Dabbi Alloy', value: 'Mild Steel' },
      { name: 'DP Dabbi Type', value: 'Double Pole Dabbi' },
      { name: 'DP Dabbi Plating', value: 'Navrang' }
    ],
    valueName: '1 No Mild Steel Double Pole Dabbi (Navrang)',
    valueCode: 'DPD-1-MS-NV'
  },
  {
    itemName: 'Double Pole Febric',
    props: [
      { name: 'DP Febric Name', value: 'GM' },
      { name: 'DP Febric Type', value: 'Double Pole Febric' }
    ],
    valueName: 'GM Double Pole Febric',
    valueCode: 'DPRF-GM'
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

async function seed() {
  for (const item of itemsData) {
    const itemRes = await runQuery(
      "INSERT INTO items (name, display_name, group_id, unit_id, quantity, naming_format, available_for_purchase, created_at, updated_at) VALUES (?, ?, ?, ?, ?, '', 1, datetime('now'), datetime('now'))",
      [item.itemName, item.itemName, groupId, unitId, 100]
    );
    const itemId = itemRes.lastID;
    
    let currentParentId = null;
    
    // Create nested properties and values
    for (let i = 0; i < item.props.length; i++) {
      const prop = item.props[i];
      const isLast = i === item.props.length - 1;
      
      const propRes = await runQuery(
        "INSERT INTO item_variation_nodes (item_id, parent_node_id, kind, name, display_name, position, code, created_at, updated_at) VALUES (?, ?, 'property', ?, ?, 0, '', datetime('now'), datetime('now'))",
        [itemId, currentParentId, prop.name, prop.name]
      );
      
      const propId = propRes.lastID;
      
      const code = isLast ? item.valueCode : '';
      
      const valRes = await runQuery(
        "INSERT INTO item_variation_nodes (item_id, parent_node_id, kind, name, display_name, position, code, created_at, updated_at) VALUES (?, ?, 'value', ?, ?, 0, ?, datetime('now'), datetime('now'))",
        [itemId, propId, prop.value, prop.value, code]
      );
      
      currentParentId = valRes.lastID;
    }
    
    console.log(`Seeded item: ${item.itemName}`);
  }
}

db.serialize(() => {
  seed().then(() => {
    console.log('Done!');
  }).catch(e => {
    console.error(e);
  });
});
