import 'dart:async';

import 'package:flutter/material.dart';

import '../../production_pipelines/domain/pipeline_template.dart';
import '../../production_pipelines/domain/process_node.dart';
import '../../production_pipelines/domain/material_flow.dart';

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

class ActiveProductionRun {
  const ActiveProductionRun({
    required this.id,
    required this.templateId,
    required this.phase,
    required this.logs,
    required this.startedAt,
    this.closedAt,
  });

  final String id;
  final String templateId;
  final ProductionRunPhase phase;
  final List<NodeExecutionLog> logs;
  final DateTime startedAt;
  final DateTime? closedAt;

  ActiveProductionRun copyWith({
    String? id,
    String? templateId,
    ProductionRunPhase? phase,
    List<NodeExecutionLog>? logs,
    DateTime? startedAt,
    DateTime? closedAt,
  }) {
    return ActiveProductionRun(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      phase: phase ?? this.phase,
      logs: logs ?? this.logs,
      startedAt: startedAt ?? this.startedAt,
      closedAt: closedAt ?? this.closedAt,
    );
  }
}

class NodeExecutionLog {
  const NodeExecutionLog({
    required this.nodeId,
    required this.machineId,
    required this.dieId,
    required this.startedAt,
    this.completedAt,
    this.goodYieldCount = 0,
    this.scrapWeightKg = 0,
  });

  final String nodeId;
  final String machineId;
  final String dieId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final int goodYieldCount;
  final double scrapWeightKg;

  NodeExecutionLog copyWith({
    String? nodeId,
    String? machineId,
    String? dieId,
    DateTime? startedAt,
    DateTime? completedAt,
    int? goodYieldCount,
    double? scrapWeightKg,
  }) {
    return NodeExecutionLog(
      nodeId: nodeId ?? this.nodeId,
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
    this.producedItemName = 'WIP_BOARD_LOT_B42',
    this.lotNumber = 1,
  });

  final double parentReelStockKg;
  final int wipBoardLotUnits;
  final double coreShreddingScrapKg;
  final String producedItemName;
  final int lotNumber;

  List<String> get lines => [
    'Parent Reel Stock: ${_signedKg(parentReelStockKg)}',
    'WIP Board Lot: ${_signedUnits(wipBoardLotUnits)}',
    'Core Shredding Scrap: ${_signedKg(coreShreddingScrapKg)}',
  ];

