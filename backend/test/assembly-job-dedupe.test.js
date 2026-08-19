const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// Reaching an Assembly node pushes the stage into the freelancer job pool so
// it can be assigned to workers. A node's status can be re-set any number of
// times (re-queued, reopened, a second pass), and that must not fan out into
// duplicate jobs for the same stage of the same run.

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

async function firstItemId(baseUrl, auth) {
  const res = await fetch(`${baseUrl}/api/items`, { headers: auth });
  const body = await res.json();
  const items = body.items || body.data || body;
  assert.ok(Array.isArray(items) && items.length > 0, 'demo seed must provide items');
  return items[0].id;
}

function templatePayload(id, outputItemId) {
  return {
    id,
    name: 'Assembly dedupe template',
    version: 1,
    status: 'active',
    stageLabels: ['Input', 'Assembly', 'Output'],
    laneLabels: ['Lane 1'],
    nodes: [
      {
        id: 'n-input', name: 'Input', processType: 'Input',
        stageIndex: 0, laneIndex: 0, inputs: [], outputs: ['raw'],
        machine: '', dieId: '', durationHours: 0, status: 'idle',
        isIntermediate: false,
        outputItem: { itemId: outputItemId, itemName: 'raw' },
      },
      {
        id: 'n-assembly', name: 'Fit and rivet', processType: 'Assembly',
        stageIndex: 1, laneIndex: 0, inputs: ['raw'], outputs: ['assembled'],
        machine: '', dieId: '', durationHours: 1, status: 'idle',
        isIntermediate: false,
        // Deliberately binds nothing — an assembly step is a merge point with
        // no item, machine or die of its own. The job's item comes from the
        // order the run is building, or from the steps feeding it.
      },
      {
        id: 'n-output', name: 'Output', processType: 'Output',
        stageIndex: 2, laneIndex: 0, inputs: ['assembled'], outputs: [],
        machine: '', dieId: '', durationHours: 0, status: 'idle',
        isIntermediate: false,
      },
    ],
    flows: [
      { id: 'f1', fromNodeId: 'n-input', toNodeId: 'n-assembly' },
      { id: 'f2', fromNodeId: 'n-assembly', toNodeId: 'n-output' },
    ],
  };
}

test('an Assembly node raises exactly one job however often its status is re-set', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-assembly-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'assembly@paper.local';
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
      body: JSON.stringify({
        email: 'assembly@paper.local',
        password: 'OwnerPass1234',
      }),
    });
    const { token } = await login.json();
    assert.ok(token);
    const auth = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };

    const countJobs = async () => {
      const res = await fetch(`${baseUrl}/api/freelancer-jobs`, { headers: auth });
      const body = await res.json();
      return body.jobs.filter((job) => job.node_id === 'n-assembly');
    };

    const templateId = 'tpl-assembly-dedupe';
    const outputItemId = await firstItemId(baseUrl, auth);
    const created = await fetch(`${baseUrl}/templates`, {
      method: 'POST',
      headers: auth,
      body: JSON.stringify(templatePayload(templateId, outputItemId)),
    });
    const createdBody = await created.json();
    assert.equal(created.status, 201, JSON.stringify(createdBody));

    const runRes = await fetch(`${baseUrl}/runs`, {
      method: 'POST',
      headers: auth,
      body: JSON.stringify({ templateId, name: 'Assembly dedupe run' }),
    });
    const runBody = await runRes.json();
    assert.equal(runRes.status, 201, JSON.stringify(runBody));
    const runId = runBody.run.id;

    const setStatus = (status, batchQuantity) =>
      fetch(`${baseUrl}/runs/${runId}/node-status`, {
        method: 'PUT',
        headers: auth,
        body: JSON.stringify({ nodeId: 'n-assembly', status, batchQuantity }),
      });

    assert.equal((await countJobs()).length, 0, 'no job before the node is reached');

    assert.equal((await setStatus('ready', 10)).status, 200);
    const afterFirst = await countJobs();
    assert.equal(afterFirst.length, 1, 'reaching the node opens one job');
    assert.equal(afterFirst[0].status, 'pending');
    assert.equal(afterFirst[0].batch_id, null, 'lands unassigned in the pool');
    assert.equal(afterFirst[0].run_id, runId);

    // Re-set the same node repeatedly, including a different quantity.
    assert.equal((await setStatus('active')).status, 200);
    assert.equal((await setStatus('queued')).status, 200);
    assert.equal((await setStatus('ready', 25)).status, 200);

    const afterRepeats = await countJobs();
    assert.equal(afterRepeats.length, 1, 'still exactly one job for this stage');
    assert.equal(afterRepeats[0].id, afterFirst[0].id, 'and it is the same job row');
    assert.equal(
      afterRepeats[0].quantity,
      25,
      'an untouched pending job tracks the latest batch quantity',
    );
  } finally {
    await closeServer(server);
  }
});

