const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// Groups carried no realtime signal at all. A group another user created,
// renamed, deleted or filled with variants stayed invisible until someone
// reloaded — and with two or three people filing variants at once that is the
// difference between one shared catalogue and three diverging ones.
//
// The signal goes through the changelog rather than a bare socket emit: that is
// what feeds the desktop's SSE stream, and it is persisted, so a client that
// was asleep replays what it missed instead of silently staying stale.
//
// Filing items into a group is the case that matters most, and it is two
// changes, not one: the group's membership moved, and so did
// `combinationGroupIds` on every item that joined — which is what the group
// sidebar actually lists.

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

test('group writes reach the changelog the clients read', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-group-rt-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'rt@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const loginResponse = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'rt@paper.local',
        password: 'OwnerPass1234',
      }),
    });
    const { token } = await loginResponse.json();
    const authHeaders = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    };
    const send = async (method, route, body) => {
      const response = await fetch(`${baseUrl}${route}`, {
        method,
        headers: authHeaders,
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      return { status: response.status, body: await response.json() };
    };

    // The changelog is the wire. Reading it directly is how a client's SSE
    // stream sees these, replay included.
    const changesSince = async (afterId, table) => {
      const rows = await backend.all(
        'SELECT id, table_name, record_id, event_type FROM changelog WHERE id > ? ORDER BY id ASC',
        [afterId],
      );
      return rows.filter((row) => !table || row.table_name === table);
    };
    const head = async () => {
      const row = await backend.get('SELECT MAX(id) AS maxId FROM changelog');
      return Number(row?.maxId || 0);
    };

    const groups = (await send('GET', '/api/groups')).body.groups;
    const home = groups.find(
      (group) =>
        group.groupType === 'item' && group.groupStructure !== 'combination',
    );
    const unitId = (await send('GET', '/api/units')).body.units[0].id;

    // --- create ---
    let mark = await head();
    const combo = await send('POST', '/api/groups', {
      name: 'Realtime Set',
      groupType: 'item',
      groupStructure: 'combination',
      description: '',
    });
    assert.equal(combo.status, 201, JSON.stringify(combo.body));
    const comboId = combo.body.group.id;
    let logged = await changesSince(mark, 'groups');
    assert.deepEqual(
      logged.map((row) => [row.record_id, row.event_type]),
      [[comboId, 'INSERT']],
      'creating a group announces itself',
    );

    // --- rename ---
    mark = await head();
    const renamed = await send('PATCH', `/api/groups/${comboId}`, {
      name: 'Realtime Set Renamed',
      groupType: 'item',
      groupStructure: 'combination',
      description: '',
      parentGroupId: null,
    });
    assert.equal(renamed.status, 200, JSON.stringify(renamed.body));
    logged = await changesSince(mark, 'groups');
    assert.deepEqual(logged.map((row) => [row.record_id, row.event_type]), [
      [comboId, 'UPDATE'],
    ]);

    // --- filing items in: the group AND every item that joined ---
    const first = await send('POST', '/api/items', {
      name: 'Realtime Item A',
      groupId: home.id,
      unitId,
      variationTree: [],
    });
    const second = await send('POST', '/api/items', {
      name: 'Realtime Item B',
      groupId: home.id,
      unitId,
      variationTree: [],
    });
    const memberIds = [first.body.item.id, second.body.item.id];

    mark = await head();
    const assigned = await send('POST', `/api/groups/${comboId}/items`, {
      itemIds: memberIds,
    });
    assert.equal(assigned.status, 201, JSON.stringify(assigned.body));

    logged = await changesSince(mark, 'groups');
    assert.deepEqual(
      logged.map((row) => [row.record_id, row.event_type]),
      [[comboId, 'UPDATE']],
      'the group says its membership moved',
    );

    const itemChanges = await changesSince(mark, 'items');
    assert.deepEqual(
      itemChanges.map((row) => row.record_id).sort((a, b) => a - b),
      [...memberIds].sort((a, b) => a - b),
      'and every item that joined says so too — the sidebar reads the items, '
        + 'so without this the group keeps rendering as empty',
    );
    assert.ok(
      itemChanges.every((row) => row.event_type === 'UPDATE'),
      'joining a group updates an item, it does not create one',
    );

    // --- delete ---
    // Deletion already announced itself before any of this work: the delete
    // port logs its own row. What was missing was a client that listened for
    // table_name 'groups' at all. Asserted as exactly one row, because adding a
    // second emit here would make every client refresh twice per deletion.
    mark = await head();
    const deleted = await send('DELETE', `/api/groups/${comboId}`);
    assert.equal(deleted.status, 200, JSON.stringify(deleted.body));
    logged = await changesSince(mark, 'groups');
    assert.deepEqual(logged.map((row) => [row.record_id, row.event_type]), [
      [comboId, 'DELETE'],
    ]);
  } finally {
    await closeServer(server);
  }
});
