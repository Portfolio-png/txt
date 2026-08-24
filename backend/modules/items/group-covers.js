'use strict';

// ---------------------------------------------------------------------------
// Group covers — the items whose photos make up a group's card.
//
// A group is an abstraction: "Finished Goods" has no photograph of its own and
// never will. What it does have is the things inside it, so the card is made of
// them. That also makes the card carry information rather than decoration — you
// recognise a group by what comes out of it.
//
// Which items get chosen, in order:
//
//   1. the most ordered — how often the item appears on an order line
//   2. the most recently added — for a group nothing has been ordered from yet
//
// Order lines rather than production runs or stock movements: on this data they
// are the only signal with real coverage, and they are the honest reading of
// "most used" anyway. A shop's busiest item is the one customers keep asking
// for, not the one that happens to have moved between racks.
//
// One query for every group, not one per group. A card view renders every group
// at once, so an N+1 here would be felt immediately.
// ---------------------------------------------------------------------------

/// How many items a card shows. Four fills a 2x2 mosaic; beyond that each tile
/// is too small to recognise anything in.
const COVER_LIMIT = 4;

/// Rank items within each group and keep the top few.
///
/// `orderCount` is carried through to the client so a card can say *why* an
/// item is on it — "most ordered" is worth stating, and a group falling back to
/// recency should not silently look like a popularity ranking.
const COVER_SQL = `
  WITH ordered AS (
    SELECT item_id, COUNT(*) AS lines, COALESCE(SUM(quantity), 0) AS qty
    FROM order_items
    WHERE item_id IS NOT NULL
    GROUP BY item_id
  ),
  ranked AS (
    SELECT
      items.id,
      items.group_id,
      items.name,
      items.display_name,
      items.photo_url,
      COALESCE(ordered.lines, 0) AS order_count,
      COALESCE(ordered.qty, 0) AS order_quantity,
      ROW_NUMBER() OVER (
        PARTITION BY items.group_id
        ORDER BY
          COALESCE(ordered.lines, 0) DESC,
          COALESCE(ordered.qty, 0) DESC,
          items.created_at DESC,
          items.id DESC
      ) AS rank
    FROM items
    LEFT JOIN ordered ON ordered.item_id = items.id
    WHERE items.is_archived = 0 AND items.group_id IS NOT NULL
  )
  SELECT id, group_id, name, display_name, photo_url, order_count, order_quantity
  FROM ranked
  WHERE rank <= ?
  ORDER BY group_id, rank
`;

/// How many live items each group holds.
///
/// Not the group's `usage_count`, which adds child groups and linked materials
/// together with items — a fine number for "is this safe to delete", useless
/// for "how much is in here".
const COUNT_SQL = `
  SELECT group_id, COUNT(*) AS item_count
  FROM items
  WHERE is_archived = 0 AND group_id IS NOT NULL
  GROUP BY group_id
`;

async function itemCountsByGroup({ all } = {}) {
  const rows = await all(COUNT_SQL, []);
  const out = new Map();
  for (const row of rows) out.set(Number(row.group_id), Number(row.item_count));
  return out;
}

function coverToDto(row) {
  const name = String(row.display_name || row.name || '').trim();
  return {
    itemId: row.id,
    name,
    photoUrl: row.photo_url || '',
    orderCount: Number(row.order_count || 0),
    orderQuantity: Number(row.order_quantity || 0),
  };
}

/// Covers for every group, as a Map of groupId -> cover list.
async function coversByGroup({ all, limit = COVER_LIMIT } = {}) {
  const rows = await all(COVER_SQL, [limit]);
  const out = new Map();
  for (const row of rows) {
    const key = Number(row.group_id);
    if (!out.has(key)) out.set(key, []);
    out.get(key).push(coverToDto(row));
  }
  return out;
}

/// Whether this group's covers are a popularity ranking or just what is newest.
///
/// Said out loud rather than left for the reader to infer from zeroes: a card
/// that shows recent items while implying they are the most used would be
/// lying quietly, which is the worst kind.
function coverBasis(covers) {
  if (!covers || covers.length === 0) return 'empty';
  return covers.some((cover) => cover.orderCount > 0) ? 'ordered' : 'recent';
}

module.exports = {
  coversByGroup,
  itemCountsByGroup,
  coverBasis,
  COVER_LIMIT,
  COVER_SQL,
};
