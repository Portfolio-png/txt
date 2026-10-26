-- The people at a company, as many as it has, and which of them a part's deal
-- was done with.
--
-- 047 put ONE person on a client (contact_name/designation/phone/email) and
-- said "the person lives on the company". The company was right; the one was
-- not. A deal happens with whoever picks up the phone — the director one week,
-- the purchase manager the next — and the shop wants every one of them on file.
-- The quotation stays one figure per part: it does not change with who was
-- spoken to, so it stays on items.
--
-- party_contacts is CANONICAL. The flat clients.contact_* columns survive as a
-- MIRROR of the primary contact, written by exactly one helper
-- (modules/parties/contacts.js mirrorPrimary), so every reader that already
-- uses them — the client DTO, developedForDto's JOIN, the wizard — stays right
-- without being touched. Nothing writes those columns any other way.
--
-- party_type is generic because vendors and die makers carry the same flat
-- contact shape and will want the same list; only clients are wired today.
-- Contacts are archived, never deleted, once a part names them.
--
-- item_deal_contacts is its own table rather than entity_links: the ticks are
-- part of a part's developed-for block, rewritten with it wholesale, and must
-- belong to that block's client — a rule a generic link store cannot hold.
-- Same reasoning that kept item_dies out of entity_links (043).
--
-- Design checklist: no floor event. People at a customer are master data, and
-- field history comes through trackCreate/trackUpdate into
-- entity_activity_log. Feature-to-Metric: deals per contact and who brings
-- work, in the Commercial cluster beside 047's parts-per-client.
--
-- Idempotent: both migration runners run every file on every boot.

CREATE TABLE IF NOT EXISTS party_contacts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  party_type TEXT NOT NULL CHECK (party_type IN ('client', 'vendor', 'die_maker')),
  party_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  designation TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  email TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  is_primary INTEGER NOT NULL DEFAULT 0,
  is_archived INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_party_contacts_party
  ON party_contacts(party_type, party_id);

-- At most one person to ring first per company. Partial, so any number of
-- non-primary rows coexist.
CREATE UNIQUE INDEX IF NOT EXISTS ux_party_contacts_primary
  ON party_contacts(party_type, party_id) WHERE is_primary = 1;

CREATE TABLE IF NOT EXISTS item_deal_contacts (
  item_id INTEGER NOT NULL,
  contact_id INTEGER NOT NULL,
  PRIMARY KEY (item_id, contact_id)
);

CREATE INDEX IF NOT EXISTS idx_item_deal_contacts_contact
  ON item_deal_contacts(contact_id);

-- Every client that already has a person becomes a company with one primary
-- contact. Guarded by NOT EXISTS so the second boot adds nothing.
INSERT INTO party_contacts (party_type, party_id, name, designation, phone, email, is_primary)
SELECT 'client', clients.id, TRIM(clients.contact_name),
       COALESCE(clients.designation, ''), COALESCE(clients.phone, ''),
       COALESCE(clients.email, ''), 1
FROM clients
WHERE TRIM(COALESCE(clients.contact_name, '')) <> ''
  AND NOT EXISTS (
    SELECT 1 FROM party_contacts p
    WHERE p.party_type = 'client' AND p.party_id = clients.id
  );
