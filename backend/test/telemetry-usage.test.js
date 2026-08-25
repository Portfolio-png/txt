const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// The fleet snapshot used to say how *big* a deployment was — orders, items,
// users. That cannot answer the question that decides what to build next:
// which parts do people actually touch, and where are they working around the
// software rather than with it.
//
// Everything asserted here is derived from records the app already writes for
// its own audit trail. No new tracking, no per-click instrumentation, and
// aggregates only — which modules were touched and how often, never what was
// typed into them.

test('the snapshot reports how the software is used, not just how much', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-telemetry-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'tele@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();

  const snapshot = await backend.computeTelemetrySnapshot();

  // The size figures are still there — this adds to them rather than replacing.
  assert.ok(snapshot.metrics, 'the size metrics survive');
  assert.equal(typeof snapshot.metrics.items, 'number');

  const usage = snapshot.usage;
  assert.ok(usage, 'the snapshot carries usage');

  // Which modules are touched, by how many people, and when last. A module
  // missing from this list is one nobody is using.
  assert.ok(Array.isArray(usage.moduleActivity));
  for (const row of usage.moduleActivity) {
    assert.equal(typeof row.module, 'string');
    assert.equal(typeof row.actions, 'number');
    assert.equal(typeof row.people, 'number');
  }

  // Adoption: the parts that only pay off once they are filled in. Reported as
  // a pair — filled in, and total — because a bare count says nothing without
  // knowing what it is a count out of.
  for (const [filled, total] of [
    ['itemsWithVariations', 'itemsTotal'],
    ['runsWithStockAssigned', 'runsTotal'],
    ['deliveriesLinkedToOrder', 'deliveriesTotal'],
  ]) {
    assert.equal(typeof usage.adoption[filled], 'number', filled);
    assert.equal(typeof usage.adoption[total], 'number', total);
    assert.ok(
      usage.adoption[filled] <= usage.adoption[total],
      `${filled} cannot exceed ${total}`,
    );
  }

  // Workarounds: where the shape of the software and the shape of the work
  // disagree. Each is a question about the design, not a fault of the user.
  for (const key of [
    'materialsWithoutReceipt',
    'consumptionWithoutSource',
    'itemsUngrouped',
    'challansLeftDraft',
  ]) {
    assert.equal(typeof usage.workarounds[key], 'number', key);
    assert.ok(usage.workarounds[key] >= 0, key);
  }

  // Which build produced the reading — a fleet dashboard comparing two
  // deployments has to know whether it is comparing two versions.
  assert.ok('release' in snapshot);
  assert.ok('environment' in snapshot);
});

test('telemetry never throws, whatever the schema looks like', async () => {
  // A deployment must not misbehave because a metric could not be computed.
  // The usage block is wrapped for exactly this reason, so an older or partly
  // migrated database still produces a snapshot rather than an exception.
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-telemetry-drop-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'tele2@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();

  // Take a table the usage block reads out from under it.
  await backend.run('DROP TABLE IF EXISTS entity_activity_log');

  const snapshot = await backend.computeTelemetrySnapshot();
  assert.ok(snapshot, 'a snapshot is still produced');
  assert.ok(snapshot.metrics, 'and still carries the size metrics');
  assert.deepEqual(
    snapshot.usage.moduleActivity,
    [],
    'the part that could not be computed is empty, not missing or thrown',
  );
});
