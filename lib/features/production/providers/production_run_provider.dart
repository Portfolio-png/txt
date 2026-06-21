import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../production_pipelines/domain/material_batch.dart';
import '../../production_pipelines/domain/pipeline_run.dart';
import '../../production_pipelines/domain/process_node.dart';
import '../data/datasources/offline_database_helper.dart';

enum ProductionState { idle, setup, running, paused, completed }

enum LeftoverAction { returnToInventory, scrap }

/// What a reconcile commit booked, so a later revert can compensate it.
class ReconcileResult {
  const ReconcileResult({
    required this.loss,
    required this.scrapLogged,
    required this.leftoverReturned,
    required this.output,
    this.barcode,
  });

  /// Allotted − output: the amount deducted from the source chip.
  final double loss;

  /// Scrap booked to the production scrap ledger.
  final double scrapLogged;

  /// Leftover returned to inventory.
  final double leftoverReturned;

  /// The exact output quantity from this stage.
  final double output;

  /// The material the scrap/leftover was booked against.
  final String? barcode;
}

/// A request to reconcile a stage/batch, surfaced in the Assign Stock sidebar
/// (SolidWorks-style docked panel) rather than a centred dialog. The caller
/// awaits [ProductionRunProvider.requestReconcile]; the sidebar form resolves
/// it with a [ReconcileResult] on commit or null on cancel.
class ReconcileRequest {
  const ReconcileRequest({
    required this.node,
    required this.runId,
    this.batchOutput,
    this.batchAllottedMax,
    this.batchReconcileQty,
    this.batchUnit,
    this.batchBarcode,
    this.batchLabel,
  });

  final ProcessNode node;
  final String runId;
  final double? batchOutput;
  final double? batchAllottedMax;
  final double? batchReconcileQty;
  final String? batchUnit;
  final String? batchBarcode;
  final String? batchLabel;
}

typedef ProductionNow = DateTime Function();
typedef ProductionBufferCommitter =
    Future<void> Function(ProductionRunCommit commit);

class ProductionRunCommit {
  const ProductionRunCommit({
    required this.runId,
    required this.stageId,
    required this.goodYield,
    required this.setupScrap,
    required this.state,
  });

  final String runId;
  final String stageId;
  final int goodYield;
  final int setupScrap;
  final ProductionState state;
}

class ProductionRunProvider extends ChangeNotifier {
  ProductionRunProvider({
    ProductionBufferCommitter? bufferCommitter,
    ProductionNow? now,
    Duration tickInterval = const Duration(seconds: 1),
    Duration offlinePollInterval = const Duration(seconds: 30),
  }) : _bufferCommitter = bufferCommitter,
       _now = now ?? DateTime.now,
       _tickInterval = tickInterval,
       _offlinePollInterval = offlinePollInterval {
    _startOfflineSyncTimer();
    _restoreActiveRun();
  }

  static const String _activeRunKey = 'active_run_id';

  final ProductionBufferCommitter? _bufferCommitter;
  final ProductionNow _now;
  final Duration _tickInterval;
  final Duration _offlinePollInterval;

  ProductionState _state = ProductionState.idle;
  String? _runId;
  DateTime? _stageStartedAt;
  Duration _bankedElapsed = Duration.zero;
  int _currentYield = 0;
  int _currentScrap = 0;
  bool _isCommitting = false;
  Timer? _ticker;

  String? _stageId;
  Timer? _offlineSyncTimer;
  int _refreshCount = 0;

  int get refreshCount => _refreshCount;

  void triggerRefresh() {
    _refreshCount++;
    notifyListeners();
  }

  // Latest server snapshot of the open run, published by the canvas poll so
  // node-metric widgets read one shared source instead of each re-fetching.
  PipelineRun? _currentRun;
  PipelineRun? get currentRun => _currentRun;

  void setCurrentRun(PipelineRun? run) {
    if (identical(_currentRun, run)) return;
    _currentRun = run;
    notifyListeners();
  }

  // Double-clicking a stage/batch pops out the action circles (start / mark
  // done / skip, or batch reconcile / revert). Reconcile itself is handled by
  // the docked panel below, not a popout mode. [_popoutBatch] null =>
  // whole-stage; otherwise per-batch.
  String? _popoutNodeId;
  MaterialBatch? _popoutBatch;

  String? get popoutNodeId => _popoutNodeId;
  MaterialBatch? get popoutBatch => _popoutBatch;
  bool get hasPopout => _popoutNodeId != null;

