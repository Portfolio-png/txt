const fs = require('fs');
let code = fs.readFileSync('server.js', 'utf8');

// Update reseed-data endpoint
code = code.replace(
  `app.post(
  '/api/admin/reseed-data',
  requireRoles('super_admin', 'admin'),
  requirePermission('config.write'),
  async (_req, res) => {
    try {
      await reseedDemoData();`,
  `app.post(
  '/api/admin/reseed-data',
  requireRoles('super_admin', 'admin'),
  requirePermission('config.write'),
  async (req, res) => {
    try {
      const scenarioId = req.body?.scenarioId || 'default';
      await reseedDemoData(scenarioId);`
);

// We need to add scenarioId to reseedDemoData
code = code.replace(
  `async function reseedDemoData() {
  await seedMaterialsIfEmpty();
  await seedUnitsIfEmpty();
  await bootstrapUnitsFromMaterials();
  await backfillMaterialUnitIds();
  await seedClientsIfEmpty();
  await seedGroupsIfEmpty();
  await seedItemsIfEmpty();
  await seedOrdersIfEmpty();
  await seedTemplatesIfEmpty();
  await seedCompanyProfileIfEmpty();
  await ensureDemoDataset();
}`,
  `async function reseedDemoData(scenarioId = 'default') {
  await seedMaterialsIfEmpty();
  await seedUnitsIfEmpty();
  await bootstrapUnitsFromMaterials();
  await backfillMaterialUnitIds();
  await seedClientsIfEmpty();
  await seedGroupsIfEmpty(scenarioId);
  await seedItemsIfEmpty(scenarioId);
  await seedOrdersIfEmpty();
  await seedTemplatesIfEmpty();
  await seedCompanyProfileIfEmpty();
  await ensureDemoDataset(scenarioId);
  if (scenarioId === 'manufacturing') {
    await ensureDemoInventoryPresent(scenarioId);
  }
}`
);

// We need to add scenarioId to resetAndSeedDemoData
code = code.replace(
  `async function resetAndSeedDemoData() {
  await initDb();
  await clearAllData();
  await reseedDemoData();
}`,
  `async function resetAndSeedDemoData(scenarioId = 'default') {
  await initDb();
  await clearAllData();
  await reseedDemoData(scenarioId);
}`
);

// Now change ensureDemoGroupsPresent
code = code.replace(
  `async function ensureDemoGroupsPresent() {
  let [primary] = await all('SELECT id FROM groups WHERE name = ?', ['Primary Group']);
  if (!primary) {
    await run(
      \`INSERT INTO groups (id, name, created_at, updated_at) VALUES (356, 'Primary Group', datetime('now'), datetime('now'))\`
    );
  }
}`,
  `async function ensureDemoGroupsPresent(scenarioId = 'default') {
  let [primary] = await all('SELECT id FROM groups WHERE name = ?', ['Primary Group']);
  if (!primary) {
    await run(
      \`INSERT INTO groups (id, name, created_at, updated_at) VALUES (356, 'Primary Group', datetime('now'), datetime('now'))\`
    );
  }
  if (scenarioId === 'manufacturing') {
    let [mfg] = await all('SELECT id FROM groups WHERE name = ?', ['Manufacturing']);
    if (!mfg) {
      await run(
        \`INSERT INTO groups (id, name, created_at, updated_at) VALUES (400, 'Manufacturing', datetime('now'), datetime('now'))\`
      );
    }
  }
}`
);

code = code.replace(
  `async function seedGroupsIfEmpty() {
  const existing = await all('SELECT 1 FROM groups LIMIT 1');
  if (existing.length === 0) {
    await ensureDemoGroupsPresent();
  }
}`,
  `async function seedGroupsIfEmpty(scenarioId = 'default') {
  const existing = await all('SELECT 1 FROM groups LIMIT 1');
  if (existing.length === 0) {
    await ensureDemoGroupsPresent(scenarioId);
  }
}`
);

code = code.replace(
  `async function seedItemsIfEmpty() {
  const existing = await all('SELECT 1 FROM items LIMIT 1');
  if (existing.length === 0) {
    await ensureDemoItemsPresent();
  }
}`,
  `async function seedItemsIfEmpty(scenarioId = 'default') {
  const existing = await all('SELECT 1 FROM items LIMIT 1');
  if (existing.length === 0) {
    await ensureDemoItemsPresent(scenarioId);
  }
}`
);

// Replace ensureDemoUnitsPresent
code = code.replace(
  `async function ensureDemoUnitsPresent() {
  const desiredUnits = [
    { name: 'Piece', symbol: 'Pcs' },
    { name: 'Box', symbol: 'Box' },
    { name: 'Carton', symbol: 'Ctn' },
  ];`,
  `async function ensureDemoUnitsPresent(scenarioId = 'default') {
  let desiredUnits = [
    { name: 'Piece', symbol: 'Pcs' },
    { name: 'Box', symbol: 'Box' },
    { name: 'Carton', symbol: 'Ctn' },
  ];
  if (scenarioId === 'manufacturing') {
    desiredUnits = [
      { name: 'Kilogram', symbol: 'kg' },
      { name: 'Piece', symbol: 'Pcs' },
    ];
  }`
);

fs.writeFileSync('server.js', code);
console.log('Patched server.js with scenario logic framework');
