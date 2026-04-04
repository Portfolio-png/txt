import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_info_panel.dart';
import '../../../core/widgets/app_section_title.dart';
import '../../inventory/data/repositories/inventory_repository.dart';
import '../../inventory/domain/material_record.dart';
import '../../inventory/presentation/screens/material_scan_screen.dart';
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
      child: const _PipelinesView(),
    );
  }
}

class _PipelinesView extends StatelessWidget {
  const _PipelinesView();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PipelinesProvider>();
    final template = provider.activeTemplate;
    final selectedNode = provider.selectedNode;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionTitle(
            title: template?.name ?? 'Production Pipelines',
            subtitle: provider.mode == PipelineMode.template
                ? 'Grid-based template editor for manufacturing stages and lanes.'
                : 'Run mode tracks node status and attached scanned materials.',
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
          _PipelinesToolbar(provider: provider, selectedNode: selectedNode),
          if (provider.errorMessage != null) ...[
            const SizedBox(height: 12),
            _MessageBanner(message: provider.errorMessage!),
          ],
          if (provider.scanErrorMessage != null) ...[
            const SizedBox(height: 12),
            _MessageBanner(
              message: provider.scanErrorMessage!,
              color: const Color(0xFFB91C1C),
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 1200;
                final canvas = _PipelineCanvas(
                  provider: provider,
                  template: template,
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
    );
  }
}

class _PipelinesToolbar extends StatelessWidget {
  const _PipelinesToolbar({required this.provider, required this.selectedNode});

  final PipelinesProvider provider;
  final ProcessNode? selectedNode;

  @override
  Widget build(BuildContext context) {
    return Wrap(
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
            onPressed: provider.persistTemplateEdits,
          ),
        if (provider.mode == PipelineMode.run)
          AppButton(
            label: 'Scan Material for Selected Node',
            icon: Icons.qr_code_scanner_outlined,
            isLoading: provider.isScanningMaterial,
            onPressed: selectedNode == null
                ? null
                : () => _scanForSelectedNode(context, provider, selectedNode!),
          ),
      ],
    );
  }

  Future<void> _scanForSelectedNode(
    BuildContext context,
    PipelinesProvider provider,
    ProcessNode node,
  ) async {
    String? barcode;
    if (!kIsWeb && Platform.isAndroid) {
      final scannedRecord = await Navigator.of(context).push<MaterialRecord>(
        MaterialPageRoute(
          builder: (_) => const MaterialScanScreen(popOnSuccess: true),
          fullscreenDialog: true,
        ),
      );
      barcode = scannedRecord?.barcode;
    } else {
      barcode = await showDialog<String>(
        context: context,
        builder: (_) => const _ManualBarcodeDialog(),
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
        content: Text('${attached.materialName} attached to ${node.name}.'),
      ),
    );
  }
}

class _PipelineCanvas extends StatelessWidget {
  const _PipelineCanvas({required this.provider, required this.template});

  final PipelinesProvider provider;
  final PipelineTemplate? template;

