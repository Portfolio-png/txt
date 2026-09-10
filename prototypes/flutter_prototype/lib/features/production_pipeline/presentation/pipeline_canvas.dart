import 'package:flutter/material.dart';
import '../../../app/shell/prototype_theme.dart';
import '../domain/pipeline_template.dart';
import '../domain/process_node.dart';
import 'flow_stage_card.dart';
import 'graph_edges_painter.dart';

class PipelineCanvas extends StatefulWidget {
  final PipelineTemplate template;
  final PipelineRun? run;
  final String? selectedNodeId;
  final ValueChanged<String?> onSelectNode;
  final ValueChanged<ProcessNode> onUpdateNode;
  final Function(String fromId, String toId) onAddFlow;
  final Function(int stageIndex) onAddNodeToStage;
  final VoidCallback onAddStage;

  const PipelineCanvas({
    super.key,
    required this.template,
    this.run,
    this.selectedNodeId,
    required this.onSelectNode,
    required this.onUpdateNode,
    required this.onAddFlow,
    required this.onAddNodeToStage,
    required this.onAddStage,
  });

  @override
  State<PipelineCanvas> createState() => _PipelineCanvasState();
}

class _PipelineCanvasState extends State<PipelineCanvas> {
  final TransformationController _transformController = TransformationController();
  final Map<String, Offset> _customOffsets = {};
  String? _connectingFromNodeId;

  static const double stageColWidth = 280;
  static const double stagePaddingX = 60;
  static const double nodeStartY = 90;
  static const double nodeSpacingY = 140;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  Offset _getNodePosition(ProcessNode node) {
    final defaultPos = Offset(
      stagePaddingX + node.stageIndex * stageColWidth,
      nodeStartY + node.laneIndex * nodeSpacingY,
    );
    final customOffset = _customOffsets[node.id] ?? Offset.zero;
    return defaultPos + customOffset;
  }

  Map<String, Offset> _calculateAllPositions() {
    final map = <String, Offset>{};
    for (final node in widget.template.nodes) {
      map[node.id] = _getNodePosition(node);
    }
    return map;
  }

  int get _maxStageIndex {
    if (widget.template.nodes.isEmpty) return 0;
    return widget.template.nodes.map((n) => n.stageIndex).reduce((a, b) => a > b ? a : b);
  }

  @override
  Widget build(BuildContext context) {
    final positions = _calculateAllPositions();
    final totalWidth = (stagePaddingX * 2) + ((_maxStageIndex + 2) * stageColWidth);
    const totalHeight = 800.0;

    return Container(
      color: AppColors.background,
      child: Stack(
        children: [
          // Interactive Pan & Zoom Canvas
          InteractiveViewer(
            transformationController: _transformController,
            boundaryMargin: const EdgeInsets.all(500),
            minScale: 0.4,
            maxScale: 2.0,
            constrained: false,
            child: SizedBox(
              width: totalWidth,
              height: totalHeight,
              child: Stack(
                children: [
                  // Dot Grid Background
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _DotGridPainter(),
                    ),
                  ),

                  // Stage Column Headers & Guides
                  ...List.generate(_maxStageIndex + 1, (index) {
                    final stageX = stagePaddingX + index * stageColWidth;
                    final stageLabel = index < widget.template.stageLabels.length
                        ? widget.template.stageLabels[index]
                        : 'Stage ${index + 1}';

                    return Positioned(
                      left: stageX,
                      top: 24,
                      child: Row(
                        children: [
                          Container(
                            width: FlowStageCard.cardWidth,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'STAGE ${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textMuted,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    stageLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  // Connecting Bezier Edges
                  Positioned.fill(
                    child: CustomPaint(
                      painter: GraphEdgesPainter(
                        nodes: widget.template.nodes,
                        flows: widget.template.flows,
                        nodePositions: positions,
                        selectedNodeId: widget.selectedNodeId,
                      ),
                    ),
                  ),

                  // Process Nodes (Draggable & Clickable)
                  ...widget.template.nodes.map((node) {
                    final pos = positions[node.id] ?? Offset.zero;
                    final isSelected = widget.selectedNodeId == node.id;
                    final isConnecting = _connectingFromNodeId == node.id;
                    final status = widget.run?.nodeStatuses[node.id] ?? 'pending';

                    return Positioned(
                      left: pos.dx,
                      top: pos.dy,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            final current = _customOffsets[node.id] ?? Offset.zero;
                            _customOffsets[node.id] = current + details.delta;
                          });
                        },
                        child: FlowStageCard(
                          node: node,
                          isSelected: isSelected,
                          isConnecting: isConnecting,
                          status: status,
                          onTap: () {
                            if (_connectingFromNodeId != null && _connectingFromNodeId != node.id) {
                              widget.onAddFlow(_connectingFromNodeId!, node.id);
                              setState(() => _connectingFromNodeId = null);
                            } else {
                              widget.onSelectNode(node.id);
                            }
                          },
                        ),
                      ),
                    );
                  }),

                  // Add Stage Column Button at the end
                  Positioned(
                    left: stagePaddingX + (_maxStageIndex + 1) * stageColWidth,
                    top: 24,
                    child: OutlinedButton.icon(
                      onPressed: widget.onAddStage,
                      icon: const Icon(Icons.add_circle_outline, size: 16),
                      label: const Text('Add Stage Column'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.accent, style: BorderStyle.solid),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Floating Canvas Controls (Zoom In/Out/Reset & Link mode)
          Positioned(
            left: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Zoom In',
                    icon: const Icon(Icons.add, size: 18, color: AppColors.textSecondary),
                    onPressed: () {
                      final current = _transformController.value.clone();
                      current.scaleByDouble(1.2, 1.2, 1.0, 1.0);
                      _transformController.value = current;
                    },
                  ),
                  IconButton(
                    tooltip: 'Zoom Out',
                    icon: const Icon(Icons.remove, size: 18, color: AppColors.textSecondary),
                    onPressed: () {
                      final current = _transformController.value.clone();
                      current.scaleByDouble(0.83, 0.83, 1.0, 1.0);
                      _transformController.value = current;
                    },
                  ),
                  IconButton(
                    tooltip: 'Reset Canvas View',
                    icon: const Icon(Icons.center_focus_strong_outlined, size: 18, color: AppColors.textSecondary),
                    onPressed: () {
                      _transformController.value = Matrix4.identity();
                      setState(() {
                        _customOffsets.clear();
                      });
                    },
                  ),
                  const SizedBox(width: 4),
                  Container(width: 1, height: 20, color: AppColors.border),
                  const SizedBox(width: 4),
                  if (widget.selectedNodeId != null)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          if (_connectingFromNodeId == widget.selectedNodeId) {
                            _connectingFromNodeId = null;
                          } else {
                            _connectingFromNodeId = widget.selectedNodeId;
                          }
                        });
                      },
                      icon: Icon(
                        _connectingFromNodeId != null ? Icons.close : Icons.linear_scale,
                        size: 16,
                        color: _connectingFromNodeId != null ? AppColors.warning : AppColors.accent,
                      ),
                      label: Text(
                        _connectingFromNodeId != null ? 'Cancel Connection' : 'Connect Flow Arrow',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _connectingFromNodeId != null ? AppColors.warning : AppColors.accent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = const Color(0xFFCBD5E1).withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;

    const spacing = 24.0;
    const radius = 1.0;

    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
