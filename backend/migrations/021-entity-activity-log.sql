-- Track: rich, per-entity activity log (field-level create/update/delete feed)
-- surfaced as the "Track" tab on each master and on a person's People profile.
CREATE TABLE IF NOT EXISTS entity_activity_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_type TEXT NOT NULL,   -- 'items','clients','vendors','units','machines','dies','pipeline_templates','employees'
  entity_id TEXT NOT NULL,     -- stringified record id
  action TEXT NOT NULL,        -- 'created' | 'updated' | 'deleted'
  actor_user_id INTEGER,
  actor_name TEXT,
  actor_role TEXT,
  changes_json TEXT,           -- JSON array of {field, from, to} for updates
  details_json TEXT,           -- optional context e.g. {label}
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_entity_activity_log_entity
  ON entity_activity_log(entity_type, entity_id, created_at);
CREATE INDEX IF NOT EXISTS idx_entity_activity_log_actor
  ON entity_activity_log(actor_user_id, created_at);
