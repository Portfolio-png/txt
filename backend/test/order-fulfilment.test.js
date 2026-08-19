const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// The order-book fulfilment rollup: one request for every order line's
// ordered / delivered / produced position.

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
    server.on('error', reject);
  });
}
function closeServer(server) {
  return new Promise((resolve, reject) =>
    server.close((e) => (e ? reject(e) : resolve())));
}

test('order fulfilment rollup reports ordered, delivered and produced per line', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-fulfilment-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'fulfil@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('/Users/rutuparnpuranik/Paper/backend/server.js')];
  const backend = require('/Users/rutuparnpuranik/Paper/backend/server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const login = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'fulfil@paper.local', password: 'OwnerPass1234' }),
    });
    const { token } = await login.json();
    assert.ok(token);

    const res = await fetch(`${baseUrl}/api/orders/fulfilment`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.success, true);
    assert.ok(Array.isArray(body.fulfilment), 'fulfilment must be a list');

    // The default demo seed must NOT report every order as routeless: the
    // Order Book shows these as In Progress / Completed, and Insights reading
    // the same dataset has to agree with it.
    const linked = body.fulfilment.filter((row) => row.runCount > 0);
    assert.ok(
      linked.length >= 3,
      `default seed must attach runs to its order lines, got ${linked.length}`,
    );
    const statuses = new Set(linked.map((row) => row.runStatus));
    assert.ok(statuses.has('inProgress'), 'one demo order must be mid-production');
    assert.ok(statuses.has('completed'), 'one demo order must be finished');
    assert.ok(statuses.has('notStarted'), 'one demo order must be queued');
    // And the floor figures must actually come through, or the made row on the
    // card is dead weight.
    const made = body.fulfilment.filter((row) => row.producedQty > 0);
    assert.ok(made.length > 0, 'demo seed must carry stage reconciliations');
    for (const row of made) {
      assert.ok(row.producedUnit.length > 0, 'made must be labelled with a unit');
    }

    // The demo seed has orders; every row must carry the full shape.
    assert.ok(body.fulfilment.length > 0, 'expected seeded order lines');
    for (const row of body.fulfilment) {
      assert.equal(typeof row.orderItemId, 'number');
      assert.equal(typeof row.orderedQty, 'number');
      assert.equal(typeof row.deliveredQty, 'number');
      assert.equal(typeof row.producedQty, 'number');
      assert.ok(row.deliveredQty >= 0);
      assert.ok(row.producedQty >= 0);
      assert.ok(['none', 'notStarted', 'inProgress', 'completed'].includes(row.runStatus));
    }

    // Produced is never silently converted into the ordered unit, and the unit
    // is never guessed: it is either what the terminal stage declared, or empty
    // to say "unknown" — in which case the client refuses to draw a bar.
    for (const row of body.fulfilment) {
      assert.equal(typeof row.producedUnit, 'string');
    }
  } finally {
    await closeServer(server);
  }
});

