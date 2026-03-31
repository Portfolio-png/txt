import 'package:flutter/material.dart';

import '../../inventory/data/repositories/inventory_repository.dart';
import '../../inventory/domain/material_record.dart';
import '../data/mock_pipeline_templates_repository.dart';
import '../domain/barcode_input.dart';
import '../domain/material_flow.dart';
import '../domain/pipeline_template.dart';
import '../domain/process_node.dart';

class PipelinesProvider extends ChangeNotifier {
  PipelinesProvider({
    required InventoryRepository inventoryRepository,
    MockPipelineTemplatesRepository? repository,
  }) : _repository = repository ?? const MockPipelineTemplatesRepository(),
       _inventoryRepository = inventoryRepository {
    _templates = _repository.getTemplates();
    _selectedTemplate = _templates.first;
    if (_selectedTemplate.nodes.isNotEmpty) {
      _selectedNodeId = _selectedTemplate.nodes.first.id;
      _focusedCell = (
        _selectedTemplate.nodes.first.laneIndex,
        _selectedTemplate.nodes.first.stageIndex,
      );
    }
  }

  final MockPipelineTemplatesRepository _repository;
  final InventoryRepository _inventoryRepository;

  late final List<PipelineTemplate> _templates;
  late PipelineTemplate _selectedTemplate;
  String? _selectedNodeId;
  (int lane, int stage) _focusedCell = (0, 0);
  bool _isEditing = false;
  bool _isScanningMaterial = false;
  String? _scanErrorMessage;

  List<PipelineTemplate> get templates => _templates;
  PipelineTemplate get selectedTemplate => _selectedTemplate;
  List<ProcessNode> get nodes => _selectedTemplate.nodes;
  List<MaterialFlow> get flows => _selectedTemplate.flows;
  String? get selectedNodeId => _selectedNodeId;
  ProcessNode? get selectedNode => _selectedTemplate.nodes
      .where((node) => node.id == _selectedNodeId)
      .firstOrNull;
  (int lane, int stage) get focusedCell => _focusedCell;
  bool get isEditing => _isEditing;
  bool get isScanningMaterial => _isScanningMaterial;
  String? get scanErrorMessage => _scanErrorMessage;

  void selectTemplate(String templateId) {
    final match = _templates.where((template) => template.id == templateId);
    if (match.isEmpty) {
      return;
    }

    _selectedTemplate = match.first;
    _selectedNodeId = _selectedTemplate.nodes.firstOrNull?.id;
    if (_selectedTemplate.nodes.isNotEmpty) {
      final first = _selectedTemplate.nodes.first;
      _focusedCell = (first.laneIndex, first.stageIndex);
    } else {
      _focusedCell = (0, 0);
    }
    _isEditing = false;
    notifyListeners();
  }

  void selectNode(String nodeId) {
    final node = _selectedTemplate.nodes.where((item) => item.id == nodeId);
    if (node.isEmpty) {
      return;
    }

    _selectedNodeId = node.first.id;
    _focusedCell = (node.first.laneIndex, node.first.stageIndex);
    notifyListeners();
  }

  void focusCell(int laneIndex, int stageIndex) {
    final clampedLane = laneIndex.clamp(
      0,
      _selectedTemplate.laneLabels.length - 1,
    );
    final clampedStage = stageIndex.clamp(
      0,
      _selectedTemplate.stageLabels.length - 1,
    );
    _focusedCell = (clampedLane, clampedStage);
    notifyListeners();
  }

  void moveFocus(int laneDelta, int stageDelta) {
    focusCell(_focusedCell.$1 + laneDelta, _focusedCell.$2 + stageDelta);
  }

  void openFocusedNode() {
    final node = nodeAt(_focusedCell.$1, _focusedCell.$2);
    if (node != null) {
      _selectedNodeId = node.id;
      _isEditing = true;
      notifyListeners();
    }
  }

