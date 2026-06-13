import 'package:flutter/foundation.dart';

import '../../production_pipelines/domain/material_batch.dart';

/// In-memory store of [MaterialBatch] tokens per run (Phase 0).
///
/// This is deliberately client-side only: it lets the gamified token-chip UX
/// be exercised with no backend/migration changes. A run is seeded once from
/// its assigned stock, after which chips can be split and moved between nodes.
/// Phase 1 will back these operations with the pipeline run repository.
class BatchFlowProvider extends ChangeNotifier {
  final Map<String, List<MaterialBatch>> _byRun = {};
  final Set<String> _seededRuns = {};
  int _counter = 0;

  bool isSeeded(String runId) => _seededRuns.contains(runId);

  List<MaterialBatch> batchesForRun(String runId) =>
      List.unmodifiable(_byRun[runId] ?? const []);

  List<MaterialBatch> batchesAtNode(String runId, String nodeId) =>
      (_byRun[runId] ?? const [])
          .where((b) => b.currentNodeId == nodeId && b.isLive)
          .toList(growable: false);

  /// Seeds a run's batches exactly once. No-op if already seeded.
  void seedRun(String runId, List<MaterialBatch> initial) {
    if (_seededRuns.contains(runId)) return;
    _seededRuns.add(runId);
    _byRun[runId] = [...initial];
    notifyListeners();
  }

  /// Moves [quantity] of a batch to [toNodeId]. If the quantity is less than
  /// the batch total the batch is split: the source shrinks and a new child
  /// batch lands at the target node. Moving the whole batch relocates it.
  void moveBatch({
    required String runId,
    required String batchId,
    required String toNodeId,
    required double quantity,
  }) {
    final list = _byRun[runId];
    if (list == null) return;
    final idx = list.indexWhere((b) => b.id == batchId);
    if (idx == -1) return;
    final batch = list[idx];
    if (batch.currentNodeId == toNodeId) return;

    final qty = quantity.clamp(0, batch.quantity).toDouble();
    if (qty <= 0) return;

    if (qty >= batch.quantity) {
      list[idx] = batch.copyWith(currentNodeId: toNodeId);
    } else {
      list[idx] = batch.copyWith(quantity: batch.quantity - qty);
      list.add(
        batch.copyWith(
          id: _newId(),
          quantity: qty,
          currentNodeId: toNodeId,
          parentBatchId: batch.id,
        ),
      );
    }
    notifyListeners();
  }

  /// Adds a fresh batch at [nodeId] — used when new stock is assigned to a
  /// node after the run was already seeded, so the chip appears immediately.
  void addStockAtNode({
    required String runId,
    required String nodeId,
    required String barcode,
    required String materialName,
    required double quantity,
    String? unit,
  }) {
    if (quantity <= 0) return;
    _seededRuns.add(runId);
    (_byRun[runId] ??= []).add(
      MaterialBatch(
        id: _newId(),
        barcode: barcode,
        materialName: materialName,
        quantity: quantity,
        currentNodeId: nodeId,
        unit: unit,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  /// Clears a run's batches so it can be re-seeded (e.g. after a reset).
  void resetRun(String runId) {
    _byRun.remove(runId);
    _seededRuns.remove(runId);
    notifyListeners();
  }

  String _newId() => 'b-${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
}