  @override
  Widget build(BuildContext context) {
    if (template == null) {
      return const AppCard(
        child: Center(
          child: Text(
            'No pipeline templates available.',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF374151),
            ),
          ),
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(width: 120),
                  ...List.generate(
                    template!.stageLabels.length,
                    (stageIndex) => SizedBox(
                      width: 240,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          'Stage ${stageIndex + 1}: ${template!.stageLabels[stageIndex]}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF374151),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...List.generate(
                template!.laneLabels.length,
                (laneIndex) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            template!.laneLabels[laneIndex],
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                      ),
                      ...List.generate(
                        template!.stageLabels.length,
                        (stageIndex) => _PipelineCell(
                          provider: provider,
                          laneIndex: laneIndex,
                          stageIndex: stageIndex,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PipelineCell extends StatelessWidget {
  const _PipelineCell({
    required this.provider,
    required this.laneIndex,
    required this.stageIndex,
  });

  final PipelinesProvider provider;
  final int laneIndex;
  final int stageIndex;

  @override
  Widget build(BuildContext context) {
    final node = provider.nodeAt(laneIndex, stageIndex);
    final isSelected = provider.selectedNodeId == node?.id;
    final isFocused =
        provider.focusedCell.$1 == laneIndex &&
        provider.focusedCell.$2 == stageIndex;

    return SizedBox(
      width: 240,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            provider.focusCell(laneIndex, stageIndex);
            if (node != null) {
              provider.selectNode(node.id);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            constraints: const BoxConstraints(minHeight: 180),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isFocused ? const Color(0xFFF8F7FF) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF6C63FF)
                    : isFocused
                    ? const Color(0xFFB7B2FF)
                    : const Color(0xFFD8DCE8),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: node == null
                ? _EmptyPipelineCell(mode: provider.mode)
                : _NodeCard(provider: provider, node: node),
          ),
        ),
      ),
    );
  }
}

class _EmptyPipelineCell extends StatelessWidget {
  const _EmptyPipelineCell({required this.mode});

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
                : Icons.grid_view_outlined,
            color: const Color(0xFF9CA3AF),
          ),
          const SizedBox(height: 8),
          Text(
            mode == PipelineMode.template
                ? 'Use Add Node to place a process here.'
                : 'No node in this slot.',
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

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.provider, required this.node});

  final PipelinesProvider provider;
  final ProcessNode node;

  @override
  Widget build(BuildContext context) {
    final scannedInputs = provider.scannedInputsForNode(node.id);
    final runStatus = provider.statusForNode(node.id);
    final totalScanCount = scannedInputs.fold<int>(
      0,
      (sum, item) => sum + item.scanCount,
    );

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
            _Badge(
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
        _Badge(label: node.processType, color: const Color(0xFF6C63FF)),
        const SizedBox(height: 10),
        _TagLine(
          label: 'Inputs',
          values: node.inputs,
          dotColor: const Color(0xFF2563EB),
        ),
        const SizedBox(height: 6),
        _TagLine(
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
                node.machine,
                style: const TextStyle(
                  color: Color(0xFF374151),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          provider.mode == PipelineMode.template
              ? 'ETA ${node.durationHours.toStringAsFixed(1)} h'
              : 'Run status: ${runStatus.label}',
          style: const TextStyle(
            color: Color(0xFF4B5563),
            fontWeight: FontWeight.w600,
          ),
        ),
        if (scannedInputs.isNotEmpty) ...[
          const SizedBox(height: 10),
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
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
              ),
        ],
        if (totalScanCount > 0) ...[
          const SizedBox(height: 8),
          _Badge(
            label: 'Scan count $totalScanCount',
            color: const Color(0xFF7C3AED),
          ),
        ],
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
            'Select a node to inspect its template or run details.',
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
      return AppInfoPanel(
        title: node!.name,
        subtitle: 'Template mode keeps the graph editable.',
        rows: [
          AppInfoRow(label: 'Process type', value: node!.processType),
          AppInfoRow(
            label: 'Duration',
            value: '${node!.durationHours.toStringAsFixed(1)} hours',
          ),
          AppInfoRow(label: 'Machine', value: node!.machine),
          AppInfoRow(label: 'Inputs', value: node!.inputs.join(', ')),
          AppInfoRow(label: 'Outputs', value: node!.outputs.join(', ')),
          AppInfoRow(
            label: 'Connections',
            value:
                provider
                    .flowsForNode(node!.id)
                    .map((flow) => flow.materialName)
                    .join(', ')
                    .trim()
                    .isEmpty
                ? 'No connections yet'
                : provider
                      .flowsForNode(node!.id)
                      .map((flow) => flow.materialName)
                      .join(', '),
          ),
        ],
        footer: AppButton(
          label: 'Save Template',
          icon: Icons.save_outlined,
          isLoading: provider.isLoading,
          onPressed: provider.persistTemplateEdits,
        ),
      );
    }

    return _RunDetailsPanel(provider: provider, node: node!);
  }
}

class _RunDetailsPanel extends StatefulWidget {
  const _RunDetailsPanel({required this.provider, required this.node});

