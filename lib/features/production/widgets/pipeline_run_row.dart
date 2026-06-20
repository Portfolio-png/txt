import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../production_pipelines/domain/pipeline_run.dart';
import '../../production_pipelines/domain/pipeline_template.dart';
import '../../production_pipelines/domain/process_node.dart';
import '../../production_pipelines/domain/material_batch.dart';
import '../../production_pipelines/domain/node_run_status.dart';

import '../providers/batch_flow_provider.dart';
import 'batch_chip.dart';

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

  static const double _cardW = 172;
  static const double _cardH = 56;
  static const double _captionBlockH = 32;
  static const double _connectorW = 60; // 44 + 8 + 8

  @override
  Widget build(BuildContext context) {
    final stages = <int, List<ProcessNode>>{};
    for (final node in template.nodes) {
      stages.putIfAbsent(node.stageIndex, () => []).add(node);
    }
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
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
                const SizedBox(height: 24),
                _buildBatchTracks(context, batchProvider, sortedStageIndices),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageColumn(BuildContext context, List<ProcessNode> stageNodes, String label, BatchFlowProvider batchProvider) {
    final nodes = List<ProcessNode>.from(stageNodes)..sort((a, b) => a.laneIndex.compareTo(b.laneIndex));
    final accent = _stageAccent(nodes);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
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
        for (int i = 0; i < nodes.length; i++) ...[
          if (i > 0) const SizedBox(height: 24),
          _buildNodeBlock(context, nodes[i], batchProvider),
        ],
      ],
    );
  }

  Widget _buildNodeBlock(BuildContext context, ProcessNode node, BatchFlowProvider batchProvider) {
    final isSelected = selectedNodeId == node.id;
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

    return DragTarget<MaterialBatch>(
      onWillAcceptWithDetails: (details) {
        final batch = details.data;
        return batch.currentNodeId != node.id;
      },
      onAcceptWithDetails: (details) async {
        final batch = details.data;
        if (batch.currentNodeId == node.id) return;
        final qty = await BatchSplitDialog.show(
          context,
          batch: batch,
          targetNodeName: node.name.isEmpty ? 'station' : node.name,
        );
        if (qty == null) return;
        
        batchProvider.moveBatch(
          runId: run.id,
          batchId: batch.id,
          toNodeId: node.id,
          quantity: qty,
        );
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
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
                      color: isHovered ? Colors.orange : (isSelected ? accent : const Color(0xFFE2E8F0)),
                      width: isHovered || isSelected ? 1.5 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isHovered 
                            ? Colors.orange.withValues(alpha: 0.16)
                            : (isSelected
                                ? accent.withValues(alpha: 0.16)
                                : Colors.black.withValues(alpha: 0.04)),
                        blurRadius: isHovered || isSelected ? 12 : 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Row(
                      children: [
                        Container(width: 4, color: isHovered ? Colors.orange : accent),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                            child: Row(
                              children: [
                                Icon(
                                  _iconFor(activeNode, isEndpoint),
                                  size: 16,
                                  color: isHovered ? Colors.orange : accent,
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
          ],
        );
      },
    );
  }

  Widget _buildBatchTracks(BuildContext context, BatchFlowProvider batchProvider, List<int> sortedStageIndices) {
    final batches = batchProvider.batchesForRun(run.id).where((b) => b.isLive).toList();
    if (batches.isEmpty || sortedStageIndices.isEmpty) return const SizedBox.shrink();

    final double totalContentWidth = 24.0 + sortedStageIndices.length * _cardW + (sortedStageIndices.length > 0 ? sortedStageIndices.length - 1 : 0) * _connectorW + 24.0;

    return Container(
      width: totalContentWidth,
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'BATCH TRACKING',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF94A3B8),
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final batch in batches) ...[
            _buildSingleTrack(context, batch, sortedStageIndices, totalContentWidth),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildSingleTrack(BuildContext context, MaterialBatch batch, List<int> sortedStageIndices, double totalContentWidth) {
    final node = template.nodes.firstWhere((n) => n.id == batch.currentNodeId, orElse: () => template.nodes.first);
    final stageIndex = sortedStageIndices.indexOf(node.stageIndex);
    final targetX = 24.0 + stageIndex * (_cardW + _connectorW) + (_cardW / 2.0);

    return SizedBox(
      width: totalContentWidth,
      height: 28, // Matches BatchChip height
      child: Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 24.0 + (_cardW / 2.0),
            right: 24.0 + (_cardW / 2.0),
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            left: targetX,
            top: 0,
            bottom: 0,
            child: FractionalTranslation(
              translation: const Offset(-0.5, 0),
              child: BatchChip(
                batch: batch,
                compact: false,
                onRevert: null, // Revert handled via dialog instead for now
              ),
            ),
          ),
        ],
      ),
    );
  }

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
