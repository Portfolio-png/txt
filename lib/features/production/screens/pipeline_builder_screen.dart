import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/orders/presentation/providers/orders_provider.dart';
import 'package:core_erp/features/units/domain/unit_definition.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';

import '../providers/pipeline_editor_provider.dart';
import '../providers/production_provider.dart';
import '../domain/default_floor_context.dart';
import '../../production_pipelines/data/default_pipeline_templates.dart';
import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/pipeline_item_endpoint.dart';
import '../../production_pipelines/domain/pipeline_template.dart';
import '../../production_pipelines/domain/process_node.dart';
import '../../machines/data/machine_repository.dart';
import '../../machines/domain/machine.dart';
import '../../dies/data/die_repository.dart';
import '../../dies/domain/die.dart';
import '../widgets/graph_edges_painter.dart';

class PipelineBuilderScreen extends StatefulWidget {
  const PipelineBuilderScreen({
    super.key,
    this.factoryId = defaultProductionFactoryId,
    this.shopFloorId = defaultProductionShopFloorId,
  });

  final String factoryId;
  final String shopFloorId;

  @override
  State<PipelineBuilderScreen> createState() => _PipelineBuilderScreenState();
}

class _PipelineBuilderScreenState extends State<PipelineBuilderScreen> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'pipeline_builder');
  final TransformationController _canvasController = TransformationController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _initializeItemMasterData();
    });
  }

  void _initializeItemMasterData() {
    try {
      context.read<ItemsProvider>().initialize();
    } catch (_) {}
    try {
      context.read<UnitsProvider>().initialize();
    } catch (_) {}
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _canvasController.dispose();
    super.dispose();
  }

  void _zoomCanvas(double factor) {
    final currentScale = _canvasController.value.getMaxScaleOnAxis();
    final nextScale = (currentScale * factor).clamp(0.22, 1.8).toDouble();
    _canvasController.value = Matrix4.diagonal3Values(nextScale, nextScale, 1);
  }

  void _resetCanvas() {
    _canvasController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PipelineEditorProvider>();

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 980;
          return Stack(
            children: [
              Positioned.fill(
                child: _GitGraphCanvas(controller: _canvasController),
              ),
              Positioned(
                left: 16,
                top: 16,
                right: compact ? 16 : 374,
                child: _BuilderHeader(
                  provider: provider,
                  factoryId: widget.factoryId,
                  shopFloorId: widget.shopFloorId,
                ),
              ),
              if (compact)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  height: 276,
                  child: _PipelineControlPanel(provider: provider),
                )
              else
                Positioned(
                  right: 16,
                  top: 16,
                  bottom: 16,
                  width: 342,
                  child: _PipelineControlPanel(provider: provider),
                ),
              Positioned(
                left: 16,
                bottom: compact ? 308 : 16,
                child: _CanvasQuickTools(
                  onZoomIn: () => _zoomCanvas(1.18),
                  onZoomOut: () => _zoomCanvas(0.84),
                  onReset: _resetCanvas,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

List<UnitDefinition> _activeUnitsFromContext(BuildContext context) {
  try {
    return context.read<UnitsProvider>().activeUnits;
  } catch (_) {
    return const [];
  }
}

List<ItemDefinition> _activeItemsFromContext(BuildContext context) {
  try {
    return context
        .read<ItemsProvider>()
        .items
        .where((item) => !item.isArchived)
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

class _CanvasQuickTools extends StatelessWidget {
  const _CanvasQuickTools({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.045),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CanvasToolButton(
              icon: Icons.remove_rounded,
              tooltip: 'Zoom out',
              onTap: onZoomOut,
            ),
            _CanvasToolButton(
              icon: Icons.center_focus_strong_rounded,
              tooltip: 'Reset canvas',
              onTap: onReset,
            ),
            _CanvasToolButton(
              icon: Icons.add_rounded,
              tooltip: 'Zoom in',
              onTap: onZoomIn,
            ),
          ],
        ),
      ),
    );
  }
}

class _CanvasToolButton extends StatelessWidget {
  const _CanvasToolButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, color: const Color(0xFF1E293B), size: 18),
        ),
      ),
    );
  }
}

