import 'dart:convert';

import '../../domain/create_parent_material_input.dart';
import '../../domain/group_property_draft.dart';
import '../../domain/material_activity_event.dart';
import '../../domain/inventory_control_tower.dart';
import '../../domain/material_control_tower_detail.dart';
import '../../domain/material_group_configuration.dart';
import '../../domain/material_record.dart';

class MaterialDto {
  const MaterialDto({
    required this.id,
    required this.barcode,
    required this.name,
    required this.type,
    required this.grade,
    required this.thickness,
    required this.supplier,
    required this.location,
    required this.unitId,
    required this.unit,
    required this.notes,
    required this.groupMode,
    required this.inheritanceEnabled,
    required this.isParent,
    required this.parentBarcode,
    required this.numberOfChildren,
    required this.linkedChildBarcodes,
    required this.scanCount,
    required this.createdAt,
    required this.linkedGroupId,
    required this.linkedItemId,
    this.linkedVariationLeafNodeId,
    required this.displayStock,
    required this.createdBy,
    required this.workflowStatus,
    this.materialClass = MaterialClass.rawMaterial,
    this.inventoryState = InventoryState.available,
    this.procurementState = ProcurementState.notOrdered,
    this.traceabilityMode = TraceabilityMode.bulk,
    this.onHand = 0,
    this.reserved = 0,
    this.availableToPromise = 0,
    this.incoming = 0,
    this.linkedOrderCount = 0,
    this.linkedPipelineCount = 0,
    this.pendingAlertCount = 0,
    required this.updatedAt,
    required this.lastScannedAt,
  });

  final int? id;
  final String barcode;
  final String name;
  final String type;
  final String grade;
  final String thickness;
  final String supplier;
  final String location;
  final int? unitId;
  final String unit;
  final String notes;
  final String? groupMode;
  final bool inheritanceEnabled;
  final bool isParent;
  final String? parentBarcode;
  final int numberOfChildren;
  final List<String> linkedChildBarcodes;
  final int scanCount;
  final DateTime createdAt;
  final int? linkedGroupId;
  final int? linkedItemId;
  final int? linkedVariationLeafNodeId;
  final String displayStock;
  final String createdBy;
  final String workflowStatus;
  final MaterialClass materialClass;
  final InventoryState inventoryState;
  final ProcurementState procurementState;
  final TraceabilityMode traceabilityMode;
  final double onHand;
  final double reserved;
  final double availableToPromise;
  final double incoming;
  final int linkedOrderCount;
  final int linkedPipelineCount;
  final int pendingAlertCount;
  final DateTime updatedAt;
  final DateTime? lastScannedAt;

  factory MaterialDto.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['linkedChildBarcodes'];
    final parsedChildren = rawChildren is String
        ? List<String>.from(jsonDecode(rawChildren) as List<dynamic>)
        : List<String>.from((rawChildren as List<dynamic>? ?? const []));

