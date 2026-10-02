'use strict';

// ---------------------------------------------------------------------------
// Links module — HTTP routes over the generic link graph.
//
//   GET    /api/links/schema                          what can be linked
//   GET    /api/links/:type/:id                       a record's links, grouped
//   GET    /api/links/:type/:id/candidates?type=...   what it could link to
//   POST   /api/links                                 link two records
//   DELETE /api/links/:type/:id/:otherType/:otherId   unlink them
//
// Every route answers from either end: GET /api/links/die/3 lists the items
// that die makes and the machines it runs on, from the same rows that
// GET /api/links/item/5 reads to list its dies.
//
// PERMISSIONS. A link spans two modules, so there is no single (module, op) to
// map the path to and the central CRUD gate skips `/links` entirely (see
// MODULE_GATE_EXCLUDED_SEGMENTS, and the `/links` bypass in
// requireApiWritePermission). The gate is here instead, and it asks about BOTH
// sides: reading a record's links needs read on its module, listing or making a
// link to a die needs the die module too. Linking counts as `update` on both —
// it creates no record, it changes what two existing ones are attached to,
// which is the reading inventory.material.link already takes.
// ---------------------------------------------------------------------------

const {
  LINKABLE_TYPES,
  TYPE_KEYS,
  LEGACY_PAIRS,
  isLinkableType,
  typeSpec,
  canonicalPair,
  legacyPairFor,
} = require('./catalog');

