class VariationStockRecord {
  final int stockId;
  final int itemId;
  final int variationLeafNodeId;
  final double quantity;
  final String locationId;
  final DateTime updatedAt;
  final String itemName;
  final int? unitId;
  final List<String> namingFormat;
  final List<int> variationPathNodeIds;
  final List<String> variationPathValues;
  final Map<String, String> customVariationValues;

  const VariationStockRecord({
    required this.stockId,
    required this.itemId,
    required this.variationLeafNodeId,
    required this.quantity,
    required this.locationId,
    required this.updatedAt,
    required this.itemName,
    this.unitId,
    required this.namingFormat,
    this.variationPathNodeIds = const [],
    this.variationPathValues = const [],
    this.customVariationValues = const {},
  });
}
