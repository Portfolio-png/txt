import 'dart:math' as math;

import 'package:core_erp/features/units/domain/unit_definition.dart';
import 'package:flutter/material.dart';
import '../domain/default_floor_context.dart';
import '../../production_pipelines/domain/material_flow.dart';
import '../../production_pipelines/domain/pipeline_item_endpoint.dart';
import '../../production_pipelines/domain/pipeline_template.dart';
import '../../production_pipelines/domain/pipeline_unit_validation_engine.dart';
import '../../production_pipelines/domain/process_node.dart';

class ProcessNodeDraftController {
  ProcessNodeDraftController(ProcessNode node)
    : name = TextEditingController(text: node.name),
      machine = TextEditingController(text: node.machine),
      dieId = TextEditingController(text: node.dieId),
      processType = TextEditingController(text: node.processType),
      inputs = TextEditingController(text: node.inputs.join(', ')),
      outputs = TextEditingController(text: node.outputs.join(', ')),
      durationHours = TextEditingController(
        text: node.durationHours > 0 ? node.durationHours.toString() : '',
      );

  final TextEditingController name;
  final TextEditingController machine;
  final TextEditingController dieId;
  final TextEditingController processType;
  final TextEditingController inputs;
  final TextEditingController outputs;
  final TextEditingController durationHours;

  ProcessNode toNode(ProcessNode current) {
    return current.copyWith(
      name: name.text.trim().isEmpty ? current.name : name.text.trim(),
      machine: machine.text.trim().isEmpty
          ? current.machine
          : machine.text.trim(),
      dieId: dieId.text.trim().isEmpty ? current.dieId : dieId.text.trim(),
      processType: processType.text.trim().isEmpty
          ? current.processType
          : processType.text.trim(),
      inputs: inputs.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      outputs: outputs.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      durationHours:
          double.tryParse(durationHours.text.trim()) ?? current.durationHours,
    );
  }

  void dispose() {
    name.dispose();
    machine.dispose();
    dieId.dispose();
    processType.dispose();
    inputs.dispose();
    outputs.dispose();
    durationHours.dispose();
  }
}

class PipelineEditorProvider extends ChangeNotifier {
  PipelineEditorProvider({PipelineTemplate? template}) {
    if (template != null) {
      _template = template;
      for (final node in template.nodes) {
        _drafts[node.id] = ProcessNodeDraftController(node);
      }
      if (template.nodes.isNotEmpty) {
        _selectedNodeId = template.nodes.first.id;
      }
    } else {
      _template = PipelineTemplate(
        id: 'tpl-${DateTime.now().microsecondsSinceEpoch}',
        factoryId: defaultProductionFactoryId,
        shopFloorId: defaultProductionShopFloorId,
        name: 'New Pipeline',
        description: '',
        stageLabels: ['Stage 1'],
        laneLabels: ['Main'],
        nodes: [],
        flows: [],
      );
    }
  }

  late PipelineTemplate _template;
  final Map<String, ProcessNodeDraftController> _drafts = {};
  String? _selectedNodeId;
  String? _connectingFromNodeId;

  final List<PipelineTemplate> _undoStack = [];
  final List<PipelineTemplate> _redoStack = [];