class _PipelineControlPanel extends StatelessWidget {
  const _PipelineControlPanel({required this.provider});

  final PipelineEditorProvider provider;

  @override
  Widget build(BuildContext context) {
    final template = provider.template;
    final selectedNode = provider.selectedNode;
    final connectedNodeIds = <String>{
      for (final flow in template.flows) ...[flow.fromNodeId, flow.toNodeId],
    };
    final looseNodeCount = template.nodes.length <= 1
        ? 0
        : template.nodes
              .where((node) => !connectedNodeIds.contains(node.id))
              .length;
    ProcessNode? connectingNode;
    for (final node in template.nodes) {
      if (node.id == provider.connectingFromNodeId) {
        connectingNode = node;
        break;
      }
    }
    final readiness = _routeReadiness(
      nodeCount: template.nodes.length,
      flowCount: template.flows.length,
      looseNodeCount: looseNodeCount,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD9DEDA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pipeline Control',
              style: TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Build the route sequence, then start it from this canvas.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 14),
            _ReadinessCard(
              readiness: readiness,
              looseNodeCount: looseNodeCount,
            ),
            if (connectingNode != null) ...[
              const SizedBox(height: 10),
              _ConnectionModeCard(nodeName: connectingNode.name),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                _PanelMetric(
                  label: 'Stages',
                  value: '${template.stageLabels.length}',
                ),
                const SizedBox(width: 8),
                _PanelMetric(label: 'Nodes', value: '${template.nodes.length}'),
                const SizedBox(width: 8),
                _PanelMetric(label: 'Flows', value: '${template.flows.length}'),
              ],
            ),
            const SizedBox(height: 16),
            _PanelSectionTitle(
              title: 'Selected Node',
              action: selectedNode == null ? 'None' : 'Canvas actions',
            ),
            const SizedBox(height: 8),
            if (selectedNode == null)
              const _EmptySelectionCard()
            else
              _SelectedNodeCard(node: selectedNode),
          ],
        ),
      ),
    );
  }

  _RouteReadiness _routeReadiness({
    required int nodeCount,
    required int flowCount,
    required int looseNodeCount,
  }) {
    if (nodeCount == 0) {
      return const _RouteReadiness(
        label: 'Not started',
        message: 'Add the first process step to begin this route.',
        color: Color(0xFF94A09C),
        progress: 0.08,
      );
    }
    if (looseNodeCount > 0 || flowCount == 0 && nodeCount > 1) {
      return _RouteReadiness(
        label: 'Needs routing',
        message:
            '$looseNodeCount unconnected step${looseNodeCount == 1 ? '' : 's'} need flow links.',
        color: const Color(0xFFB7791F),
        progress: 0.52,
      );
    }
    return const _RouteReadiness(
      label: 'Ready to run',
      message: 'The pipeline has a connected route sequence.',
      color: Color(0xFF2F8069),
      progress: 0.92,
    );
  }
}

class _RouteReadiness {
  const _RouteReadiness({
    required this.label,
    required this.message,
    required this.color,
    required this.progress,
  });

