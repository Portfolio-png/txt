# Paper — The Vision, and What Is Still Open

> Assembled 2026-09-11 from every Claude Code session recorded for this project:
> 25 transcripts spanning 2026-07-30 → 2026-09-11, 783 messages written by the
> requester, plus the seven architecture documents in this folder and the code
> as it stands at commit `e7fc523`.
>
> **Method.** Every transcript was read in full by a separate reader; only the
> requester's own words were used, never the assistant's replies. 500 statements
> of intent and 366 candidate open items were extracted, then collapsed to 312
> and 297 by removing restatements. Part 2's status column was then checked
> against the code. Where a line says **verified**, a grep or a file read backs
> it. Where it says **unverified**, it comes from the transcript only and nobody
> has confirmed it against the code — treat those as leads, not as facts.
>
> Sibling documents: `00` kernel evacuation · `01` units · `02` the five
> reworks · `03` barcodes · `04` wire weight · `05` local-first · `06` pipeline
> editor field guide. This one sits above them and says why they exist.

---

# Part 1 — The vision

## 1. What Paper is

Paper is a full-stack ERP for a sheet-metal and electrical-components factory.
A Flutter client (desktop Windows/macOS, plus a phone app for the shop floor)
over a Node/Express + SQLite backend, sold to small Indian manufacturers and
run on their own hardware.

The thing that makes it worth building, in the requester's own words:

> *"as if all modules are interconnected in this app, so investigation and
> report generation should be seamless — that's why someone would even use this
> application, as it is keeping autonomous track of date and data."*

Everything below is downstream of that sentence. The product is not a set of
forms. It is a single connected record of what physically happened in a factory,
strong enough that questions can be answered from it rather than reconstructed
by a person holding two printouts side by side.

## 2. The constitution — principles that hold across the whole project

### 2.1 The data model is the product

**The SQL schema must hold every truth the UI claims.** Stated in capitals, and
treated as a risk register item rather than a style preference:

> *"SEE WHATEVER WE HAVE ON FRONTEND, WE SHOULD HAVE THAT IN BACKEND SQL TOO.
> ELSE THIS IS A SERIOUS RISK."*

**Store ids, not strings.** The Gauge input type stored verbatim suffixed
strings (`"0.711mm"`, `"22G"`) with no unit metadata travelling with them; when
the Material input type was designed, the rule was set explicitly so the mistake
would not repeat: store `material_type_id`, render the name.

**Pre-ship freedom, used deliberately.** Because nothing is shipped and all
current data is seeded, missing links are fixed by adding columns rather than
worked around:

> *"see if there's no link like this then please add those columns, so that it
> happens. the app isn't yet shipped. so we have time to do this."*

**Never silently corrupt data to avoid an error.** A broad try/catch around
identity resolution was rejected because its silent path would have degraded
unspecified order lines into base items. Declining to record beats recording
wrongly — *an unminted lot can be retroactively attributed; a mislabelled lot in
an append-only ledger permanently corrupts history.*

**Derive, don't ask.** Where the system already holds the facts, compute the
answer instead of adding a dropdown and demanding retroactive human input.

### 2.2 The order is the spine

The chain the whole product hangs from, stated once and never revised:

```
reception challan → inventory → assign stock to a run
      → run (a numbered pipeline instance owned by an order)
            → order → delivery challan → client
```

> *"id say do it on the order, as through order we know what's been made and how
> much of it is fulfilled, so committing a delivery challan would be made through
> order itself... also completed orders will make a report: that will show
> reconciliation of reception challan and delivery challan with dates and
> delivered qty with scrap."*

The consequence: **reports are derived artefacts, not assembled ones.** The
divided reception-vs-delivery challan screen was a human doing a join the
software could not do. Now that the join exists in data, that screen demotes to
an *investigation* view and the report generates itself.

### 2.3 Barcode is the universal spine

Every physical and paper thing in the factory carries a code — people, floors,
departments, pipelines, notes, runs, orders, reception and delivery challans,
reports, clients, material in, material out — and one lookup answers for all of
them.

> *"I want to implement barcode across the app... And when I do a lookup for
> that barcode, I get to see everything about that barcode."*

Three rules were set around it:
- **Codes are derived, not minted.** `TYPE-ID-CHECK` computed from the row that
  already exists, which removes the birthday problem rather than making it rarer.
- **The trail is append-only,** enforced by SQLite abort triggers, not by
  convention, because the question it answers — *what happened to this part* —
  is asked years later when a client returns something.
- **Custody walks both ways.** Scanning a returned workpiece must surface the
  order; scanning the order must surface its returns.

And a scope limit, deliberately: granularity stops at the batch / delivery-challan
quantity. Per-piece tagging of produced goods is **not** in scope for now.

### 2.4 Lookup is investigation, not search

The sharpest single idea in the whole corpus. Product Lookup is not "find a
thing that exists and is available" — it is **"account for this barcode,
whatever its state."**

> *"Was it even ever recorded in the software or not? So that way product lookup
> helps me."*

A dead end in Assign Stock must always have a next click. "Barcode not found" is
currently a terminal state; it should be a link into Lookup with the code
pre-filled. The same capability — *prove what happened to this material* — is
what the inventory item modal and the challan ledger are also asking for, which
is why they should share one backend endpoint rather than disagreeing with each
other.

### 2.5 The shop floor is the hard constraint

- **Operator literacy is a design input.** Stroke-cycle counting and automated
  die-wear percentages were cut to Phase 2 explicitly because they demand
  per-cycle capture from people who will not sustain it, and bad data is worse
  than no data.
