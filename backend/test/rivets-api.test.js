const assert = require('node:assert/strict');
const http = require('node:http');
const path = require('node:path');
const test = require('node:test');
const { makeTempDir } = require('./helpers/temp-dir');
const { parseMillimetres, parsePrice, formatPrice, rivetName } = require('../modules/items/rivets');

// The rivet form over HTTP (Docs/architecture/13-raw-material-forms.md).
// The owner's drawing: Bimetal, Head OD 3.5, Head Diameter 1.3, Shank
// Diameter 2.0, Shank Length 2.0, Silver Layer 0.25, Flat →
//   Bimetal Rivet 3.5 X 1.3 / 2.0 X 2.0 Flat (0.25)

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
    server.on('error', reject);
  });
}

async function boot() {
  const tempDir = makeTempDir('paper-rivets-');
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'rivets@example.test';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;
  const login = await fetch(`${baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'rivets@example.test', password: 'OwnerPass1234' }),
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
  rivetType: 'Bimetal',
  headType: 'F',
  headOd: '3.5',
  headDia: '1.3',
  shankDia: '2.0',
  shankLength: '2.0',
  silverLayer: '0.25',
};

test('numbers are parsed exactly, never through a float', () => {
  assert.deepEqual(parseMillimetres('2.0', 'x', true), { text: '2.0', nm: 2000000 });
  assert.deepEqual(parseMillimetres(' 0.25 ', 'x', true), { text: '0.25', nm: 250000 });
  assert.deepEqual(parseMillimetres('02.10', 'x', true), { text: '2.10', nm: 2100000 });
  assert.equal(parseMillimetres('', 'x', false), null);
  assert.throws(() => parseMillimetres('', 'Head OD', true), /Head OD is needed/);
  assert.throws(() => parseMillimetres('2,0', 'x', true), /number of millimetres/);
  assert.throws(() => parseMillimetres('0', 'x', true), /more than 0/);
  assert.equal(parsePrice('0.035'), 35000);
  assert.equal(parsePrice('₹ 12.5'), 12500000);
  assert.equal(formatPrice(35000), '0.035');
  assert.equal(formatPrice(12500000), '12.50');
  assert.equal(formatPrice(7000000), '7.00');
});

test('a rivet: made from its spec, named from it, priced by vendors', async (t) => {
  const ctx = await boot();
  t.after(() => new Promise((resolve) => ctx.server.close(resolve)));

  const vendorA = (await api(ctx, 'POST', '/api/vendors', { name: 'Silvertip Contacts' })).body.vendor;
  const vendorB = (await api(ctx, 'POST', '/api/vendors', { name: 'Shree Rivets' })).body.vendor;

  const created = await api(ctx, 'POST', '/api/raw-materials/rivets', {
    ...drawing,
    code: 'BR-35',
    vendors: [
      { vendorId: vendorA.id, price: '0.035', basis: 'piece' },
      { vendorId: vendorB.id, price: '32.5', basis: 'thousand' },
    ],
  });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  const rivet = created.body.rivet;
  assert.equal(rivet.name, 'Bimetal Rivet 3.5 X 1.3 / 2.0 X 2.0 Flat (0.25)');
  assert.equal(rivet.code, 'BR-35');
  assert.equal(rivet.headType, 'F');
  assert.equal(rivet.headTypeLabel, 'Flat');
  assert.deepEqual(rivet.shankDia, { mm: '2.0', nm: 2000000 });
  assert.deepEqual(
    rivet.vendors.map((v) => [v.vendorName, v.price, v.basis]),
    [['Silvertip Contacts', '0.035', 'piece'], ['Shree Rivets', '32.50', 'thousand']],
  );

  // It is an ordinary item in the Rivets group, counted in Pieces.
  const item = await ctx.backend.get(
    `SELECT i.name, g.system_key, u.name AS unit FROM items i
       JOIN groups g ON g.id = i.group_id JOIN units u ON u.id = i.unit_id WHERE i.id = ?`,
    [rivet.itemId],
  );
  assert.deepEqual(item, {
    name: 'Bimetal Rivet 3.5 X 1.3 / 2.0 X 2.0 Flat (0.25)',
    system_key: 'raw_materials.rivets',
    unit: 'Piece',
  });

  // The same spec again — even written 2 instead of 2.0 — is the same rivet.
  const twin = await api(ctx, 'POST', '/api/raw-materials/rivets', { ...drawing, shankDia: '2' });
  assert.equal(twin.status, 409);
  assert.equal(twin.body.code, 'rivet_exists');
  assert.equal(twin.body.rivet.itemId, rivet.itemId);

  // Round head, no silver layer: another rivet, and the name leaves the (…) off.
  const round = await api(ctx, 'POST', '/api/raw-materials/rivets', {
    ...drawing, rivetType: 'Copper', headType: 'r', silverLayer: '', code: 'br-35',
  });
  assert.equal(round.status, 409, 'the code is taken, ignoring case');
  assert.equal(round.body.code, 'code_taken');
  const round2 = await api(ctx, 'POST', '/api/raw-materials/rivets', {
    ...drawing, rivetType: 'Copper', headType: 'r', silverLayer: '',
  });
  assert.equal(round2.status, 201, JSON.stringify(round2.body));
  assert.equal(round2.body.rivet.name, 'Copper Rivet 3.5 X 1.3 / 2.0 X 2.0 Round');
  assert.equal(round2.body.rivet.silverLayer, null);

  // The three types, and nothing else. Only bimetal has a silver layer.
  const brass = await api(ctx, 'POST', '/api/raw-materials/rivets', { ...drawing, rivetType: 'Brass' });
  assert.equal(brass.status, 400);
  assert.equal(brass.body.code, 'bad_type');
  const bareBimetal = await api(ctx, 'POST', '/api/raw-materials/rivets', { ...drawing, shankLength: '4.0', silverLayer: '' });
  assert.equal(bareBimetal.status, 400);
  assert.match(bareBimetal.body.error, /Silver Layer is needed/);
  const silverCopper = await api(ctx, 'POST', '/api/raw-materials/rivets', { ...drawing, rivetType: 'Copper', shankLength: '4.0' });
  assert.equal(silverCopper.status, 400);
  assert.equal(silverCopper.body.code, 'no_silver_layer');
  const aluminum = await api(ctx, 'POST', '/api/raw-materials/rivets', {
    ...drawing, rivetType: 'aluminum', silverLayer: '', shankLength: '4.0',
  });
  assert.equal(aluminum.status, 201, JSON.stringify(aluminum.body));
  assert.equal(aluminum.body.rivet.rivetType, 'Aluminium', 'spelled one way');
  assert.equal(aluminum.body.rivet.name, 'Aluminium Rivet 3.5 X 1.3 / 2.0 X 4.0 Flat');

  // Bad input names the field.
  const bad = await api(ctx, 'POST', '/api/raw-materials/rivets', { ...drawing, headOd: '' });
  assert.equal(bad.status, 400);
  assert.match(bad.body.error, /Head OD/);
  const badHead = await api(ctx, 'POST', '/api/raw-materials/rivets', { ...drawing, headType: 'X' });
  assert.equal(badHead.status, 400);
  const ghostVendor = await api(ctx, 'POST', '/api/raw-materials/rivets', {
    ...drawing, shankLength: '3.0', vendors: [{ vendorId: 999999, price: '1', basis: 'piece' }],
  });
  assert.equal(ghostVendor.status, 400);
  assert.equal(ghostVendor.body.code, 'unknown_vendor');

  // Update: the name follows the spec; vendors absent = kept.
  const changed = await api(ctx, 'PUT', `/api/raw-materials/rivets/${rivet.itemId}`, {
    ...drawing, shankLength: '2.5',
  });
  assert.equal(changed.status, 200, JSON.stringify(changed.body));
  assert.equal(changed.body.rivet.name, 'Bimetal Rivet 3.5 X 1.3 / 2.0 X 2.5 Flat (0.25)');
  assert.equal(changed.body.rivet.code, 'BR-35', 'code absent = kept');
  assert.equal(changed.body.rivet.vendors.length, 2, 'vendors absent = kept');
  // Vendors given: the whole list. [] clears.
  const cleared = await api(ctx, 'PUT', `/api/raw-materials/rivets/${rivet.itemId}`, { ...drawing, shankLength: '2.5', vendors: [] });
  assert.equal(cleared.body.rivet.vendors.length, 0);
  // Changing into another rivet's spec is refused.
  const clash = await api(ctx, 'PUT', `/api/raw-materials/rivets/${round2.body.rivet.itemId}`, { ...drawing, shankLength: '2.5' });
  assert.equal(clash.status, 409);

  const list = await api(ctx, 'GET', '/api/raw-materials/rivets');
  assert.equal(list.status, 200);
  assert.deepEqual(list.body.rivets.map((r) => r.name).filter((n) => !n.includes('6.0')).sort(), [
    'Aluminium Rivet 3.5 X 1.3 / 2.0 X 4.0 Flat',
    'Bimetal Rivet 3.5 X 1.3 / 2.0 X 2.5 Flat (0.25)',
    'Copper Rivet 3.5 X 1.3 / 2.0 X 2.0 Round',
  ]);
  assert.equal((await api(ctx, 'GET', '/api/raw-materials/rivets/999999')).status, 404);

  // An item filed under Rivets from the plain item form has no spec; PUT
  // gives it one on the same item (the editor's Rivet view). Any other item
  // cannot be made a rivet.
  const rivetsGroup = await ctx.backend.get("SELECT id, unit_id FROM groups WHERE system_key = 'raw_materials.rivets'");
  const stamp = new Date().toISOString();
  const plain = await ctx.backend.run(
    `INSERT INTO items (name, display_name, group_id, unit_id, created_at, updated_at) VALUES ('rivet typed by hand', 'rivet typed by hand', ?, ?, ?, ?)`,
    [rivetsGroup.id, rivetsGroup.unit_id, stamp, stamp],
  );
  const attached = await api(ctx, 'PUT', `/api/raw-materials/rivets/${plain.lastID}`, {
    ...drawing, rivetType: 'Copper', silverLayer: '', shankLength: '6.0',
  });
  assert.equal(attached.status, 200, JSON.stringify(attached.body));
  assert.equal(attached.body.rivet.itemId, plain.lastID, 'the same item, not a new one');
  assert.equal(attached.body.rivet.name, 'Copper Rivet 3.5 X 1.3 / 2.0 X 6.0 Flat');
  const elsewhere = await ctx.backend.get("SELECT id FROM groups WHERE system_key = 'raw_materials.springs'");
  const notRivet = await ctx.backend.run(
    `INSERT INTO items (name, display_name, group_id, unit_id, created_at, updated_at) VALUES ('a spring', 'a spring', ?, ?, ?, ?)`,
    [elsewhere.id, rivetsGroup.unit_id, stamp, stamp],
  );
  assert.equal((await api(ctx, 'PUT', `/api/raw-materials/rivets/${notRivet.lastID}`, { ...drawing, shankLength: '7.0' })).status, 404);

  // Not signed in: refused. The path is gated, not left open.
  const anonymous = await api(ctx, 'GET', '/api/raw-materials/rivets', undefined, {});
  assert.equal(anonymous.status, 401);

  // Deleting the item takes its spec and prices with it.
  await api(ctx, 'PUT', `/api/raw-materials/rivets/${rivet.itemId}`, {
    ...drawing, shankLength: '2.5', vendors: [{ vendorId: vendorA.id, price: '1', basis: 'kg' }],
  });
  const del = await api(ctx, 'DELETE', `/api/items/${rivet.itemId}`);
  assert.ok([200, 204].includes(del.status), JSON.stringify(del.body));
  assert.equal((await ctx.backend.get('SELECT COUNT(*) AS n FROM raw_material_specs WHERE item_id = ?', [rivet.itemId])).n, 0);
  assert.equal((await ctx.backend.get('SELECT COUNT(*) AS n FROM item_vendor_prices WHERE item_id = ?', [rivet.itemId])).n, 0);
});

test('the name rule, on its own', () => {
  const spec = {
    rivetType: 'Bimetal', headType: 'F',
    headOd: { text: '3.5' }, headDia: { text: '1.3' }, shankDia: { text: '2.0' },
    shankLength: { text: '2.0' }, silverLayer: { text: '0.25' },
  };
  assert.equal(rivetName(spec), 'Bimetal Rivet 3.5 X 1.3 / 2.0 X 2.0 Flat (0.25)');
});
