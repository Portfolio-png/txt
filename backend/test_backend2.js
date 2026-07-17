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
    const items = JSON.parse(data).items;
    const item = items.find(i => i.name === 'Custom Multi-Prop Item 1');
    
    // Add conversion
    item.unitConversions = [{ unitId: 2, factorToPrimary: 1.0 }];

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
