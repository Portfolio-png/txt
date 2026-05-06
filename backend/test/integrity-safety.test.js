const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

test('master usage guards, simple orders, and material variation links stay consistent', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-integrity-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'owner@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'Qz79Luma4821';

  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const owner = await login(baseUrl, 'owner@paper.local', 'Qz79Luma4821');
    await assert.rejects(
      () =>
        backend.run(
          `
          INSERT INTO groups (name, parent_group_id, unit_id, is_archived, created_at, updated_at)
          VALUES (?, NULL, ?, 0, ?, ?)
          `,
          ['Broken FK Group', 999999, new Date().toISOString(), new Date().toISOString()],
        ),
      /foreign key/i,
    );

    const activeClient = (await backend.getClientsWithUsage()).find(
      (row) => !row.is_archived && Number(row.usage_count || 0) > 0,
    );
    const archivedClient = (await backend.getClientsWithUsage()).find(
      (row) => row.is_archived,
    );
    const activeUnit = (await backend.getUnitsWithUsage()).find(
      (row) => !row.is_archived && Number(row.usage_count || 0) > 0,
    );
    const activeGroup = (await backend.getGroupsWithUsage()).find(
      (row) => !row.is_archived && Number(row.usage_count || 0) > 0,
    );
    const activeItemRow = (await backend.getItemsWithUsage()).find(
      (row) => !row.is_archived && Number(row.usage_count || 0) > 0,
    );
    assert.ok(activeClient, 'expected a used client');
    assert.ok(archivedClient, 'expected an archived client');
    assert.ok(activeUnit, 'expected a used unit');
    assert.ok(activeGroup, 'expected a used group');
    assert.ok(activeItemRow, 'expected a used item');

    const activeItem = await backend.rowToItemDto(activeItemRow);
    await assert.rejects(
      () =>
        backend.saveClient({
          id: activeClient.id,
          name: `${activeClient.name} Renamed`,
          alias: activeClient.alias || '',
          gstNumber: activeClient.gst_number || '',
          address: activeClient.address || '',
        }),
      /Used clients cannot change name or GST number/,
    );
    await assert.rejects(
      () =>
        backend.saveGroup({
          id: activeGroup.id,
          name: `${activeGroup.name} Renamed`,
          parentGroupId: activeGroup.parent_group_id || null,
          unitId: activeGroup.unit_id,
        }),
      /Used groups cannot be edited/,
    );
    await assert.rejects(
      () =>
        backend.saveUnit({
          id: activeUnit.id,
          name: activeUnit.name,
          symbol: `${activeUnit.symbol}X`,
          notes: activeUnit.notes || '',
        }),
      /Used units cannot change identity or conversion details/,
    );
    const renamedUsedItem = await backend.saveItem({
      id: activeItem.id,
      name: `${activeItem.name} Renamed`,
      alias: `${activeItem.alias || activeItem.name} Alias`,
      displayName: `${activeItem.displayName} Renamed`,
      groupId: activeItem.groupId,
      unitId: activeItem.unitId,
      unitConversions: activeItem.unitConversions,
      namingFormat: [{ id: 'itemName', label: 'Item Name' }],
      variationTree: activeItem.variationTree,
    });
    assert.equal(renamedUsedItem.name, `${activeItem.name} Renamed`);
    assert.equal(renamedUsedItem.display_name, `${activeItem.displayName} Renamed`);

    const alternateGroup = await backend.saveGroup({
      name: 'Integrity Alternate Group',
      unitId: activeUnit.id,
    });
    await assert.rejects(
      () =>
        backend.saveItem({
          id: activeItem.id,
          name: renamedUsedItem.name,
          alias: renamedUsedItem.alias || '',
          displayName: renamedUsedItem.display_name,
          groupId: alternateGroup.id,
          unitId: activeItem.unitId,
          unitConversions: activeItem.unitConversions,
          namingFormat: [{ id: 'itemName', label: 'Item Name' }],
          variationTree: activeItem.variationTree,
        }),
      /Used items can only update names, aliases, display names, naming formats, and unit conversions/,
    );

    assert.equal(
      (await patchJson(baseUrl, `/api/clients/${activeClient.id}/archive`, owner.token, {})).status,
      409,
    );
    assert.equal(
      (await patchJson(baseUrl, `/api/groups/${activeGroup.id}/archive`, owner.token, {})).status,
      409,
    );
    assert.equal(
      (await patchJson(baseUrl, `/api/units/${activeUnit.id}/archive`, owner.token, {})).status,
      409,
    );
    assert.equal(
      (await patchJson(baseUrl, `/api/items/${activeItem.id}/archive`, owner.token, {})).status,
      409,
    );

    const archiveReadyGroup = await backend.saveGroup({
      name: 'Integrity Archive Ready Group',
      unitId: activeUnit.id,
    });
    const archiveReadyItem = await backend.saveItem({
      name: 'Integrity Archive Ready Item',
      alias: '',
      displayName: 'Integrity Archive Ready Item',
      groupId: archiveReadyGroup.id,
      unitId: activeUnit.id,
      variationTree: [],
    });
    assert.equal(
      (await patchJson(baseUrl, `/api/items/${archiveReadyItem.id}/archive`, owner.token, {})).status,
      200,
    );
    const refreshedArchiveReadyGroup = (await backend.getGroupsWithUsage()).find(
      (row) => row.id === archiveReadyGroup.id,
    );
    assert.equal(Number(refreshedArchiveReadyGroup?.usage_count || 0), 0);
    assert.equal(
      (await patchJson(baseUrl, `/api/groups/${archiveReadyGroup.id}/archive`, owner.token, {})).status,
      200,
    );

    const simpleItem = await backend.saveItem({
      name: 'Integrity Simple Item',
      alias: '',
      displayName: 'Integrity Simple Item',
      groupId: activeGroup.id,
      unitId: activeUnit.id,
      variationTree: [],
    });
    const simpleOrder = await backend.saveOrder({
      orderNo: 'ORD-INTEGRITY-SIMPLE',
      clientId: activeClient.id,
      clientName: activeClient.name,
      poNumber: 'PO-INTEGRITY-SIMPLE',
      clientCode: 'client text name',
      itemId: simpleItem.id,
      itemName: simpleItem.display_name,
      variationLeafNodeId: 0,
      variationPathNodeIds: [],
      quantity: 2,
      status: 'inProgress',
    });
    assert.equal(simpleOrder.variation_leaf_node_id, 0);
    assert.equal(simpleOrder.variation_path_node_ids_json, '[]');

    const variantItem = await findActiveVariantItem(backend);
    const variantLeaf = findFirstLeafVariation(variantItem.variationTree);
    const nonLeafNode = findFirstVariationProperty(variantItem.variationTree);
    assert.ok(variantLeaf, 'expected active variant leaf');
    assert.ok(nonLeafNode, 'expected active variant property node');

    await assert.rejects(
      () =>
        backend.saveOrder({
          orderNo: 'ORD-INTEGRITY-MISSING-CLIENT',
          clientId: 999999,
          clientName: 'Missing Client',
          poNumber: 'PO-INTEGRITY-MISSING-CLIENT',
          itemId: variantItem.id,
          itemName: variantItem.displayName,
          variationLeafNodeId: variantLeaf.id,
          variationPathLabel: variantLeaf.label,
          variationPathNodeIds: [...variantLeaf.path].reverse(),
          quantity: 1,
          status: 'inProgress',
        }),
      /Selected client is not available/,
    );
    await assert.rejects(
      () =>
        backend.saveOrder({
          orderNo: 'ORD-INTEGRITY-ARCHIVED-CLIENT',
          clientId: archivedClient.id,
          clientName: archivedClient.name,
          poNumber: 'PO-INTEGRITY-ARCHIVED-CLIENT',
          itemId: variantItem.id,
          itemName: variantItem.displayName,
          variationLeafNodeId: variantLeaf.id,
          variationPathLabel: variantLeaf.label,
          variationPathNodeIds: [...variantLeaf.path].reverse(),
          quantity: 1,
          status: 'inProgress',
        }),
      /Selected client is not available/,
    );

    const canonicalOrder = await backend.saveOrder({
      orderNo: 'ORD-INTEGRITY-CANONICAL',
      clientId: activeClient.id,
      clientName: activeClient.name,
      poNumber: 'PO-INTEGRITY-CANONICAL',
      clientCode: 'manual client code',
      itemId: variantItem.id,
      itemName: variantItem.displayName,
      variationLeafNodeId: variantLeaf.id,
      variationPathLabel: 'FORGED LABEL',
      variationPathNodeIds: [...variantLeaf.path].reverse(),
      quantity: 3,
      status: 'inProgress',
    });
    assert.equal(
      canonicalOrder.variation_path_node_ids_json,
      JSON.stringify(variantLeaf.path),
    );
    assert.equal(canonicalOrder.variation_path_label, variantLeaf.label);

    await assert.rejects(
      () =>
        backend.saveOrder({
          orderNo: 'ORD-INTEGRITY-MISSING-VARIANT',
          clientId: activeClient.id,
          clientName: activeClient.name,
          poNumber: 'PO-INTEGRITY-MISSING',
          itemId: variantItem.id,
          itemName: variantItem.displayName,
          variationLeafNodeId: 0,
          variationPathNodeIds: [],
          quantity: 1,
          status: 'inProgress',
        }),
      /variation values are required/,
    );
    await assert.rejects(
      () =>
        backend.saveOrder({
          orderNo: 'ORD-INTEGRITY-NON-LEAF',
          clientId: activeClient.id,
          clientName: activeClient.name,
          poNumber: 'PO-INTEGRITY-NON-LEAF',
          itemId: variantItem.id,
          itemName: variantItem.displayName,
          variationLeafNodeId: nonLeafNode.id,
          variationPathNodeIds: [nonLeafNode.id],
          quantity: 1,
          status: 'inProgress',
        }),
      /Selected variation leaf is not available/,
    );

    const baseUnit = await backend.saveUnit({
      name: 'Integrity Meter',
      symbol: 'im',
      notes: 'base',
      unitGroupName: 'Integrity Length',
      conversionFactor: 1,
    });
    await backend.saveUnit({
      name: 'Integrity Centimeter',
      symbol: 'icm',
      notes: 'derived',
      unitGroupName: 'Integrity Length',
      conversionFactor: 100,
    });
    const refreshedBaseUnit = (await backend.getUnitsWithUsage()).find(
      (row) => row.id === baseUnit.id,
    );
    assert.ok(
      Number(refreshedBaseUnit?.usage_count || 0) > 0,
      'expected conversion base unit usage to be counted',
    );
    await assert.rejects(
      () =>
        backend.saveUnit({
          id: baseUnit.id,
          name: 'Integrity Meter Renamed',
          symbol: 'im',
          notes: 'base',
          unitGroupName: 'Integrity Length',
          conversionFactor: 1,
        }),
      /Used units cannot change identity or conversion details/,
    );
    assert.equal(
      (await patchJson(baseUrl, `/api/units/${baseUnit.id}/archive`, owner.token, {})).status,
      409,
    );

    const foreignItemRow = await backend.saveItem({
      name: 'Integrity Foreign Variant',
      alias: '',
      displayName: 'Integrity Foreign Variant',
      groupId: activeGroup.id,
      unitId: activeUnit.id,
      variationTree: [
        {
          kind: 'property',
          name: 'Shade',
          children: [{ kind: 'value', name: 'Blue', children: [] }],
        },
      ],
    });
    const foreignItem = await backend.rowToItemDto(foreignItemRow);
    const foreignLeaf = findFirstLeafVariation(foreignItem.variationTree);
    await assert.rejects(
      () =>
        backend.saveOrder({
          orderNo: 'ORD-INTEGRITY-FOREIGN-LEAF',
          clientId: activeClient.id,
          clientName: activeClient.name,
          poNumber: 'PO-INTEGRITY-FOREIGN',
          itemId: variantItem.id,
          itemName: variantItem.displayName,
          variationLeafNodeId: foreignLeaf.id,
          variationPathNodeIds: foreignLeaf.path,
          quantity: 1,
          status: 'inProgress',
        }),
      /Selected variation leaf is not available/,
    );

    const material = await backend.createParentWithChildren({
      name: 'Integrity Linked Material',
      type: 'Raw Material',
      unit: activeUnit.symbol,
      numberOfChildren: 0,
    });
    const linked = await backend.linkMaterialRecordToItem(
      material.barcode,
      foreignItem.id,
      foreignLeaf.id,
    );
    assert.equal(linked.linked_item_id, foreignItem.id);
    assert.equal(linked.linked_variation_leaf_node_id, foreignLeaf.id);
    const linkedItemUsage = (await backend.getItemsWithUsage()).find(
      (row) => row.id === foreignItem.id,
    );
    assert.equal(Number(linkedItemUsage.usage_count || 0), 1);

    const linkedGroup = await backend.saveGroup({
      name: 'Integrity Linked Group',
      unitId: activeUnit.id,
    });
    const linkedToGroup = await backend.linkMaterialRecordToGroup(
      material.barcode,
      linkedGroup.id,
    );
    assert.equal(linkedToGroup.linked_item_id, null);
    assert.equal(linkedToGroup.linked_variation_leaf_node_id, null);
    const linkedGroupUsage = (await backend.getGroupsWithUsage()).find(
      (row) => row.id === linkedGroup.id,
    );
    assert.equal(Number(linkedGroupUsage.usage_count || 0), 1);

    await backend.linkMaterialRecordToItem(material.barcode, foreignItem.id, foreignLeaf.id);
    const unlinked = await backend.unlinkMaterialRecord(material.barcode);
    assert.equal(unlinked.linked_item_id, null);
    assert.equal(unlinked.linked_variation_leaf_node_id, null);

    const stockedMaterial = await backend.createParentWithChildren({
      name: 'Integrity Stock Guard Material',
      type: 'Raw Material',
      unit: activeUnit.symbol,
      location: 'WAREHOUSE-A',
      numberOfChildren: 1,
    });
    await assert.rejects(
      () =>
        backend.applyInventoryMovement({
          barcode: stockedMaterial.barcode,
          movementType: 'issue',
          qty: 150,
          actor: { name: 'Ops User' },
        }),
      /Insufficient stock/,
    );
    await assert.rejects(
      () =>
        backend.applyInventoryMovement({
          barcode: stockedMaterial.barcode,
          movementType: 'transfer',
          qty: 10,
          toLocationId: 'WAREHOUSE-B',
          actor: { name: 'Ops User' },
        }),
      /fromLocationId is required for transfer movements/,
    );
    await backend.applyInventoryMovement({
      barcode: stockedMaterial.barcode,
      movementType: 'reserve',
      qty: 20,
      actor: { name: 'Ops User' },
    });
    await assert.rejects(
      () =>
        backend.applyInventoryMovement({
          barcode: stockedMaterial.barcode,
          movementType: 'release',
          qty: 25,
          actor: { name: 'Ops User' },
        }),
      /Insufficient reserved stock/,
    );
    await backend.applyInventoryMovement({
      barcode: stockedMaterial.barcode,
      movementType: 'adjust',
      qty: 5,
      actor: { name: 'Ops User' },
    });
    const latestMovement = await backend.get(
      `
      SELECT actor
      FROM inventory_movements
      WHERE material_barcode = ?
      ORDER BY datetime(created_at) DESC, rowid DESC
      LIMIT 1
      `,
      [stockedMaterial.barcode],
    );
    assert.equal(latestMovement?.actor, 'Ops User');
  } finally {
    await closeServer(server);
    await backend.closeDb();
  }
});

