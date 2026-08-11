# Simulation Playbook — Decoupled Inventory vs. On-Demand Procurement

> Status: DRAFT. Written 2026-08-12. Walk-through scripts for demonstrating how
> the system handles realistic raw-material stock consumption. **This document
> describes how the system actually behaves today** (verified against
> `backend/server.js`), including the honest limits of what is and isn't tracked.

## 0. How stock actually moves (read this first)

Before running either scenario, know the real mechanics — the demo must not
imply tracking the system doesn't do:

- **Raw stock is aggregate.** Reception/issue update a single
  `variation_stock(item_id, variation_leaf_node_id, location_id).quantity`
  bucket via `applyVariationStockDelta` (`server.js` ~7622). There is **no
  vendor-batch / lot / FIFO dimension on the stock bucket** — a deduction just
  lowers the aggregate; it does **not** record *which* receive batch it drew
  down.
- **Per-movement provenance exists** on `inventory_movements`
  (`reference_type`/`reference_id`, `source_challan_id`/`_type`/`_line_id`,
  `actor`, `created_at`) — so each individual receive/issue can be traced to its
  challan and actor, even though the stock *bucket* can't.
- **Per-vendor-sheet lineage** is only captured when an operator **scans the
  physical sheet tag** (`piece_barcodes.parent_code`) into a production run
  (`POST /runs/:id/barcodes` sheet branch). That writes a `run_barcode_inputs`
  row with `source_kind='sheet'` + the vendor. Without that scan, run→material is
  SKU-level only.
- **Finished-good origin** (run, operator, produced-at) lands on the
  `inventory_movements` receive row (`reference_type='pipeline_run'`), **not** on
  the `materials` row. The order is a further join
  (movement → run → `order_pipeline_assignments` → order).

### Seeding a base dataset

```bash
cd backend
npm run seed:demo                 # resetAndSeedDemoData: clients, vendors, items,
                                  # orders, pipeline templates + runs, stage stock
node ./scripts/populate-challans.js   # adds reception challans against vendors
```
The `manufacturing` scenario (`ensureDemoInventoryPresent`) stocks finished/stage
materials into `inventory_stock_positions`; `populate-challans.js` fabricates
reception challans. Neither wires reception→order or vendor-batch consumption —
those are driven through the HTTP flow below.

---

## Scenario A — Decoupled stock consumption (common case)

*Reality:* bulk sheets are pre-procured and sit in stock; many small client
orders draw from the shared pool. **No 1-to-1 client↔vendor correlation** — and
the system models this as an aggregate drawdown, exactly as described.

### Steps
1. **Seed vendor stock** — create + **issue** a Reception Challan from Vendor A
   for 500 sheets of item `X`.
   `POST /api/challans` `{ type:'reception', vendor_id, items:[{item_id:X, quantity_pcs:500, weight}] }`
   → `POST /api/challans/:id` issue. Effect: `variation_stock(X,…) += 500`
   (`issueDeliveryChallan`, delta `+` for reception).
2. **Order 1** — Client X places `ORD-101` (needs 50).
3. **Process Order 1** — consume 50, either via an internal consumption challan
   (`type:'internal'`, issue → `variation_stock -= 50`) or a run barcode scan
   (`POST /runs/:id/barcodes` SKU branch → `movementType:'consume'`).
   Effect: `variation_stock(X,…) = 450`.
4. **Order 2** — Client Y places `ORD-102` (needs 100).
5. **Process Order 2** — consume 100 → `variation_stock(X,…) = 350`.

### Expected result (accurate)
- Inventory reads **350** correctly.
- **What is NOT literally true in the data:** "both runs linked to the *same
  vendor batch*." The 350 bucket has no vendor/batch tag. What you *can* show:
  - each **consumption movement** ties to its order via the internal challan /
    run reference (`inventory_movements.reference_id`), and
  - if operators scanned Vendor A's actual **sheet tags** into the runs, those
    exact sheets → Vendor A are recoverable via `run_barcode_inputs` +
    `/api/orders/:orderNo/trace` (the Trace tab).
- **Demo the honest version:** show the aggregate drop to 350, then open a run's
  Trace tab to show the *scanned* sheets tracing back to Vendor A. Do not claim
  the stock bucket itself remembers the vendor.

---

## Scenario B — On-demand procurement (custom / low-volume)

*Reality:* a custom order needs non-stocked material; the factory procures
specific sheets **for that order**. As of 2026-08-12 the reception challan can now
**persist the client order it was procured for** (`delivery_challans.order_no`),
so the vendor sheets tie back to `ORD-103`.

### Steps
1. **Custom order** — Client Z places `ORD-103` for a specialized spec.
2. **Procure for the order** — create + issue a Reception Challan from Vendor B
   **carrying the order link**:
   `POST /api/challans` `{ type:'reception', vendor_id:B, order_no:'ORD-103', po_number:'PO-77', items:[{item_id, quantity_pcs, weight}] }`.
   The new `order_no` on a reception challan is persisted (previously forced
   null). Effect: stock `+`, and the challan is now queryable as "procured for
   ORD-103". Generate the sheet tags (`POST /api/challans/:id/piece-barcodes`).
3. **Execute & track** — run the pipeline for `ORD-103`; at each material node
   the operator **scans Vendor B's sheet tag** (`POST /runs/:id/barcodes`), which
   records the exact sheet → vendor → order lineage, plus finished output +
   scrap.

### Expected result (accurate)
- `ORD-103` → reception challan (Vendor B) is a real, stored link.
- `/api/orders/ORD-103/trace` (Trace tab) shows: run → die/machine → the exact
  Vendor B sheets consumed → Vendor B. This is genuinely end-to-end **because**
  the sheets were scanned into the run.

---

## What to demo in the UI

- **Inventory → Groups → Cards** (new grouped card view): group-header bands with
  rolled-up item counts + stock; finished-good and raw-sheet cards; the
  **lineage** (⤳) affordance opens a material's provenance (movements → run /
  challan → operator/timestamp), and raw-sheet cards surface the **vendor** +
  scannable **barcode**.
- **Order → Trace tab** (built earlier): the backward lineage for an order —
  returns → runs → die/machine → consumed vendor sheets.
- A reception challan created with `order_no` (Scenario B) shows its linked order.

## Honest limitations to state up front
1. Stock buckets are aggregate — no vendor-batch/FIFO on `variation_stock`.
2. Vendor-sheet lineage requires the operator to **scan the sheet** at
   consumption; otherwise run→material is SKU-level (`retro:true` in the trace).
3. Finished-good origin (run/order/operator) is reconstructed from the
   `inventory_movements` ledger, not stored on the material row.
