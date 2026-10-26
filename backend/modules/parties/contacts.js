'use strict';

// ---------------------------------------------------------------------------
// The people at a company.
//
//   GET   /api/clients/:clientId/contacts                everyone, archived last
//   POST  /api/clients/:clientId/contacts                add one
//   PATCH /api/clients/:clientId/contacts/:id            change one (absent = keep)
//   PATCH /api/clients/:clientId/contacts/:id/archive    archive / restore
//
// Nested under the client on purpose: `clients` is the first path segment, so
// the central CRUD gate maps every route here to the clients module — its
// permissions and its per-record grants. A flat /api/party-contacts/:id would
// be an undeclared segment, which skips the per-module check entirely rather
// than failing closed.
//
// party_contacts is canonical; clients.contact_* is a mirror of the primary
// contact kept by mirrorPrimary() and nothing else. See 056-party-contacts.sql.
// ---------------------------------------------------------------------------

const CONTACT_FIELDS = {
  name: 'name',
  designation: 'designation',
  phone: 'phone',
  email: 'email',
  notes: 'notes',
};

function rowToContactDto(row) {
  if (!row) return null;
  return {
    id: row.id,
    partyType: row.party_type,
    partyId: row.party_id,
    name: row.name || '',
    designation: row.designation || '',
    phone: row.phone || '',
    email: row.email || '',
    notes: row.notes || '',
    isPrimary: row.is_primary === 1,
    isArchived: row.is_archived === 1,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function badRequest(message, statusCode = 400) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

/// Copies the primary contact onto the party's flat columns, or blanks them
/// when the party has no primary. The ONLY writer of clients.contact_*.
async function mirrorPrimary({ get, run }, partyType, partyId) {
  if (partyType !== 'client') return;
  const primary = await get(
    `SELECT * FROM party_contacts
     WHERE party_type = ? AND party_id = ? AND is_primary = 1`,
    [partyType, partyId],
  );
  await run(
    `UPDATE clients
     SET contact_name = ?, designation = ?, phone = ?, email = ?
     WHERE id = ?`,
    [
      primary?.name || '',
      primary?.designation || '',
      primary?.phone || '',
      primary?.email || '',
      partyId,
    ],
  );
}

/// Makes [contactId] the party's one primary, clearing any other.
async function makePrimary({ run }, partyType, partyId, contactId) {
  await run(
    `UPDATE party_contacts SET is_primary = 0
     WHERE party_type = ? AND party_id = ? AND id <> ? AND is_primary = 1`,
    [partyType, partyId, contactId],
  );
  await run('UPDATE party_contacts SET is_primary = 1 WHERE id = ?', [contactId]);
}

/// The client form still edits one person through flat fields. Whatever it
/// sends lands on the primary contact — created if the company has none and a
/// name was given — and the mirror follows. Absent fields are left alone.
///
/// A DIFFERENT name is a different person: they become the primary and the
/// one before stays on file, demoted. Renaming the row in place rewrote every
/// past deal that ticked them — "dealt with Ravi" became "dealt with Meena".
/// The same name (ignoring case and spacing) edits that person's details.
async function syncPrimaryFromFlat(db, clientId, { contactName, designation, phone, email }) {
  const { get, run } = db;
  const flat = { name: contactName, designation, phone, email };
  if (Object.values(flat).every((value) => value === undefined)) return;

  const primary = await get(
    `SELECT * FROM party_contacts
     WHERE party_type = 'client' AND party_id = ? AND is_primary = 1`,
    [clientId],
  );
  const now = new Date().toISOString();

  if (primary) {
    const sets = [];
    const params = [];
    for (const [column, value] of Object.entries(flat)) {
      if (value === undefined) continue;
      sets.push(`${column} = ?`);
      params.push(String(value || '').trim());
    }
    // Blanking the name on the form means "nobody to ring first" — the person
    // is archived rather than left nameless, and keeps their place on parts.
    const nameNow = flat.name === undefined ? primary.name : String(flat.name || '').trim();
    const samePerson = (a, b) =>
      String(a || '').trim().replace(/\s+/g, ' ').toLowerCase() ===
      String(b || '').trim().replace(/\s+/g, ' ').toLowerCase();
    if (!nameNow) {
      await run(
        'UPDATE party_contacts SET is_primary = 0, is_archived = 1, updated_at = ? WHERE id = ?',
        [now, primary.id],
      );
    } else if (!samePerson(nameNow, primary.name)) {
      await run(
        'UPDATE party_contacts SET is_primary = 0, updated_at = ? WHERE id = ?',
        [now, primary.id],
      );
      // Details not sent are the new person's to fill in, not the old one's
      // to lend: a phone left unchanged on the form was the previous person's.
      await run(
        `INSERT INTO party_contacts
           (party_type, party_id, name, designation, phone, email, is_primary, created_at, updated_at)
         VALUES ('client', ?, ?, ?, ?, ?, 1, ?, ?)`,
        [
          clientId,
          nameNow,
          String(flat.designation ?? '').trim(),
          String(flat.phone ?? '').trim(),
          String(flat.email ?? '').trim(),
          now,
          now,
        ],
      );
    } else {
      await run(
        `UPDATE party_contacts SET ${sets.join(', ')}, updated_at = ? WHERE id = ?`,
        [...params, now, primary.id],
      );
    }
  } else {
    const name = String(flat.name || '').trim();
    // A phone with nobody's name on it makes no person. Leave the flat
    // columns as saveClient wrote them rather than mirror a blank over them.
    if (!name) return;
    await run(
      `INSERT INTO party_contacts
         (party_type, party_id, name, designation, phone, email, is_primary, created_at, updated_at)
       VALUES ('client', ?, ?, ?, ?, ?, 1, ?, ?)`,
      [
        clientId,
        name,
        String(flat.designation || '').trim(),
        String(flat.phone || '').trim(),
        String(flat.email || '').trim(),
        now,
        now,
      ],
    );
  }
  await mirrorPrimary(db, 'client', clientId);
}

/// Hangs `contacts` on each client row, in ONE query whatever the count.
/// rowToClientDto reads it; a row without it simply lists nobody.
async function attachClientContacts({ all }, rows) {
  const list = Array.isArray(rows) ? rows : [rows];
  const ids = list.filter(Boolean).map((row) => row.id);
  if (!ids.length) return rows;
  const contacts = await all(
    `SELECT * FROM party_contacts
     WHERE party_type = 'client' AND party_id IN (${ids.map(() => '?').join(', ')})
     ORDER BY is_archived ASC, is_primary DESC, name COLLATE NOCASE ASC`,
    ids,
  );
  const byParty = new Map();
  for (const contact of contacts) {
    if (!byParty.has(contact.party_id)) byParty.set(contact.party_id, []);
    byParty.get(contact.party_id).push(rowToContactDto(contact));
  }
  for (const row of list) {
    if (row) row.contacts = byParty.get(row.id) || [];
  }
  return rows;
}

function registerPartyContactRoutes(ctx) {
  const { app, get, all, run, requirePermission, trackCreate, trackUpdate, emit } = ctx;
  const db = { get, all, run };

  const loadClient = async (req) => {
    const clientId = Number(req.params.clientId);
    const client = Number.isInteger(clientId) && clientId > 0
      ? await get('SELECT id FROM clients WHERE id = ?', [clientId])
      : null;
    if (!client) throw badRequest('No such client.', 404);
    return client.id;
  };

  const loadContact = async (clientId, id) => {
    const row = await get(
      `SELECT * FROM party_contacts WHERE id = ? AND party_type = 'client' AND party_id = ?`,
      [Number(id), clientId],
    );
    if (!row) throw badRequest('No such person at this client.', 404);
    return row;
  };

  const fail = (res, error) =>
    res.status(error.statusCode || 500).json({ success: false, error: error.message });

  app.get('/api/clients/:clientId/contacts', requirePermission('config.read'), async (req, res) => {
    try {
      const clientId = await loadClient(req);
      const rows = await all(
        `SELECT * FROM party_contacts
         WHERE party_type = 'client' AND party_id = ?
         ORDER BY is_archived ASC, is_primary DESC, name COLLATE NOCASE ASC`,
        [clientId],
      );
      res.json({ success: true, contacts: rows.map(rowToContactDto) });
    } catch (error) {
      fail(res, error);
    }
  });

  app.post('/api/clients/:clientId/contacts', requirePermission('config.write'), async (req, res) => {
    try {
      const clientId = await loadClient(req);
      const body = req.body || {};
      const name = String(body.name || '').trim();
      if (!name) throw badRequest('A person needs a name.');

      const others = await get(
        `SELECT COUNT(*) AS count FROM party_contacts
         WHERE party_type = 'client' AND party_id = ? AND is_archived = 0`,
        [clientId],
      );
      // The first person at a company is the one to ring first until someone
      // says otherwise.
      const primary = body.isPrimary === true || Number(others?.count || 0) === 0;

      const now = new Date().toISOString();
      await run('BEGIN TRANSACTION');
      let id;
      try {
        const result = await run(
          `INSERT INTO party_contacts
             (party_type, party_id, name, designation, phone, email, notes, is_primary, created_at, updated_at)
           VALUES ('client', ?, ?, ?, ?, ?, ?, 0, ?, ?)`,
          [
            clientId,
            name,
            String(body.designation || '').trim(),
            String(body.phone || '').trim(),
            String(body.email || '').trim(),
            String(body.notes || '').trim(),
            now,
            now,
          ],
        );
        id = result.lastID;
        if (primary) await makePrimary(db, 'client', clientId, id);
        await mirrorPrimary(db, 'client', clientId);
        await run('COMMIT');
      } catch (error) {
        await run('ROLLBACK');
        throw error;
      }

      const row = await get('SELECT * FROM party_contacts WHERE id = ?', [id]);
      if (trackCreate) trackCreate('party_contacts', id, row, req);
      if (emit) emit(clientId);
      res.status(201).json({ success: true, contact: rowToContactDto(row) });
    } catch (error) {
      fail(res, error);
    }
  });

  const update = async (req, res, body) => {
    const clientId = await loadClient(req);
    const before = await loadContact(clientId, req.params.id);

    const sets = [];
    const params = [];
    for (const [field, column] of Object.entries(CONTACT_FIELDS)) {
      if (!(field in body)) continue;
      const value = String(body[field] || '').trim();
      if (column === 'name' && !value) throw badRequest('A person needs a name.');
      sets.push(`${column} = ?`);
      params.push(value);
    }
    const archiving = 'isArchived' in body ? Boolean(body.isArchived) : null;
    if (archiving !== null) {
      sets.push('is_archived = ?');
      params.push(archiving ? 1 : 0);
      // An archived person is nobody's first call.
      if (archiving) sets.push('is_primary = 0');
    }

    await run('BEGIN TRANSACTION');
    try {
      if (sets.length) {
        await run(
          `UPDATE party_contacts SET ${sets.join(', ')}, updated_at = ? WHERE id = ?`,
          [...params, new Date().toISOString(), before.id],
        );
      }
      if (body.isPrimary === true && archiving !== true) {
        // Someone archived stays out of the first-call slot until restored —
        // or the client's flat phone and email would be an archived person's.
        if (archiving === null && before.is_archived === 1) {
          throw badRequest('Restore this person before making them the first call.');
        }
        await makePrimary(db, 'client', clientId, before.id);
      } else if (body.isPrimary === false) {
        await run('UPDATE party_contacts SET is_primary = 0 WHERE id = ?', [before.id]);
      }
      // Archiving the first call hands the slot to the longest-standing person
      // still on file — the rule a company's first person follows. Left empty,
      // the client had no primary for good (nothing in the app sets one) and
      // its phone and email read blank.
      if (archiving === true && before.is_primary === 1) {
        const next = await get(
          `SELECT id FROM party_contacts
           WHERE party_type = 'client' AND party_id = ? AND is_archived = 0 AND id <> ?
           ORDER BY id ASC LIMIT 1`,
          [clientId, before.id],
        );
        if (next) await makePrimary(db, 'client', clientId, next.id);
      }
      await mirrorPrimary(db, 'client', clientId);
      await run('COMMIT');
    } catch (error) {
      await run('ROLLBACK');
      throw error;
    }

    const after = await get('SELECT * FROM party_contacts WHERE id = ?', [before.id]);
    if (trackUpdate) trackUpdate('party_contacts', before.id, before, after, req);
    if (emit) emit(clientId);
    res.json({ success: true, contact: rowToContactDto(after) });
  };

  app.patch('/api/clients/:clientId/contacts/:id/archive', requirePermission('config.write'), async (req, res) => {
    try {
      const body = req.body || {};
      await update(req, res, { isArchived: 'isArchived' in body ? body.isArchived : true });
    } catch (error) {
      fail(res, error);
    }
  });

  app.patch('/api/clients/:clientId/contacts/:id', requirePermission('config.write'), async (req, res) => {
    try {
      await update(req, res, req.body || {});
    } catch (error) {
      fail(res, error);
    }
  });
}

module.exports = registerPartyContactRoutes;
module.exports.rowToContactDto = rowToContactDto;
module.exports.attachClientContacts = attachClientContacts;
module.exports.syncPrimaryFromFlat = syncPrimaryFromFlat;
module.exports.mirrorPrimary = mirrorPrimary;