  final PipelinesProvider provider;
  final ProcessNode node;

  @override
  State<_RunDetailsPanel> createState() => _RunDetailsPanelState();
}

class _RunDetailsPanelState extends State<_RunDetailsPanel> {
  late final TextEditingController _durationController;
  late final TextEditingController _batchController;
  late final TextEditingController _machineController;
  late NodeRunStatus _status;

  @override
  void initState() {
    super.initState();
    _durationController = TextEditingController();
    _batchController = TextEditingController();
    _machineController = TextEditingController();
    _syncFromRun();
  }

  @override
  void didUpdateWidget(covariant _RunDetailsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id ||
        oldWidget.provider.activeRun?.id != widget.provider.activeRun?.id) {
      _syncFromRun();
    }
  }

  @override
  void dispose() {
    _durationController.dispose();
    _batchController.dispose();
    _machineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scannedInputs = widget.provider.scannedInputsForNode(widget.node.id);

    return AppCard(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSectionTitle(
              title: widget.node.name,
              subtitle:
                  'Run mode is read-only for the template and editable for execution data.',
            ),
            const SizedBox(height: 16),
            AppInfoPanel(
              title: 'Template Snapshot',
              rows: [
                AppInfoRow(
                  label: 'Process type',
                  value: widget.node.processType,
                ),
                AppInfoRow(label: 'Machine', value: widget.node.machine),
                AppInfoRow(
                  label: 'Inputs',
                  value: widget.node.inputs.join(', '),
                ),
                AppInfoRow(
                  label: 'Outputs',
                  value: widget.node.outputs.join(', '),
                ),
              ],
            ),
            const SizedBox(height: 16),
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
                if (value != null) {
                  setState(() => _status = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _durationController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: _fieldDecoration('Actual duration (hours)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _batchController,
              keyboardType: TextInputType.number,
              decoration: _fieldDecoration('Batch quantity'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _machineController,
              decoration: _fieldDecoration('Machine override'),
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'Save Run Details',
              icon: Icons.save_outlined,
              isLoading: widget.provider.isLoading,
              onPressed: () => widget.provider.updateNodeStatus(
                widget.node.id,
                _status,
                actualDurationHours: double.tryParse(
                  _durationController.text.trim(),
                ),
                batchQuantity: int.tryParse(_batchController.text.trim()),
                machineOverride: _machineController.text.trim(),
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
                'No barcodes attached yet.',
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
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF4B5563),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _Badge(
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
    _durationController.text =
        (overrides.actualDurationHoursByNode[widget.node.id] ??
                widget.node.durationHours)
            .toStringAsFixed(1);
    _batchController.text =
        overrides.batchQuantityByNode[widget.node.id]?.toString() ?? '';
    _machineController.text =
        overrides.machineOverrideByNode[widget.node.id] ?? widget.node.machine;
  }
}

class _ManualBarcodeDialog extends StatefulWidget {
  const _ManualBarcodeDialog();

  @override
  State<_ManualBarcodeDialog> createState() => _ManualBarcodeDialogState();
}

class _ManualBarcodeDialogState extends State<_ManualBarcodeDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter barcode'),
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
          label: 'Lookup',
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        ),
      ],
    );
  }
}

class _TagLine extends StatelessWidget {
  const _TagLine({
    required this.label,
    required this.values,
    required this.dotColor,
  });

  final String label;
  final List<String> values;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '$label:',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6B7280),
          ),
        ),
        ...values.map(
          (value) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                    color: dotColor,
                    shape: BoxShape.circle,
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
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

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

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({
    required this.message,
    this.color = const Color(0xFF92400E),
  });

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        message,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
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
