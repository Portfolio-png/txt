const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// The Master Data routes over HTTP: the (variant, pipeline) pair is the key, so
// the same variant on two pipelines must answer with two different baselines,
// and a pair with nothing behind it must say so rather than inventing a match.

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

test('Master Data routes key on the (variant, pipeline) pair', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-master-data-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'md-owner@paper.local';
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

    const itemsResponse = await fetch(`${baseUrl}/api/items`, {
      headers: authHeaders,
    });
    const itemsPayload = await itemsResponse.json();
    const item = (itemsPayload.items || itemsPayload.data || [])[0];
    assert.ok(item, 'the demo seed should leave at least one item');

    // Nothing recorded yet, so the answer is "new data", not a silent baseline.
    const fresh = await fetch(
      `${baseUrl}/api/items/${item.id}/master-data/resolve?pipelineId=pl-alpha`,
      { headers: authHeaders }
    ).then((response) => response.json());
    assert.equal(fresh.success, true);
    assert.equal(fresh.matched, false);
    assert.equal(fresh.source, 'new');

    // Two pipelines, two records, kept apart.
    for (const [pipelineId, inputKg] of [
      ['pl-alpha', 120],
      ['pl-beta', 300],
    ]) {
      const saved = await fetch(
        `${baseUrl}/api/items/${item.id}/master-data/${pipelineId}`,
        {
          method: 'PUT',
          headers: authHeaders,
          body: JSON.stringify({
            baseline: { mode: 'whole', inputKg, outputKg: inputKg * 0.9 },
          }),
        }
      ).then((response) => response.json());
      assert.equal(saved.success, true, JSON.stringify(saved));
      assert.equal(saved.record.pipelineId, pipelineId);
    }

    const onAlpha = await fetch(
      `${baseUrl}/api/items/${item.id}/master-data/resolve?pipelineId=pl-alpha`,
      { headers: authHeaders }
    ).then((response) => response.json());
    assert.equal(onAlpha.source, 'pair');
    assert.equal(onAlpha.baseline.inputKg, 120);

    const onBeta = await fetch(
      `${baseUrl}/api/items/${item.id}/master-data/resolve?pipelineId=pl-beta`,
      { headers: authHeaders }
    ).then((response) => response.json());
    assert.equal(onBeta.source, 'pair');
    assert.equal(onBeta.baseline.inputKg, 300);

    const records = await fetch(
      `${baseUrl}/api/items/${item.id}/master-data`,
      { headers: authHeaders }
    ).then((response) => response.json());
    assert.equal(records.records.length, 2);

    // The insight view: one pipeline, every variant on it.
    const roster = await fetch(
      `${baseUrl}/api/pipelines/pl-alpha/master-data`,
      { headers: authHeaders }
    ).then((response) => response.json());
    assert.equal(roster.success, true);
    assert.equal(roster.count, 1);
    assert.equal(roster.measuredCount, 1);
    assert.equal(roster.entries[0].itemId, item.id);
    assert.equal(roster.entries[0].yieldPercent, 90);

    const removed = await fetch(
      `${baseUrl}/api/items/${item.id}/master-data/pl-alpha`,
      { method: 'DELETE', headers: authHeaders }
    ).then((response) => response.json());
    assert.equal(removed.success, true);

    const afterDelete = await fetch(
      `${baseUrl}/api/items/${item.id}/master-data/resolve?pipelineId=pl-alpha`,
      { headers: authHeaders }
    ).then((response) => response.json());
    assert.equal(afterDelete.matched, false);

    // adopt=1 commits the answer, so the next lookup is an exact hit.
    const adopted = await fetch(
      `${baseUrl}/api/items/${item.id}/master-data/resolve?pipelineId=pl-alpha&adopt=1`,
      { headers: authHeaders }
    ).then((response) => response.json());
    assert.equal(adopted.persisted, true);
    const afterAdopt = await fetch(
      `${baseUrl}/api/items/${item.id}/master-data/resolve?pipelineId=pl-alpha`,
      { headers: authHeaders }
    ).then((response) => response.json());
    assert.equal(afterAdopt.source, 'pair');
    assert.equal(afterAdopt.origin, 'new', 'the row remembers it was never measured');

    const missing = await fetch(
      `${baseUrl}/api/items/99999999/master-data/resolve?pipelineId=pl-alpha`,
      { headers: authHeaders }
    );
    assert.equal(missing.status, 404);
  } finally {
    await closeServer(server);
  }
});