test('scenario_c seeds every state the insights screen can show', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-scenario-c-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'scenc@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('/Users/rutuparnpuranik/Paper/backend/server.js')];
  const backend = require('/Users/rutuparnpuranik/Paper/backend/server.js');
  await backend.resetAndSeedDemoData('scenario_c');
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const login = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'scenc@paper.local', password: 'OwnerPass1234' }),
    });
    const { token } = await login.json();
    const auth = { Authorization: `Bearer ${token}` };

    const res = await fetch(`${baseUrl}/api/orders/fulfilment`, { headers: auth });
    const body = await res.json();
    assert.equal(body.success, true);

    const byNo = new Map(body.fulfilment.map((row) => [row.orderNo, row]));
    for (const no of ['SIM-C-1001', 'SIM-C-1002', 'SIM-C-1003', 'SIM-C-1004',
      'SIM-C-1005', 'SIM-C-1006', 'SIM-C-1007']) {
      assert.ok(byNo.has(no), `scenario_c must seed ${no}`);
    }

    // Top row of the insights screen: no run attached at all.
    for (const no of ['SIM-C-1001', 'SIM-C-1002']) {
      assert.equal(byNo.get(no).runCount, 0, `${no} must have no pipeline`);
      assert.equal(byNo.get(no).runStatus, 'none');
    }

    // Bottom row: a run exists, in each of its three states.
    assert.equal(byNo.get('SIM-C-1003').runStatus, 'notStarted');
    assert.equal(byNo.get('SIM-C-1004').runStatus, 'inProgress');
    assert.equal(byNo.get('SIM-C-1007').runStatus, 'completed');

    // C4 — terminal stage reports pieces, the same unit the line was ordered
    // in, so the client is allowed to draw produced against ordered.
    const c4 = byNo.get('SIM-C-1004');
    assert.equal(c4.orderedQty, 1000);
    assert.ok(c4.orderedUnit.length > 0);
    assert.equal(c4.producedQty, 620, 'produced must be the terminal good yield');
    assert.equal(c4.producedUnit, c4.orderedUnit, 'C4 is the matching-unit case');
    assert.equal(c4.scrapQty, 35);
    assert.equal(c4.deliveredQty, 250);

    // C5 — terminal stage reports kilograms against a pieces order. The rollup
    // must report the floor's own unit, NOT the ordered one; this is the pair
    // that proves nothing is being silently converted.
    const c5 = byNo.get('SIM-C-1005');
    assert.equal(c5.producedQty, 1240);
    assert.ok(c5.producedUnit.length > 0, 'the floor unit must be named');
    assert.notEqual(
      c5.producedUnit, c5.orderedUnit,
      'C5 is the mismatched-unit case: produced must keep the floor unit',
    );
    assert.equal(c5.deliveredQty, 150);

    // C6 — running for weeks with nothing delivered: the Stalled case.
    const c6 = byNo.get('SIM-C-1006');
    assert.equal(c6.runStatus, 'inProgress');
    assert.equal(c6.deliveredQty, 0);

    // Each delivery must come back as its own checkpoint, carrying the id the
    // client needs to open it and the position it sits at on the bar.
    assert.ok(Array.isArray(c4.deliveries), 'deliveries must be a list');
    assert.equal(c4.deliveries.length, 1, 'C4 had one challan');
    const [d4] = c4.deliveries;
    assert.ok(d4.challanId > 0, 'a checkpoint must name the challan to open');
    assert.equal(d4.challanNo, 'SIM-C-DEL-1004');
    assert.equal(d4.quantity, 250);
    assert.equal(d4.cumulativeQty, 250);
    assert.equal(d4.status, 'issued');
    assert.ok(d4.date, 'a checkpoint must carry its date');

    // The headline total is derived from the same rows, so they cannot drift.
    for (const row of body.fulfilment) {
      const summed = row.deliveries.reduce((total, d) => total + d.quantity, 0);
      assert.equal(
        Math.round(summed * 100),
        Math.round(row.deliveredQty * 100),
        `${row.orderNo}: delivered total must equal its checkpoints`,
      );
      let running = 0;
      for (const delivery of row.deliveries) {
        running += delivery.quantity;
        assert.equal(
          Math.round(delivery.cumulativeQty * 100),
          Math.round(running * 100),
          'cumulative must be the running sum, oldest first',
        );
      }
    }

    // C7 — fully delivered against the ordered quantity.
    const c7 = byNo.get('SIM-C-1007');
    assert.equal(c7.deliveredQty, c7.orderedQty);

    // Produced counts the terminal stage only. Summing all three stages would
    // triple-count the same material, so assert it did not.
    assert.ok(c4.producedQty < 1000, 'terminal stage only, not a sum of stages');

    // The age filters need a spread of order dates to mean anything.
    const orders = await (await fetch(`${baseUrl}/api/orders`, { headers: auth })).json();
    const list = Array.isArray(orders) ? orders : (orders.orders || []);
    const dated = list.filter((o) => String(o.orderNo || '').startsWith('SIM-C-'));
    assert.ok(dated.length >= 7, 'scenario_c orders must be readable from the order book');
    const ages = dated.map((o) =>
      Math.round((Date.now() - new Date(o.createdAt).getTime()) / 86400000));
    assert.ok(Math.max(...ages) >= 30, 'needs an order old enough to be Old');
    assert.ok(Math.max(...ages) - Math.min(...ages) >= 20, 'needs a spread of dates');
  } finally {
    await closeServer(server);
  }
});
