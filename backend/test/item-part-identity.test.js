const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

const {
  buildPartCode,
  propertyCodeFor,
  valueCodeFor,
  initialsOf,
  groupLineage,
} = require('../modules/items/part-identity');

// A part is known on the floor by a number and a code — "the forty-eighth
// Dolly patti in Switch Action", written SADP48. This proves the columns
// exist, that the insert's placeholders line up with its columns, that an
// update which omits them does not wipe what was stamped, and that the code is
// unique within a group however the clash arrives.

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

async function boot(prefix, email) {
  const tempDir = mkdtempSync(path.join(tmpdir(), prefix));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = email;
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;
  const login = await fetch(`${baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: 'OwnerPass1234' }),
  }).then((r) => r.json());
  assert.ok(login.token, 'expected a login token');
  return {
    backend,
    server,
    baseUrl,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${login.token}`,
    },
  };
}

// --- the shared fixture -----------------------------------------------------
// The same table is asserted in packages/core_erp/test/part_code_test.dart.
// The two implementations are allowed to exist; drifting apart is not.
// A variant's code: the same trunk, the value codes, then the number.
// The same table is asserted in packages/core_erp/test/part_code_test.dart.
const VARIANT_FIXTURE = [
  // The two the factory sheet asks for.
  { group: 'Switch Action', set: 'Dolly', item: 'Patti', values: ['B', '22'], no: 48, code: 'SADPB2248' },
  { group: 'Switch Action', set: 'Dolly', item: 'Patti', values: ['MS', '22'], no: 48, code: 'SADPMS2248' },
  // Order is the caller's and is kept verbatim — gauge-then-alloy is a
  // different code, which is why the item's naming format decides it.
  { group: 'Switch Action', set: 'Dolly', item: 'Patti', values: ['22', 'B'], no: 48, code: 'SADP22B48' },
  // Blank and punctuation-only value codes drop out rather than leaving a gap.
  { group: 'Switch Action', set: 'Dolly', item: 'Patti', values: ['B', '', '  ', '-'], no: 48, code: 'SADPB48' },
  // No values at all is the plain part code, so a variant of nothing is not a
  // second name for the part.
  { group: 'Switch Action', set: 'Dolly', item: 'Patti', values: [], no: 48, code: 'SADP48' },
  // Lower case and spacing inside a typed code are normalised.
  { group: 'Ash Trays', set: '', item: 'Lid', values: ['ss 304'], no: 2, code: 'ATLSS3042' },
  // No letters anywhere is still '', never the bare number.
  { group: '', set: '', item: '', values: ['B'], no: 48, code: '' },
  // The 12-letter cap applies to the trunk only: clipping a value code would
  // make two variants collide.
  {
    group: 'Switch Action Assembly',
    set: 'Mounting Plate Bracket',
    item: 'Rear Cover Plate',
    values: ['BRASS', '22'],
    no: 9,
    code: 'SAAMPBRCPBRASS229',
  },
];

// How a value with no typed code reads.
const VALUE_CODE_FIXTURE = [
  { name: 'Brass', code: 'BRAS' },
  { name: 'MS', code: 'MS' },
  { name: 'Mild Steel', code: 'MS' },
  { name: '22', code: '22' },
  { name: 'Stainless Steel 304', code: 'SS304' },
  { name: 'Aluminium', code: 'ALUM' },
  { name: '', code: '' },
];

const CODE_FIXTURE = [
  { group: 'Switch Action', set: 'Dolly', item: 'Patti', no: 48, code: 'SADP48' },
  { group: 'Switch Action', set: '', item: 'Patti', no: 1, code: 'SAP1' },
  { group: 'Ash Trays', set: null, item: 'Lid', no: null, code: 'ATL' },
  { group: '', set: '', item: '2mm Washer', no: 3, code: 'W3' },
  { group: '', set: '', item: 'M8 Bolt', no: 3, code: 'MB3' },
  { group: '', set: '', item: 'L-Bracket', no: 7, code: 'LB7' },
  { group: '', set: '', item: '48', no: 48, code: '' },
  { group: '', set: '', item: '', no: 48, code: '' },
  { group: 'पट्टी', set: '', item: '', no: 2, code: '' },
  {
    group: 'Switch Action Assembly',
    set: 'Mounting Plate Bracket',
    item: 'Rear Cover Plate',
    no: 9,
    code: 'SAAMPBRCP9',
  },
];

