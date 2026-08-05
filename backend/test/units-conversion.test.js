const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// Units master & conversion: the convert-batch endpoint accepts qualified
// values ("22G") and unit-id pairs, returning one result per requested
// conversion without failing the whole batch on a bad entry.

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

test('units convert-batch answers per-conversion results', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-units-conv-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'units-owner@paper.local';
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
        email: 'units-owner@paper.local',
        password: 'OwnerPass1234',
      }),
    });
    const { token } = await loginResponse.json();
    assert.ok(token, 'expected a login token');

    const response = await fetch(`${baseUrl}/api/units/convert-batch`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        conversions: [{ value: '22G', toUnitId: 2 }],
      }),
    });
    assert.equal(response.status, 200);
    const payload = await response.json();
    assert.equal(payload.success, true);
    assert.ok(Array.isArray(payload.results), 'expected per-conversion results');
    assert.equal(payload.results.length, 1);
    // Each entry reports its own success/error; a bad entry must not 500 the
    // batch. (Whether "22G" resolves depends on seeded gauge points.)
    assert.ok('success' in payload.results[0]);
  } finally {
    await closeServer(server);
    await backend.closeDb?.();
  }
});
