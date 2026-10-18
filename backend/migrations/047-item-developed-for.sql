-- Who a part was developed for, when, and what was quoted.
--
-- A part recorded nothing about why it exists. There was a vestigial
-- items.developed_for_client_id — a client id, pickable from one chip in the
-- item editor — but nothing outside that editor ever showed it and nothing ever
-- queried by it, so the comment on that column ("so it can be listed under
-- them") was never true. The floor wants the whole row: for whom, which person
-- there, when, and the figure quoted.
--
-- The person lives on the COMPANY, the way a vendor's contact already does
-- (vendors carries contact_name/phone/email). A client gains the same three
-- plus a designation, so "Kissan Jain, Director, 986565656" is answered once
-- per company rather than retyped on every part.
--
-- clients.contact_* is the company's own primary contact — the person you ring
-- about this company. sub_contractors are parties you give work TO. The two
-- overlap by nature and the same human may appear in both; they are not the
-- same fact and should not be merged.
--
-- A part's "For" is one of '', 'self', 'client' or 'contractor'. The string is
-- stored rather than derived from which id is set, because "developed in-house"
-- and "nobody filled this in yet" are different facts and no pair of ids can
-- tell them apart — the same reason part_no is NULL rather than 0.
--
-- Design checklist: no new event row. This is an attribute of a part, not a
-- floor transition, and field-level history comes free through diffRows into
-- entity_activity_log on every PATCH. developed_for_at is the occurrence time
-- (when the part was developed for them); items.created_at remains the entry
-- time. Feature-to-Metric: parts developed per client, quotation value, and
-- quote-to-first-order lag, in the Commercial cluster.
ALTER TABLE clients ADD COLUMN contact_name TEXT DEFAULT '';
ALTER TABLE clients ADD COLUMN designation TEXT DEFAULT '';
ALTER TABLE clients ADD COLUMN phone TEXT DEFAULT '';
ALTER TABLE clients ADD COLUMN email TEXT DEFAULT '';

-- So a contractor answers the same four questions a client does.
ALTER TABLE sub_contractors ADD COLUMN designation TEXT DEFAULT '';

ALTER TABLE items ADD COLUMN developed_for_kind TEXT NOT NULL DEFAULT '';
ALTER TABLE items ADD COLUMN developed_for_sub_contractor_id INTEGER;

-- A full ISO instant in UTC, like orders.start_date — the only date convention
-- in this app that keeps a time, which this one needs ("15/05/2026 10.05 AM").
-- Never read its fields directly: the client converts with .toLocal() first.
ALTER TABLE items ADD COLUMN developed_for_at TEXT;

-- Rupees, REAL, like every other amount here (orders.unit_price,
-- invoice_headers.total_amount). Nullable on purpose: quoted at zero and never
-- quoted are different, and NOT NULL DEFAULT 0 would print ₹0.00 across the
-- whole catalogue.
ALTER TABLE items ADD COLUMN developed_for_quotation_amount REAL;

-- Every part that already named a client was, by definition, developed for one.
UPDATE items SET developed_for_kind = 'client' WHERE developed_for_client_id IS NOT NULL;

-- The first queries by these columns: today nothing filters on them at all.
CREATE INDEX IF NOT EXISTS idx_items_developed_for_client
  ON items(developed_for_client_id)
  WHERE developed_for_client_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_items_developed_for_contractor
  ON items(developed_for_sub_contractor_id)
  WHERE developed_for_sub_contractor_id IS NOT NULL;
