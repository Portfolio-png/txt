const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

function loadBackend() {
  const backendPath = require.resolve('../server.js');
  delete require.cache[backendPath];
  return require('../server.js');
}

test('orders persistence functions create, list, and transition lifecycle', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-orders-api-'));
  const dbPath = path.join(tempDir, 'paper.db');
  process.env.DB_PATH = dbPath;

  const backend = loadBackend();

  try {
    await backend.initDb();

    const seededClients = await backend.getClientsWithUsage();
    const seededItems = await backend.getItemsWithUsage();
    const seededOrders = await backend.getOrders();
    const seededUnits = await backend.getUnitsWithUsage();
    assert.ok(seededUnits.length >= 4, 'expected seeded mock units');
    assert.ok(seededClients.length >= 3, 'expected seeded mock clients');
    assert.ok(seededItems.length >= 2, 'expected seeded mock items');
    assert.ok(seededOrders.length >= 4, 'expected seeded mock orders');

    const clientRow = (await backend.getClientsWithUsage()).find(
      (entry) => !entry.is_archived,
    );
    assert.ok(clientRow, 'expected an active seeded client');
    const client = backend.rowToClientDto(clientRow);

    const itemRows = await backend.getItemsWithUsage();
    const itemRow = itemRows.find((entry) => !entry.is_archived);
    assert.ok(itemRow, 'expected an active seeded item');
    const item = await backend.rowToItemDto(itemRow);

    const leaf = findFirstLeafVariation(item.variationTree || []);
    assert.ok(leaf, 'expected a seeded leaf variation path');

    const created = await backend.saveOrder({
      orderNo: 'ORD-DB-001',
      clientId: client.id,
      clientName: client.name,
      poNumber: 'PO-DB-77',
      clientCode: client.alias,
      itemId: item.id,
      itemName: item.displayName,
      variationLeafNodeId: leaf.id,
      variationPathLabel: leaf.displayName,
      variationPathNodeIds: leaf.path,
      quantity: 12,
      status: 'confirmed',
      priority: 'high',
      startDate: '2026-04-04T00:00:00.000Z',
      endDate: '2026-04-10T00:00:00.000Z',
    });

    const createdDto = backend.rowToOrderDto
        ? backend.rowToOrderDto(created)
        : created;
    assert.equal(createdDto.orderNo, 'ORD-DB-001');
    assert.equal(createdDto.status, 'confirmed');
    assert.equal(createdDto.priority, 'high');
    assert.equal(createdDto.quantity, 12);

    const listedRows = await backend.getOrders();
    assert.equal(listedRows.length, seededOrders.length + 1);
    assert.ok(
      listedRows.some(
        (entry) =>
          entry.order_no === 'ORD-DB-001' && entry.variation_leaf_node_id === leaf.id,
      ),
    );

    const updated = await backend.updateOrderLifecycle({
      id: created.id,
      toStatus: 'allocated',
      reason: 'Stock reserved',
      startDate: '2026-04-05T00:00:00.000Z',
      endDate: '2026-04-12T00:00:00.000Z',
    });
    const updatedDto = backend.rowToOrderDto ? backend.rowToOrderDto(updated) : updated;
    assert.equal(updatedDto.status, 'allocated');
    assert.equal(updatedDto.endDate, '2026-04-12T00:00:00.000Z');

    const reprioritized = await backend.updateOrderPriority({
      id: created.id,
      priority: 'urgent',
      source: 'test',
    });
    const reprioritizedDto = backend.rowToOrderDto
      ? backend.rowToOrderDto(reprioritized)
      : reprioritized;
    assert.equal(reprioritizedDto.priority, 'urgent');

    const invalidTransitionPromise = backend.updateOrderLifecycle({
      id: created.id,
      toStatus: 'closed',
    });
    await assert.rejects(invalidTransitionPromise);

    const statusHistoryRows = await backend.getOrderStatusHistory(created.id);
    assert.ok(statusHistoryRows.length >= 2, 'expected status history rows');
    assert.equal(statusHistoryRows[0].to_status, 'allocated');
    assert.equal(statusHistoryRows[1].to_status, 'confirmed');

    const activityRows = await backend.getOrderActivity(created.id);
    assert.ok(activityRows.length >= 2, 'expected activity rows');
    assert.equal(activityRows[0].event_type, 'field_updated');
    assert.ok(
      activityRows.some((entry) => entry.event_type === 'status_changed'),
      'expected status_changed activity row',
    );
    assert.ok(
      activityRows.some((entry) => entry.event_type === 'order_created'),
      'expected order_created activity row',
    );

    const materialRow = await backend.get(
      'SELECT * FROM materials WHERE kind = ? ORDER BY id ASC LIMIT 1',
      ['parent'],
    );
    assert.ok(materialRow, 'expected a seeded material for bom linkage');
    await backend.replaceItemBomLines({
      itemId: item.id,
      lines: [
        {
          materialBarcode: materialRow.barcode,
          quantityPerUnit: 2,
          wastagePercent: 0,
        },
      ],
    });
    const now = new Date().toISOString();
    await backend.run('DELETE FROM inventory_stock_positions WHERE material_barcode = ?', [
      materialRow.barcode,
    ]);
    await backend.run(
      `
      INSERT INTO inventory_stock_positions (
        material_barcode, location_id, lot_code, unit_id, on_hand_qty, reserved_qty, damaged_qty, updated_at
      ) VALUES (?, 'MAIN', '', ?, ?, 0, 0, ?)
      `,
      [materialRow.barcode, materialRow.unit_id || null, 100, now],
    );
    const refreshedRequirements = await backend.syncOrderMaterialRequirements({
      orderId: created.id,
      source: 'test',
    });
    await Promise.all([
      backend.syncOrderMaterialRequirements({ orderId: created.id, source: 'test' }),
      backend.syncOrderMaterialRequirements({ orderId: created.id, source: 'test' }),
    ]);
    assert.equal(refreshedRequirements.length, 1);
    assert.equal(Number(refreshedRequirements[0].required_qty), 24);
    assert.equal(Number(refreshedRequirements[0].allocated_qty), 0);

    const allocatedRequirements = await backend.allocateOrderMaterials({
      orderId: created.id,
      source: 'test',
    });
    assert.equal(allocatedRequirements.length, 1);
    assert.equal(Number(allocatedRequirements[0].allocated_qty), 24);
    assert.equal(Number(allocatedRequirements[0].shortage_qty), 0);

    const releasedRequirements = await backend.releaseOrderMaterials({
      orderId: created.id,
      source: 'test',
    });
    assert.equal(releasedRequirements.length, 1);
    assert.equal(Number(releasedRequirements[0].allocated_qty), 0);
    assert.equal(Number(releasedRequirements[0].shortage_qty), 24);
    const shortageSuggestions = await backend.getOrderProcurementSuggestions(created.id);
    assert.equal(shortageSuggestions.length, 1);
    assert.equal(String(shortageSuggestions[0].material_barcode), materialRow.barcode);
    assert.equal(Number(shortageSuggestions[0].shortage_qty), 24);
    assert.equal(
      String(shortageSuggestions[0].procurement_state || ''),
      String(materialRow.procurement_state || 'not_ordered'),
    );
    await backend.refreshOrderProcurementSuggestions({
      orderId: created.id,
      source: 'test',
    });
    const activityAfterRefresh = await backend.getOrderActivity(created.id);
    assert.equal(
      String(activityAfterRefresh[0].event_type || ''),
      'procurement_suggestions_refreshed',
    );

    await backend.allocateOrderMaterials({
      orderId: created.id,
      source: 'test',
    });
    const consumedRequirements = await backend.consumeOrderMaterials({
      orderId: created.id,
      source: 'test',
    });
    assert.equal(consumedRequirements.length, 1);
    assert.equal(Number(consumedRequirements[0].allocated_qty), 0);
    assert.equal(Number(consumedRequirements[0].consumed_qty), 24);
    assert.equal(Number(consumedRequirements[0].shortage_qty), 0);
    assert.equal(String(consumedRequirements[0].status), 'consumed');
    const suggestionsAfterConsume = await backend.getOrderProcurementSuggestions(
      created.id,
    );
    assert.equal(suggestionsAfterConsume.length, 0);
    const allSuggestions = await backend.getAllOrderProcurementSuggestions();
    assert.equal(
      allSuggestions.some((entry) => Number(entry.order_id || entry.orderId) === created.id),
      false,
    );

    const draft = await backend.saveOrder({
      orderNo: 'ORD-DB-TRANS-001',
      clientId: client.id,
      clientName: client.name,
      poNumber: 'PO-DB-TRANS-77',
      clientCode: client.alias,
      itemId: item.id,
      itemName: item.displayName,
      variationLeafNodeId: leaf.id,
      variationPathLabel: leaf.displayName,
      variationPathNodeIds: leaf.path,
      quantity: 3,
      status: 'draft',
    });
    const draftOptions = backend.getOrderTransitionOptions(draft);
    assert.deepEqual(
      draftOptions.map((entry) => entry.action),
      ['confirm', 'cancel'],
    );
    const confirmed = await backend.transitionOrderByAction({
      id: draft.id,
      action: 'confirm',
      source: 'test',
    });
    assert.equal(confirmed.status, 'confirmed');
    const confirmedOptions = backend
      .getOrderTransitionOptions(confirmed)
      .map((entry) => entry.action);
    assert.ok(confirmedOptions.includes('allocate'));
    assert.ok(confirmedOptions.includes('hold'));
  } finally {
    try {
      await backend.closeDb();
    } catch (_) {
      // ignore already-closed db handles when test runner reuses module cache
    }
  }
});

