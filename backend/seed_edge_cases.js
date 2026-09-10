const sqlite3 = require('sqlite3').verbose();

async function seed() {
  const db = new sqlite3.Database('paper.db');
  
  const run = (sql, params = []) => new Promise((resolve, reject) => {
    db.run(sql, params, function(err) {
      if (err) reject(err);
      else resolve(this);
    });
  });

  const get = (sql, params = []) => new Promise((resolve, reject) => {
    db.get(sql, params, (err, row) => {
      if (err) reject(err);
      else resolve(row);
    });
  });
  
  const groupId = 353;
  const unitId = 259;
  const pipelineId = 'tpl-1788813977334373'; // New Pipeline

  const itemsToSeed = [
    { name: "Edge Case: Dies Only", pipelineId: pipelineId, machines: [], dies: ["Hexagon Tool X", "Square Punch Y"] },
    { name: "Edge Case: Extremely Long Name Item That Should Wrap Correctly In The UI Because It Is So Long That It Exceeds Standard Container Boundaries", pipelineId: pipelineId, machines: ["Machine 1", "Machine 2", "Machine 3", "Machine 4", "Machine 5"], dies: ["Die A", "Die B", "Die C", "Die D", "Die E"] }
  ];

  for (const item of itemsToSeed) {
    let existingItem = await get('SELECT id FROM items WHERE name = ?', [item.name]);
    let itemId;
    if (existingItem) {
      itemId = existingItem.id;
    } else {
      let res = await run(
        "INSERT INTO items (name, display_name, group_id, unit_id, default_pipeline_id, quantity, naming_format, available_for_purchase, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 100, '', 1, datetime('now'), datetime('now'))",
        [item.name, item.name, groupId, unitId, item.pipelineId]
      );
      itemId = res.lastID;
    }

    for (const mName of item.machines) {
      let m = await get('SELECT id FROM machines WHERE name = ?', [mName]);
      let mId;
      if (!m) {
        let r = await run("INSERT INTO machines (name, asset_id, status, created_at, updated_at) VALUES (?, ?, 'active', datetime('now'), datetime('now'))", [mName, "M-" + Date.now() + Math.random()]);
        mId = r.lastID;
      } else {
        mId = m.id;
      }
      await run("INSERT INTO item_machines (item_id, machine_id, created_at) VALUES (?, ?, datetime('now'))", [itemId, mId]);
    }

    for (const dName of item.dies) {
      let d = await get('SELECT id FROM dies WHERE tool_code = ?', [dName]);
      let dId;
      if (!d) {
        let r = await run("INSERT INTO dies (tool_code, ownership, status, created_at, updated_at) VALUES (?, 'internal', 'active', datetime('now'), datetime('now'))", [dName]);
        dId = r.lastID;
      } else {
        dId = d.id;
      }
      await run("INSERT INTO item_dies (item_id, die_id, created_at) VALUES (?, ?, datetime('now'))", [itemId, dId]);
    }
    
    console.log(`Seeded item: ${item.name}`);
  }
  
  db.close();
}

seed().catch(console.error);
