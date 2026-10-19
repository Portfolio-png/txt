const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

const { buildPartCode } = require('../modules/items/part-identity');

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

test('the next part identity restarts per group and set, and counts archived parts', async () => {
  const ctx = await boot('paper-part-next-', 'part-next@paper.local');
  try {
    const items = await fetch(`${ctx.baseUrl}/api/items`, {
      headers: ctx.headers,
    }).then((r) => r.json());
    const sample = items.items[0];
    const groupId = sample.groupId;

    const ask = (query) =>
      fetch(`${ctx.baseUrl}/api/items/next-part-identity?${query}`, {
        headers: ctx.headers,
      }).then(async (r) => ({ status: r.status, body: await r.json() }));

    // The route must not be swallowed by /api/items/:id.
    const first = await ask(`groupId=${groupId}&name=Patti`);
    assert.equal(first.status, 200, JSON.stringify(first.body));
    assert.equal(first.body.scope, 'group-unfiled');
    assert.ok(first.body.partNo >= 1);
    assert.ok(first.body.partCode.endsWith(String(first.body.partNo)));

    // A set that has only been named has no members, so its scope is empty.
    const pending = await ask(`groupId=${groupId}&setPending=1&name=Patti`);
    assert.equal(pending.body.partNo, 1);
    assert.equal(pending.body.scope, 'pending-set');

    // Build a real set in this group with two numbered members.
    const unitId = sample.unitId;
    const madeIds = [];
    for (const [index, name] of ['Scoped A', 'Scoped B'].entries()) {
      const made = await fetch(`${ctx.baseUrl}/api/items`, {
        method: 'POST',
        headers: ctx.headers,
        body: JSON.stringify({
          name,
          displayName: name,
          groupId,
          unitId,
          partNo: index + 1,
          partCode: `SCOPE${index + 1}`,
        }),
      }).then((r) => r.json());
      madeIds.push(made.item.id);
    }
    const set = await fetch(`${ctx.baseUrl}/api/inventory/sets`, {
      method: 'POST',
      headers: ctx.headers,
      body: JSON.stringify({
        name: 'Scoped Kit',
        groupId,
        lines: madeIds.map((itemId, position) => ({
          itemId,
          variationLeafNodeId: 0,
          quantity: 1,
          position,
        })),
      }),
    }).then((r) => r.json());

    const inSet = await ask(`groupId=${groupId}&setId=${set.set.id}&name=Patti`);
    assert.equal(inSet.body.partNo, 3, 'the set holds 1 and 2, so the next is 3');
    assert.equal(inSet.body.scope, 'set');

    // Archived parts still hold their number: it was issued, and reissuing it
    // would collide on the code.
    await ctx.backend.run('UPDATE items SET is_archived = 1 WHERE id = ?', [madeIds[1]]);
    const afterArchive = await ask(
      `groupId=${groupId}&setId=${set.set.id}&name=Patti`,
    );
    assert.equal(afterArchive.body.partNo, 3);

    // A different set in the same group starts again.
    const otherSet = await fetch(`${ctx.baseUrl}/api/inventory/sets`, {
      method: 'POST',
      headers: ctx.headers,
      body: JSON.stringify({
        name: 'Other Kit',
        groupId,
        lines: [
          { itemId: madeIds[0], variationLeafNodeId: 0, quantity: 1, position: 0 },
        ],
      }),
    }).then((r) => r.json());
    const otherScope = await ask(
      `groupId=${groupId}&setId=${otherSet.set.id}&name=Patti`,
    );
    assert.equal(otherScope.body.partNo, 2, 'only Scoped A (no 1) is in this set');

    assert.equal((await ask('name=Patti')).status, 400, 'groupId is required');
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
