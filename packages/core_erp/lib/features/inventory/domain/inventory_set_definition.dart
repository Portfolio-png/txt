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
    this.groupId,
    this.groupName,
    this.groupIsArchived = false,
    this.version = 0,
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

  /// The group the set is filed under, and the name to show for it. Null for a
  /// set nobody has filed — a set produced by an assembly step is always one.
  ///
  /// The name travels with the set so a display surface never has to reach for
  /// GroupsProvider to label it.
  final int? groupId;
  final String? groupName;

  /// True when that group has since been archived, so a card can say so rather
  /// than present a retired group as a live one.
  final bool groupIsArchived;

  /// What this set's state is numbered, bumped by every save.
  ///
  /// A save that carries the version it was opened at is refused when the set
  /// has moved on — which is the only thing standing between two people with
  /// the same set open and one of them silently erasing the other's lines.
  /// Defaulted rather than required: most of the places that build one of these
  /// by hand have no version to give.
  final int version;
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
    this.groupId,
    this.groupIdSpecified = false,
    this.expectedVersion,
  });

  final int? id;
  final String name;
  final List<SaveInventorySetLineInput> lines;

  /// The set's photo, as the read URL returned by the upload. Empty clears it.
  final String photoUrl;

  /// The group to file the set under, and whether this save is speaking about
  /// the group at all.
  ///
  /// The save is a full replace, but not every caller fills the whole form: the
  /// "add spawned items to a set" path in the items master sends a name and
  /// lines only. Were a null groupId read as "clear", adding items to a set
  /// would silently unfile it. So only a save that sets [groupIdSpecified]
  /// touches the group; [groupId] null with the flag set means "clear it".
  final int? groupId;
  final bool groupIdSpecified;

  /// The version the caller opened this set at, when it knows one.
  ///
  /// Sent only when non-null, and then the server refuses the save if the set
  /// has changed since. Null means "do not check" — which is right for a create
  /// (there is nothing to conflict with) and for a caller that never read the
  /// set in the first place. No tri-state is needed: unknown and absent mean
  /// the same thing here.
  final int? expectedVersion;
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
