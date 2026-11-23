'use strict';

// Who a part was developed for: the deal (client or sub-contractor, the
// quotation and cost) and the people it was done with.
//
// A factory: `deps` is what server.js still owns (the database helpers and
// a few shared helpers), `api` is the items service being assembled, through
// which these reach the sibling files; both are read at call time.



function createDevelopedFor(deps, api) {
  const { desk } = deps;
  const { all, get, run } = deps;

  // The four columns behind "Developed For" (migrations/047), validated and
  // resolved into what the row should hold.
  //
  // Returns `undefined` when the caller said nothing, which is how every other
  // optional field on saveItem preserves what is stored — a seed, an
  // ensureItemRecord re-save or a PATCH about the name must not erase who a part
  // was made for. A present block with kind 'self' is how you clear it.
  //
  // For a contractor the PARENT CLIENT is derived and stored alongside, the way
  // saveOrder does it: without that, "For: Contractor" has no company name to
  // print, and a future "parts for this client" would silently exclude every
  // part made through one of their contractors.
  // Which of the client's people the deal was done with (056).
  //
  // Absent → undefined, and saveItem keeps what is ticked unless the client
  // itself changed. Present → the whole list, replacing what was there. Every id
  // must be a person at THIS client: a tick from another company would put a
  // stranger on the part. Archived people are allowed, the way an archived
  // client is — a part dealt with someone who has since left still records it.
  async function normalizeDealContactIds(raw, clientId) {
    if (raw === undefined) return undefined;
    if (raw === null) return [];
    if (!Array.isArray(raw)) {
      const error = new Error('contactIds must be a list of contact ids.');
      error.statusCode = 400;
      throw error;
    }
    const ids = [];
    for (const value of raw) {
      const id = Number(value);
      if (!Number.isInteger(id) || id <= 0) {
        const error = new Error('contactIds must be a list of contact ids.');
        error.statusCode = 400;
        throw error;
      }
      if (!ids.includes(id)) ids.push(id);
    }
    if (!ids.length) return ids;
    if (!clientId) {
      const error = new Error("Only a client's people can be marked on the deal.");
      error.statusCode = 400;
      throw error;
    }
    // The people are the clients module's; it is asked who they are.
    const found = (await desk.ask('clients.contacts.byIds', { ids })).rows.filter(
      (person) => person.party_type === 'client' && Number(person.party_id) === Number(clientId),
    );
    if (found.length !== ids.length) {
      const error = new Error('Every person marked on the deal must work at its client.');
      error.statusCode = 400;
      throw error;
    }
    return ids;
  }

  async function normalizeDevelopedFor(developedFor) {
    if (developedFor === undefined) return undefined;
    if (developedFor === null) {
      return {
        kind: '',
        clientId: null,
        subContractorId: null,
        at: null,
        quotationAmount: null,
        costAmount: null,
        contactIds: [],
      };
    }

    const kind = String(developedFor.kind || '').trim();
    if (!['', 'self', 'client', 'contractor'].includes(kind)) {
      const error = new Error("Developed for must be one of self, client or contractor.");
      error.statusCode = 400;
      throw error;
    }

    const rawClientId = developedFor.clientId ? Number(developedFor.clientId) : null;
    const rawSubContractorId = developedFor.subContractorId
      ? Number(developedFor.subContractorId)
      : null;

    const at = String(developedFor.at || '').trim() || null;
    const quotationRaw = developedFor.quotationAmount;
    let quotationAmount = null;
    if (quotationRaw !== null && quotationRaw !== undefined && quotationRaw !== '') {
      const parsed = Number(quotationRaw);
      if (!Number.isFinite(parsed) || parsed < 0) {
        const error = new Error('Quotation must be an amount of zero or more.');
        error.statusCode = 400;
        throw error;
      }
      quotationAmount = parsed;
    }

    const costRaw = developedFor.costAmount;
    // Absent = keep what is stored, the contactIds rule: the cost is entered
    // somewhere other than every screen that sends this block, so a save from
    // one of those must not wipe it. An explicit null still clears.
    let costAmount = Object.prototype.hasOwnProperty.call(developedFor, 'costAmount')
      ? null
      : undefined;
    if (costRaw !== null && costRaw !== undefined && costRaw !== '') {
      const parsed = Number(costRaw);
      if (!Number.isFinite(parsed) || parsed < 0) {
        const error = new Error('Development cost must be an amount of zero or more.');
        error.statusCode = 400;
        throw error;
      }
      costAmount = parsed;
    }

    // 'self' means developed in-house, so no party at all — and that is a
    // different fact from '' (nobody has filled this in yet), which is why the
    // kind is stored rather than inferred from which id happens to be set.
    if (kind === 'self') {
      // No party, so nobody to have dealt with. A tick sent anyway is refused.
      await normalizeDealContactIds(developedFor.contactIds, null);
      return {
        kind, clientId: null, subContractorId: null, at, quotationAmount, costAmount,
        contactIds: [],
      };
    }

    if (kind === 'contractor') {
      if (!rawSubContractorId) {
        const error = new Error('Pick the contractor this part was developed for.');
        error.statusCode = 400;
        throw error;
      }
      const { row: contractor } = await desk.ask('clients.subContractors.row', { id: rawSubContractorId });
      if (!contractor) {
        const error = new Error('Selected contractor does not exist.');
        error.statusCode = 400;
        throw error;
      }
      // A contractor is owned by one client. If the caller named a different one
      // it is a mistake worth refusing rather than quietly overruling — the two
      // answers would disagree about which company the part belongs to.
      if (rawClientId && Number(contractor.client_id || 0) !== rawClientId) {
        const error = new Error('That contractor belongs to a different client.');
        error.statusCode = 400;
        throw error;
      }
      // A contractor IS the person, so there is nobody else there to tick.
      await normalizeDealContactIds(developedFor.contactIds, null);
      return {
        kind,
        clientId: contractor.client_id || null,
        subContractorId: contractor.id,
        at,
        quotationAmount,
        costAmount,
        contactIds: [],
      };
    }

    if (kind === 'client') {
      if (!rawClientId) {
        const error = new Error('Pick the client this part was developed for.');
        error.statusCode = 400;
        throw error;
      }
      // No is_archived check: a part made for a client who has since been
      // archived still records that fact, and the read resolves the name either
      // way. Only the picker hides archived rows.
      const { row: client } = await desk.ask('clients.rows.get', { id: rawClientId });
      if (!client) {
        const error = new Error('Selected client does not exist.');
        error.statusCode = 400;
        throw error;
      }
      return {
        kind, clientId: client.id, subContractorId: null, at, quotationAmount, costAmount,
        contactIds: await normalizeDealContactIds(developedFor.contactIds, client.id),
      };
    }

    // kind '' — explicitly emptied. A client id arriving with it is the legacy
    // shape (developed_for_client_id with nothing to say about kind), and the
    // only thing it can have meant is 'client'.
    if (rawClientId) {
      return {
        kind: 'client',
        clientId: rawClientId,
        subContractorId: null,
        at,
        quotationAmount,
        costAmount,
        contactIds: await normalizeDealContactIds(developedFor.contactIds, rawClientId),
      };
    }
    await normalizeDealContactIds(developedFor.contactIds, null);
    return {
      kind: '', clientId: null, subContractorId: null, at, quotationAmount, costAmount,
      contactIds: [],
    };
  }

  // Replaces the people ticked on a part's deal. Called inside saveItem's
  // transaction, after normalizeDealContactIds has checked every id.
  async function writeDealContacts(itemId, contactIds) {
    await run('DELETE FROM item_deal_contacts WHERE item_id = ?', [itemId]);
    for (const contactId of contactIds) {
      await run(
        'INSERT OR IGNORE INTO item_deal_contacts (item_id, contact_id) VALUES (?, ?)',
        [itemId, contactId],
      );
    }
  }

  // Who a part was developed for, read off the columns the item queries join in
  // (migrations/047). A row, not nine loose fields: it crosses the border, the
  // Dart domain, two inputs and three screens, and developedForClientId already
  // taught us what nine of those look like.
  //
  // The person is resolved FROM THE PARTY, so changing a client's phone number
  // changes what every part developed for them shows. For a contractor the
  // company is still the client (normalizeDevelopedFor derives the parent id, so
  // "parts for this client" includes contractor work) while the person is the
  // contractor itself — that is who you actually deal with.
  //
  // Reading joined columns rather than issuing a SELECT per item is deliberate:
  // this DTO already costs ~7 queries per item and GET /api/items runs it over
  // every row.
  function developedForDto(row) {
    const kindColumn = String(row.developed_for_kind || '').trim();
    const clientId = row.developed_for_client_id || null;
    const subContractorId = row.developed_for_sub_contractor_id || null;
    // A row written before 047 has no kind but may well name a client. The
    // migration backfilled those, so this only catches a write that went around
    // saveItem — but '' with a client id can only have meant 'client'.
    const kind = kindColumn || (clientId ? 'client' : '');
    const fromContractor = kind === 'contractor' && subContractorId;

    // Who at the company the deal was done with (056) — any number of them,
    // from the JSON column the item SELECTs carry. A read that did not select
    // it lists nobody rather than failing.
    let contacts = [];
    try {
      const parsed = row.developed_for_contacts_json
        ? JSON.parse(row.developed_for_contacts_json)
        : [];
      contacts = (Array.isArray(parsed) ? parsed : [])
        .filter((contact) => contact && contact.id != null)
        .map((contact) => ({
          id: Number(contact.id),
          name: contact.name || '',
          designation: contact.designation || '',
          phone: contact.phone || '',
          email: contact.email || '',
          isArchived: Number(contact.isArchived || 0) === 1,
        }));
    } catch (_) {
      contacts = [];
    }
    // The single person the older surfaces print: the first one ticked, else
    // the company's primary (which the flat client columns mirror).
    const lead = !fromContractor && contacts.length ? contacts[0] : null;

    return {
      kind,
      clientId,
      clientName: row.developed_for_client_name || '',
      subContractorId,
      subContractorName: row.developed_for_sub_contractor_name || '',
      contactIds: contacts.map((contact) => contact.id),
      contacts,
      companyName: row.developed_for_client_name || '',
      contactName: fromContractor
        ? row.developed_for_sub_contractor_name || ''
        : lead ? lead.name : row.developed_for_contact_name || '',
      designation: fromContractor
        ? row.developed_for_sub_contractor_designation || ''
        : lead ? lead.designation : row.developed_for_designation || '',
      phone: fromContractor
        ? row.developed_for_sub_contractor_phone || ''
        : lead ? lead.phone : row.developed_for_phone || '',
      email: fromContractor
        ? row.developed_for_sub_contractor_email || ''
        : lead ? lead.email : row.developed_for_email || '',
      // Full ISO in UTC. The client converts with .toLocal() before showing it.
      at: row.developed_for_at || null,
      // Rupees. Null rather than 0, so "never quoted" is not printed as the
      // figure zero across the whole catalogue.
      quotationAmount:
        row.developed_for_quotation_amount === null ||
        row.developed_for_quotation_amount === undefined
          ? null
          : Number(row.developed_for_quotation_amount),
      // What the die making cost us. Null is "never costed", which a margin must
      // treat as unknown rather than as zero cost — zero would read as 100%.
      costAmount:
        row.developed_for_cost_amount === null ||
        row.developed_for_cost_amount === undefined
          ? null
          : Number(row.developed_for_cost_amount),
    };
  }

  // --- several companies per part (item_deals, 2026-11-24) -----------------

  const companyKey = (deal) => `${deal.clientId || 0}:${deal.subContractorId || 0}`;

  async function storedDeals(itemId) {
    if (!itemId) return [];
    const rows = await all(
      'SELECT * FROM item_deals WHERE item_id = ? ORDER BY position ASC, id ASC',
      [itemId],
    );
    const people = rows.length
      ? await all(
        `SELECT deal_id, contact_id FROM item_deal_people
          WHERE deal_id IN (${rows.map(() => '?').join(',')})`,
        rows.map((row) => row.id),
      )
      : [];
    return rows.map((row) => ({
      id: row.id,
      kind: row.kind,
      clientId: row.client_id || null,
      subContractorId: row.sub_contractor_id || null,
      quotationAmount: row.quotation_amount ?? null,
      at: row.at || null,
      contactIds: people.filter((p) => p.deal_id === row.id).map((p) => p.contact_id),
    }));
  }

  // The `deals` a save sends: the whole list, in order. Absent → undefined
  // (keep what is stored). Each deal is checked as the single block always
  // was; a deal must name a company, and a company only once per part. A deal
  // that says nothing about its people or its time keeps what the stored deal
  // for the same company had, so a screen that does not show them cannot wipe
  // them.
  async function normalizeDeals(raw, itemId) {
    if (raw === undefined) return undefined;
    if (raw === null) return [];
    if (!Array.isArray(raw)) {
      const error = new Error('Deals must be a list.');
      error.statusCode = 400;
      throw error;
    }
    const stored = new Map((await storedDeals(itemId)).map((deal) => [companyKey(deal), deal]));
    const seen = new Set();
    const out = [];
    for (const entry of raw) {
      const deal = await normalizeDevelopedFor({ ...(entry || {}), costAmount: undefined });
      if (deal.kind !== 'client' && deal.kind !== 'contractor') {
        const error = new Error('Each company tab needs its company.');
        error.statusCode = 400;
        error.code = 'deal_company_missing';
        throw error;
      }
      const key = companyKey(deal);
      if (seen.has(key)) {
        const error = new Error('That company is already on this part — one tab per company.');
        error.statusCode = 400;
        error.code = 'deal_company_twice';
        throw error;
      }
      seen.add(key);
      const before = stored.get(key);
      out.push({
        kind: deal.kind,
        clientId: deal.clientId,
        subContractorId: deal.subContractorId,
        quotationAmount: deal.quotationAmount,
        at: deal.at || before?.at || new Date().toISOString(),
        contactIds: deal.contactIds !== undefined ? deal.contactIds : (before?.contactIds || []),
      });
    }
    return out;
  }

  // Replaces a part's deals with [deals], in order. Inside saveItem's
  // transaction.
  async function writeDeals(itemId, deals) {
    await run(
      'DELETE FROM item_deal_people WHERE deal_id IN (SELECT id FROM item_deals WHERE item_id = ?)',
      [itemId],
    );
    await run('DELETE FROM item_deals WHERE item_id = ?', [itemId]);
    const now = new Date().toISOString();
    for (let position = 0; position < deals.length; position += 1) {
      const deal = deals[position];
      const result = await run(
        `INSERT INTO item_deals (item_id, kind, client_id, sub_contractor_id, quotation_amount, at, position, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        [itemId, deal.kind, deal.clientId, deal.subContractorId, deal.quotationAmount, deal.at, position, now],
      );
      for (const contactId of deal.contactIds || []) {
        await run(
          'INSERT OR IGNORE INTO item_deal_people (deal_id, contact_id) VALUES (?, ?)',
          [result.lastID, contactId],
        );
      }
    }
  }

  // A save that spoke about the ONE deal (developedFor, or the older
  // developedForClientId) — the item editor, the catalog wizard. The flat
  // columns now hold it; the first deal becomes it, the other companies stay,
  // and one that is now the first is not kept twice. "Developed for: self"
  // clears them all.
  async function syncDealsFromMirror(itemId) {
    const item = await get(
      `SELECT developed_for_kind, developed_for_client_id, developed_for_sub_contractor_id,
              developed_for_quotation_amount, developed_for_at FROM items WHERE id = ?`,
      [itemId],
    );
    const kind = String(item?.developed_for_kind || '');
    if (kind !== 'client' && kind !== 'contractor') {
      await writeDeals(itemId, []);
      return;
    }
    const people = await all('SELECT contact_id FROM item_deal_contacts WHERE item_id = ?', [itemId]);
    const first = {
      kind,
      clientId: item.developed_for_client_id || null,
      subContractorId: item.developed_for_sub_contractor_id || null,
      quotationAmount: item.developed_for_quotation_amount ?? null,
      at: item.developed_for_at || new Date().toISOString(),
      contactIds: people.map((row) => row.contact_id),
    };
    const rest = (await storedDeals(itemId))
      .slice(1)
      .filter((deal) => companyKey(deal) !== companyKey(first));
    await writeDeals(itemId, [first, ...rest]);
  }

  return {
    normalizeDealContactIds,
    normalizeDevelopedFor,
    writeDealContacts,
    developedForDto,
    normalizeDeals,
    writeDeals,
    syncDealsFromMirror,
  };
}

module.exports = { createDevelopedFor };
