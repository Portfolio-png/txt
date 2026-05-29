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
    final selectedId = provider.selectedNodeId;
    final selectedIndex = nodes.indexWhere((n) => n.id == selectedId);
    final runState = context.select<ProductionRunProvider, ProductionState>(
      (p) => p.state,
    );

    return Container(
      width: double.infinity,
      height: 120,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: nodes.length,
        separatorBuilder: (context, index) {
          final isPast = index < selectedIndex;
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
          final isSelected = nodes[index].id == selectedId;
          final isCompleted = index < selectedIndex;
          final isActive = isSelected &&
              (runState == ProductionState.running ||
                  runState == ProductionState.paused);
          return Center(
            child: _FlowNode(
              node: nodes[index],
              index: index,
              isSelected: isSelected,
              isCompleted: isCompleted,
              isActive: isActive,
              onTap: () => provider.selectNode(nodes[index].id),
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
                    'NODE ${index + 1}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: isCompleted
                          ? const Color(0xFF10B981)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  if (isCompleted)
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
