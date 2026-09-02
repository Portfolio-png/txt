-- Cancelling a challan gives the quantity back.
--
-- An order line shows total_delivered_qty summed over its dispatched lines —
-- but only from challans that are not cancelled:
--
--   SELECT SUM(dci.quantity_pcs) ... WHERE dci.order_item_id = o.id
--     AND dc.status != 'cancelled'
--
-- So cancelling a challan changes what every order line it touched displays,
-- while writing no delivery_challan_items row and no order_items row. Migration
-- 041 announces the order line when a challan LINE changes; it had nothing to
-- say when the challan's own status moved.
--
-- The symptom is the one users notice: "delivered 300 of 500" that never gives
-- the 300 back after the dispatch is cancelled.
--
-- Only on UPDATE. An INSERT has no lines yet, and a DELETE cascades to the
-- lines, whose own triggers announce the order rows.
CREATE TRIGGER IF NOT EXISTS trg_derived_challans_order_items_au
  AFTER UPDATE ON delivery_challans
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  SELECT DISTINCT 'order_items', dci.order_item_id, 'UPDATE', datetime('now')
  FROM delivery_challan_items dci
  WHERE dci.challan_id = NEW.id AND dci.order_item_id IS NOT NULL;
END;
