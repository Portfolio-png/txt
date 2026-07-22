-- Per-record (row-level) permission grants for an individual user.
-- Presence of a row = that user is allowed `op` on that specific record, even
-- when they lack the module-level permission. op in ('read','update','delete').
-- Create is module-level only (you can't "create" a specific existing record).
CREATE TABLE IF NOT EXISTS user_record_permissions (
  user_id INTEGER NOT NULL,
  entity_type TEXT NOT NULL,   -- 'items','clients','vendors','units','machines','dies','people'
  entity_id TEXT NOT NULL,
  op TEXT NOT NULL,            -- 'read' | 'update' | 'delete'
  created_at TEXT NOT NULL,
  PRIMARY KEY (user_id, entity_type, entity_id, op)
);
CREATE INDEX IF NOT EXISTS idx_user_record_permissions_user
  ON user_record_permissions(user_id);
