-- Which kind of device a login session belongs to ('desktop' | 'mobile').
--
-- A login now ends only the same user's sessions on the same kind of device,
-- so one person can be on the desktop and the phone at once — the phone is
-- where the desktop sends photos to be taken. Rows from before this column
-- read as desktop.
--
-- Alone in its file and last: both runners tolerate the duplicate column on a
-- second boot, and a failing statement would skip anything after it.

ALTER TABLE auth_sessions ADD COLUMN client_platform TEXT DEFAULT 'desktop';
