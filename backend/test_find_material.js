const sqlite3 = require('sqlite3');
const db = new sqlite3.Database('paper.db');

const get = (query, params = []) => new Promise((resolve, reject) => {
  db.get(query, params, (err, row) => err ? reject(err) : resolve(row));
});

async function findMaterialByItemSelection(itemId, variationLeafNodeId, customVariationValues = null) {
  let customJson = null;
  if (customVariationValues && Object.keys(customVariationValues).length > 0) {
    const ordered = {};
    Object.keys(customVariationValues).sort().forEach(k => ordered[k] = customVariationValues[k]);
    customJson = JSON.stringify(ordered);
  }

  if (Number(variationLeafNodeId || 0) > 0 || customJson) {
    const exact = await get(
      `
      SELECT *
      FROM materials
      WHERE linked_item_id = ?
        AND COALESCE(linked_variation_leaf_node_id, 0) = ?
        AND COALESCE(custom_variation_values_json, '') = COALESCE(?, '')
      ORDER BY id ASC
      LIMIT 1
      `,
      [itemId, Number(variationLeafNodeId || 0), customJson],
    );
    if (exact) {
      return exact;
    }
  }
  const base = await get(
    `
    SELECT *
    FROM materials
    WHERE linked_item_id = ?
      AND COALESCE(linked_variation_leaf_node_id, 0) = 0
      AND COALESCE(custom_variation_values_json, '') = ''
    ORDER BY id ASC
    LIMIT 1
    `,
    [itemId],
  );
  return base;
}

findMaterialByItemSelection(8, 17).then(console.log).catch(console.error);
