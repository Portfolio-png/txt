# Tier 3 readiness: audit before building

Audited 2026-08-29 against the live schema and `backend/server.js`.

The Tier 3 plan is right in shape. Its foundation is not there yet, and the gap
is precisely the failure the brief names: *lag because a row or column never got
appended.*

## The finding

Tier 3 replays `GET /api/events?since=<cursor>`, which serves the `changelog`
table. **A table that never calls `logChange` can never sync a delta.** So the
changelog's coverage is the hard ceiling on what a local replica can keep
truthful.

Counting mutation statements against `logChange` calls:

| table | INSERT | UPDATE | DELETE | logged |
|---|---:|---:|---:|---:|
| materials | 12 | 17 | 2 | **0** |
| delivery_challans | 4 | 8 | 2 | 4 |
| pipeline_templates | 6 | 5 | 2 | **0** |
| order_items | 2 | 9 | 1 | **0** |
| delivery_challan_items | 5 | 2 | 4 | **0** |
| units | 6 | 5 | 0 | **0** |
| groups | 6 | 4 | 0 | ~1 |
| pipeline_runs | 3 | 5 | 2 | **0** |
| items | 3 | 6 | 0 | 4 |
| item_variation_nodes | 3 | 5 | 1 | **0** |
| machines | 5 | 2 | 2 | **0** |
| dies | 5 | 2 | 2 | **0** |
| clients | 2 | 5 | 0 | 2 |
| invoice_headers | 1 | 3 | 2 | **0** |
| inventory_stock_positions | 3 | 1 | 2 | **0** |
| vendors | 2 | 2 | 1 | 2 |
| departments | 1 | 1 | 0 | **0** |

**≈174 mutation sites. ≈13 logged. About 7%.**

Built on this as it stands, a local replica would be confidently wrong. Editing
an item's variation tree touches `item_variation_nodes` — never logged — so every
picker in the app would keep rendering the old tree until someone reinstalled.
Materials have **31 mutation sites and zero logging**.

That is worse than today's behaviour, because today a stale read is impossible:
the network is asked every time.

### Three smaller defects found alongside

1. **Three `logChange` calls name a table that does not exist.** They log
   `'material'`; the table is `materials`. Those events reach the client and
   match nothing.
2. **The client maps only 5 of the 7 logged names** — `clients`, `vendors`,
   `items`, `groups`, `delivery_challans`. Events for `material` and
   `item_master_data` are received and dropped.
3. **The plan's `local_order_headers` mirrors the wrong grain.** `/api/orders`
   selects `FROM order_items` — the app's order list is *lines*, with a status
   computed per line from its pipeline runs. A local `order_headers` table would
   replicate something the UI never reads.

## What this changes about the plan

Steps 1 and 3–5 of the plan (local SQLite, delta engine, local repositories,
provider integration) are all correct and all downstream of one prerequisite:

> **Every write must record that it happened.**

The wrong way to close it is to add `logChange` to 174 call sites. It would be
wrong within a month — the next feature adds a write and forgets the line, and
the symptom is not a crash but one screen quietly serving last week's data.

### Do it in the database, not in the application

`changelog` rows should be written by **SQLite triggers**, one set per replicated
table:

```sql
CREATE TRIGGER changelog_materials_insert AFTER INSERT ON materials
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('materials', NEW.rowid, 'INSERT', datetime('now'));
END;
```

Why this and not application code:

- **It cannot be forgotten.** Coverage stops depending on whether whoever wrote
  the endpoint remembered. That is the property Tier 3 actually needs, and no
  amount of care at 174 call sites provides it.
- **It covers writes the application does not make** — migrations, backfills,
  scenario seeders, a maintenance script, `sqlite3` on the box.
- **It is transactional.** The log entry commits or rolls back with the row it
  describes, so the changelog cannot claim a change that was rolled back — which
  application-level logging on an error path does.
- **There is precedent here already**: `barcode_ledger` uses triggers to enforce
  append-only, for the same reason — a rule the code cannot bypass.

Cost: a write does two inserts instead of one. Given the server currently answers
in 1–16 ms, that is not the constraint.

Two things to decide when doing it:

- **Seeding floods it.** A reseed would write thousands of rows. Either accept it
  (the cursor just advances) or suppress triggers around bulk seeds, the way
  `clearAllData` already drops and recreates the ledger triggers.
- **Retention.** The table grows forever. It needs a prune older than the oldest
  live cursor, or a client that has been closed for a month falls back to a full
  snapshot — which the plan already provides for.

## Recommended order

1. **Changelog triggers for every replicated table**, plus a test asserting that
   each table's INSERT/UPDATE/DELETE produces exactly one changelog row. This is
   the whole prerequisite, and it is verifiable independently of any client work.
2. Fix the three defects above (`'material'` → `'materials'`, client mapping,
   order grain).
3. Then Steps 1–5 of the Tier 3 plan as written.

Doing 3 before 1 produces a fast app that is sometimes wrong, and the wrongness
is invisible from inside the app. That is a worse product than a slow one.


---

# Phase 1 & 2: built (2026-08-29)

## Phase 1 — the changelog now records everything

`migrations/040-changelog-triggers.sql`: **51 triggers over 17 tables.**
Coverage goes from ~7% of mutation sites to every write, including writes the
application never makes. The test issues raw SQL with no route and no
`logChange` in the path and asserts the row is still logged — that property is
the whole reason for choosing triggers.

**The live push had to be rebuilt to suit.** Triggers write the changelog but
cannot notify Node, and `logChange` was doing both. The stream now *tails* the
changelog (`drainChangelog`), so a change made by a migration, a backfill or
`sqlite3` on the box reaches a connected client — which was never true before.

Three things the work turned up:

- **Triggers cannot see logical changes.** Filing items into a combination group
  writes a link table, so no `items` row changes and no trigger fires — but
  those items are stale for anyone rendering the group. That needs an explicit
  `logChange(..., { force: true })`. Triggers record *row* changes; only a
  caller knows about *logical* ones.
- **A factory reset would have flooded every connected client.** Seeding writes
  through the triggers, so a reseeded workspace left thousands of undelivered
  rows and the next drain would push all of them. The cursor now resyncs past
  the seed.
- **The four dead calls are fixed.** `logChange('material', …, 'create')` named
  a table that does not exist *and* an event type the CHECK rejects; it had been
  failing and being swallowed on every call since it was written.

Retention: `CHANGELOG_RETENTION` prunes at boot, never above the push cursor, so
a row cannot be deleted between being written and being delivered.

## Phase 2 — the client can hold a replica and remember its place

`local_database_helper.dart` builds `paper_local.db` — 15 tables, namespaced per
user so one person's workspace is never served to the next on a shared machine.
Separate files rather than a discriminator column: a forgotten
`WHERE user_id = ?` leaks silently, a separate file cannot.

Every table keeps `raw_payload_json` beside its extracted columns. The extracted
ones filter and sort in SQL; the payload lets a row be handed to the same
`fromJson` the network path uses. Without it, every new field the server learned
to send would need a migration here first, and the replica would quietly serve a
subset of the truth.

Orders are stored as **`local_order_items`**, matching `/api/orders`, which
selects `FROM order_items`. The original plan's `local_order_headers` would have
mirrored a table the app never reads.

`sync_metadata_store.dart` persists the cursor. It never moves backwards —
events can arrive out of order across a reconnect, and a cursor that went
backwards would replay applied changes and mask a genuine gap.

**The dispatcher was dropping twelve of seventeen tables.** A machine renamed, a
unit added, a pipeline template edited, an order line's status moving: all
arrived and were discarded, because only five tables had a branch. That is the
same disease as the changelog gap, living on the client. It now emits a generic
`table-change` for every table — so a delta engine can replicate one without
anyone adding a case — while keeping the named events existing providers already
listen for, so the migration is non-breaking.

## What is not done

Phase 3: the delta engine that applies these events to the replica, the local
repositories, and pointing the providers at them. The foundations under it are
now real and tested; nothing in Phase 3 has to take anything on trust.


---

# Phase 3, part 1: the derived-field gap (2026-08-29)

Migration 040 made the changelog record every **row** change. That turned out to
be necessary and still not sufficient.

## The item DTO is an aggregate over eight tables