- **Never block physical work.** A standalone run whose operator answers "not
  sure yet" deploys anyway rather than cancelling — *forcing a rigid decision
  before physical work begins causes operators to bypass systems or invent fake
  selections.*
- **Weights are an accountability instrument.** Per-sheet weights are typed
  individually rather than averaged, because per-sheet truth is what lets you
  catch a miscalculation or a theft and confront the delivery driver on the spot.
- **Analytics live on the object,** not on a metrics page. Machine utilisation
  belongs on the machine card, not on a separate dashboard.

### 2.6 The wire, and the weak machine

Two hardware facts that forced an architecture:

> *"I'm installing this software in an i3 with 8 gigs of ram with no gpu pc. and
> being such a 21mb of software. this still lags with absolute no UI."*

> *"...it will create a JSON blob and go to AWS, then check, then come again.
> This is very repetitive and shitty... Even with, say, if someone has like a
> one MBPS speed to their connection."*

The measured answer: the server answers in 1–16 ms and the wire costs ~2000 ms.
So the fix is not a faster backend and not fewer features — it is to stop
sending so much, so often, and to stop re-sending what has not changed. That
produced the tiered plan: compression and slim list DTOs (14.8× on cold start),
conditional requests (a relaunch costs ~0 bytes), then a local SQLite replica
fed by a change log.

And the rule that made the replica trustworthy: **change logging must be
database-enforced, not hand-written.** Coverage was ~7% across 174 mutation
sites, because it depended on whoever wrote the endpoint remembering. Triggers
cannot be forgotten.

**Real time is a multi-user requirement**, and the bar is stated bluntly:

> *"when we have, like, two to three users on the line, it will be quite tough
> if the updates are not being pushed real time in microseconds."*

### 2.7 The kernel — dissolving the monolith

`backend/server.js` was 27,561 lines, ~200 routes, ~93 tables. The plan is not a
rewrite: a kernel is mounted *inside* the running process and the legacy code
becomes a tenant. Five rules, enforced from day one:

| | Rule |
|---|---|
| **K1** | Inversion — the kernel owns the app, DB, auth and boot order |
| **K2** | Freeze — no new feature ever lands in legacy again |
| **K3** | Metering — unclaimed routes and tables are a visible warning |
| **K4** | One question, one border — no route-local permission logic, ever |
| **K5** | Module-to-module is ports and events only, never direct SQL |

Two production bugs motivated it, and both were border failures: an asset-upload
403 caused by three overlapping permission regimes, and a negative variation-leaf
id caused by challans reading items' tree internals directly.

### 2.8 How the UI is supposed to feel

A consistent set of rules, repeated across many sessions:

- **Never stock Flutter.** Every screen gets a pass against the house standard.
- **No horizontal scroll, and on Orders no vertical scroll either** — cards, not
  a scrolling list.
- **Slide, don't pop.** A new panel slides in beside the current one so a
  multi-step task reads as a workflow rather than a stack of dialogs.
- **Side panel over popup.** Detail views use the Inventory-style right panel on
  single click; a real popup is reserved for double click.
- **Steppers, never long forms.** The primary button becomes *Next*, and each
  stage is its own step.
- **Congestion is a defect.** Nested content stays collapsed until clicked, and
  anything expanded needs a bounding box so it reads as distinct.
- **Never truncate a name.** *"Don't do that three dot thing"* — wrap instead.
- **Hover bubbles must add information,** never restate what the card shows.
- **Animation must be legible** — slow enough to see the row carry over.
- **One component everywhere.** Divergent copies of the same picker are a defect
  to be fixed, not a local variation to tolerate.
- **A link-out must arrive at the thing,** not at the list that contains it.
- **Dropdowns open where the eye already is,** adjacent to the field being typed.
- **Density over prose.** *"this is way too much text and giving no value.
  collapse it or say concrete it."*
- **Colour is a learned language.** Group types get distinct folder colours, and
  the same colours appear on the creation rows so the user learns what they are
  about to make.
- **No unexplained jargon.** *"what is jerf and edge trim? ... I don't have a
  fucking view what that means."*

### 2.9 Creation must be cyclic

The single loudest usability theme of the last month. Today a pipeline needs an
item, the item needs master data, and the pipeline must exist before the item —
*"quite a dependency and never ending, like, never ending dependency loop."*

> *"make it so cyclic that adding a set or adding an item to a set is vice
> versa, or adding a pipeline to an item, or making a pipeline through the set."*

Everything must be creatable in place: a die, a machine, an item, a raw
material, a process, a group — from wherever you happen to need it. A new user
arriving with everything on paper should never have to walk items, then
pipelines, then variations as separate lengthy lists.

The chosen metaphor for this is **MIT Scratch**: the pipeline is assembled out
of snap-together blocks, the left rail is Paper's own masters (dies, machines,
items, raw materials, scrap, clients) instead of motion/looks/sound, and
if/else logic gets expressed the Scratch way — a client block stacked over a die
declares who it is being made for.

### 2.10 Ways of working

- **Bathroom thoughts.** Ideas that arrive away from the keyboard are dictated
  raw, written down, and **played back for correction** — the document exists
  specifically to survive the requester's own context loss. *Capture is
  explicitly not a commitment to build.*
- **Prototype before you commit.** New interaction ideas are built in a
  throwaway webview or React project and only folded into Flutter once proven.
- **Simulation as proof, not demo dressing.** Seed a business that has been
  using the software for nearly a year, with real imagery on every master, so
  the app can be judged as it would look in use. Editing seeded data must
  propagate in real time exactly like user-entered data.
