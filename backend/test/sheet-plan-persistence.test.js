const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// A sheet plan is worth nothing if it does not survive being closed.
//
// The baseline is stored as opaque JSON, which means new fields persist without
// a migration — and also means nothing would complain if the server quietly
// dropped them. So this reads the plan back from a FRESH GET rather than from
// the PATCH response: an echoed request body proves the server parsed it, not
// that the database kept it.

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => {
      resolve({ server, port: server.address().port });
    });
    server.on('error', reject);
  });
}

function closeServer(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}

// Exactly what the Dart PenPaperBaseline.toJson emits for a planned sheet:
// a 4' x 8' sheet of mild steel sheared into strips and blanked.
const SHEET_PLAN = {
  mode: 'whole',
  materialType: '',
  inputKg: 0,
  outputKg: 0,
  notes: '',
  stageReconciliations: [],
  sheetWidthInches: 48,
  sheetHeightInches: 96,
  sheetThicknessMm: 1.6,
  faceUnit: 'in',
  gaugeUnit: 'mm',
  materialName: 'Steel / MS',
  primaryAxis: 'columns',
  bands: [
    { sizeMm: 300, count: 4 },
    { sizeMm: 150, count: 1 },
  ],
  // Region keys are stringified on the way out and parsed back on the way in;
  // -1 is the offcut region, which must survive as a key and not be coerced.
  subCuts: {
    0: [{ sizeMm: 1200, count: 2 }],
    1: [{ sizeMm: 600, count: 4 }],
    '-1': [{ sizeMm: 400, count: 1 }],
  },
  kerfMm: 3,
  edgeTrimMm: 10,
  plannedPartId: 42,
  plannedPartName: 'MS Bracket 60x40',
};

test('a sheet plan survives being saved and reopened', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-sheet-plan-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'sheets@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const { token } = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: process.env.PAPER_SUPER_ADMIN_EMAIL,
        password: process.env.PAPER_SUPER_ADMIN_PASSWORD,
      }),
    }).then((r) => r.json());
    const authHeaders = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    };
    const send = async (method, p, payload) => {
      const r = await fetch(`${baseUrl}${p}`, {
        method,
        headers: authHeaders,
        body: JSON.stringify(payload),
      });
      return { status: r.status, body: await r.json() };
    };
    const get = async (p) => {
      const r = await fetch(`${baseUrl}${p}`, { headers: authHeaders });
      return { status: r.status, body: await r.json() };
    };

    const groups = await get('/api/groups');
    const units = await get('/api/units');
    const groupId = groups.body.groups[0].id;
    const unitId = units.body.units[0].id;

    const created = await send('POST', '/api/items', {
      name: 'Sheet Plan Round Trip',
      groupId,
      unitId,
      penPaperBaseline: SHEET_PLAN,
    });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    const itemId = created.body.item.id;

    // The real check: read it back fresh, as reopening the editor would.
    const reread = await get(`/api/items/${itemId}`);
    assert.equal(reread.status, 200);
    const stored = reread.body.item.penPaperBaseline;
    assert.ok(stored, 'the plan came back at all');

    // Every field, not a spot check — a dropped one is silent.
    assert.deepEqual(
      stored,
      SHEET_PLAN,
      'the plan came back different from how it went in'
    );

    // Named individually so a failure says which part of the plan was lost.
    assert.equal(stored.sheetWidthInches, 48);
    assert.equal(stored.sheetThicknessMm, 1.6);
    assert.equal(stored.materialName, 'Steel / MS');
    assert.equal(stored.kerfMm, 3);
    assert.equal(stored.edgeTrimMm, 10);
    assert.equal(stored.primaryAxis, 'columns');
    assert.equal(stored.bands.length, 2);
    assert.equal(stored.bands[0].sizeMm, 300);
    assert.equal(stored.plannedPartName, 'MS Bracket 60x40');
    // The offcut region's negative key is the one most likely to be mangled.
    assert.deepEqual(stored.subCuts['-1'], [{ sizeMm: 400, count: 1 }]);
    assert.deepEqual(stored.subCuts['0'], [{ sizeMm: 1200, count: 2 }]);

    // Editing the plan replaces it rather than merging into the old one.
    const edited = await send('PATCH', `/api/items/${itemId}`, {
      name: 'Sheet Plan Round Trip',
      groupId,
      unitId,
      penPaperBaseline: {
        ...SHEET_PLAN,
        materialName: 'Aluminium',
        bands: [{ sizeMm: 300, count: 4 }],
      },
    });
    assert.equal(edited.status, 200);
    const afterEdit = await get(`/api/items/${itemId}`);
    assert.equal(afterEdit.body.item.penPaperBaseline.materialName, 'Aluminium');
    assert.equal(
      afterEdit.body.item.penPaperBaseline.bands.length,
      1,
      'the removed band is gone, not merged back in'
    );

    // A plan on the pipeline template persists the same way, which is what
    // makes step 3 of Master Data resolution possible.
    const templates = await get('/api/production/pipeline-templates');
    assert.equal(templates.status, 200, JSON.stringify(templates.body));
    const template = templates.body.templates[0];
    assert.ok(template, 'the seed has a pipeline template to plan against');

    const saved = await send(
      'PUT',
      `/api/production/pipeline-templates/${template.id}`,
      { ...template, penPaperBaseline: SHEET_PLAN }
    );
    assert.equal(saved.status, 200, JSON.stringify(saved.body));

    const back = await get('/api/production/pipeline-templates');
    const onTemplate = back.body.templates.find((row) => row.id === template.id)
      .penPaperBaseline;
    assert.deepEqual(
      onTemplate,
      SHEET_PLAN,
      'a plan on the pipeline is what Master Data step 3 inherits from'
    );
    // --- the (variant, pipeline) pair, which is the record the editor
    // --- actually resolves against when it reopens ---
    const pipelineId = template.id;
    const pair = await send(
      'PUT',
      `/api/items/${itemId}/master-data/${encodeURIComponent(pipelineId)}`,
      { baseline: SHEET_PLAN }
    );
    assert.equal(pair.status, 200, JSON.stringify(pair.body));
    assert.deepEqual(pair.body.record.baseline, SHEET_PLAN);

    // Read back through resolution, the way reopening the item does. This is
    // the path that matters: a plan stored but not resolvable is a plan lost.
    const resolved = await get(
      `/api/items/${itemId}/master-data/resolve?pipelineId=${encodeURIComponent(pipelineId)}`
    );
    assert.equal(resolved.status, 200, JSON.stringify(resolved.body));
    assert.equal(resolved.body.matched, true);
    assert.equal(resolved.body.source, 'pair', 'an exact pair, not inherited');
    assert.deepEqual(
      resolved.body.baseline,
      SHEET_PLAN,
      'the plan came back through resolution different from how it went in'
    );

    // And listed among the item's records, so it can be found and deleted.
    const listed = await get(`/api/items/${itemId}/master-data`);
    assert.equal(listed.status, 200);
    const record = listed.body.records.find(
      (row) => row.pipelineId === pipelineId
    );
    assert.ok(record, 'the pair is listed against the item');
    assert.equal(record.baseline.materialName, 'Steel / MS');
    assert.equal(record.baseline.kerfMm, 3);
  } finally {
    await closeServer(server);
  }
});
