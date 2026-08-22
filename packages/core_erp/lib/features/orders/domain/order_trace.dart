/// A logged customer return / defect event on an order — the trigger for the
/// backward QC lineage trace.
class OrderReturn {
  const OrderReturn({
    required this.id,
    required this.returnNo,
    required this.orderNo,
    this.orderItemId,
    this.quantity = 0,
    this.unit = 'pcs',
    this.reasonCode = 'defect',
    this.defectDescription = '',
    this.status = 'open',
    this.returnedBarcode = '',
    this.pipelineRunId,
    this.loggedBy = '',
  });

  final int id;
  final String returnNo;
  final String orderNo;
  final int? orderItemId;
  final double quantity;
  final String unit;
  final String reasonCode;
  final String defectDescription;
  final String status;
  final String returnedBarcode;
  final String? pipelineRunId;
  final String loggedBy;

  factory OrderReturn.fromJson(Map<String, dynamic> json) {
    return OrderReturn(
      id: (json['id'] as num?)?.toInt() ?? 0,
      returnNo: (json['returnNo'] ?? json['return_no']) as String? ?? '',
      orderNo: (json['orderNo'] ?? json['order_no']) as String? ?? '',
      orderItemId: (json['orderItemId'] ?? json['order_item_id']) as int?,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      unit: json['unit'] as String? ?? 'pcs',
      reasonCode:
          (json['reasonCode'] ?? json['reason_code']) as String? ?? 'defect',
      defectDescription:
          (json['defectDescription'] ?? json['defect_description'])
              as String? ??
          '',
      status: json['status'] as String? ?? 'open',
      returnedBarcode:
          (json['returnedBarcode'] ?? json['returned_barcode']) as String? ??
          '',
      pipelineRunId:
          (json['pipelineRunId'] ?? json['pipeline_run_id']) as String?,
      loggedBy: (json['loggedBy'] ?? json['logged_by']) as String? ?? '',
    );
  }
}

/// Payload to log a new return/defect.
class CreateOrderReturnInput {
  const CreateOrderReturnInput({
    required this.orderNo,
    this.orderItemId,
    this.quantity = 0,
    this.unit = 'pcs',
    this.reasonCode = 'defect',
    this.defectDescription = '',
    this.returnedBarcode = '',
  });

  final String orderNo;
  final int? orderItemId;
  final double quantity;
  final String unit;
  final String reasonCode;
  final String defectDescription;
  final String returnedBarcode;

  Map<String, dynamic> toJson() => {
    if (orderItemId != null) 'orderItemId': orderItemId,
    'quantity': quantity,
    'unit': unit,
    'reasonCode': reasonCode,
    if (defectDescription.trim().isNotEmpty)
      'defectDescription': defectDescription.trim(),
    if (returnedBarcode.trim().isNotEmpty)
      'returnedBarcode': returnedBarcode.trim(),
  };
}

/// One die+machine stage a run passed through.
class OrderTraceStage {
  const OrderTraceStage({
    required this.nodeId,
    required this.name,
    required this.machineAssetId,
    required this.machineName,
    required this.dieToolCode,
  });

  final String nodeId;
  final String name;
  final String machineAssetId;
  final String machineName;
  final String dieToolCode;

  factory OrderTraceStage.fromJson(Map<String, dynamic> json) {
    return OrderTraceStage(
      nodeId: json['nodeId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      machineAssetId: json['machineAssetId'] as String? ?? '',
      machineName: json['machineName'] as String? ?? '',
      dieToolCode: json['dieToolCode'] as String? ?? '',
    );
  }
}

/// One consumed vendor sheet resolved back to its supplier.
class OrderTraceSheet {
  const OrderTraceSheet({
    required this.parentCode,
    this.childCode = '',
    this.weight = 0,
    this.vendorId,
    this.vendorName = '',
    this.receptionChallanNo = '',
    this.receptionDate = '',
    this.retro = false,
  });

  final String parentCode;
  final String childCode;
  final double weight;
  final int? vendorId;
  final String vendorName;
  final String receptionChallanNo;
  final String receptionDate;

  /// True when the sheet could not be resolved to a live piece_barcode (a legacy
  /// run captured only SKU-level input).
  final bool retro;

  factory OrderTraceSheet.fromJson(Map<String, dynamic> json) {
    return OrderTraceSheet(
      parentCode: json['parentCode'] as String? ?? '',
      childCode: json['childCode'] as String? ?? '',
      weight: (json['weight'] as num?)?.toDouble() ?? 0,
      vendorId: (json['vendorId'] as num?)?.toInt(),
      vendorName: json['vendorName'] as String? ?? '',
      receptionChallanNo: json['receptionChallanNo'] as String? ?? '',
      receptionDate: json['receptionDate'] as String? ?? '',
      retro: json['retro'] == true,
    );
  }
}

/// One production run in the lineage, with its stages and consumed sheets.
class OrderTraceRun {
  const OrderTraceRun({
    required this.runId,
    required this.runName,
    this.orderItemId,
    this.stages = const [],
    this.sheets = const [],
  });

  final String runId;
  final String runName;
  final int? orderItemId;
  final List<OrderTraceStage> stages;
  final List<OrderTraceSheet> sheets;

  factory OrderTraceRun.fromJson(Map<String, dynamic> json) {
    return OrderTraceRun(
      runId: '${json['runId'] ?? ''}',
      runName: '${json['runName'] ?? ''}',
      orderItemId: (json['orderItemId'] as num?)?.toInt(),
      stages: (json['stages'] as List<dynamic>? ?? const [])
          .map((e) => OrderTraceStage.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      sheets: (json['sheets'] as List<dynamic>? ?? const [])
          .map((e) => OrderTraceSheet.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

/// The full backward QC lineage for an order: return events → runs → die/machine
/// → consumed vendor sheets.
class OrderTrace {
  const OrderTrace({
    required this.orderNo,
    this.clientName = '',
    this.returns = const [],
    this.runs = const [],
  });

  final String orderNo;
  final String clientName;
  final List<OrderReturn> returns;
  final List<OrderTraceRun> runs;

  factory OrderTrace.fromJson(Map<String, dynamic> json) {
    return OrderTrace(
      orderNo: json['orderNo'] as String? ?? '',
      clientName: json['clientName'] as String? ?? '',
      returns: (json['returns'] as List<dynamic>? ?? const [])
          .map((e) => OrderReturn.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      runs: (json['runs'] as List<dynamic>? ?? const [])
          .map((e) => OrderTraceRun.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}
