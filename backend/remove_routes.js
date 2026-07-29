const fs = require('fs');

const serverJsPath = 'backend/server.js';
const content = fs.readFileSync(serverJsPath, 'utf8');

// List of exact route signatures to remove
const routesToRemove = [
  "app.get('/api/groups'",
  "app.post('/api/items/:id/assets/upload-intent'",
  "app.post('/api/items/:id/assets/upload-complete'",
  "app.get('/api/items/:id/assets'",
  "app.get('/api/items/:id/usage'",
  "app.get('/api/items'",
  "app.get('/api/items/:id'",
  "app.put('/api/items/:id/short-code'",
  "app.post('/api/items'",
  "app.patch('/api/items/:id'",
  "app.delete('/api/items/:id'",
  "app.patch('/api/items/:id/group'",
  "app.post('/api/groups'",
  "app.post('/api/groups/:groupId/items'",
  "app.get('/api/groups/:groupId/items'",
  "app.patch('/api/groups/:id'",
  "app.delete('/api/groups/:id'",
  "app.get('/api/groups/:id/effective-schema'"
];

const lines = content.split('\n');
const newLines = [];
let insideRoute = false;

for (let i = 0; i < lines.length; i++) {
  const line = lines[i];

  if (!insideRoute) {
    let match = false;
    for (const route of routesToRemove) {
      if (line.startsWith(route)) {
        match = true;
        break;
      }
    }
    if (match) {
      insideRoute = true;
    } else {
      newLines.push(line);
    }
  } else {
    // We are inside a route to remove. Wait until we see exactly "});" at the start of the line.
    if (line === '});') {
      insideRoute = false;
    }
  }
}

// Ensure registerItemsModuleRoutes is added if not present
let outStr = newLines.join('\n');
if (!outStr.includes('registerItemsModuleRoutes(')) {
  const registerCode = `
// Items module routes (evacuated to modules/items/routes.js). Domain logic
// still lives here in legacy and is handed over via this ctx; it shrinks as
// the evacuation proceeds — never grows (kernel rule K2).
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
  // Add it before "const server = http.createServer(app);" or at the end
  outStr = outStr.replace('const server = http.createServer(app);', registerCode + '\nconst server = http.createServer(app);');
}

if (!outStr.includes("const { registerItemsModuleRoutes } = require('./modules/items/routes');")) {
  outStr = outStr.replace("const { createItemsPorts } = require('./modules/items/ports');", 
  "const { createItemsPorts } = require('./modules/items/ports');\nconst { registerItemsModuleRoutes } = require('./modules/items/routes');");
}

fs.writeFileSync(serverJsPath, outStr, 'utf8');
console.log('Removed ' + routesToRemove.length + ' routes and injected registerItemsModuleRoutes');
