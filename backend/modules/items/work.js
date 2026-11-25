'use strict';

// ---------------------------------------------------------------------------
// Items and groups: what the twenty-eight handlers in routes.js did.
//
// Statement for statement what they were. Instead of writing a response each
// returns answer(status, body), the same status and the same body; a Track
// entry is noted on the request (req.track) and written by the route, which
// has the real request. A function takes a plain `req` with `params`,
// `query`, `body` and `user`.
//
// What these call to do the work (saveItem, saveGroup, the variation tree, the
// usage reads) is still defined in server.js and handed in by name. Moving that
// into this folder is a separate piece of work; this file is the seam it will
// be moved behind.
//
// ./operations.js publishes these at the kernel desk; ./routes.js asks the desk.
// ---------------------------------------------------------------------------

const { answer } = require('../../kernel/desk-kit');
const {
  buildVariantPartCode,
  propertyCodeFor,
  nextPartNo,
} = require('./part-identity');
const { buildGroupOverview } = require('./group-overview');
const { isSystemGroup } = require('./system-groups');
const { validateSectionTree, reconcileSectionLinks } = require('./section-tree');
const {
  coversByGroup,
  itemCountsByGroup,
  coverBasis,
} = require('./group-covers');


function createItemsWork({
  desk,
  get,
  all,
  run,
  logChange,
  saveItem,
  saveGroup,
  rowToItemDto,
  rowsToItemDtos,
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
  createAssetUploadIntent,
  completeAssetUpload,
  listAssetsForEntity,
  listEntityPhotos,
  arrangeEntityPhotos,
  MAX_PART_PHOTOS,
  itemsPorts,
}) {

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

  // --- what an item needs to know from its neighbours -------------------------

  /// How many records in other modules name this item: order lines and
  /// material requirements, challan lines, materials and material-group links.
  /// An item with any cannot be archived.
  async function itemUsageCount(itemId) {
    const [orders, challans, inventory] = [
      await desk.ask('orders.items.usage', { itemId }),
      await desk.ask('challans.items.lineCount', { itemId }),
      await desk.ask('inventory.items.usage', { itemId }),
    ];
    return orders.count + challans.count + inventory.count;
  }

  /// A unit's name by its id, asked of units. Nothing is remembered between
  /// calls here: a unit can be renamed, and a name kept would go stale.
  async function unitNameOf(unitId) {
    if (unitId == null) return null;
    const { row } = await desk.ask('units.rows.get', { id: unitId });
    return row ? row.name : null;
  }

  /// The columns an item's read used to get from joins: the name of its default
  /// pipeline, who it was developed for, the people of that deal as JSON, and
  /// its usage count. Same names, same shapes.
  async function itemNeighbourFacts(item) {
    const pipeline = item.default_pipeline_id
      ? (await desk.ask('pipelines.templates.row', { id: item.default_pipeline_id })).row
      : null;
    const client = item.developed_for_client_id
      ? (await desk.ask('clients.rows.get', { id: item.developed_for_client_id })).row
      : null;
    const contractor = item.developed_for_sub_contractor_id
      ? (await desk.ask('clients.subContractors.row', { id: item.developed_for_sub_contractor_id })).row
      : null;
    // Which people is this module's record (item_deal_contacts); who they are
    // is the clients module's.
    const dealt = await all('SELECT contact_id FROM item_deal_contacts WHERE item_id = ?', [item.id]);
    const people = dealt.length
      ? (await desk.ask('clients.contacts.byIds', { ids: dealt.map((row) => row.contact_id) })).rows
      : [];
    const or = (value) => (value === undefined ? null : value);
    return {
      default_pipeline_name: or(pipeline?.name),
      developed_for_client_name: or(client?.name),
      developed_for_contact_name: or(client?.contact_name),
      developed_for_designation: or(client?.designation),
      developed_for_phone: or(client?.phone),
      developed_for_email: or(client?.email),
      developed_for_sub_contractor_name: or(contractor?.name),
      developed_for_sub_contractor_designation: or(contractor?.designation),
      developed_for_sub_contractor_phone: or(contractor?.phone),
      developed_for_sub_contractor_email: or(contractor?.email),
      developed_for_contacts_json: JSON.stringify(people.map((person) => ({
        id: person.id,
        name: person.name,
        designation: person.designation,
        phone: person.phone,
        email: person.email,
        isArchived: person.is_archived,
      }))),
      usage_count: await itemUsageCount(item.id),
    };
  }

  async function listGroups(req) {
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
      return answer(200, { success: true, groups, error: null });
    } catch (error) {
      return answer(500, { success: false, groups: [], error: error.message });
    }
  }

  async function itemAssetUploadIntent(req) {
    try {
      const entityId = Number(req.params.id);
      if (!Number.isInteger(entityId) || entityId <= 0) {
        return answer(400, {
          success: false,
          intent: null,
          error: 'A valid item id is required.',
        });
        return;
      }
      const requestedEntityId = req.body?.entityId;
      if (requestedEntityId != null && Number(requestedEntityId) !== entityId) {
        return answer(400, {
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
      return answer(intent.alreadyUploaded ? 200 : 201, {
        success: true,
        intent,
        error: null,
      });
    } catch (error) {
      return answer(error.statusCode || 500, {
        success: false,
        intent: null,
        error: error.message,
        code: error.code || null,
      });
    }
  }

  async function itemAssetUploadComplete(req) {
    try {
      const entityId = Number(req.params.id);
      if (!Number.isInteger(entityId) || entityId <= 0) {
        return answer(400, {
          success: false,
          asset: null,
          error: 'A valid item id is required.',
        });
        return;
      }
      const asset = await completeAssetUpload(req.body || {});
      if (asset.entityType !== 'item' || Number(asset.entityId) !== entityId) {
        return answer(400, {
          success: false,
          asset: null,
          error: 'Completed upload does not belong to the requested item.',
        });
        return;
      }
      return answer(200, { success: true, asset, error: null });
    } catch (error) {
      return answer(error.statusCode || 500, {
        success: false,
        asset: null,
        error: error.message,
        code: error.code || null,
      });
    }
  }

  async function listItemAssets(req) {
    try {
      const assets = await listAssetsForEntity('item', Number(req.params.id));
      return answer(200, { success: true, assets, error: null });
    } catch (error) {
      return answer(error.statusCode || 500, {
        success: false,
        assets: [],
        error: error.message,
      });
    }
  }

  // A part's photos — its views — as one ordered array: the gallery's one
  // request. Each carries permanent links to its thumbnail and its photo.
  // Gated as the part's attachments (items.asset.*), the same right the
  // gallery's uploads and deletes need, so a Save never stops half-way.
  const partPhotos = () => 'item';
  async function listItemPhotos(req) {
    try {
      const photos = await listEntityPhotos('item', Number(req.params.id));
      return answer(200, { success: true, photos, limit: MAX_PART_PHOTOS, error: null });
    } catch (error) {
      return answer(error.statusCode || 500, {
        success: false,
        photos: [],
        error: error.message,
      });
    }
  }

  // The gallery's Save: { order: [photo ids, first to last], primaryId }.
  async function arrangeItemPhotos(req) {
    try {
      const photos = await arrangeEntityPhotos('item', Number(req.params.id), {
        order: req.body?.order,
        primaryId: req.body?.primaryId,
      });
      return answer(200, { success: true, photos, limit: MAX_PART_PHOTOS, error: null });
    } catch (error) {
      return answer(error.statusCode || 500, {
        success: false,
        photos: [],
        error: error.message,
      });
    }
  }

  // Which sets hold this part. Gated on config.read like the rest of
  // /api/items/:id/*, rather than inventory.read: the people who live in the
  // item editor are not necessarily the people who run inventory.
  async function itemSets(req) {
    try {
      const sets = await getItemSetMembership(Number(req.params.id));
      return answer(200, { success: true, sets, error: null });
    } catch (error) {
      return answer(500, { success: false, sets: [], error: error.message });
    }
  }

  async function itemUsage(req) {
    try {
      const usage = await getItemUsageDetails(Number(req.params.id));
      return answer(200, { success: true, usage, error: null });
    } catch (error) {
      return answer(500, { success: false, usage: [], error: error.message });
    }
  }

  // The variation tree as the list carries it: without the five node fields no
  // client reads or sends back — each node's own timestamps, its item id (the
  // item it sits in says that), its position (the array order says that), and
  // isArchived (only live nodes are listed). 18% of the list, compressed.
  //
  // Beyond the tree: since B42 every whole-item save and the editor start from
  // `GET /api/items/:id`, so the list may drop what only they read —
  // `attachments` always, and the CAD file's key and name when the part has
  // none (the detail panel shows a CAD file off the list, so a real one stays).
  // `unitConversions` stays: challans, orders, reconciliation and the phone
  // convert quantities with it straight off list rows. `GET /api/items/:id`
  // keeps everything.
  const LIST_NODE_FIELDS_DROPPED = ['createdAt', 'updatedAt', 'itemId', 'position', 'isArchived'];
  function listNode(node) {
    const out = {};
    for (const [key, value] of Object.entries(node)) {
      if (!LIST_NODE_FIELDS_DROPPED.includes(key)) out[key] = value;
    }
    out.children = (node.children || []).map(listNode);
    return out;
  }

  async function listItems(req) {
    try {
      const rows = await getItemsWithUsage();
      const items = (await rowsToItemDtos(rows)).map((item) => {
        const { attachments, cadFileKey, cadFileName, ...rest } = item;
        return {
          ...rest,
          ...(cadFileKey ? { cadFileKey, cadFileName } : {}),
          variationTree: (item.variationTree || []).map(listNode),
        };
      });
      return answer(200, { success: true, items, error: null });
    } catch (error) {
      return answer(500, { success: false, items: [], error: error.message });
    }
  }

  // What the next part in this scope should be called, for a form to pre-fill.
  //
  // Declared before /api/items/:id or Express reads the path as an id. The
  // sequence lives here rather than in the dialog that shows it: a rule a
  // screen owns is a rule the next screen skips.
  async function nextPartIdentity(req) {
    try {
      const groupId = Number(req.query.groupId || 0);
      if (!groupId) {
        return answer(400, { success: false, error: 'groupId is required.' });
      }
      const setId = Number(req.query.setId || 0) || null;
      // A set that has only been named has no members, so its scope is
      // empty. Nothing stored can tell us that — the caller says so.
      const setPending =
        req.query.setPending === '1' || req.query.setPending === 'true';

      const groupRow = await get('SELECT name FROM groups WHERE id = ?', [groupId]);
      if (!groupRow) {
        return answer(404, { success: false, error: 'Group not found.' });
      }
      // A set is inventory's; only its name is needed here.
      const setName = setId ? (await desk.ask('inventory.sets.name', { id: setId })).name : null;
      const setRow = setName == null ? null : { name: setName };

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
      return answer(200, {
        success: true,
        partNo,
        partCode,
        // The number counts parts of this NAME in the group now, so the old
        // set/group-unfiled distinction no longer describes what was counted.
        scope: itemName ? 'group-name' : 'group',
        error: null,
      });
    } catch (error) {
      return answer(500, { success: false, error: error.message });
    }
  }

  async function getItem(req) {
    try {
      // The item is this module's. Its pipeline's name, who it was developed
      // for, the people that deal was done with and how much it is used all
      // belong to other modules, and are asked of them. This used to be one
      // statement joining seven of their tables.
      const stored = await get('SELECT items.* FROM items WHERE items.id = ?', [req.params.id]);
      const row = stored ? { ...stored, ...(await itemNeighbourFacts(stored)) } : stored;
      if (!row) {
        return answer(404, { success: false, item: null, error: 'Not found' });
      }
      return answer(200, { success: true, item: await rowToItemDto(row), error: null });
    } catch (error) {
      return answer(500, { success: false, item: null, error: error.message });
    }
  }

  async function setShortCode(req) {
    try {
      const id = Number(req.params.id);
      const shortCode = req.body.shortCode || '';

      if (!id) {
        return answer(400, { success: false, error: 'Invalid ID' });
      }

      const item = await get('SELECT * FROM items WHERE id = ?', [id]);
      if (!item) {
        return answer(404, { success: false, error: 'Item not found' });
      }

      await run('UPDATE items SET short_code = ?, updated_at = ? WHERE id = ?', [shortCode, new Date().toISOString(), id]);

      // Notify clients of the change
      await logChange('items', id, 'UPDATE');

      const updatedRow = await get('SELECT * FROM items WHERE id = ?', [id]);
      const itemDto = await rowToItemDto(updatedRow);

      return answer(200, { success: true, item: itemDto, error: null });
    } catch (error) {
      return answer(500, { success: false, error: error.message });
    }
  }

  async function createItem(req) {
    try {
      const item = await saveItem(req.body || {});
      const itemDto = await rowToItemDto(item);
      req.track('create', 'items', item.id, item);
      return answer(201, { success: true, item: itemDto, error: null });
    } catch (error) {
      return answer(error.statusCode || 500, {
        success: false,
        item: null,
        error: error.message,
      });
    }
  }

  async function updateItem(req) {
    try {
      const id = Number(req.params.id);
      const before = await get('SELECT * FROM items WHERE id = ?', [id]);
      const item = await saveItem({
        ...(req.body || {}),
        id,
      });
      const itemDto = await rowToItemDto(item);
      const after = await get('SELECT * FROM items WHERE id = ?', [id]);
      req.track('update', 'items', id, before, after);
      return answer(200, { success: true, item: itemDto, error: null });
    } catch (error) {
      return answer(error.statusCode || 500, {
        success: false,
        item: null,
        error: error.message,
      });
    }
  }

  // How the part's item sheet is nested, and therefore which of its records
  // are linked to which (migration 057). One validator, one writer: the tree
  // is checked here and the links are made by reconcileSectionLinks only.
  async function setSectionTree(req) {
    try {
      const id = Number(req.params.id);
      const before = await get('SELECT * FROM items WHERE id = ?', [id]);
      if (!before) {
        return answer(404, { success: false, item: null, error: 'Item not found.' });
      }
      const tree = validateSectionTree(req.body?.tree);
      await run('BEGIN TRANSACTION');
      try {
        await run('UPDATE items SET section_tree_json = ?, updated_at = ? WHERE id = ?', [
          JSON.stringify(tree),
          new Date().toISOString(),
          id,
        ]);
        const links = await reconcileSectionLinks({ get, all, desk }, id);
        await logChange('items', id, 'UPDATE');
        await run('COMMIT');
        const after = await get('SELECT * FROM items WHERE id = ?', [id]);
        req.track('update', 'items', id, before, after);
        const itemDto = await rowToItemDto(await getItemRowById(id));
        return answer(200, { success: true, item: itemDto, links, error: null });
      } catch (error) {
        await run('ROLLBACK');
        throw error;
      }
    } catch (error) {
      return answer(error.statusCode || 500, {
        success: false,
        item: null,
        code: error.code || null,
        error: error.message,
      });
    }
  }

  async function archiveItem(req) {
    try {
      const id = Number(req.params.id);
      const item = await get('SELECT * FROM items WHERE id = ?', [id]);
      if (!item) {
        return answer(404, { success: false, error: 'Not found' });
      }
      const usage = { count: await itemUsageCount(id) };
      if ((usage?.count || 0) > 0) {
        // Said whole: the sheet shows this sentence as the reason.
        const error = new Error(
          'This part is used on orders, challans or materials, so it cannot be archived.',
        );
        error.statusCode = 409;
        throw error;
      }
      await run('UPDATE items SET is_archived = 1, updated_at = ? WHERE id = ?', [new Date().toISOString(), id]);
      await run('UPDATE item_variation_nodes SET is_archived = 1, updated_at = ? WHERE item_id = ?', [new Date().toISOString(), id]);
      // Archiving is an update, not a removal, so it logs as one — but it
      // logged as nothing at all before, which made a sitting that archived a
      // part look like a sitting where nobody touched it.
      const archived = await get('SELECT * FROM items WHERE id = ?', [id]);
      req.track('update', 'items', id, item, archived);
      return answer(200, { success: true, error: null });
    } catch (error) {
      return answer(error.statusCode || 500, { success: false, error: error.message });
    }
  }

  async function deleteItem(req) {
    try {
      const id = Number(req.params.id);
      const before = await get('SELECT * FROM items WHERE id = ?', [id]);
      await itemsPorts.delete('item', id, req);
      req.track('delete', 'items', id, before);
      return answer(200, { success: true, error: null });
    } catch (error) {
      return answer(500, { success: false, error: error.message });
    }
  }

  // Relocate an item to another group without touching its variation tree /
  // conversions (saveItem would rewrite those). Used by the delete-group flow.
  async function moveItemToGroup(req) {
    try {
      const id = Number(req.params.id);
      const groupId = Number((req.body || {}).groupId);
      const existing = await getItemRowById(id);
      if (!existing) {
        return answer(404, { success: false, item: null, error: 'Item not found.' });
        return;
      }
      if (!groupId) {
        return answer(400, { success: false, item: null, error: 'A target group is required.' });
        return;
      }
      const groupRow = await get('SELECT * FROM groups WHERE id = ?', [groupId]);
      if (!groupRow || groupRow.is_archived) {
        return answer(400, {
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
      return answer(200, { success: true, item: await rowToItemDto(updated), error: null });
    } catch (error) {
      // A part code is unique per group, so moving a part into a group that
      // already has its code is a conflict to show, not a server fault.
      if (/UNIQUE constraint failed: items\.group_id, items\.part_code/.test(String(error?.message || ''))) {
        return answer(409, {
          success: false,
          item: null,
          code: 'part_code_duplicate',
          error: 'That group already has a part with this part code. Change the code first.',
        });
        return;
      }
      return answer(error.statusCode || 500, { success: false, item: null, error: error.message });
    }
  }

  async function createGroup(req) {
    try {
      const group = await saveGroup(req.body || {});
      const dto = rowToGroupDto(group);
      await emitGroupsChanged(dto.id, 'INSERT');
      req.track('create', 'groups', dto.id, group);
      return answer(201, { success: true, group: dto, error: null });
    } catch (error) {
      return answer(error.statusCode || 500, {
        success: false,
        group: null,
        error: error.message,
      });
    }
  }

  // Enhancement 2.2/2.3 — bulk-assign item variants to a combination group.
  // Idempotent: re-assigning an item that is already a member is a no-op, and the
  // item's primary hierarchical group (items.group_id) is never modified, so dual
  // membership is preserved.
  async function addItemsToGroup(req) {
    try {
      const groupId = Number(req.params.groupId);
      const group = await getGroupRowById(groupId);
      if (!group) {
        return answer(404, { success: false, group: null, assignedCount: 0, error: 'Group not found.' });
        return;
      }
      if ((group.group_structure || 'hierarchical') !== 'combination') {
        return answer(400, {
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
        return answer(400, {
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
        return answer(400, {
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

      return answer(201, {
        success: true,
        group: rowToGroupDto(await getGroupRowById(groupId)),
        assignedCount,
        skippedCount: validIds.length - assignedCount,
        missingCount: itemIds.length - validIds.length,
        error: null,
      });
    } catch (error) {
      return answer(error.statusCode || 500, {
        success: false,
        group: null,
        assignedCount: 0,
        error: error.message,
      });
    }
  }

  // List the item ids that belong to a combination (or any) group.
  async function groupItems(req) {
    try {
      const groupId = Number(req.params.groupId);
      const group = await getGroupRowById(groupId);
      if (!group) {
        return answer(404, { success: false, itemIds: [], error: 'Group not found.' });
        return;
      }
      const rows = await all(
        'SELECT item_id FROM group_item_memberships WHERE group_id = ? ORDER BY sort_order ASC',
        [groupId],
      );
      return answer(200, { success: true, itemIds: rows.map((row) => row.item_id), error: null });
    } catch (error) {
      return answer(500, { success: false, itemIds: [], error: error.message });
    }
  }

  async function updateGroup(req) {
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
      req.track('update', 'groups', dto.id, before, group);
      return answer(200, { success: true, group: dto, error: null });
    } catch (error) {
      return answer(error.statusCode || 500, {
        success: false,
        group: null,
        error: error.message,
      });
    }
  }

  // Archiving says "not in use any more" without destroying anything, which is
  // what people actually want nine times out of ten — DELETE here cascades
  // through the group's items.
  //
  // The refusal NAMES what is still inside. It counted child groups, items and
  // linked materials separately all along and then threw away which, leaving
  // the user to guess what to empty.
  async function archiveGroup(req) {
    try {
      const id = Number(req.params.id);
      const group = await get('SELECT * FROM groups WHERE id = ?', [id]);
      if (!group) {
        return answer(404, { success: false, error: 'Not found' });
      }
      if (isSystemGroup(group)) {
        return answer(409, {
          success: false,
          code: 'system_group',
          error: `"${group.name}" is a default group and cannot be archived.`,
        });
      }
      const usage = await get(`
        SELECT
          (SELECT COUNT(*) FROM groups WHERE parent_group_id = ? AND is_archived = 0) AS childGroups,
          (SELECT COUNT(*) FROM items WHERE group_id = ? AND is_archived = 0) AS items
      `, [id, id]);
      // Materials that inherit from the group are inventory's to count.
      usage.materials = (await desk.ask('inventory.groups.materialCount', { groupId: id })).count;
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
      return answer(200, { success: true, group: rowToGroupDto(await getGroupRowById(id)), error: null });
    } catch (error) {
      return answer(error.statusCode || 500, {
        success: false,
        group: null,
        code: error.code || null,
        error: error.message,
      });
    }
  }

  // Archive was a one-way door: there was no route back, so a group archived by
  // mistake could only be fixed in the database.
  async function unarchiveGroup(req) {
    try {
      const id = Number(req.params.id);
      const group = await get('SELECT * FROM groups WHERE id = ?', [id]);
      if (!group) {
        return answer(404, { success: false, error: 'Not found' });
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
      return answer(200, { success: true, group: rowToGroupDto(await getGroupRowById(id)), error: null });
    } catch (error) {
      return answer(error.statusCode || 500, {
        success: false,
        group: null,
        code: error.code || null,
        error: error.message,
      });
    }
  }

  async function deleteGroup(req) {
    try {
      const id = Number(req.params.id);
      const before = await get('SELECT * FROM groups WHERE id = ?', [id]);
      // No emitGroupsChanged here: the delete port already writes its own
      // DELETE row to the changelog, and a second one would have every client
      // refresh twice for one deletion.
      await itemsPorts.delete('group', id, req);
      req.track('delete', 'groups', id, before);
      return answer(200, { success: true, error: null });
    } catch (error) {
      return answer(error.statusCode || 500, {
        success: false,
        ...(error.code ? { code: error.code } : {}),
        error: error.message,
      });
    }
  }

  // Scarcity → abundance.
  //
  // Lists the fields the group now asks for that existing items have no value
  // for, plus the items concerned, so the UI can ask the user to fill them in.
  // Nothing is back-filled automatically: until someone supplies a value the
  // field simply reads as nil on those items.
  async function groupSchemaImpact(req) {
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
      return answer(200, {
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
      return answer(error.statusCode || 500, {
        success: false,
        groupId: null,
        itemCount: 0,
        missingProperties: [],
        retiredProperties: [],
        error: error.message,
      });
    }
  }

  // Everything a group is, in one read: what it holds, what it inherits, and
  // what its items say about it. Clicking a group asks "what is this", which
  // the editor was never the answer to.
  async function groupOverview(req) {
    try {
      const groupId = Number(req.params.id);
      const group = await getGroupRowById(groupId);
      if (!group) {
        return answer(404, { success: false, overview: null, error: 'Group not found.' });
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
      const overview = await buildGroupOverview({ all, group, schema, unitNameOf });
      return answer(200, {
        success: true,
        overview: { ...overview, group: rowToGroupDto(group) },
        error: null,
      });
    } catch (error) {
      return answer(error.statusCode || 500, {
        success: false,
        overview: null,
        error: error.message,
      });
    }
  }

  async function groupEffectiveSchema(req) {
    try {
      const schema = await getEffectiveSchema(Number(req.params.id));
      return answer(200, { success: true, schema, error: null });
    } catch (error) {
      return answer(error.statusCode || 500, {
        success: false,
        schema: null,
        error: error.message,
      });
    }
  }

  return {
    listGroups,
    itemAssetUploadIntent,
    itemAssetUploadComplete,
    listItemAssets,
    listItemPhotos,
    arrangeItemPhotos,
    itemSets,
    itemUsage,
    listItems,
    nextPartIdentity,
    getItem,
    setShortCode,
    createItem,
    updateItem,
    setSectionTree,
    archiveItem,
    deleteItem,
    moveItemToGroup,
    createGroup,
    addItemsToGroup,
    groupItems,
    updateGroup,
    archiveGroup,
    unarchiveGroup,
    deleteGroup,
    groupSchemaImpact,
    groupOverview,
    groupEffectiveSchema,
  };
}

module.exports = { createItemsWork };
