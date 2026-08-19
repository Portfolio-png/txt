const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const sqlite3 = require('sqlite3');

const { splitSqlStatements } = require('../modules/kernel/migration-runner');

const {
  createMasterData,
  materialTypeOf,
  summarise,
  ORIGINS,
} = require('../modules/items/master-data');

// Master Data is keyed by (variant, pipeline), and the four resolution steps
// are the whole feature: exact pair, then the variant's own record, then the
// pipeline's, and only then is new data created. These cover each step plus the
// adoption that collapses steps 2–4 onto the pair.

function connect() {
  const db = new sqlite3.Database(':memory:');
  const run = (sql, params = []) =>
    new Promise((resolve, reject) => {
      db.run(sql, params, function onRun(error) {
        if (error) reject(error);
        else resolve(this);
      });
    });
  const get = (sql, params = []) =>
    new Promise((resolve, reject) => {
      db.get(sql, params, (error, row) => (error ? reject(error) : resolve(row)));
    });
  const all = (sql, params = []) =>
    new Promise((resolve, reject) => {
      db.all(sql, params, (error, rows) => (error ? reject(error) : resolve(rows)));
    });
  return { db, run, get, all };
}

async function schema({ run }) {
  await run(`
    CREATE TABLE items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      display_name TEXT NOT NULL,
      base_item_id INTEGER,
      unit_id INTEGER DEFAULT 1,
      is_archived INTEGER DEFAULT 0,
      default_pipeline_id TEXT,
      pen_paper_baseline_json TEXT
    )
  `);
  await run(`
    CREATE TABLE pipeline_templates (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      pen_paper_baseline_json TEXT DEFAULT '{}'
    )
  `);
  await applyMigration({ run });
}

/// Applied through the runner's own splitter, so the test exercises the same
/// path production does rather than a look-alike.
async function applyMigration({ run }) {
  const migration = readFileSync(
    path.join(__dirname, '..', 'migrations', '032-item-pipeline-baselines.sql'),
    'utf8'
  );
  for (const statement of splitSqlStatements(migration)) {
    await run(statement);
  }
}

const MEASURED = { mode: 'whole', inputKg: 100, outputKg: 90, inputQty: 40, outputQty: 38 };
const FROM_PIPELINE = { mode: 'whole', inputKg: 200, outputKg: 170, inputQty: 10, outputQty: 9 };
const FROM_ITEM = { mode: 'whole', inputKg: 50, outputKg: 47, inputQty: 20, outputQty: 19 };

async function fixture() {
  const ctx = connect();
  await schema(ctx);
  await ctx.run(
    "INSERT INTO pipeline_templates (id, name, pen_paper_baseline_json) VALUES ('pl-cut', 'Cut → Punch', '{}')"
  );
  await ctx.run(
    "INSERT INTO pipeline_templates (id, name, pen_paper_baseline_json) VALUES ('pl-roll', 'Roll → Anneal', '{}')"
  );
  await ctx.run(
    `INSERT INTO items (name, display_name, base_item_id, default_pipeline_id)
     VALUES ('Alloy - 16A - MS Sheet', 'Alloy - 16A - MS Sheet', 1, 'pl-cut')`
  );
  return { ...ctx, masterData: createMasterData(ctx) };
}

test('step 1 — the exact (variant, pipeline) pair is a match', async () => {
  const { masterData } = await fixture();
  await masterData.writePair({
    itemId: 1,
    pipelineId: 'pl-cut',
    baseline: MEASURED,
    origin: ORIGINS.manual,
  });

  const resolution = await masterData.resolve({ itemId: 1, pipelineId: 'pl-cut' });
  assert.equal(resolution.matched, true);
  assert.equal(resolution.source, 'pair');
  assert.equal(resolution.origin, ORIGINS.manual);
  assert.equal(resolution.baseline.inputKg, 100);
});

