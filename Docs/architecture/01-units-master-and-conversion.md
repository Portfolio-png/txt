# Units Master — Families, Conversion Engine & App-wide Autonomy

> Status: PLANNED. Drafted 2026-07-29. Sequel to
> `00-kernel-and-items-evacuation.md`; the `units` module manifest already
> exists in `backend/kernel/registry.js:140-148` with `evacuated:false`, so this
> work doubles as the **second module evacuation** after items.
>
> Product decisions locked with the requester (2026-07-29):
> 1. **Included-units grain = per-family + per-usage-context** (inventory /
>    production / sales), stored company-wide in `sandbox_client_configs`.
> 2. **Gauge = a first-class, table-backed unit** in the Length family (not just
>    a variation input). The SWG table moves server-side and becomes the single
>    authoritative source for both the Length family and the existing gauge
>    variation input.
> 3. **"Global symbol" view = an interactive converter widget** in the Units
>    master, backed by one canonical symbol per unit reused identically
>    everywhere in the app.
>
> Reviewed 2026-07-29 (requester) — four refinements folded in:
> (1) `item_unit_conversions` stays **cross-dimension-capable** — no intra-family
> constraint (§1.2, §7, §10); (2) pickers must **union the entity's current
> unit(s)** into the included list (§1.3, §5); (3) `convert()` handles **suffixed
> gauge variation strings** via a companion parser (§3, §6); (4) config-sync is a
> **real test**, not a note (§4, §9).

---

## 0. What the survey found (facts, not plans)

A 7-slice recon (backend schema, backend API, Dart units feature, dropdown
consumers, gauge/SWG, kernel pattern, settings/precision) plus firsthand reads
established the following. Every claim below is cited.

### 0.1 Families are hollow

| Thing | Reality today | Where |
|---|---|---|
| `unit_groups` table | `(id, name, created_at, updated_at)` — **no `base_unit_id`, no dimension/type** | `server.js:3535-3541` |
| Family "base unit" | Only **implicit** = the grouped unit whose `conversion_base_unit_id IS NULL` | `server.js:15903` |
| Canonical Length/Mass/Quantity families | Defined in `unitSystem_grouping.json` but that file is a **dead artifact** — referenced by no code, never seeded | `unitSystem_grouping.json`; grep = 0 hits |
| Family key | Inconsistent: some surfaces key on `unitGroupId` (int), inventory filter + units screen on `unitGroupName` (string) | `inventory_screen.dart:9564`, `units_screen.dart:304` |

### 0.2 Conversions are linear-only; gauge lives outside the system

- A unit stores exactly one linear multiplier: `conversion_factor REAL DEFAULT 1`
  + a self-FK `conversion_base_unit_id` → a **flat one-hop star** to the family
  base, never a chain, never non-linear (`server.js:3544-3558`,
  `resolveUnitConversion` `server.js:15886-15917`).
- **Gauge/SWG** is a hardcoded 40-row Dart const
  (`swg_gauge_table.dart`), used as a third variation *input type*
  (Text→Numeric→Gauge) via the shared `_GaugeStepField`
  (`variation_path_selector_dialog.dart:1190-1483`). Captured values are
  verbatim suffixed strings (`"0.711mm"`, `"22G"`) stored as custom variation
  values; **no unit metadata travels with them**.
- The gauge→thickness schedule is non-uniform (1→2 drops 0.024 in; 27→28 drops
  0.0016 in) → **a table lookup is mandatory; no single factor exists**. Within
  the table mm↔inch *are* linear (×25.4). (`swg_gauge_table.dart:16-55`.)
- There is **no pound** in the Mass family; seeds are ad-hoc mocks all with
  `unit_group_id NULL` (`server.js:6696-6730`).

### 0.3 Dropdowns have zero family / inclusion awareness

- **11 picker surfaces** all draw from the flat `UnitsProvider.activeUnits`
  (all non-archived units): orders (item-scoped), delivery challans, items
  (primary+secondary), inventory (×3: create-group, add-stock sheet, unit-group
  filter), masters group editor, dies, machines, and **two** production
  Quick-Create dialogs. Verified by enumeration (`activeUnits` in 11 files).
