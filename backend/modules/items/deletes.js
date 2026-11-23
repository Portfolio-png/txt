'use strict';

// Removing an item or a group with everything that hangs off it.
//
// A factory: `deps` is what server.js still owns (the database helpers and
// a few shared helpers), `api` is the items service being assembled, through
// which these reach the sibling files; both are read at call time.



function createDeletes(deps, api) {
  const inventoryPorts = deps.inventory;
  const { desk } = deps;
  const { all, markEntityAssetsDeleted, run, trashAndDelete } = deps;
  const purgeEntityLinks = (...args) => deps.purgeEntityLinks()(...args);
  const purgeEntityVariations = (...args) => deps.purgeEntityVariations()(...args);

  async function deleteItemWithCascade(id, req) {
    await run('DELETE FROM item_variation_nodes WHERE item_id = ?', [id]);
    await run('DELETE FROM item_unit_conversions WHERE item_id = ?', [id]);
    await run('DELETE FROM variation_stock WHERE item_id = ?', [id]);
    // The rows stay, marked, so the sweep can delete their stored objects.
    await markEntityAssetsDeleted('item', id);
    // Membership rows have to go by hand. trashAndDelete removes the item over
    // the dedicated delete connection, which runs with foreign_keys = OFF for its
    // whole lifetime, so the ON DELETE CASCADE declared on
    // group_item_memberships never fires and inventory_set_lines never had one.
    // Left behind, a set keeps a nameless ghost line that still counts toward its
    // total AND makes the set unsaveable, because saveInventorySet re-validates
    // every line and rejects one whose item no longer exists.
    await run('DELETE FROM group_item_memberships WHERE item_id = ?', [id]);
    await inventoryPorts.sets.removeLinesForItem(id);
    // Same reason: every one of these declares ON DELETE CASCADE on items(id),
    // and every one of them is orphaned instead.
    await run('DELETE FROM item_attachments WHERE item_id = ?', [id]);
    await run('DELETE FROM item_machines WHERE item_id = ?', [id]);
    await run('DELETE FROM item_dies WHERE item_id = ?', [id]);
    await run('DELETE FROM item_property_schema WHERE item_id = ?', [id]);
    await run('DELETE FROM item_bom_lines WHERE item_id = ?', [id]);
    // The part's sheet nesting (057) is client↔die and die↔machine links that
    // carry the part only in their relation, so the purge below — which matches
    // an item at either END — never touched them, and no reconcile ever runs
    // for this id again. Its deal ticks (056) likewise.
    await desk.ask('links.removeRelation', { relation: `part_tree:${id}` });
    await run('DELETE FROM item_deal_contacts WHERE item_id = ?', [id]);
    await run('DELETE FROM item_deal_people WHERE deal_id IN (SELECT id FROM item_deals WHERE item_id = ?)', [id]);
    await run('DELETE FROM item_deals WHERE item_id = ?', [id]);
    if (purgeEntityLinks) await purgeEntityLinks('item', id);
    if (purgeEntityVariations) await purgeEntityVariations('item', id);
    await trashAndDelete('items', id, req);
  }

  async function deleteGroupWithCascade(id, req) {
    const items = await all('SELECT id FROM items WHERE group_id = ?', [id]);
    for (const row of items) {
      await deleteItemWithCascade(row.id, req);
    }

    const subgroups = await all('SELECT id FROM groups WHERE parent_group_id = ?', [id]);
    for (const row of subgroups) {
      await deleteGroupWithCascade(row.id, req);
    }

    // The rows stay, marked, so the sweep can delete their stored objects.
    await markEntityAssetsDeleted('group', id);
    // Links the group is on either side of. Sets are the first pair a user would
    // notice this for — a set's card names its group, so a stale row would show.
    if (purgeEntityLinks) await purgeEntityLinks('group', id);
    await trashAndDelete('groups', id, req);
  }

  return { deleteItemWithCascade, deleteGroupWithCascade };
}

module.exports = { createDeletes };
