-- A variation property whose values come from the material master.
--
-- Gauge was the first input type whose values are not free text, and it stores
-- them the wrong way: a verbatim suffixed string ("0.711mm", "22G") with no
-- metadata travelling alongside it, so nothing downstream can get back to the
-- table the value came from. Material must not repeat that.
--
-- A value node under a Material property therefore carries the id of the
-- material type it stands for. Every selection already records the leaf node it
-- landed on, so the id reaches an order line, a challan line and a stock row
-- with no new per-line storage at all — and with the id comes the density, which
-- is what turns a sheet's dimensions into a weight and a weight back into an
-- area.
--
-- Nullable, and no cascade: a material type that is archived or renamed must not
-- take variation values with it. A value whose material type has gone still
-- names itself; it has simply lost the link.
ALTER TABLE item_variation_nodes ADD COLUMN material_type_id INTEGER REFERENCES material_types(id);

CREATE INDEX IF NOT EXISTS idx_item_variation_nodes_material_type
  ON item_variation_nodes(material_type_id);
