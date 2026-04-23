import '../../domain/order_entry.dart';
import '../../domain/order_inputs.dart';

OrderStatus _statusFromJson(String value) {
  return OrderStatus.values
          .where((status) => status.name == value)
          .firstOrNull ??
      OrderStatus.draft;
}

OrderPriority _priorityFromJson(String value) {
  return OrderPriority.values
          .where((priority) => priority.name == value)
          .firstOrNull ??
      OrderPriority.normal;
}

class OrderDto {
  const OrderDto({
    required this.id,
    required this.orderNo,
    required this.clientId,
    required this.clientName,
    required this.poNumber,
    required this.clientCode,
    required this.itemId,
    required this.itemName,
    required this.variationLeafNodeId,
    required this.variationPathLabel,
    required this.variationPathNodeIds,
    required this.quantity,
    required this.status,
    required this.priority,
    required this.createdAt,
    required this.hasMaterialShortage,
    required this.procurementPending,
    required this.materialReadiness,
    required this.startDate,
    required this.endDate,
    required this.previousStatus,
    required this.holdReason,
    required this.cancelReason,
    required this.confirmedAt,
    required this.allocatedAt,
    required this.productionStartedAt,
    required this.completedAt,
    required this.dispatchedAt,
    required this.closedAt,
    required this.updatedBy,
  });

  final int id;
  final String orderNo;
  final int clientId;
  final String clientName;
  final String poNumber;
  final String clientCode;
  final int itemId;
  final String itemName;
  final int variationLeafNodeId;
  final String variationPathLabel;
  final List<int> variationPathNodeIds;
  final int quantity;
  final OrderStatus status;
  final OrderPriority priority;
  final DateTime createdAt;
  final bool hasMaterialShortage;
  final bool procurementPending;
  final String materialReadiness;
  final DateTime? startDate;
  final DateTime? endDate;
  final OrderStatus? previousStatus;
  final String? holdReason;
  final String? cancelReason;
  final DateTime? confirmedAt;
  final DateTime? allocatedAt;
  final DateTime? productionStartedAt;
  final DateTime? completedAt;
  final DateTime? dispatchedAt;
  final DateTime? closedAt;
  final String? updatedBy;

  factory OrderDto.fromJson(Map<String, dynamic> json) {
    return OrderDto(
      id: json['id'] as int? ?? 0,
      orderNo: json['orderNo'] as String? ?? '',
      clientId: json['clientId'] as int? ?? 0,
      clientName: json['clientName'] as String? ?? '',
      poNumber: json['poNumber'] as String? ?? '',
      clientCode: json['clientCode'] as String? ?? '',
      itemId: json['itemId'] as int? ?? 0,
      itemName: json['itemName'] as String? ?? '',
      variationLeafNodeId: json['variationLeafNodeId'] as int? ?? 0,
      variationPathLabel: json['variationPathLabel'] as String? ?? '',
      variationPathNodeIds:
          (json['variationPathNodeIds'] as List<dynamic>? ?? const [])
              .map((entry) => entry as int)
              .toList(growable: false),
      quantity: json['quantity'] as int? ?? 0,
      status: _statusFromJson(json['status'] as String? ?? ''),
      priority: _priorityFromJson(json['priority'] as String? ?? ''),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      hasMaterialShortage: json['hasMaterialShortage'] as bool? ?? false,
      procurementPending: json['procurementPending'] as bool? ?? false,
      materialReadiness: json['materialReadiness'] as String? ?? 'none',
      startDate: DateTime.tryParse(json['startDate'] as String? ?? ''),
      endDate: DateTime.tryParse(json['endDate'] as String? ?? ''),
      previousStatus: (json['previousStatus'] as String?) == null
          ? null
          : _statusFromJson(json['previousStatus'] as String),
      holdReason: json['holdReason'] as String?,
      cancelReason: json['cancelReason'] as String?,
      confirmedAt: DateTime.tryParse(json['confirmedAt'] as String? ?? ''),
      allocatedAt: DateTime.tryParse(json['allocatedAt'] as String? ?? ''),
      productionStartedAt: DateTime.tryParse(
        json['productionStartedAt'] as String? ?? '',
      ),
      completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
      dispatchedAt: DateTime.tryParse(json['dispatchedAt'] as String? ?? ''),
      closedAt: DateTime.tryParse(json['closedAt'] as String? ?? ''),
      updatedBy: json['updatedBy'] as String?,
    );
  }

