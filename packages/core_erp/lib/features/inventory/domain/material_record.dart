import 'inventory_control_tower.dart';

class MaterialRecord {
  const MaterialRecord({
    required this.id,
    required this.barcode,
    required this.name,
    required this.type,
    required this.grade,
    required this.thickness,
    required this.supplier,
    this.location = '',
    this.unitId,
    this.unit = '',
    this.notes = '',
    this.groupMode,
    this.inheritanceEnabled = false,
    required this.createdAt,
    required this.kind,
    required this.parentBarcode,
    required this.numberOfChildren,
    required this.linkedChildBarcodes,
    required this.scanCount,
    this.linkedGroupId,
    this.linkedItemId,
    this.linkedVariationLeafNodeId,
    this.displayStock = '',
    this.createdBy = '',
    this.workflowStatus = 'notStarted',
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
    DateTime? updatedAt,
    this.lastScannedAt,
  }) : updatedAt = updatedAt ?? createdAt;

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

  bool get isParent => kind == 'parent';
  bool get isChild => kind == 'child';
  bool get hasInheritanceLink => linkedGroupId != null || linkedItemId != null;
  bool get hasBeenScanned => scanCount > 0 || lastScannedAt != null;
}
