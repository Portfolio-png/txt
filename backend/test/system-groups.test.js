const assert = require('node:assert/strict');
const http = require('node:http');
const path = require('node:path');
const test = require('node:test');
const { makeTempDir } = require('./helpers/temp-dir');
const { ensureSystemGroups } = require('../modules/items/system-groups');

// The groups the app ships: Raw Materials › Rivets, Springs.
// They must exist on a fresh workspace, come back after Clear Data, and refuse
// the edits that would lose them (delete, archive, rename, move).

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
    server.on('error', reject);
  });
}

async function boot() {
  const tempDir = makeTempDir('paper-system-groups-');
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'sysgroups@example.test';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;
  const login = await fetch(`${baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'sysgroups@example.test', password: 'OwnerPass1234' }),
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

async function systemGroups(backend) {
  return backend.all(
    `SELECT g.id, g.system_key AS key, g.name, g.parent_group_id AS parentId,
            p.system_key AS parentKey, u.name AS unit, g.is_archived AS archived
       FROM groups g
       LEFT JOIN groups p ON p.id = g.parent_group_id
       LEFT JOIN units u ON u.id = g.unit_id
      WHERE g.system_key IS NOT NULL
      ORDER BY g.system_key`,
  );
}

test('default raw-material groups: seeded, guarded, and back after Clear Data', async (t) => {
  const ctx = await boot();
  t.after(() => new Promise((resolve) => ctx.server.close(resolve)));
  const { backend } = ctx;

  const seeded = await systemGroups(backend);
  assert.deepEqual(
    seeded.map(({ key, name, parentKey, unit, archived }) => ({ key, name, parentKey, unit, archived })),
    [
      { key: 'raw_materials', name: 'Raw Materials', parentKey: null, unit: 'Primary Unit', archived: 0 },
      { key: 'raw_materials.rivets', name: 'Rivets', parentKey: 'raw_materials', unit: 'Piece', archived: 0 },
      { key: 'raw_materials.springs', name: 'Springs', parentKey: 'raw_materials', unit: 'Piece', archived: 0 },
    ],
  );
  const [raw, rivets] = seeded;

  // The API says which groups are defaults.
  const listed = await api(ctx, 'GET', '/api/groups');
  assert.equal(listed.status, 200);
  const listedRivets = (listed.body.groups || listed.body).find((g) => g.id === rivets.id);
  assert.equal(listedRivets.systemKey, 'raw_materials.rivets');

  const piece = await backend.get("SELECT id FROM units WHERE name = 'Piece'");

  // Delete, archive, rename, move: refused, 409, nothing changed.
  const del = await api(ctx, 'DELETE', `/api/groups/${rivets.id}`);
  assert.equal(del.status, 409);
  assert.equal(del.body.code, 'system_group');
  // Deleting the parent would cascade into its defaults; the parent is a default too.
  assert.equal((await api(ctx, 'DELETE', `/api/groups/${raw.id}`)).status, 409);
  assert.equal((await api(ctx, 'PATCH', `/api/groups/${rivets.id}/archive`)).status, 409);
  const rename = await api(ctx, 'PATCH', `/api/groups/${rivets.id}`, {
    name: 'Rivet stock', parentGroupId: raw.id, unitId: piece.id,
  });
  assert.equal(rename.status, 409);
  const move = await api(ctx, 'PATCH', `/api/groups/${rivets.id}`, {
    name: 'Rivets', parentGroupId: null, unitId: piece.id,
  });
  assert.equal(move.status, 409);

  // Editing what is allowed still works — and saving Raw Materials (a root)
  // no longer files it under Primary Group.
  const describe = await api(ctx, 'PATCH', `/api/groups/${rivets.id}`, {
    name: 'Rivets', parentGroupId: raw.id, unitId: piece.id, description: 'Bimetal and copper rivets',
  });
  assert.equal(describe.status, 200, JSON.stringify(describe.body));
  assert.equal(describe.body.group.description, 'Bimetal and copper rivets');
  const rawUnit = await backend.get('SELECT unit_id FROM groups WHERE id = ?', [raw.id]);
  const saveRoot = await api(ctx, 'PATCH', `/api/groups/${raw.id}`, {
    name: 'Raw Materials', parentGroupId: null, unitId: rawUnit.unit_id,
  });
  assert.equal(saveRoot.status, 200, JSON.stringify(saveRoot.body));
  assert.equal(saveRoot.body.group.parentGroupId, null);

  // A user can still add their own group beside the defaults.
  const own = await api(ctx, 'POST', '/api/groups', {
    name: 'Washers', parentGroupId: raw.id, unitId: piece.id,
  });
  assert.equal(own.status, 201, JSON.stringify(own.body));

  // Clear Data wipes the workspace; the defaults come back.
  const cleared = await api(ctx, 'POST', '/api/admin/clear-data');
  assert.equal(cleared.status, 200);
  const after = await systemGroups(backend);
  assert.deepEqual(after.map((g) => [g.key, g.name, g.unit]), [
    ['raw_materials', 'Raw Materials', 'Primary Unit'],
    ['raw_materials.rivets', 'Rivets', 'Piece'],
    ['raw_materials.springs', 'Springs', 'Piece'],
  ]);
  assert.equal((await backend.get("SELECT COUNT(*) AS n FROM groups WHERE name = 'Washers'")).n, 0);
});

test('the seed claims groups that already exist under a known name, and is idempotent', async (t) => {
  const ctx = await boot();
  t.after(() => new Promise((resolve) => ctx.server.close(resolve)));
  const { backend } = ctx;
  const db = { run: backend.run, get: backend.get };
  const piece = await backend.get("SELECT id FROM units WHERE name = 'Piece'");
  const primary = await backend.get("SELECT id FROM units WHERE name = 'Primary Unit'");
  const units = { primary: primary.id, piece: piece.id };

  // An older database: the groups exist, made by hand, with no key — and one
  // of them archived.
  await backend.run('UPDATE groups SET system_key = NULL');
  const rivets = await backend.get("SELECT id FROM groups WHERE name = 'Rivets'");
  await backend.run("UPDATE groups SET name = 'rivet', is_archived = 1 WHERE id = ?", [rivets.id]);
  const before = (await backend.get('SELECT COUNT(*) AS n FROM groups')).n;

  await ensureSystemGroups(db, units);
  await ensureSystemGroups(db, units);

  assert.equal((await backend.get('SELECT COUNT(*) AS n FROM groups')).n, before, 'no twins');
  const claimed = await backend.get('SELECT system_key, is_archived FROM groups WHERE id = ?', [rivets.id]);
  assert.equal(claimed.system_key, 'raw_materials.rivets');
  assert.equal(claimed.is_archived, 0);
});
