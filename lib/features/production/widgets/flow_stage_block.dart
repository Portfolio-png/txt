import 'package:flutter/material.dart';
import '../../production_pipelines/domain/process_node.dart';

class FlowStageBlock extends StatelessWidget {
  const FlowStageBlock({
    super.key,
    required this.width,
    required this.height,
    required this.node,
    this.emphasized = false,
    this.target = false,
    this.isSelected = false,
  });

  final double width;
  final double height;
  final ProcessNode node;
  final bool emphasized;
  final bool target;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final palette = FlowStagePalette.forNode(node);
    final dotColor = palette.isEndpoint
        ? palette.accent
        : switch (node.status.toLowerCase()) {
            'running' || 'active' => const Color(0xFF10B981),
            'setup' || 'idle' => const Color(0xFFF59E0B),
            'reversed' => const Color(0xFFEF4444),
            'skipped' => const Color(0xFF94A3B8),
            _ => const Color(0xFF94A3B8),
          };

    final isValid =
        node.hasMachineAssignment &&
        node.inputItem != null &&
        node.outputItem != null;
    final hasError = !isValid;
    final isHighlighted = isSelected || emphasized;
    final borderColor = hasError
        ? Colors.orange
        : (isSelected
            ? const Color(0xFF3B82F6)
            : (emphasized
                ? (target
                    ? const Color(0xFF10B981)
                    : const Color(0xFFF59E0B))
                : palette.border));

    final backgroundColor = hasError
        ? Colors.orange.withValues(alpha: 0.05)
        : palette.fill;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor,
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
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
                              style: TextStyle(
                                color: palette.title,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              node.machineAssignmentLabel.isEmpty
                                  ? 'Unassigned'
                                  : node.machineAssignmentLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.subtitle,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
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
                              if (!node.hasMachineAssignment)
                                'Missing Machine / Group',
                              if (node.inputItem == null) 'Missing Input Item',
                              if (node.outputItem == null)
                                'Missing Output Item',
                            ].join('\n'),
                            child: const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange,
                              size: 16,
                            ),
                          ),
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

class FlowStagePalette {
  const FlowStagePalette({
    required this.fill,
    required this.border,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.isEndpoint,
  });

  final Color fill;
  final Color border;
  final Color accent;
  final Color title;
  final Color subtitle;
  final bool isEndpoint;

  static FlowStagePalette forNode(ProcessNode node) {
    if (node.status.toLowerCase() == 'reversed') {
      return const FlowStagePalette(
        fill: Color(0xFFFEF2F2),
        border: Color(0xFFFCA5A5),
        accent: Color(0xFFEF4444),
        title: Color(0xFF991B1B),
        subtitle: Color(0xFFB91C1C),
        isEndpoint: false,
      );
    }
    if (node.status.toLowerCase() == 'skipped') {
      return const FlowStagePalette(
        fill: Color(0xFFF1F5F9),
        border: Color(0xFFCBD5E1),
        accent: Color(0xFF94A3B8),
        title: Color(0xFF64748B),
        subtitle: Color(0xFF94A3B8),
        isEndpoint: false,
      );
    }
    if (!node.isIntermediate) {
      return const FlowStagePalette(
        fill: Color(0xFFF0FDF4),
        border: Color(0xFFBBF7D0),
        accent: Color(0xFF22C55E),
        title: Color(0xFF166534),
        subtitle: Color(0xFF15803D),
        isEndpoint: true,
      );
    }
    return const FlowStagePalette(
      fill: Colors.white,
      border: Color(0xFFE2E8F0),
      accent: Color(0xFF94A3B8),
      title: Color(0xFF1E293B),
      subtitle: Color(0xFF64748B),
      isEndpoint: false,
    );
  }
}
