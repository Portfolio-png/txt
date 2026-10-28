const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// The item sheet's own property columns (061): added with the sheet's "+",
// each with a list of options, kept for everyone until the column is removed.
// They lived only in the sheet's memory before, and were gone on reopen.

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
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;
  const login = async (who, password) =>
    (
      await fetch(`${baseUrl}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: who, password }),
      }).then((r) => r.json())
    ).token;
  const token = await login(email, 'OwnerPass1234');
  const as = (tok) => async (method, p, body) => {
    const r = await fetch(`${baseUrl}${p}`, {
      method,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${tok}` },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: r.status, body: await r.json() };
  };
  return { backend, server, call: as(token), as, login };
}

test('a property column is kept with its options until it is removed', async () => {
  const ctx = await boot('paper-sheet-props-', 'sheet-props@paper.local');
  const { call } = ctx;
  try {
    const made = await call('POST', '/api/item-sheet-properties', {
      name: '  Plating ',
      kind: 'text',
      options: ['Nickel', ' Chrome ', 'nickel', '', 'Gold'],
    });
    assert.equal(made.status, 201, JSON.stringify(made.body));
    const plating = made.body.property;
    assert.equal(plating.name, 'Plating');
    assert.equal(plating.key, 'plating');
    assert.equal(plating.kind, 'text');
    // Trimmed, blanks out, duplicates (ignoring case) out, order kept.
    assert.deepEqual(plating.options, ['Nickel', 'Chrome', 'Gold']);

    const second = await call('POST', '/api/item-sheet-properties', { name: 'Temper' });
    assert.equal(second.body.property.position, plating.position + 1, 'appended in order');

    // The same name, any case, is the same column.
    const dup = await call('POST', '/api/item-sheet-properties', { name: 'PLATING' });
    assert.equal(dup.status, 409);
    assert.equal(dup.body.code, 'property_exists');
    assert.equal(dup.body.property.id, plating.id);

    // A value typed on a part joins the list once, however often it is sent.
    let added = await call('POST', `/api/item-sheet-properties/${plating.id}/options`, { label: 'Satin' });
    assert.deepEqual(added.body.property.options, ['Nickel', 'Chrome', 'Gold', 'Satin']);
    added = await call('POST', `/api/item-sheet-properties/${plating.id}/options`, { label: 'satin' });
    assert.deepEqual(added.body.property.options, ['Nickel', 'Chrome', 'Gold', 'Satin']);

    // The dropdown's delete takes one option off, in any case, and only it.
    let gone = await call('DELETE', `/api/item-sheet-properties/${plating.id}/options?label=${encodeURIComponent('GOLD')}`);
    assert.equal(gone.status, 200, JSON.stringify(gone.body));
    assert.deepEqual(gone.body.property.options, ['Nickel', 'Chrome', 'Satin']);
    gone = await call('DELETE', `/api/item-sheet-properties/${plating.id}/options?label=Gold`);
    assert.deepEqual(gone.body.property.options, ['Nickel', 'Chrome', 'Satin'], 'already gone is fine');
    const nameless = await call('DELETE', `/api/item-sheet-properties/${plating.id}/options`);
    assert.equal(nameless.status, 400);

    // Rename is the label only; the key the parts carry stays.
    const renamed = await call('PATCH', `/api/item-sheet-properties/${plating.id}`, {
      displayName: 'Plating finish',
      options: ['Chrome', 'Nickel'],
    });
    assert.equal(renamed.body.property.name, 'Plating finish');
    assert.equal(renamed.body.property.key, 'plating');
    assert.equal(renamed.body.property.propertyName, 'Plating', 'what parts carry stays');
    assert.deepEqual(renamed.body.property.options, ['Chrome', 'Nickel']);

    const listed = await call('GET', '/api/item-sheet-properties');
    assert.deepEqual(listed.body.properties.map((p) => p.key), ['plating', 'temper']);

    // It reaches other windows: the change is in the log.
    const logged = await ctx.backend.get(
      "SELECT COUNT(*) AS c FROM changelog WHERE table_name = 'item_sheet_properties' AND record_id = ?",
      [plating.id],
    );
    assert.ok(Number(logged.c) >= 3);

    const removed = await call('DELETE', `/api/item-sheet-properties/${plating.id}`);
    assert.equal(removed.status, 200);
    const after = await call('GET', '/api/item-sheet-properties');
    assert.deepEqual(after.body.properties.map((p) => p.key), ['temper']);
  } finally {
    await closeServer(ctx.server);
  }
});

test('what is not a property column is refused', async () => {
  const ctx = await boot('paper-sheet-props-bad-', 'sheet-props-bad@paper.local');
  const { call } = ctx;
  try {
    assert.equal((await call('POST', '/api/item-sheet-properties', { name: '' })).status, 400);
    assert.equal(
      (await call('POST', '/api/item-sheet-properties', { name: 'Finish', kind: 'colour' })).status,
      400,
    );
    assert.equal(
      (await call('POST', '/api/item-sheet-properties', { name: 'Finish', options: ['x'.repeat(81)] }))
        .status,
      400,
    );
    assert.equal(
      (await call('POST', '/api/item-sheet-properties', { name: 'Finish', options: 'Chrome' })).status,
      400,
    );
    assert.equal((await call('DELETE', '/api/item-sheet-properties/99999')).status, 404);
  } finally {
    await closeServer(ctx.server);
  }
});

test('only someone who may change items may change the sheet columns', async () => {
  const ctx = await boot('paper-sheet-props-authz-', 'sheet-props-authz@paper.local');
  try {
    // Staff read every module and write none by default.
    const created = await ctx.call('POST', '/api/users', {
      name: 'Reader',
      email: 'sheet-reader@paper.local',
      password: 'ReaderPass1234',
      role: 'user',
      permissions: ['items.read', 'login.desktop'],
    });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    const reader = ctx.as(await ctx.login('sheet-reader@paper.local', 'ReaderPass1234'));

    assert.equal((await reader('GET', '/api/item-sheet-properties')).status, 200);
    assert.equal(
      (await reader('POST', '/api/item-sheet-properties', { name: 'Plating' })).status,
      403,
    );
  } finally {
    await closeServer(ctx.server);
  }
});
