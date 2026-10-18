/// The number a machine is known by on the floor.
///
/// "The fourth power press" is `PP-4`: the type's initials, then the next
/// number in that type — the same rule as a part's `SADP48` and a die's
/// `CDSADP48`, built on the same `initialsOf`, so three codes cannot disagree
/// about what counts as a letter.
///
/// **The backend is authoritative** — `backend/modules/machines/machine-identity.js`
/// owns this rule. This copy exists so the field can fill in as someone picks a
/// type, and the fixture table in `machine_no_test.dart` is asserted on both
/// sides so the two cannot drift.
///
/// It only ever *suggests*. Machines already on the floor are numbered several
/// different ways (`PP-60T-01`, `CUT-04`, `MAC-1001`); nothing renumbers them,
/// and a number someone types is kept as typed.
library;

import '../../items/domain/part_code.dart';

/// The number for a machine, or `''` when there is nothing to build one from.
///
/// Without a type there are no initials, and a bare `-4` names nothing.
String buildMachineNo({String? typeName, int? nextNumber}) {
  final letters = partCodeInitials(typeName);
  if (letters.isEmpty) return '';
  if (nextNumber == null || nextNumber <= 0) return '';
  return '$letters-$nextNumber';
}

/// The first free number in the `PP-4`, `PP-5`, `PP-6` … series, skipping the
/// ones in [taken].
///
/// The series is a run of numbers, so a clash moves to the next number — not
/// to `PP-4-2`, which would read as a machine that does not exist.
String nextFreeMachineNo(String base, Iterable<String> taken) {
  final root = base.trim().toUpperCase();
  if (root.isEmpty) return '';
  final used = taken
      .map((value) => value.trim().toUpperCase())
      .where((value) => value.isNotEmpty)
      .toSet();
  if (!used.contains(root)) return root;

  final match = RegExp(r'^(.*?)(\d+)$').firstMatch(root);
  for (var step = 1; step < 200; step += 1) {
    final candidate = match == null
        ? '$root-${step + 1}'
        : '${match.group(1)}${int.parse(match.group(2)!) + step}';
    if (!used.contains(candidate)) return candidate;
  }
  return root;
}
