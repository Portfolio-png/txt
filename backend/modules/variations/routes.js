'use strict';

// ---------------------------------------------------------------------------
// Variations module — a property/value tree for any master that is not items.
//
//   GET  /api/variations/:type/:id            the tree, and the version it is on
//   PUT  /api/variations/:type/:id            save the tree (see THE VERSION RULE)
//   POST /api/variations/:type/:id/versions   declare a new version
//
// WHO OWNS WHAT. The entity catalog is the links module's: one declaration of
// which masters exist, what table they live in and which kernel module gates
// them, shared rather than copied. A master that can be linked can carry a
// tree, and neither feature had to learn about the other to make that true.
//
// THE VERSION RULE. For the client this is built for, items are derived from
// dies: a die saying it cuts 2 and 4 cavities is a statement every item struck
// from it was made under. So the tree is FIXED within a version —
//
//   * adding a property or a value is allowed in place. It takes nothing away
//     from what was already derived, and "after creation they can still add
//     values" is exactly how the shop works;
//   * renaming, retyping or removing anything that is already there is NOT,
//     because something downstream may have been derived from it. It needs a
//     new version, which is the shop declaring the change out loud.
//
// A PUT that would break the rule is refused with 409 and a list of what it
// would have changed, rather than being silently dropped or silently applied.
// ---------------------------------------------------------------------------

const { isLinkableType, typeSpec } = require('../links/catalog');

// What makes two versions of a node "the same node, changed" rather than an
// addition. Position is not here: reordering a tree rewrites no history.
const TRACKED_FIELDS = [
  'name',
  'code',
  'displayName',
  'inputType',
  'numericMin',
  'numericMax',
  'materialTypeId',
];

