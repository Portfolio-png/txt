# Universal barcode & QR ecosystem — what exists

Status as of 2026-08-26. The probe that preceded this is in
`02-bathroom-thoughts-2026-08-24.md` §"Barcode probe (2026-08-26)"; this file
records what was actually built, and — more usefully — what was not.

## The shape of it

One resolver answers for every kind of code, so the scanner gun does not have to
know what it is pointed at and neither does the person holding it.

```
receive → mint → issue to run → scan anywhere → read the trail → walk it → reprint
```

## Codes are derived, not minted

`backend/kernel/barcodes.js`. A code is `TYPE-ID-CHECK`, computed from the row
that already exists rather than allocated from a counter.

- **17 entity types** — MAT, DC, RC, DCL, ORD, RUN, MFG, EMP, DEP, PLN, CLI,
  VEN, MCH, DIE, ITM, GRP, MOV.
- **No collisions are possible.** The probe measured the previous scheme at 41%
  of workspaces colliding by 100 parents and 99.3% by 300 — 5183 duplicate
  parents in 20000 mints. Deriving from the primary key removes the birthday
  problem rather than making it rarer.
- **Position-weighted check character**, so a misread is detected rather than
  silently resolving to a different real record.
- **`LEGACY_SOURCES`** — codes already printed on physical stock
  (`materials.barcode`, `machines.barcode`, `employees.barcode_id`,
  `dies.tool_code`, `items.short_code`, `production_runs.run_code`,
  `delivery_challans.challan_no`, `order_headers.order_no`) still resolve, and
  the resolver says they did so by fallback and offers the canonical code.

**Resolution is `COLLATE NOCASE`.** Codes are uppercased on the label but
`pipeline_templates.id` is `sheet-metal-flow`. Caught by test, not in the field.

## The trail is append-only

`backend/migrations/038-barcode-ledger.sql`. Business tables are rewritten in
place and can only say what is true *now*. The ledger says who touched a thing,
when, on what paperwork, and what it became — the question asked when a client
returns a defective part.

Enforced by SQLite triggers that `RAISE(ABORT, …)` on UPDATE and DELETE, not by
convention. Factory Reset drops and recreates them around the wipe; that
exemption is written visibly in `clearAllData` and a test asserts protection is
restored afterwards.

**Emitted:** `INWARD_RECEIVED` (also naming the vendor as a parent),
`ISSUED_TO_PIPELINE` (now from all three issue branches — SKU, quantity and
sheet), `DISPATCH_PACKED`, `STAGE_PROCESSED`, `OUTPUT_MINTED`, `LOCATION_MOVED`,
`INVOICED`, `CUSTOMER_RETURN`.

**Deliberately refused**, because the concept is not modelled and an event
invented to complete a checklist writes a lie into a table that cannot be
corrected:

- `CLIENT_DELIVERED` — `delivery_challans` has exactly three statuses
  (`draft`, `issued`, `cancelled`) and no `delivered_at`, `received_at` or
  acknowledgement route anywhere. "Goods reached the client" has no
  representation. Hanging it on `issued` would just be a second name for
  `DISPATCH_PACKED`.
- `GENESIS_PURCHASE` — there is no purchase concept distinct from a reception
  challan. `delivery_challans.type` is `{delivery, reception, internal}`; the
  mobile "Purchase" tile creates a reception challan, and the wizard calls
  create-then-issue back to back, so the event would land at the same instant as
  `INWARD_RECEIVED`. Two events describing one moment make the trail less
  readable. The vendor link that motivated it now rides on `INWARD_RECEIVED`
  instead, which is one row rather than two.

### What each event is careful about

- **`STAGE_PROCESSED`** — the subject is the RUN, not the materials. The payload
  is a stage aggregate (5.5kg allotted, 5 out, 0.2 scrap) and nothing splits it
  per input, so a material subject would write three rows each claiming the
  stage produced 5. The materials are named as parents instead, and `loadCustody`
  matches parents, so scanning one still surfaces the stage.
  Two clients PUT to this route: the reconciliation dialog sends the whole
  booking with timestamps, the inline metric box sends one key. Only a full
  booking counts as the stage being worked; a single-key edit counts only once
  the stage has actually been booked, and is marked `revised`. A re-save that
  changes nothing writes nothing — `stage_reconciliations` is an UPSERT that
  converges to one row, but the ledger cannot.
