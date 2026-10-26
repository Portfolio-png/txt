const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

const { buildDieCode, nextFreeDieCode, dieTypeLabel } = require('../modules/dies/die-identity');

// What a die sheet records beside the die (migrations/048), and the code it is
// known by: type initials, then D, then the part's own code — CDSADP48.
//
// The first assertion is the load-bearing one: it fails loudly if the columns
// never reached the test database, which is the whole reason this feature is
// migration-only.

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

async function saveDie(ctx, body) {
  const response = await fetch(`${ctx.baseUrl}/api/dies`, {
    method: 'POST',
    headers: ctx.headers,
    body: JSON.stringify(body),
  });
  return { status: response.status, body: await response.json() };
}

// --- the shared rule, asserted here and in die_code_test.dart ---------------
const CODE_FIXTURE = [
  { type: 'cutting', partCode: 'SADP48', code: 'CDSADP48' },
  { type: 'bending', partCode: 'SADP48', code: 'BDSADP48' },
  // The factory sheet's other two dies. RD and AD, not R and A: the mandatory
  // D keeps a die code distinct from its own part code on a scan.
  { type: 'riveting', partCode: 'SADP48', code: 'RDSADP48' },
  { type: 'assembly', partCode: 'SADP48', code: 'ADSADP48' },
  { type: 'cutting', partCode: 'atl1', code: 'CDATL1' },
  { type: 'cutting', partCode: '', code: '' },
  { type: '', partCode: 'SADP48', code: '' },
  { type: 'nonsense', partCode: 'SADP48', code: '' },
];

test('a die code is the type initials, then D, then the part code', () => {
  for (const row of CODE_FIXTURE) {
    assert.equal(
      buildDieCode({ dieType: row.type, partCode: row.partCode }),
      row.code,
      `${row.type} / ${row.partCode}`,
    );
  }
  // The label is what the initials come from, so a two-word type gives two.
  assert.equal(dieTypeLabel('cutting'), 'Cutting');
  assert.equal(dieTypeLabel('nope'), '');
});

test('the die sheet round-trips, and the code is derived from the part', async () => {
  const ctx = await boot('paper-die-sheet-', 'die-owner@paper.local');
  try {
    const created = await saveDie(ctx, {
      dieType: 'cutting',
      partCode: 'SADP48',
      madeBy: 'Atul Mestry',
      poAt: '2026-05-21T04:50:00.000Z',
      dateInAt: '2026-09-15T06:00:00.000Z',
      linerSizeNm: 94500000,
      linerSizeUnit: 'mm',
      noOfSet: 1,
      storeArea: 'F206',
      rackNo: '23-4',
      status: 'ready',
      ownership: 'inHouse',
    });
    assert.equal(created.status, 200, JSON.stringify(created.body));
    const die = created.body.die;

    // Derived, not stamped with the clock — the assertion that fails if
    // migration 048 never ran is every line below it.
    assert.equal(die.toolCode, 'CDSADP48');
    assert.equal(die.dieType, 'cutting');
    assert.equal(die.madeBy, 'Atul Mestry');
    assert.equal(die.poAt, '2026-05-21T04:50:00.000Z');
    assert.equal(die.dateInAt, '2026-09-15T06:00:00.000Z');
    assert.equal(die.linerSizeNm, 94500000);
    assert.equal(die.linerSizeUnit, 'mm');
    assert.equal(die.noOfSet, 1);
    assert.equal(die.storeArea, 'F206');
    assert.equal(die.rackNo, '23-4');

    // And the list read carries it, not only the save's own response.
    const listed = await fetch(`${ctx.baseUrl}/api/dies`, { headers: ctx.headers })
      .then((r) => r.json());
    const fromList = listed.dies.find((row) => row.id === die.id);
    assert.equal(fromList.toolCode, 'CDSADP48');
    assert.equal(fromList.storeArea, 'F206');

    // Never measured and measured at zero are different rows.
    const unmeasured = await saveDie(ctx, {
      dieType: 'bending',
      partCode: 'SADP48',
      status: 'ready',
      ownership: 'inHouse',
    });
    assert.equal(unmeasured.status, 200, JSON.stringify(unmeasured.body));
    assert.equal(unmeasured.body.die.toolCode, 'BDSADP48');
    assert.equal(unmeasured.body.die.linerSizeNm, null);
    assert.equal(unmeasured.body.die.noOfSet, null);
  } finally {
    await closeServer(ctx.server);
  }
});

