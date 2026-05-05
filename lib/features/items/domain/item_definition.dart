enum ItemVariationNodeKind { property, value }

class ItemVariationNodeDefinition {
  const ItemVariationNodeDefinition({
    required this.id,
    required this.itemId,
    required this.parentNodeId,
    required this.kind,
    required this.name,
    this.code = '',
    required this.displayName,
    required this.position,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
    required this.children,
  });

  final int id;
  final int itemId;
  final int? parentNodeId;
  final ItemVariationNodeKind kind;
  final String name;
  final String code;
  final String displayName;
  final int position;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ItemVariationNodeDefinition> children;

  bool get isLeafValue =>
      kind == ItemVariationNodeKind.value && children.isEmpty;

  List<ItemVariationNodeDefinition> get activeChildren =>
      children.where((node) => !node.isArchived).toList(growable: false);

  List<ItemVariationNodeDefinition> get leafValueNodes {
    final leaves = <ItemVariationNodeDefinition>[];
    void visit(ItemVariationNodeDefinition node) {
      if (node.kind == ItemVariationNodeKind.value && node.children.isEmpty) {
        leaves.add(node);
        return;
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    visit(this);
    return leaves;
  }
}

class ItemDefinition {
  const ItemDefinition({
    required this.id,
    required this.name,
    required this.alias,
    required this.displayName,
    required this.quantity,
    required this.groupId,
    required this.unitId,
    this.namingFormat = const [],
    required this.isArchived,
    required this.usageCount,
    required this.createdAt,
    required this.updatedAt,
    required this.variationTree,
  });

  final int id;
  final String name;
  final String alias;
  final String displayName;
  final double quantity;
  final int groupId;
  final int unitId;
  final List<String> namingFormat;
  final bool isArchived;
  final int usageCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ItemVariationNodeDefinition> variationTree;

  bool get isUsed => usageCount > 0;

  List<ItemVariationNodeDefinition> get activeVariationTree =>
      variationTree.where((node) => !node.isArchived).toList(growable: false);

  List<ItemVariationNodeDefinition> get topLevelProperties =>
      activeVariationTree
          .where((node) => node.kind == ItemVariationNodeKind.property)
          .toList(growable: false);

  List<ItemVariationNodeDefinition> get leafVariationNodes {
    final leaves = <ItemVariationNodeDefinition>[];

    void visit(ItemVariationNodeDefinition node) {
      if (node.kind == ItemVariationNodeKind.value && node.children.isEmpty) {
        leaves.add(node);
        return;
      }
      for (final child in node.activeChildren) {
        visit(child);
      }
    }

    for (final node in activeVariationTree) {
      visit(node);
    }
    return leaves;
  }
}
