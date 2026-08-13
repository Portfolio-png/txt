-- Per-item sample baseline (pen & paper yield record). Distinct from
-- pipeline_templates.pen_paper_baseline_json, which is shared by every item on
-- the template: basic items each record their own sample run. NULL = never
-- recorded.
ALTER TABLE items ADD COLUMN pen_paper_baseline_json TEXT;
