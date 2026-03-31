import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_info_panel.dart';
import '../../../core/widgets/app_section_title.dart';
import '../../inventory/data/repositories/inventory_repository.dart';
import '../data/repositories/pipeline_run_repository.dart';
import '../domain/node_run_status.dart';
import '../domain/pipeline_template.dart';
import '../domain/process_node.dart';
import 'pipelines_provider.dart';
import 'widgets/pipeline_mode_dropdown.dart';

class PipelinesScreen extends StatelessWidget {
  const PipelinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => PipelinesProvider(
        inventoryRepository: context.read<InventoryRepository>(),
        pipelineRepository: context.read<PipelineRunRepository>(),
      )..initialize(),
      child: const _PipelinesCanvasView(),
    );
  }
}

class _PipelinesCanvasView extends StatefulWidget {
  const _PipelinesCanvasView();

  @override
  State<_PipelinesCanvasView> createState() => _PipelinesCanvasViewState();
}

class _PipelinesCanvasViewState extends State<_PipelinesCanvasView> {
  final FocusNode _keyboardFocusNode = FocusNode();

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PipelinesProvider>();
    final template = provider.activeTemplate;
    final selectedNode = provider.selectedNode;

    return Focus(
      autofocus: true,
      focusNode: _keyboardFocusNode,
      onKeyEvent: (_, event) => _handleKeyEvent(event, provider),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSectionTitle(
              title: template?.name ?? 'Production Pipelines',
              subtitle: provider.mode == PipelineMode.template
                  ? (template?.description ??
                        'Template editor for manufacturing DAGs.')
                  : 'Run mode locks the graph and tracks actual execution details.',
              trailing: SizedBox(
                width: 280,
                child: PipelineModeDropdown(
                  mode: provider.mode,
                  runs: provider.runs,
                  activeRunId: provider.activeRun?.id,
                  onTemplateSelected: () =>
                      provider.setMode(PipelineMode.template),
                  onRunSelected: provider.selectRun,
                  onStartRun: template == null
                      ? () {}
                      : () => provider.startRun(template.id),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ToolbarRow(
              provider: provider,
              selectedNode: selectedNode,
              onScanPressed: selectedNode == null
                  ? null
                  : () => _handleScanForNode(context, provider, selectedNode),
            ),
            if (provider.errorMessage != null) ...[
              const SizedBox(height: 12),
              _CanvasErrorBanner(message: provider.errorMessage!),
            ],
            if (provider.scanErrorMessage != null) ...[
              const SizedBox(height: 12),
              _CanvasErrorBanner(
                message: provider.scanErrorMessage!,
                accentColor: const Color(0xFFB91C1C),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 1220;
                  final canvas = _CanvasPanel(
                    template: template,
                    provider: provider,
                  );
                  final details = _NodeDetailsPanel(
                    provider: provider,
                    node: selectedNode,
                  );

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: canvas),
                        const SizedBox(width: 16),
                        SizedBox(width: 360, child: details),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      Expanded(child: canvas),
                      const SizedBox(height: 16),
                      SizedBox(height: 420, child: details),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(KeyEvent event, PipelinesProvider provider) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        provider.moveFocus(-1, 0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        provider.moveFocus(1, 0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        provider.moveFocus(0, -1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        provider.moveFocus(0, 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        provider.openFocusedNode();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyN:
        provider.addNodeAtFocusedCell();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  Future<void> _handleScanForNode(
    BuildContext context,
    PipelinesProvider provider,
    ProcessNode node,
  ) async {
    String? barcode;
    if (!kIsWeb && Platform.isAndroid) {
      barcode = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => const _PipelineBarcodeScannerScreen(),
          fullscreenDialog: true,
        ),
      );
    } else {
      barcode = await showDialog<String>(
        context: context,
        builder: (_) => const _ManualPipelineBarcodeDialog(),
      );
    }

    if (!context.mounted || barcode == null || barcode.trim().isEmpty) {
      return;
    }

    final attached = await provider.scanForNode(node.id, barcode);
    if (!context.mounted || attached == null) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${attached.barcode} attached to ${node.name} for the active run.',
        ),
      ),
    );
  }
}

class _ToolbarRow extends StatelessWidget {
  const _ToolbarRow({
    required this.provider,
    required this.selectedNode,
    required this.onScanPressed,
  });

  final PipelinesProvider provider;
  final ProcessNode? selectedNode;
  final VoidCallback? onScanPressed;

  @override
  Widget build(BuildContext context) {
    final template = provider.activeTemplate;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _InfoChip(label: 'Template', value: template?.name ?? '-'),
              const SizedBox(width: 16),
              _InfoChip(
                label: 'Mode',
                value: provider.mode == PipelineMode.template
                    ? 'Template'
                    : 'Run',
                accentColor: provider.mode == PipelineMode.template
                    ? const Color(0xFF6C63FF)
                    : const Color(0xFF16A34A),
              ),
              if (provider.activeRun != null) ...[
                const SizedBox(width: 16),
                _InfoChip(
                  label: 'Active Run',
                  value: provider.activeRun!.name,
                  accentColor: const Color(0xFF16A34A),
                ),
              ],
            ],
          ),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (provider.mode == PipelineMode.template)
              AppButton(
                label: 'Add Node',
                icon: Icons.add_box_outlined,
                variant: AppButtonVariant.secondary,
                onPressed: provider.addNodeAtFocusedCell,
              ),
            if (provider.mode == PipelineMode.template)
              AppButton(
                label: 'Save Template',
                icon: Icons.save_outlined,
                isLoading: provider.isLoading,
                onPressed: template == null
                    ? null
                    : provider.persistTemplateEdits,
              ),
            if (provider.mode == PipelineMode.run)
              AppButton(
                label: 'Scan Material for Selected Node',
                icon: Icons.qr_code_scanner,
                isLoading: provider.isScanningMaterial,
                onPressed: selectedNode == null ? null : onScanPressed,
              ),
          ],
        ),
      ],
    );
  }
}

