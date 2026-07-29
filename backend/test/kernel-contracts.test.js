const assert = require('node:assert/strict');
const test = require('node:test');

const { checkPayload } = require('../kernel/contracts');
const { itemWrite, groupWrite } = require('../modules/items/contract');

test('item contract accepts a valid payload without problems', () => {
  const problems = checkPayload(itemWrite, {
    name: 'Binding Wire',
    alias: 'BW',
    quantity: 0,
    groupId: 3,
    unitId: '7', // numeric strings are representation-tolerated
    unitConversions: [{ unitId: 9, factorToPrimary: 12.5 }],
    namingFormat: [],
    variationTree: [
      {
        kind: 'property',
        name: 'Gauge',
        inputType: 'Gauge',
        children: [{ kind: 'value', name: '21G', id: 4012, children: [] }],
      },
    ],
    availableForPurchase: true,
  });
  assert.deepEqual(problems, []);
});

test('item contract flags structural impossibilities', () => {
  const problems = checkPayload(itemWrite, {
    name: '   ',
    unitId: 'not-a-number',
    variationTree: [
      {
        kind: 'property',
        name: 'Gauge',
        children: [{ kind: 'value', name: '21', id: -7 }],
      },
      { kind: 'texture', name: 'Rough' },
    ],
    unitConversions: [{ unitId: 4, factorToPrimary: 0 }],
  });
  const codesByPath = Object.fromEntries(problems.map((p) => [p.path, p.code]));
  assert.equal(codesByPath['item.name'], 'empty');
  assert.equal(codesByPath['item.groupId'], 'missing');
  assert.equal(codesByPath['item.unitId'], 'not-a-number');
  // The negative synthetic node id — the exact bug class from the challan
  // "invalid variation leaf" failures — must be flagged.
  assert.equal(codesByPath['item.variationTree[0].children[0].id'], 'below-min');
  assert.equal(codesByPath['item.variationTree[1].kind'], 'not-in-enum');
  assert.equal(codesByPath['item.unitConversions[0].factorToPrimary'], 'not-above');
});

test('group contract accepts valid payloads and flags missing name', () => {
  assert.deepEqual(
    checkPayload(groupWrite, {
      name: 'Raw material',
      unitId: 2,
      groupStructure: 'hierarchical',
    }),
    [],
  );
  const problems = checkPayload(groupWrite, { unitId: 2, parentGroupId: -1 });
  const codes = Object.fromEntries(problems.map((p) => [p.path, p.code]));
  assert.equal(codes['group.name'], 'missing');
  assert.equal(codes['group.parentGroupId'], 'below-min');
});

test('null on optional fields is tolerated; null on required is not', () => {
  const tolerated = checkPayload(itemWrite, {
    name: 'Widget',
    groupId: 1,
    unitId: 1,
    baseItemId: null,
    photoUrl: null,
    defaultPipelineId: null,
  });
  assert.deepEqual(tolerated, []);
  const flagged = checkPayload(itemWrite, { name: null, groupId: 1, unitId: 1 });
  assert.equal(flagged[0].code, 'null');
  assert.equal(flagged[0].path, 'item.name');
});