- The family-scoped helper `compatibleActiveUnitsForGroupUnitId(groupUnitId)`
  **exists but is dead code** — no dropdown calls it
  (`units_provider.dart:113`).
- **No "included" flag** exists on a unit — only `is_archived`
  (`unit_definition.dart:18`). The special `"Primary Unit"` placeholder
  (`name=='Primary Unit'`, `symbol=='-'`) is treated as universally compatible
  and hard-coded into orders/items warnings — must stay special-cased.

### 0.4 No per-user store; company config is one JSON blob

- Company settings + all feature flags = one JSON blob per client in
  `sandbox_client_configs` (`server.js:5071`), read via
  `GET /sandbox-config/:clientId` (`server.js:24937`), written by the
  control-plane. The default object is **triple-duplicated** (backend seed
  `server.js:5127`, static fallback `server.js:24952`, Dart `_globalDefaults`
  `config_service.dart:32`) with no generator keeping them in sync.
- `FeatureFlags.isEnabled('dotted.key')` returns **bool only**; a non-bool
  preference (an id list, a precision int) must be read off
  `ConfigService.instance.config[...]` directly (`feature_flags.dart:192-216`).
- **No per-user preference store** exists. Closest precedents are
  `material_group_preferences` (per material) and
  `material_group_units(material_id, unit_id, is_primary)` (per-material unit
  inclusion) — both per-material, not per-user (`server.js:3428,3441`).

### 0.5 Formatting is fully decentralized

- **67** `toStringAsFixed(N)` call-sites with hardcoded `N` + **9**
  `_formatQuantity`/`formatQuantity` definitions (two are duplicated private
  copies: `inventory_screen.dart:6313`, `jobs_screen.dart:3041`). The `units`
  table has **no precision column**, so per-unit precision is not representable
  today.

### 0.6 The evacuation vehicle is ready

- `registry.js:140-148` already declares the `units` module (label `Units`,
  group `Masters`, `pathSegments ['units']`, `tables ['units','unit_groups']`,
  `evacuated:false`). `modules/items/{contract,routes,ports}.js` is the textbook
  template.
- **Caveat:** `server.js` does **not** yet `require('./kernel/registry')` — it
  keeps parallel inline maps and gates `/api/units` on **legacy
  `config.read/config.write`** passthrough keys, not `units.crud`
  (`server.js:20847-21011`). Two contract engines coexist: kernel `checkPayload`
  (log-only, used by tests) vs server.js `guardContract` (rejects HTTP 400).
- **Live, not mock:** the `useMockResponses=true` default is overridden at every
  real entrypoint (`challan_mobile/lib/main.dart:491` passes `false`), so
  `/api/units` is live in shipped apps — this migration *will* be visible.

---

## 1. Target model

### 1.1 First-class families

Promote `unit_groups` to a real **family** (a physical *dimension*):

```
unit_groups
  + dimension    TEXT     -- 'length' | 'mass' | 'quantity' | 'area' | ... (stable, canonical)
  + base_unit_id INTEGER  -- authoritative family base (FK units.id)
```

- `base_unit_id` becomes the **authoritative** base; the implicit
  `conversion_base_unit_id IS NULL` convention is kept in sync on every write so
  nothing downstream breaks.
- Seed the canonical **Length / Mass / Quantity** families from
  `unitSystem_grouping.json` (the dead file finally becomes the seed source).
  Bases: **meter** (Length), **kilogram** (Mass), **piece** (Quantity).
- Everything keys on the **numeric `unitGroupId`** app-wide; the string
  `unitGroupName` keying (inventory filter, units-screen autocomplete) is
  migrated to the canonical id.

### 1.2 Conversion engine: linear + table-backed (gauge)

Add a conversion-kind discriminator and a points table for non-linear units:

```
units
  + conversion_type TEXT NOT NULL DEFAULT 'linear'   -- 'linear' | 'table'
  + precision       INTEGER                            -- display decimals (nullable)

unit_conversion_points        -- NEW: only for conversion_type='table'
  id           INTEGER PK
  unit_id      INTEGER NOT NULL FK units.id ON DELETE CASCADE
  point_key    TEXT    NOT NULL   -- e.g. '22'  (the gauge number)
  base_value   REAL    NOT NULL   -- value in the FAMILY BASE unit (meters), e.g. 0.000711
  UNIQUE(unit_id, point_key)
```

- **Linear** units keep `conversion_factor` (mm↔inch↔meter all linear in
  Length). **Table** units (gauge) store one row per discrete point; the value
  is normalized to the **family base (meter)** so a single `convert()` path
  serves both kinds.
- Gauge becomes a real Length-family unit (`symbol` `G`, `conversion_type`
  `'table'`), seeded with 40 points migrated from `swg_gauge_table.dart`.
- Reverse lookup (thickness→gauge) reuses the existing tolerance policy
  (0.0005 mm / 0.00005 in, `swg_gauge_table.dart:80-97`), now formalized
  server-side. Off-table thicknesses keep today's behavior: **stored verbatim,
  no gauge snap** (explicit policy, §6).

### 1.3 Included units — per-family + per-context (company-wide)

Stored in `sandbox_client_configs` under a new top-level `units` section (added
to all three sync points, §4):

```jsonc
"units": {
  "families": {
    "length": {
      "inventory":  [<unitId>, ...],
      "production": [<unitId>, ...],
      "sales":      [<unitId>, ...]
    },
    "mass":     { "inventory": [...], "production": [...], "sales": [...] },
    "quantity": { "inventory": [...], "production": [...], "sales": [...] }
  }
}
```

- A new `UnitsProvider.includedUnitsFor(familyId, context)` intersects
  `activeUnits` ∩ family scope ∩ the config list. When a family/context is
  absent from config it **falls back to all active units of that family**
  (safe default — nothing disappears until an admin curates).
- **Inclusion is a UI filter, never a data constraint.** A picker rendered on an
  existing entity must **union `includedUnitsFor(...)` with that entity's
  current primary unit and any already-configured secondary units**, so editing
  a legacy item whose unit was later un-included never silently drops or rewrites
  it. Out-of-policy current units may be visually flagged but must remain
  selectable/savable. (See §5 for where this lives.)
- This finally **wires the dead `compatibleActiveUnitsForGroupUnitId` helper**
  and gives every dropdown a single governed accessor.

### 1.4 The converter (the "global symbol" view)

- `units.symbol` is treated as **THE** global symbol — no parallel column. It is
  made authoritative by routing every dropdown label and display through one
  provider/port accessor, so a unit shows the identical symbol in orders,
  challans, inventory, mobile, etc.
- The Units master gains an **interactive converter**: pick a family, type a
  value in any unit, see it in every other included unit of that family — gauge
  included via table lookup. Backed by the same `convert()` used server-side.

---

## 2. Schema changes (one migration)

New numbered migration in `backend/migrations/` + `ensureColumnExists` guards
for fresh-DB bootstrap (the pattern at `server.js:6413,4673-4683`):

1. `ALTER unit_groups ADD dimension TEXT`, `ADD base_unit_id INTEGER`.
2. `ALTER units ADD conversion_type TEXT NOT NULL DEFAULT 'linear'`,
   `ADD precision INTEGER`.
3. `CREATE TABLE unit_conversion_points (...)` + index on `unit_id`.
4. Register both new columns in `rowToUnitDto` (`server.js:2170-2190`) and the
   Dart `UnitDefinition`.
5. Add `unit_conversion_points` to the `units` module's declared `tables` in
   `registry.js:147` (territory-meter ownership).

**Guardrail:** used units are frozen — changing name/symbol/group/factor/base on
a unit with `usage_count>0` throws 409 (`server.js:15830-15841`). Therefore all
base-unit assignment and factor backfill happens in the **data migration**, not
via the API (§7).

