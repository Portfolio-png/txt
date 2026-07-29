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

module.exports = function registerItemsModuleRoutes(ctx) {
  const {
    app,
    requirePermission,
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
    getItemRowById,
    getGroupRowById,
    getEffectiveSchema,
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

  app.get('/api/groups', requirePermission('config.read'), async (req, res) => {
    try {
      const rows = await getGroupsWithUsage();
      res.json({ success: true, groups: rows.map(rowToGroupDto), error: null });
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

  app.get('/api/items/:id/usage', requirePermission('config.read'), async (req, res) => {
    try {
      const usage = await getItemUsageDetails(Number(req.params.id));
      res.json({ success: true, usage, error: null });
    } catch (error) {
      res.status(500).json({ success: false, usage: [], error: error.message });
    }
  });

  app.get('/api/items', requirePermission('config.read'), async (req, res) => {
    try {
      const rows = await getItemsWithUsage();
      const items = await Promise.all(rows.map(rowToItemDto));
      res.json({ success: true, items, error: null });
    } catch (error) {
      res.status(500).json({ success: false, items: [], error: error.message });
    }
  });

  app.get('/api/items/:id', requirePermission('config.read'), async (req, res) => {
    try {
      const row = await get(`
        SELECT
          items.*,
          pipeline_templates.name AS default_pipeline_name,
          (
            (SELECT COUNT(*) FROM order_items WHERE order_items.item_id = items.id) +
            (SELECT COUNT(*) FROM delivery_challan_items WHERE delivery_challan_items.item_id = items.id) +
            (SELECT COUNT(*) FROM order_material_requirements WHERE order_material_requirements.item_id = items.id) +
            (SELECT COUNT(*) FROM materials WHERE materials.linked_item_id = items.id) +
            (SELECT COUNT(*) FROM material_group_item_links WHERE material_group_item_links.item_id = items.id)
          ) AS usage_count
        FROM items
        LEFT JOIN pipeline_templates ON items.default_pipeline_id = pipeline_templates.id
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
      res.json({ success: true, error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/items/:id', requirePermission('config.write'), async (req, res) => {
    try {
      const id = Number(req.params.id);
      await itemsPorts.delete('item', id, req);
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
      res.status(error.statusCode || 500).json({ success: false, item: null, error: error.message });
    }
  });

  app.post('/api/groups', requirePermission('config.write'), guardContract(contracts.groupWrite), async (req, res) => {
    try {
      const group = await saveGroup(req.body || {});
      res.status(201).json({ success: true, group: rowToGroupDto(group), error: null });
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
      const group = await saveGroup({
        ...(req.body || {}),
        id: Number(req.params.id),
      });
      res.json({ success: true, group: rowToGroupDto(group), error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({
        success: false,
        group: null,
        error: error.message,
      });
    }
  });

  app.patch('/api/groups/:id/archive', requirePermission('config.write'), async (req, res) => {
    try {
      const id = Number(req.params.id);
      const group = await get('SELECT * FROM groups WHERE id = ?', [id]);
      if (!group) {
        return res.status(404).json({ success: false, error: 'Not found' });
      }
      const usage = await get(`
        SELECT
          (SELECT COUNT(*) FROM groups WHERE parent_group_id = ? AND is_archived = 0) +
          (SELECT COUNT(*) FROM items WHERE group_id = ? AND is_archived = 0) +
          (SELECT COUNT(*) FROM materials WHERE linked_group_id = ?) AS count
      `, [id, id, id]);
      if ((usage?.count || 0) > 0) {
        const error = new Error('Group is in use');
        error.statusCode = 409;
        throw error;
      }
      await run('UPDATE groups SET is_archived = 1, updated_at = ? WHERE id = ?', [new Date().toISOString(), id]);
      res.json({ success: true, error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/groups/:id', requirePermission('config.write'), async (req, res) => {
    try {
      const id = Number(req.params.id);
      await itemsPorts.delete('group', id, req);
      res.json({ success: true, error: null });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
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
