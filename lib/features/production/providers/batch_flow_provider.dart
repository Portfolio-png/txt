import 'package:flutter/foundation.dart';

import '../../production_pipelines/domain/material_batch.dart';
import '../../production_pipelines/domain/pipeline_run.dart';

/// A reversible record of one forward batch move and every side effect it
/// caused, so any chip's last hop can be precisely undone (chip + inventory).
/// The side-effect fields are filled in by the caller after the move/booking.
class BatchMoveRecord {
  BatchMoveRecord({
    required this.resultBatchId,
    required this.fromNodeId,
    required this.toNodeId,
    required this.qty,
    required this.wasSplit,
    this.parentBatchId,
  });

  /// The batch now sitting at [toNodeId] (a new child for a split, or the same
  /// batch for a full move).
  final String resultBatchId;
  final String fromNodeId;
  final String toNodeId;
  final double qty;
  final bool wasSplit;
  final String? parentBatchId;

  // Side effects to compensate on revert.
  String? consumeBarcode; // raw consumed when leaving Input
  double consumeQty = 0;
  String? yieldLotBarcode; // produced lot when landing at Output
  double yieldQty = 0;
  double scrapLogged = 0; // scrap booked by reconcile
  double leftoverReturned = 0; // leftover returned to inventory by reconcile
  String? reconcileBarcode; // material the scrap/leftover was booked against
  double lossQty = 0; // amount reduced from the source chip by reconcile
}

/// In-memory store of [MaterialBatch] tokens per run (Phase 0).
///
/// This is deliberately client-side only: it lets the gamified token-chip UX
/// be exercised with no backend/migration changes. A run is seeded once from
/// its assigned stock, after which chips can be split and moved between nodes.
/// Phase 1 will back these operations with the pipeline run repository.
class BatchFlowProvider extends ChangeNotifier {
  final Map<String, List<MaterialBatch>> _byRun = {};
  final Map<String, List<BatchMoveRecord>> _historyByRun = {};
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

  /// Seeds a run from its persisted batches, or — first time — derives chips
  /// from the stock assigned to each node. No-op if already seeded. Lets any
  /// screen (not just the canvas) bring the token view up from a saved run.
  void seedFromRun(PipelineRun run) {
    if (_seededRuns.contains(run.id)) return;
    if (run.batches.isNotEmpty) {
      seedRun(run.id, run.batches);
      return;
    }
    final initial = <MaterialBatch>[];
    run.attachedBarcodeInputs.forEach((nodeId, inputs) {
      for (final input in inputs) {
        final qty = input.quantity ?? 0;
        if (qty <= 0) continue;
        initial.add(
          MaterialBatch(
            id: 'seed-${run.id}-$nodeId-${input.barcode}-${initial.length}',
            barcode: input.barcode,
            materialName: input.materialName,
            quantity: qty,
            unit: input.unit,
            currentNodeId: nodeId,
          ),
        );
      }
    });
    seedRun(run.id, initial);
  }

  // --- Live sync (cross-client polling) -----------------------------------
  final Map<String, DateTime> _lastLocalChangeAt = {};

  /// When the local user last mutated this run's batches. The live poller uses
  /// this to avoid clobbering an edit that may not have finished persisting.
  DateTime? lastLocalChangeAt(String runId) => _lastLocalChangeAt[runId];

  void _touchLocal(String runId) {
    _lastLocalChangeAt[runId] = DateTime.now();
  }

  /// Replaces a run's batches with authoritative server state (from a poll),
  /// marking the run seeded. No-op if the batches are already identical so the
  /// poll doesn't churn the UI. Caller should skip this while a local edit is
  /// still settling (see [lastLocalChangeAt]).
  void syncFromRun(PipelineRun run) {
    final current = _byRun[run.id];
    if (current != null && _sameBatches(current, run.batches)) {
      _seededRuns.add(run.id);
      return;
    }
    _seededRuns.add(run.id);
    _byRun[run.id] = [...run.batches];
    notifyListeners();
  }