class _CanvasPanel extends StatelessWidget {
  const _CanvasPanel({required this.template, required this.provider});

  final PipelineTemplate? template;
  final PipelinesProvider provider;

  @override
  Widget build(BuildContext context) {
    if (template == null) {
      return const AppCard(
        child: Center(
          child: Text(
            'No pipeline templates available yet.',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StageHeaders(stageLabels: template!.stageLabels),
                  const SizedBox(height: 12),
                  ...List.generate(
                    template!.laneLabels.length,
                    (laneIndex) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _LaneRow(
                        laneIndex: laneIndex,
                        laneLabel: template!.laneLabels[laneIndex],
                        template: template!,
                        provider: provider,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StageHeaders extends StatelessWidget {
  const _StageHeaders({required this.stageLabels});

  final List<String> stageLabels;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 120,
          child: Text(
            'Lanes',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
            ),
          ),
        ),
        ...List.generate(
          stageLabels.length,
          (index) => Container(
            width: 240,
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              'Stage ${index + 1}: ${stageLabels[index]}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF374151),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LaneRow extends StatelessWidget {
  const _LaneRow({
    required this.laneIndex,
    required this.laneLabel,
    required this.template,
    required this.provider,
  });

  final int laneIndex;
  final String laneLabel;
  final PipelineTemplate template;
  final PipelinesProvider provider;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              laneLabel,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
          ),
        ),
        ...List.generate(
          template.stageLabels.length,
          (stageIndex) => _CanvasCell(
            laneIndex: laneIndex,
            stageIndex: stageIndex,
            node: provider.nodeAt(laneIndex, stageIndex),
            provider: provider,
          ),
        ),
      ],
    );
  }
}

class _CanvasCell extends StatelessWidget {
  const _CanvasCell({
    required this.laneIndex,
    required this.stageIndex,
    required this.node,
    required this.provider,
  });

  final int laneIndex;
  final int stageIndex;
  final ProcessNode? node;
  final PipelinesProvider provider;

  @override
  Widget build(BuildContext context) {
    final isFocused =
        provider.focusedCell.$1 == laneIndex &&
        provider.focusedCell.$2 == stageIndex;
    final isSelected = provider.selectedNodeId == node?.id;

    return SizedBox(
      width: 240,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: GestureDetector(
          onTap: () {
            provider.focusCell(laneIndex, stageIndex);
            if (node != null) {
              provider.selectNode(node!.id);
            }
          },
          onDoubleTap: node == null ? null : provider.openFocusedNode,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            constraints: const BoxConstraints(minHeight: 190),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF6C63FF)
                    : isFocused
                    ? const Color(0xFFB7B2FF)
                    : const Color(0xFFD8DCE8),
                width: isSelected ? 2 : 1,
              ),
              color: isFocused ? const Color(0xFFF8F7FF) : Colors.transparent,
            ),
            padding: const EdgeInsets.all(8),
            child: node == null
                ? _EmptyCellHint(mode: provider.mode)
                : _ProcessNodeCard(node: node!, provider: provider),
          ),
        ),
      ),
    );
  }
}

