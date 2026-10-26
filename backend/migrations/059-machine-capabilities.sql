-- A machine's capabilities — what it can do (blanking up to a size, piercing,
-- forming), as the machine form's Capabilities section lists them.
--
-- The form has always shown and sent them, and POST /api/machines has never
-- read them: there was no column, so everything typed there was gone on the
-- next load. Demo mode kept them in memory, which is why it looked fine.
--
-- JSON, like custom_properties beside it: the list's shape belongs to the
-- form, and nothing queries inside it. Re-run safe: both runners tolerate the
-- duplicate column on the second boot.

ALTER TABLE machines ADD COLUMN capabilities_json TEXT NOT NULL DEFAULT '[]';
