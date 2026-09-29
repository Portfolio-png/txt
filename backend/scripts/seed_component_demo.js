// Seeds demo components for the component-creation view.
//
//   node scripts/seed_component_demo.js
//
// 1. Backs up paper.db next to itself (paper.db.bak-<timestamp>).
// 2. Archives every active component group. Nothing is deleted: the old
//    components' items are catalogue items that orders, challans and runs
//    still point at, so they stay where they are.
// 3. Adds three components whose items carry photos, codes, units, variation
//    trees (some nested) and a spread of dies/machines — including items with
//    none, one, and many — so every state of the left column shows up.
//
// Re-runnable: each run archives the previous demo components too.

const path = require('path');
const sqlite3 = require('sqlite3').verbose();

const DB_PATH = process.env.DB_PATH || path.join(__dirname, '..', 'paper.db');
const PIECE = 454;
const KG = 459;

const photo = (slug) => `https://picsum.photos/seed/${slug}/240/240`;

/** A property with values; a value may carry nested properties. */
const prop = (name, values) => ({ kind: 'property', name, values });
const val = (name, code, children = []) => ({ name, code, children });

const COMPONENTS = [
  {
    name: 'Ceiling Fan Motor Housing',
    description: 'Pressed steel housing for the 1200 mm ceiling fan motor.',
    items: [
      {
        name: 'Top Cover',
        alias: 'FMH-TC-01',
        unit: PIECE,
        photo: 'fan-top-cover',
        tree: [
          prop('Sheet Thickness', [val('0.8 mm', '08'), val('1.0 mm', '10')]),
          prop('Finish', [
            val('Powder Coated', 'PC', [
              prop('Colour', [val('White', 'WHT'), val('Ivory', 'IVR'), val('Brown', 'BRN')]),
            ]),
            val('Raw', 'RAW'),
          ]),
        ],
        dies: [['DB-101', 'Rack A · Shelf 1'], ['DF-102', 'Rack A · Shelf 2']],
        machines: [['100T Power Press', 'PP-100-01', 'Kirloskar KP-100']],
      },
      {
        name: 'Bottom Cover',
        alias: 'FMH-BC-01',
        unit: PIECE,
        photo: 'fan-bottom-cover',
        tree: [prop('Sheet Thickness', [val('0.8 mm', '08'), val('1.0 mm', '10')])],
        dies: [['DB-103', 'Rack A · Shelf 3']],
        machines: [['100T Power Press', 'PP-100-01', 'Kirloskar KP-100']],
      },
      {
        name: 'Stator Stamping',
        alias: 'FMH-ST-24',
        unit: KG,
        photo: 'stator-stamping',
        tree: [
          prop('Grade', [val('CRNO', 'CRN'), val('CRGO', 'CRG')]),
          prop('Lamination', [val('0.35 mm', '35'), val('0.50 mm', '50')]),
          prop('Slots', [val('24', '24'), val('36', '36')]),
        ],
        dies: [
          ['PR-201', 'Tool Room · Bay 2'],
          ['PR-202', 'Tool Room · Bay 2'],
          ['NT-203', 'Tool Room · Bay 3'],
        ],
        machines: [
          ['High Speed Press', 'HSP-60-01', 'Bruderer BSTA 60'],
          ['Annealing Furnace', 'AF-01', 'Local fabricated'],
        ],
      },
      {
        name: 'Rotor Stamping',
        alias: 'FMH-RT-01',
        unit: KG,
        photo: 'rotor-stamping',
        tree: [prop('Grade', [val('CRNO', 'CRN')])],
        dies: [],
        machines: [],
      },
    ],
  },
  {
    name: 'Modular Switch Plate',
    description: 'Front plate, frame and terminals for the modular switch range.',
    items: [
      {
        name: 'Front Plate',
        alias: 'MSP-FP',
        unit: PIECE,
        photo: 'switch-front-plate',
        tree: [
          prop('Module', [val('1M', '1M'), val('2M', '2M'), val('4M', '4M'), val('8M', '8M')]),
          prop('Surface', [
            val('Glossy', 'GL', [prop('Colour', [val('White', 'WHT'), val('Black', 'BLK')])]),
            val('Matte', 'MT', [prop('Colour', [val('Grey', 'GRY'), val('Champagne', 'CHP')])]),
          ]),
        ],
        dies: [['IM-301', 'Mould Store · M1']],
        machines: [['Injection Moulding 150T', 'IMM-150-01', 'Toshiba EC150']],
      },
      {
        name: 'Back Frame',
        alias: 'MSP-BF',
        unit: PIECE,
        photo: 'switch-back-frame',
        tree: [prop('Module', [val('1M', '1M'), val('2M', '2M'), val('4M', '4M')])],
        dies: [['IM-302', 'Mould Store · M2']],
        machines: [['Injection Moulding 150T', 'IMM-150-01', 'Toshiba EC150']],
      },
      {
        name: 'Terminal Clip',
        alias: 'MSP-TC',
        unit: PIECE,
        photo: 'terminal-clip',
        tree: [
          prop('Material', [val('Brass', 'BR'), val('Phosphor Bronze', 'PB')]),
          prop('Rating', [val('6A', '06'), val('16A', '16'), val('25A', '25')]),
        ],
        dies: [
          ['PG-311', 'Tool Room · Bay 1'],
          ['PG-312', 'Tool Room · Bay 1'],
          ['PG-313', 'Tool Room · Bay 1'],
          ['PG-314', 'Tool Room · Bay 4'],
          ['BD-315', 'Tool Room · Bay 4'],
        ],
        machines: [
          ['Progressive Press 40T', 'PGP-40-01', 'Aida NC1-40'],
          ['Progressive Press 40T', 'PGP-40-02', 'Aida NC1-40'],
          ['Tapping Machine', 'TAP-01', 'Ashok TM-12'],
          ['Barrel Plating Line', 'BPL-01', 'Grauer & Weil'],
        ],
      },
      {
        name: 'Screw Cover Cap',
        alias: '',
        unit: PIECE,
        photo: '',
        tree: [],
        dies: [],
        machines: [],
      },
    ],
  },
  {
    name: 'Paper Cone Set',
    description: 'Cone, base and joint strip for the textile paper cone.',
    items: [
      {
        name: 'Cone Top',
        alias: 'PCS-CT',
        unit: PIECE,
        photo: 'paper-cone-top',
        tree: [
          prop('GSM', [val('120', '120'), val('150', '150'), val('180', '180')]),
          prop('Angle', [val('4°20′', '420'), val('5°57′', '557')]),
        ],
        dies: [['CT-401', 'Die Rack C']],
        machines: [['Cone Winding Machine', 'CWM-01', 'Jagdish CW-6']],
      },
      {
        name: 'Cone Base',
        alias: 'PCS-CB',
        unit: PIECE,
        photo: 'paper-cone-base',
        tree: [
          prop('GSM', [
            val('150', '150', [prop('Print', [val('Plain', 'PLN'), val('Logo', 'LGO')])]),
            val('180', '180'),
          ]),
        ],
        dies: [],
        machines: [['Cone Winding Machine', 'CWM-01', 'Jagdish CW-6']],
      },
      {
        name: 'Joint Strip',
        alias: 'PCS-JS',
        unit: KG,
        photo: 'paper-joint-strip',
        tree: [],
        dies: [['SL-403', 'Die Rack C']],
        machines: [],
      },
    ],
  },
];