  OrderEntry toDomain() {
    return OrderEntry(
      id: id,
      orderNo: orderNo,
      clientId: clientId,
      clientName: clientName,
      poNumber: poNumber,
      clientCode: clientCode,
      itemId: itemId,
      itemName: itemName,
      variationLeafNodeId: variationLeafNodeId,
      variationPathLabel: variationPathLabel,
      variationPathNodeIds: variationPathNodeIds,
      quantity: quantity,
      status: status,
      priority: priority,
      createdAt: createdAt,
      hasMaterialShortage: hasMaterialShortage,
      procurementPending: procurementPending,
      materialReadiness: materialReadiness,
      startDate: startDate,
      endDate: endDate,
      previousStatus: previousStatus,
      holdReason: holdReason,
      cancelReason: cancelReason,
      confirmedAt: confirmedAt,
      allocatedAt: allocatedAt,
      productionStartedAt: productionStartedAt,
      completedAt: completedAt,
      dispatchedAt: dispatchedAt,
      closedAt: closedAt,
      updatedBy: updatedBy,
    );
  }
}

class OrderResponse {
  const OrderResponse({required this.success, this.order, this.error});

  final bool success;
  final OrderDto? order;
  final String? error;

  factory OrderResponse.fromJson(Map<String, dynamic> json) {
    return OrderResponse(
      success: json['success'] as bool? ?? false,
      order: json['order'] == null
          ? null
          : OrderDto.fromJson(json['order'] as Map<String, dynamic>),
      error: json['error'] as String?,
    );
  }
}

class OrdersListResponse {
  const OrdersListResponse({required this.success, required this.orders});

  final bool success;
  final List<OrderDto> orders;