---

## 3. Backend — evacuate `units` and add the convert port

Follow the items evacuation sequence (`Docs/00 §3.2`) — **verbatim move first,
logic changes in separate commits**:

- **W1 — contract (log-only).** `modules/units/contract.js`: `unitWrite`
  (name/symbol required, `unitGroupId` nullable, `conversionFactor gt:0`,
  `conversionType enum`, `conversionBaseUnitId` nullable, `precision` nullable)
  + `unitEgress` mirroring `rowToUnitDto`. Wire `guardContract` on POST/PATCH
  `/api/units`.
- **W2 — move routes verbatim.** The 5 routes (`server.js:20847-21011`) →
  `registerUnitsModuleRoutes(ctx)` in `modules/units/routes.js`. No logic edits.
  Add `backend/test/units-module.test.js` mirroring `items-module.test.js`.
  Also add the missing **`unit_groups` routes** and **`GET /api/units/:id`**
  (gaps today) so the module owns its surface.
- **W3 — ports (`modules/units/ports.js`).** The high-leverage piece —
  `createUnitsPorts` exposing:
  - `units.describe(unitId)` → `{id, name, symbol, familyId, dimension, ...}`
    — replaces scattered `SELECT * FROM units` / `JOIN units` read-sites
    (`server.js:4610,7075,14533,14706,17454`, items contract `46-56`).
  - `units.convert({from, to, value})` → linear factor OR point lookup;
    the single authoritative conversion path (feeds the Dart converter over
    HTTP and any server-side conversion). **`convert()` is numeric-in** (`from`
    is a unit id, `value` a number) — it does not parse strings.
  - `units.parseQualifiedValue(str)` → resolves a **suffixed variation string**
    to `{unitId, value}` for the conversion path: `"22G"` → (gauge unit, point
    key `22`), `"0.711mm"`/`"0.028in"` → (the linear Length unit, number). Any
    caller that wants to re-render a stored gauge/thickness variation value in
    another unit runs `parseQualifiedValue` **then** `convert()`. Keeping the
    parse out of `convert()` preserves a clean numeric seam.
  - `units.gaugeTable()` → the 40 SWG points, so the Dart gauge input can pull
    the authoritative table instead of the local const.
- **W4 — service move.** `saveUnit`, `getUnitsWithUsage`, `rowToUnitDto`,
  unit-group helpers → `modules/units/service.js`. Invert the cross-module
  usage-count reads (materials/groups/items/order_items) toward ports/events to
  avoid K5 violations (`server.js:15734` + archive guard `20979-20988`).
- **W5 — enforce + flip.** Switch `/api/units` to `units.crud` keys (retire the
  legacy `config.*` passthrough), reconcile the log-only vs 400-reject contract
  engines, then set `evacuated:true` (`registry.js:147`).

---

## 4. Config — the `units` section

Add the `units.families.<dim>.<context>` block (§1.3) to the **three** default
JSONs that must stay in sync (`server.js:5127`, `server.js:24952`,
`config_service.dart:32`), plus an entry in `feature_registry.json` so the
control-plane admin UI can edit it. Because it is non-bool, expose it via a
typed `ConfigService` accessor (not `FeatureFlags.isEnabled`). Admin edits flow
through the existing `POST /api/sandbox-dashboard/client/:clientId/config`.

**Ship the drift guard with the section, not later:** a backend test
(`backend/test/config-defaults-sync.test.js`) asserts the three default sources
carry structurally matching keys for the `units` section (and ideally the whole
config tree). This lands in the **same commit** that adds the section, so the
triple-duplication can never silently drift in a future PR.

**Curation UI:** the Units master gets an "Include in app" matrix per family ×
context (checkbox grid), writing this config section. This is the concrete home
of *"user can select which units to include."*

---

## 5. Flutter — model, provider, converter, dropdown migration

- **Model.** Extend `UnitDefinition` with `dimension`, `conversionType`,
  `precision`, and family `base_unit_id`; add a `ConversionPoint` list for
  table units. Update `unit_api_models.dart` mapping.
