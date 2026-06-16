class PipelineItemEndpoint {
  const PipelineItemEndpoint({
    required this.itemId,
    required this.itemName,
    required this.unitId,
    required this.unitName,
    required this.unitSymbol,
    this.groupId,
    this.groupName,
  });

  final int itemId;
  final String itemName;
  final int unitId;
  final String unitName;
  final String unitSymbol;

  /// When set, this endpoint is an abstract item *group* rather than a specific
  /// item — the concrete item is resolved at production time from the stock
  /// assigned to the node. Group endpoints carry no fixed unit.
  final int? groupId;
  final String? groupName;

  bool get isGroup => groupId != null;

  factory PipelineItemEndpoint.fromJson(Map<String, dynamic> json) {
    return PipelineItemEndpoint(
      itemId: (json['itemId'] as num?)?.toInt() ?? 0,
      itemName: json['itemName'] as String? ?? '',
      unitId: (json['unitId'] as num?)?.toInt() ?? 0,
      unitName: json['unitName'] as String? ?? '',
      unitSymbol: json['unitSymbol'] as String? ?? '',
      groupId: (json['groupId'] as num?)?.toInt(),
      groupName: json['groupName'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'itemId': itemId,
      'itemName': itemName,
      'unitId': unitId,
      'unitName': unitName,
      'unitSymbol': unitSymbol,
      if (groupId != null) 'groupId': groupId,
      if (groupName != null) 'groupName': groupName,
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