- **`OUTPUT_MINTED`** — the subject is the MFG code, because that is what gets
  printed on the finished piece and scanned off it later. Mirror of
  `ISSUED_TO_PIPELINE`, where the material is the subject and the run is a child.
- **`LOCATION_MOVED`** — only `transfer`, and only when the two ends differ.
  `receive`/`consume`/`issue` are already told by the events that cause them.
  Locations are strings, not records, so there is no `LOC` type to point at and
  both ends go into metrics — an honest amputation, not an invented entity.
- **`INVOICED`** — the subject is the challan, not the invoice: an invoice is
  not a thing anyone holds and scans. Once per distinct challan, not once per
  line, and only on creation.

## The two stock models, and the bridge

The gap that made orders untraceable: `variation_stock` counts item+variation,
`materials` names a physical piece. They did not meet, and inbound material
carried `'-' // legacy barcode`.

- **Reception mints.** `mintReceivedMaterial` writes both a `materials` row and
  an `inventory_stock_positions` row — the second because
  `assertInventoryQuantityAvailable` reads positions, and minting the material
  alone left Assign Stock refusing with "Insufficient stock. Available: 0".
  Idempotent via `source_challan_item_id`.
- **Production consumes by quantity.** `POST /runs/:id/barcodes` has a
  `source_kind='quantity'` branch, because a workshop issues 40kg of a coil, not
  40 barcoded pieces.
- **The bridge column** names the challan line a consumption came from, so
  `buildOrderReconciliation` can trace inbound and reports `coverage`
  (`untracedBarcodes`, `inboundTraceable`) rather than implying completeness.

## Reading a scan

`GET /api/scan/:code` returns one envelope whatever was scanned. The client
renders it in `universal_barcode_inspector_dialog.dart`.

What the screen is careful about is **honesty**. A scan that failed its check
character, one found by an old label, and one that matched nothing look
superficially alike, and the whole value of the resolver is lost if they render
the same:

- a **misread** shows the record but says "check it is what you are actually
  holding" — refusing outright is less useful;
- a **legacy** hit says so and offers the canonical code for reprinting;
- **not found** distinguishes *ours* (deleted, or another workspace) from a
  *supplier's own label*. The old lookup could not draw that distinction, which
  is why scanning a sheet you were holding was indistinguishable from scanning
  gibberish;
- an **unknown event type** renders verbatim rather than being dropped, because
  a workshop will record something this build has never heard of.

Every barcode the trail mentions is a step you can take, so the panel is a
walkable chain rather than a list.

## Getting a code in

- **The scanner gun works anywhere.** A gun *is* a keyboard; only speed
  separates it from typing. `ScanBuffer` holds that judgement, kept out of the
  widget so it can be tested without faking a keyboard. Too eager and the
  listener fights every text field in the app; too strict and a real scan
  silently does nothing.
- **`Ctrl/Cmd+B`**, and a scan button in the top bar — for a code read by eye
  off a smudged label that the gun refuses.
- **`Ctrl/Cmd+K`** search still resolves a typed code through the same path.

## Getting a code out

`barcode_label_service.dart`. Until this existed the codes were real but
invisible — bookkeeping, not tracking.

- Six stocks; **the stock is chosen by what was scanned** (sheet → sticker,
  crate → shipping label, machine → plate, person → badge), because picking the
  roll by hand every time is how the wrong one ends up loaded.
- **Code 128 by default** (the floor uses guns, which read 1D fastest), **plus a
  QR** where the stock has room (someone at a machine in a corner has a phone).
  A code Code 128 cannot encode falls back to QR instead of throwing mid-run.
- **Tiling arithmetic floors, never rounds.** Label stock is bought in rolls; a
  layout that overhangs ruins every sheet and is discovered after the run.
  Stock larger than the page falls back to one-per-page rather than dividing by
  zero.
- Reprinting is offered **even when the scan resolved to nothing**, because the
  usual reason to reprint is that the sticker is unreadable — which is exactly
  when the scan fails.

**Known limitation, pre-existing and app-wide:** every PDF in this app
(challans, invoices, reports, labels) uses the PDF built-in Latin-1 fonts, so a
title outside Latin-1 loses characters. For labels this degrades gracefully —
the code is uppercase ASCII by construction, so the label still scans. Fixing it
properly means bundling a Unicode TTF and touching every PDF path.

## Three real defects found and fixed while wiring the events

These were pre-existing. They are recorded because each would have quietly
corrupted the trail rather than failing loudly.

