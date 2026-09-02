-- Every write records that it happened.
--
-- The changelog is what a local read replica replays, so its coverage is the
-- hard ceiling on what such a replica can keep truthful. An audit found ~174
-- mutation sites across these tables and ~13 of them logging: about 7%.
-- Editing an item variation touched item_variation_nodes, which logged nothing,
-- so a replica would have served the old tree indefinitely.
--
-- Written by triggers rather than by application code on purpose:
--
--   * it cannot be forgotten -- coverage stops depending on whether whoever
--     wrote an endpoint remembered a line, which no amount of care at 174
--     call sites can guarantee;
--   * it covers writes the application never makes -- migrations, backfills,
--     scenario seeders, a maintenance script, sqlite3 on the box;
--   * it is transactional, so a log entry commits or rolls back with the row
--     it describes and cannot claim a change that was undone.
--
-- Same reasoning as barcode_ledger enforcing append-only by trigger: a rule the
-- code cannot bypass.
--
-- record_id is declared INTEGER but three of these tables are keyed by text
-- (order_headers.order_no, pipeline_templates.id, pipeline_runs.id). SQLite
-- stores those as TEXT under INTEGER affinity rather than rejecting them, and
-- the client already coerces either form.

CREATE TRIGGER IF NOT EXISTS trg_changelog_materials_ai
  AFTER INSERT ON materials
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('materials', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_materials_au
  AFTER UPDATE ON materials
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('materials', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_materials_ad
  AFTER DELETE ON materials
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('materials', OLD.id, 'DELETE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_item_variation_nodes_ai
  AFTER INSERT ON item_variation_nodes
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('item_variation_nodes', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_item_variation_nodes_au
  AFTER UPDATE ON item_variation_nodes
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('item_variation_nodes', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_item_variation_nodes_ad
  AFTER DELETE ON item_variation_nodes
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('item_variation_nodes', OLD.id, 'DELETE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_order_items_ai
  AFTER INSERT ON order_items
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('order_items', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_order_items_au
  AFTER UPDATE ON order_items
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('order_items', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_order_items_ad
  AFTER DELETE ON order_items
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('order_items', OLD.id, 'DELETE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_order_headers_ai
  AFTER INSERT ON order_headers
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('order_headers', NEW.order_no, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_order_headers_au
  AFTER UPDATE ON order_headers
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('order_headers', NEW.order_no, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_order_headers_ad
  AFTER DELETE ON order_headers
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('order_headers', OLD.order_no, 'DELETE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_delivery_challan_items_ai
  AFTER INSERT ON delivery_challan_items
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('delivery_challan_items', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_delivery_challan_items_au
  AFTER UPDATE ON delivery_challan_items
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('delivery_challan_items', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_delivery_challan_items_ad
  AFTER DELETE ON delivery_challan_items
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('delivery_challan_items', OLD.id, 'DELETE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_delivery_challans_ai
  AFTER INSERT ON delivery_challans
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('delivery_challans', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_delivery_challans_au
  AFTER UPDATE ON delivery_challans
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('delivery_challans', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_delivery_challans_ad
  AFTER DELETE ON delivery_challans
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('delivery_challans', OLD.id, 'DELETE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_items_ai
  AFTER INSERT ON items
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_items_au
  AFTER UPDATE ON items
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_items_ad
  AFTER DELETE ON items
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', OLD.id, 'DELETE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_units_ai
  AFTER INSERT ON units
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('units', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_units_au
  AFTER UPDATE ON units
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('units', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_units_ad
  AFTER DELETE ON units
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('units', OLD.id, 'DELETE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_groups_ai
  AFTER INSERT ON groups
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('groups', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_groups_au
  AFTER UPDATE ON groups
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('groups', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_groups_ad
  AFTER DELETE ON groups
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('groups', OLD.id, 'DELETE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_pipeline_templates_ai
  AFTER INSERT ON pipeline_templates
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('pipeline_templates', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_pipeline_templates_au
  AFTER UPDATE ON pipeline_templates
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('pipeline_templates', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_pipeline_templates_ad
  AFTER DELETE ON pipeline_templates
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('pipeline_templates', OLD.id, 'DELETE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_pipeline_runs_ai
  AFTER INSERT ON pipeline_runs
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('pipeline_runs', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_pipeline_runs_au
  AFTER UPDATE ON pipeline_runs
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('pipeline_runs', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_pipeline_runs_ad
  AFTER DELETE ON pipeline_runs
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('pipeline_runs', OLD.id, 'DELETE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_machines_ai
  AFTER INSERT ON machines
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('machines', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_machines_au
  AFTER UPDATE ON machines
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('machines', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_machines_ad
  AFTER DELETE ON machines
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('machines', OLD.id, 'DELETE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_dies_ai
  AFTER INSERT ON dies
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('dies', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_dies_au
  AFTER UPDATE ON dies
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('dies', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_dies_ad
  AFTER DELETE ON dies
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('dies', OLD.id, 'DELETE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_clients_ai
  AFTER INSERT ON clients
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('clients', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_clients_au
  AFTER UPDATE ON clients
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('clients', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_clients_ad
  AFTER DELETE ON clients
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('clients', OLD.id, 'DELETE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_vendors_ai
  AFTER INSERT ON vendors
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('vendors', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_vendors_au
  AFTER UPDATE ON vendors
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('vendors', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_vendors_ad
  AFTER DELETE ON vendors
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('vendors', OLD.id, 'DELETE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_departments_ai
  AFTER INSERT ON departments
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('departments', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_departments_au
  AFTER UPDATE ON departments
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('departments', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_departments_ad
  AFTER DELETE ON departments
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('departments', OLD.id, 'DELETE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_inventory_stock_positions_ai
  AFTER INSERT ON inventory_stock_positions
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('inventory_stock_positions', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_inventory_stock_positions_au
  AFTER UPDATE ON inventory_stock_positions
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('inventory_stock_positions', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_inventory_stock_positions_ad
  AFTER DELETE ON inventory_stock_positions
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('inventory_stock_positions', OLD.id, 'DELETE', datetime('now'));
END;

