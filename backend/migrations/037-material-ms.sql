-- "Steel / MS" becomes "MS".
--
-- The seed shipped one row doing two jobs: a slash-joined name covering both
-- "steel" generally and mild steel specifically. On a shop floor it is called
-- MS, so that is what the list should say.
--
-- Done as a **rename in place rather than a delete and re-insert**, because
-- `item_variation_nodes.material_type_id` points at these rows by id. Deleting
-- the old row would leave every variation value that named it pointing at
-- nothing — which the app renders as "Material missing", on items that were
-- perfectly fine. Renaming keeps the id, so every existing link still resolves
-- and picks up the new name for free.
--
-- Density is unchanged: mild steel is 7.85 g/cm³, which is what the row already
-- carried. Nothing that has been weighed against it changes value.
--
-- Written to be safe in any order and to run on a database where someone has
-- already added an "MS" of their own — the name has a UNIQUE NOCASE index, so
-- a blind rename would fail there.

-- 1. If an "MS" row already exists, move anything pointing at "Steel / MS"
--    onto it first, so nothing is orphaned by step 2.
UPDATE item_variation_nodes
SET material_type_id = (
  SELECT id FROM material_types WHERE name = 'MS' COLLATE NOCASE LIMIT 1
)
WHERE material_type_id = (
  SELECT id FROM material_types WHERE name = 'Steel / MS' COLLATE NOCASE LIMIT 1
)
AND EXISTS (SELECT 1 FROM material_types WHERE name = 'MS' COLLATE NOCASE);

-- 2. Then the duplicate can go: nothing references it any more.
DELETE FROM material_types
WHERE name = 'Steel / MS' COLLATE NOCASE
AND EXISTS (SELECT 1 FROM material_types WHERE name = 'MS' COLLATE NOCASE);

-- 3. The ordinary case — no "MS" yet. Rename in place and keep the id.
UPDATE material_types
SET name = 'MS',
    notes = 'Mild steel — the common shop default',
    updated_at = datetime('now')
WHERE name = 'Steel / MS' COLLATE NOCASE;

-- 4. And a database that never had the seed row still ends up with MS.
INSERT OR IGNORE INTO material_types (name, density_g_cm3, category, notes)
VALUES ('MS', 7.85, 'metal', 'Mild steel — the common shop default');