  final String label;
  final String message;
  final Color color;
  final double progress;
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.readiness, required this.looseNodeCount});

  final _RouteReadiness readiness;
  final int looseNodeCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: readiness.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: readiness.color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: readiness.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                readiness.label,
                style: TextStyle(
                  color: readiness.color,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                looseNodeCount == 0 ? 'OK' : '$looseNodeCount gaps',
                style: TextStyle(
                  color: readiness.color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: readiness.progress,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.72),
              valueColor: AlwaysStoppedAnimation(readiness.color),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            readiness.message,
            style: const TextStyle(
              color: Color(0xFF6A7572),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionModeCard extends StatelessWidget {
  const _ConnectionModeCard({required this.nodeName});

  final String nodeName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.link_rounded, size: 17, color: Color(0xFF2563EB)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tap a target block to connect from $nodeName.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF1D4ED8),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelMetric extends StatelessWidget {
  const _PanelMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F1EC).withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelSectionTitle extends StatelessWidget {
  const _PanelSectionTitle({required this.title, required this.action});

  final String title;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            action,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptySelectionCard extends StatelessWidget {
  const _EmptySelectionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Text(
        'Select a block on the canvas. A small toolbar will appear on the block for common actions.',
        style: TextStyle(
          color: Color(0xFF64748B),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

class _SelectedNodeCard extends StatelessWidget {
  const _SelectedNodeCard({required this.node});

  final ProcessNode node;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            node.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${node.processType} · Stage ${node.stageIndex + 1} / Lane ${node.laneIndex + 1}',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _NodeFact(label: 'Machine', value: node.machine),
          _NodeFact(label: 'Die', value: node.dieId),
          _NodeFact(
            label: 'Flow',
            value: '${_join(node.inputs)} -> ${_join(node.outputs)}',
          ),
          if (node.inputItem != null)
            _NodeFact(
              label: 'Input',
              value:
                  '${node.inputItem!.itemName} (${node.inputItem!.unitLabel})',
            ),
          if (node.outputItem != null)
            _NodeFact(
              label: 'Output',
              value:
                  '${node.outputItem!.itemName} (${node.outputItem!.unitLabel})',
            ),
          const SizedBox(height: 10),
          const Text(
            'Use the floating toolbar on the selected block. Double-click the block to edit details.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  String _join(List<String> values) {
    return values.isEmpty ? '-' : values.join(', ');
  }
}

class _NodeFact extends StatelessWidget {
  const _NodeFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '-' : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _TemplateAction { sheetMetal, blank }

class _BuilderHeader extends StatelessWidget {
  const _BuilderHeader({
    required this.provider,
    required this.factoryId,
    required this.shopFloorId,
  });

  final PipelineEditorProvider provider;
  final String factoryId;
  final String shopFloorId;

  void _showPipelineDetailsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => _PipelineDetailsDialog(
        initialName: provider.template.name,
        initialDescription: provider.template.description,
        initialInputMaterial: provider.template.inputMaterial,
        initialOutputMaterial: provider.template.outputMaterial,
        onApply: (name, description, inputMaterial, outputMaterial) {
          provider.updateTemplateDetails(
            name: name,
            description: description,
            inputMaterial: inputMaterial,
            outputMaterial: outputMaterial,
          );
        },
      ),
    );
  }

  Future<PipelineTemplate?> _saveTemplate(
    BuildContext context, {
    bool showError = true,
  }) async {
    try {
      provider.applyUnitContinuityAutoFixes(_activeUnitsFromContext(context));
      final template = provider.template.copyWith(
        factoryId: factoryId,
        shopFloorId: shopFloorId,
      );
      final repo = context.read<PipelineRunRepository>();
      final existing = await repo.getTemplate(template.id);
      if (existing == null) {
        return repo.createTemplate(template);
      }
      return repo.updateTemplate(template);
    } catch (_) {
      if (showError && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pipeline could not be saved. Please check the route and try again.',
            ),
          ),
        );
      }
      return null;
    }
  }

  Future<void> _saveAndNotify(BuildContext context) async {
    final saved = await _saveTemplate(context);
    if (saved == null || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pipeline saved to this canvas.')),
    );
  }

  Future<void> _startFlow(BuildContext context) async {
    if (provider.template.nodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one stage before starting.'),
        ),
      );
      return;
    }

    final saved = await _saveTemplate(context, showError: false);
    final runnable =
        saved ??
        provider.template.copyWith(
          factoryId: factoryId,
          shopFloorId: shopFloorId,
        );
    if (!context.mounted) {
      return;
    }

    try {
      final production = context.read<ProductionProvider>();
      production.loadTemplate(runnable);
      final node = production.selectedNode;
      if (node == null) {
        throw const ProductionSetupException('Select a production step first.');
      }
      production.beginSetup();
      production.verifyAssetSetup(node.machine, node.dieId);
      production.startRun();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Started ${runnable.name}.')));
      }
    } on ProductionSetupException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  void _applyTemplateAction(BuildContext context, _TemplateAction action) {
    switch (action) {
      case _TemplateAction.sheetMetal:
        provider.loadTemplate(
          sheetMetalPipelineTemplate.copyWith(
            factoryId: factoryId,
            shopFloorId: shopFloorId,
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Loaded Sheet Metal Process.')),
        );
        return;
      case _TemplateAction.blank:
        provider.startNewTemplate(
          factoryId: factoryId,
          shopFloorId: shopFloorId,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Started a blank production canvas.')),
        );
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final production = context.watch<ProductionProvider>();
    final canStart =
        provider.template.nodes.isNotEmpty && !production.isRunning;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.045),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.account_tree_rounded,
                color: Colors.white,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                provider.template.name.trim().isEmpty
                    ? 'Untitled flow'
                    : provider.template.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PopupMenuButton<_TemplateAction>(
                        tooltip: 'Templates',
                        position: PopupMenuPosition.under,
                        onSelected: (action) =>
                            _applyTemplateAction(context, action),
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: _TemplateAction.sheetMetal,
                            child: _TemplateMenuItem(
                              icon: Icons.precision_manufacturing_rounded,
                              title: 'Sheet Metal',
                              subtitle:
                                  'Input, cutting, piercing, bend, drill, pack',
                            ),
                          ),
                          PopupMenuDivider(),
                          PopupMenuItem(
                            value: _TemplateAction.blank,
                            child: _TemplateMenuItem(
                              icon: Icons.note_add_outlined,
                              title: 'Blank Canvas',
                              subtitle: 'Start without stages or flows',
                            ),
                          ),
                        ],
                        child: const _HeaderMenuButton(
                          icon: Icons.dashboard_customize_rounded,
                          label: 'Templates',
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(
                          Icons.drive_file_rename_outline_rounded,
                          size: 17,
                        ),
                        label: const Text('Details'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1E293B),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => _showPipelineDetailsDialog(context),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Flow Step'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => provider.addNextStepFromSelection(
                          units: _activeUnitsFromContext(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        icon: Icon(
                          production.isRunning
                              ? Icons.play_circle_filled_rounded
                              : Icons.play_arrow_rounded,
                          size: 18,
                        ),
                        label: Text(
                          production.isRunning ? 'Running' : 'Start Flow',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFF8E9995),
                          disabledForegroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: canStart ? () => _startFlow(context) : null,
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.save_rounded, size: 17),
                        label: const Text('Save'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1E293B),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => _saveAndNotify(context),
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
}

class _HeaderMenuButton extends StatelessWidget {
  const _HeaderMenuButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: const Color(0xFF1E293B)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateMenuItem extends StatelessWidget {
  const _TemplateMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 252,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 17, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PipelineDetailsDialog extends StatefulWidget {
  const _PipelineDetailsDialog({
    required this.initialName,
    required this.initialDescription,
    required this.initialInputMaterial,
    required this.initialOutputMaterial,
    required this.onApply,
  });

  final String initialName;
  final String initialDescription;
  final String initialInputMaterial;
  final String initialOutputMaterial;
  final void Function(
    String name,
    String description,
    String inputMaterial,
    String outputMaterial,
  )
  onApply;

  @override
  State<_PipelineDetailsDialog> createState() => _PipelineDetailsDialogState();
}

class _PipelineDetailsDialogState extends State<_PipelineDetailsDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _inputMaterialController;
  late final TextEditingController _outputMaterialController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
    _inputMaterialController = TextEditingController(
      text: widget.initialInputMaterial,
    );
    _outputMaterialController = TextEditingController(
      text: widget.initialOutputMaterial,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _inputMaterialController.dispose();
    _outputMaterialController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    InventoryProvider? inventoryProvider;
    try {
      inventoryProvider = context.read<InventoryProvider>();
    } catch (_) {}
    final materials = inventoryProvider?.materials ?? const [];
    final uniqueMaterialNames = materials.map((m) => m.name).toSet().toList();

    OrdersProvider? ordersProvider;
    try {
      ordersProvider = context.read<OrdersProvider>();
    } catch (_) {}
    final orders = ordersProvider?.orders ?? const [];
    final uniqueOrderItems = orders.map((o) => o.itemName).toSet().toList();

    if (_inputMaterialController.text.isEmpty &&
        uniqueMaterialNames.isNotEmpty) {
      _inputMaterialController.text = uniqueMaterialNames.first;
    }

    if (_outputMaterialController.text.isEmpty && uniqueOrderItems.isNotEmpty) {
      _outputMaterialController.text = uniqueOrderItems.first;
    }

    return AlertDialog(
      title: const Text('Pipeline Details'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Pipeline Name'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Short Description',
                ),
                minLines: 2,
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue:
                    uniqueMaterialNames.contains(_inputMaterialController.text)
                    ? _inputMaterialController.text
                    : (_inputMaterialController.text.isNotEmpty
                          ? _inputMaterialController.text
                          : null),
                decoration: const InputDecoration(labelText: 'Input Material'),
                items:
                    {
                      if (_inputMaterialController.text.isNotEmpty &&
                          !uniqueMaterialNames.contains(
                            _inputMaterialController.text,
                          ))
                        _inputMaterialController.text,
                      ...uniqueMaterialNames,
                    }.map((name) {
                      return DropdownMenuItem<String>(
                        value: name,
                        child: Text(name),
                      );
                    }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _inputMaterialController.text = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue:
                    uniqueOrderItems.contains(_outputMaterialController.text)
                    ? _outputMaterialController.text
                    : (_outputMaterialController.text.isNotEmpty
                          ? _outputMaterialController.text
                          : null),
                decoration: const InputDecoration(labelText: 'Output Material'),
                items:
                    {
                      if (_outputMaterialController.text.isNotEmpty &&
                          !uniqueOrderItems.contains(
                            _outputMaterialController.text,
                          ))
                        _outputMaterialController.text,
                      ...uniqueOrderItems,
                    }.map((name) {
                      return DropdownMenuItem<String>(
                        value: name,
                        child: Text(name),
                      );
                    }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _outputMaterialController.text = val;
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            widget.onApply(
              _nameController.text,
              _descriptionController.text,
              _inputMaterialController.text,
              _outputMaterialController.text,
            );
            Navigator.pop(context);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _NodeEditDialog extends StatefulWidget {
  const _NodeEditDialog({
    required this.node,
    required this.draft,
    required this.provider,
    required this.items,
    required this.units,
  });

  final ProcessNode node;
  final ProcessNodeDraftController draft;
  final PipelineEditorProvider provider;
  final List<ItemDefinition> items;
  final List<UnitDefinition> units;

  @override
  State<_NodeEditDialog> createState() => _NodeEditDialogState();
}

class _NodeEditDialogState extends State<_NodeEditDialog> {
  int? _inputItemId;
  int? _outputItemId;

  @override
  void initState() {
    super.initState();
    _inputItemId = widget.node.inputItem?.itemId;
    _outputItemId = widget.node.outputItem?.itemId;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.node.name}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogField('Name', widget.draft.name),
              _ItemEndpointDropdown(
                key: const ValueKey('pipeline-node-input-item'),
                label: 'Input Item',
                selectedItemId: _inputItemId,
                items: widget.items,
                units: widget.units,
                onChanged: (itemId) => setState(() => _inputItemId = itemId),
              ),
              const SizedBox(height: 12),
              _ItemEndpointDropdown(
                key: const ValueKey('pipeline-node-output-item'),
                label: 'Output Item',
                selectedItemId: _outputItemId,
                items: widget.items,
                units: widget.units,
                onChanged: (itemId) => setState(() => _outputItemId = itemId),
              ),
              const SizedBox(height: 12),
              _MachineDropdownField(controller: widget.draft.machine),
              _DieDropdownField(controller: widget.draft.dieId),
              _DialogField('Process Action', widget.draft.processType),
              _DialogField('Inputs (comma sep)', widget.draft.inputs),
              _DialogField('Outputs (comma sep)', widget.draft.outputs),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.provider.beginConnecting(widget.node.id);
                    },
                    icon: const Icon(Icons.arrow_right_alt),
                    label: const Text('Connect to...'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      widget.provider.selectNode(
                        widget.node.id,
                        units: widget.units,
                      );
                      widget.provider.deleteSelectedNode();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.delete),
                    label: const Text('Delete'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.provider.saveNodeDraft(widget.node.id);
            widget.provider.updateNodeItems(
              nodeId: widget.node.id,
              inputItem: _endpointFor(
                _inputItemId,
                fallback: widget.node.inputItem,
              ),
              outputItem: _endpointFor(
                _outputItemId,
                fallback: widget.node.outputItem,
              ),
              units: widget.units,
            );
            Navigator.pop(context);
          },
          child: const Text('Save Changes'),
        ),
      ],
    );
  }

  PipelineItemEndpoint? _endpointFor(
    int? itemId, {
    PipelineItemEndpoint? fallback,
  }) {
    if (itemId == null) {
      return null;
    }
    final item = _itemById(itemId);
    if (item == null) {
      return fallback?.itemId == itemId ? fallback : null;
    }
    final unit = _unitById(item.unitId);
    return PipelineItemEndpoint(
      itemId: item.id,
      itemName: _itemName(item),
      unitId: item.unitId,
      unitName: unit?.name ?? '',
      unitSymbol: unit?.symbol ?? '',
    );
  }

  ItemDefinition? _itemById(int id) {
    for (final item in widget.items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  UnitDefinition? _unitById(int id) {
    for (final unit in widget.units) {
      if (unit.id == id) {
        return unit;
      }
    }
    return null;
  }
}

class _ItemEndpointDropdown extends StatelessWidget {
  const _ItemEndpointDropdown({
    super.key,
    required this.label,
    required this.selectedItemId,
    required this.items,
    required this.units,
    required this.onChanged,
  });

  final String label;
  final int? selectedItemId;
  final List<ItemDefinition> items;
  final List<UnitDefinition> units;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final hasSelection = items.any((item) => item.id == selectedItemId);
    return DropdownButtonFormField<int>(
      initialValue: hasSelection ? selectedItemId : null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        helperText: items.isEmpty
            ? 'Item masters are not loaded yet.'
            : 'Unit comes from the selected item master.',
      ),
      items: items.map((item) {
        return DropdownMenuItem<int>(
          value: item.id,
          child: Text(
            '${_itemName(item)} (${_unitLabel(item.unitId, units)})',
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: items.isEmpty ? null : onChanged,
    );
  }
}

String _itemName(ItemDefinition item) {
  final displayName = item.displayName.trim();
  if (displayName.isNotEmpty) {
    return displayName;
  }
  return item.name;
}

String _unitLabel(int unitId, List<UnitDefinition> units) {
  for (final unit in units) {
    if (unit.id == unitId) {
      final symbol = unit.symbol.trim();
      if (symbol.isNotEmpty) {
        return symbol;
      }
      return unit.name;
    }
  }
  return 'Unit #$unitId';
}

class _GitGraphCanvas extends StatelessWidget {
  const _GitGraphCanvas({required this.controller});

  final TransformationController controller;

  static const double nodeWidth = 160;
  static const double nodeHeight = 52;
  static const double columnWidth = 240;
  static const double rowHeight = 112;

  void _showEditDialog(
    BuildContext context,
    ProcessNode node,
    PipelineEditorProvider provider,
  ) {
    final draft = provider.draftFor(node.id);
    if (draft == null) return;
    final items = _activeItemsFromContext(context);
    final units = _activeUnitsFromContext(context);

    showDialog(
      context: context,
      builder: (context) => _NodeEditDialog(
        node: node,
        draft: draft,
        provider: provider,
        items: items,
        units: units,
      ),
    );
  }

  void _showStageRenameDialog(
    BuildContext context,
    int stageIndex,
    String currentName,
    PipelineEditorProvider provider,
  ) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Stage'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Stage Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              provider.renameStage(stageIndex, controller.text);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PipelineEditorProvider>();
    final nodes = provider.template.nodes;
    final flows = provider.template.flows;
    final stageLabels = provider.template.stageLabels;

    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
      child: GestureDetector(
        onTap: provider.clearSelection,
        child: InteractiveViewer(
          transformationController: controller,
          boundaryMargin: const EdgeInsets.all(1500),
          minScale: 0.1,
          maxScale: 2.0,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                size: const Size(4000, 4000),
                painter: GraphEdgesPainter(
                  nodes: nodes,
                  flows: flows,
                  columnWidth: columnWidth,
                  rowHeight: rowHeight,
                  nodeWidth: nodeWidth,
                  nodeHeight: nodeHeight,
                ),
              ),
              // Drag Targets Grid
              for (int s = 0; s < 15; s++)
                for (int l = 0; l < 15; l++)
                  Positioned(
                    left: 100 + (s * columnWidth),
                    top: 100 + (l * rowHeight),
                    width: nodeWidth,
                    height: nodeHeight,
                    child: DragTarget<String>(
                      onAcceptWithDetails: (details) {
                        provider.updateNodePosition(details.data, s, l);
                      },
                      builder: (context, candidateData, rejectedData) {
                        return Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: candidateData.isNotEmpty
                                  ? const Color(
                                      0xFF2563EB,
                                    ).withValues(alpha: 0.3)
                                  : Colors.transparent,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        );
                      },
                    ),
                  ),
              // Stage Labels
              for (int s = 0; s < stageLabels.length; s++)
                Positioned(
                  left: 100 + (s * columnWidth),
                  top: 50,
                  width: nodeWidth,
                  child: GestureDetector(
                    onTap: () => _showStageRenameDialog(
                      context,
                      s,
                      stageLabels[s],
                      provider,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              stageLabels[s].toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                letterSpacing: 0.5,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.edit,
                            size: 14,
                            color: Color(0xFF64748B),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Nodes
              ...nodes.expand((node) {
                final isConnecting = provider.connectingFromNodeId == node.id;
                final isTarget =
                    provider.connectingFromNodeId != null &&
                    provider.connectingFromNodeId != node.id;
                final isSelected = provider.selectedNodeId == node.id;
                final left = 100 + (node.stageIndex * columnWidth);
                final top = 100 + (node.laneIndex * rowHeight);

                final nodeWidget = _FlowStageBlock(
                  width: nodeWidth,
                  height: nodeHeight,
                  node: node,
                  emphasized: isConnecting || isTarget,
                  target: isTarget,
                  isSelected: isSelected,
                );

                return [
                  Positioned(
                    left: left,
                    top: top,
                    child: Draggable<String>(
                      data: node.id,
                      feedback: Material(
                        color: Colors.transparent,
                        child: Opacity(opacity: 0.7, child: nodeWidget),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.3,
                        child: nodeWidget,
                      ),
                      child: GestureDetector(
                        onTap: () {
                          provider.selectNode(
                            node.id,
                            units: _activeUnitsFromContext(context),
                          );
                        },
                        onDoubleTap: () {
                          _showEditDialog(context, node, provider);
                        },
                        child: nodeWidget,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Positioned(
                      left: left - 22,
                      top: top + nodeHeight + 10,
                      child: _NodeCanvasToolbar(
                        onAddNext: () => provider.addNextStepFromSelection(
                          units: _activeUnitsFromContext(context),
                        ),
                        onEdit: () => _showEditDialog(context, node, provider),
                        onConnect: () => provider.beginConnecting(node.id),
                        onDuplicate: provider.duplicateSelectedNode,
                        onDisconnect: provider.disconnectSelectedNode,
                        onDelete: provider.deleteSelectedNode,
                      ),
                    ),
                ];
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _NodeCanvasToolbar extends StatelessWidget {
  const _NodeCanvasToolbar({
    required this.onAddNext,
    required this.onEdit,
    required this.onConnect,
    required this.onDuplicate,
    required this.onDisconnect,
    required this.onDelete,
  });

  final VoidCallback onAddNext;
  final VoidCallback onEdit;
  final VoidCallback onConnect;
  final VoidCallback onDuplicate;
  final VoidCallback onDisconnect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CanvasNodeAction(
              icon: Icons.add_rounded,
              tooltip: 'Add next step',
              onTap: onAddNext,
            ),
            _CanvasNodeAction(
              icon: Icons.edit_rounded,
              tooltip: 'Edit block',
              onTap: onEdit,
            ),
            _CanvasNodeAction(
              icon: Icons.link_rounded,
              tooltip: 'Connect from this block',
              onTap: onConnect,
            ),
            _CanvasNodeAction(
              icon: Icons.copy_rounded,
              tooltip: 'Duplicate block',
              onTap: onDuplicate,
            ),
            _CanvasNodeAction(
              icon: Icons.link_off_rounded,
              tooltip: 'Disconnect block',
              onTap: onDisconnect,
            ),
            _CanvasNodeAction(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Delete block',
              onTap: onDelete,
              destructive: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _CanvasNodeAction extends StatelessWidget {
  const _CanvasNodeAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? const Color(0xFFDC2626)
        : const Color(0xFF475569);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

class _FlowStageBlock extends StatelessWidget {
  const _FlowStageBlock({
    required this.width,
    required this.height,
    required this.node,
    required this.emphasized,
    required this.target,
    required this.isSelected,
  });

  final double width;
  final double height;
  final ProcessNode node;
  final bool emphasized;
  final bool target;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final dotColor = switch (node.status.toLowerCase()) {
      'running' || 'active' => const Color(0xFF10B981),
      'setup' || 'idle' => const Color(0xFFF59E0B),
      _ => const Color(0xFF94A3B8),
    };

    final isHighlighted = isSelected || emphasized;
    final borderColor = isSelected
        ? const Color(0xFF3B82F6)
        : (emphasized
              ? (target ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
              : const Color(0xFFE2E8F0));

    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: isHighlighted ? 2.0 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? const Color(0x223B82F6)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF1E293B),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    node.machine.trim().isEmpty ? 'Unassigned' : node.machine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField(this.label, this.controller);

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _MachineDropdownField extends StatefulWidget {
  const _MachineDropdownField({required this.controller});
  final TextEditingController controller;

  @override
  State<_MachineDropdownField> createState() => _MachineDropdownFieldState();
}

class _MachineDropdownFieldState extends State<_MachineDropdownField> {
  List<Machine>? _machines;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = context.read<MachineRepository>();
      final m = await repo.fetchMachines();
      if (!mounted) return;
      setState(() {
        _machines = m;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _machines = const [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: CircularProgressIndicator(),
      );
    }
    final machines = _machines ?? [];
    if (machines.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: _DialogField('Machine (Text)', widget.controller),
      );
    }

    // Ensure the current value exists in the list, or add it as a placeholder option
    final currentValue = widget.controller.text;
    final hasMatch = machines.any((m) => m.id == currentValue);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        initialValue: hasMatch ? currentValue : null,
        decoration: const InputDecoration(
          labelText: 'Assign Machine',
          border: OutlineInputBorder(),
        ),
        items: [
          if (!hasMatch && currentValue.isNotEmpty)
            DropdownMenuItem(value: currentValue, child: Text(currentValue)),
          ...machines.map(
            (m) => DropdownMenuItem(
              value: m.id,
              child: Text('${m.name} (${m.assetId})'),
            ),
          ),
        ],
        onChanged: (val) {
          if (val != null) {
            widget.controller.text = val;
          }
        },
      ),
    );
  }
}

class _DieDropdownField extends StatefulWidget {
  const _DieDropdownField({required this.controller});
  final TextEditingController controller;

  @override
  State<_DieDropdownField> createState() => _DieDropdownFieldState();
}

class _DieDropdownFieldState extends State<_DieDropdownField> {
  List<Die>? _dies;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = context.read<DieRepository>();
      final d = await repo.fetchDies();
      if (!mounted) return;
      setState(() {
        _dies = d;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dies = const [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: CircularProgressIndicator(),
      );
    }
    final dies = _dies ?? [];
    if (dies.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: _DialogField('Die (Text)', widget.controller),
      );
    }

    final currentValue = widget.controller.text;
    final hasMatch = dies.any((d) => d.id == currentValue);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        initialValue: hasMatch ? currentValue : null,
        decoration: const InputDecoration(
          labelText: 'Assign Die',
          border: OutlineInputBorder(),
        ),
        items: [
          if (!hasMatch && currentValue.isNotEmpty)
            DropdownMenuItem(value: currentValue, child: Text(currentValue)),
          ...dies.map(
            (d) => DropdownMenuItem(
              value: d.id,
              child: Text('${d.name} (${d.toolCode})'),
            ),
          ),
        ],
        onChanged: (val) {
          if (val != null) {
            widget.controller.text = val;
          }
        },
      ),
    );
  }
}
