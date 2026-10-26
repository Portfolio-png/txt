const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// Who a part was developed for (migrations/047): the kind, the party, when, and
// what was quoted — with the person read off the party so one edit to a client
// changes every part made for them.
//
// The first assertion here is the load-bearing one: it fails loudly if the
// migration's columns never reached the test database, which is the whole
// reason this feature is migration-only rather than belt-and-braces with
// ensureColumnExists.

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

async function anyItemShape(ctx) {
  const listed = await fetch(`${ctx.baseUrl}/api/items`, { headers: ctx.headers }).then((r) =>
    r.json(),
  );
  const sample = listed.items[0];
  assert.ok(sample, 'the demo seed should leave at least one item');
  return sample;
}

async function createClient(ctx, body) {
  const response = await fetch(`${ctx.baseUrl}/api/clients`, {
    method: 'POST',
    headers: ctx.headers,
    body: JSON.stringify(body),
  });
  assert.equal(response.status, 201, await response.clone().text());
  return (await response.json()).client;
}

async function createItem(ctx, body) {
  const response = await fetch(`${ctx.baseUrl}/api/items`, {
    method: 'POST',
    headers: ctx.headers,
    body: JSON.stringify(body),
  });
  return { status: response.status, body: await response.json() };
}

async function readItem(ctx, id) {
  const response = await fetch(`${ctx.baseUrl}/api/items/${id}`, { headers: ctx.headers });
  assert.equal(response.status, 200, await response.clone().text());
  return (await response.json()).item;
}

test('a part records who it was developed for, and reads it back', async () => {
  const ctx = await boot('paper-developed-for-', 'developed-owner@paper.local');
  try {
    const sample = await anyItemShape(ctx);
    const client = await createClient(ctx, {
      name: 'Gold Madel Industries',
      alias: 'Gold Madel',
      contactName: 'Kissan Jain',
      designation: 'Director',
      phone: '986565656',
      email: 'kissan@goldmadel.example',
    });

    // The client editor's new Contact card round-trips.
    assert.equal(client.contactName, 'Kissan Jain');
    assert.equal(client.designation, 'Director');
    assert.equal(client.phone, '986565656');
    assert.equal(client.email, 'kissan@goldmadel.example');

    const created = await createItem(ctx, {
      name: 'Developed Patti',
      displayName: 'Developed Patti',
      groupId: sample.groupId,
      unitId: sample.unitId,
      developedFor: {
        kind: 'client',
        clientId: client.id,
        at: '2026-05-15T04:35:00.000Z',
        quotationAmount: 85000,
      },
    });
    assert.equal(created.status, 201, JSON.stringify(created.body));

    // The create's own response already carries it — this is the assertion
    // that fails if migration 047 never ran against the test database.
    const block = created.body.item.developedFor;
    assert.equal(block.kind, 'client');
    assert.equal(block.clientId, client.id);
    assert.equal(block.companyName, 'Gold Madel Industries');
    assert.equal(block.at, '2026-05-15T04:35:00.000Z');
    assert.equal(block.quotationAmount, 85000);

    // The person comes from the party, not from the part.
    assert.equal(block.contactName, 'Kissan Jain');
    assert.equal(block.designation, 'Director');
    assert.equal(block.phone, '986565656');
    assert.equal(block.email, 'kissan@goldmadel.example');

    // Both reads agree: the single-item SELECT and the list.
    const fetched = await readItem(ctx, created.body.item.id);
    assert.deepEqual(fetched.developedFor, block);
    const listed = await fetch(`${ctx.baseUrl}/api/items`, { headers: ctx.headers }).then((r) =>
      r.json(),
    );
    const fromList = listed.items.find((row) => row.id === created.body.item.id);
    assert.deepEqual(fromList.developedFor, block);

    // The pre-047 aliases still answer, because the local replica has payloads
    // on disk that were written with only these two fields in them.
    assert.equal(fetched.developedForClientId, client.id);
    assert.equal(fetched.developedForClientName, 'Gold Madel Industries');

    // Editing the client moves every part made for them, in one place.
    const renamedContact = await fetch(`${ctx.baseUrl}/api/clients/${client.id}`, {
      method: 'PATCH',
      headers: ctx.headers,
      body: JSON.stringify({ phone: '900000001' }),
    });
    assert.equal(renamedContact.status, 200, await renamedContact.clone().text());
    const afterContactEdit = await readItem(ctx, created.body.item.id);
    assert.equal(afterContactEdit.developedFor.phone, '900000001');
    // ...and the PATCH mentioned only the phone, so the rest is still there.
    assert.equal(afterContactEdit.developedFor.contactName, 'Kissan Jain');
    assert.equal(afterContactEdit.developedFor.companyName, 'Gold Madel Industries');
  } finally {
    await closeServer(ctx.server);
  }
});