test('buildPartCode follows one rule, shared with the client', () => {
  for (const row of CODE_FIXTURE) {
    assert.equal(
      buildPartCode({
        groupName: row.group,
        setName: row.set,
        itemName: row.item,
        partNo: row.no,
      }),
      row.code,
      `${row.group} / ${row.set} / ${row.item} / ${row.no}`,
    );
  }
  // null and '' are the same absence, and neither leaves a gap.
  assert.equal(
    buildPartCode({ groupName: null, setName: '', itemName: 'Lid', partNo: 2 }),
    buildPartCode({ groupName: '', setName: null, itemName: 'Lid', partNo: 2 }),
  );
  // The letter run is capped before the number, so a code stays sayable.
  const long = buildPartCode({
    groupName: 'A B C D E F G H I J K L M N',
    itemName: 'O P',
    partNo: 5,
  });
  assert.equal(long, 'ABCDEFGHIJKL5');
});

test('an item carries its part identity through create, read and update', async () => {
  const ctx = await boot('paper-part-identity-', 'part-owner@paper.local');
  try {
    const existing = await fetch(`${ctx.baseUrl}/api/items`, {
      headers: ctx.headers,
    }).then((r) => r.json());
    const sample = existing.items[0];
    assert.ok(sample, 'the demo seed should leave at least one item');

    const created = await fetch(`${ctx.baseUrl}/api/items`, {
      method: 'POST',
      headers: ctx.headers,
      body: JSON.stringify({
        name: 'Wizard Patti',
        displayName: 'Wizard Patti',
        groupId: sample.groupId,
        unitId: sample.unitId,
        partNo: 48,
        partCode: 'SADP48',
      }),
    });
    assert.equal(created.status, 201, await created.clone().text());
    const item = (await created.json()).item;
    assert.equal(item.partNo, 48);
    assert.equal(item.partCode, 'SADP48');

    // The list read carries it too, not just the create's own response.
    const listed = await fetch(`${ctx.baseUrl}/api/items`, {
      headers: ctx.headers,
    }).then((r) => r.json());
    const fromList = listed.items.find((row) => row.id === item.id);
    assert.equal(fromList.partCode, 'SADP48');

    // An update that says nothing about identity keeps what was stamped. This
    // is the failure mode that would otherwise arrive silently, through any
    // save that rebuilds the whole item.
    const updated = await fetch(`${ctx.baseUrl}/api/items/${item.id}`, {
      method: 'PATCH',
      headers: ctx.headers,
      body: JSON.stringify({
        name: 'Wizard Patti',
        displayName: 'Wizard Patti',
        groupId: sample.groupId,
        unitId: sample.unitId,
      }),
    });
    assert.equal(updated.status, 200, await updated.clone().text());
    assert.equal((await updated.json()).item.partCode, 'SADP48');

    // Lower case in, upper case stored — the index is case-insensitive by
    // normalisation rather than by collation.
    const lower = await fetch(`${ctx.baseUrl}/api/items`, {
      method: 'POST',
      headers: ctx.headers,
      body: JSON.stringify({
        name: 'Wizard Dabbi',
        displayName: 'Wizard Dabbi',
        groupId: sample.groupId,
        unitId: sample.unitId,
        partNo: 49,
        partCode: 'sadd49',
      }),
    });
    assert.equal((await lower.json()).item.partCode, 'SADD49');
  } finally {
    await closeServer(ctx.server);
    await ctx.backend.closeDb();
  }
});

