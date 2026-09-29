import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/barcode_input.dart';
import '../../production_pipelines/domain/material_batch.dart';
import '../../production_pipelines/domain/node_run_status.dart';
import '../../production_pipelines/domain/pipeline_run.dart';
import '../../production_pipelines/domain/pipeline_template.dart';
import '../../production_pipelines/domain/run_overrides.dart';
import 'produce_sample_data.dart';

/// The whole backend of the Produce tab: one in-memory store, shared by the
/// runs list and the live monitor so the sandbox stays self-consistent for the
/// session. It satisfies [PipelineRunRepository] so the real monitor widgets
/// can be reused verbatim — every read and write they make lands here instead
/// of on the server, and nothing survives a restart.
///
/// Swapping Produce onto the real backend means dropping this provider, not
/// rewriting the screens.
class ProduceSandboxRepository implements PipelineRunRepository {
  ProduceSandboxRepository._();

  static final ProduceSandboxRepository instance = ProduceSandboxRepository._();

  final List<PipelineTemplate> _templates = buildProduceSampleTemplates();
  final List<PipelineRun> _runs = buildProduceSampleRuns();
  int _nextRunSeq = 1;

  /// Synchronous views, for the list screen that has no reason to await.
  List<PipelineTemplate> get templatesNow => List.unmodifiable(_templates);
  List<PipelineRun> get runsNow => List.unmodifiable(_runs);

