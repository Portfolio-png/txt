-- What a die sheet actually records, beside the die.
--
-- The dies table held a tool code, a free-text storage location and a bag of
-- JSON specs. The sheet the floor keeps has eleven columns, and all but the
-- code had nowhere to go:
--
--   PO-Date · Time · Die Made By · Type · Liner Size · Die Code ·
--   No of Set · Store Area · Rack No · Date in · Time
--
-- Each one here, with why it is the shape it is.
--
-- die_type is a SLUG, stored, not inferred from anything else. '' ("nobody
-- said") and 'cutting' are different facts, and the code rule reads the type's
-- LABEL to build its initials — Cutting → CD, Bending → BD — so the two sides
-- have to agree on a vocabulary rather than guess from a column. Same rule as
-- items.developed_for_kind in 047.
ALTER TABLE dies ADD COLUMN die_type TEXT NOT NULL DEFAULT '';

-- Free text, deliberately. A die is made by a fitter on the floor or by an
-- outside toolroom, and a master that can hold only one of those would be
-- wrong half the time. The field suggests names already used on a die, which
-- is the useful half of a master without the maintenance.
ALTER TABLE dies ADD COLUMN made_by TEXT NOT NULL DEFAULT '';

-- Full ISO instants in UTC, named _at like items.developed_for_at, because the
-- sheet carries a time beside each date ("21/05/26 10:20"). Never read their
-- fields directly: the client converts with .toLocal() first, or an Indian
-- shop sees a die received at 11.30 AM as 6.00 AM the same day.
ALTER TABLE dies ADD COLUMN po_at TEXT;
ALTER TABLE dies ADD COLUMN date_in_at TEXT;

-- Liner size, as an INTEGER COUNT OF NANOMETRES.
--
-- This is the units contract's own answer (.claude/skills/units/SKILL.md), not
-- a dodge around it. I1 forbids REAL for a quantity; §1.2 requires an integer
-- count of base units where the base is small enough that every unit in the
-- family is a whole multiple of it. Micrometres fail that test — 1 thou is
-- 25.4 µm, so "15.5 thou" could not be stored without the silent rounding I6
-- forbids. In nanometres every unit this field offers is exact: mm 1,000,000,
-- cm 10,000,000, inch 25,400,000, thou 25,400, and every row of the SWG table.
-- items.blank_width_mm REAL is the shape NOT to copy.
--
-- The module itself — families, Quantity, QuantityText — does not exist yet;
-- §0 of the skill says so plainly. So this column is integer base units with
-- one documented conversion at the field's parse/format boundary, and it gets
-- the type when the module lands.
ALTER TABLE dies ADD COLUMN liner_size_nm INTEGER;

-- How the size was READ, as a symbol. A deviation from I3 (store ids, not
-- strings) worth naming out loud: the units master has no Length family at all
-- — unit_groups is empty and every unit's unit_group_id is NULL — so there is
-- no id to store. It is a display unit and never takes part in arithmetic,
-- which is what makes the deviation survivable until the family exists.
ALTER TABLE dies ADD COLUMN liner_size_unit TEXT NOT NULL DEFAULT 'mm';

-- How many sets of the die were made. A count, so an integer; nullable,
-- because one set and nobody counted are different answers.
ALTER TABLE dies ADD COLUMN no_of_set INTEGER;

-- Where it is kept. TEXT and not foreign keys: there is no store-area master
-- in this system, and inventing one is a different feature with its own
-- screens. These two REPLACE the free-text storage_location for anything
-- written from now on — see the subtitle expression in modules/links/catalog.js,
-- which prefers them and falls back to the old column for dies that only have
-- it. Nothing backfills: a live row reads "Rack 12, Area B", and splitting it
-- by guess would put a rack number in the area column with no way back.
ALTER TABLE dies ADD COLUMN store_area TEXT NOT NULL DEFAULT '';
ALTER TABLE dies ADD COLUMN rack_no TEXT NOT NULL DEFAULT '';

-- Design checklist: no new event row and no new event_type. A die's purchase
-- order date, maker and rack are attributes of a tool, not transitions it goes
-- through, and field-level history already comes free — dies is in the
-- changelog triggers (040) and the route calls trackCreate/trackUpdate into
-- entity_activity_log. Feature-to-Metric: dies made per month and per maker,
-- and PO-to-date-in lead time, in the Tooling cluster.
--
-- No UNIQUE index here: the runner absorbs "duplicate column name" but NOT
-- "UNIQUE constraint failed", so an index that a live database cannot satisfy
-- would stop every boot. tool_code's existing UNIQUE is enough, and the route
-- now refuses a clash by name before it reaches it.
CREATE INDEX IF NOT EXISTS idx_dies_made_by ON dies(made_by) WHERE made_by <> '';
CREATE INDEX IF NOT EXISTS idx_dies_die_type ON dies(die_type) WHERE die_type <> '';
