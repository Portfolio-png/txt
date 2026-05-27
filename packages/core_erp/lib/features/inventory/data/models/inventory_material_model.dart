import 'dart:convert';

import '../../domain/inventory_control_tower.dart';
import '../../domain/material_record.dart';

class InventoryMaterialModel {
  const InventoryMaterialModel({
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
    required this.createdAt,
    required this.kind,
    required this.parentBarcode,
    required this.numberOfChildren,
    required this.linkedChildBarcodes,
    required this.scanCount,
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
  final DateTime createdAt;
  final String kind;
  final String? parentBarcode;
  final int numberOfChildren;
  final List<String> linkedChildBarcodes;
  final int scanCount;
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

  factory InventoryMaterialModel.fromMap(Map<String, Object?> map) {
    final rawLinked = map['linked_child_barcodes'] as String?;
    return InventoryMaterialModel(
      id: map['id'] as int?,
      barcode: map['barcode'] as String,
      name: map['name'] as String,
      type: map['type'] as String,
      grade: map['grade'] as String? ?? '',
      thickness: map['thickness'] as String? ?? '',
      supplier: map['supplier'] as String? ?? '',
      location: map['location'] as String? ?? '',
      unitId: map['unit_id'] as int?,
      unit: map['unit'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      groupMode: map['group_mode'] as String?,
      inheritanceEnabled: (map['inheritance_enabled'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      kind: map['kind'] as String,
      parentBarcode: map['parent_barcode'] as String?,
      numberOfChildren: (map['number_of_children'] as int?) ?? 0,
      linkedChildBarcodes: rawLinked == null || rawLinked.isEmpty
          ? const []
          : List<String>.from(jsonDecode(rawLinked) as List<dynamic>),
      scanCount: (map['scan_count'] as int?) ?? 0,
      linkedGroupId: map['linked_group_id'] as int?,
      linkedItemId: map['linked_item_id'] as int?,
      linkedVariationLeafNodeId: map['linked_variation_leaf_node_id'] as int?,
      displayStock: map['display_stock'] as String? ?? '',
      createdBy: map['created_by'] as String? ?? '',
      workflowStatus: map['workflow_status'] as String? ?? 'notStarted',
      materialClass: _materialClassFromWire(
        map['material_class'] as String? ?? 'raw_material',
      ),
      inventoryState: _inventoryStateFromWire(
        map['inventory_state'] as String? ?? 'available',
      ),
      procurementState: _procurementStateFromWire(
        map['procurement_state'] as String? ?? 'not_ordered',
      ),
      traceabilityMode: _traceabilityModeFromWire(
        map['traceability_mode'] as String? ?? 'bulk',
      ),
      onHand: (map['on_hand_qty'] as num?)?.toDouble() ?? 0,
      reserved: (map['reserved_qty'] as num?)?.toDouble() ?? 0,
      availableToPromise:
          (map['available_to_promise_qty'] as num?)?.toDouble() ?? 0,
      incoming: (map['incoming_qty'] as num?)?.toDouble() ?? 0,
      linkedOrderCount: (map['linked_order_count'] as num?)?.toInt() ?? 0,
      linkedPipelineCount: (map['linked_pipeline_count'] as num?)?.toInt() ?? 0,
      pendingAlertCount: (map['pending_alert_count'] as num?)?.toInt() ?? 0,
      updatedAt:
          DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.parse(map['created_at'] as String),
      lastScannedAt: DateTime.tryParse(map['last_scanned_at'] as String? ?? ''),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'barcode': barcode,
      'name': name,
      'type': type,
      'grade': grade,
      'thickness': thickness,
      'supplier': supplier,
      'location': location,
      'unit_id': unitId,
      'unit': unit,
      'notes': notes,
      'group_mode': groupMode,
      'inheritance_enabled': inheritanceEnabled ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'kind': kind,
      'parent_barcode': parentBarcode,
      'number_of_children': numberOfChildren,
      'linked_child_barcodes': jsonEncode(linkedChildBarcodes),
      'scan_count': scanCount,
      'linked_group_id': linkedGroupId,
      'linked_item_id': linkedItemId,
      'linked_variation_leaf_node_id': linkedVariationLeafNodeId,
      'display_stock': displayStock,
      'created_by': createdBy,
      'workflow_status': workflowStatus,
      'material_class': _materialClassToWire(materialClass),
      'inventory_state': _inventoryStateToWire(inventoryState),
      'procurement_state': _procurementStateToWire(procurementState),
      'traceability_mode': _traceabilityModeToWire(traceabilityMode),
      'on_hand_qty': onHand,
      'reserved_qty': reserved,
      'available_to_promise_qty': availableToPromise,
      'incoming_qty': incoming,
      'linked_order_count': linkedOrderCount,
      'linked_pipeline_count': linkedPipelineCount,
      'pending_alert_count': pendingAlertCount,
      'updated_at': updatedAt.toIso8601String(),
      'last_scanned_at': lastScannedAt?.toIso8601String(),
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
      kind: kind,
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
