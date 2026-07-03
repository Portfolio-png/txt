const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

test('stage reconciliation metrics persist to stage_reconciliations table', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-stage-recon-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  try {
    await backend.initDb();

    const nodesJson = JSON.stringify([
      {
        id: 'node-b',
        name: 'Cutting',
        stageIndex: 0,
        processType: 'cut',
        machine: 'M-01',
        dieId: 'D-1',
        durationHours: 2,
        inputItem: { itemId: 1, itemName: 'Copper Sheet', unitId: 1, unitName: 'Kilogram', unitSymbol: 'kg' },
        outputItem: { itemId: 2, itemName: 'Blank', unitId: 2, unitName: 'Pieces', unitSymbol: 'pcs' },
      },
    ]);
    await backend.run(
      `INSERT INTO pipeline_templates (id, name, stage_labels_json, lane_labels_json, nodes_json, flows_json)
       VALUES ('tpl-recon', 'Recon Template', '[]', '[]', ?, '[]')`,
      [nodesJson],
    );
    // Legacy run whose metrics live only in the JSON blob.
    await backend.run(
      `INSERT INTO pipeline_runs (id, template_id, template_version, node_metrics_json)
       VALUES ('run-recon', 'tpl-recon', 1, ?)`,
      [JSON.stringify({ 'node-a': { allotted: 10, output: 8, scrap: 2 } })],
    );

    await backend.backfillStageReconciliations();
    const legacy = await backend.get(
      "SELECT * FROM stage_reconciliations WHERE run_id = 'run-recon' AND node_id = 'node-a'",
    );
    assert.ok(legacy, 'backfill should copy blob metrics into the table');
    assert.equal(legacy.allotted, 10);
    assert.equal(legacy.output, 8);
    assert.equal(legacy.scrap, 2);

    const server = await new Promise((resolve) => {
      const s = backend.app.listen(0, '127.0.0.1', () => resolve(s));
    });
    try {
      const base = `http://127.0.0.1:${server.address().port}`;

      const loginRes = await fetch(`${base}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: 'super@paper.local', password: 'Paper@12345' }),
      });
      const login = await loginRes.json();
      const authHeaders = {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${login.token || login.data?.token}`,
      };

      const res = await fetch(`${base}/runs/run-recon/node-metrics`, {
        method: 'PUT',
        headers: authHeaders,
        body: JSON.stringify({
          nodeId: 'node-b',
          metrics: {
            allotted: 5.5,
            output: 5,
            remaining: 0.5,
            inputTime: '2026-07-02T10:00:00',
            outputTime: '2026-07-02T12:00:00',
          },
        }),
      });
      const payload = await res.json();
      assert.equal(payload.success, true);
      assert.equal(payload.run.nodeMetrics['node-b'].output, 5);
      assert.equal(payload.run.nodeMetrics['node-b'].remaining, 0.5);
      assert.equal(payload.run.nodeMetrics['node-a'].allotted, 10, 'legacy blob metrics still visible');

      const rowB = await backend.get(
        "SELECT * FROM stage_reconciliations WHERE run_id = 'run-recon' AND node_id = 'node-b'",
      );
      assert.equal(rowB.leftover, 0.5);
      assert.equal(rowB.input_time, '2026-07-02T10:00:00');

      const blob = await backend.get(
        "SELECT node_metrics_json FROM pipeline_runs WHERE id = 'run-recon'",
      );
      assert.ok(
        !String(blob.node_metrics_json).includes('node-b'),
        'endpoint must not write the JSON blob anymore',
      );

      // Partial update (editable metric box sends a single key) merges in place.
      await fetch(`${base}/runs/run-recon/node-metrics`, {
        method: 'PUT',
        headers: authHeaders,
        body: JSON.stringify({ nodeId: 'node-b', metrics: { output: 4 } }),
      });
      const rowB2 = await backend.get(
        "SELECT * FROM stage_reconciliations WHERE run_id = 'run-recon' AND node_id = 'node-b'",
      );
      assert.equal(rowB2.output, 4);
      assert.equal(rowB2.allotted, 5.5, 'partial update must keep other columns');

      // Production report joins order -> run -> template nodes -> reconciliations.
      await backend.run(
        `INSERT INTO clients (name, created_at, updated_at)
         VALUES ('Recon Client', datetime('now'), datetime('now'))`,
      );
      const client = await backend.get(
        "SELECT id FROM clients WHERE name = 'Recon Client'",
      );
      await backend.run(
        `INSERT INTO items (name, display_name, group_id, unit_id, created_at, updated_at)
         VALUES ('Recon Item', 'Recon Item', 1, 1, datetime('now'), datetime('now'))`,
      );
      const item = await backend.get(
        "SELECT id FROM items WHERE name = 'Recon Item'",
      );
      await backend.run(
        `INSERT INTO order_headers (order_no, client_id, po_number, created_at, updated_at)
         VALUES ('ORD-RECON', ?, '', datetime('now'), datetime('now'))`,
        [client.id],
      );
      await backend.run(
        `INSERT INTO order_items (order_no, client_id, item_id, item_name, quantity, unit_symbol, unit_price, created_at)
         VALUES ('ORD-RECON', ?, ?, 'Recon Item', 22, 'pcs', 5, datetime('now'))`,
        [client.id, item.id],
      );
      const orderItem = await backend.get(
        "SELECT id FROM order_items WHERE order_no = 'ORD-RECON'",
      );
      await backend.run(
        `INSERT INTO order_pipeline_assignments (order_item_id, pipeline_run_id, allocated_quantity, created_at)
         VALUES (?, 'run-recon', 22, datetime('now'))`,
        [orderItem.id],
      );

      const reportRes = await fetch(
        `${base}/api/orders/ORD-RECON/production-report`,
        { headers: authHeaders },
      );
      const reportPayload = await reportRes.json();
      assert.equal(reportPayload.success, true);
      const report = reportPayload.report;
      assert.equal(report.orderNo, 'ORD-RECON');
      assert.equal(report.items[0].quantity, 22);
      assert.equal(report.items[0].unitPrice, 5);
      assert.equal(report.runs.length, 1);
      const stage = report.runs[0].stages[0];
      assert.equal(stage.material, 'Copper Sheet');
      assert.equal(stage.machine, 'M-01');
      assert.equal(stage.dieId, 'D-1');
      assert.equal(stage.allotted, 5.5);
      assert.equal(stage.output, 4);
    } finally {
      await new Promise((resolve) => server.close(resolve));
    }
  } finally {
    if (backend.closeDb) {
      await backend.closeDb().catch(() => {});
    }
  }
});
