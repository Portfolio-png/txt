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
    this.inputType = 'Text',
    this.nameJoin = '',
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
  final String inputType;

  /// Separator between this property's combined child values in display
  /// names ('x' → "14 x 48"); empty follows the item's display format.
  final String nameJoin;

  bool get isLeafValue =>
      kind == ItemVariationNodeKind.value && activeChildren.isEmpty;

  List<ItemVariationNodeDefinition> get activeChildren =>
      children.where((node) => !node.isArchived).toList(growable: false);

  List<ItemVariationNodeDefinition> get leafValueNodes {
    final leaves = <ItemVariationNodeDefinition>[];
    void visit(ItemVariationNodeDefinition node) {
      if (node.kind == ItemVariationNodeKind.value && node.activeChildren.isEmpty) {
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

class ItemPropertySchemaEntry {
  const ItemPropertySchemaEntry({
    required this.propertyKey,
    required this.displayName,
    required this.inputType,
    required this.mandatory,
    this.unitId,
    this.unitSymbol,
    this.unitLabel,
    this.sourceType = 'manual',
    this.sourceGroupId,
    this.sourceGroupName,
    this.sourceItemIds = const <int>[],
    this.sortOrder = 0,
  });

  final String propertyKey;
  final String displayName;
  final String inputType;
  final bool mandatory;
  final int? unitId;
  final String? unitSymbol;
  final String? unitLabel;
  final String sourceType;
  final int? sourceGroupId;
  final String? sourceGroupName;
  final List<int> sourceItemIds;
  final int sortOrder;
}

class ItemDefinition {
  const ItemDefinition({
    required this.id,
    required this.name,
    required this.alias,
    this.shortCode = '',
    required this.displayName,
    required this.quantity,
    required this.groupId,
    required this.unitId,
    this.unitConversions = const [],
    this.propertySchema = const [],
    this.namingFormat = const [],
    required this.isArchived,
    required this.usageCount,
    required this.createdAt,
    required this.updatedAt,
    required this.variationTree,
    this.defaultPipelineId,
    this.defaultPipelineName,
    this.baseItemId,
    this.photoUrl = '',
    this.cadFileKey = '',
    this.cadFileName = '',
    this.attachments = const <ItemAttachmentDefinition>[],
    this.developedForClientId,
    this.developedForClientName = '',
    this.machines = const <ItemMachineLink>[],
    this.dies = const <ItemDieLink>[],
    this.combinationGroupIds = const <int>[],
    this.availableForPurchase = false,
  });

  final int id;
  final String name;
  final String alias;
  final String shortCode;
  final String displayName;
  final double quantity;
  final int groupId;

  /// Combination groups this item additionally belongs to (Enhancement 2.3),
  /// distinct from the primary hierarchical [groupId]. Usually empty.
  final List<int> combinationGroupIds;
  final int unitId;
  final List<ItemUnitConversionDefinition> unitConversions;
  final List<ItemPropertySchemaEntry> propertySchema;
  final List<String> namingFormat;
  final bool isArchived;
  final int usageCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ItemVariationNodeDefinition> variationTree;
  final String? defaultPipelineId;
  final String? defaultPipelineName;
  final int? baseItemId;
  final String photoUrl;

  /// Permanent S3 object key of the CAD / drawing file attached to this item
  /// master — never a presigned URL, which would expire. Read URLs are minted
  /// on demand via `ItemsProvider.createCadFileReadUrl`. Empty when no CAD file
  /// is attached; the attachment lives until someone clears it.
  final String cadFileKey;

  /// Original file name of [cadFileKey], kept so the UI can label the
  /// attachment instead of showing the opaque object key.
  final String cadFileName;

  /// Extra named files beyond the photo and CAD file, in display order.
  final List<ItemAttachmentDefinition> attachments;

  /// Machines this item can be produced on.
  final List<ItemMachineLink> machines;

  /// Dies used to produce this item.
  final List<ItemDieLink> dies;

  /// Client this item was developed for, so it can be listed under them.
  final int? developedForClientId;
  final String developedForClientName;

  /// Whether this item can be ordered as a purchase (reception) line in the
  /// mobile Purchase-challan flow. Curated in the desktop item editor.
  final bool availableForPurchase;

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
      if (node.kind == ItemVariationNodeKind.value && node.activeChildren.isEmpty) {
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

/// An extra named file on an item master — a user-supplied label plus the
/// permanent object key of the uploaded file.
class ItemAttachmentDefinition {
  const ItemAttachmentDefinition({
    this.id,
    required this.label,
    required this.objectKey,
    required this.fileName,
  });

  /// Server-side row id; null for an attachment added but not yet saved.
  final int? id;
  final String label;
  final String objectKey;
  final String fileName;

  /// What to show when the row is listed: the user's label, falling back to the
  /// uploaded file name.
  String get displayLabel =>
      label.trim().isNotEmpty ? label.trim() : fileName.trim();
}

class ItemMachineLink {
  const ItemMachineLink({
    required this.id,
    required this.name,
    this.assetId = '',
  });

  final String id;
  final String name;
  final String assetId;
}

class ItemDieLink {
  const ItemDieLink({required this.id, required this.toolCode});

  final String id;
  final String toolCode;
}

class ItemUnitConversionDefinition {
  const ItemUnitConversionDefinition({
    required this.unitId,
    required this.unitName,
    required this.unitSymbol,
    required this.factorToPrimary,
  });

  final int unitId;
  final String unitName;
  final String unitSymbol;
  final double factorToPrimary;
}
