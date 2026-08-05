-- Border wall for stock identity (kernel rule K4, last line of defense).
--
-- Stock-managed line references must point at real variation nodes. The
-- client-side selector mints SYNTHETIC NEGATIVE ids (-propertyId) for typed
-- Gauge/Numeric values; those are display riders and must never persist as
-- variation_leaf_node_id — a negative id saved on a challan line is exactly
-- the bug that made internal-use challans un-issuable (2026-07-27). Ingress
-- normalization already maps them to the deepest real node; these triggers
-- make the invariant hold against every future code path.

CREATE TRIGGER IF NOT EXISTS trg_delivery_challan_items_leaf_nonneg_ins
BEFORE INSERT ON delivery_challan_items
WHEN NEW.variation_leaf_node_id < 0
BEGIN
  SELECT RAISE(ABORT, 'delivery_challan_items.variation_leaf_node_id must reference a real node (>= 0)');
END;

CREATE TRIGGER IF NOT EXISTS trg_delivery_challan_items_leaf_nonneg_upd
BEFORE UPDATE OF variation_leaf_node_id ON delivery_challan_items
WHEN NEW.variation_leaf_node_id < 0
BEGIN
  SELECT RAISE(ABORT, 'delivery_challan_items.variation_leaf_node_id must reference a real node (>= 0)');
END;

CREATE TRIGGER IF NOT EXISTS trg_order_items_leaf_nonneg_ins
BEFORE INSERT ON order_items
WHEN NEW.variation_leaf_node_id < 0
BEGIN
  SELECT RAISE(ABORT, 'order_items.variation_leaf_node_id must reference a real node (>= 0)');
END;

CREATE TRIGGER IF NOT EXISTS trg_order_items_leaf_nonneg_upd
BEFORE UPDATE OF variation_leaf_node_id ON order_items
WHEN NEW.variation_leaf_node_id < 0
BEGIN
  SELECT RAISE(ABORT, 'order_items.variation_leaf_node_id must reference a real node (>= 0)');
END;

CREATE TRIGGER IF NOT EXISTS trg_variation_stock_leaf_positive_ins
BEFORE INSERT ON variation_stock
WHEN NEW.variation_leaf_node_id <= 0
BEGIN
  SELECT RAISE(ABORT, 'variation_stock.variation_leaf_node_id must reference a real node (> 0)');
END;