test('a job already assigned to a freelancer is not rewritten when the node is re-set', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-assembly-assigned-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'assembly2@paper.local';
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
      body: JSON.stringify({
        email: 'assembly2@paper.local',
        password: 'OwnerPass1234',
      }),
    });
    const { token } = await login.json();
    const auth = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };

    const templateId = 'tpl-assembly-assigned';
    const outputItemId = await firstItemId(baseUrl, auth);
    const created = await fetch(`${baseUrl}/templates`, {
      method: 'POST',
      headers: auth,
      body: JSON.stringify(templatePayload(templateId, outputItemId)),
    });
    assert.equal(created.status, 201, JSON.stringify(await created.json()));

    const runRes = await fetch(`${baseUrl}/runs`, {
      method: 'POST',
      headers: auth,
      body: JSON.stringify({ templateId, name: 'Assembly assigned run' }),
    });
    const runBody = await runRes.json();
    assert.equal(runRes.status, 201, JSON.stringify(runBody));
    const runId = runBody.run.id;

    const statusRes = await fetch(`${baseUrl}/runs/${runId}/node-status`, {
      method: 'PUT',
      headers: auth,
      body: JSON.stringify({ nodeId: 'n-assembly', status: 'ready', batchQuantity: 10 }),
    });
    assert.equal(statusRes.status, 200, JSON.stringify(await statusRes.json()));

    const jobsRes = await fetch(`${baseUrl}/api/freelancer-jobs`, { headers: auth });
    const job = (await jobsRes.json()).jobs.find((j) => j.node_id === 'n-assembly');
    assert.ok(job, 'the assembly job exists');

    // Assign it to a freelancer — this is what the Jobs tab's batch flow does.
    const batchRes = await fetch(`${baseUrl}/api/freelancer-jobs/batches`, {
      method: 'POST',
      headers: auth,
      body: JSON.stringify({ freelancer_id: null, job_ids: [job.id] }),
    });
    assert.equal(batchRes.status, 200, JSON.stringify(await batchRes.json()));

    // Re-set the node with a different quantity; assigned work must survive.
    await fetch(`${baseUrl}/runs/${runId}/node-status`, {
      method: 'PUT',
      headers: auth,
      body: JSON.stringify({ nodeId: 'n-assembly', status: 'ready', batchQuantity: 99 }),
    });

    const afterRes = await fetch(`${baseUrl}/api/freelancer-jobs`, { headers: auth });
    const after = (await afterRes.json()).jobs.filter((j) => j.node_id === 'n-assembly');
    assert.equal(after.length, 1, 'no second job is raised alongside the assigned one');
    assert.equal(after[0].id, job.id);
    assert.ok(after[0].batch_id !== null, 'stays batched to its freelancer');
    assert.equal(after[0].quantity, 10, 'assigned work keeps the quantity it was given');
  } finally {
    await closeServer(server);
  }
});

