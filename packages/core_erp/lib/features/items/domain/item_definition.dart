import '../../production_pipelines/domain/pen_paper_baseline.dart';

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
    this.numericMin,
    this.numericMax,
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

  /// Inclusive bounds a 'Numeric' property accepts. Either may be null
  /// (open-ended); both are null for Text/Gauge properties.
  final double? numericMin;
  final double? numericMax;

  /// Whether this property constrains typed numbers to a range at all.
  bool get hasNumericRange =>
      inputType == 'Numeric' && (numericMin != null || numericMax != null);

  /// Human-readable range for labels and hints — '1 – 40', '≥ 1', '≤ 40'.
  String get numericRangeLabel {
    String fmt(double value) => value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
    if (numericMin != null && numericMax != null) {
      return '${fmt(numericMin!)} – ${fmt(numericMax!)}';
    }
    if (numericMin != null) return '≥ ${fmt(numericMin!)}';
    if (numericMax != null) return '≤ ${fmt(numericMax!)}';
    return '';
  }

  bool get isLeafValue =>
      kind == ItemVariationNodeKind.value && activeChildren.isEmpty;

  List<ItemVariationNodeDefinition> get activeChildren =>
      children.where((node) => !node.isArchived).toList(growable: false);

  List<ItemVariationNodeDefinition> get leafValueNodes {
    final leaves = <ItemVariationNodeDefinition>[];
    void visit(ItemVariationNodeDefinition node) {
      if (node.kind == ItemVariationNodeKind.value &&
          node.activeChildren.isEmpty) {
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
    this.penPaperBaseline,
    this.blankWidthMm = 0,
    this.blankHeightMm = 0,
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

  /// The blank this part is cut as, in millimetres.
  ///
  /// Sheet planning needs a part to have a size before it can be planned onto a
  /// sheet. Held on the item rather than on the die because the blank IS the
  /// item — the die is the tool that happens to produce it, and one part can
  /// outlive several dies. Zero means nobody has measured it, and the planner
  /// says so rather than guessing.
  final double blankWidthMm;
  final double blankHeightMm;

  /// Whether this part can be planned onto a sheet at all.
  bool get hasBlankSize => blankWidthMm > 0 && blankHeightMm > 0;

  /// Client this item was developed for, so it can be listed under them.
  final int? developedForClientId;
  final String developedForClientName;

  /// Whether this item can be ordered as a purchase (reception) line in the
  /// mobile Purchase-challan flow. Curated in the desktop item editor.
  final bool availableForPurchase;

  /// Sample run recorded against this specific item — the pen & paper yield
  /// baseline. Distinct from the pipeline template's copy, which every item on
  /// that template shares. Null until a sample is recorded.
  final PenPaperBaseline? penPaperBaseline;

  /// A "basic item": spawned from a base item by Variation Creation, so it has
  /// no variation tree of its own and inherits group, unit and naming from its
  /// base. These open the trimmed basic-item editor.
  bool get isBasicItem => baseItemId != null;

  bool get isUsed => usageCount > 0;

  List<ItemVariationNodeDefinition> get activeVariationTree =>
      variationTree.where((node) => !node.isArchived).toList(growable: false);

  List<ItemVariationNodeDefinition> get topLevelProperties =>
      activeVariationTree
          .where((node) => node.kind == ItemVariationNodeKind.property)
          .toList(growable: false);

  /// The same item under a new name pair. A variant's name is derived from its
  /// values, so changing a value has to show up before the save round-trips —
  /// this is what the screen puts on the list while the update is in flight.
  ItemDefinition renamed({String? name, String? displayName}) {
    return ItemDefinition(
      id: id,
      name: name ?? this.name,
      alias: alias,
      shortCode: shortCode,
      displayName: displayName ?? this.displayName,
      quantity: quantity,
      groupId: groupId,
      unitId: unitId,
      unitConversions: unitConversions,
      propertySchema: propertySchema,
      namingFormat: namingFormat,
      isArchived: isArchived,
      usageCount: usageCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
      variationTree: variationTree,
      defaultPipelineId: defaultPipelineId,
      defaultPipelineName: defaultPipelineName,
      baseItemId: baseItemId,
      photoUrl: photoUrl,
      cadFileKey: cadFileKey,
      cadFileName: cadFileName,
      attachments: attachments,
      developedForClientId: developedForClientId,
      developedForClientName: developedForClientName,
      machines: machines,
      dies: dies,
      combinationGroupIds: combinationGroupIds,
      availableForPurchase: availableForPurchase,
      penPaperBaseline: penPaperBaseline,
      blankWidthMm: blankWidthMm,
      blankHeightMm: blankHeightMm,
    );
  }

  List<ItemVariationNodeDefinition> get leafVariationNodes {
    final leaves = <ItemVariationNodeDefinition>[];

    void visit(ItemVariationNodeDefinition node) {
      if (node.kind == ItemVariationNodeKind.value &&
          node.activeChildren.isEmpty) {
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
