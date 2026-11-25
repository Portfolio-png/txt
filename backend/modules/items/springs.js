'use strict';

const {
  badRequest,
  parseMillimetres,
  lengthDto,
  createRawFormWork,
  registerRawFormRoutes,
} = require('./raw-forms');

// ---------------------------------------------------------------------------
// Springs — the second raw-material form, on the same engine as Rivets
// (raw-forms.js; Docs/architecture/13-raw-material-forms.md).
//
// The owner, 2026-11-25:
//
//   Kind   Double Hook  an extension spring, a hook at each end (the first
//                       drawing): Coil Length, Coil Number, Coil OD, Coil ID,
//                       Wire Gauge
//          Conical      wound down from a large end to a small one (the
//                       second picture): Free Length, Total Coils, Small OD,
//                       Large OD, Wire Diameter
//          Iron Connector  no drawing yet — the Double Hook's sizes
//   Type   1.5 Cell, 5 A Steel, 15 A Steel, 16 A Iron Connector … (typed;
//          these are offered)
//   Wire Grade, and the shop's Spring Code, on every kind.
//
// What tells two springs apart is everything measured — "let [the wire
// gauge] be the differentiator". What the NAME says is the user's choice:
// each spring carries its naming format, an ordered list of blocks joined by
// a space, X, + or -, so "Double Hook Spring 114 X 6" can become
// "Double Hook Spring 114 X 6 - 22 SWG". Two springs may not share a name
// (the items list could not tell them apart): the engine refuses it and says
// to put the block that differs into the name.
// ---------------------------------------------------------------------------

const FORM_KEY = 'raw_materials.springs';

const MAX_TEXT = 40;

const KINDS = ['Double Hook', 'Conical', 'Iron Connector'];

/// The sizes of each kind: key → [label, 'mm' | 'count', required].
const EXTENSION = {
  coilLength: ['Coil Length', 'mm', true],
  coilNumber: ['Coil Number', 'count', true],
  coilOd: ['Coil OD', 'mm', false],
  coilId: ['Coil ID', 'mm', false],
};
const CONICAL = {
  freeLength: ['Free Length', 'mm', true],
  totalCoils: ['Total Coils', 'count', true],
  smallOd: ['Small OD', 'mm', false],
  largeOd: ['Large OD', 'mm', false],
  wireDiameter: ['Wire Diameter', 'mm', false],
};
const SIZES = { 'Double Hook': EXTENSION, Conical: CONICAL, 'Iron Connector': EXTENSION };

/// Text fields any kind may carry (Wire Gauge where the wire is gauged, not
/// measured: the extension kinds).
const TEXTS = {
  springType: 'Spring Type',
  wireGauge: 'Wire Gauge',
  wireGrade: 'Wire Grade',
};

/// Separators a naming format joins blocks with.
const SEPARATORS = { ' ': ' ', x: ' X ', '+': ' + ', '-': ' - ' };

/// The blocks a name can be made of, for a kind.
function blocksFor(kind) {
  return [
    'kind',
    'spring',
    'springType',
    ...Object.keys(SIZES[kind]),
    ...(kind === 'Conical' ? [] : ['wireGauge']),
    'wireGrade',
  ];
}

/// The name a spring gets until somebody arranges it otherwise:
/// "Double Hook Spring 114 X 6", "Conical Spring 20 X 5".
function defaultFormat(kind) {
  const [length, count] = kind === 'Conical' ? ['freeLength', 'totalCoils'] : ['coilLength', 'coilNumber'];
  return [
    { block: 'kind', sep: ' ' },
    { block: 'spring', sep: ' ' },
    { block: length, sep: ' ' },
    { block: count, sep: 'x' },
  ];
}

/// "double  hook" → "Double Hook".
function titleCase(text) {
  return text
    .toLowerCase()
    .split(' ')
    .map((word) => (word ? word[0].toUpperCase() + word.slice(1) : word))
    .join(' ');
}

function cleanText(raw, label) {
  const text = String(raw ?? '').trim().replace(/\s+/g, ' ');
  if (text.length > MAX_TEXT) throw badRequest(`Keep ${label} under ${MAX_TEXT} characters.`);
  return text;
}

function cleanCount(raw, label, required) {
  const text = String(raw ?? '').trim();
  if (!text) {
    if (required) throw badRequest(`${label} is needed.`, 'missing_field');
    return null;
  }
  if (!/^\d{1,4}$/.test(text) || Number(text) <= 0) {
    throw badRequest(`${label} is how many coils: a whole number, like 6.`, 'bad_coil_number');
  }
  return Number(text);
}

