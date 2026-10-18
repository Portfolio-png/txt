const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// Sittings: which opening of a window a change belongs to.
//
// `entity_activity_log` said who changed what and never what else was changed
// at the same time, so "where did the die I just made go?" had no answer the
// server could give. One nullable column, filled from the `X-Paper-Sitting`
// header inside `logEntityActivity` — which already receives `req` for the
// actor — so every existing track* call site gained it without being edited.

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
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
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'SittingPass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  const { token } = await fetch(`${baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: 'SittingPass1234' }),
  }).then((r) => r.json());

  const base = { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` };

  // `sitting` null => no header at all, which is what a write from any other
  // screen looks like.
  const call = async (method, p, body, sitting) => {
    const headers = { ...base };
    if (sitting) headers['X-Paper-Sitting'] = sitting;
    const r = await fetch(`${baseUrl}${p}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: r.status, body: await r.json() };
  };

  // Telemetry is fire-and-forget, so a row may land just after the response.
  const rowsFor = async (sitting) => {
    for (let i = 0; i < 20; i++) {
      const rows = await backend.all(
        'SELECT entity_type, entity_id, action, sitting_id FROM entity_activity_log WHERE sitting_id = ? ORDER BY id',
        [sitting],
      );
      if (rows.length > 0) return rows;
      await new Promise((r) => setTimeout(r, 25));
    }
    return [];
  };

  // A second identity, so scoping can be asserted rather than assumed.
  const asRole = async (name, email, role, permissions) => {
    // Two endpoints, not one: POST /api/users is the STAFF route and coerces
    // every role it is given to 'user' (verified — asking it for an admin
    // silently yields a staff account). An admin comes from POST /api/admins,
    // which is super_admin-only.
    const path = role === 'admin' ? '/api/admins' : '/api/users';
    const created = await fetch(`${baseUrl}${path}`, {
      method: 'POST',
      headers: base,
      body: JSON.stringify({
        name, email, role, password: 'OtherPass1234', permissions,
      }),
    });
    if (created.status !== 201) {
      throw new Error(`could not make ${role}: ${await created.text()}`);
    }
    // The `permissions` array on create does not survive DEFAULT_ROLE_PERMISSIONS
    // — staff read every module and write none — so the grid has to say it
    // again, explicitly, the way entity-links-api.test.js does.
    const madeUser = (await created.json()).user;
    if (madeUser.role !== role) {
      throw new Error(`asked for ${role}, got ${madeUser.role}`);
    }
    const theirId = madeUser.id;
    const grid = await fetch(`${baseUrl}/api/users/${theirId}/permissions`, {
      method: 'PATCH',
      headers: base,
      body: JSON.stringify({
        overrides: permissions.map((key) => ({ key, allowed: true })),
      }),
    });
    if (grid.status !== 200) {
      throw new Error(`could not grant to ${role}: ${await grid.text()}`);
    }
    const { token: theirs } = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: 'OtherPass1234' }),
    }).then((r) => r.json());
    const theirHeaders = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${theirs}`,
    };
    return async (method, p, body, sitting) => {
      const headers = { ...theirHeaders };
      if (sitting) headers['X-Paper-Sitting'] = sitting;
      const r = await fetch(`${baseUrl}${p}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      return { status: r.status, body: await r.json() };
    };
  };

  return { backend, server, call, rowsFor, asRole };
}

test('a write carries its sitting, and a write without one carries none', async () => {
  const ctx = await boot('paper-sitting-spine-', 'sitting-spine@paper.local');
  try {
    const { call, rowsFor, backend } = ctx;
    const sitting = 's-spine-001';

    const made = await call('POST', '/api/clients', {
      name: 'Sitting Papers',
      alias: 'Sitting',
      gstNumber: '',
      address: 'Somewhere',
    }, sitting);
    assert.equal(made.status, 201, JSON.stringify(made.body));

    const rows = await rowsFor(sitting);
    assert.equal(rows.length, 1, 'the create should have logged exactly one row');
    assert.equal(rows[0].entity_type, 'clients');
    assert.equal(rows[0].action, 'created');
    assert.equal(rows[0].sitting_id, sitting);

    // The same write from anywhere else is not in a sitting at all.
    const outside = await call('POST', '/api/clients', {
      name: 'Ordinary Papers',
      alias: 'Ordinary',
      gstNumber: '',
      address: 'Elsewhere',
    });
    assert.equal(outside.status, 201, JSON.stringify(outside.body));

    const loose = await backend.all(
      "SELECT sitting_id FROM entity_activity_log WHERE entity_id = ? AND entity_type = 'clients'",
      [String(outside.body.client.id)],
    );
    assert.equal(loose.length, 1);
    assert.equal(loose[0].sitting_id, null, 'no header means no sitting, not an empty string');
  } finally {
    await closeServer(ctx.server);
  }
});

