import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/domain/material_record.dart';
import 'package:core_erp/features/inventory/domain/inventory_control_tower.dart';
import '../../domain/barcode_input.dart';
import '../../domain/node_run_status.dart';
import '../../domain/pipeline_run.dart';
import '../../domain/pipeline_template.dart';
import '../../domain/run_overrides.dart';
import '../mock_pipeline_templates_repository.dart';
import 'pipeline_run_repository.dart';

class MockPipelineRunRepository implements PipelineRunRepository {
  MockPipelineRunRepository({required InventoryRepository inventoryRepository})
    : _inventoryRepository = inventoryRepository;

  final InventoryRepository _inventoryRepository;

  final MockPipelineTemplatesRepository _templatesRepository =
      const MockPipelineTemplatesRepository();

  List<PipelineTemplate>? _templates;
  final List<PipelineRun> _runs = <PipelineRun>[];
  int _nextRunId = 1;

  @override
  Future<List<PipelineTemplate>> getTemplates() async {
    _ensureSeeded();
    return List<PipelineTemplate>.unmodifiable(_templates!);
  }

  @override
  Future<PipelineTemplate> createTemplate(PipelineTemplate template) async {
    _ensureSeeded();
    final created = template.id.trim().isEmpty
        ? template.copyWith(id: 'template-${_templates!.length + 1}')
        : template;
    _templates = <PipelineTemplate>[..._templates!, created];
    return created;
  }

  @override
  Future<PipelineTemplate> updateTemplate(PipelineTemplate template) async {
    _ensureSeeded();
    final index = _templates!.indexWhere((item) => item.id == template.id);
    if (index == -1) {
      throw const PipelineApiException('Template not found.');
    }
    _templates![index] = template;
    return template;
  }

  @override
  Future<PipelineTemplate?> getTemplate(String id) async {
    _ensureSeeded();
    return _templates!.where((item) => item.id == id).firstOrNull;
  }

  @override
  Future<List<PipelineRun>> getRuns({String? templateId}) async {
    _ensureSeeded();
    final scoped = templateId == null
        ? _runs
        : _runs.where((run) => run.templateId == templateId);
    return scoped.toList(growable: false);
  }

  @override
  Future<List<PipelineRun>> getRunsForOrder(String orderNo) async {
    _ensureSeeded();
    return _runs.where((run) => run.orderNo == orderNo).toList();
  }

  @override
  Future<PipelineRun> createRun(
    String templateId, {
    String? name,
    String? orderNo,
    int? orderItemId,
    String? scrapRouting,
  }) async {
    _ensureSeeded();
    final template = _templates!
        .where((item) => item.id == templateId)
        .firstOrNull;
    if (template == null) {
      throw const PipelineApiException('Template not found.');
    }

    final run = PipelineRun(
      id: 'run-${_nextRunId++}',
      templateId: templateId,
      templateVersion: 1,
      name: name?.trim().isNotEmpty == true
          ? name!.trim()
          : '${template.name} #${_nextRunId - 1}',
      orderNo: orderNo,
      status: 'active',
      overrides: const RunOverrides(),
      nodeStatuses: {
        for (final node in template.nodes) node.id: NodeRunStatus.pending,
      },
      attachedBarcodeInputs: const <String, List<BarcodeInput>>{},
      createdAt: DateTime.now(),
      startedAt: DateTime.now(),
    );
    _runs.insert(0, run);
    return run;
  }

