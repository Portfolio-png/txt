const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

function loadFreshBackend() {
  const backendPath = require.resolve('../server.js');
  delete require.cache[backendPath];
  return require('../server.js');
}

test('inventory sets can be created, merged, listed, rejected, and deleted', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-inventory-sets-'));
  const dbPath = path.join(tempDir, 'paper.db');
  process.env.DB_PATH = dbPath;
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'sets-owner@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'SetsOwner1234';

  const backend = loadFreshBackend();

  try {
    await backend.resetAndSeedDemoData();
    const itemRows = await backend.getItemsWithUsage();
    const firstRow = itemRows.find((entry) => !entry.is_archived);
    const secondRow = itemRows.find(
      (entry) => !entry.is_archived && entry.id !== firstRow?.id,
    );
    assert.ok(firstRow, 'expected first active item');
    assert.ok(secondRow, 'expected second active item');
    const firstItem = await backend.rowToItemDto(firstRow);
    const secondItem = await backend.rowToItemDto(secondRow);
    const firstLeaf = findFirstLeafVariation(firstItem.variationTree || []);
    const secondLeaf = findFirstLeafVariation(secondItem.variationTree || []);
    assert.ok(firstLeaf, 'expected first leaf variation');
    assert.ok(secondLeaf, 'expected second leaf variation');

    const { server, port } = await listen(backend.app);
    const baseUrl = `http://127.0.0.1:${port}`;

    try {
      const owner = await login(
        baseUrl,
        'sets-owner@paper.local',
        'SetsOwner1234',
      );

      const created = await postJson(
        baseUrl,
        '/api/inventory/sets',
        owner.token,
        {
          name: 'Starter Pack',
          lines: [
            {
              itemId: firstItem.id,
              variationLeafNodeId: firstLeaf.id,
              quantity: 2,
              position: 0,
            },
            {
              itemId: firstItem.id,
              variationLeafNodeId: firstLeaf.id,
              quantity: 3,
              position: 1,
            },
            {
              itemId: secondItem.id,
              variationLeafNodeId: secondLeaf.id,
              quantity: 5,
              position: 2,
            },
          ],
        },
      );
      assert.equal(created.status, 201);
      assert.equal(created.body.set.name, 'Starter Pack');
      assert.equal(created.body.set.totalItemCount, 10);
      assert.equal(created.body.set.lines.length, 2);
      assert.equal(created.body.set.lines[0].quantity, 5);

      const list = await getJson(baseUrl, '/api/inventory/sets', owner.token);
      assert.equal(list.status, 200);
      assert.equal(list.body.sets.length, 1);
      assert.equal(list.body.sets[0].name, 'Starter Pack');
      assert.equal(list.body.sets[0].totalItemCount, 10);

      const invalid = await postJson(
        baseUrl,
        '/api/inventory/sets',
        owner.token,
        {
          name: 'Broken Pack',
          lines: [
            {
              itemId: firstItem.id,
              variationLeafNodeId: secondLeaf.id,
              quantity: 1,
              position: 0,
            },
          ],
        },
      );
  assert.equal(invalid.status, 400);
  assert.match(
    invalid.body.error,
    /does not belong to the selected item|variation leaf|selected variation path is not valid for this item/i,
  );

      const deleted = await requestJson(
        baseUrl,
        `/api/inventory/sets/${created.body.set.id}`,
        'DELETE',
        owner.token,
        null,
      );
      assert.equal(deleted.status, 200);

      const afterDelete = await getJson(
        baseUrl,
        '/api/inventory/sets',
        owner.token,
      );
      assert.equal(afterDelete.status, 200);
      assert.equal(afterDelete.body.sets.length, 0);
    } finally {
      await closeServer(server);
    }
  } finally {
    await backend.closeDb();
  }
});

