import 'dart:async';

import 'package:flutter/material.dart';

enum ProductionRunPhase {
  idle,
  verifyingSetup,
  setupVerified,
  running,
  paused,
  loggingClosure,
  closed,
}

class ProductionSetupException implements Exception {
  const ProductionSetupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PipelineBlueprint {
  const PipelineBlueprint({
    required this.id,
    required this.name,
    required this.stages,
  });

  final String id;
  final String name;
  final List<PipelineStage> stages;

  PipelineBlueprint copyWith({
    String? id,
    String? name,
    List<PipelineStage>? stages,
  }) {
    return PipelineBlueprint(
      id: id ?? this.id,
      name: name ?? this.name,
      stages: stages ?? this.stages,
    );
  }
}

class PipelineStage {
  const PipelineStage({
    required this.id,
    required this.name,
    required this.machineId,
    required this.dieId,
    required this.inputMaterial,
    required this.machineAction,
    required this.outputMaterial,
    required this.scrapPolicy,
    required this.targetOutputUnits,
  });

  final String id;
  final String name;
  final String machineId;
  final String dieId;
  final String inputMaterial;
  final String machineAction;
  final String outputMaterial;
  final String scrapPolicy;
  final int targetOutputUnits;

  PipelineStage copyWith({
    String? id,
    String? name,
    String? machineId,
    String? dieId,
    String? inputMaterial,
    String? machineAction,
    String? outputMaterial,
    String? scrapPolicy,
    int? targetOutputUnits,
  }) {
    return PipelineStage(
      id: id ?? this.id,
      name: name ?? this.name,
      machineId: machineId ?? this.machineId,
      dieId: dieId ?? this.dieId,
      inputMaterial: inputMaterial ?? this.inputMaterial,
      machineAction: machineAction ?? this.machineAction,
      outputMaterial: outputMaterial ?? this.outputMaterial,
      scrapPolicy: scrapPolicy ?? this.scrapPolicy,
      targetOutputUnits: targetOutputUnits ?? this.targetOutputUnits,
    );
  }
}

class ActiveProductionRun {
  const ActiveProductionRun({
    required this.id,
    required this.blueprintId,
    required this.phase,
    required this.logs,
    required this.startedAt,
    this.closedAt,
  });

  final String id;
  final String blueprintId;
  final ProductionRunPhase phase;
  final List<StageExecutionLog> logs;
  final DateTime startedAt;
  final DateTime? closedAt;

  ActiveProductionRun copyWith({
    String? id,
    String? blueprintId,
    ProductionRunPhase? phase,
    List<StageExecutionLog>? logs,
    DateTime? startedAt,
    DateTime? closedAt,
  }) {
    return ActiveProductionRun(
      id: id ?? this.id,
      blueprintId: blueprintId ?? this.blueprintId,
      phase: phase ?? this.phase,
      logs: logs ?? this.logs,
      startedAt: startedAt ?? this.startedAt,
      closedAt: closedAt ?? this.closedAt,
    );
  }
}

class StageExecutionLog {
  const StageExecutionLog({
    required this.stageId,
    required this.machineId,
    required this.dieId,
    required this.startedAt,
    this.completedAt,
    this.goodYieldCount = 0,
    this.scrapWeightKg = 0,
  });

  final String stageId;
  final String machineId;
  final String dieId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final int goodYieldCount;
  final double scrapWeightKg;

  StageExecutionLog copyWith({
    String? stageId,
    String? machineId,
    String? dieId,
    DateTime? startedAt,
    DateTime? completedAt,
    int? goodYieldCount,
    double? scrapWeightKg,
  }) {
    return StageExecutionLog(
      stageId: stageId ?? this.stageId,
      machineId: machineId ?? this.machineId,
      dieId: dieId ?? this.dieId,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      goodYieldCount: goodYieldCount ?? this.goodYieldCount,
      scrapWeightKg: scrapWeightKg ?? this.scrapWeightKg,
    );
  }
}

class MaterialLedgerPreview {
  const MaterialLedgerPreview({
    required this.parentReelStockKg,
    required this.wipBoardLotUnits,
    required this.coreShreddingScrapKg,
  });

  final double parentReelStockKg;
  final int wipBoardLotUnits;
  final double coreShreddingScrapKg;

  List<String> get lines => [
    'Parent Reel Stock: ${_signedKg(parentReelStockKg)}',
    'WIP Board Lot: ${_signedUnits(wipBoardLotUnits)}',
    'Core Shredding Scrap: ${_signedKg(coreShreddingScrapKg)}',
  ];

