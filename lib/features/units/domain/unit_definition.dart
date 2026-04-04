class UnitDefinition {
  const UnitDefinition({
    required this.id,
    required this.name,
    required this.symbol,
    required this.notes,
    required this.isArchived,
    required this.usageCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String symbol;
  final String notes;
  final bool isArchived;
  final int usageCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isUsed => usageCount > 0;

  String get displayLabel => '$name ($symbol)';
}