  void addNodeAtFocusedCell() {
    final lane = _focusedCell.$1;
    final stage = _focusedCell.$2;
    final existing = nodeAt(lane, stage);
    if (existing != null) {
      _selectedNodeId = existing.id;
      _isEditing = true;
      notifyListeners();
      return;
    }

    final node = ProcessNode(
      id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
      name: 'New Process',
      processType: 'Custom',
      stageIndex: stage,
      laneIndex: lane,
      inputs: const ['Input'],
      outputs: const ['Output'],
      machine: 'Unassigned',
      durationHours: 1,
      status: 'Queued',
      isIntermediate: true,
      scannedInputs: const [],
    );

    _selectedTemplate = _selectedTemplate.copyWith(
      nodes: [..._selectedTemplate.nodes, node],
    );
    _selectedNodeId = node.id;
    _isEditing = true;
    notifyListeners();
  }

  Future<MaterialRecord?> scanForNode(String nodeId, String barcode) async {
    if (barcode.trim().isEmpty) {
      _scanErrorMessage = 'Enter a barcode before scanning for a node.';
      notifyListeners();
      return null;
    }

    _isScanningMaterial = true;
    _scanErrorMessage = null;
    notifyListeners();

    try {
      final record = await _inventoryRepository.getMaterialByBarcode(barcode);
      if (record == null) {
        _scanErrorMessage = 'No material found for barcode $barcode.';
        return null;
      }

      _attachMaterialToNode(nodeId, record);
      return record;
    } catch (_) {
      _scanErrorMessage = 'Failed to attach scanned material.';
      return null;
    } finally {
      _isScanningMaterial = false;
      notifyListeners();
    }
  }

  void attachScannedMaterialRecord(String nodeId, MaterialRecord record) {
    _scanErrorMessage = null;
    _attachMaterialToNode(nodeId, record);
    notifyListeners();
  }

  void clearScanError() {
    if (_scanErrorMessage == null) {
      return;
    }
    _scanErrorMessage = null;
    notifyListeners();
  }

  void updateSelectedNode({
    String? processType,
    double? durationHours,
    List<String>? inputs,
    List<String>? outputs,
    String? machine,
  }) {
    final current = selectedNode;
    if (current == null) {
      return;
    }

    final updatedNode = current.copyWith(
      processType: processType,
      durationHours: durationHours,
      inputs: inputs,
      outputs: outputs,
      machine: machine,
    );

    final updatedNodes = _selectedTemplate.nodes
        .map((node) => node.id == current.id ? updatedNode : node)
        .toList(growable: false);

    _selectedTemplate = _selectedTemplate.copyWith(nodes: updatedNodes);
    _selectedNodeId = updatedNode.id;
    notifyListeners();
  }

  void toggleEditing(bool value) {
    if (_isEditing == value) {
      return;
    }

    _isEditing = value;
    notifyListeners();
  }

  ProcessNode? nodeAt(int laneIndex, int stageIndex) {
    return _selectedTemplate.nodes
        .where(
          (node) =>
              node.laneIndex == laneIndex && node.stageIndex == stageIndex,
        )
        .firstOrNull;
  }

  List<MaterialFlow> flowsForNode(String nodeId) {
    return _selectedTemplate.flows
        .where((flow) => flow.fromNodeId == nodeId || flow.toNodeId == nodeId)
        .toList(growable: false);
  }

  void _attachMaterialToNode(String nodeId, MaterialRecord record) {
    final updatedNodes = _selectedTemplate.nodes
        .map((node) {
          if (node.id != nodeId) {
            return node;
          }

          final scannedInput = BarcodeInput.fromMaterialRecord(record);
          final existing = node.scannedInputs.where(
            (item) => item.barcode == scannedInput.barcode,
          );
          final mergedInputs = existing.isEmpty
              ? [...node.scannedInputs, scannedInput]
              : node.scannedInputs
                    .map(
                      (item) => item.barcode == scannedInput.barcode
                          ? scannedInput
                          : item,
                    )
                    .toList(growable: false);

          final mergedNamedInputs = node.inputs.contains(record.name)
              ? node.inputs
              : [...node.inputs, record.name];

          return node.copyWith(
            inputs: mergedNamedInputs,
            scannedInputs: mergedInputs,
          );
        })
        .toList(growable: false);

    _selectedTemplate = _selectedTemplate.copyWith(nodes: updatedNodes);
    _selectedNodeId = nodeId;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
