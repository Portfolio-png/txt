import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:paper/features/groups/data/repositories/group_repository.dart';
import 'package:paper/features/groups/domain/group_definition.dart';
import 'package:paper/features/groups/domain/group_inputs.dart';
import 'package:paper/features/inventory/data/repositories/inventory_repository.dart';
import 'package:paper/features/inventory/domain/create_parent_material_input.dart';
import 'package:paper/features/inventory/domain/material_inputs.dart';
import 'package:paper/features/inventory/domain/material_record.dart';
import 'package:paper/features/clients/data/repositories/client_repository.dart';
import 'package:paper/features/clients/domain/client_definition.dart';
import 'package:paper/features/clients/domain/client_inputs.dart';
import 'package:paper/features/items/data/repositories/item_repository.dart';
import 'package:paper/features/items/domain/item_definition.dart';
import 'package:paper/features/items/domain/item_inputs.dart';
import 'package:paper/features/orders/data/repositories/order_repository.dart';
import 'package:paper/features/orders/domain/order_entry.dart';
import 'package:paper/features/orders/domain/order_inputs.dart';
import 'package:paper/features/units/data/repositories/unit_repository.dart';
import 'package:paper/features/units/domain/unit_definition.dart';
import 'package:paper/features/units/domain/unit_inputs.dart';
import 'package:paper/main.dart';

