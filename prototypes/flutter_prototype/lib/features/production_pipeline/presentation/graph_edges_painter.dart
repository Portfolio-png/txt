import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../app/shell/prototype_theme.dart';
import '../domain/pipeline_template.dart';
import '../domain/process_node.dart';
import 'flow_stage_card.dart';

class GraphEdgesPainter extends CustomPainter {
  final List<ProcessNode> nodes;
  final List<PipelineFlow> flows;
  final Map<String, Offset> nodePositions;
  final String? selectedNodeId;

  GraphEdgesPainter({
    required this.nodes,
    required this.flows,
    required this.nodePositions,
    this.selectedNodeId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final flow in flows) {
      final fromPos = nodePositions[flow.fromNodeId];
      final toPos = nodePositions[flow.toNodeId];

      if (fromPos == null || toPos == null) continue;

      // Source point: right edge middle of source card
      final start = Offset(
        fromPos.dx + FlowStageCard.cardWidth,
        fromPos.dy + FlowStageCard.cardHeight / 2,
      );

      // Target point: left edge middle of target card
      final end = Offset(
        toPos.dx,
        toPos.dy + FlowStageCard.cardHeight / 2,
      );

      final isHighlighted = selectedNodeId == flow.fromNodeId || selectedNodeId == flow.toNodeId;

      _drawCurvedConnector(canvas, start, end, isHighlighted);
    }
  }

  void _drawCurvedConnector(Canvas canvas, Offset start, Offset end, bool isHighlighted) {
    final dx = (end.dx - start.dx).abs();
    final controlPointOffset = math.max(40.0, dx * 0.45);

    final cp1 = Offset(start.dx + controlPointOffset, start.dy);
    final cp2 = Offset(end.dx - controlPointOffset, end.dy);

    final path = Path();
    path.moveTo(start.dx, start.dy);
    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);

    if (isHighlighted) {
      // Glow background for active connector
      final glowPaint = Paint()
        ..color = AppColors.accent.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, glowPaint);
    }

    // Main connector line
    final linePaint = Paint()
      ..color = isHighlighted ? AppColors.accent : const Color(0xFF94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isHighlighted ? 2.5 : 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    // Draw directional arrowhead at the target end
    final arrowPaint = Paint()
      ..color = isHighlighted ? AppColors.accent : const Color(0xFF64748B)
      ..style = PaintingStyle.fill;

    const arrowSize = 6.0;
    final arrowPath = Path();
    arrowPath.moveTo(end.dx, end.dy);
    arrowPath.lineTo(end.dx - arrowSize * 1.5, end.dy - arrowSize);
    arrowPath.lineTo(end.dx - arrowSize * 1.5, end.dy + arrowSize);
    arrowPath.close();
    canvas.drawPath(arrowPath, arrowPaint);

    // Small source anchor dot
    final dotPaint = Paint()
      ..color = isHighlighted ? AppColors.accent : const Color(0xFF94A3B8)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(start, 3.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant GraphEdgesPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.flows != flows ||
        oldDelegate.nodePositions != nodePositions ||
        oldDelegate.selectedNodeId != selectedNodeId;
  }
}