`rowToItemDto` (server.js:2726-2846) reads from the variation tree, unit
conversions, group memberships, attachments, machine links, die links, a client
name and a pipeline name. **Seven of those tables had no triggers at all.** A
replica storing the item payload would have gone stale on any of them, and the
item row itself would never have changed to say so.

The same shape elsewhere:

| what the UI shows | on | actually derived from |
|---|---|---|
| `status` | an order line | `pipeline_runs` via `order_pipeline_assignments` |
| `total_delivered_qty` | an order line | `delivery_challan_items` |
| `variationTree` | an item | `item_variation_nodes` (nested at server.js:2814) |
| `lineCount` / `totalQty` / `totalWeight` | a challan | `delivery_challan_items` |

## Migration 041: announce the row a change is *visible* on

**31 triggers**, in SQL for the same reason as 040 — a comment asking the next
person to remember an extra `logChange` would not survive. Child rows announce
their parent, and the indirect case does the join inside the trigger:

```sql
CREATE TRIGGER trg_derived_pipeline_runs_order_items_au AFTER UPDATE ON pipeline_runs
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  SELECT 'order_items', opa.order_item_id, 'UPDATE', datetime('now')
  FROM order_pipeline_assignments opa WHERE opa.pipeline_run_id = NEW.id;
END;
```

This also **simplified** Phase 1: the forced `logChange('items', …, {force: true})`
added for group membership is now redundant, because the trigger on
`group_item_memberships` announces the item — and covers a membership written by
a migration or a script, which the application call never would.

**Repeats are not a defect.** Filing three items into a group announces the group
three times: row-level triggers cannot see that three inserts are one user
action. A change-data-capture consumer folds by `(table, record_id)` before
acting. Two tests were asserting exact counts written before 041 existed and now
assert the folded set.

## Three live bugs found while mapping

1. **Orders had no single-record endpoint.** `getOrderRowById` had the correct
   projection — including the derived `status` — and was never routed, so a
   change to an order line could not be applied to a replica at all. Added
   `GET /api/orders/:id`.

2. **That new route swallowed `/api/orders/fulfilment`.** Both are one segment,
   and a wildcard registered before a literal wins. It now matches numeric ids
   only, so the outcome does not depend on registration order.

3. **`?ids=` returned everything when it matched nothing.** A non-numeric id
   coerced to `NaN`, was filtered out, and left a list indistinguishable from
   "no ids requested" — so the clause was dropped and the query ran unfiltered.
   A caller asking for one record got the whole table; for a replica that reads
   as "this record is now every record". Now an impossible condition.

## Fetch-by-id map (from the audit fan-out)

Nine of seventeen tables have a clean by-id GET. Four need a fallback. Four are
mismatched in ways a naive engine would not notice:

- **materials** — the trigger writes `NEW.id`, the endpoint is keyed by
  `barcode`. The replica must reverse-look-up id → barcode, and fall back to a
  full refetch on an INSERT it has never seen.
- **order_headers** — keyed by `order_no` TEXT, no endpoint, no local mirror.
  The engine must ignore it; the order *lines* carry everything the app reads.
- **delivery_challan_items** — the trigger key is a LINE id, not a challan id.
  Migration 041 already announces the parent challan, so the engine should apply
  that and ignore the line event.
- **inventory_stock_positions** — no endpoint emits this id at all.

That map is the input to the delta engine, which is next.


## What the fan-out settled (and two things it stopped)

### The data-loss vector: do NOT rebuild the item tree locally

`updateItem` sends the **whole variation tree as a destructive replace** —
`UpdateItemRequest.fromInput`, `item_api_models.dart:690`. Any node missing from
the tree the client sends is **deleted server-side**.

So a local item repository must serve the *verbatim* payload, never a tree
reassembled from `local_item_variation_nodes`. A lossy rebuild would not be a
display bug; it would silently delete a customer's variations on the next save.
`local_item_variation_nodes` is for lookup and cascade only — never for
reconstructing what gets sent back.

Reinforcing it: `ItemDto` and `ItemVariationNodeDto` have **`fromJson` only** —
no `toJson`. A parsed DTO cannot be serialized back to payload shape, so the raw
map must be captured off the HTTP body *before* parsing. That is what
`raw_payload_json` is for, and there is no shortcut around it.

### Cold start, measured per module

