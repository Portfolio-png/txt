const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// The variation tree for masters other than items (modules/variations/*).
//
// The behaviour worth pinning is the version rule: a die's values are what
// items were derived under, so adding to them is free and changing them is
// not. A bug there would either silently rewrite history or block the one edit
// the shop floor actually makes all day.

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
    server.on('error', reject);
  });
}

function closeServer(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}

test('a die carries a versioned variation tree', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-variations-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'vars-owner@paper.local';
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
        email: 'vars-owner@paper.local',
        password: 'OwnerPass1234',
      }),
    });
    const { token } = await loginResponse.json();
    const authHeaders = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    };
    const getJson = async (p) => {
      const r = await fetch(`${baseUrl}${p}`, { headers: authHeaders });
      return { status: r.status, body: await r.json() };
    };
    const sendJson = async (method, p, payload) => {
      const r = await fetch(`${baseUrl}${p}`, {
        method,
        headers: authHeaders,
        body: payload === undefined ? undefined : JSON.stringify(payload),
      });
      return { status: r.status, body: await r.json() };
    };

    const dieResponse = await sendJson('POST', '/api/dies', {
      toolCode: 'DIE-VAR-1',
      status: 'active',
      ownership: 'owned',
    });
    const dieId = String(dieResponse.body.die?.id ?? dieResponse.body.id);
    assert.ok(dieId && dieId !== 'undefined', 'expected a created die');

    // --- empty to begin with, on version 1 ---
    const empty = await getJson(`/api/variations/die/${dieId}`);
    assert.equal(empty.status, 200);
    assert.deepEqual(empty.body.nodes, []);
    assert.equal(empty.body.version, 1);

    // --- the first tree ---
    const first = await sendJson('PUT', `/api/variations/die/${dieId}`, {
      nodes: [
        {
          kind: 'property',
          name: 'Cavity',
          inputType: 'Numeric',
          children: [
            { kind: 'value', name: '2', code: 'C2' },
            { kind: 'value', name: '4', code: 'C4' },
          ],
        },
        {
          kind: 'property',
          name: 'Profile',
          children: [{ kind: 'value', name: 'A' }],
        },
      ],
    });
    assert.equal(first.status, 200, JSON.stringify(first.body));
    assert.deepEqual(
      first.body.nodes.map((node) => node.name),
      ['Cavity', 'Profile'],
    );
    const cavity = first.body.nodes[0];
    assert.equal(cavity.inputType, 'Numeric');
    assert.deepEqual(cavity.children.map((child) => child.name), ['2', '4']);
    assert.deepEqual(cavity.children.map((child) => child.code), ['C2', 'C4']);

    // --- adding a value afterwards is allowed in place ---
    const added = await sendJson('PUT', `/api/variations/die/${dieId}`, {
      nodes: [
        {
          ...cavity,
          children: [...cavity.children, { kind: 'value', name: '6', code: 'C6' }],
        },
        first.body.nodes[1],
      ],
    });
    assert.equal(added.status, 200, JSON.stringify(added.body));
    assert.deepEqual(
      added.body.nodes[0].children.map((child) => child.name),
      ['2', '4', '6'],
      'a value added after creation goes in without a new version',
    );
    assert.equal(added.body.version, 1, 'adding does not bump the version');

    // --- changing one does not ---
    const renamed = JSON.parse(JSON.stringify(added.body.nodes));
    renamed[0].children[0].name = '3';
    const refused = await sendJson('PUT', `/api/variations/die/${dieId}`, {
      nodes: renamed,
    });
    assert.equal(refused.status, 409, JSON.stringify(refused.body));
    assert.equal(refused.body.requiresNewVersion, true);
    assert.ok(
      refused.body.changes.some((change) => change.includes("'2' -> '3'")),
      `expected the refusal to name the change: ${JSON.stringify(refused.body.changes)}`,
    );

    // --- and removing one does not either ---
    const dropped = JSON.parse(JSON.stringify(added.body.nodes));
    dropped[0].children.pop();
    const refusedDrop = await sendJson('PUT', `/api/variations/die/${dieId}`, {
      nodes: dropped,
    });
    assert.equal(refusedDrop.status, 409);
    assert.ok(
      refusedDrop.body.changes.some((change) => change.includes('removed')),
      'the refusal says what would have been removed',
    );

    // --- a new version is what declares the change ---
    const bumped = await sendJson('POST', `/api/variations/die/${dieId}/versions`, {
      label: 'Rev B',
      note: 'Cavity 2 reground to 3',
    });
    assert.equal(bumped.status, 201);
    assert.equal(bumped.body.version, 2);

    const applied = await sendJson('PUT', `/api/variations/die/${dieId}`, {
      version: 2,
      nodes: renamed,
    });
    assert.equal(applied.status, 200, JSON.stringify(applied.body));
    assert.deepEqual(
      applied.body.nodes[0].children.map((child) => child.name),
      ['3', '4', '6'],
    );
    assert.equal(applied.body.version, 2);
    assert.equal(applied.body.label, 'Rev B');

    // The bump is spent: a second corrective pass needs a second version.
    const again = JSON.parse(JSON.stringify(applied.body.nodes));
    again[0].children[0].name = '5';
    const refusedAgain = await sendJson('PUT', `/api/variations/die/${dieId}`, {
      nodes: again,
    });
    assert.equal(
      refusedAgain.status,
      409,
      'one declared version buys one editing pass, not an open season',
    );

    // Adding, though, is still free at any time.
    const stillAdding = JSON.parse(JSON.stringify(applied.body.nodes));
    stillAdding[1].children.push({ kind: 'value', name: 'B' });
    const addedLater = await sendJson('PUT', `/api/variations/die/${dieId}`, {
      nodes: stillAdding,
    });
    assert.equal(addedLater.status, 200, JSON.stringify(addedLater.body));
    assert.deepEqual(
      addedLater.body.nodes[1].children.map((child) => child.name),
      ['A', 'B'],
    );

    // --- refusals ---
    assert.equal(
      (await sendJson('PUT', `/api/variations/die/${dieId}`, {
        version: 2,
        nodes: [{ kind: 'property', name: '   ' }],
      })).status,
      400,
      'a node with no name is refused',
    );
    assert.equal((await getJson('/api/variations/teapot/1')).status, 400);
    assert.equal((await getJson('/api/variations/die/999999')).status, 404);

    // --- the tree goes when the die does ---
    assert.equal((await sendJson('DELETE', `/api/dies/${dieId}`)).status, 200);
    const orphan = await getJson(`/api/variations/die/${dieId}`);
    assert.equal(orphan.status, 404, 'a deleted die has no tree to read');
  } finally {
    await closeServer(server);
  }
});

