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
}
