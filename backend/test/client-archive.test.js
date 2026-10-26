const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// Archiving a client: the honest way to take one out of use.
//
// Same half-built shape the group route was in — it existed with no Dart
// caller, answered with nothing but `{success}`, never broadcast, logged
// nothing, and refused with the bare words "Client is in use" without saying
// what was using it. There was no way back at all. This covers the finished
// shape.

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
    server.on('error', reject);
  });
}

function closeServer(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}

async function boot(prefix, email) {
  const tempDir = mkdtempSync(path.join(tmpdir(), prefix));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = email;
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'ArchivePass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  const { token } = await fetch(`${baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: 'ArchivePass1234' }),
  }).then((r) => r.json());
  const headers = { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` };

  const call = async (method, p, body) => {
    const r = await fetch(`${baseUrl}${p}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: r.status, body: await r.json() };
  };

  return { backend, server, call };
}

test('a client archives, comes back, and says what is holding it', async () => {
  const ctx = await boot('paper-client-archive-', 'client-archive@paper.local');
  try {
    const { call } = ctx;

    const made = await call('POST', '/api/clients', {
      name: 'Archivable Papers',
      alias: 'Archivable',
      gstNumber: '',
      address: 'Nowhere',
    });
    assert.equal(made.status, 201, JSON.stringify(made.body));
    const client = made.body.client;

    // Archiving answers with the row, so a caller knows the new state without
    // refetching the whole list.
    const archived = await call('PATCH', `/api/clients/${client.id}/archive`);
    assert.equal(archived.status, 200, JSON.stringify(archived.body));
    assert.equal(archived.body.client.isArchived, true);

    // Pressing it twice is not an error — two sessions may race the button.
    const again = await call('PATCH', `/api/clients/${client.id}/archive`);
    assert.equal(again.status, 200);
    assert.equal(again.body.client.isArchived, true);

    // And there is a way back, which there was not before at all.
    const restored = await call('PATCH', `/api/clients/${client.id}/unarchive`);
    assert.equal(restored.status, 200, JSON.stringify(restored.body));
    assert.equal(restored.body.client.isArchived, false);
  } finally {
    await closeServer(ctx.server);
  }
});

test('a client holding a sub-contractor names it rather than saying "in use"', async () => {
  const ctx = await boot('paper-client-blocked-', 'client-blocked@paper.local');
  try {
    const { call } = ctx;

    const made = await call('POST', '/api/clients', {
      name: 'Held Papers',
      alias: 'Held',
      gstNumber: '',
      address: 'Somewhere',
    });
    assert.equal(made.status, 201, JSON.stringify(made.body));
    const client = made.body.client;

    const sub = await call('POST', `/api/clients/${client.id}/sub-contractors`, {
      name: 'Bend Works',
      designation: 'Bending',
    });
    assert.ok(sub.status === 201 || sub.status === 200, JSON.stringify(sub.body));

    const refused = await call('PATCH', `/api/clients/${client.id}/archive`);
    assert.equal(refused.status, 409, JSON.stringify(refused.body));
    assert.equal(refused.body.code, 'client_in_use');
    // The refusal has to name what is holding it; "Client is in use" sent the
    // user looking through every screen in the product.
    assert.match(refused.body.error, /Held Papers/);
    assert.match(refused.body.error, /1 sub-contractor/);

    // And it really is still active, not half-archived.
    const listed = await call('GET', '/api/clients');
    const row = listed.body.clients.find((c) => c.id === client.id);
    assert.equal(row.isArchived, false);
  } finally {
    await closeServer(ctx.server);
  }
});

test('archiving a client that is not there is a 404, not a 500', async () => {
  const ctx = await boot('paper-client-missing-', 'client-missing@paper.local');
  try {
    const missing = await ctx.call('PATCH', '/api/clients/999999/archive');
    assert.equal(missing.status, 404, JSON.stringify(missing.body));
    const back = await ctx.call('PATCH', '/api/clients/999999/unarchive');
    assert.equal(back.status, 404, JSON.stringify(back.body));
  } finally {
    await closeServer(ctx.server);
  }
});

test('a client keeps its logo, and one still in use cannot be deleted', async () => {
  const ctx = await boot('paper-client-delete-', 'client-delete@paper.local');
  try {
    const { call } = ctx;
    // The editor uploads a logo and saves; the server used to accept it and
    // store nothing, so it was blank on reopen.
    const made = await call('POST', '/api/clients', {
      name: 'Logo Papers',
      logoUrl: 'https://cdn.example/logo.png',
      photoUrl: 'https://cdn.example/photo.png',
    });
    assert.equal(made.status, 201, JSON.stringify(made.body));
    const client = made.body.client;
    assert.equal(client.logoUrl, 'https://cdn.example/logo.png');
    assert.equal(client.photoUrl, 'https://cdn.example/photo.png');

    // A PATCH about something else keeps it.
    const patched = await call('PATCH', `/api/clients/${client.id}`, { address: 'Pune' });
    assert.equal(patched.body.client.logoUrl, 'https://cdn.example/logo.png');

    // Named on a sub-contractor: delete refuses and says why, as archive does.
    const sub = await call('POST', `/api/clients/${client.id}/sub-contractors`, { name: 'Ashok Dies' });
    assert.ok(sub.status < 300, JSON.stringify(sub.body));
    const refused = await call('DELETE', `/api/clients/${client.id}`);
    assert.equal(refused.status, 409, JSON.stringify(refused.body));
    assert.equal(refused.body.code, 'client_in_use');
    assert.match(refused.body.error, /sub-contractor/);

    // Nothing holding it: it goes.
    const free = await call('POST', '/api/clients', { name: 'Unused Papers' });
    const gone = await call('DELETE', `/api/clients/${free.body.client.id}`);
    assert.equal(gone.status, 200, JSON.stringify(gone.body));
  } finally {
    await new Promise((resolve) => ctx.server.close(resolve));
  }
});
