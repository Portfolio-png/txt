-- A set carries a photo like every other master: the Sets card leads with it in
-- card view, and the set editor uploads to it. Until now a set's picture could
-- only arrive through uploaded_assets, which the seeder can write but the editor
-- cannot — so a user had no way to give a set an image.
--
-- Additive and idempotent; the runner absorbs "duplicate column name".
ALTER TABLE inventory_sets ADD COLUMN photo_url TEXT DEFAULT '';
