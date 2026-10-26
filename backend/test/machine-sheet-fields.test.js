const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

const {
  buildMachineNo,
  nextFreeMachineNo,
} = require('../modules/machines/machine-identity');

// What a machine sheet records beside the machine (migrations/049), and the
// number it is known by: the type's initials, then the next in that type — the
// fourth power press is PP-4.
//
// The first assertion is the load-bearing one: it fails loudly if the columns
// never reached the test database.

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

async function saveMachine(ctx, body) {
  const response = await fetch(`${ctx.baseUrl}/api/machines`, {
    method: 'POST',
    headers: ctx.headers,
    body: JSON.stringify(body),
  });
  return { status: response.status, body: await response.json() };
}

/// A machine type. There are none on a fresh database — the picker's "Add New"
/// is the only thing that ever creates one, which is the point.
async function makeType(ctx, name) {
  const response = await fetch(`${ctx.baseUrl}/api/groups`, {
    method: 'POST',
    headers: ctx.headers,
    body: JSON.stringify({ name, groupType: 'machine', groupStructure: 'hierarchical' }),
  });
  assert.equal(response.status, 201, await response.clone().text());
  return (await response.json()).group;
}

// --- the shared rule, asserted here and in machine_no_test.dart -------------
const NUMBER_FIXTURE = [
  { type: 'Power Press', next: 4, no: 'PP-4' },
  { type: 'Punching M', next: 1, no: 'PM-1' },
  { type: 'Hand Press', next: 12, no: 'HP-12' },
  { type: 'Jigs & Fixtures', next: 2, no: 'JF-2' },
  { type: 'Feeder', next: 3, no: 'F-3' },
  { type: '', next: 4, no: '' },
  { type: 'Power Press', next: 0, no: '' },
];

test('a machine number is the type initials and the next in that type', () => {
  for (const row of NUMBER_FIXTURE) {
    assert.equal(
      buildMachineNo({ groupName: row.type, nextNumber: row.next }),
      row.no,
      `${row.type} / ${row.next}`,
    );
  }
});

test('the machine sheet round-trips, and the number comes from the type', async () => {
  const ctx = await boot('paper-machine-sheet-', 'machine-owner@paper.local');
  try {
    const type = await makeType(ctx, 'Power Press');

    const created = await saveMachine(ctx, {
      name: 'Press 4',
      groupId: type.id,
      machineMake: 'Mayank',
      manufacturedYear: 2011,
      feederMake: 'Jay Shanti',
      runningHours: 5001,
      strokesPerMinute: 110,
      capacityKind: 'rated',
      capacityKgf: 35000,
      dieFeedType: 'Progressive',
      status: 'active',
      primaryPhotoUrl: '',
    });
    assert.equal(created.status, 200, JSON.stringify(created.body));
    const machine = created.body.machine;

    // Derived from the type, not stamped with the clock — and every line below
    // fails if migration 049 never ran.
    assert.equal(machine.assetId, 'PP-1', 'the first press of its type');
    assert.equal(machine.machineMake, 'Mayank');
    assert.equal(machine.manufacturedYear, 2011);
    assert.equal(machine.feederMake, 'Jay Shanti');
    assert.equal(machine.runningHours, 5001);
    assert.equal(machine.strokesPerMinute, 110);
    assert.equal(machine.capacityKind, 'rated');
    assert.equal(machine.capacityKgf, 35000);
    assert.equal(machine.dieFeedType, 'Progressive');

    // The list read carries it too.
    const listed = await fetch(`${ctx.baseUrl}/api/machines`, { headers: ctx.headers })
      .then((r) => r.json());
    const fromList = listed.machines.find((row) => row.id === machine.id);
    assert.equal(fromList.machineMake, 'Mayank');
    assert.equal(fromList.capacityKgf, 35000);

    // The second press of the same type takes the next number.
    const second = await saveMachine(ctx, {
      name: 'Press 5',
      groupId: type.id,
      status: 'active',
      primaryPhotoUrl: '',
    });
    assert.equal(second.status, 200, JSON.stringify(second.body));
    assert.equal(second.body.machine.assetId, 'PP-2');

    // Never read and read as zero are different rows.
    assert.equal(second.body.machine.runningHours, null);
    assert.equal(second.body.machine.capacityKgf, null);
    assert.equal(second.body.machine.capacityKind, '');
  } finally {
    await closeServer(ctx.server);
  }
});