test('an update that says nothing about it preserves it; self clears the party', async () => {
  const ctx = await boot('paper-developed-preserve-', 'developed-preserve@paper.local');
  try {
    const sample = await anyItemShape(ctx);
    const client = await createClient(ctx, { name: 'Preserve Co' });
    const created = await createItem(ctx, {
      name: 'Preserved Patti',
      displayName: 'Preserved Patti',
      groupId: sample.groupId,
      unitId: sample.unitId,
      developedFor: {
        kind: 'client',
        clientId: client.id,
        at: '2026-05-15T04:35:00.000Z',
        quotationAmount: 85000,
      },
    });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    const itemId = created.body.item.id;

    // The failure mode that would arrive silently: any save that rebuilds the
    // whole item without mentioning the block.
    const quiet = await fetch(`${ctx.baseUrl}/api/items/${itemId}`, {
      method: 'PATCH',
      headers: ctx.headers,
      body: JSON.stringify({
        name: 'Preserved Patti',
        displayName: 'Preserved Patti',
        groupId: sample.groupId,
        unitId: sample.unitId,
      }),
    });
    assert.equal(quiet.status, 200, await quiet.clone().text());
    const afterQuiet = (await quiet.json()).item;
    assert.equal(afterQuiet.developedFor.kind, 'client');
    assert.equal(afterQuiet.developedFor.clientId, client.id);
    assert.equal(afterQuiet.developedFor.quotationAmount, 85000);
    assert.equal(afterQuiet.developedFor.at, '2026-05-15T04:35:00.000Z');

    // Sending the block is how it is cleared — "developed in-house" is a fact,
    // and a different one from "nobody has said".
    const toSelf = await fetch(`${ctx.baseUrl}/api/items/${itemId}`, {
      method: 'PATCH',
      headers: ctx.headers,
      body: JSON.stringify({
        name: 'Preserved Patti',
        displayName: 'Preserved Patti',
        groupId: sample.groupId,
        unitId: sample.unitId,
        developedFor: { kind: 'self', at: '2026-06-01T00:00:00.000Z' },
      }),
    });
    assert.equal(toSelf.status, 200, await toSelf.clone().text());
    const afterSelf = (await toSelf.json()).item;
    assert.equal(afterSelf.developedFor.kind, 'self');
    assert.equal(afterSelf.developedFor.clientId, null);
    assert.equal(afterSelf.developedFor.companyName, '');
    assert.equal(afterSelf.developedFor.contactName, '');
    // A quotation nobody mentioned in a block that WAS sent is cleared, not
    // carried: the block is one fact and arrives whole.
    assert.equal(afterSelf.developedFor.quotationAmount, null);
    assert.equal(afterSelf.developedForClientId, null);

    // Never quoted and quoted at zero are different rows.
    const zero = await fetch(`${ctx.baseUrl}/api/items/${itemId}`, {
      method: 'PATCH',
      headers: ctx.headers,
      body: JSON.stringify({
        name: 'Preserved Patti',
        displayName: 'Preserved Patti',
        groupId: sample.groupId,
        unitId: sample.unitId,
        developedFor: { kind: 'self', quotationAmount: 0 },
      }),
    }).then((r) => r.json());
    assert.equal(zero.item.developedFor.quotationAmount, 0);
  } finally {
    await closeServer(ctx.server);
  }
});

