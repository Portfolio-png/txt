const assert = require('node:assert/strict');
const http = require('node:http');
const path = require('node:path');
const test = require('node:test');
const { makeTempDir } = require('./helpers/temp-dir');

// The vendor master over HTTP.
//
// Written before the vendors code left server.js, so that what it asserts is
// what the old code did, not what the new code does. The two things worth the
// most are the ones that cross into another module's tables: a vendor's
// usageCount and "still named on N challans" both come from
// delivery_challans, and both have to survive that read moving behind a port.

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
  const tempDir = makeTempDir('paper-vendors-');
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'vendors@example.test';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;
  const login = await fetch(`${baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'vendors@example.test', password: 'OwnerPass1234' }),
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

async function insertReceptionChallan(backend, vendorId, challanNo, itemId = 1) {
  const now = new Date().toISOString();
  const result = await backend.run(
    `INSERT INTO delivery_challans
       (type, challan_no, date, vendor_id, vendor_name, status, created_at, updated_at)
     VALUES ('reception', ?, ?, ?, 'x', 'issued', ?, ?)`,
    [challanNo, now.slice(0, 10), vendorId, now, now],
  );
  await backend.run(
    `INSERT INTO delivery_challan_items
       (challan_id, item_id, variation_leaf_node_id, particulars, created_at, updated_at)
     VALUES (?, ?, 7, 'Sheet 1.2mm', ?, ?)`,
    [result.lastID, itemId, now, now],
  );
  return result.lastID;
}

test('vendors: create, read, list, update', async (t) => {
  const ctx = await boot();
  t.after(() => closeServer(ctx.server));

  const created = await api(ctx, 'POST', '/api/vendors', {
    name: '  Alpha   Metals ',
    gstNumber: ' 27 abcde1234f1z5 ',
    phone: '9000000001',
  });
  assert.equal(created.status, 201);
  assert.equal(created.body.success, true);
  const vendor = created.body.vendor;
  assert.equal(vendor.name, 'Alpha   Metals', 'name is trimmed at the ends only');
  assert.equal(vendor.gstNumber, '27ABCDE1234F1Z5', 'gst loses spaces and is upper-cased');
  assert.equal(vendor.usageCount, 0);
  assert.equal(vendor.isArchived, false);

  const one = await api(ctx, 'GET', `/api/vendors/${vendor.id}`);
  assert.equal(one.status, 200);
  assert.equal(one.body.vendor.id, vendor.id);
  assert.equal(one.body.vendor.usageCount, 0);

  const missing = await api(ctx, 'GET', '/api/vendors/999999');
  assert.equal(missing.status, 404);
  assert.equal(missing.body.vendor, null);

  const list = await api(ctx, 'GET', '/api/vendors');
  assert.equal(list.status, 200);
  assert.ok(list.body.vendors.some((v) => v.id === vendor.id));
  const names = list.body.vendors.filter((v) => !v.isArchived).map((v) => v.name.toLowerCase());
  assert.deepEqual(names, [...names].sort(), 'active vendors read in name order');

  const patched = await api(ctx, 'PATCH', `/api/vendors/${vendor.id}`, {
    name: 'Alpha Metals',
    phone: '9000000002',
  });
  assert.equal(patched.status, 200);
  assert.equal(patched.body.vendor.phone, '9000000002');
  assert.equal(
    patched.body.vendor.gstNumber,
    '',
    'a full-replace save with no gst clears it, as the form sends everything',
  );
});

test('vendors: a name is required and a duplicate name or GST is refused', async (t) => {
  const ctx = await boot();
  t.after(() => closeServer(ctx.server));

  const blank = await api(ctx, 'POST', '/api/vendors', { name: '   ' });
  assert.equal(blank.status, 400);
  assert.equal(blank.body.vendor, null);

  const first = await api(ctx, 'POST', '/api/vendors', {
    name: 'Beta Traders',
    gstNumber: '29AAAAA0000A1Z5',
  });
  assert.equal(first.status, 201);

  const sameName = await api(ctx, 'POST', '/api/vendors', { name: 'beta   TRADERS' });
  assert.equal(sameName.status, 409);

  const sameGst = await api(ctx, 'POST', '/api/vendors', {
    name: 'Gamma Traders',
    gstNumber: '29 aaaaa0000a1z5',
  });
  assert.equal(sameGst.status, 409);

  const second = await api(ctx, 'POST', '/api/vendors', { name: 'Delta Traders' });
  assert.equal(second.status, 201);
  const clash = await api(ctx, 'PATCH', `/api/vendors/${second.body.vendor.id}`, {
    name: 'Beta Traders',
  });
  assert.equal(clash.status, 409, 'renaming onto an existing vendor is refused too');

  const ghost = await api(ctx, 'PATCH', '/api/vendors/999999', { name: 'Nobody' });
  assert.equal(ghost.status, 404);
});

test('vendors: challans count as usage, block delete, and feed purchase history', async (t) => {
  const ctx = await boot();
  t.after(() => closeServer(ctx.server));

  const made = await api(ctx, 'POST', '/api/vendors', { name: 'Epsilon Steels' });
  const id = made.body.vendor.id;

  const before = await api(ctx, 'GET', `/api/vendors/${id}/purchase-history`);
  assert.equal(before.status, 200);
  assert.deepEqual(before.body.history, []);

  await insertReceptionChallan(ctx.backend, id, 'TST-REC-1');
  await insertReceptionChallan(ctx.backend, id, 'TST-REC-2');

  const one = await api(ctx, 'GET', `/api/vendors/${id}`);
  assert.equal(one.body.vendor.usageCount, 2);
  const list = await api(ctx, 'GET', '/api/vendors');
  assert.equal(list.body.vendors.find((v) => v.id === id).usageCount, 2);

  const history = await api(ctx, 'GET', `/api/vendors/${id}/purchase-history`);
  assert.equal(history.status, 200);
  assert.equal(history.body.history.length, 1, 'the same item and leaf collapse to one line');
  assert.equal(history.body.history[0].variationLeafNodeId, 7);
  assert.ok(history.body.history[0].particulars);

  const blocked = await api(ctx, 'DELETE', `/api/vendors/${id}`);
  assert.equal(blocked.status, 409);
  assert.equal(blocked.body.code, 'vendor_in_use');
  assert.match(blocked.body.error, /2 challans/);
});

test('vendors: an unused vendor can be deleted and is gone afterwards', async (t) => {
  const ctx = await boot();
  t.after(() => closeServer(ctx.server));

  const made = await api(ctx, 'POST', '/api/vendors', { name: 'Zeta Supplies' });
  const id = made.body.vendor.id;

  const deleted = await api(ctx, 'DELETE', `/api/vendors/${id}`);
  assert.equal(deleted.status, 200);
  assert.equal(deleted.body.success, true);

  const after = await api(ctx, 'GET', `/api/vendors/${id}`);
  assert.equal(after.status, 404);
});

// What a vendor is for (2026-11-24): raw material, outsourced work, or both.
test('vendors: raw material and outsourcing are ticks; an update without them keeps them', async (t) => {
  const ctx = await boot();
  t.after(() => closeServer(ctx.server));

  const plain = await api(ctx, 'POST', '/api/vendors', { name: 'Untyped Traders' });
  assert.equal(plain.status, 201, JSON.stringify(plain.body));
  assert.equal(plain.body.vendor.suppliesRawMaterial, false);
  assert.equal(plain.body.vendor.doesOutsourcing, false);

  const both = await api(ctx, 'POST', '/api/vendors', {
    name: 'Both Ways Metals',
    suppliesRawMaterial: true,
    doesOutsourcing: true,
  });
  assert.equal(both.status, 201, JSON.stringify(both.body));
  assert.equal(both.body.vendor.suppliesRawMaterial, true);
  assert.equal(both.body.vendor.doesOutsourcing, true);
  const id = both.body.vendor.id;

  // Not mentioned: kept.
  const renamed = await api(ctx, 'PATCH', `/api/vendors/${id}`, { name: 'Both Ways Metals Pvt' });
  assert.equal(renamed.status, 200, JSON.stringify(renamed.body));
  assert.equal(renamed.body.vendor.suppliesRawMaterial, true);
  assert.equal(renamed.body.vendor.doesOutsourcing, true);

  // Unticked: cleared, the other left as it is.
  const unticked = await api(ctx, 'PATCH', `/api/vendors/${id}`, {
    name: 'Both Ways Metals Pvt',
    doesOutsourcing: false,
  });
  assert.equal(unticked.body.vendor.suppliesRawMaterial, true);
  assert.equal(unticked.body.vendor.doesOutsourcing, false);

  const listed = await api(ctx, 'GET', '/api/vendors');
  const row = listed.body.vendors.find((v) => v.id === id);
  assert.equal(row.suppliesRawMaterial, true);
  assert.equal(row.doesOutsourcing, false);

  const wrong = await api(ctx, 'POST', '/api/vendors', { name: 'Odd Co', doesOutsourcing: 'yes' });
  assert.equal(wrong.status, 400, 'a tick is true or false');
});
