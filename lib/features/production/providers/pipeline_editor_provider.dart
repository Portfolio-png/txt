import 'package:flutter/material.dart';
import '../../production_pipelines/domain/material_flow.dart';
import '../../production_pipelines/domain/pipeline_template.dart';
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

  void updateTemplateDetails({String? name, String? description}) {
    _template = _template.copyWith(
      name: name == null || name.trim().isEmpty ? _template.name : name.trim(),
      description: description == null
          ? _template.description
          : description.trim(),
    );
    notifyListeners();
  }

  void selectNode(String id) {
    if (_connectingFromNodeId != null && _connectingFromNodeId != id) {
      // Connect mode is active! Connect from _connectingFromNodeId to id
      _addFlow(_connectingFromNodeId!, id);
      _connectingFromNodeId = null;
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
      id: 'flow-${DateTime.now().microsecondsSinceEpoch}',
      fromNodeId: fromId,
      toNodeId: toId,
      materialName: 'Material',
    );
    _template = _template.copyWith(flows: [..._template.flows, flow]);
    notifyListeners();
  }

  void addNode(int stageIndex, int laneIndex) {
    final node = _buildNode(stageIndex, laneIndex);
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

  void addNextStepFromSelection() {
    final source = selectedNode;
    if (source == null) {
      addNode(0, 0);
      return;
    }

    final node = _buildNode(source.stageIndex + 1, source.laneIndex);
    final flow = MaterialFlow(
      id: 'flow-${DateTime.now().microsecondsSinceEpoch}',
      fromNodeId: source.id,
      toNodeId: node.id,
      materialName: source.outputs.isEmpty ? 'Material' : source.outputs.first,
    );

    _template = _template.copyWith(
      nodes: [..._template.nodes, node],
      flows: [..._template.flows, flow],
      stageLabels: _stageLabelsFor(node.stageIndex),
      laneLabels: _laneLabelsFor(node.laneIndex),
    );
    _drafts[node.id] = ProcessNodeDraftController(node);
    _selectedNodeId = node.id;
    _connectingFromNodeId = null;
    notifyListeners();
  }

  ProcessNode _buildNode(int stageIndex, int laneIndex) {
    final nextNumber = _template.nodes.length + 1;
    return ProcessNode(
      id: 'node-${DateTime.now().microsecondsSinceEpoch}',
      name: 'Process $nextNumber',
      processType: 'Action',
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

  void saveNodeDraft(String id) {
    final draft = _drafts[id];
    if (draft == null) return;

    final updatedNodes = _template.nodes.map((n) {
      if (n.id != id) return n;
      return draft.toNode(n);
    }).toList();

    _template = _template.copyWith(nodes: updatedNodes);
    notifyListeners();
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
