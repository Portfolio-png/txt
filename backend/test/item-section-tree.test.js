const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

const { validateSectionTree } = require('../modules/items/section-tree');

// A part's section tree (migration 057): how its item sheet is nested, and
// the links that nesting stands for. Die under Client = the client's tooling;
// Machine under Die = the machines that run those dies.

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
  const headers = { 'Content-Type': 'application/json', Authorization: `Bearer ${login.token}` };
  const call = async (method, p, body) => {
    const response = await fetch(`${baseUrl}${p}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: response.status, body: await response.json() };
  };
  return { backend, server, call };
}

/// The part's tree links, as "type:id-type:id" strings, sorted.
async function treeLinks(ctx, itemId) {
  const rows = await ctx.backend.all(
    'SELECT left_type, left_id, right_type, right_id FROM entity_links WHERE relation = ? ORDER BY 1,2,3,4',
    [`part_tree:${itemId}`],
  );
  return rows.map((r) => `${r.left_type}:${r.left_id}-${r.right_type}:${r.right_id}`);
}

async function setUp(ctx) {
  const sample = (await ctx.call('GET', '/api/items')).body.items[0];
  const client = (await ctx.call('POST', '/api/clients', { name: 'Tree Client' })).body.client;
  const die = await ctx.call('POST', '/api/dies', { toolCode: 'TREE-DIE-1', status: 'active', ownership: 'owned' });
  const dieId = String(die.body.die?.id ?? die.body.id);
  const machine = await ctx.call('POST', '/api/machines', { name: 'Tree Press', assetId: 'TREE-M-1', status: 'operational' });
  const machineId = String(machine.body.machine?.id ?? machine.body.id);
  const made = await ctx.call('POST', '/api/items', {
    name: 'Tree Patti',
    displayName: 'Tree Patti',
    groupId: sample.groupId,
    unitId: sample.unitId,
    developedFor: { kind: 'client', clientId: client.id },
    dieIds: [dieId],
    machineIds: [machineId],
  });
  assert.equal(made.status, 201, JSON.stringify(made.body));
  return { sample, client, dieId, machineId, item: made.body.item };
}

test('the validator refuses what is not a tree', () => {
  assert.throws(() => validateSectionTree({ client_vendor: 'die_master' }), /circle/);
  assert.throws(() => validateSectionTree({ group_item: 'die_master' }), /not a section that can be moved/);
  assert.throws(() => validateSectionTree({ die_master: 'die_master' }), /itself/);
  assert.throws(() => validateSectionTree({ die_master: 'warehouse' }), /not a section/);
  assert.deepEqual(validateSectionTree({ machine_master: 'client_vendor' }).machine_master, 'client_vendor');
});

test('the default tree links client↔die and die↔machine; re-nesting swaps them', async () => {
  const ctx = await boot('paper-section-tree-', 'section-tree@paper.local');
  try {
    const { client, dieId, machineId, item } = await setUp(ctx);
    assert.equal(item.sectionTree, null, 'no tree saved means the default chain');
    assert.deepEqual(await treeLinks(ctx, item.id), [
      `client:${client.id}-die:${dieId}`,
      `die:${dieId}-machine:${machineId}`,
    ]);

    // Machines move under the client: the die↔machine link goes, client↔machine comes.
    const moved = await ctx.call('PUT', `/api/items/${item.id}/section-tree`, {
      tree: { machine_master: 'client_vendor' },
    });
    assert.equal(moved.status, 200, JSON.stringify(moved.body));
    assert.equal(moved.body.item.sectionTree.machine_master, 'client_vendor');
    assert.deepEqual(await treeLinks(ctx, item.id), [
      `client:${client.id}-die:${dieId}`,
      `client:${client.id}-machine:${machineId}`,
    ]);

    // The generic link API sees them from either end.
    const fromMachine = await ctx.call('GET', `/api/links/machine/${machineId}`);
    const clients = fromMachine.body.groups.find((g) => g.type === 'client');
    assert.ok(clients && clients.links.some((l) => String(l.id) === String(client.id)));

    // Everything directly under the part: no cross-links at all.
    await ctx.call('PUT', `/api/items/${item.id}/section-tree`, {
      tree: { client_vendor: 'group_item', die_master: 'group_item', machine_master: 'group_item' },
    });
    assert.deepEqual(await treeLinks(ctx, item.id), []);

    const cyclic = await ctx.call('PUT', `/api/items/${item.id}/section-tree`, {
      tree: { client_vendor: 'machine_master' },
    });
    assert.equal(cyclic.status, 400);
    assert.equal(cyclic.body.code, 'section_tree_invalid');
  } finally {
    await closeServer(ctx.server);
  }
});

test('the links follow the part: a die taken off, no client, a hand-made link kept', async () => {
  const ctx = await boot('paper-section-follow-', 'section-follow@paper.local');
  try {
    const { sample, client, dieId, machineId, item } = await setUp(ctx);
    const base = { name: 'Tree Patti', displayName: 'Tree Patti', groupId: sample.groupId, unitId: sample.unitId };

    // Somebody also linked the die and machine by hand.
    const manual = await ctx.call('POST', '/api/links', {
      from: { type: 'die', id: dieId },
      to: { type: 'machine', id: machineId },
    });
    assert.equal(manual.status, 201, JSON.stringify(manual.body));

    // The die comes off the part. Its tree links go; the machines, nested
    // under an empty Die section, fall through to the client.
    const off = await ctx.call('PATCH', `/api/items/${item.id}`, { ...base, dieIds: [] });
    assert.equal(off.status, 200, JSON.stringify(off.body));
    assert.deepEqual(await treeLinks(ctx, item.id), [`client:${client.id}-machine:${machineId}`]);
    const handMade = await ctx.backend.get(
      "SELECT 1 AS ok FROM entity_links WHERE relation = 'linked' AND left_type = 'die' AND left_id = ? AND right_id = ?",
      [dieId, machineId],
    );
    assert.ok(handMade, 'a link the sheet did not make is never touched');

    // Developed in-house: no client, nothing to link to.
    await ctx.call('PATCH', `/api/items/${item.id}`, { ...base, developedFor: { kind: 'self' } });
    assert.deepEqual(await treeLinks(ctx, item.id), []);
  } finally {
    await closeServer(ctx.server);
  }
});

test('two parts implying the same pair keep their own links', async () => {
  const ctx = await boot('paper-section-two-', 'section-two@paper.local');
  try {
    const { sample, client, dieId, machineId, item } = await setUp(ctx);
    const twin = await ctx.call('POST', '/api/items', {
      name: 'Tree Twin',
      displayName: 'Tree Twin',
      groupId: sample.groupId,
      unitId: sample.unitId,
      developedFor: { kind: 'client', clientId: client.id },
      dieIds: [dieId],
      machineIds: [machineId],
    });
    assert.equal(twin.status, 201, JSON.stringify(twin.body));

    // The first part flattens its tree; the twin's links are untouched.
    await ctx.call('PUT', `/api/items/${item.id}/section-tree`, {
      tree: { die_master: 'group_item', machine_master: 'group_item' },
    });
    assert.deepEqual(await treeLinks(ctx, item.id), []);
    assert.equal((await treeLinks(ctx, twin.body.item.id)).length, 2);
  } finally {
    await closeServer(ctx.server);
  }
});

test('only the sheet owns its links: unlink, forgery and delete', async () => {
  const ctx = await boot('paper-section-owned-', 'section-owned@paper.local');
  try {
    const { client, dieId, machineId, item } = await setUp(ctx);
    const expected = [
      `client:${client.id}-die:${dieId}`,
      `die:${dieId}-machine:${machineId}`,
    ];
    assert.deepEqual(await treeLinks(ctx, item.id), expected);

    // A hand-made link on the same pair, then an unlink that names no
    // relation: the hand-made one goes, the part's nesting stays.
    const manual = await ctx.call('POST', '/api/links', {
      from: { type: 'die', id: dieId },
      to: { type: 'machine', id: machineId },
    });
    assert.equal(manual.status, 201, JSON.stringify(manual.body));
    const unlinked = await ctx.call('DELETE', `/api/links/die/${dieId}/machine/${machineId}`);
    assert.equal(unlinked.status, 200, JSON.stringify(unlinked.body));
    assert.deepEqual(await treeLinks(ctx, item.id), expected);

    // Nobody writes the sheet's relation by hand.
    const forged = await ctx.call('POST', '/api/links', {
      from: { type: 'die', id: dieId },
      to: { type: 'machine', id: machineId },
      relation: `part_tree:${item.id}`,
    });
    assert.equal(forged.status, 400, JSON.stringify(forged.body));

    // Deleting the part takes its nesting with it. The links name the part
    // only in their relation, so the item purge never reached them.
    const deleted = await ctx.call('DELETE', `/api/items/${item.id}`);
    assert.ok(deleted.status < 300, JSON.stringify(deleted.body));
    assert.deepEqual(await treeLinks(ctx, item.id), []);
  } finally {
    await closeServer(ctx.server);
  }
});