- **Root causes, not symptoms** — graded explicitly on that axis.
- **Handover-ready specs**, complete enough for the next developer.
- **Watch how they actually use it.** Control over client data, to see whether
  users are using the software the wrong way *or whether their way is the way*,
  and plan features from that.

## 3. Vision, module by module

### Items, Groups, Variations
An item is the orderable atom and carries its own die and its own pipeline.
**Simple items must stay simple** — the variant workflow only appears once the
user clicks "Create Variant". **Variants are the normal case** though, so every
new property type must work properly in the variant flow. Variants inherit their
base item's group automatically, appearing both under the item and under the
group. **Group rules are deliberately not strict**: combination groups attach to
variants, nest under primary groups, and hierarchical groups can contain
combination groups. Item name and display name are different things; display
name can be built from property:value codes, and **every value under a top-level
property must carry a code**, with a legible error when one is missing.
The item short code simply *is* the item name.

**Item + expression grammar.** One-line entry — `Item + value + value` — that
creates an item with its values inline, and it belongs on *every* item selector
dropdown in the app, not just the items master.

### Sets and Components
A Set is a quantified bill of items — *"two times item A and one times item B"* —
which is what a component is. Orders expand sets into lines carrying set
provenance; they never reference the set itself. Sets are orderable, carry their
own photo, and belong to a client.

**Reversed 2026-09-07:** sets must be left alone. All BOM, pipeline, die and
machine work moves to **component groups** instead, and the group-wide default
pipeline is removed — each individual item carries its own pipeline. The
exploration metaphor for a component is expanding **kanban columns**: pipelines
and items beside the component, clicking a pipeline opens a machines column and
a dies column to its right.

### Inventory and Materials
Stock is **decoupled**: sheets are bought in bulk from vendors and many small
client orders nibble portions off them; there is deliberately no 1-to-1 link
between a client purchase and a vendor purchase. Procurement-on-demand is the
second mode, where a reception must point back at the client order.

Raw sheets keep their vendor identity. Finished-goods cards surface their
pedigree — the pipeline that produced them, the order they came from, when and
who. Items nest: many sheets under one coil, and the desktop must show what
mobile records.

The inventory item modal should be a **simple life story**: when it arrived,
which orders it was processed for (clickable through to the order), and what is
nested under it. Everything else moves behind a disclosure.

A **Material master** holds density per material, mirroring the Global Units
pattern, so weight = density × volume is derived rather than typed. Registered
materials survive a factory reset, because they are a property of the material,
not of the transactions.

### Delivery Challans (desktop + mobile)
Weight is mandatory on mobile and typed per sheet, with **total in = total out**.
Each sheet gets a card carrying its own barcode and weight box, printable.
Informal flows still get formal records: a vendor sheet return is logged as a
specialised return challan.

The desktop challan screen collapses to one list; the three-column ledger
survives behind a *Compare in/out* toggle as the investigation path.

**Still to capture: thickness.** With thickness plus the per-sheet weights
already captured plus the material's density, sheet dimensions fall out — and
with them the **total surface area of metal sitting in the factory**, which is
what a sheet-metal shop actually plans against.

### Orders
Order creation toggles between items and sets. Quantity accepts Indian shorthand
(1k, 1L, 10L) so nobody counts zeroes. **Order Insights** slides in from the
right: orders with and without a pipeline, a fulfilment bar fed by what the
floor actually reports through reconciliation, with delivery checkpoints drawn
like *a knife in the cake*. **Track** clubs timeline and trace into one view —
who handled it, and how long each stage took.

**Backward traceability forever:** a client return years later must walk
Return → Order → Run → Die + Machine → vendor sheet → Vendor.

### Production, Pipelines, Node Configurator
Production is a numbered pipeline instance per order. An **Assembly node** is a
void where many steps converge — pure human assemblage, so no input item, output
item, machine or die. At assembly there is no scrap: a bad part is a
**rejection**, and rejections land on the worker's card. Items clipped together
at assembly become a temporary Set, which surfaces in Inventory with its
provenance and its own in/out ledger — and assigning it to a job worker is an
OUT movement, because it has left the facility.

Scrap and rejection are **different things** and the node must ask which it is,
then ask for the destination group. Today the app infers it from step type, and
the distinction does not survive to reconcile time.

The **Node Configurator** is a marketplace of reusable nodes on its own full
screen: compose a node (this machine, this die), save it, let different clients
pull from the shelf. Slot modes are semantically distinct — *"without machine,
without die, with machine, with die, with machine group, with die not
assigned"* — and must not collapse into a null. Units are always the user's
choice, because loss is sometimes measured in gross.

### Sheet planning
The real product, taken straight from a client meeting: they hold dies as
DWG/CAD files and do sheet planning today with pen and paper. The software does
all the obvious work, and helps with the last non-obvious part. Distinctions on
the sheet are shown with **colour and shape, never mathematical notation** —
mathematics was how it was communicated on paper; the front end has better
tools. Cuts are dynamic and region-targeted. Every node gets its own sheet
planning, and the result carries forward to the next node.

### Masters, Settings, Platform
Card view across all masters, with Pipelines and People excluded. People is
department-first. Factory Reset is super_admin-only and typed-phrase gated.
Scenarios live in Settings, not in scripts. Permissions are module × CRUD keys
enforced by one central path→module middleware. Deployment needs a **canal** —
pushing a backend update must never revoke the copy the client is running.

---

# Part 2 — Uncompleted tasks, as a tree

Legend — every leaf carries `[layer · state · first asked]`:

- layer: **FS** full stack · **BE** backend only · **FE** frontend only
- state: **OPEN✓** confirmed open against the code · **OPEN?** from the
  transcript only, not code-checked · **PART** partly built · **PROTO** exists
  only in a throwaway prototype · **DEFER** deliberately postponed

```
Paper [full stack]
│
├── ORDERS ────────────────────────────────────────────────── [full stack]
│   ├── Orders screen (orders_screen.dart)
│   │   ├── No vertical scroll; every order as a card regardless of
│   │   │   categorisation ........................... [FE · OPEN? · 08-17]
│   │   ├── Commit the delivery challan from the order itself,
│   │   │   not from the challans screen ............. [FS · OPEN? · 08-25]
│   │   └── Completed order emits its reconciliation report
│   │       (backend traversal exists, no UI) ........ [FE · PART  · 08-25]
│   ├── Order Insights
│   │   ├── Fulfilment bar fed by real floor reconciliation
│   │   │   rather than seeded data ................... [FS · OPEN? · 08-14]
│   │   ├── Progress never renders green (3 reports) .. [FE · OPEN? · 08-14]
│   │   ├── Checkpoints drawn as "knife in the cake" .. [FE · OPEN? · 08-14]
│   │   ├── Delivery checkpoint showing units delivered [FS · OPEN? · 08-14]
│   │   ├── Checkpoint hover bubble → challan preview,
│   │   │   with a back route to the insight .......... [FS · OPEN? · 08-15]
│   │   ├── Filters: started/stalled, not-started/old . [FS · OPEN? · 08-14]
│   │   └── Remove "runs struggle" from Insights ...... [FE · OPEN? · 08-15]
│   ├── Track tab
│   │   └── Club timeline + trace into one view, carrying
│   │       the Insights content ...................... [FS · OPEN? · 08-17]
│   └── Trace / Returns  (backend landed 08-26: order_returns table +
│       GET /api/orders/:orderNo/trace + CUSTOMER_RETURN events)
│       ├── "Log Return" dialog on the order modal .... [FE · OPEN? · 08-11]
│       ├── "Trace" tab + backward lineage tree UI
│       │   (barcode_trail_visualization.html is a static
│       │    mockup with no data binding) ............. [FE · OPEN? · 08-11]
│       └── OrderTrace / OrderReturn Dart models ...... [FE · OPEN? · 08-11]
│
├── DELIVERY CHALLANS ─────────────────────────────────────── [full stack]
│   ├── Challan screen (delivery_challan_screen.dart, 6.8k lines)
│   │   ├── Single list + "Compare in/out" toggle ..... [DONE 08-25]
│   │   ├── Derived per-order report replacing the manual
│   │   │   statement — the other half of the rework .. [FS · OPEN✓ · 08-24]
│   │   ├── Decide: does it replace ChallanInvoice-
│   │   │   ReconciliationScreen or feed it? ......... [-- · OPEN? · 08-24]
│   │   ├── Third preview column should close on re-click [FE · OPEN? · 08-15]
│   │   └── Remove the company-profile challan template
│   │       (duplicates the Profile section) ......... [FE · OPEN? · 08-15]
│   ├── Challan lines
│   │   ├── Lot-selection UI at pack/issue time
│   │   │   (columns + DISPATCH_PACKED linking landed
│   │   │    in migration 039; the picker did not) .... [FE · OPEN? · 08-27]
│   │   ├── Reception lines must record units of what
│   │   │   came in .................................. [BE · OPEN? · 08-25]
│   │   └── Reception challan → client order link is never
│   │       persisted (columns exist, forced null for
│   │       non-delivery types) ...................... [BE · OPEN? · 08-11]
│   ├── Invoices ..................................... [FS · DEFER · 08-24]
│   │      "we are not taking invoice as of now" — INV- codes are
│   │      minted and an Invoice Generated stage exists, unused.
│   └── Challan Mobile (apps/challan_mobile)
│       ├── Capture thickness at challan / add-item time
│       │   (grep: zero hits in purchase_wizard_screens) [FS · OPEN✓ · 08-24]
│       ├── Derive sheet dimensions + factory surface
│       │   area from thickness × weight × density .... [FS · OPEN✓ · 08-24]
│       ├── Pick item and its values in one pass — the
│       │   desktop Material input type landed 08-25,
│       │   the mobile single-motion flow did not ..... [FS · OPEN? · 08-24]
│       ├── How density resolves on mobile — question
│       │   never answered ........................... [-- · OPEN? · 08-25]
│       └── Fresh-install sync: token lives in memory
│           only, server URL never persisted, sqflite
│           repo is dead code ........................ [FS · OPEN? · 07-30]
│
├── INVENTORY ─────────────────────────────────────────────── [full stack]
│   ├── Inventory screen (inventory_screen.dart, 13.9k lines)
│   │   ├── Grouped card view by category / master group
│   │   │   (cards exist for items mode only) ......... [FE · OPEN? · 08-11]
│   │   ├── Extend the card/list toggle to Groups + Sets [FE · OPEN? · 08-11]
│   │   ├── Finished-goods origin (pipeline, order,
│   │   │   operator, timestamp) on the row model ..... [FS · OPEN? · 08-11]
│   │   ├── Deep link from a card to the origin order
│   │   │   modal .................................... [FE · OPEN? · 08-11]
│   │   └── Decoupled sheet cards with vendor code +
│   │       barcode ................................... [FS · OPEN? · 08-11]
│   ├── Item view modal (_InventoryDetailSheet, ~20 flat rows)
│   │   ├── Cut to arrival + orders + children ........ [FS · OPEN✓ · 08-24]
│   │   ├── "Linked demand" is a count, not a clickable
│   │   │   list (verified at line 6441) ............. [FS · OPEN✓ · 08-24]
│   │   └── Child barcodes render as inert chips — no
│   │       weight, no drill-down (verified 6452) .... [FE · OPEN✓ · 08-24]
│   ├── Sets in Inventory
│   │   └── Temporary sets from the assembly node, with
│   │       provenance and an in/out ledger .......... [FS · OPEN? · 08-15]
│   ├── Stock model
│   │   ├── Consumption is not tied to a vendor batch —
│   │   │   no lot / FIFO drawdown ................... [BE · OPEN? · 08-11]
│   │   └── Job-work OUT movement when a temporary set is
│   │       assigned to a worker ..................... [BE · OPEN? · 08-15]
│   └── Product Lookup  ← the investigation spine
│       ├── No such screen exists anywhere (grep: 0) .. [FS · OPEN✓ · 08-24]
│       ├── Unified GET /api/trace/:barcode consumed by
│       │   Lookup, the inventory modal and the ledger  [BE · OPEN✓ · 08-24]
│       └── "Barcode not found" must become a link, not
│           a dead end .............................. [FE · OPEN✓ · 08-24]
│
├── PRODUCTION & PIPELINES ────────────────────────────────── [full stack]
│   ├── Pipeline builder (pipeline_builder_screen.dart, 5k lines)
│   │   ├── Declutter the node panel — field relevance by
│   │   │   node kind, rare settings behind disclosure  [FE · OPEN✓ · 08-24]
│   │   │     └ open: which fields are the clutter? needs
│   │   │       the requester pointing at the screen.
│   │   ├── Ask rejection-node vs scrap-node, then the
│   │   │   destination group (no scrapKind field
│   │   │   exists; inferred from step type today) .... [FS · OPEN✓ · 08-24]
│   │   ├── Carry that split through to reconcile time
│   │   │   (`ponytail:` note still live at
│   │   │    process_node.dart:69) ................... [FS · OPEN✓ · 08-24]
│   │   ├── Per-panel save-state: Unsaved → Saving →
│   │   │   Saved .................................... [FE · OPEN✓ · 08-24]
│   │   ├── Save navigates back to the pipelines screen
│   │   │   (_saveAndNotify:1323 has no onBack; delete
│   │   │    at :1365 does — the hook exists) ........ [FE · OPEN✓ · 08-24]
│   │   ├── Two save paths (_savePipeline, _saveTemplate)
│   │   │   must get the same treatment ............. [FE · OPEN✓ · 08-24]
│   │   ├── Die/machine attached at pipeline level must
│   │   │   appear for dropping onto any node ........ [FS · OPEN? · 09-07]
│   │   ├── Un-assign a pipeline picked by mistake .... [FE · OPEN? · 09-07]
│   │   └── Quick-create input material: item not saved,
│   │       and unit is always "box" — "not working for
│   │       several months" ......................... [FS · OPEN? · 09-07]
│   ├── Scratch block builder  (whole arc lives in a React/HTML prototype)
│   │   ├── Block grammar + persistence format ........ [FS · PROTO · 09-02]
│   │   ├── On-the-fly creation of die / machine / item /
│   │   │   raw material inside pipeline creation ..... [FS · PROTO · 09-02]
│   │   ├── Die-to-stage assignment on the canvas ..... [FE · PROTO · 09-02]
│   │   ├── Client blocks stacked over a die / stock ... [FE · PROTO · 09-02]
│   │   ├── Hand-off from the block canvas into the
│   │   │   per-node editor .......................... [FS · PROTO · 09-02]
│   │   ├── Horizontal production+pipeline editing ported
│   │   │   back into Flutter ........................ [FE · PROTO · 09-02]
│   │   ├── Stacked node metrics (die/machine/scrap/item) [FE · PROTO · 09-03]
│   │   ├── Editable node entities, n of each ......... [FE · PROTO · 09-03]
│   │   ├── "Zip" the block UI so a canvas works ...... [FE · PROTO · 09-02]
│   │   └── Matrix prototype (asked for, session ended)  [FE · OPEN? · 09-02]
│   ├── Runs
│   │   ├── Standalone runs producing variation items
│   │   │   mint nothing — add output_variation_leaf_
│   │   │   node_id + the operator picker ............ [FS · OPEN? · 08-27]
│   │   ├── Two run tables (production_runs INTEGER vs
│   │   │   pipeline_runs TEXT) never reconciled;
│   │   │   dispatch and lineage sit on different rails [BE · OPEN? · 08-11]
│   │   ├── delivery_challan_items.production_run_id
│   │   │   reads 0 in live data — nobody uses the picker[FS · OPEN? · 08-25]
│   │   ├── Widget test for _OutputVariationDialog —
│   │   │   skeleton left as comments ................ [FE · OPEN? · 08-27]
│   │   └── Rejections from the assembly node landing on
│   │       the worker's card ........................ [FS · OPEN? · 08-15]
│   └── Master data (per pipeline)
│       ├── Input/output accounting table: type, weight,
│       │   qty | output, scrap + scrap-to-account,
│       │   rejection as % of weight, weight loss ..... [FS · OPEN? · 08-19]
│       ├── Matching rule: variant selection + data
│       │   attached to variant and pipeline .......... [BE · OPEN? · 08-19]
│       ├── Per-pipeline insight inside the order modal
│       │   under Track .............................. [FS · OPEN? · 08-19]
│       ├── Stage names grepped from pipeline stage nodes[FS · OPEN? · 08-19]
│       └── Cost derivation from master data — open
│           question, never answered ................. [-- · OPEN? · 08-22]
│
├── SHEET PLANNING ────────────────────────────────────────── [full stack]
│   ├── Steps 2 and 3 of the workflow (only step 1 built) [FS · DEFER · 08-21]
│   ├── Per-node sheet planning, carried forward to the
│   │   next node .................................... [FS · OPEN? · 09-03]
│   ├── Import die / CAD (DXF, DWG) dimensions — parser
│   │   exists, entry point into the planning UI does not[FS · PART  · 08-21]
│   │     └ blocked: no real sample file from the client yet
│   ├── Explain or rename "kerf" and "edge trim" ...... [FE · OPEN? · 08-21]
│   ├── Colour-coded distinction between cut sizes .... [FE · OPEN? · 08-21]
│   ├── Region-targeted cut prompt (undrawn region vs
│   │   row vs existing column) ...................... [FE · OPEN? · 08-21]
│   ├── Per-strip work lost when switching columns .... [FE · OPEN? · 08-21]
│   ├── Alternative 3D sheet view (never settled) ..... [FE · OPEN? · 08-20]
│   └── Animate stage-to-stage transformation for the
│       client ....................................... [FE · OPEN? · 09-03]
│
├── PM / NODE CONFIGURATOR ────────────────────────────────── [frontend only]
│   │    Screen + domain + widgets exist; grep finds no backend route.
│   ├── Any backend model, persistence or API .......... [BE · OPEN✓ · 09-06]
│   ├── Node "happening" — the yield/consumption maths .. [FS · DEFER · 09-06]
│   ├── Marketplace: per-client node catalogues, save a
│   │   node for reuse ............................... [FS · OPEN✓ · 09-06]
│   ├── Scrap vs rejection capture on the node ......... [FS · OPEN✓ · 09-06]
│   ├── Per-entry unit override on loss quantities ..... [FS · OPEN✓ · 09-06]
│   └── Create a new process on the fly ............... [FS · OPEN✓ · 09-06]
│
├── MASTERS (Configurator) ────────────────────────────────── [full stack]
│   ├── Items
│   │   ├── Item + expression: backend persistence of
│   │   │   created items/properties/values ........... [BE · OPEN✓ · 09-07]
│   │   ├── Audit entry "user X made this value on the
│   │   │   fly" ..................................... [BE · OPEN✓ · 09-06]
│   │   ├── Auto-named placeholder property for overflow
│   │   │   "+" values ............................... [FS · OPEN? · 09-06]
│   │   ├── Roll the grammar out to every item selector
│   │   │   in the app (absent from component groups) . [FE · OPEN? · 09-07]
│   │   ├── Number / material sub-entry inline in the
│   │   │   same field — no popup, no second field .... [FE · OPEN? · 09-07]
│   │   ├── Compulsory value codes with legible errors . [FS · OPEN? · 08-25]
│   │   ├── Gauge still stores verbatim suffixed strings
│   │   │   with no unit metadata ..................... [FS · OPEN? · 08-25]
│   │   ├── Proper materials view inside create-variant  [FE · OPEN? · 08-25]
│   │   ├── Club "generated" and "spawned" variant into
│   │   │   one concept ............................... [FS · OPEN? · 08-19]
│   │   ├── Variation creation collapsed to 3 steps with
│   │   │   an edit column ............................ [FE · OPEN? · 08-19]
│   │   ├── Multi-select spawned variants for bulk group
│   │   │   filing .................................... [FE · OPEN? · 08-14]
│   │   ├── Bin icon on spawned-variant rows .......... [FE · OPEN? · 08-14]
│   │   ├── Group selector in the variant view modal, to
│   │   │   move one variant singly ................... [FS · OPEN? · 08-24]
│   │   └── "Component" as a fourth toggle beside Items /
│   │       Item groups / Sets ....................... [FE · OPEN? · 09-06]
│   ├── Groups
│   │   ├── Inheritance drawn as inherited group ROWS in
│   │   │   the main screen, items only at the last level
│   │   │   — restated three times in 20 minutes ...... [FE · OPEN? · 08-25]
│   │   ├── Group view (read-only) distinct from the edit
│   │   │   dialog ................................... [FE · OPEN? · 08-23]
│   │   ├── Card view with a most-used-items collage ... [FE · OPEN? · 08-23]
│   │   ├── Group-type colours echoed on the creation
│   │   │   rows, so the user learns the mapping ...... [FE · OPEN? · 08-25]
│   │   ├── Collapse variants under an item until clicked[FE · OPEN? · 08-25]
│   │   ├── Combination-group creation asks for an
│   │   │   optional parent group ..................... [FS · OPEN? · 08-24]
│   │   ├── Enforce: combination groups on variants only,
│   │   │   never on base items ...................... [FS · OPEN? · 08-24]
│   │   ├── On-the-fly group creation while filing
│   │   │   variants is broken ....................... [FS · OPEN? · 08-19]
│   │   └── Real-time push of group/item counts ....... [FS · OPEN? · 08-25]
│   ├── Component groups  ← the live front, re-scoped 09-07
│   │   ├── Move the whole BOM / pipeline / die / machine
│   │   │   workflow off Sets onto component groups ... [FS · PART  · 09-07]
│   │   ├── Bento / Pinterest no-scroll creation form,
│   │   │   sections collapsing as they complete ...... [FE · OPEN? · 09-09]
│   │   ├── Section order: details → permissions → item →
│   │   │   pipeline → machine & dies ................ [FE · OPEN? · 09-09]
│   │   ├── Rename section 2 to Options / Permissions .. [FE · OPEN? · 09-09]
│   │   ├── Per-item permission selection in the form ... [FS · OPEN? · 09-09]
│   │   ├── Kanban lineage columns, as explored for sets  [FE · OPEN? · 09-07]
│   │   ├── Machine / die on-the-fly creation + linking . [FS · OPEN? · 09-07]
│   │   ├── Client field on the creation header ........ [FS · OPEN? · 09-07]
│   │   ├── Stepper (Next, not Save) across edit group →
│   │   │   items → pipeline → machine/dies ........... [FE · OPEN? · 09-07]
│   │   ├── Assignment needs two clicks to render —
│   │   │   regressed after a claimed fix, root cause
│   │   │   never established ........................ [FE · OPEN? · 09-09]
│   │   ├── Dialog width mismatch ..................... [FE · OPEN? · 09-09]
│   │   └── Unidentified runtime error raised at the end
│   │       of the last session, never diagnosed ...... [?? · OPEN? · 09-09]
│   ├── Sets
│   │   ├── Set-level editing toolbox — edit master data
│   │   │   for all members at once, or singly ........ [FE · OPEN? · 09-06]
│   │   ├── Set view modal reported broken ............ [FE · OPEN? · 09-06]
│   │   ├── Set image upload (asked twice) ............ [FS · OPEN? · 08-17]
│   │   ├── Save a set composed inside the item wizard .. [FS · OPEN? · 08-14]
│   │   ├── Per-item property popup when ordering a
│   │   │   hierarchical set ......................... [FS · OPEN? · 08-14]
│   │   ├── Items/sets toggle relabelling the order
│   │   │   section, picker swapping in place ........ [FE · OPEN? · 08-14]
│   │   ├── Three-column sliding entry: trigger on scroll,
│   │   │   slower animation, never ellipsise ........ [FE · OPEN? · 08-15]
│   │   └── Hamburger drag-reorder on the added list ... [FE · OPEN? · 08-15]
│   ├── Materials
│   │   └── Material master card view with images ...... [FE · OPEN? · 08-22]
│   ├── Units
│   │   └── Global (not-installed) units available for
│   │       conversion AND for recording major events,
│   │       via a slim searchable dropdown ........... [FS · PART  · 08-22]
│   ├── Machines
│   │   ├── Average idle-time dot + tooltip — fully
│   │   │   greenfield, no activity log exists ........ [FS · DEFER · 08-11]
│   │   ├── Battery queue icon + queue popup — needs
│   │   │   machine_id on runs, created_by, run weight  [FS · OPEN? · 08-11]
│   │   ├── Stroke-cycle counting ..................... [FS · DEFER · 08-11]
│   │   ├── Die-wear percentage ...................... [FS · DEFER · 08-11]
│   │   ├── Info bubble on the battery button, placed in
│   │   │   the barcode row or top-right ............. [FE · OPEN? · 08-17]
│   │   └── Blockwork stacking of process/machine masters,
│   │       any master nestable in any other .......... [FS · OPEN? · 09-02]
│   │         ├ relational table recording the stacking  [BE · OPEN? · 09-02]
│   │         ├ analytics overlook on customer stacks .. [BE · OPEN? · 09-02]
│   │         └ retire the line map ................... [FE · OPEN? · 09-02]
│   ├── Dies
│   │   └── Remove "strokes per piece" from the die modal [FE · OPEN? · 08-19]
│   └── People
│       └── Department-first flow, Add Employee inside the
│           selected department's right column ....... [FE · OPEN? · 08-17]
│
├── PLATFORM / KERNEL ─────────────────────────────────────── [full stack]
│   ├── Module evacuation: 1 of 16 modules marked
│   │   evacuated (items). 15 still live in legacy .... [BE · OPEN✓ · 07-27]
│   ├── Units = second evacuation, designed in doc 01,
│   │   not started ................................... [BE · OPEN✓ · 07-29]
│   ├── Contract guard is still LOG-ONLY — "without
│   │   mutating or rejecting anything"; the enforcement
│   │   flip is pending (kernel/contracts.js:8) ...... [BE · OPEN✓ · 07-27]
│   ├── Local-first
│   │   ├── Replica must cover every module's CRUD, not
│   │   │   the 13 tables it holds ................... [FS · OPEN? · 09-01]
│   │   ├── No endpoint fetches a variation node by id —
│   │   │   the delta engine cannot resolve those events[BE · OPEN? · 09-01]
│   │   ├── Capture the raw Map before DTO parse, in every
│   │   │   replicated module (read DTOs have no toJson)[FE · PART  · 09-01]
│   │   ├── Changelog retention / pruning job ......... [BE · OPEN? · 09-01]
│   │   ├── Trigger suppression during seed and wipe ... [BE · OPEN? · 09-01]
│   │   └── Tier 4 — queued offline writes with conflict
│   │       resolution ............................... [FS · DEFER · 09-01]
│   │         (out of scope by design: barcode_ledger is
│   │          append-only, so an optimistic event that
│   │          failed to land would be a lie it cannot retract)
│   ├── Barcodes
│   │   ├── Floors and locations (FLR / LOC) as
│   │   │   resolvable places ........................ [FS · OPEN? · 08-26]
│   │   ├── /api/barcode/lookup must return vendor_id,
│   │   │   not just vendor_name ..................... [BE · OPEN? · 08-11]
│   │   ├── Multi-up A4 label sheets built but unwired
│   │   │   to any screen ............................ [FE · PART  · 08-26]
│   │   ├── Asset plates + personnel ID badge formats .. [FE · OPEN? · 08-26]
│   │   ├── Hardware scanner-gun keystroke-wedge test
│   │   │   never run ................................ [-- · OPEN? · 08-26]
│   │   ├── Manual end-to-end walkthrough never reported
│   │   │   as run ................................... [-- · OPEN? · 08-26]
│   │   └── Notes and reports remain unscannable ...... [FS · DEFER · 08-26]
│   ├── Search
│   │   ├── Match across tokens, not exact ............ [FS · OPEN? · 08-15]
│   │   └── Dropdowns anchored near their field
│   │       (repeat complaint, never properly fixed) .. [FE · OPEN? · 09-07]
│   ├── Performance
│   │   └── i3 / 8 GB / no GPU still lags with almost no
│   │       UI drawn; only a reduced-effects toggle
│   │       followed ................................. [FE · OPEN? · 08-26]
│   ├── Deployment
│   │   └── Safe deploy + a "canal" bridging client and
│   │       dev updates .............................. [BE · OPEN? · 08-25]
│   └── Cross-cutting cleanups (doc 02 §C)
│       ├── `groupName.contains('raw material')` ...... [FIXED 08-25]
│       ├── Scrap routing keyed on a group literally
│       │   named "Scrap" (pipeline_builder:2068) .... [FE · OPEN✓ · 08-24]
│       └── materials.type is free text with no FK to
│           material_types .......................... [BE · OPEN? · 08-24]
│
└── DOCS & SIMULATION ─────────────────────────────────────── [--]
    ├── SIMULATION_PLAYBOOK.md exists as a 127-line draft
    │   describing real behaviour, but carries only two
    │   code blocks — the "exact CLI scripts, sqlite seed
    │   templates and manual GUI sequences" asked for are
    │   not in it .................................... [-- · PART  · 08-11]
    ├── Dependency atlas covering "every single detail"
    │   of the whole app (dependency-atlas.html was
    │   produced; he reported it "didnt open") ........ [-- · PART  · 08-15]
    ├── POST /dev/seed-manufacturing-demo is completely
    │   ungated — no requireAuth, no requireRoles, no
    │   requirePermission (server.js:27810) — and
    │   duplicates rows on every call ................ [BE · OPEN✓ · 08-11]
    └── Images on every master for the one-year scenario [-- · OPEN? · 08-17]
```