    return MaterialDto(
      id: json['id'] as int?,
      barcode: json['barcode'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      grade: json['grade'] as String? ?? '',
      thickness: json['thickness'] as String? ?? '',
      supplier: json['supplier'] as String? ?? '',
      location: json['location'] as String? ?? '',
      unitId: json['unitId'] as int?,
      unit: json['unit'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      groupMode: json['groupMode'] as String?,
      inheritanceEnabled: json['inheritanceEnabled'] as bool? ?? false,
      isParent: json['isParent'] as bool? ?? false,
      parentBarcode: json['parentBarcode'] as String?,
      numberOfChildren: json['numberOfChildren'] as int? ?? 0,
      linkedChildBarcodes: parsedChildren,
      scanCount: json['scanCount'] as int? ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      linkedGroupId: json['linkedGroupId'] as int?,
      linkedItemId: json['linkedItemId'] as int?,
      linkedVariationLeafNodeId: json['linkedVariationLeafNodeId'] as int?,
      displayStock: json['displayStock'] as String? ?? '',
      createdBy: json['createdBy'] as String? ?? '',
      workflowStatus: json['workflowStatus'] as String? ?? 'notStarted',
      materialClass: _materialClassFromWire(
        json['materialClass'] as String? ?? 'raw_material',
      ),
      inventoryState: _inventoryStateFromWire(
        json['inventoryState'] as String? ?? 'available',
      ),
      procurementState: _procurementStateFromWire(
        json['procurementState'] as String? ?? 'not_ordered',
      ),
      traceabilityMode: _traceabilityModeFromWire(
        json['traceabilityMode'] as String? ?? 'bulk',
      ),
      onHand: (json['onHand'] as num?)?.toDouble() ?? 0,
      reserved: (json['reserved'] as num?)?.toDouble() ?? 0,
      availableToPromise: (json['availableToPromise'] as num?)?.toDouble() ?? 0,
      incoming: (json['incoming'] as num?)?.toDouble() ?? 0,
      linkedOrderCount: (json['linkedOrderCount'] as num?)?.toInt() ?? 0,
      linkedPipelineCount: (json['linkedPipelineCount'] as num?)?.toInt() ?? 0,
      pendingAlertCount: (json['pendingAlertCount'] as num?)?.toInt() ?? 0,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      lastScannedAt: DateTime.tryParse(json['lastScannedAt'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'barcode': barcode,
      'name': name,
      'type': type,
      'grade': grade,
      'thickness': thickness,
      'supplier': supplier,
      'location': location,
      'unitId': unitId,
      'unit': unit,
      'notes': notes,
      'groupMode': groupMode,
      'inheritanceEnabled': inheritanceEnabled,
      'isParent': isParent,
      'parentBarcode': parentBarcode,
      'numberOfChildren': numberOfChildren,
      'linkedChildBarcodes': linkedChildBarcodes,
      'scanCount': scanCount,
      'createdAt': createdAt.toIso8601String(),
      'linkedGroupId': linkedGroupId,
      'linkedItemId': linkedItemId,
      'linkedVariationLeafNodeId': linkedVariationLeafNodeId,
      'displayStock': displayStock,
      'createdBy': createdBy,
      'workflowStatus': workflowStatus,
      'materialClass': _materialClassToWire(materialClass),
      'inventoryState': _inventoryStateToWire(inventoryState),
      'procurementState': _procurementStateToWire(procurementState),
      'traceabilityMode': _traceabilityModeToWire(traceabilityMode),
      'onHand': onHand,
      'reserved': reserved,
      'availableToPromise': availableToPromise,
      'incoming': incoming,
      'linkedOrderCount': linkedOrderCount,
      'linkedPipelineCount': linkedPipelineCount,
      'pendingAlertCount': pendingAlertCount,
      'updatedAt': updatedAt.toIso8601String(),
      'lastScannedAt': lastScannedAt?.toIso8601String(),
    };
  }

  MaterialRecord toRecord() {
    return MaterialRecord(
      id: id,
      barcode: barcode,
      name: name,
      type: type,
      grade: grade,
      thickness: thickness,
      supplier: supplier,
      location: location,
      unitId: unitId,
      unit: unit,
      notes: notes,
      groupMode: groupMode,
      inheritanceEnabled: inheritanceEnabled,
      createdAt: createdAt,
      kind: isParent ? 'parent' : 'child',
      parentBarcode: parentBarcode,
      numberOfChildren: numberOfChildren,
      linkedChildBarcodes: linkedChildBarcodes,
      scanCount: scanCount,
      linkedGroupId: linkedGroupId,
      linkedItemId: linkedItemId,
      linkedVariationLeafNodeId: linkedVariationLeafNodeId,
      displayStock: displayStock,
      createdBy: createdBy,
      workflowStatus: workflowStatus,
      materialClass: materialClass,
      inventoryState: inventoryState,
      procurementState: procurementState,
      traceabilityMode: traceabilityMode,
      onHand: onHand,
      reserved: reserved,
      availableToPromise: availableToPromise,
      incoming: incoming,
      linkedOrderCount: linkedOrderCount,
      linkedPipelineCount: linkedPipelineCount,
      pendingAlertCount: pendingAlertCount,
      updatedAt: updatedAt,
      lastScannedAt: lastScannedAt,
    );
  }

  factory MaterialDto.fromRecord(MaterialRecord record) {
    return MaterialDto(
      id: record.id,
      barcode: record.barcode,
      name: record.name,
      type: record.type,
      grade: record.grade,
      thickness: record.thickness,
      supplier: record.supplier,
      location: record.location,
      unitId: record.unitId,
      unit: record.unit,
      notes: record.notes,
      groupMode: record.groupMode,
      inheritanceEnabled: record.inheritanceEnabled,
      isParent: record.isParent,
      parentBarcode: record.parentBarcode,
      numberOfChildren: record.numberOfChildren,
      linkedChildBarcodes: record.linkedChildBarcodes,
      scanCount: record.scanCount,
      createdAt: record.createdAt,
      linkedGroupId: record.linkedGroupId,
      linkedItemId: record.linkedItemId,
      linkedVariationLeafNodeId: record.linkedVariationLeafNodeId,
      displayStock: record.displayStock,
      createdBy: record.createdBy,
      workflowStatus: record.workflowStatus,
      materialClass: record.materialClass,
      inventoryState: record.inventoryState,
      procurementState: record.procurementState,
      traceabilityMode: record.traceabilityMode,
      onHand: record.onHand,
      reserved: record.reserved,
      availableToPromise: record.availableToPromise,
      incoming: record.incoming,
      linkedOrderCount: record.linkedOrderCount,
      linkedPipelineCount: record.linkedPipelineCount,
      pendingAlertCount: record.pendingAlertCount,
      updatedAt: record.updatedAt,
      lastScannedAt: record.lastScannedAt,
    );
  }

  static MaterialClass _materialClassFromWire(String value) {
    switch (value) {
      case 'wip':
        return MaterialClass.wip;
      case 'finished_good':
        return MaterialClass.finishedGood;
      case 'packaging':
        return MaterialClass.packaging;
      case 'consumable':
        return MaterialClass.consumable;
      default:
        return MaterialClass.rawMaterial;
    }
  }

  static String _materialClassToWire(MaterialClass value) {
    switch (value) {
      case MaterialClass.rawMaterial:
        return 'raw_material';
      case MaterialClass.wip:
        return 'wip';
      case MaterialClass.finishedGood:
        return 'finished_good';
      case MaterialClass.packaging:
        return 'packaging';
      case MaterialClass.consumable:
        return 'consumable';
    }
  }

  static InventoryState _inventoryStateFromWire(String value) {
    switch (value) {
      case 'reserved':
        return InventoryState.reserved;
      case 'in_production':
        return InventoryState.inProduction;
      case 'quality_hold':
        return InventoryState.qualityHold;
      case 'damaged':
        return InventoryState.damaged;
      case 'archived':
        return InventoryState.archived;
      default:
        return InventoryState.available;
    }
  }

  static String _inventoryStateToWire(InventoryState value) {
    switch (value) {
      case InventoryState.available:
        return 'available';
      case InventoryState.reserved:
        return 'reserved';
      case InventoryState.inProduction:
        return 'in_production';
      case InventoryState.qualityHold:
        return 'quality_hold';
      case InventoryState.damaged:
        return 'damaged';
      case InventoryState.archived:
        return 'archived';
    }
  }

  static ProcurementState _procurementStateFromWire(String value) {
    switch (value) {
      case 'ordered':
        return ProcurementState.ordered;
      case 'received_partial':
        return ProcurementState.receivedPartial;
      case 'received_complete':
        return ProcurementState.receivedComplete;
      default:
        return ProcurementState.notOrdered;
    }
  }

  static String _procurementStateToWire(ProcurementState value) {
    switch (value) {
      case ProcurementState.notOrdered:
        return 'not_ordered';
      case ProcurementState.ordered:
        return 'ordered';
      case ProcurementState.receivedPartial:
        return 'received_partial';
      case ProcurementState.receivedComplete:
        return 'received_complete';
    }
  }

  static TraceabilityMode _traceabilityModeFromWire(String value) {
    switch (value) {
      case 'lot_tracked':
        return TraceabilityMode.lotTracked;
      case 'serial_tracked':
        return TraceabilityMode.serialTracked;
      default:
        return TraceabilityMode.bulk;
    }
  }

  static String _traceabilityModeToWire(TraceabilityMode value) {
    switch (value) {
      case TraceabilityMode.lotTracked:
        return 'lot_tracked';
      case TraceabilityMode.serialTracked:
        return 'serial_tracked';
      case TraceabilityMode.bulk:
        return 'bulk';
    }
  }
}

class StockPositionDto {
  const StockPositionDto({
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

  factory StockPositionDto.fromJson(Map<String, dynamic> json) {
    return StockPositionDto(
      locationId: json['locationId'] as String? ?? '',
      locationName: json['locationName'] as String? ?? '',
      lotCode: json['lotCode'] as String? ?? '',
      unitId: (json['unitId'] as num?)?.toInt(),
      onHandQty: (json['onHandQty'] as num?)?.toDouble() ?? 0,
      reservedQty: (json['reservedQty'] as num?)?.toDouble() ?? 0,
      damagedQty: (json['damagedQty'] as num?)?.toDouble() ?? 0,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  StockPosition toDomain() {
    return StockPosition(
      locationId: locationId,
      locationName: locationName,
      lotCode: lotCode,
      unitId: unitId,
      onHandQty: onHandQty,
      reservedQty: reservedQty,
      damagedQty: damagedQty,
      updatedAt: updatedAt,
    );
  }
}

class InventoryMovementDto {
  const InventoryMovementDto({
    required this.id,
    required this.materialBarcode,
    required this.movementType,
    required this.qty,
    required this.fromLocationId,
    required this.toLocationId,
    required this.reasonCode,
    required this.referenceType,
    required this.referenceId,
    required this.actor,
    required this.createdAt,
  });

  final String id;
  final String materialBarcode;
  final String movementType;
  final double qty;
  final String? fromLocationId;
  final String? toLocationId;
  final String? reasonCode;
  final String? referenceType;
  final String? referenceId;
  final String actor;
  final DateTime createdAt;

  factory InventoryMovementDto.fromJson(Map<String, dynamic> json) {
    return InventoryMovementDto(
      id: json['id'] as String? ?? '',
      materialBarcode: json['materialBarcode'] as String? ?? '',
      movementType: json['movementType'] as String? ?? 'adjust',
      qty: (json['qty'] as num?)?.toDouble() ?? 0,
      fromLocationId: json['fromLocationId'] as String?,
      toLocationId: json['toLocationId'] as String?,
      reasonCode: json['reasonCode'] as String?,
      referenceType: json['referenceType'] as String?,
      referenceId: json['referenceId'] as String?,
      actor: json['actor'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  InventoryMovement toDomain() {
    return InventoryMovement(
      id: id,
      materialBarcode: materialBarcode,
      movementType: _movementTypeFromWire(movementType),
      qty: qty,
      fromLocationId: fromLocationId,
      toLocationId: toLocationId,
      reasonCode: reasonCode,
      referenceType: referenceType,
      referenceId: referenceId,
      actor: actor,
      createdAt: createdAt,
    );
  }

  static InventoryMovementType _movementTypeFromWire(String value) {
    switch (value) {
      case 'receive':
        return InventoryMovementType.receive;
      case 'issue':
        return InventoryMovementType.issue;
      case 'transfer':
        return InventoryMovementType.transfer;
      case 'reserve':
        return InventoryMovementType.reserve;
      case 'release':
        return InventoryMovementType.release;
      case 'consume':
        return InventoryMovementType.consume;
      case 'split':
        return InventoryMovementType.split;
      case 'merge':
        return InventoryMovementType.merge;
      default:
        return InventoryMovementType.adjust;
    }
  }

  static String movementTypeToWire(InventoryMovementType value) {
    switch (value) {
      case InventoryMovementType.receive:
        return 'receive';
      case InventoryMovementType.issue:
        return 'issue';
      case InventoryMovementType.transfer:
        return 'transfer';
      case InventoryMovementType.adjust:
        return 'adjust';
      case InventoryMovementType.reserve:
        return 'reserve';
      case InventoryMovementType.release:
        return 'release';
      case InventoryMovementType.consume:
        return 'consume';
      case InventoryMovementType.split:
        return 'split';
      case InventoryMovementType.merge:
        return 'merge';
    }
  }
}

class InventoryReservationDto {
  const InventoryReservationDto({
    required this.referenceType,
    required this.referenceId,
    required this.reservedQty,
    required this.status,
  });

  final String referenceType;
  final String referenceId;
  final double reservedQty;
  final String status;

  factory InventoryReservationDto.fromJson(Map<String, dynamic> json) {
    return InventoryReservationDto(
      referenceType: json['referenceType'] as String? ?? '',
      referenceId: json['referenceId'] as String? ?? '',
      reservedQty: (json['reservedQty'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? '',
    );
  }

  InventoryReservation toDomain() {
    return InventoryReservation(
      referenceType: referenceType,
      referenceId: referenceId,
      reservedQty: reservedQty,
      status: status,
    );
  }
}

class InventoryAlertDto {
  const InventoryAlertDto({
    required this.alertType,
    required this.severity,
    required this.message,
    required this.isOpen,
  });

  final String alertType;
  final String severity;
  final String message;
  final bool isOpen;

  factory InventoryAlertDto.fromJson(Map<String, dynamic> json) {
    return InventoryAlertDto(
      alertType: json['alertType'] as String? ?? '',
      severity: json['severity'] as String? ?? 'info',
      message: json['message'] as String? ?? '',
      isOpen: json['isOpen'] as bool? ?? false,
    );
  }

  InventoryAlert toDomain() {
    return InventoryAlert(
      alertType: alertType,
      severity: _severityFromWire(severity),
      message: message,
      isOpen: isOpen,
    );
  }

  static InventoryAlertSeverity _severityFromWire(String value) {
    switch (value) {
      case 'critical':
        return InventoryAlertSeverity.critical;
      case 'warning':
        return InventoryAlertSeverity.warning;
      default:
        return InventoryAlertSeverity.info;
    }
  }
}

class MaterialControlTowerDetailResponse {
  const MaterialControlTowerDetailResponse({
    required this.success,
    this.material,
    this.stockPositions = const <StockPositionDto>[],
    this.movements = const <InventoryMovementDto>[],
    this.reservations = const <InventoryReservationDto>[],
    this.alerts = const <InventoryAlertDto>[],
    this.linkedOrderDemand = 0,
    this.linkedPipelineDemand = 0,
    this.pendingAlertsCount = 0,
    this.groupConfiguration,
    this.error,
  });

  final bool success;
  final MaterialDto? material;
  final List<StockPositionDto> stockPositions;
  final List<InventoryMovementDto> movements;
  final List<InventoryReservationDto> reservations;
  final List<InventoryAlertDto> alerts;
  final double linkedOrderDemand;
  final double linkedPipelineDemand;
  final int pendingAlertsCount;
  final MaterialGroupConfigurationDto? groupConfiguration;
  final String? error;

  factory MaterialControlTowerDetailResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    return MaterialControlTowerDetailResponse(
      success: json['success'] as bool? ?? false,
      material: json['material'] == null
          ? null
          : MaterialDto.fromJson(json['material'] as Map<String, dynamic>),
      stockPositions: (json['stockPositions'] as List<dynamic>? ?? const [])
          .map(
            (item) => StockPositionDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      movements: (json['movements'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                InventoryMovementDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      reservations: (json['reservations'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                InventoryReservationDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      alerts: (json['alerts'] as List<dynamic>? ?? const [])
          .map(
            (item) => InventoryAlertDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      linkedOrderDemand: (json['linkedOrderDemand'] as num?)?.toDouble() ?? 0,
      linkedPipelineDemand:
          (json['linkedPipelineDemand'] as num?)?.toDouble() ?? 0,
      pendingAlertsCount: (json['pendingAlertsCount'] as num?)?.toInt() ?? 0,
      groupConfiguration: json['groupConfiguration'] == null
          ? null
          : MaterialGroupConfigurationDto.fromJson(
              json['groupConfiguration'] as Map<String, dynamic>,
            ),
      error: json['error'] as String?,
    );
  }

  MaterialControlTowerDetail toDomain() {
    final materialRecord = material?.toRecord();
    if (materialRecord == null) {
      throw StateError('Material is required in detail response.');
    }
    return MaterialControlTowerDetail(
      material: materialRecord,
      stockPositions: stockPositions
          .map((position) => position.toDomain())
          .toList(growable: false),
      movements: movements
          .map((movement) => movement.toDomain())
          .toList(growable: false),
      reservations: reservations
          .map((reservation) => reservation.toDomain())
          .toList(growable: false),
      alerts: alerts.map((alert) => alert.toDomain()).toList(growable: false),
      linkedOrderDemand: linkedOrderDemand,
      linkedPipelineDemand: linkedPipelineDemand,
      pendingAlertsCount: pendingAlertsCount,
    );
  }
}

class InventoryHealthResponse {
  const InventoryHealthResponse({
    required this.success,
    required this.health,
    this.error,
  });

  final bool success;
  final InventoryHealthSnapshot health;
  final String? error;

  factory InventoryHealthResponse.fromJson(Map<String, dynamic> json) {
    final rawHealth = json['health'] as Map<String, dynamic>? ?? const {};
    return InventoryHealthResponse(
      success: json['success'] as bool? ?? false,
      health: InventoryHealthSnapshot(
        lowStockCount: (rawHealth['lowStockCount'] as num?)?.toInt() ?? 0,
        reservedRiskCount:
            (rawHealth['reservedRiskCount'] as num?)?.toInt() ?? 0,
        incomingTodayCount:
            (rawHealth['incomingTodayCount'] as num?)?.toInt() ?? 0,
        qualityHoldCount: (rawHealth['qualityHoldCount'] as num?)?.toInt() ?? 0,
        unitMismatchCount:
            (rawHealth['unitMismatchCount'] as num?)?.toInt() ?? 0,
        pendingReconciliationCount:
            (rawHealth['pendingReconciliationCount'] as num?)?.toInt() ?? 0,
      ),
      error: json['error'] as String?,
    );
  }
}

class CreateInventoryMovementRequest {
  const CreateInventoryMovementRequest({
    required this.barcode,
    required this.movementType,
    required this.qty,
    required this.fromLocationId,
    required this.toLocationId,
    required this.reasonCode,
    required this.referenceType,
    required this.referenceId,
    required this.actor,
    required this.lotCode,
  });

  final String barcode;
  final String movementType;
  final double qty;
  final String? fromLocationId;
  final String? toLocationId;
  final String? reasonCode;
  final String? referenceType;
  final String? referenceId;
  final String? actor;
  final String? lotCode;

  factory CreateInventoryMovementRequest.fromInput(
    CreateInventoryMovementInput input,
  ) {
    return CreateInventoryMovementRequest(
      barcode: input.materialBarcode,
      movementType: InventoryMovementDto.movementTypeToWire(input.movementType),
      qty: input.qty,
      fromLocationId: input.fromLocationId,
      toLocationId: input.toLocationId,
      reasonCode: input.reasonCode,
      referenceType: input.referenceType,
      referenceId: input.referenceId,
      actor: input.actor,
      lotCode: input.lotCode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'barcode': barcode,
      'movementType': movementType,
      'qty': qty,
      'fromLocationId': fromLocationId,
      'toLocationId': toLocationId,
      'reasonCode': reasonCode,
      'referenceType': referenceType,
      'referenceId': referenceId,
      'actor': actor,
      'lotCode': lotCode,
    };
  }
}

class CreateParentRequest {
  const CreateParentRequest({
    required this.name,
    required this.type,
    required this.grade,
    required this.thickness,
    required this.supplier,
    required this.location,
    required this.unitId,
    required this.unit,
    required this.groupMode,
    required this.inheritanceEnabled,
    required this.selectedItemIds,
    required this.propertyDrafts,
    required this.unitGovernance,
    required this.uiPreferences,
    required this.notes,
    required this.numberOfChildren,
  });

  final String name;
  final String type;
  final String grade;
  final String thickness;
  final String supplier;
  final String location;
  final int? unitId;
  final String unit;
  final String? groupMode;
  final bool inheritanceEnabled;
  final List<int> selectedItemIds;
  final List<GroupPropertyDraftDto> propertyDrafts;
  final List<GroupUnitGovernanceDto> unitGovernance;
  final GroupUiPreferencesDto uiPreferences;
  final String notes;
  final int numberOfChildren;

  factory CreateParentRequest.fromInput(CreateParentMaterialInput input) {
    return CreateParentRequest(
      name: input.name,
      type: input.type,
      grade: input.grade,
      thickness: input.thickness,
      supplier: input.supplier,
      location: input.location,
      unitId: input.unitId,
      unit: input.unit,
      groupMode: input.groupMode,
      inheritanceEnabled: input.inheritanceEnabled,
      selectedItemIds: input.selectedItemIds,
      propertyDrafts: input.propertyDrafts
          .map(GroupPropertyDraftDto.fromDomain)
          .toList(growable: false),
      unitGovernance: input.unitGovernance
          .map(GroupUnitGovernanceDto.fromDomain)
          .toList(growable: false),
      uiPreferences: GroupUiPreferencesDto.fromDomain(input.uiPreferences),
      notes: input.notes,
      numberOfChildren: input.numberOfChildren,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'grade': grade,
      'thickness': thickness,
      'supplier': supplier,
      'location': location,
      'unitId': unitId,
      'unit': unit,
      'groupMode': groupMode,
      'inheritanceEnabled': inheritanceEnabled,
      'selectedItemIds': selectedItemIds,
      'propertyDrafts': propertyDrafts
          .map((propertyDraft) => propertyDraft.toJson())
          .toList(growable: false),
      'unitGovernance': unitGovernance
          .map((unitGovernanceRow) => unitGovernanceRow.toJson())
          .toList(growable: false),
      'uiPreferences': uiPreferences.toJson(),
      'notes': notes,
      'numberOfChildren': numberOfChildren,
    };
  }
}

class GroupPropertySourceDto {
  const GroupPropertySourceDto({required this.itemId, this.itemName});

  final int itemId;
  final String? itemName;

  factory GroupPropertySourceDto.fromJson(Map<String, dynamic> json) {
    return GroupPropertySourceDto(
      itemId: json['itemId'] as int? ?? 0,
      itemName: json['itemName'] as String?,
    );
  }

  factory GroupPropertySourceDto.fromDomain(GroupPropertySource source) {
    return GroupPropertySourceDto(
      itemId: source.itemId,
      itemName: source.itemName,
    );
  }

  GroupPropertySource toDomain() {
    return GroupPropertySource(itemId: itemId, itemName: itemName);
  }

  Map<String, dynamic> toJson() {
    return {'itemId': itemId, 'itemName': itemName};
  }
}

class GroupPropertyDraftDto {
  const GroupPropertyDraftDto({
    required this.name,
    required this.inputType,
    required this.mandatory,
    required this.sourceType,
    required this.state,
    required this.sources,
    required this.overrideLocked,
    required this.hasTypeConflict,
    required this.coverageCount,
    required this.selectedItemCountAtResolution,
    this.resolutionSource,
  });

  final String name;
  final String inputType;
  final bool mandatory;
  final String sourceType;
  final String state;
  final List<GroupPropertySourceDto> sources;
  final bool overrideLocked;
  final bool hasTypeConflict;
  final int coverageCount;
  final int selectedItemCountAtResolution;
  final String? resolutionSource;

  factory GroupPropertyDraftDto.fromJson(Map<String, dynamic> json) {
    return GroupPropertyDraftDto(
      name: json['name'] as String? ?? '',
      inputType: json['inputType'] as String? ?? 'Text',
      mandatory: json['mandatory'] as bool? ?? false,
      sourceType: json['sourceType'] as String? ?? 'manual',
      state: json['state'] as String? ?? 'active',
      sources: (json['sources'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                GroupPropertySourceDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      overrideLocked: json['overrideLocked'] as bool? ?? false,
      hasTypeConflict: json['hasTypeConflict'] as bool? ?? false,
      coverageCount: json['coverageCount'] as int? ?? 0,
      selectedItemCountAtResolution:
          json['selectedItemCountAtResolution'] as int? ?? 0,
      resolutionSource: json['resolutionSource'] as String?,
    );
  }

  factory GroupPropertyDraftDto.fromDomain(GroupPropertyDraft draft) {
    return GroupPropertyDraftDto(
      name: draft.name,
      inputType: draft.inputType,
      mandatory: draft.mandatory,
      sourceType: _sourceTypeToWire(draft.sourceType),
      state: _stateToWire(draft.state),
      sources: draft.sources
          .map(GroupPropertySourceDto.fromDomain)
          .toList(growable: false),
      overrideLocked: draft.overrideLocked,
      hasTypeConflict: draft.hasTypeConflict,
      coverageCount: draft.coverageCount,
      selectedItemCountAtResolution: draft.selectedItemCountAtResolution,
      resolutionSource: draft.resolutionSource,
    );
  }

  GroupPropertyDraft toDomain() {
    return GroupPropertyDraft(
      name: name,
      inputType: inputType,
      mandatory: mandatory,
      sourceType: _sourceTypeFromWire(sourceType),
      state: _stateFromWire(state),
      sources: sources
          .map((source) => source.toDomain())
          .toList(growable: false),
      overrideLocked: overrideLocked,
      hasTypeConflict: hasTypeConflict,
      coverageCount: coverageCount,
      selectedItemCountAtResolution: selectedItemCountAtResolution,
      resolutionSource: resolutionSource,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'inputType': inputType,
      'mandatory': mandatory,
      'sourceType': sourceType,
      'state': state,
      'sources': sources
          .map((source) => source.toJson())
          .toList(growable: false),
      'overrideLocked': overrideLocked,
      'hasTypeConflict': hasTypeConflict,
      'coverageCount': coverageCount,
      'selectedItemCountAtResolution': selectedItemCountAtResolution,
      'resolutionSource': resolutionSource,
    };
  }

  static GroupPropertySourceType _sourceTypeFromWire(String value) {
    switch (value) {
      case 'inherited_item':
        return GroupPropertySourceType.inheritedItem;
      default:
        return GroupPropertySourceType.manual;
    }
  }

  static String _sourceTypeToWire(GroupPropertySourceType value) {
    switch (value) {
      case GroupPropertySourceType.inheritedItem:
        return 'inherited_item';
      case GroupPropertySourceType.manual:
        return 'manual';
    }
  }

  static GroupPropertyState _stateFromWire(String value) {
    switch (value) {
      case 'unlinked':
        return GroupPropertyState.unlinked;
      case 'overridden':
        return GroupPropertyState.overridden;
      default:
        return GroupPropertyState.active;
    }
  }

  static String _stateToWire(GroupPropertyState value) {
    switch (value) {
      case GroupPropertyState.active:
        return 'active';
      case GroupPropertyState.unlinked:
        return 'unlinked';
      case GroupPropertyState.overridden:
        return 'overridden';
    }
  }
}

class MaterialResponse {
  const MaterialResponse({
    required this.success,
    this.material,
    this.groupConfiguration,
    this.error,
  });

  final bool success;
  final MaterialDto? material;
  final MaterialGroupConfigurationDto? groupConfiguration;
  final String? error;

  factory MaterialResponse.fromJson(Map<String, dynamic> json) {
    return MaterialResponse(
      success: json['success'] as bool? ?? false,
      material: json['material'] == null
          ? null
          : MaterialDto.fromJson(json['material'] as Map<String, dynamic>),
      groupConfiguration: json['groupConfiguration'] == null
          ? null
          : MaterialGroupConfigurationDto.fromJson(
              json['groupConfiguration'] as Map<String, dynamic>,
            ),
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'material': material?.toJson(),
      'groupConfiguration': groupConfiguration?.toJson(),
      'error': error,
    };
  }
}

class MaterialGroupConfigurationDto {
  const MaterialGroupConfigurationDto({
    required this.selectedItemIds,
    required this.propertyDrafts,
    required this.unitGovernance,
    required this.uiPreferences,
  });

  final List<int> selectedItemIds;
  final List<GroupPropertyDraftDto> propertyDrafts;
  final List<GroupUnitGovernanceDto> unitGovernance;
  final GroupUiPreferencesDto uiPreferences;

  factory MaterialGroupConfigurationDto.fromJson(Map<String, dynamic> json) {
    return MaterialGroupConfigurationDto(
      selectedItemIds: (json['selectedItemIds'] as List<dynamic>? ?? const [])
          .map((id) => (id as num).toInt())
          .toList(growable: false),
      propertyDrafts: (json['propertyDrafts'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                GroupPropertyDraftDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      unitGovernance: (json['unitGovernance'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                GroupUnitGovernanceDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      uiPreferences: GroupUiPreferencesDto.fromJson(
        json['uiPreferences'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'selectedItemIds': selectedItemIds,
      'propertyDrafts': propertyDrafts
          .map((draft) => draft.toJson())
          .toList(growable: false),
      'unitGovernance': unitGovernance
          .map((unitGovernanceRow) => unitGovernanceRow.toJson())
          .toList(growable: false),
      'uiPreferences': uiPreferences.toJson(),
    };
  }

  MaterialGroupConfiguration toDomain({required bool inheritanceEnabled}) {
    return MaterialGroupConfiguration(
      inheritanceEnabled: inheritanceEnabled,
      selectedItemIds: selectedItemIds,
      propertyDrafts: propertyDrafts
          .map((draft) => draft.toDomain())
          .toList(growable: false),
      unitGovernance: unitGovernance
          .map((unitGovernanceRow) => unitGovernanceRow.toDomain())
          .toList(growable: false),
      uiPreferences: uiPreferences.toDomain(),
    );
  }
}

class GroupUnitGovernanceDto {
  const GroupUnitGovernanceDto({
    required this.unitId,
    required this.state,
    required this.isPrimary,
  });

  final int unitId;
  final String state;
  final bool isPrimary;

  factory GroupUnitGovernanceDto.fromJson(Map<String, dynamic> json) {
    return GroupUnitGovernanceDto(
      unitId: (json['unitId'] as num?)?.toInt() ?? 0,
      state: json['state'] as String? ?? 'active',
      isPrimary: json['isPrimary'] as bool? ?? false,
    );
  }

  factory GroupUnitGovernanceDto.fromDomain(GroupUnitGovernance row) {
    return GroupUnitGovernanceDto(
      unitId: row.unitId,
      state: row.state == GroupUnitState.detached ? 'detached' : 'active',
      isPrimary: row.isPrimary,
    );
  }

  GroupUnitGovernance toDomain() {
    return GroupUnitGovernance(
      unitId: unitId,
      state: state == 'detached'
          ? GroupUnitState.detached
          : GroupUnitState.active,
      isPrimary: isPrimary,
    );
  }

  Map<String, dynamic> toJson() {
    return {'unitId': unitId, 'state': state, 'isPrimary': isPrimary};
  }
}

class GroupUiPreferencesDto {
  const GroupUiPreferencesDto({
    required this.commonOnlyMode,
    required this.showPartialMatches,
  });

  final bool commonOnlyMode;
  final bool showPartialMatches;

  factory GroupUiPreferencesDto.fromJson(Map<String, dynamic> json) {
    return GroupUiPreferencesDto(
      commonOnlyMode: json['commonOnlyMode'] as bool? ?? true,
      showPartialMatches: json['showPartialMatches'] as bool? ?? true,
    );
  }

  factory GroupUiPreferencesDto.fromDomain(GroupUiPreferences prefs) {
    return GroupUiPreferencesDto(
      commonOnlyMode: prefs.commonOnlyMode,
      showPartialMatches: prefs.showPartialMatches,
    );
  }

  GroupUiPreferences toDomain() {
    return GroupUiPreferences(
      commonOnlyMode: commonOnlyMode,
      showPartialMatches: showPartialMatches,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'commonOnlyMode': commonOnlyMode,
      'showPartialMatches': showPartialMatches,
    };
  }
}

class MaterialsListResponse {
  const MaterialsListResponse({required this.success, required this.materials});

  final bool success;
  final List<MaterialDto> materials;

  factory MaterialsListResponse.fromJson(Map<String, dynamic> json) {
    return MaterialsListResponse(
      success: json['success'] as bool? ?? false,
      materials: (json['materials'] as List<dynamic>? ?? const [])
          .map((item) => MaterialDto.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'materials': materials.map((material) => material.toJson()).toList(),
    };
  }
}

class MaterialActivityEventDto {
  const MaterialActivityEventDto({
    required this.id,
    required this.barcode,
    required this.type,
    required this.label,
    required this.description,
    required this.actor,
    required this.createdAt,
  });

  final int? id;
  final String barcode;
  final String type;
  final String label;
  final String description;
  final String actor;
  final DateTime createdAt;

  factory MaterialActivityEventDto.fromJson(Map<String, dynamic> json) {
    return MaterialActivityEventDto(
      id: json['id'] as int?,
      barcode: json['barcode'] as String? ?? '',
      type: json['type'] as String? ?? '',
      label: json['label'] as String? ?? '',
      description: json['description'] as String? ?? '',
      actor: json['actor'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  MaterialActivityEvent toEvent() {
    return MaterialActivityEvent(
      id: id,
      barcode: barcode,
      type: type,
      label: label,
      description: description,
      actor: actor,
      createdAt: createdAt,
    );
  }
}

class MaterialActivityListResponse {
  const MaterialActivityListResponse({
    required this.success,
    required this.events,
    this.error,
  });

  final bool success;
  final List<MaterialActivityEventDto> events;
  final String? error;

  factory MaterialActivityListResponse.fromJson(Map<String, dynamic> json) {
    return MaterialActivityListResponse(
      success: json['success'] as bool? ?? false,
      events: (json['events'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                MaterialActivityEventDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      error: json['error'] as String?,
    );
  }
}
