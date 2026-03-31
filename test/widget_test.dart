import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:paper/main.dart';
import 'package:paper/features/inventory/data/repositories/inventory_repository.dart';
import 'package:paper/features/inventory/domain/create_parent_material_input.dart';
import 'package:paper/features/inventory/domain/material_record.dart';

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
      createdAt: DateTime(2024),
      kind: 'parent',
      parentBarcode: null,
      numberOfChildren: 2,
      linkedChildBarcodes: const ['CHD-0001-01', 'CHD-0001-02'],
      scanCount: 0,
    ),
    MaterialRecord(
      id: 2,
      barcode: 'CHD-0001-01',
      name: 'Seed Parent - Child 1',
      type: 'Raw Material',
      grade: 'A1',
      thickness: '1.2 mm',
      supplier: 'Seed Supplier',
      createdAt: DateTime(2024),
      kind: 'child',
      parentBarcode: 'PAR-SEED-0001',
      numberOfChildren: 0,
      linkedChildBarcodes: const [],
      scanCount: 0,
    ),
    MaterialRecord(
      id: 3,
      barcode: 'CHD-0001-02',
      name: 'Seed Parent - Child 2',
      type: 'Raw Material',
      grade: 'A1',
      thickness: '1.2 mm',
      supplier: 'Seed Supplier',
      createdAt: DateTime(2024),
      kind: 'child',
      parentBarcode: 'PAR-SEED-0001',
      numberOfChildren: 0,
      linkedChildBarcodes: const [],
      scanCount: 0,
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
        createdAt: DateTime.now(),
        kind: 'parent',
        parentBarcode: null,
        numberOfChildren: input.numberOfChildren,
        linkedChildBarcodes: childBarcodes,
        scanCount: 0,
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
          createdAt: DateTime.now(),
          kind: 'child',
          parentBarcode: parentBarcode,
          numberOfChildren: 0,
          linkedChildBarcodes: const [],
          scanCount: 0,
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
      createdAt: record.createdAt,
      kind: record.kind,
      parentBarcode: record.parentBarcode,
      numberOfChildren: record.numberOfChildren,
      linkedChildBarcodes: record.linkedChildBarcodes,
      scanCount: record.scanCount + 1,
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
      createdAt: record.createdAt,
      kind: record.kind,
      parentBarcode: record.parentBarcode,
      numberOfChildren: record.numberOfChildren,
      linkedChildBarcodes: record.linkedChildBarcodes,
      scanCount: 0,
    );
    _materials[index] = updated;
    return updated;
  }
}

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    FakeInventoryRepository? repository,
  }) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MyApp(inventoryRepository: repository ?? FakeInventoryRepository()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('app opens into inventory shell', (tester) async {
    await pumpApp(tester);

    expect(find.text('Inventory Materials'), findsOneWidget);
    expect(find.text('Add New Big Sheet'), findsOneWidget);
    expect(find.text('Inventory'), findsWidgets);
  });

  testWidgets(
    'inventory add flow creates parent and four children with hierarchy',
    (tester) async {
      final repository = FakeInventoryRepository();
      await pumpApp(tester, repository: repository);

      await tester.tap(find.text('Add New Big Sheet'));
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
      expect(find.text('Parent of 4 children'), findsWidgets);
      expect(createdChildren, hasLength(4));
      expect(createdChildren.first.name, 'Dolly Sheet - Child 1');
      expect(createdChildren.last.name, 'Dolly Sheet - Child 4');
    },
  );

  testWidgets('scan lookups increment trace count', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.textContaining('Inventory Scan'));
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