221,862 B raw across 13 provider loads. Items, challans and orders are 77.8% of
it. Of the remaining ten:

- **Materials (19.8 KB) is the only one worth a local repository** — and it is
  the worst offender on the live path: `InventoryProvider` subscribes
  `inventory_updated`, `challan_updated` *and* `challan_generated_ok` to a full
  `refresh()`, which re-issues **four** requests. Every challan write anywhere
  in the workspace costs every connected client ~20 KB.
- **Units, groups, clients, vendors, machines, dies, departments** — 16.4 KB raw
  / 3.9 KB gzip combined. Not worth a local repository for bandwidth, but worth
  one for latency, and they are the cheapest proving ground for the delta engine:
  flat rows, no nested trees, tables already exist.
- **Jobs and action-center cannot be replicated at all.** No triggers on
  `freelancer_jobs*` or on whatever backs `/api/trash`. They must stay on the
  network, and that has to be stated rather than left to look like an oversight.

### A second replica already exists, unwired

`LocalInventoryRepository` opens its own database at
`getApplicationDocumentsDirectory()/paper_inventory.db` — not
`LocalDatabaseHelper`'s file, and not namespaced per user. It is wired to
nothing today. **Two replicas with different lifetimes is worse than one**, so
it should be deleted or folded into `LocalDatabaseHelper` before anyone wires
it; leaving it is an invitation.

### Migration 042: cancelling a challan

`total_delivered_qty` sums only over challans that are **not cancelled**, so
cancelling one changes every order line it touched while writing no
`delivery_challan_items` and no `order_items` row. 041 announced the order line
when a challan *line* changed; it had nothing to say when the challan's own
status moved. The user-visible symptom is "delivered 300 of 500" that never
gives the 300 back.

### Ordering the replica must reproduce

- items: `ORDER BY is_archived ASC, LOWER(name) ASC` — **archived items are
  returned**, not filtered. The provider then re-sorts, and does so
  *differently* on the refresh path (isArchived, groupId, name, displayName)
  than on the socket path (`_sortItems` drops the isArchived leg) — so a
  live-updated list is already ordered differently from a freshly-refreshed one,
  today, before any replica exists.
- orders: `ORDER BY datetime(created_at) DESC, id DESC` — the id is the
  tiebreaker and omitting it reorders same-second rows.
- challans: `ORDER BY date(dc.date) DESC, dc.id DESC`.


---

# Phase 3, part 2: the delta engine (2026-08-29)

`packages/core_erp/lib/core/sync/replica_bindings.dart` and
`delta_sync_engine.dart`, with 15 tests.

## The fetch map is data, not branches

Turning `(table, record_id)` into "which local row, fetched how" is where a
naive engine corrupts the replica, so all seventeen decisions sit in
`kReplicaBindings` with the reasoning attached to each. A wrong entry is then a
visible line rather than a buried condition.

| strategy | tables | why |
|---|---|---|
| `fetchById` | items, delivery_challans, order_items, clients, vendors, machines, dies, pipeline_templates, pipeline_runs | a by-id GET exists and returns the same shape as a list element |
| `fetchByBarcode` | materials | announced by `NEW.id`, served by `/api/materials/:barcode` |
| `viaParent` | item_variation_nodes | no endpoint; the tree is nested in the item |
| `refetchList` | groups, units, departments | no by-id endpoint, and the whole list is 1–4 KB |
| `ignore` | delivery_challan_items, order_headers, inventory_stock_positions | the announced key cannot address the record |

The `ignore` entries are the ones that matter. `delivery_challan_items`
announces a **line** id; handing it to `/api/challans/:id` would fetch a
*different challan* and write it over the right one. Migration 041 announces the
parent challan separately, so nothing is lost by skipping it.

## Two properties the tests exist for

**It folds.** A CDC feed announces rows, not user actions: filing three items
into a group announces the group three times, and one request can announce a row
from its own trigger and its parent's. A DELETE folded with an earlier UPDATE
wins, because fetching a row deleted later in the same batch only 404s.

**The cursor never advances past work that failed.** `apply()` returns the
highest changelog id *fully applied*; a failed fetch blocks the position behind
it so the next sync retries. A cursor that moved on regardless would turn a
transient network error into permanent staleness — the failure this whole design
exists to prevent. Two tests cover it, including the dangerous ordering where a
later change succeeds after an earlier one failed.