  @override
  Future<PipelineRun?> getRun(String id) async {
    _ensureSeeded();
    return _runs.where((run) => run.id == id).firstOrNull;
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
    _ensureSeeded();
    final index = _runs.indexWhere((run) => run.id == runId);
    if (index == -1) {
      throw const PipelineApiException('Run not found.');
    }

    final current = _runs[index];
    final updatedStatuses = <String, NodeRunStatus>{
      ...current.nodeStatuses,
      nodeId: status,
    };
    final updatedOverrides = current.overrides.copyWith(
      actualDurationHoursByNode: actualDurationHours == null
          ? current.overrides.actualDurationHoursByNode
          : <String, double>{
              ...current.overrides.actualDurationHoursByNode,
              nodeId: actualDurationHours,
            },
      batchQuantityByNode: batchQuantity == null
          ? current.overrides.batchQuantityByNode
          : <String, int>{
              ...current.overrides.batchQuantityByNode,
              nodeId: batchQuantity,
            },
      machineOverrideByNode:
          machineOverride == null || machineOverride.trim().isEmpty
          ? current.overrides.machineOverrideByNode
          : <String, String>{
              ...current.overrides.machineOverrideByNode,
              nodeId: machineOverride.trim(),
            },
    );
    final updated = current.copyWith(
      nodeStatuses: updatedStatuses,
      overrides: updatedOverrides,
      status: _resolveRunStatus(updatedStatuses.values),
      completedAt: _allDone(updatedStatuses.values) ? DateTime.now() : null,
    );
    _runs[index] = updated;
    return updated;
  }

  @override
  Future<PipelineRun> attachBarcodeToRunNode({
    required String runId,
    required String nodeId,
    required String barcode,
    double? quantity,
  }) async {
    _ensureSeeded();
    final index = _runs.indexWhere((run) => run.id == runId);
    if (index == -1) {
      throw const PipelineApiException('Run not found.');
    }

    final material = await _lookupMaterial(barcode);
    if (material == null) {
      throw PipelineApiException(
        'No material found for barcode ${barcode.trim()}.',
      );
    }

    if (quantity != null && quantity > 0) {
      await _inventoryRepository.createInventoryMovement(
        CreateInventoryMovementInput(
          materialBarcode: barcode,
          movementType: InventoryMovementType.consume,
          qty: quantity,
          reasonCode: 'PRODUCTION_ASSIGN',
          referenceType: 'pipeline_run',
          referenceId: runId,
        ),
      );
    }

    final current = _runs[index];
    final existing = current.attachedBarcodeInputs[nodeId] ?? const [];
    final updated = current.copyWith(
      attachedBarcodeInputs: {
        ...current.attachedBarcodeInputs,
        nodeId: <BarcodeInput>[
          ...existing,
          BarcodeInput.fromMaterialRecord(material, quantity: quantity),
        ],
      },
    );
    _runs[index] = updated;
    return updated;
  }

  Future<MaterialRecord?> _lookupMaterial(String barcode) async {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return _inventoryRepository.getMaterialByBarcode(trimmed);
  }

  void _ensureSeeded() {
    _templates ??= _templatesRepository.getTemplates().toList(growable: true);
  }

  static String _resolveRunStatus(Iterable<NodeRunStatus> statuses) {
    if (statuses.any((status) => status == NodeRunStatus.active)) {
      return 'active';
    }
    if (_allDone(statuses)) {
      return 'completed';
    }
    return 'planned';
  }

  static bool _allDone(Iterable<NodeRunStatus> statuses) {
    return statuses.isNotEmpty &&
        statuses.every(
          (status) =>
              status == NodeRunStatus.done || status == NodeRunStatus.skipped,
        );
  }

