class UnitDefinition {
  const UnitDefinition({
    required this.id,
    required this.name,
    required this.symbol,
    required this.notes,
    required this.unitGroupId,
    required this.unitGroupName,
    required this.conversionFactor,
    required this.conversionBaseUnitId,
    required this.conversionBaseUnitName,
    required this.isArchived,
    required this.usageCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String symbol;
  final String notes;
  final int? unitGroupId;
  final String? unitGroupName;
  final double conversionFactor;
  final int? conversionBaseUnitId;
  final String? conversionBaseUnitName;
  final bool isArchived;
  final int usageCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isUsed => usageCount > 0;
  bool get isGrouped => unitGroupId != null && (unitGroupName?.isNotEmpty ?? false);
  bool get isBaseUnit => isGrouped && conversionBaseUnitId == null;

  String get displayLabel => '$name ($symbol)';
}
