const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// A Material variation property names its values from the material master, and
// each value carries the id of the type it stands for.
//
// The id is the whole point. Gauge — the input type this one is modelled on —
// stores a verbatim suffixed string ("0.711mm", "22G") and nothing downstream
// can get back to the table it came from. A value that keeps the id reaches an
// order line, a challan line and a stock row through the leaf node the
// selection already records, and brings the density with it.

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

test('a Material property keeps the material id on each of its values', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-var-material-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'material@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const loginResponse = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'material@paper.local',
        password: 'OwnerPass1234',
      }),
    });
    const { token } = await loginResponse.json();
    assert.ok(token, 'expected a login token');
    const authHeaders = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    };
    const send = async (method, route, body) => {
      const response = await fetch(`${baseUrl}${route}`, {
        method,
        headers: authHeaders,
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      return { status: response.status, body: await response.json() };
    };

    const materials = await send('GET', '/api/material-types');
    assert.equal(materials.status, 200, JSON.stringify(materials.body));
    const list = materials.body.materialTypes || materials.body.materials;
    assert.ok(Array.isArray(list) && list.length > 0, 'seeded material types');
    const brass = list.find((row) => row.name === 'Brass');
    const aluminium = list.find((row) => row.name === 'Aluminium');
    assert.ok(brass && aluminium, 'expected Brass and Aluminium in the seed');

    const groups = await send('GET', '/api/groups');
    const home = groups.body.groups.find(
      (group) =>
        group.groupType === 'item' && group.groupStructure !== 'combination',
    );
    const units = await send('GET', '/api/units');
    const unitId = units.body.units[0].id;

    const created = await send('POST', '/api/items', {
      name: 'Socket Body',
      groupId: home.id,
      unitId,
      variationTree: [
        {
          kind: 'property',
          name: 'Socket Alloy',
          inputType: 'Material',
          children: [
            {
              kind: 'value',
              name: 'Brass',
              code: 'BR',
              materialTypeId: brass.id,
              children: [],
            },
            {
              kind: 'value',
              name: 'Aluminium',
              code: 'AL',
              materialTypeId: aluminium.id,
              children: [],
            },
          ],
        },
      ],
    });
    assert.equal(created.status, 201, JSON.stringify(created.body));

    const readBack = await send('GET', `/api/items/${created.body.item.id}`);
    assert.equal(readBack.status, 200);
    const property = readBack.body.item.variationTree[0];
    assert.equal(property.inputType, 'Material');
    assert.equal(
      property.materialTypeId,
      null,
      'the property declares the type; only its values carry a link',
    );

    const byName = new Map(
      property.children.map((child) => [child.name, child]),
    );
    assert.equal(byName.get('Brass').materialTypeId, brass.id);
    assert.equal(byName.get('Aluminium').materialTypeId, aluminium.id);
    assert.equal(byName.get('Brass').code, 'BR');

    // An update must not drop the link — the item editor sends the whole tree
    // back on every save, so a field it forgets is a field that is erased.
    const renamed = await send('PATCH', `/api/items/${created.body.item.id}`, {
      name: 'Socket Body',
      displayName: 'Socket Body',
      groupId: home.id,
      unitId,
      variationTree: [
        {
          id: property.id,
          kind: 'property',
          name: 'Socket Alloy',
          inputType: 'Material',
          children: property.children.map((child) => ({
            id: child.id,
            kind: 'value',
            name: child.name,
            code: child.code,
            materialTypeId: child.materialTypeId,
            children: [],
          })),
        },
      ],
    });
    assert.equal(renamed.status, 200, JSON.stringify(renamed.body));
    const afterUpdate = new Map(
      renamed.body.item.variationTree[0].children.map((child) => [
        child.name,
        child,
      ]),
    );
    assert.equal(afterUpdate.get('Brass').materialTypeId, brass.id);
    assert.equal(afterUpdate.get('Aluminium').materialTypeId, aluminium.id);

    // A value with no link reads back as null rather than 0 or '', so "not a
    // material" is one answer and not three.
    const plain = await send('POST', '/api/items', {
      name: 'Plain Item',
      groupId: home.id,
      unitId,
      variationTree: [
        {
          kind: 'property',
          name: 'Colour',
          children: [{ kind: 'value', name: 'Black', code: 'BK', children: [] }],
        },
      ],
    });
    assert.equal(plain.status, 201, JSON.stringify(plain.body));
    assert.equal(
      plain.body.item.variationTree[0].children[0].materialTypeId,
      null,
    );
  } finally {
    await closeServer(server);
  }
});