  List<String> get diffLines => [
    '- STOCK_REEL_8821       [ ${parentReelStockKg.abs().toStringAsFixed(2).padLeft(6)} Kg ]  (Consumed)',
    '+ WIP_BOARD_LOT_B42     [ ${_formatInt(wipBoardLotUnits.abs()).padLeft(5)} Pcs ]  (Produced)',
    '+ SCRAP_SHRED_CORE      [ ${coreShreddingScrapKg.abs().toStringAsFixed(2).padLeft(6)} Kg ]  (Wastage)',
  ];

  static String _signedKg(double value) {
    final sign = value >= 0 ? '+' : '-';
    return '$sign${value.abs().toStringAsFixed(2)} Kg';
  }

  static String _signedUnits(int value) {
    final sign = value >= 0 ? '+' : '-';
    return '$sign${_formatInt(value.abs())} Units';
  }

  static String _formatInt(int value) {
    final text = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i += 1) {
      final fromEnd = text.length - i;
      buffer.write(text[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }
}

class StageDraftControllerPool {
  StageDraftControllerPool(PipelineStage stage)
    : name = TextEditingController(text: stage.name),
      machineId = TextEditingController(text: stage.machineId),
      dieId = TextEditingController(text: stage.dieId),
      inputMaterial = TextEditingController(text: stage.inputMaterial),
      machineAction = TextEditingController(text: stage.machineAction),
      outputMaterial = TextEditingController(text: stage.outputMaterial),
      scrapPolicy = TextEditingController(text: stage.scrapPolicy),
      targetOutputUnits = TextEditingController(
        text: stage.targetOutputUnits.toString(),
      );

  final TextEditingController name;
  final TextEditingController machineId;
  final TextEditingController dieId;
  final TextEditingController inputMaterial;
  final TextEditingController machineAction;
  final TextEditingController outputMaterial;
  final TextEditingController scrapPolicy;
  final TextEditingController targetOutputUnits;

  PipelineStage toStage(PipelineStage current) {
    return current.copyWith(
      name: name.text.trim().isEmpty ? current.name : name.text.trim(),
      machineId: machineId.text.trim().isEmpty
          ? current.machineId
          : machineId.text.trim(),
      dieId: dieId.text.trim().isEmpty ? current.dieId : dieId.text.trim(),
      inputMaterial: inputMaterial.text.trim().isEmpty
          ? current.inputMaterial
          : inputMaterial.text.trim(),
      machineAction: machineAction.text.trim().isEmpty
          ? current.machineAction
          : machineAction.text.trim(),
      outputMaterial: outputMaterial.text.trim().isEmpty
          ? current.outputMaterial
          : outputMaterial.text.trim(),
      scrapPolicy: scrapPolicy.text.trim().isEmpty
          ? current.scrapPolicy
          : scrapPolicy.text.trim(),
      targetOutputUnits:
          int.tryParse(targetOutputUnits.text.trim()) ??
          current.targetOutputUnits,
    );
  }

  void dispose() {
    name.dispose();
    machineId.dispose();
    dieId.dispose();
    inputMaterial.dispose();
    machineAction.dispose();
    outputMaterial.dispose();
    scrapPolicy.dispose();
    targetOutputUnits.dispose();
  }
}

class ProductionProvider extends ChangeNotifier {
  ProductionProvider({required PipelineBlueprint blueprint})
    : _blueprint = blueprint {
    if (blueprint.stages.isNotEmpty) {
      _selectedStageId = blueprint.stages.first.id;
    }
    for (final stage in blueprint.stages) {
      _draftPools[stage.id] = StageDraftControllerPool(stage);
    }
  }

  factory ProductionProvider.seeded() {
    return ProductionProvider(
      blueprint: const PipelineBlueprint(
        id: 'paper-board-high-throughput',
        name: 'Paper Board High Throughput Line',
        stages: [
          PipelineStage(
            id: 'stage-slitting',
            name: 'Reel Slitting',
            machineId: 'MC-SLIT-01',
            dieId: 'DIE-1450-A',
            inputMaterial: 'Parent kraft reel, 510 Kg',
            machineAction: 'Slit parent reel into board-width webs',
            outputMaterial: 'WIP board lot',
            scrapPolicy: 'Setup trim and edge dust routed to core shredding',
            targetOutputUnits: 4850,
          ),
          PipelineStage(
            id: 'stage-punching',
            name: 'Die Punching',
            machineId: 'MC-PUNCH-03',
            dieId: 'DIE-CARTON-22',
            inputMaterial: 'WIP board lot',
            machineAction: 'Punch blanks using locked die settings',
            outputMaterial: 'Carton blank stack',
            scrapPolicy: 'Punch skeleton scrap weighed by bin',
            targetOutputUnits: 4700,
          ),
          PipelineStage(
            id: 'stage-folding',
            name: 'Folding + Glue',
            machineId: 'MC-FOLD-02',
            dieId: 'DIE-GLUE-08',
            inputMaterial: 'Carton blank stack',
            machineAction: 'Fold, glue, count, and bundle finished output',
            outputMaterial: 'Finished carton bundles',
            scrapPolicy: 'Rejected setup bundles logged as production scrap',
            targetOutputUnits: 4600,
          ),
        ],
      ),
    );
  }

  String _activeOperator = 'FLOOR-ADMIN';
  PipelineBlueprint _blueprint;
  ActiveProductionRun? _activeRun;
  ProductionRunPhase _phase = ProductionRunPhase.idle;
  String? _selectedStageId;
  String? _currentMachineId;
  String? _currentDieId;
  DateTime? _stageStartedAt;
  Duration _bankedElapsed = Duration.zero;
  int _goodYieldCount = 0;
  double _scrapWeightKg = 0;
  double _parentReelConsumedKg = 510;
  String? _validationErrorMessage;
  PipelineStage? _lastDeletedStage;
  int? _lastDeletedIndex;
  Timer? _clock;
  final Map<String, StageDraftControllerPool> _draftPools = {};

  String get activeOperator => _activeOperator;

  void switchOperator(String operator) {
    _activeOperator = operator.trim().isEmpty
        ? 'FLOOR-ADMIN'
        : operator.trim().toUpperCase();
    notifyListeners();
  }

  PipelineBlueprint get blueprint => _blueprint;
  ActiveProductionRun? get activeRun => _activeRun;
  ProductionRunPhase get phase => _phase;
  String? get selectedStageId => _selectedStageId;
  String? get currentMachineId => _currentMachineId;
  String? get currentDieId => _currentDieId;
  int get elapsedSeconds => _currentElapsed.inSeconds;
  int get goodYieldCount => _goodYieldCount;
  double get scrapWeightKg => _scrapWeightKg;
  double get parentReelConsumedKg => _parentReelConsumedKg;
  String? get validationErrorMessage => _validationErrorMessage;
  bool get hasUndoDelete =>
      _lastDeletedStage != null && _lastDeletedIndex != null;

  bool get isIdle => _phase == ProductionRunPhase.idle;
  bool get isVerifyingSetup => _phase == ProductionRunPhase.verifyingSetup;
  bool get isRunning => _phase == ProductionRunPhase.running;
  bool get isPaused => _phase == ProductionRunPhase.paused;
  bool get isLoggingClosure => _phase == ProductionRunPhase.loggingClosure;

  PipelineStage? get selectedStage {
    final selectedId = _selectedStageId;
    if (selectedId == null) {
      return null;
    }
    return _blueprint.stages
        .where((stage) => stage.id == selectedId)
        .firstOrNull;
  }

  StageDraftControllerPool? draftFor(String stageId) => _draftPools[stageId];

  MaterialLedgerPreview get ledgerPreview => MaterialLedgerPreview(
    parentReelStockKg: -_parentReelConsumedKg,
    wipBoardLotUnits: _goodYieldCount,
    coreShreddingScrapKg: _scrapWeightKg,
  );

  String get formattedElapsed {
    final totalSeconds = _currentElapsed.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Duration get _currentElapsed {
    final startedAt = _stageStartedAt;
    if (isRunning && startedAt != null) {
      final liveDelta = DateTime.now().difference(startedAt);
      if (liveDelta.isNegative) {
        return _bankedElapsed;
      }
      return _bankedElapsed + liveDelta;
    }
    return _bankedElapsed;
  }

  void selectStage(String stageId) {
    if (_selectedStageId == stageId) {
      return;
    }
    final nextStage = _blueprint.stages
        .where((stage) => stage.id == stageId)
        .firstOrNull;
    if (nextStage == null) {
      return;
    }
    _selectedStageId = stageId;
    _validationErrorMessage = null;
    if (!isRunning && !isPaused && !isLoggingClosure) {
      final setupMatchesStage =
          _currentMachineId == nextStage.machineId &&
          _currentDieId == nextStage.dieId;
      if (!setupMatchesStage) {
        _phase = ProductionRunPhase.idle;
        _currentMachineId = null;
        _currentDieId = null;
      }
    }
    notifyListeners();
  }

  PipelineStage appendStage() {
    final nextNumber = _blueprint.stages.length + 1;
    final stage = PipelineStage(
      id: 'stage-${DateTime.now().microsecondsSinceEpoch}',
      name: 'Production Step $nextNumber',
      machineId: 'MC-NEW-$nextNumber',
      dieId: 'DIE-NEW-$nextNumber',
      inputMaterial: 'Input material',
      machineAction: 'Machine action',
      outputMaterial: 'Target output',
      scrapPolicy: 'Setup scrap weighed and logged',
      targetOutputUnits: 1000,
    );
    _blueprint = _blueprint.copyWith(stages: [..._blueprint.stages, stage]);
    _draftPools[stage.id] = StageDraftControllerPool(stage);
    _selectedStageId = stage.id;
    notifyListeners();
    return stage;
  }

  PipelineStage? deleteSelectedStage() {
    final selectedId = _selectedStageId;
    if (selectedId == null || _blueprint.stages.length <= 1) {
      return null;
    }
    final index = _blueprint.stages.indexWhere(
      (stage) => stage.id == selectedId,
    );
    if (index == -1) {
      return null;
    }
    final removed = _blueprint.stages[index];
    final updated = [..._blueprint.stages]..removeAt(index);
    _lastDeletedStage = removed;
    _lastDeletedIndex = index;
    _draftPools.remove(removed.id)?.dispose();
    _blueprint = _blueprint.copyWith(stages: updated);
    _selectedStageId = updated[index.clamp(0, updated.length - 1)].id;
    notifyListeners();
    return removed;
  }

  void reorderStages(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _blueprint.stages.length) return;
    if (newIndex < 0 || newIndex > _blueprint.stages.length) return;

    final stages = [..._blueprint.stages];
    final item = stages.removeAt(oldIndex);
    var targetIndex = newIndex;
    if (oldIndex < targetIndex) {
      targetIndex -= 1;
    }
    stages.insert(targetIndex, item);
    _blueprint = _blueprint.copyWith(stages: stages);
    notifyListeners();
  }

  void undoLastStageDelete() {
    final stage = _lastDeletedStage;
    final index = _lastDeletedIndex;
    if (stage == null || index == null) {
      return;
    }
    final updated = [..._blueprint.stages];
    updated.insert(index.clamp(0, updated.length), stage);
    _blueprint = _blueprint.copyWith(stages: updated);
    _draftPools[stage.id] = StageDraftControllerPool(stage);
    _selectedStageId = stage.id;
    _lastDeletedStage = null;
    _lastDeletedIndex = null;
    notifyListeners();
  }

  void saveStageDraft(String stageId) {
    final draft = _draftPools[stageId];
    if (draft == null) {
      return;
    }
    final updatedStages = _blueprint.stages
        .map((stage) {
          if (stage.id != stageId) {
            return stage;
          }
          return draft.toStage(stage);
        })
        .toList(growable: false);
    _blueprint = _blueprint.copyWith(stages: updatedStages);
    notifyListeners();
  }

  void verifyAssetSetup(String scannedMachineCode, String scannedDieCode) {
    final stage = selectedStage;
    if (stage == null) {
      throw const ProductionSetupException('Select a production step first.');
    }

    _phase = ProductionRunPhase.verifyingSetup;
    _validationErrorMessage = null;
    notifyListeners();

    final scannedMachineId = _normalizeAssetCode(scannedMachineCode);
    final scannedDieId = _normalizeAssetCode(scannedDieCode);
    final expectedMachineId = _normalizeAssetCode(stage.machineId);
    final expectedDieId = _normalizeAssetCode(stage.dieId);

    if (scannedMachineId != expectedMachineId) {
      _validationErrorMessage =
          'Machine lock-key mismatch. Expected ${stage.machineId}, scanned $scannedMachineCode.';
      _phase = ProductionRunPhase.idle;
      notifyListeners();
      throw ProductionSetupException(_validationErrorMessage!);
    }

    if (scannedDieId != expectedDieId) {
      _validationErrorMessage =
          'Die lock-key mismatch. Expected ${stage.dieId}, scanned $scannedDieCode.';
      _phase = ProductionRunPhase.idle;
      notifyListeners();
      throw ProductionSetupException(_validationErrorMessage!);
    }

    _currentMachineId = stage.machineId;
    _currentDieId = stage.dieId;
    _phase = ProductionRunPhase.setupVerified;
    notifyListeners();
  }

  void startRun() {
    final stage = selectedStage;
    if (stage == null) {
      return;
    }
    if (_phase != ProductionRunPhase.setupVerified ||
        _currentMachineId != stage.machineId ||
        _currentDieId != stage.dieId) {
      _validationErrorMessage =
          'Verify the machine and die lock-key setup before starting.';
      notifyListeners();
      return;
    }
    final now = DateTime.now();
    final log = StageExecutionLog(
      stageId: stage.id,
      machineId: _currentMachineId ?? stage.machineId,
      dieId: _currentDieId ?? stage.dieId,
      startedAt: now,
    );
    _activeRun = ActiveProductionRun(
      id: 'run-${now.microsecondsSinceEpoch}',
      blueprintId: _blueprint.id,
      phase: ProductionRunPhase.running,
      logs: [log],
      startedAt: now,
    );
    _phase = ProductionRunPhase.running;
    _bankedElapsed = Duration.zero;
    _stageStartedAt = now;
    _validationErrorMessage = null;
    _startClock();
    notifyListeners();
  }

  void pauseRun() {
    if (!isRunning) {
      return;
    }
    _bankElapsed();
    _phase = ProductionRunPhase.paused;
    _activeRun = _activeRun?.copyWith(phase: _phase);
    _clock?.cancel();
    notifyListeners();
  }

  void resumeRun() {
    if (!isPaused) {
      return;
    }
    _phase = ProductionRunPhase.running;
    _stageStartedAt = DateTime.now();
    _activeRun = _activeRun?.copyWith(phase: _phase);
    _startClock();
    notifyListeners();
  }

  void beginClosure() {
    if (!isRunning && !isPaused) {
      return;
    }
    _bankElapsed();
    _phase = ProductionRunPhase.loggingClosure;
    _activeRun = _activeRun?.copyWith(phase: _phase);
    _clock?.cancel();
    notifyListeners();
  }

  void cancelClosure() {
    if (!isLoggingClosure) {
      return;
    }
    _phase = ProductionRunPhase.paused;
    _activeRun = _activeRun?.copyWith(phase: _phase);
    notifyListeners();
  }

  void updateClosureValues({
    double? parentReelConsumedKg,
    int? goodYieldCount,
    double? scrapWeightKg,
  }) {
    _parentReelConsumedKg = (parentReelConsumedKg ?? _parentReelConsumedKg)
        .clamp(0, double.infinity);
    _goodYieldCount = (goodYieldCount ?? _goodYieldCount).clamp(0, 999999999);
    _scrapWeightKg = (scrapWeightKg ?? _scrapWeightKg).clamp(
      0,
      double.infinity,
    );
    notifyListeners();
  }

  void commitClosure() {
    final run = _activeRun;
    if (run == null) {
      return;
    }
    final logs = run.logs.isEmpty
        ? run.logs
        : [
            ...run.logs.take(run.logs.length - 1),
            run.logs.last.copyWith(
              completedAt: DateTime.now(),
              goodYieldCount: _goodYieldCount,
              scrapWeightKg: _scrapWeightKg,
            ),
          ];
    _phase = ProductionRunPhase.closed;
    _activeRun = run.copyWith(
      phase: _phase,
      logs: logs,
      closedAt: DateTime.now(),
    );
    _stageStartedAt = null;
    _clock?.cancel();
    notifyListeners();
  }

  void resetRun() {
    _clock?.cancel();
    _activeRun = null;
    _phase = ProductionRunPhase.idle;
    _currentMachineId = null;
    _currentDieId = null;
    _stageStartedAt = null;
    _bankedElapsed = Duration.zero;
    _goodYieldCount = 0;
    _scrapWeightKg = 0;
    _validationErrorMessage = null;
    notifyListeners();
  }

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isRunning) {
        notifyListeners();
      }
    });
  }

  void _bankElapsed() {
    final startedAt = _stageStartedAt;
    if (startedAt == null) {
      return;
    }
    final delta = DateTime.now().difference(startedAt);
    if (!delta.isNegative) {
      _bankedElapsed += delta;
    }
    _stageStartedAt = null;
  }

  String _normalizeAssetCode(String value) {
    final upper = value.trim().toUpperCase();
    if (upper.contains(':')) {
      return upper.split(':').last.trim();
    }
    if (upper.contains('|')) {
      return upper.split('|').last.trim();
    }
    return upper;
  }

  @override
  void dispose() {
    _clock?.cancel();
    for (final draft in _draftPools.values) {
      draft.dispose();
    }
    super.dispose();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