## Extractors verified against real payloads

Every extracted column was checked against what the server actually sends, by
booting it and reading the responses rather than by reading the DTO builders:

- items, orders, materials — camelCase throughout, matching.
- challans — **snake_case** (`challan_no`, `customer_name`, `created_at`) with
  the aggregates in camelCase (`lineCount`, `totalQty`, `totalWeight`). The
  extractors read both spellings, so both resolve.
- `materials.kind` is not sent at all; it stores `''`, which is the column
  default. Harmless, and correct if the server later starts sending it.

The payload itself is stored **verbatim** and never reconstructed from the
extracted columns — the read DTOs have no `toJson`, and `updateItem` sends the
whole variation tree as a destructive replace, so a rebuilt payload sent back
would delete whatever the rebuild missed.

## Adversarial review: eight bugs, three that corrupt

The engine went through a four-dimension review (cursor arithmetic, wrong-row
writes, ordering and atomicity, payload extraction), each finding then handed to
a refuter told to default to "refuted" when uncertain. **16 raised, 5 survived.**
Three more were found alongside and fixed. All eight:

**`ConflictAlgorithm.replace` wiped every challan line.** It compiles to
`INSERT OR REPLACE`, which *deletes the existing row first* — firing the
`ON DELETE CASCADE` on `local_delivery_challan_items`. Any update to a challan
silently emptied its lines, so the replica would show every challan as having
none the moment anything about it changed. Replaced with a real
`INSERT … ON CONFLICT DO UPDATE`. Verified by reintroducing the bug: the test
fails with `Actual: []`.

**A blanket "DELETE wins" in the fold lost recreated rows.** `pipeline_templates`
and `pipeline_runs` are keyed by caller-supplied TEXT, and the same key
legitimately dies and comes back — `seedTemplatesIfEmpty` re-inserts
`sheet-metal-flow` under its fixed id, `ensurePipelineRunRecord` does the same
for `demo-dolly-run-active`. A DELETE(40)+INSERT(41) pair folded to DELETE and
advanced the cursor past the re-creation: the row exists on the server, is absent
locally, and nothing will ever say so again. Now the last action *by position*
wins.

**`viaParent` could never fire.** It resolves a variation node to its item
through `local_item_variation_nodes`, and nothing populated that table. Storing
an item now mirrors its nested tree into it — for lookup only; the item's own
payload stays the authority, because a tree rebuilt from parts and sent back
through `updateItem` would delete whatever the rebuild missed.

**Three extractors read keys the server never sends.** Clients and vendors read
`gstin` where the API sends `gstNumber`; dies read a `name` the die DTO has never
had (identity is `toolCode`); materials read a `kind` it does not emit. Each
stored an empty string on every row, nothing threw, and any list sorting or
filtering on those columns would have sorted on nothing. The schema now names
the columns after what the server actually sends.

**A live event could freeze the cursor.** SSE events carry `changelogId` 0;
treating a failure on one as a barrier set the block to 0 and froze the position
for the whole batch, so every later change went uncredited and replayed forever.

**An unknown table wedged the cursor.** The one skip that did not credit the
position — so a batch entirely of tables this build has no binding for would
replay on every reconnect, over a window that grows. It is credited now: this
build can never apply it, and `unknownTables` surfaces it.

# Phase 3, part 3: the sync service and the first local repository

## `ReplicaSyncService`

Owns the loop: open this user's replica, remember where the replay got to, ask
only for what changed since, and announce which local tables moved.

It deliberately does **not** serve reads — repositories do that, straight off the
replica. Keeping them apart is what stops a screen ever waiting on a sync: it
paints from whatever is on disk, and the service quietly makes that better.

- **First run has no cursor to replay from**, so it pulls the lists once. That
  is the one launch a replica costs a full download, and the reason every launch
  after it costs almost nothing. Hydration goes through the same engine writer
  as a steady-state refetch, so the two cannot drift — two paths would, and the
  second would be the one nobody tests.
- **Live events are batched** over 250 ms before applying, because one user
  action announces several rows.
