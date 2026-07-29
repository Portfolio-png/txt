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

code = code.replace(registerCode, "");
code = code.replace("const { registerItemsModuleRoutes } = require('./modules/items/routes');", "");

code = code.replace(
  'const { computeTerritory } = require("./kernel/territory");',
  registerCode + '\nconst { computeTerritory } = require("./kernel/territory");'
);

fs.writeFileSync('backend/server.js', code);
console.log('Fixed routes placement');