  factory OrdersListResponse.fromJson(Map<String, dynamic> json) {
    return OrdersListResponse(
      success: json['success'] as bool? ?? false,
      orders: (json['orders'] as List<dynamic>? ?? const [])
          .map((item) => OrderDto.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class CreateOrderRequest {
  const CreateOrderRequest({
    required this.orderNo,
    required this.clientId,
    required this.clientName,
    required this.poNumber,
    required this.clientCode,
    required this.itemId,
    required this.itemName,
    required this.variationLeafNodeId,
    required this.variationPathLabel,
    required this.variationPathNodeIds,
    required this.quantity,
    required this.status,
    required this.priority,
    this.startDate,
    this.endDate,
  });

  final String orderNo;
  final int clientId;
  final String clientName;
  final String poNumber;
  final String clientCode;
  final int itemId;
  final String itemName;
  final int variationLeafNodeId;
  final String variationPathLabel;
  final List<int> variationPathNodeIds;
  final int quantity;
  final OrderStatus status;
  final OrderPriority priority;
  final DateTime? startDate;
  final DateTime? endDate;

  factory CreateOrderRequest.fromInput(CreateOrderInput input) {
    return CreateOrderRequest(
      orderNo: input.orderNo,
      clientId: input.clientId,
      clientName: input.clientName,
      poNumber: input.poNumber,
      clientCode: input.clientCode,
      itemId: input.itemId,
      itemName: input.itemName,
      variationLeafNodeId: input.variationLeafNodeId,
      variationPathLabel: input.variationPathLabel,
      variationPathNodeIds: input.variationPathNodeIds,
      quantity: input.quantity,
      status: input.status,
      priority: input.priority,
      startDate: input.startDate,
      endDate: input.endDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'orderNo': orderNo,
      'clientId': clientId,
      'clientName': clientName,
      'poNumber': poNumber,
      'clientCode': clientCode,
      'itemId': itemId,
      'itemName': itemName,
      'variationLeafNodeId': variationLeafNodeId,
      'variationPathLabel': variationPathLabel,
      'variationPathNodeIds': variationPathNodeIds,
      'quantity': quantity,
      'status': status.name,
      'priority': priority.name,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
    };
  }
}

class UpdateOrderLifecycleRequest {
  const UpdateOrderLifecycleRequest({
    required this.toStatus,
    this.reason,
    this.startDate,
    this.endDate,
  });

  final OrderStatus toStatus;
  final String? reason;
  final DateTime? startDate;
  final DateTime? endDate;

  factory UpdateOrderLifecycleRequest.fromInput(
    UpdateOrderLifecycleInput input,
  ) {
    return UpdateOrderLifecycleRequest(
      toStatus: input.toStatus,
      reason: input.reason,
      startDate: input.startDate,
      endDate: input.endDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'toStatus': toStatus.name,
      'reason': reason,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
    };
  }
}

class OrderStatusHistoryDto {
  const OrderStatusHistoryDto({
    required this.id,
    required this.orderId,
    required this.fromStatus,
    required this.toStatus,
    required this.reason,
    required this.changedByUserId,
    required this.changedByName,
    required this.changedByRole,
    required this.source,
    required this.changedAt,
  });

  final int id;
  final int orderId;
  final OrderStatus? fromStatus;
  final OrderStatus toStatus;
  final String? reason;
  final int? changedByUserId;
  final String changedByName;
  final String? changedByRole;
  final String? source;
  final DateTime changedAt;

  factory OrderStatusHistoryDto.fromJson(Map<String, dynamic> json) {
    return OrderStatusHistoryDto(
      id: json['id'] as int? ?? 0,
      orderId: json['orderId'] as int? ?? 0,
      fromStatus: (json['fromStatus'] as String?) == null
          ? null
          : _statusFromJson(json['fromStatus'] as String),
      toStatus: _statusFromJson(json['toStatus'] as String? ?? ''),
      reason: json['reason'] as String?,
      changedByUserId: json['changedByUserId'] as int?,
      changedByName: json['changedByName'] as String? ?? 'System',
      changedByRole: json['changedByRole'] as String?,
      source: json['source'] as String?,
      changedAt:
          DateTime.tryParse(json['changedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  OrderStatusHistoryEntry toDomain() {
    return OrderStatusHistoryEntry(
      id: id,
      orderId: orderId,
      fromStatus: fromStatus,
      toStatus: toStatus,
      reason: reason,
      changedByUserId: changedByUserId,
      changedByName: changedByName,
      changedByRole: changedByRole,
      source: source,
      changedAt: changedAt,
    );
  }
}

class OrderActivityDto {
  const OrderActivityDto({
    required this.id,
    required this.orderId,
    required this.eventType,
    required this.title,
    required this.description,
    required this.actorUserId,
    required this.actorName,
    required this.actorRole,
    required this.oldValue,
    required this.newValue,
    required this.metadata,
    required this.source,
    required this.createdAt,
  });

  final int id;
  final int orderId;
  final String eventType;
  final String title;
  final String description;
  final int? actorUserId;
  final String actorName;
  final String? actorRole;
  final String? oldValue;
  final String? newValue;
  final Map<String, dynamic> metadata;
  final String? source;
  final DateTime createdAt;

  factory OrderActivityDto.fromJson(Map<String, dynamic> json) {
    return OrderActivityDto(
      id: json['id'] as int? ?? 0,
      orderId: json['orderId'] as int? ?? 0,
      eventType: json['eventType'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      actorUserId: json['actorUserId'] as int?,
      actorName: json['actorName'] as String? ?? 'System',
      actorRole: json['actorRole'] as String?,
      oldValue: json['oldValue'] as String?,
      newValue: json['newValue'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
      source: json['source'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  OrderActivityEntry toDomain() {
    return OrderActivityEntry(
      id: id,
      orderId: orderId,
      eventType: eventType,
      title: title,
      description: description,
      actorUserId: actorUserId,
      actorName: actorName,
      actorRole: actorRole,
      oldValue: oldValue,
      newValue: newValue,
      metadata: metadata,
      source: source,
      createdAt: createdAt,
    );
  }
}

class OrderTransitionOptionDto {
  const OrderTransitionOptionDto({
    required this.action,
    required this.label,
    required this.toStatus,
    required this.transitionStatus,
    required this.needsReason,
  });

  final String action;
  final String label;
  final OrderStatus toStatus;
  final OrderStatus transitionStatus;
  final bool needsReason;

  factory OrderTransitionOptionDto.fromJson(Map<String, dynamic> json) {
    return OrderTransitionOptionDto(
      action: json['action'] as String? ?? '',
      label: json['label'] as String? ?? '',
      toStatus: _statusFromJson(json['toStatus'] as String? ?? ''),
      transitionStatus: _statusFromJson(
        json['transitionStatus'] as String? ?? '',
      ),
      needsReason: json['needsReason'] as bool? ?? false,
    );
  }

  OrderTransitionOption toDomain() {
    return OrderTransitionOption(
      action: action,
      label: label,
      toStatus: toStatus,
      transitionStatus: transitionStatus,
      needsReason: needsReason,
    );
  }
}

class OrderStatusHistoryListResponse {
  const OrderStatusHistoryListResponse({
    required this.success,
    required this.history,
    this.error,
  });

  final bool success;
  final List<OrderStatusHistoryDto> history;
  final String? error;

  factory OrderStatusHistoryListResponse.fromJson(Map<String, dynamic> json) {
    return OrderStatusHistoryListResponse(
      success: json['success'] as bool? ?? false,
      history: (json['history'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                OrderStatusHistoryDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      error: json['error'] as String?,
    );
  }
}

class OrderActivityListResponse {
  const OrderActivityListResponse({
    required this.success,
    required this.events,
    this.error,
  });

  final bool success;
  final List<OrderActivityDto> events;
  final String? error;

  factory OrderActivityListResponse.fromJson(Map<String, dynamic> json) {
    return OrderActivityListResponse(
      success: json['success'] as bool? ?? false,
      events: (json['events'] as List<dynamic>? ?? const [])
          .map(
            (item) => OrderActivityDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      error: json['error'] as String?,
    );
  }
}

class OrderTransitionOptionsResponse {
  const OrderTransitionOptionsResponse({
    required this.success,
    required this.options,
    this.error,
  });

  final bool success;
  final List<OrderTransitionOptionDto> options;
  final String? error;

  factory OrderTransitionOptionsResponse.fromJson(Map<String, dynamic> json) {
    return OrderTransitionOptionsResponse(
      success: json['success'] as bool? ?? false,
      options: (json['options'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                OrderTransitionOptionDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      error: json['error'] as String?,
    );
  }
}

class AddOrderNoteRequest {
  const AddOrderNoteRequest({required this.note});

  final String note;

  factory AddOrderNoteRequest.fromInput(AddOrderNoteInput input) {
    return AddOrderNoteRequest(note: input.note);
  }

  Map<String, dynamic> toJson() {
    return {'note': note};
  }
}

class OrderActivityResponse {
  const OrderActivityResponse({
    required this.success,
    required this.event,
    this.error,
  });

  final bool success;
  final OrderActivityDto? event;
  final String? error;

  factory OrderActivityResponse.fromJson(Map<String, dynamic> json) {
    return OrderActivityResponse(
      success: json['success'] as bool? ?? false,
      event: json['event'] == null
          ? null
          : OrderActivityDto.fromJson(json['event'] as Map<String, dynamic>),
      error: json['error'] as String?,
    );
  }
}

class OrderMaterialRequirementDto {
  const OrderMaterialRequirementDto({
    required this.id,
    required this.orderId,
    required this.itemId,
    required this.materialBarcode,
    required this.materialName,
    required this.requiredQty,
    required this.allocatedQty,
    required this.consumedQty,
    required this.availableQty,
    required this.shortageQty,
    required this.unitId,
    required this.unitSymbol,
    required this.status,
    required this.procurementRequestNumber,
    required this.procurementRequestStatus,
    required this.procurementRequestedQty,
    required this.procurementReceivedQty,
    required this.procurementPendingQty,
    required this.updatedAt,
  });

  final int id;
  final int orderId;
  final int itemId;
  final String materialBarcode;
  final String materialName;
  final double requiredQty;
  final double allocatedQty;
  final double consumedQty;
  final double availableQty;
  final double shortageQty;
  final int? unitId;
  final String unitSymbol;
  final String status;
  final String? procurementRequestNumber;
  final String? procurementRequestStatus;
  final double procurementRequestedQty;
  final double procurementReceivedQty;
  final double procurementPendingQty;
  final DateTime? updatedAt;

  factory OrderMaterialRequirementDto.fromJson(Map<String, dynamic> json) {
    return OrderMaterialRequirementDto(
      id: json['id'] as int? ?? 0,
      orderId: json['orderId'] as int? ?? 0,
      itemId: json['itemId'] as int? ?? 0,
      materialBarcode: json['materialBarcode'] as String? ?? '',
      materialName: json['materialName'] as String? ?? '',
      requiredQty: (json['requiredQty'] as num? ?? 0).toDouble(),
      allocatedQty: (json['allocatedQty'] as num? ?? 0).toDouble(),
      consumedQty: (json['consumedQty'] as num? ?? 0).toDouble(),
      availableQty: (json['availableQty'] as num? ?? 0).toDouble(),
      shortageQty: (json['shortageQty'] as num? ?? 0).toDouble(),
      unitId: json['unitId'] as int?,
      unitSymbol: json['unitSymbol'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      procurementRequestNumber: json['procurementRequestNumber'] as String?,
      procurementRequestStatus: json['procurementRequestStatus'] as String?,
      procurementRequestedQty: (json['procurementRequestedQty'] as num? ?? 0)
          .toDouble(),
      procurementReceivedQty: (json['procurementReceivedQty'] as num? ?? 0)
          .toDouble(),
      procurementPendingQty: (json['procurementPendingQty'] as num? ?? 0)
          .toDouble(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }

  OrderMaterialRequirementEntry toDomain() {
    return OrderMaterialRequirementEntry(
      id: id,
      orderId: orderId,
      itemId: itemId,
      materialBarcode: materialBarcode,
      materialName: materialName,
      requiredQty: requiredQty,
      allocatedQty: allocatedQty,
      consumedQty: consumedQty,
      availableQty: availableQty,
      shortageQty: shortageQty,
      unitId: unitId,
      unitSymbol: unitSymbol,
      status: status,
      procurementRequestNumber: procurementRequestNumber,
      procurementRequestStatus: procurementRequestStatus,
      procurementRequestedQty: procurementRequestedQty,
      procurementReceivedQty: procurementReceivedQty,
      procurementPendingQty: procurementPendingQty,
      updatedAt: updatedAt,
    );
  }
}

class OrderMaterialSummaryDto {
  const OrderMaterialSummaryDto({
    required this.requiredQty,
    required this.allocatedQty,
    required this.consumedQty,
    required this.availableQty,
    required this.shortageQty,
    required this.materialCount,
    required this.shortageCount,
    required this.readiness,
  });

  final double requiredQty;
  final double allocatedQty;
  final double consumedQty;
  final double availableQty;
  final double shortageQty;
  final int materialCount;
  final int shortageCount;
  final String readiness;

  factory OrderMaterialSummaryDto.fromJson(Map<String, dynamic> json) {
    return OrderMaterialSummaryDto(
      requiredQty: (json['requiredQty'] as num? ?? 0).toDouble(),
      allocatedQty: (json['allocatedQty'] as num? ?? 0).toDouble(),
      consumedQty: (json['consumedQty'] as num? ?? 0).toDouble(),
      availableQty: (json['availableQty'] as num? ?? 0).toDouble(),
      shortageQty: (json['shortageQty'] as num? ?? 0).toDouble(),
      materialCount: json['materialCount'] as int? ?? 0,
      shortageCount: json['shortageCount'] as int? ?? 0,
      readiness: json['readiness'] as String? ?? 'ready',
    );
  }

  OrderMaterialSummary toDomain() {
    return OrderMaterialSummary(
      requiredQty: requiredQty,
      allocatedQty: allocatedQty,
      consumedQty: consumedQty,
      availableQty: availableQty,
      shortageQty: shortageQty,
      materialCount: materialCount,
      shortageCount: shortageCount,
      readiness: readiness,
    );
  }
}

class OrderMaterialSnapshotResponse {
  const OrderMaterialSnapshotResponse({
    required this.success,
    required this.requirements,
    required this.summary,
    this.error,
  });

  final bool success;
  final List<OrderMaterialRequirementDto> requirements;
  final OrderMaterialSummaryDto summary;
  final String? error;

  factory OrderMaterialSnapshotResponse.fromJson(Map<String, dynamic> json) {
    return OrderMaterialSnapshotResponse(
      success: json['success'] as bool? ?? false,
      requirements: (json['requirements'] as List<dynamic>? ?? const [])
          .map(
            (item) => OrderMaterialRequirementDto.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(growable: false),
      summary: OrderMaterialSummaryDto.fromJson(
        (json['summary'] as Map<String, dynamic>?) ?? const {},
      ),
      error: json['error'] as String?,
    );
  }

  OrderMaterialSnapshot toDomain() {
    return OrderMaterialSnapshot(
      requirements: requirements
          .map((requirement) => requirement.toDomain())
          .toList(growable: false),
      summary: summary.toDomain(),
    );
  }
}

class OrderProcurementSuggestionDto {
  const OrderProcurementSuggestionDto({
    required this.orderId,
    required this.orderNo,
    required this.materialBarcode,
    required this.materialName,
    required this.supplier,
    required this.unitSymbol,
    required this.requiredQty,
    required this.allocatedQty,
    required this.consumedQty,
    required this.availableQty,
    required this.shortageQty,
    required this.suggestedQty,
    required this.procurementState,
  });

  final int orderId;
  final String orderNo;
  final String materialBarcode;
  final String materialName;
  final String supplier;
  final String unitSymbol;
  final double requiredQty;
  final double allocatedQty;
  final double consumedQty;
  final double availableQty;
  final double shortageQty;
  final double suggestedQty;
  final String procurementState;

  factory OrderProcurementSuggestionDto.fromJson(Map<String, dynamic> json) {
    return OrderProcurementSuggestionDto(
      orderId: json['orderId'] as int? ?? 0,
      orderNo: json['orderNo'] as String? ?? '',
      materialBarcode: json['materialBarcode'] as String? ?? '',
      materialName: json['materialName'] as String? ?? '',
      supplier: json['supplier'] as String? ?? '',
      unitSymbol: json['unitSymbol'] as String? ?? '',
      requiredQty: (json['requiredQty'] as num? ?? 0).toDouble(),
      allocatedQty: (json['allocatedQty'] as num? ?? 0).toDouble(),
      consumedQty: (json['consumedQty'] as num? ?? 0).toDouble(),
      availableQty: (json['availableQty'] as num? ?? 0).toDouble(),
      shortageQty: (json['shortageQty'] as num? ?? 0).toDouble(),
      suggestedQty: (json['suggestedQty'] as num? ?? 0).toDouble(),
      procurementState: json['procurementState'] as String? ?? 'not_ordered',
    );
  }

  OrderProcurementSuggestionEntry toDomain() {
    return OrderProcurementSuggestionEntry(
      orderId: orderId,
      orderNo: orderNo,
      materialBarcode: materialBarcode,
      materialName: materialName,
      supplier: supplier,
      unitSymbol: unitSymbol,
      requiredQty: requiredQty,
      allocatedQty: allocatedQty,
      consumedQty: consumedQty,
      availableQty: availableQty,
      shortageQty: shortageQty,
      suggestedQty: suggestedQty,
      procurementState: procurementState,
    );
  }
}

class OrderProcurementSuggestionsResponse {
  const OrderProcurementSuggestionsResponse({
    required this.success,
    required this.suggestions,
    this.error,
  });

  final bool success;
  final List<OrderProcurementSuggestionDto> suggestions;
  final String? error;

  factory OrderProcurementSuggestionsResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    return OrderProcurementSuggestionsResponse(
      success: json['success'] as bool? ?? false,
      suggestions: (json['suggestions'] as List<dynamic>? ?? const [])
          .map(
            (item) => OrderProcurementSuggestionDto.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(growable: false),
      error: json['error'] as String?,
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
