'use strict';

// ---------------------------------------------------------------------------
// Universal barcode codec.
//
// One code space over every entity in the system, so a scanner gun pointed at
// anything — a sheet, a challan, a machine, a person — resolves to the record
// it names without the scanner needing to know what it is looking at.
//
// **Derived, not minted.** A code is computed from (type, id) rather than
// generated and stored. Every entity already has a stable primary key, so:
//
//   * nothing has to be allocated, so nothing can be allocated twice;
//   * every row that already exists has a barcode the moment this file does —
//     all 93 orders and 100 challans, with no backfill;
//   * the code says what it points at, so the resolver dispatches on the code
//     itself rather than searching every table.
//
// This is deliberately not how `PAR-{ms}-{rand4}` works. That mints, and a
// measured probe put its collision rate at 41% of workspaces by 100 parents
// (99.3% by 300) because a child keeps only a 4-digit random. Derived codes
// cannot collide: an id is unique within its table and the prefix separates the
// tables.
//
// ## The check character
//
// Every emitted code ends in one check character. Once a single code space
// covers everything, `ORD-000093` and `ORD-000098` are both valid codes for
// different real orders — one misread digit silently resolves to the wrong
// order and nothing looks wrong. The check character turns that into a rejected
// scan.
//
// It is required on a scan and optional on input: a code typed by hand or read
// off an older label still resolves, it just does so unverified, and the
// resolver says which of the two happened.
// ---------------------------------------------------------------------------

/// Every entity that can carry a barcode, and where it lives.
///
/// `idColumn` is what the code's payload holds. Where a table already has a
/// human code — a challan number, an order number — that is used rather than
/// the row id, because it is what people already say out loud and what is
/// already printed on the paperwork.
const TYPES = Object.freeze({
  MAT: { label: 'Material', table: 'materials', idColumn: 'barcode', numeric: false },
  DC: { label: 'Delivery challan', table: 'delivery_challans', idColumn: 'challan_no', numeric: false, where: "type = 'delivery'" },
  RC: { label: 'Reception challan', table: 'delivery_challans', idColumn: 'challan_no', numeric: false, where: "type = 'reception'" },
  DCL: { label: 'Dispatch batch', table: 'delivery_challan_items', idColumn: 'id', numeric: true },
  ORD: { label: 'Order', table: 'order_headers', idColumn: 'order_no', numeric: false },
  RUN: { label: 'Production run', table: 'pipeline_runs', idColumn: 'id', numeric: false },
  MFG: { label: 'Production output', table: 'production_runs', idColumn: 'run_code', numeric: false },
  EMP: { label: 'Person', table: 'employees', idColumn: 'id', numeric: true },
  DEP: { label: 'Department', table: 'departments', idColumn: 'id', numeric: true },
  PLN: { label: 'Pipeline', table: 'pipeline_templates', idColumn: 'id', numeric: false },
  CLI: { label: 'Client', table: 'clients', idColumn: 'id', numeric: true },
  VEN: { label: 'Vendor', table: 'vendors', idColumn: 'id', numeric: true },
  MCH: { label: 'Machine', table: 'machines', idColumn: 'id', numeric: true },
  DIE: { label: 'Die', table: 'dies', idColumn: 'id', numeric: true },
  ITM: { label: 'Item', table: 'items', idColumn: 'id', numeric: true },
  GRP: { label: 'Group', table: 'groups', idColumn: 'id', numeric: true },
  MOV: { label: 'Stock movement', table: 'inventory_movements', idColumn: 'id', numeric: false },
  // Places. These two are NOT record-backed like everything above: there is no
  // `locations` table and no `shop_floors` table. A location is a free-text
  // string on `inventory_stock_positions`, and a floor is a free-text string on
  // `machines`. `place: true` says so, and the resolver matches them by
  // normalised value rather than by primary key.
  //
  // Modelled this way rather than refused because the places are real and
  // already named consistently in the data ('Cutting bay', 'Rack A1', 'MAIN') —
  // someone can print a sticker for a rack today. What is missing is a record,
  // not the thing. When locations become records, only the spec changes.
  //
  // The normalisation matters: a code strips whitespace, so 'Cutting bay'
  // travels as CUTTINGBAY and would never match a column compare.
  LOC: {
    label: 'Storage location',
    table: 'inventory_stock_positions',
    idColumn: 'location_id',
    numeric: false,
    place: true,
  },
  FLR: {
    label: 'Shop floor',
    table: 'machines',
    idColumn: 'location',
    numeric: false,
    place: true,
  },
});

