const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

const { weightKg, validate } = require('../modules/items/material-types');

// The material master exists for one sum: volume × density = weight. So the
// arithmetic is tested directly, and the API is tested for the ways a density
// can be entered wrongly — a density out by a thousand is invisible in a form
// and catastrophic in a costing.

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

test('volume times density is weight', () => {
  // A 1219 × 2438 × 1.6 mm mild steel sheet: 4755 cm³ at 7.85 g/cm³.
  assert.equal(Math.round(weightKg(4755, 7.85) * 100) / 100, 37.33);
  // Water is the reference: a litre weighs a kilogram.
  assert.equal(weightKg(1000, 1), 1);
  // Nothing from nothing.
  assert.equal(weightKg(0, 7.85), 0);
  assert.equal(weightKg(4755, 0), 0);
  assert.equal(weightKg(-10, 7.85), 0);
});

test('a density in the wrong unit is refused, not stored', () => {
  // 7850 is steel in kg/m³. Stored as g/cm³ it would make every sheet weigh a
  // thousand times too much, and nothing on screen would look odd.
  const wrong = validate({ name: 'Steel', densityGCm3: 7850 });
  assert.ok(wrong.error);
  assert.match(wrong.error, /7\.85, not 7850/);

  const right = validate({ name: 'Steel', densityGCm3: 7.85 });
  assert.equal(right.error, undefined);
  assert.equal(right.density, 7.85);
});

test('a material needs a name and a real density', () => {
  assert.ok(validate({ name: '', densityGCm3: 7.85 }).error);
  assert.ok(validate({ name: 'Steel', densityGCm3: 0 }).error);
  assert.ok(validate({ name: 'Steel', densityGCm3: -1 }).error);
  assert.ok(validate({ name: 'Steel' }).error);
});

test('an unknown category falls back rather than being stored raw', () => {
  assert.equal(
    validate({ name: 'Steel', densityGCm3: 7.85, category: 'unobtanium' })
      .category,
    'other'
  );
  assert.equal(
    validate({ name: 'Nylon', densityGCm3: 1.15, category: 'PLASTIC' })
      .category,
    'plastic'
  );
});

test('the material master seeds, lists, edits and archives', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-materials-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'materials@paper.local';
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
    }).then((response) => response.json());
    const authHeaders = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    };

    const listed = await fetch(`${baseUrl}/api/material-types`, {
      headers: authHeaders,
    }).then((response) => response.json());
    assert.equal(listed.success, true);
    const byName = new Map(
      listed.materialTypes.map((material) => [material.name, material])
    );

    // The two the client named, and a spread of the rest. Mild steel is listed
    // as MS — what it is called on a shop floor — rather than the slash-joined
    // "Steel / MS" the seed originally shipped.
    assert.equal(byName.get('MS').densityGCm3, 7.85);
    assert.equal(byName.has('Steel / MS'), false);
    assert.equal(byName.get('Aluminium').densityGCm3, 2.7);
    assert.equal(byName.get('Brass').densityGCm3, 8.5);
    assert.equal(byName.get('Titanium').densityGCm3, 4.51);
    assert.equal(byName.get('Water').densityGCm3, 1);
    assert.ok(listed.materialTypes.length >= 36);

    // Every density is plausible: none in kg/m³ by mistake.
    for (const material of listed.materialTypes) {
      assert.ok(
        material.densityGCm3 > 0 && material.densityGCm3 < 30,
        `${material.name} has an implausible density ${material.densityGCm3}`
      );
    }

    // Plastics are lighter than water, metals heavier — a coarse check that
    // the whole table is not off by a factor.
    assert.ok(byName.get('Polypropylene').densityGCm3 < 1);
    assert.ok(byName.get('Gold').densityGCm3 > 19);

    const created = await fetch(`${baseUrl}/api/material-types`, {
      method: 'POST',
      headers: authHeaders,
      body: JSON.stringify({
        name: 'Inconel 625',
        densityGCm3: 8.44,
        category: 'metal',
      }),
    }).then((response) => response.json());
    assert.equal(created.success, true, JSON.stringify(created));
    assert.equal(created.materialType.densityGCm3, 8.44);

    // A shop's own brass is whatever its supplier ships.
    const edited = await fetch(
      `${baseUrl}/api/material-types/${byName.get('Brass').id}`,
      {
        method: 'PATCH',
        headers: authHeaders,
        body: JSON.stringify({ densityGCm3: 8.47 }),
      }
    ).then((response) => response.json());
    assert.equal(edited.materialType.densityGCm3, 8.47);
    assert.equal(edited.materialType.name, 'Brass', 'the name survived');

    const duplicate = await fetch(`${baseUrl}/api/material-types`, {
      method: 'POST',
      headers: authHeaders,
      body: JSON.stringify({ name: 'brass', densityGCm3: 8.5 }),
    });
    assert.equal(duplicate.status, 409, 'two Brass rows is unanswerable');

    const badUnit = await fetch(`${baseUrl}/api/material-types`, {
      method: 'POST',
      headers: authHeaders,
      body: JSON.stringify({ name: 'Steel in kg/m3', densityGCm3: 7850 }),
    });
    assert.equal(badUnit.status, 400);

    // Archived, not deleted: a plan from last year names its material.
    const archived = await fetch(
      `${baseUrl}/api/material-types/${created.materialType.id}`,
      { method: 'DELETE', headers: authHeaders }
    ).then((response) => response.json());
    assert.equal(archived.success, true);

    const after = await fetch(`${baseUrl}/api/material-types`, {
      headers: authHeaders,
    }).then((response) => response.json());
    assert.equal(
      after.materialTypes.some((m) => m.name === 'Inconel 625'),
      false
    );
    const withArchived = await fetch(
      `${baseUrl}/api/material-types?includeArchived=1`,
      { headers: authHeaders }
    ).then((response) => response.json());
    assert.equal(
      withArchived.materialTypes.some((m) => m.name === 'Inconel 625'),
      true
    );
  } finally {
    await closeServer(server);
  }
});
