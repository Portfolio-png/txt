-- One link table for every master, read from either end.
--
-- Until now a link between two masters meant a new table: item_dies,
-- item_machines, material_group_item_links. Three tables, three shapes, three
-- read paths -- and each one answers in exactly one direction. item_dies is
-- read as "the dies of this item" by the item DTO and written only by the item
-- PUT; nothing anywhere can answer "which items does this die make?", even
-- though that is the same row seen from the other side. Adding die <-> machine
-- would have meant a fourth table, and the question "what is this die set up
-- to run on?" would still have had one answer in one direction.
--
-- entity_links is the general form: a link is (type, id) <-> (type, id), one
-- row, with no privileged end.
--
--   CANONICAL ORDERING. The pair is stored sorted by type, and by id when the
--   types match, so die<->machine and machine<->die are the same row and the
--   UNIQUE constraint actually catches a duplicate. The CHECK enforces it at
--   the schema level rather than trusting every writer to normalise first --
--   same reasoning as barcode_ledger's append-only trigger: a rule the code
--   cannot bypass. A reader asks from whichever end it holds:
--
--     WHERE (left_type = ?1 AND left_id = ?2) OR (right_type = ?1 AND right_id = ?2)
--
--   and the matching index serves either branch. The CHECK's strict < on the
--   same-type branch also makes a record linked to itself unrepresentable.
--
--   TEXT ids, deliberately. materials are keyed by barcode and pipeline
--   templates by a text id; an INTEGER column would have forced those two
--   masters back out of the general case.
--
-- The two existing item link tables are NOT folded in here, and nothing is
-- backfilled. item_dies and item_machines are read by the item DTO and written
-- by the item PUT; copying their rows here would leave two stores that both
-- claim to hold item<->die and drift the moment one write path is missed. The
-- links module instead routes those two pairs to the legacy tables and every
-- other pair here -- one store per pair, no dual write -- and reads both ends
-- of the legacy tables too, so "which items does this die make?" is answerable
-- now without moving a single row.

CREATE TABLE IF NOT EXISTS entity_links (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  left_type TEXT NOT NULL,
  left_id TEXT NOT NULL,
  right_type TEXT NOT NULL,
  right_id TEXT NOT NULL,
  -- What the link means, when the type pair does not already say it. The pair
  -- carries the sense in every case we have so far (a die <-> machine link is
  -- "this die runs on that machine"), so this defaults to a bare 'linked'
  -- rather than making every caller invent a verb. It is part of the UNIQUE
  -- key, so the same two records can be linked twice under different senses.
  relation TEXT NOT NULL DEFAULT 'linked',
  -- Per-link facts that belong to the link and not to either record -- a
  -- cavity count, a setup note, a quantity. JSON so a new one does not need a
  -- migration; nothing reads it yet.
  metadata TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  created_by INTEGER,
  UNIQUE (left_type, left_id, right_type, right_id, relation),
  CHECK (
    left_type < right_type
    OR (left_type = right_type AND left_id < right_id)
  )
);

-- Either end of the OR above.
CREATE INDEX IF NOT EXISTS idx_entity_links_left
  ON entity_links (left_type, left_id);
CREATE INDEX IF NOT EXISTS idx_entity_links_right
  ON entity_links (right_type, right_id);

-- Links are state like any other row, so a client that was asleep replays
-- them instead of sitting on a stale graph (migration 040's reasoning).
--
-- Logged as entity_links rather than as an update to each endpoint: announcing
-- the endpoints would mean mapping a type back to its table in SQL, and the
-- endpoint rows have not in fact changed -- the link between them has. A
-- reader of the link graph watches this table name.
CREATE TRIGGER IF NOT EXISTS trg_changelog_entity_links_ai
  AFTER INSERT ON entity_links
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('entity_links', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_entity_links_au
  AFTER UPDATE ON entity_links
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('entity_links', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_entity_links_ad
  AFTER DELETE ON entity_links
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('entity_links', OLD.id, 'DELETE', datetime('now'));
END;
