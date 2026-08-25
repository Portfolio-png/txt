-- Joining the two halves of stock.
--
-- Challans have always moved stock at the grain of "25 of this item, in this
-- variation": issuing one writes a variation_stock row and an
-- inventory_movements row whose barcode column is the literal '-', commented in
-- the source as "legacy barcode". Production consumes at the opposite grain —
-- a physical piece, named by barcode, recorded in run_barcode_inputs.
--
-- Nothing joined the two, so material received on a challan never became
-- assignable on the floor, and an order could never say what went into it. Not
-- for want of a column: the two halves were counting different things.
--
-- Three links, one per direction of the problem:
--
--   1. a material row remembers the challan line that brought it in, so
--      provenance is a column rather than a join through movements;
--   2. a consumption remembers the challan line its material came from, which
--      is the bridge column that already existed and was never written;
--   3. a consumption can be a quantity of an item+variation rather than a
--      barcode, so stock that was never barcoded is still consumable.

-- 1. Where a material came from. Null for stock created directly in inventory,
--    which stays legitimate — it just cannot be attributed to a receipt.
ALTER TABLE materials ADD COLUMN source_challan_id INTEGER;
ALTER TABLE materials ADD COLUMN source_challan_item_id INTEGER;

CREATE INDEX IF NOT EXISTS idx_materials_source_challan
  ON materials(source_challan_id);

-- 2/3. What a run consumed, in whichever grain it was consumed in.
--
--   challan_item_id          the line that supplied it (the bridge)
--   item_id / variation_leaf_node_id
--                            what was consumed, when it was consumed by
--                            quantity rather than by barcode
--   consumed_qty             how much, in the item's own unit
--
-- `challan_item_id` is declared here for the fresh-database path;
-- ensureColumnExists already adds it to existing databases, and adding a
-- duplicate column would fail, so the runner tolerates that below.
ALTER TABLE run_barcode_inputs ADD COLUMN item_id INTEGER;
ALTER TABLE run_barcode_inputs ADD COLUMN variation_leaf_node_id INTEGER;
ALTER TABLE run_barcode_inputs ADD COLUMN consumed_qty REAL;

CREATE INDEX IF NOT EXISTS idx_run_barcode_inputs_challan_item
  ON run_barcode_inputs(challan_item_id);