test('procurement request workflow groups shortages, raises, receives, and recomputes readiness', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-procurement-api-'));
  const dbPath = path.join(tempDir, 'paper.db');
  process.env.DB_PATH = dbPath;
  const backend = loadBackend();

  try {
    await backend.initDb();

    const clientRow = (await backend.getClientsWithUsage()).find(
      (entry) => !entry.is_archived,
    );
    assert.ok(clientRow, 'expected active client');
    const itemRow = (await backend.getItemsWithUsage()).find(
      (entry) => !entry.is_archived,
    );
    assert.ok(itemRow, 'expected active item');
    const item = await backend.rowToItemDto(itemRow);
    const leaf = findFirstLeafVariation(item.variationTree || []);
    assert.ok(leaf, 'expected leaf variation');

    const unitRow = (await backend.getUnitsWithUsage())[0];
    assert.ok(unitRow, 'expected seeded unit');
    const materialBarcode = `PAR-PROC-${Date.now()}`;
    const now = new Date().toISOString();
    await backend.run(
      `
      INSERT INTO materials (
        barcode, name, type, grade, thickness, supplier, location, unit_id, unit, notes,
        created_at, kind, parent_barcode, number_of_children, linked_child_barcodes
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'parent', NULL, 0, '[]')
      `,
      [
        materialBarcode,
        'Procurement Test Material',
        'Raw Material',
        'A',
        '1.0 mm',
        'Procurement Test Supplier',
        'MAIN',
        unitRow.id,
        unitRow.symbol || unitRow.name,
        'phase-5 test',
        now,
      ],
    );
    const materialRow = await backend.getMaterialRowByBarcode(materialBarcode);
    assert.ok(materialRow, 'expected inserted material');

    await backend.replaceItemBomLines({
      itemId: item.id,
      lines: [
        {
          materialBarcode: materialRow.barcode,
          materialName: materialRow.name,
          quantityPerUnit: 2,
          wastagePercent: 0,
          unitId: materialRow.unit_id || null,
          unitSymbol: materialRow.unit || '',
        },
      ],
    });

    await backend.run('DELETE FROM inventory_stock_positions WHERE material_barcode = ?', [
      materialRow.barcode,
    ]);

    const createdOne = await backend.saveOrder({
      orderNo: 'ORD-PROC-001',
      clientId: clientRow.id,
      clientName: clientRow.name,
      poNumber: 'PO-PROC-001',
      clientCode: clientRow.alias,
      itemId: item.id,
      itemName: item.displayName,
      variationLeafNodeId: leaf.id,
      variationPathLabel: leaf.displayName,
      variationPathNodeIds: leaf.path,
      quantity: 10,
      status: 'confirmed',
      endDate: '2026-05-10T00:00:00.000Z',
    });
    const createdTwo = await backend.saveOrder({
      orderNo: 'ORD-PROC-002',
      clientId: clientRow.id,
      clientName: clientRow.name,
      poNumber: 'PO-PROC-002',
      clientCode: clientRow.alias,
      itemId: item.id,
      itemName: item.displayName,
      variationLeafNodeId: leaf.id,
      variationPathLabel: leaf.displayName,
      variationPathNodeIds: leaf.path,
      quantity: 5,
      status: 'confirmed',
      endDate: '2026-05-08T00:00:00.000Z',
    });

    await backend.syncOrderMaterialRequirements({ orderId: createdOne.id, source: 'test' });
    await backend.syncOrderMaterialRequirements({ orderId: createdTwo.id, source: 'test' });

    const queueRows = await backend.getProcurementQueueRows({ source: 'test' });
    const queueRow = queueRows.find(
      (row) => String(row.material_barcode || '') === String(materialRow.barcode),
    );
    assert.ok(queueRow, 'expected grouped queue row for shortage material');
    assert.equal(Number(queueRow.total_shortage_qty) >= 30, true);
    assert.equal(Number(queueRow.affected_order_count) >= 2, true);
    assert.equal(Number(queueRow.uncovered_qty) >= 30, true);

    const createdRequests = await backend.createProcurementRequestsFromQueue({
      selections: [
        {
          supplierName: queueRow.supplier_name,
          materialBarcode: queueRow.material_barcode,
          requestedQty: Number(queueRow.uncovered_qty || 0),
        },
      ],
      actor: { userId: 1, name: 'Tester', role: 'super_admin' },
      source: 'test',
    });
    assert.equal(createdRequests.length, 1);
    const requestId = Number(createdRequests[0].id);
    assert.ok(requestId > 0, 'expected created request id');

    const createdLines = await backend.getProcurementRequestLines(requestId);
    assert.equal(createdLines.length, 1);
    assert.equal(
      Number(createdLines[0].requested_qty),
      Number(queueRow.uncovered_qty || 0),
    );
    assert.equal(
      Number(createdLines[0].pending_qty),
      Number(queueRow.uncovered_qty || 0),
    );

    const sourceLinks = await backend.all(
      `
      SELECT *
      FROM procurement_request_line_sources
      WHERE procurement_request_id = ?
      ORDER BY id ASC
      `,
      [requestId],
    );
    assert.equal(sourceLinks.length > 0, true);
    assert.equal(
      sourceLinks.reduce((sum, row) => sum + Number(row.linked_qty || 0), 0),
      Number(queueRow.uncovered_qty || 0),
    );

    const queueAfterCreate = await backend.getProcurementQueueRows({ source: 'test' });
    assert.equal(
      queueAfterCreate.some(
        (row) => String(row.material_barcode || '') === String(materialRow.barcode),
      ),
      false,
    );

    const duplicateCreatePromise = backend.createProcurementRequestsFromQueue({
      selections: [
        {
          supplierName: queueRow.supplier_name,
          materialBarcode: queueRow.material_barcode,
        },
      ],
      actor: { userId: 1, name: 'Tester', role: 'super_admin' },
      source: 'test',
    });
    await assert.rejects(duplicateCreatePromise);

    const raisedRequest = await backend.raiseProcurementRequest({
      id: requestId,
      actor: { userId: 1, name: 'Tester', role: 'super_admin' },
      source: 'test',
    });
    assert.equal(String(raisedRequest.status), 'raised');
    const updatedRaisedRequest = await backend.updateProcurementRequest({
      id: requestId,
      expectedDate: '2026-05-14',
      notes: 'Raised request metadata edit test',
      actor: { userId: 1, name: 'Tester', role: 'super_admin' },
      source: 'test',
    });
    assert.equal(String(updatedRaisedRequest.expected_date || ''), '2026-05-14');
    assert.equal(
      String(updatedRaisedRequest.notes || ''),
      'Raised request metadata edit test',
    );

    const partial = await backend.receiveProcurementRequest({
      id: requestId,
      lines: [
        {
          requestLineId: createdLines[0].id,
          receivedQty: 12,
          note: 'Partial inward',
        },
      ],
      actor: { userId: 1, name: 'Store', role: 'admin' },
      source: 'test',
    });
    assert.equal(String(partial.status), 'partially_received');
    const lineAfterPartial = (await backend.getProcurementRequestLines(requestId))[0];
    assert.equal(Number(lineAfterPartial.received_qty), 12);
    assert.equal(
      Number(lineAfterPartial.pending_qty),
      Number(queueRow.uncovered_qty || 0) - 12,
    );

    const materialAfterReceive = await backend.getMaterialRowByBarcode(materialRow.barcode);
    assert.equal(Number(materialAfterReceive.on_hand_qty), 12);

    const orderOneRequirements = await backend.getOrderMaterialRequirements(createdOne.id);
    assert.equal(
      Number(orderOneRequirements[0].procurement_requested_qty || 0) > 0,
      true,
    );
    assert.equal(
      Number(orderOneRequirements[0].procurement_received_qty || 0) > 0,
      true,
    );
    assert.equal(
      String(orderOneRequirements[0].procurement_request_number || '').startsWith('PR-'),
      true,
    );

    const badCancelPromise = backend.cancelProcurementRequest({
      id: requestId,
      reason: '',
      actor: { userId: 1, name: 'Tester', role: 'super_admin' },
      source: 'test',
    });
    await assert.rejects(badCancelPromise);
    await backend.cancelProcurementRequest({
      id: requestId,
      reason: 'Supplier dropped commitment',
      actor: { userId: 1, name: 'Tester', role: 'super_admin' },
      source: 'test',
    });
    const queueAfterCancel = await backend.getProcurementQueueRows({ source: 'test' });
    const queueAfterCancelRow = queueAfterCancel.find(
      (row) => String(row.material_barcode || '') === String(materialRow.barcode),
    );
    assert.ok(queueAfterCancelRow, 'expected shortage to return to queue after cancel');
    assert.equal(Number(queueAfterCancelRow.uncovered_qty) > 0, true);
  } finally {
    try {
      await backend.closeDb();
    } catch (_) {
      // ignore already-closed db handles when test runner reuses module cache
    }
  }
});

function findFirstLeafVariation(nodes, currentPath = []) {
  for (const node of nodes) {
    const nextPath = [...currentPath, node.id];
    if (node.kind === 'value' && (!node.children || node.children.length === 0)) {
      return { id: node.id, displayName: node.displayName, path: nextPath };
    }
    const nested = findFirstLeafVariation(node.children || [], nextPath);
    if (nested) {
      return nested;
    }
  }
  return null;
}
