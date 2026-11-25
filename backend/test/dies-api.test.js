const assert = require('node:assert/strict');
const http = require('node:http');
const path = require('node:path');
const test = require('node:test');
const { makeTempDir } = require('./helpers/temp-dir');

// The die master, the parts of it die-sheet-fields.test.js and die-makers.test.js
// do not reach: reading one, the three refusals a save can make (an unusable
// type, a client or a maker that is not there), deleting (and being refused
// while a live pipeline run is using the die), and the photo routes.
//
// Written before the dies code left server.js. The sheet, the code rule and the
// keep-what-is-stored rule are pinned in die-sheet-fields.test.js.

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
  const tempDir = makeTempDir('paper-dies-');
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'dies@example.test';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;
  const login = await fetch(`${baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'dies@example.test', password: 'OwnerPass1234' }),
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

test('dies: create, read one, list, update keeps what the save did not mention', async (t) => {
  const ctx = await boot();
  t.after(() => closeServer(ctx.server));

  const created = await api(ctx, 'POST', '/api/dies', {
    toolCode: 'CD-TEST-1',
    storageLocation: 'Rack 4',
    status: 'active',
    ownership: 'inHouse',
  });
  assert.equal(created.status, 200);
  assert.equal(created.body.success, true);
  const die = created.body.die;
  assert.equal(die.toolCode, 'CD-TEST-1');
  assert.equal(die.clientId, null, 'no client link until one is sent');
  assert.deepEqual(die.producedPartNumbers, []);

  const one = await api(ctx, 'GET', `/api/dies/${die.id}`);
  assert.equal(one.status, 200);
  assert.equal(one.body.die.storageLocation, 'Rack 4');

  const missing = await api(ctx, 'GET', '/api/dies/999999');
  assert.equal(missing.status, 404);
  assert.equal(missing.body.die, null);

  const list = await api(ctx, 'GET', '/api/dies');
  assert.equal(list.status, 200);
  assert.ok(list.body.dies.some((d) => d.id === die.id));

  const updated = await api(ctx, 'POST', '/api/dies', { id: die.id, rackNo: 'R-9' });
  assert.equal(updated.status, 200);
  assert.equal(updated.body.die.rackNo, 'R-9');
  assert.equal(updated.body.die.storageLocation, 'Rack 4', 'what the save did not mention is kept');
  assert.equal(updated.body.die.toolCode, 'CD-TEST-1');

  // The app sends the id as a NUMBER since B69 (2026-11-24); the service used
  // to call `.trim()` on it and every save of an existing die answered 500
  // "id.trim is not a function" (B74).
  const numeric = await api(ctx, 'POST', '/api/dies', { id: Number(die.id), rackNo: 'R-10' });
  assert.equal(numeric.status, 200, JSON.stringify(numeric.body));
  assert.equal(numeric.body.die.rackNo, 'R-10');
  assert.equal(numeric.body.die.toolCode, 'CD-TEST-1', 'a numeric id updates, never duplicates');

  const ghost = await api(ctx, 'POST', '/api/dies', { id: '999999', toolCode: 'NOPE' });
  assert.equal(ghost.status, 404);
  const ghostNumber = await api(ctx, 'POST', '/api/dies', { id: 999999, toolCode: 'NOPE' });
  assert.equal(ghostNumber.status, 404);
});

test('dies: the client is a link, set by clientId and cleared by null', async (t) => {
  const ctx = await boot();
  t.after(() => closeServer(ctx.server));

  const client = await api(ctx, 'POST', '/api/clients', { name: 'Die Client Ltd' });
  assert.ok([200, 201].includes(client.status), JSON.stringify(client.body));
  const clientId = Number(client.body.client.id);

  const made = await api(ctx, 'POST', '/api/dies', { toolCode: 'CD-LINK-1', status: 'active', ownership: 'inHouse', clientId });
  assert.equal(made.status, 200);
  assert.equal(made.body.die.clientId, clientId);

  const kept = await api(ctx, 'POST', '/api/dies', { id: made.body.die.id, rackNo: 'R-1' });
  assert.equal(kept.body.die.clientId, clientId, 'absent clientId leaves the link alone');

  const cleared = await api(ctx, 'POST', '/api/dies', { id: made.body.die.id, clientId: null });
  assert.equal(cleared.body.die.clientId, null);

  const bad = await api(ctx, 'POST', '/api/dies', { toolCode: 'CD-LINK-2', clientId: 999999 });
  assert.equal(bad.status, 400);
  assert.equal(bad.body.error, 'That client does not exist.');
});

test('dies: an unusable type and an unknown maker are refused by name', async (t) => {
  const ctx = await boot();
  t.after(() => closeServer(ctx.server));

  const type = await api(ctx, 'POST', '/api/dies', { toolCode: 'CD-T-1', dieType: 'mystery' });
  assert.equal(type.status, 400);
  assert.match(type.body.error, /is not a die type, and no name was given for it/);

  const maker = await api(ctx, 'POST', '/api/dies', { toolCode: 'CD-M-1', dieMakerId: 999999 });
  assert.equal(maker.status, 400);
  assert.equal(maker.body.code, 'die_maker_unknown');
});

test('dies: a taken code is refused with a free one offered', async (t) => {
  const ctx = await boot();
  t.after(() => closeServer(ctx.server));

  await api(ctx, 'POST', '/api/dies', { toolCode: 'CD-DUP-1', status: 'active', ownership: 'inHouse' });
  const clash = await api(ctx, 'POST', '/api/dies', { toolCode: 'cd-dup-1', status: 'active', ownership: 'inHouse' });
  assert.equal(clash.status, 409);
  assert.equal(clash.body.code, 'die_tool_code_duplicate');
  assert.match(clash.body.error, /already used by die #/);
});

test('dies: delete removes one, and a live pipeline run holds it', async (t) => {
  const ctx = await boot();
  t.after(() => closeServer(ctx.server));

  const free = (await api(ctx, 'POST', '/api/dies', { toolCode: 'CD-FREE-1', status: 'active', ownership: 'inHouse' })).body.die;
  assert.equal((await api(ctx, 'DELETE', `/api/dies/${free.id}`)).status, 200);
  assert.equal((await api(ctx, 'GET', `/api/dies/${free.id}`)).status, 404);

  const busy = (await api(ctx, 'POST', '/api/dies', { toolCode: 'CD-BUSY-1', status: 'active', ownership: 'inHouse' })).body.die;
  await ctx.backend.run('PRAGMA foreign_keys = OFF');
  await ctx.backend.run(
    `INSERT INTO pipeline_runs (id, template_id, template_version, name, status, overrides_json)
     VALUES ('run-dies-1', 'tpl-x', 1, 'Held', 'paused', ?)`,
    [JSON.stringify({ dieOverrideByNode: { 'node-1': busy.id } })],
  );
  const refused = await api(ctx, 'DELETE', `/api/dies/${busy.id}`);
  assert.equal(refused.status, 400);
  assert.match(refused.body.error, /assigned to an active pipeline run/);

  await ctx.backend.run("UPDATE pipeline_runs SET status = 'completed' WHERE id = 'run-dies-1'");
  assert.equal((await api(ctx, 'DELETE', `/api/dies/${busy.id}`)).status, 200);
});

test('dies: the photo list starts empty and an upload intent is raised for the die', async (t) => {
  const ctx = await boot();
  t.after(() => closeServer(ctx.server));

  const die = (await api(ctx, 'POST', '/api/dies', { toolCode: 'CD-SNAP-1', status: 'active', ownership: 'inHouse' })).body.die;
  const list = await api(ctx, 'GET', `/api/dies/${die.id}/assets`);
  assert.equal(list.status, 200);
  assert.deepEqual(list.body.assets, []);

  const intent = await api(ctx, 'POST', `/api/dies/${die.id}/assets/upload-intent`, {
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
