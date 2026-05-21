import 'dart:async';

import 'package:flutter/foundation.dart';

enum ProductionState { idle, setup, running, paused, completed }

typedef ProductionNow = DateTime Function();
typedef ProductionStatusFetcher =
    Future<ProductionState?> Function(String runId);
typedef ProductionBufferCommitter =
    Future<void> Function(ProductionRunCommit commit);

class ProductionRunCommit {
  const ProductionRunCommit({
    required this.runId,
    required this.goodYield,
    required this.setupScrap,
    required this.state,
  });

  final String runId;
  final int goodYield;
  final int setupScrap;
  final ProductionState state;
}

class ProductionRunProvider extends ChangeNotifier {
  ProductionRunProvider({
    ProductionStatusFetcher? statusFetcher,
    ProductionBufferCommitter? bufferCommitter,
    ProductionNow? now,
    Duration tickInterval = const Duration(seconds: 1),
    Duration syncInterval = const Duration(seconds: 5),
  }) : _statusFetcher = statusFetcher,
       _bufferCommitter = bufferCommitter,
       _now = now ?? DateTime.now,
       _tickInterval = tickInterval,
       _syncInterval = syncInterval;

  final ProductionStatusFetcher? _statusFetcher;
  final ProductionBufferCommitter? _bufferCommitter;
  final ProductionNow _now;
  final Duration _tickInterval;
  final Duration _syncInterval;

  ProductionState _state = ProductionState.idle;
  String? _runId;
  DateTime? _stageStartedAt;
  Duration _bankedElapsed = Duration.zero;
  int _currentYield = 0;
  int _currentScrap = 0;
  bool _isInputLocked = false;
  bool _isCommitting = false;
  Timer? _ticker;
  Timer? _serverSync;

  ProductionState get state => _state;
  String? get runId => _runId;
  DateTime? get stageStartedAt => _stageStartedAt;
  int get goodYield => _currentYield;
  int get setupScrap => _currentScrap;
  bool get isInputLocked => _isInputLocked;
  bool get isCommitting => _isCommitting;
  bool get isIdle => _state == ProductionState.idle;
  bool get isSetup => _state == ProductionState.setup;
  bool get isRunning => _state == ProductionState.running;
  bool get isPaused => _state == ProductionState.paused;
  bool get isCompleted => _state == ProductionState.completed;

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

  void enterSetup(String runId) {
    _runId = runId;
    _state = ProductionState.setup;
    _stageStartedAt = null;
    _bankedElapsed = Duration.zero;
    _currentYield = 0;
    _currentScrap = 0;
    _isInputLocked = false;
    _startServerSync();
    notifyListeners();
  }

  void startRun({String? runId}) {
    if (runId != null) {
      _runId = runId;
    }
    _runId ??= 'local-${_now().microsecondsSinceEpoch}';
    _state = ProductionState.running;
    _isInputLocked = false;
    _stageStartedAt = _now();
    _startTicker();
    _startServerSync();
    notifyListeners();
  }

  Future<void> pauseRun({bool remote = false}) async {
    if (_state != ProductionState.running) {
      return;
    }
    _bankElapsed();
    _state = ProductionState.paused;
    _isInputLocked = remote;
    _ticker?.cancel();
    notifyListeners();
    await _commitBuffers();
  }

  void resumeRun() {
    if (_state != ProductionState.paused || _isInputLocked) {
      return;
    }
    _state = ProductionState.running;
    _stageStartedAt = _now();
    _startTicker();
    notifyListeners();
  }

  Future<void> completeRun() async {
    if (_state == ProductionState.completed) {
      return;
    }
    _bankElapsed();
    _state = ProductionState.completed;
    _isInputLocked = true;
    _ticker?.cancel();
    _serverSync?.cancel();
    notifyListeners();
    await _commitBuffers();
  }

  void incrementYield([int amount = 1]) {
    if (_isInputLocked || amount <= 0) {
      return;
    }
    _currentYield += amount;
    notifyListeners();
  }

  void decrementYield([int amount = 1]) {
    if (_isInputLocked || amount <= 0) {
      return;
    }
    _currentYield = (_currentYield - amount).clamp(0, 1 << 31);
    notifyListeners();
  }

  void addScrap([int amount = 1]) {
    if (_isInputLocked || amount <= 0) {
      return;
    }
    _currentScrap += amount;
    notifyListeners();
  }

  void removeScrap([int amount = 1]) {
    if (_isInputLocked || amount <= 0) {
      return;
    }
    _currentScrap = (_currentScrap - amount).clamp(0, 1 << 31);
    notifyListeners();
  }

  @visibleForTesting
  Future<void> syncOnce() => _syncFromServer();

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(_tickInterval, (_) {
      if (_state == ProductionState.running) {
        notifyListeners();
      }
    });
  }

  void _startServerSync() {
    _serverSync?.cancel();
    if (_statusFetcher == null || _runId == null) {
      return;
    }
    _serverSync = Timer.periodic(_syncInterval, (_) => _syncFromServer());
  }

  Future<void> _syncFromServer() async {
    final fetcher = _statusFetcher;
    final runId = _runId;
    if (fetcher == null || runId == null) {
      return;
    }
    final remoteState = await fetcher(runId);
    if (remoteState == null || remoteState == _state) {
      return;
    }

    switch (remoteState) {
      case ProductionState.paused:
        if (_state == ProductionState.running) {
          await pauseRun(remote: true);
        } else {
          _state = ProductionState.paused;
          _isInputLocked = true;
          _ticker?.cancel();
          notifyListeners();
        }
      case ProductionState.running:
        if (_state == ProductionState.paused && !_isInputLocked) {
          resumeRun();
        } else if (_state != ProductionState.running) {
          _state = ProductionState.running;
          _isInputLocked = false;
          _stageStartedAt = _now();
          _startTicker();
          notifyListeners();
        }
      case ProductionState.completed:
        await completeRun();
      case ProductionState.setup:
        _state = ProductionState.setup;
        _isInputLocked = false;
        _ticker?.cancel();
        notifyListeners();
      case ProductionState.idle:
        _state = ProductionState.idle;
        _isInputLocked = false;
        _ticker?.cancel();
        notifyListeners();
    }
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

  @override
  void dispose() {
    _ticker?.cancel();
    _serverSync?.cancel();
    super.dispose();
  }
}
