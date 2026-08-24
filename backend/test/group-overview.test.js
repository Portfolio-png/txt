const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

const { summarise, schemaToDto } = require('../modules/items/group-overview');

// The overview answers "what is this group", which the editor never did. The
// part most worth guarding is where the items come from: a combination group
// curates a list, everything else owns one, and reading the wrong table makes a
// populated group look empty.

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

test('the summary is counted from the items, never guessed', () => {
  const items = [
    { unitName: 'Nos', orderCount: 3, isVariant: false, photoUrl: 'a.png', hasPipeline: true, hasBaseline: true },
    { unitName: 'Nos', orderCount: 0, isVariant: true, photoUrl: '', hasPipeline: false, hasBaseline: false },
    { unitName: 'Kg', orderCount: 2, isVariant: true, photoUrl: '', hasPipeline: true, hasBaseline: false },
  ];
  const summary = summarise(items);
  assert.equal(summary.itemCount, 3);
  assert.equal(summary.orderedItemCount, 2, 'two have been ordered at all');
  assert.equal(summary.orderLineCount, 5, 'across five order lines');
  assert.equal(summary.variantCount, 2);
  assert.equal(summary.withPhotoCount, 1);
  assert.equal(summary.withPipelineCount, 2);
  assert.equal(summary.withBaselineCount, 1);
  assert.deepEqual(summary.units, ['Kg', 'Nos'], 'sorted and de-duplicated');
});

test('an empty group summarises to zeroes rather than to nothing', () => {
  const summary = summarise([]);
  assert.equal(summary.itemCount, 0);
  assert.deepEqual(summary.units, []);
});

test('a property remembers which group in the lineage put it there', () => {
  const dto = schemaToDto({
    lineageGroupIds: [1, 2],
    lineageGroupNames: ['Primary', 'Sockets'],
    propertyDrafts: [
      { propertyKey: 'colour', displayName: 'Colour', inputType: 'text', mandatory: true, sourceGroupId: 1, sourceGroupName: 'Primary' },
      { propertyKey: 'amps', inputType: 'number', unitSymbol: 'A', sourceGroupId: 2, sourceGroupName: 'Sockets' },
    ],
  });
  assert.deepEqual(dto.lineage, [
    { groupId: 1, name: 'Primary' },
    { groupId: 2, name: 'Sockets' },
  ]);
  assert.equal(dto.properties[0].sourceGroupName, 'Primary');
  assert.equal(dto.properties[0].mandatory, true);
  // A property with no display name falls back to its key rather than blank.
  assert.equal(dto.properties[1].displayName, 'amps');
  assert.equal(dto.properties[1].unitSymbol, 'A');
});

test('a missing schema is an empty one, not a crash', () => {
  assert.deepEqual(schemaToDto(null), { properties: [], lineage: [] });
});

