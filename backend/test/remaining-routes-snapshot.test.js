const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const test = require('node:test');
const { makeTempDir } = require('./helpers/temp-dir');

// How the routes outside the fifteen business modules answer: accounts, the
// activity trail, search, assets, payroll, settings, the control plane.
//
// Taken before those routes left server.js. Each one is called twice, without a
// login and as the owner, with a placeholder for every parameter and an empty
// body. What is kept is the status and the SHAPE of the answer (its keys, and
// its error message), not values that change from run to run. That is enough
// to catch what a move can break: a route that is no longer reached, a guard
// that no longer applies, a handler that throws because something it used was
// not handed to it.
//
// To accept a deliberate change:  UPDATE_ROUTE_SNAPSHOT=1 npm test

const FIXTURE = path.join(__dirname, 'fixtures', 'remaining-routes-snapshot.json');

// First path segments (after /api/) that belong to modules with their own tests.
const MODULE_SEGMENTS = new Set([
  'items', 'groups', 'item-groups', 'item-sets', 'vendors', 'clients', 'client-portal', 'portal',
  'machines', 'dies', 'die-makers', 'departments', 'employees', 'people', 'orders', 'order-returns',
  'challans', 'delivery-challans', 'challan-templates', 'invoices', 'reports', 'inventory', 'inventory-sets',
  'materials', 'material-types', 'production', 'production-runs', 'production-scrap', 'freelancer-jobs',
  'freelancer-portal', 'delete-requests', 'trash', 'issues', 'process-stages', 'process-routes', 'links',
  'entity-variations', 'variations', 'kernel', 'party-contacts', 'item-sheet-properties', 'conversion-overrides',
  'waste-audit', 'report-groups', 'sub-contractors', 'dev', 'raw-materials',
]);

// Never called: they stream forever, wipe the database the later calls need, or
// reach outside the machine.
const SKIP = [
  /^GET \/api\/events$/,
  /factory-reset|clear-data|reset-demo|seed|simulation|scenario/i,
  /^POST \/api\/auth\/logout/,
  /delete-s3-object/,
];

function listRoutes(app) {
  const out = [];
  const walk = (stack) => {
    for (const layer of stack || []) {
      if (layer.route) {
        const paths = Array.isArray(layer.route.path) ? layer.route.path : [layer.route.path];
        for (const p of paths) {
          for (const method of Object.keys(layer.route.methods || {})) {
            if (layer.route.methods[method]) out.push(`${method.toUpperCase()} ${String(p)}`);
          }
        }
      } else if (layer.handle && Array.isArray(layer.handle.stack)) {
        walk(layer.handle.stack);
      }
    }
  };
  walk((app.router && app.router.stack) || app._router.stack);
  return out;
}

function shapeOf(value, depth = 0) {
  if (Array.isArray(value)) return value.length ? [shapeOf(value[0], depth + 1)] : [];
  if (value && typeof value === 'object') {
    if (depth >= 2) return '{…}';
    const out = {};
    for (const key of Object.keys(value).sort()) out[key] = shapeOf(value[key], depth + 1);
    return out;
  }
  return value === null ? 'null' : typeof value;
}

// Messages carry ids and stamps; the snapshot keeps their wording only.
const steady = (text) => String(text)
  .replace(/\d{4}-\d{2}-\d{2}T[\d:.]+Z/g, '<time>')
  .replace(/\d+/g, '<n>');

test('the routes outside the business modules answer as they did', async (t) => {
  const tempDir = makeTempDir('paper-remaining-routes-');
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'remaining@example.test';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const server = http.createServer(backend.app);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  t.after(() => server.close());
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  const login = await fetch(`${baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'remaining@example.test', password: 'OwnerPass1234' }),
  }).then((r) => r.json());
  assert.ok(login.token);

  const routes = [...new Set(listRoutes(backend.app))]
    .filter((route) => {
      const routePath = route.split(' ')[1];
      if (SKIP.some((pattern) => pattern.test(route))) return false;
      if (!routePath.startsWith('/api/')) return !/^\/(runs|templates|health)/.test(routePath);
      return !MODULE_SEGMENTS.has(routePath.slice(5).split('/')[0]);
    })
    // Reads first, then the writes that change the least, so what one call
    // leaves behind does not decide how the next one answers.
    .sort((a, b) => {
      const rank = (r) => ['GET', 'PUT', 'PATCH', 'POST', 'DELETE'].indexOf(r.split(' ')[0]);
      return rank(a) - rank(b) || a.localeCompare(b);
    });
  assert.ok(routes.length > 60, `expected the remaining surface, saw ${routes.length}`);

  const call = async (route, token) => {
    const [method, pattern] = route.split(' ');
    const url = baseUrl + pattern.replace(/:[A-Za-z_]+\??/g, '999999').replace(/\*\w*/g, 'x');
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 4000);
    try {
      const res = await fetch(url, {
        method,
        headers: {
          ...(method === 'GET' ? {} : { 'Content-Type': 'application/json' }),
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: method === 'GET' ? undefined : '{}',
        signal: controller.signal,
      });
      const type = (res.headers.get('content-type') || '').split(';')[0];
      const text = await res.text();
      let body = null;
      try { body = JSON.parse(text); } catch (_) { /* not JSON */ }
      return {
        status: res.status,
        type,
        shape: body === null ? null : shapeOf(body),
        error: body && typeof body === 'object' && typeof body.error === 'string' ? steady(body.error) : undefined,
      };
    } catch (error) {
      return { status: 'no answer', type: error.name };
    } finally {
      clearTimeout(timer);
    }
  };

  const taken = {};
  for (const route of routes) taken[`anonymous ${route}`] = await call(route, null);
  for (const route of routes) taken[`owner ${route}`] = await call(route, login.token);
  // Through JSON, so it compares like the file it is kept in.
  const snapshot = JSON.parse(JSON.stringify(taken));

  if (process.env.UPDATE_ROUTE_SNAPSHOT === '1') {
    fs.writeFileSync(FIXTURE, `${JSON.stringify(snapshot, null, 1)}\n`);
    return;
  }
  const expected = JSON.parse(fs.readFileSync(FIXTURE, 'utf8'));
  assert.deepEqual(Object.keys(snapshot).sort(), Object.keys(expected).sort(), 'the same routes are called');
  for (const key of Object.keys(expected)) {
    assert.deepEqual(snapshot[key], expected[key], key);
  }
});
