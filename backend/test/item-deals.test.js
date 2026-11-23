const assert = require('node:assert/strict');
const http = require('node:http');
const path = require('node:path');
const test = require('node:test');
const { makeTempDir } = require('./helpers/temp-dir');

// One part, several companies (item_deals, 2026-11-24): each with its own
// quotation, people and recorded time. The development cost stays one figure
// on the part. The flat developed_for columns mirror the first deal, so the
// older single-deal readers and writers keep working.

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
    server.on('error', reject);
  });
}

async function boot(prefix) {
  const tempDir = makeTempDir(prefix);
  const email = `${prefix}owner@paper.local`;
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
  const headers = { 'Content-Type': 'application/json', Authorization: `Bearer ${login.token}` };
  const call = async (method, url, body) => {
    const response = await fetch(`${baseUrl}${url}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: response.status, body: await response.json() };
  };
  const close = async () => {
    await new Promise((resolve) => server.close(resolve));
    await backend.closeDb();
  };
  const listed = await call('GET', '/api/items');
  const sample = listed.body.items[0];
  const client = async (name) => {
    const made = await call('POST', '/api/clients', { name, contactName: `${name} lead` });
    assert.equal(made.status, 201, JSON.stringify(made.body));
    return made.body.client;
  };
  // A PATCH carries the part's name, group and unit, as every screen's does.
  const patch = (id, name, body) => call('PATCH', `/api/items/${id}`, {
    name, displayName: name, groupId: sample.groupId, unitId: sample.unitId, ...body,
  });
  return { backend, call, close, sample, client, patch };
}

test('two companies, two quotations: saved, read back in order, the first mirrored', async () => {
  const ctx = await boot('paper-deals-two-');
  try {
    const gold = await ctx.client('Gold Medal');
    const silver = await ctx.client('Silver Line');
    const made = await ctx.call('POST', '/api/items', {
      name: 'Two Quote Patti',
      displayName: 'Two Quote Patti',
      groupId: ctx.sample.groupId,
      unitId: ctx.sample.unitId,
      developedFor: { kind: 'client', clientId: gold.id, costAmount: 9000 },
      deals: [
        { kind: 'client', clientId: gold.id, quotationAmount: 45000, contactIds: [gold.contacts[0].id] },
        { kind: 'client', clientId: silver.id, quotationAmount: 52000 },
      ],
    });
    assert.equal(made.status, 201, JSON.stringify(made.body));
    const item = made.body.item;
    assert.deepEqual(item.deals.map((d) => [d.companyName, d.quotationAmount]), [
      ['Gold Medal', 45000],
      ['Silver Line', 52000],
    ]);
    assert.deepEqual(item.deals[0].contactIds, [gold.contacts[0].id], 'people kept per company');
    assert.deepEqual(item.deals[1].contactIds, []);
    assert.ok(item.deals.every((d) => d.at), 'each company has its recorded time');
    // The single block is the first company, with the part's own cost.
    assert.equal(item.developedFor.companyName, 'Gold Medal');
    assert.equal(item.developedFor.quotationAmount, 45000);
    assert.equal(item.developedFor.costAmount, 9000);

    // The list read agrees, and a save that does not mention deals keeps them.
    const quiet = await ctx.patch(item.id, 'Two Quote Patti', {});
    assert.equal(quiet.status, 200, JSON.stringify(quiet.body));
    const listed = await ctx.call('GET', '/api/items');
    const again = listed.body.items.find((row) => row.id === item.id);
    assert.equal(again.deals.length, 2);

    // Taking the first off: the next becomes the mirror.
    const dropped = await ctx.patch(item.id, 'Two Quote Patti', {
      deals: [{ kind: 'client', clientId: silver.id, quotationAmount: 52000 }],
    });
    assert.equal(dropped.status, 200, JSON.stringify(dropped.body));
    assert.equal(dropped.body.item.deals.length, 1);
    assert.equal(dropped.body.item.developedFor.companyName, 'Silver Line');
    assert.equal(dropped.body.item.developedFor.costAmount, 9000, 'the cost is the part\'s and stays');

    // [] clears every company.
    const cleared = await ctx.patch(item.id, 'Two Quote Patti', { deals: [] });
    assert.equal(cleared.status, 200, JSON.stringify(cleared.body));
    assert.deepEqual(cleared.body.item.deals, []);
    assert.equal(cleared.body.item.developedFor.kind, '');
  } finally {
    await ctx.close();
  }
});

test('one company twice, or a tab with no company, is refused', async () => {
  const ctx = await boot('paper-deals-refuse-');
  try {
    const gold = await ctx.client('Gold Medal');
    const base = {
      name: 'Refused Patti',
      displayName: 'Refused Patti',
      groupId: ctx.sample.groupId,
      unitId: ctx.sample.unitId,
    };
    const twice = await ctx.call('POST', '/api/items', {
      ...base,
      deals: [
        { kind: 'client', clientId: gold.id, quotationAmount: 1 },
        { kind: 'client', clientId: gold.id, quotationAmount: 2 },
      ],
    });
    assert.equal(twice.status, 400);
    assert.match(twice.body.error, /already on this part/);

    const empty = await ctx.call('POST', '/api/items', { ...base, deals: [{ quotationAmount: 5 }] });
    assert.equal(empty.status, 400);
    assert.match(empty.body.error, /needs its company/);
  } finally {
    await ctx.close();
  }
});

test('a save about the one deal (older screens) keeps the other companies', async () => {
  const ctx = await boot('paper-deals-legacy-');
  try {
    const gold = await ctx.client('Gold Medal');
    const silver = await ctx.client('Silver Line');
    const bronze = await ctx.client('Bronze Works');
    const made = await ctx.call('POST', '/api/items', {
      name: 'Legacy Patti',
      displayName: 'Legacy Patti',
      groupId: ctx.sample.groupId,
      unitId: ctx.sample.unitId,
      deals: [
        { kind: 'client', clientId: gold.id, quotationAmount: 100 },
        { kind: 'client', clientId: silver.id, quotationAmount: 200 },
      ],
    });
    assert.equal(made.status, 201, JSON.stringify(made.body));
    const id = made.body.item.id;

    // The item editor speaks about the one deal: it becomes the first.
    const edited = await ctx.patch(id, 'Legacy Patti', {
      developedFor: { kind: 'client', clientId: bronze.id, quotationAmount: 300 },
    });
    assert.equal(edited.status, 200, JSON.stringify(edited.body));
    assert.deepEqual(edited.body.item.deals.map((d) => d.companyName), ['Bronze Works', 'Silver Line']);

    // The first again names a company that is further down: not kept twice.
    const moved = await ctx.patch(id, 'Legacy Patti', {
      developedFor: { kind: 'client', clientId: silver.id, quotationAmount: 250 },
    });
    assert.deepEqual(moved.body.item.deals.map((d) => [d.companyName, d.quotationAmount]), [
      ['Silver Line', 250],
    ]);

    // "Developed for: self" clears every company.
    const self = await ctx.patch(id, 'Legacy Patti', { developedFor: { kind: 'self' } });
    assert.deepEqual(self.body.item.deals, []);
  } finally {
    await ctx.close();
  }
});

test('a part recorded with one deal before item_deals gets it as its first, once', async () => {
  const ctx = await boot('paper-deals-backfill-');
  try {
    const gold = await ctx.client('Gold Medal');
    const made = await ctx.call('POST', '/api/items', {
      name: 'Old Patti',
      displayName: 'Old Patti',
      groupId: ctx.sample.groupId,
      unitId: ctx.sample.unitId,
      developedFor: { kind: 'client', clientId: gold.id, quotationAmount: 700 },
    });
    const id = made.body.item.id;
    // As an older database holds it: the flat columns, no deal rows.
    await ctx.backend.run('DELETE FROM item_deals WHERE item_id = ?', [id]);
    const { createSchema } = require('../modules/items/schema');
    const db = { run: ctx.backend.run, all: ctx.backend.all, get: ctx.backend.get };
    await createSchema(db);
    await createSchema(db);
    const rows = await ctx.backend.all('SELECT * FROM item_deals WHERE item_id = ?', [id]);
    assert.equal(rows.length, 1, 'carried over once, not once per boot');
    assert.equal(rows[0].client_id, gold.id);
    assert.equal(rows[0].quotation_amount, 700);
  } finally {
    await ctx.close();
  }
});