module.exports = function registerLinksModuleRoutes(ctx) {
  const { app, get, all, run, logChange, hasPermission, hasRecordPermission } = ctx;

  // -------------------------------------------------------------------------
  // Access
  // -------------------------------------------------------------------------

  // True when the user may do `op` to this record's module, either outright or
  // through a per-record grant on this particular record. Mirrors the central
  // gate's fallback: entity_type is the module key, which is why the catalog
  // records one per type.
  async function mayTouch(req, type, id, op) {
    const spec = typeSpec(type);
    if (!spec) return false;
    if (hasPermission(req, `${spec.module}.${op}`)) return true;
    if (!id) return false;
    return hasRecordPermission(req.user?.id, spec.module, String(id), op);
  }

  // Both sides, or 403. `sides` entries may omit `id` when the request does
  // not name one (a candidates list over a whole type); the module right is
  // then the only way in, which is correct — picking from every die there is
  // needs more than a grant on one die.
  async function assertAccess(req, res, op, sides) {
    for (const side of sides) {
      if (!(await mayTouch(req, side.type, side.id, op))) {
        const spec = typeSpec(side.type);
        res.status(403).json({
          success: false,
          error: `You do not have ${op} access to ${spec ? spec.plural : side.type}.`,
        });
        return false;
      }
    }
    return true;
  }

  function rejectUnknownType(res, type) {
    res.status(400).json({
      success: false,
      error: `'${type}' cannot be linked. Linkable: ${TYPE_KEYS.join(', ')}.`,
    });
  }

  // -------------------------------------------------------------------------
  // Reading
  // -------------------------------------------------------------------------

  // The record itself, or null when it does not exist.
  async function describe(type, id) {
    const spec = typeSpec(type);
    if (!spec) return null;
    const row = await get(
      `SELECT ${spec.labelSql} AS label, ${spec.subtitleSql} AS subtitle
       FROM ${spec.table} WHERE ${spec.idCol} = ?`,
      [id],
    );
    if (!row) return null;
    return {
      type: String(type),
      id: String(id),
      label: String(row.label || ''),
      subtitle: String(row.subtitle || ''),
    };
  }

  // Labels for many ids of one type, in one query, keyed by id as text.
  //
  // Archived records are deliberately included: a link to a die archived after
  // it was attached still exists, and dropping it from the list would make it
  // look as though someone had unlinked it. Only the candidate picker filters
  // them out.
  async function describeMany(type, ids) {
    const spec = typeSpec(type);
    const unique = [...new Set(ids.map(String))];
    if (!spec || unique.length === 0) return new Map();
    const placeholders = unique.map(() => '?').join(', ');
    // The ids arrive as text; SQLite applies the column's own affinity to each
    // comparand, so an INTEGER id column still matches '5' through its index.
    const rows = await all(
      `SELECT ${spec.idCol} AS id, ${spec.labelSql} AS label, ${spec.subtitleSql} AS subtitle
       FROM ${spec.table} WHERE ${spec.idCol} IN (${placeholders})`,
      unique,
    );
    return new Map(
      rows.map((row) => [
        String(row.id),
        { label: String(row.label || ''), subtitle: String(row.subtitle || '') },
      ]),
    );
  }

  function readLimit(req) {
    return Math.min(Math.max(Number(req.query.limit) || 50, 1), 200);
  }

  // Records of one master, by name, for a column to list. Archived records are
  // left out: this feeds the pickers, and nobody means to attach a retired die.
  async function browse(type, rawQuery, limit) {
    const spec = typeSpec(type);
    const query = String(rawQuery || '').trim();
    const where = [];
    const params = [];
    if (spec.archivedCol) where.push(`${spec.archivedCol} = 0`);
    if (query) {
      where.push(`(${spec.labelSql} LIKE ? OR ${spec.subtitleSql} LIKE ?)`);
      params.push(`%${query}%`, `%${query}%`);
    }
    const rows = await all(
      `SELECT ${spec.idCol} AS id, ${spec.labelSql} AS label, ${spec.subtitleSql} AS subtitle
       FROM ${spec.table}
       ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
       ORDER BY ${spec.labelSql} COLLATE NOCASE ASC
       LIMIT ?`,
      [...params, limit],
    );
    return rows.map((row) => ({
      type: String(type),
      id: String(row.id),
      label: String(row.label || ''),
      subtitle: String(row.subtitle || ''),
    }));
  }

  // Every neighbour of (type, id), as { otherType, otherId, relation, store }.
  // Reads the generic table and the legacy pair tables and concatenates them;
  // a caller cannot tell which store a link came from except by `store`, which
  // is reported only so the UI can explain why a legacy link has no metadata.
  async function neighboursOf(type, id) {
    const found = [];

    const rows = await all(
      `SELECT
         id AS link_id,
         relation,
         CASE WHEN left_type = ? AND left_id = ? THEN right_type ELSE left_type END AS other_type,
         CASE WHEN left_type = ? AND left_id = ? THEN right_id ELSE left_id END AS other_id,
         created_at
       FROM entity_links
       WHERE (left_type = ? AND left_id = ?) OR (right_type = ? AND right_id = ?)
       ORDER BY id ASC`,
      [type, id, type, id, type, id, type, id],
    );
    for (const row of rows) {
      found.push({
        otherType: String(row.other_type),
        otherId: String(row.other_id),
        relation: String(row.relation || 'linked'),
        createdAt: row.created_at || null,
        store: 'entity_links',
      });
    }

    for (const [pairKey, pair] of Object.entries(LEGACY_PAIRS)) {
      const types = pairKey.split('|');
      if (!types.includes(type)) continue;
      // A legacy pair always joins two different masters, so "the other side"
      // is whichever of the two is not the one being asked about.
      const otherType = types[0] === type ? types[1] : types[0];
      const legacyRows = await all(
        `SELECT ${pair.columns[otherType]} AS other_id, created_at
         FROM ${pair.table} WHERE ${pair.columns[type]} = ?
         ORDER BY ${pair.columns[otherType]} ASC`,
        [id],
      );
      for (const row of legacyRows) {
        found.push({
          otherType,
          otherId: String(row.other_id),
          relation: 'linked',
          createdAt: row.created_at || null,
          store: pair.table,
        });
      }
    }

    return found;
  }

  // Neighbours grouped by master, in catalog order, with labels resolved and
  // the ones the caller may not read dropped.
  async function groupedLinks(req, type, id) {
    const neighbours = await neighboursOf(type, id);
    const byType = new Map();
    for (const neighbour of neighbours) {
      if (!isLinkableType(neighbour.otherType)) continue;
      if (!byType.has(neighbour.otherType)) byType.set(neighbour.otherType, []);
      byType.get(neighbour.otherType).push(neighbour);
    }

    const groups = [];
    for (const otherType of TYPE_KEYS) {
      const entries = byType.get(otherType);
      if (!entries || entries.length === 0) continue;
      // A link to a master this user cannot read is not shown at all, rather
      // than shown as an unnamed row: the label is the whole content of the
      // row, and leaking it is exactly what the module right withholds.
      if (!(await mayTouch(req, otherType, null, 'read'))) continue;
      const spec = typeSpec(otherType);
      const labels = await describeMany(
        otherType,
        entries.map((entry) => entry.otherId),
      );
      const links = [];
      for (const entry of entries) {
        const resolved = labels.get(entry.otherId);
        // No row behind the id: the record was deleted and left the link
        // behind (nothing can declare a foreign key against a polymorphic
        // pair). An orphan has no name, so there is nothing to show.
        if (!resolved) continue;
        links.push({
          type: otherType,
          id: entry.otherId,
          label: resolved.label,
          subtitle: resolved.subtitle,
          relation: entry.relation,
          createdAt: entry.createdAt,
          store: entry.store,
        });
      }
      if (links.length === 0) continue;
      links.sort((a, b) => a.label.localeCompare(b.label));
      groups.push({
        type: otherType,
        label: spec.label,
        plural: spec.plural,
        icon: spec.icon,
        count: links.length,
        links,
      });
    }
    return groups;
  }

  // -------------------------------------------------------------------------
  // GET /api/links/schema — what can be linked to what.
  //
  // The column UI builds its "+ link" menus from this instead of hardcoding
  // Item/Die/Machine, so a master added to the catalog appears without a
  // client release. Types the caller cannot read are left out, which is also
  // what keeps the menu honest about what they can actually attach.
  // -------------------------------------------------------------------------
  app.get('/api/links/schema', async (req, res) => {
    try {
      const types = [];
      for (const key of TYPE_KEYS) {
        if (!(await mayTouch(req, key, null, 'read'))) continue;
        const spec = LINKABLE_TYPES[key];
        types.push({
          type: key,
          label: spec.label,
          plural: spec.plural,
          icon: spec.icon,
          canLink: hasPermission(req, `${spec.module}.update`),
        });
      }
      res.json({ success: true, types });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // -------------------------------------------------------------------------
  // GET /api/links/:type?q=&limit= — the records of one master.
  //
  // The first column of a column view has no record to start from, so it needs
  // a plain listing. Registered after /schema, which is the same one-segment
  // shape under a name no master can have.
  // -------------------------------------------------------------------------
  app.get('/api/links/:type', async (req, res) => {
    try {
      const { type } = req.params;
      if (!isLinkableType(type)) return rejectUnknownType(res, type);
      if (!(await assertAccess(req, res, 'read', [{ type }]))) return;
      res.json({
        success: true,
        records: await browse(String(type), req.query.q, readLimit(req)),
      });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // -------------------------------------------------------------------------
  // GET /api/links/:type/:id — one record and its links, grouped by master.
  // -------------------------------------------------------------------------
  app.get('/api/links/:type/:id', async (req, res) => {
    try {
      const { type, id } = req.params;
      if (!isLinkableType(type)) return rejectUnknownType(res, type);
      if (!(await assertAccess(req, res, 'read', [{ type, id }]))) return;
      const entity = await describe(type, id);
      if (!entity) {
        return res.status(404).json({ success: false, error: 'Record not found.' });
      }
      res.json({
        success: true,
        entity,
        groups: await groupedLinks(req, String(type), String(id)),
      });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // -------------------------------------------------------------------------
  // GET /api/links/:type/:id/candidates?type=die&q=&limit=
  //
  // Records of one master that this one is not linked to yet — the list behind
  // "attach an existing die". Archived records are excluded here (unlike in
  // the links themselves): nobody means to attach a retired die.
  // -------------------------------------------------------------------------
  app.get('/api/links/:type/:id/candidates', async (req, res) => {
    try {
      const { type, id } = req.params;
      const otherType = String(req.query.type || '');
      if (!isLinkableType(type)) return rejectUnknownType(res, type);
      if (!isLinkableType(otherType)) return rejectUnknownType(res, otherType);
      if (
        !(await assertAccess(req, res, 'read', [
          { type, id },
          { type: otherType },
        ]))
      ) {
        return;
      }
      if (!(await describe(type, id))) {
        return res.status(404).json({ success: false, error: 'Record not found.' });
      }

      const spec = typeSpec(otherType);
      const taken = new Set(
        (await neighboursOf(String(type), String(id)))
          .filter((neighbour) => neighbour.otherType === otherType)
          .map((neighbour) => neighbour.otherId),
      );
      // Linking a master to itself is allowed (one item made of another), but
      // not a record to itself — the store's CHECK forbids it, so it must not
      // be offered.
      if (otherType === String(type)) taken.add(String(id));

      const limit = readLimit(req);
      // Over-fetch by the number already linked so filtering them out below
      // cannot leave the page short.
      const rows = await browse(otherType, req.query.q, limit + taken.size);
      res.json({
        success: true,
        candidates: rows.filter((row) => !taken.has(row.id)).slice(0, limit),
      });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // -------------------------------------------------------------------------
  // POST /api/links — { from: {type, id}, to: {type, id}, relation?, metadata? }
  //
  // Direction is not stored, so posting from either side produces the same
  // row; posting the same pair twice returns the link that is already there
  // rather than erroring, because "make sure these two are linked" is what
  // every caller actually means.
  // -------------------------------------------------------------------------
  app.post('/api/links', async (req, res) => {
    try {
      const from = req.body?.from || {};
      const to = req.body?.to || {};
      const fromType = String(from.type || '');
      const toType = String(to.type || '');
      const fromId = from.id === undefined || from.id === null ? '' : String(from.id);
      const toId = to.id === undefined || to.id === null ? '' : String(to.id);
      const relation = String(req.body?.relation || 'linked').trim() || 'linked';

      if (!isLinkableType(fromType)) return rejectUnknownType(res, fromType);
      if (!isLinkableType(toType)) return rejectUnknownType(res, toType);
      if (!fromId || !toId) {
        return res.status(400).json({ success: false, error: 'Both sides need an id.' });
      }
      if (fromType === toType && fromId === toId) {
        return res
          .status(400)
          .json({ success: false, error: 'A record cannot be linked to itself.' });
      }
      if (
        !(await assertAccess(req, res, 'update', [
          { type: fromType, id: fromId },
          { type: toType, id: toId },
        ]))
      ) {
        return;
      }

      const fromEntity = await describe(fromType, fromId);
      const toEntity = await describe(toType, toId);
      if (!fromEntity || !toEntity) {
        // Checked rather than left to a foreign key, which a polymorphic pair
        // cannot declare: without this, a typo'd id becomes a link to nothing
        // that only ever shows up as a silently skipped orphan on read.
        return res.status(404).json({
          success: false,
          error: `No ${!fromEntity ? fromType : toType} with that id.`,
        });
      }

      const { left, right } = canonicalPair(fromType, fromId, toType, toId);
      const legacy = legacyPairFor(left.type, right.type);
      const now = new Date().toISOString();

      if (legacy) {
        const byType = { [left.type]: left.id, [right.type]: right.id };
        await run(
          `INSERT OR IGNORE INTO ${legacy.table}
             (${legacy.columns[left.type]}, ${legacy.columns[right.type]}, created_at)
           VALUES (?, ?, ?)`,
          [byType[left.type], byType[right.type], now],
        );
      } else {
        await run(
          `INSERT OR IGNORE INTO entity_links
             (left_type, left_id, right_type, right_id, relation, metadata, created_at, created_by)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
          [
            left.type,
            left.id,
            right.type,
            right.id,
            relation,
            JSON.stringify(req.body?.metadata || {}),
            now,
            req.user?.id || null,
          ],
        );
      }

      // An item's DTO carries its dies and machines, so a legacy link changes
      // what GET /api/items/:id answers; the item_dies / item_machines derived
      // triggers already announce that. entity_links announces itself.
      if (legacy) {
        const itemId = left.type === 'item' ? left.id : right.id;
        try {
          await logChange('items', itemId, 'UPDATE');
        } catch (_) {
          /* the trigger has already recorded it; this is belt and braces */
        }
      }

      res.status(201).json({
        success: true,
        link: {
          from: fromEntity,
          to: toEntity,
          relation: legacy ? 'linked' : relation,
          store: legacy ? legacy.table : 'entity_links',
        },
      });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // -------------------------------------------------------------------------
  // DELETE /api/links/:type/:id/:otherType/:otherId?relation=
  //
  // By pair rather than by link id, because the legacy tables have no id of
  // their own — and because the pair is what the caller is holding.
  // -------------------------------------------------------------------------
  app.delete('/api/links/:type/:id/:otherType/:otherId', async (req, res) => {
    try {
      const { type, id, otherType, otherId } = req.params;
      if (!isLinkableType(type)) return rejectUnknownType(res, type);
      if (!isLinkableType(otherType)) return rejectUnknownType(res, otherType);
      if (
        !(await assertAccess(req, res, 'update', [
          { type, id },
          { type: otherType, id: otherId },
        ]))
      ) {
        return;
      }

      const { left, right } = canonicalPair(type, id, otherType, otherId);
      const legacy = legacyPairFor(left.type, right.type);
      let removed = 0;

      if (legacy) {
        const byType = { [left.type]: left.id, [right.type]: right.id };
        const result = await run(
          `DELETE FROM ${legacy.table}
           WHERE ${legacy.columns[left.type]} = ? AND ${legacy.columns[right.type]} = ?`,
          [byType[left.type], byType[right.type]],
        );
        removed = result?.changes ?? 0;
        if (removed > 0) {
          const itemId = left.type === 'item' ? left.id : right.id;
          try {
            await logChange('items', itemId, 'UPDATE');
          } catch (_) {
            /* the derived trigger has already recorded it */
          }
        }
      } else {
        const relation = req.query.relation ? String(req.query.relation) : null;
        const result = await run(
          `DELETE FROM entity_links
           WHERE left_type = ? AND left_id = ? AND right_type = ? AND right_id = ?
             ${relation ? 'AND relation = ?' : ''}`,
          relation
            ? [left.type, left.id, right.type, right.id, relation]
            : [left.type, left.id, right.type, right.id],
        );
        removed = result?.changes ?? 0;
      }

      if (removed === 0) {
        return res.status(404).json({ success: false, error: 'No such link.' });
      }
      res.json({ success: true, removed });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Links a deleted record leaves behind. Nothing can declare a foreign key
  // against a polymorphic pair, so a cascade has to be asked for; reads skip
  // orphans anyway, but a purged row cannot come back to life attached to a
  // recycled id.
  async function purgeLinksFor(type, id) {
    await run(
      `DELETE FROM entity_links
       WHERE (left_type = ? AND left_id = ?) OR (right_type = ? AND right_id = ?)`,
      [String(type), String(id), String(type), String(id)],
    );
  }

  return { purgeLinksFor, neighboursOf };
};
