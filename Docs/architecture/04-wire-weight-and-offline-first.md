# Wire weight: what the app actually costs on a slow link

Measured 2026-08-27 against a **copy of the live `paper.db`** (100 challans,
93 orders, real rows — not seed data), by booting the real server and hitting
the real endpoints. Numbers below are bytes on the wire, not estimates.

## The finding in one line

The server answers in **1–16 ms**. The wire costs **~2000 ms**. Nothing that
hurts is happening in SQLite; all of it is transfer.

That single fact decides the architecture: the fix is not a faster backend, and
not fewer features. It is to stop sending so much, so often, and to stop
re-sending what has not changed.

## What was measured

| Endpoint | raw | gzip | ratio | 1 Mbps (raw) |
|---|---|---|---|---|
| `/api/challans` | 130,234 B | 6,052 B | **21.5×** | 8.3 s |
| `/api/orders` | 60,947 B | 5,567 B | 10.9× | 3.9 s |
| `/api/items` | 30,035 B | 1,834 B | 16.3× | 1.9 s |
| `/api/materials` | 19,810 B | 1,802 B | 10.9× | 1.3 s |
| `/api/production/pipeline-templates` | 10,497 B | 1,967 B | 5.3× | 0.7 s |

**Cold start fires 13 list requests in parallel** (`main.dart:874-886`) on every
login, for every module, regardless of which screen is opened:

```
raw   234,740 B   →  1.8 s of transfer on 1 Mbps
gzip   17,044 B   →  0.14 s
                      13.7× smaller
```

Server-side time for all of it is single-digit milliseconds. The 130 KB challan
response is assembled in **16 ms**.

## The four problems, cheapest first

### 1. Nothing is compressed. At all.

`compression` is not a dependency and no middleware sets `Content-Encoding`.
JSON is the most compressible payload there is — the same forty-five key names
repeat on every row — which is why the ratios are 10–21×, far above the ~3× you
would get on prose.

This is one line of middleware for a **13.7× reduction on cold start**. It is
the highest value-per-effort change available anywhere in this codebase.

### 2. List endpoints send whole records

A challan row on the wire carries **45 fields**. A list view needs about ten.
Worse, every challan's **line items are nested inside the list response** —
26% of that 130 KB (34,390 B) is `items` for challans nobody has opened.

```
full list  130,197 B raw / 6,018 B gzip
slim list   21,010 B raw / 2,064 B gzip     ← 10 list-shaped fields
over-fetch     6.2×
```

Compression and slimming multiply: **130 KB → 2 KB, about 63×.**

### 3. No conditional requests

No `ETag`, no `If-None-Match`, no `Last-Modified` anywhere. A refetch of
unchanged data costs full price every time. Given the server assembles these
responses in milliseconds, computing a hash and answering `304 Not Modified` is
nearly free — and a 304 is a few hundred bytes instead of 130 KB.

### 4. Nothing survives a restart — including the sync cursor

`SocketService._lastEventId` starts at **0** on every launch and is never
persisted. No server data is cached to disk: `LocalInventoryRepository` exists
but is **wired to nothing**, and `SharedPreferences` is used only for settings.

So every launch re-downloads the entire workspace, having thrown away both the
data and the position that would have let it ask for only the difference.

## What is already right (and should not be rebuilt)

Worth stating plainly, because the shift below is smaller than it looks:

- **Surgical refetch already exists.** On an SSE change, `ItemsProvider` and
  `DeliveryChallanProvider` fetch *the one record* by id and splice it into the
  list, falling back to a full refresh only on failure. That is the correct
  pattern and it is already written.
- **A durable change-data-capture feed already exists.** `changelog` is an
  append-only table written by `logChange(table, id, action)`, and the SSE
  endpoint already serves cursor replay:

  ```sql
  -- GET /api/events?since=<id>
  SELECT id, table_name, record_id, event_type
  FROM changelog WHERE id > ? ORDER BY id ASC LIMIT 1000
  ```

- **The client already tracks the cursor** (`_lastEventId`) and already resumes
  from it *within* a session.

The replication protocol is built. What is missing is a durable local store to
apply it to, and one `setInt` to remember where it got to.

Not right yet: `InventoryProvider`, `VendorsProvider` and `GroupsProvider` still
do a full `refresh()` on every change event. For groups that is 1.1 KB and fine;
for inventory it is not.

## The shift, in tiers

Ordered by value per unit of risk. Each tier is independently shippable — none
of them requires the next.

### Tier 0 — compress (hours, no risk)

`app.use(compression())`. **13.7× on everything.** Verify with a response-header
assertion in the test suite so it cannot be silently lost.

