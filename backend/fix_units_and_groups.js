const { Database } = require('sqlite3').verbose();
const db = new Database('paper.db');

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

async function runGet(query, params = []) {
  return new Promise((resolve, reject) => {
    db.get(query, params, function (err, row) {
      if (err) reject(err);
      else resolve(row);
    });
  });
}

async function fix() {
  // 1. Fix Item Group
  const itemGroup = await runGet("SELECT id FROM groups WHERE name = 'Primary Group'");
  if (itemGroup) {
    await runQuery("UPDATE items SET group_id = ? WHERE group_id = 353", [itemGroup.id]);
    console.log(`Moved items to item group "Primary Group" (ID ${itemGroup.id})`);
  }

  // 2. Create Unit Group "Primary Group" if not exists
  let unitGroup = await runGet("SELECT id FROM unit_groups WHERE name = 'Primary Group'");
  if (!unitGroup) {
    const res = await runQuery("INSERT INTO unit_groups (name, created_at, updated_at) VALUES ('Primary Group', datetime('now'), datetime('now'))");
    unitGroup = { id: res.lastID };
    console.log(`Created unit group "Primary Group" (ID ${unitGroup.id})`);
  } else {
    console.log(`Found unit group "Primary Group" (ID ${unitGroup.id})`);
  }

  // 3. Create units
  const unitsToCreate = [
    { name: 'Piece', symbol: 'Pc', factor: 1 },
    { name: 'Box', symbol: 'Box', factor: 10 },
    { name: 'Carton', symbol: 'Ctn', factor: 100 }
  ];

  for (const u of unitsToCreate) {
    const existing = await runGet("SELECT id FROM units WHERE name = ?", [u.name]);
    if (!existing) {
      await runQuery(
        "INSERT INTO units (name, symbol, unit_group_id, conversion_factor, conversion_base_unit_id, notes, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, NULL, '', 0, datetime('now'), datetime('now'))",
        [u.name, u.symbol, unitGroup.id, u.factor]
      );
      console.log(`Created unit ${u.name}`);
    } else {
      await runQuery("UPDATE units SET unit_group_id = ? WHERE id = ?", [unitGroup.id, existing.id]);
      console.log(`Updated unit ${u.name} with unit group`);
    }
  }

  // 4. Update the primary unit of seeded items to Piece (if they are still Primary Unit)
  const pieceUnit = await runGet("SELECT id FROM units WHERE name = 'Piece'");
  if (pieceUnit) {
    // items seeded with 259
    await runQuery("UPDATE items SET unit_id = ? WHERE unit_id = 259 OR unit_id = 262", [pieceUnit.id]);
    console.log(`Updated seeded items to use 'Piece' as primary unit`);
  }

  // 5. Add Box as a conversion for the seeded items
  const boxUnit = await runGet("SELECT id FROM units WHERE name = 'Box'");
  if (boxUnit && pieceUnit) {
     const seededItems = await runAll("SELECT id FROM items WHERE unit_id = ?", [pieceUnit.id]);
     for (const item of seededItems) {
        const conv = await runGet("SELECT id FROM item_unit_conversions WHERE item_id = ? AND unit_id = ?", [item.id, boxUnit.id]);
        if (!conv) {
           await runQuery("INSERT INTO item_unit_conversions (item_id, unit_id, factor_to_primary, created_at, updated_at) VALUES (?, ?, ?, datetime('now'), datetime('now'))", [item.id, boxUnit.id, 0.1]); // 1 piece = 0.1 box
        }
     }
     console.log(`Added Box as a secondary unit conversion for seeded items.`);
  }

}

db.serialize(() => {
  fix().then(() => console.log('Done!')).catch(e => console.error(e));
});
