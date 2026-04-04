const express = require('express');
const cors = require('cors');
const path = require('path');
const sqlite3 = require('sqlite3').verbose();

const app = express();
const PORT = Number(process.env.PORT || 18080);
const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'paper.db');
const db = new sqlite3.Database(DB_PATH);

app.use(cors());
app.use(express.json());

function run(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.run(sql, params, function onRun(error) {
      if (error) {
        reject(error);
        return;
      }
      resolve(this);
    });
  });
}

function get(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.get(sql, params, (error, row) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(row);
    });
  });
}

function all(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.all(sql, params, (error, rows) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(rows);
    });
  });
}

function closeDb() {
  return new Promise((resolve, reject) => {
    db.close((error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
    });
  });
}

function normalizeBarcode(value = '') {
  return String(value)
    .replace(/\s+/g, '')
    .replace(/[^\x20-\x7E]/g, '')
    .trim()
    .toUpperCase();
}

function generateParentBarcode() {
  const suffix = 1000 + Math.floor(Math.random() * 9000);
  return `PAR-${Date.now()}-${suffix}`;
}

function generateChildBarcode(parentBarcode, index) {
  const parts = parentBarcode.split('-');
  const suffix = parts.length > 0 ? parts[parts.length - 1] : parentBarcode;
  return `CHD-${suffix}-${String(index).padStart(2, '0')}`;
}

function parseJson(value, fallback) {
  if (!value) {
    return fallback;
  }
  try {
    return JSON.parse(value);
  } catch (_) {
    return fallback;
  }
}

function normalizeUnitValue(value = '') {
  return String(value).trim().replace(/\s+/g, ' ').toLowerCase();
}

function rowToMaterialDto(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    barcode: row.barcode,
    name: row.name,
    type: row.type,
    grade: row.grade || '',
    thickness: row.thickness || '',
    supplier: row.supplier || '',
    unitId: row.unit_id || null,
    unit: row.unit || '',
    notes: row.notes || '',
    isParent: row.kind === 'parent',
    parentBarcode: row.parent_barcode || null,
    numberOfChildren: row.number_of_children || 0,
    linkedChildBarcodes: parseJson(row.linked_child_barcodes, []),
    scanCount: row.scan_count || 0,
    createdAt: row.created_at,
  };
}