### Tier 1 — list DTOs and pagination (days, low risk)

List endpoints return list-shaped rows; detail is fetched when a row is opened.
Stop nesting `items` in the challan list. **~6× further**, and it also fixes the
part that gets *worse* as the workspace grows — 100 challans today is 130 KB;
1,000 is 1.3 MB, which is 80 seconds on a 1 Mbps link.

Note this is the only tier that changes response shapes, so it needs the client
moved in step.

### Tier 2 — ETags (days, low risk)

Hash the response, honour `If-None-Match`. Cheap because the server is already
fast. Turns "reopen the app, nothing changed" from 235 KB into ~13 × 300 B.

### Tier 3 — a local read model (weeks, this is the actual shift)

**Stop treating the network as the source of truth for reads.**

A local SQLite mirror that the UI reads from. On launch the app reads from disk
and paints immediately — no spinner, no network — then asks
`/api/events?since=<persisted cursor>` for what changed and applies the deltas.

This is what makes the app "work its weight": on a 1 Mbps link, opening a screen
costs nothing, because the data is already local. Bandwidth is spent only on
change.

The two hard parts of this — an ordered durable change feed, and cursor replay —
**already exist and are tested**. What is needed:

1. persist `_lastEventId` (one line);
2. a local schema mirroring the read models;
3. an apply step per `table_name` (the SSE dispatch in `socket_service.dart` is
   already the right shape and already switches on table name);
4. a first-run full sync, which is what happens today anyway.

Precedent already in the repo: `OfflineSyncDbHelper` does exactly this for
production runs.

