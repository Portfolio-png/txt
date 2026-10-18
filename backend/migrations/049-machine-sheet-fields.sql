-- What a machine sheet actually records, beside the machine.
--
-- The floor keeps a "Machine in Plant" sheet with nine columns and only two of
-- them had a live home: Machine Type is machines.group_id, Machine No is
-- machines.asset_id. The rest lived nowhere, or in the custom_properties bag —
-- the seed literally stores [{"key": "Tonnage", "value": "80T"}], which is the
-- escape hatch this replaces.
--
--   Machine Type · Machine Make · D O M · Feeder · Running Hrs ·
--   Stroke/Min · Capacity · Machine No · Die Type
--
-- Each new column, and why it is the shape it is.

-- Its own column rather than the existing make_model, which is a trap: the
-- machine editor treats make_model, serial_number, location and
-- installation_date as legacy, reads them into custom fields on load and
-- writes them back EMPTY on every save (machine_form_screen.dart). Putting
-- Machine Make there would mean the Machines screen blanked it the next time
-- anyone opened a machine. make_model is left alone, unread and unwritten,
-- rather than quietly revived — the same call as storage_location on dies.
ALTER TABLE machines ADD COLUMN machine_make TEXT NOT NULL DEFAULT '';

-- A year, not a date. The sheet says "2011" and that is all anyone knows; a
-- stored 2011-01-01 would be three facts where there is one, and the screen
-- would print a day nobody recorded. Distinct from installation_date, which is
-- when the machine arrived here — a press built in 2011 may have been
-- installed in 2019, and those are different questions.
ALTER TABLE machines ADD COLUMN manufactured_year INTEGER;

-- The make of the feeder attached to this machine, as free text.
--
-- NOT the pipeline sense of the word. Everywhere else in this system a feeder
-- is an upstream node that feeds an assembly step (_feederStepNames,
-- _AssemblySummary). The sheet uses "Feeder" twice over — as a Machine Type
-- value and as this column — so the column and its label both say "make".
--
-- Free text with suggestions drawn from what has been typed before, not a
-- master: a feeder may one day be tracked as its own machine, and that is a
-- different change from recording the name on the press.
ALTER TABLE machines ADD COLUMN feeder_make TEXT NOT NULL DEFAULT '';

-- A meter reading and a rating. Integers: nobody records half a stroke, and a
-- meter reads whole hours. Nullable because "never read" is not "zero".
--
-- running_hours is the latest reading, not a log — the same shape as
-- dies.stroke_count. A machine's hours between services is a question for the
-- telemetry tables, not for this column.
ALTER TABLE machines ADD COLUMN running_hours INTEGER;
ALTER TABLE machines ADD COLUMN strokes_per_minute INTEGER;

-- Capacity, as a kind and a figure.
--
-- The kind is stored rather than inferred, the developed_for_kind rule from
-- 047: '' is nobody said, 'rated' means capacity_kgf holds it, 'free_hand'
-- means the machine has no rated capacity at all. No arrangement of a single
-- nullable number can tell "free hand" from "unfilled", and the sheet lists
-- both.
ALTER TABLE machines ADD COLUMN capacity_kind TEXT NOT NULL DEFAULT '';

-- An INTEGER COUNT OF KILOGRAMS-FORCE, which is the units contract's rule
-- rather than a preference (.claude/skills/units/SKILL.md): no floats in a
-- quantity, and a base small enough that every unit offered is a whole
-- multiple of it. A press quoted at 35 Ton is 35,000 kgf; a 1.5 Ton press is
-- 1,500. Both units the field offers land exactly.
--
-- As with dies.liner_size_nm, the units master has NO force family at all —
-- unit_groups is empty — so there is no unit_id to store and the symbol lives
-- in the UI. The same documented I3 deviation, and it gets the type when the
-- module exists.
ALTER TABLE machines ADD COLUMN capacity_kgf INTEGER;

-- What tooling the machine takes: Manual, Semi Prog, Progressive.
--
-- THIS IS NOT dies.die_type. That one is Cutting or Bending — what the die
-- does. This is how the machine feeds one. The two will be confused by the
-- next reader unless this says so.
--
-- Free text with suggestions, not a slug list, because the sheet's own column
-- ends in "Add New" — a vocabulary with an escape hatch is not a vocabulary,
-- the same call as a client contact's designation.
ALTER TABLE machines ADD COLUMN die_feed_type TEXT NOT NULL DEFAULT '';

-- Nothing is backfilled from custom_properties. "80T" parses; "2500mm",
-- "80 T" and whatever else is in that bag do not, and guessing writes a wrong
-- tonnage onto a real press.
--
-- Design checklist: no new event row and no new event_type. A machine's
-- tonnage, maker and feeder are attributes of an asset, not transitions it
-- goes through; machine_assigned / machine_released already carry the Capacity
-- cluster, and field-level history comes free because machines is in the
-- changelog triggers (040) and the route calls trackCreate/trackUpdate.
-- Feature-to-Metric: machines per type, rated tonnage available, strokes/min
-- by machine, and running hours between services — Capacity cluster.
--
-- No UNIQUE index here: the runner absorbs "duplicate column name" but NOT
-- "UNIQUE constraint failed", so an index a live database cannot satisfy would
-- stop every boot. asset_id's existing UNIQUE is enough, and the route now
-- refuses a clash by name before it reaches it.
CREATE INDEX IF NOT EXISTS idx_machines_make ON machines(machine_make) WHERE machine_make <> '';
CREATE INDEX IF NOT EXISTS idx_machines_capacity ON machines(capacity_kgf) WHERE capacity_kgf IS NOT NULL;
