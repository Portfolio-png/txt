const fs = require('fs');
let code = fs.readFileSync('server.js', 'utf8');

const regex = /async function ensureDemoItemsPresent\(\) \{[\s\S]*?await ensureItemRecord\(itemSeed\);\n  \}\n\}/;

const newImplementation = `async function ensureDemoItemsPresent(scenarioId = 'default') {
  const groups = await getGroupsWithUsage();
  const units = await getUnitsWithUsage();
  const groupByName = new Map(
    groups.map((group) => [normalizeUnitValue(group.name), group]),
  );
  const primaryGroup = groupByName.get(normalizeUnitValue('Primary Group')) || groups[0];
  const mfgGroup = groupByName.get(normalizeUnitValue('Manufacturing')) || groups[0];

  const unitByName = new Map(
    units.map((unit) => [normalizeUnitValue(unit.name), unit]),
  );
  const piecesUnit = unitByName.get(normalizeUnitValue('Piece')) || units[0];
  const boxUnit = unitByName.get(normalizeUnitValue('Box')) || units[0];
  const kgUnit = unitByName.get(normalizeUnitValue('Kilogram')) || units[0];

  if (scenarioId === 'manufacturing') {
    const rawMaterial = {
      baseItem: {
        name: 'Aluminum Billet',
        group_id: mfgGroup.id,
        hsn_code: '7601',
        is_active: 1,
      },
      variations: {
        'Initial State': [
          { name: 'Raw', code: 'RAW' },
        ],
        'Primary Process': [
          { name: 'None', code: 'NON' },
          { name: 'Milled', code: 'MLL' },
        ],
        'Finishing': [
          { name: 'None', code: 'NON' },
          { name: 'Anodized', code: 'ANO' },
        ],
      },
      unit_id: kgUnit.id,
    };
    
    const intermediate = {
      baseItem: {
        name: 'Copper Coil',
        group_id: mfgGroup.id,
        hsn_code: '7408',
        is_active: 1,
      },
      variations: {
        'State': [
          { name: 'Drawn', code: 'DRW' },
        ],
        'Treatment': [
          { name: 'Insulated', code: 'INS' },
          { name: 'Bare', code: 'BAR' },
        ]
      },
      unit_id: kgUnit.id,
    };
    
    const result = [];
    for (const data of [rawMaterial, intermediate]) {
      const dbItem = await seedScenarioItem(data);
      result.push(dbItem);
    }
    return result;
  }

  // default scenario
  const seedItems = [
    {
      baseItem: {
        name: 'Anchor Roma Classic Switch 10A 1-Way',
        group_id: primaryGroup.id,
        hsn_code: '8536',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'White', code: 'WH'}],
        'Module': [{name: '1M', code: '1M'}]
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 10 } ],
    },
    {
      baseItem: {
        name: 'Anchor Roma Classic Switch 20A 1-Way',
        group_id: primaryGroup.id,
        hsn_code: '8536',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'White', code: 'WH'}],
        'Module': [{name: '1M', code: '1M'}]
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 10 } ],
    },
    {
      baseItem: {
        name: 'Anchor Roma Classic Socket 10A',
        group_id: primaryGroup.id,
        hsn_code: '8536',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'White', code: 'WH'}],
        'Module': [{name: '2M', code: '2M'}]
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 10 } ],
    },
    {
      baseItem: {
        name: 'Anchor Roma Classic Socket 20A',
        group_id: primaryGroup.id,
        hsn_code: '8536',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'White', code: 'WH'}],
        'Module': [{name: '2M', code: '2M'}]
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 10 } ],
    },
    {
      baseItem: {
        name: 'Anchor Roma Penta Switch 10A',
        group_id: primaryGroup.id,
        hsn_code: '8536',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'White', code: 'WH'}],
        'Module': [{name: '1M', code: '1M'}]
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 10 } ],
    },
    {
      baseItem: {
        name: 'Anchor Roma Penta Switch 20A',
        group_id: primaryGroup.id,
        hsn_code: '8536',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'White', code: 'WH'}],
        'Module': [{name: '1M', code: '1M'}]
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 10 } ],
    },
    {
      baseItem: {
        name: 'Anchor Roma Penta Socket 10A',
        group_id: primaryGroup.id,
        hsn_code: '8536',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'White', code: 'WH'}],
        'Module': [{name: '2M', code: '2M'}]
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 10 } ],
    },
    {
      baseItem: {
        name: 'Anchor Roma Penta Socket 20A',
        group_id: primaryGroup.id,
        hsn_code: '8536',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'White', code: 'WH'}],
        'Module': [{name: '2M', code: '2M'}]
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 10 } ],
    },
    {
      baseItem: {
        name: 'Polycab 1.5 sq mm FR PVC Wire (90m)',
        group_id: primaryGroup.id,
        hsn_code: '8544',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'Red', code: 'RD'}],
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 12 } ],
    },
    {
      baseItem: {
        name: 'Polycab 2.5 sq mm FR PVC Wire (90m)',
        group_id: primaryGroup.id,
        hsn_code: '8544',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'Red', code: 'RD'}],
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 12 } ],
    },
    {
      baseItem: {
        name: 'Orient Electric 1200mm Ceiling Fan',
        group_id: primaryGroup.id,
        hsn_code: '8414',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'Brown', code: 'BR'}],
      },
      unit_id: piecesUnit.id,
      conversions: [],
    },
    {
      baseItem: {
        name: 'Crompton Greaves 1200mm Ceiling Fan',
        group_id: primaryGroup.id,
        hsn_code: '8414',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'White', code: 'WH'}],
      },
      unit_id: piecesUnit.id,
      conversions: [],
    },
    {
      baseItem: {
        name: 'Philips 9W LED Bulb',
        group_id: primaryGroup.id,
        hsn_code: '8539',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'Cool Day Light', code: 'CDL'}],
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 10 } ],
    },
  ];

  const result = [];
  for (const data of seedItems) {
    const dbItem = await seedScenarioItem(data);
    result.push(dbItem);
  }
  return result;
}

async function seedScenarioItem(data) {
  let [existing] = await all('SELECT id FROM items WHERE name = ?', [
    data.baseItem.name,
  ]);
  
  let itemId;
  if (!existing) {
    const res = await run(
      \`INSERT INTO items (name, group_id, hsn_code, created_at, updated_at) 
       VALUES (?, ?, ?, datetime('now'), datetime('now'))\`,
      [data.baseItem.name, data.baseItem.group_id, data.baseItem.hsn_code],
    );
    itemId = res.lastID;
    
    // insert properties & values
    let order_index = 0;
    for (const [propName, values] of Object.entries(data.variations)) {
      const propRes = await run(
        \`INSERT INTO item_variation_nodes 
         (item_id, parent_id, kind, value, order_index, is_archived, created_at, updated_at)
         VALUES (?, NULL, 'property', ?, ?, 0, datetime('now'), datetime('now'))\`,
         [itemId, propName, order_index]
      );
      const propId = propRes.lastID;
      
      let val_index = 0;
      for (const val of values) {
        await run(
          \`INSERT INTO item_variation_nodes 
           (item_id, parent_id, kind, value, code, order_index, is_archived, created_at, updated_at)
           VALUES (?, ?, 'value', ?, ?, ?, 0, datetime('now'), datetime('now'))\`,
           [itemId, propId, val.name, val.code, val_index]
        );
        val_index++;
      }
      order_index++;
    }
    
    if (data.unit_id) {
      await run(\`INSERT INTO item_units (item_id, unit_id) VALUES (?, ?)\`, [
        itemId,
        data.unit_id,
      ]);
    }
    if (data.conversions) {
      for (const conv of data.conversions) {
        await run(
          \`INSERT INTO item_unit_conversions (item_id, unit_id, multiplier, created_at, updated_at) VALUES (?, ?, ?, datetime('now'), datetime('now'))\`,
          [itemId, conv.unit_id, conv.multiplier],
        );
      }
    }
    await logChange('items', itemId, 'CREATE');
  } else {
    itemId = existing.id;
  }
  return getItemRowById(itemId);
}

// ensureDemoInventoryPresent
async function ensureDemoInventoryPresent(scenarioId) {
  if (scenarioId !== 'manufacturing') return;
  
  // We need to fetch the items we created and create materials & inventory for them.
  const items = await all('SELECT * FROM items');
  for (const item of items) {
    if (item.name === 'Aluminum Billet') {
      // Create materials for RAW-MLL-ANO
      const variations = {
        'Initial State': 'Raw',
        'Primary Process': 'Milled',
        'Finishing': 'Anodized'
      };
      const materialId = await createOrGetMaterial(item.id, variations);
      
      // Also maybe RAW-NON-NON
      const materialId2 = await createOrGetMaterial(item.id, {
        'Initial State': 'Raw',
        'Primary Process': 'None',
        'Finishing': 'None'
      });
      
      await addInventory(materialId, 500); // 500 kg
      await addInventory(materialId2, 1000); // 1000 kg
    }
    
    if (item.name === 'Copper Coil') {
      const materialId = await createOrGetMaterial(item.id, {
        'State': 'Drawn',
        'Treatment': 'Insulated'
      });
      await addInventory(materialId, 250);
    }
  }
}

async function createOrGetMaterial(itemId, pathMap) {
  // get the node ids for the pathMap
  const nodes = await all('SELECT * FROM item_variation_nodes WHERE item_id = ?', [itemId]);
  
  const properties = nodes.filter(n => n.kind === 'property' && !n.is_archived);
  properties.sort((a,b) => a.order_index - b.order_index);
  
  const selectionMap = {};
  for (const prop of properties) {
    const valName = pathMap[prop.value];
    if (valName) {
      const valNode = nodes.find(n => n.parent_id === prop.id && n.value === valName && !n.is_archived);
      if (valNode) {
        selectionMap[prop.id] = valNode.id;
      }
    }
  }
  
  return await ensureMaterialForItemSelection(itemId, selectionMap);
}

async function addInventory(materialId, qty) {
  // Check if inventory exists
  const [existing] = await all('SELECT id, qty FROM inventory WHERE material_id = ?', [materialId]);
  if (existing) {
    await run('UPDATE inventory SET qty = qty + ?, updated_at = datetime("now") WHERE id = ?', [qty, existing.id]);
  } else {
    await run('INSERT INTO inventory (material_id, qty, last_counted_at, created_at, updated_at) VALUES (?, ?, datetime("now"), datetime("now"), datetime("now"))', [materialId, qty]);
  }
}
`;

code = code.replace(regex, newImplementation);

fs.writeFileSync('server.js', code);
console.log('Patched ensureDemoItemsPresent');