test('a save that says nothing about the sheet keeps it', async () => {
  const ctx = await boot('paper-die-preserve-', 'die-preserve@paper.local');
  try {
    const created = await saveDie(ctx, {
      dieType: 'cutting',
      partCode: 'SADP48',
      madeBy: 'Atul Mestry',
      linerSizeNm: 94500000,
      noOfSet: 2,
      storeArea: 'F206',
      rackNo: '23-4',
      status: 'ready',
      ownership: 'inHouse',
      operationalNotes: 'Grease before every run',
    });
    assert.equal(created.status, 200, JSON.stringify(created.body));
    const id = String(created.body.die.id);

    // The Dies screen saving a note, mentioning none of the sheet. Before 048
    // this blanked every column it left out.
    const quiet = await saveDie(ctx, {
      id,
      operationalNotes: 'Grease twice',
      status: 'ready',
      ownership: 'inHouse',
    });
    assert.equal(quiet.status, 200, JSON.stringify(quiet.body));
    const after = quiet.body.die;
    assert.equal(after.operationalNotes, 'Grease twice');
    assert.equal(after.toolCode, 'CDSADP48');
    assert.equal(after.madeBy, 'Atul Mestry');
    assert.equal(after.linerSizeNm, 94500000);
    assert.equal(after.noOfSet, 2);
    assert.equal(after.storeArea, 'F206');
    assert.equal(after.rackNo, '23-4');

    // Clearing still works — '' is a value, absence is not.
    const cleared = await saveDie(ctx, { id, madeBy: '' });
    assert.equal(cleared.body.die.madeBy, '');
    assert.equal(cleared.body.die.storeArea, 'F206');
  } finally {
    await closeServer(ctx.server);
  }
});

