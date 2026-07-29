const fs = require('fs');
let code = fs.readFileSync('backend/server.js', 'utf8');

const registerCode = `
const { registerItemsModuleRoutes } = require('./modules/items/routes');
registerItemsModuleRoutes({
  app,
  requirePermission,
  guardContract,
  get,
  all,
  run,
  logChange,
  saveItem,
  saveGroup,
  rowToItemDto,
  rowToGroupDto,
  getItemsWithUsage,
  getGroupsWithUsage,
  getItemUsageDetails,
  getItemRowById,
  getGroupRowById,
  getEffectiveSchema,
  trackCreate,
  trackUpdate,
  trackDelete,
  trashAndDelete,
  trashAndDeleteMany,
  createAssetUploadIntent,
  completeAssetUpload,
  listAssetsForEntity,
  itemsPorts,
  getIo: () => io,
});
`;

if (!code.includes('registerItemsModuleRoutes')) {
  code = code.replace("const server = app.listen(PORT, '0.0.0.0', async () => {", registerCode + "\n    const server = app.listen(PORT, '0.0.0.0', async () => {");
  fs.writeFileSync('backend/server.js', code);
  console.log('Injected registerItemsModuleRoutes');
} else {
  console.log('registerItemsModuleRoutes already exists');
}
