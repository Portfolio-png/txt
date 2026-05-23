import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/soft_erp_theme.dart';
import '../providers/production_provider.dart';

class PipelineBuilderScreen extends StatefulWidget {
  const PipelineBuilderScreen({super.key});

  @override
  State<PipelineBuilderScreen> createState() => _PipelineBuilderScreenState();
}

class _PipelineBuilderScreenState extends State<PipelineBuilderScreen> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'pipeline_builder');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductionProvider>();
    final selectedStage = provider.selectedStage;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyN): () {
          context.read<ProductionProvider>().appendStage();
        },
        const SingleActivator(LogicalKeyboardKey.delete): () {
          final removed = context
              .read<ProductionProvider>()
              .deleteSelectedStage();
          if (removed == null) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${removed.name} removed.'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: context
                    .read<ProductionProvider>()
                    .undoLastStageDelete,
              ),
            ),
          );
        },
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BuilderHeader(provider: provider),
              const SizedBox(height: 16),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 980;
                    return isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Expanded(child: _PipelineCanvas()),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                width: selectedStage == null ? 0 : 420,
                                child: selectedStage == null
                                    ? const SizedBox.shrink()
                                    : _StageInspector(stage: selectedStage),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              const Expanded(child: _PipelineCanvas()),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                height: selectedStage == null ? 0 : 440,
                                child: selectedStage == null
                                    ? const SizedBox.shrink()
                                    : _StageInspector(stage: selectedStage),
                              ),
                            ],
                          );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BuilderHeader extends StatelessWidget {
  const _BuilderHeader({required this.provider});

  final ProductionProvider provider;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                provider.blueprint.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Production transformation chain: inputs, machine actions, die settings, outputs, and scrap.',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _ProductionActionButton(
          icon: Icons.add_circle_outline,
          label: 'Add Stage',
          onPressed: context.read<ProductionProvider>().appendStage,
        ),
      ],
    );
  }
}

class _PipelineCanvas extends StatefulWidget {
  const _PipelineCanvas();

  @override
  State<_PipelineCanvas> createState() => _PipelineCanvasState();
}

class _PipelineCanvasState extends State<_PipelineCanvas> {
  static const double _nodeWidth = 344;
  static const double _nodeHeight = 174;
  static const double _nodeGap = 132;
  static const double _canvasPadding = 96;
  static const double _baselineY = 188;
  static const double _minScale = 0.34;
  static const double _maxScale = 1.7;

