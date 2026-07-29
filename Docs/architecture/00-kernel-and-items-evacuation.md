# Kernel + Items Evacuation — Work Breakdown

> Status: IN PROGRESS. Drafted 2026-07-27; work items 1–2 delivered same day:
> `backend/kernel/registry.js` (all seven maps consolidated, server.js consumes
> it, behavior-identical) and `backend/kernel/territory.js` +
> `GET /api/kernel/territory` (admin-gated burn-down meter). First meter run:
> 261 routes — 163 module-claimed / 67 kernel / **31 unclaimed** (payroll 9,
> freelancer-jobs 5 — real gating holes: those routes bypass module CRUD;
> also search, portal, mobile, production-scrap, company-profile,
> freelancer-portal). Tables: 93 — 72 claimed / 21 kernel / 0 unclaimed.
> Test suite: 7 failures, all verified pre-existing at HEAD (stale
> expectations); consolidation added zero. Bonus fix: fresh-DB bootstrap was
> missing migrations 023/025 columns (`input_type`, `name_join`) — cured a
> 21-test sweep.
>
> Work item 3 delivered same day: `backend/kernel/contracts.js` (contract
> engine), `backend/modules/items/contract.js` (itemWrite/groupWrite/
> variationNode declared from current behavior — negative node ids flagged),
> LOG-ONLY `guardContract()` on POST/PATCH items+groups, `guardAlert()` filing
> into entity_activity_log as entity_type `kernel_guard`, and admin-gated
> `GET /api/kernel/guard-alerts`. Unit tests in
> `backend/test/kernel-contracts.test.js` (4 passing); end-to-end verified:
> bad payload → 201 + alert with route/actor/problems.
>
> Work item 4 delivered same day: all 18 items/groups routes moved VERBATIM
> into `backend/modules/items/routes.js` (registered via
> `registerItemsModuleRoutes(ctx)`; only mechanical transform: late-bound
> socket `io` becomes `ctx.getIo()`). Egress DTO shapes declared in
> `contract.js` (`itemEgress`/`groupEgress`). Integration coverage in
> `backend/test/items-module.test.js` exercises every moved route plus the
> guard-alert feed. server.js now contains zero /api/items or /api/groups
> routes. Domain logic (saveItem/saveGroup/DTOs/usage queries) still lives in
> legacy and flows in via ctx — it evacuates next (service.js + ports, work
> item 5), shrinking ctx toward kernel facilities only.
>
> Work item 5 (first tranche) delivered same day: `modules/items/ports.js` —
> the K5 boundary is live. Port surface: describe, resolveSelection,
> selectionSnapshot, stock.assertLeaf, **stock.applyDelta (now the single
> cross-module write path into variation_stock)**, bom.lines. 14 external
> call-sites switched to `itemsPorts.*`: challan issue/cancel (assert + delta
> + unit lookup via describe), inventory movements (4 deltas), orders
> (resolveSelection), challan save + materials bridge + production
> (selectionSnapshot ×4), production + freelancer-jobs (bom.lines). Only
> items-internal calls remain on the bare helpers — the boundary is greppable
> (`itemsPorts.`) and metered: per-port call counts surface in
> `/api/kernel/territory` under `modules.items.runtime.portCalls`.
> Implementations still live in legacy and evacuate behind the boundary next
> (service move), consumers untouched. Remaining tranche for item 5/6: the
> read-only `JOIN items` sites (describe rollout), reconciliation's raw
> INSERTs (H2), delete-requests raw DELETEs (H1), name-based production
> matching (H3), then enforcement flip + constraints migration.
>
> Companion to the architecture discussion: the monolith dissolves into module
> packages behind a thin kernel; expansion/collapse and fleet replication are
> reconciler operations over git-versioned client manifests.

## 0. What the survey found (facts, not plans)

The vision does not start from zero. Every layer already has an embryo in this repo:

