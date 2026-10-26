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
  bending('bending', 'Bending'),
  riveting('riveting', 'Riveting'),
  assembly('assembly', 'Assembly');

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

/// A kind of die — one of the four, or words the shop typed.
///
/// The four built-ins are a closed set everywhere that matters: their slug is
/// authoritative and their label is looked up from it, so a stale label cannot
/// rename one. A typed type has no row to look anything up in, so it carries
/// its own [label], and that label is the ONLY place the words survive — the
/// code is built from their initials, and a slug with no label derives `''`.
///
/// `Deep Drawing` → slug `deep-drawing`, label `Deep Drawing`, code
/// `DDD<part code>`.
class DieTypeChoice {
  const DieTypeChoice._(this.slug, this.label, this.builtIn);

  factory DieTypeChoice.of(DieType type) =>
      DieTypeChoice._(type.slug, type.label, true);

  /// A type somebody typed. Empty or whitespace gives null — there is no
  /// such thing as a nameless type.
  static DieTypeChoice? custom(String label) {
    final words = label.trim();
    if (words.isEmpty) return null;
    final slug = slugifyDieType(words);
    if (slug.isEmpty) return null;
    // Typing the name of a built-in gives the built-in, not a second one
    // that happens to read the same.
    for (final type in DieType.values) {
      if (type.slug == slug || type.label.toLowerCase() == words.toLowerCase()) {
        return DieTypeChoice.of(type);
      }
    }
    return DieTypeChoice._(slug, words, false);
  }

  /// Reconstitutes what a die was stored as.
  static DieTypeChoice? fromStored(String? slug, String? storedLabel) {
    final known = DieType.fromSlug(slug);
    if (known != null) return DieTypeChoice.of(known);
    final raw = (slug ?? '').trim();
    if (raw.isEmpty) return null;
    final words = (storedLabel ?? '').trim();
    // A slug whose words were never stored can still be shown — as itself,
    // which is better than a blank Type cell on a die that has one.
    return DieTypeChoice._(raw, words.isEmpty ? raw : words, false);
  }

  final String slug;
  final String label;
  final bool builtIn;

  /// What goes in `dies.die_type_label`. Empty for a built-in, whose label is
  /// looked up from the slug on both sides.
  String get storedLabel => builtIn ? '' : label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DieTypeChoice && other.slug == slug && other.label == label);

  @override
  int get hashCode => Object.hash(slug, label);
}

/// The slug for a typed label: lower case, non-alphanumerics to `-`.
///
/// Twin of `slugifyDieType` in `backend/modules/dies/die-identity.js`.
String slugifyDieType(String label) {
  return label
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

/// The code for a die, or `''` when there is nothing to build one from.
///
/// Both halves are required. A die code of just "D" names nothing, and one
/// that was only the part's code would collide with the part itself the moment
/// either is scanned.
String buildDieCode({DieType? type, String? partCode}) =>
    buildDieCodeFor(
      choice: type == null ? null : DieTypeChoice.of(type),
      partCode: partCode,
    );

/// The same rule, for a type that may have been typed rather than picked.
String buildDieCodeFor({DieTypeChoice? choice, String? partCode}) {
  if (choice == null) return '';
  final letters = partCodeInitials(choice.label);
  final code = (partCode ?? '').trim().toUpperCase();
  if (letters.isEmpty || code.isEmpty) return '';
  return '${letters}D$code';
}
