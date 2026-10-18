-- A variation tree that is not owned by items.
--
-- `item_variation_nodes` is keyed by item_id, so a die cannot have a tree
-- without either a fourth near-identical table or a column that lies. This is
-- the general form, keyed by (entity_type, entity_id) — the same move
-- entity_links made for links, and for the same reason: the shape is one shape,
-- and only the owner differs.
--
-- Items are NOT migrated onto it. Their tree is read and written by a dozen
-- paths in items_screen.dart and the items module, and two stores both claiming
-- to hold an item's properties would drift the first time one was missed. Dies
-- start here; items follow when someone is ready to move those paths across,
-- and the column set below is deliberately the same as item_variation_nodes'
-- so that migration is a copy rather than a redesign.
--
--   VERSIONS. For the client this is built for, items are derived from dies, so
--   a die's values are a contract: once a die says it cuts 2 and 4 cavities,
--   every item derived from it was derived under that statement. Changing a
--   value afterwards would silently rewrite history, so it is not allowed —
--   the tree is FIXED within a version, and a new version is how a change gets
--   declared. Adding a value is the exception: it takes nothing away from what
--   was already derived, so it is allowed in place.
--
--   The rule is enforced in modules/variations/routes.js rather than here,
--   because "may this edit happen" depends on whether a value is new, and SQL
--   cannot see the difference between an append and a rewrite in one row.

CREATE TABLE IF NOT EXISTS entity_variation_nodes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  parent_node_id INTEGER REFERENCES entity_variation_nodes(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  name TEXT NOT NULL,
  code TEXT NOT NULL DEFAULT '',
  display_name TEXT NOT NULL DEFAULT '',
  position INTEGER NOT NULL DEFAULT 0,
  input_type TEXT NOT NULL DEFAULT 'Text',
  name_join TEXT NOT NULL DEFAULT '',
  numeric_min REAL,
  numeric_max REAL,
  material_type_id INTEGER REFERENCES material_types(id),
  -- The version this node was introduced in, so a tree can be read back as it
  -- stood when something was derived from it.
  version INTEGER NOT NULL DEFAULT 1,
  is_archived INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  CHECK (kind IN ('property', 'value'))
);

CREATE INDEX IF NOT EXISTS idx_entity_variation_nodes_owner
  ON entity_variation_nodes (entity_type, entity_id, is_archived);
CREATE INDEX IF NOT EXISTS idx_entity_variation_nodes_parent
  ON entity_variation_nodes (parent_node_id);

-- What version each owner's tree is currently on, and why it was last bumped.
--
-- Kept apart from the nodes so a version exists even before anything is in the
-- tree, and so the reason for a bump survives the nodes it changed.
CREATE TABLE IF NOT EXISTS entity_variation_versions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  version INTEGER NOT NULL,
  label TEXT NOT NULL DEFAULT '',
  note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  created_by INTEGER,
  UNIQUE (entity_type, entity_id, version)
);

-- Replayed by a client that was asleep, like every other write (migration 040).
CREATE TRIGGER IF NOT EXISTS trg_changelog_entity_variation_nodes_ai
  AFTER INSERT ON entity_variation_nodes
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('entity_variation_nodes', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_entity_variation_nodes_au
  AFTER UPDATE ON entity_variation_nodes
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('entity_variation_nodes', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_entity_variation_nodes_ad
  AFTER DELETE ON entity_variation_nodes
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('entity_variation_nodes', OLD.id, 'DELETE', datetime('now'));
END;
