const test = require('node:test');
const { app } = require('./server.js');
const request = require('supertest');
test('debug', async () => {
  const agent = request(app);
  await agent.post('/api/admin/reset-demo-data');
  const r = await agent.get('/api/inventory/items');
  const item = r.body.items.find(i => !i.isArchived);
  console.log(item ? item.name : 'No items');
  console.log(item ? JSON.stringify(item.variationTree, null, 2) : '');
});
