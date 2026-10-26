const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

const {
  buildDieCode,
  dieTypeLabel,
  slugifyDieType,
  isUsableDieType,
} = require('../modules/dies/die-identity');

// The master behind "Die Made By", and a die type the shop typed.
//
// Migration 048 argued against both: made_by was free text "deliberately",
// and a die type was one of four. The shop reversed it. What these assert is
// that the reversal did not cost anything that was already right — a die that
// names its maker in text still reads back, and an unknown type with no name
// for it is still refused rather than filed under nonsense.

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

function api(ctx, method, route, body) {
  return fetch(`${ctx.baseUrl}${route}`, {
    method,
    headers: ctx.headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  }).then(async (r) => ({ status: r.status, body: await r.json() }));
}

// --- the typed-type rule, mirrored in die_code_test.dart -------------------

test('a typed die type derives its code from the words that were typed', () => {
  // The whole reason the label is stored: there is no row to look it up in,
  // and without it the code is '' rather than anything wrong-looking.
  assert.equal(dieTypeLabel('deep-drawing', 'Deep Drawing'), 'Deep Drawing');
  assert.equal(
    buildDieCode({
      dieType: 'deep-drawing',
      dieTypeLabel: 'Deep Drawing',
      partCode: 'SADP48',
    }),
    'DDDSADP48',
    'two words give two initials, then the mandatory D',
  );

  // A built-in ignores any label sent beside it — the slug is authoritative
  // for the four, so a stale label cannot rename a die type.
  assert.equal(dieTypeLabel('cutting', 'Something Else'), 'Cutting');
  assert.equal(
    buildDieCode({ dieType: 'cutting', dieTypeLabel: 'Something Else', partCode: 'SADP48' }),
    'CDSADP48',
  );

  // And an unknown slug with nothing to read still yields no code.
  assert.equal(buildDieCode({ dieType: 'squashing', partCode: 'SADP48' }), '');
});

test('slugifyDieType and isUsableDieType agree on what may be stored', () => {
  assert.equal(slugifyDieType('Deep Drawing'), 'deep-drawing');
  assert.equal(slugifyDieType('  Coining / Sizing  '), 'coining-sizing');
  assert.equal(slugifyDieType(''), '');

  assert.equal(isUsableDieType('cutting'), true, 'a built-in needs no label');
  assert.equal(isUsableDieType(''), true, 'no type at all is allowed');
  assert.equal(isUsableDieType('deep-drawing', 'Deep Drawing'), true);
  assert.equal(
    isUsableDieType('deep-drawing'),
    false,
    'an unknown slug with no label names a die whose code cannot be rebuilt',
  );
});

// --- the master ------------------------------------------------------------

test('a die maker is created, listed and picked by name', async () => {
  const ctx = await boot('paper-die-makers-', 'die-makers@paper.local');
  try {
    const created = await api(ctx, 'POST', '/api/die-makers', {
      name: 'Sharma Tool Works',
      alias: 'STW',
      gstNumber: '27AAFCS1234Z1ZQ',
      address: 'Plot 14, MIDC',
      contactName: 'Ramesh Sharma',
      designation: 'Proprietor',
      phone: '9876543210',
      email: 'ramesh@sharmatools.in',
    });
    assert.equal(created.status, 200, JSON.stringify(created.body));
    assert.equal(created.body.dieMaker.name, 'Sharma Tool Works');
    assert.equal(created.body.dieMaker.designation, 'Proprietor');
    assert.equal(created.body.dieMaker.usageCount, 0);

    // The same name again is a 409 that names who holds it, so the picker can
    // select the existing one instead of making a second.
    const again = await api(ctx, 'POST', '/api/die-makers', {
      name: 'sharma tool works',
    });
    assert.equal(again.status, 409, JSON.stringify(again.body));
    assert.equal(again.body.code, 'die_maker_duplicate');
    assert.equal(again.body.dieMakerId, created.body.dieMaker.id);

    const listed = await api(ctx, 'GET', '/api/die-makers');
    assert.equal(listed.status, 200);
    assert.ok(
      listed.body.dieMakers.some((m) => m.id === created.body.dieMaker.id),
      'the created maker should be in the list',
    );
  } finally {
    await closeServer(ctx.server);
  }
});