**The honest risk:** a local mirror is a cache, and cache invalidation is where
this class of change goes wrong. The mitigations are that the feed is
monotonic (so a gap is detectable), the cursor is a single integer (so "am I
behind?" is one comparison), and a corrupt or unknown state can always fall back
to a full resync — which is just today's behaviour.

### Tier 4 — queued writes (weeks, highest risk)

Writes go to a local outbox, apply optimistically, and drain when the link
allows. This is what makes the app usable on a *dropping* connection rather than
merely a slow one.

Highest risk, and it should be last: it needs conflict rules, and it is the only
tier where a bug can lose someone's work rather than merely show them stale
data. It also does not compose with everything — `barcode_ledger` is append-only
by trigger, and an optimistic custody event that later fails to land would be a
lie the ledger cannot retract. Custody writes should stay synchronous.

## What this does not fix

- **Round-trip latency.** These are transfer-size measurements. A remote link
  also pays RTT per request, and 13 parallel requests at cold start pay
  connection setup. Tier 3 fixes this properly, by not making the requests.
- **Rendering cost on weak hardware.** Separate problem, addressed separately by
  `AppPerformance.reducedEffects`.
- **The 21 MB binary.** Download size, paid once at install.

## Phase 1 — done (2026-08-27)

Tiers 0–2 are implemented and measured against the same live-data copy:

```
cold start, 13 requests, on the wire
  before   234,740 B    1.88 s on 1 Mbps
  after     15,783 B    0.12 s
            14.8x
```

- **Compression** is on globally (`app.use(compression())`).
- **`cacheMasterData`** sets `public, max-age=0, must-revalidate` on the
  high-volume read paths; Express's default weak ETag then answers **304 with a
  zero-length body** for unchanged data.
- **The challan list is a summary.** `items` is gone; `lineCount`, `itemsCount`,
  `totalQty` and `totalWeight` replace it. `/api/challans/:id` still carries the
  lines.
- **`variationTree` stays on `/api/items`**, deliberately — 48 read sites across
  12 files need it resident, so stripping it would convert one response into N
  round trips at picker-open time.

### Three things that had to be got right

**The aggregate SQL was wrong on both column names** — `delivery_challan_id`
and `quantity` do not exist; they are `challan_id` and `quantity_pcs`. It threw,
and since `rowToDeliveryChallanDto` is awaited inside the list map, it would
have taken the entire `/api/challans` response down rather than degrading.

**`getDeliveryChallanItems` returns raw rows, not DTOs.** Summing
`item.quantityPcs` off a `SELECT *` reads `undefined` and totals zero — which is
indistinguishable from a challan of weighed goods, and would have shipped
looking correct.

**Pieces and weight are summed separately.** These lines are mixed: some are
counted, some are weighed. One combined `totalQty` would have reported a 45 kg
line as 45 pieces.

### The client half, which the plan did not cover

Stripping `items` server-side breaks any screen that read them off a list row.
Four paths needed checking; two were already safe:

| path | before | now |
|---|---|---|
| editor | already hydrated via `loadChallan` | unchanged |
| print preview | already hydrated | unchanged |
| **detail pane** | read from the in-memory list | hydrates on focus |
| **duplicate** | skipped hydration — would have copied an empty challan | hydrates |

The list row's `_qtyLabel` also summed the lines, so it now falls back to the
aggregates — otherwise "Delivered 12 Pcs · 45 kg" would silently have become
"Delivered 3 items", which is exactly the regression the aggregates exist to
prevent.

### A testing trap worth remembering

**Node's `fetch` cannot test conditional requests.** Setting `If-None-Match`
makes undici attach `Cache-Control: no-cache` and `Pragma: no-cache`, and
Express then correctly declines to answer 304 — the client just said it did not
want a cached answer. curl returns 304 against the same server. The ETag test
uses a raw `http.request` instead; Dart's `HttpClient`, which the app actually
uses, adds no such header.

## Phase 2 — the client half of Tier 2 (2026-08-27)

Phase 1 made the server issue validators. **Nothing sent them back.** No Dart
code referenced `ETag` or `If-None-Match`, so the 304 machinery had no client
and never fired once: every launch still re-downloaded the whole workspace.

`ConditionalCacheClient` wraps the shared `AuthenticatedHttpClient` and closes
that loop. Measured against the same live-data copy, over ten endpoints:

```
first launch (cold cache)   18,300 B
relaunch     (warm cache)        0 B    10/10 answered 304
```

Design points that matter:

- **The server decides what may be cached.** Only responses carrying
  `must-revalidate` — the marker `cacheMasterData` puts on chosen endpoints —
  are stored. A volatile route is never cached, and that judgement lives in one
  place instead of as a path list on the client that drifts.
- **The client never decides its copy is current.** A validator is derived from
  the response the server built *for that request*, so a stale or foreign ETag
  simply fails to match and a full 200 comes back. A 304 is the server saying
  "what you hold is exactly what I would send you".
- **Persisted to disk**, because cold start is the measured pain and an
  in-memory cache is empty at exactly that moment.
- **Namespaced per user, not cleared on sign-out.** A launch begins with a
  sign-in, so clearing there would empty the cache at the moment it is worth
  having. Each user keeps their own warm copy and reads no one else's.
- **Degrades rather than fails**: no writable directory falls back to memory, an
  unreadable entry costs one refetch, and a failed write never fails the request
  that produced the data.

### A live bug the measuring turned up

`/api/dies` was answering 95 bytes of

```json
{"success":false,"dies":[],"error":"Unexpected token 'P', \"Penta face\"..."}
```

on the real database — **the Dies screen was showing nothing at all.**
`produced_part_numbers` is declared JSON but holds text typed in before the
column meant anything stricter (`Penta faceplate pierce`), and a bare
`JSON.parse` inside the list map took every row down with it. It now reads such
a value as the one value it plainly is: six dies come back. Pre-existing, and
invisible until something counted the bytes.

## Tier 1, finished — and why pagination is not part of it (2026-08-27)

**Field trimming.** Diffing the challan list response's keys against every
`json['...']` the Flutter model reads found **eight fields nothing could
read**, in either spelling — a company profile snapshot and a reconciliation
blob per challan, a hundred times over, for rows nobody had opened. 19% of the
raw payload. They are dropped from the summary only; the detail endpoint still
carries every one, so the editor, the printable document and the report
generator are untouched.

```
challan list   raw 102,039 -> 81,676 B     (-20%)
               wire  4,422 ->  4,075 B     (-8%)
```

The gap between those two numbers is the honest result: **gzip had already
absorbed most of the repetition.** Trimming a fifth of the raw bytes bought 8%
on the wire. Compression did the heavy lifting; field-level surgery is now
diminishing returns, and that is worth knowing before spending more effort on
shapes.

### Pagination: built, opt-in, and not yet adopted by the UI

`/api/orders` now takes `search`, `client_id`, `limit` and `offset`, and answers
with `total` and `hasMore` alongside the rows. **A request with no `limit` still
returns every order**, byte-for-byte as before, so nothing is truncated by a
caller that has not been moved.

```
(no params)              rows=93  total=93  hasMore=false
?limit=20                rows=20  total=93  hasMore=true
?limit=20&offset=80      rows=13  total=93  hasMore=false
?search=anchor           rows=54  total=54  hasMore=false
?search=anchor&limit=5   rows= 5  total=54  hasMore=true
```

`hasMore` is stated rather than inferred from a short page, because "this is
everything" and "this is all that fits" must not look the same to a caller.

**The search was ported field-for-field and checked against the original.** The
Flutter provider filtered in memory across eight fields; the SQL now does the
same, and the two were compared on real data across seven queries — including
the computed `status`, the numeric `quantity`, and a multi-word term:

```
"anchor" 54/54   "socket" 26/26   "completed" 67/67
"10"     93/93   "SW-"     0/0    "zzz"        0/0    "Anchor Roma" 54/54
```

That comparison is the point of the exercise: moving a filter from Dart to SQL
is exactly where a search regression comes from, and the symptom is a user who
cannot find an order they know exists.

### The consumers, migrated

The earlier claim that "43 sites read `OrdersProvider`" was misleading — that
counted every use of the provider, most for other methods. The actual
**list-reading surface is 8 sites in 4 files**, and each wanted a narrow slice
rather than everything:

| consumer | wanted | state |
|---|---|---|
| production order picker | orders still worth putting on a machine | **migrated** — `?status=inProgress,notStarted,draft`, 21 rows of 93 |
| client purchases sheet | one client's history | **migrated** — `?client_id=`, 9 rows of 93 |
| challan order-selection (2 sites) | one client's open lines | still reads the full list |
| orders screen (3 sites) | the list itself | still reads the full list |

**The saving is not banked yet.** `OrdersProvider.initialize()` still calls
`refresh()`, which loads every order, because the two unmigrated consumers
depend on it. So the migrated screens now issue their own small queries *on top
of* a full load that still happens — a few hundred bytes more, not less.

Bytes only drop when the last consumer stops needing the resident list and
`initialize()` can load a page. Half a migration is worse than none; this one is
worth finishing or reverting, not leaving.

`status` and `ids` filters were added for these, and the WHERE-building is shared
between the page and its count so the two cannot drift — a count that disagrees
with its own page is how "load more" loops forever or hides rows.

### The one real cost, stated plainly

Searching a resident list is **instant**; searching server-side is a round trip
per query. On a 1 Mbps link that is the interaction users perform most, made
slower.

That is the whole trade, and it is worth taking only because the alternative
scales the wrong way: 93 orders resident is 5.9 KB, but 5,000 is ~320 KB — on
every launch, parsed and held in memory on an i3. A page stays ~3.6 KB whatever
the workspace grows to, and a search costs one small request that the response
cache will answer 304 for when repeated.

Debouncing the search field is what makes it acceptable in practice; without it
typing "anchor" issues six requests.

### What is left

The **orders screen itself** still loads the full list and filters in memory.
That is the last consumer, and the only one where the round-trip cost is felt,
so it is the one worth deciding deliberately rather than by momentum.

Everything it needs is in place: `limit`/`offset`/`search` on the server,
`total` and `hasMore` in the response, and the parameters plumbed through the
repository and provider.

For reference, the consumers that still want the whole set:

| list | who needs all of it |
|---|---|
| orders | production order picker, client screen, challan order-selection — 43 sites read `OrdersProvider` |
| challans | Excel export view, client report generator |

Paginating the shared provider today would silently truncate an export, a picker
and a report — a correctness bug wearing a performance costume. The narrowing
those features want (`?client_id=`) now exists, so they can move one at a time.

Today's numbers do not force the issue: 93 orders is 5.9 KB on the wire, a page
of 50 is 3.6 KB, and a relaunch is ~0 bytes. At a few thousand orders the full
list is ~320 KB and a page is still ~3.6 KB. **The trigger to adopt paging is
the orders payload growing, not the calendar.**

### Superseded: the earlier note that pagination was not a drop-in

Both lists are treated as **app-wide working sets**, not as screens:

| list | who needs all of it |
|---|---|
| orders | the production order picker, the client screen, challan order-selection — 43 sites read `OrdersProvider` |
| challans | the Excel export view, the client report generator |

Paginating the shared provider would silently truncate an export, a picker and a
report. That is a correctness regression, not a performance trade — the same
reasoning that kept `variationTree` on `/api/items`, applied to rows instead of
fields.

Orders is the sharper case: its search is **client-side over the full list**
(`filteredOrders`, eight fields), and `/api/orders` accepts no filters at all.
Paginating it without first moving search server-side would make search cover
only the first page.

So pagination needs its consumers moved first, and the honest place for that is
**Tier 3**: a local mirror is what those features actually want — the whole set
resident, cheaply and correctly — rather than a page of it.

Today's numbers do not force the issue: 93 orders is 5.9 KB on the wire, and a
relaunch is ~0 bytes. At a few thousand orders it will, and the trigger to
revisit is the orders payload rather than the calendar.

## Suggested order

Tiers 0–2 are done and measured at **14.8× on cold start**. Measure on a real
1 Mbps link before committing to Tier 3: the remaining win there is latency and
restart cost, not bytes, and 15.8 KB may simply be fast enough.