  void openStageActions(String nodeId) {
    _popoutNodeId = nodeId;
    _popoutBatch = null;
    notifyListeners();
  }

  void openBatchActions(String nodeId, MaterialBatch batch) {
    _popoutNodeId = nodeId;
    _popoutBatch = batch;
    notifyListeners();
  }

  void closePopout() {
    if (_popoutNodeId == null && _popoutBatch == null) return;
    _popoutNodeId = null;
    _popoutBatch = null;
    notifyListeners();
  }

  // The reconcile form docks into the Assign Stock sidebar. A caller (canvas
  // drag-drop or a stage/batch action) opens one with [requestReconcile] and
  // awaits the result; the sidebar form resolves it via [submitReconcile] /
  // [cancelReconcile].
  ReconcileRequest? _reconcileRequest;
  Completer<ReconcileResult?>? _reconcileCompleter;

  ReconcileRequest? get reconcileRequest => _reconcileRequest;

  Future<ReconcileResult?> requestReconcile(ReconcileRequest request) {
    // Only one docked reconcile at a time — cancel any in-flight one first.
    _reconcileCompleter?.complete(null);
    closePopout();
    _reconcileRequest = request;
    _reconcileCompleter = Completer<ReconcileResult?>();
    notifyListeners();
    return _reconcileCompleter!.future;
  }

  void submitReconcile(ReconcileResult result) => _resolveReconcile(result);

  void cancelReconcile() => _resolveReconcile(null);

  void _resolveReconcile(ReconcileResult? result) {
    final completer = _reconcileCompleter;
    _reconcileRequest = null;
    _reconcileCompleter = null;
    notifyListeners();
    if (completer != null && !completer.isCompleted) completer.complete(result);
  }

  ProductionState get state => _state;
  String? get runId => _runId;
  DateTime? get stageStartedAt => _stageStartedAt;
  int get goodYield => _currentYield;
  int get setupScrap => _currentScrap;
  bool get isCommitting => _isCommitting;
  bool get isIdle => _state == ProductionState.idle;
  bool get isRunning => _state == ProductionState.running;
  bool get isPaused => _state == ProductionState.paused;
  bool get isCompleted => _state == ProductionState.completed;

  String? get stageId => _stageId;

  Duration get elapsed {
    final startedAt = _stageStartedAt;
    if (_state == ProductionState.running && startedAt != null) {
      final liveDelta = _now().difference(startedAt);
      if (liveDelta.isNegative) {
        return _bankedElapsed;
      }
      return _bankedElapsed + liveDelta;
    }
    return _bankedElapsed;
  }

  int get elapsedSeconds => elapsed.inSeconds;

  String get elapsedDisplay => _formatDuration(elapsed);

  void initializeIdleRun(String runId) {
    _runId = runId;
    _state = ProductionState.idle;
    _stageStartedAt = null;
    _bankedElapsed = Duration.zero;
    _currentYield = 0;
    _currentScrap = 0;
    _persistActiveRun(runId);
    notifyListeners();
  }

