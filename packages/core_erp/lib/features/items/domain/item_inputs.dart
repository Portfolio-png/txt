import 'item_definition.dart';

class ItemUnitConversionInput {
  const ItemUnitConversionInput({
    required this.unitId,
    required this.factorToPrimary,
  });

  final int unitId;
  final double factorToPrimary;
}

class ItemAttachmentInput {
  const ItemAttachmentInput({
    required this.label,
    required this.objectKey,
    required this.fileName,
  });

  final String label;
  final String objectKey;
  final String fileName;
}

class ItemVariationNodeInput {
  const ItemVariationNodeInput({
    this.id,
    this.parentNodeId,
    required this.kind,
    required this.name,
    this.code = '',
    this.displayName = '',
    this.inputType = 'Text',
    this.nameJoin = '',
    this.children = const [],
  });

  final int? id;
  final int? parentNodeId;
  final ItemVariationNodeKind kind;
  final String name;
  final String code;
  final String displayName;
  final String inputType;
  final String nameJoin;
  final List<ItemVariationNodeInput> children;
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
    this.cadFileKey = '',
    this.cadFileName = '',
    this.attachments = const [],
    this.machineIds = const [],
    this.dieIds = const [],
    this.developedForClientId,
    this.availableForPurchase = false,
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
  final String cadFileKey;
  final String cadFileName;
  final List<ItemAttachmentInput> attachments;
  final List<String> machineIds;
  final List<String> dieIds;
  final int? developedForClientId;
  final bool availableForPurchase;
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
    this.cadFileKey = '',
    this.cadFileName = '',
    this.attachments = const [],
    this.machineIds = const [],
    this.dieIds = const [],
    this.developedForClientId,
    this.availableForPurchase = false,
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
  final String cadFileKey;
  final String cadFileName;
  final List<ItemAttachmentInput> attachments;
  final List<String> machineIds;
  final List<String> dieIds;
  final int? developedForClientId;
  final bool availableForPurchase;
}
