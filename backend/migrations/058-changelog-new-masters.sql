-- The masters added after 040 reach the changelog.
--
-- die_makers (055), process_stages (052) and party_contacts (056) were created
-- without triggers, and nothing in the application logs them either — so a
-- die maker or a stage added in one window never reached another, nor a local
-- replica, until it reloaded. Same reasoning as 040: a trigger cannot be
-- forgotten at a call site.
--
-- item_deal_contacts has no id of its own (its key is the pair), and a tick is
-- a change to the PART, so it is recorded against the item — the derived
-- family 041 started. Likewise a person is part of what a client reads back,
-- so a change to one is recorded against the client too.
--
-- Also the index the section-tree reconcile needs: it reads
-- `entity_links WHERE relation = ?` after every item save, and 043's UNIQUE
-- index has relation LAST, so that was a scan of the whole link table.
--
-- Idempotent: both runners run every file on every boot.

CREATE TRIGGER IF NOT EXISTS trg_changelog_die_makers_ai
  AFTER INSERT ON die_makers
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('die_makers', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_die_makers_au
  AFTER UPDATE ON die_makers
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('die_makers', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_die_makers_ad
  AFTER DELETE ON die_makers
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('die_makers', OLD.id, 'DELETE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_process_stages_ai
  AFTER INSERT ON process_stages
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('process_stages', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_process_stages_au
  AFTER UPDATE ON process_stages
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('process_stages', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_process_stages_ad
  AFTER DELETE ON process_stages
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('process_stages', OLD.id, 'DELETE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_party_contacts_ai
  AFTER INSERT ON party_contacts
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('party_contacts', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_party_contacts_au
  AFTER UPDATE ON party_contacts
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('party_contacts', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_party_contacts_ad
  AFTER DELETE ON party_contacts
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('party_contacts', OLD.id, 'DELETE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_party_contacts_client_ai
  AFTER INSERT ON party_contacts
  WHEN NEW.party_type = 'client'
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('clients', NEW.party_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_party_contacts_client_au
  AFTER UPDATE ON party_contacts
  WHEN NEW.party_type = 'client'
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('clients', NEW.party_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_item_deal_contacts_ai
  AFTER INSERT ON item_deal_contacts
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', NEW.item_id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_derived_item_deal_contacts_ad
  AFTER DELETE ON item_deal_contacts
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('items', OLD.item_id, 'UPDATE', datetime('now'));
END;

CREATE INDEX IF NOT EXISTS idx_entity_links_relation
  ON entity_links (relation);
