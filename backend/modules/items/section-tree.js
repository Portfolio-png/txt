'use strict';

// ---------------------------------------------------------------------------
// A part's section tree — how its item sheet is nested, and the links that
// nesting stands for. See migrations/057-item-section-tree.sql.
//
// Sections: group_item (the part, the fixed root), client_vendor (the client
// it was developed for), die_master (its dies), machine_master (its machines).
// A tree is { child: parent } over the three non-root sections.
//
// Nesting B under A links every record in B to every record in A, in
// entity_links with relation `part_tree:<itemId>`. Edges that touch the part
// itself add nothing — the part already owns its client, dies and machines
// through items.developed_for_*, item_dies and item_machines.
// ---------------------------------------------------------------------------

const ROOT = 'group_item';
const CHILDREN = ['client_vendor', 'die_master', 'machine_master'];
const SECTIONS = [ROOT, ...CHILDREN];

const DEFAULT_TREE = Object.freeze({
  client_vendor: ROOT,
  die_master: 'client_vendor',
  machine_master: 'die_master',
});

/// What entity_links type each section's records are.
const TYPE_OF = {
  client_vendor: 'client',
  die_master: 'die',
  machine_master: 'machine',
};

function invalid(message) {
  const error = new Error(message);
  error.statusCode = 400;
  error.code = 'section_tree_invalid';
  return error;
}

/// The tree a caller sent, checked; throws a 400 otherwise. Sections left out
/// keep their default parent, so a partial tree is a complete one.
function validateSectionTree(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw invalid('The section tree must be an object of section → parent.');
  }
  const tree = { ...DEFAULT_TREE };
  for (const [child, parent] of Object.entries(raw)) {
    if (!CHILDREN.includes(child)) throw invalid(`"${child}" is not a section that can be moved.`);
    if (!SECTIONS.includes(parent)) throw invalid(`"${parent}" is not a section.`);
    if (parent === child) throw invalid('A section cannot be nested under itself.');
    tree[child] = parent;
  }
  // Every section must reach the part without going round in a circle.
  for (const start of CHILDREN) {
    const seen = new Set([start]);
    let at = tree[start];
    while (at !== ROOT) {
      if (seen.has(at)) throw invalid('That nesting goes round in a circle.');
      seen.add(at);
      at = tree[at];
    }
  }
  return tree;
}

function parseStoredTree(json) {
  if (!json) return { ...DEFAULT_TREE };
  try {
    return validateSectionTree(JSON.parse(json));
  } catch (_) {
    // A stored tree that no longer validates falls back rather than breaking
    // every save of the part.
    return { ...DEFAULT_TREE };
  }
}

function canonical(aType, aId, bType, bId) {
  const a = { type: aType, id: String(aId) };
  const b = { type: bType, id: String(bId) };
  const flip = a.type > b.type || (a.type === b.type && a.id > b.id);
  return flip ? [b, a] : [a, b];
}

/// Makes entity_links say exactly what the part's tree implies — no more, no
/// less — touching only this part's own `part_tree:<id>` links.
///
/// A section with no records (an in-house part has no client) is passed
/// through: its children count as nested under its parent, so "Die under an
/// absent client" is simply the part's dies and links nothing.
async function reconcileSectionLinks({ get, all, run }, itemId) {
  const item = await get(
    'SELECT id, developed_for_client_id, section_tree_json FROM items WHERE id = ?',
    [itemId],
  );
  if (!item) return { added: 0, removed: 0 };
  const tree = parseStoredTree(item.section_tree_json);

  const records = {
    client_vendor: item.developed_for_client_id ? [String(item.developed_for_client_id)] : [],
    die_master: (await all('SELECT die_id FROM item_dies WHERE item_id = ?', [itemId]))
      .map((r) => String(r.die_id)),
    machine_master: (await all('SELECT machine_id FROM item_machines WHERE item_id = ?', [itemId]))
      .map((r) => String(r.machine_id)),
  };

  // The nearest ancestor that has records, skipping empty sections.
  const effectiveParent = (section) => {
    let at = tree[section];
    while (at !== ROOT && records[at].length === 0) at = tree[at];
    return at;
  };

  const relation = `part_tree:${itemId}`;
  const desired = new Map();
  for (const child of CHILDREN) {
    const parent = effectiveParent(child);
    if (parent === ROOT) continue;
    for (const p of records[parent]) {
      for (const c of records[child]) {
        const [left, right] = canonical(TYPE_OF[parent], p, TYPE_OF[child], c);
        desired.set(`${left.type}|${left.id}|${right.type}|${right.id}`, [left, right]);
      }
    }
  }

  const existing = await all(
    'SELECT id, left_type, left_id, right_type, right_id FROM entity_links WHERE relation = ?',
    [relation],
  );
  let removed = 0;
  for (const row of existing) {
    const key = `${row.left_type}|${row.left_id}|${row.right_type}|${row.right_id}`;
    if (desired.has(key)) {
      desired.delete(key);
    } else {
      await run('DELETE FROM entity_links WHERE id = ?', [row.id]);
      removed += 1;
    }
  }
  const now = new Date().toISOString();
  let added = 0;
  for (const [left, right] of desired.values()) {
    const result = await run(
      `INSERT OR IGNORE INTO entity_links
         (left_type, left_id, right_type, right_id, relation, metadata, created_at, created_by)
       VALUES (?, ?, ?, ?, ?, ?, ?, NULL)`,
      [left.type, left.id, right.type, right.id, relation,
        JSON.stringify({ partId: Number(itemId), source: 'item_sheet_tree' }), now],
    );
    added += result?.changes || 0;
  }
  return { added, removed };
}

module.exports = {
  ROOT,
  CHILDREN,
  DEFAULT_TREE,
  validateSectionTree,
  parseStoredTree,
  reconcileSectionLinks,
};
