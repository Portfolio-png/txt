'use strict';

// ---------------------------------------------------------------------------
// Part identity — the number a part is issued and the code derived from it.
//
// "The forty-eighth Dolly patti in Switch Action" is SADP48: one letter per
// word of the group, then the set, then the part name, then the number.
//
// This module is authoritative. The Flutter side mirrors buildPartCode so the
// field can fill in as someone types (packages/core_erp/lib/features/items/
// domain/part_code.dart), but anything that reaches the database comes through
// here — a rule that lived only in a dialog would be skipped by the item
// editor, by an import, and by the portal.
// ---------------------------------------------------------------------------

// Long enough to read a part off a drawing, short enough to print beside a
// barcode. A group, a set and a name can each be several words, and without a
// cap "Switch Action Assembly Mounting Plate" becomes a code nobody can say.
const MAX_CODE_LETTERS = 12;

// One letter per word, taken only where the word STARTS with an ASCII letter.
// "2mm Washer" is a washer, not an M-something, so the leading number loses its
// word; "M8 Bolt" keeps both, because M8 is how that part is named.
//
// The character is tested before it is upper-cased, deliberately: Node's
// toUpperCase is locale-sensitive (Turkish dotless i) and Dart's is not, and
// the two sides have to agree on what counts as a letter.
function initialsOf(value) {
  const words = String(value || '').split(/[^A-Za-z0-9]+/);
  let out = '';
  for (const word of words) {
    if (!word) continue;
    const first = word[0];
    if (!/[A-Za-z]/.test(first)) continue;
    out += first.toUpperCase();
  }
  return out;
}

// The code for a part, or '' when there is nothing to build one from.
//
// A missing segment is simply absent — null and '' mean the same thing, and
// neither leaves a gap. With no letters anywhere the answer is '', never the
// bare number: a code that is only digits is indistinguishable from the part
// number and tells a reader nothing.
// "The same name" — trim, collapse internal whitespace, lower-case.
//
// Twin of normalizeUnitValue in server.js, which is what the duplicate-name
// check uses. The part number scopes by name, so the two have to agree: a name
// the duplicate check calls identical must get the next number, not a fresh 1.
function normalizeName(value) {
  return String(value || '').trim().replace(/\s+/g, ' ').toLowerCase();
}

// The group lineage a code's letters come from, root first.
//
// A part is filed under the DEEPEST group it belongs to — the sheet creates
// "Dolly" as a child of "Switch Action" and files the part there — so the one
// row the save has in hand is the child. Taking only its name gave `DP` for a
// part the sheet calls `SADP`, and the two disagreed on every part that has a
// type. Walk up.
//
// Bounded, because a cycle in parent_group_id would otherwise hang the save.
async function groupLineage(groupId, { get }) {
  const names = [];
  let current = Number(groupId || 0);
  const seen = new Set();
  for (let depth = 0; depth < 10 && current; depth += 1) {
    if (seen.has(current)) break;
    seen.add(current);
    const row = await get('SELECT name, parent_group_id FROM groups WHERE id = ?', [
      current,
    ]);
    if (!row) break;
    names.push(row.name || '');
    current = Number(row.parent_group_id || 0);
  }
  const lineage = names.reverse();
  // "Primary Group" is the root saveGroup files every parentless group under,
  // not a name anybody chose for the part, so it is no part of the code: the
  // sheet shows action › dolly › patti and previews ADP…, and the stamp read
  // PGADP… until this. Only when something sits below it — a part filed
  // straight under Primary Group keeps its letters.
  if (lineage.length > 1 && normalizeName(lineage[0]) === 'primary group') {
    lineage.shift();
  }
  return lineage;
}

function buildPartCode({ groupName, setName, itemName, partNo } = {}) {
  const letters = (
    initialsOf(groupName) +
    initialsOf(setName) +
    initialsOf(itemName)
  ).slice(0, MAX_CODE_LETTERS);
  if (!letters) return '';
  const number =
    partNo === null || partNo === undefined || !Number.isFinite(Number(partNo))
      ? ''
      : String(Math.trunc(Number(partNo)));
  return `${letters}${number}`;
}

