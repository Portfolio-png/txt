-- Sittings: which opening of a window a change belongs to.
--
-- `entity_activity_log` already says who changed what. It has never said what
-- else was changed at the same time, so "where did the die I just made go?"
-- had no answer the server could give — the records were made together and
-- nothing recorded that.
--
-- One nullable column, filled from the `X-Paper-Sitting` header by
-- `logEntityActivity`, so all ~26 existing trackCreate/Update/Delete call sites
-- gain it without being touched. NULL is the honest value for everything
-- written before this and for every write made outside a window.
--
-- Both statements are idempotent on purpose. Two runners execute this file on
-- EVERY boot — `migrate.js` first (it tolerates only /duplicate column name/i)
-- and then `modules/kernel/migration-runner.js` from inside initDb — so the
-- second pass must fail in exactly the way they both already forgive.
--
-- The same column is in the inline definition in `server.js` initDb. Change
-- both or fresh and existing databases drift apart.

ALTER TABLE entity_activity_log ADD COLUMN sitting_id TEXT;

CREATE INDEX IF NOT EXISTS idx_entity_activity_log_sitting
  ON entity_activity_log(sitting_id, created_at);
