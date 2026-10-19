const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

const { validateRouteSteps, readSteps } = require('../modules/process_routes/service');

// Process routing: an ordered list of stages for a part.
//
// The model and the three rules are prescribed in
// Docs/architecture/10-design-philosophy.md's worked example and had never been
// built. The rules are asserted twice over — once against the pure validator,
// where a case costs nothing, and once through HTTP, because a rule that holds
// in a unit test and not on the wire is not enforced.

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

async function boot(prefix, email) {
  const tempDir = mkdtempSync(path.join(tmpdir(), prefix));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = email;
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'RoutePass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  const { token } = await fetch(`${baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: 'RoutePass1234' }),
  }).then((r) => r.json());

  const base = { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` };
  const call = async (method, p, body, sitting) => {
    const headers = { ...base };
    if (sitting) headers['X-Paper-Sitting'] = sitting;
    const r = await fetch(`${baseUrl}${p}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: r.status, body: await r.json() };
  };

  const partId = (await backend.get('SELECT id FROM items ORDER BY id LIMIT 1')).id;
  return { backend, server, call, partId };
}

// --- the validator, on its own ----------------------------------------------

const STAGES = [
  { id: 1, name: 'Die', repeatable: 0, active: 1 },
  { id: 2, name: 'Shearing', repeatable: 0, active: 1 },
  { id: 3, name: 'Cutting', repeatable: 1, active: 1 },
  { id: 9, name: 'Delivery', repeatable: 0, active: 1 },
  { id: 7, name: 'Hand Lapping', repeatable: 0, active: 0 },
];

test('an ordered list of stage ids is numbered 1..n', () => {
  const result = validateRouteSteps(readSteps([1, 2, 9]), STAGES);
  assert.equal(result.ok, true, result.error);
  assert.deepEqual(result.steps.map((s) => s.seq), [1, 2, 3]);
  assert.deepEqual(result.steps.map((s) => s.stageId), [1, 2, 9]);
});

test('an empty route is refused', () => {
  assert.equal(validateRouteSteps(readSteps([]), STAGES).code, 'route_empty');
});

test('seq must be contiguous from 1 with no gaps', () => {
  const gap = validateRouteSteps(readSteps([{ stageId: 1, seq: 1 }, { stageId: 2, seq: 3 }]), STAGES);
  assert.equal(gap.code, 'route_seq_gap');

  const fromZero = validateRouteSteps(readSteps([{ stageId: 1, seq: 0 }, { stageId: 2, seq: 1 }]), STAGES);
  assert.equal(fromZero.code, 'route_seq_gap');

  // Out of order but complete is fine: the service sorts, then checks.
  const shuffled = validateRouteSteps(readSteps([{ stageId: 2, seq: 2 }, { stageId: 1, seq: 1 }]), STAGES);
  assert.equal(shuffled.ok, true, shuffled.error);
  assert.deepEqual(shuffled.steps.map((s) => s.stageId), [1, 2]);
});

test('seq on some steps but not others is refused rather than guessed', () => {
  const mixed = validateRouteSteps(readSteps([{ stageId: 1, seq: 1 }, { stageId: 2 }]), STAGES);
  assert.equal(mixed.code, 'route_seq_partial');
});

test('a stage appears at most once per route unless it is repeatable', () => {
  const twice = validateRouteSteps(readSteps([1, 2, 1]), STAGES);
  assert.equal(twice.code, 'route_stage_repeated');
  assert.match(twice.error, /Die/, 'the refusal should name the stage');

  // Cutting is flagged repeatable, so twice is allowed.
  const repeatable = validateRouteSteps(readSteps([3, 2, 3]), STAGES);
  assert.equal(repeatable.ok, true, repeatable.error);
  assert.equal(repeatable.steps.length, 3);
});

test('an unknown or retired stage cannot be routed through', () => {
  assert.equal(validateRouteSteps(readSteps([1, 4242]), STAGES).code, 'route_stage_unknown');
  assert.equal(validateRouteSteps(readSteps([1, 7]), STAGES).code, 'route_stage_inactive');
});

