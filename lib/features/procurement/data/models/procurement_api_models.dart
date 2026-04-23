import '../../domain/procurement_models.dart';

class ProcurementQueueRowDto {
  const ProcurementQueueRowDto({
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

  factory ProcurementQueueRowDto.fromJson(Map<String, dynamic> json) {
    List<int> parseInts(dynamic value) {
      if (value is List<dynamic>) {
        return value
            .map((entry) => (entry as num?)?.toInt() ?? 0)
            .toList(growable: false);
      }
      return const <int>[];
    }

    return ProcurementQueueRowDto(
      supplierName: json['supplierName'] as String? ?? 'Unassigned',
      materialBarcode: json['materialBarcode'] as String? ?? '',
      materialName: json['materialName'] as String? ?? '',
      unitId: json['unitId'] as int?,
      unitSymbol: json['unitSymbol'] as String? ?? '',
      totalShortageQty: (json['totalShortageQty'] as num? ?? 0).toDouble(),
      openRequestedQty: (json['openRequestedQty'] as num? ?? 0).toDouble(),
      uncoveredQty: (json['uncoveredQty'] as num? ?? 0).toDouble(),
      affectedOrderCount: json['affectedOrderCount'] as int? ?? 0,
      procurementStatus: json['procurementStatus'] as String? ?? 'unrequested',
      linkedRequestCount: json['linkedRequestCount'] as int? ?? 0,
      earliestOrderEndDate: json['earliestOrderEndDate'] as String?,
      orderIds: parseInts(json['orderIds']),
      sourceRequirementIds: parseInts(json['sourceRequirementIds']),
    );
  }

  ProcurementQueueRow toDomain() {
    return ProcurementQueueRow(
      supplierName: supplierName,
      materialBarcode: materialBarcode,
      materialName: materialName,
      unitId: unitId,
      unitSymbol: unitSymbol,
      totalShortageQty: totalShortageQty,
      openRequestedQty: openRequestedQty,
      uncoveredQty: uncoveredQty,
      affectedOrderCount: affectedOrderCount,
      procurementStatus: procurementStatus,
      linkedRequestCount: linkedRequestCount,
      earliestOrderEndDate: earliestOrderEndDate,
      orderIds: orderIds,
      sourceRequirementIds: sourceRequirementIds,
    );
  }
}

class ProcurementRequestSummaryDto {
  const ProcurementRequestSummaryDto({
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

  factory ProcurementRequestSummaryDto.fromJson(Map<String, dynamic> json) {
    return ProcurementRequestSummaryDto(
      id: json['id'] as int? ?? 0,
      requestNumber: json['requestNumber'] as String? ?? '',
      supplierName: json['supplierName'] as String? ?? '',
      status: json['status'] as String? ?? 'draft',
      lineCount: json['lineCount'] as int? ?? 0,
      totalRequestedQty: (json['totalRequestedQty'] as num? ?? 0).toDouble(),
      totalReceivedQty: (json['totalReceivedQty'] as num? ?? 0).toDouble(),
      totalPendingQty: (json['totalPendingQty'] as num? ?? 0).toDouble(),
      expectedDate: json['expectedDate'] as String?,
      notes: json['notes'] as String? ?? '',
    );
  }

  ProcurementRequestSummary toDomain() {
    return ProcurementRequestSummary(
      id: id,
      requestNumber: requestNumber,
      supplierName: supplierName,
      status: status,
      lineCount: lineCount,
      totalRequestedQty: totalRequestedQty,
      totalReceivedQty: totalReceivedQty,
      totalPendingQty: totalPendingQty,
      expectedDate: expectedDate,
      notes: notes,
    );
  }
}

class ProcurementRequestLineDto {
  const ProcurementRequestLineDto({
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
  final String status;
  final int linkedOrderCount;
  final int linkedRequirementCount;
  final List<int> linkedOrderIds;
  final int? unitId;
  final String unitSymbol;
  final String? updatedAt;

  factory ProcurementRequestLineDto.fromJson(Map<String, dynamic> json) {
    return ProcurementRequestLineDto(
      id: json['id'] as int? ?? 0,
      procurementRequestId: json['procurementRequestId'] as int? ?? 0,
      materialBarcode: json['materialBarcode'] as String? ?? '',
      materialName: json['materialName'] as String? ?? '',
      requestedQty: (json['requestedQty'] as num? ?? 0).toDouble(),
      receivedQty: (json['receivedQty'] as num? ?? 0).toDouble(),
      pendingQty: (json['pendingQty'] as num? ?? 0).toDouble(),
      status: json['status'] as String? ?? 'draft',
      linkedOrderCount: json['linkedOrderCount'] as int? ?? 0,
      linkedRequirementCount: json['linkedRequirementCount'] as int? ?? 0,
      linkedOrderIds: (json['linkedOrderIds'] as List<dynamic>? ?? const [])
          .map((entry) => (entry as num?)?.toInt() ?? 0)
          .toList(growable: false),
      unitId: json['unitId'] as int?,
      unitSymbol: json['unitSymbol'] as String? ?? '',
      updatedAt: json['updatedAt'] as String?,
    );
  }

  ProcurementRequestLine toDomain() {
    return ProcurementRequestLine(
      id: id,
      procurementRequestId: procurementRequestId,
      materialBarcode: materialBarcode,
      materialName: materialName,
      requestedQty: requestedQty,
      receivedQty: receivedQty,
      pendingQty: pendingQty,
      status: status,
      linkedOrderCount: linkedOrderCount,
      linkedRequirementCount: linkedRequirementCount,
      linkedOrderIds: linkedOrderIds,
      unitId: unitId,
      unitSymbol: unitSymbol,
      updatedAt: updatedAt,
    );
  }
}

class ProcurementActivityDto {
  const ProcurementActivityDto({
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

  factory ProcurementActivityDto.fromJson(Map<String, dynamic> json) {
    return ProcurementActivityDto(
      id: json['id'] as int? ?? 0,
      procurementRequestId: json['procurementRequestId'] as int? ?? 0,
      procurementRequestLineId: json['procurementRequestLineId'] as int?,
      eventType: json['eventType'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      actorName: json['actorName'] as String? ?? 'System',
      actorRole: json['actorRole'] as String?,
      metadata:
          (json['metadata'] as Map<String, dynamic>?) ??
          const <String, dynamic>{},
      source: json['source'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }

  ProcurementActivityEvent toDomain() {
    return ProcurementActivityEvent(
      id: id,
      procurementRequestId: procurementRequestId,
      procurementRequestLineId: procurementRequestLineId,
      eventType: eventType,
      title: title,
      description: description,
      actorName: actorName,
      actorRole: actorRole,
      metadata: metadata,
      source: source,
      createdAt: createdAt,
    );
  }
}

class ProcurementDetailResponse {
  const ProcurementDetailResponse({
    required this.success,
    required this.request,
    required this.lines,
    required this.activity,
    this.error,
  });

  final bool success;
  final ProcurementRequestSummaryDto? request;
  final List<ProcurementRequestLineDto> lines;
  final List<ProcurementActivityDto> activity;
  final String? error;

  factory ProcurementDetailResponse.fromJson(Map<String, dynamic> json) {
    return ProcurementDetailResponse(
      success: json['success'] as bool? ?? false,
      request: (json['request'] as Map<String, dynamic>?) == null
          ? null
          : ProcurementRequestSummaryDto.fromJson(
              json['request'] as Map<String, dynamic>,
            ),
      lines: (json['lines'] as List<dynamic>? ?? const [])
          .map(
            (entry) => ProcurementRequestLineDto.fromJson(
              entry as Map<String, dynamic>,
            ),
          )
          .toList(growable: false),
      activity: (json['activity'] as List<dynamic>? ?? const [])
          .map(
            (entry) =>
                ProcurementActivityDto.fromJson(entry as Map<String, dynamic>),
          )
          .toList(growable: false),
      error: json['error'] as String?,
    );
  }
}