1. **The seeders were writing custody.** `issueDeliveryChallan` carries the
   `INWARD_RECEIVED` / `DISPATCH_PACKED` emit, and the demo and scenario seeders
   call it five times. Every reseed poured invented history into a table whose
   triggers forbid UPDATE and DELETE, so it could never be cleaned out. Fixed
   with a `recordCustody` option, false at all five seeder call sites. A trail
   that is part fiction is worse than no trail, because people act on it.

2. **`run_code` collided for 94% of runs.** It was derived from the first eight
   characters of the pipeline run id, and on the real database 68 of 72 run ids
   began `run-ord-`. Since `production_runs.run_code` is UNIQUE, the first run to
   finish took the code and an `if (!exists)` check silently swallowed the other
   67 — real goods completed with no `production_runs` row, no lot, no movement.
   It also made the MFG barcode a lie: one code naming 68 different runs' output.
   Now derived from the whole id. A derived code is only safe when what it
   derives from is unique.

3. **A dispatch named a class of goods, never an instance.** The event recorded
   an item id and a variation, so scanning a delivered piece reached "some of
   this kind of thing" and stopped — the run, the material and the vendor were
   all unreachable from the customer end, which is the end complaints arrive at.
   `delivery_challan_items.production_run_id` was already written at save and
   validated at issue, and is now named as a parent. That closes the walk.

   The same emit also sat inside the per-line loop, so a twelve-line consignment
   wrote twelve rows differing only in metrics. A dispatch is now one event with
   the lines summarised, built from the challan's lines rather than from the
   stock loop — a document-only challan still dispatches goods, it just does not
   track them.

## The 'leaf' kind that never existed

`OUTPUT_MINTED` had never fired once, and the reason was three layers down.

Completing a run looked up the variation it had produced with:

```sql
SELECT * FROM item_variation_nodes WHERE item_id = ? AND kind = 'leaf' LIMIT 1
```

`kind` has only ever held `'property'` or `'value'`. There is no `'leaf'` kind
and never has been, so the query never matched, `variationLeafNodeId` stayed 0,
`resolveOrderVariationSelection` threw *"Client, item, and variation values are
required"*, and the whole `node-status` request came back 500. **No run could
finish and no finished goods ever entered inventory.**

It was also a guess even when it appeared to work: `LIMIT 1` with no ordering
picks an arbitrary variation, which would have stamped the wrong one onto real
goods.

The variation now comes from the order line the run is assigned to — the only
place that actually knows — and only when that line is for the same item the
template says it outputs, so one item's variation is never stamped onto
another's.

**The throw itself was not the bug.** `resolveOrderVariationSelection` already
returns the base item cleanly for items with no variation properties; it throws
only when an item *has* variations and none was chosen, which is exactly what
should stop a half-specified order line. Catching it broadly would have silently
turned every unspecified line into the base item. Instead the run now completes
either way, and mints only when the output is genuinely identifiable — a
mislabelled lot is permanent, a missing one is recoverable.

Alongside it: every finished lot in the system was literally named
`"Finished Good"`, because the insert read `snapshot.fullName` and the snapshot
has no such field. It returns `particulars`.

## Places: the one type with no records behind it

`LOC` and `FLR` resolve, but they are not record-backed like the other 17. A
location is a free-text string on `inventory_stock_positions`; a floor is one on
`machines`. There is no `locations` table and no `shop_floors` table.

They are modelled anyway — rather than refused the way `CLIENT_DELIVERED` was —
because the places are real and already consistently named in the data
(`Cutting bay`, `Rack A1`, `MAIN`). Someone can print a sticker for a rack today.
What is missing is a record, not the thing. `place: true` marks them, and when
locations do become records only the spec changes.

Two things this needed:

- **Matching by normalised value, not by key.** A code strips whitespace, so
  `Cutting bay` travels as `CUTTINGBAY` and no column compare would ever find
  it. Done in JS with the same `normalize` that produced the code, because
  SQLite's `REPLACE` handles one character at a time.
- **`loadCustody` matching `location_barcode`.** A location is never a subject,
  a parent or a child — a rack does not descend from anything — so without it a
  scanned rack resolved and then showed an empty history, which reads as
  "nothing ever happened here" rather than "this view cannot see it".

Scanning a place reports what is on it: materials and quantities for a rack,
machines and their status for a floor. Being told "this is a rack" would be
worse than not resolving at all.

## Closing the circle (migration 039)

