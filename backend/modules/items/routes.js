'use strict';

// ---------------------------------------------------------------------------
// Items module — HTTP routes (evacuation step 1: routes moved VERBATIM from
// server.js; no logic edits — reviewability rule from the evacuation plan).
//
// The only mechanical transform applied during the move: the socket server
// `io` is late-bound in server.js (`let io = null`, assigned at listen), so
// handlers receive it through ctx.getIo() instead of a closure variable.
//
// Domain logic (saveItem, saveGroup, DTOs, usage queries) still lives in
// legacy server.js and arrives via ctx — it evacuates in the next step, when
// modules/items/service.js takes it over and the remaining ctx shrinks to
// kernel facilities only.
// ---------------------------------------------------------------------------

const contracts = require('./contract');
const {
  buildVariantPartCode,
  propertyCodeFor,
  nextPartNo,
} = require('./part-identity');
const { buildGroupOverview } = require('./group-overview');
const { validateSectionTree, reconcileSectionLinks } = require('./section-tree');
const {
  coversByGroup,
  itemCountsByGroup,
  coverBasis,
} = require('./group-covers');

module.exports = function registerItemsModuleRoutes(ctx) {
  const {
    app,
    requirePermission,
    cacheMasterData,
    guardContract,
    get,
    all,
    run,
    logChange,
    saveItem,
    saveGroup,
    rowToItemDto,
    rowToGroupDto,
    getItemsWithUsage,
    getGroupsWithUsage,
    getItemUsageDetails,
    getItemSetMembership,
    getItemRowById,
    getGroupRowById,
    getEffectiveSchema,
    getItemVariationTree,
    normalizePropertyKey,
    trackCreate,
    trackUpdate,
    trackDelete,
    trashAndDelete,
    trashAndDeleteMany,
    createAssetUploadIntent,
    completeAssetUpload,
    listAssetsForEntity,
    itemsPorts,
    getIo,
  } = ctx;

  // Groups had no realtime signal at all: a group created, renamed, deleted or
  // filled by one user stayed invisible to everyone else until they reloaded.
  //
  // Through the changelog rather than a bare socket emit, deliberately. The
  // desktop reads the SSE stream, which is fed by `logChange` — a socket.io
  // emit reaches the mobile app and nothing else. The changelog is also
  // persisted, so a client that was asleep replays what it missed on reconnect
  // instead of sitting on a stale list until someone reloads.
  async function emitGroupsChanged(groupId, action) {
    try {
      await logChange('groups', groupId, action);
    } catch (_) {
      // A broadcast is a courtesy, never the reason a write fails.
    }
  }

  /// Says that these items changed. Membership lives on the item as
  /// `combinationGroupIds`, so filing variants into a group changes the items
  /// as much as it changes the group — and the group sidebar reads the items.
  async function emitItemsUpdated(itemIds) {
    if (!Array.isArray(itemIds)) return;
    for (const itemId of itemIds) {
      try {
        // Not forced any more. Migration 041 puts a trigger on
        // group_item_memberships that announces the item, so the row is already
        // logged — this only needs to push it. Forcing as well announced every
        // item twice.
        //
        // The trigger is the better home for it: it also covers a membership
        // written by a migration or a script, which this never would.
        await logChange('items', itemId, 'UPDATE');
      } catch (_) {
        // As above.
      }
    }
  }

  app.get('/api/groups', requirePermission('config.read'), cacheMasterData, async (req, res) => {
    try {
      const rows = await getGroupsWithUsage();
      const groups = rows.map(rowToGroupDto);
      // How many items are in each group is one GROUP BY over an indexed
      // column, and both the table and the cards say it — so it always ships.
      const counts = await itemCountsByGroup({ all });
      for (const group of groups) {
        group.itemCount = counts.get(Number(group.id)) || 0;
      }
      // The cover mosaic is a different matter: it reads real item rows per
      // group, so it stays asked-for rather than always paid for.
      if (String(req.query.withCovers || '') === '1') {
        const covers = await coversByGroup({ all });
        for (const group of groups) {
          const forGroup = covers.get(Number(group.id)) || [];
          group.coverItems = forGroup;
          group.coverBasis = coverBasis(forGroup);
        }
      }
      res.json({ success: true, groups, error: null });
    } catch (error) {
      res.status(500).json({ success: false, groups: [], error: error.message });
    }
  });

  app.post('/api/items/:id/assets/upload-intent', requirePermission('config.write'), async (req, res) => {
    try {
      const entityId = Number(req.params.id);
      if (!Number.isInteger(entityId) || entityId <= 0) {
        res.status(400).json({
          success: false,
          intent: null,
          error: 'A valid item id is required.',
        });
        return;
      }
      const requestedEntityId = req.body?.entityId;
      if (requestedEntityId != null && Number(requestedEntityId) !== entityId) {
        res.status(400).json({
          success: false,
          intent: null,
          error: 'Request item id does not match the upload route item id.',
        });
        return;
      }
      const intent = await createAssetUploadIntent({
        ...(req.body || {}),
        entityType: 'item',
        entityId,
      });
      res.status(intent.alreadyUploaded ? 200 : 201).json({
        success: true,
        intent,
        error: null,
      });
    } catch (error) {
      res.status(error.statusCode || 500).json({
        success: false,
        intent: null,
        error: error.message,
      });
    }
  });

  app.post('/api/items/:id/assets/upload-complete', requirePermission('config.write'), async (req, res) => {
    try {
      const entityId = Number(req.params.id);
      if (!Number.isInteger(entityId) || entityId <= 0) {
        res.status(400).json({
          success: false,
          asset: null,
          error: 'A valid item id is required.',
        });
        return;
      }
      const asset = await completeAssetUpload(req.body || {});
      if (asset.entityType !== 'item' || Number(asset.entityId) !== entityId) {
        res.status(400).json({
          success: false,
          asset: null,
          error: 'Completed upload does not belong to the requested item.',
        });
        return;
      }
      res.json({ success: true, asset, error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({
        success: false,
        asset: null,
        error: error.message,
      });
    }
  });

  app.get('/api/items/:id/assets', requirePermission('config.read'), async (req, res) => {
    try {
      const assets = await listAssetsForEntity('item', Number(req.params.id));
      res.json({ success: true, assets, error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({
        success: false,
        assets: [],
        error: error.message,
      });
    }
  });

  // Which sets hold this part. Gated on config.read like the rest of
  // /api/items/:id/*, rather than inventory.read: the people who live in the
  // item editor are not necessarily the people who run inventory.
  app.get('/api/items/:id/sets', requirePermission('config.read'), async (req, res) => {
    try {
      const sets = await getItemSetMembership(Number(req.params.id));
      res.json({ success: true, sets, error: null });
    } catch (error) {
      res.status(500).json({ success: false, sets: [], error: error.message });
    }
  });

  app.get('/api/items/:id/usage', requirePermission('config.read'), async (req, res) => {
    try {
      const usage = await getItemUsageDetails(Number(req.params.id));
      res.json({ success: true, usage, error: null });
    } catch (error) {
      res.status(500).json({ success: false, usage: [], error: error.message });
    }
  });

  app.get('/api/items', requirePermission('config.read'), cacheMasterData, async (req, res) => {
    try {
      const rows = await getItemsWithUsage();
      const items = await Promise.all(rows.map(rowToItemDto));
      res.json({ success: true, items, error: null });
    } catch (error) {
      res.status(500).json({ success: false, items: [], error: error.message });
    }
  });

  // What the next part in this scope should be called, for a form to pre-fill.
  //
  // Declared before /api/items/:id or Express reads the path as an id. The
  // sequence lives here rather than in the dialog that shows it: a rule a
  // screen owns is a rule the next screen skips.
  app.get(
    '/api/items/next-part-identity',
    requirePermission('config.read'),
    async (req, res) => {
      try {
        const groupId = Number(req.query.groupId || 0);
        if (!groupId) {
          return res
            .status(400)
            .json({ success: false, error: 'groupId is required.' });
        }
        const setId = Number(req.query.setId || 0) || null;
        // A set that has only been named has no members, so its scope is
        // empty. Nothing stored can tell us that — the caller says so.
        const setPending =
          req.query.setPending === '1' || req.query.setPending === 'true';

        const groupRow = await get('SELECT name FROM groups WHERE id = ?', [groupId]);
        if (!groupRow) {
          return res.status(404).json({ success: false, error: 'Group not found.' });
        }
        const setRow = setId
          ? await get('SELECT name FROM inventory_sets WHERE id = ?', [setId])
          : null;

        // The property values, in declared order, so the suggestion matches
        // what the save will stamp. Absent means a caller with no properties —
        // the quick-entry dialog — and the answer is then what it always was.
        const rawValues = req.query.values;
        const values = Array.isArray(rawValues)
          ? rawValues
          : typeof rawValues === 'string' && rawValues.length
            ? rawValues.split('|')
            : [];
        const valueCodes = values
          .map((value) => propertyCodeFor(value))
          .filter((code) => code.length > 0);

        const itemName = req.query.name || '';
        const partNo = await nextPartNo(
          { groupId, setId, setPending, itemName },
          { get, all },
        );
        const partCode = buildVariantPartCode({
          groupName: groupRow.name,
          setName: req.query.setName || setRow?.name || '',
          itemName,
          valueCodes,
          partNo,
        });
        res.json({
          success: true,
          partNo,
          partCode,
          // The number counts parts of this NAME in the group now, so the old
          // set/group-unfiled distinction no longer describes what was counted.
          scope: itemName ? 'group-name' : 'group',
          error: null,
        });
      } catch (error) {
        res.status(500).json({ success: false, error: error.message });
      }
    },
  );

  app.get('/api/items/:id', requirePermission('config.read'), async (req, res) => {
    try {
      const row = await get(`
        SELECT
          items.*,
          pipeline_templates.name AS default_pipeline_name,
          developed_for_client.name AS developed_for_client_name,
          developed_for_client.contact_name AS developed_for_contact_name,
          developed_for_client.designation AS developed_for_designation,
          developed_for_client.phone AS developed_for_phone,
          developed_for_client.email AS developed_for_email,
          developed_for_contractor.name AS developed_for_sub_contractor_name,
          developed_for_contractor.designation AS developed_for_sub_contractor_designation,
          developed_for_contractor.phone AS developed_for_sub_contractor_phone,
          developed_for_contractor.email AS developed_for_sub_contractor_email,
          -- The people this part's deal was done with (056), as one JSON column so
          -- the list read stays one statement per page however many parts it has.
          (
            SELECT json_group_array(json_object(
              'id', c.id, 'name', c.name, 'designation', c.designation,
              'phone', c.phone, 'email', c.email, 'isArchived', c.is_archived
            ))
            FROM (
              SELECT pc.* FROM item_deal_contacts idc
              JOIN party_contacts pc ON pc.id = idc.contact_id
              WHERE idc.item_id = items.id
              ORDER BY pc.is_primary DESC, pc.name COLLATE NOCASE ASC
            ) c
          ) AS developed_for_contacts_json,
          (
            (SELECT COUNT(*) FROM order_items WHERE order_items.item_id = items.id) +
            (SELECT COUNT(*) FROM delivery_challan_items WHERE delivery_challan_items.item_id = items.id) +
            (SELECT COUNT(*) FROM order_material_requirements WHERE order_material_requirements.item_id = items.id) +
            (SELECT COUNT(*) FROM materials WHERE materials.linked_item_id = items.id) +
            (SELECT COUNT(*) FROM material_group_item_links WHERE material_group_item_links.item_id = items.id)
          ) AS usage_count
        FROM items
        LEFT JOIN pipeline_templates ON items.default_pipeline_id = pipeline_templates.id
        LEFT JOIN clients developed_for_client ON developed_for_client.id = items.developed_for_client_id
        LEFT JOIN sub_contractors developed_for_contractor ON developed_for_contractor.id = items.developed_for_sub_contractor_id
        WHERE items.id = ?
      `, [req.params.id]);
      if (!row) {
        return res.status(404).json({ success: false, item: null, error: 'Not found' });
      }
      res.json({ success: true, item: await rowToItemDto(row), error: null });
    } catch (error) {
      res.status(500).json({ success: false, item: null, error: error.message });
    }
  });

  app.put('/api/items/:id/short-code', requirePermission('config.write'), async (req, res) => {
    try {
      const io = getIo();
      const id = Number(req.params.id);
      const shortCode = req.body.shortCode || '';

      if (!id) {
        return res.status(400).json({ success: false, error: 'Invalid ID' });
      }

      const item = await get('SELECT * FROM items WHERE id = ?', [id]);
      if (!item) {
        return res.status(404).json({ success: false, error: 'Item not found' });
      }

      await run('UPDATE items SET short_code = ?, updated_at = ? WHERE id = ?', [shortCode, new Date().toISOString(), id]);

      // Notify clients of the change
      await logChange('items', id, 'UPDATE');

      const updatedRow = await get('SELECT * FROM items WHERE id = ?', [id]);
      const itemDto = await rowToItemDto(updatedRow);

      if (io) {
        io.emit('item_updated', itemDto);
      }

      res.json({ success: true, item: itemDto, error: null });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/items', requirePermission('config.write'), guardContract(contracts.itemWrite), async (req, res) => {
    try {
      const io = getIo();
      const item = await saveItem(req.body || {});
      const itemDto = await rowToItemDto(item);
      if (io) {
        io.emit('item_added', itemDto);
      }
      trackCreate('items', item.id, item, req);
      res.status(201).json({ success: true, item: itemDto, error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({
        success: false,
        item: null,
        error: error.message,
      });
    }
  });

  app.patch('/api/items/:id', requirePermission('config.write'), guardContract(contracts.itemWrite), async (req, res) => {
    try {
      const io = getIo();
      const id = Number(req.params.id);
      const before = await get('SELECT * FROM items WHERE id = ?', [id]);
      const item = await saveItem({
        ...(req.body || {}),
        id,
      });
      const itemDto = await rowToItemDto(item);
      if (io) {
        io.emit('item_updated', itemDto);
      }
      const after = await get('SELECT * FROM items WHERE id = ?', [id]);
      trackUpdate('items', id, before, after, req);
      res.json({ success: true, item: itemDto, error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({
        success: false,
        item: null,
        error: error.message,
      });
    }
  });

  // How the part's item sheet is nested, and therefore which of its records
  // are linked to which (migration 057). One validator, one writer: the tree
  // is checked here and the links are made by reconcileSectionLinks only.
  app.put('/api/items/:id/section-tree', requirePermission('config.write'), async (req, res) => {
    try {
      const id = Number(req.params.id);
      const before = await get('SELECT * FROM items WHERE id = ?', [id]);
      if (!before) {
        return res.status(404).json({ success: false, item: null, error: 'Item not found.' });
      }
      const tree = validateSectionTree(req.body?.tree);
      await run('BEGIN TRANSACTION');
      try {
        await run('UPDATE items SET section_tree_json = ?, updated_at = ? WHERE id = ?', [
          JSON.stringify(tree),
          new Date().toISOString(),
          id,
        ]);
        const links = await reconcileSectionLinks({ get, all, run }, id);
        await logChange('items', id, 'UPDATE');
        await run('COMMIT');
        const after = await get('SELECT * FROM items WHERE id = ?', [id]);
        trackUpdate('items', id, before, after, req);
        const itemDto = await rowToItemDto(await getItemRowById(id));
        const io = getIo();
        if (io) io.emit('item_updated', itemDto);
        res.json({ success: true, item: itemDto, links, error: null });
      } catch (error) {
        await run('ROLLBACK');
        throw error;
      }
    } catch (error) {
      res.status(error.statusCode || 500).json({
        success: false,
        item: null,
        code: error.code || null,
        error: error.message,
      });
    }
  });

  app.patch('/api/items/:id/archive', requirePermission('config.write'), async (req, res) => {
    try {
      const id = Number(req.params.id);
      const item = await get('SELECT * FROM items WHERE id = ?', [id]);
      if (!item) {
        return res.status(404).json({ success: false, error: 'Not found' });
      }
      const usage = await get(`
        SELECT 
          (SELECT COUNT(*) FROM order_items WHERE item_id = ?) +
          (SELECT COUNT(*) FROM delivery_challan_items WHERE item_id = ?) +
          (SELECT COUNT(*) FROM order_material_requirements WHERE item_id = ?) +
          (SELECT COUNT(*) FROM materials WHERE linked_item_id = ?) +
          (SELECT COUNT(*) FROM material_group_item_links WHERE item_id = ?) AS count
      `, [id, id, id, id, id]);
      if ((usage?.count || 0) > 0) {
        const error = new Error('Item is in use');
        error.statusCode = 409;
        throw error;
      }
      await run('UPDATE items SET is_archived = 1, updated_at = ? WHERE id = ?', [new Date().toISOString(), id]);
      await run('UPDATE item_variation_nodes SET is_archived = 1, updated_at = ? WHERE item_id = ?', [new Date().toISOString(), id]);
      // Archiving is an update, not a removal, so it logs as one — but it
      // logged as nothing at all before, which made a sitting that archived a
      // part look like a sitting where nobody touched it.
      const archived = await get('SELECT * FROM items WHERE id = ?', [id]);
      trackUpdate('items', id, item, archived, req);
      res.json({ success: true, error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/items/:id', requirePermission('config.write'), async (req, res) => {
    try {
      const id = Number(req.params.id);
      const before = await get('SELECT * FROM items WHERE id = ?', [id]);
      await itemsPorts.delete('item', id, req);
      trackDelete('items', id, before, req);
      res.json({ success: true, error: null });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Relocate an item to another group without touching its variation tree /
  // conversions (saveItem would rewrite those). Used by the delete-group flow.
  app.patch('/api/items/:id/group', requirePermission('config.write'), async (req, res) => {
    try {
      const id = Number(req.params.id);
      const groupId = Number((req.body || {}).groupId);
      const existing = await getItemRowById(id);
      if (!existing) {
        res.status(404).json({ success: false, item: null, error: 'Item not found.' });
        return;
      }
      if (!groupId) {
        res.status(400).json({ success: false, item: null, error: 'A target group is required.' });
        return;
      }
      const groupRow = await get('SELECT * FROM groups WHERE id = ?', [groupId]);
      if (!groupRow || groupRow.is_archived) {
        res.status(400).json({
          success: false,
          item: null,
          error: 'Selected group does not exist or is archived.',
        });
        return;
      }
      await run('UPDATE items SET group_id = ?, updated_at = ? WHERE id = ?', [
        groupId,
        new Date().toISOString(),
        id,
      ]);
      const updated = await getItemRowById(id);
      res.json({ success: true, item: await rowToItemDto(updated), error: null });
    } catch (error) {
      // A part code is unique per group, so moving a part into a group that
      // already has its code is a conflict to show, not a server fault.
      if (/UNIQUE constraint failed: items\.group_id, items\.part_code/.test(String(error?.message || ''))) {
        res.status(409).json({
          success: false,
          item: null,
          code: 'part_code_duplicate',
          error: 'That group already has a part with this part code. Change the code first.',
        });
        return;
      }
      res.status(error.statusCode || 500).json({ success: false, item: null, error: error.message });
    }
  });

  app.post('/api/groups', requirePermission('config.write'), guardContract(contracts.groupWrite), async (req, res) => {
    try {
      const group = await saveGroup(req.body || {});
      const dto = rowToGroupDto(group);
      await emitGroupsChanged(dto.id, 'INSERT');
      trackCreate('groups', dto.id, group, req);
      res.status(201).json({ success: true, group: dto, error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({
        success: false,
        group: null,
        error: error.message,
      });
    }
  });

  // Enhancement 2.2/2.3 — bulk-assign item variants to a combination group.
  // Idempotent: re-assigning an item that is already a member is a no-op, and the
  // item's primary hierarchical group (items.group_id) is never modified, so dual
  // membership is preserved.
  app.post('/api/groups/:groupId/items', requirePermission('config.write'), async (req, res) => {
    try {
      const groupId = Number(req.params.groupId);
      const group = await getGroupRowById(groupId);
      if (!group) {
        res.status(404).json({ success: false, group: null, assignedCount: 0, error: 'Group not found.' });
        return;
      }
      if ((group.group_structure || 'hierarchical') !== 'combination') {
        res.status(400).json({
          success: false,
          group: rowToGroupDto(group),
          assignedCount: 0,
          error: 'Items can only be bulk-assigned to combination groups.',
        });
        return;
      }
      const rawIds = Array.isArray(req.body?.itemIds) ? req.body.itemIds : [];
      const itemIds = [...new Set(rawIds.map((value) => Number(value)).filter((value) => Number.isInteger(value) && value > 0))];
      if (itemIds.length === 0) {
        res.status(400).json({
          success: false,
          group: rowToGroupDto(group),
          assignedCount: 0,
          error: 'itemIds must be a non-empty array of item ids.',
        });
        return;
      }

      const placeholders = itemIds.map(() => '?').join(', ');
      const existingItems = await all(
        `SELECT id FROM items WHERE id IN (${placeholders})`,
        itemIds,
      );
      const validIds = existingItems.map((row) => row.id);
      if (validIds.length === 0) {
        res.status(400).json({
          success: false,
          group: rowToGroupDto(group),
          assignedCount: 0,
          error: 'None of the supplied item ids exist.',
        });
        return;
      }

      const now = new Date().toISOString();
      const maxOrderRow = await get(
        'SELECT MAX(sort_order) AS max_order FROM group_item_memberships WHERE group_id = ?',
        [groupId],
      );
      let sortOrder = Number(maxOrderRow?.max_order || 0);
      let assignedCount = 0;
      for (const itemId of validIds) {
        sortOrder += 1;
        const result = await run(
          `
          INSERT OR IGNORE INTO group_item_memberships (group_id, item_id, sort_order, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?)
          `,
          [groupId, itemId, sortOrder, now, now],
        );
        if (result.changes > 0) {
          assignedCount += 1;
        } else {
          sortOrder -= 1; // already a member; don't burn a sort slot
        }
      }
      await run('UPDATE groups SET updated_at = ? WHERE id = ?', [now, groupId]);

      // Two different things changed, so two different signals. The group's
      // membership moved — and so did `combinationGroupIds` on every item that
      // joined it, which is what the group sidebar actually lists. Without the
      // per-item signal every other screen keeps showing the group as empty.
      await emitGroupsChanged(groupId, 'UPDATE');
      await emitItemsUpdated(validIds);

      res.status(201).json({
        success: true,
        group: rowToGroupDto(await getGroupRowById(groupId)),
        assignedCount,
        skippedCount: validIds.length - assignedCount,
        missingCount: itemIds.length - validIds.length,
        error: null,
      });
    } catch (error) {
      res.status(error.statusCode || 500).json({
        success: false,
        group: null,
        assignedCount: 0,
        error: error.message,
      });
    }
  });

  // List the item ids that belong to a combination (or any) group.
  app.get('/api/groups/:groupId/items', requirePermission('config.read'), async (req, res) => {
    try {
      const groupId = Number(req.params.groupId);
      const group = await getGroupRowById(groupId);
      if (!group) {
        res.status(404).json({ success: false, itemIds: [], error: 'Group not found.' });
        return;
      }
      const rows = await all(
        'SELECT item_id FROM group_item_memberships WHERE group_id = ? ORDER BY sort_order ASC',
        [groupId],
      );
      res.json({ success: true, itemIds: rows.map((row) => row.item_id), error: null });
    } catch (error) {
      res.status(500).json({ success: false, itemIds: [], error: error.message });
    }
  });

  app.patch('/api/groups/:id', requirePermission('config.write'), guardContract(contracts.groupWrite), async (req, res) => {
    try {
      const id = Number(req.params.id);
      // saveGroup answers with the saved row, not the one it replaced, so the
      // before state is read here or the diff is empty and nothing is logged.
      const before = await get('SELECT * FROM groups WHERE id = ?', [id]);
      const group = await saveGroup({
        ...(req.body || {}),
        id,
      });
      const dto = rowToGroupDto(group);
      await emitGroupsChanged(dto.id, 'UPDATE');
      trackUpdate('groups', dto.id, before, group, req);
      res.json({ success: true, group: dto, error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({
        success: false,
        group: null,
        error: error.message,
      });
    }
  });

  // Archiving says "not in use any more" without destroying anything, which is
  // what people actually want nine times out of ten — DELETE here cascades
  // through the group's items.
  //
  // The refusal NAMES what is still inside. It counted child groups, items and
  // linked materials separately all along and then threw away which, leaving
  // the user to guess what to empty.
  app.patch('/api/groups/:id/archive', requirePermission('config.write'), async (req, res) => {
    try {
      const id = Number(req.params.id);
      const group = await get('SELECT * FROM groups WHERE id = ?', [id]);
      if (!group) {
        return res.status(404).json({ success: false, error: 'Not found' });
      }
      const usage = await get(`
        SELECT
          (SELECT COUNT(*) FROM groups WHERE parent_group_id = ? AND is_archived = 0) AS childGroups,
          (SELECT COUNT(*) FROM items WHERE group_id = ? AND is_archived = 0) AS items,
          (SELECT COUNT(*) FROM materials WHERE linked_group_id = ?) AS materials
      `, [id, id, id]);
      const blockers = [];
      const plural = (count, word) => `${count} ${word}${count === 1 ? '' : 's'}`;
      if (Number(usage?.childGroups || 0) > 0) {
        blockers.push(plural(Number(usage.childGroups), 'active child group'));
      }
      if (Number(usage?.items || 0) > 0) {
        blockers.push(plural(Number(usage.items), 'active item'));
      }
      if (Number(usage?.materials || 0) > 0) {
        blockers.push(plural(Number(usage.materials), 'linked material'));
      }
      if (blockers.length > 0) {
        const error = new Error(
          `"${group.name}" still holds ${blockers.join(' and ')}. `
          + 'Move or archive them first.',
        );
        error.statusCode = 409;
        error.code = 'group_in_use';
        throw error;
      }
      await run('UPDATE groups SET is_archived = 1, updated_at = ? WHERE id = ?', [new Date().toISOString(), id]);
      // Every other group write broadcasts; this one never did, so an archive
      // stayed invisible to every other client until they reloaded.
      await emitGroupsChanged(id, 'UPDATE');
      // The updated row, so the caller knows the new state without refetching
      // the whole list.
      res.json({ success: true, group: rowToGroupDto(await getGroupRowById(id)), error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({
        success: false,
        group: null,
        code: error.code || null,
        error: error.message,
      });
    }
  });

  // Archive was a one-way door: there was no route back, so a group archived by
  // mistake could only be fixed in the database.
  app.patch('/api/groups/:id/unarchive', requirePermission('config.write'), async (req, res) => {
    try {
      const id = Number(req.params.id);
      const group = await get('SELECT * FROM groups WHERE id = ?', [id]);
      if (!group) {
        return res.status(404).json({ success: false, error: 'Not found' });
      }
      if (group.parent_group_id) {
        const parent = await get('SELECT id, name, is_archived FROM groups WHERE id = ?', [group.parent_group_id]);
        // A live group inside an archived one is a group nobody can reach from
        // the tree: restore the parent first and the question answers itself.
        if (parent && Number(parent.is_archived || 0) === 1) {
          const error = new Error(
            `"${group.name}" sits under "${parent.name}", which is archived. `
            + 'Restore that one first.',
          );
          error.statusCode = 409;
          error.code = 'parent_archived';
          throw error;
        }
      }
      await run('UPDATE groups SET is_archived = 0, updated_at = ? WHERE id = ?', [new Date().toISOString(), id]);
      await emitGroupsChanged(id, 'UPDATE');
      res.json({ success: true, group: rowToGroupDto(await getGroupRowById(id)), error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({
        success: false,
        group: null,
        code: error.code || null,
        error: error.message,
      });
    }
  });

  app.delete('/api/groups/:id', requirePermission('config.write'), async (req, res) => {
    try {
      const id = Number(req.params.id);
      const before = await get('SELECT * FROM groups WHERE id = ?', [id]);
      // No emitGroupsChanged here: the delete port already writes its own
      // DELETE row to the changelog, and a second one would have every client
      // refresh twice for one deletion.
      await itemsPorts.delete('group', id, req);
      trackDelete('groups', id, before, req);
      res.json({ success: true, error: null });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Scarcity → abundance.
  //
  // Lists the fields the group now asks for that existing items have no value
  // for, plus the items concerned, so the UI can ask the user to fill them in.
  // Nothing is back-filled automatically: until someone supplies a value the
  // field simply reads as nil on those items.
  app.get('/api/groups/:id/schema-impact', requirePermission('config.read'), async (req, res) => {
    try {
      const groupId = Number(req.params.id);
      const group = await getGroupRowById(groupId);
      if (!group) {
        const error = new Error('Group not found.');
        error.statusCode = 404;
        throw error;
      }
      const schema = await getEffectiveSchema(groupId);
      const items = await all(
        'SELECT id, name, display_name FROM items WHERE group_id = ? AND is_archived = 0 ORDER BY LOWER(COALESCE(NULLIF(display_name, \'\'), name)) ASC',
        [groupId],
      );

      const missingByProperty = new Map();
      for (const item of items) {
        const tree = await getItemVariationTree(item.id);
        const presentKeys = new Set(
          (Array.isArray(tree) ? tree : [])
            .filter((node) => node.kind === 'property')
            .map((node) => normalizePropertyKey(node.name))
            .filter(Boolean),
        );
        for (const draft of schema.propertyDrafts || []) {
          if (presentKeys.has(draft.propertyKey)) {
            continue;
          }
          if (!missingByProperty.has(draft.propertyKey)) {
            missingByProperty.set(draft.propertyKey, {
              propertyKey: draft.propertyKey,
              displayName: draft.name || draft.propertyKey,
              mandatory: Boolean(draft.mandatory),
              items: [],
            });
          }
          missingByProperty.get(draft.propertyKey).items.push({
            id: item.id,
            name: item.display_name || item.name || `Item #${item.id}`,
          });
        }
      }

      const missingProperties = [...missingByProperty.values()];
      res.json({
        success: true,
        groupId,
        itemCount: items.length,
        missingProperties,
        retiredProperties: (schema.retiredPropertyDrafts || []).map((draft) => ({
          propertyKey: draft.propertyKey,
          displayName: draft.name || draft.propertyKey,
        })),
        error: null,
      });
    } catch (error) {
      res.status(error.statusCode || 500).json({
        success: false,
        groupId: null,
        itemCount: 0,
        missingProperties: [],
        retiredProperties: [],
        error: error.message,
      });
    }
  });

  // Everything a group is, in one read: what it holds, what it inherits, and
  // what its items say about it. Clicking a group asks "what is this", which
  // the editor was never the answer to.
  app.get('/api/groups/:id/overview', requirePermission('config.read'), async (req, res) => {
    try {
      const groupId = Number(req.params.id);
      const group = await getGroupRowById(groupId);
      if (!group) {
        res.status(404).json({ success: false, overview: null, error: 'Group not found.' });
        return;
      }
      // A group with a broken lineage should still show its items rather than
      // failing the whole read for a schema nobody asked to see.
      let schema = null;
      try {
        schema = await getEffectiveSchema(groupId);
      } catch (error) {
        console.warn(`[groups] schema unavailable for ${groupId}: ${error.message}`);
      }
      const overview = await buildGroupOverview({ all, group, schema });
      res.json({
        success: true,
        overview: { ...overview, group: rowToGroupDto(group) },
        error: null,
      });
    } catch (error) {
      res.status(error.statusCode || 500).json({
        success: false,
        overview: null,
        error: error.message,
      });
    }
  });

  app.get('/api/groups/:id/effective-schema', requirePermission('config.read'), async (req, res) => {
    try {
      const schema = await getEffectiveSchema(Number(req.params.id));
      res.json({ success: true, schema, error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({
        success: false,
        schema: null,
        error: error.message,
      });
    }
  });
};