/// Codes that predate this scheme and are already printed on labels or spoken
/// on the floor. The resolver falls back to these, so nothing in the factory
/// stops scanning the day this ships.
///
/// Ordered: the first match wins, so the most specific prefixes come first.
const LEGACY_SOURCES = Object.freeze([
  { type: 'MAT', table: 'materials', column: 'barcode', label: 'Material' },
  { type: 'MAT', table: 'materials', column: 'parent_barcode', label: 'Material (as parent)' },
  { type: 'MCH', table: 'machines', column: 'barcode', label: 'Machine' },
  { type: 'EMP', table: 'employees', column: 'barcode_id', label: 'Person' },
  { type: 'DIE', table: 'dies', column: 'tool_code', label: 'Die' },
  { type: 'ITM', table: 'items', column: 'short_code', label: 'Item' },
  { type: 'MFG', table: 'production_runs', column: 'run_code', label: 'Production output' },
  { type: 'DC', table: 'delivery_challans', column: 'challan_no', label: 'Challan' },
  { type: 'ORD', table: 'order_headers', column: 'order_no', label: 'Order' },
]);

const CHECK_ALPHABET = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

/// Uppercase, trimmed, inner whitespace removed.
///
/// Scanner guns and phone keyboards both introduce stray space, and a code that
/// fails to resolve because of a space someone cannot see is indistinguishable
/// from a code that does not exist.
function normalize(code) {
  return String(code == null ? '' : code)
    .replace(/\s+/g, '')
    .trim()
    .toUpperCase();
}

/// One character derived from everything before it.
///
/// Weighted so that transposing two adjacent characters changes the result —
/// an unweighted sum would not, and transposition is the commonest typing slip
/// after a single wrong digit.
function checkCharacter(payload) {
  const text = normalize(payload);
  let total = 0;
  for (let i = 0; i < text.length; i += 1) {
    total += text.charCodeAt(i) * (i + 1);
  }
  return CHECK_ALPHABET[total % CHECK_ALPHABET.length];
}

/// The barcode for an entity. Returns null when the type is unknown or the id
/// is empty — a code that names nothing is worse than no code.
function encode(type, id) {
  const upperType = normalize(type);
  if (!TYPES[upperType]) return null;
  const value = normalize(id);
  if (!value) return null;
  const payload = `${upperType}-${value}`;
  return `${payload}-${checkCharacter(payload)}`;
}

/// Reads a code back to the entity it names.
///
/// Returns `{ type, id, hasCheck, checkValid }`, or null when the string is not
/// one of ours. `checkValid` is false only when a check character was present
/// and did not match — an unverified code (no check character at all) is
/// reported by `hasCheck: false` rather than as a failure, because that is what
/// a hand-typed or legacy code looks like.
function decode(code) {
  const text = normalize(code);
  if (!text) return null;

  const parts = text.split('-');
  if (parts.length < 2) return null;

  const type = parts[0];
  if (!TYPES[type]) return null;

  // A trailing single character *may* be the check. It may equally be part of
  // an id that happens to end in one character after a dash — `DC-00042-L1`
  // does not, but `RUN-A` would. Decide by testing it.
  const last = parts[parts.length - 1];
  if (parts.length > 2 && last.length === 1) {
    const payload = parts.slice(0, -1).join('-');
    if (checkCharacter(payload) === last) {
      return {
        type,
        id: parts.slice(1, -1).join('-'),
        hasCheck: true,
        checkValid: true,
      };
    }
    // A single trailing character that is not the right check is a misread, not
    // an id — reporting it as a bad check is the whole point of having one.
    return {
      type,
      id: parts.slice(1, -1).join('-'),
      hasCheck: true,
      checkValid: false,
    };
  }

  return {
    type,
    id: parts.slice(1).join('-'),
    hasCheck: false,
    checkValid: true,
  };
}

/// Whether a string looks like one of ours at all. Used to decide between the
/// structured path and the legacy search, not as validation.
function isStructured(code) {
  return decode(code) != null;
}

module.exports = {
  TYPES,
  LEGACY_SOURCES,
  normalize,
  checkCharacter,
  encode,
  decode,
  isStructured,
};