test('readSteps takes all three spellings and refuses nonsense', () => {
  assert.deepEqual(readSteps([1, 2]).map((s) => s.stageId), [1, 2]);
  assert.deepEqual(readSteps([{ stageId: 1 }]).map((s) => s.stageId), [1]);
  assert.deepEqual(readSteps([{ stage_id: 5 }]).map((s) => s.stageId), [5]);
  assert.equal(readSteps('die'), null);
  assert.equal(readSteps([0]), null);
  assert.equal(readSteps([{ stageId: 'x' }]), null);
  assert.equal(readSteps([null]), null);
});

// --- the same rules over HTTP -----------------------------------------------

test('the nine stages are seeded as rows', async () => {
  const ctx = await boot('paper-route-stages-', 'route-stages@paper.local');
  try {
    const res = await ctx.call('GET', '/api/process-stages');
    assert.equal(res.status, 200, JSON.stringify(res.body));
    const codes = res.body.stages.map((s) => s.code);
    assert.deepEqual(codes, [
      'die', 'shearing', 'cutting', 'riveting',
      'assembly', 'barcode', 'packing', 'billing', 'delivery',
    ]);
    // Rows, not constants: every one is editable and deactivatable.
    assert.ok(res.body.stages.every((s) => Number(s.active) === 1));
  } finally {
    await closeServer(ctx.server);
  }
});

test('a route saves, reads back in order, and refuses an in-place edit', async () => {
  const ctx = await boot('paper-route-save-', 'route-save@paper.local');
  try {
    const { call, partId } = ctx;
    const stages = (await call('GET', '/api/process-stages')).body.stages;
    const id = (code) => stages.find((s) => s.code === code).id;

    const saved = await call('POST', `/api/items/${partId}/routes`, {
      steps: [id('die'), id('shearing'), id('cutting'), id('delivery')],
    });
    assert.equal(saved.status, 200, JSON.stringify(saved.body));
    assert.equal(saved.body.version, 1);
    assert.equal(saved.body.status, 'active');

    const read = await call('GET', `/api/items/${partId}/routes`);
    assert.equal(read.status, 200);
    assert.equal(read.body.routes.length, 1);
    const route = read.body.routes[0];
    assert.deepEqual(route.steps.map((s) => s.seq), [1, 2, 3, 4]);
    assert.deepEqual(route.steps.map((s) => s.stage_code), ['die', 'shearing', 'cutting', 'delivery']);

    // The doc's third rule: an active route is never edited in place, and the
    // refusal names the route to version so the caller is not just stuck.
    const again = await call('POST', `/api/items/${partId}/routes`, { steps: [id('die')] });
    assert.equal(again.status, 409, JSON.stringify(again.body));
    assert.equal(again.body.code, 'route_active');
    assert.equal(again.body.routeId, route.id);
  } finally {
    await closeServer(ctx.server);
  }
});

test('a change mints a new version and retires the old one, never editing it', async () => {
  const ctx = await boot('paper-route-version-', 'route-version@paper.local');
  try {
    const { call, partId, backend } = ctx;
    const stages = (await call('GET', '/api/process-stages')).body.stages;
    const id = (code) => stages.find((s) => s.code === code).id;

    await call('POST', `/api/items/${partId}/routes`, { steps: [id('die'), id('shearing')] });
    const v2 = await call('POST', `/api/items/${partId}/routes/versions`, {
      steps: [id('die'), id('shearing'), id('packing')],
      note: 'added packing',
    });
    assert.equal(v2.status, 200, JSON.stringify(v2.body));
    assert.equal(v2.body.version, 2);
    assert.equal(v2.body.previousVersion, 1);

    const rows = await backend.all(
      'SELECT version, status FROM process_routes WHERE part_id = ? ORDER BY version',
      [partId],
    );
    assert.deepEqual(rows, [
      { version: 1, status: 'retired' },
      { version: 2, status: 'active' },
    ]);

    // v1's steps still read as they did, which is the point of versioning —
    // a job that ran under v1 can still be read against v1.
    const read = await call('GET', `/api/items/${partId}/routes`);
    const v1 = read.body.routes.find((r) => r.version === 1);
    assert.deepEqual(v1.steps.map((s) => s.stage_code), ['die', 'shearing']);
    // Active first, whatever the version order.
    assert.equal(read.body.routes[0].status, 'active');

    const none = await boot('paper-route-noactive-', 'route-noactive@paper.local');
    try {
      const refused = await none.call('POST', `/api/items/${none.partId}/routes/versions`, {
        steps: [1],
      });
      assert.equal(refused.status, 409);
      assert.equal(refused.body.code, 'route_not_active');
    } finally {
      await closeServer(none.server);
    }
  } finally {
    await closeServer(ctx.server);
  }
});

