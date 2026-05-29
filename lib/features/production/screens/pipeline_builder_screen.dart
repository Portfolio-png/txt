import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/pipeline_editor_provider.dart';
import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/process_node.dart';
import '../../machines/data/machine_repository.dart';
import '../../machines/domain/machine.dart';
import '../../dies/data/die_repository.dart';
import '../../dies/domain/die.dart';
import '../widgets/graph_edges_painter.dart';

class PipelineBuilderScreen extends StatefulWidget {
  final String shopFloorId;
  const PipelineBuilderScreen({super.key, required this.shopFloorId});

  @override
  State<PipelineBuilderScreen> createState() => _PipelineBuilderScreenState();
}

class _PipelineBuilderScreenState extends State<PipelineBuilderScreen> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'pipeline_builder');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PipelineEditorProvider>();

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BuilderHeader(provider: provider, shopFloorId: widget.shopFloorId),
            const SizedBox(height: 16),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 980) {
                    return Column(
                      children: [
                        const Expanded(flex: 7, child: _GitGraphCanvas()),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 270,
                          child: _PipelineControlPanel(provider: provider),
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Expanded(child: _GitGraphCanvas()),
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 330,
                        child: _PipelineControlPanel(provider: provider),
                      ),
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
                color: Color(0xFF263130),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Build the route sequence, then run it from the pipeline library.',
              style: TextStyle(
                color: Color(0xFF6A7572),
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
            _PanelSectionTitle(title: 'Create', action: 'No modal required'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _PanelActionButton(
                    icon: Icons.view_column_rounded,
                    label: 'Add Stage',
                    onTap: provider.addStage,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PanelActionButton(
                    icon: Icons.table_rows_rounded,
                    label: 'Add Lane',
                    onTap: provider.addLane,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _PanelActionButton(
              icon: Icons.add_road_rounded,
              label: selectedNode == null ? 'Add First Step' : 'Add Next Step',
              onTap: provider.addNextStepFromSelection,
              expanded: true,
            ),
            const SizedBox(height: 16),
            _PanelSectionTitle(
              title: 'Selected Node',
              action: selectedNode == null ? 'None' : 'Active',
            ),
            const SizedBox(height: 8),
            if (selectedNode == null)
              const _EmptySelectionCard()
            else
              _SelectedNodeCard(node: selectedNode, provider: provider),
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
                color: Color(0xFF263130),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6A7572),
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
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF263130),
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const Spacer(),
        Text(
          action,
          style: const TextStyle(
            color: Color(0xFF6A7572),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PanelActionButton extends StatelessWidget {
  const _PanelActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.expanded = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE7F0EE),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: expanded ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: const Color(0xFF256D66), size: 17),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF256D66),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
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

class _EmptySelectionCard extends StatelessWidget {
  const _EmptySelectionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAF7),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFD9DEDA)),
      ),
      child: const Text(
        'Select a node on the canvas to see machine, die, and material flow context here.',
        style: TextStyle(
          color: Color(0xFF6A7572),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

class _SelectedNodeCard extends StatelessWidget {
  const _SelectedNodeCard({required this.node, required this.provider});

  final ProcessNode node;
  final PipelineEditorProvider provider;

  @override
  Widget build(BuildContext context) {
    final draft = provider.draftFor(node.id);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAF7),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFD9DEDA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            node.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF263130),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${node.processType} · Stage ${node.stageIndex + 1} / Lane ${node.laneIndex + 1}',
            style: const TextStyle(
              color: Color(0xFF6A7572),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (draft == null) ...[
            _NodeFact(label: 'Machine', value: node.machine),
            _NodeFact(label: 'Die', value: node.dieId),
            _NodeFact(
              label: 'Flow',
              value: '${_join(node.inputs)} -> ${_join(node.outputs)}',
            ),
          ] else ...[
            _PanelActionButton(
              icon: Icons.check_circle_outline_rounded,
              label: 'Apply Node Changes',
              onTap: () => provider.saveNodeDraft(node.id),
              expanded: true,
            ),
            const SizedBox(height: 10),
            _InlineNodeField(label: 'Node Name', controller: draft.name),
            _InlineNodeField(label: 'Action', controller: draft.processType),
            Row(
              children: [
                Expanded(
                  child: _InlineNodeField(
                    label: 'Machine',
                    controller: draft.machine,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _InlineNodeField(
                    label: 'Die',
                    controller: draft.dieId,
                  ),
                ),
              ],
            ),
            _InlineNodeField(
              label: 'Inputs',
              controller: draft.inputs,
              helper: 'Comma separated',
            ),
            _InlineNodeField(
              label: 'Outputs',
              controller: draft.outputs,
              helper: 'Comma separated',
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PanelActionButton(
                  icon: Icons.link_rounded,
                  label: 'Connect From',
                  onTap: () => provider.beginConnecting(node.id),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PanelActionButton(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  onTap: () {
                    provider.selectNode(node.id);
                    provider.deleteSelectedNode();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _join(List<String> values) {
    return values.isEmpty ? '-' : values.join(', ');
  }
}

class _InlineNodeField extends StatelessWidget {
  const _InlineNodeField({
    required this.label,
    required this.controller,
    this.helper,
  });

  final String label;
  final TextEditingController controller;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: TextField(
        controller: controller,
        style: const TextStyle(
          color: Color(0xFF263130),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          isDense: true,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.72),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 11,
            vertical: 10,
          ),
          labelStyle: const TextStyle(
            color: Color(0xFF6A7572),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
          helperStyle: const TextStyle(
            color: Color(0xFF94A09C),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Color(0xFFD9DEDA)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Color(0xFFD9DEDA)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Color(0xFF256D66), width: 1.4),
          ),
        ),
      ),
    );
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
                color: Color(0xFF6A7572),
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
                color: Color(0xFF263130),
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

class _BuilderHeader extends StatelessWidget {
  const _BuilderHeader({required this.provider, required this.shopFloorId});

  final PipelineEditorProvider provider;
  final String shopFloorId;

  void _showPipelineDetailsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => _PipelineDetailsDialog(
        initialName: provider.template.name,
        initialDescription: provider.template.description,
        onApply: (name, description) {
          provider.updateTemplateDetails(name: name, description: description);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                provider.template.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF263130),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Route builder: drag stages across the floor sequence, click a node to edit.',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6A7572),
                ),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.drive_file_rename_outline_rounded, size: 18),
          label: const Text('Details'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF263130),
            side: const BorderSide(color: Color(0xFFD9DEDA)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () => _showPipelineDetailsDialog(context),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add Node'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF256D66),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () {
            provider.addNode(0, 0); // Adds node at stage 0, lane 0
          },
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          icon: const Icon(Icons.save),
          label: const Text('Save Pipeline'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF263130),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () async {
            try {
              final template = provider.template.copyWith(
                shopFloorId: shopFloorId,
              );
              final repo = context.read<PipelineRunRepository>();
              final existing = await repo.getTemplate(template.id);
              if (existing == null) {
                await repo.createTemplate(template);
              } else {
                await repo.updateTemplate(template);
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pipeline saved.')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Pipeline could not be saved. Please check the route details and try again.',
                    ),
                  ),
                );
              }
            }
          },
        ),
      ],
    );
  }
}

