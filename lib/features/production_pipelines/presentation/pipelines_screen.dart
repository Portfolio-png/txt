import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_info_panel.dart';
import '../../../core/widgets/app_section_title.dart';
import '../../inventory/data/repositories/inventory_repository.dart';
import '../../inventory/domain/material_record.dart';
import '../../inventory/presentation/screens/material_scan_screen.dart';
import '../domain/barcode_input.dart';
import '../domain/process_node.dart';
import 'pipelines_provider.dart';

class PipelinesScreen extends StatelessWidget {
  const PipelinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => PipelinesProvider(
        inventoryRepository: context.read<InventoryRepository>(),
      ),
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
  final FocusNode _keyboardFocusNode = FocusNode(
    debugLabel: 'pipelines-canvas',
  );

  bool get _isAndroidPlatform => !kIsWeb && Platform.isAndroid;

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PipelinesProvider>(
      builder: (context, provider, _) {
        final isStacked = MediaQuery.of(context).size.width < 1100;

        return Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.arrowUp): _MoveIntent(-1, 0),
            SingleActivator(LogicalKeyboardKey.arrowDown): _MoveIntent(1, 0),
            SingleActivator(LogicalKeyboardKey.arrowLeft): _MoveIntent(0, -1),
            SingleActivator(LogicalKeyboardKey.arrowRight): _MoveIntent(0, 1),
            SingleActivator(LogicalKeyboardKey.keyN): _AddNodeIntent(),
            SingleActivator(LogicalKeyboardKey.enter): _OpenNodeIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _MoveIntent: CallbackAction<_MoveIntent>(
                onInvoke: (intent) {
                  provider.moveFocus(intent.laneDelta, intent.stageDelta);
                  return null;
                },
              ),
              _AddNodeIntent: CallbackAction<_AddNodeIntent>(
                onInvoke: (intent) {
                  provider.addNodeAtFocusedCell();
                  return null;
                },
              ),
              _OpenNodeIntent: CallbackAction<_OpenNodeIntent>(
                onInvoke: (intent) {
                  provider.openFocusedNode();
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              focusNode: _keyboardFocusNode,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSectionTitle(
                      title: 'Production Pipelines Canvas',
                      subtitle:
                          'Grid-based template editor for stage-by-stage process planning. Arrow keys move focus, N adds a node, Enter opens details.',
                      trailing: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: 280,
                              child: DropdownButtonFormField<String>(
                                initialValue: provider.selectedTemplate.id,
                                decoration: InputDecoration(
                                  labelText: 'Pipeline Template',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                                items: provider.templates
                                    .map(
                                      (template) => DropdownMenuItem<String>(
                                        value: template.id,
                                        child: Text(template.name),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: (value) {
                                  if (value != null) {
                                    provider.selectTemplate(value);
                                  }
                                },
                              ),
                            ),
                            AppButton(
                              label: 'Scan Material for Selected Node',
                              icon: Icons.qr_code_scanner_outlined,
                              isLoading: provider.isScanningMaterial,
                              onPressed: provider.selectedNode == null
                                  ? null
                                  : () => _startNodeScan(
                                      context,
                                      provider,
                                      provider.selectedNode!,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (provider.scanErrorMessage != null) ...[
                      const SizedBox(height: 12),
                      _CanvasErrorBanner(message: provider.scanErrorMessage!),
                    ],
                    const SizedBox(height: 18),
                    Expanded(
                      child: isStacked
                          ? ListView(
                              children: [
                                _CanvasPanel(
                                  templateDescription:
                                      provider.selectedTemplate.description,
                                ),
                                const SizedBox(height: 16),
                                const SizedBox(
                                  height: 520,
                                  child: _NodeDetailsPanel(),
                                ),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: _CanvasPanel(
                                    templateDescription:
                                        provider.selectedTemplate.description,
                                  ),
                                ),
                                const SizedBox(width: 20),
                                const Expanded(
                                  flex: 2,
                                  child: _NodeDetailsPanel(),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _startNodeScan(
    BuildContext context,
    PipelinesProvider provider,
    ProcessNode node,
  ) async {
    provider.clearScanError();

    if (_isAndroidPlatform) {
      final record = await Navigator.of(context).push<MaterialRecord>(
        MaterialPageRoute<MaterialRecord>(
          fullscreenDialog: true,
          builder: (_) => const MaterialScanScreen(popOnSuccess: true),
        ),
      );
      if (!mounted || record == null) {
        return;
      }
      provider.attachScannedMaterialRecord(node.id, record);
      return;
    }

    final barcode = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _ManualPipelineBarcodeDialog(),
    );
    if (!mounted || barcode == null || barcode.trim().isEmpty) {
      return;
    }
    await provider.scanForNode(node.id, barcode);
  }
}

class _CanvasPanel extends StatelessWidget {
  const _CanvasPanel({required this.templateDescription});

  final String templateDescription;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PipelinesProvider>();
    final template = provider.selectedTemplate;
    const laneLabelWidth = 120.0;
    const cellWidth = 220.0;
    const cellHeight = 160.0;
    const canvasHeight = 620.0;

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        height: canvasHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              template.name,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              templateDescription,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7280)),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width:
                        laneLabelWidth +
                        (template.stageLabels.length * cellWidth),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const SizedBox(width: laneLabelWidth),
                            ...List.generate(
                              template.stageLabels.length,
                              (stageIndex) => _StageHeaderCell(
                                label: template.stageLabels[stageIndex],
                                width: cellWidth,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: ListView.separated(
                            itemCount: template.laneLabels.length,
                            separatorBuilder: (_, index) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, laneIndex) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: laneLabelWidth,
                                    height: cellHeight,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        template.laneLabels[laneIndex],
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF374151),
                                            ),
                                      ),
                                    ),
                                  ),
                                  ...List.generate(
                                    template.stageLabels.length,
                                    (stageIndex) => _CanvasCell(
                                      laneIndex: laneIndex,
                                      stageIndex: stageIndex,
                                      width: cellWidth,
                                      height: cellHeight,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StageHeaderCell extends StatelessWidget {
  const _StageHeaderCell({required this.label, required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F0FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD9D3FF)),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF4338CA),
            ),
          ),
        ),
      ),
    );
  }
}

class _CanvasCell extends StatelessWidget {
  const _CanvasCell({
    required this.laneIndex,
    required this.stageIndex,
    required this.width,
    required this.height,
  });