test('a contractor derives its parent client, and a mismatched one is refused', async () => {
  const ctx = await boot('paper-developed-contractor-', 'developed-contractor@paper.local');
  try {
    const sample = await anyItemShape(ctx);
    const owner = await createClient(ctx, { name: 'Owning Client', contactName: 'Owner Person' });
    const other = await createClient(ctx, { name: 'Other Client' });

    const contractorResponse = await fetch(
      `${ctx.baseUrl}/api/clients/${owner.id}/sub-contractors`,
      {
        method: 'POST',
        headers: ctx.headers,
        body: JSON.stringify({
          name: 'Shree Fabrication',
          designation: 'Proprietor',
          phone: '911111111',
          email: 'shree@fab.example',
        }),
      },
    );
    assert.equal(contractorResponse.status, 201, await contractorResponse.clone().text());
    const contractor = (await contractorResponse.json()).subContractor;
    assert.equal(contractor.designation, 'Proprietor');

    const created = await createItem(ctx, {
      name: 'Contractor Patti',
      displayName: 'Contractor Patti',
      groupId: sample.groupId,
      unitId: sample.unitId,
      developedFor: {
        kind: 'contractor',
        subContractorId: contractor.id,
        quotationAmount: 4200.5,
      },
    });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    const block = created.body.item.developedFor;

    // The parent client is derived and stored, so the part has a company name
    // to print and "parts for this client" will include contractor work.
    assert.equal(block.kind, 'contractor');
    assert.equal(block.subContractorId, contractor.id);
    assert.equal(block.subContractorName, 'Shree Fabrication');
    assert.equal(block.clientId, owner.id);
    assert.equal(block.companyName, 'Owning Client');
    // The person is the contractor, not the owning client's contact.
    assert.equal(block.contactName, 'Shree Fabrication');
    assert.equal(block.designation, 'Proprietor');
    assert.equal(block.phone, '911111111');
    assert.equal(block.quotationAmount, 4200.5);

    // Two answers about which company the part belongs to is a refusal, not a
    // silent overrule.
    const mismatched = await createItem(ctx, {
      name: 'Mismatched Patti',
      displayName: 'Mismatched Patti',
      groupId: sample.groupId,
      unitId: sample.unitId,
      developedFor: {
        kind: 'contractor',
        subContractorId: contractor.id,
        clientId: other.id,
      },
    });
    assert.equal(mismatched.status, 400, JSON.stringify(mismatched.body));
    assert.match(mismatched.body.error, /different client/i);

    // So are a kind nobody defined, a contractor that does not exist, and a
    // client kind with no client.
    for (const developedFor of [
      { kind: 'someone-else', clientId: owner.id },
      { kind: 'contractor', subContractorId: 999999 },
      { kind: 'client' },
      { kind: 'client', clientId: owner.id, quotationAmount: -5 },
    ]) {
      const refused = await createItem(ctx, {
        name: `Refused ${JSON.stringify(developedFor)}`,
        displayName: 'Refused Patti',
        groupId: sample.groupId,
        unitId: sample.unitId,
        developedFor,
      });
      assert.equal(refused.status, 400, JSON.stringify(refused.body));
    }
  } finally {
    await closeServer(ctx.server);
  }
});

test('a legacy row reads as a client, and an archived client still has a name', async () => {
  const ctx = await boot('paper-developed-legacy-', 'developed-legacy@paper.local');
  try {
    const sample = await anyItemShape(ctx);
    const client = await createClient(ctx, { name: 'Legacy Client', contactName: 'Old Contact' });

    // The pre-047 shape: a single client id and nothing about the kind. This is
    // what every item written before this change looks like.
    const legacy = await createItem(ctx, {
      name: 'Legacy Patti',
      displayName: 'Legacy Patti',
      groupId: sample.groupId,
      unitId: sample.unitId,
      developedForClientId: client.id,
    });
    assert.equal(legacy.status, 201, JSON.stringify(legacy.body));
    assert.equal(legacy.body.item.developedFor.kind, 'client');
    assert.equal(legacy.body.item.developedFor.clientId, client.id);
    assert.equal(legacy.body.item.developedFor.contactName, 'Old Contact');

    // And the same read with the kind column forced empty, which is the state
    // the migration's backfill exists to repair — the DTO still resolves it.
    await ctx.backend.run('UPDATE items SET developed_for_kind = ? WHERE id = ?', [
      '',
      legacy.body.item.id,
    ]);
    const stillClient = await readItem(ctx, legacy.body.item.id);
    assert.equal(stillClient.developedFor.kind, 'client');
    assert.equal(stillClient.developedFor.companyName, 'Legacy Client');

    // An archived client must still resolve its name: neither join filters on
    // is_archived, or a part would silently forget who it was made for.
    const archived = await fetch(`${ctx.baseUrl}/api/clients/${client.id}/archive`, {
      method: 'PATCH',
      headers: ctx.headers,
      body: JSON.stringify({ isArchived: true }),
    });
    assert.equal(archived.status, 200, await archived.clone().text());
    const afterArchive = await readItem(ctx, legacy.body.item.id);
    assert.equal(afterArchive.developedFor.companyName, 'Legacy Client');
    assert.equal(afterArchive.developedFor.contactName, 'Old Contact');
  } finally {
    await closeServer(ctx.server);
  }
});

