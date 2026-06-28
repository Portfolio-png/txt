import 'dart:convert';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/create_parent_material_input.dart';
import '../../domain/effective_group_schema.dart';
import '../../domain/group_property_draft.dart';
import '../../domain/inventory_control_tower.dart';
import '../../domain/inventory_set_definition.dart';
import '../../domain/material_activity_event.dart';
import '../../domain/material_control_tower_detail.dart';
import '../../domain/material_group_configuration.dart';
import '../../domain/material_inputs.dart';
import '../../domain/material_record.dart';
import '../models/material_activity_event_model.dart';
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
      version: 14,
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
            location TEXT,
            unit_id INTEGER,
            unit TEXT,
            notes TEXT,
            group_mode TEXT,
            inheritance_enabled INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            kind TEXT NOT NULL,
            parent_barcode TEXT,
            number_of_children INTEGER NOT NULL DEFAULT 0,
            linked_child_barcodes TEXT,
            scan_count INTEGER NOT NULL DEFAULT 0,
            linked_group_id INTEGER,
            linked_item_id INTEGER,
            linked_variation_leaf_node_id INTEGER,
            display_stock TEXT DEFAULT '',
            created_by TEXT DEFAULT '',
            workflow_status TEXT DEFAULT 'notStarted',
            material_class TEXT DEFAULT 'raw_material',
            inventory_state TEXT DEFAULT 'available',
            procurement_state TEXT DEFAULT 'not_ordered',
            traceability_mode TEXT DEFAULT 'bulk',
            on_hand_qty REAL NOT NULL DEFAULT 0,
            reserved_qty REAL NOT NULL DEFAULT 0,
            available_to_promise_qty REAL NOT NULL DEFAULT 0,
            incoming_qty REAL NOT NULL DEFAULT 0,
            linked_order_count INTEGER NOT NULL DEFAULT 0,
            linked_pipeline_count INTEGER NOT NULL DEFAULT 0,
            pending_alert_count INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT,
            last_scanned_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE material_group_item_links (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            material_id INTEGER NOT NULL,
            item_id INTEGER NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(material_id, item_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE material_group_properties (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            material_id INTEGER NOT NULL,
            property_key TEXT NOT NULL,
            display_name TEXT NOT NULL,
            input_type TEXT NOT NULL DEFAULT 'Text',
            mandatory INTEGER NOT NULL DEFAULT 0,
            unit_id INTEGER,
            unit_symbol TEXT,
            unit_label TEXT,
            source_type TEXT NOT NULL DEFAULT 'manual',
            source_item_ids_json TEXT NOT NULL DEFAULT '[]',
            source_group_id INTEGER,
            source_group_name TEXT,
            state TEXT NOT NULL DEFAULT 'active',
            override_locked INTEGER NOT NULL DEFAULT 0,
            has_type_conflict INTEGER NOT NULL DEFAULT 0,
            coverage_count INTEGER NOT NULL DEFAULT 0,
            selected_item_count_at_resolution INTEGER NOT NULL DEFAULT 0,
            resolution_source TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(material_id, property_key)
          )
        ''');
        await db.execute('''
          CREATE TABLE material_group_units (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            material_id INTEGER NOT NULL,
            unit_id INTEGER NOT NULL,
            state TEXT NOT NULL DEFAULT 'active',
            is_primary INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(material_id, unit_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE material_group_preferences (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            material_id INTEGER NOT NULL UNIQUE,
            common_only_mode INTEGER NOT NULL DEFAULT 1,
            show_partial_matches INTEGER NOT NULL DEFAULT 1,
            discarded_property_keys_json TEXT NOT NULL DEFAULT '[]',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE scan_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            barcode TEXT NOT NULL,
            scanned_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE material_activity (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            barcode TEXT NOT NULL,
            event_type TEXT NOT NULL,
            event_label TEXT NOT NULL,
            event_description TEXT DEFAULT '',
            actor TEXT DEFAULT '',
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE inventory_sets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE inventory_set_lines (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            set_id INTEGER NOT NULL,
            item_id INTEGER NOT NULL,
            variation_leaf_node_id INTEGER DEFAULT 0,
            quantity INTEGER NOT NULL DEFAULT 1,
            position INTEGER NOT NULL DEFAULT 0,
            item_name TEXT DEFAULT '',
            item_display_name TEXT DEFAULT '',
            variation_path_label TEXT DEFAULT '',
            variation_path_node_ids_json TEXT NOT NULL DEFAULT '[]',
            UNIQUE(set_id, item_id, variation_leaf_node_id)
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
          await db.execute('ALTER TABLE materials ADD COLUMN unit_id INTEGER');
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE materials ADD COLUMN linked_group_id INTEGER',
          );
          await db.execute(
            'ALTER TABLE materials ADD COLUMN linked_item_id INTEGER',
          );
        }
        if (oldVersion < 5) {
          await db.execute(
            'ALTER TABLE materials ADD COLUMN display_stock TEXT DEFAULT \'\'',
          );
          await db.execute(
            'ALTER TABLE materials ADD COLUMN created_by TEXT DEFAULT \'\'',
          );
          await db.execute(
            'ALTER TABLE materials ADD COLUMN workflow_status TEXT DEFAULT \'notStarted\'',
          );
          await db.execute('ALTER TABLE materials ADD COLUMN updated_at TEXT');
          await db.execute(
            'ALTER TABLE materials ADD COLUMN last_scanned_at TEXT',
          );
          await db.execute(
            'UPDATE materials SET updated_at = created_at WHERE updated_at IS NULL',
          );
        }
        if (oldVersion < 6) {
          await db.execute('''
            CREATE TABLE material_activity (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              barcode TEXT NOT NULL,
              event_type TEXT NOT NULL,
              event_label TEXT NOT NULL,
              event_description TEXT DEFAULT '',
              actor TEXT DEFAULT '',
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 7) {
          await db.execute(
            'ALTER TABLE materials ADD COLUMN location TEXT DEFAULT \'\'',
          );
        }
        if (oldVersion < 8) {
          await db.execute('ALTER TABLE materials ADD COLUMN group_mode TEXT');
          await db.execute(
            'ALTER TABLE materials ADD COLUMN inheritance_enabled INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute('''
            CREATE TABLE IF NOT EXISTS material_group_item_links (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              material_id INTEGER NOT NULL,
              item_id INTEGER NOT NULL,
              sort_order INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              UNIQUE(material_id, item_id)
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS material_group_properties (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              material_id INTEGER NOT NULL,
              property_key TEXT NOT NULL,
              display_name TEXT NOT NULL,
              input_type TEXT NOT NULL DEFAULT 'Text',
              mandatory INTEGER NOT NULL DEFAULT 0,
              unit_id INTEGER,
              unit_symbol TEXT,
              unit_label TEXT,
              source_type TEXT NOT NULL DEFAULT 'manual',
              source_item_ids_json TEXT NOT NULL DEFAULT '[]',
              source_group_id INTEGER,
              source_group_name TEXT,
              state TEXT NOT NULL DEFAULT 'active',
              override_locked INTEGER NOT NULL DEFAULT 0,
              has_type_conflict INTEGER NOT NULL DEFAULT 0,
              coverage_count INTEGER NOT NULL DEFAULT 0,
              selected_item_count_at_resolution INTEGER NOT NULL DEFAULT 0,
              resolution_source TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              UNIQUE(material_id, property_key)
            )
          ''');
        }
        if (oldVersion < 9) {
          await db.execute(
            'ALTER TABLE material_group_properties ADD COLUMN coverage_count INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE material_group_properties ADD COLUMN selected_item_count_at_resolution INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE material_group_properties ADD COLUMN resolution_source TEXT',
          );
          await db.execute('''
            CREATE TABLE IF NOT EXISTS material_group_units (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              material_id INTEGER NOT NULL,
              unit_id INTEGER NOT NULL,
              state TEXT NOT NULL DEFAULT 'active',
              is_primary INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              UNIQUE(material_id, unit_id)
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS material_group_preferences (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              material_id INTEGER NOT NULL UNIQUE,
              common_only_mode INTEGER NOT NULL DEFAULT 1,
              show_partial_matches INTEGER NOT NULL DEFAULT 1,
              discarded_property_keys_json TEXT NOT NULL DEFAULT '[]',
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 10) {
          await db.execute(
            'ALTER TABLE materials ADD COLUMN material_class TEXT DEFAULT \'raw_material\'',
          );
          await db.execute(
            'ALTER TABLE materials ADD COLUMN inventory_state TEXT DEFAULT \'available\'',
          );
          await db.execute(
            'ALTER TABLE materials ADD COLUMN procurement_state TEXT DEFAULT \'not_ordered\'',
          );
          await db.execute(
            'ALTER TABLE materials ADD COLUMN traceability_mode TEXT DEFAULT \'bulk\'',
          );
          await db.execute(
            'ALTER TABLE materials ADD COLUMN on_hand_qty REAL NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE materials ADD COLUMN reserved_qty REAL NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE materials ADD COLUMN available_to_promise_qty REAL NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE materials ADD COLUMN incoming_qty REAL NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE materials ADD COLUMN linked_order_count INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE materials ADD COLUMN linked_pipeline_count INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE materials ADD COLUMN pending_alert_count INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 11) {
          await db.execute(
            'ALTER TABLE materials ADD COLUMN linked_variation_leaf_node_id INTEGER',
          );
        }
        if (oldVersion < 12) {
          await db.execute(
            'ALTER TABLE material_group_properties ADD COLUMN unit_id INTEGER',
          );
          await db.execute(
            'ALTER TABLE material_group_properties ADD COLUMN unit_symbol TEXT',
          );
          await db.execute(
            'ALTER TABLE material_group_properties ADD COLUMN unit_label TEXT',
          );
          await db.execute(
            'ALTER TABLE material_group_properties ADD COLUMN source_group_id INTEGER',
          );
          await db.execute(
            'ALTER TABLE material_group_properties ADD COLUMN source_group_name TEXT',
          );
          await db.execute(
            'ALTER TABLE material_group_preferences ADD COLUMN discarded_property_keys_json TEXT NOT NULL DEFAULT \'[]\'',
          );
        }
        if (oldVersion < 13) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS inventory_sets (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS inventory_set_lines (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              set_id INTEGER NOT NULL,
              item_id INTEGER NOT NULL,
              variation_leaf_node_id INTEGER DEFAULT 0,
              quantity INTEGER NOT NULL DEFAULT 1,
              position INTEGER NOT NULL DEFAULT 0,
              item_name TEXT DEFAULT '',
              item_display_name TEXT DEFAULT '',
              variation_path_label TEXT DEFAULT '',
              variation_path_node_ids_json TEXT NOT NULL DEFAULT '[]',
              UNIQUE(set_id, item_id, variation_leaf_node_id)
            )
          ''');
        }
        if (oldVersion < 14) {
          await _migrateInventorySetLinesTable(db);
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

    final chemicals = await saveParentWithChildren(
      const CreateParentMaterialInput(
        name: 'Chemicals',
        type: 'Raw Material',
        grade: 'Industrial',
        thickness: 'Mixed',
        supplier: 'Central Chemical Supply',
        unitId: null,
        unit: 'Kg',
        numberOfChildren: 0,
      ),
    );
    final adhesives = await saveParentWithChildren(
      const CreateParentMaterialInput(
        name: 'Adhesives',
        type: 'Raw Material',
        grade: 'Reactive',
        thickness: 'Mixed',
        supplier: 'BondChem Industries',
        unitId: null,
        unit: 'Kg',
        numberOfChildren: 2,
      ),
    );
    final solvents = await saveParentWithChildren(
      const CreateParentMaterialInput(
        name: 'Solvents',
        type: 'Raw Material',
        grade: 'Purified',
        thickness: 'Mixed',
        supplier: 'PureChem Logistics',
        unitId: null,
        unit: 'Litre',
        numberOfChildren: 1,
      ),
    );
    final inks = await saveParentWithChildren(
      const CreateParentMaterialInput(
        name: 'Inks',
        type: 'Raw Material',
        grade: 'Flexo',
        thickness: 'Mixed',
        supplier: 'ColorBond Inks',
        unitId: null,
        unit: 'Kg',
        numberOfChildren: 1,
      ),
    );

    await linkMaterialToGroup(chemicals.parentBarcode, 1);

    await linkMaterialToGroup(adhesives.parentBarcode, 2);
    if (adhesives.childBarcodes.isNotEmpty) {
      await linkMaterialToItem(adhesives.childBarcodes[0], 1);
    }
    if (adhesives.childBarcodes.length > 1) {
      await linkMaterialToItem(adhesives.childBarcodes[1], 2);
    }

    await linkMaterialToGroup(solvents.parentBarcode, 3);
    if (solvents.childBarcodes.isNotEmpty) {
      await linkMaterialToItem(solvents.childBarcodes[0], 3);
    }

    await linkMaterialToGroup(inks.parentBarcode, 4);
    if (inks.childBarcodes.isNotEmpty) {
      await linkMaterialToItem(inks.childBarcodes[0], 4);
    }
  }

  @override
  Future<SaveParentResult> saveParentWithChildren(
    CreateParentMaterialInput input,
  ) async {
    final db = await _db;
    final parentBarcode = _generateParentBarcode();
    Map<String, Object?>? parentGroupMaterialRow;
    if (input.parentGroupId != null) {
      final parentRows = await db.query(
        'materials',
        where: 'linked_group_id = ?',
        whereArgs: [input.parentGroupId],
        limit: 1,
      );
      parentGroupMaterialRow = parentRows.isEmpty ? null : parentRows.first;
    }
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
        location: input.location,
        unitId: input.unitId,
        unit: input.unit,
        notes: input.notes,
        groupMode: input.groupMode,
        inheritanceEnabled: input.inheritanceEnabled,
        createdAt: now,
        kind: 'parent',
        parentBarcode: (parentGroupMaterialRow?['barcode'] as String?)?.trim(),
        numberOfChildren: input.numberOfChildren,
        linkedChildBarcodes: childBarcodes,
        scanCount: 0,
        linkedGroupId: null,
        linkedItemId: null,
        displayStock: input.unit.trim().isEmpty
            ? '0'
            : '0 ${input.unit.trim()}',
        createdBy: 'Demo Admin',
        workflowStatus: 'inProgress',
        updatedAt: now,
        lastScannedAt: null,
      );
      final parentId = await txn.insert(
        'materials',
        parentModel.toMap()..remove('id'),
      );
      await _persistGroupGovernance(
        txn,
        materialId: parentId,
        selectedItemIds: input.selectedItemIds,
        propertyDrafts: input.propertyDrafts,
        unitGovernance: input.unitGovernance,
        uiPreferences: input.uiPreferences,
        discardedPropertyKeys: input.discardedPropertyKeys,
        createdAt: now,
      );
      await _recordActivity(
        txn,
        barcode: parentBarcode,
        type: 'created',
        label: 'Group created',
        description: 'Inventory group ${input.name} was created.',
        actor: parentModel.createdBy,
        createdAt: now,
      );

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
          location: input.location,
          unitId: input.unitId,
          unit: input.unit,
          notes: input.notes,
          groupMode: input.groupMode,
          inheritanceEnabled: input.inheritanceEnabled,
          createdAt: now,
          kind: 'child',
          parentBarcode: parentBarcode,
          numberOfChildren: 0,
          linkedChildBarcodes: const [],
          scanCount: 0,
          linkedGroupId: null,
          linkedItemId: null,
          displayStock: input.unit.trim().isEmpty
              ? '0'
              : '0 ${input.unit.trim()}',
          createdBy: 'Demo Admin',
          workflowStatus: 'notStarted',
          updatedAt: now,
          lastScannedAt: null,
        );
        await txn.insert('materials', childModel.toMap()..remove('id'));
        await _recordActivity(
          txn,
          barcode: childBarcodes[i],
          type: 'created',
          label: 'Item created',
          description: 'Inventory item ${childModel.name} was created.',
          actor: childModel.createdBy,
          createdAt: now,
        );
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
    final now = DateTime.now();
    await transaction.rawUpdate(
      'UPDATE materials SET scan_count = scan_count + 1, updated_at = ?, last_scanned_at = ? WHERE barcode = ?',
      [now.toIso8601String(), now.toIso8601String(), model.barcode],
    );

    await transaction.insert(
      'scan_history',
      ScanEventModel(barcode: model.barcode, scannedAt: DateTime.now()).toMap()
        ..remove('id'),
    );
    await _recordActivity(
      transaction,
      barcode: model.barcode,
      type: 'scan',
      label: 'Material scanned',
      description: 'Scan trace updated to ${model.scanCount + 1} total scans.',
      actor: 'Scanner',
      createdAt: now,
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
        {
          'scan_count': 0,
          'updated_at': DateTime.now().toIso8601String(),
          'last_scanned_at': null,
        },
        where: 'barcode = ?',
        whereArgs: [barcode],
      );
      await txn.delete(
        'scan_history',
        where: 'barcode = ?',
        whereArgs: [barcode],
      );
      await _recordActivity(
        txn,
        barcode: barcode,
        type: 'scanReset',
        label: 'Trace reset',
        description: 'Scan history was cleared for this material.',
        actor: 'Demo Admin',
        createdAt: DateTime.now(),
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

  @override
  Future<MaterialRecord> createChildMaterial(
    CreateChildMaterialInput input,
  ) async {
    final db = await _db;
    return db.transaction((txn) async {
      final parent = await _getMaterialMapByBarcode(input.parentBarcode, txn);
      if (parent == null) {
        throw Exception('Parent material not found.');
      }
      final parentModel = InventoryMaterialModel.fromMap(parent);
      final childIndex = parentModel.numberOfChildren + 1;
      final childBarcode = _generateChildBarcode(
        parentModel.barcode,
        childIndex,
      );
      final childModel = InventoryMaterialModel(
        id: null,
        barcode: childBarcode,
        name: input.name.trim(),
        type: parentModel.type,
        grade: parentModel.grade,
        thickness: parentModel.thickness,
        supplier: parentModel.supplier,
        location: parentModel.location,
        unitId: parentModel.unitId,
        unit: parentModel.unit,
        notes: input.notes,
        groupMode: parentModel.groupMode,
        inheritanceEnabled: parentModel.inheritanceEnabled,
        createdAt: DateTime.now(),
        kind: 'child',
        parentBarcode: parentModel.barcode,
        numberOfChildren: 0,
        linkedChildBarcodes: const [],
        scanCount: 0,
        linkedGroupId: null,
        linkedItemId: null,
        displayStock: parentModel.displayStock,
        createdBy: parentModel.createdBy,
        workflowStatus: 'notStarted',
        updatedAt: DateTime.now(),
        lastScannedAt: null,
      );
      final nextChildren = [...parentModel.linkedChildBarcodes, childBarcode];
      await txn.insert('materials', childModel.toMap()..remove('id'));
      await _recordActivity(
        txn,
        barcode: childBarcode,
        type: 'created',
        label: 'Sub-group created',
        description: 'Created under parent ${parentModel.name}.',
        actor: childModel.createdBy,
        createdAt: childModel.updatedAt,
      );
      await txn.update(
        'materials',
        {
          'number_of_children': nextChildren.length,
          'linked_child_barcodes': jsonEncode(nextChildren),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'barcode = ?',
        whereArgs: [parentModel.barcode],
      );
      final created = await _getMaterialMapByBarcode(childBarcode, txn);
      return InventoryMaterialModel.fromMap(created!).toRecord();
    });
  }

  @override
  Future<MaterialRecord> updateMaterial(UpdateMaterialInput input) async {
    final db = await _db;
    return db.transaction((txn) async {
      final existing = await _getMaterialMapByBarcode(input.barcode, txn);
      if (existing == null) {
        throw Exception('Material not found.');
      }
      await txn.update(
        'materials',
        {
          'name': input.name.trim(),
          'type': input.type.trim(),
          'grade': input.grade.trim(),
          'thickness': input.thickness.trim(),
          'supplier': input.supplier.trim(),
          'location': input.location.trim(),
          'unit_id': input.unitId,
          'unit': input.unit.trim(),
          'notes': input.notes.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'barcode = ?',
        whereArgs: [input.barcode],
      );
      await _recordActivity(
        txn,
        barcode: input.barcode,
        type: 'updated',
        label: 'Record updated',
        description: 'Material details were edited.',
        actor: 'Demo Admin',
        createdAt: DateTime.now(),
      );
      final updated = await _getMaterialMapByBarcode(input.barcode, txn);
      return InventoryMaterialModel.fromMap(updated!).toRecord();
    });
  }

  @override
  Future<void> deleteMaterial(String barcode) async {
    final db = await _db;
    await db.transaction((txn) async {
      final existing = await _getMaterialMapByBarcode(barcode, txn);
      if (existing == null) {
        throw Exception('Material not found.');
      }
      final model = InventoryMaterialModel.fromMap(existing);
      if (model.kind == 'parent') {
        final childRows = await txn.query(
          'materials',
          columns: ['barcode'],
          where: 'parent_barcode = ?',
          whereArgs: [model.barcode],
        );
        for (final child in childRows) {
          await txn.delete(
            'material_activity',
            where: 'barcode = ?',
            whereArgs: [child['barcode']],
          );
        }
        await txn.delete(
          'materials',
          where: 'parent_barcode = ?',
          whereArgs: [model.barcode],
        );
      } else if (model.parentBarcode != null) {
        final parent = await _getMaterialMapByBarcode(
          model.parentBarcode!,
          txn,
        );
        if (parent != null) {
          final parentModel = InventoryMaterialModel.fromMap(parent);
          final nextChildren = parentModel.linkedChildBarcodes
              .where((childBarcode) => childBarcode != model.barcode)
              .toList(growable: false);
          await txn.update(
            'materials',
            {
              'number_of_children': nextChildren.length,
              'linked_child_barcodes': jsonEncode(nextChildren),
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'barcode = ?',
            whereArgs: [parentModel.barcode],
          );
        }
      }
      await txn.delete(
        'scan_history',
        where: 'barcode = ?',
        whereArgs: [model.barcode],
      );
      await txn.delete(
        'material_activity',
        where: 'barcode = ?',
        whereArgs: [model.barcode],
      );
      if (model.id != null) {
        await txn.delete(
          'material_group_item_links',
          where: 'material_id = ?',
          whereArgs: [model.id],
        );
        await txn.delete(
          'material_group_properties',
          where: 'material_id = ?',
          whereArgs: [model.id],
        );
        await txn.delete(
          'material_group_units',
          where: 'material_id = ?',
          whereArgs: [model.id],
        );
        await txn.delete(
          'material_group_preferences',
          where: 'material_id = ?',
          whereArgs: [model.id],
        );
      }
      await txn.delete(
        'materials',
        where: 'barcode = ?',
        whereArgs: [model.barcode],
      );
    });
  }

  @override
  Future<MaterialRecord> linkMaterialToGroup(
    String barcode,
    int groupId,
  ) async {
    return _updateLink(
      barcode,
      linkedGroupId: groupId,
      linkedItemId: null,
      linkedVariationLeafNodeId: null,
    );
  }

  @override
  Future<MaterialRecord> linkMaterialToItem(
    String barcode,
    int itemId, {
    int? variationLeafNodeId,
  }) async {
    return _updateLink(
      barcode,
      linkedGroupId: null,
      linkedItemId: itemId,
      linkedVariationLeafNodeId: variationLeafNodeId,
    );
  }

  @override
  Future<MaterialRecord> unlinkMaterial(String barcode) async {
    return _updateLink(
      barcode,
      linkedGroupId: null,
      linkedItemId: null,
      linkedVariationLeafNodeId: null,
    );
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

  Future<Map<String, Object?>?> _getMaterialMapByBarcode(
    String barcode,
    DatabaseExecutor executor,
  ) async {
    final rows = await executor.query(
      'materials',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<MaterialRecord> _updateLink(
    String barcode, {
    required int? linkedGroupId,
    required int? linkedItemId,
    required int? linkedVariationLeafNodeId,
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      final existing = await _getMaterialMapByBarcode(barcode, txn);
      if (existing == null) {
        throw Exception('Material not found.');
      }
      await txn.update(
        'materials',
        {
          'linked_group_id': linkedGroupId,
          'linked_item_id': linkedItemId,
          'linked_variation_leaf_node_id': linkedVariationLeafNodeId,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'barcode = ?',
        whereArgs: [barcode],
      );
      await _recordActivity(
        txn,
        barcode: barcode,
        type: linkedItemId != null || linkedGroupId != null
            ? 'linked'
            : 'unlinked',
        label: linkedItemId != null || linkedGroupId != null
            ? 'Inheritance linked'
            : 'Inheritance removed',
        description: linkedItemId != null
            ? 'Linked to an item definition.'
            : linkedGroupId != null
            ? 'Linked to a group definition.'
            : 'Removed inheritance link.',
        actor: 'Demo Admin',
        createdAt: DateTime.now(),
      );
      final updated = await _getMaterialMapByBarcode(barcode, txn);
      return InventoryMaterialModel.fromMap(updated!).toRecord();
    });
  }

  @override
  Future<List<MaterialActivityEvent>> getMaterialActivity(
    String barcode,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'material_activity',
      where: 'barcode = ?',
      whereArgs: [barcode],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows
        .map((row) => MaterialActivityEventModel.fromMap(row).toEvent())
        .toList(growable: false);
  }

  @override
  Future<InventoryHealthSnapshot> getInventoryHealth() async {
    final materials = await getAllMaterials();
    final lowStockCount = materials
        .where((item) => item.availableToPromise <= 100 && item.onHand > 0)
        .length;
    final reservedRiskCount = materials
        .where((item) => item.reserved > item.onHand && item.reserved > 0)
        .length;
    final incomingTodayCount = materials
        .where((item) => item.incoming > 0)
        .length;
    final qualityHoldCount = materials
        .where((item) => item.inventoryState == InventoryState.qualityHold)
        .length;
    final pendingReconciliationCount = materials
        .where((item) => item.pendingAlertCount > 0)
        .length;
    return InventoryHealthSnapshot(
      lowStockCount: lowStockCount,
      reservedRiskCount: reservedRiskCount,
      incomingTodayCount: incomingTodayCount,
      qualityHoldCount: qualityHoldCount,
      unitMismatchCount: pendingReconciliationCount,
      pendingReconciliationCount: pendingReconciliationCount,
    );
  }

  @override
  Future<MaterialControlTowerDetail?> getMaterialControlTowerDetail(
    String barcode,
  ) async {
    final material = await getMaterialByBarcode(barcode);
    if (material == null) {
      return null;
    }
    final stockPositions = <StockPosition>[
      StockPosition(
        locationId: material.location.trim().isEmpty
            ? 'MAIN'
            : material.location.trim(),
        locationName: material.location.trim().isEmpty
            ? 'Main Warehouse'
            : material.location.trim(),
        lotCode: material.barcode,
        unitId: material.unitId,
        onHandQty: material.onHand,
        reservedQty: material.reserved,
        damagedQty: 0,
        updatedAt: material.updatedAt,
      ),
    ];
    final activity = await getMaterialActivity(barcode);
    final movements = activity
        .map(
          (event) => InventoryMovement(
            id: '${event.id ?? 0}',
            materialBarcode: event.barcode,
            movementType: InventoryMovementType.adjust,
            qty: 0,
            primaryQty: 0,
            uom: material.unit,
            fromLocationId: null,
            toLocationId: material.location,
            reasonCode: event.type,
            referenceType: null,
            referenceId: null,
            sourceChallanId: null,
            sourceChallanType: null,
            sourceChallanLineId: null,
            sourceLabel: null,
            actor: event.actor,
            createdAt: event.createdAt,
          ),
        )
        .toList(growable: false);
    return MaterialControlTowerDetail(
      material: material,
      stockPositions: stockPositions,
      movements: movements,
      reservations: const [],
      alerts: const [],
      linkedOrderDemand: material.linkedOrderCount.toDouble(),
      linkedPipelineDemand: material.linkedPipelineCount.toDouble(),
      pendingAlertsCount: material.pendingAlertCount,
    );
  }

  @override
  Future<MaterialControlTowerDetail> createInventoryMovement(
    CreateInventoryMovementInput input,
  ) async {
    final material = await getMaterialByBarcode(input.materialBarcode);
    if (material == null) {
      throw Exception('Material not found.');
    }
    final now = DateTime.now();
    final nextOnHand = switch (input.movementType) {
      InventoryMovementType.receive => material.onHand + input.qty,
      InventoryMovementType.issue => material.onHand - input.qty,
      InventoryMovementType.consume => material.onHand - input.qty,
      InventoryMovementType.adjust => material.onHand + input.qty,
      _ => material.onHand,
    };
    final nextReserved = switch (input.movementType) {
      InventoryMovementType.reserve => material.reserved + input.qty,
      InventoryMovementType.release => max(0, material.reserved - input.qty),
      _ => material.reserved,
    };
    final db = await _db;
    await db.update(
      'materials',
      {
        'on_hand_qty': nextOnHand,
        'reserved_qty': nextReserved,
        'available_to_promise_qty': nextOnHand - nextReserved,
        'updated_at': now.toIso8601String(),
      },
      where: 'barcode = ?',
      whereArgs: [material.barcode],
    );
    await _recordActivity(
      db,
      barcode: material.barcode,
      type: input.movementType.name,
      label: 'Inventory movement posted',
      description:
          '${input.movementType.name} ${input.qty.toStringAsFixed(2)} ${material.unit}',
      actor: input.actor ?? 'Demo Admin',
      createdAt: now,
    );
    final detail = await getMaterialControlTowerDetail(input.materialBarcode);
    if (detail == null) {
      throw Exception('Failed to load material detail.');
    }
    return detail;
  }

  @override
  Future<MaterialGroupConfiguration> getGroupConfiguration(
    String barcode,
  ) async {
    final db = await _db;
    final material = await _getMaterialMapByBarcode(barcode, db);
    if (material == null) {
      throw Exception('Material not found.');
    }
    final materialId = (material['id'] as num?)?.toInt();
    if (materialId == null) {
      return const MaterialGroupConfiguration();
    }
    return _readGroupGovernance(
      db,
      materialId: materialId,
      inheritanceEnabled: (material['inheritance_enabled'] as int? ?? 0) == 1,
    );
  }

  @override
  Future<EffectiveGroupSchema> getEffectiveSchema(int groupId) async {
    final db = await _db;
    final rows = await db.query(
      'materials',
      where: 'linked_group_id = ?',
      whereArgs: [groupId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return EffectiveGroupSchema(groupId: groupId);
    }

    // BUG: The local repository does not have access to the master 'groups' table.
    // Previously, this code walked the inventory 'parent_barcode' chain, but that
    // represents physical inventory nesting, not the logical group hierarchy (a group
    // can have a parentGroupId without a physical parent inventory material).
    // TODO: Once a shared Groups SQLite DB is available, walk 'parent_group_id' here.
    // For now, in offline mode, we only return the current group's configuration.
    final materialRow = rows.first;
    final materialId = (materialRow['id'] as num?)?.toInt();
    if (materialId == null) {
      return EffectiveGroupSchema(groupId: groupId);
    }

    final config = await _readGroupGovernance(
      db,
      materialId: materialId,
      inheritanceEnabled:
          (materialRow['inheritance_enabled'] as int? ?? 0) == 1,
    );

    final effectiveByKey = <String, GroupPropertyDraft>{};
    final discarded = <String>{};

    for (final key in config.discardedPropertyKeys) {
      final normalized = key.trim().toLowerCase();
      if (normalized.isEmpty) {
        continue;
      }
      discarded.add(normalized);
    }
    for (final draft in config.propertyDrafts) {
      final key = (draft.propertyKey ?? draft.name).trim().toLowerCase();
      if (key.isEmpty || discarded.contains(key)) {
        continue;
      }
      effectiveByKey[key] = draft;
    }

    final groupName = (materialRow['name'] as String? ?? '').trim();

    return EffectiveGroupSchema(
      groupId: groupId,
      propertyDrafts: effectiveByKey.values.toList(growable: false),
      discardedPropertyKeys: discarded.toList(growable: false),
      lineageGroupIds: [groupId],
      lineageGroupNames: groupName.isNotEmpty ? [groupName] : const [],
    );
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
    final db = await _db;
    return db.transaction((txn) async {
      final material = await _getMaterialMapByBarcode(barcode, txn);
      if (material == null) {
        throw Exception('Material not found.');
      }
      final materialId = (material['id'] as num?)?.toInt();
      if (materialId == null) {
        throw Exception('Material id missing.');
      }
      final now = DateTime.now();
      await txn.update(
        'materials',
        {
          'inheritance_enabled': inheritanceEnabled ? 1 : 0,
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [materialId],
      );
      await _persistGroupGovernance(
        txn,
        materialId: materialId,
        selectedItemIds: selectedItemIds,
        propertyDrafts: propertyDrafts,
        unitGovernance: unitGovernance,
        uiPreferences: uiPreferences,
        discardedPropertyKeys: discardedPropertyKeys,
        createdAt: now,
      );
      await _recordActivity(
        txn,
        barcode: barcode,
        type: 'updated',
        label: 'Group configuration updated',
        description: 'Inheritance governance settings were updated.',
        actor: 'Demo Admin',
        createdAt: now,
      );
      return _readGroupGovernance(
        txn,
        materialId: materialId,
        inheritanceEnabled: inheritanceEnabled,
      );
    });
  }

  @override
  Future<List<InventorySetDefinition>> getSets() async {
    final db = await _db;
    final setRows = await db.query(
      'inventory_sets',
      orderBy: 'created_at DESC, id DESC',
    );
    return Future.wait(
      setRows.map((row) async => _mapInventorySetDefinition(db, row)),
    );
  }

  @override
  Future<InventorySetDefinition> saveSet(SaveInventorySetInput input) async {
    final db = await _db;
    return db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final mergedLines = _mergeInventorySetLines(input.lines);
      int setId;
      String createdAt = now;
      if (input.id == null) {
        setId = await txn.insert('inventory_sets', {
          'name': input.name.trim(),
          'created_at': now,
          'updated_at': now,
        });
      } else {
        setId = input.id!;
        final existing = await txn.query(
          'inventory_sets',
          where: 'id = ?',
          whereArgs: [setId],
          limit: 1,
        );
        if (existing.isEmpty) {
          throw Exception('Set not found.');
        }
        createdAt = existing.first['created_at'] as String? ?? now;
        await txn.update(
          'inventory_sets',
          {'name': input.name.trim(), 'updated_at': now},
          where: 'id = ?',
          whereArgs: [setId],
        );
        await txn.delete(
          'inventory_set_lines',
          where: 'set_id = ?',
          whereArgs: [setId],
        );
      }

      for (final line in mergedLines) {
        await txn.insert('inventory_set_lines', {
          'set_id': setId,
          'item_id': line.itemId,
          'variation_leaf_node_id': line.variationLeafNodeId <= 0
              ? 0
              : line.variationLeafNodeId,
          'quantity': line.quantity,
          'position': line.position,
          'item_name': line.itemName,
          'item_display_name': line.itemDisplayName,
          'variation_path_label': line.variationPathLabel,
          'variation_path_node_ids_json': jsonEncode(line.variationPathNodeIds),
        });
      }
      final row = {
        'id': setId,
        'name': input.name.trim(),
        'created_at': createdAt,
        'updated_at': now,
      };
      return _mapInventorySetDefinition(txn, row);
    });
  }

  @override
  Future<void> deleteSet(int setId) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        'inventory_set_lines',
        where: 'set_id = ?',
        whereArgs: [setId],
      );
      await txn.delete('inventory_sets', where: 'id = ?', whereArgs: [setId]);
    });
  }

  List<SaveInventorySetLineInput> _mergeInventorySetLines(
    List<SaveInventorySetLineInput> lines,
  ) {
    final merged = <String, SaveInventorySetLineInput>{};
    for (final line in lines) {
      final key = '${line.itemId}:${line.variationLeafNodeId}';
      final existing = merged[key];
      merged[key] = SaveInventorySetLineInput(
        itemId: line.itemId,
        variationLeafNodeId: line.variationLeafNodeId,
        quantity: (existing?.quantity ?? 0) + line.quantity,
        position: existing?.position ?? line.position,
        itemName: existing?.itemName ?? line.itemName,
        itemDisplayName: existing?.itemDisplayName ?? line.itemDisplayName,
        variationPathLabel:
            existing?.variationPathLabel ?? line.variationPathLabel,
        variationPathNodeIds:
            existing?.variationPathNodeIds ?? line.variationPathNodeIds,
      );
    }
    return merged.values.toList(growable: false)
      ..sort((a, b) => a.position.compareTo(b.position));
  }

  Future<InventorySetDefinition> _mapInventorySetDefinition(
    DatabaseExecutor executor,
    Map<String, Object?> row,
  ) async {
    final setId = (row['id'] as num?)?.toInt() ?? 0;
    final lines = await executor.rawQuery(
      '''
      SELECT
        lines.id,
        lines.item_id,
        lines.variation_leaf_node_id,
        lines.quantity,
        lines.position,
        lines.item_name,
        lines.item_display_name,
        lines.variation_path_label,
        lines.variation_path_node_ids_json
      FROM inventory_set_lines lines
      WHERE lines.set_id = ?
      ORDER BY lines.position ASC, lines.id ASC
      ''',
      [setId],
    );

    return InventorySetDefinition(
      id: setId,
      name: row['name'] as String? ?? '',
      totalItemCount: lines.fold<int>(
        0,
        (sum, line) => sum + ((line['quantity'] as num?)?.toInt() ?? 0),
      ),
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(row['updated_at'] as String? ?? '') ??
          DateTime.now(),
      lines: lines
          .map(
            (line) => InventorySetLineDefinition(
              id: (line['id'] as num?)?.toInt(),
              itemId: (line['item_id'] as num?)?.toInt() ?? 0,
              variationLeafNodeId:
                  (line['variation_leaf_node_id'] as num?)?.toInt() ?? 0,
              quantity: (line['quantity'] as num?)?.toInt() ?? 0,
              position: (line['position'] as num?)?.toInt() ?? 0,
              itemName: line['item_name'] as String? ?? '',
              itemDisplayName: line['item_display_name'] as String? ?? '',
              variationPathLabel:
                  (line['variation_path_label'] as String?)?.trim().isEmpty ??
                      true
                  ? (((line['variation_leaf_node_id'] as num?)?.toInt() ?? 0) ==
                            0
                        ? 'Base item'
                        : '')
                  : (line['variation_path_label'] as String? ?? ''),
              variationPathNodeIds: _decodeIntList(
                line['variation_path_node_ids_json'] as String?,
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  static Future<void> _migrateInventorySetLinesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_set_lines_next (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        set_id INTEGER NOT NULL,
        item_id INTEGER NOT NULL,
        variation_leaf_node_id INTEGER DEFAULT 0,
        quantity INTEGER NOT NULL DEFAULT 1,
        position INTEGER NOT NULL DEFAULT 0,
        item_name TEXT DEFAULT '',
        item_display_name TEXT DEFAULT '',
        variation_path_label TEXT DEFAULT '',
        variation_path_node_ids_json TEXT NOT NULL DEFAULT '[]',
        UNIQUE(set_id, item_id, variation_leaf_node_id)
      )
    ''');
    await db.execute('''
      INSERT INTO inventory_set_lines_next (
        id,
        set_id,
        item_id,
        variation_leaf_node_id,
        quantity,
        position,
        item_name,
        item_display_name,
        variation_path_label,
        variation_path_node_ids_json
      )
      SELECT
        id,
        set_id,
        item_id,
        COALESCE(variation_leaf_node_id, 0),
        quantity,
        position,
        '',
        '',
        CASE
          WHEN COALESCE(variation_leaf_node_id, 0) = 0 THEN 'Base item'
          ELSE ''
        END,
        '[]'
      FROM inventory_set_lines
    ''');
    await db.execute('DROP TABLE inventory_set_lines');
    await db.execute(
      'ALTER TABLE inventory_set_lines_next RENAME TO inventory_set_lines',
    );
  }

  static List<int> _decodeIntList(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) {
      return const <int>[];
    }
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) {
        return const <int>[];
      }
      return decoded
          .map((value) => value is num ? value.toInt() : int.tryParse('$value'))
          .whereType<int>()
          .toList(growable: false);
    } catch (_) {
      return const <int>[];
    }
  }

  Future<void> _persistGroupGovernance(
    DatabaseExecutor executor, {
    required int materialId,
    required List<int> selectedItemIds,
    required List<GroupPropertyDraft> propertyDrafts,
    required List<GroupUnitGovernance> unitGovernance,
    required GroupUiPreferences uiPreferences,
    required List<String> discardedPropertyKeys,
    required DateTime createdAt,
  }) async {
    final nowIso = createdAt.toIso8601String();
    await executor.delete(
      'material_group_item_links',
      where: 'material_id = ?',
      whereArgs: [materialId],
    );
    await executor.delete(
      'material_group_properties',
      where: 'material_id = ?',
      whereArgs: [materialId],
    );
    await executor.delete(
      'material_group_units',
      where: 'material_id = ?',
      whereArgs: [materialId],
    );
    await executor.delete(
      'material_group_preferences',
      where: 'material_id = ?',
      whereArgs: [materialId],
    );

    for (var i = 0; i < selectedItemIds.length; i++) {
      await executor.insert('material_group_item_links', {
        'material_id': materialId,
        'item_id': selectedItemIds[i],
        'sort_order': i,
        'created_at': nowIso,
        'updated_at': nowIso,
      });
    }

    for (final unitRow in unitGovernance) {
      if (unitRow.unitId <= 0) {
        continue;
      }
      await executor.insert('material_group_units', {
        'material_id': materialId,
        'unit_id': unitRow.unitId,
        'state': unitRow.state == GroupUnitState.detached
            ? 'detached'
            : 'active',
        'is_primary': unitRow.isPrimary ? 1 : 0,
        'created_at': nowIso,
        'updated_at': nowIso,
      });
    }

    await executor.insert('material_group_preferences', {
      'material_id': materialId,
      'common_only_mode': uiPreferences.commonOnlyMode ? 1 : 0,
      'show_partial_matches': uiPreferences.showPartialMatches ? 1 : 0,
      'discarded_property_keys_json': jsonEncode(
        discardedPropertyKeys
            .map((value) => value.trim().toLowerCase())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(growable: false),
      ),
      'created_at': nowIso,
      'updated_at': nowIso,
    });

    final seenKeys = <String>{};
    for (final property in propertyDrafts) {
      final key = (property.propertyKey ?? property.name).trim().toLowerCase();
      if (key.isEmpty || seenKeys.contains(key)) {
        continue;
      }
      seenKeys.add(key);

      final sourceItemIds = property.sources
          .map((source) => source.itemId)
          .toSet()
          .toList(growable: false);

      await executor.insert('material_group_properties', {
        'material_id': materialId,
        'property_key': key,
        'display_name': property.name.trim(),
        'input_type': property.inputType.trim().isEmpty
            ? 'Text'
            : property.inputType.trim(),
        'mandatory': property.mandatory ? 1 : 0,
        'unit_id': property.unitId,
        'unit_symbol': property.unitSymbol,
        'unit_label': property.unitLabel,
        'source_type': switch (property.sourceType) {
          GroupPropertySourceType.inheritedItem => 'inherited_item',
          GroupPropertySourceType.inheritedGroup => 'inherited_group',
          GroupPropertySourceType.manual => 'manual',
        },
        'source_item_ids_json': jsonEncode(sourceItemIds),
        'source_group_id': property.sourceGroupId,
        'source_group_name': property.sourceGroupName,
        'state': switch (property.state) {
          GroupPropertyState.active => 'active',
          GroupPropertyState.unlinked => 'unlinked',
          GroupPropertyState.overridden => 'overridden',
        },
        'override_locked': property.overrideLocked ? 1 : 0,
        'has_type_conflict': property.hasTypeConflict ? 1 : 0,
        'coverage_count': property.coverageCount,
        'selected_item_count_at_resolution':
            property.selectedItemCountAtResolution,
        'resolution_source': property.resolutionSource,
        'created_at': nowIso,
        'updated_at': nowIso,
      });
    }
  }

  Future<MaterialGroupConfiguration> _readGroupGovernance(
    DatabaseExecutor executor, {
    required int materialId,
    required bool inheritanceEnabled,
  }) async {
    final linkRows = await executor.query(
      'material_group_item_links',
      columns: ['item_id'],
      where: 'material_id = ?',
      whereArgs: [materialId],
      orderBy: 'sort_order ASC, id ASC',
    );
    final propertyRows = await executor.query(
      'material_group_properties',
      where: 'material_id = ?',
      whereArgs: [materialId],
      orderBy: 'id ASC',
    );
    final unitRows = await executor.query(
      'material_group_units',
      where: 'material_id = ?',
      whereArgs: [materialId],
      orderBy: 'is_primary DESC, id ASC',
    );
    final preferenceRows = await executor.query(
      'material_group_preferences',
      where: 'material_id = ?',
      whereArgs: [materialId],
      limit: 1,
    );
    final preference = preferenceRows.isEmpty ? null : preferenceRows.first;

    return MaterialGroupConfiguration(
      inheritanceEnabled: inheritanceEnabled,
      selectedItemIds: linkRows
          .map((row) => (row['item_id'] as num?)?.toInt())
          .whereType<int>()
          .toList(growable: false),
      propertyDrafts: propertyRows
          .map((row) {
            final sourceIds = _decodeSourceItemIds(row['source_item_ids_json']);
            final sourceTypeWire = (row['source_type'] as String? ?? 'manual')
                .trim()
                .toLowerCase();
            final stateWire = (row['state'] as String? ?? 'active')
                .trim()
                .toLowerCase();
            return GroupPropertyDraft(
              name: (row['display_name'] as String? ?? '').trim(),
              inputType: (row['input_type'] as String? ?? 'Text').trim(),
              mandatory: (row['mandatory'] as int? ?? 0) == 1,
              propertyKey: (row['property_key'] as String? ?? '').trim(),
              unitId: (row['unit_id'] as num?)?.toInt(),
              unitSymbol: (row['unit_symbol'] as String?)?.trim(),
              unitLabel: (row['unit_label'] as String?)?.trim(),
              sourceType: switch (sourceTypeWire) {
                'inherited_item' => GroupPropertySourceType.inheritedItem,
                'inherited_group' => GroupPropertySourceType.inheritedGroup,
                _ => GroupPropertySourceType.manual,
              },
              state: switch (stateWire) {
                'unlinked' => GroupPropertyState.unlinked,
                'overridden' => GroupPropertyState.overridden,
                _ => GroupPropertyState.active,
              },
              sources: sourceIds
                  .map((id) => GroupPropertySource(itemId: id))
                  .toList(growable: false),
              sourceGroupId: (row['source_group_id'] as num?)?.toInt(),
              sourceGroupName: (row['source_group_name'] as String?)?.trim(),
              overrideLocked: (row['override_locked'] as int? ?? 0) == 1,
              hasTypeConflict: (row['has_type_conflict'] as int? ?? 0) == 1,
              coverageCount: (row['coverage_count'] as int? ?? 0),
              selectedItemCountAtResolution:
                  (row['selected_item_count_at_resolution'] as int? ?? 0),
              resolutionSource: (row['resolution_source'] as String?)?.trim(),
            );
          })
          .toList(growable: false),
      unitGovernance: unitRows
          .map((row) {
            final stateWire = (row['state'] as String? ?? 'active')
                .trim()
                .toLowerCase();
            return GroupUnitGovernance(
              unitId: (row['unit_id'] as num?)?.toInt() ?? 0,
              state: stateWire == 'detached'
                  ? GroupUnitState.detached
                  : GroupUnitState.active,
              isPrimary: (row['is_primary'] as int? ?? 0) == 1,
            );
          })
          .toList(growable: false),
      uiPreferences: GroupUiPreferences(
        commonOnlyMode: (preference?['common_only_mode'] as int? ?? 1) == 1,
        showPartialMatches:
            (preference?['show_partial_matches'] as int? ?? 1) == 1,
      ),
      discardedPropertyKeys: _decodeStringList(
        preference?['discarded_property_keys_json'],
      ),
    );
  }

  List<int> _decodeSourceItemIds(Object? rawValue) {
    final jsonString = (rawValue as String? ?? '').trim();
    if (jsonString.isEmpty) {
      return const <int>[];
    }
    final decoded = jsonDecode(jsonString);
    if (decoded is! List<dynamic>) {
      return const <int>[];
    }
    return decoded
        .map((value) => (value as num?)?.toInt())
        .whereType<int>()
        .toList(growable: false);
  }

  List<String> _decodeStringList(Object? rawValue) {
    final jsonString = (rawValue as String? ?? '').trim();
    if (jsonString.isEmpty) {
      return const <String>[];
    }
    final decoded = jsonDecode(jsonString);
    if (decoded is! List<dynamic>) {
      return const <String>[];
    }
    return decoded
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _recordActivity(
    DatabaseExecutor executor, {
    required String barcode,
    required String type,
    required String label,
    required String description,
    required String actor,
    required DateTime createdAt,
  }) async {
    await executor.insert(
      'material_activity',
      MaterialActivityEventModel(
        id: null,
        barcode: barcode,
        type: type,
        label: label,
        description: description,
        actor: actor,
        createdAt: createdAt,
      ).toMap()..remove('id'),
    );
  }
}
