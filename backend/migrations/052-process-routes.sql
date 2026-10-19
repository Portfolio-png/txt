-- Process routing: the ordered list of stages a part goes through.
--
-- This is the canonical model from Docs/architecture/10-design-philosophy.md,
-- whose worked example IS process routing. It prescribed these tables and these
-- rules; nothing had been built. `pipeline_templates` exists and is a different
-- axis — a node/flow/lane GRAPH for a production run, with machines bound to
-- nodes. A route is a flat ordered list of stages belonging to a PART. Bending
-- one into the other would have made both worse, and `items.default_pipeline_id`
-- keeps its current meaning.
--
--   NAMES. The doc writes `process_stage` / `route` / `route_step` singular.
--   This schema is plural throughout (`item_dies`, `pipeline_templates`,
--   `entity_variation_nodes`), and a bare `routes` table in a codebase where
--   every module's HTTP file is called routes.js would be read wrong by
--   everyone. So: plural, and `process_` on all three so the family is obvious.
--   Same model, repo's spelling.
--
-- The three rules the doc puts in the backend live in
-- modules/process_routes/service.js, not here, because SQL cannot see them:
-- contiguity of `seq` is a property of the whole set, "once per route unless
-- repeatable" needs the stage's flag, and "version rather than edit" depends on
-- whether the route has been used. What SQL CAN hold is below: no two steps at
-- one seq, no two versions of one part's route, and at most one active route
-- per part.
--
-- Idempotent on purpose. Two runners execute this file on EVERY boot —
-- migrate.js first (tolerates only /duplicate column name/i), then
-- modules/kernel/migration-runner.js from inside initDb (tolerates
-- duplicate-column / already-exists / no-such-table). CREATE TABLE IF NOT
-- EXISTS, CREATE INDEX IF NOT EXISTS and INSERT OR IGNORE all fail the second
-- pass in a way both forgive.

-- The factory's stage master. Rows, not constants: the nine below are this
-- client's ribbon, and the next factory's list is different. Two hardcoded
-- Dart lists of process types exist today and disagree with each other
-- (node_blueprint.dart and pipeline_builder_screen.dart, the latter with the
-- typos "Slating" and "Prograsive"). Those stay where they are for now; this
-- is the one place a ROUTE reads from.
CREATE TABLE IF NOT EXISTS process_stages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  position INTEGER NOT NULL DEFAULT 0,
  -- A stage may appear twice in one route only if it says so. Default 0 is the
  -- doc's stricter reading; flipping one is a single UPDATE.
  repeatable INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_process_stages_active
  ON process_stages (active, position);

-- One route per part per version. `status` is the doc's three words exactly.
CREATE TABLE IF NOT EXISTS process_routes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  part_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  version INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'draft',
  note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  created_by INTEGER,
  UNIQUE (part_id, version),
  CHECK (status IN ('draft', 'active', 'retired'))
);

-- At most one active route per part. The partial index is the whole enforcement
-- of that invariant, so a second view cannot route around it.
CREATE UNIQUE INDEX IF NOT EXISTS idx_process_routes_one_active
  ON process_routes (part_id) WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_process_routes_part
  ON process_routes (part_id, status, version);

-- The ordered steps. `seq` runs 1..n with no gaps (checked in the service).
--
-- machine_id and die_id are nullable and deliberately NOT the tooling masters'
-- only home: which die makes a part is still item_dies, and a route step naming
-- a die says "use this one at this step", which is a narrower claim. NULL means
-- the step does not care, which is the common case for Billing or Delivery.
CREATE TABLE IF NOT EXISTS process_route_steps (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  route_id INTEGER NOT NULL REFERENCES process_routes(id) ON DELETE CASCADE,
  seq INTEGER NOT NULL,
  stage_id INTEGER NOT NULL REFERENCES process_stages(id),
  notes TEXT NOT NULL DEFAULT '',
  machine_id INTEGER REFERENCES machines(id) ON DELETE SET NULL,
  die_id INTEGER REFERENCES dies(id) ON DELETE SET NULL,
  UNIQUE (route_id, seq)
);

CREATE INDEX IF NOT EXISTS idx_process_route_steps_route
  ON process_route_steps (route_id, seq);
CREATE INDEX IF NOT EXISTS idx_process_route_steps_stage
  ON process_route_steps (stage_id);

-- Replayed by a client that was asleep, like every other write (migration 040).
CREATE TRIGGER IF NOT EXISTS trg_changelog_process_routes_ai
  AFTER INSERT ON process_routes
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('process_routes', NEW.id, 'INSERT', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_process_routes_au
  AFTER UPDATE ON process_routes
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('process_routes', NEW.id, 'UPDATE', datetime('now'));
END;

CREATE TRIGGER IF NOT EXISTS trg_changelog_process_routes_ad
  AFTER DELETE ON process_routes
BEGIN
  INSERT INTO changelog (table_name, record_id, event_type, timestamp)
  VALUES ('process_routes', OLD.id, 'DELETE', datetime('now'));
END;

-- This client's nine. INSERT OR IGNORE against the UNIQUE on `code`, so a
-- factory that renames or deactivates one keeps its change across every boot.
INSERT OR IGNORE INTO process_stages (code, name, position) VALUES
  ('die',      'Die',      1),
  ('shearing', 'Shearing', 2),
  ('cutting',  'Cutting',  3),
  ('riveting', 'Riveting', 4),
  ('assembly', 'Assembly', 5),
  ('barcode',  'Barcode',  6),
  ('packing',  'Packing',  7),
  ('billing',  'Billing',  8),
  ('delivery', 'Delivery', 9);