test('identity is cleared only when the save speaks about it', async () => {
  const ctx = await boot('paper-part-clear-', 'part-clear@paper.local');
  try {
    const items = await fetch(`${ctx.baseUrl}/api/items`, {
      headers: ctx.headers,
    }).then((r) => r.json());
    const sample = items.items[0];

    const created = await fetch(`${ctx.baseUrl}/api/items`, {
      method: 'POST',
      headers: ctx.headers,
      body: JSON.stringify({
        name: 'Clearable Part',
        displayName: 'Clearable Part',
        groupId: sample.groupId,
        unitId: sample.unitId,
        partNo: 12,
        partCode: 'CLR12',
      }),
    }).then((r) => r.json());
    const id = created.item.id;

    const patch = (body) =>
      fetch(`${ctx.baseUrl}/api/items/${id}`, {
        method: 'PATCH',
        headers: ctx.headers,
        body: JSON.stringify({
          name: 'Clearable Part',
          displayName: 'Clearable Part',
          groupId: sample.groupId,
          unitId: sample.unitId,
          ...body,
        }),
      }).then(async (r) => ({ status: r.status, body: await r.json() }));

    // Saying nothing keeps what is stamped — the contract every other caller
    // relies on.
    const silent = await patch({});
    assert.equal(silent.body.item.partNo, 12);
    assert.equal(silent.body.item.partCode, 'CLR12');

    // Speaking about it with nothing in hand clears it. This is the whole
    // reason the editor sends both keys.
    const cleared = await patch({ partNo: null, partCode: '' });
    assert.equal(cleared.status, 200, JSON.stringify(cleared.body));
    assert.equal(cleared.body.item.partNo, null);
    assert.equal(cleared.body.item.partCode, '');
  } finally {
    await closeServer(ctx.server);
    await ctx.backend.closeDb();
  }
});

test('a refused part code costs the user nothing else in that save', async () => {
  const ctx = await boot('paper-part-atomic-', 'part-atomic@paper.local');
  try {
    const items = await fetch(`${ctx.baseUrl}/api/items`, {
      headers: ctx.headers,
    }).then((r) => r.json());
    const sample = items.items[0];

    const make = (name, partCode) =>
      fetch(`${ctx.baseUrl}/api/items`, {
        method: 'POST',
        headers: ctx.headers,
        body: JSON.stringify({
          name,
          displayName: name,
          groupId: sample.groupId,
          unitId: sample.unitId,
          partNo: 5,
          partCode,
        }),
      }).then((r) => r.json());

    await make('Holder Part', 'TAKEN5');
    const mine = await make('Mover Part', 'MINE5');

    // One save that changes the name AND walks into a taken code.
    const refused = await fetch(`${ctx.baseUrl}/api/items/${mine.item.id}`, {
      method: 'PATCH',
      headers: ctx.headers,
      body: JSON.stringify({
        name: 'Renamed Mover',
        displayName: 'Renamed Mover',
        groupId: sample.groupId,
        unitId: sample.unitId,
        partCode: 'TAKEN5',
      }),
    });
    assert.equal(refused.status, 409);
    const body = await refused.json();
    assert.match(body.error, /Holder Part/);

    // The row is untouched: the check runs before the transaction, and the
    // index backstop rolls back.
    const after = await fetch(`${ctx.baseUrl}/api/items/${mine.item.id}`, {
      headers: ctx.headers,
    }).then((r) => r.json());
    assert.equal(after.item.name, 'Mover Part', 'the rename did not land either');
    assert.equal(after.item.partCode, 'MINE5');
  } finally {
    await closeServer(ctx.server);
    await ctx.backend.closeDb();
  }
});

test('a part code is unique within its group, and says who holds it', async () => {
  const ctx = await boot('paper-part-unique-', 'part-unique@paper.local');
  try {
    const groups = await fetch(`${ctx.baseUrl}/api/groups`, {
      headers: ctx.headers,
    }).then((r) => r.json());
    const active = (groups.groups || groups).filter((g) => !g.isArchived);
    const units = await fetch(`${ctx.baseUrl}/api/units`, {
      headers: ctx.headers,
    }).then((r) => r.json());
    const unitId = (units.units || units).find((u) => !u.isArchived).id;

    const make = (name, groupId, partCode, partNo) =>
      fetch(`${ctx.baseUrl}/api/items`, {
        method: 'POST',
        headers: ctx.headers,
        body: JSON.stringify({
          name,
          displayName: name,
          groupId,
          unitId,
          partNo,
          partCode,
        }),
      });

    assert.equal((await make('First Part', active[0].id, 'DUP7', 7)).status, 201);

    const clash = await make('Second Part', active[0].id, 'DUP7', 8);
    assert.equal(clash.status, 409);
    const body = await clash.json();
    assert.match(body.error, /DUP7/);
    assert.match(
      body.error,
      /First Part/,
      'the refusal names the part that holds the code',
    );

    // Same code, different group: both are legitimate parts, because the
    // numbers restart per group and set.
    const other = await make('Third Part', active[1].id, 'DUP7', 7);
    assert.equal(other.status, 201, await other.clone().text());

    // Case does not sneak a duplicate past the index either.
    const cased = await make('Fourth Part', active[0].id, 'dup7', 9);
    assert.equal(cased.status, 409);
  } finally {
    await closeServer(ctx.server);
    await ctx.backend.closeDb();
  }
});

