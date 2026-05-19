import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:paper/app/shell/navigation_provider.dart';
import 'package:paper/app/reports/domain/reconciliation_report.dart';
import 'package:paper/features/auth/presentation/providers/auth_provider.dart';
import 'package:paper/features/delivery_challans/data/delivery_challan_repository.dart';
import 'package:paper/features/delivery_challans/domain/challan_template.dart';
import 'package:paper/features/delivery_challans/domain/delivery_challan.dart';
import 'package:paper/features/groups/data/repositories/group_repository.dart';
import 'package:paper/features/groups/domain/group_definition.dart';
import 'package:paper/features/groups/domain/group_inputs.dart';
import 'package:paper/features/inventory/data/repositories/inventory_repository.dart';
import 'package:paper/features/inventory/domain/create_parent_material_input.dart';
import 'package:paper/features/inventory/domain/effective_group_schema.dart';
import 'package:paper/features/inventory/domain/group_property_draft.dart';
import 'package:paper/features/inventory/domain/inventory_control_tower.dart';
import 'package:paper/features/inventory/domain/inventory_set_definition.dart';
import 'package:paper/features/inventory/domain/material_activity_event.dart';
import 'package:paper/features/inventory/domain/material_control_tower_detail.dart';
import 'package:paper/features/inventory/domain/material_group_configuration.dart';
import 'package:paper/features/inventory/domain/material_inputs.dart';
import 'package:paper/features/inventory/domain/material_record.dart';
import 'package:paper/features/inventory/presentation/screens/inventory_screen.dart';
import 'package:paper/features/clients/data/repositories/client_repository.dart';
import 'package:paper/features/clients/domain/client_definition.dart';
import 'package:paper/features/clients/domain/client_inputs.dart';
import 'package:paper/features/clients/presentation/providers/clients_provider.dart';
import 'package:paper/features/clients/presentation/screens/clients_screen.dart';
import 'package:paper/features/delivery_challans/presentation/providers/delivery_challan_provider.dart';
import 'package:paper/features/delivery_challans/presentation/screens/challan_template_mapping_screen.dart';
import 'package:paper/features/items/data/repositories/item_repository.dart';
import 'package:paper/features/items/domain/item_asset.dart';
import 'package:paper/features/items/domain/item_definition.dart';
import 'package:paper/features/items/domain/item_inputs.dart';
import 'package:paper/features/orders/data/repositories/order_repository.dart';
import 'package:paper/features/orders/domain/order_entry.dart';
import 'package:paper/features/orders/domain/order_history.dart';
import 'package:paper/features/orders/domain/order_inputs.dart';
import 'package:paper/features/orders/domain/po_document.dart';
import 'package:paper/features/units/data/repositories/unit_repository.dart';
import 'package:paper/features/units/domain/unit_definition.dart';
import 'package:paper/features/units/domain/unit_inputs.dart';
import 'package:paper/features/vendors/data/repositories/vendor_repository.dart';
import 'package:paper/features/vendors/domain/vendor_definition.dart';
import 'package:paper/features/vendors/domain/vendor_inputs.dart';
import 'package:paper/features/vendors/presentation/providers/vendors_provider.dart';
import 'package:paper/features/vendors/presentation/screens/vendors_screen.dart';
import 'package:paper/main.dart';

void _noop() {}

class FakeInventoryRepository extends InventoryRepository {
  FakeInventoryRepository({
    List<MaterialRecord>? seedMaterials,
    List<InventorySetDefinition>? seedSets,
    Map<int, EffectiveGroupSchema>? effectiveSchemasByGroupId,
  }) : _effectiveSchemasByGroupId = Map<int, EffectiveGroupSchema>.from(
         effectiveSchemasByGroupId ?? const <int, EffectiveGroupSchema>{},
       ) {
    if (seedMaterials != null) {
      _materials
        ..clear()
        ..addAll(seedMaterials);
      _nextId = seedMaterials.isEmpty
          ? 1
          : seedMaterials
                    .map((record) => record.id ?? 0)
                    .reduce((left, right) => left > right ? left : right) +
                1;
    }
    if (seedSets != null) {
      _sets
        ..clear()
        ..addAll(seedSets);
      _nextSetId = seedSets.isEmpty
          ? 1
          : seedSets
                    .map((set) => set.id)
                    .reduce((left, right) => left > right ? left : right) +
                1;
    }
  }

  final List<MaterialRecord> _materials = <MaterialRecord>[
    MaterialRecord(
      id: 1,
      barcode: 'PAR-SEED-0001',
      name: 'Seed Parent',
      type: 'Raw Material',
      grade: 'A1',
      thickness: '1.2 mm',
      supplier: 'Seed Supplier',
      unitId: 1,
      unit: 'Kg',
      createdAt: DateTime(2024),
      kind: 'parent',
      parentBarcode: null,
      numberOfChildren: 2,
      linkedChildBarcodes: const ['CHD-0001-01', 'CHD-0001-02'],
      scanCount: 0,
      displayStock: '200 Kg',
      createdBy: 'Seed User',
      workflowStatus: 'inProgress',
    ),
    MaterialRecord(
      id: 2,
      barcode: 'CHD-0001-01',
      name: 'Seed Parent - Child 1',
      type: 'Raw Material',
      grade: 'A1',
      thickness: '1.2 mm',
      supplier: 'Seed Supplier',
      unitId: 1,
      unit: 'Kg',
      createdAt: DateTime(2024),
      kind: 'child',
      parentBarcode: 'PAR-SEED-0001',
      numberOfChildren: 0,
      linkedChildBarcodes: const [],
      scanCount: 0,
      displayStock: '100 Kg',
      createdBy: 'Seed User',
      workflowStatus: 'notStarted',
    ),
    MaterialRecord(
      id: 3,
      barcode: 'CHD-0001-02',
      name: 'Seed Parent - Child 2',
      type: 'Raw Material',
      grade: 'A1',
      thickness: '1.2 mm',
      supplier: 'Seed Supplier',
      unitId: 1,
      unit: 'Kg',
      createdAt: DateTime(2024),
      kind: 'child',
      parentBarcode: 'PAR-SEED-0001',
      numberOfChildren: 0,
      linkedChildBarcodes: const [],
      scanCount: 0,
      displayStock: '100 Kg',
      createdBy: 'Seed User',
      workflowStatus: 'notStarted',
    ),
  ];

  int _nextId = 4;
  int _saveCounter = 0;
  final Map<String, MaterialGroupConfiguration> _groupConfigurations =
      <String, MaterialGroupConfiguration>{};
  final Map<int, EffectiveGroupSchema> _effectiveSchemasByGroupId;
  final List<InventorySetDefinition> _sets = <InventorySetDefinition>[];
  int _nextSetId = 1;

  @override
  Future<void> init() async {}

  @override
  Future<void> seedIfEmpty() async {}

  @override
  Future<List<MaterialRecord>> getAllMaterials() async =>
      List<MaterialRecord>.from(_materials);

  @override
  Future<SaveParentResult> saveParentWithChildren(
    CreateParentMaterialInput input,
  ) async {
    _saveCounter += 1;
    final parentBarcode = 'PAR-TEST-${_saveCounter.toString().padLeft(4, '0')}';
    final childBarcodes = List<String>.generate(
      input.numberOfChildren,
      (index) =>
          'CHD-${_saveCounter.toString().padLeft(4, '0')}-${(index + 1).toString().padLeft(2, '0')}',
    );

    _materials.add(
      MaterialRecord(
        id: _nextId++,
        barcode: parentBarcode,
        name: input.name,
        type: input.type,
        grade: input.grade,
        thickness: input.thickness,
        supplier: input.supplier,
        unitId: input.unitId,
        unit: input.unit,
        createdAt: DateTime.now(),
        kind: 'parent',
        parentBarcode: null,
        numberOfChildren: input.numberOfChildren,
        linkedChildBarcodes: childBarcodes,
        scanCount: 0,
        displayStock: '${input.numberOfChildren * 100} ${input.unit}',
        createdBy: 'Test User',
        workflowStatus: 'inProgress',
      ),
    );

    for (var i = 0; i < childBarcodes.length; i++) {
      _materials.add(
        MaterialRecord(
          id: _nextId++,
          barcode: childBarcodes[i],
          name: '${input.name} - Child ${i + 1}',
          type: input.type,
          grade: input.grade,
          thickness: input.thickness,
          supplier: input.supplier,
          unitId: input.unitId,
          unit: input.unit,
          createdAt: DateTime.now(),
          kind: 'child',
          parentBarcode: parentBarcode,
          numberOfChildren: 0,
          linkedChildBarcodes: const [],
          scanCount: 0,
          displayStock: '100 ${input.unit}',
          createdBy: 'Test User',
          workflowStatus: 'notStarted',
        ),
      );
    }

    _groupConfigurations[parentBarcode] = MaterialGroupConfiguration(
      inheritanceEnabled: input.inheritanceEnabled,
      selectedItemIds: input.selectedItemIds,
      propertyDrafts: input.propertyDrafts,
      discardedPropertyKeys: input.discardedPropertyKeys,
    );

    return SaveParentResult(
      parentBarcode: parentBarcode,
      childBarcodes: childBarcodes,
    );
  }

  @override
  Future<MaterialRecord?> getMaterialByBarcode(String barcode) async {
    final index = _materials.indexWhere((item) => item.barcode == barcode);
    if (index == -1) {
      return null;
    }

    return incrementScanCount(barcode);
  }

  @override
  Future<MaterialRecord?> incrementScanCount(String barcode) async {
    final index = _materials.indexWhere((item) => item.barcode == barcode);
    if (index == -1) {
      return null;
    }

    final record = _materials[index];
    final updated = MaterialRecord(
      id: record.id,
      barcode: record.barcode,
      name: record.name,
      type: record.type,
      grade: record.grade,
      thickness: record.thickness,
      supplier: record.supplier,
      unitId: record.unitId,
      unit: record.unit,
      createdAt: record.createdAt,
      kind: record.kind,
      parentBarcode: record.parentBarcode,
      numberOfChildren: record.numberOfChildren,
      linkedChildBarcodes: record.linkedChildBarcodes,
      scanCount: record.scanCount + 1,
      displayStock: record.displayStock,
      createdBy: record.createdBy,
      workflowStatus: record.workflowStatus,
    );
    _materials[index] = updated;
    return updated;
  }

  @override
  Future<MaterialRecord?> resetScanTrace(String barcode) async {
    final index = _materials.indexWhere((item) => item.barcode == barcode);
    if (index == -1) {
      return null;
    }

    final record = _materials[index];
    final updated = MaterialRecord(
      id: record.id,
      barcode: record.barcode,
      name: record.name,
      type: record.type,
      grade: record.grade,
      thickness: record.thickness,
      supplier: record.supplier,
      unitId: record.unitId,
      unit: record.unit,
      createdAt: record.createdAt,
      kind: record.kind,
      parentBarcode: record.parentBarcode,
      numberOfChildren: record.numberOfChildren,
      linkedChildBarcodes: record.linkedChildBarcodes,
      scanCount: 0,
      displayStock: record.displayStock,
      createdBy: record.createdBy,
      workflowStatus: record.workflowStatus,
    );
    _materials[index] = updated;
    return updated;
  }

  @override
  Future<MaterialRecord> createChildMaterial(
    CreateChildMaterialInput input,
  ) async {
    final parentIndex = _materials.indexWhere(
      (item) => item.barcode == input.parentBarcode,
    );
    if (parentIndex == -1) {
      throw Exception('Parent material not found.');
    }
    final parent = _materials[parentIndex];
    final childBarcode =
        'CHD-${_saveCounter.toString().padLeft(4, '0')}-${parent.numberOfChildren + 1}';
    final created = MaterialRecord(
      id: _nextId++,
      barcode: childBarcode,
      name: input.name,
      type: parent.type,
      grade: parent.grade,
      thickness: parent.thickness,
      supplier: parent.supplier,
      unitId: parent.unitId,
      unit: parent.unit,
      notes: input.notes,
      createdAt: DateTime.now(),
      kind: 'child',
      parentBarcode: parent.barcode,
      numberOfChildren: 0,
      linkedChildBarcodes: const [],
      scanCount: 0,
      displayStock: parent.displayStock,
      createdBy: parent.createdBy,
      workflowStatus: 'notStarted',
    );
    _materials.add(created);
    return created;
  }

