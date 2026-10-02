const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// The generic link graph (modules/links/*): one row per link, read from either
// end, over both the generic store and the two legacy item link tables.
//
// The behaviour worth pinning is the symmetry — that asking from the die's
// side returns the link the item's side stored — because that is the thing
// item_dies alone could never answer, and the thing a canonical-ordering bug
// would break silently in one direction only.

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

test('links are one row readable from either end', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-entity-links-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'links-owner@paper.local';
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
        email: 'links-owner@paper.local',
        password: 'OwnerPass1234',
      }),
    });
    const { token } = await loginResponse.json();
    assert.ok(token, 'expected a login token');
    const authHeaders = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    };
    const getJson = async (p) => {
      const r = await fetch(`${baseUrl}${p}`, { headers: authHeaders });
      return { status: r.status, body: await r.json() };
    };
    const sendJson = async (method, p, payload) => {
      const r = await fetch(`${baseUrl}${p}`, {
        method,
        headers: authHeaders,
        body: payload === undefined ? undefined : JSON.stringify(payload),
      });
      return { status: r.status, body: await r.json() };
    };

    // --- the catalog the column UI builds its menus from ---
    const schema = await getJson('/api/links/schema');
    assert.equal(schema.status, 200);
    const schemaTypes = schema.body.types.map((entry) => entry.type);
    for (const expected of ['item', 'die', 'machine']) {
      assert.ok(schemaTypes.includes(expected), `schema missing ${expected}`);
    }
    assert.ok(
      schema.body.types.every((entry) => entry.label && entry.plural),
      'every schema type needs a label and a plural for its column header',
    );

    // --- the first column: a master listed on its own ---
    const browse = await getJson('/api/links/item?limit=5');
    assert.equal(browse.status, 200);
    assert.ok(browse.body.records.length > 0, 'expected items to browse');
    assert.ok(
      browse.body.records.length <= 5,
      'the listing honours its limit, so a column can page',
    );
    assert.ok(
      browse.body.records.every((record) => record.type === 'item' && record.id),
      'every browsed record names its own type, so a column can act on it',
    );
    assert.equal(
      (await getJson('/api/links/teapot')).status,
      400,
      'browsing a master that does not exist is refused by name',
    );

    // --- the records to link ---
    const items = await getJson('/api/items');
    const itemA = items.body.items[0];
    const itemB = items.body.items[1];
    assert.ok(itemA && itemB, 'expected at least two seeded items');

    const dieOne = await sendJson('POST', '/api/dies', {
      toolCode: 'DIE-LINK-1',
      status: 'active',
      ownership: 'owned',
      storageLocation: 'Rack 4',
    });
    assert.equal(dieOne.status, 200);
    const dieTwo = await sendJson('POST', '/api/dies', {
      toolCode: 'DIE-LINK-2',
      status: 'active',
      ownership: 'owned',
    });
    const dieOneId = String(dieOne.body.die?.id ?? dieOne.body.id);
    const dieTwoId = String(dieTwo.body.die?.id ?? dieTwo.body.id);
    assert.ok(dieOneId && dieOneId !== 'undefined', 'expected a created die id');

    const machine = await sendJson('POST', '/api/machines', {
      name: 'Link Press',
      assetId: 'MACH-LINK-1',
      status: 'operational',
    });
    const machineId = String(machine.body.machine?.id ?? machine.body.id);
    assert.ok(machineId && machineId !== 'undefined', 'expected a machine id');

    // --- more than one die on one item ---
    const linkDieOne = await sendJson('POST', '/api/links', {
      from: { type: 'item', id: itemA.id },
      to: { type: 'die', id: dieOneId },
    });
    assert.equal(linkDieOne.status, 201);
    assert.equal(
      linkDieOne.body.link.store,
      'item_dies',
      'item <-> die must keep living in its own table, not be copied',
    );
    const linkDieTwo = await sendJson('POST', '/api/links', {
      from: { type: 'item', id: itemA.id },
      to: { type: 'die', id: dieTwoId },
    });
    assert.equal(linkDieTwo.status, 201);

    const itemLinks = await getJson(`/api/links/item/${itemA.id}`);
    assert.equal(itemLinks.status, 200);
    const dieGroup = itemLinks.body.groups.find((g) => g.type === 'die');
    assert.equal(dieGroup.count, 2, 'both dies belong to the item');
    assert.deepEqual(
      dieGroup.links.map((link) => link.label).sort(),
      ['DIE-LINK-1', 'DIE-LINK-2'],
    );
    assert.equal(
      dieGroup.links.find((link) => link.label === 'DIE-LINK-1').subtitle,
      'Rack 4',
      'the die column shows its storage location as the second line',
    );

    // --- the direction item_dies alone could never answer ---
    const dieLinks = await getJson(`/api/links/die/${dieOneId}`);
    assert.equal(dieLinks.status, 200);
    assert.equal(dieLinks.body.entity.label, 'DIE-LINK-1');
    const itemsOfDie = dieLinks.body.groups.find((g) => g.type === 'item');
    assert.ok(itemsOfDie, 'a die must list the items it makes');
    assert.deepEqual(
      itemsOfDie.links.map((link) => String(link.id)),
      [String(itemA.id)],
    );

    // --- a pair with no legacy table of its own: die <-> machine ---
    const dieMachine = await sendJson('POST', '/api/links', {
      from: { type: 'die', id: dieOneId },
      to: { type: 'machine', id: machineId },
    });
    assert.equal(dieMachine.status, 201);
    assert.equal(dieMachine.body.link.store, 'entity_links');

    const fromMachine = await getJson(`/api/links/machine/${machineId}`);
    const diesOfMachine = fromMachine.body.groups.find((g) => g.type === 'die');
    assert.deepEqual(
      diesOfMachine.links.map((link) => link.label),
      ['DIE-LINK-1'],
      'the machine lists the die, from the row the die stored',
    );

    // --- posting the same pair the other way round is the same row ---
    const flipped = await sendJson('POST', '/api/links', {
      from: { type: 'machine', id: machineId },
      to: { type: 'die', id: dieOneId },
    });
    assert.equal(flipped.status, 201);
    const afterFlip = await getJson(`/api/links/die/${dieOneId}`);
    assert.equal(
      afterFlip.body.groups.find((g) => g.type === 'machine').count,
      1,
      'linking B to A after A to B must not make a second link',
    );

    // --- what it could still be linked to ---
    const candidates = await getJson(
      `/api/links/item/${itemA.id}/candidates?type=die`,
    );
    assert.equal(candidates.status, 200);
    assert.deepEqual(
      candidates.body.candidates.filter((c) =>
        [dieOneId, dieTwoId].includes(c.id),
      ),
      [],
      'a die already linked is not offered again',
    );
    const searched = await getJson(
      `/api/links/machine/${machineId}/candidates?type=item&q=${encodeURIComponent(itemB.name)}`,
    );
    assert.ok(
      searched.body.candidates.some((c) => String(c.id) === String(itemB.id)),
      'the candidate search finds an item by name',
    );
    const selfCandidates = await getJson(
      `/api/links/item/${itemA.id}/candidates?type=item`,
    );
    assert.ok(
      selfCandidates.body.candidates.every(
        (c) => String(c.id) !== String(itemA.id),
      ),
      'a record is never offered as a candidate for itself',
    );

    // --- refusals ---
    assert.equal(
      (await sendJson('POST', '/api/links', {
        from: { type: 'item', id: itemA.id },
        to: { type: 'item', id: itemA.id },
      })).status,
      400,
      'a record cannot be linked to itself',
    );
    assert.equal(
      (await sendJson('POST', '/api/links', {
        from: { type: 'item', id: itemA.id },
        to: { type: 'teapot', id: '1' },
      })).status,
      400,
      'an unknown master is refused by name',
    );
    assert.equal(
      (await sendJson('POST', '/api/links', {
        from: { type: 'item', id: itemA.id },
        to: { type: 'die', id: '999999' },
      })).status,
      404,
      'a link to an id with no record behind it is refused, not stored',
    );
    assert.equal((await getJson('/api/links/item/999999')).status, 404);

    // --- the item DTO still carries what the links API attached ---
    const itemAfter = await getJson(`/api/items/${itemA.id}`);
    assert.deepEqual(
      itemAfter.body.item.dies.map((die) => die.toolCode).sort(),
      ['DIE-LINK-1', 'DIE-LINK-2'],
      'a die attached through /api/links shows up on the item itself',
    );

    // --- unlinking, from the end that did not create the link ---
    const unlink = await sendJson(
      'DELETE',
      `/api/links/die/${dieTwoId}/item/${itemA.id}`,
    );
    assert.equal(unlink.status, 200);
    const afterUnlink = await getJson(`/api/links/item/${itemA.id}`);
    assert.equal(
      afterUnlink.body.groups.find((g) => g.type === 'die').count,
      1,
    );
    assert.equal(
      (await sendJson('DELETE', `/api/links/die/${dieTwoId}/item/${itemA.id}`))
        .status,
      404,
      'unlinking what is not linked says so',
    );

    // --- a deleted record takes its links with it ---
    assert.equal(
      (await sendJson('DELETE', `/api/links/die/${dieOneId}/machine/${machineId}`))
        .status,
      200,
    );
    const relink = await sendJson('POST', '/api/links', {
      from: { type: 'die', id: dieOneId },
      to: { type: 'machine', id: machineId },
    });
    assert.equal(relink.status, 201);
    assert.equal(
      (await sendJson('DELETE', `/api/dies/${dieOneId}`)).status,
      200,
    );
    const machineAfterPurge = await getJson(`/api/links/machine/${machineId}`);
    assert.equal(
      machineAfterPurge.body.groups.find((g) => g.type === 'die'),
      undefined,
      'deleting the die leaves the machine with no die links at all',
    );
  } finally {
    await closeServer(server);
  }
});

