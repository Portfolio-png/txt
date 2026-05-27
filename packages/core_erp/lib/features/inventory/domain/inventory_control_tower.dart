enum MaterialClass { rawMaterial, wip, finishedGood, packaging, consumable }

enum InventoryState {
  available,
  reserved,
  inProduction,
  qualityHold,
  damaged,
  archived,
}

enum ProcurementState { notOrdered, ordered, receivedPartial, receivedComplete }

enum TraceabilityMode { lotTracked, serialTracked, bulk }

enum InventoryMovementType {
  receive,
  issue,
  transfer,
  adjust,
  reserve,
  release,
  consume,
  split,
  merge,
}

enum InventoryAlertSeverity { info, warning, critical }

class StockPosition {
  const StockPosition({
    required this.locationId,
    required this.locationName,
    required this.lotCode,
    required this.unitId,
    required this.onHandQty,
    required this.reservedQty,
    required this.damagedQty,
    required this.updatedAt,
  });

  final String locationId;
  final String locationName;
  final String lotCode;
  final int? unitId;
  final double onHandQty;
  final double reservedQty;
  final double damagedQty;
  final DateTime updatedAt;

  double get availableQty => onHandQty - reservedQty;
}

class InventoryMovement {
  const InventoryMovement({
    required this.id,
    required this.materialBarcode,
    required this.movementType,
    required this.qty,
    required this.primaryQty,
    required this.uom,
    required this.fromLocationId,
    required this.toLocationId,
    required this.reasonCode,
    required this.referenceType,
    required this.referenceId,
    required this.sourceChallanId,
    required this.sourceChallanType,
    required this.sourceChallanLineId,
    required this.sourceLabel,
    required this.actor,
    required this.createdAt,
  });

  final String id;
  final String materialBarcode;
  final InventoryMovementType movementType;
  final double qty;
  final double primaryQty;
  final String uom;
  final String? fromLocationId;
  final String? toLocationId;
  final String? reasonCode;
  final String? referenceType;
  final String? referenceId;
  final int? sourceChallanId;
  final String? sourceChallanType;
  final int? sourceChallanLineId;
  final String? sourceLabel;
  final String actor;
  final DateTime createdAt;
}

class InventoryReservation {
  const InventoryReservation({
    required this.referenceType,
    required this.referenceId,
    required this.reservedQty,
    required this.status,
  });

  final String referenceType;
  final String referenceId;
  final double reservedQty;
  final String status;
}

class InventoryAlert {
  const InventoryAlert({
    required this.alertType,
    required this.severity,
    required this.message,
    required this.isOpen,
  });

  final String alertType;
  final InventoryAlertSeverity severity;
  final String message;
  final bool isOpen;
}

class InventoryHealthSnapshot {
  const InventoryHealthSnapshot({
    this.lowStockCount = 0,
    this.reservedRiskCount = 0,
    this.incomingTodayCount = 0,
    this.qualityHoldCount = 0,
    this.unitMismatchCount = 0,
    this.pendingReconciliationCount = 0,
  });

  final int lowStockCount;
  final int reservedRiskCount;
  final int incomingTodayCount;
  final int qualityHoldCount;
  final int unitMismatchCount;
  final int pendingReconciliationCount;
}

class CreateInventoryMovementInput {
  const CreateInventoryMovementInput({
    required this.materialBarcode,
    required this.movementType,
    required this.qty,
    this.fromLocationId,
    this.toLocationId,
    this.reasonCode,
    this.referenceType,
    this.referenceId,
    this.actor,
    this.lotCode,
  });

  final String materialBarcode;
  final InventoryMovementType movementType;
  final double qty;
  final String? fromLocationId;
  final String? toLocationId;
  final String? reasonCode;
  final String? referenceType;
  final String? referenceId;
  final String? actor;
  final String? lotCode;
}
