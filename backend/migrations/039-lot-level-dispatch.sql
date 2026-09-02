-- Closing the last two gaps in the custody chain.
--
-- Both are the same shape of problem: a fact that exists in the world had
-- nowhere to live in the schema, so the code either guessed it or dropped it.
--
-- 1. WHAT A STANDALONE RUN IS MAKING
--
-- A run assigned to an order line knows which variation it produces, because
-- the line says so. A run started to build stock does not, and nothing could
-- say — so completing one either invented a variation (the old
-- `kind = 'leaf' LIMIT 1` lookup, which picked an arbitrary one) or, after that
-- was fixed, declined to mint anything at all rather than guess.
--
-- Declining is the right default and stays the fallback. But an operator
-- starting a run usually does know what they are about to make, and there was
-- no column to write it in. Now there is, and the resolution runs:
--
--     the assigned order line  ->  the run's own stated target  ->  don't guess
--
-- 0 means "not stated", matching order_items.variation_leaf_node_id, so a base
-- item and an unstated variation stay distinguishable from each other.
ALTER TABLE pipeline_runs ADD COLUMN output_variation_leaf_node_id INTEGER DEFAULT 0;
ALTER TABLE pipeline_runs ADD COLUMN output_variation_path_label TEXT DEFAULT '';

-- 2. WHICH LOT ACTUALLY WENT OUT
--
-- `delivery_challan_items.production_run_id` records which run made the goods
-- on a line, which is one hop short of the question people ask. A run can mint
-- more than one lot over its life, so "made by run 42" does not identify the
-- physical thing in the customer's hands — and a defect report starts by
-- scanning that thing.
--
-- With the lot on the line, scanning a package tag reaches the lot, the lot
-- reaches the run that made it (OUTPUT_MINTED), and the run reaches the
-- material it consumed (ISSUED_TO_PIPELINE). That is the full circle, back to
-- the vendor, in hops a person can follow.
--
-- Empty string, not NULL, to match how the neighbouring text columns on this
-- table already spell "nothing here" — a challan line for stock that was never
-- lot-tracked is perfectly legitimate and must stay so.
ALTER TABLE delivery_challan_items ADD COLUMN lot_code TEXT DEFAULT '';
ALTER TABLE delivery_challan_items ADD COLUMN material_barcode TEXT DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_delivery_challan_items_lot
  ON delivery_challan_items(lot_code);
