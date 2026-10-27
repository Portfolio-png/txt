const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// The unit families are the units contract, not demo data. A database booted
// without the demo seed used to get migration 051's six family rows with no
// unit linked to any of them, so /api/units/families read back empty and no
// screen could offer a dozen or a gross.

test('a plain boot links the families to their ladders, once', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-units-boot-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'units-boot@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'UnitsBoot1234';
  delete process.env.PAPER_SEED_DEMO_DATA_ON_BOOT;

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');

  const ladderOf = async (code) => {
    const family = await backend.get('SELECT id FROM unit_groups WHERE code = ?', [code]);
    assert.ok(family, `the ${code} family exists`);
    return backend.all(
      'SELECT symbol, factor_to_base FROM units WHERE unit_group_id = ? ORDER BY factor_to_base',
      [family.id],
    );
  };

  // initDb runs every migration file itself (the kernel runner).
  await backend.initDb();
  const count = await ladderOf('count');
  assert.deepEqual(
    count.map((unit) => [unit.symbol, unit.factor_to_base]),
    [['Pc', 1], ['doz', 12], ['gro', 144]],
  );
  assert.ok((await ladderOf('mass')).some((unit) => unit.symbol === 'kg'));

  // Every boot runs it; the second must not add a second dozen.
  await backend.initDb();
  assert.equal((await ladderOf('count')).length, 3);
});
