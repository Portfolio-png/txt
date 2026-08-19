-- Clients and vendors carry a logo and a photo: ClientDefinition and
-- VendorDefinition both expose logoUrl/photoUrl, the editors upload to them and
-- the master cards render them. The columns only ever existed on databases that
-- had been through an older server, so a fresh install had the feature in the
-- app and nowhere to put the data.
--
-- Additive and idempotent: the runner absorbs "duplicate column name" on any
-- database that already has them.
ALTER TABLE clients ADD COLUMN logo_url TEXT DEFAULT '';
ALTER TABLE clients ADD COLUMN photo_url TEXT DEFAULT '';
ALTER TABLE vendors ADD COLUMN logo_url TEXT DEFAULT '';
ALTER TABLE vendors ADD COLUMN photo_url TEXT DEFAULT '';