test('inventory sets reject mixed valid and invalid lines without partial save', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-inventory-sets-strict-'));
  const dbPath = path.join(tempDir, 'paper.db');
  process.env.DB_PATH = dbPath;
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'sets-strict@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'SetsStrict1234';

  const backend = loadFreshBackend();

  try {
    await backend.resetAndSeedDemoData();
    const itemRows = await backend.getItemsWithUsage();
    const firstRow = itemRows.find((entry) => !entry.is_archived);
    assert.ok(firstRow, 'expected active item');
    const firstItem = await backend.rowToItemDto(firstRow);
    const firstLeaf = findFirstLeafVariation(firstItem.variationTree || []);
    assert.ok(firstLeaf, 'expected orderable leaf');

    const { server, port } = await listen(backend.app);
    const baseUrl = `http://127.0.0.1:${port}`;

    try {
      const owner = await login(
        baseUrl,
        'sets-strict@paper.local',
        'SetsStrict1234',
      );

      const invalid = await postJson(
        baseUrl,
        '/api/inventory/sets',
        owner.token,
        {
          name: 'Mixed Pack',
          lines: [
            {
              itemId: firstItem.id,
              variationLeafNodeId: firstLeaf.id,
              quantity: 2,
              position: 0,
            },
            {
              itemId: firstItem.id,
              variationLeafNodeId: firstLeaf.id,
              quantity: 0,
              position: 1,
            },
          ],
        },
      );

      assert.equal(invalid.status, 400);
      assert.match(invalid.body.error, /set line 2|quantity greater than 0/i);

      const list = await getJson(baseUrl, '/api/inventory/sets', owner.token);
      assert.equal(list.status, 200);
      assert.equal(list.body.sets.length, 0);
    } finally {
      await closeServer(server);
    }
  } finally {
    await backend.closeDb();
  }
});

test('inventory sets allow base items with no variation leaf', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-inventory-sets-base-'));
  const dbPath = path.join(tempDir, 'paper.db');
  process.env.DB_PATH = dbPath;
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'sets-base@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'SetsBase1234';

  const backend = loadFreshBackend();

  try {
    await backend.resetAndSeedDemoData();
    const groupRows = await backend.getGroupsWithUsage();
    const unitRows = await backend.getUnitsWithUsage();
    const groupRow = groupRows.find((entry) => !entry.is_archived);
    const unitRow = unitRows.find((entry) => !entry.is_archived);
    assert.ok(groupRow, 'expected active group');
    assert.ok(unitRow, 'expected active unit');
    const baseItem = await backend.saveItem({
      name: 'Base Set Item',
      displayName: 'Base Set Item',
      groupId: groupRow.id,
      unitId: unitRow.id,
      variationTree: [],
    });

    const { server, port } = await listen(backend.app);
    const baseUrl = `http://127.0.0.1:${port}`;

    try {
      const owner = await login(
        baseUrl,
        'sets-base@paper.local',
        'SetsBase1234',
      );

      const created = await postJson(
        baseUrl,
        '/api/inventory/sets',
        owner.token,
        {
          name: 'Base Item Pack',
          lines: [
            {
              itemId: baseItem.id,
              variationLeafNodeId: 0,
              quantity: 4,
              position: 0,
            },
          ],
        },
      );
      assert.equal(created.status, 201);
      assert.equal(created.body.set.lines.length, 1);
      assert.equal(created.body.set.lines[0].variationLeafNodeId, 0);
      assert.equal(created.body.set.lines[0].variationPathLabel, 'Base item');
      assert.equal(created.body.set.lines[0].quantity, 4);
    } finally {
      await closeServer(server);
    }
  } finally {
    await backend.closeDb();
  }
});

