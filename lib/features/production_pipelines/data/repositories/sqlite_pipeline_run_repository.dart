import 'dart:convert';
import 'package:uuid/uuid.dart';

import '../../domain/barcode_input.dart';
import '../../domain/node_run_status.dart';
import '../../domain/pipeline_run.dart';
import '../../domain/pipeline_template.dart';
import '../../domain/run_overrides.dart';
import 'pipeline_run_repository.dart';
import '../../../production/data/datasources/offline_database_helper.dart';

class SqlitePipelineRunRepository implements PipelineRunRepository {
  final _dbHelper = OfflineSyncDbHelper.instance;
  final _uuid = const Uuid();

  @override
  Future<List<PipelineTemplate>> getTemplates() async {
    final db = await _dbHelper.database;
    final maps = await db.query('pipeline_templates', orderBy: 'created_at DESC');
    return maps.map((m) {
      final data = jsonDecode(m['data'] as String) as Map<String, dynamic>;
      return PipelineTemplate.fromJson(data);
    }).toList();
  }

  @override
  Future<PipelineTemplate> createTemplate(PipelineTemplate template) async {
    final db = await _dbHelper.database;
    final newTemplate = template.copyWith(id: template.id.isEmpty ? _uuid.v4() : template.id);
    await db.insert('pipeline_templates', {
      'id': newTemplate.id,
      'name': newTemplate.name,
      'data': jsonEncode(newTemplate.toJson()),
      'created_at': DateTime.now().toIso8601String(),
    });
    return newTemplate;
  }

  @override
  Future<PipelineTemplate> updateTemplate(PipelineTemplate template) async {
    final db = await _dbHelper.database;
    await db.update(
      'pipeline_templates',
      {
        'name': template.name,
        'data': jsonEncode(template.toJson()),
      },
      where: 'id = ?',
      whereArgs: [template.id],
    );
    return template;
  }

  @override
  Future<PipelineTemplate?> getTemplate(String id) async {
    final db = await _dbHelper.database;
    final maps = await db.query('pipeline_templates', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    final data = jsonDecode(maps.first['data'] as String) as Map<String, dynamic>;
    return PipelineTemplate.fromJson(data);
  }

  @override
  Future<List<PipelineRun>> getRuns({String? templateId}) async {
    final db = await _dbHelper.database;
    final List<Map<String, Object?>> maps;
    if (templateId != null) {
      maps = await db.query('pipeline_runs', where: 'template_id = ?', whereArgs: [templateId], orderBy: 'start_time DESC');
    } else {
      maps = await db.query('pipeline_runs', orderBy: 'start_time DESC');
    }
    return maps.map((m) {
      final data = jsonDecode(m['data'] as String) as Map<String, dynamic>;
      return PipelineRun.fromJson(data);
    }).toList();
  }

  @override
  Future<PipelineRun> createRun(String templateId, {String? name}) async {
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
        for (final node in template.nodes) node.id: NodeRunStatus.pending
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
    final maps = await db.query('pipeline_runs', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    final data = jsonDecode(maps.first['data'] as String) as Map<String, dynamic>;
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

    final allCompleted = updatedStatuses.isNotEmpty &&
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

    final bool anyActiveOrDone = updatedStatuses.values.any((s) => s == NodeRunStatus.active || s == NodeRunStatus.done || s == NodeRunStatus.skipped);
    final String runStatus = allCompleted ? 'completed' : (anyActiveOrDone ? 'active' : 'planned');
    final DateTime? startedAt = run.startedAt ?? (anyActiveOrDone ? DateTime.now() : null);

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
  }) async {
    final run = await getRun(runId);
    if (run == null) throw const PipelineApiException('Run not found');

    final trimmed = barcode.trim();
    if (trimmed.isEmpty) return run;

    final existingList = run.attachedBarcodeInputs[nodeId] ?? const <BarcodeInput>[];
    
    final updatedList = <BarcodeInput>[];
    bool found = false;
    for (final item in existingList) {
      if (item.barcode == trimmed) {
        updatedList.add(BarcodeInput(
          barcode: item.barcode,
          materialName: item.materialName,
          materialType: item.materialType,
          scanCount: item.scanCount + 1,
        ));
        found = true;
      } else {
        updatedList.add(item);
      }
    }
    
    if (!found) {
      updatedList.add(BarcodeInput(
        barcode: trimmed,
        materialName: 'Material $trimmed',
        materialType: 'Scanned Input',
        scanCount: 1,
      ));
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
}