## Closed since it was raised — verified against the code

These appear in the transcripts as open asks and are **done**. Recorded so they
are not re-opened by a future reading of the same sessions.

| Ask | Evidence |
|---|---|
| Machine barcode on the card | `machine.dart:71` |
| Per-sheet typed weights + printable sheet barcodes | commits `68b8eed`, `fcee07d` |
| Material as a fourth input type storing `material_type_id` | migration `035` |
| Universal barcode codec, 17 types, append-only ledger | `kernel/barcodes.js`, migration `038` |
| Lot-level dispatch columns on challan lines | migration `039` |
| Order reconciliation traversal | `GET /api/orders/:orderNo/reconciliation` |
| `order_returns` + backward trace endpoint | `server.js:5648`, `:26712` |
| Challan screen collapsed to one list + compare toggle | `delivery_challan_screen.dart:286` |
| gzip compression on every response | `server.js:639` |
| Changelog by SQLite trigger, not by hand | migration `040` |
| SSE change stream | `GET /api/events` |
| Local-first repositories for items, challans, orders, inventory | all four present |
| Vendor return as an internal challan subtype, with a mobile scan screen | `internal_subtype` column + `vendor_return_screen.dart` |
| Set member quantity persisted | `inventory_set_lines.quantity` |
| Sets expand into order lines carrying set provenance | `order_entry.dart:36-38` |
| One shared `GroupPickerField` across six screens | `group_picker_field.dart` |
| Usage telemetry derived from the existing audit trail | `telemetry-usage.test.js` |
| MS (mild steel) added to the material handbook | migration `037` |
| Scenario A and Scenario B simulation seeders | `ensureSimulationScenario`, `server.js:29961` |
| Assign-stock filter keyed on `materialClass`, not a group name | `inventory_sidebar.dart:112` |