test('a set can be filed under a group, re-filed, and cleared', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-inventory-sets-group-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'sets-group@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'SetsGroup1234';

  const backend = loadFreshBackend();

  try {
    await backend.resetAndSeedDemoData();
    const itemRows = await backend.getItemsWithUsage();
    const itemRow = itemRows.find((entry) => !entry.is_archived);
    assert.ok(itemRow, 'expected an active item');
    const item = await backend.rowToItemDto(itemRow);
    const leaf = findFirstLeafVariation(item.variationTree || []);
    assert.ok(leaf, 'expected a leaf variation');

    const groupRows = await backend.getGroupsWithUsage();
    const activeGroups = groupRows.filter((entry) => !entry.is_archived);
    const homeGroup = activeGroups[0];
    const otherGroup = activeGroups[1];
    assert.ok(homeGroup && otherGroup, 'expected two active groups');

    const { server, port } = await listen(backend.app);
    const baseUrl = `http://127.0.0.1:${port}`;

    try {
      const owner = await login(baseUrl, 'sets-group@paper.local', 'SetsGroup1234');
      const lines = [
        { itemId: item.id, variationLeafNodeId: leaf.id, quantity: 1, position: 0 },
      ];

      const created = await postJson(baseUrl, '/api/inventory/sets', owner.token, {
        name: 'Filed Pack',
        groupId: homeGroup.id,
        lines,
      });
      assert.equal(created.status, 201, JSON.stringify(created.body));
      const setId = created.body.set.id;
      assert.equal(created.body.set.groupId, homeGroup.id);
      assert.equal(created.body.set.groupName, homeGroup.name);
      assert.equal(created.body.set.groupIsArchived, false);

      // The list read resolves the group too, not just the detail read.
      const listed = await getJson(baseUrl, '/api/inventory/sets', owner.token);
      const fromList = listed.body.sets.find((entry) => entry.id === setId);
      assert.equal(fromList.groupId, homeGroup.id);
      assert.equal(fromList.groupName, homeGroup.name);

      // Stored as the canonical pair, which is what the CHECK enforces: a
      // flipped insert would abort the whole save.
      const linkRows = await backend.all(
        `SELECT left_type, left_id, right_type, right_id FROM entity_links
          WHERE (left_type = 'set' AND left_id = ?) OR (right_type = 'set' AND right_id = ?)`,
        [String(setId), String(setId)],
      );
      assert.equal(linkRows.length, 1);
      assert.equal(linkRows[0].left_type, 'group');
      assert.equal(linkRows[0].left_id, String(homeGroup.id));
      assert.equal(linkRows[0].right_type, 'set');

      // Re-filing replaces the link; it does not accumulate a second one.
      const refiled = await requestJson(
        baseUrl,
        `/api/inventory/sets/${setId}`,
        'PATCH',
        owner.token,
        JSON.stringify({ name: 'Filed Pack', groupId: otherGroup.id, lines }),
      );
      assert.equal(refiled.status, 200, JSON.stringify(refiled.body));
      assert.equal(refiled.body.set.groupId, otherGroup.id);
      assert.equal(await setLinkCount(backend, setId), 1);

      // The key absent means "leave the group alone". This is the shape the
      // "add spawned items to a set" path sends, and reading it as a clear
      // would silently unfile the set.
      const untouched = await requestJson(
        baseUrl,
        `/api/inventory/sets/${setId}`,
        'PATCH',
        owner.token,
        JSON.stringify({ name: 'Filed Pack', lines }),
      );
      assert.equal(untouched.status, 200, JSON.stringify(untouched.body));
      assert.equal(untouched.body.set.groupId, otherGroup.id);
      assert.equal(await setLinkCount(backend, setId), 1);

      // Present and null means clear.
      const cleared = await requestJson(
        baseUrl,
        `/api/inventory/sets/${setId}`,
        'PATCH',
        owner.token,
        JSON.stringify({ name: 'Filed Pack', groupId: null, lines }),
      );
      assert.equal(cleared.status, 200, JSON.stringify(cleared.body));
      assert.equal(cleared.body.set.groupId, null);
      assert.equal(cleared.body.set.groupName, null);
      assert.equal(await setLinkCount(backend, setId), 0);

      // Deleting the set takes its links with it.
      const refiledAgain = await requestJson(
        baseUrl,
        `/api/inventory/sets/${setId}`,
        'PATCH',
        owner.token,
        JSON.stringify({ name: 'Filed Pack', groupId: homeGroup.id, lines }),
      );
      assert.equal(refiledAgain.status, 200);
      assert.equal(await setLinkCount(backend, setId), 1);
      const deleted = await requestJson(
        baseUrl,
        `/api/inventory/sets/${setId}`,
        'DELETE',
        owner.token,
        null,
      );
      assert.equal(deleted.status, 200);
      assert.equal(await setLinkCount(backend, setId), 0);
    } finally {
      await closeServer(server);
    }
  } finally {
    await backend.closeDb();
  }
});