test('the next part identity restarts per NAME, and counts archived parts', async () => {
  // The number counts parts of this name in this group — "the forty-eighth
  // Dolly patti" counts Dolly pattis. It used to count the group's set
  // members, so 48 was the forty-eighth part of ANY name in that set and the
  // code said one thing while the number counted another.
  const ctx = await boot('paper-part-next-', 'part-next@paper.local');
  try {
    const items = await fetch(`${ctx.baseUrl}/api/items`, {
      headers: ctx.headers,
    }).then((r) => r.json());
    const sample = items.items[0];
    const groupId = sample.groupId;
    const unitId = sample.unitId;

    const ask = (query) =>
      fetch(`${ctx.baseUrl}/api/items/next-part-identity?${query}`, {
        headers: ctx.headers,
      }).then(async (r) => ({ status: r.status, body: await r.json() }));

    // The route must not be swallowed by /api/items/:id.
    const first = await ask(`groupId=${groupId}&name=Scoped A`);
    assert.equal(first.status, 200, JSON.stringify(first.body));
    assert.equal(first.body.scope, 'group-name');
    assert.equal(first.body.partNo, 1, 'no Scoped A in this group yet');
    assert.ok(first.body.partCode.endsWith(String(first.body.partNo)));

    // Make one, and the next of that name follows it.
    const made = await fetch(`${ctx.baseUrl}/api/items`, {
      method: 'POST',
      headers: ctx.headers,
      body: JSON.stringify({
        name: 'Scoped A',
        displayName: 'Scoped A',
        groupId,
        unitId,
        partNo: 1,
        partCode: 'SCOPE1',
      }),
    }).then((r) => r.json());

    const second = await ask(`groupId=${groupId}&name=Scoped A`);
    assert.equal(second.body.partNo, 2, 'Scoped A holds 1, so the next is 2');

    // A different name is a different scope and starts again.
    const other = await ask(`groupId=${groupId}&name=Scoped B`);
    assert.equal(other.body.partNo, 1, 'no Scoped B in this group');

    // The same name, spelled differently, is the same name. This is the rule
    // the duplicate-name check uses, and the two have to agree or a name it
    // calls identical would get a fresh 1 and collide on the code.
    const spelled = await ask(`groupId=${groupId}&name=${encodeURIComponent('  scoped   a  ')}`);
    assert.equal(spelled.body.partNo, 2, 'trimmed, collapsed and lower-cased');

    // Archived parts still hold their number: it was issued, and reissuing it
    // would collide on the code.
    await ctx.backend.run('UPDATE items SET is_archived = 1 WHERE id = ?', [
      made.item.id,
    ]);
    const afterArchive = await ask(`groupId=${groupId}&name=Scoped A`);
    assert.equal(afterArchive.body.partNo, 2);

    assert.equal((await ask('name=Scoped A')).status, 400, 'groupId is required');
  } finally {
    await closeServer(ctx.server);
    await ctx.backend.closeDb();
  }
});

test('propertyCodeFor is numbers whole, letters first', () => {
  // The same vectors as partPropertyCode in part_code.dart. The two
  // implementations are allowed to exist; drifting apart is not.
  const fixture = [
    ['Brass', 'B'],
    ['Nickel', 'N'],
    ['copper', 'C'],
    ['Mild Steel', 'MS'],
    ['Brass Polish', 'BP'],
    ['22 Gauge', '22G'],
    ['24 Gauge', '24G'],
    // Typed without the space, which is how a gauge cell usually gets one.
    // These used to come out '2' and '2' — the collision this rule exists to
    // prevent, reintroduced by the spelling.
    ['22G', '22G'],
    ['24G', '24G'],
    ['2mm', '2M'],
    ['M8', 'M8'],
    ['128GB', '128G'],
    ['12GB', '12G'],
    ['16GB', '16G'],
    ['SS 304', 'S304'],
    ['', ''],
    ['   ', ''],
    ['---', ''],
  ];
  for (const [value, want] of fixture) {
    assert.equal(propertyCodeFor(value), want, JSON.stringify(value));
  }

  // The digits are the whole point: taking strictly the first character makes
  // these two the same, and they are the two parts a press shop most needs to
  // tell apart.
  assert.notEqual(propertyCodeFor('22 Gauge'), propertyCodeFor('24 Gauge'));
  assert.notEqual(propertyCodeFor('22G'), propertyCodeFor('24G'));
  assert.notEqual(propertyCodeFor('12GB'), propertyCodeFor('16GB'));

  // Distinct from valueCodeFor, which keeps a short single word whole because
  // it answers a different question.
  assert.equal(valueCodeFor('Brass'), 'BRAS');
  assert.equal(propertyCodeFor('Brass'), 'B');
});

