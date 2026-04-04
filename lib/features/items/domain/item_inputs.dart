import 'item_definition.dart';

class ItemVariationNodeInput {
  const ItemVariationNodeInput({
    this.id,
    this.parentNodeId,
    required this.kind,
    required this.name,
    this.displayName = '',
    this.children = const [],
  });

  final int? id;
  final int? parentNodeId;
  final ItemVariationNodeKind kind;
  final String name;
  final String displayName;
  final List<ItemVariationNodeInput> children;
}

class CreateItemInput {
  const CreateItemInput({
    required this.name,
    this.alias = '',
    required this.displayName,
    required this.quantity,
    required this.groupId,
    required this.unitId,
    this.variationTree = const [],
  });

  final String name;
  final String alias;
  final String displayName;
  final double quantity;
  final int groupId;
  final int unitId;
  final List<ItemVariationNodeInput> variationTree;
}

class UpdateItemInput {
  const UpdateItemInput({
    required this.id,
    required this.name,
    this.alias = '',
    required this.displayName,
    required this.quantity,
    required this.groupId,
    required this.unitId,
    this.variationTree = const [],
  });

  final int id;
  final String name;
  final String alias;
  final String displayName;
  final double quantity;
  final int groupId;
  final int unitId;
  final List<ItemVariationNodeInput> variationTree;
}