module.exports = function registerVariationsModuleRoutes(ctx) {
  const { app, get, all, run, hasPermission, hasRecordPermission } = ctx;

  async function mayTouch(req, type, id, op) {
    const spec = typeSpec(type);
    if (!spec) return false;
    if (hasPermission(req, `${spec.module}.${op}`)) return true;
    if (!id) return false;
    return hasRecordPermission(req.user?.id, spec.module, String(id), op);
  }

  async function guard(req, res, type, id, op) {
    if (!isLinkableType(type)) {
      res.status(400).json({ success: false, error: `'${type}' has no variation tree.` });
      return false;
    }
    if (!(await mayTouch(req, type, id, op))) {
      const spec = typeSpec(type);
      res.status(403).json({
        success: false,
        error: `You do not have ${op} access to ${spec ? spec.plural : type}.`,
      });
      return false;
    }
    const spec = typeSpec(type);
    const row = await get(
      `SELECT 1 FROM ${spec.table} WHERE ${spec.idCol} = ?`,
      [id],
    );
    if (!row) {
      res.status(404).json({ success: false, error: 'Record not found.' });
      return false;
    }
    return true;
  }

  function nodeDto(row) {
    return {
      id: row.id,
      parentNodeId: row.parent_node_id || null,
      kind: row.kind,
      name: row.name || '',
      code: row.code || '',
      displayName: row.display_name || '',
      position: Number(row.position || 0),
      inputType: row.input_type || 'Text',
      nameJoin: row.name_join || '',
      numericMin: row.numeric_min === null ? null : Number(row.numeric_min),
      numericMax: row.numeric_max === null ? null : Number(row.numeric_max),
      materialTypeId: row.material_type_id || null,
      version: Number(row.version || 1),
      children: [],
    };
  }

  // Flat rows -> the nested tree the editor draws.
  function nest(rows) {
    const byId = new Map(rows.map((row) => [row.id, nodeDto(row)]));
    const roots = [];
    for (const row of rows) {
      const node = byId.get(row.id);
      const parent = row.parent_node_id ? byId.get(row.parent_node_id) : null;
      if (parent) parent.children.push(node);
      else roots.push(node);
    }
    const sort = (list) => {
      list.sort((a, b) => a.position - b.position || a.id - b.id);
      for (const node of list) sort(node.children);
    };
    sort(roots);
    return roots;
  }

  async function loadRows(type, id) {
    return all(
      `SELECT * FROM entity_variation_nodes
       WHERE entity_type = ? AND entity_id = ? AND is_archived = 0`,
      [String(type), String(id)],
    );
  }

  async function currentVersion(type, id) {
    const row = await get(
      `SELECT version, label, note FROM entity_variation_versions
       WHERE entity_type = ? AND entity_id = ?
       ORDER BY version DESC LIMIT 1`,
      [String(type), String(id)],
    );
    return {
      version: row ? Number(row.version) : 1,
      label: row ? row.label || '' : '',
      note: row ? row.note || '' : '',
    };
  }

  // -------------------------------------------------------------------------
  // GET /api/variations/:type/:id
  // -------------------------------------------------------------------------
  app.get('/api/variations/:type/:id', async (req, res) => {
    try {
      const { type, id } = req.params;
      if (!(await guard(req, res, type, id, 'read'))) return;
      const rows = await loadRows(type, id);
      res.json({
        success: true,
        ...(await currentVersion(type, id)),
        nodes: nest(rows),
      });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // -------------------------------------------------------------------------
  // POST /api/variations/:type/:id/versions — declare a new version.
  //
  // What unlocks an edit the version rule would otherwise refuse. Takes a
  // label ('Rev B') and a note, because a version nobody can account for is
  // not much of a declaration.
  // -------------------------------------------------------------------------
  app.post('/api/variations/:type/:id/versions', async (req, res) => {
    try {
      const { type, id } = req.params;
      if (!(await guard(req, res, type, id, 'update'))) return;
      const { version } = await currentVersion(type, id);
      const next = version + 1;
      await run(
        `INSERT INTO entity_variation_versions
           (entity_type, entity_id, version, label, note, created_at, created_by)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [
          String(type),
          String(id),
          next,
          String(req.body?.label || `v${next}`).trim(),
          String(req.body?.note || '').trim(),
          new Date().toISOString(),
          req.user?.id || null,
        ],
      );
      res.status(201).json({ success: true, version: next });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // -------------------------------------------------------------------------
  // PUT /api/variations/:type/:id — { nodes: [...], version? }
  //
  // The whole tree, as the editor holds it. Nodes with an id are existing ones;
  // nodes without are new. See THE VERSION RULE above for what each may do.
  // -------------------------------------------------------------------------
  app.put('/api/variations/:type/:id', async (req, res) => {
    try {
      const { type, id } = req.params;
      if (!(await guard(req, res, type, id, 'update'))) return;

      const incoming = Array.isArray(req.body?.nodes) ? req.body.nodes : null;
      if (!incoming) {
        return res.status(400).json({ success: false, error: 'nodes array is required.' });
      }

      const existingRows = await loadRows(type, id);
      const existing = new Map(existingRows.map((row) => [row.id, row]));
      const { version } = await currentVersion(type, id);

      // A declared version is SPENT by the save that follows it.
      //
      // Nodes carry the version they were last written in. While the tree's
      // newest node is already at the current version, the tree is as the
      // current version describes it and changing it would rewrite that
      // description — locked. Declaring a new version puts the current version
      // ahead of every node, and the next save may then change anything,
      // stamping what it touches with the new version and locking it again.
      //
      // So one bump buys one editing pass, which is what a form does anyway:
      // open it, make the changes, save once. A second corrective pass needs a
      // second version, and for a record items are derived from, saying so out
      // loud twice is the right cost.
      const highestWritten = existingRows.reduce(
        (highest, row) => Math.max(highest, Number(row.version || 1)),
        0,
      );
      const locked = existingRows.length > 0 && version <= highestWritten;
      // The version everything written by this save is stamped with. Never the
      // client's claim: a client cannot unlock itself by asserting a number.
      const claimed = version;

      // Walk the incoming tree into flat rows, keeping parentage and order.
      const flat = [];
      const walk = (nodes, parentKey) => {
        nodes.forEach((node, index) => {
          if (!node || typeof node !== 'object') return;
          const key = flat.length;
          flat.push({
            key,
            parentKey,
            id: Number.isFinite(Number(node.id)) && Number(node.id) > 0
              ? Number(node.id)
              : null,
            kind: node.kind === 'value' ? 'value' : 'property',
            name: String(node.name || '').trim(),
            code: String(node.code || '').trim(),
            displayName: String(node.displayName || '').trim(),
            position: index,
            inputType: String(node.inputType || 'Text').trim() || 'Text',
            nameJoin: String(node.nameJoin || '').trim(),
            numericMin: node.numericMin === null || node.numericMin === undefined
              ? null
              : Number(node.numericMin),
            numericMax: node.numericMax === null || node.numericMax === undefined
              ? null
              : Number(node.numericMax),
            materialTypeId: node.materialTypeId || null,
          });
          walk(Array.isArray(node.children) ? node.children : [], key);
        });
      };
      walk(incoming, null);

      if (flat.some((node) => !node.name)) {
        return res.status(400).json({ success: false, error: 'Every node needs a name.' });
      }

      // What this save would change about nodes that already exist.
      if (locked) {
        const breaks = [];
        const seen = new Set();
        for (const node of flat) {
          if (node.id === null) continue; // an addition, always allowed
          seen.add(node.id);
          const before = existing.get(node.id);
          if (!before) continue;
          const was = nodeDto(before);
          for (const field of TRACKED_FIELDS) {
            if (`${was[field] ?? ''}` !== `${node[field] ?? ''}`) {
              breaks.push(`${was.name}: ${field} '${was[field] ?? ''}' -> '${node[field] ?? ''}'`);
            }
          }
        }
        for (const row of existingRows) {
          if (!seen.has(row.id)) breaks.push(`${row.name}: removed`);
        }
        if (breaks.length > 0) {
          const spec = typeSpec(type);
          const noun = spec ? spec.label.toLowerCase() : type;
          return res.status(409).json({
            success: false,
            error:
              `This ${noun} is on version ${version}, and these are already ` +
              'part of it. Adding is fine; changing or removing needs a new ' +
              'version.',
            requiresNewVersion: true,
            changes: breaks,
          });
        }
      }

      const now = new Date().toISOString();
      const idByKey = new Map();
      const kept = new Set();
      for (const node of flat) {
        const parentId = node.parentKey === null
          ? null
          : idByKey.get(node.parentKey) ?? null;
        if (node.id !== null && existing.has(node.id)) {
          await run(
            `UPDATE entity_variation_nodes SET
               parent_node_id = ?, kind = ?, name = ?, code = ?, display_name = ?,
               position = ?, input_type = ?, name_join = ?, numeric_min = ?,
               numeric_max = ?, material_type_id = ?, version = ?, updated_at = ?
             WHERE id = ?`,
            [
              parentId, node.kind, node.name, node.code, node.displayName,
              node.position, node.inputType, node.nameJoin, node.numericMin,
              node.numericMax, node.materialTypeId, claimed, now, node.id,
            ],
          );
          idByKey.set(node.key, node.id);
          kept.add(node.id);
        } else {
          const result = await run(
            `INSERT INTO entity_variation_nodes
               (entity_type, entity_id, parent_node_id, kind, name, code,
                display_name, position, input_type, name_join, numeric_min,
                numeric_max, material_type_id, version, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
              String(type), String(id), parentId, node.kind, node.name, node.code,
              node.displayName, node.position, node.inputType, node.nameJoin,
              node.numericMin, node.numericMax, node.materialTypeId, claimed,
              now, now,
            ],
          );
          idByKey.set(node.key, result.lastID);
          kept.add(result.lastID);
        }
      }

      // Archived rather than deleted: something derived under an earlier
      // version still has to be able to read the tree it was derived from.
      for (const row of existingRows) {
        if (kept.has(row.id)) continue;
        await run(
          'UPDATE entity_variation_nodes SET is_archived = 1, updated_at = ? WHERE id = ?',
          [now, row.id],
        );
      }

      res.json({
        success: true,
        ...(await currentVersion(type, id)),
        nodes: nest(await loadRows(type, id)),
      });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // A deleted record's tree. No foreign key can reach a polymorphic owner, so
  // the cascades ask for this by hand (same as the link graph).
  async function purgeVariationsFor(type, id) {
    await run(
      'DELETE FROM entity_variation_nodes WHERE entity_type = ? AND entity_id = ?',
      [String(type), String(id)],
    );
    await run(
      'DELETE FROM entity_variation_versions WHERE entity_type = ? AND entity_id = ?',
      [String(type), String(id)],
    );
  }

  return { purgeVariationsFor };
};
