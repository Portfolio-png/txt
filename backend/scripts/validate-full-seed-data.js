const fs = require('fs');
const path = require('path');
const assert = require('assert');

const seedPath = path.resolve(__dirname, '..', 'demo_seed_full.json');
const seed = JSON.parse(fs.readFileSync(seedPath, 'utf8'));

const requiredTopLevelKeys = [
  'units',
  'clients',
  'vendors',
  'items',
  'machines',
  'dies',
  'pipelines',
  'users',
  'inventory',
  'orders',
  'purchaseOrders',
  'productionRuns',
  'challans',
];

function byId(rows, label) {
  const map = new Map();
  for (const row of rows) {
    assert(row.id, `${label} row is missing id`);
    assert(!map.has(row.id), `${label} has duplicate id ${row.id}`);
    map.set(row.id, row);
  }
  return map;
}

function expectRef(map, id, label) {
  if (id == null) return;
  assert(map.has(id), `${label} references missing id ${id}`);
}

for (const key of requiredTopLevelKeys) {
  assert(Array.isArray(seed[key]), `Missing top-level array: ${key}`);
}

const units = byId(seed.units, 'units');
const clients = byId(seed.clients, 'clients');
const vendors = byId(seed.vendors, 'vendors');
const items = byId(seed.items, 'items');
const machines = byId(seed.machines, 'machines');
const dies = byId(seed.dies, 'dies');
const pipelines = byId(seed.pipelines, 'pipelines');
const users = byId(seed.users, 'users');
const inventory = byId(seed.inventory, 'inventory');
const orders = byId(seed.orders, 'orders');
const purchaseOrders = byId(seed.purchaseOrders, 'purchaseOrders');
const productionRuns = byId(seed.productionRuns, 'productionRuns');
const challans = byId(seed.challans, 'challans');

for (const item of seed.items) {
  expectRef(units, item.unitId, `item ${item.id}`);
}

for (const machine of seed.machines) {
  for (const dieId of machine.compatibleDieIds || []) {
    expectRef(dies, dieId, `machine ${machine.id}`);
  }
}

for (const die of seed.dies) {
  for (const machineId of die.compatibleMachineIds || []) {
    expectRef(machines, machineId, `die ${die.id}`);
  }
}

for (const pipeline of seed.pipelines) {
  for (const itemId of pipeline.inputItemIds || []) {
    expectRef(items, itemId, `pipeline ${pipeline.id}`);
  }
  expectRef(items, pipeline.outputItemId, `pipeline ${pipeline.id}`);
  for (const stage of pipeline.stages || []) {
    expectRef(machines, stage.machineId, `stage ${stage.id}`);
    expectRef(dies, stage.dieId, `stage ${stage.id}`);
    if (stage.machineId && stage.dieId) {
      const machine = machines.get(stage.machineId);
      assert(
        (machine.compatibleDieIds || []).includes(stage.dieId),
        `stage ${stage.id} assigns incompatible die ${stage.dieId} to ${stage.machineId}`,
      );
    }
    for (const input of stage.inputs || []) {
      expectRef(items, input.itemId, `stage input ${stage.id}`);
      expectRef(units, input.unitId, `stage input ${stage.id}`);
    }
    for (const output of stage.outputs || []) {
      expectRef(items, output.itemId, `stage output ${stage.id}`);
    }
  }
}

for (const stock of seed.inventory) {
  expectRef(items, stock.itemId, `stock ${stock.id}`);
  expectRef(units, stock.unitId, `stock ${stock.id}`);
  expectRef(vendors, stock.supplierId, `stock ${stock.id}`);
  expectRef(challans, stock.receivedChallanId, `stock ${stock.id}`);
}

for (const order of seed.orders) {
  expectRef(clients, order.clientId, `order ${order.id}`);
  for (const runId of order.linkedProductionRunIds || []) {
    expectRef(productionRuns, runId, `order ${order.id}`);
  }
  for (const challanId of order.linkedChallanIds || []) {
    expectRef(challans, challanId, `order ${order.id}`);
  }
  for (const line of order.lineItems || []) {
    expectRef(items, line.itemId, `order line ${line.id}`);
    expectRef(units, line.unitId, `order line ${line.id}`);
  }
}

for (const po of seed.purchaseOrders) {
  expectRef(vendors, po.vendorId, `purchase order ${po.id}`);
  for (const challanId of po.linkedReceptionChallanIds || []) {
    expectRef(challans, challanId, `purchase order ${po.id}`);
  }
  for (const line of po.lineItems || []) {
    expectRef(items, line.itemId, `purchase order line ${line.id}`);
    expectRef(units, line.unitId, `purchase order line ${line.id}`);
  }
}

for (const run of seed.productionRuns) {
  expectRef(pipelines, run.pipelineId, `production run ${run.id}`);
  expectRef(orders, run.orderId, `production run ${run.id}`);
  const pipeline = pipelines.get(run.pipelineId);
  const stageIds = new Set((pipeline.stages || []).map((stage) => stage.id));
  for (const assignment of run.assignedStock || []) {
    assert(stageIds.has(assignment.stageId), `run ${run.id} references missing stage ${assignment.stageId}`);
    expectRef(inventory, assignment.stockId, `run assignment ${run.id}`);
    expectRef(units, assignment.unitId, `run assignment ${run.id}`);
  }
  for (const actual of run.stageActuals || []) {
    assert(stageIds.has(actual.stageId), `run ${run.id} references missing stage ${actual.stageId}`);
    expectRef(machines, actual.machineId, `run actual ${run.id}`);
    expectRef(dies, actual.dieId, `run actual ${run.id}`);
    expectRef(users, actual.operatorUserId, `run actual ${run.id}`);
  }
}

for (const challan of seed.challans) {
  expectRef(clients, challan.clientId, `challan ${challan.id}`);
  expectRef(vendors, challan.vendorId, `challan ${challan.id}`);
  expectRef(orders, challan.orderId, `challan ${challan.id}`);
  expectRef(purchaseOrders, challan.purchaseOrderId, `challan ${challan.id}`);
  expectRef(productionRuns, challan.productionRunId, `challan ${challan.id}`);
  if (challan.duplicateOf) {
    assert(
      challans.has(challan.duplicateOf) || challan.status === 'cancelled',
      `challan ${challan.id} duplicateOf ${challan.duplicateOf} is not present`,
    );
  }
  for (const line of challan.lineItems || []) {
    expectRef(items, line.itemId, `challan line ${challan.id}`);
    expectRef(units, line.unitId, `challan line ${challan.id}`);
    expectRef(inventory, line.sourceStockId, `challan line ${challan.id}`);
    expectRef(inventory, line.targetStockId, `challan line ${challan.id}`);
  }
}

console.log(`Validated ${seedPath}`);
console.log(
  [
    `${seed.units.length} units`,
    `${seed.clients.length} clients`,
    `${seed.vendors.length} vendors`,
    `${seed.items.length} items`,
    `${seed.machines.length} machines`,
    `${seed.dies.length} dies`,
    `${seed.pipelines.length} pipelines`,
    `${seed.orders.length} orders`,
    `${seed.productionRuns.length} production runs`,
    `${seed.challans.length} challans`,
  ].join(', '),
);
