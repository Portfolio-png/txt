-- Announcing the row a change is VISIBLE on, not just the row it happened to.
--
-- Migration 040 logs every row change. That is necessary and not sufficient,
-- because several things the UI displays are derived from a DIFFERENT table
-- than the row carrying them. Change the source and the displayed value goes
-- stale while the carrying row never changes -- so no trigger fires, no delta
-- is sent, and a replica serves the old value indefinitely.
--
-- The item DTO is the worst of it: rowToItemDto reads EIGHT other tables
-- (server.js:2726-2846) -- the variation tree, unit conversions, group
-- memberships, attachments, machine links, die links, a client name and a
-- pipeline name. Seven of those had no triggers at all.
--
-- Done in SQL for the same reason as 040: it cannot be forgotten. A comment
-- asking the next person to remember an extra logChange would not survive.

CREATE TRIGGER IF NOT EXISTS trg_derived_item_variation_nodes_items_ai
  AFTER INSERT ON item_variation_nodes
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', NEW.item_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_item_variation_nodes_items_au
  AFTER UPDATE ON item_variation_nodes
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', NEW.item_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_item_variation_nodes_items_ad
  AFTER DELETE ON item_variation_nodes
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', OLD.item_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_item_unit_conversions_items_ai
  AFTER INSERT ON item_unit_conversions
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', NEW.item_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_item_unit_conversions_items_au
  AFTER UPDATE ON item_unit_conversions
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', NEW.item_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_item_unit_conversions_items_ad
  AFTER DELETE ON item_unit_conversions
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', OLD.item_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_group_item_memberships_items_ai
  AFTER INSERT ON group_item_memberships
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', NEW.item_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_group_item_memberships_items_au
  AFTER UPDATE ON group_item_memberships
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', NEW.item_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_group_item_memberships_items_ad
  AFTER DELETE ON group_item_memberships
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', OLD.item_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_group_item_memberships_groups_ai
  AFTER INSERT ON group_item_memberships
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('groups', NEW.group_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_group_item_memberships_groups_au
  AFTER UPDATE ON group_item_memberships
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('groups', NEW.group_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_group_item_memberships_groups_ad
  AFTER DELETE ON group_item_memberships
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('groups', OLD.group_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_item_attachments_items_ai
  AFTER INSERT ON item_attachments
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', NEW.item_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_item_attachments_items_au
  AFTER UPDATE ON item_attachments
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', NEW.item_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_item_attachments_items_ad
  AFTER DELETE ON item_attachments
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', OLD.item_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_item_machines_items_ai
  AFTER INSERT ON item_machines
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', NEW.item_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_item_machines_items_au
  AFTER UPDATE ON item_machines
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', NEW.item_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_item_machines_items_ad
  AFTER DELETE ON item_machines
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', OLD.item_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_item_dies_items_ai
  AFTER INSERT ON item_dies
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', NEW.item_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_item_dies_items_au
  AFTER UPDATE ON item_dies
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', NEW.item_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_item_dies_items_ad
  AFTER DELETE ON item_dies
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', OLD.item_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_delivery_challan_items_delivery_challans_ai
  AFTER INSERT ON delivery_challan_items
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('delivery_challans', NEW.challan_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_delivery_challan_items_delivery_challans_au
  AFTER UPDATE ON delivery_challan_items
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('delivery_challans', NEW.challan_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_delivery_challan_items_delivery_challans_ad
  AFTER DELETE ON delivery_challan_items
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('delivery_challans', OLD.challan_id, 'UPDATE', datetime('now'));
END;

-- Indirect. An order line shows a status COALESCEd from the pipeline runs
-- assigned to it, so a run completing changes what the line displays while
-- changing no order_items row. The join is done inside the trigger.

CREATE TRIGGER IF NOT EXISTS trg_derived_pipeline_runs_order_items_au
  AFTER UPDATE ON pipeline_runs
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  SELECT 'order_items', opa.order_item_id, 'UPDATE', datetime('now')
  FROM order_pipeline_assignments opa WHERE opa.pipeline_run_id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_pipeline_runs_order_items_ad
  AFTER DELETE ON pipeline_runs
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  SELECT 'order_items', opa.order_item_id, 'UPDATE', datetime('now')
  FROM order_pipeline_assignments opa WHERE opa.pipeline_run_id = OLD.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_assignments_order_items_ai
  AFTER INSERT ON order_pipeline_assignments
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('order_items', NEW.order_item_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_assignments_order_items_ad
  AFTER DELETE ON order_pipeline_assignments
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('order_items', OLD.order_item_id, 'UPDATE', datetime('now'));
END;

-- A dispatched line moves the order line total_delivered_qty is summed from.

CREATE TRIGGER IF NOT EXISTS trg_derived_challan_items_order_items_ai
  AFTER INSERT ON delivery_challan_items
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  SELECT 'order_items', NEW.order_item_id, 'UPDATE', datetime('now')
  WHERE NEW.order_item_id IS NOT NULL;
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_challan_items_order_items_au
  AFTER UPDATE ON delivery_challan_items
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  SELECT 'order_items', NEW.order_item_id, 'UPDATE', datetime('now')
  WHERE NEW.order_item_id IS NOT NULL;
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_challan_items_order_items_ad
  AFTER DELETE ON delivery_challan_items
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  SELECT 'order_items', OLD.order_item_id, 'UPDATE', datetime('now')
  WHERE OLD.order_item_id IS NOT NULL;
END;

