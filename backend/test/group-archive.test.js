const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// Archiving a group: the honest way to take one out of use.
//
// The route existed with no caller, returned nothing but `{success}`, never
// broadcast, and refused with the bare words "Group is in use" — leaving the
// user to guess which of three different things was still inside. There was no
// way back at all. This covers the finished shape.

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
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'ArchivePass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  const { token } = await fetch(`${baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: 'ArchivePass1234' }),
  }).then((r) => r.json());
  const headers = { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` };

  const call = async (method, p, body) => {
    const r = await fetch(`${baseUrl}${p}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: r.status, body: await r.json() };
  };

  return { backend, server, call };
}

test('a group archives, comes back, and says what is holding it', async () => {
  const ctx = await boot('paper-group-archive-', 'archive@paper.local');
  try {
    const { call } = ctx;
    const groups = await call('GET', '/api/groups');
    const parent = groups.body.groups.find((g) => g.groupType === 'item');
    assert.ok(parent, 'the seed has an item group');

    const made = await call('POST', '/api/groups', {
      name: 'Archivable',
      groupType: 'item',
      parentGroupId: parent.id,
      unitId: parent.unitId,
    });
    assert.equal(made.status, 201, JSON.stringify(made.body));
    const group = made.body.group;

    // --- empty, so it goes ------------------------------------------------
    const archived = await call('PATCH', `/api/groups/${group.id}/archive`);
    assert.equal(archived.status, 200, JSON.stringify(archived.body));
    // The updated row comes back, so the caller does not have to refetch the
    // whole list to learn the new state.
    assert.equal(archived.body.group.id, group.id);
    assert.equal(archived.body.group.isArchived, true);

    const afterArchive = await call('GET', '/api/groups');
    const seen = afterArchive.body.groups.find((g) => g.id === group.id);
    assert.equal(seen.isArchived, true, 'the list agrees');

    // --- and comes back ----------------------------------------------------
    const restored = await call('PATCH', `/api/groups/${group.id}/unarchive`);
    assert.equal(restored.status, 200, JSON.stringify(restored.body));
    assert.equal(restored.body.group.isArchived, false);
  } finally {
    await closeServer(ctx.server);
  }
});

test('the refusal names what is still in the group', async () => {
  const ctx = await boot('paper-group-archive-busy-', 'archive-busy@paper.local');
  try {
    const { call } = ctx;
    const groups = await call('GET', '/api/groups');
    const parent = groups.body.groups.find((g) => g.groupType === 'item');

    const made = await call('POST', '/api/groups', {
      name: 'Holds Things',
      groupType: 'item',
      parentGroupId: parent.id,
      unitId: parent.unitId,
    });
    const group = made.body.group;

    const item = await call('POST', '/api/items', {
      name: 'Still In It',
      groupId: group.id,
      unitId: parent.unitId,
    });
    assert.equal(item.status, 201, JSON.stringify(item.body));

    const refused = await call('PATCH', `/api/groups/${group.id}/archive`);
    assert.equal(refused.status, 409);
    assert.equal(refused.body.code, 'group_in_use');
    // Which thing, not merely that there was one — the old message said
    // "Group is in use" and left the user to go looking.
    assert.match(refused.body.error, /1 active item/);
    assert.match(refused.body.error, /Holds Things/);

    // A child group counts too, and both are named together.
    const child = await call('POST', '/api/groups', {
      name: 'Underneath',
      groupType: 'item',
      parentGroupId: group.id,
      unitId: parent.unitId,
    });
    assert.equal(child.status, 201, JSON.stringify(child.body));
    const refusedAgain = await call('PATCH', `/api/groups/${group.id}/archive`);
    assert.equal(refusedAgain.status, 409);
    assert.match(refusedAgain.body.error, /1 active child group and 1 active item/);

    // Nothing was written: a refused archive must not half-apply.
    const after = await call('GET', '/api/groups');
    assert.equal(after.body.groups.find((g) => g.id === group.id).isArchived, false);
  } finally {
    await closeServer(ctx.server);
  }
});

test('a group is not restored into an archived parent', async () => {
  const ctx = await boot('paper-group-unarchive-', 'unarchive@paper.local');
  try {
    const { call } = ctx;
    const groups = await call('GET', '/api/groups');
    const root = groups.body.groups.find((g) => g.groupType === 'item');

    const outer = await call('POST', '/api/groups', {
      name: 'Outer',
      groupType: 'item',
      parentGroupId: root.id,
      unitId: root.unitId,
    });
    const inner = await call('POST', '/api/groups', {
      name: 'Inner',
      groupType: 'item',
      parentGroupId: outer.body.group.id,
      unitId: root.unitId,
    });

    // Inner first, since a parent with an active child cannot be archived.
    assert.equal((await call('PATCH', `/api/groups/${inner.body.group.id}/archive`)).status, 200);
    assert.equal((await call('PATCH', `/api/groups/${outer.body.group.id}/archive`)).status, 200);

    // A live group inside an archived one cannot be reached from the tree, so
    // restoring the child alone is refused and says which to do first.
    const refused = await call('PATCH', `/api/groups/${inner.body.group.id}/unarchive`);
    assert.equal(refused.status, 409);
    assert.equal(refused.body.code, 'parent_archived');
    assert.match(refused.body.error, /Outer/);

    // Parent first, then the child goes back.
    assert.equal((await call('PATCH', `/api/groups/${outer.body.group.id}/unarchive`)).status, 200);
    const ok = await call('PATCH', `/api/groups/${inner.body.group.id}/unarchive`);
    assert.equal(ok.status, 200, JSON.stringify(ok.body));
    assert.equal(ok.body.group.isArchived, false);
  } finally {
    await closeServer(ctx.server);
  }
});

test('archiving a group that is not there is a 404, not a 500', async () => {
  const ctx = await boot('paper-group-archive-404-', 'archive404@paper.local');
  try {
    const missing = await ctx.call('PATCH', '/api/groups/999999/archive');
    assert.equal(missing.status, 404);
    const missingBack = await ctx.call('PATCH', '/api/groups/999999/unarchive');
    assert.equal(missingBack.status, 404);
  } finally {
    await closeServer(ctx.server);
  }
});