- **Provider.** Add `includedUnitsFor(familyId, context)` (§1.3),
  `familyBaseUnit(familyId)`, and `convert(from, to, value)` (local for linear,
  port-backed for table). Keep `activeUnits` for back-compat during rollout.
- **Converter widget.** New in the Units master (§1.4).
- **Dropdown migration (flag-gated, incremental).** Migrate the 11 pickers from
  flat `activeUnits` to `includedUnitsFor(familyId, context)`. Each call-site
  already knows its context: inventory/orders/challans = the item's family
  (`item.unitId`'s group) in the relevant context; production Quick-Create =
  `production`; masters/dies/machines = the entity's family. Orders stays
  item-scoped (its own `unitConversions`) but the *addable* set becomes
  family+context scoped. **Preserve** the `"Primary Unit"` placeholder
  special-case and each site's inline-create affordance (decision: inline create
  still allowed on desktop, still forbidden on mobile — unchanged).
- **Current-unit union (mandatory, prevents edit-time data loss).** Every picker
  on an existing entity renders `includedUnitsFor(familyId, context) ∪
  {entity.currentUnitId} ∪ {already-configured secondary unit ids}`. Without
  this, opening a legacy item whose unit was later un-included would show a list
  missing that unit → the field defaults elsewhere and **saving silently mutates
  stored data**. The current-but-out-of-policy unit stays selectable (optionally
  flagged). This is the single most important correctness rule of the migration.
- **Shared `QuantityFormatter`.** Co-locate with `NamingFormatHelper`; honors
  `unit.precision`. Replace the 2 duplicated `_formatQuantity` first, then chip
  away at the 67 `toStringAsFixed` sites opportunistically (not a blocker).

---

## 6. Gauge integration specifics

- **Authoritative table server-side.** Seed `unit_conversion_points` for the
  gauge unit from `swg_gauge_table.dart` (base_value in meters). `swg_gauge_table.dart`
  becomes a **cache/fallback** of `units.gaugeTable()` so mobile capture is
  unchanged if offline.
- **Capture unchanged.** `_GaugeStepField` still emits the suffixed verbatim
  string (`"22G"`, `"0.711mm"`) — the variation value contract does not change.
  What changes: the field's grid + unit-chip fills now come from the
  authoritative table, and a gauge value is now *interpretable* elsewhere because
  the unit exists in the registry.
