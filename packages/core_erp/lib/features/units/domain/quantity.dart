/// Physical Quantity: an integer count of base units, plus its family.
/// Per `.claude/skills/units/SKILL.md` §1, §2, §4.
library;

import 'unit_family.dart';

class Quantity implements Comparable<Quantity> {
  const Quantity(this.base, this.family);

  /// Integer count of base units — the truth (Invariant I1).
  final int base;
  final UnitFamily family;

  Quantity operator +(Quantity other) {
    if (family.id != other.family.id) {
      throw ArgumentError(
        'Cannot add quantities across different families '
        '(${family.name} and ${other.family.name}). Invariant I4 violated.',
      );
    }
    return Quantity(base + other.base, family);
  }

  Quantity operator -(Quantity other) {
    if (family.id != other.family.id) {
      throw ArgumentError(
        'Cannot subtract quantities across different families '
        '(${family.name} and ${other.family.name}). Invariant I4 violated.',
      );
    }
    return Quantity(base - other.base, family);
  }

  Quantity times(int n) => Quantity(base * n, family);

  bool get isZero => base == 0;

  @override
  int compareTo(Quantity other) {
    if (family.id != other.family.id) {
      throw ArgumentError(
        'Cannot compare quantities across different families '
        '(${family.name} and ${other.family.name}). Invariant I4 violated.',
      );
    }
    return base.compareTo(other.base);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Quantity &&
          runtimeType == other.runtimeType &&
          base == other.base &&
          family.id == other.family.id;

  @override
  int get hashCode => Object.hash(base, family.id);

  @override
  String toString() => 'Quantity($base base units, family: ${family.code})';
}