| Vision layer | Existing embryo | Where |
|---|---|---|
| Module registry | `feature_registry.json` (`modules.orders`, `modules.inventory`, …) served to the sandbox dashboard | `backend/feature_registry.json`, `server.js` `/api/sandbox-dashboard/feature-registry` |
| Per-client desired state | `sandbox_client_configs` (JSON per `client_id`, `default` fallback) + activation machinery | `server.js` ~5022, ~25216 |
| Fleet control plane | **Falcon View** — vendor-side telemetry ingest + fleet dashboard, deployment keys, opt-in emitter | `control-plane/` |
| Verification harness | 13 integration test files that boot the real `server.js` against a temp DB and drive real business flows | `backend/test/*.test.js` (`npm test`) |
| Migration machinery | Numbered SQL chain 001–025 + `migrate.js` | `backend/migrations/` |
| Frontend module seeds | Feature folders in `packages/core_erp/lib/features/*`, `apps/challan_mobile` | Flutter workspace |

Territory to govern:

- `backend/server.js`: **27,561 lines**, ~200 route registrations across ~45 path prefixes, ~93 tables.
- Items territory (first evacuation): `items`, `groups`, `group_item_memberships`,
  `item_variation_nodes`, `item_variations`, `item_variation_values`,
  `item_variation_dimensions`, `variation_stock`, `item_property_schema`,
  `item_unit_conversions`, `item_bom_lines`, plus the variation/leaf/stock helper family.

Two bugs this week were both **cross-border failures** and motivate the design:
1. Asset-upload 403 — three overlapping permission regimes with unclear jurisdiction.
2. Negative variation-leaf id — challans code reading items' tree internals directly
   and persisting a synthetic id that items never issued.

## 1. The kernel (skeleton first, never a rewrite)

New directory `backend/kernel/`, mounted **inside the existing process** — the app
keeps running throughout. The kernel owns process concerns; the legacy code becomes
a tenant, not the host.

```
backend/
  kernel/
    index.js          // boot: load modules, mount legacy, start reconciler
    registry.js       // module manifests (the seven scattered maps consolidated)
    borders.js        // auth chain + central permission gate + ingress/egress engine
    ports.js          // inter-module call bus (sync queries between modules)
    events.js         // event bus (module facts: challan.issued, item.created…)
    reconcile.js      // desired-state vs actual-state; plan/apply
    migrate.js        // per-module migration chains (wraps existing migrations/)
    territory.js      // burn-down metering: routes/tables still unclaimed by manifests
  modules/
    items/            // first evacuated module (see §3)
  legacy/
    server.legacy.js  // what remains of server.js, shrinking to zero
```

Kernel rules (constitution, enforced from day one):

- **K1 — Inversion**: kernel owns the Express app, DB connection, auth middlewares,
  and boot order. Legacy mounts under it with zero special privileges.
- **K2 — Freeze**: no new feature lands in `legacy/` ever again. New capability ⇒ new
  module (or addition to an evacuated one).
- **K3 — Metering**: `territory.js` computes, on boot and on demand: routes and tables
  claimed by manifests vs total. Exposed at `/api/kernel/territory` and pushed as
  telemetry to Falcon View. Unclaimed territory is a visible warning, not a norm.
- **K4 — One question, one border**: identity → auth; module rights → central gate
  reading the registry; payload shape → the target module's ingress contract;
  impossibility → DB constraints. No route-local permission logic, ever.
- **K5 — Module-to-module = ports + events only.** Direct cross-module SQL is a
  violation `territory.js` counts (detected by table-access mapping, §3).

## 2. Contracts (what a module declares)

Each module ships one manifest; everything else derives from it:

```
modules/items/
  manifest.js         // identity: name, version, pathPrefixes, permission keys,
                      // record sources, track labels, owned tables
  contract.js         // entity schemas: fields, types, invariants, visibility
                      // → derives ingress validation, egress DTO projection,
                      //   DDL CHECK/FK constraints, and a JSON contract doc
  ports.js            // the services items exposes to other modules (§3)
  events.js           // facts items announces (item.created, variation.archived…)
  migrations/         // module-owned chain (seeded from relevant 0xx files)
  routes.js           // route handlers (moved verbatim from server.js, then cleaned)
  service.js          // domain logic
  seeds.js            // default data the reconciler applies on expansion
  items.test.js       // contract tests — the evacuation's safety net
```

