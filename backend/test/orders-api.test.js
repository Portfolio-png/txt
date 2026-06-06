const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

test('orders persistence functions create, list, and update lifecycle', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-orders-api-'));
  const dbPath = path.join(tempDir, 'paper.db');
  process.env.DB_PATH = dbPath;
  process.env.PAPER_S3_REGION = 'us-east-1';
  process.env.PAPER_S3_BUCKET_NAME = 'paper-test';
  process.env.AWS_ACCESS_KEY_ID = 'test-access';
  process.env.AWS_SECRET_ACCESS_KEY = 'test-secret';
  process.env.S3_SKIP_OBJECT_VERIFY = 'true';
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'owner@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'Qz79Luma4821';

  const backend = require('../server.js');

  try {
    await backend.resetAndSeedDemoData();
    const orderColumns = await backend.all("PRAGMA table_info(order_items)");
    assert.equal(
      orderColumns.some((column) => column.name === 'updated_at'),
      true,
      'order_items table must expose updated_at',
    );
    assert.equal(
      orderColumns.some((column) => column.name === 'unit_price'),
      true,
      'order_items table must expose unit_price',
    );
    assert.equal(
      orderColumns.some((column) => column.name === 'unit_id'),
      true,
      'order_items table must expose unit_id',
    );
    assert.equal(
      orderColumns.some((column) => column.name === 'unit_symbol'),
      true,
      'order_items table must expose unit_symbol',
    );
    assert.equal(
      orderColumns.some((column) => column.name === 'total_invoiced_qty'),
      true,
      'order_items table must expose total_invoiced_qty',
    );

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
      uploadType: 'ORDER_PO',
      fileName: 'client-po.pdf',
      contentType: 'application/pdf',
      sizeBytes: 1024,
      sha256: 'a'.repeat(64),
    });
    assert.equal(uploadIntent.alreadyUploaded, false);
    assert.ok(uploadIntent.upload.uploadUrl.includes('X-Amz-Signature'));
    assert.match(uploadIntent.upload.objectKey, /^orders\/po-docs\/\d+-a{12}-client-po\.pdf$/);

    const document = await backend.completePoUpload({
      uploadSessionId: uploadIntent.upload.uploadSessionId,
      objectKey: uploadIntent.upload.objectKey,
    });
    assert.equal(document.fileName, 'client-po.pdf');

    const repeatedIntent = await backend.createPoUploadIntent({
      uploadType: 'ORDER_PO',
      fileName: 'client-po.pdf',
      contentType: 'application/pdf',
      sizeBytes: 1024,
      sha256: 'a'.repeat(64),
    });
    assert.equal(repeatedIntent.alreadyUploaded, true);
    assert.equal(repeatedIntent.document.id, document.id);

    const staleTimestamp = new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString();
    await backend.run(
      `
      INSERT INTO po_documents (
        file_name, content_type, size_bytes, sha256, object_key, status, created_at, uploaded_at
      ) VALUES (?, ?, ?, ?, ?, 'uploaded', ?, ?)
      `,
      [
        'stale-po.pdf',
        'application/pdf',
        256,
        'c'.repeat(64),
        'orders/po-docs/stale/stale-po.pdf',
        staleTimestamp,
        staleTimestamp,
      ],
    );
    await backend.run(
      `
      INSERT INTO po_upload_sessions (
        id, file_name, content_type, size_bytes, sha256, object_key, status, expires_at, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?)
      `,
      [
        'stale-upload-session',
        'stale-session-po.pdf',
        'application/pdf',
        256,
        'd'.repeat(64),
        'orders/po-docs/stale/stale-session-po.pdf',
        staleTimestamp,
        staleTimestamp,
      ],
    );
    await backend.createPoUploadIntent({
      uploadType: 'ORDER_PO',
      fileName: 'fresh-po.pdf',
      contentType: 'application/pdf',
      sizeBytes: 512,
      sha256: 'e'.repeat(64),
    });
    const staleDocument = await backend.get(
      "SELECT id FROM po_documents WHERE sha256 = ?",
      ['c'.repeat(64)],
    );
    assert.equal(staleDocument == null, true);
    const staleSession = await backend.get(
      "SELECT id FROM po_upload_sessions WHERE id = ?",
      ['stale-upload-session'],
    );
    assert.equal(staleSession == null, true);

    const imageIntent = await backend.createAssetUploadIntent({
      uploadType: 'ITEM_IMAGE',
      entityType: 'item',
      entityId: item.id,
      fileName: 'printed-sleeve.png',
      contentType: 'image/png',
      sizeBytes: 2048,
      sha256: 'b'.repeat(64),
      isPrimary: true,
    });
    assert.equal(imageIntent.alreadyUploaded, false);
    assert.ok(imageIntent.upload.uploadUrl.includes('X-Amz-Signature'));
    assert.match(
      imageIntent.upload.objectKey,
      new RegExp(`^masters/items/item-${item.id}/\\d+-b{12}-printed-sleeve\\.png$`),
    );
    const asset = await backend.completeAssetUpload({
      uploadSessionId: imageIntent.upload.uploadSessionId,
      objectKey: imageIntent.upload.objectKey,
    });
    assert.equal(asset.entityType, 'item');
    assert.equal(asset.entityId, item.id);
    assert.equal(asset.isPrimary, true);
    assert.ok(asset.readUrl.includes('X-Amz-Signature'));
    const itemAssets = await backend.listAssetsForEntity('item', item.id);
    assert.equal(itemAssets.length, 1);
    assert.equal(itemAssets[0].id, asset.id);

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
    await assert.rejects(
      () =>
        backend.saveOrder({
          orderNo: 'ORD-BAD-QTY',
          clientId: client.id,
          clientName: client.name,
          poNumber: 'PO-BAD-QTY',
          clientCode: client.alias,
          itemId: item.id,
          itemName: item.displayName,
          variationLeafNodeId: leaf.id,
          variationPathLabel: leaf.displayName,
          variationPathNodeIds: leaf.path,
          quantity: 1.5,
          status: 'draft',
        }),
      /whole number/,
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
      unitPrice: 42.5,
      totalInvoicedQty: 3,
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
    assert.equal(createdDto.unitId, item.unitId);
    assert.ok(createdDto.unitSymbol.length > 0);
    assert.equal(createdDto.unitPrice, 42.5);
    assert.equal(createdDto.totalInvoicedQty, 3);
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
    assert.equal(updatedDto.endDate, '2026-04-12');

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

    const merged = await backend.saveOrder(
      {
        orderNo: 'ORD-DB-001',
        clientId: client.id,
        clientName: client.name,
        poNumber: 'PO-DB-77',
        clientCode: 'client-facing code',
        itemId: item.id,
        itemName: item.displayName,
        variationLeafNodeId: leaf.id,
        variationPathLabel: leaf.displayName,
        variationPathNodeIds: leaf.path,
        quantity: 4,
        unitPrice: 45,
        status: 'completed',
        startDate: '2026-04-05T00:00:00.000Z',
        endDate: '2026-04-12T00:00:00.000Z',
        actor: { id: 1, name: 'Test User', role: 'admin', source: 'test' },
      },
      { returnMeta: true },
    );
    assert.equal(merged.merged, true);
    assert.equal(merged.quantityBefore, 12);
    assert.equal(merged.quantityAdded, 4);
    assert.equal(merged.quantityAfter, 16);
    const mergedRow = await backend.get('SELECT * FROM order_items WHERE id = ?', [created.id]);
    assert.equal(mergedRow.quantity, 16);
    assert.equal(mergedRow.status, 'completed');
    assert.equal(mergedRow.client_code, 'client-facing code');
    assert.equal(mergedRow.unit_price, 45);
    assert.equal(mergedRow.total_invoiced_qty, 3);
    assert.equal(mergedRow.variation_path_node_ids_json, JSON.stringify(leaf.path));
    assert.equal(mergedRow.variation_path_label, leaf.displayName);
    assert.ok(mergedRow.updated_at);
    assert.notEqual(mergedRow.updated_at, created.updated_at);

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

    const draftOnlyClient = await backend.saveClient({
      name: 'Draft Only Client',
      alias: 'DOC',
      gstNumber: '29ABCDE1234F2Z5',
      address: 'Draft Street',
    });
    await backend.saveOrder({
      orderNo: 'ORD-DRAFT-ONLY',
      clientId: draftOnlyClient.id,
      clientName: draftOnlyClient.name,
      poNumber: 'PO-DRAFT-ONLY',
      clientCode: 'draft-code',
      itemId: item.id,
      itemName: item.displayName,
      variationLeafNodeId: leaf.id,
      variationPathLabel: leaf.displayName,
      variationPathNodeIds: leaf.path,
      quantity: 5,
      status: 'draft',
    });
    const renamedDraftOnlyClient = await backend.saveClient({
      id: draftOnlyClient.id,
      name: 'Draft Only Client Renamed',
      alias: 'DOC',
      gstNumber: '29ABCDE1234F2Z5',
      address: 'Draft Street',
    });
    assert.equal(renamedDraftOnlyClient.name, 'Draft Only Client Renamed');

    const importedMaterial = await backend.createParentWithChildren({
      name: 'Imported Production Material',
      type: 'Raw Material',
      unit: 'kg',
      location: 'STAGING',
      numberOfChildren: 0,
    });
    await backend.run(
      'DELETE FROM inventory_stock_positions WHERE material_barcode = ?',
      [importedMaterial.barcode],
    );
    await backend.initDb();
    const gatedBackfillCount = await backend.get(
      `
      SELECT COUNT(*) AS count
      FROM inventory_stock_positions
      WHERE material_barcode = ?
      `,
      [importedMaterial.barcode],
    );
    assert.equal(Number(gatedBackfillCount?.count || 0), 0);

    const { server, port } = await listen(backend.app);
    const baseUrl = `http://127.0.0.1:${port}`;
    try {
      const owner = await login(baseUrl, 'owner@paper.local', 'Qz79Luma4821');
      const assetIntentResponse = await postJson(
        baseUrl,
        `/api/items/${item.id}/assets/upload-intent`,
        owner.token,
        {
          uploadType: 'ITEM_IMAGE',
          fileName: 'alias-item-image.png',
          contentType: 'image/png',
          sizeBytes: 128,
          sha256: 'f'.repeat(64),
          isPrimary: true,
        },
      );
      assert.equal(assetIntentResponse.status, 201);
      assert.equal(assetIntentResponse.body.success, true);
      assert.equal(assetIntentResponse.body.intent.upload != null, true);

      const assetCompleteResponse = await postJson(
        baseUrl,
        `/api/items/${item.id}/assets/upload-complete`,
        owner.token,
        {
          uploadSessionId:
              assetIntentResponse.body.intent.upload.uploadSessionId,
          objectKey: assetIntentResponse.body.intent.upload.objectKey,
        },
      );
      assert.equal(assetCompleteResponse.status, 200);
      assert.equal(assetCompleteResponse.body.success, true);
      assert.equal(assetCompleteResponse.body.asset.entityId, item.id);

      const createResponse = await postJson(baseUrl, '/api/orders', owner.token, {
        orderNo: 'ORD-HTTP-001',
        clientId: client.id,
        clientName: client.name,
        poNumber: 'PO-HTTP-001',
        clientCode: 'http-client-code',
        itemId: item.id,
        itemName: item.displayName,
        variationLeafNodeId: leaf.id,
        variationPathLabel: leaf.displayName,
        variationPathNodeIds: leaf.path,
        quantity: 6,
        status: 'inProgress',
        startDate: '2026-04-20T00:00:00.000Z',
        endDate: '2026-04-25T00:00:00.000Z',
      });
      assert.equal(createResponse.status, 201);
      assert.equal(createResponse.body.merged, false);

      const mergeResponse = await postJson(baseUrl, '/api/orders', owner.token, {
        orderNo: 'ORD-HTTP-001',
        clientId: client.id,
        clientName: client.name,
        poNumber: 'PO-HTTP-001',
        clientCode: 'http-client-code-updated',
        itemId: item.id,
        itemName: item.displayName,
        variationLeafNodeId: leaf.id,
        variationPathLabel: leaf.displayName,
        variationPathNodeIds: leaf.path,
        quantity: 4,
        status: 'completed',
        startDate: '2026-04-20T00:00:00.000Z',
        endDate: '2026-04-25T00:00:00.000Z',
      });
      assert.equal(mergeResponse.status, 200);
      assert.equal(mergeResponse.body.merged, true);
      assert.equal(mergeResponse.body.quantityBefore, 6);
      assert.equal(mergeResponse.body.quantityAdded, 4);
      assert.equal(mergeResponse.body.quantityAfter, 10);
      assert.equal(mergeResponse.body.order.quantity, 10);
      assert.equal(mergeResponse.body.order.status, 'completed');
    } finally {
      await closeServer(server);
    }
  } finally {
    await backend.closeDb();
  }
});

function findFirstLeafVariation(nodes, currentPath = []) {
  for (const node of nodes) {
    const nextPath = node.kind === 'value' ? [...currentPath, node.id] : [...currentPath];
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

async function postJson(baseUrl, pathname, token, body) {
  const payload = JSON.stringify(body);
  return requestJson(baseUrl, pathname, 'POST', token, payload);
}

async function requestJson(baseUrl, pathname, method, token, body) {
  const target = new URL(pathname, baseUrl);
  const headers = {
    Accept: 'application/json',
  };
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }
  if (body != null) {
    headers['Content-Type'] = 'application/json';
    headers['Content-Length'] = Buffer.byteLength(body);
  }

  const response = await fetch(target, {
    method,
    headers,
    body,
  });
  const text = await response.text();
  let parsed = null;
  if (text) {
    try {
      parsed = JSON.parse(text);
    } catch (error) {
      parsed = { raw: text };
    }
  }
  return { status: response.status, body: parsed };
}
