const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// A combination group is where a family of variants is gathered, and the base
// item — the one carrying the top-level properties every variant is struck
// from — belongs in it too. Filing only the variants leaves the group holding
// the offspring but not the thing they came from, so the group can never say
// what family it is.
//
// The membership endpoint takes item ids and asks nothing about their shape;
// this pins that down, because the client used to offer only spawned variants
// and the constraint could easily be mistaken for a server rule.

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

test('a base item with top-level properties can join a combination group', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-combo-base-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'combo-base@paper.local';
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
        email: 'combo-base@paper.local',
        password: 'OwnerPass1234',
      }),
    });
    const { token } = await loginResponse.json();
    assert.ok(token, 'expected a login token');
    const authHeaders = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    };

    const post = async (route, body) => {
      const response = await fetch(`${baseUrl}${route}`, {
        method: 'POST',
        headers: authHeaders,
        body: JSON.stringify(body),
      });
      return { status: response.status, body: await response.json() };
    };

    const groupsList = await fetch(`${baseUrl}/api/groups`, {
      headers: authHeaders,
    });
    const { groups } = await groupsList.json();
    const home = groups.find(
      (group) =>
        group.groupType === 'item' && group.groupStructure !== 'combination',
    );
    assert.ok(home, 'needed an item group to file the base item under');

    const unitsList = await fetch(`${baseUrl}/api/units`, {
      headers: authHeaders,
    });
    const { units } = await unitsList.json();
    const unitId = units[0].id;

    // The base item: it has top-level properties, which is exactly the shape
    // the client used to refuse to offer.
    const base = await post('/api/items', {
      name: 'Socket Earthing',
      groupId: home.id,
      unitId,
      variationTree: [
        {
          kind: 'property',
          name: 'Socket Amp',
          children: [
            { kind: 'value', name: '6 Amp', children: [] },
            { kind: 'value', name: '16 Amp', children: [] },
          ],
        },
      ],
    });
    assert.equal(base.status, 201, JSON.stringify(base.body));
    const baseId = base.body.item.id;
    assert.ok(
      base.body.item.variationTree.length > 0,
      'the base item must actually carry top-level properties',
    );

    const variant = await post('/api/items', {
      name: 'Socket Earthing - 6 Amp',
      groupId: home.id,
      unitId,
      baseItemId: baseId,
      variationTree: [],
    });
    assert.equal(variant.status, 201, JSON.stringify(variant.body));
    const variantId = variant.body.item.id;

    const combo = await post('/api/groups', {
      name: 'Socket Family',
      groupType: 'item',
      groupStructure: 'combination',
      description: 'The base item and everything struck from it.',
    });
    assert.equal(combo.status, 201, JSON.stringify(combo.body));
    const comboId = combo.body.group.id;

    // Both go in, in one call, base first.
    const assigned = await post(`/api/groups/${comboId}/items`, {
      itemIds: [baseId, variantId],
    });
    assert.equal(assigned.status, 201, JSON.stringify(assigned.body));
    assert.equal(assigned.body.assignedCount, 2);

    const overviewResponse = await fetch(
      `${baseUrl}/api/groups/${comboId}/overview`,
      { headers: authHeaders },
    );
    const overviewBody = await overviewResponse.json();
    assert.equal(overviewResponse.status, 200, JSON.stringify(overviewBody));
    const overview = overviewBody.overview;
    assert.equal(overview.itemSource, 'curated');

    const memberIds = overview.items.map((item) => item.itemId);
    assert.deepEqual(
      memberIds,
      [baseId, variantId],
      'the base item and its variant are both members, in the order filed',
    );

    // Filing into a combination group is a second membership, not a move: the
    // base item still lives in the group it was created under.
    const itemRead = await fetch(`${baseUrl}/api/items/${baseId}`, {
      headers: authHeaders,
    });
    const itemBody = await itemRead.json();
    assert.equal(itemBody.item.groupId, home.id);

    // And the variant is still linked to its base, so the group view can nest
    // one under the other.
    const baseRow = overview.items.find((item) => item.itemId === baseId);
    const variantRow = overview.items.find((item) => item.itemId === variantId);
    assert.equal(baseRow.isVariant, false);
    assert.equal(baseRow.baseItemId, null);
    assert.equal(variantRow.isVariant, true);
    assert.equal(variantRow.baseItemId, baseId);

    // A combination group is also selectable as an item's own group, the way
    // any other group is. An item filed under one that way is not curated into
    // it, so the overview has to read both — otherwise the item is filed
    // somewhere it cannot be seen.
    const lodger = await post('/api/items', {
      name: 'Filed Straight Into The Set',
      groupId: comboId,
      unitId,
      variationTree: [],
    });
    assert.equal(lodger.status, 201, JSON.stringify(lodger.body));
    assert.equal(lodger.body.item.groupId, comboId);

    const reread = await fetch(`${baseUrl}/api/groups/${comboId}/overview`, {
      headers: authHeaders,
    });
    const rereadBody = await reread.json();
    assert.equal(reread.status, 200, JSON.stringify(rereadBody));
    const rereadIds = rereadBody.overview.items.map((item) => item.itemId);
    assert.deepEqual(
      rereadIds,
      [baseId, variantId, lodger.body.item.id],
      'curated members keep their order, and an owned item follows them',
    );

    // Counted once, not twice: the base item is curated in AND could be read
    // by either query if the merge were sloppy.
    assert.equal(
      rereadIds.filter((id) => id === baseId).length,
      1,
      'a curated item that is also owned appears once',
    );
  } finally {
    await closeServer(server);
  }
});
