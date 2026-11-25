'use strict';

const assert = require('node:assert/strict');
const path = require('node:path');
const test = require('node:test');
const { makeTempDir } = require('./helpers/temp-dir');
const { identityValue, identityOfTree } = require('../modules/items/part-identity');

// Same group and name, another Alloy or Thickness: another part, with its own
// part number. The SAME name and properties again used to be refused (409
// item_name_duplicate); since 2026-11-25 duplicates are allowed while the
// owner collects real data ("then we will restrict rules"), so those cases
// below now save — kept as they were, to become refusals again in one place.

const tree = (alloy, thickness) => [
  ...(alloy ? [{ kind: 'property', name: 'Alloy', children: [{ kind: 'value', name: alloy, children: [] }] }] : []),
  ...(thickness ? [{ kind: 'property', name: 'Thickness', children: [{ kind: 'value', name: thickness, children: [] }] }] : []),
];

test('identity values: "1.20" is "1.2", case and spacing do not matter, order of values does not', () => {
  assert.equal(identityValue('1.20'), '1.2');
  assert.equal(identityValue('10'), '10');
  assert.equal(identityValue('  Mild  Steel '), 'mild steel');
  assert.deepEqual(identityOfTree(tree('MS', '1.20')), { alloy: 'ms', thickness: '1.2' });
  assert.deepEqual(identityOfTree([]), { alloy: '', thickness: '' });
  const twoValues = (a, b) => [{ kind: 'property', name: 'Alloy', children: [{ kind: 'value', name: a }, { kind: 'value', name: b }] }];
  assert.deepEqual(identityOfTree(twoValues('SS', 'MS')), identityOfTree(twoValues('MS', 'SS')));
});

async function boot() {
  const tempDir = makeTempDir('paper-identity-');
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'identity@paper.test';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData('scenario_a');
  const group = await backend.get('SELECT id FROM groups WHERE is_archived = 0 ORDER BY id LIMIT 1');
  const unit = await backend.get('SELECT id FROM units WHERE is_archived = 0 ORDER BY id LIMIT 1');
  const save = (name, variationTree, extra = {}) => backend.saveItem({
    name, alias: '', displayName: name, groupId: group.id, unitId: unit.id, variationTree, ...extra,
  });
  return { backend, save };
}

async function refusal(promise) {
  try {
    await promise;
  } catch (error) {
    return error;
  }
  assert.fail('expected the save to be refused');
}

test('two Pattis with different alloys are two parts with their own numbers; the same alloy and thickness is allowed for now', async () => {
  const { backend, save } = await boot();
  const ms = await save('Patti', tree('MS', '1.2'));
  const ss = await save('Patti', tree('SS', '1.5'));
  assert.notEqual(ms.id, ss.id);
  const rows = await backend.all('SELECT id, part_no, part_code FROM items WHERE id IN (?, ?) ORDER BY id', [ms.id, ss.id]);
  assert.notEqual(rows[0].part_no, rows[1].part_no, 'each its own part number');
  if (rows[0].part_code && rows[1].part_code) assert.notEqual(rows[0].part_code, rows[1].part_code);

  const thicker = await save('Patti', tree('MS', '2.0'));
  assert.ok(thicker.id, 'the same alloy at another thickness is another part too');

  const again = await save('patti ', tree('ms', '1.20'));
  assert.ok(again.id && again.id !== ms.id, 'a duplicate saves, as its own part');
});

test('without alloy or thickness the same name saves again too, for now', async () => {
  const { save } = await boot();
  const first = await save('Washer', []);
  const again = await save('Washer', []);
  assert.notEqual(again.id, first.id);
  const withAlloy = await save('Washer', tree('Brass', null));
  assert.ok(withAlloy.id, 'one with an alloy is told apart from the one without');
});

test('changing a part onto a sibling\'s alloy and thickness is allowed for now; its own save is fine', async () => {
  const { save } = await boot();
  await save('Bracket', tree('MS', '1.2'));
  const ss = await save('Bracket', tree('SS', '1.2'));
  const resaved = await save('Bracket', tree('SS', '1.2'), { id: ss.id });
  assert.equal(resaved.id, ss.id, 'saving it unchanged is fine');
  const moved = await save('Bracket', tree('MS', '1.2'), { id: ss.id });
  assert.equal(moved.id, ss.id, 'it becomes a second MS 1.2 Bracket');
});

// Every property counts (user, 2026-11-23): all must match to be the same part.
test('any other property tells two parts apart too; all the same saves too, for now', async () => {
  const { save } = await boot();
  const withMore = (alloy, thickness, extra) => [
    ...tree(alloy, thickness),
    ...Object.entries(extra).map(([name, value]) => ({
      kind: 'property', name, children: value == null ? [] : [{ kind: 'value', name: value }],
    })),
  ];
  const soft = await save('Clip', withMore('MS', '1.2', { Grade: '2nd', Hardness: 'Soft' }));
  const hard = await save('Clip', withMore('MS', '1.2', { Grade: '2nd', Hardness: 'Hard' }));
  assert.notEqual(soft.id, hard.id, 'another hardness is another part');
  const none = await save('Clip', withMore('MS', '1.2', { Grade: '2nd' }));
  assert.ok(none.id, 'so is one with no hardness at all');

  const again = await save('Clip', withMore('ms', '1.20', { grade: '2ND', hardness: 'soft' }));
  assert.ok(again.id && again.id !== soft.id, 'all the same: saved as another part');
  const empty = await save('Clip', withMore('MS', '1.2', { Grade: '2nd', Hardness: null }));
  assert.ok(empty.id, 'a property left empty: saved too');
});

// Owner, 2026-11-25: Part No is the die generation a part was made from, not a
// key ("part number has nothing to do with uniqueness"). The shop sets it;
// two parts may share it; a part given one gets its code from it.
test('a Part No given is kept — shared by two Pattis of different alloys — and the code is built from it', async () => {
  const { backend, save } = await boot();
  const ms = await save('Patti', tree('MS', '1.2'), { partNo: 2 });
  const ss = await save('Patti', tree('SS', '1.2'), { partNo: 2 });
  const rows = await backend.all(
    'SELECT id, part_no, part_code FROM items WHERE id IN (?, ?) ORDER BY id',
    [ms.id, ss.id],
  );
  assert.deepEqual(rows.map((r) => r.part_no), [2, 2], 'the number given, on both');
  for (const row of rows) {
    assert.ok(row.part_code, 'a code, built from the number — not none');
    assert.match(row.part_code, /2/);
  }
  assert.notEqual(rows[0].part_code, rows[1].part_code, 'told apart by the alloy');
});
