const assert = require('node:assert/strict');
const http = require('node:http');
const path = require('node:path');
const test = require('node:test');
const { makeTempDir } = require('./helpers/temp-dir');

// Raw material per die (owner, 2026-11-25): "one item has many dies — every
// die creates new raw material data". A plan per (part, die), beside the
// part's own.

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
    server.on('error', reject);
  });
}

async function boot() {
  const tempDir = makeTempDir('paper-die-plans-');
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'dieplans@example.test';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;
  const login = await fetch(`${baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'dieplans@example.test', password: 'OwnerPass1234' }),
  }).then((r) => r.json());
  assert.ok(login.token);
  return {
    backend,
    server,
    baseUrl,
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${login.token}` },
  };
}

function api(ctx, method, route, body, headers = ctx.headers) {
  return fetch(`${ctx.baseUrl}${route}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  }).then(async (r) => ({ status: r.status, body: await r.json() }));
}

test('each die a part is made on keeps its own raw plan', async (t) => {
  const ctx = await boot();
  t.after(() => new Promise((resolve) => ctx.server.close(resolve)));
  const group = await ctx.backend.get("SELECT id, unit_id FROM groups WHERE system_key IS NULL AND group_type = 'item' LIMIT 1");
  const part = await ctx.backend.saveItem({ name: 'Patti', groupId: group.id, unitId: group.unit_id });
  const oldDie = (await api(ctx, 'POST', '/api/dies', { toolCode: 'PT-2014', status: 'active', ownership: 'inHouse' })).body.die;
  const newDie = (await api(ctx, 'POST', '/api/dies', { toolCode: 'PT-2024', status: 'active', ownership: 'inHouse' })).body.die;

  const empty = await api(ctx, 'GET', `/api/items/${part.id}/die-raw-plans`);
  assert.equal(empty.status, 200);
  assert.deepEqual(empty.body.plans, []);

  const strip = { lastForm: 'strip', formChosen: true, forms: { strip: { widthNm: 120000000 } } };
  const sheet = { lastForm: 'sheet', formChosen: true, sheetWidthInches: 48 };
  assert.equal((await api(ctx, 'PUT', `/api/items/${part.id}/die-raw-plans/${oldDie.id}`, { baseline: sheet })).status, 200);
  const saved = await api(ctx, 'PUT', `/api/items/${part.id}/die-raw-plans/${newDie.id}`, { baseline: strip });
  assert.equal(saved.status, 200, JSON.stringify(saved.body));
  assert.deepEqual(saved.body.plan.baseline, strip);

  // Written again: replaced, not added.
  const again = { ...strip, forms: { strip: { widthNm: 125000000 } } };
  await api(ctx, 'PUT', `/api/items/${part.id}/die-raw-plans/${newDie.id}`, { baseline: again });

  const listed = await api(ctx, 'GET', `/api/items/${part.id}/die-raw-plans`);
  assert.deepEqual(
    listed.body.plans.map((p) => [p.dieId, p.baseline.lastForm]),
    [[Number(oldDie.id), 'sheet'], [Number(newDie.id), 'strip']],
  );
  assert.equal(listed.body.plans[1].baseline.forms.strip.widthNm, 125000000);

  // The part's own plan is untouched by any of it.
  const row = await ctx.backend.get('SELECT pen_paper_baseline FROM items WHERE id = ?', [part.id]).catch(() => null);
  if (row) assert.ok(!String(row.pen_paper_baseline || '').includes('125000000'));

  // Refused: a die that does not exist, no plan, a part that does not exist.
  assert.equal((await api(ctx, 'PUT', `/api/items/${part.id}/die-raw-plans/999999`, { baseline: strip })).status, 404);
  assert.equal((await api(ctx, 'PUT', `/api/items/${part.id}/die-raw-plans/${newDie.id}`, {})).status, 400);
  assert.equal((await api(ctx, 'GET', '/api/items/999999/die-raw-plans')).status, 404);
  assert.equal((await api(ctx, 'GET', `/api/items/${part.id}/die-raw-plans`, undefined, {})).status, 401);

  // A part deleted takes its die plans with it.
  await api(ctx, 'DELETE', `/api/items/${part.id}`);
  assert.equal((await ctx.backend.get('SELECT COUNT(*) AS n FROM item_die_raw_plans WHERE item_id = ?', [part.id])).n, 0);
});