test('a supervisor booking scrap on an assembly stage rejects it on the worker job', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-assembly-reject-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'assembly3@paper.local';
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
      body: JSON.stringify({
        email: 'assembly3@paper.local',
        password: 'OwnerPass1234',
      }),
    });
    const { token } = await login.json();
    const auth = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };

    const templateId = 'tpl-assembly-reject';
    const outputItemId = await firstItemId(baseUrl, auth);
    await fetch(`${baseUrl}/templates`, {
      method: 'POST', headers: auth,
      body: JSON.stringify(templatePayload(templateId, outputItemId)),
    });
    const runBody = await (await fetch(`${baseUrl}/runs`, {
      method: 'POST', headers: auth,
      body: JSON.stringify({ templateId, name: 'Assembly reject run' }),
    })).json();
    const runId = runBody.run.id;

    await fetch(`${baseUrl}/runs/${runId}/node-status`, {
      method: 'PUT', headers: auth,
      body: JSON.stringify({ nodeId: 'n-assembly', status: 'ready', batchQuantity: 100 }),
    });

    const jobOf = async () => {
      const body = await (await fetch(`${baseUrl}/api/freelancer-jobs`, { headers: auth })).json();
      return body.jobs.find((j) => j.node_id === 'n-assembly');
    };

    const before = await jobOf();
    assert.ok(before, 'the assembly job exists');
    assert.equal(before.rejected_quantity, 0, 'nothing rejected before reconciliation');

    // The supervisor reconciles the stage: 100 allotted, 7 came off rejected.
    const recon = await fetch(`${baseUrl}/runs/${runId}/node-metrics`, {
      method: 'PUT', headers: auth,
      body: JSON.stringify({
        nodeId: 'n-assembly',
        metrics: { allotted: 100, output: 93, scrap: 7, scrapItem: 'Reject bin' },
      }),
    });
    assert.equal(recon.status, 200, JSON.stringify(await recon.json()));

    const after = await jobOf();
    assert.equal(after.rejected_quantity, 7, 'rejection lands on the worker job');
    assert.match(after.rejection_note, /Reject bin/, 'and says where it went');
    assert.equal(after.id, before.id, 'same job, not a new one');

    // Reconciliation is the source of truth — a corrected figure overwrites.
    await fetch(`${baseUrl}/runs/${runId}/node-metrics`, {
      method: 'PUT', headers: auth,
      body: JSON.stringify({ nodeId: 'n-assembly', metrics: { scrap: 3 } }),
    });
    assert.equal((await jobOf()).rejected_quantity, 3, 'a correction overwrites');
  } finally {
    await closeServer(server);
  }
});

test('reconciling an assembly stage mints a temporary set into inventory', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-assembly-set-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'assembly4@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('/Users/rutuparnpuranik/Paper/backend/server.js')];
  const backend = require('/Users/rutuparnpuranik/Paper/backend/server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const login = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'assembly4@paper.local', password: 'OwnerPass1234' }),
    });
    const { token } = await login.json();
    const auth = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };

    const templateId = 'tpl-assembly-set';
    const outputItemId = await firstItemId(baseUrl, auth);
    await fetch(`${baseUrl}/templates`, {
      method: 'POST', headers: auth,
      body: JSON.stringify(templatePayload(templateId, outputItemId)),
    });
    const runBody = await (await fetch(`${baseUrl}/runs`, {
      method: 'POST', headers: auth,
      body: JSON.stringify({ templateId, name: 'Assembly set run' }),
    })).json();
    const runId = runBody.run.id;

    const sets = async () => {
      const r = await fetch(`${baseUrl}/api/inventory/sets`, { headers: auth });
      const body = await r.json();
      return (body.sets || body.data || []).filter((s) => s.originRunId === runId);
    };

    assert.equal((await sets()).length, 0, 'no set before the stage is reconciled');

    await fetch(`${baseUrl}/runs/${runId}/node-metrics`, {
      method: 'PUT', headers: auth,
      body: JSON.stringify({
        nodeId: 'n-assembly',
        metrics: { allotted: 50, output: 48, scrap: 2 },
      }),
    });

    const produced = await sets();
    assert.equal(produced.length, 1, 'reconciling mints exactly one set');
    const made = produced[0];
    assert.equal(made.isTemporary, true, 'flagged as produced, not defined');
    assert.equal(made.originNodeId, 'n-assembly');
    assert.ok(made.producedAt, 'carries a completion time');
    assert.match(made.name, /^Temporary · /, 'named so its origin is obvious');
    assert.match(made.name, new RegExp(runId), 'and names the run');
    assert.ok(made.lines.length > 0, 'composition captured from the feeder step');

    // The Sets tab builds this barcode from originRunId + originNodeId to open
    // the set's ledger. If either side ever renames, this breaks here rather
    // than silently opening nothing in the app.
    const derived = `SET-${made.originRunId}-${made.originNodeId}`;
    const detail = await fetch(
      `${baseUrl}/api/materials/${encodeURIComponent(derived)}/detail`, { headers: auth });
    assert.equal(detail.status, 200,
      'the set is reachable at the barcode the UI derives from its origin');

    // Re-reconciling the same stage must update, not mint a second set.
    await fetch(`${baseUrl}/runs/${runId}/node-metrics`, {
      method: 'PUT', headers: auth,
      body: JSON.stringify({ nodeId: 'n-assembly', metrics: { output: 44 } }),
    });
    const after = await sets();
    assert.equal(after.length, 1, 'still one set for this stage');
    assert.equal(after[0].id, made.id, 'and it is the same set');
  } finally {
    await closeServer(server);
  }
});

