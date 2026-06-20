import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';

import '../../production_pipelines/domain/pipeline_run.dart';
import '../../production_pipelines/domain/pipeline_template.dart';
import '../../production_pipelines/domain/process_node.dart';
import '../../production_pipelines/domain/node_run_status.dart';

import '../providers/batch_flow_provider.dart';
import 'flow_stage_block.dart';
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
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      height: 100, // align with first node
                      child: const Center(
                        child: Icon(Icons.arrow_right_alt, color: Color(0xFFCBD5E1), size: 32),
                      ),
                    ),
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

  Widget _buildStageColumn(BuildContext context, List<ProcessNode> stageNodes, String label, BatchFlowProvider batchProvider) {
    // Sort nodes by laneIndex to stack them
    final nodes = List<ProcessNode>.from(stageNodes)..sort((a, b) => a.laneIndex.compareTo(b.laneIndex));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Stage Label
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: Color(0xFF64748B),
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
    
    // Inject active status into node
    final activeNode = run.nodeStatuses.containsKey(node.id)
        ? node.copyWith(status: run.nodeStatuses[node.id]!.name)
        : node;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => onNodeSelected(node.id),
            onDoubleTap: onNodeDoubleTap == null ? null : () => onNodeDoubleTap!(node.id),
            child: Container(
              width: 180,
              height: 100,
              decoration: isSelected
                  ? BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF10B981), width: 2),
                    )
                  : null,
              child: FlowStageBlock(
                width: 180,
                height: 100,
                node: activeNode,
                isSelected: isSelected,
              ),
            ),
          ),
        ),
        if (nodeBatches.isNotEmpty) ...[
          const SizedBox(height: 8),
          NodeBatchTray(
            batches: nodeBatches,
            width: 180,
            onRevert: (b) {}, // Revert batch logic needs context, will handle later
          ),
        ],
      ],
    );
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
