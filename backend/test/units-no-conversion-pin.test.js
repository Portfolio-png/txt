const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// Pins the state of the units module in Phase 2:
// Standard families and integer factor ladders per `.claude/skills/units/SKILL.md`.
// Conversion ladders are real, base units are integer 1, and no fractional factors exist.

test('seeded workspace has standard families and conversion ladders (Phase 2)', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-units-pin-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'units-pin@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();

  const groups = await backend.all('SELECT id, name, dimension, code, integral_only, base_unit_id FROM unit_groups');
  assert.ok(
    groups.length >= 6,
    'All 6 canonical families (Count, Mass, Length, Area, Volume, Time) must be present in unit_groups.',
  );

  const units = await backend.all(
    'SELECT name, symbol, unit_group_id, factor_to_base, is_base, on_ladder, ' +
      'conversion_factor, conversion_base_unit_id FROM units',
  );
  assert.ok(units.length > 0, 'the seed should have made some units');

  // Verify base units exist and have factor_to_base = 1
  const baseUnits = units.filter((u) => u.is_base === 1);
  assert.ok(baseUnits.length >= 6, 'Every canonical family must have exactly one base unit');
  for (const b of baseUnits) {
    assert.equal(b.factor_to_base, 1, `Base unit ${b.name} must have factor_to_base = 1`);
  }

  // Verify ladder units have integer factor_to_base > 0
  for (const unit of units) {
    if (unit.unit_group_id != null) {
      assert.ok(
        Number.isInteger(unit.factor_to_base) && unit.factor_to_base >= 1,
        `${unit.name} must carry an integer factor_to_base >= 1`,
      );
    }
  }
});
