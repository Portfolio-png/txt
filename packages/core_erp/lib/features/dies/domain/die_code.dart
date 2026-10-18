/// The code a die is known by on the floor.
///
/// "The cutting die for the forty-eighth Dolly patti in Switch Action" is
/// `CDSADP48`: the type's initials, then D for die, then the part's own code.
///
/// **The backend is authoritative** — `backend/modules/dies/die-identity.js`
/// owns this rule, and every write goes through it. This copy exists so the
/// field can fill in as someone picks a type, and the fixture table in
/// `die_code_test.dart` is asserted on both sides so the two cannot drift.
library;

import '../../items/domain/part_code.dart';

/// The kinds of die the floor makes.
///
/// A third is a value here and a row there; nothing else branches on it,
/// because the code rule reads the [label] rather than the name.
enum DieType {
  cutting('cutting', 'Cutting'),
  bending('bending', 'Bending');

  const DieType(this.slug, this.label);

  /// What `dies.die_type` holds.
  final String slug;

  /// What the code's initials come from, and what a person reads.
  final String label;

  static DieType? fromSlug(String? value) {
    final raw = (value ?? '').trim();
    for (final type in DieType.values) {
      if (type.slug == raw) return type;
    }
    // An unknown kind reads as "nobody said" rather than throwing: a client one
    // version behind the server still has to open the die.
    return null;
  }
}

/// The code for a die, or `''` when there is nothing to build one from.
///
/// Both halves are required. A die code of just "D" names nothing, and one
/// that was only the part's code would collide with the part itself the moment
/// either is scanned.
String buildDieCode({DieType? type, String? partCode}) {
  if (type == null) return '';
  final letters = partCodeInitials(type.label);
  final code = (partCode ?? '').trim().toUpperCase();
  if (letters.isEmpty || code.isEmpty) return '';
  return '${letters}D$code';
}
