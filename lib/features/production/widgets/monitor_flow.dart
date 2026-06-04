import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/production_provider.dart';
import '../providers/production_run_provider.dart';
import '../../production_pipelines/domain/process_node.dart';

class MonitorPipelineFlow extends StatelessWidget {
  const MonitorPipelineFlow({super.key, required this.provider});

  final ProductionProvider provider;

  @override
  Widget build(BuildContext context) {
    final nodes = provider.template.nodes;
    final Map<int, List<ProcessNode>> nodesByStage = {};
    for (final node in nodes) {
      nodesByStage.putIfAbsent(node.stageIndex, () => []).add(node);
    }
    final stages = nodesByStage.keys.toList()..sort();
    
    final selectedId = provider.selectedNodeId;
    final selectedNode = nodes.firstWhere((n) => n.id == selectedId, orElse: () => nodes.first);
    final selectedStageIndex = selectedNode.stageIndex;

    final runState = context.select<ProductionRunProvider, ProductionState>(
      (p) => p.state,
    );

    return Container(
      width: double.infinity,
      height: 160,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: stages.length,
        separatorBuilder: (context, index) {
          final isPast = stages[index] < selectedStageIndex;
          return Container(
            width: 40,
            alignment: Alignment.center,
            child: Container(
              height: 2,
              color: isPast ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
            ),
          );
        },
        itemBuilder: (context, index) {
          final stageNodes = nodesByStage[stages[index]]!;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: stageNodes.map((node) {
                final isSelected = node.id == selectedId;
                final isCompleted = node.stageIndex < selectedStageIndex || node.status == 'Reversed' || node.status == 'Skipped';
                final isActive = isSelected &&
                    (runState == ProductionState.running ||
                        runState == ProductionState.paused);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _FlowNode(
                    node: node,
                    index: node.stageIndex,
                    isSelected: isSelected,
                    isCompleted: isCompleted,
                    isActive: isActive,
                    onTap: () => provider.selectNode(node.id),
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}

class _FlowNode extends StatelessWidget {
  const _FlowNode({
    required this.node,
    required this.index,
    required this.isSelected,
    required this.isCompleted,
    required this.isActive,
    required this.onTap,
  });

  final ProcessNode node;
  final int index;
  final bool isSelected;
  final bool isCompleted;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = isCompleted
        ? const Color(0xFF10B981)
        : isSelected
            ? const Color(0xFF2563EB)
            : const Color(0xFFCBD5E1);
    final bgColor = isActive
        ? const Color(0xFF2563EB).withValues(alpha: 0.05)
        : Colors.white;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                      blurRadius: 12,
                      spreadRadius: 2,
                    )
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    node.status == 'Reversed' ? 'REWORK / REVERSED' : 
                    node.status == 'Skipped' ? 'SKIPPED' : 'STAGE ${index + 1}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: node.status == 'Reversed' ? const Color(0xFFEF4444) :
                             node.status == 'Skipped' ? const Color(0xFFF59E0B) :
                             isCompleted
                          ? const Color(0xFF10B981)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  if (isCompleted && node.status != 'Reversed' && node.status != 'Skipped')
                    const Icon(Icons.check_circle,
                        size: 14, color: Color(0xFF10B981)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                node.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'MC: ${node.machine}',
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