Both remaining gaps were the same shape: a fact that exists in the world had
nowhere to live in the schema, so the code either guessed it or dropped it.

**What a standalone run is making.** A run tied to an order line knows its
variation; a run started to build stock did not, and completing one declined to
mint rather than guess. `pipeline_runs` now carries
`output_variation_leaf_node_id` / `output_variation_path_label`, and resolution
runs in a strict order:

> the assigned order line → the run's own stated target → don't guess

The order line wins when both exist, because it is what was promised to a
customer; the run's target is one person's intent at the machine. Declining
stays the floor, and the operator is asked at deploy time only when there is
something to ask — a base item, or an output this workspace does not carry as an
item, has no variation to state. The dialog's "Not sure yet" still deploys the
run: forcing an answer would stop someone starting work over a lot they could
attribute later — and an operator who cannot begin without answering learns to
answer falsely, which is permanent where an unattributed lot is not.

The prompt lives in `packages/core_erp/lib/shared/widgets/output_variation_prompt.dart`
rather than beside the console that calls it, because the app's own `test/`
directory does not compile (pre-existing) and anything left there is untestable
in practice. It is split into a pure `outputVariationChoices` and the dialog, so
the decision *is there even a question to ask?* can be checked without pumping a
frame.

That split immediately earned itself. `buildExactItemVariationReferences`
represents a base item as **one** reference with leaf id 0, not as an empty
list — so checking emptiness alone would have opened a dialog offering a single
meaningless option, on exactly the items that have nothing to state. Leaf 0 is
also what the server reads as "not stated", so choosing it would have said
nothing. The choice list now keeps only references with a real leaf.

**Which lot actually went out.** `delivery_challan_items.production_run_id` said
which run made the goods, one hop short of the question people ask — a run mints
a lot every time it completes, so "made by run 42" does not identify the thing in
the customer's hands, and a defect report starts by scanning that thing. The line
now carries `lot_code` / `material_barcode`, **derived** at issue rather than
picked in the UI: minting wrote an inventory movement naming the pipeline run, so
every existing line that names a run gets its lot with nobody re-entering
anything. It is written back, because the run may mint again tomorrow and this
line shipped this lot.

`DISPATCH_PACKED` names the lot as a parent, which completes the walk:

```
package tag → lot → OUTPUT_MINTED → run → ISSUED_TO_PIPELINE → sheet → vendor
```

Verified against a copy of the live database: all four columns and the index
applied, 72 runs and 76 challan lines intact. (The runner records
`039 … | converged` because two migration paths both process the directory and
the second tolerates "duplicate column" by design.)

## Not built

- **Multi-up A4 sheets** — now wired: the desktop material barcode dialog prints
  a parent and its linked children, one per label or tiled on A4.
- **A standalone run whose operator answers "not sure yet" still mints nothing.**
  That is the design, not a gap: guessing a variation is permanent.
- **Notes and reports are not records**, so they cannot be scanned.
- **Notes and reports** remain the only unscannable things left.

## Tests

Backend 133 passing: `universal-barcode.test.js` (12),
`barcode-ledger-events.test.js` (22), `barcode-codec-vectors.test.js` (5),
`challan-stock-bridge.test.js` (3), `order-reconciliation.test.js` (3).
Dart: `scan_buffer_test.dart` (8), `universal_barcode_inspector_test.dart` (12),
`barcode_label_service_test.dart` (19), `barcode_codec_test.dart` (8),
`search_provider_scan_test.dart` (6).

## The codec exists twice, and is kept honest from outside

`backend/kernel/barcodes.js` and
`packages/core_erp/lib/core/services/barcode_codec.dart` implement the same
scheme. Duplicated logic across two languages is a real hazard: nothing stops one
side drifting, and the symptom would be a freshly printed label the server
refuses to resolve.

So the test vectors are **generated by running the JS implementation**
(`tool/gen_barcode_vectors.js`, via `tool/regen_barcode_vectors.sh`) and pinned
on both sides — 27 encode and 59 decode cases, covering all 17 types, a failing
check character, and unverified legacy codes. A mirror checked against
hand-written expectations only proves the two agree with whoever wrote them.

If a vector test fails and you did not deliberately change the codec, **do not
regenerate** — the two sides have drifted, and regenerating papers over exactly
the bug the fixture exists to catch.

The Dart side exists so the desktop can print a **canonical** code. Printing the
raw stored id still scans, via the legacy fallback, but resolves unverified — and
a label being printed today should not be born legacy.
