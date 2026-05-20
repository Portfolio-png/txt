const backend = require('../server.js');
async function test() {
  const ids = [16, 17];
  for (const id of ids) {
    try {
      const challan = await backend.issueDeliveryChallan(id, { id: 1, name: 'System', role: 'admin' });
      console.log(`Success ${id}:`, challan.challan_no);
    } catch (e) {
      console.error(`Error issuing challan ${id}:`, e.message);
    }
  }
}
setTimeout(test, 1000);
