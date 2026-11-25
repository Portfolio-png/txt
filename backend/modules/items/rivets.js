'use strict';

const {
  PRICE_BASES,
  badRequest,
  parseMillimetres,
  parsePrice,
  formatPrice,
  lengthDto,
  createRawFormWork,
  registerRawFormRoutes,
} = require('./raw-forms');

// ---------------------------------------------------------------------------
// Rivets — the first raw-material form (Docs/architecture/13-raw-material-forms.md).
//
// A rivet is an ordinary item filed under the default Rivets group
// (system_key raw_materials.rivets), so stock, challans, BOM lines and orders
// treat it like any other item. What makes it a rivet is its spec, one row in
// raw_material_specs, and its name is BUILT from that spec here — never typed:
//
//   Bimetal Rivet 3.5 X 1.3 / 2.0 X 2.0 Flat (0.25)
//   {type}  Rivet {Head OD} X {Head Dia} / {Shank Dia} X {Shank Length} {Head} ({Silver Layer})
//
// The same spec twice is the same rivet: refused with 409 and the one that
// exists. Vendors quote a price for a rivet (item_vendor_prices), per piece,
// per 100, per 1000 or per kg.
//
//   GET  /api/raw-materials/rivets          all rivets, with their vendors
//   GET  /api/raw-materials/rivets/:id      one (id = the item's id)
//   POST /api/raw-materials/rivets          make one
//   PUT  /api/raw-materials/rivets/:id      change its spec, code or vendors
//
// Its own path segment, gated as `items` by the central CRUD map (server.js)
// and declared in kernel/registry.js. Under /api/items/ it would be swallowed
// by /api/items/:id.
//
// Numbers: lengths are integer nanometres (the units contract's base for a
// length) with the text as typed kept beside them, so 2.0 shows as 2.0 again.
// Prices are integer micro-rupees, so ₹0.035 a piece is exact. No floats.
// ---------------------------------------------------------------------------

const FORM_KEY = 'raw_materials.rivets';

const HEAD_TYPES = { F: 'Flat', R: 'Round' };

/// The three kinds of rivet the shop uses (owner, 2026-11-25: "that's all").
/// Matched ignoring case; "Aluminum" is taken as Aluminium. Only a bimetal
/// rivet has a silver layer — it is the silver on the copper — so there it is
/// required, and on the other two it must be blank.
const RIVET_TYPES = ['Bimetal', 'Copper', 'Aluminium'];
const RIVET_TYPE_ALIASES = { aluminum: 'Aluminium' };
const hasSilverLayer = (rivetType) => rivetType === 'Bimetal';

/// The dimensions, in the order the name prints them. Silver Layer is only
/// for a bimetal rivet (see RIVET_TYPES); without one it is left out of the name.
const DIMENSIONS = [
  { key: 'headOd', label: 'Head OD', required: true },
  { key: 'headDia', label: 'Head Diameter', required: true },
  { key: 'shankDia', label: 'Shank Diameter', required: true },
  { key: 'shankLength', label: 'Shank Length', required: true },
  { key: 'silverLayer', label: 'Silver Layer', required: false },
];

function cleanSpec(body) {
  const typed = String(body.rivetType ?? '').trim().replace(/\s+/g, ' ');
  if (!typed) throw badRequest('Rivet Type is needed.', 'missing_type');
  const rivetType =
    RIVET_TYPES.find((t) => t.toLowerCase() === typed.toLowerCase()) ||
    RIVET_TYPE_ALIASES[typed.toLowerCase()];
  if (!rivetType) {
    throw badRequest(`Rivet Type is ${RIVET_TYPES.join(', ')}.`, 'bad_type');
  }
  const headType = String(body.headType ?? '').trim().toUpperCase();
  if (!HEAD_TYPES[headType]) throw badRequest('Head Type is F (flat) or R (round).', 'bad_head_type');
  const spec = { rivetType, headType };
  for (const dim of DIMENSIONS) {
    if (dim.key === 'silverLayer') continue;
    spec[dim.key] = parseMillimetres(body[dim.key], dim.label, dim.required);
  }
  if (hasSilverLayer(rivetType)) {
    spec.silverLayer = parseMillimetres(body.silverLayer, 'Silver Layer', true);
  } else {
    if (String(body.silverLayer ?? '').trim()) {
      throw badRequest(`A ${rivetType.toLowerCase()} rivet has no silver layer; leave it blank.`, 'no_silver_layer');
    }
    spec.silverLayer = null;
  }
  return spec;
}

/// The rivet's name, from its spec. The one place it is built.
function rivetName(spec) {
  const d = (key) => spec[key]?.text;
  const base = `${spec.rivetType} Rivet ${d('headOd')} X ${d('headDia')} / ${d('shankDia')} X ${d('shankLength')} ${HEAD_TYPES[spec.headType]}`;
  return spec.silverLayer ? `${base} (${d('silverLayer')})` : base;
}

/// Two rivets with this key are the same rivet. Built from the nanometres,
/// so "2" and "2.0" are one size.
function specKey(spec) {
  return [
    spec.rivetType.toLowerCase(),
    spec.headType,
    ...DIMENSIONS.map((dim) => (spec[dim.key] ? spec[dim.key].nm : '')),
  ].join('|');
}

/// The rivet form, as the raw-form engine (raw-forms.js) takes it.
const RIVET_FORM = {
  key: FORM_KEY,
  noun: 'rivet',
  plural: 'rivets',
  group: 'Rivets',
  clean: cleanSpec,
  name: rivetName,
  specKey,
  fields: (values) => ({
    rivetType: values.rivetType || '',
    headType: values.headType || '',
    headTypeLabel: HEAD_TYPES[values.headType] || '',
    ...Object.fromEntries(DIMENSIONS.map((d) => [d.key, lengthDto(values[d.key])])),
  }),
};

/// The handlers, under the names operations.js asks for.
function createRivetWork(deps) {
  const work = createRawFormWork(deps, RIVET_FORM);
  return {
    listRivets: work.list,
    getRivet: work.get,
    createRivet: work.create,
    updateRivet: work.update,
  };
}

function registerRivetRoutes(ctx) {
  registerRawFormRoutes(ctx, 'rivets');
}

module.exports = {
  FORM_KEY,
  HEAD_TYPES,
  RIVET_TYPES,
  DIMENSIONS,
  PRICE_BASES,
  RIVET_FORM,
  createRivetWork,
  registerRivetRoutes,
  rivetName,
  specKey,
  parseMillimetres,
  parsePrice,
  formatPrice,
};
