# Five Reworks: Lookup-as-Investigation, Pipeline Node Clutter, Inventory Item View, Mobile Thickness + Material-as-Value, Challan Screen Collapse

> Status: **CAPTURED, NOT PLANNED.** Recorded 2026-08-24 from the requester's
> spoken notes ("bathroom thoughts"). Nothing here is scheduled, designed, or
> approved. The purpose of this file is to survive context loss: if the mental
> picture fades, this is the reconstruction seed.
>
> Structure per thought:
> - **Said** — faithful condensation of the requester's words.
> - **Understood** — my reading, stated concretely enough to be wrong.
> - **Today** — what the code actually does right now, cited.
> - **Open** — what I could not infer and need answered before design.
>
> **Read the "Open" lists first when picking this up.** They are the parts where
> the requester's picture was clear and mine was not.

---

## 1. Product Lookup becomes an investigation tool, not just a happy-path search

### Said

Today the flow is: a pipeline exists → assign the pipeline to an order → open
the order in production → assign stock to the first (Input) node. You type a
barcode into the Assign Stock search bar and get **no result** — but the
material is physically sitting in the factory. Product Lookup should be the
place you go next: search that barcode and find out *where it went*. Was it a
typo that caused it to be consumed? Was it ever recorded in the software at
all? The lookup should answer that.

### Understood

Product Lookup stops being "find a thing that exists and is available" and
becomes **"account for this barcode, whatever its state."** Concretely, given a
scanned or typed code, it should be able to say one of:

1. **Never recorded.** This code does not exist in any table. → offer to record
   it now (a reception challan, or a direct stock entry).
2. **Recorded and available** — here it is, here's the rack, and *here is why
   the Assign Stock search didn't show it* (wrong group, zero on-hand, reserved,
   archived, wrong factory/floor).
3. **Recorded and consumed** — consumed on `<date>`, into run `<run>`, at node
   `<node>`, for order `<order>`, by `<user>`. With the receipt trail: which
   challan brought it in, which scan events touched it, which movement rows
   moved it.
4. **Recorded but the trail is contradictory** — e.g. consumed but on-hand is
   still positive, or a child barcode whose parent was consumed whole. These are
   the typo cases. Surface them as *discrepancies*, not as errors to hide.

The framing I take from this: **a dead end in Assign Stock must always have a
next click.** "Barcode not found" is currently a terminal state; it should be a
link into Lookup with the code pre-filled.

### Today

