class PipelineItemEndpoint {
  const PipelineItemEndpoint({
    required this.itemId,
    required this.itemName,
    required this.unitId,
    required this.unitName,
    required this.unitSymbol,
  });

  final int itemId;
  final String itemName;
  final int unitId;
  final String unitName;
  final String unitSymbol;

  factory PipelineItemEndpoint.fromJson(Map<String, dynamic> json) {
    return PipelineItemEndpoint(
      itemId: (json['itemId'] as num?)?.toInt() ?? 0,
      itemName: json['itemName'] as String? ?? '',
      unitId: (json['unitId'] as num?)?.toInt() ?? 0,
      unitName: json['unitName'] as String? ?? '',
      unitSymbol: json['unitSymbol'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'itemId': itemId,
      'itemName': itemName,
      'unitId': unitId,
      'unitName': unitName,
      'unitSymbol': unitSymbol,
    };
  }

  String get unitLabel {
    final symbol = unitSymbol.trim();
    if (symbol.isNotEmpty) {
      return symbol;
    }
    final name = unitName.trim();
    return name.isNotEmpty ? name : 'Unit #$unitId';
  }
}
