-- A part needs a size before it can be planned onto a sheet.
--
-- Sheet planning is nesting: given a sheet and a set of parts, work out how the
-- parts come off it. Nothing in the catalogue carried a part's blank size, so
-- every plan had to be typed by hand from a drawing — which is the data entry
-- the client is trying to stop doing.
--
-- Held on the item rather than on the die because the blank IS the item. The
-- die is the tool that happens to produce it, one part can outlive several
-- dies, and a part that is sheared to size has no die at all.
--
-- Millimetres, because that is what the floor measures a blank in, even where
-- the sheet it comes off is bought in inches. Zero means unmeasured, and the
-- planner says so rather than guessing a size.
ALTER TABLE items ADD COLUMN blank_width_mm REAL DEFAULT 0;
ALTER TABLE items ADD COLUMN blank_height_mm REAL DEFAULT 0;

-- Parts that can be planned. Partial, because most of the catalogue is raw
-- material and consumables that will never carry a blank size.
CREATE INDEX IF NOT EXISTS idx_items_blank_size
  ON items(blank_width_mm, blank_height_mm)
  WHERE blank_width_mm > 0 AND blank_height_mm > 0;