test('a produced set keeps a ledger: in from production, out when issued to a worker', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-assembly-ledger-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'assembly5@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('/Users/rutuparnpuranik/Paper/backend/server.js')];
  const backend = require('/Users/rutuparnpuranik/Paper/backend/server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const login = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'assembly5@paper.local', password: 'OwnerPass1234' }),
    });
    const { token } = await login.json();
    const auth = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };

    const templateId = 'tpl-assembly-ledger';
    const outputItemId = await firstItemId(baseUrl, auth);
    await fetch(`${baseUrl}/templates`, {
      method: 'POST', headers: auth,
      body: JSON.stringify(templatePayload(templateId, outputItemId)),
    });
    const runId = (await (await fetch(`${baseUrl}/runs`, {
      method: 'POST', headers: auth,
      body: JSON.stringify({ templateId, name: 'Assembly ledger run' }),
    })).json()).run.id;

    // Reaching the stage opens the worker job.
    await fetch(`${baseUrl}/runs/${runId}/node-status`, {
      method: 'PUT', headers: auth,
      body: JSON.stringify({ nodeId: 'n-assembly', status: 'ready', batchQuantity: 40 }),
    });
    // Reconciling it produces the set: 40 assembled.
    await fetch(`${baseUrl}/runs/${runId}/node-metrics`, {
      method: 'PUT', headers: auth,
      body: JSON.stringify({ nodeId: 'n-assembly', metrics: { allotted: 40, output: 40 } }),
    });

    const barcode = `SET-${runId}-n-assembly`;
    // The ledger itself is the point: what came in from production and what
    // went out to the worker.
    const ledger = async () => {
      const r = await fetch(`${baseUrl}/api/materials/${encodeURIComponent(barcode)}/detail`,
        { headers: auth });
      if (r.status !== 200) return null;
      const body = await r.json();
      const movements = body.movements || [];
      const sum = (type) => movements
        .filter((m) => (m.movementType || m.movement_type) === type)
        .reduce((t, m) => t + Number(m.qty || 0), 0);
      return { material: body.material, received: sum('receive'), issued: sum('issue') };
    };

    const stocked = await ledger();
    assert.ok(stocked?.material, 'the produced set holds stock as a material');
    assert.equal(stocked.received, 40, 'in from production');
    assert.equal(stocked.issued, 0, 'nothing has left yet');

    // The Sets row reads stock off the set itself, so the API has to carry it.
    const setsNow = await (await fetch(`${baseUrl}/api/inventory/sets`, { headers: auth })).json();
    const setRow = (setsNow.sets || []).find((x) => x.originRunId === runId);
    assert.ok(setRow, 'the produced set is listed');
    assert.equal(setRow.onHandQty, 40, 'set carries its real stock, not its line count');
    assert.equal(setRow.materialBarcode, barcode, 'and the barcode its ledger lives under');

    // Assigning the job means it left the facility.
    const job = (await (await fetch(`${baseUrl}/api/freelancer-jobs`, { headers: auth })).json())
      .jobs.find((j) => j.node_id === 'n-assembly');
    assert.ok(job, 'the worker job exists');
    const batchRes = await fetch(`${baseUrl}/api/freelancer-jobs/batches`, {
      method: 'POST', headers: auth,
      body: JSON.stringify({ freelancer_id: null, job_ids: [job.id] }),
    });
    assert.equal(batchRes.status, 200, JSON.stringify(await batchRes.json()));

    const issued = await ledger();
    assert.equal(issued.issued, 40, 'out when handed to the worker');

    const setsAfter = await (await fetch(`${baseUrl}/api/inventory/sets`, { headers: auth })).json();
    const issuedRow = (setsAfter.sets || []).find((x) => x.originRunId === runId);
    assert.equal(issuedRow.onHandQty, 0,
      'and the Sets row reads zero once it has left the facility');

    // Assigning again must not book a second issue.
    await fetch(`${baseUrl}/api/freelancer-jobs/batches`, {
      method: 'POST', headers: auth,
      body: JSON.stringify({ freelancer_id: null, job_ids: [job.id] }),
    });
    assert.equal((await ledger()).issued, 40, 'issued once, not twice');
  } finally {
    await closeServer(server);
  }
});
