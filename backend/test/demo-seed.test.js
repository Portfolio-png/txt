const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

test('demo dataset is rich enough for app walkthroughs', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-demo-seed-'));
  const dbPath = path.join(tempDir, 'paper.db');
  process.env.DB_PATH = dbPath;

  const backend = require('../server.js');

  try {
    await backend.resetAndSeedDemoData();

    const units = await backend.getUnitsWithUsage();
    const groups = await backend.getGroupsWithUsage();
    const clients = await backend.getClientsWithUsage();
    const items = await backend.getItemsWithUsage();
    const orders = await backend.getOrders();
    const materials = await backend.all('SELECT * FROM materials ORDER BY id ASC');
    const templates = await backend.all('SELECT * FROM pipeline_templates');
    const runs = await backend.all('SELECT * FROM pipeline_runs');
    const barcodeInputs = await backend.all('SELECT * FROM run_barcode_inputs');

    assert.ok(units.length >= 8, 'expected a broad unit catalogue');
    assert.ok(units.some((unit) => unit.is_archived), 'expected archived units');
    assert.ok(groups.length >= 10, 'expected nested group hierarchy');
    assert.ok(groups.some((group) => group.parent_group_id != null), 'expected child groups');
    assert.ok(clients.length >= 6, 'expected multiple clients');
    assert.ok(clients.some((client) => client.is_archived), 'expected archived clients');
    assert.ok(items.length >= 5, 'expected active and archived items');
    assert.ok(items.some((item) => item.is_archived), 'expected archived items');
    assert.ok(orders.length >= 10, 'expected enough orders for all status states');
    assert.ok(materials.length >= 16, 'expected parent and child material records');
    assert.ok(
      materials.some((material) => material.linked_group_id != null),
      'expected materials linked to groups',
    );
    assert.ok(
      materials.some((material) => material.linked_item_id != null),
      'expected materials linked to items',
    );
    assert.ok(
      materials.some((material) => Number(material.scan_count || 0) > 0),
      'expected scan activity in inventory',
    );
    assert.equal(templates.length, 3, 'expected three pipeline templates');
    assert.ok(runs.length >= 3, 'expected seeded production runs');
    assert.ok(barcodeInputs.length >= 3, 'expected scanned barcode inputs in runs');
  } finally {
    await backend.closeDb();
  }
});
