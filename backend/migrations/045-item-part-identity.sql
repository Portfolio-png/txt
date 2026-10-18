-- A part needs a number and a code a human can read out.
--
-- The floor does not say "item 312". It says "the forty-eighth Dolly patti in
-- Switch Action", and writes SADP48 on the drawing: the initials of the group,
-- the set and the part name, then the number. Nothing in the catalogue carried
-- either, so every drawing reference had to be matched to an item by name.
--
-- This is NOT the barcode system. A barcode resolves an item by ITM:<id>
-- (kernel/barcodes.js); short_code is only the subtitle a scan shows, and is
-- deliberately left alone here. A part code is for a person reading a drawing,
-- which is why it is short, lossy and editable, and why it is kept out of the
-- resolver.
--
-- part_no is a STAMP, not a sequence invariant. It records which number this
-- part was issued when it was created, under whatever group and set were in
-- play then. Nothing here stops two rows in one scope holding the same number,
-- and the number does not follow an item later moved to another group or added
-- to another set. The durable guard is the unique index on the code below.
-- NULL means never stamped, which is a different fact from numbered zero.
ALTER TABLE items ADD COLUMN part_no INTEGER;
ALTER TABLE items ADD COLUMN part_code TEXT NOT NULL DEFAULT '';

-- Unique per group, not globally. Numbers restart per group and set, so
-- ("Switch Action", "Dolly", "Patti", 48) and ("Steel Angle", "Die", "Plate",
-- 48) both derive SADP48 and are both legitimate parts; a global index would
-- refuse the second and make a user hand-edit a code the system proposed.
--
-- Partial, on a non-empty code: a part code is optional, every row this
-- migration touches starts at '', and any number of those must coexist. Built
-- in this file, immediately after the ALTER, so it can only ever be created
-- against an all-empty column — the migration runner tolerates "duplicate
-- column name" but not a UNIQUE constraint failure, which would stop the
-- server booting.
CREATE UNIQUE INDEX IF NOT EXISTS idx_items_part_code
  ON items(group_id, part_code)
  WHERE part_code <> '';

CREATE INDEX IF NOT EXISTS idx_items_part_no
  ON items(group_id, part_no)
  WHERE part_no IS NOT NULL;

-- Design checklist: a new canonical attribute of an item, not a view of one.
-- No floor transition, so no event row and no new event_type — created_at is
-- the time, and it is entry time rather than floor time. No new row in the
-- Feature-to-Metric Map: this makes existing items addressable by a readable
-- code, which belongs to the Identifiers and Barcodes lane. One code rule for
-- every client; a client that wants its own would be a preference, not a
-- branch in the builder.