  bool _sameBatches(List<MaterialBatch> a, List<MaterialBatch> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].quantity != b[i].quantity ||
          a[i].currentNodeId != b[i].currentNodeId ||
          a[i].scrap != b[i].scrap ||
          a[i].leftover != b[i].leftover) {
        return false;
      }
    }
    return true;
  }

  /// Moves [quantity] of a batch to [toNodeId]. If the quantity is less than
  /// the batch total the batch is split: the source shrinks and a new child
  /// batch lands at the target node. Moving the whole batch relocates it.
  ///
  /// Returns the id of the batch now sitting at [toNodeId] (the new child for a
  /// split, or the same id for a full move), or null if nothing moved.
  String? moveBatch({
    required String runId,
    required String batchId,
    required String toNodeId,
    required double quantity,
  }) {
    final list = _byRun[runId];
    if (list == null) return null;
    final idx = list.indexWhere((b) => b.id == batchId);
    if (idx == -1) return null;
    final batch = list[idx];
    if (batch.currentNodeId == toNodeId) return null;

    final qty = quantity.clamp(0, batch.quantity).toDouble();
    if (qty <= 0) return null;

    // Stamp the arrival time so the ledger can show when stock reached a stage.
    final arrivedAt = DateTime.now();
    String resultId;
    if (qty >= batch.quantity) {
      list[idx] = batch.copyWith(currentNodeId: toNodeId, createdAt: arrivedAt);
      resultId = batch.id;
    } else {
      list[idx] = batch.copyWith(quantity: batch.quantity - qty);
      resultId = _newId();
      list.add(
        batch.copyWith(
          id: resultId,
          quantity: qty,
          currentNodeId: toNodeId,
          parentBatchId: batch.id,
          createdAt: arrivedAt,
        ),
      );
    }
    _touchLocal(runId);
    notifyListeners();
    return resultId;
  }

  /// Records a reversible forward move for [runId].
  void recordMove(String runId, BatchMoveRecord record) {
    (_historyByRun[runId] ??= []).add(record);
  }

  /// The most recent move that brought batch [batchId] to its current node,
  /// or null if there's no reversible history for it.
  BatchMoveRecord? lastRecordForBatch(String runId, String batchId) {
    final history = _historyByRun[runId];
    if (history == null) return null;
    for (var i = history.length - 1; i >= 0; i--) {
      if (history[i].resultBatchId == batchId) return history[i];
    }
    return null;
  }

  /// Reverses the chip half of a move: removes the target arrival and restores
  /// the advanced qty (plus any reconcile loss) to the source. The caller is
  /// responsible for compensating the inventory side effects. Returns false if
  /// the target batch is gone (e.g. it was moved on again) — revert unsafe.
  bool revertChip(String runId, BatchMoveRecord r) {
    final list = _byRun[runId];
    if (list == null) return false;
    final idx = list.indexWhere((b) => b.id == r.resultBatchId);
    if (idx == -1) return false;
    final result = list[idx];

    if (r.wasSplit) {
      // The loss was deducted from the parent remainder, not the child.
      final restore = r.qty + r.lossQty;
      list.removeAt(idx);
      final pIdx = r.parentBatchId == null
          ? -1
          : list.indexWhere(
              (b) => b.id == r.parentBatchId && b.currentNodeId == r.fromNodeId,
            );
      if (pIdx != -1) {
        list[pIdx] = list[pIdx].copyWith(
          quantity: list[pIdx].quantity + restore,
        );
      } else {
        // Parent already moved on — recreate the stock at the source node.
        list.add(
          result.copyWith(
            id: _newId(),
            quantity: restore,
            currentNodeId: r.fromNodeId,
            parentBatchId: null,
          ),
        );
      }
    } else {
      // Full move: the loss was deducted from this same batch — relocate it
      // back and add the loss back.
      list[idx] = result.copyWith(
        currentNodeId: r.fromNodeId,
        quantity: result.quantity + r.lossQty,
      );
    }

    _historyByRun[runId]?.remove(r);
    _touchLocal(runId);
    notifyListeners();
    return true;
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
    _touchLocal(runId);
    notifyListeners();
  }

  /// Reduces a batch's quantity by [amount] — e.g. the scrap/leftover that a
  /// stage reconciliation declared as having left the production pool beyond
  /// what advanced. The [scrap] and [leftover] split is accumulated onto the
  /// batch so the ledger can report it. Removes the batch if it drops to (near)
  /// zero.
  // ponytail: a batch fully consumed to scrap/leftover is removed, so its
  // totals drop off the ledger. Keep a zero-qty "spent" batch only if that case
  // needs reporting.
  void reduceBatch({
    required String runId,
    required String batchId,
    required double amount,
    double scrap = 0,
    double leftover = 0,
  }) {
    if (amount <= 0) return;
    final list = _byRun[runId];
    if (list == null) return;
    final idx = list.indexWhere((b) => b.id == batchId);
    if (idx == -1) return;
    final next = list[idx].quantity - amount;
    if (next <= 0.0001) {
      list.removeAt(idx);
    } else {
      list[idx] = list[idx].copyWith(
        quantity: next,
        scrap: list[idx].scrap + scrap,
        leftover: list[idx].leftover + leftover,
      );
    }
    _touchLocal(runId);
    notifyListeners();
  }

  /// Clears a run's batches so it can be re-seeded (e.g. after a reset).
  void resetRun(String runId) {
    _byRun.remove(runId);
    _historyByRun.remove(runId);
    _seededRuns.remove(runId);
    notifyListeners();
  }

  String _newId() => 'b-${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
}