test('a set rejects a missing or archived group and survives its group being deleted', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-inventory-sets-group-edge-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'sets-edge@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'SetsEdge1234';

  const backend = loadFreshBackend();

  try {
    await backend.resetAndSeedDemoData();
    const itemRows = await backend.getItemsWithUsage();
    const itemRow = itemRows.find((entry) => !entry.is_archived);
    const item = await backend.rowToItemDto(itemRow);
    const leaf = findFirstLeafVariation(item.variationTree || []);
    const unitRows = await backend.getUnitsWithUsage();
    const unitRow = unitRows.find((entry) => !entry.is_archived);

    // Two groups of this test's own, so deleting and archiving them cannot
    // disturb the demo data the other assertions lean on.
    const doomedGroup = await backend.saveGroup({
      name: 'Doomed Set Group',
      unitId: unitRow.id,
    });
    const archivedGroup = await backend.saveGroup({
      name: 'Retired Set Group',
      unitId: unitRow.id,
    });
    await backend.run('UPDATE groups SET is_archived = 1 WHERE id = ?', [archivedGroup.id]);

    const { server, port } = await listen(backend.app);
    const baseUrl = `http://127.0.0.1:${port}`;

    try {
      const owner = await login(baseUrl, 'sets-edge@paper.local', 'SetsEdge1234');
      const lines = [
        { itemId: item.id, variationLeafNodeId: leaf.id, quantity: 1, position: 0 },
      ];

      for (const badGroupId of [999999, archivedGroup.id]) {
        const rejected = await postJson(baseUrl, '/api/inventory/sets', owner.token, {
          name: `Bad Group Pack ${badGroupId}`,
          groupId: badGroupId,
          lines,
        });
        assert.equal(rejected.status, 400, JSON.stringify(rejected.body));
        assert.equal(
          rejected.body.error,
          'Selected group does not exist or is archived.',
        );
        // Rejected before anything was written.
        const rows = await backend.all(
          'SELECT id FROM inventory_sets WHERE name = ?',
          [`Bad Group Pack ${badGroupId}`],
        );
        assert.equal(rows.length, 0);
      }

      const created = await postJson(baseUrl, '/api/inventory/sets', owner.token, {
        name: 'Orphan Pack',
        groupId: doomedGroup.id,
        lines,
      });
      assert.equal(created.status, 201, JSON.stringify(created.body));
      const setId = created.body.set.id;

      const groupDeleted = await requestJson(
        baseUrl,
        `/api/groups/${doomedGroup.id}`,
        'DELETE',
        owner.token,
        null,
      );
      assert.equal(groupDeleted.status, 200, JSON.stringify(groupDeleted.body));

      // The set still reads, as ungrouped rather than as an id with no name
      // behind it, and the link row is gone rather than orphaned.
      const after = await getJson(baseUrl, `/api/inventory/sets`, owner.token);
      const stillThere = after.body.sets.find((entry) => entry.id === setId);
      assert.ok(stillThere, 'expected the set to survive its group');
      assert.equal(stillThere.groupId, null);
      assert.equal(stillThere.groupName, null);
      assert.equal(await setLinkCount(backend, setId), 0);
    } finally {
      await closeServer(server);
    }
  } finally {
    await backend.closeDb();
  }
});

