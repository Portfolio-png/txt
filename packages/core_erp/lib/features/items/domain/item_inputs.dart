import 'item_definition.dart';

class ItemUnitConversionInput {
  const ItemUnitConversionInput({
    required this.unitId,
    required this.factorToPrimary,
  });

  final int unitId;
  final double factorToPrimary;
}

class ItemVariationNodeInput {
  const ItemVariationNodeInput({
    this.id,
    this.parentNodeId,
    required this.kind,
    required this.name,
    this.code = '',
    this.displayName = '',
    this.children = const [],
    this.isMeasurable = false,
    this.unitId,
    this.allowedUnitIds = const <int>[],
  });

  final int? id;
  final int? parentNodeId;
  final ItemVariationNodeKind kind;
  final String name;
  final String code;
  final String displayName;
  final List<ItemVariationNodeInput> children;

  /// Enhancement 3 — measurable flag (property nodes).
  final bool isMeasurable;

  /// Intrinsic unit (value leaves under a measurable property).
  final int? unitId;

  /// Allowed units for the unit dropdown (measurable property nodes).
  final List<int> allowedUnitIds;
}

class CreateItemInput {
  const CreateItemInput({
    required this.name,
    this.alias = '',
    required this.displayName,
    required this.groupId,
    required this.unitId,
    this.unitConversions = const [],
    this.namingFormat = const [],
    this.variationTree = const [],
    this.defaultPipelineId,
    this.baseItemId,
    this.photoUrl = '',
  });

  final String name;
  final String alias;
  final String displayName;
  final int groupId;
  final int unitId;
  final List<ItemUnitConversionInput> unitConversions;
  final List<String> namingFormat;
  final List<ItemVariationNodeInput> variationTree;
  final String? defaultPipelineId;
  final int? baseItemId;
  final String photoUrl;
}

class UpdateItemInput {
  const UpdateItemInput({
    required this.id,
    required this.name,
    this.alias = '',
    required this.displayName,
    required this.groupId,
    required this.unitId,
    this.unitConversions = const [],
    this.namingFormat = const [],
    this.variationTree = const [],
    this.defaultPipelineId,
    this.baseItemId,
    this.photoUrl = '',
  });

  final int id;
  final String name;
  final String alias;
  final String displayName;
  final int groupId;
  final int unitId;
  final List<ItemUnitConversionInput> unitConversions;
  final List<String> namingFormat;
  final List<ItemVariationNodeInput> variationTree;
  final String? defaultPipelineId;
  final int? baseItemId;
  final String photoUrl;
}