- **Offline is not an error.** A failed catch-up leaves the replica stale and
  usable, which is the entire point of having it.
- **`resync()`** throws the copy away and starts again, for a cursor pointing at
  pruned history or a schema this build no longer understands. Always available,
  because the server can rebuild it.

## `LocalFirstItemRepository`

A **decorator**, not a replacement. Of the 23 methods on `ItemRepository`, three
can be answered from a mirror of the list endpoint; the rest are writes, signed
URLs, asset uploads and usage reports only the server can do. Wrapping means
those keep working untouched and the local path is a strict addition — removable
by deleting one line of wiring.

Three things it gets right that a naive version would not:

- **The payload comes back verbatim**, parsed by the same `fromJson` the network
  path uses. Reassembling an item from the extracted columns and saving it would
  delete every variation the reconstruction missed, because `updateItem` is a
  destructive tree replace.
- **Archived items are returned**, ordered `is_archived ASC, LOWER(name) ASC` to
  match the server exactly. `getItemsWithUsage` has no WHERE clause; a local
  `WHERE is_archived = 0` would silently drop rows the app renders.
- **An empty or unsynced replica asks the network** rather than reporting a
  workspace with nothing in it. The cursor, not the row count, is what says the
  copy can be trusted — rows without a completed sync could be a partial
  hydration.

`noSuchMethod` was removed from it on purpose: with it, an unimplemented method
compiles and throws at runtime. Every method is now delegated explicitly, so the
interface growing breaks the build instead of a screen.

## Wired (2026-09-02)

Tier 3 is now *used*, not merely built — the distinction this codebase has been
bitten by before (`LocalInventoryRepository` and multi-up label printing both sat
finished and unreachable).

- **`GET /api/changes?since=&limit=`** — the endpoint a replica calls at launch.
  The SSE stream replays too, but a client catching up wants a request that
  *ends*, not a connection it must decide when to stop reading. It returns
  `hasMore` for paging and, more importantly, **`oldestAvailable`**: the
  changelog is pruned, so a client closed long enough holds a cursor pointing at
  history that no longer exists. Replaying from the oldest surviving row would
  silently skip everything in between; stating the floor lets the client notice
  and take a fresh snapshot instead.
- **`ReplicaApi`** owns the endpoint map, because it is not derivable —
  `order_items` is served by `/api/orders`, `delivery_challans` by
  `/api/challans`, and the pipeline routes have no `/api` prefix at all. Tables
  with no by-id route are *absent* from `recordPaths` rather than guessed at;
  inventing `/api/groups/:id` would 404 on every delta.
- **Envelope unwrapping is tested**, because getting it wrong does not throw. It
  returns an empty list, the replica hydrates with nothing, and the app looks
  like a workspace with no data in it. `success` is the first key in every
  response and would otherwise be mistaken for the record.
- **`main.dart`** opens the replica for the signed-in user, feeds `table-change`
  into it, and wraps only the item repository. Failure is survivable by design:
  the local-first repository checks `isHydrated` before trusting the replica, so
  a replica that never opened means the app behaves exactly as it did before —
  slower, and working. Demo mode skips it entirely; there is no server behind
  the canned responses to replicate from.

## Verified against the real backend (2026-09-02)

`tool/run_live_replica_test.sh` boots the actual server on a **copy** of
`backend/paper.db`, logs in, and drives the whole replica pipeline from Dart.
Every other test here uses a fake server, which proves the engine's logic and
nothing about whether the endpoints exist, the envelopes match, or the field
names are what the extractors expect — and those mistakes do not throw. They
hydrate an empty replica, and the app looks like a workspace with no data.

```
LIVE hydrated: local_items: 17, local_delivery_challans: 100,
  local_order_items: 93, local_materials: 22, local_groups: 5, local_units: 9,
  local_departments: 5, local_clients: 6, local_vendors: 6, local_machines: 8,
  local_dies: 6, local_pipeline_templates: 4, local_pipeline_runs: 72
  (empty: [])
```

**All thirteen replicable tables filled with real rows, none empty.** Every path
resolves, every envelope unwraps, every extractor's keys match, every by-id
fetch works, and the catch-up endpoint advances the cursor. The script picks a
free port rather than a fixed one — a collision with a server left over from an
interrupted run fails as `EADDRINUSE`, which looks nothing like the thing being
tested.