test('step 2 — the variant\'s own record matches when the pair has none', async () => {
  const { run, masterData } = await fixture();
  await run('UPDATE items SET pen_paper_baseline_json = ? WHERE id = 1', [
    JSON.stringify(FROM_ITEM),
  ]);

  const resolution = await masterData.resolve({ itemId: 1, pipelineId: 'pl-cut' });
  assert.equal(resolution.matched, true);
  assert.equal(resolution.source, 'item');
  assert.equal(resolution.baseline.inputKg, 50);
  // Not adopted, so nothing was written.
  assert.equal(resolution.persisted, false);
  assert.equal(await masterData.readPair(1, 'pl-cut'), undefined);
});

test('step 3 — the pipeline that makes the item as output matches next', async () => {
  const { run, masterData } = await fixture();
  await run('UPDATE pipeline_templates SET pen_paper_baseline_json = ? WHERE id = ?', [
    JSON.stringify(FROM_PIPELINE),
    'pl-cut',
  ]);

  const resolution = await masterData.resolve({ itemId: 1, pipelineId: 'pl-cut' });
  assert.equal(resolution.matched, true);
  assert.equal(resolution.source, 'pipeline');
  assert.equal(resolution.baseline.inputKg, 200);
});

test('the variant beats the pipeline when both have a record', async () => {
  const { run, masterData } = await fixture();
  await run('UPDATE items SET pen_paper_baseline_json = ? WHERE id = 1', [
    JSON.stringify(FROM_ITEM),
  ]);
  await run('UPDATE pipeline_templates SET pen_paper_baseline_json = ? WHERE id = ?', [
    JSON.stringify(FROM_PIPELINE),
    'pl-cut',
  ]);

  const resolution = await masterData.resolve({ itemId: 1, pipelineId: 'pl-cut' });
  assert.equal(resolution.source, 'item');
});

test('step 4 — nothing matches, so new data is created', async () => {
  const { masterData } = await fixture();
  const resolution = await masterData.resolve({ itemId: 1, pipelineId: 'pl-cut' });

  assert.equal(resolution.matched, false);
  assert.equal(resolution.source, 'new');
  assert.equal(resolution.baseline.inputKg, 0);
  // The material type is read off the variant's own name.
  assert.equal(resolution.baseline.materialType, 'sheet');
});

test('adopting collapses an inherited match onto the pair, so the next hit is exact', async () => {
  const { run, masterData } = await fixture();
  await run('UPDATE pipeline_templates SET pen_paper_baseline_json = ? WHERE id = ?', [
    JSON.stringify(FROM_PIPELINE),
    'pl-cut',
  ]);

  const first = await masterData.resolve({ itemId: 1, pipelineId: 'pl-cut', adopt: true });
  assert.equal(first.source, 'pipeline');
  assert.equal(first.persisted, true);

  const second = await masterData.resolve({ itemId: 1, pipelineId: 'pl-cut' });
  assert.equal(second.source, 'pair');
  assert.equal(second.origin, ORIGINS.pipeline, 'the row remembers it was inherited');
  assert.equal(second.baseline.inputKg, 200);
});

test('the same variant on two pipelines keeps two separate records', async () => {
  const { masterData } = await fixture();
  await masterData.writePair({
    itemId: 1,
    pipelineId: 'pl-cut',
    baseline: MEASURED,
    origin: ORIGINS.manual,
  });
  await masterData.writePair({
    itemId: 1,
    pipelineId: 'pl-roll',
    baseline: FROM_PIPELINE,
    origin: ORIGINS.manual,
  });

  const onCut = await masterData.resolve({ itemId: 1, pipelineId: 'pl-cut' });
  const onRoll = await masterData.resolve({ itemId: 1, pipelineId: 'pl-roll' });
  assert.equal(onCut.baseline.inputKg, 100);
  assert.equal(onRoll.baseline.inputKg, 200);

  const records = await masterData.listForItem(1);
  assert.equal(records.length, 2);
  assert.deepEqual(
    records.map((record) => record.pipelineName).sort(),
    ['Cut → Punch', 'Roll → Anneal']
  );
});

