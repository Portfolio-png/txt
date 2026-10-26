-- A die or machine edit is a change to every part that uses it.
--
-- An item's read carries its dies and machines (type, maker, code, capacity…),
-- joined at read time. So when a die is corrected, every part listing it now
-- reads differently — but nothing said so: dies and machines log themselves
-- (040) and the parts that show them never heard. A replica, or any screen
-- waiting on an `items` change, kept the old die on the part until something
-- else touched it.
--
-- Same family as 041: record which OTHER rows a change is visible on. One
-- changelog row per part using the tool, via the link tables.

CREATE TRIGGER IF NOT EXISTS trg_derived_dies_items_au
  AFTER UPDATE ON dies
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  SELECT 'items', item_id, 'UPDATE', datetime('now')
    FROM item_dies WHERE die_id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_machines_items_au
  AFTER UPDATE ON machines
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  SELECT 'items', item_id, 'UPDATE', datetime('now')
    FROM item_machines WHERE machine_id = NEW.id;
END;