// The code for a VARIANT of a part — "the brass 22-gauge forty-eighth Dolly
// patti in Switch Action", written SADPB2248.
//
// The trunk is `buildPartCode`'s trunk, unchanged, because a variant of SADP48
// must be legible as one; the value codes go between the letters and the
// number, in the order the variation properties are declared. That ordering is
// the caller's: it is the item's naming format, which this module cannot see.
//
// A value code is whatever the shop typed into the variation editor's `Code`
// field, falling back to `valueCodeFor` below. The cap applies to the TRUNK
// only — clipping a value code would make two variants share one code, which
// is worse than a long one, and the unique index would then refuse the second
// variant with no way to tell why.
function buildVariantPartCode({ groupName, setName, itemName, valueCodes, partNo } = {}) {
  const letters = (
    initialsOf(groupName) +
    initialsOf(setName) +
    initialsOf(itemName)
  ).slice(0, MAX_CODE_LETTERS);
  if (!letters) return '';
  const values = (Array.isArray(valueCodes) ? valueCodes : [])
    .map((code) => String(code || '').replace(/[^A-Za-z0-9]+/g, '').toUpperCase())
    .filter((code) => code.length > 0)
    .join('');
  const number =
    partNo === null || partNo === undefined || !Number.isFinite(Number(partNo))
      ? ''
      : String(Math.trunc(Number(partNo)));
  return `${letters}${values}${number}`;
}

// The variant code for a part that ALREADY HAS a code — `SADP48` plus
// ['B','22'] becomes `SADPB2248`.
//
// Prefer this over buildVariantPartCode whenever the part is already saved,
// because the trunk then comes from the code the part is actually known by.
// Re-deriving from names needs the group AND the set, and getting the set
// wrong is silent: 'Switch Action' + 'Patti' with no set derives SAP, so a
// variant of SADP48 would be stamped SAPB2248 — a code whose trunk its own
// parent does not share. That is not hypothetical; it is what the end-to-end
// check produced before this function existed.
//
// '' when the base has no code: a variant of an unnamed part cannot be named
// either, and inventing a trunk would give the variant a code its parent does
// not have. Twin of `variantCodeFromPartCode` in part_code.dart.
function variantCodeFromPartCode(basePartCode, valueCodes) {
  const base = String(basePartCode || '').trim().toUpperCase();
  if (!base) return '';
  const values = (Array.isArray(valueCodes) ? valueCodes : [])
    .map((code) => String(code || '').replace(/[^A-Za-z0-9]+/g, '').toUpperCase())
    .filter((code) => code.length > 0)
    .join('');
  if (!values) return base;
  // The number is the trailing digit run and stays last, so a variant code
  // reads the same way round as the part code it came from.
  const match = /^(.*?)(\d*)$/.exec(base);
  const trunk = match[1];
  if (!trunk) return base;
  return `${trunk}${values}${match[2]}`;
}

// A code derived from a variation value's name, for values nobody has coded.
//
// One word becomes its first four letters; several become their initials,
// except all-digit words, which are kept whole — "22" has to stay 22, because
// a gauge is not the letter 2. The twin of `generatedCodeForText` in
// packages/core_erp/lib/features/items/domain/variation_code.dart, which is
// where this rule has always lived; it is here because a variant code has to
// be derivable on the server too.
//
// Note what this means in practice: "Brass" derives BRAS, not B. B is a
// decision somebody makes in the Code field; BRAS is the guess made when
// nobody did.
function valueCodeFor(value) {
  const words = String(value || '').match(/[A-Za-z0-9]+/g) || [];
  if (words.length === 0) return String(value || '').trim();
  if (words.length === 1) {
    const word = words[0].toUpperCase();
    return word.length <= 4 ? word : word.slice(0, 4);
  }
  return words
    .map((word) => (/^\d+$/.test(word) ? word : word[0]))
    .join('')
    .toUpperCase();
}

