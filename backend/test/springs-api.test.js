const assert = require('node:assert/strict');
const http = require('node:http');
const path = require('node:path');
const test = require('node:test');
const { makeTempDir } = require('./helpers/temp-dir');
const { springName } = require('../modules/items/springs');

// The spring form over HTTP (Docs/architecture/13-raw-material-forms.md).
// The owner's drawing: Coil Length 114, Coil Number 6, Coil Hook Double Hook →
//   Double Hook Spring 114 X 6

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
    server.on('error', reject);
  });
}

async function boot() {
  const tempDir = makeTempDir('paper-springs-');
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'springs@example.test';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;
  const login = await fetch(`${baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'springs@example.test', password: 'OwnerPass1234' }),
  }).then((r) => r.json());
  assert.ok(login.token, 'expected a login token');
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

const drawing = {
  kind: 'Double Hook',
  coilLength: '114',
  coilNumber: '6',
  coilOd: '8.0',
  coilId: '6.4',
  wireGauge: '22 SWG',
  wireGrade: 'SS 302',
};

test('the name rule matches the drawing, and follows a naming format', () => {
  const spec = { kind: 'Double Hook', coilLength: { text: '114' }, coilNumber: 6, wireGauge: '22 SWG' };
  assert.equal(springName(spec), 'Double Hook Spring 114 X 6');
  assert.equal(
    springName({
      ...spec,
      nameFormat: [
        { block: 'coilLength', sep: ' ' },
        { block: 'coilNumber', sep: 'x' },
        { block: 'wireGauge', sep: '-' },
        { block: 'kind', sep: '+' },
        { block: 'springType', sep: ' ' },
      ],
    }),
    '114 X 6 - 22 SWG + Double Hook',
    'a block with nothing in it (no type) is left out with its separator',
  );
});

test('a spring: made from its spec, named from it, priced by vendors', async (t) => {
  const ctx = await boot();
  t.after(() => new Promise((resolve) => ctx.server.close(resolve)));
  const vendor = (await api(ctx, 'POST', '/api/vendors', { name: 'Coil Works' })).body.vendor;

  const created = await api(ctx, 'POST', '/api/raw-materials/springs', {
    ...drawing,
    code: 'SP-114',
    vendors: [{ vendorId: vendor.id, price: '1.25', basis: 'piece' }],
  });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  const spring = created.body.spring;
  assert.equal(spring.name, 'Double Hook Spring 114 X 6');
  assert.equal(spring.code, 'SP-114');
  assert.deepEqual(spring.coilLength, { mm: '114', nm: 114000000 });
  assert.equal(spring.coilNumber, 6);
  assert.equal(spring.wireGauge, '22 SWG', 'verbatim');
  assert.deepEqual(spring.vendors.map((v) => [v.vendorName, v.price, v.basis]), [['Coil Works', '1.25', 'piece']]);

  // An ordinary item in Springs, counted in Pieces.
  const item = await ctx.backend.get(
    `SELECT g.system_key, u.name AS unit FROM items i
       JOIN groups g ON g.id = i.group_id JOIN units u ON u.id = i.unit_id WHERE i.id = ?`,
    [spring.itemId],
  );
  assert.deepEqual(item, { system_key: 'raw_materials.springs', unit: 'Piece' });

  // Everything measured is the spring: the same again is refused…
  const twin = await api(ctx, 'POST', '/api/raw-materials/springs', {
    ...drawing, kind: 'double hook', coilLength: '114.0',
  });
  assert.equal(twin.status, 409);
  assert.equal(twin.body.code, 'spring_exists');
  assert.equal(twin.body.spring.itemId, spring.itemId);
  // …another wire is another spring, but not under the same name: the user
  // is told to put the wire in the name, and then it saves.
  const otherWire = { ...drawing, wireGauge: '24 SWG', code: '' };
  const sameName = await api(ctx, 'POST', '/api/raw-materials/springs', otherWire);
  assert.equal(sameName.status, 409);
  assert.equal(sameName.body.code, 'name_taken');
  assert.match(sameName.body.error, /Wire Gauge/);
  const named = await api(ctx, 'POST', '/api/raw-materials/springs', {
    ...otherWire,
    nameFormat: [
      { block: 'kind', sep: ' ' },
      { block: 'spring', sep: ' ' },
      { block: 'coilLength', sep: ' ' },
      { block: 'coilNumber', sep: 'x' },
      { block: 'wireGauge', sep: '-' },
    ],
  });
  assert.equal(named.status, 201, JSON.stringify(named.body));
  assert.equal(named.body.spring.name, 'Double Hook Spring 114 X 6 - 24 SWG');
  assert.equal(named.body.spring.nameFormat.length, 5, 'the format is kept on the spring');

  // A conical spring has its own sizes; a type is Title Case.
  const conical = await api(ctx, 'POST', '/api/raw-materials/springs', {
    kind: 'conical', springType: '15 a steel', freeLength: '20', totalCoils: '5',
    smallOd: '6', largeOd: '12', wireDiameter: '0.8',
  });
  assert.equal(conical.status, 201, JSON.stringify(conical.body));
  assert.equal(conical.body.spring.name, 'Conical Spring 20 X 5');
  assert.equal(conical.body.spring.springType, '15 A Steel');
  assert.deepEqual(conical.body.spring.wireDiameter, { mm: '0.8', nm: 800000 });
  const upsideDown = await api(ctx, 'POST', '/api/raw-materials/springs', {
    kind: 'Conical', freeLength: '21', totalCoils: '5', smallOd: '12', largeOd: '6',
  });
  assert.equal(upsideDown.status, 400);
  assert.match(upsideDown.body.error, /Small OD must be smaller than Large OD/);
  assert.equal((await api(ctx, 'POST', '/api/raw-materials/springs', { ...drawing, kind: 'Leaf' })).status, 400);

  // Only what the name needs is required; the rest is checked when given.
  const bare = await api(ctx, 'POST', '/api/raw-materials/springs', {
    coilHook: 'double hook', coilLength: '50', coilNumber: '12', // the old field name still reads as the kind
  });
  assert.equal(bare.status, 201, JSON.stringify(bare.body));
  assert.equal(bare.body.spring.name, 'Double Hook Spring 50 X 12', 'one spelling per hook');
  assert.equal(bare.body.spring.coilOd, null);
  for (const [body, why] of [
    [{ ...drawing, kind: '' }, /Spring Kind/],
    [{ ...drawing, coilNumber: '6.5' }, /whole number/],
    [{ ...drawing, coilLength: '' }, /Coil Length/],
    [{ ...drawing, coilLength: '70', coilId: '9' }, /smaller than Coil OD/],
  ]) {
    const refused = await api(ctx, 'POST', '/api/raw-materials/springs', body);
    assert.equal(refused.status, 400, JSON.stringify(body));
    assert.match(refused.body.error, why);
  }

  // Update: the name follows; vendors absent = kept.
  const changed = await api(ctx, 'PUT', `/api/raw-materials/springs/${spring.itemId}`, { ...drawing, coilNumber: '8' });
  assert.equal(changed.status, 200, JSON.stringify(changed.body));
  assert.equal(changed.body.spring.name, 'Double Hook Spring 114 X 8');
  assert.equal(changed.body.spring.vendors.length, 1);

  const list = await api(ctx, 'GET', '/api/raw-materials/springs');
  assert.deepEqual(list.body.springs.map((s) => s.name).sort(), [
    'Conical Spring 20 X 5',
    'Double Hook Spring 114 X 6 - 24 SWG',
    'Double Hook Spring 114 X 8',
    'Double Hook Spring 50 X 12',
  ]);
  // Rivets and springs are separate forms: neither lists the other.
  assert.equal((await api(ctx, 'GET', '/api/raw-materials/rivets')).body.rivets.length, 0);
  assert.equal((await api(ctx, 'GET', '/api/raw-materials/springs', undefined, {})).status, 401);
});