async function main() {
  const db = new sqlite3.Database(DB_PATH);
  const run = (sql, params = []) =>
    new Promise((resolve, reject) =>
      db.run(sql, params, function (err) {
        if (err) reject(err);
        else resolve(this);
      }),
    );
  const get = (sql, params = []) =>
    new Promise((resolve, reject) =>
      db.get(sql, params, (err, row) => (err ? reject(err) : resolve(row))),
    );

  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backup = `${DB_PATH}.bak-${stamp}`;
  await run(`VACUUM INTO ?`, [backup]);
  console.log(`Backed up to ${backup}`);

  const now = new Date().toISOString();
  await run('BEGIN');
  try {
    const archived = await run(
      `UPDATE groups SET is_archived = 1, updated_at = ?
       WHERE group_structure = 'component' AND is_archived = 0`,
      [now],
    );
    console.log(`Archived ${archived.changes} existing component(s)`);

    const dieIds = new Map();
    const dieId = async ([toolCode, location]) => {
      if (dieIds.has(toolCode)) return dieIds.get(toolCode);
      const found = await get('SELECT id FROM dies WHERE tool_code = ?', [toolCode]);
      const id = found
        ? found.id
        : (
            await run(
              `INSERT INTO dies (tool_code, storage_location, status, ownership,
                 photo_urls, compatible_machine_group_ids, created_at, updated_at)
               VALUES (?, ?, 'ready', 'inHouse', '[]', '[]', ?, ?)`,
              [toolCode, location, now, now],
            )
          ).lastID;
      dieIds.set(toolCode, id);
      return id;
    };

    const machineIds = new Map();
    const machineId = async ([name, assetId, makeModel]) => {
      if (machineIds.has(assetId)) return machineIds.get(assetId);
      const found = await get('SELECT id FROM machines WHERE asset_id = ?', [assetId]);
      const id = found
        ? found.id
        : (
            await run(
              `INSERT INTO machines (name, asset_id, make_model, status,
                 created_at, updated_at)
               VALUES (?, ?, ?, 'active', ?, ?)`,
              [name, assetId, makeModel, now, now],
            )
          ).lastID;
      machineIds.set(assetId, id);
      return id;
    };

    const insertNodes = async (itemId, nodes, parentId) => {
      for (const [position, node] of nodes.entries()) {
        const property = await run(
          `INSERT INTO item_variation_nodes (item_id, parent_node_id, kind, name,
             display_name, position, is_archived, code, created_at, updated_at)
           VALUES (?, ?, 'property', ?, ?, ?, 0, '', ?, ?)`,
          [itemId, parentId, node.name, node.name, position, now, now],
        );
        for (const [valuePosition, value] of node.values.entries()) {
          const inserted = await run(
            `INSERT INTO item_variation_nodes (item_id, parent_node_id, kind, name,
               display_name, position, is_archived, code, created_at, updated_at)
             VALUES (?, ?, 'value', ?, ?, ?, 0, ?, ?, ?)`,
            [itemId, property.lastID, value.name, value.name, valuePosition,
              value.code, now, now],
          );
          await insertNodes(itemId, value.children, inserted.lastID);
        }
      }
    };

    for (const component of COMPONENTS) {
      const group = await run(
        `INSERT INTO groups (name, group_type, group_structure, description,
           parent_group_id, unit_id, is_archived, created_at, updated_at)
         VALUES (?, 'item', 'component', ?, NULL, NULL, 0, ?, ?)`,
        [component.name, component.description, now, now],
      );
      for (const item of component.items) {
        const created = await run(
          `INSERT INTO items (name, alias, display_name, group_id, unit_id,
             quantity, naming_format, photo_url, short_code, is_archived,
             created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, 0, '[]', ?, '', 0, ?, ?)`,
          [item.name, item.alias, item.name, group.lastID, item.unit,
            item.photo ? photo(item.photo) : '', now, now],
        );
        const itemId = created.lastID;
        await insertNodes(itemId, item.tree, null);
        for (const die of item.dies) {
          await run(
            'INSERT INTO item_dies (item_id, die_id, created_at) VALUES (?, ?, ?)',
            [itemId, await dieId(die), now],
          );
        }
        for (const machine of item.machines) {
          await run(
            'INSERT INTO item_machines (item_id, machine_id, created_at) VALUES (?, ?, ?)',
            [itemId, await machineId(machine), now],
          );
        }
      }
      console.log(
        `Seeded "${component.name}" (group ${group.lastID}) with ${component.items.length} items`,
      );
    }
    await run('COMMIT');
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  } finally {
    db.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
