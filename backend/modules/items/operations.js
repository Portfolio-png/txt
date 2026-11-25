'use strict';

const F = require('../../kernel/fields');
const contracts = require('./contract');

const { runMoved, joinOperations, operationsFromAsks } = require('../../kernel/desk-kit');
const ASKS = require('./asks');

// ---------------------------------------------------------------------------
// Items — what the module offers at the kernel desk.
//
//   offered to users
//     items.list · .get · .create · .update · .archive · .delete
//     items.moveToGroup · .setShortCode · .setSectionTree · .nextPartIdentity
//     items.sets · .usage · items.assets.* · items.photos.*
//     items.groups.list · .create · .update · .archive · .unarchive · .delete
//     items.groups.items · .addItems · .overview · .schemaImpact · .effectiveSchema
//     items.masterData.*        Master Data per item and pipeline
//     items.materialTypes.*     the material types and their densities
//     items.sheetProperties.*   the item sheet's property columns
//
//   internal — asked by other modules
//     items.rows.get · .rows.forCatalogue · items.units.usageCounts
//     items.groups.name · .row · .propertyNamesInUse
//     items.variations.node · .codeForValue
//
// WHO MAY ASK is what stood in front of each route: `items.*` by method for
// everything under /api/items, /api/groups and /api/item-sheet-properties; the
// attachment keys for a part's photos (`items.asset.list`, `items.asset.upload`);
// and, for /api/material-types and /api/pipelines/:id/master-data, which map to
// no module, a signed-in session to read and what the old write gate asks to
// change.
//
// The work is ./work.js and, for the three smaller route sets, a work function
// in their own files. A request's path values are named, its query travels
// under `query` and its body under `data`; an item's payload is checked by its
// own contract (./contract.js) at the route and again by saveItem.
//
//     and ./ports.js behind names, listed in ./asks.js: describe, lookupByName,
//     resolveSelection, selectionSnapshot, stock.*, groups.*, …
//
// A module reaches the second group through ./client.js.
// ---------------------------------------------------------------------------

/// How many of this module's records name each unit, as { unitId: count }.
/// `tables` are this module's own tables that have a unit_id column. With
/// `unitId`, only that unit is counted. The units master adds these up across
/// modules to decide whether a unit may still be changed or archived.
async function unitUsageCounts(all, unitId, tables) {
  const one = unitId != null && unitId !== '';
  const counts = {};
  for (const table of tables) {
    const rows = await all(
      `SELECT unit_id, COUNT(*) AS c FROM ${table}
        WHERE unit_id IS NOT NULL ${one ? 'AND unit_id = ?' : ''}
        GROUP BY unit_id`,
      one ? [unitId] : [],
    );
    for (const row of rows) counts[row.unit_id] = (counts[row.unit_id] || 0) + Number(row.c || 0);
  }
  return { ok: true, counts };
}

// What the old write gate asks of a POST to a path no module claims.
const OLD_WRITE_GATE = {
  anyRole: ['super_admin', 'admin'],
  anyPermission: ['config.write', 'inventory.update'],
};

module.exports = function itemsOperations({ all, get, run, ports, core, masterData, materialTypes, sheetProperties, rivets, springs, dieRawPlans }) {
  return joinOperations(
    operationsFromAsks('items', ASKS, ports),
    internalOperations({ all, get, run }),
    userOperations({ core, masterData, materialTypes, sheetProperties, rivets, springs, dieRawPlans }),
  );
};