test('a taken die code is refused by name, with a free one offered', async () => {
  const ctx = await boot('paper-die-clash-', 'die-clash@paper.local');
  try {
    const first = await saveDie(ctx, {
      dieType: 'cutting',
      partCode: 'SADP48',
      status: 'ready',
      ownership: 'inHouse',
    });
    assert.equal(first.status, 200, JSON.stringify(first.body));
    assert.equal(first.body.die.toolCode, 'CDSADP48');

    // The same part code in another group derives the same die code — a real
    // case, because part codes are unique per group and die codes are not.
    const second = await saveDie(ctx, {
      dieType: 'cutting',
      partCode: 'SADP48',
      status: 'ready',
      ownership: 'inHouse',
    });
    assert.equal(second.status, 409, JSON.stringify(second.body));
    assert.equal(second.body.code, 'die_tool_code_duplicate');
    assert.equal(second.body.suggestedToolCode, 'CDSADP48-2');
    assert.match(second.body.error, /already used by die #/);

    // Taking the offer works, and the next clash moves on again.
    const third = await saveDie(ctx, {
      toolCode: 'CDSADP48-2',
      dieType: 'cutting',
      partCode: 'SADP48',
      status: 'ready',
      ownership: 'inHouse',
    });
    assert.equal(third.status, 200, JSON.stringify(third.body));
    assert.equal(
      await nextFreeDieCode('CDSADP48', { get: ctx.backend.get }),
      'CDSADP48-3',
    );

    // A die keeping its own code is not a clash with itself.
    const renamed = await saveDie(ctx, {
      id: String(first.body.die.id),
      toolCode: 'CDSADP48',
      madeBy: 'Suresh Amb',
    });
    assert.equal(renamed.status, 200, JSON.stringify(renamed.body));
    assert.equal(renamed.body.die.madeBy, 'Suresh Amb');

    // And a type nobody defined is a 400, not a die filed under nonsense.
    const badType = await saveDie(ctx, {
      dieType: 'squashing',
      partCode: 'SADP48',
      status: 'ready',
      ownership: 'inHouse',
    });
    assert.equal(badType.status, 400, JSON.stringify(badType.body));
  } finally {
    await closeServer(ctx.server);
  }
});

test('a die picker reads where the die is kept', async () => {
  const ctx = await boot('paper-die-where-', 'die-where@paper.local');
  try {
    const structured = await saveDie(ctx, {
      dieType: 'cutting',
      partCode: 'SADP48',
      storeArea: 'F206',
      rackNo: '23-4',
      status: 'ready',
      ownership: 'inHouse',
    });
    assert.equal(structured.status, 200, JSON.stringify(structured.body));

    // The shape every die had before 048: one free-text location.
    const legacy = await saveDie(ctx, {
      toolCode: 'OLD-DIE-1',
      storageLocation: 'Rack B, Shelf 3',
      status: 'ready',
      ownership: 'inHouse',
    });
    assert.equal(legacy.status, 200, JSON.stringify(legacy.body));

    // Candidates are always asked for on behalf of something, so this is the
    // list an item's die picker would show.
    const items = await fetch(`${ctx.baseUrl}/api/items`, { headers: ctx.headers })
      .then((r) => r.json());
    const owner = items.items[0];
    assert.ok(owner, 'the demo seed should leave at least one item');
    const candidates = await fetch(
      `${ctx.baseUrl}/api/links/item/${owner.id}/candidates?type=die&limit=200`,
      { headers: ctx.headers },
    ).then((r) => r.json());
    const rows = candidates.candidates || [];
    const structuredRow = rows.find((row) => row.label === 'CDSADP48');
    const legacyRow = rows.find((row) => row.label === 'OLD-DIE-1');
    assert.ok(structuredRow, 'the structured die is offered');
    assert.ok(legacyRow, 'the legacy die is offered');
    assert.equal(structuredRow.subtitle, 'F206 · Rack 23-4');
    assert.equal(legacyRow.subtitle, 'Rack B, Shelf 3');
  } finally {
    await closeServer(ctx.server);
  }
});

test('a part reads its dies’ typed type and maker; a bad maker is a 400', async () => {
  // The item sheet edits a die from beside its part, so the part's own read
  // must carry what the die sheet shows. Without dieTypeLabel and dieMakerId
  // there, every correction sent back a bare slug and no maker — and the
  // upsert stores what it is sent.
  const ctx = await boot('paper-die-maker-link-', 'die-maker-link@paper.local');
  try {
    const maker = await fetch(`${ctx.baseUrl}/api/die-makers`, {
      method: 'POST',
      headers: ctx.headers,
      body: JSON.stringify({ name: 'Ashok Dies' }),
    }).then((r) => r.json());
    assert.ok(maker.dieMaker?.id, JSON.stringify(maker));

    const created = await saveDie(ctx, {
      dieType: 'deep-draw',
      dieTypeLabel: 'Deep Draw',
      partCode: 'SADP48',
      dieMakerId: maker.dieMaker.id,
      status: 'ready',
      ownership: 'inHouse',
    });
    assert.equal(created.status, 200, JSON.stringify(created.body));
    const dieId = String(created.body.die.id);

    const items = await fetch(`${ctx.baseUrl}/api/items`, { headers: ctx.headers }).then((r) =>
      r.json(),
    );
    const part = items.items[0];
    const linked = await fetch(`${ctx.baseUrl}/api/links`, {
      method: 'POST',
      headers: ctx.headers,
      body: JSON.stringify({ from: { type: 'item', id: part.id }, to: { type: 'die', id: dieId } }),
    });
    assert.equal(linked.status, 201, await linked.clone().text());

    const read = await fetch(`${ctx.baseUrl}/api/items/${part.id}`, { headers: ctx.headers }).then(
      (r) => r.json(),
    );
    const onPart = read.item.dies.find((d) => d.id === dieId);
    assert.ok(onPart, 'the die is listed on its part');
    assert.equal(onPart.dieTypeLabel, 'Deep Draw');
    assert.equal(onPart.dieMakerId, maker.dieMaker.id);

    // A maker that is not there is the caller's mistake, not a 500.
    const unknown = await saveDie(ctx, { id: dieId, dieMakerId: 999999 });
    assert.equal(unknown.status, 400, JSON.stringify(unknown.body));

    // Switching to a built-in type drops the typed label with it.
    const builtIn = await saveDie(ctx, { id: dieId, dieType: 'cutting' });
    assert.equal(builtIn.status, 200, JSON.stringify(builtIn.body));
    assert.equal(builtIn.body.die.dieTypeLabel, '');
    // And the maker, not mentioned, stays.
    assert.equal(builtIn.body.die.dieMakerId, maker.dieMaker.id);
  } finally {
    await closeServer(ctx.server);
  }
});