  void _pushHistory() {
    _undoStack.add(_template);
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void undo() {
    if (!canUndo) return;
    _redoStack.add(_template);
    _template = _undoStack.removeLast();
    _rebuildDrafts();
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _undoStack.add(_template);
    _template = _redoStack.removeLast();
    _rebuildDrafts();
    notifyListeners();
  }

  void _rebuildDrafts() {
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    _drafts.clear();
    for (final node in _template.nodes) {
      _drafts[node.id] = ProcessNodeDraftController(node);
    }
    if (_selectedNodeId != null) {
      if (!_template.nodes.any((n) => n.id == _selectedNodeId)) {
        _selectedNodeId = null;
      }
    }
  }

  PipelineTemplate get template => _template;
  String? get selectedNodeId => _selectedNodeId;
  String? get connectingFromNodeId => _connectingFromNodeId;

  ProcessNode? get selectedNode =>
      _template.nodes.where((n) => n.id == _selectedNodeId).firstOrNull;
  ProcessNodeDraftController? draftFor(String id) => _drafts[id];

  void loadTemplate(PipelineTemplate template) {
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    _drafts.clear();
    _template = template;
    for (final node in template.nodes) {
      _drafts[node.id] = ProcessNodeDraftController(node);
    }
    _selectedNodeId = template.nodes.firstOrNull?.id;
    _connectingFromNodeId = null;
    notifyListeners();
  }

  void startNewTemplate({
    String factoryId = defaultProductionFactoryId,
    String shopFloorId = defaultProductionShopFloorId,
  }) {
    loadTemplate(
      PipelineTemplate(
        id: 'tpl-${DateTime.now().microsecondsSinceEpoch}',
        factoryId: factoryId,
        shopFloorId: shopFloorId,
        name: 'New Pipeline',
        description: '',
        stageLabels: const ['Stage 1'],
        laneLabels: const ['Main'],
        nodes: const [],
        flows: const [],
      ),
    );
  }

  void updateTemplateDetails({
    String? name,
    String? description,
    String? inputMaterial,
    String? outputMaterial,
  }) {
    _pushHistory();
    _template = _template.copyWith(
      name: name == null || name.trim().isEmpty ? _template.name : name.trim(),
      description: description == null
          ? _template.description
          : description.trim(),
      inputMaterial: inputMaterial == null
          ? _template.inputMaterial
          : inputMaterial.trim(),
      outputMaterial: outputMaterial == null
          ? _template.outputMaterial
          : outputMaterial.trim(),
    );
    notifyListeners();
  }

  void selectNode(String id, {List<UnitDefinition> units = const []}) {
    if (_connectingFromNodeId != null && _connectingFromNodeId != id) {
      // Connect mode is active! Connect from _connectingFromNodeId to id
      _addFlow(_connectingFromNodeId!, id);
      _connectingFromNodeId = null;
      _applyUnitContinuityAutoFixes(units);
    } else {
      _selectedNodeId = id;
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedNodeId = null;
    _connectingFromNodeId = null;
    notifyListeners();
  }

  void beginConnecting(String fromNodeId) {
    _connectingFromNodeId = fromNodeId;
    _selectedNodeId = null;
    notifyListeners();
  }

  void _addFlow(String fromId, String toId) {
    if (_template.flows.any(
      (f) => f.fromNodeId == fromId && f.toNodeId == toId,
    )) {
      return;
    }

    final fromNode = _template.nodes.firstWhere((n) => n.id == fromId);
    final toNode = _template.nodes.firstWhere((n) => n.id == toId);

    final materialName = fromNode.outputs.isEmpty
        ? 'Material'
        : fromNode.outputs.first;
    final flow = MaterialFlow(
      id: _newFlowId(),
      fromNodeId: fromId,
      toNodeId: toId,
      materialName: materialName,
    );

    // Auto-inherit input mapping from upstream node
    ProcessNode updatedToNode = toNode.copyWith(
      inputItem: toNode.inputItem ?? fromNode.outputItem,
      inputs: [
        toNode.inputItem?.itemName ??
            fromNode.outputItem?.itemName ??
            materialName,
      ],
    );

    // Auto-generate output naming if it hasn't been mapped yet
    if (updatedToNode.outputItem == null) {
      final originalItemName = _getOriginalItemName(fromNode.id);
      final stageName = _template.stageLabels.length > updatedToNode.stageIndex
          ? _template.stageLabels[updatedToNode.stageIndex]
          : 'Stage ${updatedToNode.stageIndex + 1}';

      final defaultOutputName =
          '${stageName}_${updatedToNode.processType}_$originalItemName';

      final outputItem = PipelineItemEndpoint(
        itemId: DateTime.now().microsecondsSinceEpoch,
        itemName: defaultOutputName,
        unitId: fromNode.outputItem?.unitId ?? 0,
        unitName: fromNode.outputItem?.unitName ?? 'Pieces',
        unitSymbol: fromNode.outputItem?.unitSymbol ?? 'Pcs',
      );

      updatedToNode = updatedToNode.copyWith(
        outputItem: outputItem,
        outputs: [defaultOutputName],
      );
    }

    final updatedNodes = _template.nodes.map((n) {
      if (n.id == updatedToNode.id) return updatedToNode;
      return n;
    }).toList();

    _pushHistory();
    _template = _template.copyWith(
      nodes: updatedNodes,
      flows: [..._template.flows, flow],
    );

    if (_drafts.containsKey(updatedToNode.id)) {
      _drafts[updatedToNode.id] = ProcessNodeDraftController(updatedToNode);
    }

    notifyListeners();
  }

  void addNode(
    int stageIndex,
    int laneIndex, {
    String processType = 'Action',
    String? name,
  }) {
    final node = _buildNode(
      stageIndex,
      laneIndex,
      processType: processType,
      name: name,
    );
    final updatedNodes = [..._template.nodes, node];

    _pushHistory();
    _template = _template.copyWith(
      nodes: updatedNodes,
      stageLabels: _stageLabelsFor(stageIndex),
      laneLabels: _laneLabelsFor(laneIndex),
    );
    _drafts[node.id] = ProcessNodeDraftController(node);
    _selectedNodeId = node.id;
    _connectingFromNodeId = null;
    notifyListeners();
  }

  void addStage() {
    final updatedStageLabels = [..._template.stageLabels];
    updatedStageLabels.add('Stage ${updatedStageLabels.length + 1}');
    _pushHistory();
    _template = _template.copyWith(stageLabels: updatedStageLabels);
    notifyListeners();
  }

  void addLane() {
    final updatedLaneLabels = [..._template.laneLabels];
    updatedLaneLabels.add('Lane ${updatedLaneLabels.length + 1}');
    _pushHistory();
    _template = _template.copyWith(laneLabels: updatedLaneLabels);
    notifyListeners();
  }

  void insertNodeAtStage(
    int targetStageIndex, {
    List<UnitDefinition> units = const [],
  }) {
    final shiftedNodes = _template.nodes.map((node) {
      if (node.stageIndex >= targetStageIndex) {
        return node.copyWith(stageIndex: node.stageIndex + 1);
      }
      return node;
    }).toList();

    final node = _buildNode(targetStageIndex, 0);
    final newNodesList = [...shiftedNodes, node];

    int maxStage = 0;
    for (final n in newNodesList) {
      if (n.stageIndex > maxStage) maxStage = n.stageIndex;
    }

    _pushHistory();
    _template = _template.copyWith(
      nodes: newNodesList,
      stageLabels: _stageLabelsWithInsertedStage(
        targetStageIndex,
        _stageLabelForNode(node),
      ),
    );
    _drafts[node.id] = ProcessNodeDraftController(node);
    _selectedNodeId = node.id;
    _connectingFromNodeId = null;
    notifyListeners();
  }

  void addNextStepFromSelection({List<UnitDefinition> units = const []}) {
    addTypedStepFromSelection(units: units);
  }

  void addInputStepFromSelection({List<UnitDefinition> units = const []}) {
    addTypedStepFromSelection(
      processType: 'Input',
      namePrefix: 'Input',
      units: units,
    );
  }

  void addDecisionStepFromSelection({List<UnitDefinition> units = const []}) {
    addTypedStepFromSelection(
      processType: 'Decision',
      namePrefix: 'Check',
      units: units,
    );
  }

  void addOutputStepFromSelection({List<UnitDefinition> units = const []}) {
    addTypedStepFromSelection(
      processType: 'Output',
      namePrefix: 'Output',
      units: units,
    );
  }

  void addTypedStepFromSelection({
    String processType = 'Action',
    String? namePrefix,
    List<UnitDefinition> units = const [],
  }) {
    final source = selectedNode;
    if (source == null) {
      addNode(
        0,
        0,
        processType: processType,
        name: namePrefix == null ? null : '$namePrefix 1',
      );
      return;
    }

    final nextNumber = _template.nodes.length + 1;
    final node = _buildNode(
      source.stageIndex + 1,
      source.laneIndex,
      processType: processType,
      name: namePrefix == null ? null : '$namePrefix $nextNumber',
    );

    final originalItemName = _getOriginalItemName(source.id);
    final stageName = _stageLabelForNode(node);

    final defaultOutputName = '${stageName}_${processType}_$originalItemName';

    final outputItem = PipelineItemEndpoint(
      itemId: DateTime.now().microsecondsSinceEpoch,
      itemName: defaultOutputName,
      unitId: source.outputItem?.unitId ?? 0,
      unitName: source.outputItem?.unitName ?? 'Pieces',
      unitSymbol: source.outputItem?.unitSymbol ?? 'Pcs',
    );

    final inputMaterial = source.outputs.isEmpty
        ? 'Material'
        : source.outputs.first;
    final updatedNode = node.copyWith(
      inputs: [source.outputItem?.itemName ?? inputMaterial],
      outputs: [defaultOutputName],
      inputItem: source.outputItem,
      outputItem: outputItem,
    );

    final insertStage = source.stageIndex + 1;
    final shiftedNodes = _template.nodes.map((n) {
      if (n.stageIndex >= insertStage) {
        return n.copyWith(stageIndex: n.stageIndex + 1);
      }
      return n;
    }).toList();
    final newNodesList = [...shiftedNodes, updatedNode];
    final newFlowsList = [
      ..._template.flows,
      MaterialFlow(
        id: _newFlowId(),
        fromNodeId: source.id,
        toNodeId: updatedNode.id,
        materialName: inputMaterial,
      ),
    ];

    int maxStage = 0;
    for (final n in newNodesList) {
      if (n.stageIndex > maxStage) maxStage = n.stageIndex;
    }

    _pushHistory();
    _template = _template.copyWith(
      nodes: newNodesList,
      flows: newFlowsList,
      stageLabels: _stageLabelsWithInsertedStage(
        insertStage,
        _stageLabelForNode(updatedNode),
      ),
      laneLabels: _laneLabelsFor(source.laneIndex),
    );

    _drafts[updatedNode.id] = ProcessNodeDraftController(updatedNode);
    _selectedNodeId = updatedNode.id;
    _connectingFromNodeId = null;
    _applyUnitContinuityAutoFixes(units);
    notifyListeners();
  }

  void generateBatchFlow(
    List<String> processTypes, {
    List<UnitDefinition> units = const [],
  }) {
    if (processTypes.isEmpty) return;

    _pushHistory();

    // Find where to append
    int startStage = 0;
    ProcessNode? lastNode;
    ProcessNode? outputNode;
    
    if (_template.nodes.isNotEmpty) {
      for (final n in _template.nodes) {
        if (n.name.toLowerCase().contains('output')) {
          outputNode = n;
        }
        if (n.stageIndex >= startStage) {
          startStage = n.stageIndex + 1;
          lastNode = n;
        }
      }
    }

    final newNodes = List<ProcessNode>.from(_template.nodes);
    final newFlows = List<MaterialFlow>.from(_template.flows);

    bool insertBeforeOutput = false;
    ProcessNode? nodeToConnectFrom = lastNode;
    int insertStageIndex = startStage;

    if (outputNode != null && outputNode.id == lastNode?.id) {
      insertBeforeOutput = true;
      insertStageIndex = outputNode.stageIndex;
      
      final incomingFlows = _template.flows.where((f) => f.toNodeId == outputNode!.id).toList();
      if (incomingFlows.isNotEmpty) {
        final incomingFlow = incomingFlows.first;
        nodeToConnectFrom = _template.nodes.where((n) => n.id == incomingFlow.fromNodeId).firstOrNull;
        newFlows.removeWhere((f) => f.toNodeId == outputNode!.id);
      } else {
        nodeToConnectFrom = null;
      }
    }

    String? currentInputItem = nodeToConnectFrom?.outputItem?.itemName ?? 'Material';
    PipelineItemEndpoint? currentInputEndpoint = nodeToConnectFrom?.outputItem;
    ProcessNode? lastAddedNode = nodeToConnectFrom;

    for (int i = 0; i < processTypes.length; i++) {
      final processType = processTypes[i];
      final stageIndex = insertStageIndex + i;
      final isLast = i == processTypes.length - 1 && !insertBeforeOutput;

      final nextNumber = newNodes.length + 1;
      
      String outputName;
      PipelineItemEndpoint? outputEndpoint;

      if (isLast) {
        outputName = 'Final Product';
        outputEndpoint = PipelineItemEndpoint(
          itemId: DateTime.now().microsecondsSinceEpoch + i,
          itemName: outputName,
          unitId: currentInputEndpoint?.unitId ?? 0,
          unitName: currentInputEndpoint?.unitName ?? 'Pieces',
          unitSymbol: currentInputEndpoint?.unitSymbol ?? 'Pcs',
        );
      } else if (insertBeforeOutput && i == processTypes.length - 1 && outputNode != null) {
        // Inherit from the output node we are inserting before
        outputName = outputNode.outputItem?.itemName ?? outputNode.inputs.firstOrNull ?? 'Final Product';
        outputEndpoint = outputNode.outputItem ?? PipelineItemEndpoint(
          itemId: DateTime.now().microsecondsSinceEpoch + i,
          itemName: outputName,
          unitId: currentInputEndpoint?.unitId ?? 0,
          unitName: currentInputEndpoint?.unitName ?? 'Pieces',
          unitSymbol: currentInputEndpoint?.unitSymbol ?? 'Pcs',
        );
      } else {
        outputName = '${processType}_Output_$nextNumber';
        outputEndpoint = PipelineItemEndpoint(
          itemId: DateTime.now().microsecondsSinceEpoch + i,
          itemName: outputName,
          unitId: currentInputEndpoint?.unitId ?? 0,
          unitName: currentInputEndpoint?.unitName ?? 'Pieces',
          unitSymbol: currentInputEndpoint?.unitSymbol ?? 'Pcs',
        );
      }

      final node =
          _buildNode(
            stageIndex,
            0,
            processType: processType,
            name: processType,
          ).copyWith(
            inputs: [currentInputItem ?? 'Material'],
            outputs: [outputName],
            inputItem: currentInputEndpoint,
            outputItem: outputEndpoint,
          );

      newNodes.add(node);
      _drafts[node.id] = ProcessNodeDraftController(node);

      if (lastAddedNode != null) {
        newFlows.add(
          MaterialFlow(
            id: _newFlowId(),
            fromNodeId: lastAddedNode.id,
            toNodeId: node.id,
            materialName: currentInputItem ?? 'Material',
          ),
        );
      }

      lastAddedNode = node;
      currentInputItem = outputName;
      currentInputEndpoint = outputEndpoint;
    }

    if (insertBeforeOutput && outputNode != null) {
      final shiftedOutputNode = outputNode.copyWith(
        stageIndex: insertStageIndex + processTypes.length,
        inputItem: currentInputEndpoint,
        inputs: [currentInputItem ?? 'Material'],
      );
      
      final outputNodeIndex = newNodes.indexWhere((n) => n.id == outputNode!.id);
      if (outputNodeIndex != -1) {
        newNodes[outputNodeIndex] = shiftedOutputNode;
        _drafts[outputNode.id]?.inputs.text = currentInputItem ?? 'Material';
      }

      if (lastAddedNode != null) {
        newFlows.add(
          MaterialFlow(
            id: _newFlowId(),
            fromNodeId: lastAddedNode.id,
            toNodeId: outputNode.id,
            materialName: currentInputItem ?? 'Material',
          ),
        );
      }
      
      lastNode = shiftedOutputNode;
    } else {
      lastNode = lastAddedNode;
    }
    
    int maxStage = 0;
    for (final n in newNodes) {
      if (n.stageIndex > maxStage) maxStage = n.stageIndex;
    }

    _template = _template.copyWith(
      nodes: newNodes,
      flows: newFlows,
      stageLabels: _stageLabelsFor(maxStage),
    );

    _selectedNodeId = lastNode?.id;
    _connectingFromNodeId = null;
    _applyUnitContinuityAutoFixes(units);
    notifyListeners();
  }

  void setCommonMaterial(
    String materialName, {
    List<UnitDefinition> units = const [],
  }) {
    if (_template.nodes.isEmpty) {
      addNode(0, 0, processType: 'Input', name: 'Raw Material');
    }

    final targetId = _selectedNodeId ?? _template.nodes.first.id;
    final targetNode = _template.nodes.firstWhere((n) => n.id == targetId);

    _pushHistory();

    final endpoint = PipelineItemEndpoint(
      itemId: DateTime.now().microsecondsSinceEpoch,
      itemName: materialName,
      unitId: 0,
      unitName: 'Pieces',
      unitSymbol: 'Pcs',
    );

    final updatedNode = targetNode.copyWith(
      inputs: [materialName],
      inputItem: endpoint,
    );

    _template = _template.copyWith(
      nodes: _template.nodes
          .map((n) => n.id == targetId ? updatedNode : n)
          .toList(),
    );

    _drafts[targetId]?.dispose();
    _drafts[targetId] = ProcessNodeDraftController(updatedNode);

    _applyUnitContinuityAutoFixes(units);
    notifyListeners();
  }

  String _getOriginalItemName(String startNodeId) {
    String currentId = startNodeId;
    while (true) {
      final flow = _template.flows
          .where((f) => f.toNodeId == currentId)
          .firstOrNull;
      if (flow == null) break;
      currentId = flow.fromNodeId;
    }
    final firstNode = _template.nodes
        .where((n) => n.id == currentId)
        .firstOrNull;
    return firstNode?.inputItem?.itemName ??
        firstNode?.inputs.firstOrNull ??
        'Material';
  }

  ProcessNode _buildNode(
    int stageIndex,
    int laneIndex, {
    String processType = 'Action',
    String? name,
  }) {
    final nextNumber = _template.nodes.length + 1;
    return ProcessNode(
      id: 'node-${DateTime.now().microsecondsSinceEpoch}',
      name: name ?? 'Stage $nextNumber',
      processType: processType,
      stageIndex: stageIndex,
      laneIndex: laneIndex,
      inputs: ['Input'],
      outputs: ['Output'],
      machine: 'MC-NEW',
      dieId: 'DIE-01',
      durationHours: 1.0,
      status: 'Queued',
      isIntermediate: false,
    );
  }

  List<String> _stageLabelsFor(int stageIndex) {
    final updatedStageLabels = [..._template.stageLabels];
    while (updatedStageLabels.length <= stageIndex) {
      updatedStageLabels.add('Stage ${updatedStageLabels.length + 1}');
    }
    return updatedStageLabels;
  }

  String _stageLabelForNode(ProcessNode node) {
    final name = node.name.trim();
    if (name.isNotEmpty) {
      return name;
    }
    final processType = node.processType.trim();
    if (processType.isNotEmpty) {
      return processType;
    }
    return 'Stage ${node.stageIndex + 1}';
  }

  List<String> _stageLabelsWithInsertedStage(int insertStage, String label) {
    final labels = [..._template.stageLabels];
    while (labels.length < insertStage) {
      labels.add('Stage ${labels.length + 1}');
    }
    final resolvedLabel = label.trim().isEmpty
        ? 'Stage ${insertStage + 1}'
        : label.trim();
    if (insertStage >= labels.length) {
      labels.add(resolvedLabel);
    } else {
      labels.insert(insertStage, resolvedLabel);
    }
    return labels;
  }

  List<String> _laneLabelsFor(int laneIndex) {
    final updatedLaneLabels = [..._template.laneLabels];
    while (updatedLaneLabels.length <= laneIndex) {
      updatedLaneLabels.add('Lane ${updatedLaneLabels.length + 1}');
    }
    return updatedLaneLabels;
  }

  void duplicateSelectedNode() {
    final source = selectedNode;
    if (source == null) return;

    final node = source.copyWith(
      id: 'node-${DateTime.now().microsecondsSinceEpoch}',
      name: '${source.name} Copy',
      stageIndex: source.stageIndex + 1,
    );
    _pushHistory();
    _template = _template.copyWith(
      nodes: [..._template.nodes, node],
      stageLabels: _stageLabelsFor(node.stageIndex),
      laneLabels: _laneLabelsFor(node.laneIndex),
    );
    _drafts[node.id] = ProcessNodeDraftController(node);
    _selectedNodeId = node.id;
    _connectingFromNodeId = null;
    notifyListeners();
  }

  void disconnectSelectedNode() {
    if (_selectedNodeId == null) return;

    final updatedFlows = _template.flows
        .where(
          (flow) =>
              flow.fromNodeId != _selectedNodeId &&
              flow.toNodeId != _selectedNodeId,
        )
        .toList();
    _pushHistory();
    _template = _template.copyWith(flows: updatedFlows);
    _connectingFromNodeId = null;
    notifyListeners();
  }

  String? deleteSelectedNode() {
    if (_selectedNodeId == null) return null;

    final targetId = _selectedNodeId!;
    final targetNode = _template.nodes.firstWhere((n) => n.id == targetId);

    if (targetNode.processType == 'Input' || targetNode.processType == 'Output') {
      return 'Cannot delete ${targetNode.name} as it is required for the pipeline.';
    }

    final incoming = _template.flows
        .where((f) => f.toNodeId == targetId)
        .toList();
    final outgoing = _template.flows
        .where((f) => f.fromNodeId == targetId)
        .toList();

    final updatedNodes = _template.nodes
        .where((n) => n.id != targetId)
        .toList();

    var updatedFlows = _template.flows
        .where((f) => f.fromNodeId != targetId && f.toNodeId != targetId)
        .toList();

    String? message;

    // Auto-heal: If deleted node has exactly one predecessor and one successor, connect them directly
    if (incoming.length == 1 && outgoing.length == 1) {
      final inFlow = incoming.first;
      final outFlow = outgoing.first;
      final healedFlow = MaterialFlow(
        id: 'flow-${DateTime.now().microsecondsSinceEpoch}',
        fromNodeId: inFlow.fromNodeId,
        toNodeId: outFlow.toNodeId,
        materialName: inFlow.materialName.isNotEmpty
            ? inFlow.materialName
            : outFlow.materialName,
      );
      updatedFlows.add(healedFlow);

      final fromNode = updatedNodes.firstWhere(
        (n) => n.id == healedFlow.fromNodeId,
        orElse: () => targetNode,
      );
      final toNode = updatedNodes.firstWhere(
        (n) => n.id == healedFlow.toNodeId,
        orElse: () => targetNode,
      );
      message =
          'Deleted ${targetNode.name}. Re-wired ${fromNode.name} to ${toNode.name}.';
    } else {
      message = 'Deleted ${targetNode.name}.';
    }

    _pushHistory();
    _drafts.remove(targetId)?.dispose();
    _template = _template.copyWith(nodes: updatedNodes, flows: updatedFlows);
    _selectedNodeId = null;
    notifyListeners();
    return message;
  }

  void moveSelectedNodeEarlier() {
    if (_selectedNodeId == null) return;
    final node = _template.nodes.firstWhere((n) => n.id == _selectedNodeId);
    if (node.stageIndex > 0) {
      _updateNodeStage(node.id, node.stageIndex - 1);
    }
  }

  void moveSelectedNodeLater() {
    if (_selectedNodeId == null) return;
    final node = _template.nodes.firstWhere((n) => n.id == _selectedNodeId);
    _updateNodeStage(node.id, node.stageIndex + 1);
  }

  void _updateNodeStage(String nodeId, int newStageIndex) {
    _pushHistory();
    final updatedNodes = _template.nodes.map((n) {
      if (n.id == nodeId) {
        return n.copyWith(stageIndex: newStageIndex);
      }
      return n;
    }).toList();

    _template = _template.copyWith(
      nodes: updatedNodes,
      stageLabels: _stageLabelsFor(newStageIndex),
    );
    notifyListeners();
  }

  void moveNodeToStage(String nodeId, int newStageIndex) {
    _updateNodeStage(nodeId, newStageIndex);
  }

  void saveNodeDraft(String id, {List<UnitDefinition> units = const []}) {
    final draft = _drafts[id];
    if (draft == null) return;

    final updatedNodes = _template.nodes.map((n) {
      if (n.id != id) return n;
      return draft.toNode(n);
    }).toList();

    _pushHistory();
    _template = _template.copyWith(nodes: updatedNodes);
    _applyUnitContinuityAutoFixes(units);
    notifyListeners();
  }

  void updateNodeItems({
    required String nodeId,
    PipelineItemEndpoint? inputItem,
    PipelineItemEndpoint? outputItem,
    List<UnitDefinition> units = const [],
    bool propagate = false,
  }) {
    _pushHistory();
    final updatedNodes = _template.nodes.map((node) {
      if (node.id != nodeId) {
        return node;
      }
      return node.copyWith(
        inputItem: inputItem,
        outputItem: outputItem,
        inputs: inputItem == null ? node.inputs : [inputItem.itemName],
        outputs: outputItem == null ? node.outputs : [outputItem.itemName],
      );
    }).toList();

    _template = _template.copyWith(nodes: updatedNodes);
    final draft = _drafts[nodeId];
    if (draft != null) {
      if (inputItem != null) {
        draft.inputs.text = inputItem.itemName;
      }
      if (outputItem != null) {
        draft.outputs.text = outputItem.itemName;
      }
    }
    _applyUnitContinuityAutoFixes(units);
    if (propagate) {
      propagateItemChanges(nodeId);
    }
    notifyListeners();
  }

  void updateNodeMachineGroup({
    required String nodeId,
    int? machineGroupId,
    String? machineGroupName,
  }) {
    _pushHistory();
    final updatedNodes = _template.nodes.map((node) {
      if (node.id != nodeId) {
        return node;
      }
      return node.copyWith(
        machineGroupId: machineGroupId,
        machineGroupName: machineGroupName,
      );
    }).toList();
    _template = _template.copyWith(nodes: updatedNodes);
    notifyListeners();
  }

  void updateNodeMachine({required String nodeId, required String machineId}) {
    _pushHistory();
    final updatedNodes = _template.nodes.map((node) {
      if (node.id != nodeId) {
        return node;
      }
      return node.copyWith(machine: machineId);
    }).toList();

    _template = _template.copyWith(nodes: updatedNodes);
    final draft = _drafts[nodeId];
    if (draft != null) {
      draft.machine.text = machineId;
    }
    notifyListeners();
  }

  void propagateItemChanges(String startNodeId) {
    final startNode = _template.nodes.firstWhere((n) => n.id == startNodeId);
    if (startNode.outputItem == null) return;

    _pushHistory();
    List<ProcessNode> updatedNodes = [..._template.nodes];
    final originalItemName = _getOriginalItemName(startNodeId);

    final queue = [startNodeId];

    while (queue.isNotEmpty) {
      final currentId = queue.removeAt(0);
      final currentNode = updatedNodes.firstWhere((n) => n.id == currentId);

      final outgoingFlows = _template.flows.where(
        (f) => f.fromNodeId == currentId,
      );
      for (final flow in outgoingFlows) {
        final toIndex = updatedNodes.indexWhere((n) => n.id == flow.toNodeId);
        if (toIndex == -1) continue;

        final toNode = updatedNodes[toIndex];

        final newInputItem = currentNode.outputItem;

        final stageName = _template.stageLabels.length > toNode.stageIndex
            ? _template.stageLabels[toNode.stageIndex]
            : 'Stage ${toNode.stageIndex + 1}';

        final defaultOutputName =
            '${stageName}_${toNode.processType}_$originalItemName';

        final newOutputItem = PipelineItemEndpoint(
          itemId: DateTime.now().microsecondsSinceEpoch + toIndex,
          itemName: defaultOutputName,
          unitId: newInputItem?.unitId ?? 0,
          unitName: newInputItem?.unitName ?? 'Pieces',
          unitSymbol: newInputItem?.unitSymbol ?? 'Pcs',
        );

        updatedNodes[toIndex] = toNode.copyWith(
          inputItem: newInputItem,
          outputItem: newOutputItem,
          inputs: [newInputItem?.itemName ?? 'Material'],
          outputs: [defaultOutputName],
        );

        queue.add(flow.toNodeId);
      }
    }

    _template = _template.copyWith(nodes: updatedNodes);
    notifyListeners();
  }

  PipelineUnitValidationResult applyUnitContinuityAutoFixes(
    List<UnitDefinition> units,
  ) {
    final result = _applyUnitContinuityAutoFixes(units);
    notifyListeners();
    return result;
  }

  void updateNodePosition(String id, int newStageIndex, int newLaneIndex) {
    final updatedNodes = _template.nodes.map((n) {
      if (n.id != id) return n;
      return n.copyWith(stageIndex: newStageIndex, laneIndex: newLaneIndex);
    }).toList();

    // Ensure labels list is long enough
    final updatedStageLabels = [..._template.stageLabels];
    while (updatedStageLabels.length <= newStageIndex) {
      updatedStageLabels.add('Stage ${updatedStageLabels.length + 1}');
    }
    final updatedLaneLabels = [..._template.laneLabels];
    while (updatedLaneLabels.length <= newLaneIndex) {
      updatedLaneLabels.add('Lane ${updatedLaneLabels.length + 1}');
    }

    _pushHistory();
    _template = _template.copyWith(
      nodes: updatedNodes,
      stageLabels: updatedStageLabels,
      laneLabels: updatedLaneLabels,
    );
    notifyListeners();
  }

  void renameStage(int index, String newName) {
    if (index < 0 || index >= _template.stageLabels.length) return;
    _pushHistory();
    final updatedLabels = [..._template.stageLabels];
    updatedLabels[index] = newName;
    _template = _template.copyWith(stageLabels: updatedLabels);
    notifyListeners();
  }

  PipelineUnitValidationResult _applyUnitContinuityAutoFixes(
    List<UnitDefinition> units,
  ) {
    final engine = const PipelineUnitValidationEngine();
    var result = engine.validate(_template, units);

    for (final issue in result.bridgeIssues) {
      _insertBridgeForIssue(issue);
    }

    return engine.validate(_template, units);
  }

  void _insertBridgeForIssue(PipelineUnitIssue issue) {
    final directFlow = _template.flows.where((flow) {
      return flow.id == issue.flow.id &&
          flow.fromNodeId == issue.flow.fromNodeId &&
          flow.toNodeId == issue.flow.toNodeId;
    }).firstOrNull;
    if (directFlow == null) {
      return;
    }

    final source = _template.nodes
        .where((node) => node.id == directFlow.fromNodeId)
        .firstOrNull;
    final target = _template.nodes
        .where((node) => node.id == directFlow.toNodeId)
        .firstOrNull;
    final inputItem = source?.outputItem;
    final outputItem = target?.inputItem;
    if (source == null ||
        target == null ||
        inputItem == null ||
        outputItem == null) {
      return;
    }

    if (_hasMatchingBridge(source.id, target.id, inputItem, outputItem)) {
      _template = _template.copyWith(
        flows: _template.flows
            .where((flow) => flow.id != directFlow.id)
            .toList(),
      );
      return;
    }

    final insertStage = math.max(source.stageIndex + 1, target.stageIndex);
    final isConversion = issue.kind == PipelineUnitIssueKind.unitConversion;
    final bridge = ProcessNode(
      id: _newNodeId(prefix: 'node-bridge'),
      name: isConversion
          ? 'Convert ${inputItem.unitLabel} to ${outputItem.unitLabel}'
          : 'Transform ${inputItem.itemName} to ${outputItem.itemName}',
      processType: isConversion ? 'Unit Conversion' : 'Material Transform',
      stageIndex: insertStage,
      laneIndex: target.laneIndex,
      inputs: [inputItem.itemName],
      outputs: [outputItem.itemName],
      machine: isConversion ? 'Auto Converter' : 'Needs Setup',
      dieId: '',
      durationHours: isConversion ? 0.1 : 1.0,
      status: isConversion ? 'Ready' : 'Needs Setup',
      isIntermediate: true,
      inputItem: inputItem,
      outputItem: outputItem,
      unitConversionMultiplier: issue.multiplier,
    );

    final shiftedNodes = _template.nodes.map((node) {
      if (node.stageIndex >= insertStage) {
        return node.copyWith(stageIndex: node.stageIndex + 1);
      }
      return node;
    }).toList();
    final updatedFlows = _template.flows
        .where((flow) => flow.id != directFlow.id)
        .toList();
    updatedFlows.addAll([
      MaterialFlow(
        id: _newFlowId(),
        fromNodeId: source.id,
        toNodeId: bridge.id,
        materialName: inputItem.itemName,
      ),
      MaterialFlow(
        id: _newFlowId(offset: 1),
        fromNodeId: bridge.id,
        toNodeId: target.id,
        materialName: outputItem.itemName,
      ),
    ]);

    _template = _template.copyWith(
      nodes: [...shiftedNodes, bridge],
      flows: updatedFlows,
      stageLabels: _stageLabelsWithBridge(insertStage, bridge.processType),
      laneLabels: _laneLabelsFor(target.laneIndex),
    );
    _drafts[bridge.id] = ProcessNodeDraftController(bridge);
  }

  bool _hasMatchingBridge(
    String sourceId,
    String targetId,
    PipelineItemEndpoint inputItem,
    PipelineItemEndpoint outputItem,
  ) {
    for (final bridge in _template.nodes.where((node) => node.isIntermediate)) {
      if (bridge.inputItem?.itemId != inputItem.itemId ||
          bridge.outputItem?.itemId != outputItem.itemId) {
        continue;
      }
      final hasSourceFlow = _template.flows.any(
        (flow) => flow.fromNodeId == sourceId && flow.toNodeId == bridge.id,
      );
      final hasTargetFlow = _template.flows.any(
        (flow) => flow.fromNodeId == bridge.id && flow.toNodeId == targetId,
      );
      if (hasSourceFlow && hasTargetFlow) {
        return true;
      }
    }
    return false;
  }

  List<String> _stageLabelsWithBridge(int insertStage, String label) {
    final labels = [..._template.stageLabels];
    while (labels.length < insertStage) {
      labels.add('Stage ${labels.length + 1}');
    }
    if (insertStage >= labels.length) {
      labels.add(label);
    } else {
      labels.insert(insertStage, label);
    }
    return labels;
  }

  String _newNodeId({String prefix = 'node'}) {
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
  }

  String _newFlowId({int offset = 0}) {
    return 'flow-${DateTime.now().microsecondsSinceEpoch + offset}';
  }

  @override
  void dispose() {
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    super.dispose();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
