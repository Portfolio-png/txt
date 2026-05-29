import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../production_pipelines/domain/process_node.dart';
import '../../production_pipelines/domain/material_flow.dart';

class GraphEdgesPainter extends CustomPainter {
  GraphEdgesPainter({
    required this.nodes,
    required this.flows,
    required this.columnWidth,
    required this.rowHeight,
    required this.nodeWidth,
    required this.nodeHeight,
  });

  final List<ProcessNode> nodes;
  final List<MaterialFlow> flows;
  final double columnWidth;
  final double rowHeight;
  final double nodeWidth;
  final double nodeHeight;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw Dot Grid
    final dotPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.fill;

    for (double x = 0; x < size.width; x += 20) {
      for (double y = 0; y < size.height; y += 20) {
        canvas.drawCircle(Offset(x, y), 1.5, dotPaint);
      }
    }

    final linePaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final flow in flows) {
      final fromNode = nodes.where((n) => n.id == flow.fromNodeId).firstOrNull;
      final toNode = nodes.where((n) => n.id == flow.toNodeId).firstOrNull;

      if (fromNode != null && toNode != null) {
        final startX = 100 + (fromNode.stageIndex * columnWidth) + nodeWidth;
        final startY =
            100 + (fromNode.laneIndex * rowHeight) + (nodeHeight / 2);

        final endX = 100 + (toNode.stageIndex * columnWidth);
        final endY = 100 + (toNode.laneIndex * rowHeight) + (nodeHeight / 2);

        final path = Path();
        path.moveTo(startX, startY);

        final midX = startX + (endX - startX) / 2;
        path.cubicTo(midX, startY, midX, endY, endX, endY);

        canvas.drawPath(path, linePaint);

        // Arrow head
        final arrowPath = Path();
        arrowPath.moveTo(endX, endY);
        arrowPath.lineTo(endX - 8, endY - 4);
        arrowPath.lineTo(endX - 8, endY + 4);
        arrowPath.close();

        final arrowPaint = Paint()
          ..color = const Color(0xFF94A3B8)
          ..style = PaintingStyle.fill;
        canvas.drawPath(arrowPath, arrowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant GraphEdgesPainter oldDelegate) {
    return !listEquals(oldDelegate.nodes, nodes) ||
        !listEquals(oldDelegate.flows, flows) ||
        oldDelegate.columnWidth != columnWidth ||
        oldDelegate.rowHeight != rowHeight ||
        oldDelegate.nodeWidth != nodeWidth ||
        oldDelegate.nodeHeight != nodeHeight;
  }
}
