const http = require('http');

const ITEM_NAMES = [
  'iPhone 15',
  'MacBook Pro',
  'Nike Air Max',
  'Classic T-Shirt',
  "Levi's 501 Jeans",
  'Samsung Galaxy S24',
  'Sony WH-1000XM5',
  'Apple Watch Series 9',
  'Nintendo Switch',
  'Kindle Paperwhite'
];

const VARIATIONS = [
  { name: 'Black', code: 'BLK' },
  { name: 'White', code: 'WHT' },
  { name: 'Blue', code: 'BLU' },
  { name: 'Yellow', code: 'YEL' },
  { name: 'Green', code: 'GRN' },
  { name: 'Pink', code: 'PNK' },
  { name: 'Red', code: 'RED' },
  { name: 'Purple', code: 'PUR' },
  { name: 'Orange', code: 'ORG' },
  { name: 'Silver', code: 'SLV' },
];

async function postItem(item) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(item);
    const req = http.request(
      {
        hostname: 'localhost',
        port: 18080,
        path: '/api/items',
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(data),
        },
      },
      (res) => {
        let body = '';
        res.on('data', (c) => body += c);
        res.on('end', () => resolve({ status: res.statusCode, body }));
      }
    );
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

async function run() {
  for (const name of ITEM_NAMES) {
    const item = {
      name: name,
      displayName: name,
      groupId: 349,
      unitId: 257,
      availableForPurchase: true,
      availableForSale: true,
      quantity: 100, // starting quantity
      variationNodes: [
        {
          kind: 'property',
          name: 'Color',
          displayName: 'Color',
          children: VARIATIONS.map((v) => ({
            kind: 'value',
            name: v.name,
            code: v.code,
            displayName: v.name,
          })),
        },
      ],
    };

    console.log(`Creating item: ${name}...`);
    try {
      const res = await postItem(item);
      console.log(`Response: ${res.status} - ${res.body}`);
    } catch (err) {
      console.error(`Failed to create ${name}:`, err.message);
    }
  }
}

run();