test('the overview reads a real group end-to-end', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-group-overview-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'overview@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const { token } = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: process.env.PAPER_SUPER_ADMIN_EMAIL,
        password: process.env.PAPER_SUPER_ADMIN_PASSWORD,
      }),
    }).then((r) => r.json());
    const authHeaders = { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` };
    const get = async (p) => {
      const r = await fetch(`${baseUrl}${p}`, { headers: authHeaders });
      return { status: r.status, body: await r.json() };
    };

    const groups = await get('/api/groups');
    const withItems = await get('/api/groups?withCovers=1');
    const populated = withItems.body.groups.find((g) => g.itemCount > 0);
    assert.ok(populated, 'the seed has a group with items');

    const view = await get(`/api/groups/${populated.id}/overview`);
    assert.equal(view.status, 200, JSON.stringify(view.body));
    const overview = view.body.overview;

    assert.equal(overview.group.id, populated.id);
    assert.equal(overview.group.name, populated.name);
    assert.equal(overview.itemSource, 'owned', 'a hierarchical group owns its items');

    // The list and the summary must agree — a header that contradicts the list
    // under it is worse than no header.
    assert.equal(overview.summary.itemCount, overview.items.length);
    assert.equal(overview.summary.itemCount, populated.itemCount);
    assert.equal(
      overview.summary.orderLineCount,
      overview.items.reduce((sum, item) => sum + item.orderCount, 0)
    );
    assert.equal(
      overview.summary.orderedItemCount,
      overview.items.filter((item) => item.orderCount > 0).length
    );

    // Most ordered first, same ranking the cards use.
    const counts = overview.items.map((item) => item.orderCount);
    assert.deepEqual(counts, [...counts].sort((a, b) => b - a));

    for (const item of overview.items) {
      assert.ok(item.itemId > 0);
      assert.equal(typeof item.name, 'string');
      assert.equal(typeof item.isVariant, 'boolean');
      // The link, not just the flag: a list that nests variants under their
      // own base item cannot do it from a boolean.
      if (item.isVariant) {
        assert.equal(
          typeof item.baseItemId,
          'number',
          'a variant must say which item it is a variant of',
        );
      } else {
        assert.equal(item.baseItemId, null);
      }
    }

    assert.ok(Array.isArray(overview.lineage));
    assert.ok(Array.isArray(overview.properties));
    assert.ok(Array.isArray(overview.children));

    // An empty group is a real answer, not a 404.
    const empty = withItems.body.groups.find((g) => g.itemCount === 0);
    if (empty) {
      const emptyView = await get(`/api/groups/${empty.id}/overview`);
      assert.equal(emptyView.status, 200);
      assert.equal(emptyView.body.overview.items.length, 0);
      assert.equal(emptyView.body.overview.summary.itemCount, 0);
    }

    const missing = await get('/api/groups/99999/overview');
    assert.equal(missing.status, 404);
    assert.equal(missing.body.overview, null);

    assert.ok(groups.body.groups.length > 0);

    // --- combination groups: a curated list, from a different table ---
    //
    // The seed has none, so one is built here. This is the path the whole
    // module exists to get right: reading items.group_id for a combination
    // group returns nothing and makes a populated group look empty.
    const send = async (method, p, payload) => {
      const r = await fetch(`${baseUrl}${p}`, {
        method,
        headers: authHeaders,
        body: JSON.stringify(payload),
      });
      return { status: r.status, body: await r.json() };
    };

    const created = await send('POST', '/api/groups', {
      name: 'Fast Movers',
      groupType: 'item',
      groupStructure: 'combination',
      description: 'The ones that keep selling',
      unitId: populated.unitId,
    });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    const comboId = created.body.group.id;

    // Empty to begin with, and honest about which table it reads.
    const beforeAssign = await get(`/api/groups/${comboId}/overview`);
    assert.equal(beforeAssign.body.overview.itemSource, 'curated');
    assert.equal(beforeAssign.body.overview.items.length, 0);

    // Items keep living in their own groups; this one gathers them.
    const picked = overview.items.slice(0, 2).map((item) => item.itemId);
    assert.equal(picked.length, 2, 'two items to curate');
    const assigned = await send('POST', `/api/groups/${comboId}/items`, {
      itemIds: picked,
    });
    assert.equal(assigned.status, 201, JSON.stringify(assigned.body));
    assert.equal(assigned.body.assignedCount, 2);
    assert.equal(assigned.body.skippedCount, 0);

    const combo = await get(`/api/groups/${comboId}/overview`);
    assert.equal(combo.status, 200);
    const comboView = combo.body.overview;
    assert.equal(comboView.itemSource, 'curated');
    assert.equal(comboView.group.groupStructure, 'combination');
    assert.equal(comboView.summary.itemCount, 2);
    assert.deepEqual(
      comboView.items.map((item) => item.itemId).sort(),
      [...picked].sort(),
      'exactly the curated items, not the whole catalogue'
    );

    // The gathered items did NOT move: their own group still holds them.
    const origin = await get(`/api/groups/${populated.id}/overview`);
    assert.equal(
      origin.body.overview.summary.itemCount,
      overview.summary.itemCount,
      'curating into a combination group does not empty the real one'
    );
  } finally {
    await closeServer(server);
  }
});
