/// Formats a quantity: whole numbers drop the decimals, fractions show two.
String fmtQty(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

/// A discrete chunk of material in flight through a pipeline run.
///
/// Unlike the monolithic per-node quantity tracked by `nodeMetrics`, a batch
/// is a first-class token that sits at one node and can be split off and moved
/// downstream independently — so Batch A can be at stage 3 while Batch B is
/// still at stage 1. Splits keep [parentBatchId] for lineage.
class MaterialBatch {
  const MaterialBatch({
    required this.id,
    required this.barcode,
    required this.materialName,
    required this.quantity,
    required this.currentNodeId,
    this.unit,
    this.status = atNode,
    this.parentBatchId,
    this.createdAt,
    this.scrap = 0,
    this.leftover = 0,
  });

  static const String atNode = 'atNode';
  static const String inProcess = 'inProcess';
  static const String consumed = 'consumed';

  final String id;
  final String barcode;
  final String materialName;
  final double quantity;
  final String? unit;

  /// The node this batch is currently parked at / being worked on.
  final String currentNodeId;

  /// One of [atNode], [inProcess], [consumed].
  final String status;

  /// The batch this one was split off from, if any.
  final String? parentBatchId;
  final DateTime? createdAt;

  /// Cumulative scrap and leftover declared against this batch during stage
  /// reconciliations as it advanced.
  final double scrap;
  final double leftover;

  bool get isLive => status != consumed;

  String get unitLabel => unit != null && unit!.isNotEmpty ? unit! : '';

  MaterialBatch copyWith({
    String? id,
    String? barcode,
    String? materialName,
    double? quantity,
    String? currentNodeId,
    String? unit,
    String? status,
    String? parentBatchId,
    DateTime? createdAt,
    double? scrap,
    double? leftover,
  }) {
    return MaterialBatch(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      materialName: materialName ?? this.materialName,
      quantity: quantity ?? this.quantity,
      currentNodeId: currentNodeId ?? this.currentNodeId,
      unit: unit ?? this.unit,
      status: status ?? this.status,
      parentBatchId: parentBatchId ?? this.parentBatchId,
      createdAt: createdAt ?? this.createdAt,
      scrap: scrap ?? this.scrap,
      leftover: leftover ?? this.leftover,
    );
  }

  factory MaterialBatch.fromJson(Map<String, dynamic> json) {
    return MaterialBatch(
      id: json['id'] as String? ?? '',
      barcode: json['barcode'] as String? ?? '',
      materialName: json['materialName'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      currentNodeId: json['currentNodeId'] as String? ?? '',
      unit: json['unit'] as String?,
      status: json['status'] as String? ?? atNode,
      parentBatchId: json['parentBatchId'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      scrap: (json['scrap'] as num?)?.toDouble() ?? 0,
      leftover: (json['leftover'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'barcode': barcode,
      'materialName': materialName,
      'quantity': quantity,
      'currentNodeId': currentNodeId,
      if (unit != null) 'unit': unit,
      'status': status,
      if (parentBatchId != null) 'parentBatchId': parentBatchId,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (scrap != 0) 'scrap': scrap,
      if (leftover != 0) 'leftover': leftover,
    };
  }
}