test('free hand is a recorded answer, not a missing one', async () => {
  const ctx = await boot('paper-machine-freehand-', 'machine-free@paper.local');
  try {
    const type = await makeType(ctx, 'Hand Press');
    const created = await saveMachine(ctx, {
      name: 'Bench',
      groupId: type.id,
      capacityKind: 'free_hand',
      status: 'active',
      primaryPhotoUrl: '',
    });
    assert.equal(created.status, 200, JSON.stringify(created.body));
    assert.equal(created.body.machine.capacityKind, 'free_hand');
    // No figure rides along with it — the two would be two answers.
    assert.equal(created.body.machine.capacityKgf, null);

    const withFigure = await saveMachine(ctx, {
      id: String(created.body.machine.id),
      capacityKind: 'free_hand',
      capacityKgf: 35000,
    });
    assert.equal(withFigure.body.machine.capacityKgf, null);

    // A kind nobody defined is a 400, not a machine filed under nonsense.
    const nonsense = await saveMachine(ctx, {
      name: 'Odd',
      groupId: type.id,
      capacityKind: 'enormous',
      status: 'active',
      primaryPhotoUrl: '',
    });
    assert.equal(nonsense.status, 400, JSON.stringify(nonsense.body));
  } finally {
    await closeServer(ctx.server);
  }
});

test('a save that says nothing about the sheet keeps it', async () => {
  const ctx = await boot('paper-machine-preserve-', 'machine-preserve@paper.local');
  try {
    const type = await makeType(ctx, 'Power Press');
    const created = await saveMachine(ctx, {
      name: 'Press 4',
      groupId: type.id,
      machineMake: 'Mayank',
      manufacturedYear: 2011,
      feederMake: 'Jay Shanti',
      runningHours: 5001,
      strokesPerMinute: 110,
      capacityKind: 'rated',
      capacityKgf: 35000,
      dieFeedType: 'Progressive',
      status: 'active',
      primaryPhotoUrl: '',
      reportNotes: 'Grease the ram weekly',
    });
    assert.equal(created.status, 200, JSON.stringify(created.body));
    const id = String(created.body.machine.id);

    // The Machines screen saving a note, mentioning none of the sheet. Before
    // this change that blanked every column it left out.
    const quiet = await saveMachine(ctx, { id, reportNotes: 'Grease twice' });
    assert.equal(quiet.status, 200, JSON.stringify(quiet.body));
    const after = quiet.body.machine;
    assert.equal(after.reportNotes, 'Grease twice');
    assert.equal(after.name, 'Press 4');
    assert.equal(after.assetId, 'PP-1');
    assert.equal(after.machineMake, 'Mayank');
    assert.equal(after.manufacturedYear, 2011);
    assert.equal(after.feederMake, 'Jay Shanti');
    assert.equal(after.runningHours, 5001);
    assert.equal(after.strokesPerMinute, 110);
    assert.equal(after.capacityKgf, 35000);
    assert.equal(after.dieFeedType, 'Progressive');

    // Clearing still works — '' is a value, absence is not.
    const cleared = await saveMachine(ctx, { id, machineMake: '' });
    assert.equal(cleared.body.machine.machineMake, '');
    assert.equal(cleared.body.machine.feederMake, 'Jay Shanti');

    // And an update naming a machine that is not there says so.
    const missing = await saveMachine(ctx, { id: '999999', reportNotes: 'nope' });
    assert.equal(missing.status, 404, JSON.stringify(missing.body));
  } finally {
    await closeServer(ctx.server);
  }
});