  /// Restores the last active run id so a hot restart / app relaunch resumes
  /// the run the operator was on instead of dropping to idle.
  Future<void> _restoreActiveRun() async {
    if (_runId != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_activeRunKey);
      if (saved != null && saved.isNotEmpty && _runId == null) {
        _runId = saved;
        _state = ProductionState.idle;
        notifyListeners();
      }
    } catch (_) {
      // Prefs unavailable (e.g. tests) — stay idle.
    }
  }

  Future<void> _persistActiveRun(String? runId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (runId == null || runId.isEmpty) {
        await prefs.remove(_activeRunKey);
      } else {
        await prefs.setString(_activeRunKey, runId);
      }
    } catch (_) {
      // Best-effort; losing the pointer just means a manual reselect.
    }
  }

  /// Records which stage the run-level buffer commits against.
  void setActiveStage(String stageId) {
    if (_stageId == stageId) return;
    _stageId = stageId;
    notifyListeners();
  }

  void startRun({String? runId}) {
    if (runId != null) {
      _runId = runId;
    }
    _runId ??= 'local-${_now().microsecondsSinceEpoch}';
    _state = ProductionState.running;
    _stageStartedAt = _now();
    _persistActiveRun(_runId);
    _startTicker();
    notifyListeners();
  }

  Future<void> pauseRun() async {
    if (_state != ProductionState.running) {
      return;
    }
    _bankElapsed();
    _state = ProductionState.paused;
    _ticker?.cancel();
    notifyListeners();
    await _commitBuffers();
  }

  void resumeRun() {
    if (_state != ProductionState.paused) {
      return;
    }
    _state = ProductionState.running;
    _stageStartedAt = _now();
    _startTicker();
    notifyListeners();
  }

  Future<void> completeStage() async {
    if (_state == ProductionState.completed) {
      return;
    }
    _bankElapsed();
    _state = ProductionState.completed;
    _ticker?.cancel();
    // Forget the active-run pointer so a restart lands on a clean "pick a run"
    // state. The finished run stays viewable through its order (assign pipeline
    // → assigned → production complete). Keep _runId in memory for this session.
    _persistActiveRun(null);
    notifyListeners();

    final committer = _bufferCommitter;
    final runId = _runId;
    final stageId = _stageId;
    if (committer == null || runId == null) {
      return;
    }
    _isCommitting = true;
    notifyListeners();
    try {
      await committer(
        ProductionRunCommit(
          runId: runId,
          stageId: stageId ?? '',
          goodYield: _currentYield,
          setupScrap: _currentScrap,
          state: _state,
        ),
      );
    } on Exception catch (e) {
      if (e is SocketException || e is TimeoutException) {
        final log = OfflineStageLog(
          runId: runId,
          stageId: stageId ?? '',
          payload: {'goodYield': _currentYield, 'setupScrap': _currentScrap},
          createdAt: _now(),
          syncStatus: 'pending',
        );
        await OfflineSyncDbHelper.instance.insertLog(log);
      } else {
        rethrow;
      }
    } finally {
      _isCommitting = false;
      notifyListeners();
    }
  }

  Future<void> completeRun() async {
    await completeStage();
  }

  void incrementYield([int amount = 1]) {
    if (amount <= 0) {
      return;
    }
    _currentYield += amount;
    notifyListeners();
  }

  void decrementYield([int amount = 1]) {
    if (amount <= 0) {
      return;
    }
    _currentYield = (_currentYield - amount).clamp(0, 1 << 31);
    notifyListeners();
  }

  void addScrap([int amount = 1]) {
    if (amount <= 0) {
      return;
    }
    _currentScrap += amount;
    notifyListeners();
  }

  void removeScrap([int amount = 1]) {
    if (amount <= 0) {
      return;
    }
    _currentScrap = (_currentScrap - amount).clamp(0, 1 << 31);
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(_tickInterval, (_) {
      if (_state == ProductionState.running) {
        notifyListeners();
      }
    });
  }

  void _bankElapsed() {
    final startedAt = _stageStartedAt;
    if (startedAt == null) {
      return;
    }
    final delta = _now().difference(startedAt);
    if (!delta.isNegative) {
      _bankedElapsed += delta;
    }
    _stageStartedAt = null;
  }

  Future<void> _commitBuffers() async {
    final committer = _bufferCommitter;
    final runId = _runId;
    if (committer == null || runId == null) {
      return;
    }
    _isCommitting = true;
    notifyListeners();
    try {
      await committer(
        ProductionRunCommit(
          runId: runId,
          stageId: _stageId ?? '',
          goodYield: _currentYield,
          setupScrap: _currentScrap,
          state: _state,
        ),
      );
    } finally {
      _isCommitting = false;
      notifyListeners();
    }
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  void _startOfflineSyncTimer() {
    _offlineSyncTimer?.cancel();
    _offlineSyncTimer = Timer.periodic(
      _offlinePollInterval,
      (_) => _pollOfflineLogs(),
    );
  }

  Future<void> _pollOfflineLogs() async {
    final committer = _bufferCommitter;
    if (committer == null) {
      return;
    }
    try {
      final logs = await OfflineSyncDbHelper.instance.getPendingLogs();
      for (final log in logs) {
        try {
          final commit = ProductionRunCommit(
            runId: log.runId,
            stageId: log.stageId,
            goodYield: log.payload['goodYield'] as int? ?? 0,
            setupScrap: log.payload['setupScrap'] as int? ?? 0,
            state: ProductionState.completed,
          );
          await committer(commit);
          await OfflineSyncDbHelper.instance.deleteLog(log.id!);
        } on Exception catch (e) {
          if (e is SocketException || e is TimeoutException) {
            await OfflineSyncDbHelper.instance.updateLogStatus(
              log.id!,
              'failed',
            );
          }
        }
      }
    } catch (_) {
      // Ignore DB or background errors
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _offlineSyncTimer?.cancel();
    super.dispose();
  }
}