class _PipelineDetailsDialog extends StatefulWidget {
  const _PipelineDetailsDialog({
    required this.initialName,
    required this.initialDescription,
    required this.onApply,
  });

  final String initialName;
  final String initialDescription;
  final void Function(String name, String description) onApply;

  @override
  State<_PipelineDetailsDialog> createState() => _PipelineDetailsDialogState();
}

class _PipelineDetailsDialogState extends State<_PipelineDetailsDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pipeline Details'),
      content: SizedBox(
        width: 460,
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
              decoration: const InputDecoration(labelText: 'Short Description'),
              minLines: 2,
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            widget.onApply(_nameController.text, _descriptionController.text);
            Navigator.pop(context);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _GitGraphCanvas extends StatelessWidget {
  const _GitGraphCanvas();

  static const double nodeWidth = 180;
  static const double nodeHeight = 56;
  static const double columnWidth = 240;
  static const double rowHeight = 100;

  void _showEditDialog(
    BuildContext context,
    ProcessNode node,
    PipelineEditorProvider provider,
  ) {
    final draft = provider.draftFor(node.id);
    if (draft == null) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit ${node.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogField('Name', draft.name),
                _MachineDropdownField(controller: draft.machine),
                _DieDropdownField(controller: draft.dieId),
                _DialogField('Process Action', draft.processType),
                _DialogField('Inputs (comma sep)', draft.inputs),
                _DialogField('Outputs (comma sep)', draft.outputs),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        provider.beginConnecting(node.id);
                      },
                      icon: const Icon(Icons.arrow_right_alt),
                      label: const Text('Connect to...'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        provider.selectNode(node.id);
                        provider.deleteSelectedNode();
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                provider.saveNodeDraft(node.id);
                Navigator.pop(context);
              },
              child: const Text('Save Changes'),
            ),
          ],
        );
      },
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
                          Text(
                            stageLabels[s].toUpperCase(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              letterSpacing: 0.5,
                              color: Color(0xFF64748B),
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
              ...nodes.map((node) {
                final isConnecting = provider.connectingFromNodeId == node.id;
                final isTarget =
                    provider.connectingFromNodeId != null &&
                    provider.connectingFromNodeId != node.id;

                final nodeWidget = Container(
                  width: nodeWidth,
                  height: nodeHeight,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: isConnecting
                          ? Colors.orange
                          : (isTarget ? Colors.green : const Color(0xFFCBD5E1)),
                      width: isConnecting || isTarget ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      if (isConnecting || isTarget)
                        BoxShadow(
                          color: (isConnecting ? Colors.orange : Colors.green)
                              .withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        )
                      else
                        const BoxShadow(
                          color: Color(0x0A000000),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      node.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: Color(0xFF0F172A),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(
                                    Icons.edit_rounded,
                                    size: 14,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ],
                              ),
                              if (node.machine.isNotEmpty ||
                                  node.dieId.isNotEmpty)
                                Text(
                                  '${node.machine}${node.machine.isNotEmpty && node.dieId.isNotEmpty ? ' • ' : ''}${node.dieId}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF64748B),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.drag_indicator,
                          size: 16,
                          color: Color(0xFFCBD5E1),
                        ),
                      ],
                    ),
                  ),
                );

                return Positioned(
                  left: 100 + (node.stageIndex * columnWidth),
                  top: 100 + (node.laneIndex * rowHeight),
                  child: Draggable<String>(
                    data: node.id,
                    feedback: Material(
                      color: Colors.transparent,
                      child: Opacity(opacity: 0.7, child: nodeWidget),
                    ),
                    childWhenDragging: Opacity(opacity: 0.3, child: nodeWidget),
                    child: GestureDetector(
                      onTap: () {
                        if (provider.connectingFromNodeId != null) {
                          provider.selectNode(node.id); // completes connection
                        } else {
                          _showEditDialog(context, node, provider);
                        }
                      },
                      child: nodeWidget,
                    ),
                  ),
                );
              }),
            ],
          ),
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
    final repo = context.read<MachineRepository>();
    final m = await repo.fetchMachines();
    if (!mounted) return;
    setState(() {
      _machines = m;
      _isLoading = false;
    });
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
    final repo = context.read<DieRepository>();
    final d = await repo.fetchDies();
    if (!mounted) return;
    setState(() {
      _dies = d;
      _isLoading = false;
    });
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
