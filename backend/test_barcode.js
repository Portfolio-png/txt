const { get, run, all } = require('./server'); // or just run via sqlite3 directly

const sqlite3 = require('sqlite3').verbose();
const db = new sqlite3.Database('paper.db');
function queryGet(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.get(sql, params, (err, row) => err ? reject(err) : resolve(row));
  });
}

async function test() {
  const item = await queryGet("SELECT id FROM items WHERE name = 'Switch Action Dolly'");
  if (!item) return console.log("Item not found");
  
  const customVariationValues = {
    'Action Dolly Type': 'Dolly',
    'Action Dolly Amp': '5 Amp',
    'Action Dolly Alloy': 'Brass'
  };
  
  const codes = [];
  for (const [propName, valName] of Object.entries(customVariationValues)) {
    const row = await queryGet(`
      SELECT v.code, p.position
      FROM item_variation_nodes v
      JOIN item_variation_nodes p ON v.parent_node_id = p.id
      WHERE v.item_id = ? AND p.name = ? AND (v.name = ? OR v.display_name = ?)
    `, [item.id, propName, valName, valName]);
    if (row && row.code) {
      codes.push({ code: row.code, position: row.position });
    }
  }
  
  codes.sort((a, b) => a.position - b.position);
  console.log("Barcode:", codes.map(c => c.code).join('-'));
}

test();
