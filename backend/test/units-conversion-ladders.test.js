const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

const {
  UnitParseError,
  parseQuantity,
  formatQuantity,
  convertQuantity,
  STANDARD_FAMILIES,
} = require('../modules/units/service');

test('Units Contract: parseQuantity follows exact string/integer arithmetic without floats', () => {
  const kg = { name: 'Kilogram', symbol: 'kg', factor_to_base: 1000000 };
  const g = { name: 'Gram', symbol: 'g', factor_to_base: 1000 };
  const dozen = { name: 'Dozen', symbol: 'doz', factor_to_base: 12, integralOnly: true };
  const piece = { name: 'Piece', symbol: 'Pc', factor_to_base: 1, integralOnly: true };

  // SKILL.md §9 vectors
  assert.equal(parseQuantity('1.25', kg), 1250000);
  assert.equal(parseQuantity('0.1', g), 100);
  assert.equal(parseQuantity('1.5', dozen), 18);
  assert.equal(parseQuantity('5', piece), 5);
  assert.equal(parseQuantity('-2.5', kg), -2500000);

  // Invariant I6: Never silently round input. 1.1 dozen is 13.2 pieces, not integer -> throws
  assert.throws(
    () => parseQuantity('1.1', dozen),
    (err) => err instanceof UnitParseError,
  );

  // Non-number throws
  assert.throws(
    () => parseQuantity('abc', kg),
    (err) => err instanceof UnitParseError,
  );
});

test('Units Contract: formatQuantity auto-promotion matches SKILL.md §5 exact ladder examples', () => {
  const massFamily = STANDARD_FAMILIES.find((f) => f.code === 'mass');
  assert.ok(massFamily);

  // Reconstruct ladder with factor_to_base
  const ladder = [
    { ...massFamily.base, factor_to_base: massFamily.base.factorToBase },
    ...massFamily.ladder.map((r) => ({ ...r, factor_to_base: r.factorToBase })),
  ];
  const familyWithLadder = { ...massFamily, ladder };

  // §5 examples:
  // 999,000 mg -> "999 g"
  assert.equal(formatQuantity(999000, familyWithLadder, { mode: 'auto' }), '999 g');
  // 1,000,000 mg -> "1 kg"
  assert.equal(formatQuantity(1000000, familyWithLadder, { mode: 'auto' }), '1 kg');
  // 1,250,000 mg -> "1.25 kg"
  assert.equal(formatQuantity(1250000, familyWithLadder, { mode: 'auto' }), '1.25 kg');
  // 150,000,000 mg -> "1.5 qtl"
  assert.equal(formatQuantity(150000000, familyWithLadder, { mode: 'auto' }), '1.5 qtl');
  // 2,000,000,000 mg -> "2 t"
  assert.equal(formatQuantity(2000000000, familyWithLadder, { mode: 'auto' }), '2 t');

  // Pinned mode
  const kg = ladder.find((u) => u.symbol === 'kg');
  const g = ladder.find((u) => u.symbol === 'g');
  assert.equal(formatQuantity(1250000, kg, { mode: 'pinned', pinnedUnit: kg }), '1.25 kg');
  assert.equal(formatQuantity(1250000, g, { mode: 'pinned', pinnedUnit: g }), '1250 g');
});

test('Units Contract: Cross-family conversion throws (Invariant I4)', () => {
  const piece = { unit_group_id: 1, symbol: 'Pc' };
  const kg = { unit_group_id: 2, symbol: 'kg' };

  assert.throws(
    () => convertQuantity(100, piece, kg),
    /Cannot convert across different unit families/,
  );
});

test('Units Contract: Seeded workspace contains canonical families and ladders', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-units-ladders-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'units-ladder@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();

  const groups = await backend.all(
    'SELECT id, name, dimension, code, integral_only, base_unit_id FROM unit_groups ORDER BY id ASC',
  );
  assert.ok(groups.length >= 6, 'All 6 canonical families must be present in unit_groups');

  const countGroup = groups.find((g) => g.code === 'count');
  const massGroup = groups.find((g) => g.code === 'mass');
  const lengthGroup = groups.find((g) => g.code === 'length');

  assert.ok(countGroup && countGroup.integral_only === 1);
  assert.ok(massGroup && massGroup.integral_only === 0);
  assert.ok(lengthGroup && lengthGroup.integral_only === 0);

  assert.ok(countGroup.base_unit_id, 'Count group must point to a base_unit_id');
  assert.ok(massGroup.base_unit_id, 'Mass group must point to a base_unit_id');
  assert.ok(lengthGroup.base_unit_id, 'Length group must point to a base_unit_id');

  // Check base units
  const countBase = await backend.get('SELECT * FROM units WHERE id = ?', [countGroup.base_unit_id]);
  assert.equal(countBase.is_base, 1);
  assert.equal(countBase.factor_to_base, 1);

  const massBase = await backend.get('SELECT * FROM units WHERE id = ?', [massGroup.base_unit_id]);
  assert.equal(massBase.is_base, 1);
  assert.equal(massBase.factor_to_base, 1);
  assert.equal(massBase.symbol, 'mg');

  // Check ladder units
  const kg = await backend.get(
    'SELECT * FROM units WHERE unit_group_id = ? AND symbol = "kg"',
    [massGroup.id],
  );
  assert.ok(kg, 'Kilogram must be in Mass group');
  assert.equal(kg.factor_to_base, 1000000);
  assert.equal(kg.is_base, 0);

  const g = await backend.get(
    'SELECT * FROM units WHERE unit_group_id = ? AND symbol = "g"',
    [massGroup.id],
  );
  assert.ok(g, 'Gram must be in Mass group');
  assert.equal(g.factor_to_base, 1000);

  const mm = await backend.get(
    'SELECT * FROM units WHERE unit_group_id = ? AND symbol = "mm"',
    [lengthGroup.id],
  );
  assert.ok(mm, 'Millimeter must be in Length group');
  assert.equal(mm.factor_to_base, 1000);
});