// The next number for a part about to be created in (group, set).
//
// Scope is the group AND the set, so each type restarts at 1 — that is what
// makes 48 mean "the forty-eighth Dolly", rather than the forty-eighth thing
// in Switch Action.
//
// Archived parts count. A number that was issued is spent: reissuing it puts
// two rows on one code, which the unique index then refuses with an error the
// person typing could not have predicted.
// One value's contribution to a part code: NUMBERS WHOLE, LETTERS FIRST.
//
// Brass -> B, Nickel -> N, Mild Steel -> MS, and 22 Gauge -> 22G.
//
// The digits are kept deliberately. Taking strictly the first character turns
// both "22 Gauge" and "24 Gauge" into "2", so the two parts a press shop most
// needs to tell apart would share a code and the unique index would refuse the
// second with nothing to explain why. Gauge is the distinction; it cannot be
// the thing that gets dropped.
//
// Distinct from valueCodeFor above, which keeps a short single word whole
// (Brass -> BRAS) because it is the fallback for a VARIANT code where one value
// is being added to a part that already has a name. This is the properties rule
// for the code a part is stamped with, where every top-level property
// contributes and four letters each would not fit on a drawing.
//
// Twin of partPropertyCode in packages/core_erp/lib/features/items/domain/
// part_code.dart, asserted against the same vectors on both sides.
function propertyCodeFor(value) {
  // Split on the digit/letter boundary too, not only on punctuation and
  // spaces. "22 Gauge" was already two words and came out 22G, but "22G"
  // typed without the space was ONE word, was not all digits, and so took its
  // first character — giving 2, exactly what this rule exists to prevent, and
  // colliding with 24G. A gauge cell takes typed values verbatim, so that
  // spelling is the normal one.
  const tokens = String(value || '').match(/\d+|[A-Za-z]+/g) || [];
  if (tokens.length === 0) return '';
  return tokens
    .map((token) => (/^\d+$/.test(token) ? token : token[0]))
    .join('')
    .toUpperCase();
}

async function nextPartNo({ groupId, setId, setPending, itemName }, { get, all }) {
  const normalizedGroupId = Number(groupId || 0);
  if (!normalizedGroupId) return 1;

  // Scope is the group and the NAME, so "the forty-eighth Dolly patti" counts
  // Dolly pattis. It used to be the group and the SET, which made 48 the
  // forty-eighth part of any name in that set — the code said one thing and the
  // number counted another.
  //
  // Filtered in JS rather than matched in SQL so that "the same name" means
  // exactly what it means everywhere else. normalizeName is the twin of
  // server.js's normalizeUnitValue, and a LOWER(TRIM(...)) in SQL would not
  // collapse the internal whitespace that one does.
  //
  // Archived parts count. A number that was issued is spent: reissuing it puts
  // two rows on one code, which the unique index then refuses with an error the
  // person typing could not have predicted.
  const wanted = normalizeName(itemName);
  if (!wanted) {
    // Nothing to scope by. Fall back to the group so a part with no name yet
    // still gets a number rather than colliding on 1 with every other.
    const row = await get(
      'SELECT MAX(part_no) AS maxNo FROM items WHERE group_id = ?',
      [normalizedGroupId],
    );
    return Number(row?.maxNo || 0) + 1;
  }

  const rows = await all(
    'SELECT name, part_no FROM items WHERE group_id = ? AND part_no IS NOT NULL',
    [normalizedGroupId],
  );
  let maxNo = 0;
  for (const row of rows || []) {
    if (normalizeName(row.name) !== wanted) continue;
    const no = Number(row.part_no || 0);
    if (no > maxNo) maxNo = no;
  }
  return maxNo + 1;
}

module.exports = {
  buildPartCode,
  buildVariantPartCode,
  variantCodeFromPartCode,
  valueCodeFor,
  propertyCodeFor,
  normalizeName,
  groupLineage,
  initialsOf,
  nextPartNo,
  MAX_CODE_LETTERS,
};