function cleanFormat(raw, kind) {
  if (raw === undefined || raw === null) return defaultFormat(kind);
  if (!Array.isArray(raw) || raw.length === 0) {
    throw badRequest('The name needs at least one block.', 'bad_name_format');
  }
  const allowed = new Set(blocksFor(kind));
  const seen = new Set();
  return raw.map((entry, i) => {
    const block = String(entry?.block ?? '');
    if (!allowed.has(block)) throw badRequest(`"${block}" cannot be part of a ${kind} spring's name.`, 'bad_name_format');
    if (seen.has(block)) throw badRequest(`"${block}" is in the name twice.`, 'bad_name_format');
    seen.add(block);
    const sep = i === 0 ? ' ' : String(entry?.sep ?? ' ').toLowerCase();
    if (!(sep in SEPARATORS)) throw badRequest('Blocks are joined by a space, X, + or -.', 'bad_name_format');
    return { block, sep };
  });
}

function cleanSpec(body) {
  // Before kinds, the form sent the hook as coilHook: read as the kind.
  const typedKind = cleanText(body.kind ?? body.coilHook, 'Spring Kind');
  if (!typedKind) throw badRequest('Spring Kind is needed.', 'missing_field');
  const kind = KINDS.find((k) => k.toLowerCase() === typedKind.toLowerCase());
  if (!kind) throw badRequest(`Spring Kind is ${KINDS.join(', ')}.`, 'bad_kind');

  const spec = { kind };
  for (const [key, [label, unit, required]] of Object.entries(SIZES[kind])) {
    spec[key] = unit === 'count' ? cleanCount(body[key], label, required) : parseMillimetres(body[key], label, required);
  }
  const [inner, outer, innerLabel, outerLabel] =
    kind === 'Conical' ? ['smallOd', 'largeOd', 'Small OD', 'Large OD'] : ['coilId', 'coilOd', 'Coil ID', 'Coil OD'];
  if (spec[inner] && spec[outer] && spec[inner].nm >= spec[outer].nm) {
    throw badRequest(`${innerLabel} must be smaller than ${outerLabel}.`, 'id_not_under_od');
  }
  for (const [key, label] of Object.entries(TEXTS)) {
    if (key === 'wireGauge' && kind === 'Conical') continue;
    const text = cleanText(body[key], label);
    spec[key] = key === 'springType' ? (text ? titleCase(text) : '') : text;
  }
  spec.nameFormat = cleanFormat(body.nameFormat, kind);
  return spec;
}

/// A block's words in the name, or '' when the spring has none.
function blockText(spec, block) {
  if (block === 'kind') return spec.kind;
  if (block === 'spring') return 'Spring';
  const value = spec[block];
  if (value == null) return '';
  if (typeof value === 'object') return value.text || '';
  return String(value);
}

/// The spring's name, from its spec and its naming format. The one place it
/// is built. A block with nothing in it is left out with its separator.
function springName(spec) {
  const format = spec.nameFormat || defaultFormat(spec.kind || 'Double Hook');
  let name = '';
  for (const { block, sep } of format) {
    const text = blockText(spec, block).trim();
    if (!text) continue;
    name = name ? `${name}${SEPARATORS[sep] || ' '}${text}` : text;
  }
  return name || `${spec.kind} Spring`;
}

/// Two springs with this key are the same spring: everything measured, the
/// wire included. Lengths in nanometres, so "114" and "114.0" are one.
function specKey(spec) {
  const parts = [spec.kind.toLowerCase(), (spec.springType || '').toLowerCase()];
  for (const key of Object.keys(SIZES[spec.kind])) {
    const value = spec[key];
    parts.push(value == null ? '' : typeof value === 'object' ? value.nm : value);
  }
  parts.push((spec.wireGauge || '').toLowerCase(), (spec.wireGrade || '').toLowerCase());
  return parts.join('|');
}

/// Older springs were stored before kinds: coilHook was the kind.
function kindOf(values) {
  return values.kind || values.coilHook || 'Double Hook';
}

const SPRING_FORM = {
  key: FORM_KEY,
  noun: 'spring',
  plural: 'springs',
  group: 'Springs',
  clean: cleanSpec,
  name: springName,
  specKey,
  // Two springs with one name could not be told apart in any list.
  uniqueNames: true,
  nameTakenHint: 'Add the block that differs — Wire Gauge, say — to its name.',
  fields: (values) => {
    const kind = kindOf(values);
    const sizes = SIZES[kind] || EXTENSION;
    return {
      kind,
      springType: values.springType || '',
      ...Object.fromEntries(
        Object.entries(sizes).map(([key, [, unit]]) => [
          key,
          unit === 'count'
            ? values[key] == null ? null : Number(values[key])
            : lengthDto(values[key]),
        ]),
      ),
      wireGauge: values.wireGauge || '',
      wireGrade: values.wireGrade || '',
      nameFormat: values.nameFormat || defaultFormat(kind),
    };
  },
};

function createSpringWork(deps) {
  const work = createRawFormWork(deps, SPRING_FORM);
  return {
    listSprings: work.list,
    getSpring: work.get,
    createSpring: work.create,
    updateSpring: work.update,
  };
}

function registerSpringRoutes(ctx) {
  registerRawFormRoutes(ctx, 'springs');
}

module.exports = {
  FORM_KEY,
  KINDS,
  SPRING_FORM,
  createSpringWork,
  registerSpringRoutes,
  springName,
  specKey,
  defaultFormat,
  blocksFor,
};
