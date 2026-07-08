-- Create the changelog table to track real-time events for SSE broadcast
CREATE TABLE IF NOT EXISTS changelog (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  table_name TEXT NOT NULL,
  record_id INTEGER NOT NULL,
  event_type TEXT NOT NULL CHECK(event_type IN ('INSERT','UPDATE','DELETE')),
  timestamp TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_changelog_timestamp ON changelog(timestamp);
