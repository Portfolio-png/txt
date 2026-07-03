/// Quantities-only production report for an order. Rates/costs are
/// intentionally absent — the sheet renders blanks the user fills on paper.
class OrderProductionReport {
  const OrderProductionReport({
    required this.orderNo,
    required this.clientName,
    required this.poNumber,
    required this.items,
    required this.runs,
  });

  final String orderNo;
  final String clientName;
  final String poNumber;
  final List<OrderReportItem> items;
  final List<OrderReportRun> runs;

  factory OrderProductionReport.fromJson(Map<String, dynamic> json) {
    return OrderProductionReport(
      orderNo: json['orderNo'] as String? ?? '',
      clientName: json['clientName'] as String? ?? '',
      poNumber: json['poNumber'] as String? ?? '',
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((e) => OrderReportItem.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      runs: (json['runs'] as List<dynamic>? ?? const [])
          .map((e) => OrderReportRun.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class OrderReportItem {
  const OrderReportItem({
    required this.orderItemId,
    required this.itemName,
    required this.variationPathLabel,
    required this.quantity,
    required this.unitSymbol,
    required this.unitPrice,
  });

  final int orderItemId;
  final String itemName;
  final String variationPathLabel;
  final double quantity;
  final String unitSymbol;
  final double unitPrice;

  factory OrderReportItem.fromJson(Map<String, dynamic> json) {
    return OrderReportItem(
      orderItemId: (json['orderItemId'] as num?)?.toInt() ?? 0,
      itemName: json['itemName'] as String? ?? '',
      variationPathLabel: json['variationPathLabel'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      unitSymbol: json['unitSymbol'] as String? ?? 'pcs',
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
    );
  }
}

class OrderReportRun {
  const OrderReportRun({
    required this.runId,
    required this.runName,
    required this.status,
    required this.orderItemId,
    required this.templateName,
    required this.stages,
  });

  final String runId;
  final String runName;
  final String status;
  final int? orderItemId;
  final String templateName;
  final List<OrderReportStage> stages;

  factory OrderReportRun.fromJson(Map<String, dynamic> json) {
    return OrderReportRun(
      runId: json['runId'] as String? ?? '',
      runName: json['runName'] as String? ?? '',
      status: json['status'] as String? ?? '',
      orderItemId: (json['orderItemId'] as num?)?.toInt(),
      templateName: json['templateName'] as String? ?? '',
      stages: (json['stages'] as List<dynamic>? ?? const [])
          .map((e) => OrderReportStage.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class OrderReportStage {
  const OrderReportStage({
    required this.name,
    required this.stageIndex,
    required this.material,
    required this.materialUnit,
    required this.machine,
    required this.dieId,
    required this.plannedHours,
    this.allotted,
    this.output,
    this.leftover,
    this.scrap,
    this.inputTime,
    this.outputTime,
    this.actualHours,
  });

  final String name;
  final int stageIndex;
  final String material;
  final String materialUnit;
  final String machine;
  final String dieId;
  final double plannedHours;
  final double? allotted;
  final double? output;
  final double? leftover;
  final double? scrap;
  final DateTime? inputTime;
  final DateTime? outputTime;
  final double? actualHours;

  /// Reconciled hours if times are committed, else seed/planned fallback.
  double? get workedHours {
    if (inputTime != null && outputTime != null) {
      final minutes = outputTime!.difference(inputTime!).inMinutes;
      if (minutes > 0) return minutes / 60.0;
    }
    return actualHours;
  }

  factory OrderReportStage.fromJson(Map<String, dynamic> json) {
    return OrderReportStage(
      name: json['name'] as String? ?? '',
      stageIndex: (json['stageIndex'] as num?)?.toInt() ?? 0,
      material: json['material'] as String? ?? '',
      materialUnit: json['materialUnit'] as String? ?? '',
      machine: json['machine'] as String? ?? '',
      dieId: json['dieId'] as String? ?? '',
      plannedHours: (json['plannedHours'] as num?)?.toDouble() ?? 0,
      allotted: (json['allotted'] as num?)?.toDouble(),
      output: (json['output'] as num?)?.toDouble(),
      leftover: (json['leftover'] as num?)?.toDouble(),
      scrap: (json['scrap'] as num?)?.toDouble(),
      inputTime: DateTime.tryParse(json['inputTime'] as String? ?? ''),
      outputTime: DateTime.tryParse(json['outputTime'] as String? ?? ''),
      actualHours: (json['actualHours'] as num?)?.toDouble(),
    );
  }
}
