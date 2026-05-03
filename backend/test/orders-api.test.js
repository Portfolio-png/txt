const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

test('orders persistence functions create, list, and update lifecycle', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-orders-api-'));
  const dbPath = path.join(tempDir, 'paper.db');
  process.env.DB_PATH = dbPath;
  process.env.S3_ENDPOINT = 'https://storage.example.test';
  process.env.S3_REGION = 'us-east-1';
  process.env.S3_BUCKET = 'paper-test';
  process.env.S3_ACCESS_KEY_ID = 'test-access';
  process.env.S3_SECRET_ACCESS_KEY = 'test-secret';
  process.env.S3_FORCE_PATH_STYLE = 'true';
  process.env.S3_SKIP_OBJECT_VERIFY = 'true';

  const backend = require('../server.js');

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

    const uploadIntent = await backend.createPoUploadIntent({
      fileName: 'client-po.pdf',
      contentType: 'application/pdf',
      sizeBytes: 1024,
      sha256: 'a'.repeat(64),
    });
    assert.equal(uploadIntent.alreadyUploaded, false);
    assert.ok(uploadIntent.upload.uploadUrl.includes('X-Amz-Signature'));

    const document = await backend.completePoUpload({
      uploadSessionId: uploadIntent.upload.uploadSessionId,
      objectKey: uploadIntent.upload.objectKey,
    });
    assert.equal(document.fileName, 'client-po.pdf');

    const repeatedIntent = await backend.createPoUploadIntent({
      fileName: 'client-po.pdf',
      contentType: 'application/pdf',
      sizeBytes: 1024,
      sha256: 'a'.repeat(64),
    });
    assert.equal(repeatedIntent.alreadyUploaded, true);
    assert.equal(repeatedIntent.document.id, document.id);

    await assert.rejects(
      () =>
        backend.saveOrder({
          orderNo: 'ORD-BAD-DOC',
          clientId: client.id,
          clientName: client.name,
          poNumber: 'PO-BAD-DOC',
          clientCode: client.alias,
          itemId: item.id,
          itemName: item.displayName,
          variationLeafNodeId: leaf.id,
          variationPathLabel: leaf.displayName,
          variationPathNodeIds: leaf.path,
          quantity: 1,
          status: 'draft',
          poDocumentIds: [999999],
        }),
      /One or more PO documents were not uploaded/,
    );
    const afterFailedDocumentLink = await backend.getOrders();
    assert.equal(
      afterFailedDocumentLink.some((order) => order.order_no === 'ORD-BAD-DOC'),
      false,
      'failed PO document linking must not leave an order row behind',
    );

    // Test rollback for invalid material requirements
    await assert.rejects(
      () =>
        backend.saveOrder({
          orderNo: 'ORD-BAD-MAT',
          clientId: client.id,
          clientName: client.name,
          poNumber: 'PO-BAD-MAT',
          clientCode: client.alias,
          itemId: item.id,
          itemName: item.displayName,
          variationLeafNodeId: leaf.id,
          variationPathLabel: leaf.displayName,
          variationPathNodeIds: leaf.path,
          quantity: 1,
          status: 'draft',
          poDocumentIds: [document.id],
          materialRequirements: [
            { requiredQty: 'INVALID' } // this will throw or cause constraint failure if handled
          ],
        }),
    );
    const afterFailedMaterial = await backend.getOrders();
    assert.equal(
      afterFailedMaterial.some((order) => order.order_no === 'ORD-BAD-MAT'),
      false,
      'failed material requirement insertion must rollback order creation'
    );

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
      status: 'inProgress',
      startDate: '2026-04-04T00:00:00.000Z',
      endDate: '2026-04-10T00:00:00.000Z',
      poDocumentIds: [document.id],
      materialRequirements: [
        {
          materialBarcode: 'MOCK-BARCODE',
          materialName: 'Mock Material',
          requiredQty: 5.5,
          unitSymbol: 'kg'
        }
      ],
      actor: { id: 1, name: 'Test User', role: 'admin', source: 'test' }
    });

    const createdDto = backend.rowToOrderDto
        ? backend.rowToOrderDto(created)
        : created;
    assert.equal(createdDto.orderNo, 'ORD-DB-001');
    assert.equal(createdDto.status, 'inProgress');
    assert.equal(createdDto.quantity, 12);
    const linkedDocuments = await backend.getPoDocumentsForOrder(created.id);
    assert.equal(linkedDocuments.length, 1);
    assert.equal(linkedDocuments[0].id, document.id);

    // Verify material requirements
    const requirements = await backend.all('SELECT * FROM order_material_requirements WHERE order_id = ?', [created.id]);
    assert.equal(requirements.length, 1);
    assert.equal(requirements[0].required_qty, 5.5);
    assert.equal(requirements[0].material_barcode, 'MOCK-BARCODE');

    // Verify activity log for creation
    const activityLogs = await backend.all('SELECT * FROM order_activity_log WHERE order_id = ? ORDER BY id ASC', [created.id]);
    assert.ok(activityLogs.length >= 1, 'expected activity logs');
    assert.ok(activityLogs.some(log => log.activity_type === 'order_created'));
    const fetchedActivity = await backend.getOrderActivity(created.id);
    assert.ok(fetchedActivity.length >= 1, 'expected activity API rows');
    assert.equal(fetchedActivity[0].order_id, created.id);
    await assert.rejects(
      () => backend.getOrderActivity(999999),
      /Order not found/,
    );

    // Test duplicate linking idempotency
    const { newlyLinkedIds } = await backend.linkPoDocumentsToOrder(created.id, [document.id]);
    assert.equal(newlyLinkedIds.length, 0, 'should be idempotent and return no newly linked ids');
    const linkedOnce = await backend.getPoDocumentsForOrder(created.id);
    assert.equal(linkedOnce.length, 1);

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
      status: 'completed',
      startDate: '2026-04-05T00:00:00.000Z',
      endDate: '2026-04-12T00:00:00.000Z',
      actor: { id: 1, name: 'Test User', role: 'admin', source: 'test' }
    });
    const updatedDto = backend.rowToOrderDto ? backend.rowToOrderDto(updated) : updated;
    assert.equal(updatedDto.status, 'completed');
    assert.equal(updatedDto.endDate, '2026-04-12T00:00:00.000Z');

    // Verify status history
    const statusHistory = await backend.all('SELECT * FROM order_status_history WHERE order_id = ?', [created.id]);
    assert.equal(statusHistory.length, 1);
    assert.equal(statusHistory[0].previous_status, 'inProgress');
    assert.equal(statusHistory[0].new_status, 'completed');
    const fetchedStatusHistory = await backend.getOrderStatusHistory(created.id);
    assert.equal(fetchedStatusHistory.length, 1);
    assert.equal(fetchedStatusHistory[0].new_status, 'completed');
    await assert.rejects(
      () => backend.getOrderStatusHistory(999999),
      /Order not found/,
    );

    // Verify activity log for update
    const updateLogs = await backend.all('SELECT * FROM order_activity_log WHERE order_id = ? AND activity_type = ?', [created.id, 'lifecycle_updated']);
    assert.equal(updateLogs.length, 1);

    // Test invalid lifecycle rollback
    await assert.rejects(
      () => backend.updateOrderLifecycle({
        id: created.id,
        status: 'draft', // assuming valid
        startDate: 'INVALID_DATE', // SQLite doesn't strictly throw on string insertion to TEXT, but let's test a failed case by throwing an error in updateOrderLifecycle or using non-existent order.
      }),
    );

    const drafted = await backend.updateOrderLifecycle({
      id: created.id,
      status: 'draft',
      startDate: null,
      endDate: null,
      actor: { id: 1, name: 'Test User', role: 'admin', source: 'test' }
    });
    const draftedDto = backend.rowToOrderDto ? backend.rowToOrderDto(drafted) : drafted;
    assert.equal(draftedDto.status, 'draft');
  } finally {
    await backend.closeDb();
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
