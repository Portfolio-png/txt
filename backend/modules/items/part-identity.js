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

// The next number for a part about to be created in (group, set).
//
// Scope is the group AND the set, so each type restarts at 1 — that is what
// makes 48 mean "the forty-eighth Dolly", rather than the forty-eighth thing
// in Switch Action.
//
// Archived parts count. A number that was issued is spent: reissuing it puts
// two rows on one code, which the unique index then refuses with an error the
// person typing could not have predicted.
async function nextPartNo({ groupId, setId, setPending }, { get }) {
  const normalizedGroupId = Number(groupId || 0);
  if (!normalizedGroupId) return 1;

  // A set that has only been named has no members yet, so its scope is empty
  // and the answer is 1. The caller has to say so — nothing stored can tell us,
  // because the set does not exist.
  if (setPending) return 1;

  const normalizedSetId = Number(setId || 0);
  const row = normalizedSetId
    ? await get(
        `SELECT MAX(items.part_no) AS maxNo
           FROM items
           JOIN inventory_set_lines ON inventory_set_lines.item_id = items.id
          WHERE items.group_id = ? AND inventory_set_lines.set_id = ?`,
        [normalizedGroupId, normalizedSetId],
      )
    : await get(
        // The group's unfiled parts — the ones belonging to no set at all.
        `SELECT MAX(part_no) AS maxNo
           FROM items
          WHERE group_id = ?
            AND NOT EXISTS (
              SELECT 1 FROM inventory_set_lines
               WHERE inventory_set_lines.item_id = items.id
            )`,
        [normalizedGroupId],
      );

  return Number(row?.maxNo || 0) + 1;
}

module.exports = { buildPartCode, initialsOf, nextPartNo, MAX_CODE_LETTERS };
