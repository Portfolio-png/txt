const baseUrl = String(process.env.BACKEND_BASE_URL || 'http://127.0.0.1:18080').replace(/\/+$/, '');
const email = String(process.env.PAPER_SMOKE_EMAIL || '').trim();
const password = String(process.env.PAPER_SMOKE_PASSWORD || '').trim();

async function parseJson(response) {
  const text = await response.text();
  try {
    return JSON.parse(text);
  } catch (_) {
    throw new Error(`Expected JSON but received: ${text.slice(0, 120)}`);
  }
}

async function main() {
  if (!email || !password) {
    throw new Error('PAPER_SMOKE_EMAIL and PAPER_SMOKE_PASSWORD are required.');
  }

  const healthResponse = await fetch(`${baseUrl}/health`);
  if (!healthResponse.ok) {
    throw new Error(`/health failed with ${healthResponse.status}`);
  }
  const health = await parseJson(healthResponse);
  if (health.success !== true) {
    throw new Error('/health payload was not successful.');
  }

  const loginResponse = await fetch(`${baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  if (!loginResponse.ok) {
    throw new Error(`/api/auth/login failed with ${loginResponse.status}`);
  }
  const login = await parseJson(loginResponse);
  const token = String(login.token || '').trim();
  if (login.success !== true || !token) {
    throw new Error('Login did not return a token.');
  }

  const meResponse = await fetch(`${baseUrl}/api/auth/me`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!meResponse.ok) {
    throw new Error(`/api/auth/me failed with ${meResponse.status}`);
  }
  const me = await parseJson(meResponse);
  if (me.success !== true || !me.user?.email) {
    throw new Error('/api/auth/me payload was invalid.');
  }

  const materialsResponse = await fetch(`${baseUrl}/api/materials?limit=1`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!materialsResponse.ok) {
    throw new Error(`/api/materials failed with ${materialsResponse.status}`);
  }
  const materials = await parseJson(materialsResponse);
  if (materials.success !== true || !Array.isArray(materials.materials)) {
    throw new Error('/api/materials payload was invalid.');
  }

  console.log('Smoke check passed.');
}

main().catch((error) => {
  console.error('Smoke check failed:', error.message);
  process.exit(1);
});
