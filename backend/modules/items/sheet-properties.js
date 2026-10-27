'use strict';

// ---------------------------------------------------------------------------
// The item sheet's own property columns — added with the sheet's "+", each
// with a list of options, kept for every user until the column is removed.
// See migrations/061-item-sheet-properties.sql.
//
//   GET    /api/item-sheet-properties              all, in column order
//   POST   /api/item-sheet-properties              add one (409 if the name exists)
//   PATCH  /api/item-sheet-properties/:id          rename and/or replace options
//   POST   /api/item-sheet-properties/:id/options  add one option (idempotent)
//   DELETE /api/item-sheet-properties/:id          remove the column
//
// Its own path segment, gated as `items` by the central CRUD map: under
// /api/items/ it would be swallowed by /api/items/:id.
// ---------------------------------------------------------------------------

const KINDS = ['list', 'text', 'material', 'gauge'];
const MAX_NAME = 60;
const MAX_OPTION = 80;
const MAX_OPTIONS = 200;

function badRequest(message) {
  const error = new Error(message);
  error.statusCode = 400;
  return error;
}

/// The key a name is stored and matched by — the sheet's own rule for a
/// variation property: trimmed, spaces collapsed, lower case.
function propertyKeyOf(name) {
  return String(name || '').trim().replace(/\s+/g, ' ').toLowerCase();
}

function cleanName(raw) {
  const name = String(raw || '').trim().replace(/\s+/g, ' ');
  if (!name) throw badRequest('A property needs a name.');
  if (name.length > MAX_NAME) throw badRequest(`Keep a property name under ${MAX_NAME} characters.`);
  return name;
}

function cleanOption(raw) {
  const label = String(raw ?? '').trim().replace(/\s+/g, ' ');
  if (!label) return null;
  if (label.length > MAX_OPTION) throw badRequest(`Keep an option under ${MAX_OPTION} characters.`);
  return label;
}

/// Trimmed, blanks dropped, de-duplicated ignoring case, in the order given.
function cleanOptions(raw) {
  if (raw === undefined || raw === null) return [];
  if (!Array.isArray(raw)) throw badRequest('Options must be a list of text.');
  const seen = new Set();
  const out = [];
  for (const entry of raw) {
    const label = cleanOption(entry);
    if (!label || seen.has(label.toLowerCase())) continue;
    seen.add(label.toLowerCase());
    out.push(label);
  }
  if (out.length > MAX_OPTIONS) throw badRequest(`A property holds at most ${MAX_OPTIONS} options.`);
  return out;
}

function parseOptions(json) {
  try {
    const parsed = JSON.parse(json || '[]');
    return Array.isArray(parsed) ? parsed.map(String) : [];
  } catch (_) {
    return [];
  }
}

