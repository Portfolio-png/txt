const { saveOrder, get } = require('./server.js');
async function test() {
  try {
    const client = await get("SELECT id FROM clients LIMIT 1");
    const item = await get("SELECT id FROM items LIMIT 1");
    if (!client || !item) return console.log("No client or item");
    
    console.log("Client:", client.id, "Item:", item.id);
    
    const res = await saveOrder({
      orderNo: "test-" + Date.now(),
      clientId: client.id,
      itemId: item.id,
      quantity: 10,
      status: 'notStarted'
    });
    console.log("Success:", res);
  } catch (err) {
    console.log("Error:", err.message);
  }
}
setTimeout(test, 1000);
