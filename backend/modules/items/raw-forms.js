'use strict';

const { answer, deskRoutes } = require('../../kernel/desk-kit');

// ---------------------------------------------------------------------------
// The raw-material forms — Rivets, Springs — as one engine and a declaration
// each (Docs/architecture/13-raw-material-forms.md).
//
// A raw material is an ordinary item filed under its default group (found by
// the group's system_key), so stock, challans, BOM lines and orders treat it
// like any other item. What makes it a rivet or a spring is its spec — one row
// in raw_material_specs — and its NAME IS BUILT from that spec by the form,
// never typed. The same spec twice is the same item (409 with the one that
// exists); a code, when given, is unique within the form. Vendors quote a
// price for it (item_vendor_prices) per piece, per 100, per 1000 or per kg.
//
// A form declares only what is its own:
//
//   key       the default group's system_key, and raw_material_specs.form_key
//   noun      'rivet' — the one-item key in answers and in messages
//   plural    'rivets' — the list key, the path segment, the operation group
//   group     'Rivets' — the group's name, for messages
//   clean(body)     → spec, or a 400 naming the field
//   name(spec)      → the item's name
//   specKey(spec)   → two items with this key are the same item
//   fields(values)  → the form's own fields in an answer
//   uniqueNames     → (optional) refuse two items with one name, saying
//                     nameTakenHint — for a form whose name the user arranges
//
// Routes, one set per form, gated as `items` (the raw-materials segment is
// declared in server.js's CRUD map and kernel/registry.js):
//
//   GET  /api/raw-materials/<plural>        all, with their vendors
//   GET  /api/raw-materials/<plural>/:id    one (id = the item's id)
//   POST /api/raw-materials/<plural>        make one
//   PUT  /api/raw-materials/<plural>/:id    change its spec, code or vendors;
//                                           gives a spec to an item already
//                                           filed under the group without one
//
// Numbers: lengths are integer nanometres (the units contract's base for a
// length) with the text as typed kept beside them; prices are integer
// micro-rupees, so ₹0.035 a piece is exact. No floats.
// ---------------------------------------------------------------------------

const PRICE_BASES = {
  piece: 'per piece',
  hundred: 'per 100 pieces',
  thousand: 'per 1000 pieces',
  kg: 'per kg',
};

const MAX_CODE = 40;
const MAX_VENDORS = 50;

function badRequest(message, code) {
  const error = new Error(message);
  error.statusCode = 400;
  if (code) error.code = code;
  return error;
}

function conflict(message, code, extra = {}) {
  const error = new Error(message);
  error.statusCode = 409;
  error.code = code;
  error.extra = extra;
  return error;
}

/// "3.5" (mm) → { text: '3.5', nm: 3500000 }. Exact: the string is split, not
/// multiplied as a float. Up to 6 decimals (a nanometre).
function parseMillimetres(raw, label, required) {
  const text = String(raw ?? '').trim();
  if (!text) {
    if (required) throw badRequest(`${label} is needed.`, 'missing_dimension');
    return null;
  }
  const match = /^(\d{1,4})(?:\.(\d{1,6}))?$/.exec(text);
  if (!match) throw badRequest(`${label} must be a number of millimetres, like 2.0.`, 'bad_dimension');
  const whole = Number(match[1]);
  const fraction = Number((match[2] || '').padEnd(6, '0'));
  const nm = whole * 1000000 + fraction;
  if (nm <= 0) throw badRequest(`${label} must be more than 0.`, 'bad_dimension');
  // Leading zeros dropped ("02.0" → "2.0"); trailing ones kept, as typed.
  return { text: `${whole}${match[2] !== undefined ? `.${match[2]}` : ''}`, nm };
}

/// "12.50" (rupees) → 12500000 micro-rupees. Exact, up to 6 decimals.
function parsePrice(raw) {
  const text = String(raw ?? '').trim().replace(/^₹\s*/, '');
  if (!text) throw badRequest('Each vendor needs a price.', 'missing_price');
  const match = /^(\d{1,9})(?:\.(\d{1,6}))?$/.exec(text);
  if (!match) throw badRequest(`"${raw}" is not a price. Write it like 12.50.`, 'bad_price');
  return Number(match[1]) * 1000000 + Number((match[2] || '').padEnd(6, '0'));
}

