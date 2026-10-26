const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// The people at a company (migrations/056): as many as it has, one of them the
// person to ring first, and a part's deal ticking any number of them. The
// quotation stays one figure per part whoever was spoken to.

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => {
      resolve({ server, port: server.address().port });
    });
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
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;
  const login = await fetch(`${baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: 'OwnerPass1234' }),
  }).then((r) => r.json());
  assert.ok(login.token, 'expected a login token');
  return {
    backend,
    server,
    baseUrl,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${login.token}`,
    },
  };
}

async function call(ctx, method, url, body) {
  const response = await fetch(`${ctx.baseUrl}${url}`, {
    method,
    headers: ctx.headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: response.status, body: await response.json() };
}

async function createClient(ctx, body) {
  const made = await call(ctx, 'POST', '/api/clients', body);
  assert.equal(made.status, 201, JSON.stringify(made.body));
  return made.body.client;
}

async function addPerson(ctx, clientId, body) {
  const made = await call(ctx, 'POST', `/api/clients/${clientId}/contacts`, body);
  assert.equal(made.status, 201, JSON.stringify(made.body));
  return made.body.contact;
}

async function anyItemShape(ctx) {
  const listed = await call(ctx, 'GET', '/api/items');
  const sample = listed.body.items[0];
  assert.ok(sample, 'the demo seed should leave at least one item');
  return sample;
}

test('a company holds many people, one of them primary, mirrored onto the flat fields', async () => {
  const ctx = await boot('paper-contacts-many-', 'contacts-many@paper.local');
  try {
    // The client form's one person becomes the primary contact.
    const client = await createClient(ctx, {
      name: 'Gold Medal Electricals',
      contactName: 'Kissan Jain',
      designation: 'Director',
      phone: '9865656560',
    });
    assert.equal(client.contacts.length, 1);
    assert.equal(client.contacts[0].name, 'Kissan Jain');
    assert.equal(client.contacts[0].isPrimary, true);

    const ravi = await addPerson(ctx, client.id, {
      name: '  Ravi Shah ',
      designation: 'Purchase',
      phone: '9822000000',
      email: 'ravi@gold.example',
    });
    assert.equal(ravi.name, 'Ravi Shah');
    assert.equal(ravi.isPrimary, false, 'the second person is not first to ring');
    await addPerson(ctx, client.id, { name: 'Meena Patil', designation: 'Accounts' });

    let read = await call(ctx, 'GET', `/api/clients/${client.id}`);
    assert.deepEqual(
      read.body.client.contacts.map((c) => c.name),
      ['Kissan Jain', 'Meena Patil', 'Ravi Shah'],
      'primary first, then by name',
    );

    // Making Ravi primary demotes Kissan and moves the flat fields with it.
    const promoted = await call(ctx, 'PATCH', `/api/clients/${client.id}/contacts/${ravi.id}`, {
      isPrimary: true,
    });
    assert.equal(promoted.status, 200, JSON.stringify(promoted.body));
    read = await call(ctx, 'GET', `/api/clients/${client.id}`);
    assert.equal(read.body.client.contactName, 'Ravi Shah');
    assert.equal(read.body.client.designation, 'Purchase');
    assert.equal(read.body.client.contacts.filter((c) => c.isPrimary).length, 1);

    // The list read carries everyone too, without a query per client.
    const listed = await call(ctx, 'GET', '/api/clients');
    const listedClient = listed.body.clients.find((c) => c.id === client.id);
    assert.equal(listedClient.contacts.length, 3);

    // A client PATCH about the address leaves the people alone.
    await call(ctx, 'PATCH', `/api/clients/${client.id}`, { address: 'MIDC, Pune' });
    read = await call(ctx, 'GET', `/api/clients/${client.id}/contacts`);
    assert.equal(read.body.contacts.length, 3);
    assert.equal(read.body.contacts[0].name, 'Ravi Shah');

    // Archiving the primary hands the first call to the longest-standing
    // person still on file. Leaving the slot empty stranded the client with
    // no primary for good — nothing in the app sets one.
    const archived = await call(
      ctx,
      'PATCH',
      `/api/clients/${client.id}/contacts/${ravi.id}/archive`,
      {},
    );
    assert.equal(archived.body.contact.isArchived, true);
    assert.equal(archived.body.contact.isPrimary, false);
    read = await call(ctx, 'GET', `/api/clients/${client.id}/contacts`);
    const nextUp = read.body.contacts.filter((c) => c.isPrimary);
    assert.equal(nextUp.length, 1);
    assert.notEqual(nextUp[0].id, ravi.id);
    read = await call(ctx, 'GET', `/api/clients/${client.id}`);
    assert.equal(read.body.client.contactName, nextUp[0].name);

    // Someone archived cannot be made the first call until restored.
    const refused = await call(
      ctx,
      'PATCH',
      `/api/clients/${client.id}/contacts/${ravi.id}`,
      { isPrimary: true },
    );
    assert.equal(refused.status, 400);
  } finally {
    await closeServer(ctx.server);
  }
});

test('a person needs a name and belongs to one client', async () => {
  const ctx = await boot('paper-contacts-rules-', 'contacts-rules@paper.local');
  try {
    const one = await createClient(ctx, { name: 'One Co' });
    const two = await createClient(ctx, { name: 'Two Co' });

    const nameless = await call(ctx, 'POST', `/api/clients/${one.id}/contacts`, { name: '   ' });
    assert.equal(nameless.status, 400);

    const missing = await call(ctx, 'POST', '/api/clients/999999/contacts', { name: 'Ghost' });
    assert.equal(missing.status, 404);

    const person = await addPerson(ctx, one.id, { name: 'Asha' });
    assert.equal(person.isPrimary, true, 'the first person at a company is primary');

    const elsewhere = await call(ctx, 'PATCH', `/api/clients/${two.id}/contacts/${person.id}`, {
      phone: '1',
    });
    assert.equal(elsewhere.status, 404, 'a person is edited only through their own company');

    const blanked = await call(ctx, 'PATCH', `/api/clients/${one.id}/contacts/${person.id}`, {
      name: '',
    });
    assert.equal(blanked.status, 400);
  } finally {
    await closeServer(ctx.server);
  }
});

test('a deal ticks several people; absent keeps them, a new client clears them', async () => {
  const ctx = await boot('paper-contacts-deal-', 'contacts-deal@paper.local');
  try {
    const sample = await anyItemShape(ctx);
    const client = await createClient(ctx, { name: 'Deal Co', contactName: 'Kissan' });
    const kissan = client.contacts[0];
    const ravi = await addPerson(ctx, client.id, { name: 'Ravi', designation: 'Purchase' });
    const meena = await addPerson(ctx, client.id, { name: 'Meena' });

    const created = await call(ctx, 'POST', '/api/items', {
      name: 'Deal Patti',
      displayName: 'Deal Patti',
      groupId: sample.groupId,
      unitId: sample.unitId,
      developedFor: {
        kind: 'client',
        clientId: client.id,
        quotationAmount: 45000,
        contactIds: [ravi.id, meena.id],
      },
    });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    const itemId = created.body.item.id;
    let block = created.body.item.developedFor;
    assert.deepEqual([...block.contactIds].sort(), [ravi.id, meena.id].sort());
    assert.equal(block.quotationAmount, 45000, 'one quotation for the part');
    // The single person older surfaces print is one of the ticked, not the
    // company's primary who was not on this deal.
    assert.notEqual(block.contactName, 'Kissan');

    // The single read (the route with its own SELECT) agrees.
    let read = await call(ctx, 'GET', `/api/items/${itemId}`);
    assert.equal(read.status, 200, JSON.stringify(read.body));
    assert.equal(read.body.item.developedFor.contacts.length, 2);

    // A save that does not mention contactIds keeps them.
    const quiet = await call(ctx, 'PATCH', `/api/items/${itemId}`, {
      name: 'Deal Patti',
      displayName: 'Deal Patti',
      groupId: sample.groupId,
      unitId: sample.unitId,
      developedFor: { kind: 'client', clientId: client.id, quotationAmount: 46000 },
    });
    assert.equal(quiet.status, 200, JSON.stringify(quiet.body));
    assert.equal(quiet.body.item.developedFor.contactIds.length, 2);
    assert.equal(quiet.body.item.developedFor.quotationAmount, 46000);

    // Present replaces.
    const replaced = await call(ctx, 'PATCH', `/api/items/${itemId}`, {
      name: 'Deal Patti',
      displayName: 'Deal Patti',
      groupId: sample.groupId,
      unitId: sample.unitId,
      developedFor: { kind: 'client', clientId: client.id, contactIds: [kissan.id] },
    });
    assert.deepEqual(replaced.body.item.developedFor.contactIds, [kissan.id]);

    // A person from another company is refused.
    const other = await createClient(ctx, { name: 'Other Co', contactName: 'Stranger' });
    const foreign = await call(ctx, 'PATCH', `/api/items/${itemId}`, {
      name: 'Deal Patti',
      displayName: 'Deal Patti',
      groupId: sample.groupId,
      unitId: sample.unitId,
      developedFor: { kind: 'client', clientId: client.id, contactIds: [other.contacts[0].id] },
    });
    assert.equal(foreign.status, 400, JSON.stringify(foreign.body));

    // Moving the part to another client without naming people clears the old.
    const moved = await call(ctx, 'PATCH', `/api/items/${itemId}`, {
      name: 'Deal Patti',
      displayName: 'Deal Patti',
      groupId: sample.groupId,
      unitId: sample.unitId,
      developedFor: { kind: 'client', clientId: other.id },
    });
    assert.equal(moved.status, 200, JSON.stringify(moved.body));
    assert.deepEqual(moved.body.item.developedFor.contactIds, []);

    // Self with a tick is a contradiction, not something to quietly drop.
    const selfWithTick = await call(ctx, 'PATCH', `/api/items/${itemId}`, {
      name: 'Deal Patti',
      displayName: 'Deal Patti',
      groupId: sample.groupId,
      unitId: sample.unitId,
      developedFor: { kind: 'self', contactIds: [kissan.id] },
    });
    assert.equal(selfWithTick.status, 400, JSON.stringify(selfWithTick.body));

    // Archiving a ticked person keeps them on the part.
    await call(ctx, 'PATCH', `/api/items/${itemId}`, {
      name: 'Deal Patti',
      displayName: 'Deal Patti',
      groupId: sample.groupId,
      unitId: sample.unitId,
      developedFor: { kind: 'client', clientId: client.id, contactIds: [ravi.id] },
    });
    await call(ctx, 'PATCH', `/api/clients/${client.id}/contacts/${ravi.id}/archive`, {});
    read = await call(ctx, 'GET', `/api/items/${itemId}`);
    block = read.body.item.developedFor;
    assert.deepEqual(block.contactIds, [ravi.id]);
    assert.equal(block.contacts[0].isArchived, true);
  } finally {
    await closeServer(ctx.server);
  }
});

test('a new name on the client form is a new person; the same name edits them', async () => {
  // Renaming the primary in place rewrote history: every part whose deal
  // ticked Kissan would have said it was done with Meena.
  const ctx = await boot('paper-contacts-rename-', 'contacts-rename@paper.local');
  try {
    const client = await createClient(ctx, {
      name: 'Rename Electricals',
      contactName: 'Kissan Jain',
      phone: '9865656560',
    });
    const kissan = client.contacts[0];

    // Same person, spelled with different spacing and case: edited in place.
    let saved = await call(ctx, 'PATCH', `/api/clients/${client.id}`, {
      contactName: 'kissan  jain',
      phone: '9800000000',
    });
    assert.equal(saved.status, 200, JSON.stringify(saved.body));
    let read = await call(ctx, 'GET', `/api/clients/${client.id}/contacts`);
    assert.equal(read.body.contacts.length, 1);
    assert.equal(read.body.contacts[0].id, kissan.id);
    assert.equal(read.body.contacts[0].phone, '9800000000');

    // A different name: a new primary, and Kissan stays on file.
    saved = await call(ctx, 'PATCH', `/api/clients/${client.id}`, {
      contactName: 'Meena Patil',
      phone: '9811111111',
    });
    assert.equal(saved.status, 200, JSON.stringify(saved.body));
    read = await call(ctx, 'GET', `/api/clients/${client.id}/contacts`);
    const before = read.body.contacts.find((c) => c.id === kissan.id);
    const meena = read.body.contacts.find((c) => c.name === 'Meena Patil');
    assert.ok(before, 'the old person is kept, not renamed');
    assert.notEqual(before.name, 'Meena Patil');
    assert.equal(before.isPrimary, false);
    assert.equal(before.phone, '9800000000');
    assert.ok(meena && meena.id !== kissan.id);
    assert.equal(meena.isPrimary, true);
    assert.equal(meena.phone, '9811111111');
    const flat = await call(ctx, 'GET', `/api/clients/${client.id}`);
    assert.equal(flat.body.client.contactName, 'Meena Patil');
  } finally {
    await closeServer(ctx.server);
  }
});
