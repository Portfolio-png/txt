import 'package:flutter/material.dart';
import '../../production_pipelines/domain/pipeline_template.dart';
import 'graph_edges_painter.dart';
import 'flow_stage_block.dart';

class PipelineCanvas extends StatefulWidget {
  const PipelineCanvas({
    super.key,
    required this.template,
    required this.selectedNodeId,
    required this.onNodeSelected,
  });

  final PipelineTemplate template;
  final String? selectedNodeId;
  final ValueChanged<String> onNodeSelected;

  @override
  State<PipelineCanvas> createState() => _PipelineCanvasState();
}

class _PipelineCanvasState extends State<PipelineCanvas> {
  late final TransformationController _controller;

  static const double nodeWidth = 160;
  static const double nodeHeight = 52;
  static const double columnWidth = 240;
  static const double rowHeight = 112;

  @override
  void initState() {
    super.initState();
    _controller = TransformationController();
    // Center it a bit initially
    _controller.value = Matrix4.identity()
      ..translate(-50.0, -50.0)
      ..scale(0.9);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nodes = widget.template.nodes;
    final flows = widget.template.flows;
    final stageLabels = widget.template.stageLabels;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: InteractiveViewer(
          transformationController: _controller,
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
              // Stage Labels
              for (int s = 0; s < stageLabels.length; s++)
                Positioned(
                  left: 100 + (s * columnWidth),
                  top: 50,
                  width: nodeWidth,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      stageLabels[s].toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              // Nodes
              ...nodes.map((node) {
                final isSelected = widget.selectedNodeId == node.id;
                final left = 100 + (node.stageIndex * columnWidth);
                final top = 100 + (node.laneIndex * rowHeight);

                return Positioned(
                  left: left,
                  top: top,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => widget.onNodeSelected(node.id),
                      child: FlowStageBlock(
                        width: nodeWidth,
                        height: nodeHeight,
                        node: node,
                        isSelected: isSelected,
                      ),
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