test('a variation tree is gated by the master that owns it', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-variations-authz-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'vars-authz@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const login = async (email, password) => {
      const r = await fetch(`${baseUrl}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password }),
      });
      return (await r.json()).token;
    };
    const ownerToken = await login('vars-authz@paper.local', 'OwnerPass1234');
    const ownerHeaders = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${ownerToken}`,
    };

    const dieBody = await (
      await fetch(`${baseUrl}/api/dies`, {
        method: 'POST',
        headers: ownerHeaders,
        body: JSON.stringify({
          toolCode: 'DIE-VAR-AUTHZ',
          status: 'active',
          ownership: 'owned',
        }),
      })
    ).json();
    const dieId = String(dieBody.die?.id ?? dieBody.id);

    const created = await fetch(`${baseUrl}/api/users`, {
      method: 'POST',
      headers: ownerHeaders,
      body: JSON.stringify({
        name: 'Die Reader',
        email: 'die-reader@paper.local',
        password: 'ReaderPass1234',
        role: 'user',
        permissions: ['login.desktop'],
      }),
    });
    assert.equal(created.status, 201);

    const readerToken = await login('die-reader@paper.local', 'ReaderPass1234');
    const readerHeaders = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${readerToken}`,
    };

    // Staff read every module by default, so reading is fine...
    assert.equal(
      (await fetch(`${baseUrl}/api/variations/die/${dieId}`, { headers: readerHeaders }))
        .status,
      200,
    );
    // ...but writing a die's tree needs the die master, which they have not
    // been given. Without the module's own guard this would fall through to
    // the legacy admin gate and refuse everyone equally, which is not the
    // same thing.
    const attempt = await fetch(`${baseUrl}/api/variations/die/${dieId}`, {
      method: 'PUT',
      headers: readerHeaders,
      body: JSON.stringify({ nodes: [{ kind: 'property', name: 'Cavity' }] }),
    });
    assert.equal(attempt.status, 403);
    assert.match((await attempt.json()).error, /Dies/);

    const granted = await fetch(`${baseUrl}/api/users/${(await created.json()).user.id}/permissions`, {
      method: 'PATCH',
      headers: ownerHeaders,
      body: JSON.stringify({ overrides: [{ key: 'dies.update', allowed: true }] }),
    });
    assert.equal(granted.status, 200);

    const allowed = await fetch(`${baseUrl}/api/variations/die/${dieId}`, {
      method: 'PUT',
      headers: readerHeaders,
      body: JSON.stringify({ nodes: [{ kind: 'property', name: 'Cavity' }] }),
    });
    assert.equal(
      allowed.status,
      200,
      `staff with dies.update may edit a die's tree: ${await allowed.clone().text()}`,
    );
  } finally {
    await closeServer(server);
  }
});
