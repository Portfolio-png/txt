class MaterialFlow {
  const MaterialFlow({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.materialName,
    this.barcode,
    this.isSplit = false,
    this.isMerge = false,
  });

  final String id;
  final String fromNodeId;
  final String toNodeId;
  final String materialName;
  final String? barcode;
  final bool isSplit;
  final bool isMerge;

  factory MaterialFlow.fromJson(Map<String, dynamic> json) {
    return MaterialFlow(
      id: json['id'] as String? ?? '',
      fromNodeId: json['fromNodeId'] as String? ?? '',
      toNodeId: json['toNodeId'] as String? ?? '',
      materialName: json['materialName'] as String? ?? '',
      barcode: json['barcode'] as String?,
      isSplit: json['isSplit'] as bool? ?? false,
      isMerge: json['isMerge'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fromNodeId': fromNodeId,
      'toNodeId': toNodeId,
      'materialName': materialName,
      'barcode': barcode,
      'isSplit': isSplit,
      'isMerge': isMerge,
    };
  }
}
