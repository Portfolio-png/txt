'use strict';

const assert = require('node:assert/strict');
const path = require('node:path');
const test = require('node:test');
const { makeTempDir } = require('./helpers/temp-dir');
const { identityValue, identityOfTree } = require('../modules/items/part-identity');

// Same group and name, another Alloy or Thickness: another part, with its own
// part number. The duplicate rule is name + alloy + thickness.

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

test('two Pattis with different alloys are two parts with their own numbers; the same alloy and thickness is refused', async () => {
  const { backend, save } = await boot();
  const ms = await save('Patti', tree('MS', '1.2'));
  const ss = await save('Patti', tree('SS', '1.5'));
  assert.notEqual(ms.id, ss.id);
  const rows = await backend.all('SELECT id, part_no, part_code FROM items WHERE id IN (?, ?) ORDER BY id', [ms.id, ss.id]);
  assert.notEqual(rows[0].part_no, rows[1].part_no, 'each its own part number');
  if (rows[0].part_code && rows[1].part_code) assert.notEqual(rows[0].part_code, rows[1].part_code);

  const thicker = await save('Patti', tree('MS', '2.0'));
  assert.ok(thicker.id, 'the same alloy at another thickness is another part too');

  const again = await refusal(save('patti ', tree('ms', '1.20')));
  assert.equal(again.statusCode, 409);
  assert.equal(again.code, 'item_name_duplicate');
  assert.match(again.message, /"patti" with Alloy ms, Thickness 1\.20 already exists/);
});

test('without alloy or thickness the name alone still decides, as before', async () => {
  const { save } = await boot();
  await save('Washer', []);
  const again = await refusal(save('Washer', []));
  assert.equal(again.statusCode, 409);
  assert.match(again.message, /"Washer" already exists in this group/);
  const withAlloy = await save('Washer', tree('Brass', null));
  assert.ok(withAlloy.id, 'one with an alloy is told apart from the one without');
});

test('changing a part onto a sibling\'s alloy and thickness is refused; its own save is not a duplicate of itself', async () => {
  const { save } = await boot();
  await save('Bracket', tree('MS', '1.2'));
  const ss = await save('Bracket', tree('SS', '1.2'));
  const resaved = await save('Bracket', tree('SS', '1.2'), { id: ss.id });
  assert.equal(resaved.id, ss.id, 'saving it unchanged is fine');
  const clash = await refusal(save('Bracket', tree('MS', '1.2'), { id: ss.id }));
  assert.equal(clash.statusCode, 409, 'it would become the MS 1.2 Bracket that already exists');
});

// Every property counts (user, 2026-11-23): all must match to be the same part.
test('any other property tells two parts apart too; all the same is refused; an empty one is the same as none', async () => {
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

  const again = await refusal(save('Clip', withMore('ms', '1.20', { grade: '2ND', hardness: 'soft' })));
  assert.equal(again.statusCode, 409);
  assert.match(again.message, /hardness soft/);
  const empty = await refusal(save('Clip', withMore('MS', '1.2', { Grade: '2nd', Hardness: null })));
  assert.equal(empty.statusCode, 409, 'a property left empty is the same as one not there');
});