class _EmptyCellHint extends StatelessWidget {
  const _EmptyCellHint({required this.mode});

  final PipelineMode mode;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            mode == PipelineMode.template
                ? Icons.add_box_outlined
                : Icons.grid_view,
            color: const Color(0xFF9CA3AF),
          ),
          const SizedBox(height: 10),
          Text(
            mode == PipelineMode.template
                ? 'Press N to add a node'
                : 'No node in this cell',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProcessNodeCard extends StatelessWidget {
  const _ProcessNodeCard({required this.node, required this.provider});

  final ProcessNode node;
  final PipelinesProvider provider;

  @override
  Widget build(BuildContext context) {
    final runStatus = provider.statusForNode(node.id);
    final scannedInputs = provider.scannedInputsForNode(node.id);
    final totalScanCount = scannedInputs.fold<int>(
      0,
      (sum, input) => sum + input.scanCount,
    );
    final overrides = provider.runOverrides;
    final actualDuration =
        overrides.actualDurationHoursByNode[node.id] ?? node.durationHours;
    final batchQuantity = overrides.batchQuantityByNode[node.id];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                node.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            _StatusPill(
              label: provider.mode == PipelineMode.template
                  ? node.status
                  : runStatus.label,
              color: provider.mode == PipelineMode.template
                  ? node.statusColor
                  : _runStatusColor(runStatus),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _TypeBadge(label: node.processType),
            _NodeMetaBadge(
              label: node.isIntermediate ? 'Intermediate' : 'Terminal',
              color: node.isIntermediate
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF0F766E),
            ),
            if (batchQuantity != null)
              _NodeMetaBadge(
                label: 'Batch $batchQuantity',
                color: const Color(0xFF7C3AED),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _TagRow(
          label: 'Inputs',
          values: node.inputs,
          dotColor: const Color(0xFF2563EB),
        ),
        const SizedBox(height: 6),
        _TagRow(
          label: 'Outputs',
          values: node.outputs,
          dotColor: const Color(0xFF16A34A),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(
              Icons.precision_manufacturing_outlined,
              size: 16,
              color: Color(0xFF6B7280),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                overrides.machineOverrideByNode[node.id] ?? node.machine,
                style: const TextStyle(
                  color: Color(0xFF374151),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(
              Icons.schedule_outlined,
              size: 16,
              color: Color(0xFF6B7280),
            ),
            const SizedBox(width: 6),
            Text(
              provider.mode == PipelineMode.template
                  ? 'ETA ${node.durationHours.toStringAsFixed(1)} h'
                  : 'Actual ${actualDuration.toStringAsFixed(1)} h',
              style: const TextStyle(
                color: Color(0xFF374151),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (provider.mode == PipelineMode.run) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: _progressForStatus(runStatus),
            backgroundColor: const Color(0xFFE5E7EB),
            valueColor: AlwaysStoppedAnimation<Color>(
              _runStatusColor(runStatus),
            ),
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
          ),
        ],
        if (scannedInputs.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'Scanned Inputs',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 6),
          ...scannedInputs
              .take(3)
              .map(
                (input) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${input.barcode} : ${input.materialName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
        ],
        if (totalScanCount > 0) ...[
          const SizedBox(height: 8),
          _NodeMetaBadge(
            label: 'Scan count $totalScanCount',
            color: const Color(0xFF6C63FF),
          ),
        ],
        const Spacer(),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: provider.mode == PipelineMode.template
              ? [
                  _MiniActionChip(
                    label: 'Edit',
                    icon: Icons.edit_outlined,
                    onTap: () {
                      provider.selectNode(node.id);
                      provider.toggleEditing(true);
                    },
                  ),
                  _MiniActionChip(
                    label: 'Connect',
                    icon: Icons.share_outlined,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Connections are defined in the detail panel for now.',
                          ),
                        ),
                      );
                    },
                  ),
                  _MiniActionChip(
                    label: 'Delete',
                    icon: Icons.delete_outline,
                    onTap: () => provider.deleteNode(node.id),
                  ),
                ]
              : [
                  _MiniActionChip(
                    label: 'Mark done',
                    icon: Icons.task_alt_outlined,
                    onTap: () =>
                        provider.updateNodeStatus(node.id, NodeRunStatus.done),
                  ),
                  _MiniActionChip(
                    label: 'Open details',
                    icon: Icons.open_in_new_outlined,
                    onTap: () {
                      provider.selectNode(node.id);
                      provider.toggleEditing(true);
                    },
                  ),
                ],
        ),
      ],
    );
  }
}

