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

class _FactoryFloor {
  const _FactoryFloor({
    required this.id,
    required this.code,
    required this.name,
    required this.oee,
    required this.status,
    required this.pipelines,
  });

  final String id;
  final String code;
  final String name;
  final int oee;
  final String status;
  final List<_FactoryPipeline> pipelines;
}

class _FactoryPipeline {
  const _FactoryPipeline({
    required this.id,
    required this.code,
    required this.name,
    required this.speedUnitsPerMinute,
    required this.yieldLabel,
    required this.stages,
  });

  final String id;
  final String code;
  final String name;
  final int speedUnitsPerMinute;
  final String yieldLabel;
  final List<PipelineStage> stages;
}

class _PipelineCanvasState extends State<_PipelineCanvas> {
  static const double _nodeWidth = 344;
  static const double _nodeHeight = 174;
  static const double _nodeGap = 132;
  static const double _canvasPadding = 96;
  static const double _baselineY = 188;
  static const double _minScale = 0.34;
  static const double _maxScale = 1.7;
  static const double _floorCardWidth = 336;
  static const double _floorCardHeight = 58;
  static const double _floorCardGap = 9;
  static const double _floorRunGap = 28;
  static const double _pipelineTrackWidth = 520;
  static const double _pipelineTrackHeight = 178;
  static const double _pipelineTrackGap = 42;

  final TransformationController _transformController =
      TransformationController();
  double _scale = 1;
  bool _hasFitInitialView = false;
  String? _selectedFloorId;
  String? _selectedPipelineId;
  Size _lastViewport = Size.zero;
  Size _lastCanvasSize = Size.zero;

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
    final floors = _buildFactoryFloors(stages);
    final activeFloor = _activeFloor(floors);
    final activePipeline = _activePipeline(activeFloor);