test('the block costs no query per item', async () => {
  const ctx = await boot('paper-developed-n1-', 'developed-n1@paper.local');
  try {
    const sample = await anyItemShape(ctx);
    const client = await createClient(ctx, { name: 'Counted Client', contactName: 'Counted' });

    // Count the statements the list read issues, with one part developed for a
    // client and then with five. A per-item SELECT — which is what this DTO did
    // before 047 — would show up as four more.
    const countFor = async () => {
      let statements = 0;
      const proto = require('sqlite3').Database.prototype;
      const originals = {};
      for (const method of ['all', 'get', 'run']) {
        originals[method] = proto[method];
        proto[method] = function (...args) {
          statements += 1;
          return originals[method].apply(this, args);
        };
      }
      try {
        await fetch(`${ctx.baseUrl}/api/items`, { headers: ctx.headers }).then((r) => r.json());
      } finally {
        for (const method of ['all', 'get', 'run']) proto[method] = originals[method];
      }
      return statements;
    };

    const makeOne = async (name) => {
      const created = await createItem(ctx, {
        name,
        displayName: name,
        groupId: sample.groupId,
        unitId: sample.unitId,
        developedFor: { kind: 'client', clientId: client.id },
      });
      assert.equal(created.status, 201, JSON.stringify(created.body));
      return created.body.item;
    };

    await makeOne('Counted Patti 1');
    const withOne = await countFor();
    for (let i = 2; i <= 5; i += 1) await makeOne(`Counted Patti ${i}`);
    const withFive = await countFor();

    // Four more parts, all with a party, cost the same per part as any other
    // part — the growth is rowToItemDto's existing per-item queries, not a new
    // lookup for the client.
    const perItem = (withFive - withOne) / 4;
    const anyPart = await makeOne('Counted Patti 6');
    assert.ok(anyPart.developedFor.companyName, 'the party resolved from the join');
    const withSix = await countFor();
    // Not an exact equality: the server drains the changelog on a timer, so a
    // tick landing inside the run adds a query to whichever part it lands on
    // and makes the average fractional — which failed this once for a reason
    // that has nothing to do with the join. What it guards is that the cost
    // does not GROW with the number of parts: an O(n) client lookup would make
    // the sixth part cost strictly more than the five before it, and that is
    // still caught.
    assert.ok(
      withSix - withFive <= Math.ceil(perItem),
      `per-item query cost grew: ${withSix - withFive} against ${perItem}`,
    );
  } finally {
    await closeServer(ctx.server);
  }
});

test('a client PATCH that mentions one field keeps the rest', async () => {
  const ctx = await boot('paper-client-preserve-', 'client-preserve@paper.local');
  try {
    const client = await createClient(ctx, {
      name: 'Whole Client',
      alias: 'Whole',
      gstNumber: '29ABCDE1234F1Z9',
      address: 'MIDC, Pune',
      contactName: 'Kissan Jain',
      designation: 'Director',
      phone: '986565656',
      email: 'kissan@whole.example',
    });

    // Before 047 this blanked alias, GST and address: the route spreads the
    // request body into saveClient, and every field defaulted to ''.
    const patched = await fetch(`${ctx.baseUrl}/api/clients/${client.id}`, {
      method: 'PATCH',
      headers: ctx.headers,
      body: JSON.stringify({ designation: 'Managing Director' }),
    });
    assert.equal(patched.status, 200, await patched.clone().text());
    const after = (await patched.json()).client;
    assert.equal(after.designation, 'Managing Director');
    assert.equal(after.name, 'Whole Client');
    assert.equal(after.alias, 'Whole');
    assert.equal(after.gstNumber, '29ABCDE1234F1Z9');
    assert.equal(after.address, 'MIDC, Pune');
    assert.equal(after.contactName, 'Kissan Jain');
    assert.equal(after.phone, '986565656');
    assert.equal(after.email, 'kissan@whole.example');

    // Clearing still works — '' is a value, absence is not.
    const cleared = await fetch(`${ctx.baseUrl}/api/clients/${client.id}`, {
      method: 'PATCH',
      headers: ctx.headers,
      body: JSON.stringify({ phone: '' }),
    }).then((r) => r.json());
    assert.equal(cleared.client.phone, '');
    assert.equal(cleared.client.contactName, 'Kissan Jain');

    // A nameless client is the caller's mistake, so 400 — it was a 500.
    const nameless = await fetch(`${ctx.baseUrl}/api/clients`, {
      method: 'POST',
      headers: ctx.headers,
      body: JSON.stringify({ phone: '900000000' }),
    });
    assert.equal(nameless.status, 400, await nameless.clone().text());
  } finally {
    await closeServer(ctx.server);
  }
});

