# Challan Mobile — UI wording

Plain, worker-friendly words are used on screen. This file records the wording
choices and **where each appears**, so the UI stays consistent and future
changes keep the same words.

Rule of thumb: **on-screen text uses the plain word; code identifiers keep their
accurate technical names.** Don't rename providers, classes, routes, DB columns,
or backend values to match a UI word — only the displayed strings change.

---

## ⚠️ "Delete" vs "Discard" — they mean different things

In the code we deliberately separate two actions:

| Code term | Real meaning |
|---|---|
| **discard** (`_discardChallan`, `_discardWizard`) | Abandon **in-progress / unsaved** work — a challan still being built, collected lines, a wizard cart. Nothing on the server is removed. |
| **delete** | Remove a **saved** record. |

**On screen we now show the single word "Delete" for both**, because "Discard"
confused users. So the same "Delete challan?" prompt can mean two things:

- shown **while building** a challan (Use flow, Purchase wizard) → it is really a
  *discard* of unsaved work; no server record exists yet.
- shown on a **saved** challan → it is a true *delete*.

Keep the code names (`_discardChallan`, `_discardWizard`) as-is — they document
the real intent. Only the visible `Text('Delete …')` strings were changed.

---

## Wording map (on-screen word ← previous word)

| On screen now | Was | Where it shows (file · current line) |
|---|---|---|
| **Delete** / **Delete challan?** / tooltip **Delete challan** | Discard / Discard challan? | `lib/screens/use_item_screens.dart` (292, 299, 367) · `lib/screens/purchase_challan_screens.dart` (228, 235, 415, 618, 831) · `lib/screens/challan_mobile_editor_screen.dart` (784, 791, 1122) · `lib/screens/purchase_wizard_screens.dart` (69, 76, 345) |
| **Supplier** (tile, step label), **Select Supplier**, **Search suppliers…**, **No suppliers found**, **Supplier is required**, **Add suppliers in the desktop app first.** | Vendor / vendor(s) | `lib/screens/purchase_challan_screens.dart` (62, 85, 1183, 1200, 1201, 1212, 1345) · `lib/screens/purchase_wizard_screens.dart` (42, 371, 472, 489, 490, 509, 576, 1044) · `lib/screens/challan_mobile_editor_screen.dart` (1222, 1225) |
| **Photos** / **Failed to upload photos** | Attachments | `lib/screens/challan_mobile_editor_screen.dart` (674, 1332) |
| **Scan Area** | Live Dock Staging (screen title); Staging (bottom-nav label) | `lib/screens/challan_staging_screen.dart` (105) · `lib/screens/home_screen.dart` (113) |
| **Production Line** / **Line Status** | Production Pipeline / Pipeline Status | `lib/screens/production_screen.dart` (33, 531) |
| **Settle** / **Settled** / **Settle another** / tile **Settle used materials** | Reconcile / Reconciled / Reconcile another | `lib/screens/internal_use_reconciliation_screens.dart` (step label, titles, buttons, messages) · `lib/screens/purchase_challan_screens.dart` (In-use tile subtitle) · flag display name **"In-use Settle-up"** in `packages/core_erp/.../feature_flags.dart` |

Line numbers are a convenience and may drift; the on-screen string is the stable
locator (grep the quoted text).

### "Particulars" → "Item" — no UI change needed
There is **no** on-screen "Particulars" label. `item.particulars` is a code
field that already holds the **item's name**, and that name is what shows on the
line. Nothing to rename.

---

## Code names kept (NOT renamed to the UI word)

These stay as-is on purpose — renaming them would be churn and/or break wiring:

- **Vendor** → `VendorsProvider`, `VendorBrowseScreen`, `vendor_definition.dart`,
  `vendorId`, and the backend `type='vendor'` / vendor tables.
- **Discard** → `_discardChallan`, `_discardWizard` (see the note above).
- **Pipeline** → `pipelineRun`, `_buildPipelineProgress`, `_buildPipelineStatus`.
- **Reconcile** → `reconcileChallan`, `ChallanReconcileInput`, the
  `POST /api/challans/:id/reconcile` route, the `reconciliation_json` column, and
  the feature-flag **key** `challans.reconciliation` (only its display name changed).

---

## Terms kept as-is on screen (core domain or client's own words)

**Challan**, **GST / GSTIN**, **HSN**, **Barcode**, **Order**, **Client**,
**Weight**, **Quantity / Qty**, **Draft**, **Variation**, and the five settle
buckets — **Finished Goods · Leftover · Scrap · Rejection · Lost**.

## Not yet changed (candidates from the wording review)

Left as-is for now; change on request: **Consume / Consumed** (Use tile
"Consume raw materials"), **Inventory** (→ Stock?), **Issue / Issued** (→
Send / Sent?), **Reception Challan / Delivery Challan**, **Party Details**,
**Document Type**, **Delivery Location**.