test('re-writing a pair updates it rather than duplicating it', async () => {
  const { masterData } = await fixture();
  await masterData.writePair({ itemId: 1, pipelineId: 'pl-cut', baseline: MEASURED });
  await masterData.writePair({
    itemId: 1,
    pipelineId: 'pl-cut',
    baseline: { ...MEASURED, outputKg: 95 },
  });

  const records = await masterData.listForItem(1);
  assert.equal(records.length, 1);
  assert.equal(records[0].baseline.outputKg, 95);
});

test('no pipeline at all resolves against the variant alone', async () => {
  const { run, masterData } = await fixture();
  await run('UPDATE items SET default_pipeline_id = NULL, pen_paper_baseline_json = ? WHERE id = 1', [
    JSON.stringify(FROM_ITEM),
  ]);

  const resolution = await masterData.resolve({ itemId: 1 });
  assert.equal(resolution.pipelineId, '');
  assert.equal(resolution.matched, true);
  assert.equal(resolution.source, 'item');
});

test('an omitted pipeline falls back to the item\'s default', async () => {
  const { masterData } = await fixture();
  await masterData.writePair({ itemId: 1, pipelineId: 'pl-cut', baseline: MEASURED });

  const resolution = await masterData.resolve({ itemId: 1 });
  assert.equal(resolution.pipelineId, 'pl-cut');
  assert.equal(resolution.source, 'pair');
});

test('an empty or {} baseline is not a record', async () => {
  const { run, masterData } = await fixture();
  for (const stored of ['', '{}', 'null', '   ']) {
    await run('UPDATE items SET pen_paper_baseline_json = ? WHERE id = 1', [stored]);
    const resolution = await masterData.resolve({ itemId: 1, pipelineId: 'pl-cut' });
    assert.equal(resolution.matched, false, `"${stored}" must not count as data`);
  }
});

test('the pipeline roster reports each variant and how it got its baseline', async () => {
  const { run, masterData } = await fixture();
  await run(
    `INSERT INTO items (name, display_name, base_item_id, default_pipeline_id)
     VALUES ('Alloy - 18A - MS Sheet', 'Alloy - 18A - MS Sheet', 1, 'pl-cut')`
  );
  await run(
    `INSERT INTO items (name, display_name, base_item_id, default_pipeline_id)
     VALUES ('Alloy - 20A - MS Sheet', 'Alloy - 20A - MS Sheet', 1, 'pl-cut')`
  );
  await masterData.writePair({
    itemId: 1,
    pipelineId: 'pl-cut',
    baseline: MEASURED,
    origin: ORIGINS.manual,
  });
  await masterData.writePair({
    itemId: 2,
    pipelineId: 'pl-cut',
    baseline: FROM_PIPELINE,
    origin: ORIGINS.pipeline,
  });
  await masterData.writePair({
    itemId: 3,
    pipelineId: 'pl-cut',
    baseline: masterData.blankBaseline({ pipelineId: 'pl-cut' }),
    origin: ORIGINS.fresh,
  });

  const roster = await masterData.listForPipeline('pl-cut');
  assert.equal(roster.count, 3);
  assert.equal(roster.measuredCount, 1);
  assert.equal(roster.inheritedCount, 1);
  assert.equal(roster.blankCount, 1);
  assert.equal(roster.entries.every((entry) => entry.isVariant), true);
  const measured = roster.entries.find((entry) => entry.itemId === 1);
  assert.equal(measured.yieldPercent, 90);
});

test('an archived variant drops off the roster', async () => {
  const { run, masterData } = await fixture();
  await masterData.writePair({ itemId: 1, pipelineId: 'pl-cut', baseline: MEASURED });
  await run('UPDATE items SET is_archived = 1 WHERE id = 1');

  const roster = await masterData.listForPipeline('pl-cut');
  assert.equal(roster.count, 0);
});