class FakeInventoryRepository extends InventoryRepository {
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
  Future<MaterialRecord> linkMaterialToItem(String barcode, int itemId) async {
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
          item.quantity == input.quantity &&
          item.name.trim().toLowerCase() == input.name.trim().toLowerCase(),
    );
    if (duplicate) {
      throw Exception(
        'An item with the same name and quantity already exists in this group.',
      );
    }
    _validateTree(input.variationTree, ItemVariationNodeKind.property);
    final itemId = _nextId++;
    final created = ItemDefinition(
      id: itemId,
      name: input.name.trim(),
      alias: input.alias.trim(),
      displayName: input.displayName.trim(),
      quantity: input.quantity,
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
    if (current.usageCount > 0) {
      throw Exception('Used items cannot be edited.');
    }
    _validateTree(input.variationTree, ItemVariationNodeKind.property);
    final updated = ItemDefinition(
      id: current.id,
      name: input.name.trim(),
      alias: input.alias.trim(),
      displayName: input.displayName.trim(),
      quantity: input.quantity,
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
  final List<OrderEntry> _orders = <OrderEntry>[];
  int _nextId = 1;

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
          order.poNumber.trim().toLowerCase() == normalizedPoNo,
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
        status: current.status,
        createdAt: current.createdAt,
        startDate: current.startDate,
        endDate: current.endDate,
      );
      _orders[index] = updated;
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
      status: input.status,
      createdAt: DateTime.now(),
      startDate: input.startDate,
      endDate: input.endDate,
    );
    _orders.add(created);
    return created;
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
      status: input.status,
      createdAt: current.createdAt,
      startDate: input.startDate,
      endDate: input.endDate,
    );
    _orders[index] = updated;
    return updated;
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
    FakeInventoryRepository? repository,
    FakeGroupRepository? groupRepository,
    FakeUnitRepository? unitRepository,
    FakeClientRepository? clientRepository,
    FakeItemRepository? itemRepository,
    FakeOrderRepository? orderRepository,
  }) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MyApp(
        inventoryRepository: repository ?? FakeInventoryRepository(),
        groupRepository: groupRepository ?? FakeGroupRepository(),
        unitRepository: unitRepository ?? FakeUnitRepository(),
        clientRepository: clientRepository ?? FakeClientRepository(),
        itemRepository: itemRepository ?? FakeItemRepository(),
        orderRepository: orderRepository ?? FakeOrderRepository(),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool sidebarTileHasFocus(WidgetTester tester, String key) {
    final widget = tester.widget<InkWell>(
      find.byKey(ValueKey<String>('sidebar_tile_$key')),
    );
    return widget.focusNode?.hasFocus ?? false;
  }

  testWidgets('app opens into inventory shell', (tester) async {
    await pumpApp(tester);

    expect(find.text('+ Add Stock'), findsOneWidget);
    expect(find.text('+ New Group'), findsOneWidget);
    expect(find.text('Inventory'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('shell_top_strip_search_field')),
      findsOneWidget,
    );
    expect(
      find.text('Search groups, items, barcode, supplier, or notes'),
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

    await tester.tap(find.text('Clients'));
    await tester.pumpAndSettle();

    expect(find.text('Search clients, alias, GST, or address'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('Items'));
    await tester.pumpAndSettle();

    expect(
      find.text('Search items, properties, values, or leaf paths'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('ctrl+tab cycles sidebar navigation forward', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();

    expect(
      find.text('Search orders, clients, PO, items, or status'),
      findsOneWidget,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(
      find.text('Search groups, items, barcode, supplier, or notes'),
      findsOneWidget,
    );
  });

  testWidgets('tab focus stays looped inside sidebar items', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Units'));
    await tester.pumpAndSettle();

    expect(sidebarTileHasFocus(tester, 'configurator_units'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(sidebarTileHasFocus(tester, 'configurator_units'), isFalse);
    expect(sidebarTileHasFocus(tester, 'dashboard'), isTrue);
  });

  testWidgets('inventory top strip actions invoke navigation callbacks', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Open Scan'));
    await tester.pumpAndSettle();

    expect(find.text('Material Scan'), findsWidgets);
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
        await tester.tap(find.text(navLabel).first);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey<String>('shell_top_strip_search_field')),
          query,
        );
        await tester.pumpAndSettle();

        expect(find.text(visibleText), findsWidgets);
        expect(find.text(hiddenText), findsNothing);
        expect(find.byType(TextField), findsOneWidget);
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

  testWidgets('orders flow auto-fills client code from client master', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();

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

    expect(find.text('Acme'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey<String>('orders-editor-po-number-field')),
      'PO-42',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-item-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch Action Dolly - 1').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-dolly-amp-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 Amp').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-patti-+-dabbi-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('11+1').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-dolly-alloy-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brass').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-dolly-contact-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 Way').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-dolly-type-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dolly').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-dolly-plating-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Without Plating').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('orders-editor-quantity-field')),
      '25',
    );

    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Create Order'),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Order'));
    await tester.pumpAndSettle();

    expect(find.text('ORD-001'), findsOneWidget);
    expect(find.text('Acme Packaging Pvt. Ltd.'), findsOneWidget);
    expect(find.text('PO-42'), findsOneWidget);
    expect(
      find.text(
        'Switch Action Dolly - 1 · 5 Amp 11+1 Brass 1 Way Dolly Without Plating',
      ),
      findsOneWidget,
    );
    expect(find.text('25 Pieces'), findsOneWidget);
  });

  testWidgets('orders search filters through the shared shell strip', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Orders').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Order').first);
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
    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-item-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch Action Dolly - 1').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-dolly-amp-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 Amp').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-patti-+-dabbi-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('11+1').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-dolly-alloy-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brass').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-dolly-contact-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 Way').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-dolly-type-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dolly').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-dolly-plating-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Without Plating').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('orders-editor-quantity-field')),
      '11',
    );
    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Create Order'),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Order'));
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

    expect(find.text('No orders found'), findsOneWidget);
  });

  testWidgets('orders merge duplicate lines by order client po and item', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Orders').first);
    await tester.pumpAndSettle();

    Future<void> addOrder(String qty) async {
      await tester.tap(find.text('New Order').first);
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
      await tester.tap(
        find.byKey(const ValueKey<String>('orders-editor-item-field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch Action Dolly - 1').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('orders-editor-action-dolly-amp-field'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('5 Amp').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('orders-editor-action-patti-+-dabbi-field'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('11+1').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('orders-editor-action-dolly-alloy-field'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Brass').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('orders-editor-action-dolly-contact-field'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 Way').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('orders-editor-action-dolly-type-field'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dolly').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('orders-editor-action-dolly-plating-field'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Without Plating').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('orders-editor-quantity-field')),
        qty,
      );
      await tester.ensureVisible(
        find.widgetWithText(ElevatedButton, 'Create Order'),
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Order'));
      await tester.pumpAndSettle();
    }

    await addOrder('10');
    await addOrder('5');

    expect(find.text('ORD-002'), findsOneWidget);
    expect(find.text('15 Pieces'), findsOneWidget);
  });

  testWidgets('orders lifecycle can be updated from table row', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Orders').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Order').first);
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
    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-item-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch Action Dolly - 1').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-dolly-amp-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 Amp').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-patti-+-dabbi-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('11+1').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-dolly-alloy-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brass').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-dolly-contact-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 Way').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-dolly-type-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dolly').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-dolly-plating-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Without Plating').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('orders-editor-quantity-field')),
      '8',
    );

    final createStatusField = find.byKey(
      const ValueKey<String>('orders-editor-status-field'),
    );
    await tester.ensureVisible(createStatusField);
    await tester.tap(createStatusField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('In Progress').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Create Order'),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Order'));
    await tester.pumpAndSettle();

    expect(find.text('In Progress'), findsWidgets);

    final orderRow = find.text('ORD-004').last;
    await tester.ensureVisible(orderRow);
    await tester.tap(orderRow, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Order Details'), findsOneWidget);
    expect(find.text('Purchase order no.'), findsOneWidget);
    expect(find.text('PO-88'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Edit'));
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

  testWidgets('orders block creation when selected client has no code', (
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
    await pumpApp(tester, clientRepository: clientRepository);

    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Order').first);
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

    await tester.tap(
      find.byKey(const ValueKey<String>('orders-editor-item-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch Action Dolly - 1').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-dolly-amp-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 Amp').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-patti-+-dabbi-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('11+1').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-dolly-alloy-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brass').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-dolly-contact-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 Way').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-dolly-type-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dolly').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('orders-editor-action-dolly-plating-field'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Without Plating').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('orders-editor-quantity-field')),
      '4',
    );

    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Create Order'),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Order'));
    await tester.pumpAndSettle();

    expect(
      find.text('Selected client has no client code in master.'),
      findsOneWidget,
    );
    expect(find.text('No orders found'), findsOneWidget);
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

    await tester.tap(find.text('Units'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Kilogram'), findsOneWidget);
    expect(find.text('Sheet'), findsWidgets);

    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();

    expect(find.text('Legacy'), findsOneWidget);
  });

  testWidgets('groups screen shows seeded and archived groups', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Groups'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Paper'), findsWidgets);
    expect(find.text('Kraft'), findsOneWidget);

    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();

    expect(find.text('Legacy Group'), findsOneWidget);
  });

  testWidgets('groups add flow creates a child group', (tester) async {
    final groupRepository = FakeGroupRepository();
    await pumpApp(tester, groupRepository: groupRepository);

    await tester.tap(find.text('Groups'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Group'));
    await tester.pumpAndSettle();

    expect(find.text('Parent group'), findsOneWidget);
    expect(find.text('Unit of group'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Group name'),
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

    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Group'));
    await tester.pumpAndSettle();

    expect(find.text('Brown'), findsOneWidget);

    final groups = await groupRepository.getGroups();
    final created = groups.where((group) => group.name == 'Brown').single;
    expect(created.parentGroupId, 3);
    expect(created.unitId, 1);
  });

  testWidgets('groups edit flow preloads parent and unit', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Groups'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Kraft');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit').first);
    await tester.pumpAndSettle();

    expect(find.text('Parent: Paper'), findsOneWidget);
    expect(find.text('Unit: Sheet (Sheet)'), findsOneWidget);
  });

  testWidgets('groups screen shows empty state when no groups exist', (
    tester,
  ) async {
    await pumpApp(
      tester,
      groupRepository: FakeGroupRepository(seedGroups: <GroupDefinition>[]),
    );

    await tester.tap(find.text('Groups'));
    await tester.pumpAndSettle();

    expect(find.text('No groups found'), findsOneWidget);
  });

  testWidgets('clients screen shows seeded and archived clients', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Clients'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Acme Packaging Pvt. Ltd.'), findsOneWidget);
    expect(find.text('Sunrise Retail LLP'), findsOneWidget);

    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();

    expect(find.text('Legacy Trading Co.'), findsOneWidget);
  });

  testWidgets('clients add flow creates a client record', (tester) async {
    final clientRepository = FakeClientRepository();
    await pumpApp(tester, clientRepository: clientRepository);

    await tester.tap(find.text('Clients'));
    await tester.pumpAndSettle();

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

  testWidgets('items screen shows seeded and archived items', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Items'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Switch Action Dolly - 1'), findsOneWidget);
    expect(find.text('Glue Compound - 1'), findsOneWidget);
    expect(find.text('Luxury Pump Bottle - 100'), findsOneWidget);
    expect(find.text('Premium Mono Carton - 500'), findsOneWidget);

    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();

    expect(find.text('Legacy Stock - 5'), findsWidgets);
  });

  testWidgets('items add flow creates recursive variation tree', (
    tester,
  ) async {
    final itemRepository = FakeItemRepository();
    await pumpApp(tester, itemRepository: itemRepository);

    await tester.tap(find.text('Items'));
    await tester.pumpAndSettle();

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
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Quantity'),
      '200',
    );

    await tester.tap(find.byKey(const ValueKey<String>('items-unit-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sheet (Sheet)').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('items-group-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paper').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Add Top-Level Property'),
    );
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Add Top-Level Property'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Property Name').first,
      'Color',
    );

    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Add Value'),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Value').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Value Name').first,
      'Black',
    );

    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Add Property').last,
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Property').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Property Name').last,
      'Finish',
    );

    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Add Value').last,
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Value').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Value Name').last,
      'Glossy',
    );

    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Create Item'),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Item'));
    await tester.pumpAndSettle();

    expect(find.text('Bottle / Travel Bottle - 200'), findsWidgets);
    final items = await itemRepository.getItems();
    final created = items
        .where((item) => item.name == 'Bottle' && item.quantity == 200)
        .single;
    expect(created.displayName, 'Bottle / Travel Bottle - 200');
    expect(created.topLevelProperties.single.name, 'Color');
    expect(created.leafVariationNodes.single.displayName, 'Black Glossy');
  });

  testWidgets('items duplicate sibling names are blocked', (tester) async {
    await pumpApp(tester, itemRepository: FakeItemRepository());

    await tester.tap(find.text('Items'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Item'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Test Item',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Quantity'),
      '100',
    );

    await tester.tap(find.byKey(const ValueKey<String>('items-unit-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sheet (Sheet)').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('items-group-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paper').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Add Top-Level Property'),
    );
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Add Top-Level Property'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Property Name').first,
      'Color',
    );

    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Add Top-Level Property'),
    );
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Add Top-Level Property'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Property Name').last,
      'Color',
    );

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

    await tester.tap(find.text('Groups'));
    await tester.pumpAndSettle();

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
}