## Orders, and the line where local stops

`LocalFirstOrderRepository` answers **only the unfiltered list** from the
replica, ordered `datetime(created_at) DESC, id DESC` — the id leg matters,
because a bulk import creates rows within the same second and dropping it
reorders them.

Everything narrowed goes to the server. Its search runs across eight columns in
SQL, and reimplementing that locally would mean two filters obliged to agree
exactly; the way they would disagree is a user searching for an order that
exists and being told it does not. It is also cheap to delegate: `?client_id=`
returns nine rows where the list returns ninety-three.

The shared part is now `ReplicaReader` — query in the server's order, rehydrate
through the server's own `fromJson`, and return null rather than an empty list
when the replica cannot answer, so a caller can tell "nothing here" from "ask
the network".

## Materials, and an API gap the replica exposed

`LocalFirstInventoryRepository` serves the materials list and barcode lookups
from the replica. This is the most valuable decorator on the live path, and not
because of its size: `InventoryProvider` subscribes `inventory_updated`,
`challan_updated` *and* `challan_generated_ok` to a full `refresh()` which
re-issues four requests, so **every challan write anywhere in the workspace has
been costing every connected client about 20 KB**. The materials list is the
largest of those four.

Building it turned up something the replica was uniquely placed to notice:

> `/api/materials` orders by `kind ASC, created_at DESC, barcode ASC`, and the
> DTO did not include `kind`. **The endpoint was sorting by a column it never
> exposed**, so no client could reproduce the order it was handed.

Invisible while the server was the only thing doing the sorting. It becomes a
visible defect the moment anything else holds the rows — the local list would
have come back in a different order for no reason a user could explain.
`rowToMaterialDto` now emits it, and the replica stores `kind` and `created_at`
to sort by.

A barcode miss falls through to the server rather than returning null: a replica
that has not caught up is not evidence of absence, and a scanned barcode the app
calls unknown is the worst answer it could give.

Stock, sets and health stay on the network — they have no local tables, and no
endpoint even emits an `inventory_stock_positions` id for a delta to address.

## Challans, and where local stops again

`LocalFirstChallanRepository` serves the **plain list only**, ordered
`date(challan_date) DESC, id DESC` — the id leg matters because challans
routinely share a date.

Two limits, both of which would have failed silently:

- **The replica holds the summary shape.** `/api/challans` no longer sends the
  nested `items` array; it sends `lineCount`, `totalQty` and `totalWeight`.
  Answering `getChallan(id)` from the replica would hand the editor and the
  printable document a challan with **no lines** — the exact regression that
  detail-hydration fixed on the client side. Detail always goes to the server.
- **Several filters cannot be answered from a mirror.** `mineOnly` resolves
  server-side to `dc.created_by = req.user.id`, and filtering by item or
  variation is a line-level EXISTS over `delivery_challan_items` — rows the
  replica does not hold at all.

Its 43 delegating members were generated from the interface rather than typed,
after a first attempt silently dropped parameters from five of them
(`templatePreviewUri` lost its `challanId`, and so on). It compiled either way:
the arguments were named, so the wrong call was still valid Dart. A check that
every method declaring parameters passes them through is what caught it, and
regenerating with a correct parser was the right move over patching each by
regex.

## The provider change, measured and dropped

The plan was to point `InventoryProvider` at the replica's `changedTables`
stream instead of refreshing wholesale on every challan event. Measured against
the live workspace, the three requests that would remove total **913 bytes**:

```
/api/inventory/stock     27 B
/api/inventory/sets     709 B
/api/inventory/health   177 B
(materials, now local) 1848 B
```

The decorator had already removed the largest of the four. Under a kilobyte does
not justify threading a change stream into a provider, so it is not done —
deliberately, rather than forgotten.

## Not done

Nothing outstanding in Tier 3 worth doing on current numbers. Tier 4 (queued
offline writes) remains explicitly out of scope: `barcode_ledger` is append-only
by trigger, so an optimistic custody event that later failed to land would be a
lie it cannot retract. The pattern is proven under the hardest constraints — items is the
one with the destructive-update hazard, the nested tree and the exact ordering
requirement — so the rest is repetition.
