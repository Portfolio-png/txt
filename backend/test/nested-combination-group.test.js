const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// A combination group used to be forced flat — saveGroup dropped any
// parentGroupId it was handed. The variant workflow now offers "Nest under" so a
// variant set can live inside the item group it belongs to, which only works if
// the parent survives the write. The second half guards the half of the old rule
// that still holds: left alone, a combination group stays top level rather than
// being auto-attached to the Primary Group the way a hierarchical group is.

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

test('a combination group keeps the parent it was created under', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-nested-combo-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'combo-owner@paper.local';
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
        email: 'combo-owner@paper.local',
        password: 'OwnerPass1234',
      }),
    });
    const { token } = await loginResponse.json();
    assert.ok(token, 'expected a login token');
    const authHeaders = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    };

    const createCombinationGroup = async (name, parentGroupId) => {
      const response = await fetch(`${baseUrl}/api/groups`, {
        method: 'POST',
        headers: authHeaders,
        body: JSON.stringify({
          name,
          groupType: 'item',
          groupStructure: 'combination',
          description: '',
          ...(parentGroupId === undefined ? {} : { parentGroupId }),
        }),
      });
      return { status: response.status, body: await response.json() };
    };

    const groupList = await fetch(`${baseUrl}/api/groups`, {
      headers: authHeaders,
    });
    const { groups } = await groupList.json();
    assert.ok(Array.isArray(groups), 'expected a group list');
    const primary = groups.find((group) => group.name === 'Primary Group');
    assert.ok(primary, 'expected the seeded Primary Group');
    const unitId = primary.unitId;
    assert.ok(unitId, 'expected Primary Group to carry a unit');

    // Under Primary Group itself.
    const underPrimary = await createCombinationGroup(
      'Combo Under Primary',
      primary.id,
    );
    assert.equal(underPrimary.status, 201, JSON.stringify(underPrimary.body));
    assert.equal(
      underPrimary.body.group.parentGroupId,
      primary.id,
      'Primary Group must be usable as a parent',
    );

    // Under a hierarchical group that is itself under Primary Group.
    const midResponse = await fetch(`${baseUrl}/api/groups`, {
      method: 'POST',
      headers: authHeaders,
      body: JSON.stringify({
        name: 'Finish Goods Under Primary',
        groupType: 'item',
        groupStructure: 'hierarchical',
        parentGroupId: primary.id,
        unitId,
      }),
    });
    const midBody = await midResponse.json();
    assert.equal(midResponse.status, 201, JSON.stringify(midBody));
    assert.equal(midBody.group.parentGroupId, primary.id);

    const nested = await createCombinationGroup(
      'Combo Two Levels Down',
      midBody.group.id,
    );
    assert.equal(nested.status, 201, JSON.stringify(nested.body));
    assert.equal(
      nested.body.group.parentGroupId,
      midBody.group.id,
      'a group under Primary Group must be usable as a parent too',
    );

    const flat = await createCombinationGroup('Flat Combo Group');
    assert.equal(flat.status, 201, JSON.stringify(flat.body));
    assert.equal(
      flat.body.group.parentGroupId,
      null,
      'a combination group with no parent named must stay top level',
    );

    // Editing one must not un-nest it: the editor sends the parent on every
    // save precisely because the server reads a missing one as "top level".
    const renamed = await fetch(
      `${baseUrl}/api/groups/${nested.body.group.id}`,
      {
        method: 'PATCH',
        headers: authHeaders,
        body: JSON.stringify({
          name: 'Combo Two Levels Down (renamed)',
          groupType: 'item',
          groupStructure: 'combination',
          description: 'still nested',
          parentGroupId: midBody.group.id,
        }),
      },
    );
    const renamedBody = await renamed.json();
    assert.equal(renamed.status, 200, JSON.stringify(renamedBody));
    assert.equal(
      renamedBody.group.parentGroupId,
      midBody.group.id,
      'an edit that carries the parent must keep it',
    );

    // And moving one back to the top level still works.
    const unnested = await fetch(
      `${baseUrl}/api/groups/${nested.body.group.id}`,
      {
        method: 'PATCH',
        headers: authHeaders,
        body: JSON.stringify({
          name: 'Combo Two Levels Down (renamed)',
          groupType: 'item',
          groupStructure: 'combination',
          description: 'top level again',
          parentGroupId: null,
        }),
      },
    );
    const unnestedBody = await unnested.json();
    assert.equal(unnested.status, 200, JSON.stringify(unnestedBody));
    assert.equal(unnestedBody.group.parentGroupId, null);
  } finally {
    await closeServer(server);
  }
});
