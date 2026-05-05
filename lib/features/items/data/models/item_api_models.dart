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
    );
  }
}

class ItemDto {
  const ItemDto({
    required this.id,
    required this.name,
    required this.alias,
    required this.displayName,
    required this.quantity,
    required this.groupId,
    required this.unitId,
    required this.namingFormat,
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
  final List<ItemVariationNodeDto> variationTree;

  factory ItemDto.fromJson(Map<String, dynamic> json) {
    return ItemDto(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      alias: json['alias'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      quantity: (json['quantity'] as num? ?? 0).toDouble(),
      groupId: json['groupId'] as int? ?? 0,
      unitId: json['unitId'] as int? ?? 0,
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
      variationTree: (json['variationTree'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                ItemVariationNodeDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }

  ItemDefinition toDomain() {
    return ItemDefinition(
      id: id,
      name: name,
      alias: alias,
      displayName: displayName,
      quantity: quantity,
      groupId: groupId,
      unitId: unitId,
      namingFormat: namingFormat,
      isArchived: isArchived,
      usageCount: usageCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
      variationTree: variationTree
          .map((entry) => entry.toDomain())
          .toList(growable: false),
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
    required this.children,
  });

  final int? id;
  final int? parentNodeId;
  final ItemVariationNodeKind kind;
  final String name;
  final String code;
  final String displayName;
  final List<ItemVariationNodeRequest> children;

  factory ItemVariationNodeRequest.fromInput(ItemVariationNodeInput input) {
    return ItemVariationNodeRequest(
      id: input.id,
      parentNodeId: input.parentNodeId,
      kind: input.kind,
      name: input.name,
      code: input.code,
      displayName: input.displayName,
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
    required this.quantity,
    required this.groupId,
    required this.unitId,
    required this.namingFormat,
    required this.variationTree,
  });

  final String name;
  final String alias;
  final String displayName;
  final double quantity;
  final int groupId;
  final int unitId;
  final List<String> namingFormat;
  final List<ItemVariationNodeRequest> variationTree;

  factory CreateItemRequest.fromInput(CreateItemInput input) {
    return CreateItemRequest(
      name: input.name,
      alias: input.alias,
      displayName: input.displayName,
      quantity: input.quantity,
      groupId: input.groupId,
      unitId: input.unitId,
      namingFormat: input.namingFormat,
      variationTree: input.variationTree
          .map(ItemVariationNodeRequest.fromInput)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'alias': alias,
      'displayName': displayName,
      'quantity': quantity,
      'groupId': groupId,
      'unitId': unitId,
      'namingFormat': namingFormat,
      'variationTree': variationTree
          .map((entry) => entry.toJson())
          .toList(growable: false),
    };
  }
}

class UpdateItemRequest {
  const UpdateItemRequest({
    required this.name,
    required this.alias,
    required this.displayName,
    required this.quantity,
    required this.groupId,
    required this.unitId,
    required this.namingFormat,
    required this.variationTree,
  });

  final String name;
  final String alias;
  final String displayName;
  final double quantity;
  final int groupId;
  final int unitId;
  final List<String> namingFormat;
  final List<ItemVariationNodeRequest> variationTree;

  factory UpdateItemRequest.fromInput(UpdateItemInput input) {
    return UpdateItemRequest(
      name: input.name,
      alias: input.alias,
      displayName: input.displayName,
      quantity: input.quantity,
      groupId: input.groupId,
      unitId: input.unitId,
      namingFormat: input.namingFormat,
      variationTree: input.variationTree
          .map(ItemVariationNodeRequest.fromInput)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'alias': alias,
      'displayName': displayName,
      'quantity': quantity,
      'groupId': groupId,
      'unitId': unitId,
      'namingFormat': namingFormat,
      'variationTree': variationTree
          .map((entry) => entry.toJson())
          .toList(growable: false),
    };
  }
}