test('deleting a pair sends resolution back to creating new data', async () => {
  const { masterData } = await fixture();
  await masterData.writePair({ itemId: 1, pipelineId: 'pl-cut', baseline: MEASURED });
  assert.equal(await masterData.deletePair(1, 'pl-cut'), true);
  assert.equal(await masterData.deletePair(1, 'pl-cut'), false);

  const resolution = await masterData.resolve({ itemId: 1, pipelineId: 'pl-cut' });
  assert.equal(resolution.matched, false);
});

test('a missing item is a 404, not a silent blank baseline', async () => {
  const { masterData } = await fixture();
  await assert.rejects(
    () => masterData.resolve({ itemId: 9999, pipelineId: 'pl-cut' }),
    (error) => error.status === 404
  );
});

test('stage-by-stage summarises across the whole pipeline, not one stage', () => {
  const totals = summarise({
    mode: 'stages',
    stageReconciliations: [
      { inputKg: 100, outputKg: 90, inputQty: 50, outputQty: 48 },
      { inputKg: 90, outputKg: 84, inputQty: 48, outputQty: 45 },
      { inputKg: 84, outputKg: 80, inputQty: 45, outputQty: 44 },
    ],
  });
  assert.equal(totals.inputKg, 100, 'input comes from the first stage');
  assert.equal(totals.outputKg, 80, 'output comes from the last');
  assert.equal(totals.inputQty, 50);
  assert.equal(totals.outputQty, 44);
  assert.equal(totals.yieldPercent, 80);
});

test('the material type is read off the variant name', () => {
  assert.equal(materialTypeOf({ display_name: 'Alloy - 16A - MS Sheet' }), 'sheet');
  assert.equal(materialTypeOf({ display_name: 'Brass Patti 24mm' }), 'patti');
  assert.equal(materialTypeOf({ name: 'Copper Coil', display_name: '' }), 'coil');
  assert.equal(materialTypeOf({ display_name: 'Widget' }), '');
});

test('the migration carries an existing item baseline onto its pipeline pair', async () => {
  const ctx = connect();
  // Seed BEFORE the migration so the backfill has something to move.
  await ctx.run(`
    CREATE TABLE items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      display_name TEXT NOT NULL,
      base_item_id INTEGER,
      unit_id INTEGER DEFAULT 1,
      is_archived INTEGER DEFAULT 0,
      default_pipeline_id TEXT,
      pen_paper_baseline_json TEXT
    )
  `);
  await ctx.run(`
    CREATE TABLE pipeline_templates (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      pen_paper_baseline_json TEXT DEFAULT '{}'
    )
  `);
  await ctx.run(
    "INSERT INTO pipeline_templates (id, name) VALUES ('pl-cut', 'Cut → Punch')"
  );
  await ctx.run(
    `INSERT INTO items (name, display_name, default_pipeline_id, pen_paper_baseline_json)
     VALUES ('Alloy Sheet', 'Alloy Sheet', 'pl-cut', ?)`,
    [JSON.stringify(MEASURED)]
  );
  // And one with no pipeline, which must stay on the item.
  await ctx.run(
    `INSERT INTO items (name, display_name, default_pipeline_id, pen_paper_baseline_json)
     VALUES ('Loose Coil', 'Loose Coil', NULL, ?)`,
    [JSON.stringify(FROM_ITEM)]
  );

  await applyMigration(ctx);

  const masterData = createMasterData(ctx);
  const moved = await masterData.resolve({ itemId: 1, pipelineId: 'pl-cut' });
  assert.equal(moved.source, 'pair');
  assert.equal(moved.baseline.inputKg, 100);

  const kept = await masterData.resolve({ itemId: 2 });
  assert.equal(kept.pipelineId, '');
  assert.equal(kept.source, 'item');
  assert.equal(kept.baseline.inputKg, 50);
});