## The five questions that block design

From doc 02, still unanswered, and each one gates work above:

1. **§4a** — true sheet *dimensions* (needs width or length as a second input),
   or is *surface area* the goal? Assumed area.
2. **§2.2** — is scrap-vs-rejection a property of the **node** or of each
   **destination**? Can one node emit both? Assumed the node.
3. **§3** — does "processed for an order" mean **allocated**, or only
   **actually consumed**? Assumed consumed.
4. **§5** — does the derived report live on the **order** or stay on the
   **challan tab**? *(Answered 08-25: on the order.)*
5. **§2.1** — which specific fields are the clutter in the node panel? Cannot be
   guessed; needs the requester pointing at the screen.

## Suggested sequencing

Unchanged from doc 02, because nothing since has invalidated it:

```
4b  Material as a typed variation value      ← DONE
 │
4a  Thickness on mobile + surface area       ← next; 4b gave it density
 │
1   Unified trace endpoint + Product Lookup  ← the investigation spine
 │
3   Inventory modal rebuilt on that endpoint ← reuses 1's backend
 │
5   Challan derived report                   ← safest once 1 & 3 prove the joins
 │
2   Pipeline node panel                      ← no data dependency; any time
```

One caveat that still holds: **§1 is a prerequisite for §5, not a peer.** The
assign-stock filter bug is fixed, but only material assigned *from now on* has
consumption history. A per-order statement built today will be structurally
right and empty for every order placed before assignments started being
recorded.
