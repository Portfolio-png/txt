'use strict';

// ---------------------------------------------------------------------------
// Group overview — everything a group is, in one read.
//
// Clicking a group used to open the editor, which answers "how do I change
// this" when the question was "what IS this". A group is not just a name and a
// parent: it decides what properties its items carry, it may sit in a lineage
// that decides more of them, and it holds items whose shape says more about the
// group than any of its own fields do.
//
// Where the items come from depends on what kind of group it is, and that is
// the one distinction this file exists to get right:
//
//   combination   a curated list, from group_item_memberships. Items live in
//                 their own groups; this one gathers them deliberately.
//   otherwise     everything filed under it, from items.group_id.
//
// Reading a combination group's items from items.group_id would return nothing
// and make a populated group look empty.
// ---------------------------------------------------------------------------

/// Items filed directly under a hierarchical or component group.
const OWNED_ITEMS_SQL = `
  SELECT
    items.id, items.name, items.display_name, items.photo_url, items.quantity,
    items.base_item_id, items.unit_id, items.default_pipeline_id,
    items.pen_paper_baseline_json,
    units.name AS unit_name,
    COALESCE(ordered.lines, 0) AS order_count,
    COALESCE(ordered.qty, 0) AS order_quantity
  FROM items
  LEFT JOIN units ON units.id = items.unit_id
  LEFT JOIN (
    SELECT item_id, COUNT(*) AS lines, COALESCE(SUM(quantity), 0) AS qty
    FROM order_items WHERE item_id IS NOT NULL GROUP BY item_id
  ) AS ordered ON ordered.item_id = items.id
  WHERE items.group_id = ? AND items.is_archived = 0
  ORDER BY COALESCE(ordered.lines, 0) DESC, items.created_at DESC, items.id DESC
`;

/// Items gathered into a combination group by hand, in the order they were put
/// there — the sequence is the curator's, not ours to re-sort.
const CURATED_ITEMS_SQL = `
  SELECT
    items.id, items.name, items.display_name, items.photo_url, items.quantity,
    items.base_item_id, items.unit_id, items.default_pipeline_id,
    items.pen_paper_baseline_json,
    units.name AS unit_name,
    COALESCE(ordered.lines, 0) AS order_count,
    COALESCE(ordered.qty, 0) AS order_quantity
  FROM group_item_memberships
  JOIN items ON items.id = group_item_memberships.item_id
  LEFT JOIN units ON units.id = items.unit_id
  LEFT JOIN (
    SELECT item_id, COUNT(*) AS lines, COALESCE(SUM(quantity), 0) AS qty
    FROM order_items WHERE item_id IS NOT NULL GROUP BY item_id
  ) AS ordered ON ordered.item_id = items.id
  WHERE group_item_memberships.group_id = ? AND items.is_archived = 0
  ORDER BY group_item_memberships.sort_order ASC, items.id ASC
`;

const CHILDREN_SQL = `
  SELECT
    child.id, child.name, child.group_structure,
    (SELECT COUNT(*) FROM items
      WHERE items.group_id = child.id AND items.is_archived = 0) AS item_count
  FROM groups AS child
  WHERE child.parent_group_id = ? AND child.is_archived = 0
  ORDER BY child.name COLLATE NOCASE
`;

function itemToDto(row) {
  const name = String(row.display_name || row.name || '').trim();
  return {
    itemId: row.id,
    name,
    photoUrl: row.photo_url || '',
    unitName: row.unit_name || '',
    quantity: Number(row.quantity || 0),
    orderCount: Number(row.order_count || 0),
    orderQuantity: Number(row.order_quantity || 0),
    // A variant of another item rather than an item in its own right.
    isVariant: Boolean(row.base_item_id),
    // Which item it is a variant OF. `isVariant` alone says a row is a variant
    // but not whose, and a list that nests them needs the link, not the flag.
    baseItemId: row.base_item_id || null,
    hasPipeline: Boolean(row.default_pipeline_id),
    // A sheet plan / measured baseline has been recorded against it.
    hasBaseline: Boolean(
      row.pen_paper_baseline_json && row.pen_paper_baseline_json !== 'null'
    ),
  };
}

/// What the items say about the group, which its own columns cannot.
///
/// Every figure here is counted from the item rows actually returned, so the
/// summary can never disagree with the list under it.
function summarise(items) {
  const units = new Set();
  let ordered = 0;
  let variants = 0;
  let withPhoto = 0;
  let withPipeline = 0;
  let withBaseline = 0;
  let orderLines = 0;
  for (const item of items) {
    if (item.unitName) units.add(item.unitName);
    if (item.orderCount > 0) ordered += 1;
    orderLines += item.orderCount;
    if (item.isVariant) variants += 1;
    if (item.photoUrl) withPhoto += 1;
    if (item.hasPipeline) withPipeline += 1;
    if (item.hasBaseline) withBaseline += 1;
  }
  return {
    itemCount: items.length,
    orderedItemCount: ordered,
    orderLineCount: orderLines,
    variantCount: variants,
    withPhotoCount: withPhoto,
    withPipelineCount: withPipeline,
    withBaselineCount: withBaseline,
    units: [...units].sort(),
  };
}

/// The property schema, flattened to what a reader needs: what the property is
/// and which group in the lineage put it there.
function schemaToDto(schema) {
  if (!schema) return { properties: [], lineage: [] };
  const lineage = (schema.lineageGroupIds || []).map((id, index) => ({
    groupId: Number(id),
    name: (schema.lineageGroupNames || [])[index] || '',
  }));
  const properties = (schema.propertyDrafts || []).map((draft) => ({
    propertyKey: draft.propertyKey || '',
    displayName: draft.displayName || draft.propertyKey || '',
    inputType: draft.inputType || 'text',
    mandatory: Boolean(draft.mandatory),
    unitSymbol: draft.unitSymbol || '',
    sourceGroupId: Number(draft.sourceGroupId || 0),
    sourceGroupName: draft.sourceGroupName || '',
  }));
  return { properties, lineage };
}

async function buildGroupOverview({ all, group, schema }) {
  const structure = group.group_structure || 'hierarchical';
  const isCombination = structure === 'combination';
  const rows = await all(
    isCombination ? CURATED_ITEMS_SQL : OWNED_ITEMS_SQL,
    [group.id]
  );
  const items = rows.map(itemToDto);
  const children = (await all(CHILDREN_SQL, [group.id])).map((row) => ({
    groupId: row.id,
    name: row.name || '',
    structure: row.group_structure || 'hierarchical',
    itemCount: Number(row.item_count || 0),
  }));
  return {
    items,
    children,
    summary: summarise(items),
    // Said explicitly so the client never has to re-derive it from the
    // structure string to know why the item list looks the way it does.
    itemSource: isCombination ? 'curated' : 'owned',
    ...schemaToDto(schema),
  };
}

module.exports = {
  buildGroupOverview,
  summarise,
  schemaToDto,
  itemToDto,
  OWNED_ITEMS_SQL,
  CURATED_ITEMS_SQL,
};