class _NodeDetailsPanel extends StatelessWidget {
  const _NodeDetailsPanel({required this.provider, required this.node});

  final PipelinesProvider provider;
  final ProcessNode? node;

  @override
  Widget build(BuildContext context) {
    if (node == null) {
      return const AppCard(
        child: Center(
          child: Text(
            'Select a node to inspect or edit its details.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
        ),
      );
    }

    if (provider.mode == PipelineMode.template) {
      return _TemplateNodeDetailPanel(provider: provider, node: node!);
    }
    return _RunNodeDetailPanel(provider: provider, node: node!);
  }
}

class _TemplateNodeDetailPanel extends StatefulWidget {
  const _TemplateNodeDetailPanel({required this.provider, required this.node});

  final PipelinesProvider provider;
  final ProcessNode node;

  @override
  State<_TemplateNodeDetailPanel> createState() =>
      _TemplateNodeDetailPanelState();
}

class _TemplateNodeDetailPanelState extends State<_TemplateNodeDetailPanel> {
  late final TextEditingController _processTypeController;
  late final TextEditingController _durationController;
  late final TextEditingController _inputsController;
  late final TextEditingController _outputsController;
  late final TextEditingController _machineController;

  @override
  void initState() {
    super.initState();
    _processTypeController = TextEditingController();
    _durationController = TextEditingController();
    _inputsController = TextEditingController();
    _outputsController = TextEditingController();
    _machineController = TextEditingController();
    _syncFromNode();
  }

  @override
  void didUpdateWidget(covariant _TemplateNodeDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _syncFromNode();
    }
  }

  @override
  void dispose() {
    _processTypeController.dispose();
    _durationController.dispose();
    _inputsController.dispose();
    _outputsController.dispose();
    _machineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flows = widget.provider.flowsForNode(widget.node.id);

    return AppCard(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSectionTitle(
              title: widget.node.name,
              subtitle: 'Template mode edits the canonical pipeline graph.',
            ),
            const SizedBox(height: 18),
            _EditableField(
              label: 'Process type',
              controller: _processTypeController,
            ),
            const SizedBox(height: 12),
            _EditableField(
              label: 'Duration (hours)',
              controller: _durationController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 12),
            _EditableField(label: 'Inputs', controller: _inputsController),
            const SizedBox(height: 12),
            _EditableField(label: 'Outputs', controller: _outputsController),
            const SizedBox(height: 12),
            _EditableField(label: 'Machine', controller: _machineController),
            const SizedBox(height: 18),
            const Text(
              'Connections',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            if (flows.isEmpty)
              const Text(
                'No flows connected yet.',
                style: TextStyle(color: Color(0xFF6B7280)),
              )
            else
              ...flows.map(
                (flow) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${flow.fromNodeId == widget.node.id ? 'Outputs to' : 'Receives from'} ${flow.materialName}',
                    style: const TextStyle(
                      color: Color(0xFF374151),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            AppButton(
              label: 'Apply Template Changes',
              icon: Icons.check_circle_outline,
              onPressed: _applyChanges,
            ),
          ],
        ),
      ),
    );
  }

  void _syncFromNode() {
    _processTypeController.text = widget.node.processType;
    _durationController.text = widget.node.durationHours.toStringAsFixed(1);
    _inputsController.text = widget.node.inputs.join(', ');
    _outputsController.text = widget.node.outputs.join(', ');
    _machineController.text = widget.node.machine;
  }