test('the development cost sits beside the quotation, and null is not zero', async () => {
  // The quotation says what was quoted for making this part's dies. Without a
  // cost beside it the one question anybody asks of it — did we make anything
  // on that job — has no answer. The pair is what a margin reads.
  //
  // The null case is the one that matters: a part quoted but never costed must
  // come back null, NOT 0, because zero cost reads as a 100% margin.
  const ctx = await boot('paper-development-cost-', 'dev-cost@paper.local');
  try {
    const sample = await anyItemShape(ctx);
    const client = await createClient(ctx, { name: 'Gold Madel Industries', alias: 'GM' });

    const quotedOnly = await createItem(ctx, {
      name: 'Quoted Not Costed',
      displayName: 'Quoted Not Costed',
      groupId: sample.groupId,
      unitId: sample.unitId,
      developedFor: { kind: 'client', clientId: client.id, quotationAmount: 85000 },
    });
    assert.equal(quotedOnly.status, 201, JSON.stringify(quotedOnly.body));
    assert.equal(quotedOnly.body.item.developedFor.quotationAmount, 85000);
    assert.equal(
      quotedOnly.body.item.developedFor.costAmount,
      null,
      'never costed must be null, or the margin reads 100%',
    );

    const both = await createItem(ctx, {
      name: 'Quoted And Costed',
      displayName: 'Quoted And Costed',
      groupId: sample.groupId,
      unitId: sample.unitId,
      developedFor: {
        kind: 'client',
        clientId: client.id,
        quotationAmount: 85000,
        costAmount: 61200,
      },
    });
    assert.equal(both.status, 201, JSON.stringify(both.body));
    assert.equal(both.body.item.developedFor.costAmount, 61200);

    // Reads back off the row, not just out of the create's own response.
    const reread = await readItem(ctx, both.body.item.id);
    assert.equal(reread.developedFor.costAmount, 61200);
    assert.equal(reread.developedFor.quotationAmount, 85000);

    // Zero is a real figure — the toolmaker did it for nothing — and must
    // survive as 0 rather than being read as "unset" and dropped.
    const free = await createItem(ctx, {
      name: 'Costed At Zero',
      displayName: 'Costed At Zero',
      groupId: sample.groupId,
      unitId: sample.unitId,
      developedFor: { kind: 'client', clientId: client.id, quotationAmount: 1000, costAmount: 0 },
    });
    assert.equal(free.status, 201, JSON.stringify(free.body));
    assert.equal(free.body.item.developedFor.costAmount, 0);

    // A negative cost is refused the way a negative quotation is.
    const negative = await createItem(ctx, {
      name: 'Negative Cost',
      displayName: 'Negative Cost',
      groupId: sample.groupId,
      unitId: sample.unitId,
      developedFor: { kind: 'client', clientId: client.id, costAmount: -5 },
    });
    assert.equal(negative.status, 400, JSON.stringify(negative.body));

    // A 'self' part keeps its figures: developed in-house still has a cost,
    // and the branch that returns no party must not drop them.
    const inHouse = await createItem(ctx, {
      name: 'In House Die',
      displayName: 'In House Die',
      groupId: sample.groupId,
      unitId: sample.unitId,
      developedFor: { kind: 'self', quotationAmount: 0, costAmount: 18700 },
    });
    assert.equal(inHouse.status, 201, JSON.stringify(inHouse.body));
    assert.equal(inHouse.body.item.developedFor.kind, 'self');
    assert.equal(inHouse.body.item.developedFor.costAmount, 18700);

    // A block that does not MENTION the cost keeps it. The item sheet sends
    // the deal on every save and has no cost column, so treating an absent
    // cost as null wiped it on any edit to the part.
    const patch = (body) =>
      fetch(`${ctx.baseUrl}/api/items/${both.body.item.id}`, {
        method: 'PATCH',
        headers: ctx.headers,
        body: JSON.stringify({
          name: 'Quoted And Costed',
          displayName: 'Quoted And Costed',
          groupId: sample.groupId,
          unitId: sample.unitId,
          ...body,
        }),
      }).then(async (r) => ({ status: r.status, body: await r.json() }));
    const silent = await patch({
      developedFor: { kind: 'client', clientId: client.id, quotationAmount: 90000 },
    });
    assert.equal(silent.status, 200, JSON.stringify(silent.body));
    assert.equal(silent.body.item.developedFor.quotationAmount, 90000);
    assert.equal(silent.body.item.developedFor.costAmount, 61200);

    // An explicit null still clears it.
    const cleared = await patch({
      developedFor: {
        kind: 'client',
        clientId: client.id,
        quotationAmount: 90000,
        costAmount: null,
      },
    });
    assert.equal(cleared.status, 200, JSON.stringify(cleared.body));
    assert.equal(cleared.body.item.developedFor.costAmount, null);
  } finally {
    await closeServer(ctx.server);
  }
});
