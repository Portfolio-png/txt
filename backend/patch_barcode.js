const fs = require('fs');

const generateFunc = `async function generateBarcodeFromItemSelection(itemId, customVariationValues) {
  if (!customVariationValues || Object.keys(customVariationValues).length === 0) return null;
  const codes = [];
  for (const [propName, valName] of Object.entries(customVariationValues)) {
    const row = await get(\`
      SELECT v.code, p.position
      FROM item_variation_nodes v
      JOIN item_variation_nodes p ON v.parent_node_id = p.id
      WHERE v.item_id = ? AND p.name = ? AND (v.name = ? OR v.display_name = ?)
    \`, [itemId, propName, valName, valName]);
    if (row && row.code) {
      codes.push({ code: row.code, position: row.position });
    }
  }
  if (codes.length === 0) return null;
  codes.sort((a, b) => a.position - b.position);
  return codes.map(c => c.code).join('-');
}`;

const oldEnsure = `async function ensureMaterialForItemSelection({ itemId, variationLeafNodeId = 0, customVariationValues = null, actor = null }) {
  const existing = await findMaterialByItemSelection(itemId, variationLeafNodeId, customVariationValues);
  if (existing) {
    return existing;
  }
  const snapshot = await getItemSelectionSnapshot(itemId, variationLeafNodeId);
  const unit = snapshot.item.unit_id ? await getUnitRowById(snapshot.item.unit_id) : null;
  const now = new Date().toISOString();
  const barcode = generateStandaloneMaterialBarcode();`;

const newEnsure = `async function ensureMaterialForItemSelection({ itemId, variationLeafNodeId = 0, customVariationValues = null, actor = null }) {
  const existing = await findMaterialByItemSelection(itemId, variationLeafNodeId, customVariationValues);
  if (existing) {
    return existing;
  }
  const snapshot = await getItemSelectionSnapshot(itemId, variationLeafNodeId);
  const unit = snapshot.item.unit_id ? await getUnitRowById(snapshot.item.unit_id) : null;
  const now = new Date().toISOString();
  
  // Generate barcode from variation codes if possible
  let barcode = await generateBarcodeFromItemSelection(itemId, customVariationValues);
  if (!barcode) {
    barcode = generateStandaloneMaterialBarcode();
  } else {
    // Ensure uniqueness across the system by checking if it exists
    const existingBarcode = await getMaterialRowByBarcode(barcode);
    if (existingBarcode) {
      // If it exists but wasn't caught by findMaterialByItemSelection, it might be a collision.
      // We'll append a short random string to guarantee uniqueness.
      barcode = \`\${barcode}-\${Math.floor(Math.random() * 1000).toString().padStart(3, '0')}\`;
    }
  }`;

const serverJsPath = 'server.js';
let code = fs.readFileSync(serverJsPath, 'utf8');

if (!code.includes('generateBarcodeFromItemSelection')) {
  // Insert the helper function right before generateStandaloneMaterialBarcode
  code = code.replace('function generateStandaloneMaterialBarcode() {', generateFunc + '\\n\\nfunction generateStandaloneMaterialBarcode() {');
}

code = code.replace(oldEnsure, newEnsure);

fs.writeFileSync(serverJsPath, code);
console.log('Successfully patched barcode generation in server.js');