  @override
  Future<MaterialRecord> updateMaterial(UpdateMaterialInput input) async {
    final index = _materials.indexWhere(
      (item) => item.barcode == input.barcode,
    );
    if (index == -1) {
      throw Exception('Material not found.');
    }
    final current = _materials[index];
    final updated = MaterialRecord(
      id: current.id,
      barcode: current.barcode,
      name: input.name,
      type: input.type,
      grade: input.grade,
      thickness: input.thickness,
      supplier: input.supplier,
      unitId: input.unitId,
      unit: input.unit,
      notes: input.notes,
      createdAt: current.createdAt,
      kind: current.kind,
      parentBarcode: current.parentBarcode,
      numberOfChildren: current.numberOfChildren,
      linkedChildBarcodes: current.linkedChildBarcodes,
      scanCount: current.scanCount,
      linkedGroupId: current.linkedGroupId,
      linkedItemId: current.linkedItemId,
      displayStock: current.displayStock,
      createdBy: current.createdBy,
      workflowStatus: current.workflowStatus,
    );
    _materials[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteMaterial(String barcode) async {
    _materials.removeWhere(
      (item) => item.barcode == barcode || item.parentBarcode == barcode,
    );
  }

  @override
  Future<MaterialRecord> linkMaterialToGroup(
    String barcode,
    int groupId,
  ) async {
    final index = _materials.indexWhere((item) => item.barcode == barcode);
    if (index == -1) {
      throw Exception('Material not found.');
    }
    final current = _materials[index];
    final updated = MaterialRecord(
      id: current.id,
      barcode: current.barcode,
      name: current.name,
      type: current.type,
      grade: current.grade,
      thickness: current.thickness,
      supplier: current.supplier,
      unitId: current.unitId,
      unit: current.unit,
      notes: current.notes,
      createdAt: current.createdAt,
      kind: current.kind,
      parentBarcode: current.parentBarcode,
      numberOfChildren: current.numberOfChildren,
      linkedChildBarcodes: current.linkedChildBarcodes,
      scanCount: current.scanCount,
      linkedGroupId: groupId,
      linkedItemId: null,
      displayStock: current.displayStock,
      createdBy: current.createdBy,
      workflowStatus: current.workflowStatus,
    );
    _materials[index] = updated;
    return updated;
  }

  @override
  Future<MaterialRecord> linkMaterialToItem(
    String barcode,
    int itemId, {
    int? variationLeafNodeId,
  }) async {
    final index = _materials.indexWhere((item) => item.barcode == barcode);
    if (index == -1) {
      throw Exception('Material not found.');
    }
    final current = _materials[index];
    final updated = MaterialRecord(
      id: current.id,
      barcode: current.barcode,
      name: current.name,
      type: current.type,
      grade: current.grade,
      thickness: current.thickness,
      supplier: current.supplier,
      unitId: current.unitId,
      unit: current.unit,
      notes: current.notes,
      createdAt: current.createdAt,
      kind: current.kind,
      parentBarcode: current.parentBarcode,
      numberOfChildren: current.numberOfChildren,
      linkedChildBarcodes: current.linkedChildBarcodes,
      scanCount: current.scanCount,
      linkedGroupId: null,
      linkedItemId: itemId,
      linkedVariationLeafNodeId: variationLeafNodeId,
      displayStock: current.displayStock,
      createdBy: current.createdBy,
      workflowStatus: current.workflowStatus,
    );
    _materials[index] = updated;
    return updated;
  }

  @override
  Future<MaterialRecord> unlinkMaterial(String barcode) async {
    final index = _materials.indexWhere((item) => item.barcode == barcode);
    if (index == -1) {
      throw Exception('Material not found.');
    }
    final current = _materials[index];
    final updated = MaterialRecord(
      id: current.id,
      barcode: current.barcode,
      name: current.name,
      type: current.type,
      grade: current.grade,
      thickness: current.thickness,
      supplier: current.supplier,
      unitId: current.unitId,
      unit: current.unit,
      notes: current.notes,
      createdAt: current.createdAt,
      kind: current.kind,
      parentBarcode: current.parentBarcode,
      numberOfChildren: current.numberOfChildren,
      linkedChildBarcodes: current.linkedChildBarcodes,
      scanCount: current.scanCount,
      linkedGroupId: null,
      linkedItemId: null,
      displayStock: current.displayStock,
      createdBy: current.createdBy,
      workflowStatus: current.workflowStatus,
    );
    _materials[index] = updated;
    return updated;
  }

  @override
  Future<List<MaterialActivityEvent>> getMaterialActivity(
    String barcode,
  ) async {
    final index = _materials.indexWhere((item) => item.barcode == barcode);
    if (index == -1) {
      return const [];
    }
    final record = _materials[index];
    return <MaterialActivityEvent>[
      MaterialActivityEvent(
        barcode: record.barcode,
        type: 'created',
        label: record.isParent ? 'Group created' : 'Item created',
        description: '${record.name} added to inventory.',
        actor: record.createdBy,
        createdAt: record.createdAt,
      ),
    ];
  }

  @override
  Future<InventoryHealthSnapshot> getInventoryHealth() async {
    return const InventoryHealthSnapshot(
      lowStockCount: 1,
      reservedRiskCount: 0,
      incomingTodayCount: 0,
      qualityHoldCount: 0,
      unitMismatchCount: 0,
      pendingReconciliationCount: 0,
    );
  }

  @override
  Future<MaterialControlTowerDetail?> getMaterialControlTowerDetail(
    String barcode,
  ) async {
    final record = _materials
        .where((item) => item.barcode == barcode)
        .firstOrNull;
    if (record == null) {
      return null;
    }
    return MaterialControlTowerDetail(
      material: record,
      stockPositions: [
        StockPosition(
          locationId: 'MAIN',
          locationName: 'Main Warehouse',
          lotCode: record.barcode,
          unitId: record.unitId,
          onHandQty: record.onHand,
          reservedQty: record.reserved,
          damagedQty: 0,
          updatedAt: record.updatedAt,
        ),
      ],
      linkedOrderDemand: record.linkedOrderCount.toDouble(),
      linkedPipelineDemand: record.linkedPipelineCount.toDouble(),
      pendingAlertsCount: record.pendingAlertCount,
    );
  }

  @override
  Future<MaterialControlTowerDetail> createInventoryMovement(
    CreateInventoryMovementInput input,
  ) async {
    final detail = await getMaterialControlTowerDetail(input.materialBarcode);
    if (detail == null) {
      throw Exception('Material not found');
    }
    return detail;
  }

  @override
  Future<MaterialGroupConfiguration> getGroupConfiguration(
    String barcode,
  ) async {
    return _groupConfigurations[barcode] ?? const MaterialGroupConfiguration();
  }

  @override
  Future<EffectiveGroupSchema> getEffectiveSchema(int groupId) async {
    return _effectiveSchemasByGroupId[groupId] ??
        EffectiveGroupSchema(groupId: groupId);
  }

  @override
  Future<MaterialGroupConfiguration> updateGroupConfiguration(
    String barcode, {
    required bool inheritanceEnabled,
    required List<int> selectedItemIds,
    required List<GroupPropertyDraft> propertyDrafts,
    required List<GroupUnitGovernance> unitGovernance,
    required GroupUiPreferences uiPreferences,
    required List<String> discardedPropertyKeys,
  }) async {
    final next = MaterialGroupConfiguration(
      inheritanceEnabled: inheritanceEnabled,
      selectedItemIds: selectedItemIds,
      propertyDrafts: propertyDrafts,
      discardedPropertyKeys: discardedPropertyKeys,
      unitGovernance: unitGovernance,
      uiPreferences: uiPreferences,
    );
    _groupConfigurations[barcode] = next;
    return next;
  }

  @override
  Future<List<InventorySetDefinition>> getSets() async =>
      List<InventorySetDefinition>.from(_sets)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<InventorySetDefinition> saveSet(SaveInventorySetInput input) async {
    final merged = <String, SaveInventorySetLineInput>{};
    for (final line in input.lines) {
      final key = '${line.itemId}::${line.variationLeafNodeId}';
      final current = merged[key];
      if (current == null) {
        merged[key] = line;
      } else {
        merged[key] = SaveInventorySetLineInput(
          itemId: line.itemId,
          variationLeafNodeId: line.variationLeafNodeId,
          quantity: current.quantity + line.quantity,
          position: current.position,
          itemName: current.itemName,
          itemDisplayName: current.itemDisplayName,
          variationPathLabel: current.variationPathLabel,
          variationPathNodeIds: current.variationPathNodeIds,
        );
      }
    }
    final now = DateTime.now();
    final existingIndex = input.id == null
        ? -1
        : _sets.indexWhere((set) => set.id == input.id);
    final lines = merged.values.toList(growable: false)
      ..sort((a, b) => a.position.compareTo(b.position));
    final resolvedLines = lines
        .asMap()
        .entries
        .map((entry) {
          final index = entry.key;
          final line = entry.value;
          return InventorySetLineDefinition(
            id: index + 1,
            itemId: line.itemId,
            variationLeafNodeId: line.variationLeafNodeId,
            quantity: line.quantity,
            position: index,
            itemName: line.itemName.isEmpty
                ? 'Item ${line.itemId}'
                : line.itemName,
            itemDisplayName: line.itemDisplayName.isEmpty
                ? (line.itemName.isEmpty
                      ? 'Item ${line.itemId}'
                      : line.itemName)
                : line.itemDisplayName,
            variationPathLabel: line.variationPathLabel.isEmpty
                ? (line.variationLeafNodeId == 0
                      ? 'Base item'
                      : 'Leaf ${line.variationLeafNodeId}')
                : line.variationPathLabel,
            variationPathNodeIds: line.variationPathNodeIds,
          );
        })
        .toList(growable: false);
    final next = InventorySetDefinition(
      id: existingIndex >= 0 ? _sets[existingIndex].id : _nextSetId++,
      name: input.name.trim(),
      totalItemCount: resolvedLines.fold<int>(
        0,
        (sum, line) => sum + line.quantity,
      ),
      createdAt: existingIndex >= 0 ? _sets[existingIndex].createdAt : now,
      updatedAt: now,
      lines: resolvedLines,
    );
    if (existingIndex >= 0) {
      _sets[existingIndex] = next;
    } else {
      _sets.add(next);
    }
    return next;
  }

  @override
  Future<void> deleteSet(int setId) async {
    _sets.removeWhere((set) => set.id == setId);
  }
}

class FakeUnitRepository extends UnitRepository {
  final List<UnitDefinition> _units = <UnitDefinition>[
    UnitDefinition(
      id: 1,
      name: 'Kilogram',
      symbol: 'Kg',
      notes: 'Seeded unit',
      unitGroupId: 1,
      unitGroupName: 'Mass',
      conversionFactor: 1,
      conversionBaseUnitId: null,
      conversionBaseUnitName: null,
      isArchived: false,
      usageCount: 3,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    ),
    UnitDefinition(
      id: 2,
      name: 'Sheet',
      symbol: 'Sheet',
      notes: 'Seeded unit',
      unitGroupId: null,
      unitGroupName: null,
      conversionFactor: 1,
      conversionBaseUnitId: null,
      conversionBaseUnitName: null,
      isArchived: false,
      usageCount: 2,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    ),
    UnitDefinition(
      id: 3,
      name: 'Legacy',
      symbol: 'lg',
      notes: 'Archived unit',
      unitGroupId: null,
      unitGroupName: null,
      conversionFactor: 1,
      conversionBaseUnitId: null,
      conversionBaseUnitName: null,
      isArchived: true,
      usageCount: 0,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    ),
  ];

  int _nextId = 4;

  @override
  Future<void> init() async {}

  @override
  Future<List<UnitDefinition>> getUnits() async =>
      List<UnitDefinition>.from(_units);

  @override
  Future<UnitDefinition> createUnit(CreateUnitInput input) async {
    final duplicate = _units.any(
      (unit) =>
          unit.name.trim().toLowerCase() == input.name.trim().toLowerCase() &&
          unit.symbol.trim().toLowerCase() == input.symbol.trim().toLowerCase(),
    );
    if (duplicate) {
      throw Exception('A unit with the same name and symbol already exists.');
    }
    final created = UnitDefinition(
      id: _nextId++,
      name: input.name.trim(),
      symbol: input.symbol.trim(),
      notes: input.notes.trim(),
      unitGroupId: input.unitGroupName.trim().isEmpty ? null : 99,
      unitGroupName: input.unitGroupName.trim().isEmpty
          ? null
          : input.unitGroupName.trim(),
      conversionFactor: input.unitGroupName.trim().isEmpty
          ? 1
          : input.conversionFactor,
      conversionBaseUnitId: input.unitGroupName.trim().isEmpty ? null : 1,
      conversionBaseUnitName: input.unitGroupName.trim().isEmpty
          ? null
          : 'Kilogram',
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _units.add(created);
    return created;
  }

  @override
  Future<UnitDefinition> updateUnit(UpdateUnitInput input) async {
    final index = _units.indexWhere((unit) => unit.id == input.id);
    final current = _units[index];
    if (current.usageCount > 0) {
      final detailsChanged =
          current.name != input.name.trim() ||
          current.symbol != input.symbol.trim() ||
          current.notes != input.notes.trim();
      if (detailsChanged) {
        throw Exception('Used units cannot change name, symbol, or notes.');
      }
    }
    final updated = UnitDefinition(
      id: current.id,
      name: input.name.trim(),
      symbol: input.symbol.trim(),
      notes: input.notes.trim(),
      unitGroupId: input.unitGroupName.trim().isEmpty
          ? null
          : current.unitGroupId ?? 99,
      unitGroupName: input.unitGroupName.trim().isEmpty
          ? null
          : input.unitGroupName.trim(),
      conversionFactor: input.unitGroupName.trim().isEmpty
          ? 1
          : input.conversionFactor,
      conversionBaseUnitId: input.unitGroupName.trim().isEmpty ? null : 1,
      conversionBaseUnitName: input.unitGroupName.trim().isEmpty
          ? null
          : 'Kilogram',
      isArchived: current.isArchived,
      usageCount: current.usageCount,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    _units[index] = updated;
    return updated;
  }

  @override
  Future<UnitDefinition> archiveUnit(int id) async {
    final index = _units.indexWhere((unit) => unit.id == id);
    final current = _units[index];
    final updated = UnitDefinition(
      id: current.id,
      name: current.name,
      symbol: current.symbol,
      notes: current.notes,
      unitGroupId: current.unitGroupId,
      unitGroupName: current.unitGroupName,
      conversionFactor: current.conversionFactor,
      conversionBaseUnitId: current.conversionBaseUnitId,
      conversionBaseUnitName: current.conversionBaseUnitName,
      isArchived: true,
      usageCount: current.usageCount,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    _units[index] = updated;
    return updated;
  }

  @override
  Future<UnitDefinition> restoreUnit(int id) async {
    final index = _units.indexWhere((unit) => unit.id == id);
    final current = _units[index];
    final updated = UnitDefinition(
      id: current.id,
      name: current.name,
      symbol: current.symbol,
      notes: current.notes,
      unitGroupId: current.unitGroupId,
      unitGroupName: current.unitGroupName,
      conversionFactor: current.conversionFactor,
      conversionBaseUnitId: current.conversionBaseUnitId,
      conversionBaseUnitName: current.conversionBaseUnitName,
      isArchived: false,
      usageCount: current.usageCount,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    _units[index] = updated;
    return updated;
  }
}

class FakeGroupRepository extends GroupRepository {
  FakeGroupRepository({List<GroupDefinition>? seedGroups})
    : _groups =
          seedGroups ??
          <GroupDefinition>[
            GroupDefinition(
              id: 1,
              name: 'Paper',
              parentGroupId: null,
              unitId: 2,
              isArchived: false,
              usageCount: 2,
              createdAt: DateTime(2024),
              updatedAt: DateTime(2024),
            ),
            GroupDefinition(
              id: 2,
              name: 'Kraft',
              parentGroupId: 1,
              unitId: 2,
              isArchived: false,
              usageCount: 0,
              createdAt: DateTime(2024),
              updatedAt: DateTime(2024),
            ),
            GroupDefinition(
              id: 3,
              name: 'Chemical',
              parentGroupId: null,
              unitId: 1,
              isArchived: false,
              usageCount: 0,
              createdAt: DateTime(2024),
              updatedAt: DateTime(2024),
            ),
            GroupDefinition(
              id: 4,
              name: 'Legacy Group',
              parentGroupId: null,
              unitId: 1,
              isArchived: true,
              usageCount: 0,
              createdAt: DateTime(2024),
              updatedAt: DateTime(2024),
            ),
          ];

  final List<GroupDefinition> _groups;
  int _nextId = 5;

  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups() async =>
      List<GroupDefinition>.from(_groups);

  @override
  Future<GroupDefinition> createGroup(CreateGroupInput input) async {
    final duplicate = _groups.any(
      (group) =>
          group.parentGroupId == input.parentGroupId &&
          group.name.trim().toLowerCase() == input.name.trim().toLowerCase(),
    );
    if (duplicate) {
      throw Exception('A group with the same name already exists here.');
    }
    final created = GroupDefinition(
      id: _nextId++,
      name: input.name.trim(),
      parentGroupId: input.parentGroupId,
      unitId: input.unitId,
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _groups.add(created);
    return created;
  }

  @override
  Future<GroupDefinition> updateGroup(UpdateGroupInput input) async {
    final index = _groups.indexWhere((group) => group.id == input.id);
    final current = _groups[index];
    if (current.usageCount > 0) {
      throw Exception('Used groups cannot be edited.');
    }
    final updated = GroupDefinition(
      id: current.id,
      name: input.name.trim(),
      parentGroupId: input.parentGroupId,
      unitId: input.unitId,
      isArchived: current.isArchived,
      usageCount: current.usageCount,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    _groups[index] = updated;
    return updated;
  }

  @override
  Future<GroupDefinition> archiveGroup(int id) async {
    if (_groups.any(
      (group) => group.parentGroupId == id && !group.isArchived,
    )) {
      throw Exception(
        'This group has active child groups. Reassign or archive them first.',
      );
    }
    final index = _groups.indexWhere((group) => group.id == id);
    final current = _groups[index];
    final updated = GroupDefinition(
      id: current.id,
      name: current.name,
      parentGroupId: current.parentGroupId,
      unitId: current.unitId,
      isArchived: true,
      usageCount: current.usageCount,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    _groups[index] = updated;
    return updated;
  }

  @override
  Future<GroupDefinition> restoreGroup(int id) async {
    final index = _groups.indexWhere((group) => group.id == id);
    final current = _groups[index];
    final updated = GroupDefinition(
      id: current.id,
      name: current.name,
      parentGroupId: current.parentGroupId,
      unitId: current.unitId,
      isArchived: false,
      usageCount: current.usageCount,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    _groups[index] = updated;
    return updated;
  }
}

class FakeClientRepository extends ClientRepository {
  FakeClientRepository({List<ClientDefinition>? seedClients})
    : _clients =
          seedClients ??
          <ClientDefinition>[
            ClientDefinition(
              id: 1,
              name: 'Acme Packaging Pvt. Ltd.',
              alias: 'Acme',
              gstNumber: '27ABCDE1234F1Z5',
              address: 'MIDC Industrial Area, Pune, Maharashtra 411019',
              isArchived: false,
              usageCount: 0,
              createdAt: DateTime(2024),
              updatedAt: DateTime(2024),
            ),
            ClientDefinition(
              id: 2,
              name: 'Sunrise Retail LLP',
              alias: 'Sunrise',
              gstNumber: '24AAKCS9988M1Z2',
              address: 'Satellite Road, Ahmedabad, Gujarat 380015',
              isArchived: false,
              usageCount: 0,
              createdAt: DateTime(2024),
              updatedAt: DateTime(2024),
            ),
            ClientDefinition(
              id: 3,
              name: 'Legacy Trading Co.',
              alias: 'Legacy',
              gstNumber: '',
              address: 'Old Market Road, Indore, Madhya Pradesh 452001',
              isArchived: true,
              usageCount: 0,
              createdAt: DateTime(2024),
              updatedAt: DateTime(2024),
            ),
          ];

  final List<ClientDefinition> _clients;

  int _nextId = 4;

  @override
  Future<void> init() async {}

  @override
  Future<List<ClientDefinition>> getClients() async =>
      List<ClientDefinition>.from(_clients);

  @override
  Future<ClientDefinition> createClient(CreateClientInput input) async {
    final now = DateTime.now();
    final created = ClientDefinition(
      id: _nextId++,
      name: input.name.trim(),
      alias: input.alias.trim(),
      gstNumber: input.gstNumber.trim(),
      address: input.address.trim(),
      isArchived: false,
      usageCount: 0,
      createdAt: now,
      updatedAt: now,
    );
    _clients.add(created);
    return created;
  }

  @override
  Future<ClientDefinition> updateClient(UpdateClientInput input) async {
    final index = _clients.indexWhere((client) => client.id == input.id);
    final current = _clients[index];
    final updated = ClientDefinition(
      id: current.id,
      name: input.name.trim(),
      alias: input.alias.trim(),
      gstNumber: input.gstNumber.trim(),
      address: input.address.trim(),
      isArchived: current.isArchived,
      usageCount: current.usageCount,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    _clients[index] = updated;
    return updated;
  }

  @override
  Future<ClientDefinition> archiveClient(int id) async {
    final index = _clients.indexWhere((client) => client.id == id);
    final current = _clients[index];
    final updated = ClientDefinition(
      id: current.id,
      name: current.name,
      alias: current.alias,
      gstNumber: current.gstNumber,
      address: current.address,
      isArchived: true,
      usageCount: current.usageCount,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    _clients[index] = updated;
    return updated;
  }

  @override
  Future<ClientDefinition> restoreClient(int id) async {
    final index = _clients.indexWhere((client) => client.id == id);
    final current = _clients[index];
    final updated = ClientDefinition(
      id: current.id,
      name: current.name,
      alias: current.alias,
      gstNumber: current.gstNumber,
      address: current.address,
      isArchived: false,
      usageCount: current.usageCount,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    _clients[index] = updated;
    return updated;
  }
}

class FakeVendorRepository extends VendorRepository {
  FakeVendorRepository({List<VendorDefinition>? seedVendors})
    : _vendors =
          seedVendors ??
          <VendorDefinition>[
            VendorDefinition(
              id: 1,
              name: 'Supplier A',
              alias: 'SUP-A',
              gstNumber: '27ABCDE1234F1Z5',
              address: 'Bhosari, Pune',
              contactName: 'Rahul',
              phone: '9876543210',
              email: 'ops@suppliera.com',
              isArchived: false,
              usageCount: 0,
              createdAt: DateTime(2024),
              updatedAt: DateTime(2024),
            ),
            VendorDefinition(
              id: 2,
              name: 'Legacy Vendor',
              alias: 'LEG',
              gstNumber: '',
              address: 'Mumbai',
              contactName: 'Desk',
              phone: '',
              email: '',
              isArchived: true,
              usageCount: 0,
              createdAt: DateTime(2024),
              updatedAt: DateTime(2024),
            ),
          ];

  final List<VendorDefinition> _vendors;
  int _nextId = 3;

  @override
  Future<void> init() async {}

  @override
  Future<List<VendorDefinition>> getVendors() async =>
      List<VendorDefinition>.from(_vendors);

  @override
  Future<VendorDefinition> createVendor(CreateVendorInput input) async {
    final now = DateTime.now();
    final created = VendorDefinition(
      id: _nextId++,
      name: input.name.trim(),
      alias: input.alias.trim(),
      gstNumber: input.gstNumber.trim(),
      address: input.address.trim(),
      contactName: input.contactName.trim(),
      phone: input.phone.trim(),
      email: input.email.trim(),
      isArchived: false,
      usageCount: 0,
      createdAt: now,
      updatedAt: now,
    );
    _vendors.add(created);
    return created;
  }

  @override
  Future<VendorDefinition> updateVendor(UpdateVendorInput input) async {
    final index = _vendors.indexWhere((vendor) => vendor.id == input.id);
    final current = _vendors[index];
    final updated = VendorDefinition(
      id: current.id,
      name: input.name.trim(),
      alias: input.alias.trim(),
      gstNumber: input.gstNumber.trim(),
      address: input.address.trim(),
      contactName: input.contactName.trim(),
      phone: input.phone.trim(),
      email: input.email.trim(),
      isArchived: current.isArchived,
      usageCount: current.usageCount,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    _vendors[index] = updated;
    return updated;
  }

  @override
  Future<VendorDefinition> archiveVendor(int id) async {
    final index = _vendors.indexWhere((vendor) => vendor.id == id);
    final current = _vendors[index];
    final updated = VendorDefinition(
      id: current.id,
      name: current.name,
      alias: current.alias,
      gstNumber: current.gstNumber,
      address: current.address,
      contactName: current.contactName,
      phone: current.phone,
      email: current.email,
      isArchived: true,
      usageCount: current.usageCount,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    _vendors[index] = updated;
    return updated;
  }

  @override
  Future<VendorDefinition> restoreVendor(int id) async {
    final index = _vendors.indexWhere((vendor) => vendor.id == id);
    final current = _vendors[index];
    final updated = VendorDefinition(
      id: current.id,
      name: current.name,
      alias: current.alias,
      gstNumber: current.gstNumber,
      address: current.address,
      contactName: current.contactName,
      phone: current.phone,
      email: current.email,
      isArchived: false,
      usageCount: current.usageCount,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    _vendors[index] = updated;
    return updated;
  }
}

class FakeItemRepository extends ItemRepository {
  FakeItemRepository({List<ItemDefinition>? seedItems})
    : _items =
          seedItems ??
          <ItemDefinition>[
            ItemDefinition(
              id: 1,
              name: 'Switch Action Dolly',
              alias: 'Finish Goods Variant',
              displayName: 'Switch Action Dolly - 1',
              quantity: 1,
              groupId: 2,
              unitId: 2,
              isArchived: false,
              usageCount: 2,
              createdAt: DateTime(2024),
              updatedAt: DateTime(2024),
              variationTree: [
                _node(
                  id: 1,
                  itemId: 1,
                  kind: ItemVariationNodeKind.property,
                  name: 'Action Dolly Amp',
                  children: [
                    _node(
                      id: 2,
                      itemId: 1,
                      parentNodeId: 1,
                      kind: ItemVariationNodeKind.value,
                      name: '5 Amp',
                      children: [
                        _node(
                          id: 3,
                          itemId: 1,
                          parentNodeId: 2,
                          kind: ItemVariationNodeKind.property,
                          name: 'Action Patti + Dabbi',
                          children: [
                            _node(
                              id: 4,
                              itemId: 1,
                              parentNodeId: 3,
                              kind: ItemVariationNodeKind.value,
                              name: '11+1',
                              children: [
                                _node(
                                  id: 10,
                                  itemId: 1,
                                  parentNodeId: 4,
                                  kind: ItemVariationNodeKind.property,
                                  name: 'Action Dolly Alloy',
                                  children: [
                                    _node(
                                      id: 11,
                                      itemId: 1,
                                      parentNodeId: 10,
                                      kind: ItemVariationNodeKind.value,
                                      name: 'Brass',
                                      children: [
                                        _node(
                                          id: 12,
                                          itemId: 1,
                                          parentNodeId: 11,
                                          kind: ItemVariationNodeKind.property,
                                          name: 'Action Dolly Contact',
                                          children: [
                                            _node(
                                              id: 13,
                                              itemId: 1,
                                              parentNodeId: 12,
                                              kind: ItemVariationNodeKind.value,
                                              name: '1 Way',
                                              children: [
                                                _node(
                                                  id: 14,
                                                  itemId: 1,
                                                  parentNodeId: 13,
                                                  kind: ItemVariationNodeKind
                                                      .property,
                                                  name: 'Action Dolly Type',
                                                  children: [
                                                    _node(
                                                      id: 15,
                                                      itemId: 1,
                                                      parentNodeId: 14,
                                                      kind:
                                                          ItemVariationNodeKind
                                                              .value,
                                                      name: 'Dolly',
                                                      children: [
                                                        _node(
                                                          id: 16,
                                                          itemId: 1,
                                                          parentNodeId: 15,
                                                          kind:
                                                              ItemVariationNodeKind
                                                                  .property,
                                                          name:
                                                              'Action Dolly Plating',
                                                          children: [
                                                            _node(
                                                              id: 17,
                                                              itemId: 1,
                                                              parentNodeId: 16,
                                                              kind:
                                                                  ItemVariationNodeKind
                                                                      .value,
                                                              name:
                                                                  'Without Plating',
                                                              displayName:
                                                                  '5 Amp 11+1 Brass 1 Way Dolly Without Plating',
                                                            ),
                                                            _node(
                                                              id: 18,
                                                              itemId: 1,
                                                              parentNodeId: 16,
                                                              kind:
                                                                  ItemVariationNodeKind
                                                                      .value,
                                                              name:
                                                                  'With Plating',
                                                              displayName:
                                                                  '5 Amp 11+1 Brass 1 Way Dolly With Plating',
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    _node(
                      id: 5,
                      itemId: 1,
                      parentNodeId: 1,
                      kind: ItemVariationNodeKind.value,
                      name: '6 Amp',
                      children: [
                        _node(
                          id: 6,
                          itemId: 1,
                          parentNodeId: 5,
                          kind: ItemVariationNodeKind.property,
                          name: 'Action Patti + Dabbi',
                          children: [
                            _node(
                              id: 7,
                              itemId: 1,
                              parentNodeId: 6,
                              kind: ItemVariationNodeKind.value,
                              name: '11+1',
                              children: [
                                _node(
                                  id: 19,
                                  itemId: 1,
                                  parentNodeId: 7,
                                  kind: ItemVariationNodeKind.property,
                                  name: 'Action Dolly Alloy',
                                  children: [
                                    _node(
                                      id: 20,
                                      itemId: 1,
                                      parentNodeId: 19,
                                      kind: ItemVariationNodeKind.value,
                                      name: 'Brass',
                                      children: [
                                        _node(
                                          id: 21,
                                          itemId: 1,
                                          parentNodeId: 20,
                                          kind: ItemVariationNodeKind.property,
                                          name: 'Action Dolly Contact',
                                          children: [
                                            _node(
                                              id: 22,
                                              itemId: 1,
                                              parentNodeId: 21,
                                              kind: ItemVariationNodeKind.value,
                                              name: '1 Way',
                                              children: [
                                                _node(
                                                  id: 23,
                                                  itemId: 1,
                                                  parentNodeId: 22,
                                                  kind: ItemVariationNodeKind
                                                      .property,
                                                  name: 'Action Dolly Type',
                                                  children: [
                                                    _node(
                                                      id: 24,
                                                      itemId: 1,
                                                      parentNodeId: 23,
                                                      kind:
                                                          ItemVariationNodeKind
                                                              .value,
                                                      name: 'Dolly',
                                                      children: [
                                                        _node(
                                                          id: 25,
                                                          itemId: 1,
                                                          parentNodeId: 24,
                                                          kind:
                                                              ItemVariationNodeKind
                                                                  .property,
                                                          name:
                                                              'Action Dolly Plating',
                                                          children: [
                                                            _node(
                                                              id: 26,
                                                              itemId: 1,
                                                              parentNodeId: 25,
                                                              kind:
                                                                  ItemVariationNodeKind
                                                                      .value,
                                                              name:
                                                                  'Without Plating',
                                                              displayName:
                                                                  '6 Amp 11+1 Brass 1 Way Dolly Without Plating',
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            ItemDefinition(
              id: 2,
              name: 'Glue Compound',
              alias: 'Adhesive',
              displayName: 'Glue Compound - 1',
              quantity: 1,
              groupId: 3,
              unitId: 1,
              isArchived: false,
              usageCount: 0,
              createdAt: DateTime(2024),
              updatedAt: DateTime(2024),
              variationTree: [
                _node(
                  id: 8,
                  itemId: 2,
                  kind: ItemVariationNodeKind.property,
                  name: 'Cure Speed',
                  children: [
                    _node(
                      id: 9,
                      itemId: 2,
                      parentNodeId: 8,
                      kind: ItemVariationNodeKind.value,
                      name: 'Fast Cure',
                      displayName: 'Fast Cure',
                    ),
                  ],
                ),
              ],
            ),
            ItemDefinition(
              id: 3,
              name: 'Luxury Pump Bottle',
              alias: 'Cosmetic Pack',
              displayName: 'Luxury Pump Bottle - 100',
              quantity: 100,
              groupId: 2,
              unitId: 2,
              isArchived: false,
              usageCount: 1,
              createdAt: DateTime(2024),
              updatedAt: DateTime(2024),
              variationTree: [
                _node(
                  id: 27,
                  itemId: 3,
                  kind: ItemVariationNodeKind.property,
                  name: 'Bottle Material',
                  children: [
                    _node(
                      id: 28,
                      itemId: 3,
                      parentNodeId: 27,
                      kind: ItemVariationNodeKind.value,
                      name: 'PET',
                      children: [
                        _node(
                          id: 29,
                          itemId: 3,
                          parentNodeId: 28,
                          kind: ItemVariationNodeKind.property,
                          name: 'Bottle Color',
                          children: [
                            _node(
                              id: 30,
                              itemId: 3,
                              parentNodeId: 29,
                              kind: ItemVariationNodeKind.value,
                              name: 'Frosted Clear',
                              children: [
                                _node(
                                  id: 31,
                                  itemId: 3,
                                  parentNodeId: 30,
                                  kind: ItemVariationNodeKind.property,
                                  name: 'Pump Finish',
                                  children: [
                                    _node(
                                      id: 32,
                                      itemId: 3,
                                      parentNodeId: 31,
                                      kind: ItemVariationNodeKind.value,
                                      name: 'Matte Silver',
                                      children: [
                                        _node(
                                          id: 33,
                                          itemId: 3,
                                          parentNodeId: 32,
                                          kind: ItemVariationNodeKind.property,
                                          name: 'Lock Type',
                                          children: [
                                            _node(
                                              id: 34,
                                              itemId: 3,
                                              parentNodeId: 33,
                                              kind: ItemVariationNodeKind.value,
                                              name: 'Left Lock',
                                              displayName:
                                                  'PET Frosted Clear Matte Silver Left Lock',
                                            ),
                                            _node(
                                              id: 35,
                                              itemId: 3,
                                              parentNodeId: 33,
                                              kind: ItemVariationNodeKind.value,
                                              name: 'Right Lock',
                                              displayName:
                                                  'PET Frosted Clear Matte Silver Right Lock',
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            _node(
                              id: 36,
                              itemId: 3,
                              parentNodeId: 29,
                              kind: ItemVariationNodeKind.value,
                              name: 'Amber',
                              children: [
                                _node(
                                  id: 37,
                                  itemId: 3,
                                  parentNodeId: 36,
                                  kind: ItemVariationNodeKind.property,
                                  name: 'Pump Finish',
                                  children: [
                                    _node(
                                      id: 38,
                                      itemId: 3,
                                      parentNodeId: 37,
                                      kind: ItemVariationNodeKind.value,
                                      name: 'Gloss Gold',
                                      children: [
                                        _node(
                                          id: 39,
                                          itemId: 3,
                                          parentNodeId: 38,
                                          kind: ItemVariationNodeKind.property,
                                          name: 'Lock Type',
                                          children: [
                                            _node(
                                              id: 40,
                                              itemId: 3,
                                              parentNodeId: 39,
                                              kind: ItemVariationNodeKind.value,
                                              name: 'Left Lock',
                                              displayName:
                                                  'PET Amber Gloss Gold Left Lock',
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    _node(
                      id: 41,
                      itemId: 3,
                      parentNodeId: 27,
                      kind: ItemVariationNodeKind.value,
                      name: 'Glass',
                      children: [
                        _node(
                          id: 42,
                          itemId: 3,
                          parentNodeId: 41,
                          kind: ItemVariationNodeKind.property,
                          name: 'Bottle Color',
                          children: [
                            _node(
                              id: 43,
                              itemId: 3,
                              parentNodeId: 42,
                              kind: ItemVariationNodeKind.value,
                              name: 'Clear',
                              children: [
                                _node(
                                  id: 44,
                                  itemId: 3,
                                  parentNodeId: 43,
                                  kind: ItemVariationNodeKind.property,
                                  name: 'Pump Finish',
                                  children: [
                                    _node(
                                      id: 45,
                                      itemId: 3,
                                      parentNodeId: 44,
                                      kind: ItemVariationNodeKind.value,
                                      name: 'Rose Gold',
                                      children: [
                                        _node(
                                          id: 46,
                                          itemId: 3,
                                          parentNodeId: 45,
                                          kind: ItemVariationNodeKind.property,
                                          name: 'Lock Type',
                                          children: [
                                            _node(
                                              id: 47,
                                              itemId: 3,
                                              parentNodeId: 46,
                                              kind: ItemVariationNodeKind.value,
                                              name: 'Right Lock',
                                              displayName:
                                                  'Glass Clear Rose Gold Right Lock',
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            ItemDefinition(
              id: 4,
              name: 'Premium Mono Carton',
              alias: 'Retail Carton',
              displayName: 'Premium Mono Carton - 500',
              quantity: 500,
              groupId: 2,
              unitId: 2,
              isArchived: false,
              usageCount: 0,
              createdAt: DateTime(2024),
              updatedAt: DateTime(2024),
              variationTree: [
                _node(
                  id: 48,
                  itemId: 4,
                  kind: ItemVariationNodeKind.property,
                  name: 'Board GSM',
                  children: [
                    _node(
                      id: 49,
                      itemId: 4,
                      parentNodeId: 48,
                      kind: ItemVariationNodeKind.value,
                      name: '300 GSM',
                      children: [
                        _node(
                          id: 50,
                          itemId: 4,
                          parentNodeId: 49,
                          kind: ItemVariationNodeKind.property,
                          name: 'Print Finish',
                          children: [
                            _node(
                              id: 51,
                              itemId: 4,
                              parentNodeId: 50,
                              kind: ItemVariationNodeKind.value,
                              name: 'Matte',
                              children: [
                                _node(
                                  id: 52,
                                  itemId: 4,
                                  parentNodeId: 51,
                                  kind: ItemVariationNodeKind.property,
                                  name: 'Foil',
                                  children: [
                                    _node(
                                      id: 53,
                                      itemId: 4,
                                      parentNodeId: 52,
                                      kind: ItemVariationNodeKind.value,
                                      name: 'Gold Foil',
                                      children: [
                                        _node(
                                          id: 54,
                                          itemId: 4,
                                          parentNodeId: 53,
                                          kind: ItemVariationNodeKind.property,
                                          name: 'Window',
                                          children: [
                                            _node(
                                              id: 55,
                                              itemId: 4,
                                              parentNodeId: 54,
                                              kind: ItemVariationNodeKind.value,
                                              name: 'With Window',
                                              displayName:
                                                  '300 GSM Matte Gold Foil With Window',
                                            ),
                                            _node(
                                              id: 56,
                                              itemId: 4,
                                              parentNodeId: 54,
                                              kind: ItemVariationNodeKind.value,
                                              name: 'No Window',
                                              displayName:
                                                  '300 GSM Matte Gold Foil No Window',
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            _node(
                              id: 57,
                              itemId: 4,
                              parentNodeId: 50,
                              kind: ItemVariationNodeKind.value,
                              name: 'Gloss',
                              children: [
                                _node(
                                  id: 58,
                                  itemId: 4,
                                  parentNodeId: 57,
                                  kind: ItemVariationNodeKind.property,
                                  name: 'Foil',
                                  children: [
                                    _node(
                                      id: 59,
                                      itemId: 4,
                                      parentNodeId: 58,
                                      kind: ItemVariationNodeKind.value,
                                      name: 'No Foil',
                                      children: [
                                        _node(
                                          id: 60,
                                          itemId: 4,
                                          parentNodeId: 59,
                                          kind: ItemVariationNodeKind.property,
                                          name: 'Window',
                                          children: [
                                            _node(
                                              id: 61,
                                              itemId: 4,
                                              parentNodeId: 60,
                                              kind: ItemVariationNodeKind.value,
                                              name: 'No Window',
                                              displayName:
                                                  '300 GSM Gloss No Foil No Window',
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    _node(
                      id: 62,
                      itemId: 4,
                      parentNodeId: 48,
                      kind: ItemVariationNodeKind.value,
                      name: '350 GSM',
                      children: [
                        _node(
                          id: 63,
                          itemId: 4,
                          parentNodeId: 62,
                          kind: ItemVariationNodeKind.property,
                          name: 'Print Finish',
                          children: [
                            _node(
                              id: 64,
                              itemId: 4,
                              parentNodeId: 63,
                              kind: ItemVariationNodeKind.value,
                              name: 'Matte',
                              children: [
                                _node(
                                  id: 65,
                                  itemId: 4,
                                  parentNodeId: 64,
                                  kind: ItemVariationNodeKind.property,
                                  name: 'Foil',
                                  children: [
                                    _node(
                                      id: 66,
                                      itemId: 4,
                                      parentNodeId: 65,
                                      kind: ItemVariationNodeKind.value,
                                      name: 'Rose Gold Foil',
                                      children: [
                                        _node(
                                          id: 67,
                                          itemId: 4,
                                          parentNodeId: 66,
                                          kind: ItemVariationNodeKind.property,
                                          name: 'Window',
                                          children: [
                                            _node(
                                              id: 68,
                                              itemId: 4,
                                              parentNodeId: 67,
                                              kind: ItemVariationNodeKind.value,
                                              name: 'With Window',
                                              displayName:
                                                  '350 GSM Matte Rose Gold Foil With Window',
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            ItemDefinition(
              id: 5,
              name: 'Legacy Stock',
              alias: '',
              displayName: 'Legacy Stock - 5',
              quantity: 5,
              groupId: 4,
              unitId: 1,
              isArchived: true,
              usageCount: 0,
              createdAt: DateTime(2024),
              updatedAt: DateTime(2024),
              variationTree: const [],
            ),
          ];

  final List<ItemDefinition> _items;
  int _nextId = 6;
  int _nextNodeId = 69;

  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async =>
      List<ItemDefinition>.from(_items);

  @override
  Future<ItemDefinition> createItem(CreateItemInput input) async {
    final duplicate = _items.any(
      (item) =>
          item.groupId == input.groupId &&
          item.name.trim().toLowerCase() == input.name.trim().toLowerCase(),
    );
    if (duplicate) {
      throw Exception(
        'An item with the same name already exists in this group.',
      );
    }
    _validateTree(input.variationTree, ItemVariationNodeKind.property);
    final itemId = _nextId++;
    final created = ItemDefinition(
      id: itemId,
      name: input.name.trim(),
      alias: input.alias.trim(),
      displayName: input.displayName.trim(),
      quantity: 0,
      groupId: input.groupId,
      unitId: input.unitId,
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      variationTree: _buildTree(input.variationTree, itemId, null),
    );
    _items.add(created);
    return created;
  }

  @override
  Future<ItemDefinition> updateItem(UpdateItemInput input) async {
    final index = _items.indexWhere((item) => item.id == input.id);
    final current = _items[index];
    _validateTree(input.variationTree, ItemVariationNodeKind.property);
    final updated = ItemDefinition(
      id: current.id,
      name: input.name.trim(),
      alias: input.alias.trim(),
      displayName: input.displayName.trim(),
      quantity: 0,
      groupId: input.groupId,
      unitId: input.unitId,
      isArchived: current.isArchived,
      usageCount: current.usageCount,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
      variationTree: _buildTree(input.variationTree, current.id, null),
    );
    _items[index] = updated;
    return updated;
  }

  @override
  Future<ItemDefinition> archiveItem(int id) async {
    final index = _items.indexWhere((item) => item.id == id);
    final current = _items[index];
    final updated = ItemDefinition(
      id: current.id,
      name: current.name,
      alias: current.alias,
      displayName: current.displayName,
      quantity: current.quantity,
      groupId: current.groupId,
      unitId: current.unitId,
      isArchived: true,
      usageCount: current.usageCount,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
      variationTree: current.variationTree,
    );
    _items[index] = updated;
    return updated;
  }

  @override
  Future<ItemDefinition> restoreItem(int id) async {
    final index = _items.indexWhere((item) => item.id == id);
    final current = _items[index];
    final updated = ItemDefinition(
      id: current.id,
      name: current.name,
      alias: current.alias,
      displayName: current.displayName,
      quantity: current.quantity,
      groupId: current.groupId,
      unitId: current.unitId,
      isArchived: false,
      usageCount: current.usageCount,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
      variationTree: current.variationTree,
    );
    _items[index] = updated;
    return updated;
  }

  @override
  Future<List<ItemAsset>> getItemAssets(int itemId) async {
    return const <ItemAsset>[];
  }

  @override
  Future<ItemAssetUploadIntent> createAssetUploadIntent(
    ItemAssetUploadIntentInput input,
  ) async {
    return ItemAssetUploadIntent(
      alreadyUploaded: false,
      upload: ItemAssetUploadTarget(
        uploadSessionId: 'test-session',
        objectKey:
            'masters/items/item-${input.itemId}/test-session-${input.fileName}',
        uploadUrl: Uri.parse('https://mock.local/test-session'),
        headers: const <String, String>{},
      ),
    );
  }

  @override
  Future<ItemAsset> completeAssetUpload(
    CompleteItemAssetUploadInput input,
  ) async {
    return ItemAsset(
      id: 1,
      entityType: 'item',
      entityId: 1,
      fileName: 'test.png',
      contentType: 'image/png',
      sizeBytes: 1,
      sha256: List.filled(64, '0').join(),
      objectKey: input.objectKey,
      status: 'uploaded',
      isPrimary: true,
      createdAt: DateTime.now(),
      uploadedAt: DateTime.now(),
    );
  }

  @override
  Future<ItemAsset> setPrimaryAsset(int assetId) async {
    return ItemAsset(
      id: assetId,
      entityType: 'item',
      entityId: 1,
      fileName: 'test.png',
      contentType: 'image/png',
      sizeBytes: 1,
      sha256: List.filled(64, '0').join(),
      objectKey: 'masters/items/item-1/test.png',
      status: 'uploaded',
      isPrimary: true,
    );
  }

  @override
  Future<void> deleteAsset(int assetId) async {}

  List<ItemVariationNodeDefinition> _buildTree(
    List<ItemVariationNodeInput> inputs,
    int itemId,
    int? parentNodeId,
  ) {
    return inputs
        .asMap()
        .entries
        .map((entry) {
          final input = entry.value;
          final nodeId = input.id ?? _nextNodeId++;
          final children = _buildTree(input.children, itemId, nodeId);
          return ItemVariationNodeDefinition(
            id: nodeId,
            itemId: itemId,
            parentNodeId: parentNodeId,
            kind: input.kind,
            name: input.name.trim(),
            displayName:
                children.isEmpty && input.kind == ItemVariationNodeKind.value
                ? input.displayName.trim()
                : '',
            position: entry.key,
            isArchived: false,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            children: children,
          );
        })
        .toList(growable: false);
  }

  void _validateTree(
    List<ItemVariationNodeInput> nodes,
    ItemVariationNodeKind expectedKind,
  ) {
    final siblingNames = <String>{};
    for (final node in nodes) {
      final normalizedName = node.name.trim().toLowerCase();
      if (normalizedName.isEmpty) {
        throw Exception('Variation tree node names are required.');
      }
      if (node.kind != expectedKind) {
        throw Exception(
          'Variation tree must alternate between property groups and values.',
        );
      }
      if (!siblingNames.add(normalizedName)) {
        throw Exception('Sibling variation nodes must have unique names.');
      }
      _validateTree(
        node.children,
        expectedKind == ItemVariationNodeKind.property
            ? ItemVariationNodeKind.value
            : ItemVariationNodeKind.property,
      );
    }
  }
}

class FakeOrderRepository extends OrderRepository {
  FakeOrderRepository({List<OrderEntry> seedOrders = const <OrderEntry>[]})
    : _orders = List<OrderEntry>.from(seedOrders),
      _nextId = seedOrders.isEmpty
          ? 1
          : seedOrders
                    .map((order) => order.id)
                    .reduce(
                      (value, element) => value > element ? value : element,
                    ) +
                1;

  final List<OrderEntry> _orders;
  final List<PoDocumentEntry> _documents = <PoDocumentEntry>[];
  final Map<int, List<OrderActivityEntry>> _activities =
      <int, List<OrderActivityEntry>>{};
  final Map<int, List<OrderStatusHistoryEntry>> _statusHistory =
      <int, List<OrderStatusHistoryEntry>>{};
  final Map<int, Set<int>> _orderDocumentIds = <int, Set<int>>{};
  final Map<String, PoUploadIntentInput> _uploadSessions =
      <String, PoUploadIntentInput>{};
  int _nextId;
  int _nextDocumentId = 1;

  @override
  Future<void> init() async {}

  @override
  Future<List<OrderEntry>> getOrders() async => List<OrderEntry>.from(_orders);

  @override
  Future<OrderEntry> createOrder(CreateOrderInput input) async {
    final normalizedOrderNo = input.orderNo.trim().toLowerCase();
    final normalizedPoNo = input.poNumber.trim().toLowerCase();
    final index = _orders.indexWhere(
      (order) =>
          order.orderNo.trim().toLowerCase() == normalizedOrderNo &&
          order.clientId == input.clientId &&
          order.itemId == input.itemId &&
          order.variationLeafNodeId == input.variationLeafNodeId &&
          order.poNumber.trim().toLowerCase() == normalizedPoNo &&
          _sameMoment(order.startDate, input.startDate) &&
          _sameMoment(order.endDate, input.endDate),
    );
    if (index != -1) {
      final current = _orders[index];
      final updated = OrderEntry(
        id: current.id,
        orderNo: input.orderNo.trim(),
        clientId: input.clientId,
        clientName: input.clientName.trim(),
        poNumber: input.poNumber.trim(),
        clientCode: input.clientCode.trim(),
        itemId: input.itemId,
        itemName: input.itemName.trim(),
        variationLeafNodeId: input.variationLeafNodeId,
        variationPathLabel: input.variationPathLabel.trim(),
        variationPathNodeIds: List<int>.from(input.variationPathNodeIds),
        quantity: current.quantity + input.quantity,
        unitPrice: input.unitPrice > 0 ? input.unitPrice : current.unitPrice,
        totalInvoicedQty: input.totalInvoicedQty > 0
            ? input.totalInvoicedQty
            : current.totalInvoicedQty,
        status: input.status,
        createdAt: current.createdAt,
        startDate: input.startDate,
        endDate: input.endDate,
      );
      _orders[index] = updated;
      await linkPoDocuments(updated.id, input.poDocumentIds);
      _recordActivity(updated.id, 'order_updated');
      return updated;
    }

    final created = OrderEntry(
      id: _nextId++,
      orderNo: input.orderNo.trim(),
      clientId: input.clientId,
      clientName: input.clientName.trim(),
      poNumber: input.poNumber.trim(),
      clientCode: input.clientCode.trim(),
      itemId: input.itemId,
      itemName: input.itemName.trim(),
      variationLeafNodeId: input.variationLeafNodeId,
      variationPathLabel: input.variationPathLabel.trim(),
      variationPathNodeIds: List<int>.from(input.variationPathNodeIds),
      quantity: input.quantity,
      unitPrice: input.unitPrice,
      totalInvoicedQty: input.totalInvoicedQty,
      status: input.status,
      createdAt: DateTime.now(),
      startDate: input.startDate,
      endDate: input.endDate,
    );
    _orders.add(created);
    await linkPoDocuments(created.id, input.poDocumentIds);
    _recordActivity(created.id, 'order_created');
    return created;
  }

  @override
  Future<PoUploadIntent> createPoUploadIntent(PoUploadIntentInput input) async {
    final existing = _documents
        .where((document) => document.sha256 == input.sha256)
        .firstOrNull;
    if (existing != null) {
      return PoUploadIntent(alreadyUploaded: true, document: existing);
    }
    final sessionId = 'test-session-${_uploadSessions.length + 1}';
    _uploadSessions[sessionId] = input;
    return PoUploadIntent(
      alreadyUploaded: false,
      upload: PoUploadTarget(
        uploadSessionId: sessionId,
        objectKey: 'orders/po-docs/$sessionId-${input.fileName}',
        uploadUrl: Uri.parse('https://mock.local/$sessionId'),
        headers: const <String, String>{},
      ),
    );
  }

  @override
  Future<PoDocumentEntry> completePoUpload(CompletePoUploadInput input) async {
    final session = _uploadSessions[input.uploadSessionId];
    if (session == null) {
      throw Exception('Upload session not found.');
    }
    final existing = _documents
        .where((document) => document.sha256 == session.sha256)
        .firstOrNull;
    if (existing != null) {
      return existing;
    }
    final now = DateTime.now();
    final document = PoDocumentEntry(
      id: _nextDocumentId++,
      fileName: session.fileName,
      contentType: session.contentType,
      sizeBytes: session.sizeBytes,
      sha256: session.sha256,
      objectKey: input.objectKey,
      status: 'uploaded',
      createdAt: now,
      uploadedAt: now,
    );
    _documents.add(document);
    return document;
  }

  @override
  Future<List<PoDocumentEntry>> getPoDocuments(int orderId) async {
    final ids = _orderDocumentIds[orderId] ?? const <int>{};
    return _documents
        .where((document) => ids.contains(document.id))
        .toList(growable: false);
  }

  @override
  Future<List<OrderActivityEntry>> getOrderActivity(int orderId) async {
    return List<OrderActivityEntry>.from(
      _activities[orderId] ??
          <OrderActivityEntry>[
            OrderActivityEntry(
              id: 1,
              orderId: orderId,
              activityType: 'order_created',
              actorName: 'Demo Admin',
              actorRole: 'admin',
              source: 'test',
              createdAt: DateTime(2024),
            ),
          ],
    );
  }

  @override
  Future<List<OrderStatusHistoryEntry>> getOrderStatusHistory(
    int orderId,
  ) async {
    return List<OrderStatusHistoryEntry>.from(
      _statusHistory[orderId] ?? const <OrderStatusHistoryEntry>[],
    );
  }

  @override
  Future<void> linkPoDocuments(int orderId, List<int> documentIds) async {
    if (documentIds.isEmpty) {
      return;
    }
    final bucket = _orderDocumentIds.putIfAbsent(orderId, () => <int>{});
    bucket.addAll(documentIds);
  }

  @override
  Future<Uri> createPoDocumentReadUrl(int documentId) async {
    return Uri.parse('https://mock.local/po-documents/$documentId');
  }

  @override
  Future<OrderEntry> updateOrderLifecycle(
    UpdateOrderLifecycleInput input,
  ) async {
    final index = _orders.indexWhere((order) => order.id == input.id);
    final current = _orders[index];
    final updated = OrderEntry(
      id: current.id,
      orderNo: current.orderNo,
      clientId: current.clientId,
      clientName: current.clientName,
      poNumber: current.poNumber,
      clientCode: current.clientCode,
      itemId: current.itemId,
      itemName: current.itemName,
      variationLeafNodeId: current.variationLeafNodeId,
      variationPathLabel: current.variationPathLabel,
      variationPathNodeIds: current.variationPathNodeIds,
      quantity: current.quantity,
      unitPrice: current.unitPrice,
      totalInvoicedQty: current.totalInvoicedQty,
      status: input.status,
      createdAt: current.createdAt,
      startDate: input.startDate,
      endDate: input.endDate,
    );
    _orders[index] = updated;
    if (current.status != updated.status) {
      final history = _statusHistory.putIfAbsent(
        updated.id,
        () => <OrderStatusHistoryEntry>[],
      );
      history.add(
        OrderStatusHistoryEntry(
          id: history.length + 1,
          orderId: updated.id,
          previousStatus: current.status.name,
          newStatus: updated.status.name,
          changedAt: DateTime.now(),
        ),
      );
    }
    _recordActivity(updated.id, 'lifecycle_updated');
    return updated;
  }

  void _recordActivity(int orderId, String activityType) {
    final rows = _activities.putIfAbsent(orderId, () => <OrderActivityEntry>[]);
    rows.add(
      OrderActivityEntry(
        id: rows.length + 1,
        orderId: orderId,
        activityType: activityType,
        actorName: 'Demo Admin',
        actorRole: 'admin',
        source: 'test',
        createdAt: DateTime.now(),
      ),
    );
  }

  bool _sameMoment(DateTime? left, DateTime? right) {
    if (left == null || right == null) {
      return left == right;
    }
    return left.toUtc().millisecondsSinceEpoch ==
        right.toUtc().millisecondsSinceEpoch;
  }
}

class FakeDeliveryChallanRepository extends DeliveryChallanRepository {
  FakeDeliveryChallanRepository({
    List<DeliveryChallan>? seedChallans,
    List<ChallanTemplate>? seedTemplates,
    CompanyProfile? companyProfile,
    ReconciliationReportSnapshot? reconciliationReport,
  }) : _challans = List<DeliveryChallan>.from(seedChallans ?? const []),
       _templates = List<ChallanTemplate>.from(seedTemplates ?? const []),
       _reconciliationReport =
           reconciliationReport ?? ReconciliationReportSnapshot.empty() {
    if (companyProfile != null) {
      _companyProfile = companyProfile;
    }
  }

  int getChallansCalls = 0;
  int getCompanyProfileCalls = 0;
  int createInvoiceCalls = 0;
  int generateClientStatementReportCalls = 0;
  int saveConversionOverrideCalls = 0;
  List<String> lastClientStatementChallanNos = const <String>[];
  final List<DeliveryChallan> _challans;
  final List<ChallanTemplate> _templates;
  final List<InvoiceHeader> createdInvoices = <InvoiceHeader>[];
  final List<ConversionOverride> savedConversionOverrides =
      <ConversionOverride>[];
  final ReconciliationReportSnapshot _reconciliationReport;
  CompanyProfile _companyProfile = const CompanyProfile(
    id: 1,
    companyName: 'Paper ERP',
    mobile: '9999999999',
    businessDescription: 'Packaging and paper conversion',
    address: 'Pune',
    stateCode: '27',
    gstin: '27ABCDE1234F1Z5',
    logoUrl: '',
    signatureLabel: 'Ops Admin',
  );

  @override
  String? get lastWarningMessage => null;

  @override
  Future<void> init() async {}

  @override
  Future<CompanyProfile> getCompanyProfile() async {
    getCompanyProfileCalls += 1;
    return _companyProfile;
  }

  @override
  Future<List<DeliveryChallan>> getChallans({
    ChallanType? type,
    DeliveryChallanStatus? status,
    String search = '',
    DateTime? dateFrom,
    DateTime? dateTo,
    int? orderId,
  }) async {
    getChallansCalls += 1;
    final query = search.trim().toLowerCase();
    return _challans
        .where((challan) {
          if (type != null && challan.type != type) {
            return false;
          }
          if (status != null && challan.status != status) {
            return false;
          }
          if (orderId != null && challan.orderId != orderId) {
            return false;
          }
          if (dateFrom != null && challan.date.isBefore(dateFrom)) {
            return false;
          }
          if (dateTo != null && challan.date.isAfter(dateTo)) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          final haystack = <String>[
            challan.challanNo,
            challan.orderNo,
            challan.customerName,
            challan.vendorName,
            challan.sourceReference,
            challan.location,
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  @override
  Future<List<DeliveryChallan>> getOrderChallans(int orderId) async => _challans
      .where((challan) => challan.orderId == orderId)
      .toList(growable: false);

  @override
  Future<DeliveryChallan> getChallan(int id) async {
    return _challans.firstWhere((challan) => challan.id == id);
  }

  @override
  Future<DeliveryChallan> createChallan(DeliveryChallanDraftInput input) async {
    throw UnimplementedError();
  }

  @override
  Future<DeliveryChallan> updateChallan(
    int id,
    DeliveryChallanDraftInput input,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<DeliveryChallan> issueChallan(int id) async {
    throw UnimplementedError();
  }

  @override
  Future<DeliveryChallan> cancelChallan(int id) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteChallan(int id) async {}

  @override
  Future<void> recordPrint(int id) async {}

  @override
  Future<ReconciliationReportSnapshot> getReconciliationReport() async =>
      _reconciliationReport;

  @override
  Future<List<InvoiceHeader>> getInvoices() async => const <InvoiceHeader>[];

  @override
  Future<InvoiceHeader> getInvoice(int id) async {
    throw UnimplementedError();
  }

  @override
  Future<InvoiceHeader> createInvoice(InvoiceDraftInput input) async {
    createInvoiceCalls += 1;
    final id = createdInvoices.length + 1;
    final lines = input.lines
        .asMap()
        .entries
        .map((entry) {
          final source = entry.value;
          final taxableValue = source.quantity * source.unitPrice;
          return InvoiceLine(
            id: entry.key + 1,
            invoiceId: id,
            orderId: source.orderId,
            challanId: source.challanId,
            challanItemId: source.challanItemId,
            itemId: source.itemId,
            variationLeafNodeId: source.variationLeafNodeId,
            itemName: source.itemName,
            hsnCode: source.hsnCode,
            quantity: source.quantity,
            unitPrice: source.unitPrice,
            taxableValue: taxableValue,
            cgstRate: source.cgstRate,
            sgstRate: source.sgstRate,
            cgstAmount: taxableValue * source.cgstRate / 100,
            sgstAmount: taxableValue * source.sgstRate / 100,
          );
        })
        .toList(growable: false);
    final taxableValue = lines.fold<double>(
      0,
      (sum, line) => sum + line.taxableValue,
    );
    final cgstAmount = lines.fold<double>(
      0,
      (sum, line) => sum + line.cgstAmount,
    );
    final sgstAmount = lines.fold<double>(
      0,
      (sum, line) => sum + line.sgstAmount,
    );
    final invoice = InvoiceHeader(
      id: id,
      invoiceNo: input.invoiceNo.trim().isEmpty
          ? 'INV-${id.toString().padLeft(5, '0')}'
          : input.invoiceNo.trim(),
      clientId: input.clientId,
      clientName: input.clientName,
      gstin: input.gstin,
      status: 'draft',
      invoiceDate: input.invoiceDate,
      totalQuantity: lines.fold<double>(0, (sum, line) => sum + line.quantity),
      taxableValue: taxableValue,
      cgstAmount: cgstAmount,
      sgstAmount: sgstAmount,
      totalAmount: taxableValue + cgstAmount + sgstAmount,
      lines: lines,
    );
    createdInvoices.add(invoice);
    return invoice;
  }

  @override
  Future<List<ConversionOverride>> getConversionOverrides() async =>
      const <ConversionOverride>[];

  @override
  Future<ConversionOverride> saveConversionOverride(
    ConversionOverrideInput input,
  ) async {
    saveConversionOverrideCalls += 1;
    final override = ConversionOverride(
      id: savedConversionOverrides.length + 1,
      itemId: input.itemId,
      variationLeafNodeId: input.variationLeafNodeId,
      conversionRatio: input.conversionRatio,
      fromUnit: 'kg',
      toUnitLabel: input.toUnitLabel,
      updatedAt: DateTime(2026, 5, 12),
    );
    savedConversionOverrides.add(override);
    return override;
  }

  @override
  Future<List<WasteAuditRow>> getWasteAuditRows() async =>
      const <WasteAuditRow>[];

  @override
  Future<ClientStatementReport> generateClientStatementReport(
    List<String> challanNos,
  ) async {
    generateClientStatementReportCalls += 1;
    lastClientStatementChallanNos = List<String>.from(challanNos);
    final selected = _challans
        .where(
          (challan) =>
              challanNos.contains(challan.challanNo) &&
              challan.type == ChallanType.delivery &&
              challan.status == DeliveryChallanStatus.issued,
        )
        .toList(growable: false);
    final rows = selected
        .expand(
          (challan) => challan.items.map(
            (item) => ClientStatementReportRow(
              date: challan.date,
              challanNo: challan.challanNo,
              clientName: challan.customerName,
              orderNo: challan.orderNo,
              itemName: item.particulars,
              note: item.note,
              quantityPcs: double.tryParse(item.quantityPcs) ?? 0,
              weight: double.tryParse(item.weight) ?? 0,
            ),
          ),
        )
        .toList(growable: false);
    return ClientStatementReport(
      rows: rows,
      challanCount: selected.length,
      totalQuantityPcs: rows.fold<double>(
        0,
        (sum, row) => sum + row.quantityPcs,
      ),
      totalWeight: rows.fold<double>(0, (sum, row) => sum + row.weight),
      generatedAt: DateTime(2026, 5, 19),
    );
  }

  @override
  Future<List<CompletedProductionRun>> getCompletedProductionRuns({
    String search = '',
    int limit = 25,
  }) async => const <CompletedProductionRun>[];

  @override
  Future<List<ChallanTemplate>> getTemplates({
    ChallanTemplatePartyType? partyType,
    int? partyId,
    ChallanType? challanType,
    bool activeOnly = false,
  }) async => _templates
      .where((template) {
        if (partyType != null && template.partyType != partyType) {
          return false;
        }
        if (partyId != null && template.partyId != partyId) {
          return false;
        }
        if (challanType != null && template.challanType != challanType) {
          return false;
        }
        if (activeOnly && !template.isActive) {
          return false;
        }
        return true;
      })
      .toList(growable: false);

  @override
  Future<List<ChallanTemplateScan>> getTemplateScans({int limit = 24}) async =>
      const <ChallanTemplateScan>[];

  @override
  Future<ChallanTemplate> createTemplate(ChallanTemplateInput input) async {
    final created = ChallanTemplate(
      id: _templates.isEmpty
          ? 1
          : (_templates.map((template) => template.id).reduce(math.max) + 1),
      name: input.name,
      partyType: input.partyType,
      partyId: input.partyId,
      challanType: input.challanType,
      backgroundObjectKey: input.backgroundObjectKey,
      backgroundImageUrl: '',
      canvasWidth: input.canvasWidth,
      canvasHeight: input.canvasHeight,
      rotationDegrees: input.rotationDegrees,
      globalOffsetXmm: input.globalOffsetXmm,
      globalOffsetYmm: input.globalOffsetYmm,
      stockSize: input.stockSize,
      paperSize: input.paperSize,
      nUpLayout: input.nUpLayout,
      isActive: input.isActive,
      mappings: input.mappings,
    );
    _templates.add(created);
    return created;
  }

  @override
  Future<ChallanTemplate> updateTemplate(
    int id,
    ChallanTemplateInput input,
  ) async {
    final index = _templates.indexWhere((template) => template.id == id);
    final updated = ChallanTemplate(
      id: id,
      name: input.name,
      partyType: input.partyType,
      partyId: input.partyId,
      challanType: input.challanType,
      backgroundObjectKey: input.backgroundObjectKey,
      backgroundImageUrl: '',
      canvasWidth: input.canvasWidth,
      canvasHeight: input.canvasHeight,
      rotationDegrees: input.rotationDegrees,
      globalOffsetXmm: input.globalOffsetXmm,
      globalOffsetYmm: input.globalOffsetYmm,
      stockSize: input.stockSize,
      paperSize: input.paperSize,
      nUpLayout: input.nUpLayout,
      isActive: input.isActive,
      mappings: input.mappings,
    );
    if (index >= 0) {
      _templates[index] = updated;
    } else {
      _templates.add(updated);
    }
    return updated;
  }

  @override
  Future<void> deleteTemplate(int id) async {}

  @override
  Future<ChallanTemplateUploadTarget> createTemplateUploadIntent(
    ChallanTemplateUploadIntentInput input,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<ChallanTemplateBackground> completeTemplateUpload({
    required String uploadSessionId,
    required String objectKey,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChallanTemplateUploadTarget> createTemplateStampUploadIntent(
    ChallanTemplateUploadIntentInput input,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<ChallanTemplateBackground> completeTemplateStampUpload({
    required String uploadSessionId,
    required String objectKey,
  }) {
    throw UnimplementedError();
  }

  @override
  Uri templatePreviewUri({
    required int challanId,
    int? templateId,
    required String mode,
  }) => Uri.parse('https://mock.local/challans/$challanId/$mode');

  @override
  Future<Uint8List> fetchTemplatePreviewPdf({
    required int challanId,
    int? templateId,
    required String mode,
  }) async => Uint8List.fromList(<int>[37, 80, 68, 70]);

  @override
  Uri templateTestPrintUri({
    required int templateId,
    required String mode,
    int? itemCount,
  }) => Uri.parse(
    'https://mock.local/templates/$templateId/$mode${itemCount != null ? '?itemCount=$itemCount' : ''}',
  );

  @override
  Future<Uint8List> fetchTemplateTestPrintPdf({
    required int templateId,
    required String mode,
    int? itemCount,
    List<ChallanTemplateMapping>? mappings,
  }) async => Uint8List.fromList(<int>[37, 80, 68, 70]);

  @override
  Future<CompanyProfile> updateCompanyProfile(CompanyProfile profile) async {
    _companyProfile = profile;
    return profile;
  }
}

class TrackingInventoryRepository extends FakeInventoryRepository {
  int getAllMaterialsCalls = 0;

  @override
  Future<List<MaterialRecord>> getAllMaterials() async {
    getAllMaterialsCalls += 1;
    return super.getAllMaterials();
  }
}

class TrackingUnitRepository extends FakeUnitRepository {
  int getUnitsCalls = 0;

  @override
  Future<List<UnitDefinition>> getUnits() async {
    getUnitsCalls += 1;
    return super.getUnits();
  }
}

class TrackingGroupRepository extends FakeGroupRepository {
  int getGroupsCalls = 0;

  @override
  Future<List<GroupDefinition>> getGroups() async {
    getGroupsCalls += 1;
    return super.getGroups();
  }
}

class TrackingClientRepository extends FakeClientRepository {
  int getClientsCalls = 0;

  @override
  Future<List<ClientDefinition>> getClients() async {
    getClientsCalls += 1;
    return super.getClients();
  }
}

class TrackingItemRepository extends FakeItemRepository {
  int getItemsCalls = 0;

  @override
  Future<List<ItemDefinition>> getItems() async {
    getItemsCalls += 1;
    return super.getItems();
  }
}

class TrackingOrderRepository extends FakeOrderRepository {
  int getOrdersCalls = 0;

  @override
  Future<List<OrderEntry>> getOrders() async {
    getOrdersCalls += 1;
    return super.getOrders();
  }
}

class FakeAuthProvider extends AuthProvider {
  FakeAuthProvider({bool authenticated = true, bool canWriteConfig = true})
    : _authenticated = authenticated,
      _tokenValue = authenticated ? 'test-token' : null,
      _canWriteConfig = canWriteConfig,
      super(baseUrl: 'http://localhost');

  bool _authenticated;
  String? _tokenValue;
  final bool _canWriteConfig;
  int clearCalls = 0;
  int resetCalls = 0;
  String? _error;

  @override
  bool get isAuthenticated => _authenticated;

  @override
  String? get token => _tokenValue;

  @override
  String? get errorMessage => _error;

  @override
  bool get canAccessUserManagement => _authenticated;

  @override
  bool can(String permissionKey) {
    if (!_authenticated) {
      return false;
    }
    if (permissionKey == 'config.write') {
      return _canWriteConfig;
    }
    return true;
  }

  @override
  Future<bool> clearBackendDatabase() async {
    clearCalls += 1;
    _error = null;
    notifyListeners();
    return true;
  }

  @override
  Future<bool> resetDemoData() async {
    resetCalls += 1;
    _error = null;
    notifyListeners();
    return true;
  }

  void authenticate({String token = 'test-token'}) {
    _authenticated = true;
    _tokenValue = token;
    notifyListeners();
  }
}

ItemVariationNodeDefinition _node({
  required int id,
  required int itemId,
  int? parentNodeId,
  required ItemVariationNodeKind kind,
  required String name,
  String displayName = '',
  int position = 0,
  List<ItemVariationNodeDefinition> children = const [],
}) {
  return ItemVariationNodeDefinition(
    id: id,
    itemId: itemId,
    parentNodeId: parentNodeId,
    kind: kind,
    name: name,
    displayName: displayName,
    position: position,
    isArchived: false,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
    children: children,
  );
}

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    AuthProvider? authProvider,
    FakeInventoryRepository? repository,
    FakeGroupRepository? groupRepository,
    FakeUnitRepository? unitRepository,
    FakeClientRepository? clientRepository,
    VendorRepository? vendorRepository,
    FakeItemRepository? itemRepository,
    FakeOrderRepository? orderRepository,
    DeliveryChallanRepository? deliveryChallanRepository,
    Size viewSize = const Size(1280, 900),
  }) async {
    tester.view.physicalSize = viewSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MyApp(
        demoModeOverride: true,
        authProvider: authProvider,
        inventoryRepository: repository ?? FakeInventoryRepository(),
        groupRepository: groupRepository ?? FakeGroupRepository(),
        unitRepository: unitRepository ?? FakeUnitRepository(),
        clientRepository: clientRepository ?? FakeClientRepository(),
        vendorRepository: vendorRepository ?? FakeVendorRepository(),
        deliveryChallanRepository:
            deliveryChallanRepository ?? FakeDeliveryChallanRepository(),
        itemRepository: itemRepository ?? FakeItemRepository(),
        orderRepository: orderRepository ?? FakeOrderRepository(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openOrdersScreen(WidgetTester tester) async {
    final sidebarTile = find.byKey(
      const ValueKey<String>('sidebar_tile_orders'),
    );
    if (sidebarTile.evaluate().isNotEmpty) {
      await tester.tap(sidebarTile);
      await tester.pumpAndSettle();
      return;
    }

    final context = tester.element(find.byType(Scaffold).first);
    context.read<NavigationProvider>().select('orders', skipTransition: true);
    await tester.pumpAndSettle();
  }

  Future<void> openClientsScreen(WidgetTester tester) async {
    final context = tester.element(find.byType(Scaffold).first);
    context.read<NavigationProvider>().select(
      'configurator_clients',
      skipTransition: true,
    );
    await tester.pumpAndSettle();
  }

  Future<void> openVendorsScreen(WidgetTester tester) async {
    final context = tester.element(find.byType(Scaffold).first);
    context.read<NavigationProvider>().select(
      'configurator_vendors',
      skipTransition: true,
    );
    await tester.pumpAndSettle();
  }

  Future<void> openGroupsScreen(WidgetTester tester) async {
    final context = tester.element(find.byType(Scaffold).first);
    context.read<NavigationProvider>().select(
      'configurator_groups',
      skipTransition: true,
    );
    await tester.pumpAndSettle();
  }

  Future<void> openUnitsScreen(WidgetTester tester) async {
    final context = tester.element(find.byType(Scaffold).first);
    context.read<NavigationProvider>().select(
      'configurator_units',
      skipTransition: true,
    );
    await tester.pumpAndSettle();
  }

  Future<void> openItemsScreen(WidgetTester tester) async {
    final context = tester.element(find.byType(Scaffold).first);
    context.read<NavigationProvider>().select(
      'configurator_items',
      skipTransition: true,
    );
    await tester.pumpAndSettle();
  }

  Future<void> openChallansScreen(WidgetTester tester) async {
    final context = tester.element(find.byType(Scaffold).first);
    context.read<NavigationProvider>().select(
      'delivery_challans',
      skipTransition: true,
    );
    await tester.pumpAndSettle();
  }

  Finder treeNameEditor(String hintText) {
    return find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.hintText == hintText,
    );
  }

  Finder searchFieldWithHint(String hintText) {
    return find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.hintText == hintText,
    );
  }

  Future<void> startEditingLatestTreeNode(WidgetTester tester) async {
    final editButton = find
        .widgetWithIcon(IconButton, Icons.edit_outlined)
        .last;
    tester.widget<IconButton>(editButton).onPressed?.call();
    await tester.pumpAndSettle();
  }

  Future<void> openVariationPathSelector(WidgetTester tester) async {
    if (find.text('Select Variation Path').evaluate().isNotEmpty) {
      return;
    }
    final variationField = find.byKey(
      const ValueKey<String>('orders-editor-variation-path-field'),
    );
    await tester.ensureVisible(variationField);
    await tester.tap(variationField, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  Future<void> selectOpenVariationPath(
    WidgetTester tester, {
    required String itemLabel,
    required List<String> variationValues,
  }) async {
    await openVariationPathSelector(tester);
    if (find
        .widgetWithText(TextField, 'Search variation path')
        .evaluate()
        .isNotEmpty) {
      final optionLabel = '$itemLabel • ${variationValues.join(' | ')}';
      await tester.enterText(
        find.widgetWithText(TextField, 'Search variation path'),
        variationValues.last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(optionLabel).last);
      await tester.pumpAndSettle();
      return;
    }
    for (final value in variationValues) {
      final selectValueField = find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'orders-variation-step-',
                ),
          )
          .last;
      await tester.ensureVisible(selectValueField);
      await tester.tap(selectValueField);
      await tester.pumpAndSettle();

      final optionFinder = find.text(value).last;
      await tester.ensureVisible(optionFinder);
      await tester.tap(optionFinder);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Apply Path').last);
    await tester.pumpAndSettle();
  }

  Future<void> selectPrimaryVariationPath(
    WidgetTester tester, {
    String itemLabel = 'Switch Action Dolly - 1',
    String variationPathText = 'Without Plating',
    List<String>? variationValues,
  }) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-item-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(itemLabel).last);
    await tester.pumpAndSettle();

    await selectOpenVariationPath(
      tester,
      itemLabel: itemLabel,
      variationValues:
          variationValues ??
          <String>[
            if (itemLabel == 'Glue Compound - 1') ...[
              variationPathText,
            ] else ...[
              '5 Amp',
              '11+1',
              'Brass',
              '1 Way',
              'Dolly',
              variationPathText.contains('With Plating')
                  ? 'With Plating'
                  : 'Without Plating',
            ],
          ],
    );
  }

  Future<void> changeOpenVariationValue(
    WidgetTester tester, {
    required String itemLabel,
    required String currentValue,
    required String newValue,
  }) async {
    await openVariationPathSelector(tester);
    if (find
        .widgetWithText(TextField, 'Search variation path')
        .evaluate()
        .isNotEmpty) {
      await tester.enterText(
        find.widgetWithText(TextField, 'Search variation path'),
        newValue,
      );
      await tester.pumpAndSettle();
      final currentSegments = currentValue == 'Without Plating'
          ? <String>['5 Amp', '11+1', 'Brass', '1 Way', 'Dolly']
          : <String>[];
      final optionLabel = currentSegments.isEmpty
          ? '$itemLabel • $newValue'
          : '$itemLabel • ${[...currentSegments, newValue].join(' | ')}';
      await tester.tap(find.text(optionLabel).last);
      await tester.pumpAndSettle();
      return;
    }
    final currentValueField = find
        .ancestor(
          of: find.text(currentValue).last,
          matching: find.byType(InkWell),
        )
        .last;
    await tester.ensureVisible(currentValueField);
    await tester.tap(currentValueField);
    await tester.pumpAndSettle();

    final newValueOption = find.text(newValue).last;
    await tester.ensureVisible(newValueOption);
    await tester.tap(newValueOption);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apply Path').last);
    await tester.pumpAndSettle();
  }

  testWidgets('app opens into inventory shell', (tester) async {
    await pumpApp(tester);

    expect(find.text('+ Add Stock'), findsOneWidget);
    expect(find.text('Inventory'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('shell_top_strip_search_field')),
      findsOneWidget,
    );
  });

  testWidgets('desktop shell top strip switches config by navigation key', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('Inventory'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('shell_top_strip_search_field')),
      findsOneWidget,
    );

    await openClientsScreen(tester);
    expect(find.byType(TextField), findsOneWidget);

    await openItemsScreen(tester);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('masters submenu animates closed and reopens from down arrow', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(1440, 900));

    await openUnitsScreen(tester);

    expect(
      find.byKey(const ValueKey<String>('sidebar_tile_configurator_units')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar_tile_configurator')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('sidebar_tile_configurator_units')),
      findsNothing,
    );
    var chevronRotation = tester.widget<AnimatedRotation>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('sidebar_configurator_chevron')),
        matching: find.byType(AnimatedRotation),
      ),
    );
    expect(chevronRotation.turns, 0.0);

    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar_tile_configurator')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('sidebar_tile_configurator_units')),
      findsOneWidget,
    );
    chevronRotation = tester.widget<AnimatedRotation>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('sidebar_configurator_chevron')),
        matching: find.byType(AnimatedRotation),
      ),
    );
    expect(chevronRotation.turns, 0.5);
  });

  testWidgets('ctrl+tab cycles sidebar navigation forward', (tester) async {
    await pumpApp(tester, viewSize: const Size(1440, 900));

    await openOrdersScreen(tester);
    final context = tester.element(find.byType(Scaffold).first);
    expect(context.read<NavigationProvider>().selectedKey, 'orders');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(context.read<NavigationProvider>().selectedKey, 'delivery_challans');
  });

  testWidgets(
    'challans hub exposes contextual delivery and reception create flows',
    (tester) async {
      await pumpApp(tester, viewSize: const Size(1440, 900));
      await openChallansScreen(tester);

      expect(find.text('Delivery'), findsWidgets);
      expect(find.text('Reception'), findsWidgets);
      expect(find.text('Create Delivery'), findsWidgets);
      expect(find.text('Create Reception'), findsNothing);

      await tester.tap(find.text('Reception').first);
      await tester.pumpAndSettle();
      expect(find.text('Create Reception'), findsWidgets);
      expect(find.text('Create Delivery'), findsNothing);

      await tester.tap(find.text('Create Reception').first);
      await tester.pumpAndSettle();
      expect(find.text('Create Reception Challan'), findsOneWidget);
      expect(find.text('Vendor'), findsOneWidget);
      expect(find.text('Select order'), findsNothing);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delivery').first);
      await tester.pumpAndSettle();
      expect(find.text('Create Delivery'), findsWidgets);
      expect(find.text('Create Reception'), findsNothing);

      await tester.tap(find.text('Create Delivery').first);
      await tester.pumpAndSettle();
      expect(find.text('Create Delivery Challan'), findsOneWidget);
      expect(find.text('fetch order ↗︎'), findsOneWidget);
      expect(find.text('Vendor'), findsNothing);
    },
  );

  testWidgets('challans type toggle separates reception and delivery rows', (
    tester,
  ) async {
    final challanRepository = FakeDeliveryChallanRepository(
      seedChallans: <DeliveryChallan>[
        DeliveryChallan(
          id: 1,
          type: ChallanType.delivery,
          orderId: 10,
          orderIds: const <int>[10],
          clientId: 1,
          orderNo: 'ORD-10',
          orderNos: const <String>['ORD-10'],
          challanNo: 'DC-00001',
          date: DateTime(2026, 5, 11),
          location: 'Dispatch Bay',
          customerName: 'Acme Packaging',
          customerGstin: '27AAAAA0000A1Z5',
          vendorId: null,
          vendorName: '',
          vendorGstin: '',
          sourceReference: '',
          companyProfileSnapshot: null,
          notes: '',
          maintainStocks: true,
          status: DeliveryChallanStatus.draft,
          items: const <DeliveryChallanItem>[],
          itemsCount: 1,
          createdAt: DateTime(2026, 5, 11),
          updatedAt: DateTime(2026, 5, 11),
        ),
        DeliveryChallan(
          id: 2,
          type: ChallanType.reception,
          orderId: null,
          orderIds: const <int>[],
          clientId: null,
          orderNo: '',
          orderNos: const <String>[],
          challanNo: 'RC-00001',
          date: DateTime(2026, 5, 11),
          location: 'Inbound Dock',
          customerName: '',
          customerGstin: '',
          vendorId: 3,
          vendorName: 'Supplier A',
          vendorGstin: '27ABCDE1234F1Z5',
          sourceReference: 'GRN-101',
          companyProfileSnapshot: null,
          notes: '',
          maintainStocks: true,
          status: DeliveryChallanStatus.issued,
          items: const <DeliveryChallanItem>[],
          itemsCount: 1,
          createdAt: DateTime(2026, 5, 11),
          updatedAt: DateTime(2026, 5, 11),
        ),
      ],
    );

    await pumpApp(
      tester,
      viewSize: const Size(1440, 900),
      deliveryChallanRepository: challanRepository,
    );
    await openChallansScreen(tester);

    expect(find.text('DC-00001'), findsOneWidget);
    expect(find.text('RC-00001'), findsNothing);

    await tester.tap(find.text('Reception').first);
    await tester.pumpAndSettle();
    expect(find.text('RC-00001'), findsOneWidget);
    expect(find.text('DC-00001'), findsNothing);

    await tester.tap(find.text('Delivery').first);
    await tester.pumpAndSettle();
    expect(find.text('DC-00001'), findsOneWidget);
    expect(find.text('RC-00001'), findsNothing);
  });

  testWidgets('challan report switches between auditor client and misc rows', (
    tester,
  ) async {
    final challanRepository = FakeDeliveryChallanRepository(
      reconciliationReport: ReconciliationReportSnapshot(
        generatedAt: DateTime(2026, 5, 12),
        internalAuditor: <InternalAuditorRow>[
          InternalAuditorRow(
            challanId: 11,
            challanItemId: 7001,
            orderId: 501,
            clientId: 41,
            itemId: 91,
            variationLeafNodeId: 0,
            dcNumber: 'DC-101',
            challanDate: DateTime(2026, 5, 12),
            clientName: 'Alpha Industries',
            itemName: 'Kraft Sheet',
            hsnCode: '4805',
            totalDispatchedWeightKg: 22.8,
            convertedUnits: 60,
            invoicedQuantity: 20,
            invoiceableQuantity: 40,
            unitPrice: 18.5,
            financialExposure: 740,
            gstin: '27AAAAA0000A1Z5',
            cgst: 90,
            sgst: 90,
            cgstRate: 9,
            sgstRate: 9,
            wastePercentage: 8,
            conversionRatio: 2.63,
            toUnitLabel: 'sheets',
            variancePercent: 66.67,
            status: 'Attention Required',
            isAttentionRequired: true,
            isDirectPrint: false,
            isUnbilled: true,
          ),
          InternalAuditorRow(
            challanId: 12,
            challanItemId: 7002,
            dcNumber: 'DC-TYPE',
            clientName: 'Walk-in Customer',
            itemName: 'Typed custom tray',
            hsnCode: '',
            totalDispatchedWeightKg: 12,
            convertedUnits: 12,
            invoicedQuantity: 0,
            gstin: '',
            cgst: 0,
            sgst: 0,
            wastePercentage: 0,
            status: 'Unlinked / Direct Print',
            isAttentionRequired: false,
            isDirectPrint: true,
            isUnbilled: true,
          ),
        ],
        clientStatement: const <ClientStatementRow>[
          ClientStatementRow(
            clientName: 'Alpha Industries',
            itemName: 'Kraft Sheet',
            materialReceivedInputKg: 100,
            totalFinishedUnitsDelivered: 60,
            netBalanceMaterialRemainingKg: 77.2,
            status: 'Material Remaining',
          ),
        ],
        misc: <WasteAuditRow>[
          WasteAuditRow(
            auditTime: DateTime(2026, 5, 12),
            clientName: 'Alpha Industries',
            itemName: 'Kraft Sheet',
            challanNo: 'DC-101',
            inputWeightKg: 100,
            shippedWeightKg: 22.8,
            wasteWeightKg: 77.2,
            wastePercentage: 77.2,
            source: 'report_snapshot',
          ),
        ],
      ),
    );

    await pumpApp(
      tester,
      viewSize: const Size(1440, 900),
      deliveryChallanRepository: challanRepository,
    );
    await openChallansScreen(tester);

    await tester.tap(find.text('Report').first);
    await tester.pumpAndSettle();

    expect(find.text('Report'), findsWidgets);
    expect(find.text('Internal Auditor'), findsWidgets);
    expect(find.text('Dispatched Weight'), findsWidgets);
    expect(find.text('Attention Required'), findsWidgets);
    expect(find.text('DC-101'), findsOneWidget);
    expect(find.text('Alpha Industries'), findsWidgets);
    expect(find.text('Direct Print / Unlinked'), findsOneWidget);
    expect(find.text('Open Draft Invoice'), findsWidgets);

    tester
        .widget<TextButton>(
          find.widgetWithText(TextButton, 'Open Draft Invoice').first,
        )
        .onPressed
        ?.call();
    await tester.pumpAndSettle();

    expect(find.text('Draft Invoice'), findsOneWidget);
    expect(find.text('Create Draft Invoice'), findsOneWidget);
    expect(find.text('DC-101'), findsWidgets);
    expect(find.text('Kraft Sheet'), findsWidgets);

    await tester.tap(find.text('Create Draft Invoice'));
    await tester.pumpAndSettle();
    expect(challanRepository.createInvoiceCalls, 1);
    expect(challanRepository.createdInvoices.single.lines.single.quantity, 40);
    expect(
      challanRepository.createdInvoices.single.lines.single.unitPrice,
      18.5,
    );
    expect(challanRepository.createdInvoices.single.lines.single.cgstRate, 9);
    expect(
      find.textContaining('Draft invoice INV-00001 created.'),
      findsOneWidget,
    );

    tester
        .widget<TextButton>(
          find.widgetWithText(TextButton, 'Edit Conversion').first,
        )
        .onPressed
        ?.call();
    await tester.pumpAndSettle();
    expect(find.text('Edit Conversion'), findsWidgets);
    await tester.enterText(find.byType(TextField).last, 'sheets');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(challanRepository.saveConversionOverrideCalls, 1);
    expect(
      challanRepository.savedConversionOverrides.single.conversionRatio,
      2.63,
    );

    await tester.enterText(find.byType(TextField).first, 'Alpha');
    await tester.pump();
    await tester.tap(find.text('Client Statement'));
    await tester.pumpAndSettle();
    expect(find.text('Material Received (Input)'), findsOneWidget);
    expect(find.text('Material Remaining'), findsWidgets);

    await tester.tap(find.text('Misc'));
    await tester.pumpAndSettle();
    expect(find.text('Waste Audit Rows'), findsWidgets);
    expect(find.text('report_snapshot'), findsOneWidget);
  });

  testWidgets(
    'client report dialog separates selection from preview and exports selected challans',
    (tester) async {
      final challanRepository = FakeDeliveryChallanRepository(
        seedChallans: <DeliveryChallan>[
          DeliveryChallan(
            id: 81,
            type: ChallanType.delivery,
            orderId: 501,
            orderIds: const <int>[501],
            clientId: 41,
            orderNo: 'ORD-501',
            orderNos: const <String>['ORD-501'],
            challanNo: 'DC-CLIENT-1',
            date: DateTime(2026, 5, 18),
            location: 'Dispatch Bay',
            customerName: 'Alpha Industries',
            customerGstin: '27AAAAA0000A1Z5',
            vendorId: null,
            vendorName: '',
            vendorGstin: '',
            sourceReference: '',
            companyProfileSnapshot: null,
            notes: '',
            maintainStocks: true,
            status: DeliveryChallanStatus.issued,
            items: const <DeliveryChallanItem>[
              DeliveryChallanItem(
                id: 9101,
                orderItemId: 501,
                productionRunId: null,
                itemId: 91,
                variationLeafNodeId: 0,
                lineNo: 1,
                particulars: 'Kraft Sheet',
                hsnCode: '4805',
                variationPathLabel: 'Base item',
                note: 'Client-facing note',
                quantityPcs: '42',
                weight: '15.5',
              ),
            ],
            itemsCount: 1,
            createdAt: DateTime(2026, 5, 18),
            updatedAt: DateTime(2026, 5, 18),
          ),
          DeliveryChallan(
            id: 82,
            type: ChallanType.delivery,
            orderId: 502,
            orderIds: const <int>[502],
            clientId: 42,
            orderNo: 'ORD-502',
            orderNos: const <String>['ORD-502'],
            challanNo: 'DC-CLIENT-2',
            date: DateTime(2026, 5, 18),
            location: 'Dispatch Bay',
            customerName: 'Beta Industries',
            customerGstin: '27BBBBB0000B1Z5',
            vendorId: null,
            vendorName: '',
            vendorGstin: '',
            sourceReference: '',
            companyProfileSnapshot: null,
            notes: '',
            maintainStocks: true,
            status: DeliveryChallanStatus.issued,
            items: const <DeliveryChallanItem>[],
            itemsCount: 0,
            createdAt: DateTime(2026, 5, 18),
            updatedAt: DateTime(2026, 5, 18),
          ),
        ],
      );

      await pumpApp(
        tester,
        viewSize: const Size(1440, 900),
        deliveryChallanRepository: challanRepository,
      );
      await openChallansScreen(tester);

      await tester.tap(find.text('Report').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Client Report'));
      await tester.pumpAndSettle();

      expect(find.text('Client Report'), findsWidgets);
      expect(find.text('DC-CLIENT-1'), findsWidgets);
      expect(find.text('Client-facing note'), findsNothing);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('Client-facing note'), findsNothing);

      await tester.tap(find.text('DC-CLIENT-1').last);
      await tester.pumpAndSettle();
      expect(find.text('1 Challans Selected'), findsOneWidget);
      expect(find.text('Client-facing note'), findsOneWidget);
      expect(find.text('Qty 42\nWt 15.5'), findsOneWidget);

      final exportButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Export XLSX').last,
      );
      expect(exportButton.onPressed, isNotNull);
    },
  );

  testWidgets(
    'challan templates use fixed layout blocks and a single items area block',
    (tester) async {
      final challanRepository = FakeDeliveryChallanRepository(
        seedTemplates: <ChallanTemplate>[
          ChallanTemplate(
            id: 1,
            name: 'Client Template',
            partyType: ChallanTemplatePartyType.generic,
            partyId: 0,
            challanType: ChallanType.delivery,
            backgroundObjectKey: 'templates/client.png',
            backgroundImageUrl: '',
            canvasWidth: 1240,
            canvasHeight: 1754,
            rotationDegrees: 0,
            globalOffsetXmm: 0,
            globalOffsetYmm: 0,
            stockSize: 'A4',
            paperSize: 'A4',
            nUpLayout: 1,
            isActive: true,
            mappings: const <ChallanTemplateMapping>[
              ChallanTemplateMapping(
                id: 1,
                templateId: 1,
                fieldType: 'TABLE',
                fieldKey: 'item_particulars',
                fieldValue:
                    '{"columns":[{"fieldKey":"item_particulars","xMm":0},{"fieldKey":"hsn","xMm":72},{"fieldKey":"qty_pcs","xMm":102},{"fieldKey":"weight","xMm":124}]}',
                assetObjectKey: '',
                assetImageUrl: null,
                assetWidthPx: 0,
                assetHeightPx: 0,
                widthMm: 150,
                heightMm: 70,
                imageWidthMm: 35,
                imageHeightMm: 20,
                lockAspectRatio: true,
                xMm: 16.8,
                yMm: 106.92,
                xPercent: 0.08,
                yPercent: 0.36,
                fontSize: 10,
                fontWeight: 'normal',
                alignment: 'left',
                textColor: 'black',
                letterSpacing: 0,
                maxChars: 0,
                maxWidthMm: 37.5,
                minFontSize: 6,
                minRows: 0,
                maxRows: 11,
                tableHeightMm: 70,
                rowHeightMm: 6,
              ),
            ],
          ),
        ],
      );
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ClientsProvider>(
              create: (_) =>
                  ClientsProvider(repository: FakeClientRepository()),
            ),
            ChangeNotifierProvider<VendorsProvider>(
              create: (_) =>
                  VendorsProvider(repository: FakeVendorRepository()),
            ),
            ChangeNotifierProvider<DeliveryChallanProvider>(
              create: (_) =>
                  DeliveryChallanProvider(repository: challanRepository),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: TemplateMappingScreen(onBack: _noop)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Challan Templates'), findsOneWidget);
      expect(find.text('Layout Blocks'), findsOneWidget);
      expect(find.text('Field'), findsOneWidget);
      expect(find.text('Delete Block'), findsOneWidget);
      expect(find.text('Placed'), findsOneWidget);
      expect(find.text('Advanced Freedom'), findsOneWidget);
      expect(find.text('Table Block'), findsWidgets);

      await tester.tap(find.text('Field'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Table Block').last);
      await tester.pumpAndSettle();

      expect(find.text('Column Controls'), findsOneWidget);
      expect(find.text('HSN X'), findsOneWidget);
      expect(find.text('Qty X'), findsOneWidget);
      expect(find.text('Weight X'), findsOneWidget);

      final hsnNudgeLeft = find.byKey(
        const ValueKey<String>('table-column-hsn-nudge-left'),
      );
      await tester.ensureVisible(hsnNudgeLeft);
      await tester.pumpAndSettle();
      await tester.tap(hsnNudgeLeft);
      await tester.pumpAndSettle();

      expect(find.text('71'), findsOneWidget);
      final hsnOrderRight = find.byKey(
        const ValueKey<String>('table-column-hsn-order-right'),
      );
      await tester.ensureVisible(hsnOrderRight);
      await tester.pumpAndSettle();
      await tester.tap(hsnOrderRight);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reception challan item selection uses variation path popup', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(1440, 900));
    await openChallansScreen(tester);

    await tester.tap(find.text('Reception').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Reception').first);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('challan-reception-item-0')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('challan-reception-item-0')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch Action Dolly - 1').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('challan-reception-variation-0')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('challan-reception-variation-0')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('Select Variation Path'), findsOneWidget);
    expect(find.text('Action Dolly Amp'), findsWidgets);
  });

  testWidgets('delivery challan variation opens same popup in read only mode', (
    tester,
  ) async {
    final seededOrder = OrderEntry(
      id: 101,
      orderNo: 'ORD-101',
      clientId: 1,
      clientName: 'Acme Packaging Pvt. Ltd.',
      poNumber: 'PO-101',
      clientCode: 'Client Patti',
      itemId: 1,
      itemName: 'Switch Action Dolly - 1',
      variationLeafNodeId: 17,
      variationPathLabel:
          '5 Amp / 11+1 / Brass / 1 Way / Dolly / Without Plating',
      variationPathNodeIds: const <int>[2, 4, 11, 13, 15, 17],
      quantity: 25,
      status: OrderStatus.draft,
      createdAt: DateTime(2026, 5, 12),
      startDate: DateTime(2026, 5, 12),
      endDate: DateTime(2026, 5, 15),
    );
    await pumpApp(
      tester,
      viewSize: const Size(1440, 900),
      orderRepository: FakeOrderRepository(
        seedOrders: <OrderEntry>[seededOrder],
      ),
    );
    await openChallansScreen(tester);

    await tester.tap(find.text('Create Delivery').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('fetch order ↗︎'));
    await tester.pumpAndSettle();
    expect(find.text('Select Order Line'), findsOneWidget);
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fetch Selected Items ↗'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('challan-delivery-variation-0')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('challan-delivery-variation-0')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('Select Variation Path'), findsOneWidget);
    expect(find.text('Apply Path'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });

  test(
    'navigation provider maps the primary tabs to the requested indices',
    () {
      final navigation = NavigationProvider(initialKey: 'configurator_units');
      addTearDown(navigation.dispose);

      expect(navigation.currentTabIndex, 6);

      navigation.select('inventory_scan');
      expect(navigation.currentTabIndex, 3);

      navigation.select('challan_invoice_report');
      expect(navigation.currentTabIndex, 2);

      navigation.setTab(2);
      expect(navigation.selectedKey, 'delivery_challans');
      expect(navigation.currentTabIndex, 2);
    },
  );

  testWidgets('ctrl digits and home switch the primary shell tabs', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(1440, 900));
    final context = tester.element(find.byType(Scaffold).first);
    final navigation = context.read<NavigationProvider>();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(navigation.selectedKey, 'orders');
    expect(navigation.currentTabIndex, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(navigation.selectedKey, 'delivery_challans');
    expect(navigation.currentTabIndex, 2);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(navigation.selectedKey, 'inventory');
    expect(navigation.currentTabIndex, 3);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(navigation.selectedKey, 'production_pipelines');
    expect(navigation.currentTabIndex, 4);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(navigation.selectedKey, 'dashboard');
    expect(navigation.currentTabIndex, 0);
  });

  testWidgets('ctrl n opens the order editor only on the orders tab', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(1440, 900));

    await openOrdersScreen(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('Create New Order'), findsOneWidget);

    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    context.read<NavigationProvider>().select(
      'inventory',
      skipTransition: true,
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('Create New Order'), findsNothing);
  });

  testWidgets('challans shortcuts open delivery and reception editors', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(1440, 900));
    await openChallansScreen(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Create Delivery Challan'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await tester.pumpAndSettle();
    expect(find.text('Create Delivery Challan'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Create Reception Challan'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();
    expect(find.text('Create Reception Challan'), findsOneWidget);
  });

  testWidgets('held ctrl n does not spawn duplicate order dialogs', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(1440, 900));
    await openOrdersScreen(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('Create New Order'), findsOneWidget);
  });

  testWidgets('ctrl f focuses the shared title bar search', (tester) async {
    await pumpApp(tester, viewSize: const Size(1440, 900));

    await openOrdersScreen(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    final searchField = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('shell_top_strip_search_field')),
    );
    expect(searchField.focusNode?.hasFocus, isTrue);
  });

  testWidgets(
    'home stays within editable text instead of jumping to dashboard',
    (tester) async {
      await pumpApp(tester, viewSize: const Size(1440, 900));
      await openOrdersScreen(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey<String>('shell_top_strip_search_field')),
        'ord',
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(Scaffold).first);
      final searchField = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('shell_top_strip_search_field')),
      );
      expect(context.read<NavigationProvider>().selectedKey, 'orders');
      expect(searchField.focusNode?.hasFocus, isTrue);
    },
  );

  testWidgets('tab reaches order dropdowns and dropdown options', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(1440, 900));
    await openOrdersScreen(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-order-no-field')),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('orders-editor-order-no-field')),
      'TAB-ORDER-01',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.enterText(
      find.byKey(const ValueKey<String>('orders-editor-po-number-field')),
      'TAB-PO-01',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-client-field')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Search client'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search client'),
      'acme',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Acme Packaging Pvt. Ltd. / Acme').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Acme Packaging Pvt. Ltd.'), findsOneWidget);
  });

  testWidgets('tab focus stays looped inside sidebar items', (tester) async {
    await pumpApp(tester, viewSize: const Size(1440, 900));
    await openUnitsScreen(tester);
    final context = tester.element(find.byType(Scaffold).first);
    final navigation = context.read<NavigationProvider>();
    expect(navigation.selectedKey, 'configurator_units');
    final previousKey = navigation.selectedKey;

    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar_tile_configurator_units')),
      warnIfMissed: false,
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(navigation.selectedKey, previousKey);
  });

  testWidgets('inventory top strip actions invoke navigation callbacks', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Open Scan'));
    await tester.pumpAndSettle();

    expect(find.text('Material Scan'), findsWidgets);
  });

  testWidgets('inventory stock actions open reception challan editor', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(1440, 900));

    await tester.tap(find.text('Stock Actions ▾'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Reception Challan'));
    await tester.pumpAndSettle();

    expect(find.text('Create Reception Challan'), findsOneWidget);
    expect(find.text('Vendor'), findsOneWidget);
    expect(find.text('Select order'), findsNothing);
  });

  testWidgets(
    'shared shell strip updates provider-backed search for configurator screens',
    (tester) async {
      await pumpApp(tester);

      Future<void> expectSharedSearch({
        required String navLabel,
        required String query,
        required String visibleText,
        required String hiddenText,
      }) async {
        if (navLabel == 'Clients') {
          await openClientsScreen(tester);
        } else if (navLabel == 'Items') {
          await openItemsScreen(tester);
        } else if (navLabel == 'Groups') {
          await openGroupsScreen(tester);
        } else if (navLabel == 'Units') {
          await openUnitsScreen(tester);
        }

        await tester.enterText(
          find.byKey(const ValueKey<String>('shell_top_strip_search_field')),
          query,
        );
        await tester.pumpAndSettle();

        expect(find.text(visibleText), findsWidgets);
        expect(find.text(hiddenText), findsNothing);
        expect(find.byType(TextField), findsWidgets);
      }

      await expectSharedSearch(
        navLabel: 'Clients',
        query: 'sunrise',
        visibleText: 'Sunrise Retail LLP',
        hiddenText: 'Acme Packaging Pvt. Ltd.',
      );
      await expectSharedSearch(
        navLabel: 'Items',
        query: 'glue',
        visibleText: 'Glue Compound - 1',
        hiddenText: 'Switch Action Dolly - 1',
      );
      await expectSharedSearch(
        navLabel: 'Groups',
        query: 'kraft',
        visibleText: 'Kraft',
        hiddenText: 'Chemical',
      );
      await expectSharedSearch(
        navLabel: 'Units',
        query: 'sheet',
        visibleText: 'Sheet',
        hiddenText: 'Kilogram',
      );
    },
  );

  testWidgets('orders keep client code as a manual item text field', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(1440, 900));

    await openOrdersScreen(tester);

    expect(find.text('No orders found'), findsOneWidget);
    expect(find.byKey(const Key('orders-new-order-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('orders-new-order-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('orders-editor-order-no-field')),
      'ORD-001',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-client-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme Packaging Pvt. Ltd. / Acme').last);
    await tester.pumpAndSettle();

    final clientCodeField = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('orders-editor-client-code-field')),
    );
    expect(clientCodeField.controller?.text, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey<String>('orders-editor-client-code-field')),
      'Customer Patti Name',
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('orders-editor-po-number-field')),
      'PO-42',
    );

    await selectPrimaryVariationPath(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('ORD-001'), findsOneWidget);
    expect(find.text('Acme Packaging Pvt. Ltd.'), findsOneWidget);
    expect(find.text('PO-42'), findsOneWidget);
    expect(find.textContaining('Without Plating'), findsOneWidget);
    expect(find.text('1 Pieces'), findsOneWidget);
  });

  testWidgets('orders keep selected variation path visible after add more', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(1440, 900));

    await openOrdersScreen(tester);
    await tester.tap(find.byKey(const Key('orders-new-order-button')));
    await tester.pumpAndSettle();

    await selectPrimaryVariationPath(tester);

    await tester.ensureVisible(find.text('Add More Items'));
    await tester.tap(find.text('Add More Items'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('orders-editor-variation-path-field')),
      findsOneWidget,
    );
    expect(find.textContaining('Without Plating'), findsWidgets);
    expect(find.textContaining('Action Dolly Plating:'), findsNothing);
  });

  testWidgets('orders hide variation path until a variant item is selected', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(1440, 900));

    await openOrdersScreen(tester);
    await tester.tap(find.byKey(const Key('orders-new-order-button')));
    await tester.pumpAndSettle();

    expect(find.text('Variation Path'), findsNothing);
    expect(find.text('Select an item first'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-item-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch Action Dolly - 1').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('orders-editor-variation-path-field')),
      findsOneWidget,
    );
  });

  testWidgets(
    'orders hide item completion date column when item wise toggle is off',
    (tester) async {
      await pumpApp(tester, viewSize: const Size(1440, 900));

      await openOrdersScreen(tester);
      await tester.tap(find.byKey(const Key('orders-new-order-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey<String>('orders-editor-completion-date-field'),
        ),
        findsOneWidget,
      );
      expect(find.text('Completion Date'), findsOneWidget);

      await tester.tap(find.text('Enable Item Wise Completion Date'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey<String>('orders-editor-completion-date-field'),
        ),
        findsNothing,
      );
      expect(find.text('Completion Date'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('orders-editor-end-date-field')),
        findsOneWidget,
      );
    },
  );

  testWidgets('orders can select a leaf variation value and save draft', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(1600, 1000));

    await openOrdersScreen(tester);
    await tester.tap(find.byKey(const Key('orders-new-order-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('orders-editor-order-no-field')),
      'ORD-QUICK-LEAF',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-client-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme Packaging Pvt. Ltd. / Acme').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('orders-editor-po-number-field')),
      'PO-QUICK-LEAF',
    );

    await selectPrimaryVariationPath(
      tester,
      itemLabel: 'Glue Compound - 1',
      variationPathText: 'Fast Cure',
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('orders-editor-save-draft')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-save-draft')),
    );
    await tester.pumpAndSettle();

    expect(find.text('ORD-QUICK-LEAF'), findsOneWidget);
    expect(find.textContaining('Fast Cure'), findsWidgets);
  });

  testWidgets('orders variation path selector exposes bottle path values', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(1600, 1000));

    await openOrdersScreen(tester);
    await tester.tap(find.byKey(const Key('orders-new-order-button')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-item-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Luxury Pump Bottle - 100').last);
    await tester.pumpAndSettle();

    await openVariationPathSelector(tester);
    expect(find.text('Bottle Material'), findsWidgets);
    await tester.tap(
      find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'orders-variation-step-',
                ),
          )
          .last,
    );
    await tester.pumpAndSettle();
    expect(find.text('PET'), findsWidgets);
    expect(find.text('Glass'), findsWidgets);

    await tester.tap(find.text('PET').last);
    await tester.pumpAndSettle();

    expect(find.text('Bottle Color'), findsWidgets);
    await tester.tap(
      find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'orders-variation-step-',
                ),
          )
          .last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Amber'), findsWidgets);
  });

  testWidgets('orders variation path selector offers inline create actions', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(1600, 1000));

    await openOrdersScreen(tester);
    await tester.tap(find.byKey(const Key('orders-new-order-button')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-item-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Glue Compound - 1').last);
    await tester.pumpAndSettle();

    await openVariationPathSelector(tester);
    await tester.tap(
      find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'orders-variation-step-',
                ),
          )
          .last,
    );
    await tester.pumpAndSettle();
    await tester.enterText(searchFieldWithHint('Search value'), 'Ultra Cure');
    await tester.pumpAndSettle();

    expect(find.text('Create value "Ultra Cure"'), findsWidgets);
  });

  testWidgets('orders can change selected variation path from dropdown', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(1440, 900));

    await openOrdersScreen(tester);
    await tester.tap(find.byKey(const Key('orders-new-order-button')));
    await tester.pumpAndSettle();

    await selectPrimaryVariationPath(tester);

    expect(
      find.byKey(const ValueKey<String>('orders-editor-variation-path-field')),
      findsOneWidget,
    );
    expect(find.textContaining('Without Plating'), findsWidgets);

    await changeOpenVariationValue(
      tester,
      itemLabel: 'Switch Action Dolly - 1',
      currentValue: 'Without Plating',
      newValue: 'With Plating',
    );
    expect(find.textContaining('With Plating'), findsWidgets);
    expect(find.textContaining('Action Dolly Plating:'), findsNothing);
  });

  testWidgets('orders search filters through the shared shell strip', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(1440, 900));

    await openOrdersScreen(tester);

    await tester.tap(find.byKey(const Key('orders-new-order-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('orders-editor-order-no-field')),
      'ORD-SHARED-01',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-client-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme Packaging Pvt. Ltd. / Acme').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('orders-editor-po-number-field')),
      'PO-SHARED',
    );
    await selectPrimaryVariationPath(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('orders-editor-create-order')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-create-order')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('shell_top_strip_search_field')),
      'shared',
    );
    await tester.pumpAndSettle();

    expect(find.text('ORD-SHARED-01'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('shell_top_strip_search_field')),
      'missing',
    );
    await tester.pumpAndSettle();

    expect(find.text('No orders in this state'), findsOneWidget);
  });

  testWidgets('orders filtered empty state shows create order action', (
    tester,
  ) async {
    final seededOrderRepo = FakeOrderRepository(
      seedOrders: <OrderEntry>[
        OrderEntry(
          id: 1,
          orderNo: 'ORD-SEEDED-01',
          clientId: 1,
          clientName: 'Acme Packaging Pvt. Ltd.',
          poNumber: 'PO-SEEDED-01',
          clientCode: 'Acme',
          itemId: 1,
          itemName: 'Switch Action Dolly - 1',
          variationLeafNodeId: 11,
          variationPathLabel: '5 Amp',
          variationPathNodeIds: const <int>[1, 11],
          quantity: 10,
          status: OrderStatus.inProgress,
          createdAt: DateTime(2026, 4, 20),
          startDate: DateTime(2026, 4, 21),
          endDate: DateTime(2026, 4, 26),
        ),
      ],
    );
    await pumpApp(
      tester,
      orderRepository: seededOrderRepo,
      viewSize: const Size(1600, 1000),
    );

    await openOrdersScreen(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('shell_top_strip_search_field')),
      'no-match-value',
    );
    await tester.pumpAndSettle();

    expect(find.text('No orders in this state'), findsOneWidget);
    expect(
      find.text('No matching orders for the current filters.'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('orders-empty-create-order')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Create New Order'), findsOneWidget);
  });

  testWidgets('orders rows show urgency cues for near due and overdue', (
    tester,
  ) async {
    final now = DateTime.now();
    final nearDue = DateTime(now.year, now.month, now.day + 2);
    final overdue = DateTime(now.year, now.month, now.day - 1);

    final seededOrderRepo = FakeOrderRepository(
      seedOrders: <OrderEntry>[
        OrderEntry(
          id: 41,
          orderNo: 'ORD-NEAR',
          clientId: 1,
          clientName: 'Acme Packaging Pvt. Ltd.',
          poNumber: 'PO-NEAR',
          clientCode: 'Acme',
          itemId: 1,
          itemName: 'Switch Action Dolly - 1',
          variationLeafNodeId: 11,
          variationPathLabel: '5 Amp',
          variationPathNodeIds: const <int>[1, 11],
          quantity: 6,
          status: OrderStatus.inProgress,
          createdAt: DateTime(2026, 4, 20),
          startDate: DateTime(2026, 4, 21),
          endDate: nearDue,
        ),
        OrderEntry(
          id: 42,
          orderNo: 'ORD-OVERDUE',
          clientId: 1,
          clientName: 'Acme Packaging Pvt. Ltd.',
          poNumber: 'PO-OVERDUE',
          clientCode: 'Acme',
          itemId: 1,
          itemName: 'Switch Action Dolly - 1',
          variationLeafNodeId: 11,
          variationPathLabel: '5 Amp',
          variationPathNodeIds: const <int>[1, 11],
          quantity: 6,
          status: OrderStatus.notStarted,
          createdAt: DateTime(2026, 4, 20),
          startDate: DateTime(2026, 4, 21),
          endDate: overdue,
        ),
      ],
    );
    await pumpApp(
      tester,
      orderRepository: seededOrderRepo,
      viewSize: const Size(1600, 1000),
    );

    await openOrdersScreen(tester);

    expect(
      find.byKey(const ValueKey<String>('orders-row-urgency-near-41')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('orders-row-urgency-overdue-42')),
      findsOneWidget,
    );
  });

  testWidgets('orders summary cards show contextual sublabels and filter', (
    tester,
  ) async {
    final seededOrderRepo = FakeOrderRepository(
      seedOrders: <OrderEntry>[
        OrderEntry(
          id: 61,
          orderNo: 'ORD-DRAFT-VIEW',
          clientId: 1,
          clientName: 'Acme Packaging Pvt. Ltd.',
          poNumber: 'PO-DRAFT-VIEW',
          clientCode: 'Acme',
          itemId: 1,
          itemName: 'Switch Action Dolly - 1',
          variationLeafNodeId: 11,
          variationPathLabel: '5 Amp',
          variationPathNodeIds: const <int>[1, 11],
          quantity: 4,
          status: OrderStatus.draft,
          createdAt: DateTime(2026, 4, 20),
          startDate: DateTime(2026, 4, 21),
          endDate: DateTime(2026, 4, 30),
        ),
        OrderEntry(
          id: 62,
          orderNo: 'ORD-COMPLETE-VIEW',
          clientId: 1,
          clientName: 'Acme Packaging Pvt. Ltd.',
          poNumber: 'PO-COMPLETE-VIEW',
          clientCode: 'Acme',
          itemId: 1,
          itemName: 'Switch Action Dolly - 1',
          variationLeafNodeId: 11,
          variationPathLabel: '5 Amp',
          variationPathNodeIds: const <int>[1, 11],
          quantity: 4,
          status: OrderStatus.completed,
          createdAt: DateTime(2026, 4, 20),
          startDate: DateTime(2026, 4, 21),
          endDate: DateTime(2026, 4, 30),
        ),
      ],
    );
    await pumpApp(
      tester,
      orderRepository: seededOrderRepo,
      viewSize: const Size(1600, 1000),
    );

    await openOrdersScreen(tester);

    expect(find.text('Not Started'), findsOneWidget);
    expect(find.text('Completed'), findsWidgets);

    final completedFilter = find.text('Completed').first;
    await tester.ensureVisible(completedFilter);
    await tester.tap(completedFilter, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('ORD-COMPLETE-VIEW'), findsOneWidget);
    expect(find.text('ORD-DRAFT-VIEW'), findsNothing);
  });

  testWidgets('orders merge duplicate lines by order client po and item', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(1600, 1000));
    await openOrdersScreen(tester);

    Future<void> addOrder() async {
      await tester.tap(find.byKey(const Key('orders-new-order-button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('orders-editor-order-no-field')),
        'ORD-002',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('orders-editor-client-field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Acme Packaging Pvt. Ltd. / Acme').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('orders-editor-po-number-field')),
        'PO-77',
      );
      await selectPrimaryVariationPath(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('orders-editor-create-order')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('orders-editor-create-order')),
      );
      await tester.pumpAndSettle();
    }

    await addOrder();
    await addOrder();

    expect(find.text('ORD-002'), findsOneWidget);
    expect(find.text('2 Pieces'), findsOneWidget);
  });

  testWidgets('orders lifecycle can be updated from table row', (tester) async {
    await pumpApp(tester, viewSize: const Size(1600, 1000));

    await openOrdersScreen(tester);

    await tester.tap(find.byKey(const Key('orders-new-order-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('orders-editor-order-no-field')),
      'ORD-004',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-client-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme Packaging Pvt. Ltd. / Acme').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('orders-editor-po-number-field')),
      'PO-88',
    );
    await selectPrimaryVariationPath(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('orders-editor-create-order')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-create-order')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Not Started'), findsWidgets);

    final orderRow = find.text('ORD-004').last;
    await tester.ensureVisible(orderRow);
    await tester.tap(orderRow, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Order Details'), findsOneWidget);
    expect(find.text('Purchase order no.'), findsOneWidget);
    expect(find.text('PO-88'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey<String>('orders-details-footer-edit')),
    );
    await tester.pumpAndSettle();

    final editStatusField = find.byKey(
      const ValueKey<String>('orders-lifecycle-status-field'),
    );
    await tester.ensureVisible(editStatusField);
    await tester.tap(editStatusField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Completed'), findsWidgets);
  });

  testWidgets('orders can be saved as draft from create dialog', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(1600, 1000));

    await openOrdersScreen(tester);

    await tester.tap(find.byKey(const Key('orders-new-order-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('orders-editor-order-no-field')),
      'ORD-DRAFT-001',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-client-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme Packaging Pvt. Ltd. / Acme').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('orders-editor-po-number-field')),
      'PO-DRAFT-001',
    );
    await selectPrimaryVariationPath(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('orders-editor-save-draft')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-save-draft')),
    );
    await tester.pumpAndSettle();

    expect(find.text('ORD-DRAFT-001'), findsOneWidget);
    expect(find.text('Draft'), findsWidgets);
  });

  testWidgets('orders allow creation when client master has no alias', (
    tester,
  ) async {
    final clientRepository = FakeClientRepository(
      seedClients: <ClientDefinition>[
        ClientDefinition(
          id: 1,
          name: 'No Code Client',
          alias: '',
          gstNumber: '',
          address: 'Pune',
          isArchived: false,
          usageCount: 0,
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
        ),
      ],
    );
    await pumpApp(
      tester,
      clientRepository: clientRepository,
      viewSize: const Size(1600, 1000),
    );

    await openOrdersScreen(tester);
    await tester.tap(find.byKey(const Key('orders-new-order-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('orders-editor-order-no-field')),
      'ORD-003',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-client-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('No Code Client').last);
    await tester.pumpAndSettle();

    await selectPrimaryVariationPath(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('orders-editor-create-order')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-create-order')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Selected client has no client code in master.'),
      findsNothing,
    );
    expect(find.text('ORD-003'), findsOneWidget);
    expect(find.text('No Code Client'), findsOneWidget);
  });

  testWidgets(
    'inventory add flow creates parent and four children with hierarchy',
    (tester) async {
      final repository = FakeInventoryRepository();
      await pumpApp(tester, repository: repository);

      await tester.tap(find.text('+ Add Stock'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'Dolly Sheet',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Type'),
        'Finish Goods',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Grade'), 'B1');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Thickness'),
        '1.8 mm',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Supplier'),
        'Metro Metals',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Cut into X children'),
        '4',
      );

      await tester.tap(find.text('Save Parent + Children'));
      await tester.pumpAndSettle();

      final materials = await repository.getAllMaterials();
      final createdParent = materials
          .where((item) => item.name == 'Dolly Sheet')
          .single;
      final createdChildren = materials
          .where((item) => item.parentBarcode == createdParent.barcode)
          .toList();

      expect(find.text('Dolly Sheet'), findsWidgets);
      expect(createdChildren, hasLength(4));
      expect(createdChildren.first.name, 'Dolly Sheet - Child 1');
      expect(createdChildren.last.name, 'Dolly Sheet - Child 4');
    },
  );

  testWidgets('units screen shows seeded and archived units', (tester) async {
    await pumpApp(tester);

    await openUnitsScreen(tester);

    expect(find.byType(TextField), findsWidgets);
    expect(find.textContaining('Kilogram'), findsWidgets);
    expect(find.text('Sheet'), findsWidgets);

    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();

    expect(find.text('Legacy'), findsOneWidget);
  });

  testWidgets('groups screen shows seeded and archived groups', (tester) async {
    await pumpApp(tester);

    await openGroupsScreen(tester);

    expect(find.byType(TextField), findsWidgets);
    expect(find.text('Paper'), findsWidgets);
    expect(find.text('Kraft'), findsOneWidget);

    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();

    expect(find.text('Legacy Group'), findsOneWidget);
  });

  testWidgets('groups add flow creates a child group', (tester) async {
    final groupRepository = FakeGroupRepository();
    await pumpApp(tester, groupRepository: groupRepository);

    await openGroupsScreen(tester);

    await tester.tap(find.text('Add Group'));
    await tester.pumpAndSettle();

    expect(find.text('Parent Group'), findsWidgets);
    expect(find.text('Group Unit'), findsWidgets);
    expect(find.text('Structure & Properties'), findsNothing);
    expect(find.text('Seed Items'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Enter group name'),
      'Brown',
    );

    final parentDropdown = find.byKey(
      const ValueKey<String>('groups-parent-field'),
    );
    final unitDropdown = find.byKey(
      const ValueKey<String>('groups-unit-field'),
    );

    await tester.tap(parentDropdown.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chemical').last);
    await tester.pumpAndSettle();

    await tester.tap(unitDropdown.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kilogram (Kg)').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final groups = await groupRepository.getGroups();
    final created = groups.where((group) => group.name == 'Brown').single;
    expect(created.parentGroupId, 3);
    expect(created.unitId, 1);
  });

  testWidgets('groups parent dropdown shows one primary group option', (
    tester,
  ) async {
    final groupRepository = FakeGroupRepository(
      seedGroups: <GroupDefinition>[
        GroupDefinition(
          id: 1,
          name: 'Primary Group',
          parentGroupId: null,
          unitId: 1,
          isArchived: false,
          usageCount: 1,
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
        ),
        GroupDefinition(
          id: 2,
          name: 'Paper',
          parentGroupId: 1,
          unitId: 2,
          isArchived: false,
          usageCount: 0,
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
        ),
      ],
    );
    await pumpApp(tester, groupRepository: groupRepository);

    await openGroupsScreen(tester);

    await tester.tap(find.text('Add Group'));
    await tester.pumpAndSettle();

    final beforeOpenCount = find.text('Primary Group').evaluate().length;

    await tester.tap(find.byKey(const ValueKey<String>('groups-parent-field')));
    await tester.pumpAndSettle();

    final afterOpenCount = find.text('Primary Group').evaluate().length;
    expect(afterOpenCount, beforeOpenCount + 1);
  });

  testWidgets('groups edit flow preloads parent and unit', (tester) async {
    await pumpApp(tester);

    await openGroupsScreen(tester);

    await tester.enterText(find.byType(TextField).first, 'Kraft');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit').first);
    await tester.pumpAndSettle();

    expect(find.text('Under: Paper'), findsOneWidget);
    expect(find.text('Unit: Sheet (Sheet)'), findsOneWidget);
  });

  testWidgets('groups screen shows empty state when no groups exist', (
    tester,
  ) async {
    await pumpApp(
      tester,
      groupRepository: FakeGroupRepository(seedGroups: <GroupDefinition>[]),
    );

    await openGroupsScreen(tester);

    expect(find.text('No groups found'), findsOneWidget);
  });

  testWidgets('clients screen shows seeded and archived clients', (
    tester,
  ) async {
    await pumpApp(tester);

    await openClientsScreen(tester);

    expect(find.byType(TextField), findsWidgets);
    expect(find.text('Acme Packaging Pvt. Ltd.'), findsOneWidget);
    expect(find.text('Sunrise Retail LLP'), findsOneWidget);

    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();

    expect(find.text('Legacy Trading Co.'), findsOneWidget);
  });

  testWidgets('clients add flow creates a client record', (tester) async {
    final clientRepository = FakeClientRepository();
    await pumpApp(tester, clientRepository: clientRepository);

    await openClientsScreen(tester);

    await tester.tap(find.text('Add Client'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Northwind Papers',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Alias'),
      'Northwind',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'GST No.'),
      '29ABCDE1234F1Z5',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Address'),
      'Peenya Industrial Area, Bengaluru, Karnataka 560058',
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Client'));
    await tester.pumpAndSettle();

    expect(find.text('Northwind Papers'), findsWidgets);

    final clients = await clientRepository.getClients();
    final created = clients
        .where((client) => client.name == 'Northwind Papers')
        .single;
    expect(created.alias, 'Northwind');
    expect(created.gstNumber, '29ABCDE1234F1Z5');
  });

  testWidgets('clients editor uses normalized popup shell on narrow screens', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(430, 900));

    await openClientsScreen(tester);
    final context = tester.element(find.byType(Scaffold).first);
    ClientsScreen.openEditor(context);
    await tester.pumpAndSettle();

    expect(find.text('Identity'), findsOneWidget);
    expect(find.text('Address & Preview'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(
      find.textContaining('billing identity your team will reuse'),
      findsOneWidget,
    );
  });

  testWidgets('vendors editor uses normalized popup shell', (tester) async {
    await pumpApp(tester, vendorRepository: FakeVendorRepository());

    await openVendorsScreen(tester);
    final context = tester.element(find.byType(Scaffold).first);
    VendorsScreen.openEditor(context);
    await tester.pumpAndSettle();

    expect(find.text('Vendor Identity'), findsOneWidget);
    expect(find.text('Contacts & Address'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  testWidgets('items screen shows seeded and archived items', (tester) async {
    await pumpApp(tester);

    await openItemsScreen(tester);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Switch Action Dolly - 1'), findsOneWidget);
    expect(find.text('Glue Compound - 1'), findsOneWidget);
    expect(find.text('Luxury Pump Bottle - 100'), findsOneWidget);
    expect(find.text('Premium Mono Carton - 500'), findsOneWidget);

    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();

    expect(find.text('Legacy Stock - 5'), findsWidgets);
  });

  testWidgets('items screen toggles between table and card grid views', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(1440, 900));

    await openItemsScreen(tester);

    expect(find.text('Tree Summary'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('items-grid-view')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('items-grid-size-controls')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('items-view-toggle-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('items-grid-view')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('item-card-1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('items-grid-size-controls')),
      findsOneWidget,
    );
    expect(find.text('Tree Summary'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('items-view-toggle-button')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('items-grid-view')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('items-grid-size-controls')),
      findsNothing,
    );
    expect(find.text('Tree Summary'), findsOneWidget);
  });

  testWidgets(
    'item card grid uses sand banner neutral footer and opens detail',
    (tester) async {
      await pumpApp(tester, viewSize: const Size(1440, 900));

      await openItemsScreen(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('items-view-toggle-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Switch Action Dolly - 1'), findsOneWidget);

      final banner = tester.widget<Container>(
        find.byKey(const ValueKey<String>('item-card-banner-1')),
      );
      expect(banner.color, const Color(0xFFE4C17C));

      final footer = tester.widget<Container>(
        find.byKey(const ValueKey<String>('item-card-footer-1')),
      );
      final footerDecoration = footer.decoration! as BoxDecoration;
      expect(footerDecoration.color, const Color(0xFFF8F8FC));
      expect(footerDecoration.color, isNot(const Color(0xFF7B1FA2)));

      await tester.tap(find.byKey(const ValueKey<String>('item-card-1')));
      await tester.pumpAndSettle();

      expect(find.text('Display name'), findsOneWidget);
      expect(find.text('Switch Action Dolly - 1'), findsWidgets);
    },
  );

  testWidgets('item grid sliders update delegate width and height', (
    tester,
  ) async {
    await pumpApp(tester, viewSize: const Size(1440, 900));

    await openItemsScreen(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('items-view-toggle-button')),
    );
    await tester.pumpAndSettle();

    SliverGridDelegateWithMaxCrossAxisExtent delegate() =>
        tester
                .widget<GridView>(
                  find.byKey(const ValueKey<String>('items-grid-view')),
                )
                .gridDelegate
            as SliverGridDelegateWithMaxCrossAxisExtent;

    expect(delegate().maxCrossAxisExtent, 200);
    expect(delegate().childAspectRatio, closeTo(200 / 250, 0.001));

    await tester.drag(
      find.byKey(const ValueKey<String>('items-card-width-slider')),
      const Offset(160, 0),
    );
    await tester.pumpAndSettle();

    expect(delegate().maxCrossAxisExtent, greaterThan(200));

    final widthAfter = delegate().maxCrossAxisExtent;

    await tester.drag(
      find.byKey(const ValueKey<String>('items-card-height-slider')),
      const Offset(140, 0),
    );
    await tester.pumpAndSettle();

    expect(delegate().childAspectRatio, lessThan(widthAfter / 250));
  });

  testWidgets('items add flow creates recursive variation tree', (
    tester,
  ) async {
    final itemRepository = FakeItemRepository();
    await pumpApp(tester, itemRepository: itemRepository);

    await openItemsScreen(tester);

    await tester.tap(find.text('Add Item'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Bottle',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Alias'),
      'Travel Bottle',
    );

    await tester.tap(find.byKey(const ValueKey<String>('items-group-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paper').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('items-unit-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sheet (Sheet)').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Add Top-Level Property'),
    );
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Add Top-Level Property'),
    );
    await tester.pumpAndSettle();
    await startEditingLatestTreeNode(tester);
    await tester.enterText(treeNameEditor('Property name').last, 'Color');

    await tester.ensureVisible(find.byTooltip('Add value').first);
    await tester.tap(find.byTooltip('Add value').first);
    await tester.pumpAndSettle();
    await startEditingLatestTreeNode(tester);
    await tester.enterText(treeNameEditor('Value name').last, 'Black');

    await tester.ensureVisible(find.byTooltip('Add property').last);
    await tester.tap(find.byTooltip('Add property').last);
    await tester.pumpAndSettle();
    await startEditingLatestTreeNode(tester);
    await tester.enterText(treeNameEditor('Property name').last, 'Finish');

    await tester.ensureVisible(find.byTooltip('Add value').last);
    await tester.tap(find.byTooltip('Add value').last);
    await tester.pumpAndSettle();
    await startEditingLatestTreeNode(tester);

    await tester.enterText(treeNameEditor('Value name').last, 'Glossy');

    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Create Item'),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Item'));
    await tester.pumpAndSettle();

    expect(find.text('Bottle / Travel Bottle'), findsWidgets);
    final items = await itemRepository.getItems();
    final created = items.where((item) => item.name == 'Bottle').single;
    expect(created.displayName, 'Bottle / Travel Bottle');
    expect(created.topLevelProperties.single.name, 'Color');
    expect(created.leafVariationNodes.single.displayName, 'Black Glossy');
  });

  testWidgets('items duplicate sibling names are blocked', (tester) async {
    await pumpApp(tester, itemRepository: FakeItemRepository());

    await openItemsScreen(tester);

    await tester.tap(find.text('Add Item'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Test Item',
    );

    await tester.tap(find.byKey(const ValueKey<String>('items-group-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paper').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('items-unit-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sheet (Sheet)').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Add Top-Level Property'),
    );
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Add Top-Level Property'),
    );
    await tester.pumpAndSettle();
    await startEditingLatestTreeNode(tester);
    await tester.enterText(treeNameEditor('Property name').last, 'Color');

    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Add Top-Level Property'),
    );
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Add Top-Level Property'),
    );
    await tester.pumpAndSettle();
    await startEditingLatestTreeNode(tester);
    await tester.enterText(treeNameEditor('Property name').last, 'Color');

    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Create Item'),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Item'));
    await tester.pumpAndSettle();

    expect(
      find.text('Sibling names under the same parent must be unique.'),
      findsWidgets,
    );
  });

  testWidgets('groups archive banner appears for parent groups with children', (
    tester,
  ) async {
    await pumpApp(tester);

    await openGroupsScreen(tester);

    await tester.enterText(find.byType(TextField).first, 'Paper');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Archive').first);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('This group has active child groups'),
      findsOneWidget,
    );
  });

  testWidgets('inventory can quick-create a unit and save it', (tester) async {
    final repository = FakeInventoryRepository();
    final unitRepository = FakeUnitRepository();
    await pumpApp(
      tester,
      repository: repository,
      unitRepository: unitRepository,
    );

    await tester.tap(find.text('+ Add Stock'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Bundle Stock',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Type'),
      'Raw Material',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Grade'), 'A1');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Thickness'),
      '2.2 mm',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Supplier'),
      'Metro Metals',
    );

    await tester.tap(find.text('Select a unit'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Search unit name or symbol'),
      'Bundle',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create "Bundle"'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Symbol'), 'bdl');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Unit'));
    await tester.pumpAndSettle();

    expect(find.text('Bundle (bdl)'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Cut into X children'),
      '2',
    );
    await tester.tap(find.text('Save Parent + Children'));
    await tester.pumpAndSettle();

    final materials = await repository.getAllMaterials();
    final created = materials
        .where((item) => item.name == 'Bundle Stock')
        .single;
    expect(created.unit, 'bdl');
    expect(created.unitId, isNotNull);
  });

  testWidgets(
    'inventory create-group modal loads inherited properties from selected parent',
    (tester) async {
      final repository = FakeInventoryRepository(
        effectiveSchemasByGroupId: <int, EffectiveGroupSchema>{
          1: EffectiveGroupSchema(
            groupId: 1,
            propertyDrafts: const <GroupPropertyDraft>[
              GroupPropertyDraft(
                name: 'Length',
                propertyKey: 'length',
                inputType: 'Number',
                mandatory: true,
                unitSymbol: 'mm',
                unitLabel: 'Millimetre',
                sourceType: GroupPropertySourceType.inheritedGroup,
                sourceGroupId: 1,
                sourceGroupName: 'Paper',
              ),
            ],
            lineageGroupIds: const <int>[1],
            lineageGroupNames: const <String>['Paper'],
          ),
        },
      );
      await pumpApp(tester, repository: repository);

      final context = tester.element(find.byType(Scaffold).first);
      InventoryScreen.openCreateGroupForm(context);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('groups-parent-field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paper').last);
      await tester.pumpAndSettle();

      expect(find.text('Inherited Properties'), findsOneWidget);
      expect(find.text('Length'), findsOneWidget);
    },
  );

  testWidgets(
    'inventory create-group modal deep-seeds structured property drafts from seed item',
    (tester) async {
      final repository = FakeInventoryRepository();
      final itemRepository = FakeItemRepository(
        seedItems: <ItemDefinition>[
          ItemDefinition(
            id: 41,
            name: 'Profile Rod',
            alias: 'PR',
            displayName: 'Profile Rod - 10',
            quantity: 10,
            groupId: 1,
            unitId: 1,
            propertySchema: const <ItemPropertySchemaEntry>[
              ItemPropertySchemaEntry(
                propertyKey: 'length',
                displayName: 'Length',
                inputType: 'Number',
                mandatory: true,
                unitSymbol: 'mm',
                unitLabel: 'Millimetre',
                sortOrder: 0,
              ),
            ],
            isArchived: false,
            usageCount: 0,
            createdAt: DateTime(2024),
            updatedAt: DateTime(2024),
            variationTree: const <ItemVariationNodeDefinition>[],
          ),
        ],
      );
      await pumpApp(
        tester,
        repository: repository,
        itemRepository: itemRepository,
      );

      final context = tester.element(find.byType(Scaffold).first);
      InventoryScreen.openCreateGroupForm(context);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter group name'),
        'Seeded Group',
      );

      await tester.tap(find.byKey(const ValueKey<String>('groups-unit-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kilogram (Kg)').last);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('masters-group-seed-items')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile Rod - 10').last);
      await tester.pumpAndSettle();

      expect(find.text('Length'), findsOneWidget);

      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      final created = (await repository.getAllMaterials())
          .where((record) => record.name == 'Seeded Group')
          .single;
      final configuration = await repository.getGroupConfiguration(
        created.barcode,
      );
      final seeded = configuration.propertyDrafts.singleWhere(
        (draft) => draft.propertyKey == 'length',
      );
      expect(seeded.inputType, 'Number');
      expect(seeded.mandatory, isTrue);
      expect(seeded.unitSymbol, 'mm');
      expect(seeded.unitLabel, 'Millimetre');
    },
  );

  testWidgets(
    'inventory create-group modal stores discarded inherited properties separately',
    (tester) async {
      final repository = FakeInventoryRepository(
        effectiveSchemasByGroupId: <int, EffectiveGroupSchema>{
          1: EffectiveGroupSchema(
            groupId: 1,
            propertyDrafts: const <GroupPropertyDraft>[
              GroupPropertyDraft(
                name: 'Length',
                propertyKey: 'length',
                inputType: 'Number',
                mandatory: true,
                sourceType: GroupPropertySourceType.inheritedGroup,
                sourceGroupId: 1,
                sourceGroupName: 'Paper',
              ),
            ],
          ),
        },
      );
      await pumpApp(tester, repository: repository);

      final context = tester.element(find.byType(Scaffold).first);
      InventoryScreen.openCreateGroupForm(context);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter group name'),
        'Masked Group',
      );

      await tester.tap(find.byKey(const ValueKey<String>('groups-unit-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kilogram (Kg)').last);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('groups-parent-field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paper').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Length').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      final created = (await repository.getAllMaterials())
          .where((record) => record.name == 'Masked Group')
          .single;
      final configuration = await repository.getGroupConfiguration(
        created.barcode,
      );
      expect(configuration.discardedPropertyKeys, contains('length'));
      expect(
        configuration.propertyDrafts.where(
          (draft) => draft.propertyKey == 'length',
        ),
        isEmpty,
      );
    },
  );

  testWidgets('inventory sets drill down filters items to set membership', (
    tester,
  ) async {
    final repository = FakeInventoryRepository(
      seedMaterials: <MaterialRecord>[
        MaterialRecord(
          id: 1,
          barcode: 'ITEM-1-17',
          name: 'Switch Action Dolly Stock A',
          type: 'Item',
          grade: '',
          thickness: '',
          supplier: 'Warehouse',
          location: 'Rack A',
          createdAt: DateTime(2024),
          kind: 'child',
          parentBarcode: null,
          numberOfChildren: 0,
          linkedChildBarcodes: const <String>[],
          scanCount: 0,
          linkedItemId: 1,
          linkedVariationLeafNodeId: 17,
          displayStock: '2 pcs',
          createdBy: 'Demo Admin',
          workflowStatus: 'notStarted',
        ),
        MaterialRecord(
          id: 2,
          barcode: 'ITEM-1-18',
          name: 'Switch Action Dolly Stock B',
          type: 'Item',
          grade: '',
          thickness: '',
          supplier: 'Warehouse',
          location: 'Rack B',
          createdAt: DateTime(2024),
          kind: 'child',
          parentBarcode: null,
          numberOfChildren: 0,
          linkedChildBarcodes: const <String>[],
          scanCount: 0,
          linkedItemId: 1,
          linkedVariationLeafNodeId: 18,
          displayStock: '2 pcs',
          createdBy: 'Demo Admin',
          workflowStatus: 'notStarted',
        ),
        MaterialRecord(
          id: 3,
          barcode: 'ITEM-2-9',
          name: 'Glue Compound Stock',
          type: 'Item',
          grade: '',
          thickness: '',
          supplier: 'Warehouse',
          location: 'Rack C',
          createdAt: DateTime(2024),
          kind: 'child',
          parentBarcode: null,
          numberOfChildren: 0,
          linkedChildBarcodes: const <String>[],
          scanCount: 0,
          linkedItemId: 2,
          linkedVariationLeafNodeId: 9,
          displayStock: '5 pcs',
          createdBy: 'Demo Admin',
          workflowStatus: 'notStarted',
        ),
      ],
      seedSets: <InventorySetDefinition>[
        InventorySetDefinition(
          id: 1,
          name: 'Starter Pack',
          totalItemCount: 7,
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
          lines: const <InventorySetLineDefinition>[
            InventorySetLineDefinition(
              id: 1,
              itemId: 1,
              variationLeafNodeId: 17,
              quantity: 2,
              position: 0,
              itemName: 'Switch Action Dolly',
              itemDisplayName: 'Switch Action Dolly - 1',
              variationPathLabel:
                  '5 Amp 11+1 Brass 1 Way Dolly Without Plating',
              variationPathNodeIds: <int>[2, 4, 11, 13, 15, 17],
            ),
            InventorySetLineDefinition(
              id: 2,
              itemId: 2,
              variationLeafNodeId: 9,
              quantity: 5,
              position: 1,
              itemName: 'Glue Compound',
              itemDisplayName: 'Glue Compound - 1',
              variationPathLabel: 'Fast Cure',
              variationPathNodeIds: <int>[9],
            ),
          ],
        ),
      ],
    );
    await pumpApp(tester, repository: repository);

    await tester.tap(find.text('Sets').last);
    await tester.pumpAndSettle();

    expect(find.text('Starter Pack'), findsOneWidget);
    expect(find.text('7 items'), findsOneWidget);

    await tester.tap(find.text('Starter Pack'));
    await tester.pumpAndSettle();

    expect(find.text('Viewing items in Starter Pack'), findsOneWidget);
    expect(find.text('Switch Action Dolly - 1'), findsWidgets);
    expect(find.text('Glue Compound - 1'), findsWidgets);
    expect(find.text('Luxury Pump Bottle - 100'), findsNothing);
    expect(
      find.textContaining('Without Plating', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('With Plating', findRichText: true),
      findsNothing,
    );
    expect(find.text('2 in set'), findsOneWidget);
    expect(find.text('5 in set'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Viewing items in Starter Pack'), findsNothing);
    expect(find.text('Luxury Pump Bottle - 100'), findsWidgets);
  });

  testWidgets('set row actions open set menu without navigating into items', (
    tester,
  ) async {
    final repository = FakeInventoryRepository(
      seedSets: <InventorySetDefinition>[
        InventorySetDefinition(
          id: 1,
          name: 'Bottle Set',
          totalItemCount: 2,
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
          lines: const <InventorySetLineDefinition>[
            InventorySetLineDefinition(
              id: 1,
              itemId: 3,
              variationLeafNodeId: 40,
              quantity: 2,
              position: 0,
              itemName: 'Luxury Pump Bottle',
              itemDisplayName: 'Luxury Pump Bottle - 100',
              variationPathLabel: 'PET Amber Gloss Gold Left Lock',
              variationPathNodeIds: <int>[28, 30, 38, 40],
            ),
          ],
        ),
      ],
    );
    await pumpApp(tester, repository: repository);

    await tester.tap(find.text('Sets').last);
    await tester.pumpAndSettle();

    expect(find.text('Bottle Set'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('inventory-row-actions-SET-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Viewing items in Bottle Set'), findsNothing);
    expect(find.text('Edit'), findsWidgets);
    expect(find.text('Delete'), findsWidgets);

    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();

    expect(find.text('Edit Set'), findsOneWidget);
  });

  testWidgets('scan lookups increment trace count', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Open Scan'));
    await tester.pumpAndSettle();

    final barcodeField = find.widgetWithText(TextField, 'Barcode');
    await tester.enterText(barcodeField, 'CHD-0001-01');
    await tester.tap(find.text('Lookup Barcode'));
    await tester.pumpAndSettle();

    expect(find.text('Scanned 1 times'), findsWidgets);
    expect(find.text('Seed Parent - Child 1'), findsOneWidget);

    await tester.tap(find.text('Retry Scan'));
    await tester.pumpAndSettle();

    await tester.enterText(barcodeField, 'CHD-0001-01');
    await tester.tap(find.text('Lookup Barcode'));
    await tester.pumpAndSettle();

    expect(find.text('Scanned 2 times'), findsWidgets);
  });

  testWidgets(
    'settings dialog shows truthful actions and refreshes providers after clear and reset',
    (tester) async {
      final authProvider = FakeAuthProvider(authenticated: true);
      final inventoryRepository = TrackingInventoryRepository();
      final groupRepository = TrackingGroupRepository();
      final unitRepository = TrackingUnitRepository();
      final clientRepository = TrackingClientRepository();
      final itemRepository = TrackingItemRepository();
      final orderRepository = TrackingOrderRepository();
      final deliveryChallanRepository = FakeDeliveryChallanRepository();

      await pumpApp(
        tester,
        authProvider: authProvider,
        repository: inventoryRepository,
        groupRepository: groupRepository,
        unitRepository: unitRepository,
        clientRepository: clientRepository,
        itemRepository: itemRepository,
        orderRepository: orderRepository,
        deliveryChallanRepository: deliveryChallanRepository,
        viewSize: const Size(1440, 900),
      );

      await tester.tap(find.text('Settings &\nPreferences'));
      await tester.pumpAndSettle();

      expect(find.text('Workspace Data Controls'), findsOneWidget);
      expect(find.text('Clear Data'), findsOneWidget);
      expect(find.text('Reset + Reseed Demo'), findsOneWidget);
      expect(find.text('Reseed Data'), findsNothing);

      final initialInventoryFetches = inventoryRepository.getAllMaterialsCalls;
      final initialGroupFetches = groupRepository.getGroupsCalls;
      final initialUnitFetches = unitRepository.getUnitsCalls;
      final initialClientFetches = clientRepository.getClientsCalls;
      final initialItemFetches = itemRepository.getItemsCalls;
      final initialOrderFetches = orderRepository.getOrdersCalls;
      final initialChallanFetches = deliveryChallanRepository.getChallansCalls;

      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Clear Data'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Clear Data'));
      await tester.pumpAndSettle();

      expect(authProvider.clearCalls, 1);
      expect(
        find.text('Backend database cleared successfully.'),
        findsOneWidget,
      );
      expect(
        inventoryRepository.getAllMaterialsCalls,
        greaterThan(initialInventoryFetches),
      );
      expect(groupRepository.getGroupsCalls, greaterThan(initialGroupFetches));
      expect(unitRepository.getUnitsCalls, greaterThan(initialUnitFetches));
      expect(
        clientRepository.getClientsCalls,
        greaterThan(initialClientFetches),
      );
      expect(itemRepository.getItemsCalls, greaterThan(initialItemFetches));
      expect(orderRepository.getOrdersCalls, greaterThan(initialOrderFetches));
      expect(
        deliveryChallanRepository.getChallansCalls,
        greaterThan(initialChallanFetches),
      );

      final postClearInventoryFetches =
          inventoryRepository.getAllMaterialsCalls;
      final postClearGroupFetches = groupRepository.getGroupsCalls;
      final postClearUnitFetches = unitRepository.getUnitsCalls;
      final postClearClientFetches = clientRepository.getClientsCalls;
      final postClearItemFetches = itemRepository.getItemsCalls;
      final postClearOrderFetches = orderRepository.getOrdersCalls;
      final postClearChallanFetches =
          deliveryChallanRepository.getChallansCalls;

      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Reset + Reseed Demo'),
      );
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Reset + Reseed Demo'),
      );
      await tester.pumpAndSettle();

      expect(authProvider.resetCalls, 1);
      expect(
        inventoryRepository.getAllMaterialsCalls,
        greaterThan(postClearInventoryFetches),
      );
      expect(
        groupRepository.getGroupsCalls,
        greaterThan(postClearGroupFetches),
      );
      expect(unitRepository.getUnitsCalls, greaterThan(postClearUnitFetches));
      expect(
        clientRepository.getClientsCalls,
        greaterThan(postClearClientFetches),
      );
      expect(itemRepository.getItemsCalls, greaterThan(postClearItemFetches));
      expect(
        orderRepository.getOrdersCalls,
        greaterThan(postClearOrderFetches),
      );
      expect(
        deliveryChallanRepository.getChallansCalls,
        greaterThan(postClearChallanFetches),
      );
    },
  );

  testWidgets(
    'auth transition triggers one authenticated refresh across core providers',
    (tester) async {
      final authProvider = FakeAuthProvider(authenticated: false);
      final inventoryRepository = TrackingInventoryRepository();
      final groupRepository = TrackingGroupRepository();
      final unitRepository = TrackingUnitRepository();
      final clientRepository = TrackingClientRepository();
      final itemRepository = TrackingItemRepository();
      final orderRepository = TrackingOrderRepository();
      final deliveryChallanRepository = FakeDeliveryChallanRepository();

      await pumpApp(
        tester,
        authProvider: authProvider,
        repository: inventoryRepository,
        groupRepository: groupRepository,
        unitRepository: unitRepository,
        clientRepository: clientRepository,
        itemRepository: itemRepository,
        orderRepository: orderRepository,
        deliveryChallanRepository: deliveryChallanRepository,
      );

      expect(find.text('Sign in'), findsOneWidget);

      final initialInventoryFetches = inventoryRepository.getAllMaterialsCalls;
      final initialGroupFetches = groupRepository.getGroupsCalls;
      final initialUnitFetches = unitRepository.getUnitsCalls;
      final initialClientFetches = clientRepository.getClientsCalls;
      final initialItemFetches = itemRepository.getItemsCalls;
      final initialOrderFetches = orderRepository.getOrdersCalls;
      final initialChallanFetches = deliveryChallanRepository.getChallansCalls;

      authProvider.authenticate();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsNothing);
      expect(
        inventoryRepository.getAllMaterialsCalls,
        greaterThan(initialInventoryFetches),
      );
      expect(groupRepository.getGroupsCalls, greaterThan(initialGroupFetches));
      expect(unitRepository.getUnitsCalls, greaterThan(initialUnitFetches));
      expect(
        clientRepository.getClientsCalls,
        greaterThan(initialClientFetches),
      );
      expect(itemRepository.getItemsCalls, greaterThan(initialItemFetches));
      expect(orderRepository.getOrdersCalls, greaterThan(initialOrderFetches));
      expect(
        deliveryChallanRepository.getChallansCalls,
        greaterThan(initialChallanFetches),
      );
    },
  );
}
