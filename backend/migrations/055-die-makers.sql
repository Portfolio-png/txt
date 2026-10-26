-- Die makers: the master behind "Die Made By".
--
-- Migration 048 made `dies.made_by` free text and argued for it:
--
--   "Free text, deliberately. A die is made by a fitter on the floor or by an
--    outside toolroom, and a master that can hold only one of those would be
--    wrong half the time. The field suggests names already used on a die,
--    which is the useful half of a master without the maintenance."
--
-- That is reversed here, on the shop's instruction. What it got right is kept:
-- the text column SURVIVES. A die maker is now a record with an address, a GST
-- number and a person to ring — the same shape as a client, because that is
-- what was asked for and because an outside toolroom is a company you invoice.
-- A fitter on the floor is not, and the fields a fitter cannot answer are all
-- optional for exactly that reason. Nothing is backfilled: existing dies keep
-- the name someone typed, `die_maker_id` is simply null on them, and a read
-- prefers the master and falls back to the text — the same prefer-new,
-- fall-back-to-old shape 048 used for store_area/rack_no vs storage_location.
--
-- Column for column this mirrors `clients` (001-init + 030 photos + 047
-- contact), which is the form the shop asked to reuse. It is a fourth party
-- table beside clients, vendors and sub_contractors rather than a `kind` on a
-- shared one, because there is no shared one: 047 declined to merge client and
-- contractor ("the two overlap by nature and the same human may appear in
-- both; they are not the same fact and should not be merged") and this follows
-- that ruling rather than relitigating it.
--
-- It is NOT its own permission module. A die maker is part of die tooling, so
-- /api/die-makers is gated by dies.read / dies.create / dies.update /
-- dies.delete — the segment is declared in moduleOpForRequest, because an
-- undeclared one returns null and skips the per-module CRUD check entirely.

CREATE TABLE IF NOT EXISTS die_makers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  alias TEXT DEFAULT '',
  gst_number TEXT DEFAULT '',
  address TEXT DEFAULT '',
  contact_name TEXT DEFAULT '',
  designation TEXT DEFAULT '',
  phone TEXT DEFAULT '',
  email TEXT DEFAULT '',
  logo_url TEXT DEFAULT '',
  photo_url TEXT DEFAULT '',
  is_archived INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Name is how a die maker is picked and how a typed name is matched, so it is
-- the one thing that must not be ambiguous. NOCASE for the same reason
-- material_types.name is: "Sharma Tools" and "sharma tools" are one toolroom.
-- Partial, so archiving does not free the name for a second record that would
-- then collide on restore.
CREATE UNIQUE INDEX IF NOT EXISTS idx_die_makers_name
  ON die_makers(name COLLATE NOCASE);

-- The link from a die to its maker. Nullable on purpose: every die that exists
-- today has a name and no id, and that is a legal state, not a backlog.
ALTER TABLE dies ADD COLUMN die_maker_id INTEGER REFERENCES die_makers(id);

CREATE INDEX IF NOT EXISTS idx_dies_die_maker
  ON dies(die_maker_id) WHERE die_maker_id IS NOT NULL;

-- A die type the shop typed rather than picked.
--
-- `dies.die_type` holds a slug and the four built-in slugs are mirrored in
-- modules/dies/die-identity.js and the Dart DieType enum. A typed type has no
-- entry in either, so its LABEL has to be stored — the code is built from the
-- label's initials ("Deep Drawing" -> DD -> DDD<part code>), and a slug whose
-- label cannot be recovered derives an empty code.
--
-- Empty means "one of the four built-ins, look the label up by slug". That
-- keeps every existing row correct without touching it.
ALTER TABLE dies ADD COLUMN die_type_label TEXT NOT NULL DEFAULT '';
