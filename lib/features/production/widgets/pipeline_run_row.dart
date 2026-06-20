import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../production_pipelines/domain/pipeline_run.dart';
import '../../production_pipelines/domain/pipeline_template.dart';
import '../../production_pipelines/domain/process_node.dart';

import '../providers/batch_flow_provider.dart';
import 'node_batch_tray.dart';

class PipelineRunRow extends StatelessWidget {
  const PipelineRunRow({
    super.key,
    required this.run,
    required this.template,
    required this.selectedNodeId,
    required this.onNodeSelected,
    this.onNodeDoubleTap,
  });

  final PipelineRun run;
  final PipelineTemplate template;
  final String? selectedNodeId;
  final ValueChanged<String> onNodeSelected;
  final ValueChanged<String>? onNodeDoubleTap;

  @override
  Widget build(BuildContext context) {
    // Group nodes by stage index
    final stages = <int, List<ProcessNode>>{};
    for (final node in template.nodes) {
      stages.putIfAbsent(node.stageIndex, () => []).add(node);
    }
    
    // Sort stages
    final sortedStageIndices = stages.keys.toList()..sort();

    final batchProvider = context.watch<BatchFlowProvider>();

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.account_tree_outlined, size: 18, color: Color(0xFF3B82F6)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        run.name.isNotEmpty ? run.name : 'Instance ${run.id.split('-').last}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Template: ${template.name}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(run.status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    run.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(run.status),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Canvas Area
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < sortedStageIndices.length; i++) ...[
                  if (i > 0)
                    _buildConnector(_stageDone(stages[sortedStageIndices[i - 1]]!)),
                  _buildStageColumn(
                    context, 
                    stages[sortedStageIndices[i]]!, 
                    template.stageLabels.length > sortedStageIndices[i] ? template.stageLabels[sortedStageIndices[i]] : 'STAGE ${sortedStageIndices[i]}',
                    batchProvider,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Card geometry. The connector spacer matches the caption block so the line
  // lands on the card's vertical centre regardless of lane stacking.
  static const double _cardW = 172;
  static const double _cardH = 56;
  static const double _captionBlockH = 32;

  Widget _buildStageColumn(BuildContext context, List<ProcessNode> stageNodes, String label, BatchFlowProvider batchProvider) {
    // Sort nodes by laneIndex to stack them
    final nodes = List<ProcessNode>.from(stageNodes)..sort((a, b) => a.laneIndex.compareTo(b.laneIndex));
    final accent = _stageAccent(nodes);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Stage label — tinted to the stage's live state so the strip reads at a glance.
        SizedBox(
          height: _captionBlockH,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  color: accent,
                ),
              ),
            ),
          ),
        ),

        // Nodes
        for (int i = 0; i < nodes.length; i++) ...[
          if (i > 0) const SizedBox(height: 24), // spacing between parallel lanes
          _buildNodeBlock(context, nodes[i], batchProvider),
        ],
      ],
    );
  }

  Widget _buildNodeBlock(BuildContext context, ProcessNode node, BatchFlowProvider batchProvider) {
    final isSelected = selectedNodeId == node.id;
    final nodeBatches = batchProvider.batchesAtNode(run.id, node.id);

    // Inject live run status into the node so the card reflects current state.
    final activeNode = run.nodeStatuses.containsKey(node.id)
        ? node.copyWith(status: run.nodeStatuses[node.id]!.name)
        : node;

    final isEndpoint = !activeNode.isIntermediate;
    final accent = isEndpoint ? const Color(0xFF16A34A) : activeNode.statusColor;
    final isValid = activeNode.hasMachineAssignment &&
        activeNode.inputItem != null &&
        activeNode.outputItem != null;
    final subtitle = isEndpoint
        ? activeNode.processType
        : (activeNode.machineAssignmentLabel.isEmpty
            ? 'Unassigned'
            : activeNode.machineAssignmentLabel);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => onNodeSelected(node.id),
            onDoubleTap: onNodeDoubleTap == null ? null : () => onNodeDoubleTap!(node.id),
            child: Container(
              width: _cardW,
              height: _cardH,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: isSelected ? accent : const Color(0xFFE2E8F0),
                  width: isSelected ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? accent.withValues(alpha: 0.16)
                        : Colors.black.withValues(alpha: 0.04),
                    blurRadius: isSelected ? 12 : 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Row(
                  children: [
                    // Status rail — the card's whole state read at a glance.
                    Container(width: 4, color: accent),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                        child: Row(
                          children: [
                            Icon(
                              _iconFor(activeNode, isEndpoint),
                              size: 16,
                              color: accent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    activeNode.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isValid)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Tooltip(
                                  message: [
                                    if (!activeNode.hasMachineAssignment)
                                      'Missing Machine / Group',
                                    if (activeNode.inputItem == null)
                                      'Missing Input Item',
                                    if (activeNode.outputItem == null)
                                      'Missing Output Item',
                                  ].join('\n'),
                                  child: const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.orange,
                                    size: 15,
                                  ),
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
          ),
        ),
        if (nodeBatches.isNotEmpty) ...[
          const SizedBox(height: 8),
          NodeBatchTray(
            batches: nodeBatches,
            width: _cardW,
            onRevert: (b) {}, // Revert batch logic needs context, will handle later
          ),
        ],
      ],
    );
  }

  /// A line + chevron joining two stages, centred on the card and turning green
  /// once the upstream stage is finished.
  Widget _buildConnector(bool done) {
    final color = done ? const Color(0xFF10B981) : const Color(0xFFCBD5E1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: _captionBlockH),
          SizedBox(
            height: _cardH,
            width: 44,
            child: Center(
              child: Row(
                children: [
                  Expanded(child: Container(height: 2, color: color)),
                  Icon(Icons.chevron_right_rounded, size: 20, color: color),
                  Expanded(child: Container(height: 2, color: color)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(ProcessNode node, bool isEndpoint) {
    if (isEndpoint) {
      return node.processType.toLowerCase() == 'output'
          ? Icons.logout_rounded
          : Icons.login_rounded;
    }
    return Icons.precision_manufacturing_outlined;
  }

  bool _stageDone(List<ProcessNode> nodes) => nodes.every((n) {
        final s = (run.nodeStatuses[n.id]?.name ?? n.status).toLowerCase();
        return s == 'done' || s == 'completed' || s == 'skipped';
      });

  Color _stageAccent(List<ProcessNode> nodes) {
    if (nodes.any((n) => !n.isIntermediate)) return const Color(0xFF16A34A);
    final statuses = nodes
        .map((n) => (run.nodeStatuses[n.id]?.name ?? n.status).toLowerCase())
        .toList();
    if (statuses.any((s) => s == 'active' || s == 'running')) {
      return const Color(0xFF2563EB);
    }
    if (statuses.every((s) => s == 'done' || s == 'completed' || s == 'skipped')) {
      return const Color(0xFF10B981);
    }
    return const Color(0xFF64748B);
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'done':
        return const Color(0xFF10B981);
      case 'active':
      case 'running':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFF64748B);
    }
  }
}
