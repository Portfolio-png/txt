class ProcurementQueueRow {
  const ProcurementQueueRow({
    required this.supplierName,
    required this.materialBarcode,
    required this.materialName,
    required this.totalShortageQty,
    required this.openRequestedQty,
    required this.uncoveredQty,
    required this.affectedOrderCount,
    required this.procurementStatus,
    required this.orderIds,
    required this.sourceRequirementIds,
    this.unitId,
    this.unitSymbol = '',
    this.earliestOrderEndDate,
    this.linkedRequestCount = 0,
  });

  final String supplierName;
  final String materialBarcode;
  final String materialName;
  final int? unitId;
  final String unitSymbol;
  final double totalShortageQty;
  final double openRequestedQty;
  final double uncoveredQty;
  final int affectedOrderCount;
  final String procurementStatus;
  final int linkedRequestCount;
  final String? earliestOrderEndDate;
  final List<int> orderIds;
  final List<int> sourceRequirementIds;

  String get key => '$supplierName::$materialBarcode';
}

class ProcurementRequestSummary {
  const ProcurementRequestSummary({
    required this.id,
    required this.requestNumber,
    required this.supplierName,
    required this.status,
    required this.lineCount,
    required this.totalRequestedQty,
    required this.totalReceivedQty,
    required this.totalPendingQty,
    this.expectedDate,
    this.notes = '',
  });

  final int id;
  final String requestNumber;
  final String supplierName;
  final String status;
  final int lineCount;
  final double totalRequestedQty;
  final double totalReceivedQty;
  final double totalPendingQty;
  final String? expectedDate;
  final String notes;
}

class ProcurementRequestLine {
  const ProcurementRequestLine({
    required this.id,
    required this.procurementRequestId,
    required this.materialBarcode,
    required this.materialName,
    required this.requestedQty,
    required this.receivedQty,
    required this.pendingQty,
    required this.status,
    required this.linkedOrderCount,
    required this.linkedRequirementCount,
    required this.linkedOrderIds,
    this.unitId,
    this.unitSymbol = '',
    this.updatedAt,
  });

  final int id;
  final int procurementRequestId;
  final String materialBarcode;
  final String materialName;
  final double requestedQty;
  final double receivedQty;
  final double pendingQty;
  final int? unitId;
  final String unitSymbol;
  final String status;
  final int linkedOrderCount;
  final int linkedRequirementCount;
  final List<int> linkedOrderIds;
  final String? updatedAt;
}

class ProcurementActivityEvent {
  const ProcurementActivityEvent({
    required this.id,
    required this.procurementRequestId,
    required this.eventType,
    required this.title,
    required this.description,
    required this.actorName,
    this.procurementRequestLineId,
    this.actorRole,
    this.metadata = const <String, dynamic>{},
    this.source,
    this.createdAt,
  });

  final int id;
  final int procurementRequestId;
  final int? procurementRequestLineId;
  final String eventType;
  final String title;
  final String description;
  final String actorName;
  final String? actorRole;
  final Map<String, dynamic> metadata;
  final String? source;
  final String? createdAt;
}

class ProcurementRequestDetail {
  const ProcurementRequestDetail({
    required this.request,
    required this.lines,
    required this.activity,
  });

  final ProcurementRequestSummary request;
  final List<ProcurementRequestLine> lines;
  final List<ProcurementActivityEvent> activity;
}

class ProcurementReceiveLineInput {
  const ProcurementReceiveLineInput({
    required this.requestLineId,
    required this.receivedQty,
    this.note,
  });

  final int requestLineId;
  final double receivedQty;
  final String? note;
}
