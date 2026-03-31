import 'package:flutter/material.dart';

import '../../inventory/data/repositories/inventory_repository.dart';
import '../data/repositories/pipeline_run_repository.dart';
import '../domain/barcode_input.dart';
import '../domain/material_flow.dart';
import '../domain/node_run_status.dart';
import '../domain/pipeline_run.dart';
import '../domain/pipeline_template.dart';
import '../domain/process_node.dart';
import '../domain/run_overrides.dart';

enum PipelineMode { template, run }

class PipelinesProvider extends ChangeNotifier {
  PipelinesProvider({
    required InventoryRepository inventoryRepository,
    required PipelineRunRepository pipelineRepository,
  }) : _inventoryRepository = inventoryRepository,
       _pipelineRepository = pipelineRepository;

  final InventoryRepository _inventoryRepository;
  final PipelineRunRepository _pipelineRepository;

  List<PipelineTemplate> _templates = const [];
  List<PipelineRun> _runs = const [];
  PipelineTemplate? _activeTemplate;
  PipelineRun? _activeRun;
  PipelineMode _mode = PipelineMode.template;
  String? _selectedNodeId;
  (int lane, int stage) _focusedCell = (0, 0);
  bool _isEditing = false;
  bool _isLoading = false;
  bool _isScanningMaterial = false;
  String? _errorMessage;
  String? _scanErrorMessage;
  bool _initialized = false;

  List<PipelineTemplate> get templates => _templates;
  List<PipelineRun> get runs => _runs;
  PipelineTemplate? get activeTemplate => _activeTemplate;
  PipelineRun? get activeRun => _activeRun;
  PipelineMode get mode => _mode;
  String? get selectedNodeId => _selectedNodeId;
  (int lane, int stage) get focusedCell => _focusedCell;
  bool get isEditing => _isEditing;
  bool get isLoading => _isLoading;
  bool get isScanningMaterial => _isScanningMaterial;
  String? get errorMessage => _errorMessage;
  String? get scanErrorMessage => _scanErrorMessage;