test('a taken machine number is refused by name, with a free one offered', async () => {
  const ctx = await boot('paper-machine-clash-', 'machine-clash@paper.local');
  try {
    const type = await makeType(ctx, 'Power Press');
    const first = await saveMachine(ctx, {
      name: 'Press 1',
      groupId: type.id,
      status: 'active',
      primaryPhotoUrl: '',
    });
    assert.equal(first.body.machine.assetId, 'PP-1');

    // Typing a number another machine holds.
    const clash = await saveMachine(ctx, {
      name: 'Press 2',
      assetId: 'PP-1',
      groupId: type.id,
      status: 'active',
      primaryPhotoUrl: '',
    });
    assert.equal(clash.status, 409, JSON.stringify(clash.body));
    assert.equal(clash.body.code, 'machine_asset_id_duplicate');
    // The series is a run of numbers, so the offer is the next number — not
    // "PP-1-2", which would read as a machine that does not exist.
    assert.equal(clash.body.suggestedAssetId, 'PP-2');
    assert.match(clash.body.error, /already used by machine #/);

    // Taking the offer works, and the next clash moves on again.
    const second = await saveMachine(ctx, {
      name: 'Press 2',
      assetId: 'PP-2',
      groupId: type.id,
      status: 'active',
      primaryPhotoUrl: '',
    });
    assert.equal(second.status, 200, JSON.stringify(second.body));
    assert.equal(
      await nextFreeMachineNo('PP-1', { get: ctx.backend.get }),
      'PP-3',
    );

    // A machine keeping its own number is not a clash with itself.
    const renamed = await saveMachine(ctx, {
      id: String(first.body.machine.id),
      assetId: 'PP-1',
      machineMake: 'SKA',
    });
    assert.equal(renamed.status, 200, JSON.stringify(renamed.body));
    assert.equal(renamed.body.machine.machineMake, 'SKA');
  } finally {
    await closeServer(ctx.server);
  }
});

test('a part carries the whole sheet of every machine it runs on', async () => {
  const ctx = await boot('paper-machine-on-part-', 'machine-part@paper.local');
  try {
    const press = await makeType(ctx, 'Power Press');
    const punch = await makeType(ctx, 'Punching M');

    const one = await saveMachine(ctx, {
      name: 'Press 4',
      groupId: press.id,
      machineMake: 'Mayank',
      capacityKind: 'rated',
      capacityKgf: 35000,
      strokesPerMinute: 110,
      status: 'active',
      primaryPhotoUrl: '',
    });
    const two = await saveMachine(ctx, {
      name: 'Punch 1',
      groupId: punch.id,
      machineMake: 'SKA',
      status: 'active',
      primaryPhotoUrl: '',
    });

    const items = await fetch(`${ctx.baseUrl}/api/items`, { headers: ctx.headers })
      .then((r) => r.json());
    const part = items.items[0];
    assert.ok(part, 'the demo seed should leave at least one item');

    const linked = await fetch(`${ctx.baseUrl}/api/items/${part.id}`, {
      method: 'PATCH',
      headers: ctx.headers,
      body: JSON.stringify({
        name: part.name,
        displayName: part.displayName,
        groupId: part.groupId,
        unitId: part.unitId,
        machineIds: [one.body.machine.id, two.body.machine.id],
      }),
    });
    assert.equal(linked.status, 200, await linked.clone().text());
    const machines = (await linked.json()).item.machines;
    assert.equal(machines.length, 2);

    const pressRow = machines.find((row) => row.assetId === 'PP-1');
    assert.ok(pressRow, 'the press is on the part');
    // The whole sheet, so the screen listing them can say what tells them
    // apart without a second fetch.
    assert.equal(pressRow.machineType, 'Power Press');
    assert.equal(pressRow.machineMake, 'Mayank');
    assert.equal(pressRow.capacityKgf, 35000);
    assert.equal(pressRow.strokesPerMinute, 110);
    assert.equal(machines.find((row) => row.assetId === 'PM-1').machineType, 'Punching M');
  } finally {
    await closeServer(ctx.server);
  }
});

test('capabilities are stored, and a save that leaves them out keeps them', async () => {
  // The form's Capabilities section was sent on every save and read nowhere:
  // there was no column, so it was empty on the next load.
  const ctx = await boot('paper-machine-capabilities-', 'machine-caps@paper.local');
  try {
    const type = await makeType(ctx, 'Hydraulic Press');
    const capabilities = [{ name: 'Blanking', maxThicknessMm: 3 }];
    const created = await saveMachine(ctx, {
      name: 'Press 9',
      groupId: type.id,
      status: 'active',
      capabilities,
    });
    assert.equal(created.status, 200, JSON.stringify(created.body));
    assert.deepEqual(created.body.machine.capabilities, capabilities);

    const quiet = await saveMachine(ctx, {
      id: created.body.machine.id,
      name: 'Press 9',
      groupId: type.id,
      status: 'active',
    });
    assert.deepEqual(quiet.body.machine.capabilities, capabilities);
  } finally {
    await closeServer(ctx.server);
  }
});
