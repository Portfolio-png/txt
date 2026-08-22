const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// A part needs a blank size before it can be planned onto a sheet. This is the
// round trip that proves the column exists, the insert's placeholders line up
// with its columns, and an update that omits the size does not wipe it.

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => {
      resolve({ server, port: server.address().port });
    });
    server.on('error', reject);
  });
}

function closeServer(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}

test('an item carries its blank size through create, read and update', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-blank-size-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'blank-owner@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const loginResponse = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: process.env.PAPER_SUPER_ADMIN_EMAIL,
        password: process.env.PAPER_SUPER_ADMIN_PASSWORD,
      }),
    });
    const { token } = await loginResponse.json();
    assert.ok(token, 'expected a login token');
    const authHeaders = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    };

    const existing = await fetch(`${baseUrl}/api/items`, {
      headers: authHeaders,
    }).then((response) => response.json());
    const sample = (existing.items || existing.data || [])[0];
    assert.ok(sample, 'the demo seed should leave at least one item');

    // Create: the insert's placeholder list has to match its column list, which
    // is the failure this test exists to catch.
    const created = await fetch(`${baseUrl}/api/items`, {
      method: 'POST',
      headers: authHeaders,
      body: JSON.stringify({
        name: 'Bracket blank 60x40',
        displayName: 'Bracket blank 60x40',
        groupId: sample.groupId,
        unitId: sample.unitId,
        blankWidthMm: 60,
        blankHeightMm: 40,
      }),
    }).then((response) => response.json());
    assert.equal(created.success !== false, true, JSON.stringify(created));
    const item = created.item || created.data;
    assert.ok(item?.id, JSON.stringify(created));
    assert.equal(item.blankWidthMm, 60);
    assert.equal(item.blankHeightMm, 40);

    // Read back from the list, not just the create response.
    const listed = await fetch(`${baseUrl}/api/items`, {
      headers: authHeaders,
    }).then((response) => response.json());
    const fetched = (listed.items || listed.data || []).find(
      (row) => row.id === item.id
    );
    assert.equal(fetched.blankWidthMm, 60);
    assert.equal(fetched.blankHeightMm, 40);

    // Update carrying the size through. The item module takes a PATCH here.
    const updated = await fetch(`${baseUrl}/api/items/${item.id}`, {
      method: 'PATCH',
      headers: authHeaders,
      body: JSON.stringify({
        name: item.name,
        displayName: item.displayName,
        groupId: item.groupId,
        unitId: item.unitId,
        blankWidthMm: 65,
        blankHeightMm: 40,
      }),
    }).then((response) => response.json());
    const afterUpdate = updated.item || updated.data;
    assert.ok(afterUpdate, `update returned: ${JSON.stringify(updated)}`);
    assert.equal(afterUpdate.blankWidthMm, 65);
    assert.equal(afterUpdate.blankHeightMm, 40);

    // An update that says nothing about the blank must not wipe it — the
    // editor sends whole objects, but a caller that does not know about the
    // size should leave it alone rather than zero it.
    const untouched = await fetch(`${baseUrl}/api/items/${item.id}`, {
      method: 'PATCH',
      headers: authHeaders,
      body: JSON.stringify({
        name: item.name,
        displayName: 'Bracket blank 60x40 rev B',
        groupId: item.groupId,
        unitId: item.unitId,
      }),
    }).then((response) => response.json());
    const kept = untouched.item || untouched.data;
    assert.ok(kept, `update returned: ${JSON.stringify(untouched)}`);
    assert.equal(kept.blankWidthMm, 65, 'the blank survived an unrelated edit');
    assert.equal(kept.blankHeightMm, 40);

    // An item created without a size reads as unmeasured, not as null.
    const unmeasured = await fetch(`${baseUrl}/api/items`, {
      method: 'POST',
      headers: authHeaders,
      body: JSON.stringify({
        name: 'Raw coil stock',
        displayName: 'Raw coil stock',
        groupId: sample.groupId,
        unitId: sample.unitId,
      }),
    }).then((response) => response.json());
    const plain = unmeasured.item || unmeasured.data;
    assert.equal(plain.blankWidthMm, 0);
    assert.equal(plain.blankHeightMm, 0);
  } finally {
    await closeServer(server);
  }
});
