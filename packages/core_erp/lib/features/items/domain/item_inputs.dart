import '../../production_pipelines/domain/pen_paper_baseline.dart';
import 'developed_for.dart';
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
    this.numericMin,
    this.numericMax,
    this.materialTypeId,
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

  /// Inclusive bounds for a 'Numeric' property; null means open-ended.
  final double? numericMin;
  final double? numericMax;

  /// Which material type a value under a 'Material' property stands for.
  final int? materialTypeId;
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
    this.penPaperBaseline,
    this.blankWidthMm = 0,
    this.blankHeightMm = 0,
    this.partNo,
    this.partCode,
    this.developedFor,
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

  /// The blank size this part is cut as, in millimetres. Zero when unmeasured.
  final double blankWidthMm;
  final double blankHeightMm;

  /// The number this part is issued and the code derived from it.
  ///
  /// Null means "say nothing about identity", and the server then keeps what is
  /// already stamped. That matters because this input is rebuilt wholesale by
  /// every preserving save: a non-null default would ship on each of them and
  /// wipe the identity the first time anyone edited a variation.
  final int? partNo;
  final String? partCode;

  /// Who this part was developed for, when, and what was quoted.
  ///
  /// **Null means say nothing**, and the server then keeps whatever is
  /// recorded. Clearing it is a present-but-empty block
  /// ([DevelopedFor.empty]) — the object carries that distinction itself,
  /// which is why this needs no `specified` flag of the kind [partNo] has.
  final DevelopedFor? developedFor;


  /// Sample run recorded on this item. Null leaves whatever is already stored
  /// untouched — the server preserves the column when the field is absent.
  final PenPaperBaseline? penPaperBaseline;
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
    this.penPaperBaseline,
    this.blankWidthMm = 0,
    this.blankHeightMm = 0,
    this.partNo,
    this.partCode,
    this.partIdentitySpecified = false,
    this.developedFor,
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

  /// The blank size this part is cut as, in millimetres. Zero when unmeasured.
  final double blankWidthMm;
  final double blankHeightMm;

  /// The number this part is issued and the code derived from it.
  ///
  /// Null means "say nothing about identity", and the server then keeps what is
  /// already stamped. That matters because this input is rebuilt wholesale by
  /// every preserving save: a non-null default would ship on each of them and
  /// wipe the identity the first time anyone edited a variation.
  final int? partNo;
  final String? partCode;

  /// True when this save speaks about the part's identity at all, in which case
  /// both keys are sent — and a null [partNo] or an empty [partCode] then means
  /// **clear it**, not "leave it alone".
  ///
  /// Only the item editor sets this. Without it there is no way to remove a
  /// number, because an absent key is how every other caller says "preserve".
  /// Deliberately absent from [CreateItemInput]: the server only stamps a new
  /// part when neither key arrives, so sending them on a create would turn the
  /// automatic stamp off.
  final bool partIdentitySpecified;

  /// Who this part was developed for, when, and what was quoted.
  ///
  /// **Null means say nothing**, and the server then keeps whatever is
  /// recorded. Clearing it is a present-but-empty block
  /// ([DevelopedFor.empty]) — the object carries that distinction itself,
  /// which is why this needs no `specified` flag of the kind [partNo] has.
  final DevelopedFor? developedFor;


  /// Sample run recorded on this item. Null leaves whatever is already stored
  /// untouched — the server preserves the column when the field is absent.
  final PenPaperBaseline? penPaperBaseline;
}
