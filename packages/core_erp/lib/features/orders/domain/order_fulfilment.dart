/// One delivery challan that took part of an order line out of the building.
///
/// [cumulativeQty] is where the order stood once this challan was issued — the
/// position its checkpoint sits at on the fulfilment bar. It is computed
/// server-side from the same rows the total comes from, so a checkpoint can
/// never land somewhere the total disagrees with.
class OrderDelivery {
  const OrderDelivery({
    required this.challanId,
    required this.challanNo,
    required this.date,
    required this.status,
    required this.clientName,
    required this.quantity,
    required this.weight,
    required this.cumulativeQty,
  });

  /// The numeric id — what opens the challan. [challanNo] is a display label
  /// only and cannot be used to fetch one.
  final int challanId;
  final String challanNo;
  final DateTime? date;
  final String status;
  final String clientName;
  final double quantity;
  final double weight;
  final double cumulativeQty;

  factory OrderDelivery.fromJson(Map<String, dynamic> json) {
    final rawDate = json['date'];
    return OrderDelivery(
      challanId: (json['challanId'] as num?)?.toInt() ?? 0,
      challanNo: json['challanNo'] as String? ?? '',
      date: rawDate is String ? DateTime.tryParse(rawDate) : null,
      status: json['status'] as String? ?? '',
      clientName: json['clientName'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      weight: (json['weight'] as num?)?.toDouble() ?? 0,
      cumulativeQty: (json['cumulativeQty'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Where one order line actually stands: how much was ordered, how much has
/// left the building on a delivery challan, and how much the floor has
/// reconciled as produced.
///
/// [producedQty] carries its own [producedUnit] and is deliberately NOT
/// converted into [orderedUnit]. Floor reconciliation settles in kilograms
/// while order lines are usually pieces, and no conversion between them exists
/// — inventing one would misreport fulfilment.
class OrderFulfilment {
  const OrderFulfilment({
    required this.orderItemId,
    required this.orderNo,
    required this.orderedQty,
    required this.orderedUnit,
    required this.deliveredQty,
    required this.producedQty,
    required this.producedUnit,
    required this.scrapQty,
    required this.runCount,
    required this.runStatus,
    required this.templateName,
    this.deliveries = const <OrderDelivery>[],
    this.startedAt,
    this.completedAt,
  });

  final int orderItemId;
  final String orderNo;
  final double orderedQty;
  final String orderedUnit;
  final double deliveredQty;
  final double producedQty;
  final String producedUnit;
  final double scrapQty;

  /// How many pipeline runs are attached. Zero means the line has no route.
  final int runCount;

  /// 'none' | 'notStarted' | 'inProgress' | 'completed'
  final String runStatus;
  final String templateName;

  /// Every issued delivery challan against this line, oldest first.
  final List<OrderDelivery> deliveries;
  final DateTime? startedAt;
  final DateTime? completedAt;

  bool get hasPipeline => runCount > 0;

  /// What to call the produced quantity. The backend leaves [producedUnit]
  /// empty when the terminal stage never declared one — say "units" rather
  /// than guessing a unit the floor did not report.
  String get producedUnitLabel =>
      producedUnit.trim().isEmpty ? 'units' : producedUnit.trim();

  bool get hasFloorData => producedQty > 0;

  /// Delivered against ordered, 0..1.
  double get deliveredProgress =>
      orderedQty <= 0 ? 0 : (deliveredQty / orderedQty).clamp(0.0, 1.0);

  /// Produced against ordered — only meaningful when the floor reports in the
  /// same unit the line was ordered in.
  double? get producedProgress {
    if (orderedQty <= 0 || producedQty <= 0) return null;
    if (producedUnit.trim().toLowerCase() != orderedUnit.trim().toLowerCase()) {
      return null;
    }
    return (producedQty / orderedQty).clamp(0.0, 1.0);
  }

  factory OrderFulfilment.fromJson(Map<String, dynamic> json) {
    DateTime? parse(String key) {
      final raw = json[key];
      return raw is String ? DateTime.tryParse(raw) : null;
    }

    return OrderFulfilment(
      orderItemId: (json['orderItemId'] as num?)?.toInt() ?? 0,
      orderNo: json['orderNo'] as String? ?? '',
      orderedQty: (json['orderedQty'] as num?)?.toDouble() ?? 0,
      orderedUnit: json['orderedUnit'] as String? ?? '',
      deliveredQty: (json['deliveredQty'] as num?)?.toDouble() ?? 0,
      producedQty: (json['producedQty'] as num?)?.toDouble() ?? 0,
      producedUnit: json['producedUnit'] as String? ?? '',
      scrapQty: (json['scrapQty'] as num?)?.toDouble() ?? 0,
      runCount: (json['runCount'] as num?)?.toInt() ?? 0,
      runStatus: json['runStatus'] as String? ?? 'none',
      templateName: json['templateName'] as String? ?? '',
      deliveries: (json['deliveries'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(OrderDelivery.fromJson)
          .toList(growable: false),
      startedAt: parse('startedAt'),
      completedAt: parse('completedAt'),
    );
  }
}
