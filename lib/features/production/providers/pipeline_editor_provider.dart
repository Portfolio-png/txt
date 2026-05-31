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
      outputs = TextEditingController(text: node.outputs.join(', '));

  final TextEditingController name;
  final TextEditingController machine;
  final TextEditingController dieId;
  final TextEditingController processType;
  final TextEditingController inputs;
  final TextEditingController outputs;

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
    );
  }

  void dispose() {
    name.dispose();
    machine.dispose();
    dieId.dispose();
    processType.dispose();
    inputs.dispose();
    outputs.dispose();
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

    final flow = MaterialFlow(
      id: _newFlowId(),
      fromNodeId: fromId,
      toNodeId: toId,
      materialName: 'Material',
    );
    _template = _template.copyWith(flows: [..._template.flows, flow]);
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
    _template = _template.copyWith(stageLabels: updatedStageLabels);
    notifyListeners();
  }

  void addLane() {
    final updatedLaneLabels = [..._template.laneLabels];
    updatedLaneLabels.add('Lane ${updatedLaneLabels.length + 1}');
    _template = _template.copyWith(laneLabels: updatedLaneLabels);
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

    final inputMaterial = source.outputs.isEmpty
        ? 'Material'
        : source.outputs.first;
    final defaultOutput = '${node.name} Output';
    final updatedNode = node.copyWith(
      inputs: [inputMaterial],
      outputs: [defaultOutput],
      inputItem: source.outputItem,
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

    _template = _template.copyWith(
      nodes: newNodesList,
      flows: newFlowsList,
      stageLabels: _stageLabelsFor(maxStage),
      laneLabels: _laneLabelsFor(source.laneIndex),
    );

    _drafts[updatedNode.id] = ProcessNodeDraftController(updatedNode);
    _selectedNodeId = updatedNode.id;
    _connectingFromNodeId = null;
    _applyUnitContinuityAutoFixes(units);
    notifyListeners();
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
      name: name ?? 'Process $nextNumber',
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
    _template = _template.copyWith(flows: updatedFlows);
    _connectingFromNodeId = null;
    notifyListeners();
  }

  void deleteSelectedNode() {
    if (_selectedNodeId == null) return;

    final updatedNodes = _template.nodes
        .where((n) => n.id != _selectedNodeId)
        .toList();
    final updatedFlows = _template.flows
        .where(
          (f) =>
              f.fromNodeId != _selectedNodeId && f.toNodeId != _selectedNodeId,
        )
        .toList();

    _drafts.remove(_selectedNodeId)?.dispose();
    _template = _template.copyWith(nodes: updatedNodes, flows: updatedFlows);
    _selectedNodeId = null;
    notifyListeners();
  }

  void saveNodeDraft(String id, {List<UnitDefinition> units = const []}) {
    final draft = _drafts[id];
    if (draft == null) return;

    final updatedNodes = _template.nodes.map((n) {
      if (n.id != id) return n;
      return draft.toNode(n);
    }).toList();

    _template = _template.copyWith(nodes: updatedNodes);
    _applyUnitContinuityAutoFixes(units);
    notifyListeners();
  }

  void updateNodeItems({
    required String nodeId,
    PipelineItemEndpoint? inputItem,
    PipelineItemEndpoint? outputItem,
    List<UnitDefinition> units = const [],
  }) {
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

    _template = _template.copyWith(
      nodes: updatedNodes,
      stageLabels: updatedStageLabels,
      laneLabels: updatedLaneLabels,
    );
    notifyListeners();
  }

  void renameStage(int index, String newName) {
    if (index < 0 || index >= _template.stageLabels.length) return;
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
