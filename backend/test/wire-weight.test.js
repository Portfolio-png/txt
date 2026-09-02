'use strict';

const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// What this app costs on a slow link.
//
// Measured against a copy of a real workspace, the cold start was 235 KB of
// uncompressed JSON — 1.9 seconds of pure transfer on a 1 Mbps line, against a
// server that assembles all of it in single-digit milliseconds. None of the
// pain was in SQLite; all of it was on the wire.
//
// These are regression tests for the fix, and they are worth having because
// every one of them passes silently on a fast dev link when it is broken. That
// is exactly how the problem arrived.

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
  });
  const { token } = await login.json();
  return {
    backend,
    server,
    baseUrl,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  };
}

test('responses are compressed', async (t) => {
  const ctx = await boot('paper-wire-gzip-', 'wire-gzip@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  // JSON is the most compressible payload there is — the same key names repeat
  // on every row — which is why this was worth 13.7x on a real workspace, far
  // above the ~3x that prose gets.
  const response = await fetch(`${ctx.baseUrl}/api/items`, {
    headers: { ...ctx.headers, 'Accept-Encoding': 'gzip' },
  });
  assert.equal(response.status, 200);
  assert.equal(
    response.headers.get('content-encoding'),
    'gzip',
    'without this the app ships every byte uncompressed and nobody notices on a fast link',
  );
});

/// A plain request, because `fetch` cannot be used to test conditional ones.
///
/// Node's fetch silently attaches `Cache-Control: no-cache` and `Pragma:
/// no-cache` whenever the caller sets `If-None-Match` — the Fetch spec turns a
/// manual conditional request into a forced revalidation. Express then quite
/// correctly refuses to answer 304, because the client just said it did not
/// want a cached answer. The server is right and `fetch` is the wrong
/// instrument; Dart's HttpClient, which is what the app actually uses, adds no
/// such header.
function rawGet(baseUrl, urlPath, headers) {
  const { port } = new URL(baseUrl);
  return new Promise((resolve, reject) => {
    const request = http.request(
      { host: '127.0.0.1', port, path: urlPath, method: 'GET', headers },
      (response) => {
        const chunks = [];
        response.on('data', (chunk) => chunks.push(chunk));
        response.on('end', () =>
          resolve({
            status: response.statusCode,
            headers: response.headers,
            body: Buffer.concat(chunks),
          }));
      },
    );
    request.on('error', reject);
    request.end();
  });
}

test('a client holding the current version is told nothing changed', async (t) => {
  const ctx = await boot('paper-wire-etag-', 'wire-etag@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const first = await rawGet(ctx.baseUrl, '/api/items', ctx.headers);
  const etag = first.headers.etag;
  assert.ok(etag, 'a validator is issued');
  assert.match(
    first.headers['cache-control'] || '',
    /must-revalidate/,
    'master data is revalidated rather than served blind from a cache',
  );

  const second = await rawGet(ctx.baseUrl, '/api/items', {
    ...ctx.headers,
    'If-None-Match': etag,
  });
  assert.equal(second.status, 304, 'unchanged data costs a header, not a payload');
  assert.equal(second.body.length, 0);

  // And a stale validator still gets the goods, or the whole thing would be a
  // very efficient way of serving nothing.
  const stale = await rawGet(ctx.baseUrl, '/api/items', {
    ...ctx.headers,
    'If-None-Match': 'W/"something-else"',
  });
  assert.equal(stale.status, 200);
  assert.ok(stale.body.length > 0);
});

test('the challan list ships aggregates, not every line of every challan', async (t) => {
  const ctx = await boot('paper-wire-cqrs-', 'wire-cqrs@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const stamp = new Date().toISOString();
  const item = await ctx.backend.get('SELECT id FROM items LIMIT 1');
  const challan = await ctx.backend.run(
    `INSERT INTO delivery_challans (challan_no, date, customer_name, type, status, maintain_stocks, created_at, updated_at)
     VALUES ('WIRE-DC-1', ?, 'Wire Client', 'delivery', 'draft', 0, ?, ?)`,
    [stamp, stamp, stamp],
  );
  for (const [line, pcs, weight] of [[1, 4, 0], [2, 0, 45.5]]) {
    await ctx.backend.run(
      `INSERT INTO delivery_challan_items (
         challan_id, line_no, particulars, quantity_pcs, weight, item_id,
         variation_leaf_node_id, variation_path_node_ids_json, sheet_weights_json,
         created_at, updated_at, factor_to_primary_at_creation
       ) VALUES (?, ?, 'Line', ?, ?, ?, 0, '[]', '[]', ?, ?, 1)`,
      [challan.lastID, line, pcs, weight, item.id, stamp, stamp],
    );
  }

  const list = await (await fetch(`${ctx.baseUrl}/api/challans`, { headers: ctx.headers })).json();
  const row = (list.data || []).find((entry) => entry.id === challan.lastID);
  assert.ok(row, 'the challan is in the list');

  // The 26% of a 130 KB response that was line items for challans nobody had
  // opened.
  assert.ok(
    !row.items || row.items.length === 0,
    'the list does not carry line items',
  );

  // But it still says enough for a list row to be useful, or stripping the
  // lines would just move the cost to N detail requests.
  assert.equal(row.lineCount, 2);
  assert.equal(
    row.itemsCount,
    2,
    'sent under the name the client already parses — it falls back to '
      + 'items.length otherwise, which is now 0',
  );
  assert.equal(Number(row.totalQty), 4);
  assert.equal(
    Number(row.totalWeight),
    45.5,
    'pieces and weight are summed separately: these lines are mixed, and one '
      + 'combined number would claim a weight was a piece count',
  );
});

test('the list drops fields no row renders, and the detail keeps them', async (t) => {
  // Found by diffing the response's keys against every `json['...']` the
  // Flutter model reads: a company profile snapshot and a reconciliation blob
  // were shipped per challan, a hundred times over, for rows nobody had opened.
  // 19% of the raw list payload that nothing could read.
  //
  // Dropped from the summary only. The editor, the printable document and the
  // report generator all go through the detail endpoint, which is unchanged.
  const ctx = await boot('paper-wire-trim-', 'wire-trim@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const stamp = new Date().toISOString();
  // created_by is an FK to users(id), not a name.
  const author = await ctx.backend.get('SELECT id FROM users LIMIT 1');
  const challan = await ctx.backend.run(
    `INSERT INTO delivery_challans (challan_no, date, customer_name, type, status,
                                    maintain_stocks, company_profile_snapshot,
                                    material_owner_client_name, created_by,
                                    created_at, updated_at)
     VALUES ('WIRE-TRIM-1', ?, 'Wire Client', 'delivery', 'draft', 0,
             '{"name":"Acme Works"}', 'Owner Ltd', ?, ?, ?)`,
    [stamp, author.id, stamp, stamp],
  );

  const dropped = [
    'company_profile_snapshot',
    'companyProfileSnapshot',
    'reconciliation_json',
    'reconciliationJson',
    'material_owner_client_id',
    'material_owner_client_name',
    'material_owner_gstin',
    'created_by',
    'updated_by',
  ];

  const list = await (await fetch(`${ctx.baseUrl}/api/challans`, { headers: ctx.headers })).json();
  const row = (list.data || []).find((entry) => entry.id === challan.lastID);
  assert.ok(row, 'the challan is listed');
  for (const field of dropped) {
    assert.ok(!(field in row), `the list should not carry ${field}`);
  }

  // What a row does render must survive the trim, or this would be a very
  // efficient way of showing nothing.
  assert.equal(row.challan_no, 'WIRE-TRIM-1');
  assert.equal(row.customer_name, 'Wire Client');
  assert.ok('purpose' in row, 'the list still says what kind of challan it is');
  assert.ok('status' in row);

  const detail = await (
    await fetch(`${ctx.baseUrl}/api/challans/${challan.lastID}`, { headers: ctx.headers })
  ).json();
  assert.deepEqual(
    detail.data.company_profile_snapshot,
    { name: 'Acme Works' },
    'the printable document still gets the letterhead it prints',
  );
  assert.equal(detail.data.material_owner_client_name, 'Owner Ltd');
  assert.equal(detail.data.created_by, author.id);
});

test('the detail endpoint still carries the lines', async (t) => {
  // The other half of the contract. Stripping the list is only safe because
  // opening a challan fetches it in full.
  const ctx = await boot('paper-wire-detail-', 'wire-detail@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const stamp = new Date().toISOString();
  const item = await ctx.backend.get('SELECT id FROM items LIMIT 1');
  const challan = await ctx.backend.run(
    `INSERT INTO delivery_challans (challan_no, date, customer_name, type, status, maintain_stocks, created_at, updated_at)
     VALUES ('WIRE-DC-2', ?, 'Wire Client', 'delivery', 'draft', 0, ?, ?)`,
    [stamp, stamp, stamp],
  );
  await ctx.backend.run(
    `INSERT INTO delivery_challan_items (
       challan_id, line_no, particulars, quantity_pcs, weight, item_id,
       variation_leaf_node_id, variation_path_node_ids_json, sheet_weights_json,
       created_at, updated_at, factor_to_primary_at_creation
     ) VALUES (?, 1, 'Steel sheet', 7, 0, ?, 0, '[]', '[]', ?, ?, 1)`,
    [challan.lastID, item.id, stamp, stamp],
  );

  const detail = await (
    await fetch(`${ctx.baseUrl}/api/challans/${challan.lastID}`, { headers: ctx.headers })
  ).json();
  assert.equal(detail.data.items.length, 1);
  assert.equal(detail.data.items[0].particulars, 'Steel sheet');
  // Aggregates agree whichever way they were computed — from the loaded lines
  // here, from SQL in the list.
  assert.equal(detail.data.lineCount, 1);
  assert.equal(Number(detail.data.totalQty), 7);
});

test('orders page and narrow on the server, and do neither unless asked', async (t) => {
  // Pagination is opt-in because several features legitimately need every
  // order resident — the production order picker, challan order-selection, a
  // client's history. A default page size would silently truncate them, which
  // is a correctness bug wearing a performance costume.
  const ctx = await boot('paper-wire-page-', 'wire-page@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const unpaged = await (
    await fetch(`${ctx.baseUrl}/api/orders`, { headers: ctx.headers })
  ).json();
  const everything = unpaged.orders.length;
  assert.ok(everything > 0, 'the seed has orders');
  assert.equal(unpaged.total, everything);
  assert.equal(unpaged.hasMore, false, 'an unpaged answer is everything, and says so');

  const paged = await (
    await fetch(`${ctx.baseUrl}/api/orders?limit=2`, { headers: ctx.headers })
  ).json();
  assert.equal(paged.orders.length, Math.min(2, everything));
  assert.equal(paged.total, everything, 'a page still says what it is a page of');
  assert.equal(paged.hasMore, everything > 2);

  // Offsets walk without repeating or skipping — the failure that shows up as a
  // row the user can never reach.
  const seen = new Set();
  for (let offset = 0; offset < everything; offset += 2) {
    const page = await (
      await fetch(`${ctx.baseUrl}/api/orders?limit=2&offset=${offset}`, {
        headers: ctx.headers,
      })
    ).json();
    for (const order of page.orders) seen.add(order.id);
  }
  assert.equal(seen.size, everything, 'every order appears exactly once across the pages');
});

test('the server search matches what the client used to do in memory', async (t) => {
  // Moving a filter from Dart to SQL is where a search regression comes from:
  // the symptom is a user who cannot find an order they know exists. These pin
  // the fields the in-memory filter covered, including the computed status and
  // the numeric quantity.
  const ctx = await boot('paper-wire-search-', 'wire-search@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const all = (
    await (await fetch(`${ctx.baseUrl}/api/orders`, { headers: ctx.headers })).json()
  ).orders;

  const normalize = (value) =>
    String(value ?? '').trim().replace(/\s+/g, ' ').toLowerCase();
  const inMemory = (term) => {
    const query = normalize(term);
    if (!query) return all;
    return all.filter(
      (order) =>
        normalize(order.orderNo).includes(query)
        || normalize(order.clientName).includes(query)
        || normalize(order.poNumber).includes(query)
        || normalize(order.clientCode).includes(query)
        || normalize(order.itemName).includes(query)
        || normalize(order.variationPathLabel).includes(query)
        || normalize(order.status).includes(query)
        || String(order.quantity).includes(query),
    );
  };

  const sample = all[0];
  for (const term of [
    sample.clientName,
    sample.itemName,
    sample.orderNo,
    String(sample.quantity),
    sample.status,
    'definitely-not-present-zzz',
  ]) {
    const served = await (
      await fetch(`${ctx.baseUrl}/api/orders?search=${encodeURIComponent(term)}`, {
        headers: ctx.headers,
      })
    ).json();
    assert.equal(
      served.total,
      inMemory(term).length,
      `search ${JSON.stringify(term)} must match the in-memory filter exactly`,
    );
  }
});

test('narrowing to a client returns that client and no other', async (t) => {
  // What the client screen and challan order-selection actually want, so they
  // can stop scanning a resident copy of every order in the workspace.
  const ctx = await boot('paper-wire-client-', 'wire-client@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const all = (
    await (await fetch(`${ctx.baseUrl}/api/orders`, { headers: ctx.headers })).json()
  ).orders;
  const clientId = all.map((order) => order.clientId).find((id) => Number(id) > 0);
  assert.ok(clientId, 'the seed has an order with a client');

  const narrowed = await (
    await fetch(`${ctx.baseUrl}/api/orders?client_id=${clientId}`, { headers: ctx.headers })
  ).json();
  assert.ok(narrowed.orders.length > 0);
  assert.ok(
    narrowed.orders.every((order) => Number(order.clientId) === Number(clientId)),
    'no other client leaks in',
  );
  assert.equal(
    narrowed.orders.length,
    all.filter((order) => Number(order.clientId) === Number(clientId)).length,
    'and none of that client\'s orders are missing',
  );
});

test('one row of free text in a JSON column does not empty the whole list', async (t) => {
  // Found by measuring: /api/dies was answering 95 bytes of
  //   {"success":false,"dies":[],"error":"Unexpected token 'P', \"Penta face\"..."}
  // on a real workspace, so the Dies screen showed nothing at all. The column
  // is declared JSON but holds text typed in before it meant anything stricter,
  // and a bare JSON.parse inside a list map takes every row down with it.
  const ctx = await boot('paper-wire-dies-', 'wire-dies@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const stamp = new Date().toISOString();
  await ctx.backend.run(
    `INSERT INTO dies (tool_code, produced_part_numbers, photo_urls, operational_notes,
                       compatible_machine_group_ids, status, ownership, created_at, updated_at)
     VALUES ('DIE-OK', '["A","B"]', '[]', '', '[]', 'active', 'owned', ?, ?)`,
    [stamp, stamp],
  );
  await ctx.backend.run(
    `INSERT INTO dies (tool_code, produced_part_numbers, photo_urls, operational_notes,
                       compatible_machine_group_ids, status, ownership, created_at, updated_at)
     VALUES ('DIE-TEXT', 'Penta faceplate pierce', '[]', '', '[]', 'active', 'owned', ?, ?)`,
    [stamp, stamp],
  );

  const response = await fetch(`${ctx.baseUrl}/api/dies`, { headers: ctx.headers });
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.equal(payload.success, true, JSON.stringify(payload.error || ''));

  const dies = payload.dies || payload.data || [];
  const ok = dies.find((die) => die.toolCode === 'DIE-OK');
  const text = dies.find((die) => die.toolCode === 'DIE-TEXT');

  assert.ok(ok, 'the well-formed row survives');
  assert.deepEqual(ok.producedPartNumbers, ['A', 'B']);

  assert.ok(text, 'and so does the one that was never valid JSON');
  assert.deepEqual(
    text.producedPartNumbers,
    ['Penta faceplate pierce'],
    'read as the one value it plainly is, rather than thrown away',
  );
});

test('a challan with no lines reports zero rather than failing', async (t) => {
  // The aggregate query ran against the wrong column names and threw, which in
  // the list path would have taken the whole response down.
  const ctx = await boot('paper-wire-empty-', 'wire-empty@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const stamp = new Date().toISOString();
  await ctx.backend.run(
    `INSERT INTO delivery_challans (challan_no, date, customer_name, type, status, maintain_stocks, created_at, updated_at)
     VALUES ('WIRE-DC-3', ?, 'Wire Client', 'delivery', 'draft', 0, ?, ?)`,
    [stamp, stamp, stamp],
  );

  const response = await fetch(`${ctx.baseUrl}/api/challans`, { headers: ctx.headers });
  assert.equal(response.status, 200, 'the list still answers');
  const row = ((await response.json()).data || []).find((e) => e.challan_no === 'WIRE-DC-3');
  assert.ok(row);
  assert.equal(row.lineCount, 0);
  assert.equal(Number(row.totalQty), 0);
  assert.equal(Number(row.totalWeight), 0);
});

test('a single order line can be fetched by id, matching its row in the list', async (t) => {
  // The delta engine knows only (table, record_id) when a change arrives, so it
  // must be able to fetch that one record. There was no route to do it with —
  // `getOrderRowById` had the right projection all along and was never routed,
  // so a change to an order line could not be applied to a replica at all.
  const ctx = await boot('paper-order-one-', 'order-one@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const list = await (await fetch(`${ctx.baseUrl}/api/orders`, { headers: ctx.headers })).json();
  const first = list.orders[0];
  assert.ok(first, 'the seed has an order line');

  const single = await fetch(`${ctx.baseUrl}/api/orders/${first.id}`, { headers: ctx.headers });
  assert.equal(single.status, 200);
  const body = await single.json();
  assert.equal(body.order.id, first.id);

  // The derived fields have to agree, or a replica updated from this endpoint
  // would drift from one updated by a list refresh. `status` is COALESCEd from
  // the pipeline runs assigned to the line, not read from order_items.status.
  assert.equal(body.order.status, first.status, 'the computed status matches the list');
  assert.deepEqual(
    body.order.totalDeliveredQty ?? body.order.total_delivered_qty ?? null,
    first.totalDeliveredQty ?? first.total_delivered_qty ?? null,
  );

  const missing = await fetch(`${ctx.baseUrl}/api/orders/99999999`, { headers: ctx.headers });
  assert.equal(missing.status, 404, 'an unknown id is a miss, not an empty success');

  // One path segment, so it must not have swallowed the /:id/... family.
  const nested = await fetch(`${ctx.baseUrl}/api/orders/${first.id}/activity`, {
    headers: ctx.headers,
  });
  assert.equal(nested.status, 200, 'the sub-routes registered around it still resolve');

  // Nor its named siblings. `/api/orders/fulfilment` is also one segment, and a
  // bare `:id` captured it and answered 404 — a wildcard registered before a
  // literal wins, and the literal is easy to miss among thirty routes. The
  // route matches numeric ids only so the outcome does not depend on which was
  // registered first.
  const named = await fetch(`${ctx.baseUrl}/api/orders/fulfilment`, {
    headers: ctx.headers,
  });
  assert.notEqual(
    named.status,
    404,
    '/api/orders/fulfilment must reach its own handler, not the id lookup',
  );
});

test('asking for ids that match nothing returns nothing, not everything', async (t) => {
  // The dangerous shape of this bug: a caller asking for one specific record
  // got the entire table. `?ids=ORD-2026-014` coerced to NaN, was filtered out,
  // and left an empty list indistinguishable from "no ids requested" — so the
  // clause was dropped and the query ran unfiltered.
  //
  // For a replica applying a delta that reads as "this record is now every
  // record". A 404 would have been safe; silently returning everything is not.
  const ctx = await boot('paper-ids-', 'ids@paper.test');
  t.after(async () => {
    await closeServer(ctx.server);
  });

  const all = await (await fetch(`${ctx.baseUrl}/api/orders`, { headers: ctx.headers })).json();
  assert.ok(all.orders.length > 1, 'there is more than one order to confuse it with');

  const ask = async (query) => {
    const response = await fetch(`${ctx.baseUrl}/api/orders${query}`, { headers: ctx.headers });
    return (await response.json()).orders;
  };

  assert.equal((await ask('?ids=ORD-2026-014')).length, 0, 'a text id matches nothing');
  assert.equal((await ask('?ids=not,a,number')).length, 0);
  assert.equal((await ask('?ids=0')).length, 0, 'zero is not an id');

  // And the distinction survives: not asking still means everything.
  assert.equal((await ask('')).length, all.orders.length);

  // A partly usable list uses the usable part rather than giving up.
  const real = all.orders[0].id;
  assert.deepEqual((await ask(`?ids=${real},nonsense`)).map((o) => o.id), [real]);
});