function rowToDto(row) {
  if (!row) return null;
  return {
    id: row.id,
    key: row.property_key,
    propertyName: row.property_name,
    name: row.display_name,
    kind: row.kind,
    position: Number(row.position || 0),
    options: parseOptions(row.options_json),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

module.exports = function registerItemSheetPropertyRoutes(ctx) {
  const { app, get, all, run, requirePermission, trackCreate, trackUpdate, trackDelete } = ctx;

  const fail = (res, error) =>
    res.status(error.statusCode || 500).json({ success: false, error: error.message });

  const load = async (id) => {
    const row = await get('SELECT * FROM item_sheet_properties WHERE id = ?', [Number(id)]);
    if (!row) {
      const error = new Error('No such property column.');
      error.statusCode = 404;
      throw error;
    }
    return row;
  };

  app.get('/api/item-sheet-properties', requirePermission('items.read'), async (_req, res) => {
    try {
      const rows = await all('SELECT * FROM item_sheet_properties ORDER BY position ASC, id ASC');
      res.json({ success: true, properties: rows.map(rowToDto) });
    } catch (error) {
      fail(res, error);
    }
  });

  app.post('/api/item-sheet-properties', requirePermission('items.create'), async (req, res) => {
    try {
      const body = req.body || {};
      const name = cleanName(body.name);
      const kind = String(body.kind || 'list');
      if (!KINDS.includes(kind)) throw badRequest(`"${kind}" is not a kind of property.`);
      const options = cleanOptions(body.options);
      const key = propertyKeyOf(name);

      // A name already on the sheet is answered with that column, so two
      // people adding "Plating" at once end up with one.
      const existing = await get(
        'SELECT * FROM item_sheet_properties WHERE property_key = ? COLLATE NOCASE',
        [key],
      );
      if (existing) {
        return res.status(409).json({
          success: false,
          code: 'property_exists',
          error: `"${existing.display_name}" is already a column on the sheet.`,
          property: rowToDto(existing),
        });
      }

      const last = await get('SELECT COALESCE(MAX(position), 0) AS position FROM item_sheet_properties');
      const now = new Date().toISOString();
      let result;
      try {
        result = await run(
          `INSERT INTO item_sheet_properties
             (property_key, property_name, display_name, kind, position, options_json, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
          [key, name, name, kind, Number(last?.position || 0) + 1, JSON.stringify(options), now, now],
        );
      } catch (error) {
        if (!/UNIQUE constraint failed/.test(String(error?.message || ''))) throw error;
        const raced = await get(
          'SELECT * FROM item_sheet_properties WHERE property_key = ? COLLATE NOCASE',
          [key],
        );
        return res.status(409).json({
          success: false,
          code: 'property_exists',
          error: `"${name}" is already a column on the sheet.`,
          property: rowToDto(raced),
        });
      }
      const row = await load(result.lastID);
      if (trackCreate) trackCreate('item_sheet_properties', row.id, row, req);
      res.status(201).json({ success: true, property: rowToDto(row) });
    } catch (error) {
      fail(res, error);
    }
  });

  app.patch('/api/item-sheet-properties/:id', requirePermission('items.update'), async (req, res) => {
    try {
      const before = await load(req.params.id);
      const body = req.body || {};
      const sets = [];
      const params = [];
      // A rename changes the label only. The key is what saved parts carry
      // as their property name, and changing it would orphan their values.
      if ('displayName' in body) {
        sets.push('display_name = ?');
        params.push(cleanName(body.displayName));
      }
      if ('options' in body) {
        sets.push('options_json = ?');
        params.push(JSON.stringify(cleanOptions(body.options)));
      }
      if (sets.length) {
        sets.push('updated_at = ?');
        params.push(new Date().toISOString(), before.id);
        await run(`UPDATE item_sheet_properties SET ${sets.join(', ')} WHERE id = ?`, params);
      }
      const after = await load(before.id);
      if (trackUpdate) trackUpdate('item_sheet_properties', before.id, before, after, req);
      res.json({ success: true, property: rowToDto(after) });
    } catch (error) {
      fail(res, error);
    }
  });

  // One option, appended unless it is already there (ignoring case). Its own
  // route rather than a PATCH of the whole list: two people adding a value
  // at once would otherwise each write a list without the other's.
  app.post('/api/item-sheet-properties/:id/options', requirePermission('items.update'), async (req, res) => {
    try {
      const before = await load(req.params.id);
      const label = cleanOption((req.body || {}).label);
      if (!label) throw badRequest('An option needs some text.');
      const options = parseOptions(before.options_json);
      if (!options.some((o) => o.toLowerCase() === label.toLowerCase())) {
        if (options.length >= MAX_OPTIONS) {
          throw badRequest(`A property holds at most ${MAX_OPTIONS} options.`);
        }
        options.push(label);
        await run(
          'UPDATE item_sheet_properties SET options_json = ?, updated_at = ? WHERE id = ?',
          [JSON.stringify(options), new Date().toISOString(), before.id],
        );
        const after = await load(before.id);
        if (trackUpdate) trackUpdate('item_sheet_properties', before.id, before, after, req);
        return res.json({ success: true, property: rowToDto(after) });
      }
      res.json({ success: true, property: rowToDto(before) });
    } catch (error) {
      fail(res, error);
    }
  });

  app.delete('/api/item-sheet-properties/:id', requirePermission('items.delete'), async (req, res) => {
    try {
      const before = await load(req.params.id);
      await run('DELETE FROM item_sheet_properties WHERE id = ?', [before.id]);
      if (trackDelete) trackDelete('item_sheet_properties', before.id, before, req);
      res.json({ success: true });
    } catch (error) {
      fail(res, error);
    }
  });
};

module.exports.rowToDto = rowToDto;
module.exports.propertyKeyOf = propertyKeyOf;
