const fs = require('fs');
let content = fs.readFileSync('f:/Rutu/txt/backend/server.js', 'utf8');

const oldFindMaterial = `async function findMaterialByItemSelection(itemId, variationLeafNodeId, customVariationValues = null) {`;

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
  return base;
}

function generateStandaloneMaterialBarcode() {
  return \`MAT-\${Date.now()}-\${Math.floor(Math.random() * 100000)
    .toString()
    .padStart(5, '0')}\`;
}

async function ensureMaterialForItemSelection({ itemId, variationLeafNodeId = 0, customVariationValues = null, actor = null }) {
  const existing = await findMaterialByItemSelection(itemId, variationLeafNodeId, customVariationValues);
  if (existing) {
    return existing;
  }`;

const regex = /async function findMaterialByItemSelection[\s\S]*?(?=const snapshot = await getItemSelectionSnapshot)/;
if (content.match(regex)) {
  content = content.replace(regex, newFindMaterial + '\n  ');
  fs.writeFileSync('f:/Rutu/txt/backend/server.js', content, 'utf8');
  console.log("Patched server.js");
} else {
  console.log("Could not find regex!");
}