function userOperations({ core, masterData, materialTypes, sheetProperties, rivets, springs, dieRawPlans }) {
  return {
    'items.groups.list': {
      permission: 'items.read',
      summary: 'Every group, with how many items it holds and its cover pictures.',
      input: { fields: { query: F.obj({ withCovers: F.text }), data: F.none } },
      run: (input, ctx) => runMoved(core.listGroups, ctx, { query: input.query || {}, body: input.data }),
    },

    'items.assets.uploadIntent': {
      permission: 'items.create',
      summary: 'Ask for somewhere to upload an item attachment.',
      input: { fields: { id: F.id, query: F.none, data: F.obj({ uploadType: F.text, entityType: F.text, entityId: F.int, fileName: F.text, contentType: F.text, sizeBytes: F.int, sha256: F.text, isPrimary: F.flag, documentTitle: F.text, thumbnail: F.text, width: F.int, height: F.int }) } },
      run: (input, ctx) => runMoved(core.itemAssetUploadIntent, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.assets.uploadComplete': {
      permission: 'items.create',
      summary: 'Say an item attachment arrived.',
      input: { fields: { id: F.id, query: F.none, data: F.obj({ entityId: F.int, uploadSessionId: F.text, objectKey: F.text }) } },
      run: (input, ctx) => runMoved(core.itemAssetUploadComplete, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.assets.list': {
      permission: 'items.read',
      summary: 'An item’s attachments.',
      input: { fields: { id: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(core.listItemAssets, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.photos.list': {
      permission: 'items.asset.list',
      summary: 'A part’s photos, in order.',
      input: { fields: { id: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(core.listItemPhotos, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.photos.arrange': {
      permission: 'items.asset.upload',
      summary: 'Set a part’s photos and their order.',
      input: { fields: { id: F.id, query: F.none, data: F.obj({ order: F.list(), primaryId: F.int }) } },
      run: (input, ctx) => runMoved(core.arrangeItemPhotos, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.sets': {
      permission: 'items.read',
      summary: 'The sets an item is in, with its quantity in each.',
      input: { fields: { id: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(core.itemSets, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.usage': {
      permission: 'items.read',
      summary: 'Where an item is used: orders, challans, stock.',
      input: { fields: { id: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(core.itemUsage, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.list': {
      permission: 'items.read',
      summary: 'Items, with usage.',
      input: { fields: { query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(core.listItems, ctx, { query: input.query || {}, body: input.data }),
    },

    'items.nextPartIdentity': {
      permission: 'items.read',
      summary: 'The next part number and code for a group and set.',
      input: { fields: { query: F.obj({ groupId: F.int, setId: F.int, setPending: F.text, values: { type: 'any' }, name: F.text, setName: F.text }), data: F.none } },
      run: (input, ctx) => runMoved(core.nextPartIdentity, ctx, { query: input.query || {}, body: input.data }),
    },

    'items.get': {
      permission: 'items.read',
      summary: 'One item, with its variation tree.',
      input: { fields: { id: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(core.getItem, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.setShortCode': {
      permission: 'items.update',
      summary: 'Set an item’s short code.',
      input: { fields: { id: F.id, query: F.none, data: F.obj({ shortCode: F.text }) } },
      run: (input, ctx) => runMoved(core.setShortCode, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.create': {
      permission: 'items.create',
      summary: 'Create an item, with its variation tree.',
      input: { fields: { query: F.none, data: F.obj(contracts.itemWrite.fields) } },
      run: (input, ctx) => runMoved(core.createItem, ctx, { query: input.query || {}, body: input.data }),
    },

    'items.update': {
      permission: 'items.update',
      summary: 'Change an item. What is left out is kept.',
      input: { fields: { id: F.id, query: F.none, data: F.obj(contracts.itemWrite.fields) } },
      run: (input, ctx) => runMoved(core.updateItem, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.setSectionTree': {
      permission: 'items.update',
      summary: 'Set how a part’s sheet sections nest, and reconcile its links.',
      input: { fields: { id: F.id, query: F.none, data: F.obj({ tree: F.none }) } },
      run: (input, ctx) => runMoved(core.setSectionTree, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.archive': {
      permission: 'items.update',
      summary: 'Archive or restore an item.',
      input: { fields: { id: F.id, query: F.none, data: F.obj({ archived: F.flag }) } },
      run: (input, ctx) => runMoved(core.archiveItem, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.delete': {
      permission: 'items.delete',
      summary: 'Move an item to the trash.',
      input: { fields: { id: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(core.deleteItem, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.moveToGroup': {
      permission: 'items.update',
      summary: 'File an item under another group.',
      input: { fields: { id: F.id, query: F.none, data: F.obj({ groupId: F.int }) } },
      run: (input, ctx) => runMoved(core.moveItemToGroup, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.groups.create': {
      permission: 'items.create',
      summary: 'Create a group.',
      input: { fields: { query: F.none, data: F.obj({ ...contracts.groupWrite.fields, itemFormSections: F.none }) } },
      run: (input, ctx) => runMoved(core.createGroup, ctx, { query: input.query || {}, body: input.data }),
    },

    'items.groups.addItems': {
      permission: 'items.create',
      summary: 'File items or variants into a group.',
      input: { fields: { groupId: F.id, query: F.none, data: F.obj({ itemIds: F.list(F.int) }) } },
      run: (input, ctx) => runMoved(core.addItemsToGroup, ctx, { params: { groupId: input.groupId }, query: input.query || {}, body: input.data }),
    },

    'items.groups.items': {
      permission: 'items.read',
      summary: 'The items in a group.',
      input: { fields: { groupId: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(core.groupItems, ctx, { params: { groupId: input.groupId }, query: input.query || {}, body: input.data }),
    },

    'items.groups.update': {
      permission: 'items.update',
      summary: 'Change a group.',
      input: { fields: { id: F.id, query: F.none, data: F.obj({ ...contracts.groupWrite.fields, itemFormSections: F.none }) } },
      run: (input, ctx) => runMoved(core.updateGroup, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.groups.archive': {
      permission: 'items.update',
      summary: 'Archive a group.',
      input: { fields: { id: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(core.archiveGroup, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.groups.unarchive': {
      permission: 'items.update',
      summary: 'Restore a group.',
      input: { fields: { id: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(core.unarchiveGroup, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.groups.delete': {
      permission: 'items.delete',
      summary: 'Move a group to the trash.',
      input: { fields: { id: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(core.deleteGroup, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.groups.schemaImpact': {
      permission: 'items.read',
      summary: 'Which items a change to a group’s properties would leave without a value.',
      input: { fields: { id: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(core.groupSchemaImpact, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.groups.overview': {
      permission: 'items.read',
      summary: 'A group at a glance: its items, sets and stock.',
      input: { fields: { id: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(core.groupOverview, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.groups.effectiveSchema': {
      permission: 'items.read',
      summary: 'The properties a group’s items carry, inherited ones included.',
      input: { fields: { id: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(core.groupEffectiveSchema, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.masterData.list': {
      permission: 'items.read',
      summary: 'Every Master Data record for an item, one per pipeline.',
      input: { fields: { id: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(masterData.masterDataFor, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.masterData.resolve': {
      permission: 'items.read',
      summary: 'The Master Data that applies to an item on a pipeline, and where each value came from.',
      input: { fields: { id: F.id, query: F.obj({ pipelineId: F.text, adopt: F.text }), data: F.none } },
      run: (input, ctx) => runMoved(masterData.resolveMasterData, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.masterData.save': {
      permission: 'items.update',
      summary: 'Save an item’s Master Data for a pipeline.',
      input: { fields: { id: F.id, pipelineId: F.key, query: F.none, data: F.obj({ baseline: F.none }) } },
      run: (input, ctx) => runMoved(masterData.saveMasterData, ctx, { params: { id: input.id, pipelineId: input.pipelineId }, query: input.query || {}, body: input.data }),
    },

    'items.masterData.delete': {
      permission: 'items.delete',
      summary: 'Remove an item’s Master Data for a pipeline.',
      input: { fields: { id: F.id, pipelineId: F.key, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(masterData.deleteMasterData, ctx, { params: { id: input.id, pipelineId: input.pipelineId }, query: input.query || {}, body: input.data }),
    },

    'items.masterData.forPipeline': {
      access: 'signedIn',
      summary: 'Every item’s Master Data on one pipeline.',
      input: { fields: { id: F.key, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(masterData.pipelineMasterData, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.materialTypes.list': {
      access: 'signedIn',
      summary: 'The material types, each with its density.',
      input: { fields: { query: F.obj({ includeArchived: F.text }), data: F.none } },
      run: (input, ctx) => runMoved(materialTypes.listMaterialTypes, ctx, { query: input.query || {}, body: input.data }),
    },

    'items.materialTypes.create': {
      access: OLD_WRITE_GATE,
      summary: 'Add a material type.',
      input: { fields: { query: F.none, data: F.obj({ name: F.text, densityGCm3: F.num, category: F.text, notes: F.text }) } },
      run: (input, ctx) => runMoved(materialTypes.createMaterialType, ctx, { query: input.query || {}, body: input.data }),
    },

    'items.materialTypes.update': {
      access: OLD_WRITE_GATE,
      summary: 'Change a material type.',
      input: { fields: { id: F.id, query: F.none, data: F.obj({ name: F.text, densityGCm3: F.num, category: F.text, notes: F.text, isArchived: F.flag }) } },
      run: (input, ctx) => runMoved(materialTypes.updateMaterialType, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.materialTypes.delete': {
      access: OLD_WRITE_GATE,
      summary: 'Remove a material type.',
      input: { fields: { id: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(materialTypes.deleteMaterialType, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.sheetProperties.list': {
      permission: 'items.read',
      summary: 'The item sheet’s property columns.',
      input: { fields: { query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(sheetProperties.listSheetProperties, ctx, { query: input.query || {}, body: input.data }),
    },

    'items.sheetProperties.create': {
      permission: 'items.create',
      summary: 'Add a property column.',
      input: { fields: { query: F.none, data: F.obj({ name: F.text, kind: F.text, options: F.list(F.text) }) } },
      run: (input, ctx) => runMoved(sheetProperties.createSheetProperty, ctx, { query: input.query || {}, body: input.data }),
    },

    'items.sheetProperties.update': {
      permission: 'items.update',
      summary: 'Change a property column.',
      input: { fields: { id: F.id, query: F.none, data: F.obj({ displayName: F.text, options: F.list(F.text) }) } },
      run: (input, ctx) => runMoved(sheetProperties.updateSheetProperty, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.sheetProperties.addOption': {
      permission: 'items.create',
      summary: 'Add a value to a property column’s list.',
      input: { fields: { id: F.id, query: F.none, data: F.obj({ label: F.text }) } },
      run: (input, ctx) => runMoved(sheetProperties.addSheetPropertyOption, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.sheetProperties.removeOption': {
      permission: 'items.delete',
      summary: 'Remove a value no saved part carries.',
      input: { fields: { id: F.id, query: F.obj({ label: F.text }), data: F.none } },
      run: (input, ctx) => runMoved(sheetProperties.removeSheetPropertyOption, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.rivets.list': {
      permission: 'items.read',
      summary: 'Every rivet, with its spec and vendor prices.',
      input: { fields: { query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(rivets.listRivets, ctx, { query: input.query || {}, body: input.data }),
    },

    'items.rivets.get': {
      permission: 'items.read',
      summary: 'One rivet, by its item id.',
      input: { fields: { id: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(rivets.getRivet, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.rivets.create': {
      permission: 'items.create',
      summary: 'Make a rivet from its spec; the name is built from it.',
      input: { fields: { query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(rivets.createRivet, ctx, { query: input.query || {}, body: input.data }),
    },

    'items.rivets.update': {
      permission: 'items.update',
      summary: 'Change a rivet’s spec, code or vendor prices.',
      input: { fields: { id: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(rivets.updateRivet, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.springs.list': {
      permission: 'items.read',
      summary: 'Every spring, with its spec and vendor prices.',
      input: { fields: { query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(springs.listSprings, ctx, { query: input.query || {}, body: input.data }),
    },

    'items.springs.get': {
      permission: 'items.read',
      summary: 'One spring, by its item id.',
      input: { fields: { id: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(springs.getSpring, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.springs.create': {
      permission: 'items.create',
      summary: 'Make a spring from its spec; the name is built from it.',
      input: { fields: { query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(springs.createSpring, ctx, { query: input.query || {}, body: input.data }),
    },

    'items.springs.update': {
      permission: 'items.update',
      summary: 'Change a spring’s spec, code or vendor prices.',
      input: { fields: { id: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(springs.updateSpring, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.dieRawPlans.list': {
      permission: 'items.read',
      summary: 'A part’s raw plan for each die it is made on.',
      input: { fields: { id: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(dieRawPlans.listDieRawPlans, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },

    'items.dieRawPlans.save': {
      permission: 'items.update',
      summary: 'Write the raw plan of one die a part is made on.',
      input: { fields: { id: F.id, dieId: F.id, query: F.none, data: F.obj({ baseline: F.none }) } },
      run: (input, ctx) => runMoved(dieRawPlans.saveDieRawPlan, ctx, { params: { id: input.id, dieId: input.dieId }, query: input.query || {}, body: input.data }),
    },

    'items.sheetProperties.delete': {
      permission: 'items.delete',
      summary: 'Remove a property column.',
      input: { fields: { id: F.id, query: F.none, data: F.none } },
      run: (input, ctx) => runMoved(sheetProperties.deleteSheetProperty, ctx, { params: { id: input.id }, query: input.query || {}, body: input.data }),
    },
  };
}

function internalOperations({ all, get, run }) {
  return {
    'items.groups.name': {
      internal: true,
      summary: 'A group’s name, or nothing when there is no such group.',
      input: { fields: { id: { type: 'integer', required: true, gt: 0 } } },
      output: { fields: { name: { type: 'string', nullable: true } } },
      run: async (input) => {
        const group = await get('SELECT name FROM groups WHERE id = ?', [Number(input.id)]);
        return { ok: true, name: group?.name ?? null };
      },
    },

    'items.groups.row': {
      internal: true,
      summary: 'A group’s row as stored, or nothing.',
      input: { fields: { id: { type: 'any', required: true } } },
      output: { fields: { row: { type: 'object', nullable: true } } },
      run: async (input) => ({ ok: true, row: await get('SELECT * FROM groups WHERE id = ?', [input.id]) }),
    },

    'items.groups.propertyNamesInUse': {
      internal: true,
      summary: 'The names of the live variation properties on a group’s unarchived items, as rows of name.',
      input: { fields: { groupId: { type: 'any' } } },
      output: { fields: { rows: { type: 'array', required: true } } },
      run: async (input) => ({
        ok: true,
        rows: await all(
          `SELECT DISTINCT item_variation_nodes.name AS name
             FROM item_variation_nodes
             INNER JOIN items ON items.id = item_variation_nodes.item_id
            WHERE items.group_id = ?
              AND items.is_archived = 0
              AND item_variation_nodes.kind = 'property'
              AND item_variation_nodes.is_archived = 0`,
          [Number(input.groupId)],
        ),
      }),
    },

    'items.variations.node': {
      internal: true,
      summary: 'A variation node: which item it belongs to, its kind, and whether it is archived.',
      input: { fields: { id: { type: 'any', required: true } } },
      output: { fields: { node: { type: 'object', nullable: true } } },
      run: async (input) => ({
        ok: true,
        node: await get(
          'SELECT id, item_id, kind, is_archived FROM item_variation_nodes WHERE id = ?',
          [input.id],
        ),
      }),
    },

    'items.variations.codeForValue': {
      internal: true,
      summary: 'The code of a variation value under a named property of an item, with the property’s position.',
      input: {
        fields: {
          itemId: { type: 'any', required: true },
          propertyName: { type: 'any', required: true },
          valueName: { type: 'any', required: true },
        },
      },
      output: { fields: { row: { type: 'object', nullable: true } } },
      run: async (input) => ({
        ok: true,
        row: await get(
          `SELECT v.code, p.position
             FROM item_variation_nodes v
             JOIN item_variation_nodes p ON v.parent_node_id = p.id
            WHERE v.item_id = ? AND p.name = ? AND (v.name = ? OR v.display_name = ?)`,
          [input.itemId, input.propertyName, input.valueName, input.valueName],
        ),
      }),
    },

    'items.unitConversions.factor': {
      internal: true,
      summary: 'The factor that takes a quantity in this unit to the item’s primary unit, or null when the item has no such conversion.',
      input: { fields: { itemId: F.int, unitId: F.int } },
      output: { fields: { factor: { type: 'number', nullable: true } } },
      run: async (input) => {
        const row = await get(
          'SELECT factor_to_primary FROM item_unit_conversions WHERE item_id = ? AND unit_id = ? LIMIT 1',
          [input.itemId, input.unitId],
        );
        return { ok: true, factor: row ? Number(row.factor_to_primary) : null };
      },
    },

    'items.dies.forget': {
      internal: true,
      joinsCallerTransaction: true,
      summary: 'A die is being removed: no part lists it among its dies any more.',
      input: { fields: { dieId: F.int } },
      run: async (input) => {
        await run('DELETE FROM item_dies WHERE die_id = ?', [input.dieId]);
        return { ok: true };
      },
    },

    'items.machines.forget': {
      internal: true,
      joinsCallerTransaction: true,
      summary: 'A machine is being removed: no part lists it among its machines any more.',
      input: { fields: { machineId: F.int } },
      run: async (input) => {
        await run('DELETE FROM item_machines WHERE machine_id = ?', [input.machineId]);
        return { ok: true };
      },
    },

    'items.search.hits': {
      internal: true,
      summary: 'Items whose name, display name, alias or a variation label contain every token; with group name and stock rows; at most `limit`.',
      input: { fields: { tokens: F.list(F.text), limit: F.int } },
      output: { fields: { rows: { type: 'array', required: true } } },
      run: async (input) => {
        const tokens = (input.tokens || []).map(String).filter(Boolean);
        const conditions = tokens.map(() => '(i.name LIKE ? OR i.display_name LIKE ? OR i.alias LIKE ? OR v.variation_path_label LIKE ?)').join(' AND ');
        const params = tokens.flatMap((t) => { const l = `%${t}%`; return [l, l, l, l]; });
        return {
          ok: true,
          rows: await all(
            `SELECT i.id, i.name, i.display_name, i.quantity as base_quantity, g.name as category_name,
                    v.variation_leaf_node_id, v.variation_path_label, v.quantity as var_quantity,
                    i.naming_format
             FROM items i
             LEFT JOIN groups g ON i.group_id = g.id
             LEFT JOIN variation_stock v ON i.id = v.item_id
             WHERE ${conditions || '1=1'}
             LIMIT ${Number(input.limit) > 0 ? Number(input.limit) : 50}`,
            params,
          ),
        };
      },
    },

    'items.search.configurations': {
      internal: true,
      summary: 'What search needs to name the configurations these items have: their property schema, live variation nodes and stock rows.',
      input: { fields: { itemIds: F.list(F.int) } },
      output: { fields: { props: { type: 'array', required: true }, nodes: { type: 'array', required: true }, stockRows: { type: 'array', required: true } } },
      run: async (input) => {
        const itemIds = [...new Set((input.itemIds || []).map(Number).filter((id) => Number.isInteger(id) && id > 0))];
        if (!itemIds.length) return { ok: true, props: [], nodes: [], stockRows: [] };
        const qs = itemIds.map(() => '?').join(',');
        return {
          ok: true,
          props: await all(`SELECT item_id, property_key, display_name FROM item_property_schema WHERE item_id IN (${qs}) ORDER BY sort_order ASC`, itemIds),
          nodes: await all(`SELECT id, item_id, parent_node_id, name, display_name FROM item_variation_nodes WHERE item_id IN (${qs}) AND is_archived = 0 ORDER BY position ASC`, itemIds),
          stockRows: await all(`SELECT item_id, custom_variation_values_json, variation_path_node_ids_json FROM variation_stock WHERE item_id IN (${qs})`, itemIds),
        };
      },
    },

    'items.rows.get': {
      internal: true,
      summary: 'An item’s row as stored, or nothing.',
      input: { fields: { id: { type: 'any', required: true } } },
      output: { fields: { row: { type: 'object', nullable: true } } },
      run: async (input) => ({ ok: true, row: await get('SELECT * FROM items WHERE id = ?', [input.id]) }),
    },

    'items.rows.forCatalogue': {
      internal: true,
      summary: 'The unarchived items among these ids, as a catalogue shows them, by display name.',
      input: { fields: { ids: { type: 'array', required: true, items: { type: 'integer' } } } },
      output: { fields: { rows: { type: 'array', required: true, items: { type: 'object' } } } },
      run: async (input) => {
        const ids = (input.ids || []).map(Number).filter((id) => Number.isInteger(id));
        if (!ids.length) return { ok: true, rows: [] };
        const rows = await all(
          `SELECT id, name, display_name, alias, quantity, naming_format
             FROM items
            WHERE is_archived = 0 AND id IN (${ids.map(() => '?').join(', ')})
            ORDER BY display_name ASC`,
          ids,
        );
        return { ok: true, rows };
      },
    },

    'items.units.usageCounts': {
      internal: true,
      summary: 'How many items records name each unit.',
      input: { fields: { unitId: { type: 'integer', gt: 0, nullable: true } } },
      output: { fields: { counts: { type: 'object', required: true } } },
      run: (input) => unitUsageCounts(all, input.unitId, ['groups', 'items', 'item_unit_conversions']),
    },
  };
};
