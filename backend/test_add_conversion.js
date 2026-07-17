const http = require('http');

const options = {
  hostname: '127.0.0.1',
  port: 18080,
  path: '/api/items',
  method: 'GET',
};

const req = http.request(options, (res) => {
  let data = '';
  res.on('data', (chunk) => {
    data += chunk;
  });
  res.on('end', () => {
    const items = JSON.parse(data);
    const item = items.find(i => i.name === 'Custom Multi-Prop Item 1');
    if(!item) {
        console.log("Item not found");
        return;
    }
    
    console.log("Found item with unit_id", item.unitId);

    // Add conversion
    item.unitConversions = [{ unitId: 261, factorToPrimary: 1.0 }]; // 261 is 'lm'

    const putReq = http.request({
      hostname: '127.0.0.1',
      port: 18080,
      path: `/api/items/${item.id}`,
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json'
      }
    }, (putRes) => {
      let putData = '';
      putRes.on('data', (chunk) => putData += chunk);
      putRes.on('end', () => console.log('PATCH response:', putData));
    });
    putReq.write(JSON.stringify(item));
    putReq.end();
  });
});

req.end();
