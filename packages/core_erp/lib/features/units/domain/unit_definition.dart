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
    required this.conversionType,
    required this.precision,
    required this.unitGroupDimension,
    required this.unitGroupBaseUnitId,
    this.conversionPoints = const [],
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
  final String conversionType;
  final int? precision;
  final String? unitGroupDimension;
  final int? unitGroupBaseUnitId;
  final List<ConversionPoint> conversionPoints;
  final bool isArchived;
  final int usageCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isUsed => usageCount > 0;
  bool get isGrouped =>
      unitGroupId != null && (unitGroupName?.isNotEmpty ?? false);
  bool get isBaseUnit => isGrouped && conversionBaseUnitId == null;

  String get displayLabel => '$name ($symbol)';
}

class ConversionPoint {
  const ConversionPoint({
    required this.id,
    required this.unitId,
    required this.pointKey,
    required this.baseValue,
  });

  final int id;
  final int unitId;
  final String pointKey;
  final double baseValue;

  factory ConversionPoint.fromJson(Map<String, dynamic> json) {
    return ConversionPoint(
      id: json['id'] as int,
      unitId: json['unit_id'] as int,
      pointKey: json['point_key'] as String,
      baseValue: (json['base_value'] as num).toDouble(),
    );
  }
}
