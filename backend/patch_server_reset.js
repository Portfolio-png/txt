const fs = require('fs');

let code = fs.readFileSync('server.js', 'utf8');
code = code.replace(
  `app.post(
  '/api/admin/reset-demo-data',
  requireRoles('super_admin', 'admin'),
  requirePermission('config.write'),
  async (_req, res) => {
    try {
      await resetAndSeedDemoData();`,
  `app.post(
  '/api/admin/reset-demo-data',
  requireRoles('super_admin', 'admin'),
  requirePermission('config.write'),
  async (req, res) => {
    try {
      const scenarioId = req.body?.scenarioId || 'default';
      await resetAndSeedDemoData(scenarioId);`
);

fs.writeFileSync('server.js', code);
console.log('Patched reset-demo-data endpoint in server.js');
