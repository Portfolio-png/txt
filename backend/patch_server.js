const fs = require('fs');

const path = 'f:/Rutu/txt/backend/server.js';
let content = fs.readFileSync(path, 'utf8');

// 1. Add column to ensureColumnExists calls
const ensureColumnExistsTarget = "await ensureColumnExists('materials', 'linked_variation_leaf_node_id', 'INTEGER');";
if (content.includes(ensureColumnExistsTarget) && !content.includes("'custom_variation_values_json'")) {
  content = content.replace(
    ensureColumnExistsTarget,
    `${ensureColumnExistsTarget}\n  await ensureColumnExists('materials', 'custom_variation_values_json', 'TEXT');`
  );
}

// 2. Add customVariationValues to rowToMaterialDto
const rowToMaterialDtoTarget = "linkedVariationLeafNodeId: row.linked_variation_leaf_node_id || null,";
if (content.includes(rowToMaterialDtoTarget) && !content.includes("customVariationValues:")) {
  content = content.replace(
    rowToMaterialDtoTarget,
    `${rowToMaterialDtoTarget}\n    customVariationValues: parseJson(row.custom_variation_values_json, null),`
  );
}

// 3. Update findMaterialByItemSelection
const findMaterialTarget = "async function findMaterialByItemSelection(itemId, variationLeafNodeId) {";
if (content.includes(findMaterialTarget)) {
  const newFindMaterial = `async function findMaterialByItemSelection(itemId, variationLeafNodeId, customVariationValues = null) {
  let customJson = null;
  if (customVariationValues && Object.keys(customVariationValues).length > 0) {
    const ordered = {};
    Object.keys(customVariationValues).sort().forEach(k => ordered[k] = customVariationValues[k]);
    customJson = JSON.stringify(ordered);
  }

  if (Number(variationLeafNodeId || 0) > 0 || customJson) {
    const exact = await get(
      \`
      SELECT *
      FROM materials
      WHERE linked_item_id = ?
        AND COALESCE(linked_variation_leaf_node_id, 0) = ?
        AND COALESCE(custom_variation_values_json, '') = COALESCE(?, '')
      ORDER BY id ASC
      LIMIT 1
      \`,
      [itemId, Number(variationLeafNodeId || 0), customJson],
    );
    if (exact) {
      return exact;
    }
  }
  const base = await get(
    \`
    SELECT *
    FROM materials
    WHERE linked_item_id = ?
      AND COALESCE(linked_variation_leaf_node_id, 0) = 0
      AND COALESCE(custom_variation_values_json, '') = ''
    ORDER BY id ASC
    LIMIT 1
    \`,
    [itemId],
  );
  if (base) {
    return base;
  }
  return get(
    \`
    SELECT *
    FROM materials
    WHERE linked_item_id = ?
    ORDER BY id ASC
    LIMIT 1
    \`,
    [itemId],
  );
}`;
  
  // Replace the old function. Find the end of it (which is before function generateStandaloneMaterialBarcode)
  const regex = /async function findMaterialByItemSelection[\s\S]*?(?=function generateStandaloneMaterialBarcode)/;
  content = content.replace(regex, newFindMaterial + '\n\n');
}

// 4. Update ensureMaterialForItemSelection
const ensureMaterialTarget = "async function ensureMaterialForItemSelection({ itemId, variationLeafNodeId = 0, actor = null }) {";
if (content.includes(ensureMaterialTarget)) {
  const newEnsureMaterial = `async function ensureMaterialForItemSelection({ itemId, variationLeafNodeId = 0, customVariationValues = null, actor = null }) {
  const existing = await findMaterialByItemSelection(itemId, variationLeafNodeId, customVariationValues);
  if (existing) {
    return existing;
  }
  const snapshot = await getItemSelectionSnapshot(itemId, variationLeafNodeId);
  const unit = snapshot.item.unit_id ? await getUnitRowById(snapshot.item.unit_id) : null;
  const now = new Date().toISOString();
  const barcode = generateStandaloneMaterialBarcode();
  
  let customJson = null;
  if (customVariationValues && Object.keys(customVariationValues).length > 0) {
    const ordered = {};
    Object.keys(customVariationValues).sort().forEach(k => ordered[k] = customVariationValues[k]);
    customJson = JSON.stringify(ordered);
  }

  await run(
    \`
    INSERT INTO materials (
      barcode, name, type, grade, thickness, supplier, location, unit_id, unit, notes,
      group_mode, inheritance_enabled, created_at, kind, parent_barcode, number_of_children,
      linked_child_barcodes, scan_count, linked_group_id, linked_item_id, linked_variation_leaf_node_id,
      custom_variation_values_json,
      display_stock, created_by, workflow_status, material_class, inventory_state, procurement_state,
      traceability_mode, on_hand_qty, reserved_qty, available_to_promise_qty, incoming_qty,
      linked_order_count, linked_pipeline_count, pending_alert_count, updated_at, last_scanned_at
    ) VALUES (?, ?, 'Item', '', '', '', '', ?, ?, '', NULL, 0, ?, 'standalone', NULL, 0, '[]', 0, NULL, ?, ?, ?, ?, 'notStarted', 'finished_good', 'available', 'not_ordered', 'bulk', 0, 0, 0, 0, 0, 0, 0, ?, NULL)
    \`,
    [
      barcode,
      snapshot.particulars || snapshot.item.display_name || snapshot.item.name,
      unit?.id || snapshot.item.unit_id || null,
      unit?.symbol || '',
      now,
      snapshot.item.id,
      snapshot.variationLeafNodeId > 0 ? snapshot.variationLeafNodeId : null,
      customJson,
      unit?.symbol ? \`0 \${unit.symbol}\` : '0',
      actor?.name || actor || 'System',
      now,
    ],
  );`;

  // Find where it ends: which is before `return findMaterialByItemSelection`
  const regexEnsure = /async function ensureMaterialForItemSelection[\s\S]*?(?=return findMaterialByItemSelection)/;
  content = content.replace(regexEnsure, newEnsureMaterial + '\n  ');
}

// 5. Update issueDeliveryChallan
// Specifically this block:
//      const material = normalizeChallanType(existing.type) === 'reception'
//        ? await ensureMaterialForItemSelection({
//            itemId: Number(item.item_id || 0),
//            variationLeafNodeId: Number(item.variation_leaf_node_id || 0),
//            actor,
//          })
//        : await findMaterialByItemSelection(
//            Number(item.item_id || 0),
//            Number(item.variation_leaf_node_id || 0),
//          );
const issueChallanTarget = /const material = normalizeChallanType\(existing\.type\) === 'reception'[\s\S]*?await findMaterialByItemSelection\([\s\S]*?\);/;
if (content.match(issueChallanTarget)) {
  const replacement = `const material = normalizeChallanType(existing.type) === 'reception'
        ? await ensureMaterialForItemSelection({
            itemId: Number(item.item_id || 0),
            variationLeafNodeId: Number(item.variation_leaf_node_id || 0),
            customVariationValues: item.custom_variation_values_json ? JSON.parse(item.custom_variation_values_json) : null,
            actor,
          })
        : await findMaterialByItemSelection(
            Number(item.item_id || 0),
            Number(item.variation_leaf_node_id || 0),
            item.custom_variation_values_json ? JSON.parse(item.custom_variation_values_json) : null,
          );`;
  content = content.replace(issueChallanTarget, replacement);
}

fs.writeFileSync(path, content, 'utf8');
console.log('Successfully patched server.js!');