  final int laneIndex;
  final int stageIndex;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PipelinesProvider>();
    final focused = provider.focusedCell == (laneIndex, stageIndex);
    final node = provider.nodeAt(laneIndex, stageIndex);

    return SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: GestureDetector(
          onTap: () {
            provider.focusCell(laneIndex, stageIndex);
            if (node != null) {
              provider.selectNode(node.id);
            }
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: focused
                  ? const Color(0xFFF6F3FF)
                  : const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: focused
                    ? const Color(0xFF6C63FF)
                    : const Color(0xFFE5E7EB),
                width: focused ? 2 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: node == null
                  ? _EmptyCellHint(
                      isFocused: focused,
                      onAdd: provider.addNodeAtFocusedCell,
                    )
                  : _ProcessNodeCard(node: node),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyCellHint extends StatelessWidget {
  const _EmptyCellHint({required this.isFocused, required this.onAdd});

  final bool isFocused;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onAdd,
      borderRadius: BorderRadius.circular(8),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_circle_outline,
              color: isFocused
                  ? const Color(0xFF6C63FF)
                  : const Color(0xFF9CA3AF),
            ),
            const SizedBox(height: 8),
            Text(
              'Press N or tap to add',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProcessNodeCard extends StatelessWidget {
  const _ProcessNodeCard({required this.node});

  final ProcessNode node;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<PipelinesProvider>();
    final selected = context.select<PipelinesProvider, bool>(
      (value) => value.selectedNodeId == node.id,
    );

    return AppCard(
      onTap: () {
        provider.selectNode(node.id);
        provider.toggleEditing(true);
      },
      padding: const EdgeInsets.all(12),
      backgroundColor: selected ? const Color(0xFFF8F6FF) : Colors.white,
      borderColor: selected ? const Color(0xFF6C63FF) : const Color(0xFFE5E7F0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  node.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusDot(color: node.statusColor),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _CapsuleLabel(
                label: node.processType,
                color: const Color(0xFFEEF2FF),
                textColor: const Color(0xFF4338CA),
              ),
              _CapsuleLabel(
                label: node.isIntermediate ? 'Intermediate' : 'Terminal',
                color: const Color(0xFFECFDF3),
                textColor: const Color(0xFF047857),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TagRow(
            color: const Color(0xFF2563EB),
            label: 'Inputs',
            values: node.inputs,
          ),
          const SizedBox(height: 8),
          _TagRow(
            color: const Color(0xFF16A34A),
            label: 'Outputs',
            values: node.outputs,
          ),
          if (node.scannedInputs.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ScannedInputsRow(inputs: node.scannedInputs),
          ],
          const Spacer(),
          Row(
            children: [
              if (_totalScanCount(node) > 0) ...[
                _ScanCountBadge(scanCount: _totalScanCount(node)),
                const SizedBox(width: 8),
              ],
              const Icon(
                Icons.precision_manufacturing_outlined,
                size: 16,
                color: Color(0xFF6B7280),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  node.machine,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _totalScanCount(ProcessNode node) {
    return node.scannedInputs.fold<int>(
      0,
      (total, input) => total + input.scanCount,
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.color,
    required this.label,
    required this.values,
  });

  final Color color;
  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xFF6B7280),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: values
              .map(
                (value) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatusDot(color: color, size: 8),
                      const SizedBox(width: 6),
                      Text(
                        value,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF111827),
                          fontWeight: FontWeight.w600,
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

class _CapsuleLabel extends StatelessWidget {
  const _CapsuleLabel({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ScannedInputsRow extends StatelessWidget {
  const _ScannedInputsRow({required this.inputs});

  final List<BarcodeInput> inputs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Scanned Inputs',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xFF6B7280),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        ...inputs
            .take(2)
            .map(
              (input) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${input.barcode} : ${input.materialName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        if (inputs.length > 2)
          Text(
            '+${inputs.length - 2} more',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

class _ScanCountBadge extends StatelessWidget {
  const _ScanCountBadge({required this.scanCount});

  final int scanCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEAFE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Scans $scanCount',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF5B4FE6),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color, this.size = 10});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _NodeDetailsPanel extends StatefulWidget {
  const _NodeDetailsPanel();

  @override
  State<_NodeDetailsPanel> createState() => _NodeDetailsPanelState();
}

class _NodeDetailsPanelState extends State<_NodeDetailsPanel> {
  final TextEditingController _processTypeController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  final TextEditingController _machineController = TextEditingController();

  @override
  void dispose() {
    _processTypeController.dispose();
    _durationController.dispose();
    _machineController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final node = context.read<PipelinesProvider>().selectedNode;
    if (node != null) {
      _syncControllers(node);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PipelinesProvider>(
      builder: (context, provider, _) {
        final node = provider.selectedNode;
        if (node == null) {
          return const AppInfoPanel(
            title: 'Node details',
            subtitle:
                'Select a node on the canvas to inspect or edit its details.',
            rows: [AppInfoRow(label: 'Selection', value: 'No node selected')],
          );
        }

        _syncControllers(node);
        final relatedFlows = provider.flowsForNode(node.id);

        return AppInfoPanel(
          title: node.name,
          subtitle: 'Keyboard-first node editor and connection summary.',
          headerTrailing: AppButton(
            label: provider.isEditing ? 'Editing' : 'View',
            onPressed: () => provider.toggleEditing(!provider.isEditing),
            variant: provider.isEditing
                ? AppButtonVariant.primary
                : AppButtonVariant.secondary,
          ),
          rows: [
            AppInfoRow(
              label: 'Process type',
              child: _EditableField(
                controller: _processTypeController,
                enabled: provider.isEditing,
                onSubmitted: (value) =>
                    provider.updateSelectedNode(processType: value.trim()),
              ),
            ),
            AppInfoRow(
              label: 'Duration',
              child: _EditableField(
                controller: _durationController,
                enabled: provider.isEditing,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onSubmitted: (value) => provider.updateSelectedNode(
                  durationHours:
                      double.tryParse(value.trim()) ?? node.durationHours,
                ),
              ),
            ),
            AppInfoRow(
              label: 'Machine',
              child: _EditableField(
                controller: _machineController,
                enabled: provider.isEditing,
                onSubmitted: (value) =>
                    provider.updateSelectedNode(machine: value.trim()),
              ),
            ),
            AppInfoRow(
              label: 'Inputs',
              child: _EditableTags(
                values: node.inputs,
                enabled: provider.isEditing,
                onChanged: (values) =>
                    provider.updateSelectedNode(inputs: values),
              ),
            ),
            AppInfoRow(
              label: 'Outputs',
              child: _EditableTags(
                values: node.outputs,
                enabled: provider.isEditing,
                onChanged: (values) =>
                    provider.updateSelectedNode(outputs: values),
              ),
            ),
            AppInfoRow(
              label: 'Connections',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: relatedFlows
                    .map(
                      (flow) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${flow.fromNodeId == node.id ? 'To' : 'From'} ${flow.fromNodeId == node.id ? flow.toNodeId : flow.fromNodeId} • ${flow.materialName}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: const Color(0xFF111827),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            AppInfoRow(
              label: 'Scanned inputs',
              child: node.scannedInputs.isEmpty
                  ? Text(
                      'No material scanned yet',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6B7280),
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: node.scannedInputs
                          .map(
                            (input) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '${input.barcode} • ${input.materialName} • Scanned ${input.scanCount} times',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: const Color(0xFF111827),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
            ),
          ],
        );
      },
    );
  }

  void _syncControllers(ProcessNode node) {
    if (_processTypeController.text != node.processType) {
      _processTypeController.text = node.processType;
    }
    final durationText = node.durationHours.toStringAsFixed(
      node.durationHours.truncateToDouble() == node.durationHours ? 0 : 1,
    );
    if (_durationController.text != durationText) {
      _durationController.text = durationText;
    }
    if (_machineController.text != node.machine) {
      _machineController.text = node.machine;
    }
  }
}

class _EditableField extends StatelessWidget {
  const _EditableField({
    required this.controller,
    required this.enabled,
    required this.onSubmitted,
    this.keyboardType,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onSubmitted;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }
}

class _EditableTags extends StatelessWidget {
  const _EditableTags({
    required this.values,
    required this.enabled,
    required this.onChanged,
  });

  final List<String> values;
  final bool enabled;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values
          .map(
            (value) => Chip(
              label: Text(value),
              deleteIcon: enabled ? const Icon(Icons.close, size: 18) : null,
              onDeleted: enabled
                  ? () => onChanged(
                      values.where((item) => item != value).toList(),
                    )
                  : null,
              side: const BorderSide(color: Color(0xFFD8DCE8)),
              backgroundColor: Colors.white,
            ),
          )
          .toList(growable: false),
    );
  }
}

class _MoveIntent extends Intent {
  const _MoveIntent(this.laneDelta, this.stageDelta);

  final int laneDelta;
  final int stageDelta;
}

class _AddNodeIntent extends Intent {
  const _AddNodeIntent();
}

class _OpenNodeIntent extends Intent {
  const _OpenNodeIntent();
}

class _CanvasErrorBanner extends StatelessWidget {
  const _CanvasErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: const Color(0xFFB91C1C),
          fontWeight: FontWeight.w600,
        ),
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
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Scan Material for Node',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Desktop uses manual lookup. Enter a barcode created in Inventory and attach it to the selected node.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Barcode',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onSubmitted: (value) {
                  Navigator.of(context).pop(value.trim());
                },
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(width: 12),
                  AppButton(
                    label: 'Lookup',
                    icon: Icons.search,
                    onPressed: () {
                      Navigator.of(context).pop(_controller.text.trim());
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
