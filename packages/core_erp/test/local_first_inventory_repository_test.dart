import 'dart:convert';

import 'package:core_erp/core/database/local_database_helper.dart';
import 'package:core_erp/features/inventory/data/models/api_models.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/data/repositories/local_first_inventory_repository.dart';
import 'package:core_erp/features/inventory/domain/inventory_control_tower.dart';
import 'package:core_erp/features/inventory/domain/inventory_set_definition.dart';
import 'package:core_erp/features/inventory/domain/material_record.dart';
import 'package:core_erp/features/inventory/domain/variation_stock_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Materials off the replica.
///
/// The most valuable decorator on the live path: InventoryProvider re-issues
/// four requests on every challan write anywhere in the workspace, and the
/// materials list is the largest of them.

class _FakeInventory implements InventoryRepository {
  List<MaterialRecord> materials = const <MaterialRecord>[];
  int listCalls = 0;
  int byBarcodeCalls = 0;

  @override
  Future<List<MaterialRecord>> getAllMaterials() async {
    listCalls += 1;
    return materials;
  }

  @override
  Future<MaterialRecord?> getMaterialByBarcode(String barcode) async {
    byBarcodeCalls += 1;
    for (final material in materials) {
      if (material.barcode == barcode) return material;
    }
    return null;
  }

  final List<String> delegated = <String>[];

  @override
  Future<List<VariationStockRecord>> getVariationStock() async {
    delegated.add('getVariationStock');
    return const <VariationStockRecord>[];
  }

  @override
  Future<List<InventorySetDefinition>> getSets() async {
    delegated.add('getSets');
    return const <InventorySetDefinition>[];
  }

  @override
  Future<InventoryHealthSnapshot> getInventoryHealth() async {
    delegated.add('getInventoryHealth');
    return const InventoryHealthSnapshot();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} should not be reached');
}

Map<String, dynamic> materialPayload({
  required int id,
  required String barcode,
  required String name,
  required String kind,
  required String createdAt,
}) => <String, dynamic>{
  'id': id,
  'barcode': barcode,
  'name': name,
  'type': 'raw_material',
  'kind': kind,
  'grade': '',
  'thickness': '',
  'supplier': '',
  'location': '',
  'unit': 'kg',
  'notes': '',
  'isParent': kind == 'parent',
  'parentBarcode': null,
  'numberOfChildren': 0,
  'linkedChildBarcodes': <dynamic>[],
  'scanCount': 0,
  'createdAt': createdAt,
  'displayStock': '',
  'createdBy': '',
  'workflowStatus': '',
  'materialClass': '',
  'inventoryState': 'available',
  'procurementState': '',
  'traceabilityMode': '',
};

void main() {
  late Database db;
  late _FakeInventory remote;
  late LocalFirstInventoryRepository repository;
  var hydrated = true;

  Future<void> seed(Map<String, dynamic> payload) async {
    await db.insert('local_materials', <String, Object?>{
      'id': payload['id'],
      'barcode': payload['barcode'],
      'name': payload['name'],
      'kind': payload['kind'],
      'created_at': payload['createdAt'],
      'raw_payload_json': jsonEncode(payload),
    });
  }

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    for (final statement in LocalDatabaseHelper.schemaStatements) {
      await db.execute(statement);
    }
    remote = _FakeInventory();
    hydrated = true;
    repository = LocalFirstInventoryRepository(
      remote: remote,
      replica: () async => db,
      isHydrated: () => hydrated,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('the materials list comes off the replica', () async {
    await seed(materialPayload(
      id: 1, barcode: 'MAT-1', name: 'Steel', kind: 'single',
      createdAt: '2026-01-01T00:00:00.000Z',
    ));
    final materials = await repository.getAllMaterials();
    expect(materials.single.barcode, 'MAT-1');
    expect(remote.listCalls, 0);
  });

  test('ordered by kind, then newest, then barcode', () async {
    // `ORDER BY kind ASC, created_at DESC, barcode ASC`. `kind` was not on the
    // DTO at all until the replica needed it — the endpoint was sorting by a
    // column it did not expose, so no client could reproduce its order.
    await seed(materialPayload(
      id: 1, barcode: 'B', name: 'parent-old', kind: 'parent',
      createdAt: '2026-01-01T00:00:00.000Z',
    ));
    await seed(materialPayload(
      id: 2, barcode: 'A', name: 'child', kind: 'child',
      createdAt: '2026-01-01T00:00:00.000Z',
    ));
    await seed(materialPayload(
      id: 3, barcode: 'C', name: 'parent-new', kind: 'parent',
      createdAt: '2026-06-01T00:00:00.000Z',
    ));

    final names = (await repository.getAllMaterials()).map((m) => m.name);
    expect(names, <String>['child', 'parent-new', 'parent-old']);
  });

  test('a barcode lookup misses to the server, not to null', () async {
    // A scanned barcode the app reports as unknown is the worst answer it can
    // give — and a replica that has not caught up is not evidence of absence.
    remote.materials = <MaterialRecord>[
      MaterialDto.fromJson(materialPayload(
        id: 9, barcode: 'MAT-NEW', name: 'Just received', kind: 'single',
        createdAt: '2026-01-01T00:00:00.000Z',
      )).toRecord(),
    ];
    final found = await repository.getMaterialByBarcode('MAT-NEW');
    expect(found?.name, 'Just received');
    expect(remote.byBarcodeCalls, 1);
  });

  test('an unsynced replica asks the server', () async {
    await seed(materialPayload(
      id: 1, barcode: 'MAT-STALE', name: 'Stale', kind: 'single',
      createdAt: '2026-01-01T00:00:00.000Z',
    ));
    hydrated = false;
    remote.materials = <MaterialRecord>[
      MaterialDto.fromJson(materialPayload(
        id: 2, barcode: 'MAT-FRESH', name: 'Fresh', kind: 'single',
        createdAt: '2026-01-01T00:00:00.000Z',
      )).toRecord(),
    ];
    expect((await repository.getAllMaterials()).single.barcode, 'MAT-FRESH');
  });

  test('stock, sets and health still go to the server', () async {
    // They have no local tables — no endpoint even emits an
    // inventory_stock_positions id, so a delta could not address one.
    await repository.getVariationStock();
    await repository.getSets();
    await repository.getInventoryHealth();
    expect(remote.delegated, <String>['getVariationStock', 'getSets', 'getInventoryHealth']);
  });
}