function formatPrice(micro) {
  const whole = Math.floor(micro / 1000000);
  let fraction = String(micro % 1000000).padStart(6, '0').replace(/0+$/, '');
  if (fraction.length < 2) fraction = fraction.padEnd(2, '0');
  return `${whole}.${fraction}`;
}

function cleanCode(raw, noun) {
  const code = String(raw ?? '').trim().replace(/\s+/g, ' ');
  if (code.length > MAX_CODE) throw badRequest(`Keep the ${noun} code under ${MAX_CODE} characters.`);
  return code;
}

/// A length as an answer carries it: { mm: '2.0', nm: 2000000 }, or null.
function lengthDto(value) {
  return value ? { mm: value.text, nm: Number(value.nm) } : null;
}

function parseValues(json) {
  try {
    const parsed = JSON.parse(json || '{}');
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch (_) {
    return {};
  }
}

function createRawFormWork({ get, all, run, desk, saveItem }, form) {
  const { key, noun, plural, group: groupName } = form;

  const fail = (error) =>
    answer(error.statusCode || 500, {
      success: false,
      ...(error.code ? { code: error.code } : {}),
      ...(error.extra || {}),
      error: error.message,
    });

  async function formGroup() {
    const group = await get('SELECT id, unit_id FROM groups WHERE system_key = ?', [key]);
    if (!group) {
      // Seeded on boot and after every wipe; missing means the server has not
      // finished starting, or someone deleted it by hand in the database.
      throw Object.assign(new Error(`The ${groupName} group is missing. Restart the server to put it back.`), {
        statusCode: 503,
      });
    }
    return group;
  }

  async function vendorNames(ids) {
    const names = new Map();
    for (const id of new Set(ids)) {
      const { row } = await desk.ask('vendors.rows.get', { id });
      names.set(id, row ? row.name : null);
    }
    return names;
  }

  async function toDtos(rows) {
    if (!rows.length) return [];
    const itemIds = rows.map((row) => row.item_id);
    const marks = itemIds.map(() => '?').join(', ');
    const prices = await all(
      `SELECT * FROM item_vendor_prices WHERE item_id IN (${marks}) ORDER BY item_id, id`,
      itemIds,
    );
    const names = await vendorNames(prices.map((p) => Number(p.vendor_id)));
    return rows.map((row) => {
      const values = parseValues(row.values_json);
      return {
        itemId: row.item_id,
        name: row.item_name,
        code: row.code || '',
        ...form.fields(values),
        isArchived: Boolean(row.is_archived),
        vendors: prices
          .filter((p) => p.item_id === row.item_id)
          .map((p) => ({
            vendorId: Number(p.vendor_id),
            vendorName: names.get(Number(p.vendor_id)) || null,
            price: formatPrice(Number(p.price_micro_rupees)),
            priceMicroRupees: Number(p.price_micro_rupees),
            basis: p.basis,
            basisLabel: PRICE_BASES[p.basis] || p.basis,
          })),
        createdAt: row.created_at,
        updatedAt: row.updated_at,
      };
    });
  }

  const SELECT = `
    SELECT s.*, i.name AS item_name, i.is_archived
      FROM raw_material_specs s
      JOIN items i ON i.id = s.item_id
     WHERE s.form_key = ?`;

  async function loadOne(itemId) {
    const row = await get(`${SELECT} AND s.item_id = ?`, [key, Number(itemId)]);
    if (!row) return null;
    return (await toDtos([row]))[0];
  }

  /// [{ vendorId, price, basis }] → clean rows; null when the body does not
  /// mention vendors (absent = keep what is stored).
  async function cleanVendors(raw) {
    if (raw === undefined) return null;
    if (!Array.isArray(raw)) throw badRequest('vendors must be a list.');
    if (raw.length > MAX_VENDORS) throw badRequest(`At most ${MAX_VENDORS} vendor prices per ${noun}.`);
    const seen = new Set();
    const out = [];
    for (const entry of raw) {
      const vendorId = Number(entry?.vendorId);
      if (!Number.isInteger(vendorId) || vendorId <= 0) throw badRequest('Each price needs a vendor.', 'missing_vendor');
      const basis = String(entry?.basis || 'piece');
      if (!PRICE_BASES[basis]) throw badRequest(`"${basis}" is not a price basis.`, 'bad_basis');
      const pair = `${vendorId}|${basis}`;
      if (seen.has(pair)) throw badRequest('The same vendor is listed twice with the same basis.', 'duplicate_vendor');
      seen.add(pair);
      const { row } = await desk.ask('vendors.rows.get', { id: vendorId });
      if (!row) throw badRequest(`Vendor ${vendorId} does not exist.`, 'unknown_vendor');
      out.push({ vendorId, basis, priceMicroRupees: parsePrice(entry?.price) });
    }
    return out;
  }

  async function writeVendors(itemId, vendors, now) {
    await run('DELETE FROM item_vendor_prices WHERE item_id = ?', [itemId]);
    for (const v of vendors) {
      await run(
        `INSERT INTO item_vendor_prices (item_id, vendor_id, price_micro_rupees, basis, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [itemId, v.vendorId, v.priceMicroRupees, v.basis, now, now],
      );
    }
  }

  async function assertFree({ spec, code, exceptItemId = null }) {
    const twin = await get(
      'SELECT item_id FROM raw_material_specs WHERE form_key = ? AND spec_key = ? AND item_id != ?',
      [key, form.specKey(spec), exceptItemId ?? 0],
    );
    if (twin) {
      throw conflict(`This ${noun} already exists: ${form.name(spec)}.`, `${noun}_exists`, {
        [noun]: await loadOne(twin.item_id),
      });
    }
    // A form whose name does not carry every field (springs: the user
    // arranges it) can make two items one name; the list could not tell
    // them apart, so it is refused with what to do about it.
    if (form.uniqueNames) {
      const name = form.name(spec);
      const clash = await get(
        `SELECT s.item_id FROM raw_material_specs s JOIN items i ON i.id = s.item_id
          WHERE s.form_key = ? AND i.name = ? COLLATE NOCASE AND s.item_id != ?`,
        [key, name, exceptItemId ?? 0],
      );
      if (clash) {
        throw conflict(
          `Another ${noun} is already called ${name}. ${form.nameTakenHint || ''}`.trim(),
          'name_taken',
          { [noun]: await loadOne(clash.item_id) },
        );
      }
    }
    if (code) {
      const taken = await get(
        `SELECT s.item_id, i.name FROM raw_material_specs s JOIN items i ON i.id = s.item_id
          WHERE s.form_key = ? AND s.code = ? COLLATE NOCASE AND s.item_id != ?`,
        [key, code, exceptItemId ?? 0],
      );
      if (taken) {
        throw conflict(`Code ${code} is already used by ${taken.name}.`, 'code_taken', {
          [noun]: await loadOne(taken.item_id),
        });
      }
    }
  }

  async function list() {
    try {
      const rows = await all(`${SELECT} ORDER BY i.is_archived ASC, LOWER(i.name) ASC`, [key]);
      return answer(200, { success: true, [plural]: await toDtos(rows) });
    } catch (error) {
      return fail(error);
    }
  }

  async function getOne(req) {
    try {
      const found = await loadOne(req.params.id);
      if (!found) return answer(404, { success: false, error: `No such ${noun}.` });
      return answer(200, { success: true, [noun]: found });
    } catch (error) {
      return fail(error);
    }
  }

  async function create(req) {
    try {
      const body = req.body || {};
      const spec = form.clean(body);
      const code = cleanCode(body.code, noun);
      const vendors = (await cleanVendors(body.vendors)) || [];
      const group = await formGroup();
      await assertFree({ spec, code });

      const now = new Date().toISOString();
      let item;
      await run('BEGIN TRANSACTION');
      try {
        item = await saveItem(
          { name: form.name(spec), groupId: group.id, unitId: group.unit_id },
          { useTransaction: false },
        );
        await run(
          `INSERT INTO raw_material_specs (item_id, form_key, spec_key, code, values_json, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?)`,
          [item.id, key, form.specKey(spec), code, JSON.stringify(spec), now, now],
        );
        await writeVendors(item.id, vendors, now);
        await run('COMMIT');
      } catch (error) {
        await run('ROLLBACK').catch(() => {});
        throw error;
      }
      req.track('create', 'items', item.id, item);
      return answer(201, { success: true, [noun]: await loadOne(item.id) });
    } catch (error) {
      return fail(error);
    }
  }

  async function update(req) {
    try {
      const itemId = Number(req.params.id);
      const current = await get('SELECT * FROM raw_material_specs WHERE item_id = ? AND form_key = ?', [itemId, key]);
      // An item filed under the group from the plain item form has no spec
      // yet; the editor's view for this form gives it one, on the same item.
      // Any other item is not one of these and cannot be made one here.
      if (!current) {
        const group = await formGroup();
        const item = await get('SELECT group_id FROM items WHERE id = ?', [itemId]);
        if (!item || Number(item.group_id) !== Number(group.id)) {
          return answer(404, { success: false, error: `No such ${noun}.` });
        }
      }
      const body = req.body || {};
      const spec = form.clean(body);
      const code = body.code === undefined ? current?.code || '' : cleanCode(body.code, noun);
      const vendors = await cleanVendors(body.vendors);
      await assertFree({ spec, code, exceptItemId: itemId });

      const before = await get('SELECT * FROM items WHERE id = ?', [itemId]);
      const name = form.name(spec);
      const now = new Date().toISOString();
      await run('BEGIN TRANSACTION');
      try {
        // Only the name and display name: a whole-item save would start from
        // defaults and wipe the photo, conversions and the rest (B42).
        const alias = String(before?.alias || '').trim();
        await run('UPDATE items SET name = ?, display_name = ?, updated_at = ? WHERE id = ?', [
          name,
          alias ? `${name} / ${alias}` : name,
          now,
          itemId,
        ]);
        if (current) {
          await run(
            'UPDATE raw_material_specs SET spec_key = ?, code = ?, values_json = ?, updated_at = ? WHERE item_id = ?',
            [form.specKey(spec), code, JSON.stringify(spec), now, itemId],
          );
        } else {
          await run(
            `INSERT INTO raw_material_specs (item_id, form_key, spec_key, code, values_json, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?)`,
            [itemId, key, form.specKey(spec), code, JSON.stringify(spec), now, now],
          );
        }
        if (vendors) await writeVendors(itemId, vendors, now);
        await run('COMMIT');
      } catch (error) {
        await run('ROLLBACK').catch(() => {});
        throw error;
      }
      const after = await get('SELECT * FROM items WHERE id = ?', [itemId]);
      req.track('update', 'items', itemId, before, after);
      return answer(200, { success: true, [noun]: await loadOne(itemId) });
    } catch (error) {
      return fail(error);
    }
  }

  return { list, get: getOne, create, update };
}

/// The four routes of one form, asking the desk's items.<plural>.* operations.
function registerRawFormRoutes(ctx, plural) {
  const { app, desk, requirePermission } = ctx;
  const send = deskRoutes(desk, { create: ctx.trackCreate, update: ctx.trackUpdate, delete: ctx.trackDelete });
  const base = `/api/raw-materials/${plural}`;

  app.get(base, requirePermission('items.read'),
    send(`items.${plural}.list`, (req) => ({ query: req.query, data: req.body })));

  app.get(`${base}/:id`, requirePermission('items.read'),
    send(`items.${plural}.get`, (req) => ({ id: req.params.id, query: req.query, data: req.body })));

  app.post(base, requirePermission('items.create'),
    send(`items.${plural}.create`, (req) => ({ query: req.query, data: req.body })));

  app.put(`${base}/:id`, requirePermission('items.update'),
    send(`items.${plural}.update`, (req) => ({ id: req.params.id, query: req.query, data: req.body })));
}

module.exports = {
  PRICE_BASES,
  badRequest,
  parseMillimetres,
  parsePrice,
  formatPrice,
  lengthDto,
  createRawFormWork,
  registerRawFormRoutes,
};
