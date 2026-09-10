const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// A component group holds items that each carry their own unit, so asking the
// group for one is asking a question its members already answer. The UI stopped
// offering the field; this is the half that has to agree.
test('a component group saves without a unit, an item group still needs one', async () => {
  process.env.DB_PATH = path.join(
    mkdtempSync(path.join(tmpdir(), 'paper-component-unit-')),
    'paper.db',
  );
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'component-owner@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'ComponentOwner1';

  const backendPath = require.resolve('../server.js');
  delete require.cache[backendPath];
  const backend = require('../server.js');

  try {
    await backend.resetAndSeedDemoData();
    const { server, port } = await listen(backend.app);
    const baseUrl = `http://127.0.0.1:${port}`;

    try {
      const owner = await request(baseUrl, '/api/auth/login', 'POST', null, {
        email: 'component-owner@paper.local',
        password: 'ComponentOwner1',
      });
      assert.equal(owner.status, 200);
      const token = owner.body.token;

      const component = await request(
        baseUrl,
        '/api/groups',
        'POST',
        token,
        {
          name: 'Valve Body',
          groupType: 'item',
          groupStructure: 'component',
        },
      );
      assert.equal(component.status, 201, JSON.stringify(component.body));
      assert.equal(component.body.group.groupStructure, 'component');
      assert.equal(component.body.group.unitId ?? null, null);

      // Everything the component dialog sends on create must survive the
      // round trip: it no longer goes through the inventory parent-material
      // path, so this is the only write that stores any of it.
      const full = await request(baseUrl, '/api/groups', 'POST', token, {
        name: 'Lower Assembly',
        groupType: 'item',
        groupStructure: 'component',
        description: 'A sub-assembly',
        parentGroupId: component.body.group.id,
        itemFormSections: { order: ['identity', 'media'], hidden: ['pricing'] },
      });
      assert.equal(full.status, 201, JSON.stringify(full.body));
      const created = full.body.group;
      assert.equal(created.groupStructure, 'component');
      assert.equal(created.description, 'A sub-assembly');
      assert.equal(created.parentGroupId, component.body.group.id);
      assert.equal(created.unitId ?? null, null);

      const listed = await request(baseUrl, '/api/groups', 'GET', token);
      assert.equal(listed.status, 200);
      const readBack = listed.body.groups.find((group) => group.id === created.id);
      assert.ok(readBack, 'the created component must appear in the list the dialog reads');
      assert.equal(readBack.groupStructure, 'component');
      assert.ok(readBack.itemFormSections, 'the item-form layout must be stored on create');

      // The guard still holds where it means something.
      const plain = await request(baseUrl, '/api/groups', 'POST', token, {
        name: 'Plain Group',
        groupType: 'item',
      });
      assert.equal(plain.status >= 400, true, 'an item group still needs a unit');
      assert.match(String(plain.body.error || ''), /unitId is required/i);
    } finally {
      await closeServer(server);
    }
  } finally {
    await backend.closeDatabase?.();
  }
});

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
