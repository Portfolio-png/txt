-- The property columns added to the item sheet with its "+".
--
-- They lived only in the sheet's memory: Plating, added on Monday, was gone
-- when the sheet was next opened, and its dropdown offered only what saved
-- parts happened to carry. A column is now a workspace-wide row with its own
-- list of options, kept until the column is removed. Removing it removes the
-- definition only — parts keep the values they were saved with.
--
-- property_key is the normalised name, which is also the variation property
-- name the sheet writes onto each part, so the two always find each other.
-- options_json is the ordered list of option labels.
--
-- Idempotent: both runners run every file on every boot.

CREATE TABLE IF NOT EXISTS item_sheet_properties (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  property_key TEXT NOT NULL,
  -- The name as first typed: what the sheet writes onto parts as the
  -- property's name. A rename changes display_name only.
  property_name TEXT NOT NULL,
  display_name TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'list' CHECK (kind IN ('list', 'text', 'material', 'gauge')),
  position INTEGER NOT NULL DEFAULT 0,
  options_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_item_sheet_properties_key
  ON item_sheet_properties (property_key COLLATE NOCASE);

CREATE TRIGGER IF NOT EXISTS trg_changelog_item_sheet_properties_ai
  AFTER INSERT ON item_sheet_properties
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('item_sheet_properties', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_item_sheet_properties_au
  AFTER UPDATE ON item_sheet_properties
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('item_sheet_properties', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_item_sheet_properties_ad
  AFTER DELETE ON item_sheet_properties
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('item_sheet_properties', OLD.id, 'DELETE', datetime('now'));
END;