test('filing a set needs inventory.update alone, not items.update', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-inventory-sets-perm-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'sets-perm@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'SetsPerm1234';

  const backend = loadFreshBackend();

  try {
    await backend.resetAndSeedDemoData();
    const itemRows = await backend.getItemsWithUsage();
    const itemRow = itemRows.find((entry) => !entry.is_archived);
    const item = await backend.rowToItemDto(itemRow);
    const leaf = findFirstLeafVariation(item.variationTree || []);
    const groupRow = (await backend.getGroupsWithUsage()).find((entry) => !entry.is_archived);

    const { server, port } = await listen(backend.app);
    const baseUrl = `http://127.0.0.1:${port}`;

    try {
      const owner = await login(baseUrl, 'sets-perm@paper.local', 'SetsPerm1234');

      // A storekeeper who runs inventory and may not touch the items master.
      // Filing a set through POST /api/links would need items.update as well,
      // because the link catalog maps a group to the items module; through the
      // set endpoint it must not.
      const created = await postJson(baseUrl, '/api/users', owner.token, {
        name: 'Store Keeper',
        email: 'store-keeper@paper.local',
        password: 'KeeperPass1234',
        role: 'user',
        permissions: ['inventory.read', 'inventory.create', 'login.desktop'],
      });
      assert.equal(created.status, 201, JSON.stringify(created.body));
      const keeperId = created.body.user.id;
      const grid = await requestJson(
        baseUrl,
        `/api/users/${keeperId}/permissions`,
        'PATCH',
        owner.token,
        JSON.stringify({
          overrides: [
            { key: 'inventory.create', allowed: true },
            { key: 'inventory.update', allowed: true },
            { key: 'items.update', allowed: false },
          ],
        }),
      );
      assert.equal(grid.status, 200, JSON.stringify(grid.body));

      const keeper = await login(baseUrl, 'store-keeper@paper.local', 'KeeperPass1234');
      const filed = await postJson(baseUrl, '/api/inventory/sets', keeper.token, {
        name: 'Keeper Pack',
        groupId: groupRow.id,
        lines: [
          { itemId: item.id, variationLeafNodeId: leaf.id, quantity: 1, position: 0 },
        ],
      });
      assert.equal(filed.status, 201, JSON.stringify(filed.body));
      assert.equal(filed.body.set.groupId, groupRow.id);
    } finally {
      await closeServer(server);
    }
  } finally {
    await backend.closeDb();
  }
});

async function setLinkCount(backend, setId) {
  const rows = await backend.all(
    `SELECT id FROM entity_links
      WHERE (left_type = 'set' AND left_id = ?) OR (right_type = 'set' AND right_id = ?)`,
    [String(setId), String(setId)],
  );
  return rows.length;
}