  final TransformationController _transformController =
      TransformationController();
  double _scale = 1;
  bool _hasFitInitialView = false;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_syncScale);
  }

  @override
  void dispose() {
    _transformController
      ..removeListener(_syncScale)
      ..dispose();
    super.dispose();
  }

  void _syncScale() {
    final nextScale = _transformController.value.getMaxScaleOnAxis();
    if ((nextScale - _scale).abs() < 0.01) {
      return;
    }
    setState(() => _scale = nextScale);
  }

  @override
  Widget build(BuildContext context) {
    final stages = context.select<ProductionProvider, List<PipelineStage>>(
      (provider) => provider.blueprint.stages,
    );

    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFFAFAFA)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canvasSize = _canvasSizeFor(stages.length, constraints);
          if (!_hasFitInitialView) {
            _hasFitInitialView = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _fitToView(constraints.biggest, canvasSize);
              }
            });
          }

          return Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  transformationController: _transformController,
                  constrained: false,
                  minScale: _minScale,
                  maxScale: _maxScale,
                  boundaryMargin: const EdgeInsets.all(900),
                  child: SizedBox(
                    width: canvasSize.width,
                    height: canvasSize.height,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _PipelineCanvasPainter(
                              stages: stages.length,
                              selectedIndex: _selectedIndex(context, stages),
                              nodeWidth: _nodeWidth,
                              nodeGap: _nodeGap,
                              canvasPadding: _canvasPadding,
                              baselineY: _baselineY,
                            ),
                          ),
                        ),
                        for (var index = 0; index < stages.length; index += 1)
                          Positioned(
                            left:
                                _canvasPadding +
                                index * (_nodeWidth + _nodeGap),
                            top: _baselineY - (_nodeHeight / 2),
                            width: _nodeWidth,
                            height: _nodeHeight,
                            child: _PipelineCanvasNode(
                              stage: stages[index],
                              index: index,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 18,
                top: 18,
                child: _CanvasBadge(
                  label: 'CANVAS',
                  value: '${(_scale * 100).round()}%',
                ),
              ),
              Positioned(
                right: 18,
                top: 18,
                child: _CanvasControls(
                  onZoomOut: () => _zoomBy(0.82),
                  onZoomIn: () => _zoomBy(1.18),
                  onFit: () => _fitToView(constraints.biggest, canvasSize),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Size _canvasSizeFor(int stageCount, BoxConstraints constraints) {
    final width = math.max(
      constraints.maxWidth + 320,
      (_canvasPadding * 2) +
          (stageCount * _nodeWidth) +
          ((stageCount - 1) * _nodeGap),
    );
    final height = math.max(constraints.maxHeight + 180, 460.0);
    return Size(width, height);
  }

  int _selectedIndex(BuildContext context, List<PipelineStage> stages) {
    final selectedId = context.select<ProductionProvider, String?>(
      (provider) => provider.selectedStageId,
    );
    return stages.indexWhere((stage) => stage.id == selectedId);
  }

  void _zoomBy(double factor) {
    final current = _transformController.value;
    final currentScale = current.getMaxScaleOnAxis();
    final nextScale = (currentScale * factor).clamp(_minScale, _maxScale);
    final appliedFactor = nextScale / currentScale;
    _transformController.value = current.clone()
      ..scaleByDouble(appliedFactor, appliedFactor, appliedFactor, 1);
  }

  void _fitToView(Size viewport, Size canvas) {
    if (viewport.width <= 0 || viewport.height <= 0) {
      return;
    }
    final scale = math
        .min(
          (viewport.width - 48) / canvas.width,
          (viewport.height - 48) / canvas.height,
        )
        .clamp(_minScale, 1.0);
    final dx = (viewport.width - (canvas.width * scale)) / 2;
    final dy = (viewport.height - (canvas.height * scale)) / 2;
    _transformController.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }
}

class _PipelineCanvasNode extends StatelessWidget {
  const _PipelineCanvasNode({required this.stage, required this.index});

  final PipelineStage stage;
  final int index;

  @override
  Widget build(BuildContext context) {
    final selectedId = context.select<ProductionProvider, String?>(
      (provider) => provider.selectedStageId,
    );
    final isSelected = selectedId == stage.id;
    final rpm = 1200 + index * 150;
    final temp = 75 + index * 3;
    final telemetryText =
        '[${stage.machineId.toUpperCase()}] ${stage.machineAction.replaceAll(RegExp(r"\s+"), "_").toUpperCase()} // RPM: ${rpm.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]},")} // TEMP: ${temp}C // DIE_ID: #${stage.dieId.toUpperCase()}';

    return DragTarget<int>(
      onAcceptWithDetails: (details) {
        final oldIndex = details.data;
        if (oldIndex == index) {
          return;
        }
        final newIndex = oldIndex < index ? index + 1 : index;
        context.read<ProductionProvider>().reorderStages(oldIndex, newIndex);
      },
      builder: (context, candidateData, rejectedData) {
        final isDropTarget = candidateData.isNotEmpty;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () =>
                context.read<ProductionProvider>().selectStage(stage.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFFFFFFF)
                    : const Color(0xFFFAFAFA),
                border: Border.all(
                  color: isDropTarget
                      ? const Color(0xFF10B981)
                      : isSelected
                      ? const Color(0xFF09090B)
                      : const Color(0xFFE5E7EB),
                  width: isSelected || isDropTarget ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 14),
                        ),
                      ]
                    : null,
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${(index + 1).toString().padLeft(2, '0')}  ${stage.name}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF09090B),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _StageDragHandle(index: index, stageName: stage.name),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    telemetryText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  const SizedBox(height: 8),
                  _buildLedgerRow('INLET', stage.inputMaterial),
                  _buildLedgerRow('OUTLET', stage.outputMaterial),
                  _buildLedgerRow('SCRAP', stage.scrapPolicy),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLedgerRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1F2937),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StageDragHandle extends StatelessWidget {
  const _StageDragHandle({required this.index, required this.stageName});

  final int index;
  final String stageName;

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<int>(
      data: index,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 180,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF09090B),
            border: Border.all(color: const Color(0xFF09090B)),
          ),
          child: Text(
            stageName,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
      ),
      childWhenDragging: const Icon(
        Icons.drag_indicator_rounded,
        size: 18,
        color: Color(0xFFD4D4D8),
      ),
      child: const MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Icon(
          Icons.drag_indicator_rounded,
          size: 18,
          color: Color(0xFF9CA3AF),
        ),
      ),
    );
  }
}