test('a part is stamped with its properties in its code', async () => {
  const ctx = await boot('paper-part-props-', 'part-props@paper.local');
  try {
    const items = await fetch(`${ctx.baseUrl}/api/items`, {
      headers: ctx.headers,
    }).then((r) => r.json());
    const sample = items.items[0];
    const { groupId, unitId } = sample;
    // The WHOLE lineage, root first — not just the group the part is filed
    // under. This test used to compute `initialsOf(groupRow.name)`, one level,
    // and so asserted the very divergence it was meant to catch: the sheet
    // showed SADP… for a part the server stamped DP….
    const lineage = await groupLineage(groupId, { get: ctx.backend.get });
    const trunk = lineage.map((n) => initialsOf(n)).join('');

    const create = (name, tree) =>
      fetch(`${ctx.baseUrl}/api/items`, {
        method: 'POST',
        headers: ctx.headers,
        body: JSON.stringify({
          name,
          displayName: name,
          groupId,
          unitId,
          variationTree: tree,
        }),
      }).then((r) => r.json());

    const property = (name, value, code) => ({
      kind: 'property',
      name,
      children: [{ kind: 'value', name: value, code: code || '' }],
    });

    // No properties — stamped exactly as it always was.
    const bare = await create('Bare Part', []);
    assert.equal(bare.item.partCode, `${trunk}BP1`, 'trunk + number, unchanged');

    // With properties — one code each, in declared order, between the letters
    // and the number.
    const full = await create('Full Part', [
      property('Alloy', 'Brass'),
      property('Thickness', '22 Gauge'),
      property('Finish', 'Nickel'),
    ]);
    assert.equal(full.item.partCode, `${trunk}FPB22GN1`);

    // The shop's explicit code on a value wins over the derived one.
    const coded = await create('Coded Part', [property('Alloy', 'Brass', 'BR')]);
    assert.equal(coded.item.partCode, `${trunk}CPBR1`);

    // A part filed under a CHILD group takes the whole lineage's letters.
    //
    // This is the shape the sheet creates — it files "Switch Action › Dolly"
    // as a parent and child group and puts the part under the child — and it
    // is where the two sides disagreed: the save has only the child row in
    // hand, so taking its name alone gave DP for a part the sheet calls SADP.
    const parent = await fetch(`${ctx.baseUrl}/api/groups`, {
      method: 'POST',
      headers: ctx.headers,
      body: JSON.stringify({ name: 'Switch Action', groupType: 'item', unitId }),
    }).then((r) => r.json());
    const child = await fetch(`${ctx.baseUrl}/api/groups`, {
      method: 'POST',
      headers: ctx.headers,
      body: JSON.stringify({
        name: 'Dolly',
        groupType: 'item',
        unitId,
        parentGroupId: parent.group.id,
      }),
    }).then((r) => r.json());

    const nested = await fetch(`${ctx.baseUrl}/api/items`, {
      method: 'POST',
      headers: ctx.headers,
      body: JSON.stringify({
        name: 'Patti',
        displayName: 'Patti',
        groupId: child.group.id,
        unitId,
        variationTree: [
          property('Alloy', 'Brass'),
          property('Thickness', '22 Gauge'),
          property('Finish', 'Nickel'),
        ],
      }),
    }).then((r) => r.json());

    // Asserted as the rule, not a literal: whether "Switch Action" is itself
    // under a root group depends on the seed, and the point is that EVERY
    // level contributes — which a one-level trunk did not.
    const nestedLineage = await groupLineage(child.group.id, {
      get: ctx.backend.get,
    });
    assert.deepEqual(
      nestedLineage.slice(-2),
      ['Switch Action', 'Dolly'],
      'the lineage reaches past the group the part is filed under',
    );
    assert.equal(
      nested.item.partCode,
      `${nestedLineage.map((n) => initialsOf(n)).join('')}PB22GN1`,
      'every lineage level, then the properties, then the number',
    );
    // "Primary Group" — the root a parentless group is filed under — is not a
    // name anybody chose for the part, so it puts no letters in the code: the
    // sheet previews SADP… and the stamp must agree, not read PGSADP….
    assert.ok(
      nested.item.partCode.startsWith('SADP'),
      `the root group stays out of the code: ${nested.item.partCode}`,
    );
    assert.ok(
      nested.item.partCode.includes('SAD'),
      'Switch Action and Dolly are both in it, which is what the sheet shows',
    );

    // An update that changes a property does NOT restamp. A code is issued
    // once; it is on drawings and every die code derives from it.
    const patched = await fetch(`${ctx.baseUrl}/api/items/${full.item.id}`, {
      method: 'PATCH',
      headers: ctx.headers,
      body: JSON.stringify({
        name: 'Full Part',
        displayName: 'Full Part',
        groupId,
        unitId,
        variationTree: [property('Alloy', 'Copper')],
      }),
    }).then((r) => r.json());
    assert.equal(patched.item.partCode, `${trunk}FPB22GN1`, 'issued once');
  } finally {
    await closeServer(ctx.server);
    await ctx.backend.closeDb();
  }
});

