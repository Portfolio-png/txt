const assert = require('node:assert/strict');
const http = require('node:http');
const path = require('node:path');
const test = require('node:test');
const { makeTempDir } = require('./helpers/temp-dir');

// The machine master, the parts of it machine-sheet-fields.test.js does not
// reach: reading one, refusing a bad capacity kind, deleting (and being refused
// while a live pipeline run is using the machine), and the photo routes.
//
// Written before the machines code left server.js. The sheet, the numbering and
// the keep-what-is-stored rule are pinned in machine-sheet-fields.test.js.

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

async function boot() {
  const tempDir = makeTempDir('paper-machines-');
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'machines@example.test';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;
  const login = await fetch(`${baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'machines@example.test', password: 'OwnerPass1234' }),
  }).then((r) => r.json());
  assert.ok(login.token, 'expected a login token');
  return {
    backend,
    server,
    baseUrl,
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${login.token}` },
  };
}

function api(ctx, method, route, body) {
  return fetch(`${ctx.baseUrl}${route}`, {
    method,
    headers: ctx.headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  }).then(async (r) => ({ status: r.status, body: await r.json() }));
}

test('machines: create, read one, list, update', async (t) => {
  const ctx = await boot();
  t.after(() => closeServer(ctx.server));

  const created = await api(ctx, 'POST', '/api/machines', {
    name: 'Press A',
    assetId: 'PA-1',
    location: 'Shop 1',
    status: 'active',
  });
  assert.equal(created.status, 200);
  assert.equal(created.body.success, true);
  const machine = created.body.machine;
  assert.equal(machine.assetId, 'PA-1');
  assert.equal(machine.barcode, 'PA-1', 'the barcode defaults to the asset tag');
  assert.deepEqual(machine.customProperties, []);
  assert.deepEqual(machine.capabilities, []);

  const one = await api(ctx, 'GET', `/api/machines/${machine.id}`);
  assert.equal(one.status, 200);
  assert.equal(one.body.machine.id, machine.id);
  assert.equal(one.body.machine.location, 'Shop 1');

  const missing = await api(ctx, 'GET', '/api/machines/999999');
  assert.equal(missing.status, 404);
  assert.equal(missing.body.machine, null);

  const list = await api(ctx, 'GET', '/api/machines');
  assert.equal(list.status, 200);
  assert.ok(list.body.machines.some((m) => m.id === machine.id));

  const updated = await api(ctx, 'POST', '/api/machines', { id: machine.id, location: 'Shop 2' });
  assert.equal(updated.status, 200);
  assert.equal(updated.body.machine.location, 'Shop 2');
  // Numeric id, as the app sends it since B69 (B74: `.trim()` on a number).
  const numeric = await api(ctx, 'POST', '/api/machines', { id: Number(machine.id), location: 'Shop 3' });
  assert.equal(numeric.status, 200, JSON.stringify(numeric.body));
  assert.equal(numeric.body.machine.location, 'Shop 3');
  assert.equal(numeric.body.machine.id, machine.id, 'a numeric id updates, never duplicates');
  assert.equal(updated.body.machine.assetId, 'PA-1', 'what the save did not mention is kept');

  const ghost = await api(ctx, 'POST', '/api/machines', { id: '999999', name: 'Nobody' });
  assert.equal(ghost.status, 404);
});

test('machines: a capacity kind that is not one of the two is refused', async (t) => {
  const ctx = await boot();
  t.after(() => closeServer(ctx.server));

  const bad = await api(ctx, 'POST', '/api/machines', {
    name: 'Press B',
    assetId: 'PB-1',
    capacityKind: 'enormous',
  });
  assert.equal(bad.status, 400);
  assert.equal(bad.body.machine, null);
  assert.match(bad.body.error, /not a capacity kind/);
});

test('machines: delete removes one, and a live pipeline run holds it', async (t) => {
  const ctx = await boot();
  t.after(() => closeServer(ctx.server));

  const free = (await api(ctx, 'POST', '/api/machines', { name: 'Free', assetId: 'FR-1', status: 'active' })).body.machine;
  const gone = await api(ctx, 'DELETE', `/api/machines/${free.id}`);
  assert.equal(gone.status, 200);
  assert.equal((await api(ctx, 'GET', `/api/machines/${free.id}`)).status, 404);

  const busy = (await api(ctx, 'POST', '/api/machines', { name: 'Busy', assetId: 'BS-1', status: 'active' })).body.machine;
  await ctx.backend.run('PRAGMA foreign_keys = OFF');
  await ctx.backend.run(
    `INSERT INTO pipeline_runs (id, template_id, template_version, name, status, overrides_json)
     VALUES ('run-machines-1', 'tpl-x', 1, 'Held', 'in_progress', ?)`,
    [JSON.stringify({ machineOverrideByNode: { 'node-1': busy.id } })],
  );
  const refused = await api(ctx, 'DELETE', `/api/machines/${busy.id}`);
  assert.equal(refused.status, 400);
  assert.match(refused.body.error, /assigned to an active pipeline run/);
  assert.equal((await api(ctx, 'GET', `/api/machines/${busy.id}`)).status, 200, 'it is still there');

  await ctx.backend.run("UPDATE pipeline_runs SET status = 'completed' WHERE id = 'run-machines-1'");
  const released = await api(ctx, 'DELETE', `/api/machines/${busy.id}`);
  assert.equal(released.status, 200, 'a finished run no longer holds it');
});

test('machines: the photo list starts empty and an upload intent is raised for the machine', async (t) => {
  const ctx = await boot();
  t.after(() => closeServer(ctx.server));

  const machine = (await api(ctx, 'POST', '/api/machines', { name: 'Snap', assetId: 'SN-1', status: 'active' })).body.machine;
  const list = await api(ctx, 'GET', `/api/machines/${machine.id}/assets`);
  assert.equal(list.status, 200);
  assert.deepEqual(list.body.assets, []);

  const intent = await api(ctx, 'POST', `/api/machines/${machine.id}/assets/upload-intent`, {
    fileName: 'front.png',
    contentType: 'image/png',
    sizeBytes: 1234,
  });
  assert.ok(
    [200, 201, 500].includes(intent.status),
    `an intent answers 200/201, or 500 when no store is configured (got ${intent.status})`,
  );
  assert.equal(typeof intent.body.success, 'boolean');
});
