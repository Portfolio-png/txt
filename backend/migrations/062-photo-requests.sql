-- Photos the desktop asks the phone to take.
--
-- The item sheet is bulk entry; picking photos from the PC was the slow part,
-- because the photos are on the phone or not taken yet. A click on a photo
-- slot files one of these for the person who clicked; their phone, logged in
-- as them, shows the record's details over the camera and uploads through the
-- ordinary asset routes, then marks the job done. Owner-only: a request is
-- read, completed, skipped or cancelled only by the user who made it.
--
-- `context` is one line from the desktop about where the slot sits ("for part
-- HH1"); the record's own details are built when the phone asks, so they are
-- never stale.

CREATE TABLE IF NOT EXISTS photo_requests (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  entity_type TEXT NOT NULL,
  entity_id INTEGER NOT NULL,
  context TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending',
  asset_id INTEGER,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_photo_requests_user_status ON photo_requests(user_id, status);
