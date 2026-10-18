'use strict';

// ---------------------------------------------------------------------------
// Die identity — the code a die is known by on the floor.
//
// "The cutting die for the forty-eighth Dolly patti in Switch Action" is
// CDSADP48: the type's initials, then D for die, then the part's own code.
//
// This module is authoritative. The Flutter side mirrors buildDieCode so the
// field can fill in as someone picks a type (packages/core_erp/lib/features/
// dies/domain/die_code.dart), but anything that reaches the database comes
// through here.
//
// initialsOf is REUSED from the part's rule rather than rewritten. It already
// carries the decisions that matter — a word must start with an ASCII letter,
// and the character is tested before it is upper-cased because Node's
// toUpperCase is locale-sensitive and Dart's is not — and a die code that
// disagreed with its part code about what counts as a letter would be worse
// than either rule alone.
// ---------------------------------------------------------------------------

const { initialsOf } = require('../items/part-identity');

// The kinds the floor makes today.
//
// A third is a ROW here, not a branch anywhere else: the code rule reads the
// label, so adding { slug: 'deepdraw', label: 'Deep Drawing' } yields
// DDD<part code> with no other change, and the Dart enum beside it is the only
// other place that has to learn the word.
const DIE_TYPES = [
  { slug: 'cutting', label: 'Cutting' },
  { slug: 'bending', label: 'Bending' },
];

const DIE_TYPE_SLUGS = DIE_TYPES.map((type) => type.slug);

/** The label for a slug, or '' when it is not one we know. */
function dieTypeLabel(slug) {
  const found = DIE_TYPES.find((type) => type.slug === String(slug || '').trim());
  return found ? found.label : '';
}

// The code for a die, or '' when there is nothing to build one from.
//
// Both halves are required. A die code of just "D" names nothing, and one that
// was only the part's code would collide with the part itself the moment
// either is scanned.
function buildDieCode({ dieType, partCode } = {}) {
  const letters = initialsOf(dieTypeLabel(dieType));
  const code = String(partCode || '').trim().toUpperCase();
  if (!letters || !code) return '';
  return `${letters}D${code}`;
}

// The first free code in the CDSADP48, CDSADP48-2, CDSADP48-3 … series.
//
// Needed because dies.tool_code is unique ACROSS THE FACTORY while
// items.part_code is unique only within its group (see migration 045's index):
// two groups may each hold an SADP48, and their cutting dies both derive
// CDSADP48. That is not a mistake anyone made, so the answer is a suffix to
// choose from — never a silent overwrite, and never a retry of the write that
// was refused.
async function nextFreeDieCode(base, { get, excludeId = null } = {}) {
  const root = String(base || '').trim().toUpperCase();
  if (!root) return '';
  for (let suffix = 0; suffix < 50; suffix += 1) {
    const candidate = suffix === 0 ? root : `${root}-${suffix + 1}`;
    const taken = await get(
      'SELECT id FROM dies WHERE UPPER(tool_code) = ? AND (? IS NULL OR id <> ?)',
      [candidate, excludeId, excludeId],
    );
    if (!taken) return candidate;
  }
  // Fifty dies on one part code is not a naming collision any more, so stop
  // guessing and let the caller say so.
  return '';
}

module.exports = {
  DIE_TYPES,
  DIE_TYPE_SLUGS,
  dieTypeLabel,
  buildDieCode,
  nextFreeDieCode,
};