- **Reverse lookup + off-table policy (formalized).** thickness→gauge uses the
  0.0005 mm / 0.00005 in tolerance; off-table values are **stored verbatim with
  no gauge snap** (today's behavior), never silently mapped to the nearest
  gauge. `convert()` on an off-table value returns the linear mm/inch result but
  **no gauge point**.
- **Re-rendering stored gauge values.** Because variation values persist as
  suffixed strings (`"22G"`, `"0.711mm"`), anything wanting to show a stored
  value in another unit runs `units.parseQualifiedValue(str)` → `convert()`
  (§3). A `"G"` string resolves by point key; an `mm`/`in` string resolves as
  the linear Length unit. Nothing downstream does this today — it becomes
  possible only because gauge now exists in the registry.
- **Mobile parity.** `_GaugeStepField` is shared core_erp (desktop + mobile via
  `use_raw_material_wizard_screen.dart:251`), so both platforms get the
  authoritative table for free. Mobile remains pure data-entry (no unit picker,
  no creation).

---

## 7. Migration & seeding (one-time, direct DB — not via the frozen API)

1. Add columns + `unit_conversion_points` (§2).
2. Seed canonical families (Length base=meter, Mass base=kilogram, Quantity
   base=piece) with `dimension` + `base_unit_id`.
3. Assign existing ad-hoc / material-derived units (currently
   `unit_group_id NULL`, `server.js:6696-6730`) into families; set each family's
   `base_unit_id`; backfill `conversion_factor` so the explicit base and the
   implicit `NULL`-pointer base **agree**.
4. Insert missing linear units: **Pound** (Mass, factor 0.453592), plus Length
   members meter/mm/inch if absent.
5. Insert the **gauge** unit (`conversion_type='table'`, family=Length) + its 40
   points.
6. Leave `item_unit_conversions` **fully independent and cross-dimension-capable
   — do NOT add an intra-family constraint.** Per-item conversions are exactly
   where dimensional leaps legitimately live: `1 Box = 10 kg` (Quantity→Mass),
   volume→mass via density, etc. Enforcing "secondary unit must share the
   primary's family" would break packaging and density conversions. **Only** log
   divergence-from-family-factor for the subset where `from.family ==
   to.family` (the only case a family factor exists to diverge from); different
   families → nothing to compare, log nothing.

**If the Dart feature is still on the in-memory mock in any build**
(`api_unit_repository.dart:11-19`), re-seed the mock in parallel or flip it to
the real backend so the new families surface in-app.

---

## 8. Rollout sequencing

Behind a feature flag (`units.familiesV2`, mirroring `purchase.flowV2` /
`challans.reconciliation`) so v1 dropdowns keep working until each surface is
cut over:

1. Schema migration + seed (§2, §7) — invisible, additive.
2. Backend module W1–W3 (contract, verbatim routes, **ports**) — behavior
   identical; ports metered in `/api/kernel/territory`.
3. Config `units` section + admin curation UI (§4).
4. Flutter model + provider accessors + converter widget (§5) — additive.
5. Dropdown migration, **one surface per commit**, flag-gated (§5).
6. Backend W4–W5 (service move + enforcement flip + `evacuated:true`).
7. `QuantityFormatter` + precision adoption (ongoing).

---

## 9. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Wrong family base silently rebases every `conversion_factor` and derived item math | Finalize base in the **data migration** (used units are 409-frozen); assert explicit `base_unit_id` == implicit NULL-pointer base after backfill |
| Gauge near-boundary mis-map | Formalize the reverse-lookup tolerance server-side; off-table = verbatim, never snap; unit tests on all 40 rows + boundaries |
| Two conversion systems drift (`units.conversion_factor` vs per-item `factor_to_primary`) | Keep item conversions independent + **cross-dimension-capable** (no intra-family constraint); log divergence only when both units share a family; defer reconciliation |
| Edit-time data loss when a stored unit was later un-included from config | Pickers **union the entity's current + configured units** into the included list (§1.3, §5) — inclusion filters the UI, never constrains stored data |
| Config triple-duplication reverts a half-added section | Add `units` to all three JSONs in one commit **with** a `config-defaults-sync.test.js` drift guard (§4) |
| Legacy `config.*` gating bypasses the module CRUD grid | Switch `/api/units` to `units.crud` in the enforce step (W5) |
| Log-only contract actually rejects (400) once wired through `guardContract` | Reconcile the two engines during W1/W5 (same issue items hit) |
| `"Primary Unit"` placeholder breaks family-scoped pickers | Explicit special-case in `includedUnitsFor` (universally compatible), same as today |
| Evacuating units adds cross-border usage-count reads (K5) | Invert usage-count + archive/delete guards to ports/events in W4 |

---

## 10. Decisions

**Resolved (2026-07-29):** included-units grain = **per-family + per-context**;
gauge = **first-class table-backed unit**; family view = **interactive
converter**; base units = meter/kilogram/piece; delivery vehicle = **evacuate to
`modules/units`**; rollout = **feature-flagged, one dropdown per commit**.

**Still open (not blocking a start):**
- For the **same-family** subset only, should `item_unit_conversions` eventually
  *derive* from the family graph, or stay a per-item override? (Decided: stay
  independent + cross-dimension-capable; log divergence only within a family.
  Cross-dimensional conversions like Box→kg are always per-item — the family
  graph can never supply them.)
- Does conversion/inclusion management need a fine permission key
  (`units.conversion.manage`) or is coarse `units.crud` enough?
- Which additional families to seed beyond Length/Mass/Quantity (area? volume?)
  — the schema supports them; seeding is a data decision.