test('a GST number is fifteen characters or it is refused', async () => {
  const ctx = await boot('paper-die-maker-gst-', 'die-maker-gst@paper.local');
  try {
    const short = await api(ctx, 'POST', '/api/die-makers', {
      name: 'Short GST Tools',
      gstNumber: '27AAFCS',
    });
    assert.equal(short.status, 400, JSON.stringify(short.body));

    // Blank is fine. A fitter on the floor has no GST number, which is the
    // half of migration 048's argument that survives.
    const blank = await api(ctx, 'POST', '/api/die-makers', {
      name: 'Suresh (fitter)',
    });
    assert.equal(blank.status, 200, JSON.stringify(blank.body));
    assert.equal(blank.body.dieMaker.gstNumber, '');
  } finally {
    await closeServer(ctx.server);
  }
});

test('a die carries its maker id and still carries the typed name', async () => {
  const ctx = await boot('paper-die-maker-link-', 'die-maker-link@paper.local');
  try {
    const maker = await api(ctx, 'POST', '/api/die-makers', {
      name: 'Sharma Tool Works',
    });
    const makerId = maker.body.dieMaker.id;

    const die = await api(ctx, 'POST', '/api/dies', {
      dieType: 'cutting',
      partCode: 'SADP48',
      madeBy: 'Sharma Tool Works',
      dieMakerId: makerId,
      status: 'ready',
      ownership: 'inHouse',
    });
    assert.equal(die.status, 200, JSON.stringify(die.body));
    assert.equal(die.body.die.dieMakerId, makerId);
    assert.equal(
      die.body.die.madeBy,
      'Sharma Tool Works',
      'the text survives beside the id — a reader prefers the id and falls back',
    );

    // A die made by somebody with no record is still a legal die.
    const unlinked = await api(ctx, 'POST', '/api/dies', {
      dieType: 'bending',
      partCode: 'SADP48',
      madeBy: 'Suresh on the floor',
      status: 'ready',
      ownership: 'inHouse',
    });
    assert.equal(unlinked.status, 200, JSON.stringify(unlinked.body));
    assert.equal(unlinked.body.die.dieMakerId, null);
    assert.equal(unlinked.body.die.madeBy, 'Suresh on the floor');

    // The maker now knows it is in use, which is what makes a delete archive
    // rather than orphan the die.
    const listed = await api(ctx, 'GET', '/api/die-makers');
    const found = listed.body.dieMakers.find((m) => m.id === makerId);
    assert.equal(found.usageCount, 1);

    const removed = await api(ctx, 'DELETE', `/api/die-makers/${makerId}`);
    assert.equal(removed.status, 200, JSON.stringify(removed.body));
    assert.equal(removed.body.archived, true, 'a maker in use is archived');
  } finally {
    await closeServer(ctx.server);
  }
});

test('a die filed under a typed type keeps the words and derives from them', async () => {
  const ctx = await boot('paper-die-custom-type-', 'die-custom-type@paper.local');
  try {
    const die = await api(ctx, 'POST', '/api/dies', {
      dieType: 'deep-drawing',
      dieTypeLabel: 'Deep Drawing',
      partCode: 'SADP48',
      status: 'ready',
      ownership: 'inHouse',
    });
    assert.equal(die.status, 200, JSON.stringify(die.body));
    assert.equal(die.body.die.dieType, 'deep-drawing');
    assert.equal(die.body.die.dieTypeLabel, 'Deep Drawing');
    assert.equal(
      die.body.die.toolCode,
      'DDDSADP48',
      'the server derives the same code the sheet showed',
    );

    // Still refused when nothing says what the words were.
    const nameless = await api(ctx, 'POST', '/api/dies', {
      dieType: 'squashing',
      partCode: 'SADP48',
      status: 'ready',
      ownership: 'inHouse',
    });
    assert.equal(nameless.status, 400, JSON.stringify(nameless.body));
  } finally {
    await closeServer(ctx.server);
  }
});

test('the die-makers path is gated, not left to the legacy write gate', async () => {
  // An undeclared first path segment maps to no module, which skips the
  // per-module CRUD check entirely. This asserts the segment is declared.
  const { moduleForPath } = require('../kernel/registry');
  if (typeof moduleForPath === 'function') {
    assert.equal(moduleForPath('die-makers'), 'dies');
    return;
  }
  const { MODULES } = require('../kernel/registry');
  assert.ok(
    (MODULES.dies.pathSegments || []).includes('die-makers'),
    'die-makers must be declared on the dies module',
  );
});
