/// The single source of truth for Unit Families and Ladder Rungs.
/// Per `.claude/skills/units/SKILL.md` §4.
library;

class UnitFamily {
  const UnitFamily({
    required this.id,
    required this.code,
    required this.name,
    required this.dimension,
    this.integralOnly = false,
    this.units = const <Unit>[],
  });

  final int id;
  final String code;
  final String name;
  final String dimension;
  final bool integralOnly;
  final List<Unit> units;

  Unit get base =>
      units.firstWhere((u) => u.isBase, orElse: () => units.first);

  List<Unit> get ladder =>
      units.where((u) => u.onLadder).toList()
        ..sort((a, b) => a.factorToBase.compareTo(b.factorToBase));
}

class Unit {
  const Unit({
    required this.id,
    required this.familyId,
    required this.code,
    required this.label,
    required this.symbol,
    this.factorToBase = 1,
    this.isBase = false,
    this.onLadder = true,
    this.maxDecimals = 4,
    this.uqc,
  });

  final int id;
  final int familyId;
  final String code;
  final String label;
  final String symbol;
  final int factorToBase;
  final bool isBase;
  final bool onLadder;
  final int maxDecimals;
  final String? uqc;

  String get displayLabel => '$label ($symbol)';
}
