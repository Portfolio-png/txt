import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/create_parent_material_input.dart';
import '../../domain/material_record.dart';
import '../models/inventory_material_model.dart';
import '../models/scan_event_model.dart';
import 'inventory_repository.dart';

class LocalInventoryRepository implements InventoryRepository {
  Database? _database;

  @override
  Future<void> init() async {
    if (_database != null) {
      return;
    }

    final directory = await getApplicationDocumentsDirectory();
    final dbPath = p.join(directory.path, 'paper_inventory.db');
    _database = await openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE materials (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            barcode TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            grade TEXT,
            thickness TEXT,
            supplier TEXT,
            unit_id INTEGER,
            unit TEXT,
            notes TEXT,
            created_at TEXT NOT NULL,
            kind TEXT NOT NULL,
            parent_barcode TEXT,
            number_of_children INTEGER NOT NULL DEFAULT 0,
            linked_child_barcodes TEXT,
            scan_count INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE scan_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            barcode TEXT NOT NULL,
            scanned_at TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE materials ADD COLUMN unit TEXT DEFAULT \'\'',
          );
          await db.execute(
            'ALTER TABLE materials ADD COLUMN notes TEXT DEFAULT \'\'',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE materials ADD COLUMN unit_id INTEGER',
          );
        }
      },
    );
  }

  @override
  Future<void> seedIfEmpty() async {
    final db = await _db;
    final countResult = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM materials',
    );
    final count = Sqflite.firstIntValue(countResult) ?? 0;
    if (count > 0) {
      return;
    }

    await saveParentWithChildren(
      const CreateParentMaterialInput(
        name: 'Copper Master Roll',
        type: 'Raw Material',
        grade: 'A1',
        thickness: '1.2 mm',
        supplier: 'Shree Metals',
        unitId: null,
        numberOfChildren: 3,
      ),
    );
    await saveParentWithChildren(
      const CreateParentMaterialInput(
        name: 'Steel Sheet Batch',
        type: 'Raw Material',
        grade: 'B2',
        thickness: '2.0 mm',
        supplier: 'Metro Steels',
        unitId: null,
        numberOfChildren: 2,
      ),
    );
    await saveParentWithChildren(
      const CreateParentMaterialInput(
        name: 'Aluminium Coil',
        type: 'Raw Material',
        grade: 'AA',
        thickness: '0.8 mm',
        supplier: 'Skyline Supplies',
        unitId: null,
        numberOfChildren: 4,
      ),
    );
  }

  @override
  Future<SaveParentResult> saveParentWithChildren(
    CreateParentMaterialInput input,
  ) async {
    final db = await _db;
    final parentBarcode = _generateParentBarcode();
    final childBarcodes = List<String>.generate(
      input.numberOfChildren,
      (index) => _generateChildBarcode(parentBarcode, index + 1),
    );
    final now = DateTime.now();

    await db.transaction((txn) async {
      final parentModel = InventoryMaterialModel(
        id: null,
        barcode: parentBarcode,
        name: input.name,
        type: input.type,
        grade: input.grade,
        thickness: input.thickness,
        supplier: input.supplier,
        unitId: input.unitId,
        unit: input.unit,
        notes: input.notes,
        createdAt: now,
        kind: 'parent',
        parentBarcode: null,
        numberOfChildren: input.numberOfChildren,
        linkedChildBarcodes: childBarcodes,
        scanCount: 0,
      );
      await txn.insert('materials', parentModel.toMap()..remove('id'));

      for (var i = 0; i < childBarcodes.length; i++) {
        final childNumber = i + 1;
        final childModel = InventoryMaterialModel(
          id: null,
          barcode: childBarcodes[i],
          name: '${input.name} - Child $childNumber',
          type: input.type,
          grade: input.grade,
          thickness: input.thickness,
          supplier: input.supplier,
          unitId: input.unitId,
          unit: input.unit,
          notes: input.notes,
          createdAt: now,
          kind: 'child',
          parentBarcode: parentBarcode,
          numberOfChildren: 0,
          linkedChildBarcodes: const [],
          scanCount: 0,
        );
        await txn.insert('materials', childModel.toMap()..remove('id'));
      }
    });

    return SaveParentResult(
      parentBarcode: parentBarcode,
      childBarcodes: childBarcodes,
    );
  }

  @override
  Future<MaterialRecord?> getMaterialByBarcode(String barcode) async {
    final db = await _db;
    return db.transaction((txn) async {
      final normalizedLookup = _normalizeBarcode(barcode);
      final rawResults = await txn.query('materials');
      final matchedMap = rawResults.cast<Map<String, Object?>>().firstWhere(
        (row) =>
            _normalizeBarcode((row['barcode'] as String?) ?? '') ==
            normalizedLookup,
        orElse: () => <String, Object?>{},
      );

      if (matchedMap.isEmpty) {
        return null;
      }

      final normalizedBarcode = (matchedMap['barcode'] as String?) ?? barcode;
      return _incrementScanCountInTransaction(normalizedBarcode, txn);
    });
  }

  @override
  Future<MaterialRecord?> incrementScanCount(String barcode) async {
    final db = await _db;
    return db.transaction((txn) async {
      return _incrementScanCountInTransaction(barcode, txn);
    });
  }

  Future<MaterialRecord?> _incrementScanCountInTransaction(
    String barcode,
    Transaction transaction,
  ) async {
    final results = await transaction.query(
      'materials',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    if (results.isEmpty) {
      return null;
    }

    final model = InventoryMaterialModel.fromMap(results.first);
    await transaction.rawUpdate(
      'UPDATE materials SET scan_count = scan_count + 1 WHERE barcode = ?',
      [model.barcode],
    );

    await transaction.insert(
      'scan_history',
      ScanEventModel(barcode: model.barcode, scannedAt: DateTime.now()).toMap()
        ..remove('id'),
    );

    final updatedResults = await transaction.query(
      'materials',
      where: 'barcode = ?',
      whereArgs: [model.barcode],
      limit: 1,
    );
    if (updatedResults.isEmpty) {
      return model.toRecord();
    }

    return InventoryMaterialModel.fromMap(updatedResults.first).toRecord();
  }

  @override
  Future<MaterialRecord?> resetScanTrace(String barcode) async {
    final db = await _db;
    return db.transaction((txn) async {
      final results = await txn.query(
        'materials',
        where: 'barcode = ?',
        whereArgs: [barcode],
        limit: 1,
      );
      if (results.isEmpty) {
        return null;
      }

      await txn.update(
        'materials',
        {'scan_count': 0},
        where: 'barcode = ?',
        whereArgs: [barcode],
      );
      await txn.delete(
        'scan_history',
        where: 'barcode = ?',
        whereArgs: [barcode],
      );

      final updatedResults = await txn.query(
        'materials',
        where: 'barcode = ?',
        whereArgs: [barcode],
        limit: 1,
      );
      return InventoryMaterialModel.fromMap(updatedResults.first).toRecord();
    });
  }

  @override
  Future<List<MaterialRecord>> getAllMaterials() async {
    final db = await _db;
    final results = await db.query(
      'materials',
      orderBy: 'kind ASC, created_at DESC, barcode ASC',
    );
    final models = results.map(InventoryMaterialModel.fromMap).toList();

    models.sort((a, b) {
      if (a.kind == b.kind) {
        if (a.kind == 'child') {
          final parentCompare = (a.parentBarcode ?? '').compareTo(
            b.parentBarcode ?? '',
          );
          if (parentCompare != 0) {
            return parentCompare;
          }
        }
        return a.barcode.compareTo(b.barcode);
      }
      return a.kind == 'parent' ? -1 : 1;
    });

    return models.map((model) => model.toRecord()).toList();
  }

  Future<Database> get _db async {
    await init();
    return _database!;
  }

  String _generateParentBarcode() {
    final random = Random();
    final suffix = 1000 + random.nextInt(9000);
    return 'PAR-${DateTime.now().millisecondsSinceEpoch}-$suffix';
  }

  String _generateChildBarcode(String parentBarcode, int index) {
    final parts = parentBarcode.split('-');
    final suffix = parts.length >= 2 ? parts[parts.length - 1] : parentBarcode;
    return 'CHD-$suffix-${index.toString().padLeft(2, '0')}';
  }

  String _normalizeBarcode(String value) {
    return value
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '')
        .trim()
        .toUpperCase();
  }
}
