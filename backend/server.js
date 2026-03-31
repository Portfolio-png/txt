const express = require('express');
const cors = require('cors');
const path = require('path');
const sqlite3 = require('sqlite3').verbose();

const app = express();
const PORT = process.env.PORT || 8080;
const dbPath = path.join(__dirname, 'inventory_demo.db');
const db = new sqlite3.Database(dbPath);

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

function normalizeBarcode(value = '') {
  return String(value).replace(/\s+/g, '').replace(/[^\x20-\x7E]/g, '').trim().toUpperCase();
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

function parseLinkedChildBarcodes(value) {
  if (!value) {
    return [];
  }
  try {
    return JSON.parse(value);
  } catch (_) {
    return [];
  }
}

function rowToDto(row) {
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
    unit: row.unit || '',
    notes: row.notes || '',
    isParent: row.kind === 'parent',
    parentBarcode: row.parent_barcode || null,
    numberOfChildren: row.number_of_children || 0,
    linkedChildBarcodes: parseLinkedChildBarcodes(row.linked_child_barcodes),
    scanCount: row.scan_count || 0,
    createdAt: row.created_at,
  };
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

async function createParentWithChildren(payload) {
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
        barcode, name, type, grade, thickness, supplier, unit, notes,
        created_at, kind, parent_barcode, number_of_children,
        linked_child_barcodes, scan_count
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'parent', NULL, ?, ?, 0)
      `,
      [
        parentBarcode,
        payload.name,
        payload.type,
        payload.grade || '',
        payload.thickness || '',
        payload.supplier || '',
        payload.unit || '',
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
          barcode, name, type, grade, thickness, supplier, unit, notes,
          created_at, kind, parent_barcode, number_of_children,
          linked_child_barcodes, scan_count
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'child', ?, 0, ?, 0)
        `,
        [
          childBarcodes[index],
          `${payload.name} - Child ${index + 1}`,
          payload.type,
          payload.grade || '',
          payload.thickness || '',
          payload.supplier || '',
          payload.unit || '',
          payload.notes || '',
          createdAt,
          parentBarcode,
          JSON.stringify([]),
        ],
      );
    }

    await run('COMMIT');
    const parentRow = await get('SELECT * FROM materials WHERE id = ?', [parentResult.lastID]);
    return rowToDto(parentRow);
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }
}

app.get('/api/materials', async (req, res) => {
  try {
    const rows = await all(
      'SELECT * FROM materials ORDER BY kind ASC, created_at DESC, barcode ASC',
    );
    res.json({
      success: true,
      materials: rows.map(rowToDto),
    });
  } catch (error) {
    res.status(500).json({ success: false, materials: [], error: error.message });
  }
});

app.get('/api/materials/:barcode', async (req, res) => {
  try {
    const barcode = normalizeBarcode(req.params.barcode);
    const rows = await all('SELECT * FROM materials');
    const row = rows.find((item) => normalizeBarcode(item.barcode) === barcode);
    if (!row) {
      res.status(404).json({
        success: false,
        material: null,
        error: `No material found for barcode ${req.params.barcode}.`,
      });
      return;
    }

    res.json({ success: true, material: rowToDto(row), error: null });
  } catch (error) {
    res.status(500).json({ success: false, material: null, error: error.message });
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
    const barcode = normalizeBarcode(req.params.barcode);
    const rows = await all('SELECT * FROM materials');
    const row = rows.find((item) => normalizeBarcode(item.barcode) === barcode);
    if (!row) {
      res.status(404).json({
        success: false,
        material: null,
        error: `No material found for barcode ${req.params.barcode}.`,
      });
      return;
    }

    await run('UPDATE materials SET scan_count = scan_count + 1 WHERE id = ?', [row.id]);
    const updatedRow = await get('SELECT * FROM materials WHERE id = ?', [row.id]);
    res.json({ success: true, material: rowToDto(updatedRow), error: null });
  } catch (error) {
    res.status(500).json({ success: false, material: null, error: error.message });
  }
});

initDb()
  .then(() => {
    app.listen(PORT, () => {
      console.log(`Inventory demo backend running on http://localhost:${PORT}`);
    });
  })
  .catch((error) => {
    console.error('Failed to initialize demo backend:', error);
    process.exit(1);
  });