test('a set save carries the version it was opened at', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-inventory-sets-version-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'sets-version@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'SetsVersion1234';

  const backend = loadFreshBackend();

  try {
    await backend.resetAndSeedDemoData();
    const itemRows = await backend.getItemsWithUsage();
    const first = itemRows.find((entry) => !entry.is_archived);
    const second = itemRows.find(
      (entry) => !entry.is_archived && entry.id !== first.id,
    );
    const firstItem = await backend.rowToItemDto(first);
    const secondItem = await backend.rowToItemDto(second);
    const firstLeaf = findFirstLeafVariation(firstItem.variationTree || []);
    const secondLeaf = findFirstLeafVariation(secondItem.variationTree || []);

    const { server, port } = await listen(backend.app);
    const baseUrl = `http://127.0.0.1:${port}`;

    try {
      const owner = await login(
        baseUrl,
        'sets-version@paper.local',
        'SetsVersion1234',
      );
      const line = (item, leaf, quantity, position) => ({
        itemId: item.id,
        variationLeafNodeId: leaf.id,
        quantity,
        position,
      });

      const created = await postJson(baseUrl, '/api/inventory/sets', owner.token, {
        name: 'Contested Kit',
        lines: [line(firstItem, firstLeaf, 1, 0)],
      });
      assert.equal(created.status, 201, JSON.stringify(created.body));
      const setId = created.body.set.id;
      // A set every client has seen starts at the same number.
      assert.equal(created.body.set.version, 0);

      const patch = (body) =>
        requestJson(
          baseUrl,
          `/api/inventory/sets/${setId}`,
          'PATCH',
          owner.token,
          JSON.stringify(body),
        );

      // Two people open it. The first saves.
      const firstSave = await patch({
        name: 'Contested Kit',
        expectedVersion: 0,
        lines: [line(firstItem, firstLeaf, 9, 0)],
      });
      assert.equal(firstSave.status, 200, JSON.stringify(firstSave.body));
      assert.equal(firstSave.body.set.version, 1, 'a save moves the version on');

      // The second still holds version 0 and would replace what just landed.
      const stale = await patch({
        name: 'Contested Kit',
        expectedVersion: 0,
        lines: [line(secondItem, secondLeaf, 3, 0)],
      });
      assert.equal(stale.status, 409, JSON.stringify(stale.body));
      assert.equal(stale.body.code, 'set_changed');
      assert.match(stale.body.error, /Contested Kit/);

      // The assertion that actually proves the hole is closed: the first
      // writer's lines are still there.
      const after = await getJson(baseUrl, '/api/inventory/sets', owner.token);
      const row = after.body.sets.find((entry) => entry.id === setId);
      assert.equal(row.lines.length, 1);
      assert.equal(row.lines[0].itemId, firstItem.id);
      assert.equal(row.lines[0].quantity, 9);
      assert.equal(row.version, 1);

      // Reloading and trying again goes through.
      const retry = await patch({
        name: 'Contested Kit',
        expectedVersion: 1,
        lines: [line(secondItem, secondLeaf, 3, 0)],
      });
      assert.equal(retry.status, 200, JSON.stringify(retry.body));
      assert.equal(retry.body.set.version, 2);

      // A caller that says nothing about the version still replaces, which is
      // what every pre-version client and the seeders rely on.
      const unversioned = await patch({
        name: 'Contested Kit',
        lines: [line(firstItem, firstLeaf, 4, 0)],
      });
      assert.equal(unversioned.status, 200, JSON.stringify(unversioned.body));
      assert.equal(unversioned.body.set.version, 3);

      // A rename and a re-file each move it on too, leaving the group
      // tri-state alone.
      const groupRows = await backend.getGroupsWithUsage();
      const group = groupRows.find((entry) => !entry.is_archived);
      const renamed = await patch({
        name: 'Contested Kit Mk2',
        expectedVersion: 3,
        lines: [line(firstItem, firstLeaf, 4, 0)],
      });
      assert.equal(renamed.body.set.version, 4);
      assert.equal(renamed.body.set.groupId, null, 'no groupId key, no re-file');
      const filed = await patch({
        name: 'Contested Kit Mk2',
        groupId: group.id,
        expectedVersion: 4,
        lines: [line(firstItem, firstLeaf, 4, 0)],
      });
      assert.equal(filed.body.set.version, 5);
      assert.equal(filed.body.set.groupId, group.id);
    } finally {
      await closeServer(server);
    }
  } finally {
    await backend.closeDb();
  }
});

function findFirstLeafVariation(nodes, currentPath = []) {
  for (const node of nodes || []) {
    const nextPath =
      node.kind === 'value' ? [...currentPath, node.id] : currentPath;
    if (node.kind === 'value' && (!node.children || node.children.length === 0)) {
      return { ...node, path: nextPath };
    }
    const nested = findFirstLeafVariation(node.children || [], nextPath);
    if (nested) {
      return nested;
    }
  }
  return null;
}

async function login(baseUrl, email, password) {
  const response = await postJson(baseUrl, '/api/auth/login', null, {
    email,
    password,
  });
  assert.equal(response.status, 200);
  return response.body;
}

async function listen(app) {
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  return { server, port: address.port };
}

async function closeServer(server) {
  await new Promise((resolve, reject) =>
    server.close((error) => (error ? reject(error) : resolve())),
  );
}

async function getJson(baseUrl, pathname, token) {
  return requestJson(baseUrl, pathname, 'GET', token, null);
}

async function postJson(baseUrl, pathname, token, body) {
  return requestJson(baseUrl, pathname, 'POST', token, JSON.stringify(body));
}

async function requestJson(baseUrl, pathname, method, token, body) {
  const target = new URL(pathname, baseUrl);
  const headers = { Accept: 'application/json' };
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }
  if (body != null) {
    headers['Content-Type'] = 'application/json';
    headers['Content-Length'] = Buffer.byteLength(body);
  }
  const response = await fetch(target, { method, headers, body });
  const text = await response.text();
  return {
    status: response.status,
    body: text ? JSON.parse(text) : null,
  };
}
