const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

test('delivery challans create issue and preserve company profile snapshot', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-delivery-challans-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');

  const backend = require('../server.js');
  try {
    await backend.initDb();
    const actor = { id: 1, name: 'Delivery Tester', role: 'admin' };

    const profile = await backend.getActiveCompanyProfile();
    assert.equal(profile.company_name, 'Shree Ganesh Metal Works');
    const orders = await backend.getOrders();
    assert.ok(orders.length > 0, 'expected seeded orders for challan creation');
    const order = orders[0];

    const created = await backend.saveDeliveryChallan(
      {
        order_id: order.id,
        date: '2026-05-04',
        notes: '',
        items: [
          {
            order_item_id: order.id,
            quantity_pcs: '10',
            weight: '2.5',
          },
        ],
      },
      actor,
      { user: actor },
    );
    assert.match(created.challan_no, /^DC-/);
    assert.equal(created.order_id, order.id);
    assert.equal(created.customer_name, order.client_name);
    assert.equal(created.status, 'draft');

    const issued = await backend.issueDeliveryChallan(created.id, actor);
    assert.equal(issued.status, 'issued');

    await backend.saveCompanyProfile({
      company_name: 'Changed Company',
      mobile: '1',
    });

    const issuedRow = await backend.get(
      'SELECT company_profile_snapshot FROM delivery_challans WHERE id = ?',
      [created.id],
    );
    const snapshot = JSON.parse(issuedRow.company_profile_snapshot);
    assert.equal(snapshot.company_name, 'Shree Ganesh Metal Works');

    const empty = await backend.saveDeliveryChallan(
      { order_id: order.id, date: '2026-05-04', items: [] },
      actor,
      { user: actor },
    );
    await assert.rejects(
      () => backend.issueDeliveryChallan(empty.id, actor),
      /Add at least one line item before issuing challan/,
    );
  } finally {
    await backend.closeDb();
  }
});
