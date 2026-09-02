-- The chain-of-custody ledger.
--
-- Business tables answer "what is true now". They are updated in place, so they
-- cannot answer "who touched this, when, and what did it become" — the question
-- a defect traced back from a client actually asks. This table answers that,
-- and it answers it years later, because nothing rewrites it.
--
-- ## Append-only, enforced
--
-- A ledger described as immutable but stored in an ordinary table is immutable
-- only until someone writes an UPDATE. The triggers below make it real: rows can
-- be inserted and read, and any attempt to change or delete one is refused by
-- the database itself, whatever wrote it and whatever it thought it was doing.
--
-- That is the whole value. A provenance record that can be quietly edited after
-- the fact proves nothing about the past — it only records what someone most
-- recently claimed about it.
--
-- ## Barcodes, not foreign keys
--
-- Every reference is a barcode string rather than a foreign key, on purpose:
--
--   * a ledger row must survive the deletion of what it refers to — the whole
--     point is that it still says a sheet existed and was consumed even after
--     the sheet row is gone;
--   * one column can point at any kind of entity, because the barcode carries
--     its own type;
--   * an event can name something outside the database entirely — a vendor's
--     own lot code, a location that is a shelf and not a record.
--
-- The cost is that nothing stops a typo'd barcode being written. The resolver
-- reports what it could not resolve rather than hiding it, which is the honest
-- trade for a record that has to outlive its subjects.

CREATE TABLE IF NOT EXISTS barcode_ledger (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event_id TEXT NOT NULL UNIQUE,

  -- What this event happened to.
  subject_barcode TEXT NOT NULL,

  -- GENESIS_PURCHASE, INWARD_RECEIVED, LOCATION_MOVED, ISSUED_TO_PIPELINE,
  -- STAGE_PROCESSED, OUTPUT_MINTED, DISPATCH_PACKED, CLIENT_DELIVERED,
  -- INVOICED. Kept as free text rather than a CHECK constraint: a workshop
  -- will need an event this list does not have, and refusing to record it
  -- would lose the fact rather than tidy it.
  event_type TEXT NOT NULL,

  -- Who, where, with what.
  actor_barcode TEXT,
  actor_name TEXT DEFAULT '',
  location_barcode TEXT,
  machine_barcode TEXT,
  die_barcode TEXT,

  -- The genealogy: what went in, what came out. JSON arrays of barcodes, so one
  -- event can consume several things and produce several more — which is what a
  -- press stroke or an assembly step actually does.
  parent_barcodes_json TEXT NOT NULL DEFAULT '[]',
  child_barcodes_json TEXT NOT NULL DEFAULT '[]',

  -- The paperwork it belongs to.
  order_barcode TEXT,
  document_barcode TEXT,

  -- { qty, weightKg, unit, wasteKg, ... }. Free-form because what is worth
  -- measuring differs per event, and a column per metric would be mostly null.
  metrics_json TEXT NOT NULL DEFAULT '{}',

  notes TEXT DEFAULT '',

  -- Recorded, not observed: the moment the system was told, which is the only
  -- time it can honestly claim to know.
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- The questions this table is asked, one index each.
CREATE INDEX IF NOT EXISTS idx_barcode_ledger_subject
  ON barcode_ledger(subject_barcode, created_at);
CREATE INDEX IF NOT EXISTS idx_barcode_ledger_actor
  ON barcode_ledger(actor_barcode, created_at);
CREATE INDEX IF NOT EXISTS idx_barcode_ledger_order
  ON barcode_ledger(order_barcode);
CREATE INDEX IF NOT EXISTS idx_barcode_ledger_document
  ON barcode_ledger(document_barcode);
CREATE INDEX IF NOT EXISTS idx_barcode_ledger_type
  ON barcode_ledger(event_type, created_at);
CREATE INDEX IF NOT EXISTS idx_barcode_ledger_created
  ON barcode_ledger(created_at);

-- Immutability, enforced by the database rather than by good intentions.
CREATE TRIGGER IF NOT EXISTS barcode_ledger_no_update
BEFORE UPDATE ON barcode_ledger
BEGIN
  SELECT RAISE(ABORT, 'barcode_ledger is append-only: a custody record cannot be edited after the fact');
END;

CREATE TRIGGER IF NOT EXISTS barcode_ledger_no_delete
BEFORE DELETE ON barcode_ledger
BEGIN
  SELECT RAISE(ABORT, 'barcode_ledger is append-only: a custody record cannot be deleted');
END;