  PipelineTemplate? get selectedTemplate => _activeTemplate;
  List<ProcessNode> get nodes => _activeTemplate?.nodes ?? const [];
  List<MaterialFlow> get flows => _activeTemplate?.flows ?? const [];
  ProcessNode? get selectedNode =>
      nodes.where((node) => node.id == _selectedNodeId).firstOrNull;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _templates = await _pipelineRepository.getTemplates();
      _activeTemplate = _templates.firstOrNull;
      _selectedNodeId = _activeTemplate?.nodes.firstOrNull?.id;
      if (_activeTemplate?.nodes.isNotEmpty ?? false) {
        final first = _activeTemplate!.nodes.first;
        _focusedCell = (first.laneIndex, first.stageIndex);
      }
      if (_activeTemplate != null) {
        await loadRunsForTemplate(_activeTemplate!.id, notify: false);
      }
    } catch (error) {
      _errorMessage = 'Failed to load production pipelines. $error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setMode(PipelineMode mode) async {
    if (_mode == mode) {
      return;
    }

    _mode = mode;
    _scanErrorMessage = null;
    if (mode == PipelineMode.run &&
        _activeRun == null &&
        _activeTemplate != null &&
        _runs.isNotEmpty) {
      _activeRun = _runs.first;
    }
    notifyListeners();
  }

  Future<void> selectTemplate(String templateId) async {
    final match = _templates.where((template) => template.id == templateId);
    if (match.isEmpty) {
      return;
    }

    _activeTemplate = match.first;
    _selectedNodeId = _activeTemplate?.nodes.firstOrNull?.id;
    if (_activeTemplate?.nodes.isNotEmpty ?? false) {
      final first = _activeTemplate!.nodes.first;
      _focusedCell = (first.laneIndex, first.stageIndex);
    } else {
      _focusedCell = (0, 0);
    }
    _activeRun = null;
    _mode = PipelineMode.template;
    _isEditing = false;
    _errorMessage = null;
    notifyListeners();
    await loadRunsForTemplate(templateId);
  }

  Future<void> loadRunsForTemplate(
    String templateId, {
    bool notify = true,
  }) async {
    try {
      _runs = await _pipelineRepository.getRuns(templateId: templateId);
      if (_mode == PipelineMode.run && _runs.isNotEmpty) {
        _activeRun ??= _runs.first;
      }
    } catch (error) {
      _errorMessage = 'Failed to load runs. $error';
    } finally {
      if (notify) {
        notifyListeners();
      }
    }
  }

  Future<void> startRun(String templateId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final run = await _pipelineRepository.createRun(
        templateId,
        name: 'Run ${DateTime.now().toIso8601String()}',
      );
      _runs = [run, ..._runs];
      _activeRun = run;
      _mode = PipelineMode.run;
      notifyListeners();
    } catch (error) {
      _errorMessage = 'Failed to start run. $error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectRun(String runId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final run = await _pipelineRepository.getRun(runId);
      if (run == null) {
        _errorMessage = 'Run not found.';
        return;
      }
      _activeRun = run;
      _mode = PipelineMode.run;
    } catch (error) {
      _errorMessage = 'Failed to load run. $error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectNode(String nodeId) {
    final node = nodes.where((item) => item.id == nodeId);
    if (node.isEmpty) {
      return;
    }
    _selectedNodeId = node.first.id;
    _focusedCell = (node.first.laneIndex, node.first.stageIndex);
    notifyListeners();
  }

  void focusCell(int laneIndex, int stageIndex) {
    final template = _activeTemplate;
    if (template == null) {
      return;
    }
    final clampedLane = laneIndex.clamp(0, template.laneLabels.length - 1);
    final clampedStage = stageIndex.clamp(0, template.stageLabels.length - 1);
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
    if (_mode == PipelineMode.run || _activeTemplate == null) {
      return;
    }
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

    _activeTemplate = _activeTemplate!.copyWith(
      nodes: [..._activeTemplate!.nodes, node],
    );
    _selectedNodeId = node.id;
    _isEditing = true;
    _replaceTemplate(_activeTemplate!);
    notifyListeners();
  }

  Future<void> persistTemplateEdits() async {
    if (_activeTemplate == null || _mode == PipelineMode.run) {
      return;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await _pipelineRepository.updateTemplate(
        _activeTemplate!,
      );
      _activeTemplate = updated;
      _replaceTemplate(updated);
    } catch (error) {
      _errorMessage = 'Failed to save template. $error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<BarcodeInput?> scanForNode(String nodeId, String barcode) async {
    if (_mode != PipelineMode.run || _activeRun == null) {
      _scanErrorMessage = 'Switch to a run before scanning materials.';
      notifyListeners();
      return null;
    }
    if (barcode.trim().isEmpty) {
      _scanErrorMessage = 'Enter a barcode before scanning for a node.';
      notifyListeners();
      return null;
    }

    _isScanningMaterial = true;
    _scanErrorMessage = null;
    notifyListeners();
    try {
      final normalizedBarcode = _normalizeBarcode(barcode);
      final materials = await _inventoryRepository.getAllMaterials();
      final material = materials
          .where((item) => _normalizeBarcode(item.barcode) == normalizedBarcode)
          .firstOrNull;

      if (material == null) {
        _scanErrorMessage = 'No inventory material found for $barcode.';
        return null;
      }

      final run = await _pipelineRepository.attachBarcodeToRunNode(
        runId: _activeRun!.id,
        nodeId: nodeId,
        barcode: material.barcode,
      );
      _activeRun = run;
      _runs = _runs.map((item) => item.id == run.id ? run : item).toList();
      return (_activeRun!.attachedBarcodeInputs[nodeId] ?? const []).lastWhere(
        (input) => _normalizeBarcode(input.barcode) == normalizedBarcode,
        orElse: () => BarcodeInput.fromMaterialRecord(material),
      );
    } catch (error) {
      _scanErrorMessage = 'Failed to attach scanned material. $error';
      return null;
    } finally {
      _isScanningMaterial = false;
      notifyListeners();
    }
  }

  Future<void> updateNodeStatus(
    String nodeId,
    NodeRunStatus status, {
    double? actualDurationHours,
    int? batchQuantity,
    String? machineOverride,
  }) async {
    if (_activeRun == null) {
      return;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final run = await _pipelineRepository.updateNodeStatus(
        runId: _activeRun!.id,
        nodeId: nodeId,
        status: status,
        actualDurationHours: actualDurationHours,
        batchQuantity: batchQuantity,
        machineOverride: machineOverride,
      );
      _activeRun = run;
      _runs = _runs.map((item) => item.id == run.id ? run : item).toList();
    } catch (error) {
      _errorMessage = 'Failed to update node status. $error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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
    if (current == null || _mode == PipelineMode.run) {
      return;
    }

    final updatedNode = current.copyWith(
      processType: processType,
      durationHours: durationHours,
      inputs: inputs,
      outputs: outputs,
      machine: machine,
    );

    final updatedNodes = nodes
        .map((node) => node.id == current.id ? updatedNode : node)
        .toList(growable: false);

    _activeTemplate = _activeTemplate!.copyWith(nodes: updatedNodes);
    _replaceTemplate(_activeTemplate!);
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
    return nodes
        .where(
          (node) =>
              node.laneIndex == laneIndex && node.stageIndex == stageIndex,
        )
        .firstOrNull;
  }

  List<MaterialFlow> flowsForNode(String nodeId) {
    return flows
        .where((flow) => flow.fromNodeId == nodeId || flow.toNodeId == nodeId)
        .toList(growable: false);
  }

  List<BarcodeInput> scannedInputsForNode(String nodeId) {
    if (_mode == PipelineMode.run && _activeRun != null) {
      return _activeRun!.attachedBarcodeInputs[nodeId] ?? const [];
    }
    return selectedTemplate?.nodes
            .where((node) => node.id == nodeId)
            .firstOrNull
            ?.scannedInputs ??
        const [];
  }

  NodeRunStatus statusForNode(String nodeId) {
    return _activeRun?.nodeStatuses[nodeId] ?? NodeRunStatus.pending;
  }

  RunOverrides get runOverrides =>
      _activeRun?.overrides ?? const RunOverrides();

  void _replaceTemplate(PipelineTemplate updatedTemplate) {
    _templates = _templates
        .map(
          (template) =>
              template.id == updatedTemplate.id ? updatedTemplate : template,
        )
        .toList(growable: false);
  }

  void deleteNode(String nodeId) {
    if (_activeTemplate == null || _mode == PipelineMode.run) {
      return;
    }

    final updatedTemplate = _activeTemplate!.copyWith(
      nodes: _activeTemplate!.nodes
          .where((node) => node.id != nodeId)
          .toList(growable: false),
      flows: _activeTemplate!.flows
          .where((flow) => flow.fromNodeId != nodeId && flow.toNodeId != nodeId)
          .toList(growable: false),
    );

    _activeTemplate = updatedTemplate;
    _replaceTemplate(updatedTemplate);
    if (_selectedNodeId == nodeId) {
      _selectedNodeId = updatedTemplate.nodes.firstOrNull?.id;
      _isEditing = false;
    }
    notifyListeners();
  }

  String _normalizeBarcode(String barcode) {
    return barcode.trim().toUpperCase();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
