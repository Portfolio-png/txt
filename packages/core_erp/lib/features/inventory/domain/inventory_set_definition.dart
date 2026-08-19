class InventorySetDefinition {
  const InventorySetDefinition({
    required this.id,
    required this.name,
    required this.totalItemCount,
    required this.createdAt,
    required this.updatedAt,
    required this.lines,
    this.isTemporary = false,
    this.originRunId,
    this.originNodeId,
    this.sourceSetId,
    this.producedAt,
    this.onHandQty,
    this.materialBarcode,
    this.photoUrl,
  });

  final int id;
  final String name;
  final int totalItemCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<InventorySetLineDefinition> lines;

  /// A set an assembly step produced, rather than one someone defined. Its
  /// composition is what actually fed that step on that run.
  final bool isTemporary;

  /// The production run and assembly step it came off.
  final String? originRunId;
  final String? originNodeId;

  /// The defined set its composition matched, if any — that is where the
  /// recognisable half of its name comes from.
  final int? sourceSetId;

  /// When the stage was reconciled, i.e. when the set became real.
  final DateTime? producedAt;

  /// Stock this set actually holds, and the barcode its ledger lives under.
  /// Both null for a set defined by hand — those hold no stock.
  final double? onHandQty;
  final String? materialBarcode;

  /// The set's own photo, shown on its card in the Items master. Null when none
  /// has been uploaded.
  final String? photoUrl;
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
    this.photoUrl = '',
  });

  final int? id;
  final String name;
  final List<SaveInventorySetLineInput> lines;

  /// The set's photo, as the read URL returned by the upload. Empty clears it.
  final String photoUrl;
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
