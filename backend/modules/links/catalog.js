'use strict';

// ---------------------------------------------------------------------------
// Links module — the catalog of what can be linked, and the rules for storing
// a link between any two of them.
//
// Adding a master to the link graph = adding one entry to LINKABLE_TYPES. It
// needs no table, no migration and no route: the generic store already holds
// the row, and the column UI reads this catalog over /api/links/schema, so a
// new master shows up in the "+ link" menu of every other one.
// ---------------------------------------------------------------------------

// One linkable master.
//
//   table/idCol  where its records live.
//   label        SQL expression for the name a human recognises it by.
//   subtitle     SQL expression for the second line (a code, a role); '' for none.
//   module       kernel registry module key — decides who may read or link it,
//                and doubles as the entity_type for per-record grants.
//   archivedCol  nullable; when set, archived records are kept out of the
//                candidate picker (but NOT out of links that already exist —
//                archiving a die must not make the link to it disappear
//                silently).
//
// Declaration order is the order columns and menus list them.
const LINKABLE_TYPES = {
  item: {
    label: 'Item',
    plural: 'Items',
    icon: 'item',
    table: 'items',
    idCol: 'id',
    labelSql: "COALESCE(NULLIF(TRIM(display_name), ''), name)",
    subtitleSql: "COALESCE(NULLIF(TRIM(short_code), ''), alias, '')",
    module: 'items',
    archivedCol: 'is_archived',
  },
  die: {
    label: 'Die',
    plural: 'Dies',
    icon: 'die',
    table: 'dies',
    idCol: 'id',
    labelSql: "COALESCE(NULLIF(TRIM(tool_code), ''), 'Die ' || id)",
    subtitleSql: "COALESCE(NULLIF(TRIM(storage_location), ''), '')",
    module: 'dies',
    archivedCol: null,
  },
  machine: {
    label: 'Machine',
    plural: 'Machines',
    icon: 'machine',
    table: 'machines',
    idCol: 'id',
    labelSql: "COALESCE(NULLIF(TRIM(name), ''), asset_id)",
    subtitleSql: "COALESCE(NULLIF(TRIM(asset_id), ''), '')",
    module: 'machines',
    archivedCol: null,
  },
  group: {
    label: 'Group',
    plural: 'Groups',
    icon: 'group',
    table: 'groups',
    idCol: 'id',
    labelSql: 'name',
    subtitleSql: "COALESCE(group_structure, '')",
    module: 'items',
    archivedCol: 'is_archived',
  },
  pipeline: {
    label: 'Pipeline',
    plural: 'Pipelines',
    icon: 'pipeline',
    table: 'pipeline_templates',
    idCol: 'id',
    labelSql: 'name',
    subtitleSql: "COALESCE(status, '')",
    module: 'pipelines',
    archivedCol: null,
  },
  material: {
    label: 'Material',
    plural: 'Materials',
    icon: 'material',
    table: 'materials',
    // Materials are keyed by barcode, not by the integer id — the whole
    // reason entity_links stores ids as TEXT.
    idCol: 'barcode',
    labelSql: "COALESCE(NULLIF(TRIM(name), ''), barcode)",
    subtitleSql: "COALESCE(NULLIF(TRIM(type), ''), '')",
    module: 'inventory',
    archivedCol: null,
  },
  unit: {
    label: 'Unit',
    plural: 'Units',
    icon: 'unit',
    table: 'units',
    idCol: 'id',
    labelSql: 'name',
    subtitleSql: "COALESCE(NULLIF(TRIM(symbol), ''), '')",
    module: 'units',
    archivedCol: 'is_archived',
  },
  client: {
    label: 'Client',
    plural: 'Clients',
    icon: 'client',
    table: 'clients',
    idCol: 'id',
    labelSql: 'name',
    subtitleSql: "COALESCE(NULLIF(TRIM(alias), ''), '')",
    module: 'clients',
    archivedCol: 'is_archived',
  },
  vendor: {
    label: 'Vendor',
    plural: 'Vendors',
    icon: 'vendor',
    table: 'vendors',
    idCol: 'id',
    labelSql: 'name',
    subtitleSql: "COALESCE(NULLIF(TRIM(alias), ''), '')",
    module: 'vendors',
    archivedCol: 'is_archived',
  },
  employee: {
    label: 'Person',
    plural: 'People',
    icon: 'employee',
    table: 'employees',
    idCol: 'id',
    labelSql: 'name',
    subtitleSql: "COALESCE(NULLIF(TRIM(role), ''), '')",
    module: 'people',
    archivedCol: 'is_archived',
  },
  department: {
    label: 'Department',
    plural: 'Departments',
    icon: 'department',
    table: 'departments',
    idCol: 'id',
    labelSql: 'name',
    subtitleSql: "''",
    module: 'people',
    archivedCol: 'is_archived',
  },
};

const TYPE_KEYS = Object.keys(LINKABLE_TYPES);

function isLinkableType(type) {
  return Object.prototype.hasOwnProperty.call(LINKABLE_TYPES, String(type));
}

function typeSpec(type) {
  return LINKABLE_TYPES[String(type)] || null;
}

// The pair, in the order entity_links stores it: sorted by type, then by id.
// `flipped` tells a caller whose (type, id) ended up on the right, which is
// what lets one stored row answer the question from either end.
//
// Ids compare as text because that is how the column is typed; '10' sorting
// before '9' is of no consequence — only that the order is deterministic, so
// the same two records always normalise to the same row.
function canonicalPair(aType, aId, bType, bId) {
  const a = { type: String(aType), id: String(aId) };
  const b = { type: String(bType), id: String(bId) };
  const flipped =
    a.type > b.type || (a.type === b.type && a.id > b.id);
  return flipped
    ? { left: b, right: a, flipped: true }
    : { left: a, right: b, flipped: false };
}

// Pairs that predate the generic store and are still owned by their own table.
//
// These are NOT mirrored into entity_links. The item DTO reads item_dies and
// item_machines and the item PUT rewrites them wholesale; a copy here would be
// a second claim on the same fact, and the first write path anyone forgot
// would split them. The links module reads and writes the legacy table for
// these two pairs instead, which also makes them answerable from the die's or
// the machine's side — the direction their own table was never read from.
//
// Keyed by the canonical type pair.
const LEGACY_PAIRS = {
  'die|item': {
    table: 'item_dies',
    columns: { die: 'die_id', item: 'item_id' },
  },
  'item|machine': {
    table: 'item_machines',
    columns: { item: 'item_id', machine: 'machine_id' },
  },
};

function legacyPairFor(leftType, rightType) {
  return LEGACY_PAIRS[`${leftType}|${rightType}`] || null;
}

module.exports = {
  LINKABLE_TYPES,
  TYPE_KEYS,
  LEGACY_PAIRS,
  isLinkableType,
  typeSpec,
  canonicalPair,
  legacyPairFor,
};
