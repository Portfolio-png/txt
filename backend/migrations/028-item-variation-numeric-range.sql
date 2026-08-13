-- Numeric variation properties carry an allowed range, captured in the item
-- editor when a property's input type is switched to 'Numeric'. NULL on both
-- columns means "unbounded" (every pre-existing Numeric property).
ALTER TABLE item_variation_nodes ADD COLUMN numeric_min REAL;
ALTER TABLE item_variation_nodes ADD COLUMN numeric_max REAL;
