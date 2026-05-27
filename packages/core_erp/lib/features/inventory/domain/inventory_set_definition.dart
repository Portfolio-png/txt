class InventorySetDefinition {
  const InventorySetDefinition({
    required this.id,
    required this.name,
    required this.totalItemCount,
    required this.createdAt,
    required this.updatedAt,
    required this.lines,
  });

  final int id;
  final String name;
  final int totalItemCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<InventorySetLineDefinition> lines;
}

class InventorySetLineDefinition {
  const InventorySetLineDefinition({
    required this.id,
    required this.itemId,
    required this.variationLeafNodeId,
    required this.quantity,
    required this.position,
    required this.itemName,
    required this.itemDisplayName,
    required this.variationPathLabel,
    required this.variationPathNodeIds,
  });

  final int? id;
  final int itemId;
  final int variationLeafNodeId;
  final int quantity;
  final int position;
  final String itemName;
  final String itemDisplayName;
  final String variationPathLabel;
  final List<int> variationPathNodeIds;
}

class SaveInventorySetInput {
  const SaveInventorySetInput({
    this.id,
    required this.name,
    required this.lines,
  });

  final int? id;
  final String name;
  final List<SaveInventorySetLineInput> lines;
}

class SaveInventorySetLineInput {
  const SaveInventorySetLineInput({
    required this.itemId,
    required this.variationLeafNodeId,
    required this.quantity,
    required this.position,
    this.itemName = '',
    this.itemDisplayName = '',
    this.variationPathLabel = '',
    this.variationPathNodeIds = const <int>[],
  });

  final int itemId;
  final int variationLeafNodeId;
  final int quantity;
  final int position;
  final String itemName;
  final String itemDisplayName;
  final String variationPathLabel;
  final List<int> variationPathNodeIds;
}