  List<String> get diffLines => [
    '- STOCK_REEL_8821       [ ${parentReelStockKg.abs().toStringAsFixed(2).padLeft(6)} Kg ]  (Consumed)',
    '+ ${producedItemName}_$lotNumber     [ ${_formatInt(wipBoardLotUnits.abs()).padLeft(5)} Pcs ]  (Produced)',
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

class ProductionProvider extends ChangeNotifier {
  ProductionProvider({required PipelineTemplate template})
    : _template = template {
    if (template.nodes.isNotEmpty) {
      _selectedNodeId = template.nodes.first.id;
    }
  }

  factory ProductionProvider.seeded() {
    return ProductionProvider(
      template: const PipelineTemplate(
        id: 'paper-board-high-throughput',
        shopFloorId: 'mock-floor',
        name: 'Mock Pipeline',
        description: 'For testing',
        stageLabels: ['Stage 1', 'Stage 2', 'Stage 3'],
        laneLabels: ['Main'],
        nodes: [
          ProcessNode(
            id: 'stage-slitting',
            name: 'Reel Slitting',
            processType: 'Slitting',
            stageIndex: 0,
            laneIndex: 0,
            inputs: [],
            outputs: [],
            machine: 'MC-SLIT-01',
            dieId: 'DIE-1450-A',
            durationHours: 1,
            status: 'queued',
            isIntermediate: false,
          ),
          ProcessNode(
            id: 'stage-punching',
            name: 'Die Punching',
            processType: 'Punching',
            stageIndex: 1,
            laneIndex: 0,
            inputs: [],
            outputs: [],
            machine: 'MC-PUNCH-03',
            dieId: 'DIE-CARTON-22',
            durationHours: 1,
            status: 'queued',
            isIntermediate: false,
          ),
          ProcessNode(
            id: 'stage-folding',
            name: 'Folding + Glue',
            processType: 'Folding',
            stageIndex: 2,
            laneIndex: 0,
            inputs: [],
            outputs: [],
            machine: 'MC-FOLD-02',
            dieId: 'DIE-GLUE-08',
            durationHours: 1,
            status: 'queued',
            isIntermediate: false,
          ),
        ],
        flows: [],
      ),
    );
  }

  String _activeOperator = 'FLOOR-ADMIN';
  PipelineTemplate _template;
  PipelineTemplate? _workingTemplate;
  ActiveProductionRun? _activeRun;
  ProductionRunPhase _phase = ProductionRunPhase.idle;
  String? _selectedNodeId;
  String? _currentMachineId;
  String? _currentDieId;
  DateTime? _nodeStartedAt;
  Duration _bankedElapsed = Duration.zero;
  int _goodYieldCount = 0;
  double _scrapWeightKg = 0;
  double _parentReelConsumedKg = 510;
  String? _validationErrorMessage;

  String get activeOperator => _activeOperator;

  void switchOperator(String operator) {
    _activeOperator = operator.trim().isEmpty
        ? 'FLOOR-ADMIN'
        : operator.trim().toUpperCase();
    notifyListeners();
  }

  PipelineTemplate get template => _workingTemplate ?? _template;
  PipelineTemplate get blueprint => _template;
  ProcessNode? get selectedStage => selectedNode;
  ActiveProductionRun? get activeRun => _activeRun;
  ProductionRunPhase get phase => _phase;
  String? get selectedNodeId => _selectedNodeId;
  String? get currentMachineId => _currentMachineId;
  String? get currentDieId => _currentDieId;
  DateTime? get nodeStartedAt => _nodeStartedAt;
  int? get linkedOrderId => template.linkedOrderId;
  String? get linkedOrderNo => template.linkedOrderNo;
  String? get linkedClientName => template.linkedClientName;
  int get elapsedSeconds => _currentElapsed.inSeconds;
  int get goodYieldCount => _goodYieldCount;
  double get scrapWeightKg => _scrapWeightKg;
  double get parentReelConsumedKg => _parentReelConsumedKg;
  String? get validationErrorMessage => _validationErrorMessage;

  bool get isIdle => _phase == ProductionRunPhase.idle;
  bool get isVerifyingSetup => _phase == ProductionRunPhase.verifyingSetup;
  bool get isRunning => _phase == ProductionRunPhase.running;
  bool get isPaused => _phase == ProductionRunPhase.paused;
  bool get isLoggingClosure => _phase == ProductionRunPhase.loggingClosure;

  ProcessNode? get selectedNode {
    final selectedId = _selectedNodeId;
    if (selectedId == null) {
      return null;
    }
    return template.nodes.where((node) => node.id == selectedId).firstOrNull;
  }

  int _currentLotNumber = 1;

  MaterialLedgerPreview get ledgerPreview {
    final node = selectedNode;
    final producedItemName =
        node?.outputItem?.itemName ?? node?.outputs.firstOrNull ?? 'WIP_LOT';
    return MaterialLedgerPreview(
      parentReelStockKg: -_parentReelConsumedKg,
      wipBoardLotUnits: _goodYieldCount,
      coreShreddingScrapKg: _scrapWeightKg,
      producedItemName: producedItemName,
      lotNumber: _currentLotNumber,
    );
  }

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
    final startedAt = _nodeStartedAt;
    if (isRunning && startedAt != null) {
      final liveDelta = DateTime.now().difference(startedAt);
      if (liveDelta.isNegative) {
        return _bankedElapsed;
      }
      return _bankedElapsed + liveDelta;
    }
    return _bankedElapsed;
  }

  void loadTemplate(
    PipelineTemplate newTemplate, {
    int? orderId,
    String? orderNo,
    String? clientName,
  }) {
    if (newTemplate.id.isEmpty && newTemplate.name.isEmpty) return;

    final stampedTemplate = newTemplate.copyWith(
      linkedOrderId: orderId ?? newTemplate.linkedOrderId,
      linkedOrderNo: orderNo ?? newTemplate.linkedOrderNo,
      linkedClientName: clientName ?? newTemplate.linkedClientName,
    );

    _template = stampedTemplate;
    _workingTemplate = stampedTemplate.copyWith(
      id: 'run-${DateTime.now().microsecondsSinceEpoch}',
      name: '${stampedTemplate.name} (Active Run)',
      status: PipelineTemplateStatus.draft,
    );
    if (stampedTemplate.nodes.isNotEmpty) {
      _selectedNodeId = stampedTemplate.nodes.first.id;
    } else {
      _selectedNodeId = null;
    }
    _phase = ProductionRunPhase.idle;
    _currentMachineId = null;
    _currentDieId = null;
    _validationErrorMessage = null;
    notifyListeners();
  }

  void clearNodeSelection() {
    _selectedNodeId = null;
    notifyListeners();
  }

  void selectNode(String nodeId) {
    if (_selectedNodeId == nodeId) {
      return;
    }
    final nextNode = template.nodes
        .where((node) => node.id == nodeId)
        .firstOrNull;
    if (nextNode == null) {
      return;
    }
    _selectedNodeId = nodeId;
    _validationErrorMessage = null;
    if (!isRunning && !isPaused && !isLoggingClosure) {
      final setupMatchesNode =
          _currentMachineId == nextNode.machineAssignmentLabel &&
          _currentDieId == nextNode.dieId;
      if (!setupMatchesNode) {
        _phase = ProductionRunPhase.idle;
        _currentMachineId = null;
        _currentDieId = null;
      }
    }
    notifyListeners();
  }

  void beginSetup() {
    final node = selectedNode;
    if (node == null) {
      throw const ProductionSetupException('No active process node selected.');
    }
    _phase = ProductionRunPhase.verifyingSetup;
    _validationErrorMessage = null;
    notifyListeners();
  }

  void verifyAssetSetup(String scannedMachineCode, String scannedDieCode) {
    final node = selectedNode;
    if (node == null) {
      throw const ProductionSetupException('Select a production step first.');
    }

    _phase = ProductionRunPhase.verifyingSetup;
    _validationErrorMessage = null;
    notifyListeners();

    final scannedMachineId = _normalizeAssetCode(scannedMachineCode);
    final scannedDieId = _normalizeAssetCode(scannedDieCode);
    final expectedMachineId = _normalizeAssetCode(node.machine);
    final expectedDieId = _normalizeAssetCode(node.dieId);

    if (node.machine.trim().isNotEmpty &&
        scannedMachineId != expectedMachineId) {
      _validationErrorMessage =
          'Machine lock-key mismatch. Expected ${node.machine}, scanned $scannedMachineCode.';
      _phase = ProductionRunPhase.idle;
      notifyListeners();
      throw ProductionSetupException(_validationErrorMessage!);
    }

    if (node.dieId.isNotEmpty && scannedDieId != expectedDieId) {
      _validationErrorMessage =
          'Die lock-key mismatch. Expected ${node.dieId}, scanned $scannedDieCode.';
      _phase = ProductionRunPhase.idle;
      notifyListeners();
      throw ProductionSetupException(_validationErrorMessage!);
    }

    _currentMachineId = node.machineAssignmentLabel;
    _currentDieId = node.dieId;
    _phase = ProductionRunPhase.setupVerified;
    _validationErrorMessage = null;
    notifyListeners();
  }

  void verifySetup(String scannedMachineId, String scannedDieId) {
    try {
      verifyAssetSetup(scannedMachineId, scannedDieId);
    } catch (_) {}
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

  void selectStage(String stageId) => selectNode(stageId);
  void resumeRun() => startRun();
  void beginClosure() => initiateClosure();

  void reorderStages(int oldIndex, int newIndex) {
    final nodes = [...template.nodes];
    if (oldIndex < 0 || oldIndex >= nodes.length) return;
    if (newIndex < 0 || newIndex > nodes.length) return;

    final item = nodes.removeAt(oldIndex);
    var targetIndex = newIndex;
    if (oldIndex < targetIndex) {
      targetIndex -= 1;
    }
    nodes.insert(targetIndex, item);
    _workingTemplate = template.copyWith(nodes: nodes);
    notifyListeners();
  }

  // --- Production Dynamics: Branching, Merging, Reversing ---

  void updateWorkingTemplate(PipelineTemplate newTemplate) {
    _workingTemplate = newTemplate;
    notifyListeners();
  }

  void skipNode(String nodeId) {
    final nodes = [...template.nodes];
    final idx = nodes.indexWhere((n) => n.id == nodeId);
    if (idx != -1) {
      nodes[idx] = nodes[idx].copyWith(status: 'Skipped');
      _workingTemplate = template.copyWith(nodes: nodes);
      notifyListeners();
    }
  }

  void reverseNode(String nodeId, {required String reason}) {
    // In a real flow, this would locate the upstream node, 
    // inject a backward flow, and mark the upstream node for 'rework'.
    // For now, mark the current node as 'Reversed'.
    final nodes = [...template.nodes];
    final idx = nodes.indexWhere((n) => n.id == nodeId);
    if (idx != -1) {
      nodes[idx] = nodes[idx].copyWith(status: 'Reversed');
      _workingTemplate = template.copyWith(nodes: nodes);
      notifyListeners();
    }
  }

  void branchOutput(String nodeId, int numBranches) {
    // Basic structural branch creation for the UI.
    final nodes = [...template.nodes];
    final flows = [...template.flows];
    final sourceNode = nodes.firstWhere((n) => n.id == nodeId);
    
    // Add parallel nodes in the next stage
    final nextStageIndex = sourceNode.stageIndex + 1;
    for (int i = 0; i < numBranches; i++) {
      final newId = 'node-branch-${DateTime.now().microsecondsSinceEpoch}-$i';
      nodes.add(ProcessNode(
        id: newId,
        name: '${sourceNode.name} Branch ${i+1}',
        processType: sourceNode.processType,
        stageIndex: nextStageIndex,
        laneIndex: i, // Parallel lanes
        inputs: sourceNode.outputs,
        outputs: sourceNode.outputs,
        machine: '',
        dieId: '',
        durationHours: sourceNode.durationHours,
        status: 'queued',
        isIntermediate: true,
      ));
      flows.add(MaterialFlow(
        id: 'flow-$nodeId-$newId',
        fromNodeId: nodeId,
        toNodeId: newId,
        materialName: sourceNode.outputs.firstOrNull ?? '',
        isSplit: true,
      ));
    }
    
    // Adjust lane labels if needed
    final lanes = [...template.laneLabels];
    while (lanes.length < numBranches) {
      lanes.add('Lane ${lanes.length + 1}');
    }

    _workingTemplate = template.copyWith(
      nodes: nodes, 
      flows: flows,
      laneLabels: lanes,
    );
    notifyListeners();
  }

  void cancelSetup() {
    _phase = ProductionRunPhase.idle;
    _currentMachineId = null;
    _currentDieId = null;
    _validationErrorMessage = null;
    notifyListeners();
  }

  void startRun() {
    final node = selectedNode;
    if (node == null) {
      return;
    }
    final isAllowedPhase =
        _phase == ProductionRunPhase.setupVerified ||
        _phase == ProductionRunPhase.paused;
    if (!isAllowedPhase ||
        _currentMachineId != node.machine ||
        _currentDieId != node.dieId) {
      _validationErrorMessage =
          'Verify the machine and die lock-key setup before starting.';
      notifyListeners();
      return;
    }
    if (_activeRun == null) {
      _activeRun = ActiveProductionRun(
        id: 'run-${DateTime.now().microsecondsSinceEpoch}',
        templateId: template.id,
        phase: ProductionRunPhase.running,
        logs: [],
        startedAt: DateTime.now(),
      );
    } else {
      _activeRun = _activeRun!.copyWith(phase: ProductionRunPhase.running);
    }
    _phase = ProductionRunPhase.running;
    _nodeStartedAt = DateTime.now();
    _validationErrorMessage = null;
    notifyListeners();
  }

  void pauseRun() {
    if (_phase != ProductionRunPhase.running) return;
    _bankElapsed();
    _phase = ProductionRunPhase.paused;
    _activeRun = _activeRun?.copyWith(phase: ProductionRunPhase.paused);
    notifyListeners();
  }

  void incrementYield(int amount) {
    if (!isRunning) return;
    _goodYieldCount += amount;
    _parentReelConsumedKg += amount * 0.15;
    notifyListeners();
  }

  void decrementYield(int amount) {
    if (!isRunning || _goodYieldCount < amount) return;
    _goodYieldCount -= amount;
    _parentReelConsumedKg -= amount * 0.15;
    notifyListeners();
  }

  void logScrap(double weightKg) {
    if (!isRunning && !isPaused) return;
    _scrapWeightKg += weightKg;
    _parentReelConsumedKg += weightKg;
    notifyListeners();
  }

  void initiateClosure() {
    if (!isRunning && !isPaused) return;
    _bankElapsed();
    _phase = ProductionRunPhase.loggingClosure;
    _activeRun = _activeRun?.copyWith(phase: ProductionRunPhase.loggingClosure);
    notifyListeners();
  }

  void completeClosure() {
    if (_phase != ProductionRunPhase.loggingClosure) return;

    final node = selectedNode;
    if (node != null && _activeRun != null) {
      final log = NodeExecutionLog(
        nodeId: node.id,
        machineId: _currentMachineId ?? 'UNKNOWN',
        dieId: _currentDieId ?? 'UNKNOWN',
        startedAt: _nodeStartedAt ?? DateTime.now(),
        completedAt: DateTime.now(),
        goodYieldCount: _goodYieldCount,
        scrapWeightKg: _scrapWeightKg,
      );
      _activeRun = _activeRun!.copyWith(
        phase: ProductionRunPhase.closed,
        closedAt: DateTime.now(),
        logs: [..._activeRun!.logs, log],
      );
    }

    _phase = ProductionRunPhase.closed;
    _currentMachineId = null;
    _currentDieId = null;
    _currentLotNumber++;
    notifyListeners();

    // Reset for next node
    Future.delayed(const Duration(seconds: 2), () {
      _phase = ProductionRunPhase.idle;
      _goodYieldCount = 0;
      _scrapWeightKg = 0;
      _bankedElapsed = Duration.zero;
      _nodeStartedAt = null;
      _validationErrorMessage = null;
      notifyListeners();
    });
  }

  void commitClosure() {
    // Legacy support for the UI dialog saving data
    completeClosure();
  }

  void updateClosureValues({
    required double parentReelConsumedKg,
    required int goodYieldCount,
    required double scrapWeightKg,
  }) {
    _parentReelConsumedKg = parentReelConsumedKg;
    _goodYieldCount = goodYieldCount;
    _scrapWeightKg = scrapWeightKg;
    notifyListeners();
  }

  void cancelClosure() {
    if (_phase != ProductionRunPhase.loggingClosure) return;
    _phase = ProductionRunPhase.paused;
    _activeRun = _activeRun?.copyWith(phase: ProductionRunPhase.paused);
    notifyListeners();
  }

  void _bankElapsed() {
    final startedAt = _nodeStartedAt;
    if (startedAt != null) {
      final delta = DateTime.now().difference(startedAt);
      if (!delta.isNegative) {
        _bankedElapsed += delta;
      }
    }
    _nodeStartedAt = null;
  }
}