    return DecoratedBox(
      decoration: const BoxDecoration(color: SoftErpTheme.shellSurface),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canvasSize = _canvasSizeFor(
            floors: floors,
            activeFloor: activeFloor,
            activePipeline: activePipeline,
            constraints: constraints,
          );
          _lastViewport = constraints.biggest;
          _lastCanvasSize = canvasSize;
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
                          child: CustomPaint(painter: _CanvasGridPainter()),
                        ),
                        if (activePipeline != null)
                          ..._buildPipelineView(context, activePipeline)
                        else if (activeFloor != null)
                          ..._buildFloorView(activeFloor)
                        else
                          ..._buildFactoryView(floors),
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
                  value:
                      '${_levelLabel(activeFloor, activePipeline)} · ${(_scale * 100).round()}%',
                ),
              ),
              if (activeFloor != null)
                Positioned(
                  left: 18,
                  top: 62,
                  child: _CanvasPathControls(
                    floor: activeFloor,
                    pipeline: activePipeline,
                    onFactory: () {
                      setState(() {
                        _selectedFloorId = null;
                        _selectedPipelineId = null;
                      });
                      _fitCurrentViewSoon();
                    },
                    onFloor: () {
                      setState(() => _selectedPipelineId = null);
                      _fitCurrentViewSoon();
                    },
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

  List<Widget> _buildFactoryView(List<_FactoryFloor> floors) {
    final floorStackHeight = (_floorCardHeight * 6) + (_floorCardGap * 5);
    return [
      Positioned(
        left: _canvasPadding,
        top: _canvasPadding,
        child: SizedBox(
          height: floorStackHeight,
          child: Wrap(
            direction: Axis.vertical,
            verticalDirection: VerticalDirection.up,
            spacing: _floorCardGap,
            runSpacing: _floorRunGap,
            children: [
              for (final floor in floors)
                SizedBox(
                  width: _floorCardWidth,
                  height: _floorCardHeight,
                  child: _FactoryFloorCard(
                    floor: floor,
                    onTap: () {
                      setState(() {
                        _selectedFloorId = floor.id;
                        _selectedPipelineId = null;
                      });
                      _fitCurrentViewSoon();
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      Positioned(
        left: _canvasPadding,
        top: _canvasPadding + floorStackHeight + 28,
        child: const _CanvasInstructionStrip(
          eyebrow: 'LEVEL 1',
          title: 'Factory View',
          detail:
              'Floors stack bottom-to-top. Select a floor to inspect its production tracks.',
        ),
      ),
    ];
  }

  List<Widget> _buildFloorView(_FactoryFloor floor) {
    return [
      Positioned(
        left: _canvasPadding,
        top: 82,
        child: _CanvasInstructionStrip(
          eyebrow: 'LEVEL 2',
          title: '${floor.code} ${floor.name}',
          detail:
              '${floor.status.toUpperCase()} // OEE: ${floor.oee}% // ${floor.pipelines.length} ACTIVE TRACKS',
        ),
      ),
      Positioned(
        left: _canvasPadding,
        top: 174,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < floor.pipelines.length; index += 1)
              Padding(
                padding: EdgeInsets.only(
                  right: index == floor.pipelines.length - 1
                      ? 0
                      : _pipelineTrackGap,
                ),
                child: SizedBox(
                  width: _pipelineTrackWidth,
                  height: _pipelineTrackHeight,
                  child: _FloorPipelineTrack(
                    pipeline: floor.pipelines[index],
                    index: index,
                    onTap: () {
                      setState(
                        () => _selectedPipelineId = floor.pipelines[index].id,
                      );
                      _fitCurrentViewSoon();
                    },
                    onStageTap: (stage) => context
                        .read<ProductionProvider>()
                        .selectStage(stage.id),
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildPipelineView(
    BuildContext context,
    _FactoryPipeline pipeline,
  ) {
    final stages = pipeline.stages;
    return [
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
      Positioned(
        left: _canvasPadding,
        top: 48,
        child: _CanvasInstructionStrip(
          eyebrow: 'LEVEL 3 / 4',
          title: '${pipeline.code} ${pipeline.name}',
          detail:
              'SPD: ${pipeline.speedUnitsPerMinute}u/m | YLD: ${pipeline.yieldLabel} | MACHINE TELEMETRY',
        ),
      ),
      for (var index = 0; index < stages.length; index += 1)
        Positioned(
          left: _canvasPadding + index * (_nodeWidth + _nodeGap),
          top: _baselineY - (_nodeHeight / 2),
          width: _nodeWidth,
          height: _nodeHeight,
          child: _PipelineCanvasNode(stage: stages[index], index: index),
        ),
    ];
  }

  Size _canvasSizeFor({
    required List<_FactoryFloor> floors,
    required _FactoryFloor? activeFloor,
    required _FactoryPipeline? activePipeline,
    required BoxConstraints constraints,
  }) {
    if (activePipeline != null) {
      final stageCount = math.max(activePipeline.stages.length, 1);
      final width = math.max(
        constraints.maxWidth + 320,
        (_canvasPadding * 2) +
            (stageCount * _nodeWidth) +
            ((stageCount - 1) * _nodeGap),
      );
      final height = math.max(constraints.maxHeight + 180, 540.0);
      return Size(width, height);
    }

    if (activeFloor != null) {
      final trackCount = math.max(activeFloor.pipelines.length, 1);
      final width = math.max(
        constraints.maxWidth + 320,
        (_canvasPadding * 2) +
            (trackCount * _pipelineTrackWidth) +
            ((trackCount - 1) * _pipelineTrackGap),
      );
      final height = math.max(constraints.maxHeight + 180, 520.0);
      return Size(width, height);
    }

    final columns = (floors.length / 6).ceil().clamp(1, 99);
    final floorStackHeight = (_floorCardHeight * 6) + (_floorCardGap * 5);
    final width = math.max(
      constraints.maxWidth + 320,
      (_canvasPadding * 2) +
          (columns * _floorCardWidth) +
          ((columns - 1) * _floorRunGap),
    );
    final height = math.max(
      constraints.maxHeight + 180,
      (_canvasPadding * 2) + floorStackHeight + 92,
    );
    return Size(width, height);
  }

  List<_FactoryFloor> _buildFactoryFloors(List<PipelineStage> stages) {
    final safeStages = stages.isEmpty ? const <PipelineStage>[] : stages;
    final primary = _FactoryPipeline(
      id: 'pipe-board-main',
      code: 'PIPE-A',
      name: 'Board Conversion',
      speedUnitsPerMinute: 420,
      yieldLabel: '8K',
      stages: safeStages,
    );
    final finishing = _FactoryPipeline(
      id: 'pipe-finishing',
      code: 'PIPE-B',
      name: 'Finishing Loop',
      speedUnitsPerMinute: 360,
      yieldLabel: '6.4K',
      stages: safeStages.reversed.toList(growable: false),
    );
    final inspection = _FactoryPipeline(
      id: 'pipe-quality',
      code: 'PIPE-QA',
      name: 'Inspection Bypass',
      speedUnitsPerMinute: 180,
      yieldLabel: '2.1K',
      stages: safeStages.take(math.max(1, safeStages.length - 1)).toList(),
    );

    return [
      _FactoryFloor(
        id: 'floor-01',
        code: 'FLR-01',
        name: 'GROUND HEAVY',
        oee: 94,
        status: 'Live conversion',
        pipelines: [primary, finishing, inspection],
      ),
      _FactoryFloor(
        id: 'floor-02',
        code: 'FLR-02',
        name: 'DIE BAY',
        oee: 88,
        status: 'Tooling ready',
        pipelines: [finishing, primary],
      ),
      _FactoryFloor(
        id: 'floor-03',
        code: 'FLR-03',
        name: 'GLUE DECK',
        oee: 91,
        status: 'Balanced load',
        pipelines: [primary],
      ),
      _FactoryFloor(
        id: 'floor-04',
        code: 'FLR-04',
        name: 'QC BRIDGE',
        oee: 86,
        status: 'Sampling',
        pipelines: [inspection],
      ),
      _FactoryFloor(
        id: 'floor-05',
        code: 'FLR-05',
        name: 'PACKOUT',
        oee: 90,
        status: 'Buffer ok',
        pipelines: [finishing],
      ),
      _FactoryFloor(
        id: 'floor-06',
        code: 'FLR-06',
        name: 'MAINTENANCE',
        oee: 78,
        status: 'Standby',
        pipelines: [inspection, finishing],
      ),
      _FactoryFloor(
        id: 'floor-07',
        code: 'FLR-07',
        name: 'AUX CELL',
        oee: 82,
        status: 'Warm reserve',
        pipelines: [primary],
      ),
      _FactoryFloor(
        id: 'floor-08',
        code: 'FLR-08',
        name: 'EXPANSION',
        oee: 73,
        status: 'Offline',
        pipelines: [inspection],
      ),
    ];
  }

  _FactoryFloor? _activeFloor(List<_FactoryFloor> floors) {
    final selectedId = _selectedFloorId;
    if (selectedId == null) {
      return null;
    }
    for (final floor in floors) {
      if (floor.id == selectedId) {
        return floor;
      }
    }
    return null;
  }

  _FactoryPipeline? _activePipeline(_FactoryFloor? floor) {
    if (floor == null) {
      return null;
    }
    final selectedId = _selectedPipelineId;
    if (selectedId == null) {
      return null;
    }
    for (final pipeline in floor.pipelines) {
      if (pipeline.id == selectedId) {
        return pipeline;
      }
    }
    return null;
  }

  String _levelLabel(_FactoryFloor? floor, _FactoryPipeline? pipeline) {
    if (pipeline != null) {
      return 'PIPELINE';
    }
    if (floor != null) {
      return 'FLOOR';
    }
    return 'FACTORY';
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

  void _fitCurrentViewSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fitToView(_lastViewport, _lastCanvasSize);
      }
    });
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

class _FactoryFloorCard extends StatelessWidget {
  const _FactoryFloorCard({required this.floor, required this.onTap});

  final _FactoryFloor floor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLowOee = floor.oee < 82;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: isLowOee
                ? SoftErpTheme.warningBg
                : SoftErpTheme.cardSurfaceAlt,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: DefaultTextStyle(
            style: const TextStyle(
              fontFamily: 'monospace',
              color: SoftErpTheme.textPrimary,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '[${floor.code}] ${floor.name} // OEE: ${floor.oee}%',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: isLowOee
                        ? SoftErpTheme.warningText
                        : SoftErpTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${floor.status.toUpperCase()} // PIPES: ${floor.pipelines.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: SoftErpTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FloorPipelineTrack extends StatelessWidget {
  const _FloorPipelineTrack({
    required this.pipeline,
    required this.index,
    required this.onTap,
    required this.onStageTap,
  });

  final _FactoryPipeline pipeline;
  final int index;
  final VoidCallback onTap;
  final ValueChanged<PipelineStage> onStageTap;

  @override
  Widget build(BuildContext context) {
    const centerY = 92.0;
    const nodeWidth = 126.0;
    const nodeHeight = 48.0;
    final stageCount = math.max(pipeline.stages.length, 1);
    const railStart = 88.0;
    const availableWidth = 344.0;
    final step = stageCount <= 1 ? 0.0 : availableWidth / (stageCount - 1);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: SoftErpTheme.surfaceDecoration(
            color: SoftErpTheme.cardSurface,
            radius: SoftErpTheme.radiusMd,
            elevated: false,
            strongBorder: index == 0,
          ),
          child: Stack(
            children: [
              Positioned(
                left: 28,
                right: 28,
                top: centerY,
                child: const Divider(
                  height: 1,
                  thickness: 1.4,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
              Positioned(
                left: 20,
                top: 16,
                right: 20,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${pipeline.code} ${pipeline.name}'.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: SoftErpTheme.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      'SPD: ${pipeline.speedUnitsPerMinute}u/m | YLD: ${pipeline.yieldLabel}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: SoftErpTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              for (var i = 0; i < pipeline.stages.length; i += 1)
                Positioned(
                  left: railStart + (i * step) - (nodeWidth / 2),
                  top: centerY - (nodeHeight / 2),
                  width: nodeWidth,
                  height: nodeHeight,
                  child: _PipelineStageChip(
                    stage: pipeline.stages[i],
                    index: i,
                    onTap: () => onStageTap(pipeline.stages[i]),
                  ),
                ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 15,
                child: Text(
                  'CLICK TRACK TO ZOOM // CLICK NODE TO INSPECT STAGE',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: SoftErpTheme.textSecondary.withValues(alpha: 0.78),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PipelineStageChip extends StatelessWidget {
  const _PipelineStageChip({
    required this.stage,
    required this.index,
    required this.onTap,
  });

  final PipelineStage stage;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedId = context.select<ProductionProvider, String?>(
      (provider) => provider.selectedStageId,
    );
    final isSelected = selectedId == stage.id;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: isSelected
                ? SoftErpTheme.accent
                : SoftErpTheme.cardSurfaceAlt,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'STG-${(index + 1).toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: isSelected ? Colors.white : SoftErpTheme.accent,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                stage.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: isSelected ? Colors.white : SoftErpTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CanvasInstructionStrip extends StatelessWidget {
  const _CanvasInstructionStrip({
    required this.eyebrow,
    required this.title,
    required this.detail,
  });

  final String eyebrow;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              eyebrow,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: SoftErpTheme.accent,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: SoftErpTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              detail,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CanvasPathControls extends StatelessWidget {
  const _CanvasPathControls({
    required this.floor,
    required this.pipeline,
    required this.onFactory,
    required this.onFloor,
  });

  final _FactoryFloor floor;
  final _FactoryPipeline? pipeline;
  final VoidCallback onFactory;
  final VoidCallback onFloor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CanvasPathButton(label: 'FACTORY', onPressed: onFactory),
            const _PathSeparator(),
            _CanvasPathButton(label: floor.code, onPressed: onFloor),
            if (pipeline != null) ...[
              const _PathSeparator(),
              Text(
                pipeline!.code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CanvasPathButton extends StatelessWidget {
  const _CanvasPathButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w900,
            fontSize: 11,
            color: SoftErpTheme.accent,
          ),
        ),
      ),
    );
  }
}

class _PathSeparator extends StatelessWidget {
  const _PathSeparator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '/',
        style: TextStyle(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w900,
          fontSize: 11,
          color: SoftErpTheme.textSecondary,
        ),
      ),
    );
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
    final strokeCount = 45021 + (index * 7340);

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
                    ? SoftErpTheme.cardSurface
                    : SoftErpTheme.cardSurfaceAlt,
                border: Border.all(
                  color: isDropTarget
                      ? SoftErpTheme.successText
                      : isSelected
                      ? SoftErpTheme.accent
                      : SoftErpTheme.borderStrong,
                  width: isSelected || isDropTarget ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: SoftErpTheme.accent.withValues(alpha: 0.12),
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
                  Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? SoftErpTheme.accent
                          : SoftErpTheme.textPrimary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${(index + 1).toString().padLeft(2, '0')}  ${stage.name}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _StageDragHandle(index: index, stageName: stage.name),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              _buildLedgerRow('ACT_DIE', '#${stage.dieId}'),
                              _buildLedgerRow(
                                'MTL_IN',
                                _compactMaterial(stage.inputMaterial),
                              ),
                              _buildLedgerRow(
                                'STRK_CNT',
                                _formatInt(strokeCount),
                              ),
                              _buildLedgerRow('RPM_ACT', rpm.toString()),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            children: [
                              _buildLedgerRow('MCH_ID', stage.machineId),
                              _buildLedgerRow(
                                'MTL_OUT',
                                _compactMaterial(stage.outputMaterial),
                              ),
                              _buildLedgerRow(
                                'YLD_TGT',
                                _formatInt(stage.targetOutputUnits),
                              ),
                              _buildLedgerRow('SCRAP', stage.scrapPolicy),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _compactMaterial(String value) {
    return value
        .replaceAll(RegExp(r'[, ]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .toUpperCase();
  }

  String _formatInt(int value) {
    final text = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i += 1) {
      final fromEnd = text.length - i;
      buffer.write(text[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }

  Widget _buildLedgerRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                height: 1.05,
                fontWeight: FontWeight.w800,
                color: SoftErpTheme.textSecondary,
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
                fontSize: 9,
                height: 1.05,
                fontWeight: FontWeight.w800,
                color: SoftErpTheme.textPrimary,
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
            color: SoftErpTheme.textPrimary,
            border: Border.all(color: SoftErpTheme.textPrimary),
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
      childWhenDragging: const Text(
        'MOVE',
        style: TextStyle(
          color: Color(0xFFD4D4D8),
          fontFamily: 'monospace',
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
      child: const MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Text(
          'MOVE',
          style: TextStyle(
            color: Colors.white70,
            fontFamily: 'monospace',
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
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

class _CanvasGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = SoftErpTheme.border.withValues(alpha: 0.58)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y <= size.height; y += 48) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final originPaint = Paint()
      ..color = SoftErpTheme.accent.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), originPaint);
  }

  @override
  bool shouldRepaint(covariant _CanvasGridPainter oldDelegate) => false;
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