class _CanvasControls extends StatelessWidget {
  const _CanvasControls({
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFit,
  });

  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CanvasIconButton(icon: Icons.remove_rounded, onPressed: onZoomOut),
          _CanvasIconButton(icon: Icons.center_focus_strong, onPressed: onFit),
          _CanvasIconButton(icon: Icons.add_rounded, onPressed: onZoomIn),
        ],
      ),
    );
  }
}

class _CanvasIconButton extends StatelessWidget {
  const _CanvasIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 42,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: icon == Icons.center_focus_strong ? 'Fit canvas' : null,
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: const Color(0xFF09090B)),
      ),
    );
  }
}

class _CanvasBadge extends StatelessWidget {
  const _CanvasBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: DefaultTextStyle(
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 0,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(color: Color(0xFFA1A1AA))),
              const SizedBox(width: 8),
              Text(value, style: const TextStyle(color: Color(0xFF09090B))),
            ],
          ),
        ),
      ),
    );
  }
}

class _PipelineCanvasPainter extends CustomPainter {
  const _PipelineCanvasPainter({
    required this.stages,
    required this.selectedIndex,
    required this.nodeWidth,
    required this.nodeGap,
    required this.canvasPadding,
    required this.baselineY,
  });

  final int stages;
  final int selectedIndex;
  final double nodeWidth;
  final double nodeGap;
  final double canvasPadding;
  final double baselineY;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE5E7EB).withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y <= size.height; y += 48) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (stages == 0) {
      return;
    }

    final firstCenter = canvasPadding + (nodeWidth / 2);
    final lastCenter =
        canvasPadding +
        ((stages - 1) * (nodeWidth + nodeGap)) +
        (nodeWidth / 2);
    final linePaint = Paint()
      ..color = const Color(0xFF09090B)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(
      Offset(firstCenter, baselineY),
      Offset(lastCenter, baselineY),
      linePaint,
    );

    for (var index = 0; index < stages; index += 1) {
      final center =
          canvasPadding + (index * (nodeWidth + nodeGap)) + (nodeWidth / 2);
      final isSelected = index == selectedIndex;
      final markerPaint = Paint()
        ..color = isSelected ? const Color(0xFF09090B) : Colors.white;
      final borderPaint = Paint()
        ..color = isSelected ? const Color(0xFF09090B) : const Color(0xFFD4D4D8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2 : 1;
      canvas.drawCircle(Offset(center, baselineY), 8, markerPaint);
      canvas.drawCircle(Offset(center, baselineY), 8, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PipelineCanvasPainter oldDelegate) {
    return oldDelegate.stages != stages ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.nodeWidth != nodeWidth ||
        oldDelegate.nodeGap != nodeGap ||
        oldDelegate.canvasPadding != canvasPadding ||
        oldDelegate.baselineY != baselineY;
  }
}

class _StageInspector extends StatelessWidget {
  const _StageInspector({required this.stage});

  final PipelineStage stage;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductionProvider>();
    final draft = provider.draftFor(stage.id);
    if (draft == null) {
      return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 0, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Stage Inspector',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            _InspectorField(label: 'Stage name', controller: draft.name),
            _InspectorField(
              label: 'Machine asset ID',
              controller: draft.machineId,
            ),
            _InspectorField(label: 'Die asset ID', controller: draft.dieId),
            _InspectorField(
              label: 'Input material',
              controller: draft.inputMaterial,
            ),
            _InspectorField(
              label: 'Machine action',
              controller: draft.machineAction,
            ),
            _InspectorField(
              label: 'Target output',
              controller: draft.outputMaterial,
            ),
            _InspectorField(
              label: 'Scrap policy',
              controller: draft.scrapPolicy,
            ),
            _InspectorField(
              label: 'Target output units',
              controller: draft.targetOutputUnits,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 54,
              width: double.infinity,
              child: _ProductionActionButton(
                onPressed: () => provider.saveStageDraft(stage.id),
                icon: Icons.save_outlined,
                label: 'Save Stage Draft',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InspectorField extends StatelessWidget {
  const _InspectorField({
    required this.label,
    required this.controller,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(
              color: Color(0xFF09090B),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
            decoration: InputDecoration(
              labelText: label.toUpperCase(),
              labelStyle: const TextStyle(
                color: Color(0xFFA1A1AA),
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductionActionButton extends StatelessWidget {
  const _ProductionActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF09090B),
      child: InkWell(
        onTap: onPressed,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF09090B)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 9),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