Contract versioning: every client request carries/receives the contract version;
borders answer version mismatches explicitly (old mobile builds get a clear
"update required" instead of a deep mystery failure).

## 3. Items evacuation — the proving ground

Items is first because it is the richest dependency: nearly every other module
consumes it, so evacuating it forces the ports/events design to be real.

### 3.1 Ports (from the coupling survey)

The survey found **30 coupling sites** where non-items code reaches into items
territory, spread across challans, orders, inventory/materials, production, jobs,
reconciliation, favorites, search, reports, portal, action-center, and the
delete-requests dispatcher — plus seed/migration utilities. They reduce to this
port surface:

**The two highest-leverage ports** (each replaces 10+ sites):

| Port | What it is | Consumers |
|---|---|---|
| `items.describe(itemId)` | name, displayName, unit id+symbol, group, namingFormat, shortCode, archived | challans, production, scrap, reconcile, vendors, portal, inventory, materials, sets, search, assets — every ad-hoc `JOIN items` dies here |
| `items.stock.applyDelta(...)` **W** | the **single write path** into `variation_stock` | challan issue, challan cancel, inventory movements |

**The rest of the surface:**

| Port | Replaces | Consumers |
|---|---|---|
| `items.resolveSelection` / `items.getSelectionSnapshot` | `resolveOrderVariationSelection`, `getItemSelectionSnapshot` | orders, challans, production, materials |
| `items.stock.assertLeaf` | `assertValidStockVariationLeaf` | challan issue/cancel, inventory-set validation |
| `items.stock.query` | direct `variation_stock`+`items` joins | inventory stock route, search |
| `items.variation.tree/.activeProperties/.findLeaf/.firstOrderableLeaf` | `getItemVariationTree` + friends, raw `item_variation_nodes` reads | materials, inventory sets, search |
| `items.pathLabel` | `buildVariationPathLabel` | inventory sets, orders |
| `items.bom.lines` | raw `item_bom_lines` reads | freelancer jobs, production node-status |
| `items.lookupByName` | fragile `LOWER(name)=?` matching | production node-status/metrics (**smell — see H3**) |
| `items.groups.ensure` / `items.ensureForReconcile` **W** | raw INSERTs into `groups`/`items` | reconciliation |
| `items.favorites.*` **W** | raw `user_favorite_items` CRUD | favorites routes, clear-data |
| `items.delete` **W** | raw `DELETE FROM items/groups` | delete-requests dispatcher |
| `items.integrity.scan` | FK-integrity scans over items/groups | action-center |
| items↔materials bridge (`ensureMaterialForItemSelection` family) | — | spans two modules; ownership decided during inventory evacuation |

### 3.1b Hazards found (ranked — these justify the whole exercise)

- **H1 — Delete-requests dispatcher raw-DELETEs `items` and `groups`** with **no
  cascade handling** for `item_variation_nodes`, `variation_stock`,
  `group_item_memberships` → orphaned references (very likely the source of
  Action Center "broken reference" issues).
- **H2 — Reconciliation raw-INSERTs `items` and `groups`**
  (`ensureReconcile{PrimaryGroup,SubGroup,Item}`), bypassing `saveItem`/`saveGroup`
  entirely: no property schema, no variation nodes, no dedup.
- **H3 — Production resolves items by name** (`LOWER(name)=?`) with an
  **"any item" fallback** when no match — silent misattribution of finished-goods
  lots, jobs, and material links.
- **H4 — `variation_stock` has three external writers** (challan issue, cancel,
  inventory movements). Helper-mediated today, but it is the shared stock write
  surface; becomes `items.stock.applyDelta` exclusively.
- H5 — Favorites and seed/demo utilities write items tables directly (lower risk;
  fold into ports/seeds during evacuation).

### 3.1c Frontend coupling (for the items Flutter package boundary)

Non-items consumption concentrates on **three exported surfaces**, consumed by
orders, inventory, search, delivery-challans, reports, and the entire
challan_mobile app:

1. `ItemDefinition` (domain model)
2. `items_provider.dart` / `favorites_provider.dart` (state)
3. `NamingFormatHelper` + `VariationPathSelectorDialog` /
   `ExactItemVariationSelectField` (shared selection widgets — the transitive
   bridge most non-items screens actually use)

The items Flutter package's public API is exactly these three surfaces; everything
else becomes package-private during the frontend half of the evacuation.

### 3.2 Steps

1. **Map & fence** — the coupling map (above) becomes assertions: every non-items
   access to items tables is catalogued; `territory.js` counts them as violations
   with a burn-down number.
2. **Contract first** — write `contract.js` for items/groups/variation-nodes/stock
   from the current schema *as-is* (including warts). Generated ingress/egress goes
   live behind the existing routes with **log-only** mode: mismatches are reported
   (guard alerts into `entity_activity_log`), nothing rejected yet.
3. **Move routes verbatim** — items/groups route handlers move to
   `modules/items/routes.js` unchanged; tests must stay green. No logic edits in the
   same commit as moves (reviewability rule).
4. **Stand up ports** — implement the port list; consumers (challans, orders,
   inventory, production) switch from direct SQL/helpers to ports one call-site at a
   time. Each switch is a small, testable diff. The negative-leaf bug class dies here:
   only items can mint leaf references, and its port refuses to return synthetic ids.
5. **Enforce** — ingress flips from log-only to reject; DDL constraints migration
   lands (CHECK non-negative refs, FKs on challan-item references); K5 violations for
   items territory reach zero; items' migration chain becomes module-owned.
6. **Declare** — items' manifest claims its routes and tables; territory meter shows
   the first claimed region.

### 3.3 Definition of done

- `npm test` green throughout; new `items.test.js` covers every port and contract.
- Zero direct SQL into items tables from outside `modules/items/`.
- `variation_leaf_node_id`-class data can no longer be persisted invalid (constraint
  + ingress both refuse).
- Territory meter: items routes/tables 100% claimed.

## 4. After items (order of the front)

1. **Challans** — first heavy port consumer; event bus earns its keep
   (`challan.issued` → inventory reacts via subscription instead of inline code).
2. **Inventory/materials** — shares stock jurisdiction with items; resolves the
   "who owns variation_stock" question explicitly (items owns the ledger; inventory
   consumes via port).
3. **Orders, production, people, vendors/clients/units/machines/dies** — in
   dependency order; small masters can move in parallel once the pattern is proven
   (disjoint territory + own tests ⇒ parallel evacuation is safe).
4. **Auth/permissions stays kernel** — it is not a module; it is the border system.

## 5. Reconciler: plan/apply (grows alongside, not after)

- **v0 (with kernel skeleton)**: reads manifests + `sandbox_client_configs`,
  reports drift (modules enabled vs routes mounted vs migrations applied). Read-only.
- **v1 (after items)**: `plan` — human-readable diff of what enabling/disabling a
  module for this deployment would do (tables created, keys added, seeds applied,
  routes opened/closed). `apply` — converge, transactionally per module.
- **v2 (fleet)**: client manifests move to a git repo; deployments converge on
  commit; Falcon View shows fleet-wide drift, guard alerts, canary rollout state.
  Collapse is always *border-first, data-retained*; a collapsed border logs knocks
  (the "need of the hour" sensor).

## 6. Session-sized work items

| # | Work item | Depends on |
|---|---|---|
| 1 | Kernel skeleton: `kernel/index.js` boots, wraps existing app, `registry.js` consolidates the seven maps, tests green | — |
| 2 | `territory.js` + `/api/kernel/territory` + Falcon View telemetry field | 1 |
| 3 | Items `contract.js` + log-only ingress/egress + guard alerts | 1 |
| 4 | Items route move (verbatim) + `items.test.js` port/contract coverage | 3 |
| 5 | Ports live; challans/orders/inventory call-sites switched (several small PRs) | 4 |
| 6 | Enforcement flip + constraints migration + manifest claim | 5 |
| 7 | Reconciler v0 (drift report) | 2 |
| 8 | Challans evacuation begins | 5 |

Rules of engagement while any of this is in flight: K2 freeze active; every PR keeps
`npm test` green; moves and edits never share a commit.