test('a link is gated on both masters it spans', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-entity-links-authz-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'links-authz@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const login = async (email, password) => {
      const r = await fetch(`${baseUrl}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password }),
      });
      return (await r.json()).token;
    };
    const ownerToken = await login('links-authz@paper.local', 'OwnerPass1234');
    const ownerHeaders = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${ownerToken}`,
    };

    const items = await (
      await fetch(`${baseUrl}/api/items`, { headers: ownerHeaders })
    ).json();
    const item = items.items[0];
    const dieResponse = await fetch(`${baseUrl}/api/dies`, {
      method: 'POST',
      headers: ownerHeaders,
      body: JSON.stringify({
        toolCode: 'DIE-AUTHZ-1',
        status: 'active',
        ownership: 'owned',
      }),
    });
    const dieBody = await dieResponse.json();
    const dieId = String(dieBody.die?.id ?? dieBody.id);

    // A user who may work on items but was never given the die master. The
    // link spans both, so items.update alone must not be enough — this is the
    // hole a path-segment gate would leave, since /api/links names no module.
    const created = await fetch(`${baseUrl}/api/users`, {
      method: 'POST',
      headers: ownerHeaders,
      body: JSON.stringify({
        name: 'Item Clerk',
        email: 'item-clerk@paper.local',
        password: 'ClerkPass1234',
        role: 'user',
        permissions: ['items.read', 'items.update', 'login.desktop'],
      }),
    });
    assert.equal(created.status, 201, await created.clone().text());
    const clerkId = (await created.json()).user.id;

    // The grid, set deliberately: this clerk may change items and may not so
    // much as see a die. Staff read every module and write none of them by
    // default (DEFAULT_ROLE_PERMISSIONS), so both halves need saying.
    const grid = await fetch(`${baseUrl}/api/users/${clerkId}/permissions`, {
      method: 'PATCH',
      headers: ownerHeaders,
      body: JSON.stringify({
        overrides: [
          { key: 'items.update', allowed: true },
          { key: 'dies.read', allowed: false },
        ],
      }),
    });
    assert.equal(grid.status, 200, await grid.clone().text());

    const clerkToken = await login('item-clerk@paper.local', 'ClerkPass1234');
    assert.ok(clerkToken, 'expected the clerk to be able to sign in');
    const clerkHeaders = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${clerkToken}`,
    };

    const attempt = await fetch(`${baseUrl}/api/links`, {
      method: 'POST',
      headers: clerkHeaders,
      body: JSON.stringify({
        from: { type: 'item', id: item.id },
        to: { type: 'die', id: dieId },
      }),
    });
    assert.equal(
      attempt.status,
      403,
      'linking a die needs the die master, not just the item master',
    );
    assert.match(
      (await attempt.json()).error,
      /Dies/,
      'the refusal names the master that was missing, not a generic one',
    );

    // The other half of the same rule, and the one that proves whose gate is
    // answering: a link this clerk IS entitled to must go through. If the
    // legacy admin write gate were still in front of /api/links, this would
    // 403 too and no staff member could ever link anything.
    const items2 = await (
      await fetch(`${baseUrl}/api/items`, { headers: ownerHeaders })
    ).json();
    const other = items2.items.find((row) => row.id !== item.id);
    assert.ok(other, 'expected a second seeded item');
    const allowed = await fetch(`${baseUrl}/api/links`, {
      method: 'POST',
      headers: clerkHeaders,
      body: JSON.stringify({
        from: { type: 'item', id: item.id },
        to: { type: 'item', id: other.id },
      }),
    });
    assert.equal(
      allowed.status,
      201,
      `a staff user with items.update may link two items: ${await allowed.clone().text()}`,
    );

    // The owner links the die to the item, so there is a link for the clerk to
    // be refused a sight of.
    const ownerLink = await fetch(`${baseUrl}/api/links`, {
      method: 'POST',
      headers: ownerHeaders,
      body: JSON.stringify({
        from: { type: 'item', id: item.id },
        to: { type: 'die', id: dieId },
      }),
    });
    assert.equal(ownerLink.status, 201);

    const readDie = await fetch(`${baseUrl}/api/links/die/${dieId}`, {
      headers: clerkHeaders,
    });
    assert.equal(readDie.status, 403, 'a die the user cannot read stays unread');

    // The item itself still reads — minus the die group. A link whose other
    // end is unreadable is left out rather than shown as a nameless row,
    // because the name is the whole content of the row.
    const readItem = await fetch(`${baseUrl}/api/links/item/${item.id}`, {
      headers: clerkHeaders,
    });
    assert.equal(readItem.status, 200);
    const itemBody = await readItem.json();
    assert.equal(
      itemBody.groups.find((group) => group.type === 'die'),
      undefined,
      'the die group is withheld from someone who cannot read dies',
    );

    const clerkSchema = await (
      await fetch(`${baseUrl}/api/links/schema`, { headers: clerkHeaders })
    ).json();
    assert.ok(
      !clerkSchema.types.some((entry) => entry.type === 'die'),
      'the "+ link" menu only offers masters the user can actually read',
    );
    assert.ok(
      clerkSchema.types.some(
        (entry) => entry.type === 'item' && entry.canLink === true,
      ),
      'the menu marks the masters the user may actually attach',
    );
  } finally {
    await closeServer(server);
  }
});
