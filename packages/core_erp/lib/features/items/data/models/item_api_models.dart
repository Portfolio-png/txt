import '../../../production_pipelines/domain/pen_paper_baseline.dart';
import '../../domain/item_definition.dart';
import '../../domain/item_inputs.dart';

ItemVariationNodeKind _nodeKindFromJson(String value) {
  return value == 'value'
      ? ItemVariationNodeKind.value
      : ItemVariationNodeKind.property;
}

String _nodeKindToJson(ItemVariationNodeKind kind) {
  return kind == ItemVariationNodeKind.value ? 'value' : 'property';
}

class ItemVariationNodeDto {
  const ItemVariationNodeDto({
    required this.id,
    required this.itemId,
    required this.parentNodeId,
    required this.kind,
    required this.name,
    required this.code,
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
  final List<ItemVariationNodeDto> children;
  final String inputType;
  final String nameJoin;
  final double? numericMin;
  final double? numericMax;

  factory ItemVariationNodeDto.fromJson(Map<String, dynamic> json) {
    return ItemVariationNodeDto(
      id: json['id'] as int,
      itemId: json['itemId'] as int? ?? 0,
      parentNodeId: json['parentNodeId'] as int?,
      kind: _nodeKindFromJson(json['kind'] as String? ?? 'property'),
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      position: json['position'] as int? ?? 0,
      isArchived: json['isArchived'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      children: (json['children'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                ItemVariationNodeDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      inputType: json['inputType'] as String? ?? 'Text',
      nameJoin: json['nameJoin'] as String? ?? '',
      numericMin: (json['numericMin'] as num?)?.toDouble(),
      numericMax: (json['numericMax'] as num?)?.toDouble(),
    );
  }

  ItemVariationNodeDefinition toDomain() {
    return ItemVariationNodeDefinition(
      id: id,
      itemId: itemId,
      parentNodeId: parentNodeId,
      kind: kind,
      name: name,
      code: code,
      displayName: displayName,
      position: position,
      isArchived: isArchived,
      createdAt: createdAt,
      updatedAt: updatedAt,
      children: children
          .map((entry) => entry.toDomain())
          .toList(growable: false),
      inputType: inputType,
      nameJoin: nameJoin,
      numericMin: numericMin,
      numericMax: numericMax,
    );
  }
}

class ItemDto {
  const ItemDto({
    required this.id,
    required this.name,
    required this.alias,
    required this.shortCode,
    required this.displayName,
    required this.quantity,
    required this.groupId,
    required this.unitId,
    required this.unitConversions,
    required this.namingFormat,
    required this.isArchived,
    required this.usageCount,
    required this.createdAt,
    required this.updatedAt,
    this.defaultPipelineId,
    this.defaultPipelineName,
    required this.variationTree,
    required this.propertySchema,
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
    this.blankWidthMm = 0,
    this.blankHeightMm = 0,
    this.penPaperBaseline,
  });

  final int id;
  final String name;
  final String alias;
  final String shortCode;
  final String displayName;
  final double quantity;
  final int groupId;
  final int unitId;
  final List<ItemUnitConversionDto> unitConversions;
  final List<String> namingFormat;
  final bool isArchived;
  final int usageCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? defaultPipelineId;
  final String? defaultPipelineName;
  final List<ItemVariationNodeDto> variationTree;
  final List<ItemPropertySchemaEntryDto> propertySchema;
  final int? baseItemId;
  final String photoUrl;
  final String cadFileKey;
  final String cadFileName;
  final List<ItemAttachmentDefinition> attachments;
  final List<ItemMachineLink> machines;
  final List<ItemDieLink> dies;
  final int? developedForClientId;
  final String developedForClientName;
  final List<int> combinationGroupIds;
  final bool availableForPurchase;

  /// The blank size this part is cut as, in millimetres.
  final double blankWidthMm;
  final double blankHeightMm;
  final PenPaperBaseline? penPaperBaseline;

  factory ItemDto.fromJson(Map<String, dynamic> json) {
    return ItemDto(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      alias: json['alias'] as String? ?? '',
      shortCode:
          json['shortCode'] as String? ?? json['short_code'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      quantity: (json['quantity'] as num? ?? 0).toDouble(),
      groupId: json['groupId'] as int? ?? 0,
      unitId: json['unitId'] as int? ?? 0,
      unitConversions: (json['unitConversions'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                ItemUnitConversionDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      namingFormat: (json['namingFormat'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      isArchived: json['isArchived'] as bool? ?? false,
      usageCount: json['usageCount'] as int? ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      defaultPipelineId: json['defaultPipelineId'] as String?,
      defaultPipelineName: json['defaultPipelineName'] as String?,
      variationTree: (json['variationTree'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                ItemVariationNodeDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      propertySchema: (json['propertySchema'] as List<dynamic>? ?? const [])
          .map(
            (item) => ItemPropertySchemaEntryDto.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(growable: false),
      baseItemId: json['baseItemId'] as int?,
      photoUrl: json['photoUrl'] as String? ?? '',
      cadFileKey: json['cadFileKey'] as String? ?? '',
      cadFileName: json['cadFileName'] as String? ?? '',
      attachments: (json['attachments'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (entry) => ItemAttachmentDefinition(
              id: entry['id'] as int?,
              label: entry['label'] as String? ?? '',
              objectKey: entry['objectKey'] as String? ?? '',
              fileName: entry['fileName'] as String? ?? '',
            ),
          )
          .toList(growable: false),
      machines: (json['machines'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (entry) => ItemMachineLink(
              id: entry['id']?.toString() ?? '',
              name: entry['name'] as String? ?? '',
              assetId: entry['assetId'] as String? ?? '',
            ),
          )
          .toList(growable: false),
      dies: (json['dies'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (entry) => ItemDieLink(
              id: entry['id']?.toString() ?? '',
              toolCode: entry['toolCode'] as String? ?? '',
            ),
          )
          .toList(growable: false),
      developedForClientId: json['developedForClientId'] as int?,
      developedForClientName: json['developedForClientName'] as String? ?? '',
      combinationGroupIds:
          (json['combinationGroupIds'] as List<dynamic>? ?? const [])
              .map((e) => e as int)
              .toList(growable: false),
      availableForPurchase: json['availableForPurchase'] as bool? ?? false,
      blankWidthMm: (json['blankWidthMm'] as num?)?.toDouble() ?? 0,
      blankHeightMm: (json['blankHeightMm'] as num?)?.toDouble() ?? 0,
      penPaperBaseline: json['penPaperBaseline'] is Map<String, dynamic>
          ? PenPaperBaseline.fromJson(
              json['penPaperBaseline'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  ItemDefinition toDomain() {
    return ItemDefinition(
      id: id,
      name: name,
      alias: alias,
      shortCode: shortCode,
      displayName: displayName,
      quantity: quantity,
      groupId: groupId,
      unitId: unitId,
      unitConversions: unitConversions
          .map((entry) => entry.toDomain())
          .toList(growable: false),
      namingFormat: namingFormat,
      isArchived: isArchived,
      usageCount: usageCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
      defaultPipelineId: defaultPipelineId,
      defaultPipelineName: defaultPipelineName,
      variationTree: variationTree
          .map((entry) => entry.toDomain())
          .toList(growable: false),
      propertySchema: propertySchema
          .map((entry) => entry.toDomain())
          .toList(growable: false),
      baseItemId: baseItemId,
      photoUrl: photoUrl,
      cadFileKey: cadFileKey,
      cadFileName: cadFileName,
      attachments: attachments,
      machines: machines,
      dies: dies,
      developedForClientId: developedForClientId,
      developedForClientName: developedForClientName,
      combinationGroupIds: combinationGroupIds,
      availableForPurchase: availableForPurchase,
      blankWidthMm: blankWidthMm,
      blankHeightMm: blankHeightMm,
      penPaperBaseline: penPaperBaseline,
    );
  }
}

class ItemPropertySchemaEntryDto {
  const ItemPropertySchemaEntryDto({
    required this.propertyKey,
    required this.displayName,
    required this.inputType,
    required this.mandatory,
    this.unitId,
    this.unitSymbol,
    this.unitLabel,
    this.sourceType,
    this.sourceGroupId,
    this.sourceGroupName,
    this.sourceItemIds = const [],
    this.sortOrder = 0,
  });

  final String propertyKey;
  final String displayName;
  final String inputType;
  final bool mandatory;
  final int? unitId;
  final String? unitSymbol;
  final String? unitLabel;
  final String? sourceType;
  final int? sourceGroupId;
  final String? sourceGroupName;
  final List<int> sourceItemIds;
  final int sortOrder;

  factory ItemPropertySchemaEntryDto.fromJson(Map<String, dynamic> json) {
    return ItemPropertySchemaEntryDto(
      propertyKey: json['propertyKey'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      inputType: json['inputType'] as String? ?? 'Text',
      mandatory: json['mandatory'] as bool? ?? false,
      unitId: (json['unitId'] as num?)?.toInt(),
      unitSymbol: json['unitSymbol'] as String?,
      unitLabel: json['unitLabel'] as String?,
      sourceType: json['sourceType'] as String?,
      sourceGroupId: (json['sourceGroupId'] as num?)?.toInt(),
      sourceGroupName: json['sourceGroupName'] as String?,
      sourceItemIds: (json['sourceItemIds'] as List<dynamic>? ?? const [])
          .map((entry) => (entry as num).toInt())
          .toList(growable: false),
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  ItemPropertySchemaEntry toDomain() {
    return ItemPropertySchemaEntry(
      propertyKey: propertyKey,
      displayName: displayName,
      inputType: inputType,
      mandatory: mandatory,
      unitId: unitId,
      unitSymbol: unitSymbol,
      unitLabel: unitLabel,
      sourceType: sourceType ?? 'manual',
      sourceGroupId: sourceGroupId,
      sourceGroupName: sourceGroupName,
      sourceItemIds: sourceItemIds,
      sortOrder: sortOrder,
    );
  }
}

class ItemUnitConversionDto {
  const ItemUnitConversionDto({
    required this.unitId,
    required this.unitName,
    required this.unitSymbol,
    required this.factorToPrimary,
  });

  final int unitId;
  final String unitName;
  final String unitSymbol;
  final double factorToPrimary;

  factory ItemUnitConversionDto.fromJson(Map<String, dynamic> json) {
    return ItemUnitConversionDto(
      unitId: json['unitId'] as int? ?? 0,
      unitName: json['unitName'] as String? ?? '',
      unitSymbol: json['unitSymbol'] as String? ?? '',
      factorToPrimary: (json['factorToPrimary'] as num? ?? 1).toDouble(),
    );
  }

  ItemUnitConversionDefinition toDomain() {
    return ItemUnitConversionDefinition(
      unitId: unitId,
      unitName: unitName,
      unitSymbol: unitSymbol,
      factorToPrimary: factorToPrimary,
    );
  }
}

class ItemResponse {
  const ItemResponse({required this.success, this.item, this.error});

  final bool success;
  final ItemDto? item;
  final String? error;

  factory ItemResponse.fromJson(Map<String, dynamic> json) {
    return ItemResponse(
      success: json['success'] as bool? ?? false,
      item: json['item'] == null
          ? null
          : ItemDto.fromJson(json['item'] as Map<String, dynamic>),
      error: json['error'] as String?,
    );
  }
}

class ItemsListResponse {
  const ItemsListResponse({required this.success, required this.items});

  final bool success;
  final List<ItemDto> items;

  factory ItemsListResponse.fromJson(Map<String, dynamic> json) {
    return ItemsListResponse(
      success: json['success'] as bool? ?? false,
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((item) => ItemDto.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class ItemVariationNodeRequest {
  const ItemVariationNodeRequest({
    required this.id,
    required this.parentNodeId,
    required this.kind,
    required this.name,
    required this.code,
    required this.displayName,
    required this.inputType,
    required this.nameJoin,
    required this.children,
    this.numericMin,
    this.numericMax,
  });

  final int? id;
  final int? parentNodeId;
  final ItemVariationNodeKind kind;
  final String name;
  final String code;
  final String displayName;
  final String inputType;
  final String nameJoin;
  final double? numericMin;
  final double? numericMax;
  final List<ItemVariationNodeRequest> children;

  factory ItemVariationNodeRequest.fromInput(ItemVariationNodeInput input) {
    return ItemVariationNodeRequest(
      id: input.id,
      parentNodeId: input.parentNodeId,
      kind: input.kind,
      name: input.name,
      code: input.code,
      displayName: input.displayName,
      inputType: input.inputType,
      nameJoin: input.nameJoin,
      numericMin: input.numericMin,
      numericMax: input.numericMax,
      children: input.children
          .map(ItemVariationNodeRequest.fromInput)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'parentNodeId': parentNodeId,
      'kind': _nodeKindToJson(kind),
      'name': name,
      'code': code,
      'displayName': displayName,
      'inputType': inputType,
      'nameJoin': nameJoin,
      'numericMin': numericMin,
      'numericMax': numericMax,
      'children': children
          .map((entry) => entry.toJson())
          .toList(growable: false),
    };
  }
}

class CreateItemRequest {
  const CreateItemRequest({
    required this.name,
    required this.alias,
    required this.displayName,
    required this.groupId,
    required this.unitId,
    required this.unitConversions,
    required this.namingFormat,
    required this.variationTree,
    this.defaultPipelineId,
    this.baseItemId,
    this.photoUrl = '',
    this.cadFileKey = '',
    this.cadFileName = '',
    this.attachments = const [],
    this.machineIds = const [],
    this.dieIds = const [],
    this.developedForClientId,
    this.availableForPurchase = false,
    this.blankWidthMm = 0,
    this.blankHeightMm = 0,
    this.penPaperBaseline,
  });

  final String name;
  final String alias;
  final String displayName;
  final int groupId;
  final int unitId;
  final List<ItemUnitConversionRequest> unitConversions;
  final List<String> namingFormat;
  final List<ItemVariationNodeRequest> variationTree;
  final String? defaultPipelineId;
  final int? baseItemId;
  final String photoUrl;
  final String cadFileKey;
  final String cadFileName;
  final List<ItemAttachmentInput> attachments;
  final List<String> machineIds;
  final List<String> dieIds;
  final int? developedForClientId;
  final bool availableForPurchase;

  /// The blank size this part is cut as, in millimetres.
  final double blankWidthMm;
  final double blankHeightMm;
  final PenPaperBaseline? penPaperBaseline;

  factory CreateItemRequest.fromInput(CreateItemInput input) {
    return CreateItemRequest(
      name: input.name,
      alias: input.alias,
      displayName: input.displayName,
      groupId: input.groupId,
      unitId: input.unitId,
      unitConversions: input.unitConversions
          .map(ItemUnitConversionRequest.fromInput)
          .toList(growable: false),
      namingFormat: input.namingFormat,
      variationTree: input.variationTree
          .map(ItemVariationNodeRequest.fromInput)
          .toList(growable: false),
      defaultPipelineId: input.defaultPipelineId,
      baseItemId: input.baseItemId,
      photoUrl: input.photoUrl,
      cadFileKey: input.cadFileKey,
      cadFileName: input.cadFileName,
      attachments: input.attachments,
      machineIds: input.machineIds,
      dieIds: input.dieIds,
      developedForClientId: input.developedForClientId,
      availableForPurchase: input.availableForPurchase,
      blankWidthMm: input.blankWidthMm,
      blankHeightMm: input.blankHeightMm,
      penPaperBaseline: input.penPaperBaseline,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'alias': alias,
      'displayName': displayName,
      'groupId': groupId,
      'unitId': unitId,
      'unitConversions': unitConversions
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'namingFormat': namingFormat,
      'variationTree': variationTree
          .map((entry) => entry.toJson())
          .toList(growable: false),
      if (defaultPipelineId != null) 'defaultPipelineId': defaultPipelineId,
      if (baseItemId != null) 'baseItemId': baseItemId,
      'photoUrl': photoUrl,
      'cadFileKey': cadFileKey,
      'cadFileName': cadFileName,
      'attachments': attachments
          .map(
            (entry) => <String, dynamic>{
              'label': entry.label,
              'objectKey': entry.objectKey,
              'fileName': entry.fileName,
            },
          )
          .toList(growable: false),
      'machineIds': machineIds,
      'dieIds': dieIds,
      'developedForClientId': developedForClientId,
      'availableForPurchase': availableForPurchase,
      'blankWidthMm': blankWidthMm,
      'blankHeightMm': blankHeightMm,
      // Omitted rather than sent as null: the server preserves whatever is
      // already recorded when the key is absent, and clears it on an explicit
      // null. The editor only sends a baseline it actually has.
      if (penPaperBaseline != null)
        'penPaperBaseline': penPaperBaseline!.toJson(),
    };
  }
}

class UpdateItemRequest {
  const UpdateItemRequest({
    required this.name,
    required this.alias,
    required this.displayName,
    required this.groupId,
    required this.unitId,
    required this.unitConversions,
    required this.namingFormat,
    required this.variationTree,
    this.defaultPipelineId,
    this.baseItemId,
    this.photoUrl = '',
    this.cadFileKey = '',
    this.cadFileName = '',
    this.attachments = const [],
    this.machineIds = const [],
    this.dieIds = const [],
    this.developedForClientId,
    this.availableForPurchase = false,
    this.blankWidthMm = 0,
    this.blankHeightMm = 0,
    this.penPaperBaseline,
  });

  final String name;
  final String alias;
  final String displayName;
  final int groupId;
  final int unitId;
  final List<ItemUnitConversionRequest> unitConversions;
  final List<String> namingFormat;
  final List<ItemVariationNodeRequest> variationTree;
  final String? defaultPipelineId;
  final int? baseItemId;
  final String photoUrl;
  final String cadFileKey;
  final String cadFileName;
  final List<ItemAttachmentInput> attachments;
  final List<String> machineIds;
  final List<String> dieIds;
  final int? developedForClientId;
  final bool availableForPurchase;

  /// The blank size this part is cut as, in millimetres.
  final double blankWidthMm;
  final double blankHeightMm;
  final PenPaperBaseline? penPaperBaseline;

  factory UpdateItemRequest.fromInput(UpdateItemInput input) {
    return UpdateItemRequest(
      name: input.name,
      alias: input.alias,
      displayName: input.displayName,
      groupId: input.groupId,
      unitId: input.unitId,
      unitConversions: input.unitConversions
          .map(ItemUnitConversionRequest.fromInput)
          .toList(growable: false),
      namingFormat: input.namingFormat,
      variationTree: input.variationTree
          .map(ItemVariationNodeRequest.fromInput)
          .toList(growable: false),
      defaultPipelineId: input.defaultPipelineId,
      baseItemId: input.baseItemId,
      photoUrl: input.photoUrl,
      cadFileKey: input.cadFileKey,
      cadFileName: input.cadFileName,
      attachments: input.attachments,
      machineIds: input.machineIds,
      dieIds: input.dieIds,
      developedForClientId: input.developedForClientId,
      availableForPurchase: input.availableForPurchase,
      blankWidthMm: input.blankWidthMm,
      blankHeightMm: input.blankHeightMm,
      penPaperBaseline: input.penPaperBaseline,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'alias': alias,
      'displayName': displayName,
      'groupId': groupId,
      'unitId': unitId,
      'unitConversions': unitConversions
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'namingFormat': namingFormat,
      'variationTree': variationTree
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'defaultPipelineId': defaultPipelineId,
      if (baseItemId != null) 'baseItemId': baseItemId,
      'photoUrl': photoUrl,
      'cadFileKey': cadFileKey,
      'cadFileName': cadFileName,
      'attachments': attachments
          .map(
            (entry) => <String, dynamic>{
              'label': entry.label,
              'objectKey': entry.objectKey,
              'fileName': entry.fileName,
            },
          )
          .toList(growable: false),
      'machineIds': machineIds,
      'dieIds': dieIds,
      'developedForClientId': developedForClientId,
      'availableForPurchase': availableForPurchase,
      'blankWidthMm': blankWidthMm,
      'blankHeightMm': blankHeightMm,
      // Omitted rather than sent as null: the server preserves whatever is
      // already recorded when the key is absent, and clears it on an explicit
      // null. The editor only sends a baseline it actually has.
      if (penPaperBaseline != null)
        'penPaperBaseline': penPaperBaseline!.toJson(),
    };
  }
}

class ItemUnitConversionRequest {
  const ItemUnitConversionRequest({
    required this.unitId,
    required this.factorToPrimary,
  });

  final int unitId;
  final double factorToPrimary;

  factory ItemUnitConversionRequest.fromInput(ItemUnitConversionInput input) {
    return ItemUnitConversionRequest(
      unitId: input.unitId,
      factorToPrimary: input.factorToPrimary,
    );
  }

  Map<String, dynamic> toJson() {
    return {'unitId': unitId, 'factorToPrimary': factorToPrimary};
  }
}