test('two names that reduce to the same letters both still get a code', async () => {
  // "Patti" and "Plate" are both P, and with the number scoped by name they
  // both start at 1 — so without properties they derive one code. This used to
  // leave the second part with NO code at all, silently.
  const ctx = await boot('paper-part-clash-', 'part-clash@paper.local');
  try {
    const items = await fetch(`${ctx.baseUrl}/api/items`, {
      headers: ctx.headers,
    }).then((r) => r.json());
    const { groupId, unitId } = items.items[0];

    const create = (name) =>
      fetch(`${ctx.baseUrl}/api/items`, {
        method: 'POST',
        headers: ctx.headers,
        body: JSON.stringify({ name, displayName: name, groupId, unitId }),
      }).then((r) => r.json());

    const patti = await create('Patti');
    const plate = await create('Plate');

    assert.ok(patti.item.partCode, 'the first gets a code');
    assert.ok(plate.item.partCode, 'and so does the second');
    assert.notEqual(
      plate.item.partCode,
      patti.item.partCode,
      'the second takes the next number rather than no code',
    );
  } finally {
    await closeServer(ctx.server);
    await ctx.backend.closeDb();
  }
});

test('a part number has to be a whole number above zero', async () => {
  const ctx = await boot('paper-part-validate-', 'part-validate@paper.local');
  try {
    const items = await fetch(`${ctx.baseUrl}/api/items`, {
      headers: ctx.headers,
    }).then((r) => r.json());
    const sample = items.items[0];

    // The border's contract refuses these first — it declares partNo as an
    // integer of at least 1 — so the route answers 400 before saveItem runs.
    for (const bad of [0, -3, 2.5]) {
      const response = await fetch(`${ctx.baseUrl}/api/items`, {
        method: 'POST',
        headers: ctx.headers,
        body: JSON.stringify({
          name: `Bad Part ${bad}`,
          displayName: `Bad Part ${bad}`,
          groupId: sample.groupId,
          unitId: sample.unitId,
          partNo: bad,
        }),
      });
      assert.equal(response.status, 400, `partNo ${bad} should be refused`);
    }

    // And saveItem refuses them on its own account, for every caller that does
    // not come through that route — seeds, scripts, the next module.
    for (const bad of [0, -3, 2.5]) {
      await assert.rejects(
        () =>
          ctx.backend.saveItem({
            name: `Direct Bad ${bad}`,
            displayName: `Direct Bad ${bad}`,
            groupId: sample.groupId,
            unitId: sample.unitId,
            partNo: bad,
          }),
        (error) => {
          assert.equal(error.statusCode, 400);
          assert.match(error.message, /whole number above zero/);
          return true;
        },
      );
    }

    // The name duplicate is the more fundamental refusal and fires first.
    const dupName = await fetch(`${ctx.baseUrl}/api/items`, {
      method: 'POST',
      headers: ctx.headers,
      body: JSON.stringify({
        name: sample.name,
        displayName: sample.name,
        groupId: sample.groupId,
        unitId: sample.unitId,
        partNo: 999,
        partCode: 'ZZZ999',
      }),
    });
    assert.equal(dupName.status, 409);
    assert.match((await dupName.json()).error, /already exists in this group/);
  } finally {
    await closeServer(ctx.server);
    await ctx.backend.closeDb();
  }
});