function rowToUnitDto(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    name: row.name || '',
    symbol: row.symbol || '',
    notes: row.notes || '',
    isArchived: Boolean(row.is_archived),
    usageCount: row.usage_count || 0,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function rowToGroupDto(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    name: row.name || '',
    parentGroupId: row.parent_group_id || null,
    unitId: row.unit_id || null,
    isArchived: Boolean(row.is_archived),
    usageCount: row.usage_count || 0,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function rowToClientDto(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    name: row.name || '',
    alias: row.alias || '',
    gstNumber: row.gst_number || '',
    address: row.address || '',
    isArchived: Boolean(row.is_archived),
    usageCount: row.usage_count || 0,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function rowToOrderDto(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    orderNo: row.order_no || '',
    clientId: row.client_id || 0,
    clientName: row.client_name || '',
    poNumber: row.po_number || '',
    clientCode: row.client_code || '',
    itemId: row.item_id || 0,
    itemName: row.item_name || '',
    variationLeafNodeId: row.variation_leaf_node_id || 0,
    variationPathLabel: row.variation_path_label || '',
    variationPathNodeIds: parseJson(row.variation_path_node_ids_json, []),
    quantity: Number(row.quantity || 0),
    status: row.status || 'notStarted',
    createdAt: row.created_at,
    startDate: row.start_date,
    endDate: row.end_date,
  };
}

async function rowToItemDto(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    name: row.name || '',
    alias: row.alias || '',
    displayName: row.display_name || '',
    quantity: Number(row.quantity || 0),
    groupId: row.group_id || null,
    unitId: row.unit_id || null,
    isArchived: Boolean(row.is_archived),
    usageCount: row.usage_count || 0,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    variationTree: await getItemVariationTree(row.id),
  };
}

function rowToTemplate(row) {
  if (!row) {
    return null;
  }
  return {
    id: row.id,
    name: row.name,
    description: row.description || '',
    version: row.version || 1,
    status: row.status || 'draft',
    stageLabels: parseJson(row.stage_labels_json, []),
    laneLabels: parseJson(row.lane_labels_json, []),
    nodes: parseJson(row.nodes_json, []),
    flows: parseJson(row.flows_json, []),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function rowToRun(row) {
  if (!row) {
    return null;
  }

  const barcodeRows = await all(
    'SELECT node_id, barcode, material_payload_json FROM run_barcode_inputs WHERE run_id = ? ORDER BY scanned_at DESC',
    [row.id],
  );

  const attachedBarcodeInputs = {};
  for (const barcodeRow of barcodeRows) {
    if (!attachedBarcodeInputs[barcodeRow.node_id]) {
      attachedBarcodeInputs[barcodeRow.node_id] = [];
    }
    attachedBarcodeInputs[barcodeRow.node_id].push(
      parseJson(barcodeRow.material_payload_json, {}),
    );
  }

  return {
    id: row.id,
    templateId: row.template_id,
    templateVersion: row.template_version,
    name: row.name || '',
    status: row.status || 'planned',
    overrides: parseJson(row.overrides_json, {}),
    nodeStatuses: parseJson(row.node_status_json, {}),
    attachedBarcodeInputs,
    startedAt: row.started_at,
    completedAt: row.completed_at,
    createdAt: row.created_at,
  };
}

function buildSeedTemplates() {
  return [
    {
      id: 'dolly',
      name: 'Dolly Production',
      description:
        'Copper and steel lanes converge into a welding stage before final assembly handoff.',
      version: 1,
      status: 'published',
      stageLabels: [
        'Stage 1: Raw Input',
        'Stage 2: Prep',
        'Stage 3: Join',
        'Stage 4: Finish',
      ],
      laneLabels: ['Lane 1', 'Lane 2', 'Lane 3'],
      nodes: [
        {
          id: 'dolly-input-copper',
          name: 'Copper Roll Feed',
          processType: 'Input',
          stageIndex: 0,
          laneIndex: 0,
          inputs: ['Copper roll'],
          outputs: ['Blank copper'],
          machine: 'Rack A1',
          durationHours: 0.5,
          status: 'Ready',
          isIntermediate: false,
          scannedInputs: [],
        },
        {
          id: 'dolly-cut',
          name: 'Blank Cutting',
          processType: 'Cutting',
          stageIndex: 1,
          laneIndex: 0,
          inputs: ['Copper roll'],
          outputs: ['Cut copper'],
          machine: 'Cutter 04',
          durationHours: 1,
          status: 'Active',
          isIntermediate: true,
          scannedInputs: [],
        },
        {
          id: 'dolly-input-steel',
          name: 'Steel Sheet Feed',
          processType: 'Input',
          stageIndex: 0,
          laneIndex: 1,
          inputs: ['Steel sheet'],
          outputs: ['Drilled steel'],
          machine: 'Rack B2',
          durationHours: 0.5,
          status: 'Ready',
          isIntermediate: false,
          scannedInputs: [],
        },
        {
          id: 'dolly-drill',
          name: 'Drilling',
          processType: 'Machining',
          stageIndex: 1,
          laneIndex: 1,
          inputs: ['Steel sheet'],
          outputs: ['Drilled steel'],
          machine: 'Drill 02',
          durationHours: 1.5,
          status: 'Ready',
          isIntermediate: true,
          scannedInputs: [],
        },
        {
          id: 'dolly-weld',
          name: 'Welding',
          processType: 'Join',
          stageIndex: 2,
          laneIndex: 1,
          inputs: ['Cut copper', 'Drilled steel'],
          outputs: ['Frame body'],
          machine: 'Welder 01',
          durationHours: 2,
          status: 'Blocked',
          isIntermediate: true,
          scannedInputs: [],
        },
        {
          id: 'dolly-polish',
          name: 'Polishing',
          processType: 'Finish',
          stageIndex: 3,
          laneIndex: 1,
          inputs: ['Frame body'],
          outputs: ['Dolly frame'],
          machine: 'Polisher 01',
          durationHours: 1,
          status: 'Queued',
          isIntermediate: false,
          scannedInputs: [],
        },
      ],
      flows: [
        { id: 'flow-1', fromNodeId: 'dolly-input-copper', toNodeId: 'dolly-cut', materialName: 'Copper roll', barcode: null, isSplit: false, isMerge: false },
        { id: 'flow-2', fromNodeId: 'dolly-input-steel', toNodeId: 'dolly-drill', materialName: 'Steel sheet', barcode: null, isSplit: false, isMerge: false },
        { id: 'flow-3', fromNodeId: 'dolly-cut', toNodeId: 'dolly-weld', materialName: 'Cut copper', barcode: null, isSplit: false, isMerge: true },
        { id: 'flow-4', fromNodeId: 'dolly-drill', toNodeId: 'dolly-weld', materialName: 'Drilled steel', barcode: null, isSplit: false, isMerge: true },
        { id: 'flow-5', fromNodeId: 'dolly-weld', toNodeId: 'dolly-polish', materialName: 'Frame body', barcode: null, isSplit: false, isMerge: false },
      ],
    },
    {
      id: 'assembly',
      name: 'Assembly Mainline',
      description:
        'Three parallel sub-assemblies merge into a final assembly and packing handoff.',
      version: 1,
      status: 'published',
      stageLabels: ['Stage 1: Feed', 'Stage 2: Prep', 'Stage 3: Merge', 'Stage 4: Outbound'],
      laneLabels: ['Lane 1', 'Lane 2', 'Lane 3'],
      nodes: [
        {
          id: 'assembly-right',
          name: 'Right Side Panel',
          processType: 'Input',
          stageIndex: 0,
          laneIndex: 0,
          inputs: ['Right panel'],
          outputs: ['Ready right'],
          machine: 'Buffer A',
          durationHours: 0.25,
          status: 'Ready',
          isIntermediate: false,
          scannedInputs: [],
        },
        {
          id: 'assembly-left',
          name: 'Left Side Panel',
          processType: 'Input',
          stageIndex: 0,
          laneIndex: 1,
          inputs: ['Left panel'],
          outputs: ['Ready left'],
          machine: 'Buffer B',
          durationHours: 0.25,
          status: 'Ready',
          isIntermediate: false,
          scannedInputs: [],
        },
        {
          id: 'assembly-center',
          name: 'Center Body',
          processType: 'Input',
          stageIndex: 0,
          laneIndex: 2,
          inputs: ['Center body'],
          outputs: ['Ready center'],
          machine: 'Buffer C',
          durationHours: 0.25,
          status: 'Ready',
          isIntermediate: false,
          scannedInputs: [],
        },
        {
          id: 'assembly-fixture',
          name: 'Assembly Fixture',
          processType: 'Prep',
          stageIndex: 1,
          laneIndex: 1,
          inputs: ['Ready right', 'Ready left', 'Ready center'],
          outputs: ['Mounted body'],
          machine: 'Fixture 03',
          durationHours: 1.5,
          status: 'Active',
          isIntermediate: true,
          scannedInputs: [],
        },
        {
          id: 'assembly-pack',
          name: 'Packing',
          processType: 'Outbound',
          stageIndex: 3,
          laneIndex: 1,
          inputs: ['Mounted body'],
          outputs: ['Packed dolly'],
          machine: 'Packing 01',
          durationHours: 0.75,
          status: 'Queued',
          isIntermediate: false,
          scannedInputs: [],
        },
      ],
      flows: [
        { id: 'assembly-flow-1', fromNodeId: 'assembly-right', toNodeId: 'assembly-fixture', materialName: 'Ready right', barcode: null, isSplit: false, isMerge: true },
        { id: 'assembly-flow-2', fromNodeId: 'assembly-left', toNodeId: 'assembly-fixture', materialName: 'Ready left', barcode: null, isSplit: false, isMerge: true },
        { id: 'assembly-flow-3', fromNodeId: 'assembly-center', toNodeId: 'assembly-fixture', materialName: 'Ready center', barcode: null, isSplit: false, isMerge: true },
        { id: 'assembly-flow-4', fromNodeId: 'assembly-fixture', toNodeId: 'assembly-pack', materialName: 'Mounted body', barcode: null, isSplit: false, isMerge: false },
      ],
    },
  ];
}

async function initDb() {
  await run(`
    CREATE TABLE IF NOT EXISTS materials (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      barcode TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      grade TEXT,
      thickness TEXT,
      supplier TEXT,
      unit_id INTEGER,
      unit TEXT,
      notes TEXT,
      created_at TEXT NOT NULL,
      kind TEXT NOT NULL,
      parent_barcode TEXT,
      number_of_children INTEGER NOT NULL DEFAULT 0,
      linked_child_barcodes TEXT,
      scan_count INTEGER NOT NULL DEFAULT 0
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS units (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      symbol TEXT NOT NULL,
      notes TEXT DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS groups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      parent_group_id INTEGER REFERENCES groups(id),
      unit_id INTEGER NOT NULL REFERENCES units(id),
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS clients (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      alias TEXT DEFAULT '',
      gst_number TEXT DEFAULT '',
      address TEXT DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      alias TEXT DEFAULT '',
      display_name TEXT NOT NULL,
      quantity REAL NOT NULL DEFAULT 0,
      group_id INTEGER NOT NULL REFERENCES groups(id),
      unit_id INTEGER NOT NULL REFERENCES units(id),
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS orders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_no TEXT NOT NULL,
      client_id INTEGER NOT NULL REFERENCES clients(id),
      client_name TEXT NOT NULL DEFAULT '',
      po_number TEXT DEFAULT '',
      client_code TEXT DEFAULT '',
      item_id INTEGER NOT NULL REFERENCES items(id),
      item_name TEXT NOT NULL DEFAULT '',
      variation_leaf_node_id INTEGER NOT NULL DEFAULT 0,
      variation_path_label TEXT DEFAULT '',
      variation_path_node_ids_json TEXT NOT NULL DEFAULT '[]',
      quantity INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'notStarted',
      created_at TEXT NOT NULL,
      start_date TEXT,
      end_date TEXT
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS item_variations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      name TEXT NOT NULL DEFAULT '',
      alias TEXT DEFAULT '',
      display_name TEXT NOT NULL,
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS item_variation_dimensions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      position INTEGER NOT NULL DEFAULT 0
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS item_variation_values (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      variation_id INTEGER NOT NULL REFERENCES item_variations(id) ON DELETE CASCADE,
      dimension_id INTEGER NOT NULL REFERENCES item_variation_dimensions(id) ON DELETE CASCADE,
      value TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS item_variation_nodes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      parent_node_id INTEGER REFERENCES item_variation_nodes(id) ON DELETE CASCADE,
      kind TEXT NOT NULL,
      name TEXT NOT NULL,
      display_name TEXT NOT NULL DEFAULT '',
      position INTEGER NOT NULL DEFAULT 0,
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await ensureColumnExists('items', 'quantity', 'REAL NOT NULL DEFAULT 0');
  await ensureColumnExists('item_variations', 'alias', "TEXT DEFAULT ''");
  await ensureColumnExists('item_variations', 'display_name', "TEXT DEFAULT ''");

  await ensureColumnExists('materials', 'unit_id', 'INTEGER');

  await run(`
    CREATE TABLE IF NOT EXISTS pipeline_templates (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT DEFAULT '',
      version INTEGER NOT NULL DEFAULT 1,
      status TEXT DEFAULT 'draft',
      stage_labels_json TEXT NOT NULL,
      lane_labels_json TEXT NOT NULL,
      nodes_json TEXT NOT NULL,
      flows_json TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS pipeline_runs (
      id TEXT PRIMARY KEY,
      template_id TEXT NOT NULL REFERENCES pipeline_templates(id),
      template_version INTEGER NOT NULL,
      name TEXT,
      status TEXT DEFAULT 'planned',
      overrides_json TEXT,
      node_status_json TEXT,
      started_at TEXT,
      completed_at TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS run_barcode_inputs (
      id TEXT PRIMARY KEY,
      run_id TEXT NOT NULL REFERENCES pipeline_runs(id),
      node_id TEXT NOT NULL,
      barcode TEXT NOT NULL,
      material_id TEXT,
      material_payload_json TEXT NOT NULL,
      scanned_at TEXT DEFAULT (datetime('now'))
    )
  `);

  await seedMaterialsIfEmpty();
  await seedUnitsIfEmpty();
  await bootstrapUnitsFromMaterials();
  await backfillMaterialUnitIds();
  await seedClientsIfEmpty();
  await seedGroupsIfEmpty();
  await seedItemsIfEmpty();
  await seedOrdersIfEmpty();
  await seedTemplatesIfEmpty();
}

async function ensureColumnExists(tableName, columnName, definition) {
  const columns = await all(`PRAGMA table_info(${tableName})`);
  const hasColumn = columns.some((column) => column.name === columnName);
  if (!hasColumn) {
    await run(`ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${definition}`);
  }
}

async function seedMaterialsIfEmpty() {
  const countRow = await get('SELECT COUNT(*) AS count FROM materials');
  if ((countRow?.count || 0) > 0) {
    return;
  }

  await createParentWithChildren({
    name: 'Copper Master Roll',
    type: 'Raw Material',
    grade: 'A1',
    thickness: '1.2 mm',
    supplier: 'Shree Metals',
    unit: 'Kg',
    notes: 'Demo seed',
    numberOfChildren: 3,
  });
  await createParentWithChildren({
    name: 'Steel Sheet Batch',
    type: 'Raw Material',
    grade: 'B2',
    thickness: '2.0 mm',
    supplier: 'Metro Steels',
    unit: 'Sheet',
    notes: 'Demo seed',
    numberOfChildren: 2,
  });
}

async function bootstrapUnitsFromMaterials() {
  const countRow = await get('SELECT COUNT(*) AS count FROM units');
  if ((countRow?.count || 0) > 0) {
    return;
  }

  const materialRows = await all(
    'SELECT DISTINCT unit FROM materials WHERE TRIM(COALESCE(unit, \'\')) != \'\'',
  );
  const now = new Date().toISOString();
  const seen = new Set();
  for (const row of materialRows) {
    const value = String(row.unit || '').trim();
    const normalized = normalizeUnitValue(value);
    if (!normalized || seen.has(normalized)) {
      continue;
    }
    seen.add(normalized);
    await run(
      `
      INSERT INTO units (name, symbol, notes, is_archived, created_at, updated_at)
      VALUES (?, ?, '', 0, ?, ?)
      `,
      [value, value, now, now],
    );
  }
}

async function seedUnitsIfEmpty() {
  const countRow = await get('SELECT COUNT(*) AS count FROM units');
  if ((countRow?.count || 0) > 0) {
    return;
  }

  const now = new Date().toISOString();
  const units = [
    { name: 'Kilogram', symbol: 'Kg', notes: 'Mock seed' },
    { name: 'Sheet', symbol: 'Sheet', notes: 'Mock seed' },
    { name: 'Piece', symbol: 'Pieces', notes: 'Mock seed' },
    { name: 'Box', symbol: 'Box', notes: 'Mock seed' },
  ];

  for (const unit of units) {
    await run(
      `
      INSERT INTO units (name, symbol, notes, is_archived, created_at, updated_at)
      VALUES (?, ?, ?, 0, ?, ?)
      `,
      [unit.name, unit.symbol, unit.notes, now, now],
    );
  }
}

async function backfillMaterialUnitIds() {
  const unitRows = await all('SELECT id, symbol FROM units');
  const unitMap = new Map();
  for (const row of unitRows) {
    const normalized = normalizeUnitValue(row.symbol);
    if (!normalized) {
      continue;
    }
    if (!unitMap.has(normalized)) {
      unitMap.set(normalized, []);
    }
    unitMap.get(normalized).push(row.id);
  }

  const materialRows = await all(
    'SELECT id, unit, unit_id FROM materials WHERE unit_id IS NULL AND TRIM(COALESCE(unit, \'\')) != \'\'',
  );
  for (const row of materialRows) {
    const matches = unitMap.get(normalizeUnitValue(row.unit)) || [];
    if (matches.length === 1) {
      await run('UPDATE materials SET unit_id = ? WHERE id = ?', [matches[0], row.id]);
    }
  }
}

async function seedTemplatesIfEmpty() {
  const countRow = await get('SELECT COUNT(*) AS count FROM pipeline_templates');
  if ((countRow?.count || 0) > 0) {
    return;
  }

  const templates = buildSeedTemplates();
  for (const template of templates) {
    const now = new Date().toISOString();
    await run(
      `
      INSERT INTO pipeline_templates (
        id, name, description, version, status, stage_labels_json,
        lane_labels_json, nodes_json, flows_json, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        template.id,
        template.name,
        template.description,
        template.version,
        template.status,
        JSON.stringify(template.stageLabels),
        JSON.stringify(template.laneLabels),
        JSON.stringify(template.nodes),
        JSON.stringify(template.flows),
        now,
        now,
      ],
    );
  }
}

async function createParentWithChildren(payload) {
  const resolvedUnit = await resolveUnitPayload(payload);
  const parentBarcode = generateParentBarcode();
  const childBarcodes = Array.from(
    { length: Number(payload.numberOfChildren || 0) },
    (_, index) => generateChildBarcode(parentBarcode, index + 1),
  );
  const createdAt = new Date().toISOString();

  await run('BEGIN TRANSACTION');
  try {
    const parentResult = await run(
      `
      INSERT INTO materials (
        barcode, name, type, grade, thickness, supplier, unit_id, unit, notes,
        created_at, kind, parent_barcode, number_of_children,
        linked_child_barcodes, scan_count
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'parent', NULL, ?, ?, 0)
      `,
      [
        parentBarcode,
        payload.name,
        payload.type,
        payload.grade || '',
        payload.thickness || '',
        payload.supplier || '',
        resolvedUnit.unitId,
        resolvedUnit.unit,
        payload.notes || '',
        createdAt,
        Number(payload.numberOfChildren || 0),
        JSON.stringify(childBarcodes),
      ],
    );

    for (let index = 0; index < childBarcodes.length; index += 1) {
      await run(
        `
        INSERT INTO materials (
          barcode, name, type, grade, thickness, supplier, unit_id, unit, notes,
          created_at, kind, parent_barcode, number_of_children,
          linked_child_barcodes, scan_count
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'child', ?, 0, ?, 0)
        `,
        [
          childBarcodes[index],
          `${payload.name} - Child ${index + 1}`,
          payload.type,
          payload.grade || '',
          payload.thickness || '',
          payload.supplier || '',
          resolvedUnit.unitId,
          resolvedUnit.unit,
          payload.notes || '',
          createdAt,
          parentBarcode,
          JSON.stringify([]),
        ],
      );
    }

    await run('COMMIT');
    const parentRow = await get('SELECT * FROM materials WHERE id = ?', [
      parentResult.lastID,
    ]);
    return rowToMaterialDto(parentRow);
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }
}

async function resolveUnitPayload(payload) {
  if (!payload.unitId) {
    return {
      unitId: null,
      unit: String(payload.unit || '').trim(),
    };
  }

  const unitRow = await get('SELECT * FROM units WHERE id = ?', [payload.unitId]);
  if (!unitRow) {
    throw new Error('Selected unit does not exist.');
  }

  return {
    unitId: unitRow.id,
    unit: unitRow.symbol || '',
  };
}

async function getUnitRowById(id) {
  return get(
    `
    SELECT
      units.*,
      COUNT(materials.id) AS usage_count
    FROM units
    LEFT JOIN materials ON materials.unit_id = units.id
    WHERE units.id = ?
    GROUP BY units.id
    `,
    [id],
  );
}

async function getGroupRowById(id) {
  return get(
    `
    SELECT
      groups.*,
      0 AS usage_count
    FROM groups
    WHERE groups.id = ?
    `,
    [id],
  );
}

async function getClientRowById(id) {
  return get(
    `
    SELECT
      clients.*,
      0 AS usage_count
    FROM clients
    WHERE clients.id = ?
    `,
    [id],
  );
}

async function getItemVariationRows(itemId) {
  return all(
    `
    SELECT *
    FROM item_variations
    WHERE item_id = ?
    ORDER BY is_archived ASC, LOWER(display_name) ASC
    `,
    [itemId],
  );
}

async function getItemVariationNodeRows(itemId) {
  return all(
    `
    SELECT *
    FROM item_variation_nodes
    WHERE item_id = ?
    ORDER BY parent_node_id ASC, position ASC, LOWER(name) ASC
    `,
    [itemId],
  );
}

async function getItemVariationTree(itemId) {
  const rows = await getItemVariationNodeRows(itemId);
  const rowMap = new Map();
  for (const row of rows) {
    rowMap.set(row.id, {
      id: row.id,
      itemId: row.item_id,
      parentNodeId: row.parent_node_id,
      kind: row.kind || 'property',
      name: row.name || '',
      displayName: row.display_name || '',
      position: row.position || 0,
      isArchived: Boolean(row.is_archived),
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      children: [],
    });
  }

  const roots = [];
  for (const row of rows) {
    const node = rowMap.get(row.id);
    if (row.parent_node_id == null) {
      roots.push(node);
    } else {
      const parent = rowMap.get(row.parent_node_id);
      if (parent) {
        parent.children.push(node);
      }
    }
  }

  const sortNodes = (nodes) => {
    nodes.sort((a, b) => {
      if (a.position !== b.position) {
        return a.position - b.position;
      }
      return String(a.name || '').localeCompare(String(b.name || ''), undefined, {
        sensitivity: 'base',
      });
    });
    for (const node of nodes) {
      sortNodes(node.children);
    }
  };

  sortNodes(roots);
  return roots;
}

async function getItemVariationDimensions(itemId) {
  return all(
    `
    SELECT *
    FROM item_variation_dimensions
    WHERE item_id = ?
    ORDER BY position ASC, LOWER(name) ASC
    `,
    [itemId],
  );
}

async function getVariationValues(variationId) {
  const rows = await all(
    `
    SELECT
      item_variation_values.dimension_id,
      item_variation_dimensions.name AS dimension_name,
      item_variation_values.value
    FROM item_variation_values
    JOIN item_variation_dimensions
      ON item_variation_dimensions.id = item_variation_values.dimension_id
    WHERE item_variation_values.variation_id = ?
    ORDER BY item_variation_dimensions.position ASC
    `,
    [variationId],
  );
  return rows.map((row) => ({
    dimensionId: row.dimension_id,
    dimensionName: row.dimension_name || '',
    value: row.value || '',
  }));
}

async function getItemRowById(id) {
  return get(
    `
    SELECT
      items.*,
      0 AS usage_count
    FROM items
    WHERE items.id = ?
    `,
    [id],
  );
}

async function getItemsWithUsage() {
  return all(`
    SELECT
      items.*,
      0 AS usage_count
    FROM items
    ORDER BY items.is_archived ASC, LOWER(items.name) ASC
  `);
}

async function findItemDuplicate({ name, groupId, quantity, excludeId = null }) {
  const rows = await all('SELECT id, name, group_id, quantity FROM items');
  const normalizedName = normalizeUnitValue(name);
  return rows.find((row) => {
    if (excludeId != null && row.id === excludeId) {
      return false;
    }
    return (
      row.group_id === groupId &&
      Number(row.quantity || 0) === Number(quantity || 0) &&
      normalizeUnitValue(row.name) === normalizedName
    );
  }) || null;
}

async function getGroupsWithUsage() {
  return all(`
    SELECT
      groups.*,
      0 AS usage_count
    FROM groups
    ORDER BY groups.is_archived ASC, LOWER(groups.name) ASC
  `);
}

async function getClientsWithUsage() {
  return all(`
    SELECT
      clients.*,
      0 AS usage_count
    FROM clients
    ORDER BY clients.is_archived ASC, LOWER(clients.name) ASC
  `);
}

function normalizePartyValue(value = '') {
  return String(value).trim().replace(/\s+/g, ' ').toLowerCase();
}

function normalizeGstNumber(value = '') {
  return String(value).trim().replace(/\s+/g, '').toUpperCase();
}

async function findClientDuplicate({ name, gstNumber = '', excludeId = null }) {
  const rows = await all('SELECT id, name, gst_number FROM clients');
  const normalizedName = normalizePartyValue(name);
  const normalizedGst = normalizeGstNumber(gstNumber);
  return rows.find((row) => {
    if (excludeId != null && row.id === excludeId) {
      return false;
    }
    if (normalizePartyValue(row.name) === normalizedName) {
      return true;
    }
    return normalizedGst && normalizeGstNumber(row.gst_number) === normalizedGst;
  }) || null;
}

async function saveClient({ name, alias = '', gstNumber = '', address = '', id = null }) {
  const trimmedName = String(name || '').trim();
  const trimmedAlias = String(alias || '').trim();
  const trimmedGstNumber = normalizeGstNumber(gstNumber);
  const trimmedAddress = String(address || '').trim();

  if (!trimmedName) {
    throw new Error('name is required.');
  }
  if (trimmedGstNumber && trimmedGstNumber.length !== 15) {
    const error = new Error('GST number must be 15 characters.');
    error.statusCode = 400;
    throw error;
  }

  const duplicate = await findClientDuplicate({
    name: trimmedName,
    gstNumber: trimmedGstNumber,
    excludeId: id,
  });
  if (duplicate) {
    const duplicateByName =
      normalizePartyValue(duplicate.name) === normalizePartyValue(trimmedName);
    const error = new Error(
      duplicateByName
        ? 'A client with the same name already exists.'
        : 'A client with the same GST number already exists.',
    );
    error.statusCode = 409;
    throw error;
  }

  const now = new Date().toISOString();
  if (id == null) {
    const result = await run(
      `
      INSERT INTO clients (name, alias, gst_number, address, is_archived, created_at, updated_at)
      VALUES (?, ?, ?, ?, 0, ?, ?)
      `,
      [trimmedName, trimmedAlias, trimmedGstNumber, trimmedAddress, now, now],
    );
    return getClientRowById(result.lastID);
  }

  const existing = await getClientRowById(id);
  if (!existing) {
    const error = new Error('Client not found.');
    error.statusCode = 404;
    throw error;
  }

  await run(
    'UPDATE clients SET name = ?, alias = ?, gst_number = ?, address = ?, updated_at = ? WHERE id = ?',
    [trimmedName, trimmedAlias, trimmedGstNumber, trimmedAddress, now, id],
  );
  return getClientRowById(id);
}

async function seedClientsIfEmpty() {
  const countRow = await get('SELECT COUNT(*) AS count FROM clients');
  if ((countRow?.count || 0) > 0) {
    return;
  }

  await saveClient({
    name: 'Acme Packaging Pvt. Ltd.',
    alias: 'Acme',
    gstNumber: '27ABCDE1234F1Z5',
    address: 'MIDC Industrial Area, Pune, Maharashtra 411019',
  });
  await saveClient({
    name: 'Sunrise Retail LLP',
    alias: 'Sunrise',
    gstNumber: '24AAKCS9988M1Z2',
    address: 'Satellite Road, Ahmedabad, Gujarat 380015',
  });
  const archived = await saveClient({
    name: 'Legacy Trading Co.',
    alias: 'Legacy',
    address: 'Old Market Road, Indore, Madhya Pradesh 452001',
  });
  await run('UPDATE clients SET is_archived = 1, updated_at = ? WHERE id = ?', [
    new Date().toISOString(),
    archived.id,
  ]);
}

async function getOrderRowById(id) {
  return get('SELECT * FROM orders WHERE id = ?', [id]);
}

async function getOrders() {
  return all('SELECT * FROM orders ORDER BY datetime(created_at) DESC, id DESC');
}

async function saveOrder({
  orderNo,
  clientId,
  clientName = '',
  poNumber = '',
  clientCode = '',
  itemId,
  itemName = '',
  variationLeafNodeId = 0,
  variationPathLabel = '',
  variationPathNodeIds = [],
  quantity,
  status = 'notStarted',
  startDate = null,
  endDate = null,
}) {
  const trimmedOrderNo = String(orderNo || '').trim();
  const normalizedClientId = Number(clientId);
  const normalizedItemId = Number(itemId);
  const normalizedLeafId = Number(variationLeafNodeId || 0);
  const normalizedQuantity = Number(quantity || 0);
  const trimmedPoNumber = String(poNumber || '').trim();
  const trimmedClientName = String(clientName || '').trim();
  const trimmedClientCode = String(clientCode || '').trim();
  const trimmedItemName = String(itemName || '').trim();
  const trimmedVariationPathLabel = String(variationPathLabel || '').trim();
  const allowedStatuses = new Set(['notStarted', 'inProgress', 'completed', 'delayed']);
  const normalizedStatus = allowedStatuses.has(status) ? status : 'notStarted';

  if (!trimmedOrderNo) {
    const error = new Error('Order number is required.');
    error.statusCode = 400;
    throw error;
  }
  if (!normalizedClientId || !normalizedItemId || !normalizedLeafId) {
    const error = new Error('Client, item, and variation path are required.');
    error.statusCode = 400;
    throw error;
  }
  if (!Number.isFinite(normalizedQuantity) || normalizedQuantity <= 0) {
    const error = new Error('Quantity must be greater than zero.');
    error.statusCode = 400;
    throw error;
  }

  const now = new Date().toISOString();
  const existing = await get(
    `
    SELECT * FROM orders
    WHERE LOWER(TRIM(order_no)) = LOWER(TRIM(?))
      AND client_id = ?
      AND item_id = ?
      AND variation_leaf_node_id = ?
      AND LOWER(TRIM(po_number)) = LOWER(TRIM(?))
    `,
    [trimmedOrderNo, normalizedClientId, normalizedItemId, normalizedLeafId, trimmedPoNumber],
  );

  if (existing) {
    await run(
      `
      UPDATE orders
      SET quantity = quantity + ?,
          client_name = ?,
          client_code = ?,
          item_name = ?,
          variation_path_label = ?,
          variation_path_node_ids_json = ?
      WHERE id = ?
      `,
      [
        normalizedQuantity,
        trimmedClientName,
        trimmedClientCode,
        trimmedItemName,
        trimmedVariationPathLabel,
        JSON.stringify(Array.isArray(variationPathNodeIds) ? variationPathNodeIds : []),
        existing.id,
      ],
    );
    return getOrderRowById(existing.id);
  }

  const result = await run(
    `
    INSERT INTO orders (
      order_no, client_id, client_name, po_number, client_code, item_id, item_name,
      variation_leaf_node_id, variation_path_label, variation_path_node_ids_json,
      quantity, status, created_at, start_date, end_date
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `,
    [
      trimmedOrderNo,
      normalizedClientId,
      trimmedClientName,
      trimmedPoNumber,
      trimmedClientCode,
      normalizedItemId,
      trimmedItemName,
      normalizedLeafId,
      trimmedVariationPathLabel,
      JSON.stringify(Array.isArray(variationPathNodeIds) ? variationPathNodeIds : []),
      Math.round(normalizedQuantity),
      normalizedStatus,
      now,
      startDate || null,
      endDate || null,
    ],
  );
  return getOrderRowById(result.lastID);
}

async function updateOrderLifecycle({
  id,
  status = 'notStarted',
  startDate = null,
  endDate = null,
}) {
  const existing = await getOrderRowById(id);
  if (!existing) {
    const error = new Error('Order not found.');
    error.statusCode = 404;
    throw error;
  }
  const allowedStatuses = new Set(['notStarted', 'inProgress', 'completed', 'delayed']);
  const normalizedStatus = allowedStatuses.has(status) ? status : 'notStarted';
  await run(
    'UPDATE orders SET status = ?, start_date = ?, end_date = ? WHERE id = ?',
    [normalizedStatus, startDate || null, endDate || null, id],
  );
  return getOrderRowById(id);
}

async function findGroupDuplicate({ name, parentGroupId = null, excludeId = null }) {
  const rows = await all('SELECT id, name, parent_group_id FROM groups');
  const normalizedName = normalizeUnitValue(name);
  return rows.find((row) => {
    if (excludeId != null && row.id === excludeId) {
      return false;
    }
    return (
      normalizeUnitValue(row.name) === normalizedName &&
      (row.parent_group_id || null) === (parentGroupId || null)
    );
  }) || null;
}

async function getActiveChildGroups(parentGroupId) {
  return all(
    'SELECT * FROM groups WHERE parent_group_id = ? AND is_archived = 0',
    [parentGroupId],
  );
}

async function groupWouldCreateCycle(groupId, parentGroupId) {
  let currentId = parentGroupId;
  while (currentId != null) {
    if (currentId === groupId) {
      return true;
    }
    const row = await get('SELECT parent_group_id FROM groups WHERE id = ?', [currentId]);
    currentId = row?.parent_group_id || null;
  }
  return false;
}

async function saveGroup({ name, parentGroupId = null, unitId, id = null }) {
  const trimmedName = String(name || '').trim();
  const normalizedParentId = parentGroupId == null ? null : Number(parentGroupId);
  const normalizedUnitId = Number(unitId);

  if (!trimmedName || !normalizedUnitId) {
    throw new Error('name and unitId are required.');
  }

  const unitRow = await get('SELECT * FROM units WHERE id = ?', [normalizedUnitId]);
  if (!unitRow || unitRow.is_archived) {
    const error = new Error('Selected unit does not exist or is archived.');
    error.statusCode = 400;
    throw error;
  }

  if (id != null && normalizedParentId === id) {
    const error = new Error('A group cannot be its own parent.');
    error.statusCode = 409;
    throw error;
  }

  if (normalizedParentId != null) {
    const parentRow = await get('SELECT * FROM groups WHERE id = ?', [normalizedParentId]);
    if (!parentRow || parentRow.is_archived) {
      const error = new Error('Selected parent group is not available.');
      error.statusCode = 400;
      throw error;
    }
    if (id != null && await groupWouldCreateCycle(id, normalizedParentId)) {
      const error = new Error('A group cannot move under its own descendant.');
      error.statusCode = 409;
      throw error;
    }
  }

  const duplicate = await findGroupDuplicate({
    name: trimmedName,
    parentGroupId: normalizedParentId,
    excludeId: id,
  });
  if (duplicate) {
    const error = new Error('A group with the same name already exists here.');
    error.statusCode = 409;
    throw error;
  }

  const now = new Date().toISOString();
  if (id == null) {
    const result = await run(
      `
      INSERT INTO groups (name, parent_group_id, unit_id, is_archived, created_at, updated_at)
      VALUES (?, ?, ?, 0, ?, ?)
      `,
      [trimmedName, normalizedParentId, normalizedUnitId, now, now],
    );
    return getGroupRowById(result.lastID);
  }

  const existing = await getGroupRowById(id);
  if (!existing) {
    const error = new Error('Group not found.');
    error.statusCode = 404;
    throw error;
  }
  if ((existing.usage_count || 0) > 0) {
    const error = new Error('Used groups cannot be edited.');
    error.statusCode = 409;
    throw error;
  }

  await run(
    'UPDATE groups SET name = ?, parent_group_id = ?, unit_id = ?, updated_at = ? WHERE id = ?',
    [trimmedName, normalizedParentId, normalizedUnitId, now, id],
  );
  return getGroupRowById(id);
}

async function seedGroupsIfEmpty() {
  const countRow = await get('SELECT COUNT(*) AS count FROM groups');
  if ((countRow?.count || 0) > 0) {
    return;
  }

  const units = await all(
    'SELECT id, symbol FROM units WHERE is_archived = 0 ORDER BY id ASC',
  );
  const sheetUnit = units.find((unit) => normalizeUnitValue(unit.symbol) === 'sheet');
  const kilogramUnit = units.find((unit) => normalizeUnitValue(unit.symbol) === 'kg');
  const fallbackUnit = sheetUnit || kilogramUnit || units[0];
  if (!fallbackUnit) {
    return;
  }

  const now = new Date().toISOString();
  const paperResult = await run(
    `
    INSERT INTO groups (name, parent_group_id, unit_id, is_archived, created_at, updated_at)
    VALUES (?, NULL, ?, 0, ?, ?)
    `,
    ['Paper', sheetUnit?.id || fallbackUnit.id, now, now],
  );
  await run(
    `
    INSERT INTO groups (name, parent_group_id, unit_id, is_archived, created_at, updated_at)
    VALUES (?, ?, ?, 0, ?, ?)
    `,
    ['Kraft', paperResult.lastID, sheetUnit?.id || fallbackUnit.id, now, now],
  );
  await run(
    `
    INSERT INTO groups (name, parent_group_id, unit_id, is_archived, created_at, updated_at)
    VALUES (?, NULL, ?, 0, ?, ?)
    `,
    ['Chemical', kilogramUnit?.id || fallbackUnit.id, now, now],
  );
  await run(
    `
    INSERT INTO groups (name, parent_group_id, unit_id, is_archived, created_at, updated_at)
    VALUES (?, NULL, ?, 1, ?, ?)
    `,
    ['Legacy Group', kilogramUnit?.id || fallbackUnit.id, now, now],
  );
}

function buildItemDisplayName(name, alias, quantity) {
  const parts = [String(name || '').trim(), String(alias || '').trim()].filter(Boolean);
  const base = parts.join(' / ');
  const qty = Number(quantity || 0);
  const qtyLabel = Number.isInteger(qty) ? String(qty) : String(qty);
  return base ? `${base} - ${qtyLabel}` : qtyLabel;
}

function buildVariationPathLabel(segments = []) {
  return segments
    .map((entry) => String(entry || '').trim())
    .filter(Boolean)
    .join(' | ');
}

async function saveItem({
  name,
  alias = '',
  displayName = '',
  quantity,
  groupId,
  unitId,
  variationTree = [],
  id = null,
}) {
  const trimmedName = String(name || '').trim();
  const trimmedAlias = String(alias || '').trim();
  const normalizedQuantity = Number(quantity);
  const trimmedDisplayName =
    String(displayName || '').trim() || buildItemDisplayName(name, alias, normalizedQuantity);
  const normalizedGroupId = Number(groupId);
  const normalizedUnitId = Number(unitId);

  if (
    !trimmedName ||
    !normalizedQuantity ||
    !normalizedGroupId ||
    !normalizedUnitId ||
    !trimmedDisplayName
  ) {
    throw new Error('name, quantity, displayName, groupId, and unitId are required.');
  }

  const groupRow = await get('SELECT * FROM groups WHERE id = ?', [normalizedGroupId]);
  if (!groupRow || groupRow.is_archived) {
    const error = new Error('Selected group does not exist or is archived.');
    error.statusCode = 400;
    throw error;
  }

  const unitRow = await get('SELECT * FROM units WHERE id = ?', [normalizedUnitId]);
  if (!unitRow || unitRow.is_archived) {
    const error = new Error('Selected unit does not exist or is archived.');
    error.statusCode = 400;
    throw error;
  }

  const duplicate = await findItemDuplicate({
    name: trimmedName,
    groupId: normalizedGroupId,
    quantity: normalizedQuantity,
    excludeId: id,
  });
  if (duplicate) {
    const error = new Error('An item with the same name and quantity already exists in this group.');
    error.statusCode = 409;
    throw error;
  }

  const sanitizeNodes = (nodes, expectedKind, pathSegments = [], parentPropertyName = '') => {
    const siblingNames = new Set();
    return (nodes || []).map((node, index) => {
      const trimmedName = String(node.name || '').trim();
      if (!trimmedName) {
        const error = new Error('Variation tree node names are required.');
        error.statusCode = 400;
        throw error;
      }
      const kind = String(node.kind || '');
      if (kind !== expectedKind) {
        const error = new Error('Variation tree must alternate between property groups and values.');
        error.statusCode = 409;
        throw error;
      }
      const normalizedName = normalizeUnitValue(trimmedName);
      if (siblingNames.has(normalizedName)) {
        const error = new Error('Sibling variation nodes must have unique names.');
        error.statusCode = 409;
        throw error;
      }
      siblingNames.add(normalizedName);

      if (kind === 'property') {
        return {
          kind,
          name: trimmedName,
          displayName: '',
          position: index,
          children: sanitizeNodes(node.children || [], 'value', pathSegments, trimmedName),
        };
      }

      const nextSegments = [...pathSegments, `${parentPropertyName}: ${trimmedName}`];
      const children = sanitizeNodes(node.children || [], 'property', nextSegments, '');
      return {
        kind,
        name: trimmedName,
        displayName:
          children.length === 0
            ? String(node.displayName || '').trim() || buildVariationPathLabel(nextSegments)
            : '',
        position: index,
        children,
      };
    });
  };

  const sanitizedTree = sanitizeNodes(variationTree, 'property');

  const now = new Date().toISOString();
  await run('BEGIN TRANSACTION');
  try {
    let itemId = id;
    if (id == null) {
      const result = await run(
        `
        INSERT INTO items (
          name, alias, display_name, quantity, group_id, unit_id, is_archived, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)
        `,
        [
          trimmedName,
          trimmedAlias,
          trimmedDisplayName,
          normalizedQuantity,
          normalizedGroupId,
          normalizedUnitId,
          now,
          now,
        ],
      );
      itemId = result.lastID;
    } else {
      const existing = await getItemRowById(id);
      if (!existing) {
        const error = new Error('Item not found.');
        error.statusCode = 404;
        throw error;
      }
      if ((existing.usage_count || 0) > 0) {
        const error = new Error('Used items cannot be edited.');
        error.statusCode = 409;
        throw error;
      }
      await run(
        `
        UPDATE items
        SET name = ?, alias = ?, display_name = ?, quantity = ?, group_id = ?, unit_id = ?, updated_at = ?
        WHERE id = ?
        `,
        [
          trimmedName,
          trimmedAlias,
          trimmedDisplayName,
          normalizedQuantity,
          normalizedGroupId,
          normalizedUnitId,
          now,
          id,
        ],
      );
      await run('DELETE FROM item_variation_nodes WHERE item_id = ?', [id]);
    }

    const insertNodes = async (nodes, parentNodeId = null) => {
      for (const node of nodes) {
        const result = await run(
          `
          INSERT INTO item_variation_nodes (
            item_id, parent_node_id, kind, name, display_name, position,
            is_archived, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)
          `,
          [
            itemId,
            parentNodeId,
            node.kind,
            node.name,
            node.displayName,
            node.position,
            now,
            now,
          ],
        );
        await insertNodes(node.children, result.lastID);
      }
    };

    await insertNodes(sanitizedTree);

    await run('COMMIT');
    return getItemRowById(itemId);
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }
}

async function seedItemsIfEmpty() {
  const countRow = await get('SELECT COUNT(*) AS count FROM items');
  if ((countRow?.count || 0) > 0) {
    return;
  }

  const groups = await all('SELECT * FROM groups WHERE is_archived = 0 ORDER BY id ASC');
  const units = await all('SELECT * FROM units WHERE is_archived = 0 ORDER BY id ASC');
  const kraftGroup = groups.find((group) => normalizeUnitValue(group.name) === 'kraft') || groups[0];
  const chemicalGroup = groups.find((group) => normalizeUnitValue(group.name) === 'chemical') || groups[0];
  const sheetUnit = units.find((unit) => normalizeUnitValue(unit.symbol) === 'sheet') || units[0];
  const kilogramUnit = units.find((unit) => normalizeUnitValue(unit.symbol) === 'kg') || units[0] || sheetUnit;
  if (!kraftGroup || !sheetUnit) {
    return;
  }

  await saveItem({
    name: 'Bottle',
    alias: 'Classic Bottle',
    displayName: 'Bottle - 100',
    quantity: 100,
    groupId: kraftGroup.id,
    unitId: sheetUnit.id,
    variationTree: [
      {
        kind: 'property',
        name: 'Color',
        children: [
          {
            kind: 'value',
            name: 'Black',
            children: [
              {
                kind: 'property',
                name: 'Finish',
                children: [
                  { kind: 'value', name: 'Matte' },
                  { kind: 'value', name: 'Glossy' },
                ],
              },
            ],
          },
          {
            kind: 'value',
            name: 'White',
            children: [
              {
                kind: 'property',
                name: 'Finish',
                children: [{ kind: 'value', name: 'Glossy' }],
              },
            ],
          },
        ],
      },
    ],
  });
  if (chemicalGroup && kilogramUnit) {
    await saveItem({
      name: 'Glue Compound',
      alias: 'Adhesive',
      displayName: 'Glue Compound - 1',
      quantity: 1,
      groupId: chemicalGroup.id,
      unitId: kilogramUnit.id,
      variationTree: [
        {
          kind: 'property',
          name: 'Cure Speed',
          children: [{ kind: 'value', name: 'Fast Cure' }],
        },
      ],
    });
  }
}

function findLeafVariationNodes(nodes = [], currentPath = []) {
  const leaves = [];
  for (const node of nodes) {
    const nextPath = [...currentPath, node.id];
    if (node.kind === 'value' && (!node.children || node.children.length === 0)) {
      leaves.push({
        id: node.id,
        displayName: node.displayName || '',
        path: nextPath,
      });
      continue;
    }
    leaves.push(...findLeafVariationNodes(node.children || [], nextPath));
  }
  return leaves;
}

async function seedOrdersIfEmpty() {
  const countRow = await get('SELECT COUNT(*) AS count FROM orders');
  if ((countRow?.count || 0) > 0) {
    return;
  }

  await ensureMockOrdersPresent();
}

async function ensureMockOrdersPresent() {
  const existingOrders = await getOrders();
  const existingOrderNos = new Set(
    existingOrders.map((row) => String(row.order_no || '').trim().toLowerCase()),
  );

  const clientRows = await getClientsWithUsage();
  const itemRows = await getItemsWithUsage();
  const activeClients = clientRows
    .filter((row) => !row.is_archived)
    .map((row) => rowToClientDto(row));
  const activeItems = [];
  for (const row of itemRows) {
    if (row.is_archived) {
      continue;
    }
    activeItems.push(await rowToItemDto(row));
  }

  if (activeClients.length === 0 || activeItems.length === 0) {
    return;
  }

  const primaryClient = activeClients[0];
  const secondaryClient = activeClients[1] || activeClients[0];
  const primaryItem = activeItems[0];
  const secondaryItem = activeItems[1] || activeItems[0];
  const primaryLeaves = findLeafVariationNodes(primaryItem.variationTree || []);
  const secondaryLeaves = findLeafVariationNodes(secondaryItem.variationTree || []);
  const firstLeaf = primaryLeaves[0];
  const secondLeaf = primaryLeaves[1] || firstLeaf;
  const thirdLeaf = secondaryLeaves[0] || firstLeaf;

  if (!firstLeaf || !secondLeaf || !thirdLeaf) {
    return;
  }

  const mockOrders = [
    {
      orderNo: '123456',
      client: primaryClient,
      poNumber: 'PO-123456',
      clientCode: primaryClient.alias,
      item: primaryItem,
      leaf: firstLeaf,
      quantity: 1000,
      status: 'notStarted',
    },
    {
      orderNo: '123457',
      client: primaryClient,
      poNumber: 'PO-123457',
      clientCode: primaryClient.alias,
      item: primaryItem,
      leaf: secondLeaf,
      quantity: 1000,
      status: 'inProgress',
    },
    {
      orderNo: '123458',
      client: secondaryClient,
      poNumber: 'PO-123458',
      clientCode: secondaryClient.alias,
      item: secondaryItem,
      leaf: thirdLeaf,
      quantity: 1000,
      status: 'completed',
    },
    {
      orderNo: '123459',
      client: secondaryClient,
      poNumber: 'PO-123459',
      clientCode: secondaryClient.alias,
      item: primaryItem,
      leaf: firstLeaf,
      quantity: 1000,
      status: 'delayed',
    },
  ];

  for (const order of mockOrders) {
    if (existingOrderNos.has(order.orderNo.toLowerCase())) {
      continue;
    }
    await saveOrder({
      orderNo: order.orderNo,
      clientId: order.client.id,
      clientName: order.client.name,
      poNumber: order.poNumber,
      clientCode: order.clientCode,
      itemId: order.item.id,
      itemName: order.item.displayName,
      variationLeafNodeId: order.leaf.id,
      variationPathLabel: order.leaf.displayName,
      variationPathNodeIds: order.leaf.path,
      quantity: order.quantity,
      status: order.status,
      startDate: '2026-04-10T00:00:00.000Z',
      endDate: '2026-05-15T00:00:00.000Z',
    });
  }
}

async function getUnitsWithUsage() {
  return all(`
    SELECT
      units.*,
      COUNT(materials.id) AS usage_count
    FROM units
    LEFT JOIN materials ON materials.unit_id = units.id
    GROUP BY units.id
    ORDER BY units.is_archived ASC, LOWER(units.name) ASC, LOWER(units.symbol) ASC
  `);
}

async function findUnitDuplicate({ name, symbol, excludeId = null }) {
  const rows = await all('SELECT id, name, symbol FROM units');
  const normalizedName = normalizeUnitValue(name);
  const normalizedSymbol = normalizeUnitValue(symbol);
  return rows.find((row) => {
    if (excludeId != null && row.id === excludeId) {
      return false;
    }
    return (
      normalizeUnitValue(row.name) === normalizedName &&
      normalizeUnitValue(row.symbol) === normalizedSymbol
    );
  }) || null;
}

async function saveUnit({ name, symbol, notes = '', id = null }) {
  const trimmedName = String(name || '').trim();
  const trimmedSymbol = String(symbol || '').trim();
  const trimmedNotes = String(notes || '').trim();
  if (!trimmedName || !trimmedSymbol) {
    throw new Error('name and symbol are required.');
  }

  const duplicate = await findUnitDuplicate({
    name: trimmedName,
    symbol: trimmedSymbol,
    excludeId: id,
  });
  if (duplicate) {
    const error = new Error('A unit with the same name and symbol already exists.');
    error.statusCode = 409;
    throw error;
  }

  const now = new Date().toISOString();
  if (id == null) {
    const result = await run(
      `
      INSERT INTO units (name, symbol, notes, is_archived, created_at, updated_at)
      VALUES (?, ?, ?, 0, ?, ?)
      `,
      [trimmedName, trimmedSymbol, trimmedNotes, now, now],
    );
    return getUnitRowById(result.lastID);
  }

  const existing = await getUnitRowById(id);
  if (!existing) {
    const error = new Error('Unit not found.');
    error.statusCode = 404;
    throw error;
  }
  if ((existing.usage_count || 0) > 0) {
    const error = new Error('Used units cannot be edited.');
    error.statusCode = 409;
    throw error;
  }

  await run(
    'UPDATE units SET name = ?, symbol = ?, notes = ?, updated_at = ? WHERE id = ?',
    [trimmedName, trimmedSymbol, trimmedNotes, now, id],
  );
  return getUnitRowById(id);
}

async function getMaterialRowByBarcode(barcode) {
  const normalized = normalizeBarcode(barcode);
  const rows = await all('SELECT * FROM materials');
  return rows.find((item) => normalizeBarcode(item.barcode) === normalized) || null;
}

async function incrementMaterialScanCount(barcode) {
  const row = await getMaterialRowByBarcode(barcode);
  if (!row) {
    return null;
  }
  await run('UPDATE materials SET scan_count = scan_count + 1 WHERE id = ?', [row.id]);
  return get('SELECT * FROM materials WHERE id = ?', [row.id]);
}

async function createRunFromTemplate(templateId, name) {
  const templateRow = await get(
    'SELECT * FROM pipeline_templates WHERE id = ?',
    [templateId],
  );
  if (!templateRow) {
    return null;
  }
  const template = rowToTemplate(templateRow);
  const now = new Date().toISOString();
  const runId = `run-${Date.now()}`;
  const nodeStatuses = Object.fromEntries(
    template.nodes.map((node) => [node.id, 'pending']),
  );

  await run(
    `
    INSERT INTO pipeline_runs (
      id, template_id, template_version, name, status, overrides_json,
      node_status_json, started_at, completed_at, created_at
    ) VALUES (?, ?, ?, ?, 'planned', ?, ?, NULL, NULL, ?)
    `,
    [
      runId,
      template.id,
      template.version,
      name || `Run ${new Date(now).toLocaleDateString('en-IN')}`,
      JSON.stringify({
        actualDurationHoursByNode: {},
        batchQuantityByNode: {},
        machineOverrideByNode: {},
      }),
      JSON.stringify(nodeStatuses),
      now,
    ],
  );

  const runRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [runId]);
  return rowToRun(runRow);
}

app.get('/api/materials', async (req, res) => {
  try {
    const rows = await all(
      'SELECT * FROM materials ORDER BY kind ASC, created_at DESC, barcode ASC',
    );
    res.json({ success: true, materials: rows.map(rowToMaterialDto) });
  } catch (error) {
    res.status(500).json({ success: false, materials: [], error: error.message });
  }
});

app.get('/api/materials/:barcode', async (req, res) => {
  try {
    const row = await getMaterialRowByBarcode(req.params.barcode);
    if (!row) {
      res.status(404).json({
        success: false,
        material: null,
        error: `No material found for barcode ${req.params.barcode}.`,
      });
      return;
    }
    res.json({ success: true, material: rowToMaterialDto(row), error: null });
  } catch (error) {
    res.status(500).json({ success: false, material: null, error: error.message });
  }
});

app.get('/api/units', async (req, res) => {
  try {
    const rows = await getUnitsWithUsage();
    res.json({ success: true, units: rows.map(rowToUnitDto), error: null });
  } catch (error) {
    res.status(500).json({ success: false, units: [], error: error.message });
  }
});

app.post('/api/units', async (req, res) => {
  try {
    const unit = await saveUnit(req.body || {});
    res.status(201).json({ success: true, unit: rowToUnitDto(unit), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      unit: null,
      error: error.message,
    });
  }
});

app.patch('/api/units/:id', async (req, res) => {
  try {
    const unit = await saveUnit({
      ...(req.body || {}),
      id: Number(req.params.id),
    });
    res.json({ success: true, unit: rowToUnitDto(unit), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      unit: null,
      error: error.message,
    });
  }
});

app.patch('/api/units/:id/archive', async (req, res) => {
  try {
    const id = Number(req.params.id);
    const existing = await getUnitRowById(id);
    if (!existing) {
      res.status(404).json({ success: false, unit: null, error: 'Unit not found.' });
      return;
    }
    await run('UPDATE units SET is_archived = 1, updated_at = ? WHERE id = ?', [
      new Date().toISOString(),
      id,
    ]);
    const updated = await getUnitRowById(id);
    res.json({ success: true, unit: rowToUnitDto(updated), error: null });
  } catch (error) {
    res.status(500).json({ success: false, unit: null, error: error.message });
  }
});

app.patch('/api/units/:id/restore', async (req, res) => {
  try {
    const id = Number(req.params.id);
    const existing = await getUnitRowById(id);
    if (!existing) {
      res.status(404).json({ success: false, unit: null, error: 'Unit not found.' });
      return;
    }
    await run('UPDATE units SET is_archived = 0, updated_at = ? WHERE id = ?', [
      new Date().toISOString(),
      id,
    ]);
    const updated = await getUnitRowById(id);
    res.json({ success: true, unit: rowToUnitDto(updated), error: null });
  } catch (error) {
    res.status(500).json({ success: false, unit: null, error: error.message });
  }
});

app.get('/api/groups', async (req, res) => {
  try {
    const rows = await getGroupsWithUsage();
    res.json({ success: true, groups: rows.map(rowToGroupDto), error: null });
  } catch (error) {
    res.status(500).json({ success: false, groups: [], error: error.message });
  }
});

app.get('/api/clients', async (req, res) => {
  try {
    const rows = await getClientsWithUsage();
    res.json({ success: true, clients: rows.map(rowToClientDto), error: null });
  } catch (error) {
    res.status(500).json({ success: false, clients: [], error: error.message });
  }
});

app.get('/api/orders', async (req, res) => {
  try {
    const rows = await getOrders();
    res.json({ success: true, orders: rows.map(rowToOrderDto), error: null });
  } catch (error) {
    res.status(500).json({ success: false, orders: [], error: error.message });
  }
});

app.post('/api/orders', async (req, res) => {
  try {
    const order = await saveOrder(req.body || {});
    res.status(201).json({ success: true, order: rowToOrderDto(order), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      order: null,
      error: error.message,
    });
  }
});

app.patch('/api/orders/:id/lifecycle', async (req, res) => {
  try {
    const order = await updateOrderLifecycle({
      ...(req.body || {}),
      id: Number(req.params.id),
    });
    res.json({ success: true, order: rowToOrderDto(order), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      order: null,
      error: error.message,
    });
  }
});

app.post('/api/clients', async (req, res) => {
  try {
    const client = await saveClient(req.body || {});
    res.status(201).json({ success: true, client: rowToClientDto(client), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      client: null,
      error: error.message,
    });
  }
});

app.patch('/api/clients/:id', async (req, res) => {
  try {
    const client = await saveClient({
      ...(req.body || {}),
      id: Number(req.params.id),
    });
    res.json({ success: true, client: rowToClientDto(client), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      client: null,
      error: error.message,
    });
  }
});

app.patch('/api/clients/:id/archive', async (req, res) => {
  try {
    const id = Number(req.params.id);
    const existing = await getClientRowById(id);
    if (!existing) {
      res.status(404).json({ success: false, client: null, error: 'Client not found.' });
      return;
    }
    await run('UPDATE clients SET is_archived = 1, updated_at = ? WHERE id = ?', [
      new Date().toISOString(),
      id,
    ]);
    const updated = await getClientRowById(id);
    res.json({ success: true, client: rowToClientDto(updated), error: null });
  } catch (error) {
    res.status(500).json({ success: false, client: null, error: error.message });
  }
});

app.patch('/api/clients/:id/restore', async (req, res) => {
  try {
    const id = Number(req.params.id);
    const existing = await getClientRowById(id);
    if (!existing) {
      res.status(404).json({ success: false, client: null, error: 'Client not found.' });
      return;
    }
    await run('UPDATE clients SET is_archived = 0, updated_at = ? WHERE id = ?', [
      new Date().toISOString(),
      id,
    ]);
    const updated = await getClientRowById(id);
    res.json({ success: true, client: rowToClientDto(updated), error: null });
  } catch (error) {
    res.status(500).json({ success: false, client: null, error: error.message });
  }
});

app.get('/api/items', async (req, res) => {
  try {
    const rows = await getItemsWithUsage();
    const items = await Promise.all(rows.map(rowToItemDto));
    res.json({ success: true, items, error: null });
  } catch (error) {
    res.status(500).json({ success: false, items: [], error: error.message });
  }
});

app.post('/api/items', async (req, res) => {
  try {
    const item = await saveItem(req.body || {});
    res.status(201).json({ success: true, item: await rowToItemDto(item), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      item: null,
      error: error.message,
    });
  }
});

app.patch('/api/items/:id', async (req, res) => {
  try {
    const item = await saveItem({
      ...(req.body || {}),
      id: Number(req.params.id),
    });
    res.json({ success: true, item: await rowToItemDto(item), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      item: null,
      error: error.message,
    });
  }
});

app.patch('/api/items/:id/archive', async (req, res) => {
  try {
    const id = Number(req.params.id);
    const existing = await getItemRowById(id);
    if (!existing) {
      res.status(404).json({ success: false, item: null, error: 'Item not found.' });
      return;
    }
    const now = new Date().toISOString();
    await run('UPDATE items SET is_archived = 1, updated_at = ? WHERE id = ?', [now, id]);
    await run('UPDATE item_variation_nodes SET is_archived = 1, updated_at = ? WHERE item_id = ?', [now, id]);
    const updated = await getItemRowById(id);
    res.json({ success: true, item: await rowToItemDto(updated), error: null });
  } catch (error) {
    res.status(500).json({ success: false, item: null, error: error.message });
  }
});

app.patch('/api/items/:id/restore', async (req, res) => {
  try {
    const id = Number(req.params.id);
    const existing = await getItemRowById(id);
    if (!existing) {
      res.status(404).json({ success: false, item: null, error: 'Item not found.' });
      return;
    }
    const now = new Date().toISOString();
    await run('UPDATE items SET is_archived = 0, updated_at = ? WHERE id = ?', [now, id]);
    await run('UPDATE item_variation_nodes SET is_archived = 0, updated_at = ? WHERE item_id = ?', [now, id]);
    const updated = await getItemRowById(id);
    res.json({ success: true, item: await rowToItemDto(updated), error: null });
  } catch (error) {
    res.status(500).json({ success: false, item: null, error: error.message });
  }
});

app.post('/api/groups', async (req, res) => {
  try {
    const group = await saveGroup(req.body || {});
    res.status(201).json({ success: true, group: rowToGroupDto(group), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      group: null,
      error: error.message,
    });
  }
});

app.patch('/api/groups/:id', async (req, res) => {
  try {
    const group = await saveGroup({
      ...(req.body || {}),
      id: Number(req.params.id),
    });
    res.json({ success: true, group: rowToGroupDto(group), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      group: null,
      error: error.message,
    });
  }
});

app.patch('/api/groups/:id/archive', async (req, res) => {
  try {
    const id = Number(req.params.id);
    const existing = await getGroupRowById(id);
    if (!existing) {
      res.status(404).json({ success: false, group: null, error: 'Group not found.' });
      return;
    }
    const activeChildren = await getActiveChildGroups(id);
    if (activeChildren.length > 0) {
      res.status(409).json({
        success: false,
        group: null,
        error: 'This group has active child groups. Reassign or archive them first.',
      });
      return;
    }
    await run('UPDATE groups SET is_archived = 1, updated_at = ? WHERE id = ?', [
      new Date().toISOString(),
      id,
    ]);
    const updated = await getGroupRowById(id);
    res.json({ success: true, group: rowToGroupDto(updated), error: null });
  } catch (error) {
    res.status(500).json({ success: false, group: null, error: error.message });
  }
});

app.patch('/api/groups/:id/restore', async (req, res) => {
  try {
    const id = Number(req.params.id);
    const existing = await getGroupRowById(id);
    if (!existing) {
      res.status(404).json({ success: false, group: null, error: 'Group not found.' });
      return;
    }
    await run('UPDATE groups SET is_archived = 0, updated_at = ? WHERE id = ?', [
      new Date().toISOString(),
      id,
    ]);
    const updated = await getGroupRowById(id);
    res.json({ success: true, group: rowToGroupDto(updated), error: null });
  } catch (error) {
    res.status(500).json({ success: false, group: null, error: error.message });
  }
});

app.post('/api/materials/parent', async (req, res) => {
  try {
    const payload = req.body || {};
    if (!payload.name || !payload.type || !payload.numberOfChildren) {
      res.status(400).json({
        success: false,
        material: null,
        error: 'name, type, and numberOfChildren are required.',
      });
      return;
    }

    const material = await createParentWithChildren(payload);
    res.status(201).json({ success: true, material, error: null });
  } catch (error) {
    res.status(500).json({ success: false, material: null, error: error.message });
  }
});

app.patch('/api/materials/:barcode/scan', async (req, res) => {
  try {
    const materialRow = await incrementMaterialScanCount(req.params.barcode);
    if (!materialRow) {
      res.status(404).json({
        success: false,
        material: null,
        error: `No material found for barcode ${req.params.barcode}.`,
      });
      return;
    }
    res.json({
      success: true,
      material: rowToMaterialDto(materialRow),
      error: null,
    });
  } catch (error) {
    res.status(500).json({ success: false, material: null, error: error.message });
  }
});

app.patch('/api/materials/:barcode/scan/reset', async (req, res) => {
  try {
    const row = await getMaterialRowByBarcode(req.params.barcode);
    if (!row) {
      res.status(404).json({
        success: false,
        material: null,
        error: `No material found for barcode ${req.params.barcode}.`,
      });
      return;
    }
    await run('UPDATE materials SET scan_count = 0 WHERE id = ?', [row.id]);
    const updatedRow = await get('SELECT * FROM materials WHERE id = ?', [row.id]);
    res.json({
      success: true,
      material: rowToMaterialDto(updatedRow),
      error: null,
    });
  } catch (error) {
    res.status(500).json({ success: false, material: null, error: error.message });
  }
});

app.get('/templates', async (req, res) => {
  try {
    const rows = await all(
      'SELECT * FROM pipeline_templates ORDER BY updated_at DESC, name ASC',
    );
    res.json({ success: true, templates: rows.map(rowToTemplate) });
  } catch (error) {
    res.status(500).json({ success: false, templates: [], error: error.message });
  }
});

app.post('/templates', async (req, res) => {
  try {
    const payload = req.body || {};
    if (!payload.id || !payload.name) {
      res.status(400).json({
        success: false,
        template: null,
        error: 'id and name are required.',
      });
      return;
    }
    const now = new Date().toISOString();
    await run(
      `
      INSERT INTO pipeline_templates (
        id, name, description, version, status, stage_labels_json, lane_labels_json,
        nodes_json, flows_json, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        payload.id,
        payload.name,
        payload.description || '',
        1,
        payload.status || 'draft',
        JSON.stringify(payload.stageLabels || []),
        JSON.stringify(payload.laneLabels || []),
        JSON.stringify(payload.nodes || []),
        JSON.stringify(payload.flows || []),
        now,
        now,
      ],
    );
    const row = await get('SELECT * FROM pipeline_templates WHERE id = ?', [payload.id]);
    res.status(201).json({ success: true, template: rowToTemplate(row) });
  } catch (error) {
    res.status(500).json({ success: false, template: null, error: error.message });
  }
});

app.put('/templates/:id', async (req, res) => {
  try {
    const existing = await get('SELECT * FROM pipeline_templates WHERE id = ?', [
      req.params.id,
    ]);
    if (!existing) {
      res.status(404).json({
        success: false,
        template: null,
        error: 'Template not found.',
      });
      return;
    }
    const payload = req.body || {};
    const nextVersion = (existing.version || 1) + 1;
    const now = new Date().toISOString();
    await run(
      `
      UPDATE pipeline_templates
      SET name = ?, description = ?, version = ?, status = ?, stage_labels_json = ?,
          lane_labels_json = ?, nodes_json = ?, flows_json = ?, updated_at = ?
      WHERE id = ?
      `,
      [
        payload.name || existing.name,
        payload.description || existing.description || '',
        nextVersion,
        payload.status || existing.status || 'draft',
        JSON.stringify(payload.stageLabels || parseJson(existing.stage_labels_json, [])),
        JSON.stringify(payload.laneLabels || parseJson(existing.lane_labels_json, [])),
        JSON.stringify(payload.nodes || parseJson(existing.nodes_json, [])),
        JSON.stringify(payload.flows || parseJson(existing.flows_json, [])),
        now,
        req.params.id,
      ],
    );
    const row = await get('SELECT * FROM pipeline_templates WHERE id = ?', [
      req.params.id,
    ]);
    res.json({ success: true, template: rowToTemplate(row) });
  } catch (error) {
    res.status(500).json({ success: false, template: null, error: error.message });
  }
});

app.get('/templates/:id', async (req, res) => {
  try {
    const row = await get('SELECT * FROM pipeline_templates WHERE id = ?', [
      req.params.id,
    ]);
    if (!row) {
      res.status(404).json({
        success: false,
        template: null,
        error: 'Template not found.',
      });
      return;
    }
    res.json({ success: true, template: rowToTemplate(row) });
  } catch (error) {
    res.status(500).json({ success: false, template: null, error: error.message });
  }
});

app.get('/runs', async (req, res) => {
  try {
    const { template_id: templateId } = req.query;
    const rows = templateId
      ? await all(
          'SELECT * FROM pipeline_runs WHERE template_id = ? ORDER BY created_at DESC',
          [templateId],
        )
      : await all('SELECT * FROM pipeline_runs ORDER BY created_at DESC');
    const runs = [];
    for (const row of rows) {
      runs.push(await rowToRun(row));
    }
    res.json({ success: true, runs });
  } catch (error) {
    res.status(500).json({ success: false, runs: [], error: error.message });
  }
});

app.post('/runs', async (req, res) => {
  try {
    const { templateId, name } = req.body || {};
    if (!templateId) {
      res.status(400).json({
        success: false,
        run: null,
        error: 'templateId is required.',
      });
      return;
    }
    const run = await createRunFromTemplate(templateId, name);
    if (!run) {
      res.status(404).json({
        success: false,
        run: null,
        error: 'Template not found.',
      });
      return;
    }
    res.status(201).json({ success: true, run });
  } catch (error) {
    res.status(500).json({ success: false, run: null, error: error.message });
  }
});

app.get('/runs/:id', async (req, res) => {
  try {
    const row = await get('SELECT * FROM pipeline_runs WHERE id = ?', [req.params.id]);
    if (!row) {
      res.status(404).json({ success: false, run: null, error: 'Run not found.' });
      return;
    }
    res.json({ success: true, run: await rowToRun(row) });
  } catch (error) {
    res.status(500).json({ success: false, run: null, error: error.message });
  }
});

app.put('/runs/:id/node-status', async (req, res) => {
  try {
    const runRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [req.params.id]);
    if (!runRow) {
      res.status(404).json({ success: false, run: null, error: 'Run not found.' });
      return;
    }

    const payload = req.body || {};
    const nodeId = payload.nodeId;
    if (!nodeId || !payload.status) {
      res.status(400).json({
        success: false,
        run: null,
        error: 'nodeId and status are required.',
      });
      return;
    }

    const nodeStatuses = parseJson(runRow.node_status_json, {});
    nodeStatuses[nodeId] = payload.status;

    const overrides = parseJson(runRow.overrides_json, {
      actualDurationHoursByNode: {},
      batchQuantityByNode: {},
      machineOverrideByNode: {},
    });

    if (payload.actualDurationHours !== undefined && payload.actualDurationHours !== null) {
      overrides.actualDurationHoursByNode[nodeId] = Number(payload.actualDurationHours);
    }
    if (payload.batchQuantity !== undefined && payload.batchQuantity !== null) {
      overrides.batchQuantityByNode[nodeId] = Number(payload.batchQuantity);
    }
    if (payload.machineOverride) {
      overrides.machineOverrideByNode[nodeId] = payload.machineOverride;
    }

    await run(
      'UPDATE pipeline_runs SET node_status_json = ?, overrides_json = ? WHERE id = ?',
      [JSON.stringify(nodeStatuses), JSON.stringify(overrides), req.params.id],
    );
    const updatedRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [
      req.params.id,
    ]);
    res.json({ success: true, run: await rowToRun(updatedRow) });
  } catch (error) {
    res.status(500).json({ success: false, run: null, error: error.message });
  }
});

app.post('/runs/:id/barcodes', async (req, res) => {
  try {
    const runRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [req.params.id]);
    if (!runRow) {
      res.status(404).json({ success: false, run: null, error: 'Run not found.' });
      return;
    }

    const payload = req.body || {};
    if (!payload.nodeId || !payload.barcode) {
      res.status(400).json({
        success: false,
        run: null,
        error: 'nodeId and barcode are required.',
      });
      return;
    }

    const materialRow = await incrementMaterialScanCount(payload.barcode);
    if (!materialRow) {
      res.status(404).json({
        success: false,
        run: null,
        error: `No material found for barcode ${payload.barcode}.`,
      });
      return;
    }
    const material = rowToMaterialDto(materialRow);
    const barcodeInputId = `barcode-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
    await run(
      `
      INSERT INTO run_barcode_inputs (
        id, run_id, node_id, barcode, material_id, material_payload_json, scanned_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      `,
      [
        barcodeInputId,
        req.params.id,
        payload.nodeId,
        material.barcode,
        String(material.id || ''),
        JSON.stringify({
          barcode: material.barcode,
          materialName: material.name,
          materialType: material.type,
          scanCount: material.scanCount,
        }),
        new Date().toISOString(),
      ],
    );

    const updatedRunRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [
      req.params.id,
    ]);
    res.json({ success: true, run: await rowToRun(updatedRunRow) });
  } catch (error) {
    res.status(500).json({ success: false, run: null, error: error.message });
  }
});

function startServer() {
  return initDb().then(
    () =>
      new Promise((resolve) => {
        const server = app.listen(PORT, '0.0.0.0', () => {
          console.log(`Paper backend running on port ${PORT} using ${DB_PATH}`);
          resolve(server);
        });
      }),
  );
}

if (require.main === module) {
  startServer().catch((error) => {
    console.error('Failed to initialize backend:', error);
    process.exit(1);
  });
}

module.exports = {
  app,
  initDb,
  startServer,
  closeDb,
  saveUnit,
  saveClient,
  saveItem,
  saveOrder,
  ensureMockOrdersPresent,
  updateOrderLifecycle,
  getOrders,
  getUnitsWithUsage,
  getGroupsWithUsage,
  getClientsWithUsage,
  getItemsWithUsage,
  rowToClientDto,
  rowToOrderDto,
  rowToItemDto,
};