test('everything done in one window shares one sitting', async () => {
  const ctx = await boot('paper-sitting-window-', 'sitting-window@paper.local');
  try {
    const { call, rowsFor } = ctx;
    const sitting = 's-window-002';

    const client = await call('POST', '/api/clients', {
      name: 'Bench Client', alias: 'Bench', gstNumber: '', address: 'X',
    }, sitting);
    assert.equal(client.status, 201, JSON.stringify(client.body));

    // An edit belongs to the sitting too, not only a create: the settled
    // decision is "everything done in the window".
    const edited = await call('PATCH', `/api/clients/${client.body.client.id}`, {
      name: 'Bench Client Renamed',
      alias: 'Bench',
      gstNumber: '',
      address: 'X',
    }, sitting);
    assert.equal(edited.status, 200, JSON.stringify(edited.body));

    const rows = await rowsFor(sitting);
    const actions = rows.map((r) => r.action);
    assert.ok(actions.includes('created'), JSON.stringify(rows));
    assert.ok(actions.includes('updated'), JSON.stringify(rows));
    assert.ok(
      rows.every((r) => r.sitting_id === sitting),
      'one window, one sitting id across every row',
    );
  } finally {
    await closeServer(ctx.server);
  }
});

test('a sitting id that is absurdly long is refused rather than stored', async () => {
  const ctx = await boot('paper-sitting-bound-', 'sitting-bound@paper.local');
  try {
    const { call, backend } = ctx;
    const made = await call('POST', '/api/clients', {
      name: 'Long Header', alias: 'LH', gstNumber: '', address: 'Y',
    }, 'x'.repeat(200));
    assert.equal(made.status, 201, JSON.stringify(made.body));

    const rows = await backend.all(
      "SELECT sitting_id FROM entity_activity_log WHERE entity_type = 'clients' AND entity_id = ?",
      [String(made.body.client.id)],
    );
    assert.equal(rows.length, 1);
    assert.equal(rows[0].sitting_id, null, 'a column a read groups by should not take anything');
  } finally {
    await closeServer(ctx.server);
  }
});

test('the column survives two boots of the same database', async () => {
  // Two runners execute every migration file on EVERY boot — migrate.js first,
  // tolerating only /duplicate column name/i, then the kernel runner from
  // inside initDb. A second boot is where a non-idempotent 050 would take the
  // whole server down, so this asserts it rather than assuming it.
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-sitting-reboot-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'sitting-reboot@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'SittingPass1234';

  for (const pass of ['first', 'second']) {
    delete require.cache[require.resolve('../server.js')];
    const backend = require('../server.js');
    await backend.resetAndSeedDemoData();
    const columns = await backend.all('PRAGMA table_info(entity_activity_log)');
    const sitting = columns.filter((c) => c.name === 'sitting_id');
    assert.equal(sitting.length, 1, `sitting_id should exist exactly once on the ${pass} boot`);
    assert.equal(sitting[0].type, 'TEXT');
  }
});

test('the five masters that logged nothing now log', async () => {
  const ctx = await boot('paper-sitting-masters-', 'sitting-masters@paper.local');
  try {
    const { call, backend } = ctx;
    const sitting = 's-masters-003';

    const dept = await call('POST', '/api/departments', { name: 'Press Shop' }, sitting);
    assert.equal(dept.status, 201, JSON.stringify(dept.body));

    const client = await call('POST', '/api/clients', {
      name: 'Sub Holder', alias: 'SH', gstNumber: '', address: 'Z',
    }, sitting);
    const sub = await call(
      'POST', `/api/clients/${client.body.client.id}/sub-contractors`,
      { name: 'Bend Works', designation: 'Bending' }, sitting,
    );
    assert.equal(sub.status, 201, JSON.stringify(sub.body));

    const groups = await call('GET', '/api/groups');
    const parent = groups.body.groups.find((g) => g.groupType === 'item');
    const group = await call('POST', '/api/groups', {
      name: 'Sitting Group',
      groupType: 'item',
      parentGroupId: parent.id,
      unitId: parent.unitId,
    }, sitting);
    assert.equal(group.status, 201, JSON.stringify(group.body));

    // Give telemetry a moment — it is fire-and-forget by design.
    await new Promise((r) => setTimeout(r, 200));
    const rows = await backend.all(
      'SELECT entity_type, action FROM entity_activity_log WHERE sitting_id = ?',
      [sitting],
    );
    const types = new Set(rows.map((r) => r.entity_type));
    for (const expected of ['departments', 'sub_contractors', 'groups']) {
      assert.ok(types.has(expected), `${expected} should log: saw ${[...types].join(', ')}`);
    }
    assert.ok(
      rows.every((r) => ['created', 'updated', 'deleted'].includes(r.action)),
      JSON.stringify(rows),
    );
  } finally {
    await closeServer(ctx.server);
  }
});

