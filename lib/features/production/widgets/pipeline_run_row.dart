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

  static const double _cardW = 140;
  static const double _cardH = 48;
  static const double _captionBlockH = 32;
  static const double _connectorW = 56;

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
                const SizedBox(width: 16),
                const Tooltip(
                  message: 'Color Legend:\n🟢 Done / Completed\n🔵 Active / Running\n⚪ Pending\n🟠 Warning / Missing Setup',
                  child: Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF94A3B8)),
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
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
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 9.5,
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

    // Group the stages list for the drop zones
    final stagesDict = <int, List<ProcessNode>>{};
    for (final node in template.nodes) {
      stagesDict.putIfAbsent(node.stageIndex, () => []).add(node);
    }

    return Container(
      width: totalContentWidth,
      padding: const EdgeInsets.only(bottom: 32),
      child: Stack(
        children: [
          // Background Drop Zones matching the column areas
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(width: 24.0),
                for (int i = 0; i < sortedStageIndices.length; i++) ...[
                  if (i > 0) const SizedBox(width: _connectorW),
                  SizedBox(
                    width: _cardW,
                    child: _buildTrackDropZone(context, stagesDict[sortedStageIndices[i]]!, batchProvider),
                  ),
                ],
                const SizedBox(width: 24.0),
              ],
            ),
          ),
          // Foreground Tracks
          Column(
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
              for (int i = 0; i < batches.length; i++) ...[
                _buildSingleTrack(context, batches[i], i, sortedStageIndices, totalContentWidth),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrackDropZone(BuildContext context, List<ProcessNode> stageNodes, BatchFlowProvider batchProvider) {
    return DragTarget<MaterialBatch>(
      onWillAcceptWithDetails: (details) {
        final batch = details.data;
        return !stageNodes.any((n) => n.id == batch.currentNodeId);
      },
      onAcceptWithDetails: (details) async {
        final batch = details.data;
        ProcessNode targetNode = stageNodes.first;
        if (stageNodes.length > 1) {
          final selected = await showDialog<ProcessNode>(
             context: context,
             builder: (ctx) => SimpleDialog(
               title: const Text('Select Target Node'),
               children: stageNodes.map((n) => SimpleDialogOption(
                 onPressed: () => Navigator.pop(ctx, n),
                 child: Text(n.name),
               )).toList(),
             ),
          );
          if (selected == null) return;
          targetNode = selected;
        }

        final qty = await BatchSplitDialog.show(
          context,
          batch: batch,
          targetNodeName: targetNode.name.isEmpty ? 'station' : targetNode.name,
        );
        if (qty == null) return;
        
        batchProvider.moveBatch(
          runId: run.id,
          batchId: batch.id,
          toNodeId: targetNode.id,
          quantity: qty,
        );
      },
      builder: (context, candidateData, rejectedData) {
        return const SizedBox.expand();
      },
    );
  }

  Widget _buildSingleTrack(BuildContext context, MaterialBatch batch, int index, List<int> sortedStageIndices, double totalContentWidth) {
    final node = template.nodes.firstWhere((n) => n.id == batch.currentNodeId, orElse: () => template.nodes.first);
    final stageIndex = sortedStageIndices.indexOf(node.stageIndex);
    final targetX = 24.0 + stageIndex * (_cardW + _connectorW) + (_cardW / 2.0);

    return SizedBox(
      width: totalContentWidth,
      height: 22, // Matches BatchChip height
      child: Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [
          // Batch Name Label
          Positioned(
            left: 24.0,
            child: SizedBox(
              width: (_cardW / 2.0) - 16.0, // Space between left edge and start of track
              child: Text(
                'Batch ${index + 1}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Positioned(
            left: 24.0 + (_cardW / 2.0),
            right: 24.0 + (_cardW / 2.0),
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 1000),
            curve: Curves.elasticOut,
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
