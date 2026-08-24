const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

const { coverBasis } = require('../modules/items/group-covers');

// A group card is made of the items inside it, because a group has no photo of
// its own. What matters is that the items chosen are the RIGHT ones, and that
// the card is honest about why they were chosen — a recency fallback dressed up
// as a popularity ranking would be worse than no card at all.

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

test('the basis says whether a cover is popularity or just recency', () => {
  assert.equal(coverBasis([]), 'empty');
  assert.equal(coverBasis(null), 'empty');
  assert.equal(coverBasis([{ orderCount: 0 }, { orderCount: 0 }]), 'recent');
  assert.equal(coverBasis([{ orderCount: 3 }, { orderCount: 0 }]), 'ordered');
});

test('group covers rank by orders, then fall back to what is newest', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-group-covers-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'covers@paper.local';
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
    const authHeaders = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    };
    const get = async (p) => {
      const r = await fetch(`${baseUrl}${p}`, { headers: authHeaders });
      return { status: r.status, body: await r.json() };
    };

    // The table view must not pay for covers it does not draw.
    const plain = await get('/api/groups');
    assert.equal(plain.status, 200);
    assert.ok(plain.body.groups.length > 0);
    for (const group of plain.body.groups) {
      assert.equal(group.coverItems, undefined, 'covers are opt-in');
      assert.equal(group.coverBasis, undefined);
      // The count is not opt-in, though: the table shows it on every row, and
      // it is one GROUP BY rather than a read of item rows per group.
      assert.equal(
        typeof group.itemCount,
        'number',
        `${group.name} must carry an item count without asking for covers`,
      );
    }
    assert.ok(
      plain.body.groups.some((group) => group.itemCount > 0),
      'the seed has at least one group with items in it',
    );

    // And asking for covers must not change what the count says.
    const countsPlain = new Map(
      plain.body.groups.map((group) => [group.id, group.itemCount]),
    );

    const withCovers = await get('/api/groups?withCovers=1');
    assert.equal(withCovers.status, 200);
    const groups = withCovers.body.groups;
    for (const group of groups) {
      assert.ok(Array.isArray(group.coverItems), `${group.name} has a cover list`);
      assert.ok(group.coverItems.length <= 4, 'a mosaic holds four at most');
      assert.ok(['ordered', 'recent', 'empty'].includes(group.coverBasis));
      // An empty group says so rather than borrowing another group's items.
      if (group.coverItems.length === 0) {
        assert.equal(group.coverBasis, 'empty');
      }
      for (const cover of group.coverItems) {
        assert.ok(cover.itemId > 0);
        assert.ok(typeof cover.name === 'string');
        assert.ok(typeof cover.photoUrl === 'string');
        assert.ok(Number.isFinite(cover.orderCount));
      }
    }

    for (const group of groups) {
      assert.equal(
        group.itemCount,
        countsPlain.get(group.id),
        `${group.name} counts the same either way`,
      );
    }

    const populated = groups.find((group) => group.coverItems.length > 0);
    assert.ok(populated, 'the seed has at least one group with items');

    // Ranked, not arbitrary: order counts descend across the mosaic.
    const counts = populated.coverItems.map((cover) => cover.orderCount);
    const descending = [...counts].sort((a, b) => b - a);
    assert.deepEqual(counts, descending, 'the most ordered item comes first');

    // Cover items really belong to their group — the partition is per group,
    // and a cross-group leak is exactly what a bad window function would give.
    const items = await get('/api/items');
    const groupOf = new Map(
      items.body.items.map((item) => [item.id, item.groupId])
    );
    for (const group of groups) {
      for (const cover of group.coverItems) {
        assert.equal(
          groupOf.get(cover.itemId),
          group.id,
          `${cover.name} is on the wrong group's card`
        );
      }
    }

    // No archived item is ever shown on a card.
    const archivedIds = new Set(
      items.body.items.filter((item) => item.isArchived).map((item) => item.id)
    );
    for (const group of groups) {
      for (const cover of group.coverItems) {
        assert.equal(archivedIds.has(cover.itemId), false);
      }
    }
  } finally {
    await closeServer(server);
  }
});