  void _applyChanges() {
    widget.provider.updateSelectedNode(
      processType: _processTypeController.text.trim(),
      durationHours:
          double.tryParse(_durationController.text.trim()) ??
          widget.node.durationHours,
      inputs: _splitTags(_inputsController.text),
      outputs: _splitTags(_outputsController.text),
      machine: _machineController.text.trim(),
    );
    widget.provider.toggleEditing(true);
  }
}

class _RunNodeDetailPanel extends StatefulWidget {
  const _RunNodeDetailPanel({required this.provider, required this.node});

  final PipelinesProvider provider;
  final ProcessNode node;

  @override
  State<_RunNodeDetailPanel> createState() => _RunNodeDetailPanelState();
}

class _RunNodeDetailPanelState extends State<_RunNodeDetailPanel> {
  late final TextEditingController _actualDurationController;
  late final TextEditingController _batchQuantityController;
  late final TextEditingController _machineController;
  late NodeRunStatus _status;

  @override
  void initState() {
    super.initState();
    _actualDurationController = TextEditingController();
    _batchQuantityController = TextEditingController();
    _machineController = TextEditingController();
    _syncFromRun();
  }

  @override
  void didUpdateWidget(covariant _RunNodeDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id ||
        oldWidget.provider.activeRun?.id != widget.provider.activeRun?.id) {
      _syncFromRun();
    }
  }

  @override
  void dispose() {
    _actualDurationController.dispose();
    _batchQuantityController.dispose();
    _machineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overrides = widget.provider.runOverrides;
    final scannedInputs = widget.provider.scannedInputsForNode(widget.node.id);

    return AppCard(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSectionTitle(
              title: widget.node.name,
              subtitle:
                  'Run mode keeps template geometry read-only and tracks actual execution overrides.',
            ),
            const SizedBox(height: 18),
            AppInfoPanel(
              title: 'Template Fields',
              subtitle: 'Read-only during a production run.',
              rows: [
                AppInfoRow(
                  label: 'Process type',
                  value: widget.node.processType,
                ),
                AppInfoRow(
                  label: 'Inputs',
                  value: widget.node.inputs.join(', '),
                ),
                AppInfoRow(
                  label: 'Outputs',
                  value: widget.node.outputs.join(', '),
                ),
                AppInfoRow(label: 'Machine', value: widget.node.machine),
                AppInfoRow(
                  label: 'Est. duration',
                  value: '${widget.node.durationHours.toStringAsFixed(1)} h',
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Run Overrides',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<NodeRunStatus>(
              initialValue: _status,
              decoration: _fieldDecoration('Node status'),
              items: NodeRunStatus.values
                  .map(
                    (status) => DropdownMenuItem<NodeRunStatus>(
                      value: status,
                      child: Text(status.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _status = value);
              },
            ),
            const SizedBox(height: 12),
            _EditableField(
              label: 'Actual duration (hours)',
              controller: _actualDurationController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 12),
            _EditableField(
              label: 'Batch quantity',
              controller: _batchQuantityController,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _EditableField(
              label: 'Machine override',
              controller: _machineController,
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'Save Run Details',
              icon: Icons.save_outlined,
              isLoading: widget.provider.isLoading,
              onPressed: () => widget.provider.updateNodeStatus(
                widget.node.id,
                _status,
                actualDurationHours:
                    double.tryParse(_actualDurationController.text.trim()) ??
                    overrides.actualDurationHoursByNode[widget.node.id],
                batchQuantity: int.tryParse(
                  _batchQuantityController.text.trim(),
                ),
                machineOverride: _machineController.text.trim().isEmpty
                    ? null
                    : _machineController.text.trim(),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Attached Lots',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 10),
            if (scannedInputs.isEmpty)
              const Text(
                'No barcodes attached to this run node yet.',
                style: TextStyle(color: Color(0xFF6B7280)),
              )
            else
              ...scannedInputs.map(
                (input) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: const EdgeInsets.all(12),
                    backgroundColor: const Color(0xFFF8F7FF),
                    borderColor: const Color(0xFFE0DEFF),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                input.barcode,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${input.materialName} • ${input.materialType}',
                                style: const TextStyle(
                                  color: Color(0xFF4B5563),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _NodeMetaBadge(
                          label: 'Scanned ${input.scanCount}',
                          color: const Color(0xFF6C63FF),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _syncFromRun() {
    final overrides = widget.provider.runOverrides;
    _status = widget.provider.statusForNode(widget.node.id);
    _actualDurationController.text =
        (overrides.actualDurationHoursByNode[widget.node.id] ??
                widget.node.durationHours)
            .toStringAsFixed(1);
    _batchQuantityController.text =
        overrides.batchQuantityByNode[widget.node.id]?.toString() ?? '';
    _machineController.text =
        overrides.machineOverrideByNode[widget.node.id] ?? widget.node.machine;
  }
}

class _EditableField extends StatelessWidget {
  const _EditableField({
    required this.label,
    required this.controller,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: _fieldDecoration(label),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.value,
    this.accentColor = const Color(0xFF6C63FF),
  });

  final String label;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w700, color: accentColor),
        ),
      ],
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F1FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF5B52E6),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _NodeMetaBadge extends StatelessWidget {
  const _NodeMetaBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MiniActionChip extends StatelessWidget {
  const _MiniActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFD8DCE8)),
          color: Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: const Color(0xFF4B5563)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF374151),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.label,
    required this.values,
    required this.dotColor,
  });

  final String label;
  final List<String> values;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values
              .map(
                (value) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: dotColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _CanvasErrorBanner extends StatelessWidget {
  const _CanvasErrorBanner({
    required this.message,
    this.accentColor = const Color(0xFFB45309),
  });

  final String message;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentColor.withValues(alpha: 0.24)),
      ),
      child: Text(
        message,
        style: TextStyle(color: accentColor, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ManualPipelineBarcodeDialog extends StatefulWidget {
  const _ManualPipelineBarcodeDialog();

  @override
  State<_ManualPipelineBarcodeDialog> createState() =>
      _ManualPipelineBarcodeDialogState();
}

class _ManualPipelineBarcodeDialogState
    extends State<_ManualPipelineBarcodeDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Lookup Material Barcode'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: _fieldDecoration('Barcode'),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        AppButton(
          label: 'Attach',
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        ),
      ],
    );
  }
}

class _PipelineBarcodeScannerScreen extends StatefulWidget {
  const _PipelineBarcodeScannerScreen();

  @override
  State<_PipelineBarcodeScannerScreen> createState() =>
      _PipelineBarcodeScannerScreenState();
}

class _PipelineBarcodeScannerScreenState
    extends State<_PipelineBarcodeScannerScreen>
    with WidgetsBindingObserver {
  final TextEditingController _manualController = TextEditingController();
  late final MobileScannerController _controller;
  StreamSubscription<BarcodeCapture>? _subscription;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
    _subscription = _controller.barcodes.listen(_handleCapture);
    unawaited(_controller.start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _manualController.dispose();
    unawaited(_subscription?.cancel());
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_paused) {
          unawaited(_controller.start());
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(_controller.stop());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan Material Barcode'),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: MobileScanner(controller: _controller)),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xCCFFFFFF), width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 32,
            child: AppCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Align the barcode inside the frame or enter it manually.',
                    style: TextStyle(
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _manualController,
                    decoration: _fieldDecoration('Manual barcode'),
                    onSubmitted: _finish,
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    label: 'Use Manual Barcode',
                    onPressed: () => _finish(_manualController.text),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCapture(BarcodeCapture capture) async {
    if (_paused) {
      return;
    }
    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null || barcode.trim().isEmpty) {
      return;
    }
    _paused = true;
    await _controller.stop();
    _finish(barcode);
  }

  void _finish(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }
    Navigator.of(context).pop(trimmed);
  }
}

InputDecoration _fieldDecoration(String label) {
  return InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFD8DCE8)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
    ),
  );
}

List<String> _splitTags(String value) {
  return value
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
}

Color _runStatusColor(NodeRunStatus status) {
  switch (status) {
    case NodeRunStatus.pending:
      return const Color(0xFFF59E0B);
    case NodeRunStatus.active:
      return const Color(0xFF2563EB);
    case NodeRunStatus.done:
      return const Color(0xFF16A34A);
    case NodeRunStatus.skipped:
      return const Color(0xFF6B7280);
  }
}

double _progressForStatus(NodeRunStatus status) {
  switch (status) {
    case NodeRunStatus.pending:
      return 0.2;
    case NodeRunStatus.active:
      return 0.6;
    case NodeRunStatus.done:
      return 1.0;
    case NodeRunStatus.skipped:
      return 0.4;
  }
}