  @override
  Future<PipelineRun> updateAttachedBarcodeQuantity({
    required String runId,
    required String nodeId,
    required String barcode,
    required double quantity,
  }) async {
    _ensureSeeded();
    final index = _runs.indexWhere((run) => run.id == runId);
    if (index == -1) {
      throw const PipelineApiException('Run not found.');
    }

    final current = _runs[index];
    final existing = current.attachedBarcodeInputs[nodeId] ?? const [];
    
    double oldQty = 0;
    BarcodeInput? targetItem;
    final updatedList = <BarcodeInput>[];
    
    for (final item in existing) {
      if (item.barcode == barcode) {
        oldQty = item.quantity ?? 0;
        targetItem = BarcodeInput(
          barcode: item.barcode,
          materialName: item.materialName,
          materialType: item.materialType,
          scanCount: item.scanCount,
          quantity: quantity,
          unit: item.unit,
        );
        updatedList.add(targetItem);
      } else {
        updatedList.add(item);
      }
    }

    if (targetItem == null) {
      throw const PipelineApiException('Assigned stock not found.');
    }

    final qtyDiff = quantity - oldQty;
    if (qtyDiff != 0) {
      await _inventoryRepository.createInventoryMovement(
        CreateInventoryMovementInput(
          materialBarcode: barcode,
          movementType: qtyDiff > 0 
              ? InventoryMovementType.consume 
              : InventoryMovementType.adjust,
          qty: qtyDiff.abs(),
          reasonCode: 'PRODUCTION_ASSIGN_UPDATE',
          referenceType: 'pipeline_run',
          referenceId: runId,
        ),
      );
    }

    final updatedRun = current.copyWith(
      attachedBarcodeInputs: {
        ...current.attachedBarcodeInputs,
        nodeId: updatedList,
      },
    );
    _runs[index] = updatedRun;
    return updatedRun;
  }

  @override
  Future<PipelineRun> detachBarcodeFromRunNode({
    required String runId,
    required String nodeId,
    required String barcode,
  }) async {
    _ensureSeeded();
    final index = _runs.indexWhere((run) => run.id == runId);
    if (index == -1) {
      throw const PipelineApiException('Run not found.');
    }

    final current = _runs[index];
    final existing = current.attachedBarcodeInputs[nodeId] ?? const [];
    
    double oldQty = 0;
    final updatedList = <BarcodeInput>[];
    bool found = false;
    
    for (final item in existing) {
      if (item.barcode == barcode) {
        oldQty = item.quantity ?? 0;
        found = true;
      } else {
        updatedList.add(item);
      }
    }

    if (!found) {
      throw const PipelineApiException('Assigned stock not found.');
    }

    if (oldQty > 0) {
      await _inventoryRepository.createInventoryMovement(
        CreateInventoryMovementInput(
          materialBarcode: barcode,
          movementType: InventoryMovementType.adjust,
          qty: oldQty,
          reasonCode: 'PRODUCTION_ASSIGN_DELETE',
          referenceType: 'pipeline_run',
          referenceId: runId,
        ),
      );
    }

    final updatedRun = current.copyWith(
      attachedBarcodeInputs: {
        ...current.attachedBarcodeInputs,
        nodeId: updatedList,
      },
    );
    _runs[index] = updatedRun;
    return updatedRun;
  }

  @override
  Future<void> deleteTemplate(String id) async {
    _ensureSeeded();
    _templates?.removeWhere((t) => t.id == id);
  }

  @override
  Future<void> deleteRun(String id) async {
    _ensureSeeded();
    _runs.removeWhere((r) => r.id == id);
  }

  @override
  Future<PipelineRun> updateNodeMetrics({
    required String runId,
    required String nodeId,
    required Map<String, dynamic> metrics,
  }) async {
    _ensureSeeded();
    final index = _runs.indexWhere((run) => run.id == runId);
    if (index == -1) {
      throw const PipelineApiException('Run not found.');
    }
    // Mock implementation doesn't strictly update metrics here since PipelineRun may not have a metrics field readily mutable in the mock without more domain logic, but we return the run to satisfy the signature.
    return _runs[index];
  }

  @override
  Future<void> logProductionScrap({
    required String runId,
    required String nodeId,
    required String materialBarcode,
    required double scrapQty,
    String? orderNo,
  }) async {
    _ensureSeeded();
    final index = _runs.indexWhere((run) => run.id == runId);
    if (index == -1) {
      throw const PipelineApiException('Run not found.');
    }
    // Mock implementation: just simulate a successful log.
  }
}

