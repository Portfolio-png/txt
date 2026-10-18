'use strict';

// ---------------------------------------------------------------------------
// Machine identity — the number a machine is known by on the floor.
//
// "The fourth power press" is PP-4: the type's initials, then the next number
// in that type. The same rule as a part's SADP48 and a die's CDSADP48, and
// deliberately so — three codes that disagreed about what counts as a letter
// would be three codes nobody could read off a machine and type back in.
//
// This module is authoritative; the Flutter side mirrors buildMachineNo so the
// field can fill in as someone picks a type (packages/core_erp/lib/features/
// machines/domain/machine_no.dart).
//
// NOTE what this is not: a rule imposed on what already exists. Live asset ids
// are PP-60T-01, CUT-04, HP-150T-05, MAC-1001 — several conventions, none of
// them this one. This only ever SUGGESTS, nothing renumbers a machine that is
// already on the floor, and a number someone types is kept as typed.
// ---------------------------------------------------------------------------

const { initialsOf } = require('../items/part-identity');

// The number for a machine, or '' when there is nothing to build one from.
//
// Without a type there are no initials, and a bare "-4" names nothing.
function buildMachineNo({ groupName, nextNumber } = {}) {
  const letters = initialsOf(groupName);
  if (!letters) return '';
  const number = Number(nextNumber);
  if (!Number.isFinite(number) || number <= 0) return '';
  return `${letters}-${Math.trunc(number)}`;
}

// The next number for a machine about to be added to a type.
//
// Counts the machines already in that group rather than parsing their ids,
// because their ids follow no one convention. Best effort by design: this is a
// suggestion, and the unique index is what actually guards the number.
async function nextMachineNo({ groupId }, { get }) {
  const normalizedGroupId = Number(groupId || 0);
  if (!normalizedGroupId) return 1;
  const row = await get(
    'SELECT COUNT(*) AS count FROM machines WHERE group_id = ?',
    [normalizedGroupId],
  );
  return Number(row?.count || 0) + 1;
}

// The first free asset id in the PP-4, PP-5, PP-6 … series.
//
// asset_id is unique across the WHOLE plant, so a suggestion can collide with
// a machine in another type or with one numbered by hand years ago. The series
// is a run of numbers, so the answer is the next number — not "PP-4-2", which
// would read as a machine that does not exist.
async function nextFreeMachineNo(base, { get, excludeId = null } = {}) {
  const root = String(base || '').trim().toUpperCase();
  if (!root) return '';

  const match = root.match(/^(.*?)(\d+)$/);
  for (let step = 0; step < 200; step += 1) {
    const candidate = match
      ? `${match[1]}${Number(match[2]) + step}`
      : (step === 0 ? root : `${root}-${step + 1}`);
    const taken = await get(
      'SELECT id FROM machines WHERE UPPER(asset_id) = ? AND (? IS NULL OR id <> ?)',
      [candidate, excludeId, excludeId],
    );
    if (!taken) return candidate;
  }
  // Two hundred presses of one type is not a numbering collision any more, so
  // stop guessing and let the caller say so.
  return '';
}

module.exports = { buildMachineNo, nextMachineNo, nextFreeMachineNo };