test('the rules hold over HTTP, not only in the validator', async () => {
  const ctx = await boot('paper-route-rules-', 'route-rules@paper.local');
  try {
    const { call, partId } = ctx;
    const stages = (await call('GET', '/api/process-stages')).body.stages;
    const id = (code) => stages.find((s) => s.code === code).id;

    const repeated = await call('POST', `/api/items/${partId}/routes`, {
      steps: [id('die'), id('shearing'), id('die')],
    });
    assert.equal(repeated.status, 400, JSON.stringify(repeated.body));
    assert.equal(repeated.body.code, 'route_stage_repeated');

    const gap = await call('POST', `/api/items/${partId}/routes`, {
      steps: [{ stageId: id('die'), seq: 1 }, { stageId: id('shearing'), seq: 4 }],
    });
    assert.equal(gap.body.code, 'route_seq_gap');

    const empty = await call('POST', `/api/items/${partId}/routes`, { steps: [] });
    assert.equal(empty.body.code, 'route_empty');

    const junk = await call('POST', `/api/items/${partId}/routes`, { steps: 'die,shearing' });
    assert.equal(junk.body.code, 'route_steps_malformed');

    // A refused save leaves nothing behind.
    const read = await call('GET', `/api/items/${partId}/routes`);
    assert.equal(read.body.routes.length, 0);

    const ghost = await call('POST', '/api/items/99999/routes', { steps: [id('die')] });
    assert.equal(ghost.status, 404);
  } finally {
    await closeServer(ctx.server);
  }
});

test('a route belongs to the sitting it was made in', async () => {
  const ctx = await boot('paper-route-sitting-', 'route-sitting@paper.local');
  try {
    const { call, partId, backend } = ctx;
    const stages = (await call('GET', '/api/process-stages')).body.stages;
    const sitting = 's-route-001';

    const saved = await call(
      'POST',
      `/api/items/${partId}/routes`,
      { steps: [stages[0].id, stages[1].id] },
      sitting,
    );
    assert.equal(saved.status, 200, JSON.stringify(saved.body));

    // Telemetry is fire-and-forget, so poll rather than assume.
    let rows = [];
    for (let i = 0; i < 20; i += 1) {
      rows = await backend.all(
        'SELECT entity_type, entity_id, action FROM entity_activity_log WHERE sitting_id = ?',
        [sitting],
      );
      if (rows.length > 0) break;
      await new Promise((r) => setTimeout(r, 25));
    }
    assert.equal(rows.length, 1, 'the route should have left one activity row');
    // Logged against the PART: that is the record somebody opens Track on.
    assert.equal(rows[0].entity_type, 'items');
    assert.equal(rows[0].entity_id, String(partId));
  } finally {
    await closeServer(ctx.server);
  }
});

test('the route tables survive two boots of the same database', async () => {
  // Two runners execute every migration on EVERY boot — migrate.js first
  // (tolerating only /duplicate column name/i), then the kernel runner from
  // inside initDb. A second boot is where a non-idempotent 052 would take the
  // server down, and where an INSERT without OR IGNORE would seed 18 stages.
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-route-reboot-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'route-reboot@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'RoutePass1234';

  for (const pass of ['first', 'second']) {
    delete require.cache[require.resolve('../server.js')];
    const backend = require('../server.js');
    await backend.resetAndSeedDemoData();
    for (const table of ['process_stages', 'process_routes', 'process_route_steps']) {
      const columns = await backend.all(`PRAGMA table_info(${table})`);
      assert.ok(columns.length > 0, `${table} should exist on the ${pass} boot`);
    }
    const count = await backend.get('SELECT COUNT(*) AS n FROM process_stages');
    assert.equal(count.n, 9, `the seed should not double on the ${pass} boot`);
  }
});