  /// Runs sorted the way the tab shows them: active first, then newest.
  List<PipelineRun> get sortedRunsNow {
    final sorted = [..._runs];
    sorted.sort((a, b) {
      final aActive = a.status != 'completed';
      final bActive = b.status != 'completed';
      if (aActive && !bActive) return -1;
      if (!aActive && bActive) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return sorted;
  }

  /// Restores the hand-written rows, so a session that has been poked at can be
  /// put back to a known state.
  void reset() {
    _templates
      ..clear()
      ..addAll(buildProduceSampleTemplates());
    _runs
      ..clear()
      ..addAll(buildProduceSampleRuns());
    _nextRunSeq = 1;
  }

  int _indexOfRun(String runId) {
    final index = _runs.indexWhere((run) => run.id == runId);
    if (index == -1) {
      throw const PipelineApiException('Run not found in the Produce sandbox.');
    }
    return index;
  }

  // ── Templates ──────────────────────────────────────────────────────────────

  @override
  Future<List<PipelineTemplate>> getTemplates() async => templatesNow;

  @override
  Future<PipelineTemplate?> getTemplate(String id) async =>
      _templates.where((t) => t.id == id).firstOrNull;

  @override
  Future<PipelineTemplate> createTemplate(PipelineTemplate template) async {
    final created = template.id.trim().isEmpty
        ? template.copyWith(id: 'produce-tpl-${_templates.length + 1}')
        : template;
    final existing = _templates.indexWhere((t) => t.id == created.id);
    if (existing == -1) {
      _templates.add(created);
    } else {
      _templates[existing] = created;
    }
    return created;
  }

  @override
  Future<PipelineTemplate> updateTemplate(PipelineTemplate template) async {
    final index = _templates.indexWhere((t) => t.id == template.id);
    if (index == -1) {
      throw const PipelineApiException('Template not found in the Produce sandbox.');
    }
    _templates[index] = template;
    return template;
  }

  @override
  Future<void> deleteTemplate(String id) async {
    _templates.removeWhere((t) => t.id == id);
  }

  // ── Runs ───────────────────────────────────────────────────────────────────

  @override
  Future<List<PipelineRun>> getRuns({String? templateId}) async {
    if (templateId == null) return sortedRunsNow;
    return sortedRunsNow.where((run) => run.templateId == templateId).toList();
  }

  @override
  Future<List<PipelineRun>> getRunsForOrder(String orderNo) async {
    return _runs.where((run) => run.orderNo == orderNo).toList();
  }

  @override
  Future<PipelineRun?> getRun(String id) async =>
      _runs.where((run) => run.id == id).firstOrNull;

  @override
  Future<PipelineRun> createRun(
    String templateId, {
    String? name,
    String? orderNo,
    int? orderItemId,
    String? scrapRouting,
    int? outputVariationLeafNodeId,
    String? outputVariationPathLabel,
  }) async {
    final template = _templates.where((t) => t.id == templateId).firstOrNull;
    if (template == null) {
      throw const PipelineApiException('Template not found in the Produce sandbox.');
    }

    final seq = _nextRunSeq++;
    final run = PipelineRun(
      id: 'produce-run-$seq',
      templateId: templateId,
      templateVersion: 1,
      name: (name?.trim().isNotEmpty ?? false)
          ? name!.trim()
          : '${template.name} #$seq',
      status: 'planned',
      overrides: const RunOverrides(),
      nodeStatuses: <String, NodeRunStatus>{
        for (final node in template.nodes) node.id: NodeRunStatus.pending,
      },
      attachedBarcodeInputs: const <String, List<BarcodeInput>>{},
      createdAt: DateTime.now(),
      orderNo: orderNo,
      orderItemId: orderItemId,
      scrapRouting: scrapRouting ?? 'inventory',
    );
    _runs.insert(0, run);
    return run;
  }

  @override
  Future<void> deleteRun(String id) async {
    _runs.removeWhere((run) => run.id == id);
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
    final index = _indexOfRun(runId);
    final current = _runs[index];
    final statuses = <String, NodeRunStatus>{...current.nodeStatuses, nodeId: status};
    final overrides = current.overrides.copyWith(
      actualDurationHoursByNode: actualDurationHours == null
          ? null
          : <String, double>{
              ...current.overrides.actualDurationHoursByNode,
              nodeId: actualDurationHours,
            },
      batchQuantityByNode: batchQuantity == null
          ? null
          : <String, int>{
              ...current.overrides.batchQuantityByNode,
              nodeId: batchQuantity,
            },
      machineOverrideByNode: (machineOverride == null || machineOverride.trim().isEmpty)
          ? null
          : <String, String>{
              ...current.overrides.machineOverrideByNode,
              nodeId: machineOverride.trim(),
            },
    );

    final allDone = statuses.values.isNotEmpty &&
        statuses.values.every(
          (s) => s == NodeRunStatus.done || s == NodeRunStatus.skipped,
        );
    final updated = current.copyWith(
      nodeStatuses: statuses,
      overrides: overrides,
      status: statuses.values.any((s) => s == NodeRunStatus.active)
          ? 'running'
          : allDone
              ? 'completed'
              : current.status,
      completedAt: allDone ? DateTime.now() : null,
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
    final index = _indexOfRun(runId);
    final current = _runs[index];
    final existing = current.attachedBarcodeInputs[nodeId] ?? const <BarcodeInput>[];
    // No inventory lookup and no stock movement: the sandbox takes the barcode
    // at face value and books nothing against the real material.
    final updated = current.copyWith(
      attachedBarcodeInputs: <String, List<BarcodeInput>>{
        ...current.attachedBarcodeInputs,
        nodeId: <BarcodeInput>[
          ...existing,
          BarcodeInput(
            barcode: barcode,
            materialName: barcode,
            materialType: 'sandbox',
            scanCount: 0,
            quantity: quantity,
          ),
        ],
      },
    );
    _runs[index] = updated;
    return updated;
  }

  @override
  Future<PipelineRun> updateAttachedBarcodeQuantity({
    required String runId,
    required String nodeId,
    required String barcode,
    required double quantity,
  }) async {
    final index = _indexOfRun(runId);
    final current = _runs[index];
    final existing = current.attachedBarcodeInputs[nodeId] ?? const <BarcodeInput>[];
    final updated = current.copyWith(
      attachedBarcodeInputs: <String, List<BarcodeInput>>{
        ...current.attachedBarcodeInputs,
        nodeId: <BarcodeInput>[
          for (final input in existing)
            if (input.barcode == barcode)
              BarcodeInput(
                barcode: input.barcode,
                materialName: input.materialName,
                materialType: input.materialType,
                scanCount: input.scanCount,
                quantity: quantity,
                unit: input.unit,
              )
            else
              input,
        ],
      },
    );
    _runs[index] = updated;
    return updated;
  }

  @override
  Future<PipelineRun> detachBarcodeFromRunNode({
    required String runId,
    required String nodeId,
    required String barcode,
  }) async {
    final index = _indexOfRun(runId);
    final current = _runs[index];
    final existing = current.attachedBarcodeInputs[nodeId] ?? const <BarcodeInput>[];
    final updated = current.copyWith(
      attachedBarcodeInputs: <String, List<BarcodeInput>>{
        ...current.attachedBarcodeInputs,
        nodeId: existing.where((input) => input.barcode != barcode).toList(),
      },
    );
    _runs[index] = updated;
    return updated;
  }

  @override
  Future<PipelineRun> updateNodeMetrics({
    required String runId,
    required String nodeId,
    required Map<String, dynamic> metrics,
  }) async {
    final index = _indexOfRun(runId);
    final current = _runs[index];
    final updated = current.copyWith(
      nodeMetrics: <String, Map<String, dynamic>>{
        ...current.nodeMetrics,
        nodeId: <String, dynamic>{...?current.nodeMetrics[nodeId], ...metrics},
      },
    );
    _runs[index] = updated;
    return updated;
  }

  @override
  Future<void> logProductionScrap({
    required String runId,
    required String nodeId,
    required String materialBarcode,
    required double scrapQty,
    String? orderNo,
    int? scrapItemId,
    String? scrapItemName,
  }) async {
    // Scrap has nowhere to go in a sandbox — the ledger it would post to is
    // backend state. Recorded on the node so the UI can still show it.
    final index = _indexOfRun(runId);
    final current = _runs[index];
    _runs[index] = current.copyWith(
      nodeMetrics: <String, Map<String, dynamic>>{
        ...current.nodeMetrics,
        nodeId: <String, dynamic>{
          ...?current.nodeMetrics[nodeId],
          'scrapQty': scrapQty,
          'scrapItem': ?scrapItemName,
        },
      },
    );
  }

  @override
  Future<PipelineRun> saveBatches({
    required String runId,
    required List<MaterialBatch> batches,
  }) async {
    final index = _indexOfRun(runId);
    final updated = _runs[index].copyWith(batches: List<MaterialBatch>.from(batches));
    _runs[index] = updated;
    return updated;
  }
}