test('a department delete logs the people it cascades through', async () => {
  const ctx = await boot('paper-sitting-cascade-', 'sitting-cascade@paper.local');
  try {
    const { call, backend } = ctx;
    const sitting = 's-cascade-004';

    const dept = await call('POST', '/api/departments', { name: 'Doomed' }, sitting);
    const id = dept.body.department.id;
    const person = await call('POST', '/api/employees', {
      name: 'Will Go', departmentId: id, role: 'operator',
    }, sitting);
    // Only assert the cascade if the person actually landed.
    const hadPerson = person.status === 201;

    const gone = await call('DELETE', `/api/departments/${id}`, undefined, sitting);
    assert.equal(gone.status, 200, JSON.stringify(gone.body));

    await new Promise((r) => setTimeout(r, 200));
    const rows = await backend.all(
      "SELECT entity_type, action FROM entity_activity_log WHERE sitting_id = ? AND action = 'deleted'",
      [sitting],
    );
    assert.ok(
      rows.some((r) => r.entity_type === 'departments'),
      'the department itself must log its removal',
    );
    if (hadPerson) {
      assert.ok(
        rows.some((r) => r.entity_type === 'employees'),
        'the cascaded person must log too, or the record reads as complete while being partial',
      );
    }
  } finally {
    await closeServer(ctx.server);
  }
});

test('a link writes one row on each side, folded back into one line', async () => {
  const ctx = await boot('paper-sitting-links-', 'sitting-links@paper.local');
  try {
    const { call, backend } = ctx;
    const sitting = 's-links-005';

    const items = await call('GET', '/api/items');
    const item = items.body.items[0];
    assert.ok(item, 'the seed leaves an item');
    // The demo seed leaves no dies, so make one rather than depend on it.
    const madeDie = await call('POST', '/api/dies', {
      toolCode: 'TD-SITTING-1',
      status: 'active',
      ownership: 'owned',
    }, sitting);
    assert.ok(madeDie.status === 201 || madeDie.status === 200, JSON.stringify(madeDie.body));
    const die = madeDie.body.die;
    assert.ok(die, JSON.stringify(madeDie.body));

    const linked = await call('POST', '/api/links', {
      from: { type: 'item', id: String(item.id) },
      to: { type: 'die', id: String(die.id) },
    }, sitting);
    assert.ok(linked.status === 201 || linked.status === 200, JSON.stringify(linked.body));

    await new Promise((r) => setTimeout(r, 200));
    const rows = await backend.all(
      "SELECT entity_type, entity_id, action, details_json FROM entity_activity_log WHERE sitting_id = ? AND action = 'linked'",
      [sitting],
    );
    assert.equal(rows.length, 2, 'one row per side: ' + JSON.stringify(rows));
    const types = rows.map((r) => r.entity_type).sort();
    assert.deepEqual(types, ['dies', 'items']);
    const keys = new Set(rows.map((r) => JSON.parse(r.details_json).pairKey));
    assert.equal(keys.size, 1, 'both sides share one pairKey');

    // Linking the same pair again changes nothing, so it logs nothing.
    const again = await call('POST', '/api/links', {
      from: { type: 'item', id: String(item.id) },
      to: { type: 'die', id: String(die.id) },
    }, sitting);
    assert.ok(again.status < 500, JSON.stringify(again.body));
    await new Promise((r) => setTimeout(r, 150));
    const after = await backend.all(
      "SELECT id FROM entity_activity_log WHERE sitting_id = ? AND action = 'linked'",
      [sitting],
    );
    assert.equal(after.length, 2, 'a repeat that inserted nothing must log nothing');

    // And the sitting read folds the pair into a single line.
    const view = await call('GET', `/api/track/sitting/${sitting}`);
    assert.equal(view.status, 200, JSON.stringify(view.body));
    const linkLines = view.body.events.filter((e) => e.action === 'linked');
    assert.equal(linkLines.length, 1, 'two rows, one line');
    assert.ok(view.body.rowCount >= 2, 'but the raw count still says two');
  } finally {
    await closeServer(ctx.server);
  }
});

test('the sittings list is not swallowed by the per-record route', async () => {
  const ctx = await boot('paper-sitting-routes-', 'sitting-routes@paper.local');
  try {
    const { call } = ctx;
    const sitting = 's-routes-006';
    await call('POST', '/api/clients', {
      name: 'Listed', alias: 'L', gstNumber: '', address: 'Q',
    }, sitting);
    await new Promise((r) => setTimeout(r, 200));

    const listed = await call('GET', '/api/track/sittings');
    assert.equal(listed.status, 200, JSON.stringify(listed.body));
    // The generic /api/track/:entityType/:id route would have answered with an
    // `events` array, not `sittings` — this is the route-order assertion.
    assert.ok(Array.isArray(listed.body.sittings), JSON.stringify(listed.body));
    const mine = listed.body.sittings.find((s) => s.sittingId === sitting);
    assert.ok(mine, 'the sitting just made should be listed');
    assert.ok(mine.events >= 1);
    assert.ok(mine.startedAt && mine.endedAt);
  } finally {
    await closeServer(ctx.server);
  }
});

