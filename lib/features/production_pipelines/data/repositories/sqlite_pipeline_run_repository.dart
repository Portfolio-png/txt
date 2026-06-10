import 'dart:convert';
import 'package:uuid/uuid.dart';

import '../../domain/barcode_input.dart';
import '../../domain/node_run_status.dart';
import '../../domain/pipeline_run.dart';
import '../../domain/pipeline_template.dart';
import '../../domain/run_overrides.dart';
import 'pipeline_run_repository.dart';
import '../../../production/data/datasources/offline_database_helper.dart';
import '../default_pipeline_templates.dart';

class SqlitePipelineRunRepository implements PipelineRunRepository {
  final _dbHelper = OfflineSyncDbHelper.instance;
  final _uuid = const Uuid();

  @override
  Future<List<PipelineTemplate>> getTemplates() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'pipeline_templates',
      orderBy: 'created_at DESC',
    );
    
    final templates = maps.map((m) {
      final data = jsonDecode(m['data'] as String) as Map<String, dynamic>;
      return PipelineTemplate.fromJson(data);
    }).toList();

    if (!templates.any((t) => t.id == sheetMetalPipelineTemplate.id)) {
      await createTemplate(sheetMetalPipelineTemplate);
      templates.insert(0, sheetMetalPipelineTemplate);
    }

    return templates;
  }

  @override
  Future<PipelineTemplate> createTemplate(PipelineTemplate template) async {
    final db = await _dbHelper.database;
    await _ensureTemplateColumns(db);
    final newTemplate = template.copyWith(
      id: template.id.isEmpty ? _uuid.v4() : template.id,
    );
    await db.insert('pipeline_templates', {
      'id': newTemplate.id,
      'shop_floor_id': newTemplate.shopFloorId,
      'name': newTemplate.name,
      'data': jsonEncode(newTemplate.toJson()),
      'created_at': DateTime.now().toIso8601String(),
    });
    return newTemplate;
  }

  @override
  Future<PipelineTemplate> updateTemplate(PipelineTemplate template) async {
    final db = await _dbHelper.database;
    await _ensureTemplateColumns(db);
    await db.update(
      'pipeline_templates',
      {
        'name': template.name,
        'shop_floor_id': template.shopFloorId,
        'data': jsonEncode(template.toJson()),
      },
      where: 'id = ?',
      whereArgs: [template.id],
    );
    return template;
  }

  @override
  Future<void> deleteTemplate(String id) async {
    final db = await _dbHelper.database;
    await db.delete(
      'pipeline_templates',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteRun(String id) async {
    final db = await _dbHelper.database;
    await db.delete(
      'run_barcode_inputs',
      where: 'run_id = ?',
      whereArgs: [id],
    );
    try {
      await db.delete(
        'production_scrap',
        where: 'pipeline_run_id = ?',
        whereArgs: [id],
      );
    } catch (_) {}
    await db.delete(
      'pipeline_runs',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> _ensureTemplateColumns(dynamic db) async {
    final columns = await db.rawQuery('PRAGMA table_info(pipeline_templates)');
    final names = columns
        .map((column) => column['name'] as String? ?? '')
        .toSet();
    if (!names.contains('shop_floor_id')) {
      await db.execute(
        'ALTER TABLE pipeline_templates ADD COLUMN shop_floor_id TEXT',
      );
    }
  }

  @override
  Future<PipelineTemplate?> getTemplate(String id) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'pipeline_templates',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    final data =
        jsonDecode(maps.first['data'] as String) as Map<String, dynamic>;
    return PipelineTemplate.fromJson(data);
  }

  @override
  Future<List<PipelineRun>> getRuns({String? templateId}) async {
    final db = await _dbHelper.database;
    final List<Map<String, Object?>> maps;
    if (templateId != null) {
      maps = await db.query(
        'pipeline_runs',
        where: 'template_id = ?',
        whereArgs: [templateId],
        orderBy: 'start_time DESC',
      );
    } else {
      maps = await db.query('pipeline_runs', orderBy: 'start_time DESC');
    }
    return maps.map((m) {
      final data = jsonDecode(m['data'] as String) as Map<String, dynamic>;
      return PipelineRun.fromJson(data);
    }).toList();
  }

  @override
  Future<PipelineRun> createRun(String templateId, {String? name, String? orderNo, int? orderItemId, String? scrapRouting}) async {
    final db = await _dbHelper.database;
    final template = await getTemplate(templateId);
    if (template == null) {
      throw const PipelineApiException('Template not found');
    }

    final newRun = PipelineRun(
      id: _uuid.v4(),
      templateId: templateId,
      templateVersion: 1,
      name: name ?? '${template.name} Run ${DateTime.now().toIso8601String()}',
      status: 'planned',
      overrides: const RunOverrides(),
      nodeStatuses: {
        for (final node in template.nodes) node.id: NodeRunStatus.pending,
      },
      attachedBarcodeInputs: {},
      createdAt: DateTime.now(),
      startedAt: null,
      completedAt: null,
    );

    await db.insert('pipeline_runs', {
      'id': newRun.id,
      'template_id': newRun.templateId,
      'status': newRun.status,
      'start_time': newRun.startedAt?.toIso8601String(),
      'end_time': newRun.completedAt?.toIso8601String(),
      'good_yield': 0,
      'setup_scrap': 0,
      'parent_reel_consumed': 0.0,
      'data': jsonEncode(newRun.toJson()),
    });
    return newRun;
  }

  @override
  Future<PipelineRun?> getRun(String id) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'pipeline_runs',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    final data =
        jsonDecode(maps.first['data'] as String) as Map<String, dynamic>;
    return PipelineRun.fromJson(data);
  }

  Future<void> saveRun(PipelineRun run) async {
    final db = await _dbHelper.database;
    await db.update(
      'pipeline_runs',
      {
        'status': run.status,
        'start_time': run.startedAt?.toIso8601String(),
        'end_time': run.completedAt?.toIso8601String(),
        'data': jsonEncode(run.toJson()),
      },
      where: 'id = ?',
      whereArgs: [run.id],
    );
  }

  @override
  Future<PipelineRun> updateNodeStatus({
    required String runId,
    required String nodeId,
    required NodeRunStatus status,
    double? actualDurationHours,
    int? batchQuantity,
    String? machineOverride,
  }) async {
    final run = await getRun(runId);
    if (run == null) throw const PipelineApiException('Run not found');

    final updatedStatuses = Map<String, NodeRunStatus>.from(run.nodeStatuses);
    updatedStatuses[nodeId] = status;

    final allCompleted =
        updatedStatuses.isNotEmpty &&
        updatedStatuses.values.every(
          (s) => s == NodeRunStatus.done || s == NodeRunStatus.skipped,
        );

    final updatedOverrides = run.overrides.copyWith(
      actualDurationHoursByNode: actualDurationHours == null
          ? run.overrides.actualDurationHoursByNode
          : <String, double>{
              ...run.overrides.actualDurationHoursByNode,
              nodeId: actualDurationHours,
            },
      batchQuantityByNode: batchQuantity == null
          ? run.overrides.batchQuantityByNode
          : <String, int>{
              ...run.overrides.batchQuantityByNode,
              nodeId: batchQuantity,
            },
      machineOverrideByNode:
          machineOverride == null || machineOverride.trim().isEmpty
          ? run.overrides.machineOverrideByNode
          : <String, String>{
              ...run.overrides.machineOverrideByNode,
              nodeId: machineOverride.trim(),
            },
    );

    final bool anyActiveOrDone = updatedStatuses.values.any(
      (s) =>
          s == NodeRunStatus.active ||
          s == NodeRunStatus.done ||
          s == NodeRunStatus.skipped,
    );
    final String runStatus = allCompleted
        ? 'completed'
        : (anyActiveOrDone ? 'active' : 'planned');
    final DateTime? startedAt =
        run.startedAt ?? (anyActiveOrDone ? DateTime.now() : null);

    final updatedRun = run.copyWith(
      nodeStatuses: updatedStatuses,
      overrides: updatedOverrides,
      status: runStatus,
      startedAt: startedAt,
      completedAt: allCompleted ? (run.completedAt ?? DateTime.now()) : null,
    );

    await saveRun(updatedRun);
    return updatedRun;
  }

  @override
  Future<PipelineRun> attachBarcodeToRunNode({
    required String runId,
    required String nodeId,
    required String barcode,
    double? quantity,
  }) async {
    final run = await getRun(runId);
    if (run == null) throw const PipelineApiException('Run not found');

    final trimmed = barcode.trim();
    if (trimmed.isEmpty) return run;

    final existingList =
        run.attachedBarcodeInputs[nodeId] ?? const <BarcodeInput>[];

    final updatedList = <BarcodeInput>[];
    bool found = false;
    for (final item in existingList) {
      if (item.barcode == trimmed) {
        updatedList.add(
          BarcodeInput(
            barcode: item.barcode,
            materialName: item.materialName,
            materialType: item.materialType,
            scanCount: item.scanCount + 1,
            quantity: quantity ?? item.quantity,
          ),
        );
        found = true;
      } else {
        updatedList.add(item);
      }
    }

    if (!found) {
      updatedList.add(
        BarcodeInput(
          barcode: trimmed,
          materialName: 'Material $trimmed',
          materialType: 'Scanned Input',
          scanCount: 1,
          quantity: quantity,
        ),
      );
    }

    if (quantity != null && quantity > 0) {
      final db = await _dbHelper.database;
      await db.rawUpdate(
        'UPDATE materials SET on_hand_qty = MAX(0.0, on_hand_qty - ?) WHERE barcode = ?',
        [quantity, trimmed],
      );
    }

    final updatedRun = run.copyWith(
      attachedBarcodeInputs: {
        ...run.attachedBarcodeInputs,
        nodeId: updatedList,
      },
    );

    await saveRun(updatedRun);
    return updatedRun;
  }

  @override
  Future<PipelineRun> updateAttachedBarcodeQuantity({
    required String runId,
    required String nodeId,
    required String barcode,
    required double quantity,
  }) async {
    final run = await getRun(runId);
    if (run == null) throw const PipelineApiException('Run not found');

    final trimmed = barcode.trim();
    final existingList =
        run.attachedBarcodeInputs[nodeId] ?? const <BarcodeInput>[];

    final updatedList = <BarcodeInput>[];
    double oldQty = 0;
    bool found = false;
    for (final item in existingList) {
      if (item.barcode == trimmed) {
        oldQty = item.quantity ?? 0;
        updatedList.add(
          BarcodeInput(
            barcode: item.barcode,
            materialName: item.materialName,
            materialType: item.materialType,
            scanCount: item.scanCount,
            quantity: quantity,
            unit: item.unit,
          ),
        );
        found = true;
      } else {
        updatedList.add(item);
      }
    }

    if (!found) throw const PipelineApiException('Barcode assignment not found');

    final qtyDiff = quantity - oldQty;
    if (qtyDiff != 0) {
      final db = await _dbHelper.database;
      if (qtyDiff > 0) {
        await db.rawUpdate(
          'UPDATE materials SET on_hand_qty = MAX(0.0, on_hand_qty - ?) WHERE barcode = ?',
          [qtyDiff, trimmed],
        );
      } else {
        await db.rawUpdate(
          'UPDATE materials SET on_hand_qty = on_hand_qty + ? WHERE barcode = ?',
          [-qtyDiff, trimmed],
        );
      }
    }

    final updatedRun = run.copyWith(
      attachedBarcodeInputs: {
        ...run.attachedBarcodeInputs,
        nodeId: updatedList,
      },
    );

    await saveRun(updatedRun);
    return updatedRun;
  }

  @override
  Future<PipelineRun> detachBarcodeFromRunNode({
    required String runId,
    required String nodeId,
    required String barcode,
  }) async {
    final run = await getRun(runId);
    if (run == null) throw const PipelineApiException('Run not found');

    final trimmed = barcode.trim();
    final existingList =
        run.attachedBarcodeInputs[nodeId] ?? const <BarcodeInput>[];

    final updatedList = <BarcodeInput>[];
    double oldQty = 0;
    bool found = false;
    for (final item in existingList) {
      if (item.barcode == trimmed) {
        oldQty = item.quantity ?? 0;
        found = true;
      } else {
        updatedList.add(item);
      }
    }

    if (!found) throw const PipelineApiException('Barcode assignment not found');

    if (oldQty > 0) {
      final db = await _dbHelper.database;
      await db.rawUpdate(
        'UPDATE materials SET on_hand_qty = on_hand_qty + ? WHERE barcode = ?',
        [oldQty, trimmed],
      );
    }

    final updatedRun = run.copyWith(
      attachedBarcodeInputs: {
        ...run.attachedBarcodeInputs,
        nodeId: updatedList,
      },
    );

    await saveRun(updatedRun);
    return updatedRun;
  }

  @override
  Future<List<PipelineRun>> getRunsForOrder(String orderNo) async {
    // Basic mock implementation for offline mode
    // Real implementation would join with order_pipeline_assignments
    return [];
  }

  @override
  Future<PipelineRun> updateNodeMetrics({
    required String runId,
    required String nodeId,
    required Map<String, dynamic> metrics,
  }) async {
    throw UnimplementedError('Sqlite mock not implemented for updateNodeMetrics');
  }

  @override
  Future<void> logProductionScrap({
    required String runId,
    required String nodeId,
    required String materialBarcode,
    required double scrapQty,
    String? orderNo,
  }) async {
    throw UnimplementedError('Sqlite mock not implemented for logProductionScrap');
  }
}