- **There is no "Product Lookup" screen.** Nothing in the sidebar
  (`kSidebarNavigationOrder`, [navigation_provider.dart:5-25](lib/app/shell/navigation_provider.dart#L5-L25))
  is named that. The nearest thing is the **Global Search overlay**
  ([global_search_overlay.dart](packages/core_erp/lib/features/search/presentation/widgets/global_search_overlay.dart)),
  which has a barcode field.
- That overlay calls `GET /api/barcode/lookup`
  ([api_search_repository.dart:35-37](packages/core_erp/lib/features/search/data/repositories/api_search_repository.dart#L35-L37)
  → [server.js:24368](backend/server.js#L24368)). The query is **one join
  chain only**:
  `piece_barcodes → delivery_challan_items → delivery_challans`.
  It answers "which challan line minted this piece barcode" and nothing else.
- **Namespace gap.** `piece_barcodes` are per-piece parent/child codes minted
  off a *challan line*. Stock barcodes live in `materials.barcode`
  ([001-init.sql:1-17](backend/migrations/001-init.sql#L1-L17)) — a different
  namespace. The lookup does not search `materials` at all. So a perfectly
  valid stock barcode can return 404.
- On 404 the UI shows a snackbar: `'Barcode not found'`
  ([global_search_overlay.dart:146](packages/core_erp/lib/features/search/presentation/widgets/global_search_overlay.dart#L146)).
  Dead end, no next action.
- **The Assign Stock search is worse than it looks.** It is a *client-side
  substring filter over an already-loaded, doubly-filtered list*
  ([inventory_sidebar.dart:98-107](lib/features/production/widgets/inventory_sidebar.dart#L98-L107)):
  ```dart
  final availableMaterials = provider.materials.where((m) {
    if (m.onHand <= 0) return false;                       // (a)
    final groupName = ...;
    return groupName.contains('raw material');             // (b)
  })
  ```
  - **(a)** anything already consumed is invisible — exactly the case being
    investigated.
  - **(b)** a **hardcoded lowercase substring match on the group name**. A
    material whose group is not literally named something containing
    `"raw material"` can *never* appear here, no matter what you type. This is
    a silent, permanent dead end and is very likely a real cause of the
    scenario described, independent of any typo.
  - It never hits the server, so it cannot find anything not already paged in.
- **The evidence to answer the investigation already exists in the schema** —
  it is just not joined anywhere:
  | Table | What it can prove |
  |---|---|
  | `run_barcode_inputs` ([001-init.sql:43-51](backend/migrations/001-init.sql#L43-L51)) | this barcode was scanned into run X, node Y, at time T |
  | `order_material_allocations` ([001-init.sql:398-409](backend/migrations/001-init.sql#L398-L409)) | allocated vs **consumed** qty against an order + requirement |
  | `inventory_movements` | every quantity move, with origin |
  | `material_activity` / `scan_history` | per-barcode event stream |
  | `entity_activity_log` | the "Track" audit trail |
  | `piece_barcodes` | challan-line provenance (the only one currently used) |

  A Lookup that unions these is a **read-only join**, not new bookkeeping.

### Open

- Is Product Lookup a **new sidebar destination**, or is it the Global Search
  overlay grown up? (I lean: new destination, because investigation wants
  history, tabs, and screen space — an overlay fights that.)
- Should Lookup be able to **act** (correct a mis-consumption, reverse a
  movement, record the un-recorded material), or is it strictly read-only with
  hand-offs to the screens that already act?
- Does "no result" in Assign Stock need to *auto-offer* the Lookup jump, or is
  it enough that the user knows to go there?
- Is the `'raw material'` group-name hardcode a bug to fix outright, or is
  there an intended concept behind it (a `materialClass`, a group flag) that
  should replace it?

---

## 2. Pipeline node configuration — declutter, name the scrap/rejection intent, show save state, and land on the pipeline screen

### Said

Four separate complaints, all in the pipeline node config panel:

1. Too much clutter in that left panel when configuring a node.
2. Instead of just "scrap", **ask whether this is a rejection node or a scrap
   node**, and then ask for the scrap group.
3. There is **no way to tell whether what you typed into that box is saved**.
   The user needs some signal — saving / saved.
4. On Save you get a "Pipeline saved" toast but **stay on the builder**. You
   should be taken back to the pipeline screen, with the toast.

### Understood

**(2.1) Declutter.** The node panel currently renders every field for every
node type in one scroll. The fix is field relevance driven by node kind
(Input / process / Assembly / Output), with rarely-touched settings collapsed
behind a disclosure rather than always-on. Not a redesign — a triage of what is
shown by default.

**(2.2) Scrap vs rejection is a *declared property of the node*, not an
inference.** Today the app *infers* it: if the step is an Assembly step the
field is labelled "Rejected parts", otherwise "Scrap". The requester wants the
question asked outright — *is this a rejection node or a scrap node?* — and
then, having answered, to pick the **group** the output routes into. Note the
word used was **group**, not item: today the picker is scoped to items inside a
hardcoded group literally named `"Scrap"`. I read the ask as: let the user
nominate the destination group, then the item within it.

Semantically these differ and that is presumably why the requester wants them
separated:
- **Scrap** = material that was cut/turned/punched away. It has a *material
  type* and a weight and is sold by the kilo.
- **Rejection** = a whole part that failed. It has a *part identity*, a count,
  and it lands on somebody's job card.

**(2.3) Save-state affordance.** The panel edits are debounced into the
provider, so there is no moment where the user is told the edit landed. Wanted:
a per-panel state indicator — `Unsaved` → `Saving…` → `Saved`. This is about
the *node box*, distinct from (2.4) which is about the whole pipeline.

**(2.4) Save navigates back.** After a successful pipeline save, pop to the
pipelines list and show the toast there.

### Today

- **Panel:** `_NodePropertiesPanel` in
  [pipeline_builder_screen.dart](lib/features/production/screens/pipeline_builder_screen.dart)
  (the file is 5,048 lines; the panel body starts ~L3443). Header reads
  "Step Properties".
- **Scrap/rejection is inferred, not asked.** Two call sites with the *same*
  widget and different labels:
  - Assembly branch → `label: 'Rejected parts'`
    ([~L3518-3546](lib/features/production/screens/pipeline_builder_screen.dart#L3518-L3546))
  - Non-assembly branch → `label: 'Scrap'`
    ([~L3713-3740](lib/features/production/screens/pipeline_builder_screen.dart#L3713-L3740))

  The in-code comment states the intent explicitly: *"Nothing is machined here,
  so what comes off the line is not scrap — it is a piece the assembler
  rejected. Same routing…"* — i.e. **the distinction is already understood in
  the code but is derived from step type instead of being a user decision, and
  both cases share one storage field.**
- **Storage is one list, untyped:** `ProcessNode.scrapItems: List<ScrapItemRef>`
  ([process_node.dart:64](lib/features/production_pipelines/domain/process_node.dart#L64)).
  There is no `scrapKind` / `rejectionKind` discriminator. Adding one is a
  `nodes_json` shape change (nodes are stored as JSON on `pipeline_templates`,
  [001-init.sql:18-30](backend/migrations/001-init.sql#L18-L30)) — the file
  already has a legacy-key migration precedent (`scrapItemId` →
  `scrapItems`, [process_node.dart:120-135](lib/features/production_pipelines/domain/process_node.dart#L120-L135)),
  so follow that pattern.
- **The destination group is hardcoded.** `_ScrapItemDropdown` scopes to items
  in a group named `"Scrap"`; with none, the hint is
  `'Create a "Scrap" item group with scrap items (brass, aluminium, iron...).'`
  ([~L1988-2069](lib/features/production/screens/pipeline_builder_screen.dart#L1988-L2069)).
  Multi-scrap is behind `FeatureKeys.pipelineMultiScrapItems`.
- **Known incomplete downstream** — flagged in the code itself:
  > `// ponytail: reconciliation still routes all scrap to the first item;`
  > `// per-item scrap split in the reconcile dialog is the upgrade path.`
  > ([process_node.dart:67-69](lib/features/production_pipelines/domain/process_node.dart#L67-L69))

  So even today, configuring two scrap destinations does not actually split at
  reconcile time. **A scrap/rejection split must be carried through
  `stage_reconciliation_dialog.dart` or it is cosmetic.**
- **No save affordance in the panel.** Edits go through a `_debounce` into
  `PipelineEditorProvider`; nothing renders a dirty/saved state.
- **Save does not navigate.**
  ```dart
  Future<void> _saveAndNotify(BuildContext context) async {
    final saved = await _saveTemplate(context);
    if (saved == null || !context.mounted) return;
    showAppToast(context, 'Pipeline saved', kind: AppToastKind.success);
  }
  ```
  ([~L1326-1333](lib/features/production/screens/pipeline_builder_screen.dart#L1326-L1333))
  — no `onBack?.call()`. By contrast `_deletePipeline` *does* call
  `onBack?.call()` ([~L1367](lib/features/production/screens/pipeline_builder_screen.dart#L1367)),
  so the hook exists and the pattern is established. **This is a one-line-ish
  change** — modulo deciding whether an auto-save-on-every-edit model makes an
  explicit Save button confusing.
- There are **two save paths** — `_savePipeline` (~L116, toasts
  "Pipeline created"/"Pipeline saved") and `_saveTemplate`/`_saveAndNotify`
  (~L1289). Both need the same treatment or the behaviour stays inconsistent.

### Open

- **Which fields are the clutter?** I can guess (die, machine group, duration,
  unit-conversion multiplier, custom process code, barcode config) but the
  requester has a specific list in mind. Needs a walkthrough of the actual
  panel, pointing.
- **Is "scrap vs rejection" per-node or per-destination?** Could one node emit
  both scrap *and* rejections (a machining step that also rejects whole parts)?
  If yes, the discriminator belongs on each `ScrapItemRef`, not on the node.
- **"Ask for the scrap group"** — is the group a *filter* for the item picker,
  or is the group itself the destination (stock lands on the group, no item)?
- Does the save-state indicator mean "persisted to the server" or "committed to
  the in-memory draft"? These are very different promises. If the pipeline is
  only written on explicit Save, a per-node "Saved" badge would be a lie.
- After navigating back on save — back to the **pipelines list**, or back to
  the **shop floor** the pipeline belongs to?

---

## 3. Inventory item view modal — cut to arrival, orders, and children

### Said

The item viewing modal in Inventory has a lot of clutter. Simplify to:
- when the item arrived;
- has it been processed in a process / for an order? If yes, **list all the
  orders it has been processed for**, and clicking an order opens the order view
  modal on the Orders screen;
- **list all the subsidiary items under that item** — in the mobile app you can
  add as many sheets as you like under one coil/parent, and the desktop
  Inventory screen needs to show whether that is present or not.

### Understood

The modal answers three questions and stops:

1. **Where did this come from and when?** Arrival date, source challan/vendor.
2. **What has it been used for?** A list of orders — each row navigable into
   the Orders screen's order detail modal. If nothing, say so plainly.
3. **What is underneath it?** The parent→children tree (coil → sheets), with
   each child's own identity and weight, and each child individually
   inspectable.

Everything else — inventory-state enums, procurement state, traceability mode,
ATP, incoming, naming format, generated codes, alert lists — either moves
behind a "Details"/"Advanced" disclosure or leaves the modal entirely. These are
system-internal vocabulary, not shop-floor questions.

Note the overlap with **#1**: this modal is the natural place the *investigation*
answer lands once you have found the barcode. Same join, different entry point.
**They should share one backend endpoint and one presentation model.**

### Today

`_InventoryDetailSheet`
([inventory_screen.dart:6241](packages/core_erp/lib/features/inventory/presentation/screens/inventory_screen.dart#L6241),
in a 13,874-line file). It is a **flat `AppInfoPanel` with ~20 rows**, in order:

Inherited group · Inherited item · Naming format · Generated codes · Material
class · Inventory state · Procurement · Traceability · Location · Last activity
· Last scanned · Stock summary (On hand / Reserved / ATP / Incoming badges) ·
Stock by location · Reservations · Alerts · Linked demand · barcode info rows ·
Child barcodes · Movement timeline.

Against the three questions asked:

| Wanted | Status today |
|---|---|
| **Arrival** | Not present as such. `Last activity` / `Last scanned` only. Arrival must be derived from the first `inventory_movements` row or the source challan. |
| **Orders processed for** | **Absent.** The closest is one row: `'Linked demand'` → `'Orders {n} • Pipeline {n}'` ([~L6429-6433](packages/core_erp/lib/features/inventory/presentation/screens/inventory_screen.dart#L6429-L6433)) — **counts, not a list, not clickable.** |
| **Subsidiary items** | Present but inert: `material.linkedChildBarcodes` rendered as plain `_Badge` chips ([~L6438-6456](packages/core_erp/lib/features/inventory/presentation/screens/inventory_screen.dart#L6438-L6456)) — strings, no weight, not clickable, no drill-down. |

- **The parent/child model already exists** in schema and domain:
  `materials.kind`, `parent_barcode`, `number_of_children`,
  `linked_child_barcodes` ([001-init.sql:12-15](backend/migrations/001-init.sql#L12-L15));
  `MaterialRecord.isParent` ([material_record.dart:86](packages/core_erp/lib/features/inventory/domain/material_record.dart#L86));
  dedicated `parent_material.dart` / `child_material.dart` domain types. So #3's
  child list is a **presentation gap, not a data gap.**
- **The order deep-link target already exists**:
  `OrdersScreen.openOrderDetailsByNo` ([orders_screen.dart:132](packages/core_erp/lib/features/orders/presentation/screens/orders_screen.dart#L132))
  → `_OrderDetailsModal` ([orders_screen.dart:6175](packages/core_erp/lib/features/orders/presentation/screens/orders_screen.dart#L6175)).
  Nothing needs building on the Orders side — only the call.
- **Precedent for the click-through** already exists in this very modal: the
  movement timeline has `onOpenChallan` → `ChallanScreen.openEditor`
  ([~L6458-6474](packages/core_erp/lib/features/inventory/presentation/screens/inventory_screen.dart#L6458-L6474)).
  The order link should mirror that shape exactly.
- The data source is `loadMaterialControlTowerDetail(barcode)` →
  `MaterialControlTowerDetail` (material, stockPositions, movements,
  reservations, alerts). **It carries no orders list and no child records** —
  so this one *does* need a backend change, joining
  `order_material_allocations` + `run_barcode_inputs` → `pipeline_runs` →
  orders, and hydrating children from `materials WHERE parent_barcode = ?`.

### Open

- **"Arrived"** — the reception-challan date, the first inventory movement, or
  `created_at`? These diverge for back-dated entries.
- **"Processed for an order"** — does a *reservation/allocation* count, or only
  actual consumption (`consumed_qty > 0` / a `run_barcode_inputs` row)? I lean
  consumption, but reserved-but-not-yet-cut is a real state the shop cares
  about.
- Do the discarded fields (procurement state, ATP, traceability mode, alerts)
  get **hidden behind a disclosure** or **deleted from the modal**? Somebody may
  be relying on them.
- Children: flat list, or recursive tree (a sheet that was itself split)?
- Should the child rows show **remaining** weight vs original, so a
  half-consumed coil reads correctly?

---

## 4. Mobile: capture thickness at challan time; and let the Materials master supply variation *values*

Two related but separable asks.

### 4a. Thickness on the mobile challan / add-item flow

**Said.** In the mobile app, take **thickness** while making the challan /
adding the item, because thickness varies. Once you have thickness, plus the
per-sheet weights already captured under an item, plus the material type from
the new Materials tab, you know: total kg, the individual pieces, and what the
material *is*. From those you can back out the **dimensions** of each sheet, and
therefore account for the **total surface area of material in the factory**.

**Understood.** The chain the requester is describing:

```
material type ──► density (g/cm³)         [material_types.density_g_cm3]
per-sheet weight (kg)                     [already captured]
thickness (mm)                            [MISSING — this is the ask]

    weight ÷ (density × thickness) = surface area of that sheet
    Σ over all sheets = surface area held in the factory
```

Thickness is the one unknown. Everything else already exists. Adding it turns a
pile of kilograms into a pile of **square metres**, which is what a sheet-metal
shop actually plans against.

Note the requester said "dimensions", which strictly needs two of
{length, width, area}. From weight + density + thickness you get **area**, not
length × width. If actual rectangular dimensions are wanted, either width or
length must also be captured. Flagging this because the two are easy to
conflate and they lead to different UI.

**Today.**
- The purchase wizard captures **qty, weight, and per-sheet weights**
  ([purchase_wizard_screens.dart](apps/challan_mobile/lib/screens/purchase_wizard_screens.dart) —
  `onConfirm: (qty, weight, sheetWeights)`, ~L739 and ~L795). Grep for
  `thickness` in that file: **zero hits.** Confirmed absent.
- **`materials.thickness` already exists as a column** — `thickness TEXT`,
  [001-init.sql:7](backend/migrations/001-init.sql#L7). It is a free-text
  column, currently only used as a *search substring* in the production Assign
  Stock filter ([inventory_sidebar.dart:66](lib/features/production/widgets/inventory_sidebar.dart#L66)).
  **No migration is needed for the storage, only for making it numeric +
  unit-bearing** (`TEXT` will not sustain arithmetic).
- Density exists and is validated:
  `material_types.density_g_cm3`, 0.01–30 g/cm³, with a deliberate guard
  against kg/m³ mistakes
  ([material-types.js:19-53](backend/modules/items/material-types.js#L19-L53)).
- The migration comment already anticipates this exact use:
  > *"Sheet planning already knows a sheet's volume: width × height ×
  > thickness… What it could not know is what the sheet is made of, and
  > therefore what it weighs."*
  > ([034-material-master.sql](backend/migrations/034-material-master.sql))

  **The requester is asking to run that same relation backwards** — from
  measured weight to inferred geometry — which is the honest direction on
  receiving, where you have a scale but not a caliper on every sheet.
- `delivery_challan_items` has no thickness column; if thickness is per-line it
  needs one, and it must flow through to the `materials` rows minted from the
  challan.

**Open.**
- Thickness per **challan line**, per **sheet**, or per **item definition**?
  ("thickness can vary" suggests per-line at minimum; if it varies sheet to
  sheet within a bundle, per-sheet.)
- Units — mm, or **gauge**? The app already has a gauge input type and an SWG
  table, and gauge→mm is a documented non-linear table lookup
  (`01-units-master-and-conversion.md` §0.2). If gauge is allowed here it must
  resolve through that table, not a multiplier.
- Is surface area a **stored derived field** or **computed on read**? Stored is
  faster but goes stale when density is edited.
- Where does total factory surface area surface — Inventory header, Insights, a
  Materials-tab rollup?
- Does the requester want true **length × width** (needs one more input), or is
  **area** the actual goal? My reading is area, but this is worth confirming
  before building an input.

### 4b. Materials as selectable values under a top-level property

**Said.** With the Materials tab now existing, add functionality so that
materials can be **included as values under a top-level property** when creating
an item or a variant. Then in the mobile app the user does not have to check the
item *and* separately check the values — both happen at once.

**Understood.** Add a **`Material` variation input type**, exactly parallel to
the existing `Gauge` type: a property marked as `Material` draws its value list
**from the `material_types` master** rather than from hand-authored child value
nodes. Benefits:

- One place to add "Brass" — the Materials tab — and every item with a Material
  property gets it.
- The captured value carries a **material_type id**, so density travels with it
  → §4a's area maths works without a second lookup.
- On mobile, picking the item and picking its material collapse into one pass
  through the variation selector instead of two disjoint steps.

**Today.**
- **Exactly the right precedent exists.** Input type is a plain string on
  `ItemVariationNodeDefinition.inputType`, defaulting to `'Text'`
  ([item_definition.dart:19,37](packages/core_erp/lib/features/items/domain/item_definition.dart#L19-L37)),
  and is cycled by an `A / 1 / G` pill:
  ```dart
  String _nextVariationInputType(String current) {
    switch (current) {
      case 'Text':    return 'Numeric';
      case 'Numeric': return 'Gauge';
      default:        return 'Text';
    }
  }
  ```
  ([items_screen.dart:10330-10339](packages/core_erp/lib/features/items/presentation/screens/items_screen.dart#L10330-L10339))
  Adding `'Material'` (an `M` pill) is a fourth case here plus a picker in
  `_GaugeStepField`'s sibling position in
  [variation_path_selector_dialog.dart](packages/core_erp/lib/widgets/variation_path_selector_dialog.dart).
- Consumers that special-case data-entry types are enumerable and few — e.g.
  `node.inputType == 'Numeric' || node.inputType == 'Gauge'`
  ([orders_screen.dart:4796](packages/core_erp/lib/features/orders/presentation/screens/orders_screen.dart#L4796)),
  [set_order_dialogs.dart:299](packages/core_erp/lib/features/orders/presentation/widgets/set_order_dialogs.dart#L299),
  [items_screen.dart:9412](packages/core_erp/lib/features/items/presentation/screens/items_screen.dart#L9412).
  **Every one of these must learn about `Material` or it will be silently
  mishandled** — the Gauge rollout is the map for where the edits land.
- **Two "material" concepts are in play and must not be conflated:**
  - `material_types` — the master (name + density). *This* is what should
    populate variation values.
  - `materials` — barcoded physical stock (this sheet, this rack).
    `materials.type` is currently **free text**, unlinked to `material_types`.

  A likely companion change: give `materials` a real FK to `material_types` so
  stock inherits density instead of relying on a matching string.
- Gauge values are stored as **verbatim suffixed strings** with *no unit
  metadata travelling with them* (`01-units-master-and-conversion.md` §0.2).
  **Do not repeat that for Material** — store the `material_type_id`, render the
  name.

**Open.**
- Does the Material property expose **every** non-archived material type, or a
  per-item allow-list (a shop that only ever buys MS and SS should not scroll
  36 rows)? The units work chose per-family/per-context inclusion lists — the
  same shape probably applies.
- Can a user create a new material type **inline** from the variation picker
  (as `_ScrapItemDropdown` allows via `onCreateOption`)? If yes, density becomes
  a required field in a cramped mobile sheet.
- Should the existing free-text `materials.type` be **backfilled** onto
  `material_types`, and what happens to values that do not match anything?
- Naming: `Material` collides in conversation with the `materials` stock table.
  Consider surfacing it as **"Material type"** in the UI.

---

## 5. Challan screen — collapse the split view; reports derive from orders

### Said

The current divided screen exists so you can see, side by side, what is inside
the factory against what reception challans were given against what was
delivered — a clear view of financials, or at least the sum total of material.
That was the reason for the layout.

But the workflow has moved on: a pipeline is assigned to an order; the order is
taken from what the client wants and the items already in the system; delivery
follows when production finishes; production accounts for assigned stock, which
comes from reception challans or inventory. **A report is always made for an
order** — so the software already knows what items were used and how.

Therefore the split screen is not needed to *make* a report; reports can be
generated automatically. The divided view should remain only as an
**investigation** view. Most of the clutter on the challan screen can go.

### Understood

The split view was a **manual reconciliation instrument** — a human eye doing a
join the software could not do. Now the join exists in data
(order → pipeline → run → assigned stock → reception challan; order → delivery
challan), so:

1. **Reports become derived artefacts**, generated per order, not assembled by
   a person reading two columns.
2. The **default** challan screen becomes a plain list/browser of challans.
3. The **In / Out / Balance ledger survives as an investigation mode** — behind
   a toggle, not the front door. It is the tie-breaker when the derived numbers
   are disputed, which is the same role Product Lookup plays in #1.

This is the same shape as #1 and #3: *the happy path gets simpler because the
data model got stronger; the old manual view is retained as the audit path.*

### Today

- `_ChallanWorkspace` renders a literal three-column `Row`:
  ```dart
  Expanded(child: _column(context, ChallanType.reception)),
  Expanded(child: _column(context, ChallanType.delivery)),
  Expanded(child: _column(context, ChallanType.internal)),
  ```
  ([delivery_challan_screen.dart:1042-1064](packages/core_erp/lib/features/delivery_challans/presentation/screens/delivery_challan_screen.dart#L1042-L1064)),
  plus `_ChallanDetailPane`, `_Filters` with segment selectors, `_Header`,
  `_ItemFilterBanner`, `_LineItemsPanel`, `_ChallanPhotosPanel`. The screen is
  6,805 lines.
- The **In/Out/Balance ledger** is `ChallanExcelView`
  ([challan_excel_view.dart](packages/core_erp/lib/features/delivery_challans/presentation/widgets/challan_excel_view.dart)),
  opened via `ChallanExcelView.show(...)`
  ([delivery_challan_screen.dart:1165](packages/core_erp/lib/features/delivery_challans/presentation/screens/delivery_challan_screen.dart#L1165)).
  Columns: Date · Party Name · Item Particulars · **In** · **Out** · **Balance**
  ([~L466-495](packages/core_erp/lib/features/delivery_challans/presentation/widgets/challan_excel_view.dart#L466-L495)),
  where In fills only for `isReception` and Out only for `isDelivery`
  ([~L570-600](packages/core_erp/lib/features/delivery_challans/presentation/widgets/challan_excel_view.dart#L570-L600)).
  **This is precisely the manual reconciliation the requester is describing as
  now-redundant.** It is already a dialog, not the main screen — so demoting it
  to "investigation mode" is mostly a matter of *where it is reachable from and
  how prominent*, not a rebuild.
- A reconciliation screen already exists as its own destination:
  `'challan_invoice_report' => ChallanInvoiceReconciliationScreen()`
  ([app_shell.dart:933-934](lib/app/shell/app_shell.dart#L933-L934)), sharing
  the challans tab index ([navigation_provider.dart:56](lib/app/shell/navigation_provider.dart#L56)).
  **Whether the derived report belongs here or on the order needs deciding
  before anything is cut.**
- The joins the derived report needs are all present:
  `delivery_challan_orders` (challan↔order), `order_material_allocations`
  (allocated + consumed per barcode per order), `run_barcode_inputs`
  (barcode→run→node), `order_status_history`, `order_returns`
  ([server.js:5448](backend/server.js#L5448)).

### Open

- **What is "the report"?** Requester said "we are not taking invoice as of
  now" — so is this a material-consumption statement per order, a job-work
  reconciliation, or a pre-invoice? The content decides where it lives.
- Does the derived report **replace** `ChallanInvoiceReconciliationScreen`, or
  feed it?
- Where does the surviving ledger live — a toggle on the challan screen, a mode
  inside Product Lookup (#1), or its own investigation destination?
- **Internal-use challans** are the third column. They do not map cleanly to a
  client order. Does the simplified screen still surface them, and does the
  reconciliation flow (`POST /api/challans/:id/reconcile`) become the derived
  report's source for those?
- Is anyone currently *using* the three-column view as a daily driver? Removing
  it as the default is a visible change to whoever balances material by eye.

---

## Cross-cutting observations

**A. One theme runs through #1, #3, and #5.** All three say the same thing:
*the model is now strong enough that the manual, side-by-side, eyeball-it view
is no longer the primary interface — it should be demoted to the audit path.*
Product Lookup, the inventory modal, and the challan ledger are three faces of
one capability: **"prove what happened to this material."** If they are built
separately they will disagree with each other. **One backend
`GET /api/trace/:barcode` returning a unified provenance object, consumed by all
three surfaces, is the design I would argue for.**

**B. #4a and #4b are one feature wearing two hats.** Thickness is only valuable
because density is known; density is only reliably known if the material type is
a *reference*, not free text. Build 4b first (material as a typed value), and 4a
gets its density for free. Doing 4a first means parsing `materials.type` strings
to guess density — which is the bug, not the feature.

**C. Three hardcoded string matches turned up, all the same anti-pattern:**
| Where | Hardcode | Consequence |
|---|---|---|
| [inventory_sidebar.dart:104](lib/features/production/widgets/inventory_sidebar.dart#L104) | `groupName.contains('raw material')` | stock in a differently-named group is *unassignable*, silently |
| [pipeline_builder_screen.dart:~2052](lib/features/production/screens/pipeline_builder_screen.dart#L2052) | group literally named `"Scrap"` | scrap routing depends on a group name |
| [materials `type`](backend/migrations/001-init.sql#L5) | free-text material name | no density link |

These are worth a single pass whenever this work starts.

**D. Scope reality check.** These five touch the four largest files in the
codebase: `inventory_screen.dart` (13,874), `delivery_challan_screen.dart`
(6,805), `pipeline_builder_screen.dart` (5,048), `orders_screen.dart` (~8,400+).
None of these is a small change *in place*. Several are natural candidates for
the **module evacuation** pattern established in
`00-kernel-and-items-evacuation.md` — particularly #3 and #5.

**E. Cheap wins that need no design.** If the requester wants momentum before
the big pieces:
1. `_saveAndNotify` → add `onBack?.call()` (#2.4).
2. Barcode-not-found → make it a link, not a dead end (#1).
3. `'Linked demand'` counts → clickable order list (#3), using the existing
   `openOrderDetailsByNo`.
4. The `'raw material'` group hardcode (#1 / cross-cutting C).

## Suggested sequencing (my opinion, not a decision)

```
4b  Material as a typed variation value      ← unblocks 4a; smallest blast radius
 │
4a  Thickness on mobile + surface area       ← needs 4b's density link
 │
1   Unified trace endpoint + Product Lookup  ← the investigation spine
 │
3   Inventory modal rebuilt on that endpoint ← reuses 1's backend
 │
5   Challan screen collapse + derived report ← largest; safest once 1 & 3 prove the joins
 │
2   Pipeline node panel                      ← independent of all the above; can run in parallel
```

#2 has no data dependency on the others and can be done any time by anyone.

---

## Correct me here

The items I am least confident about, ranked. Answering these five is enough to
start designing:

1. **§4a** — do you want true sheet **dimensions** (needs one more input:
   width or length), or is **surface area** the goal? I assumed area.
2. **§2.2** — is scrap-vs-rejection a property of the **node**, or of each
   **destination** (can one node emit both)? I assumed the node.
3. **§3** — does "processed for an order" mean **allocated/reserved**, or only
   **actually consumed**? I assumed consumed.
4. **§5** — what is *"the report"* concretely, and does it live on the **order**
   or stay on the **challan tab**? I have no confident reading.
5. **§2.1** — which specific fields are the clutter in the node panel? I cannot
   guess this one usefully; it needs you pointing at the screen.