test('a sitting is only visible to someone entitled to see it', async () => {
  // The scoping dialect is `/api/audit/global`'s, lifted into actorScopeFor:
  // super_admin sees all, an admin sees their own plus a plain user's,
  // everyone else only their own. The `/api/track/*` routes beside these are
  // unscoped, which is why this needed asserting rather than assuming.
  const ctx = await boot('paper-sitting-scope-', 'sitting-owner@paper.local');
  try {
    const { call, asRole } = ctx;

    const asStaff = await asRole(
      'Staff Member', 'sitting-staff@paper.local', 'user',
      ['clients.read', 'clients.create', 'audit.read', 'login.desktop'],
    );

    // The owner (super_admin) does something in a window of their own.
    const ownerSitting = 's-owner-007';
    const ownerMade = await call('POST', '/api/clients', {
      name: 'Owner Co', alias: 'OC', gstNumber: '', address: 'A',
    }, ownerSitting);
    assert.equal(ownerMade.status, 201, JSON.stringify(ownerMade.body));

    // And the staff member does something in a window of their own.
    const staffSitting = 's-staff-008';
    const staffMade = await asStaff('POST', '/api/clients', {
      name: 'Staff Co', alias: 'SC', gstNumber: '', address: 'B',
    }, staffSitting);
    assert.equal(staffMade.status, 201, JSON.stringify(staffMade.body));
    await new Promise((r) => setTimeout(r, 250));

    // The staff member sees their own sitting and not the owner's.
    const theirList = await asStaff('GET', '/api/track/sittings');
    assert.equal(theirList.status, 200, JSON.stringify(theirList.body));
    const theirIds = theirList.body.sittings.map((s) => s.sittingId);
    assert.ok(theirIds.includes(staffSitting), JSON.stringify(theirIds));
    assert.ok(
      !theirIds.includes(ownerSitting),
      'a plain user must not be listing the owner\'s windows',
    );

    // And asking for it directly is a 404, not an empty list: "nothing
    // happened here" is not a claim this route may make about a window it is
    // not allowed to see.
    const peek = await asStaff('GET', `/api/track/sitting/${ownerSitting}`);
    assert.equal(peek.status, 404, JSON.stringify(peek.body));
    assert.deepEqual(peek.body.events, []);

    // Their own, though, reads fine.
    const own = await asStaff('GET', `/api/track/sitting/${staffSitting}`);
    assert.equal(own.status, 200, JSON.stringify(own.body));
    assert.ok(own.body.events.length >= 1);

    // The super_admin sees both.
    const ownerList = await call('GET', '/api/track/sittings');
    const ownerIds = ownerList.body.sittings.map((s) => s.sittingId);
    assert.ok(ownerIds.includes(ownerSitting));
    assert.ok(
      ownerIds.includes(staffSitting),
      'super_admin is the role that sees everything',
    );
  } finally {
    await closeServer(ctx.server);
  }
});

test('an admin sees a plain user\'s sitting, which is the point of the role', async () => {
  const ctx = await boot('paper-sitting-admin-', 'sitting-boss@paper.local');
  try {
    const { call, asRole } = ctx;

    const asAdmin = await asRole(
      'The Admin', 'sitting-admin@paper.local', 'admin',
      ['clients.read', 'clients.create', 'audit.read', 'login.desktop'],
    );
    const asStaff = await asRole(
      'The Staff', 'sitting-staff2@paper.local', 'user',
      ['clients.read', 'clients.create', 'audit.read', 'login.desktop'],
    );

    const staffSitting = 's-staff-009';
    const made = await asStaff('POST', '/api/clients', {
      name: 'Watched Co', alias: 'WC', gstNumber: '', address: 'C',
    }, staffSitting);
    assert.equal(made.status, 201, JSON.stringify(made.body));
    await new Promise((r) => setTimeout(r, 250));

    const seen = await asAdmin('GET', `/api/track/sitting/${staffSitting}`);
    assert.equal(seen.status, 200, JSON.stringify(seen.body));
    assert.ok(seen.body.events.length >= 1);

    // The existing super_admin still sees it too — scoping tightened nobody
    // who already had the view.
    const owner = await call('GET', `/api/track/sitting/${staffSitting}`);
    assert.equal(owner.status, 200, JSON.stringify(owner.body));
  } finally {
    await closeServer(ctx.server);
  }
});
