const fs = require('fs');
const file = 'backend/server.js';
let content = fs.readFileSync(file, 'utf-8');

const replacements = [
  {
    search: `    for (const recordId of chunk) {
      await logChange(tableName, recordId, 'DELETE');
    }
  }
}`,
    replace: `    for (const recordId of chunk) {
      await logChange(tableName, recordId, 'DELETE');
    }
  }
}

async function deleteEntityCascade(type, id, req) {
  if (type === 'item') {
    const nodeIds = (await all('SELECT id FROM item_variation_nodes WHERE item_id = ?', [id])).map(r => r.id);
    await trashAndDeleteMany('item_variation_nodes', nodeIds, req);
    const convIds = (await all('SELECT id FROM item_unit_conversions WHERE item_id = ?', [id])).map(r => r.id);
    await trashAndDeleteMany('item_unit_conversions', convIds, req);
    const varIds = (await all('SELECT id FROM item_variations WHERE item_id = ?', [id])).map(r => r.id);
    await trashAndDeleteMany('item_variations', varIds, req);
    const assetIds = (await all("SELECT id FROM uploaded_assets WHERE entity_type='item' AND entity_id=?", [id])).map(r => r.id);
    await trashAndDeleteMany('uploaded_assets', assetIds, req);
    await trashAndDelete('items', id, req);
    
    const io = getIo();
    if (io) io.emit('item_deleted', { id });
  } else if (type === 'group') {
    await run('DELETE FROM group_item_memberships WHERE group_id = ?', [id]);
    await run('DELETE FROM item_property_schema WHERE group_id = ?', [id]);
    await trashAndDelete('groups', id, req);
  }
}

async function lookupByName(name) {
  if (!name) return null;
  const match = await get(
    'SELECT id FROM items WHERE LOWER(name) = ? OR LOWER(alias) = ? OR LOWER(display_name) = ? LIMIT 1',
    [name.toLowerCase(), name.toLowerCase(), name.toLowerCase()]
  );
  if (match) {
    const item = await getItemRowById(match.id);
    const leaf = await get("SELECT id, name, display_name FROM item_variation_nodes WHERE item_id = ? AND kind = 'leaf' LIMIT 1", [match.id]);
    return {
      itemId: match.id,
      variationLeafNodeId: leaf ? leaf.id : 0,
      variationPathLabel: leaf ? (leaf.display_name || leaf.name || '') : ''
    };
  }
  return null;
}`
  },
  {
    search: `  bomLines: (itemId) => all('SELECT * FROM item_bom_lines WHERE item_id = ?', [Number(itemId || 0)]),
});`,
    replace: `  bomLines: (itemId) => all('SELECT * FROM item_bom_lines WHERE item_id = ?', [Number(itemId || 0)]),
  lookupByName,
  deleteEntity: deleteEntityCascade,
  ensureReconcilePrimary: ensureReconcilePrimaryGroup,
  ensureReconcileSub: ensureReconcileSubGroup,
  ensureForReconcile: ensureReconcileItem,
});`
  },
  {
    search: `  createAssetUploadIntent,
  completeAssetUpload,
  listAssetsForEntity,
  getIo: () => io,
});`,
    replace: `  createAssetUploadIntent,
  completeAssetUpload,
  listAssetsForEntity,
  itemsPorts,
  getIo: () => io,
});`
  },
  {
    search: `    } else if (reqRow.entity_type === 'item') {
      await run('DELETE FROM items WHERE id = ?', [reqRow.entity_id]);
    } else if (reqRow.entity_type === 'asset') {
      await deleteAsset(reqRow.entity_id);
    } else if (reqRow.entity_type === 'group') {
      await run('DELETE FROM groups WHERE id = ?', [reqRow.entity_id]);
    } else if (reqRow.entity_type === 'vendor') {`,
    replace: `    } else if (reqRow.entity_type === 'item') {
      await itemsPorts.delete('item', reqRow.entity_id, req);
    } else if (reqRow.entity_type === 'asset') {
      await deleteAsset(reqRow.entity_id);
    } else if (reqRow.entity_type === 'group') {
      await itemsPorts.delete('group', reqRow.entity_id, req);
    } else if (reqRow.entity_type === 'vendor') {`
  },
  {
    search: `        let itemId = 0;
        const outName = targetNode.outputs && targetNode.outputs[0];
        if (outName) {
           const matched = await get('SELECT id FROM items WHERE LOWER(name) = ? OR LOWER(alias) = ?', [outName.toLowerCase(), outName.toLowerCase()]);
           if (matched) itemId = matched.id;
        }`,
    replace: `        let itemId = 0;
        const outName = targetNode.outputs && targetNode.outputs[0];
        if (outName) {
           const match = await itemsPorts.lookupByName(outName);
           if (match) itemId = match.itemId;
        }`
  },
  {
    search: `        const lastNode = template.nodes.find((n) => !n.isIntermediate) || template.nodes[template.nodes.length - 1];
        const finalOutput = lastNode && lastNode.outputs && lastNode.outputs[0];
        if (finalOutput) {
          const matchedItem = await get(
            'SELECT * FROM items WHERE LOWER(name) = ? OR LOWER(display_name) = ? OR LOWER(alias) = ?',
            [finalOutput.toLowerCase(), finalOutput.toLowerCase(), finalOutput.toLowerCase()]
          );
          if (matchedItem) {
            itemId = matchedItem.id;
            const variationRow = await get(
              "SELECT * FROM item_variation_nodes WHERE item_id = ? AND kind = 'leaf' LIMIT 1",
              [itemId]
            );
            if (variationRow) {
              variationLeafNodeId = variationRow.id;
              variationPathLabel = variationRow.display_name || variationRow.name || '';
            }
          }
        }

        if (!itemId) {
          const fallbackItem = await get('SELECT * FROM items LIMIT 1');
          if (fallbackItem) {
            itemId = fallbackItem.id;
            const variationRow = await get(
              "SELECT * FROM item_variation_nodes WHERE item_id = ? AND kind = 'leaf' LIMIT 1",
              [itemId]
            );
            if (variationRow) {
              variationLeafNodeId = variationRow.id;
              variationPathLabel = variationRow.display_name || variationRow.name || '';
            }
          }
        }`,
    replace: `        const lastNode = template.nodes.find((n) => !n.isIntermediate) || template.nodes[template.nodes.length - 1];
        const finalOutput = lastNode && lastNode.outputs && lastNode.outputs[0];
        if (finalOutput) {
          const match = await itemsPorts.lookupByName(finalOutput);
          if (match) {
            itemId = match.itemId;
            variationLeafNodeId = match.variationLeafNodeId;
            variationPathLabel = match.variationPathLabel;
          }
        }`
  },
  {
    search: `          const matched = await get('SELECT id FROM items WHERE LOWER(name) = ? OR LOWER(alias) = ?', [inName.toLowerCase(), inName.toLowerCase()]);
          if (matched) {
            itemId = matched.id;
            const vnode = await get("SELECT * FROM item_variation_nodes WHERE item_id = ? AND kind = 'leaf' LIMIT 1", [itemId]);
            if (vnode) {
              variationLeafNodeId = vnode.id;
              variationPathLabel = vnode.display_name || vnode.name || '';
            }
          }`,
    replace: `          const match = await itemsPorts.lookupByName(inName);
          if (match) {
            itemId = match.itemId;
            variationLeafNodeId = match.variationLeafNodeId;
            variationPathLabel = match.variationPathLabel;
          }`
  },
  {
    search: `async function ensureReconcilePrimaryGroup() {
  let primary = await get(
    \`SELECT id, unit_id FROM groups WHERE lower(name) = 'primary group' AND parent_group_id IS NULL ORDER BY id LIMIT 1\`,
  );
  if (primary) return primary;
  const fallbackUnit = await get('SELECT id FROM units ORDER BY id LIMIT 1');
  const now = nowIso();
  const res = await run(
    \`INSERT INTO groups (name, group_type, group_structure, description, parent_group_id, unit_id, is_archived, created_at, updated_at)
     VALUES ('Primary Group', 'item', 'hierarchical', 'Root item group', NULL, ?, 0, ?, ?)\`,
    [fallbackUnit?.id || null, now, now],
  );
  return { id: res.lastID, unit_id: fallbackUnit?.id || null };
}`,
    replace: `async function ensureReconcilePrimaryGroup() {
  let primary = await get(
    \`SELECT id, unit_id FROM groups WHERE lower(name) = 'primary group' AND parent_group_id IS NULL ORDER BY id LIMIT 1\`,
  );
  if (primary) return primary;
  const fallbackUnit = await get('SELECT id FROM units ORDER BY id LIMIT 1');
  const group = await saveGroup({
    name: 'Primary Group',
    groupType: 'item',
    groupStructure: 'hierarchical',
    description: 'Root item group',
    parentGroupId: null,
    unitId: fallbackUnit?.id || null,
  });
  return { id: group.id, unit_id: group.unit_id };
}`
  },
  {
    search: `async function ensureReconcileSubGroup(name, parentGroupId, unitId) {
  const existing = await get(
    \`SELECT id FROM groups WHERE lower(name) = lower(?) AND parent_group_id = ? AND group_type = 'item' ORDER BY id LIMIT 1\`,
    [name, parentGroupId],
  );
  if (existing) return existing.id;
  const now = nowIso();
  const res = await run(
    \`INSERT INTO groups (name, group_type, group_structure, description, parent_group_id, unit_id, is_archived, created_at, updated_at)
     VALUES (?, 'item', 'hierarchical', 'Internal-use reconciliation returns', ?, ?, 0, ?, ?)\`,
    [name, parentGroupId, unitId, now, now],
  );
  return res.lastID;
}`,
    replace: `async function ensureReconcileSubGroup(name, parentGroupId, unitId) {
  const existing = await get(
    \`SELECT id FROM groups WHERE lower(name) = lower(?) AND parent_group_id = ? AND group_type = 'item' ORDER BY id LIMIT 1\`,
    [name, parentGroupId],
  );
  if (existing) return existing.id;
  const group = await saveGroup({
    name,
    groupType: 'item',
    groupStructure: 'hierarchical',
    description: 'Internal-use reconciliation returns',
    parentGroupId,
    unitId,
  });
  return group.id;
}`
  },
  {
    search: `async function ensureReconcileItem(name, groupId, unitId) {
  const existing = await get(
    \`SELECT id FROM items WHERE lower(name) = lower(?) AND group_id = ? ORDER BY id LIMIT 1\`,
    [name, groupId],
  );
  if (existing) return existing.id;
  const now = nowIso();
  const res = await run(
    \`INSERT INTO items (name, alias, short_code, display_name, quantity, group_id, unit_id, is_archived, created_at, updated_at)
     VALUES (?, '', '', ?, 0, ?, ?, 0, ?, ?)\`,
    [name, name, groupId, unitId, now, now],
  );
  return res.lastID;
}`,
    replace: `async function ensureReconcileItem(name, groupId, unitId) {
  const existing = await get(
    \`SELECT id FROM items WHERE lower(name) = lower(?) AND group_id = ? ORDER BY id LIMIT 1\`,
    [name, groupId],
  );
  if (existing) return existing.id;
  const item = await saveItem({
    name,
    alias: name,
    displayName: name,
    groupId,
    unitId,
    quantity: 0,
  });
  return item.id;
}`
  }
];

let changed = false;
for (const {search, replace} of replacements) {
  if (content.includes(search)) {
    content = content.replace(search, replace);
    changed = true;
  } else {
    console.error('NOT FOUND:\\n', search.substring(0, 50) + '...');
  }
}

if (changed) {
  fs.writeFileSync(file, content, 'utf-8');
  console.log('Patched server.js successfully!');
}
