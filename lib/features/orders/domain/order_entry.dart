enum OrderStatus {
  draft,
  confirmed,
  allocated,
  inProduction,
  completed,
  dispatched,
  closed,
  onHold,
  cancelled,
}

enum OrderPriority { low, normal, high, urgent }

class OrderEntry {
  const OrderEntry({
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
    this.priority = OrderPriority.normal,
    required this.createdAt,
    this.hasMaterialShortage = false,
    this.procurementPending = false,
    this.materialReadiness = 'none',
    this.startDate,
    this.endDate,
    this.previousStatus,
    this.holdReason,
    this.cancelReason,
    this.confirmedAt,
    this.allocatedAt,
    this.productionStartedAt,
    this.completedAt,
    this.dispatchedAt,
    this.closedAt,
    this.updatedBy,
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
}

class OrderStatusHistoryEntry {
  const OrderStatusHistoryEntry({
    required this.id,
    required this.orderId,
    required this.fromStatus,
    required this.toStatus,
    required this.changedByName,
    required this.changedAt,
    this.reason,
    this.changedByUserId,
    this.changedByRole,
    this.source,
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
}

class OrderActivityEntry {
  const OrderActivityEntry({
    required this.id,
    required this.orderId,
    required this.eventType,
    required this.title,
    required this.description,
    required this.actorName,
    required this.createdAt,
    required this.metadata,
    this.actorUserId,
    this.actorRole,
    this.oldValue,
    this.newValue,
    this.source,
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
}

class OrderTransitionOption {
  const OrderTransitionOption({
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
}

class OrderMaterialRequirementEntry {
  const OrderMaterialRequirementEntry({
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
    required this.unitSymbol,
    required this.status,
    required this.procurementRequestedQty,
    required this.procurementReceivedQty,
    required this.procurementPendingQty,
    this.unitId,
    this.procurementRequestNumber,
    this.procurementRequestStatus,
    this.updatedAt,
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
}

class OrderMaterialSummary {
  const OrderMaterialSummary({
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
}

class OrderMaterialSnapshot {
  const OrderMaterialSnapshot({
    required this.requirements,
    required this.summary,
  });

  final List<OrderMaterialRequirementEntry> requirements;
  final OrderMaterialSummary summary;
}

class OrderProcurementSuggestionEntry {
  const OrderProcurementSuggestionEntry({
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
}