async function findActiveVariantItem(backend) {
  for (const row of await backend.getItemsWithUsage()) {
    if (row.is_archived) {
      continue;
    }
    const item = await backend.rowToItemDto(row);
    if (findFirstLeafVariation(item.variationTree)) {
      return item;
    }
  }
  throw new Error('No active variant item found.');
}

function findFirstLeafVariation(nodes, currentPath = [], currentSegments = []) {
  for (const node of nodes || []) {
    if (node.isArchived) {
      continue;
    }
    const activeChildren = (node.children || []).filter((child) => !child.isArchived);
    const nextPath =
      node.kind === 'value' ? [...currentPath, node.id] : [...currentPath];
    const nextSegments =
      node.kind === 'value' ? [...currentSegments, node.name] : [...currentSegments];
    if (
      node.kind === 'value' &&
      activeChildren.every((child) => child.kind !== 'property')
    ) {
      return {
        id: node.id,
        displayName: node.displayName,
        path: nextPath,
        label: nextSegments.join(' | '),
      };
    }
    const nested = findFirstLeafVariation(
      activeChildren,
      nextPath,
      nextSegments,
    );
    if (nested) {
      return nested;
    }
  }
  return null;
}

function findFirstVariationProperty(nodes) {
  for (const node of nodes || []) {
    if (node.isArchived) {
      continue;
    }
    if (node.kind === 'property') {
      return node;
    }
    const nested = findFirstVariationProperty(node.children || []);
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

async function postJson(baseUrl, pathName, token, body) {
  const response = await fetch(`${baseUrl}${pathName}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
  return { status: response.status, body: await response.json() };
}

async function patchJson(baseUrl, pathName, token, body) {
  const response = await fetch(`${baseUrl}${pathName}`, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
  return { status: response.status, body: await response.json() };
}

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => {
      resolve({ server, port: server.address().port });
    });
    server.on('error', reject);
  });
}

function closeServer(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}