test('an item created without an identity is stamped with the next one', async () => {
  const ctx = await boot('paper-part-auto-', 'part-auto@paper.local');
  try {
    const items = await fetch(`${ctx.baseUrl}/api/items`, {
      headers: ctx.headers,
    }).then((r) => r.json());
    const sample = items.items[0];

    // Nobody said anything about identity, so the backend stamps one — the
    // rule is not the wizard's to own.
    const created = await fetch(`${ctx.baseUrl}/api/items`, {
      method: 'POST',
      headers: ctx.headers,
      body: JSON.stringify({
        name: 'Unstamped Lid',
        displayName: 'Unstamped Lid',
        groupId: sample.groupId,
        unitId: sample.unitId,
      }),
    }).then((r) => r.json());

    assert.ok(created.item.partNo >= 1, 'a number was issued');
    assert.ok(
      created.item.partCode.endsWith(String(created.item.partNo)),
      'the code ends in the number it was issued',
    );
  } finally {
    await closeServer(ctx.server);
    await ctx.backend.closeDb();
  }
});

test('a variant code is the trunk, the value codes, then the number', () => {
  const { buildVariantPartCode, valueCodeFor } = require('../modules/items/part-identity');

  for (const row of VARIANT_FIXTURE) {
    assert.equal(
      buildVariantPartCode({
        groupName: row.group,
        setName: row.set,
        itemName: row.item,
        valueCodes: row.values,
        partNo: row.no,
      }),
      row.code,
      `${row.group}/${row.set}/${row.item} [${row.values.join(',')}] #${row.no}`,
    );
  }

  for (const row of VALUE_CODE_FIXTURE) {
    assert.equal(valueCodeFor(row.name), row.code, row.name || '(empty)');
  }

  // Deriving from the base's OWN code, which is the safe direction. The same
  // vectors are asserted in packages/core_erp/test/part_code_test.dart.
  const { variantCodeFromPartCode } = require('../modules/items/part-identity');
  const FROM_BASE_FIXTURE = [
    ['SADP48', ['B', '22'], 'SADPB2248'],
    ['SADP48', ['MS', '22'], 'SADPMS2248'],
    ['ATL', ['SS'], 'ATLSS'],
    ['W3', ['B'], 'WB3'],
    ['SADP48', [], 'SADP48'],
    ['SADP48', ['', ' ', '-'], 'SADP48'],
    ['', ['B'], ''],
    [null, ['B'], ''],
    ['sadp48', ['ss 304'], 'SADPSS30448'],
    // An all-digit base has no trunk to insert into and is left alone.
    ['48', ['B'], '48'],
  ];
  for (const [base, values, want] of FROM_BASE_FIXTURE) {
    assert.equal(variantCodeFromPartCode(base, values), want, `${base} + [${values}]`);
  }

  // Why this direction is preferred: re-deriving a trunk from names needs the
  // SET as well, and omitting it is silent. 'Switch Action' + 'Patti' with no
  // set derives SAP, so a variant of SADP48 would be stamped SAPB2248 — a code
  // whose trunk its own parent does not share.
  const reDerived = buildVariantPartCode({
    groupName: 'Switch Action', itemName: 'Patti', valueCodes: ['B', '22'], partNo: 48,
  });
  assert.equal(reDerived, 'SAPB2248');
  assert.notEqual(reDerived, variantCodeFromPartCode('SADP48', ['B', '22']));

  // A variant code must not collide with its own part's code, or a scan could
  // not tell the part from one of its variants.
  const part = buildPartCode({ groupName: 'Switch Action', setName: 'Dolly', itemName: 'Patti', partNo: 48 });
  const variants = VARIANT_FIXTURE
    .filter((r) => r.values.length > 0 && r.code)
    .map((r) => r.code);
  for (const code of variants) {
    assert.notEqual(code, part, 'a variant and its part must not share a code');
  }
});
