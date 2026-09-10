const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// The `+` expression adds a value to an existing top-level property by
// re-sending the whole variation tree with one extra child. The client then
// looks the new value up and throws if it is missing, so this pins the one
// thing that lookup depends on: the value comes back after saving.
test('a value appended to a top-level property is saved and read back', async () => {
  process.env.DB_PATH = path.join(
    mkdtempSync(path.join(tmpdir(), 'paper-var-append-')),
    'paper.db',
  );
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'var-owner@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'VarOwner1234';

  const backendPath = require.resolve('../server.js');
  delete require.cache[backendPath];
  const backend = require('../server.js');

  try {
    await backend.resetAndSeedDemoData();
    const groupRow = (await backend.getGroupsWithUsage()).find(
      (row) => !row.is_archived,
    );
    const unitRow = (await backend.getUnitsWithUsage()).find(
      (row) => !row.is_archived,
    );
    assert.ok(groupRow && unitRow, 'expected a seeded group and unit');

    const { server, port } = await listen(backend.app);
    const baseUrl = `http://127.0.0.1:${port}`;

    try {
      const owner = await login(
        baseUrl,
        'var-owner@paper.local',
        'VarOwner1234',
      );

      const created = await request(baseUrl, '/api/items', 'POST', owner.token, {
        name: 'Billet',
        displayName: 'Billet',
        groupId: groupRow.id,
        unitId: unitRow.id,
        variationTree: [
          {
            kind: 'property',
            name: 'Initial State',
            inputType: 'Text',
            children: [{ kind: 'value', name: 'Raw', children: [] }],
          },
        ],
      });
      assert.equal(created.status, 201, JSON.stringify(created.body));

      const item = created.body.item;
      const property = item.variationTree[0];
      assert.equal(property.name, 'Initial State');

      // Exactly what the client sends: the tree as it stands, plus one value.
      const appended = await request(
        baseUrl,
        `/api/items/${item.id}`,
        'PATCH',
        owner.token,
        {
          name: item.name,
          displayName: item.displayName,
          groupId: item.groupId,
          unitId: item.unitId,
          variationTree: [
            {
              id: property.id,
              kind: 'property',
              name: property.name,
              inputType: property.inputType,
              children: [
                ...property.children.map((child) => ({
                  id: child.id,
                  kind: 'value',
                  name: child.name,
                  children: [],
                })),
                { kind: 'value', name: 'daw', children: [] },
              ],
            },
          ],
        },
      );
      assert.equal(appended.status, 200, JSON.stringify(appended.body));

      // Read it back fresh — the client looks the value up after refreshing.
      const reread = await request(
        baseUrl,
        `/api/items/${item.id}`,
        'GET',
        owner.token,
        null,
      );
      assert.equal(reread.status, 200);
      const rereadProperty = reread.body.item.variationTree.find(
        (node) => node.name === 'Initial State',
      );
      assert.ok(rereadProperty, 'the property survived the append');
      const names = (rereadProperty.children || [])
        .filter((child) => !child.isArchived)
        .map((child) => child.name);
      assert.deepEqual(
        names,
        ['Raw', 'daw'],
        'the appended value must be readable after saving',
      );
      // The property must not be silently retyped by the append.
      assert.equal(rereadProperty.inputType, 'Text');
    } finally {
      await closeServer(server);
    }
  } finally {
    await backend.closeDatabase?.();
  }
});

async function login(baseUrl, email, password) {
  const response = await request(baseUrl, '/api/auth/login', 'POST', null, {
    email,
    password,
  });
  assert.equal(response.status, 200);
  return response.body;
}

async function listen(app) {
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  return { server, port: server.address().port };
}

async function closeServer(server) {
  await new Promise((resolve, reject) =>
    server.close((error) => (error ? reject(error) : resolve())),
  );
}

async function request(baseUrl, pathname, method, token, body) {
  const headers = { Accept: 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const payload = body == null ? null : JSON.stringify(body);
  if (payload != null) {
    headers['Content-Type'] = 'application/json';
    headers['Content-Length'] = Buffer.byteLength(payload);
  }
  const response = await fetch(new URL(pathname, baseUrl), {
    method,
    headers,
    body: payload,
  });
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null };
}
