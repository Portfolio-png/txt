-- Master Data is keyed by (variant, pipeline), not by one or the other.
--
-- A pipeline is shared: the same "Cut → Punch → Deburr" makes dozens of
-- variants, each with its own weights, piece counts, scrap and rejection. One
-- baseline on the pipeline template cannot describe them all, and one baseline
-- on the item silently reinterprets the same numbers whenever the item's
-- pipeline is changed. So a pipeline carries as many Master Data records as
-- there are variants running through it, one per pair.
--
-- Resolution when a run or an order needs the baseline for (variant, pipeline):
--   1. the exact pair            -> a match
--   2. the variant's own record  -> a match, adopted onto the pair
--   3. the pipeline's own record -> a match, adopted onto the pair
--   4. nothing                   -> new data is created for the pair
-- `origin` records which of those produced the row, so the insight view can
-- say whether a variant was measured or inherited.
CREATE TABLE IF NOT EXISTS item_pipeline_baselines (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  pipeline_id TEXT NOT NULL,
  baseline_json TEXT NOT NULL,
  -- manual: typed against this pair. item: adopted from the variant's own
  -- record. pipeline: adopted from the pipeline template's record. new: created
  -- because nothing matched.
  origin TEXT NOT NULL DEFAULT 'manual',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- One record per pair: this is what makes "is there a match?" a lookup rather
-- than a search, and what stops a second run creating a duplicate.
CREATE UNIQUE INDEX IF NOT EXISTS idx_item_pipeline_baselines_pair
  ON item_pipeline_baselines(item_id, pipeline_id);

CREATE INDEX IF NOT EXISTS idx_item_pipeline_baselines_pipeline
  ON item_pipeline_baselines(pipeline_id);

-- Carry over what is already recorded. An item's existing baseline was authored
-- against whatever pipeline it points at, so that pair is where it belongs.
-- Items with no default pipeline keep it on items.pen_paper_baseline_json,
-- which stays as the variant-level fallback for step 2 above.
INSERT OR IGNORE INTO item_pipeline_baselines
  (item_id, pipeline_id, baseline_json, origin, created_at, updated_at)
SELECT
  id,
  default_pipeline_id,
  pen_paper_baseline_json,
  'manual',
  datetime('now'),
  datetime('now')
FROM items
WHERE pen_paper_baseline_json IS NOT NULL
  AND TRIM(COALESCE(pen_paper_baseline_json, '')) NOT IN ('', '{}', 'null')
  AND default_pipeline_id IS NOT NULL
  AND TRIM(COALESCE(default_pipeline_id, '')) <> '';
