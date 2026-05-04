const baseUrl = String(process.env.PAPER_API_BASE_URL || 'http://localhost:18080').replace(/\/+$/, '');
const email = process.env.PAPER_CHECK_EMAIL || process.env.PAPER_SUPER_ADMIN_EMAIL || 'super@paper.local';
const password = process.env.PAPER_CHECK_PASSWORD || process.env.PAPER_SUPER_ADMIN_PASSWORD || 'Paper@12345';

async function request(method, path, { token, body } = {}) {
  const url = `${baseUrl}${path}`;
  const response = await fetch(url, {
    method,
    headers: {
      Accept: 'application/json',
      ...(body ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  const contentType = response.headers.get('content-type') || '';
  if (contentType.includes('text/html') || text.trimStart().startsWith('<')) {
    throw new Error(`${method} ${url} returned HTML instead of JSON: ${text.slice(0, 180)}`);
  }
  const json = JSON.parse(text);
  if (!response.ok || json.success !== true) {
    throw new Error(`${method} ${url} failed (${response.status}): ${json.error || text}`);
  }
  console.log(`${method} ${path} -> JSON ${response.status}`);
  return json;
}

(async () => {
  const login = await request('POST', '/api/auth/login', {
    body: { email, password },
  });
  const token = login.token;
  await request('GET', '/api/company-profile', { token });
  const orders = await request('GET', '/api/orders', { token });
  const order = orders.orders?.[0];
  if (!order) {
    throw new Error('No order available for delivery challan route check.');
  }
  await request('GET', '/api/delivery-challans/health');
  await request('GET', '/api/delivery-challans', { token });
  await request('GET', `/api/orders/${order.id}/delivery-challans`, { token });
  await request('POST', '/api/delivery-challans', {
    token,
    body: {
      order_id: order.id,
      date: new Date().toISOString().slice(0, 10),
      notes: '',
      items: [
        {
          order_item_id: order.id,
          quantity_pcs: '1',
          weight: '',
        },
      ],
    },
  });
})().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
