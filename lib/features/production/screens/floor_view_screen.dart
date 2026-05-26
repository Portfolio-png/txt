import 'dart:math' as math;

import 'package:flutter/material.dart';

enum PipelineStatus { running, waiting, blocked, idle }

enum ZoneStatus { normal, active, constrained, blocked }

enum AlertSeverity { info, warning, danger }

class KpiTrend {
  const KpiTrend({required this.label, required this.delta});

  final String label;
  final double delta;
}

class FloorSummary {
  const FloorSummary({
    required this.id,
    required this.name,
    required this.areaName,
    required this.oee,
    required this.oeeTrend,
    required this.totalYield,
    required this.yieldTarget,
    required this.activeMachines,
    required this.totalMachines,
    required this.operatorHeadcount,
    required this.topBottleneckPipelineId,
  });

  final String id;
  final String name;
  final String areaName;
  final double oee;
  final KpiTrend oeeTrend;
  final int totalYield;
  final int yieldTarget;
  final int activeMachines;
  final int totalMachines;
  final int operatorHeadcount;
  final String topBottleneckPipelineId;

  double get utilization => totalMachines == 0
      ? 0
      : (activeMachines / totalMachines).clamp(0, 1).toDouble();
}

class PipelineSummary {
  const PipelineSummary({
    required this.id,
    required this.name,
    required this.status,
    required this.oee,
    required this.outputActual,
    required this.outputTarget,
    required this.queueMinutes,
    required this.stationCount,
    required this.activeOperators,
    required this.alertCount,
    required this.bottleneckReason,
    required this.bottleneckImpact,
  });

  final String id;
  final String name;
  final PipelineStatus status;
  final double oee;
  final int outputActual;
  final int outputTarget;
  final int queueMinutes;
  final int stationCount;
  final int activeOperators;
  final int alertCount;
  final String bottleneckReason;
  final String bottleneckImpact;

  double get progress => outputTarget == 0
      ? 0
      : (outputActual / outputTarget).clamp(0, 1).toDouble();
}

class ProductionZone {
  const ProductionZone({
    required this.id,
    required this.name,
    required this.rect,
    required this.type,
    required this.status,
  });

  final String id;
  final String name;
  final Rect rect;
  final String type;
  final ZoneStatus status;
}

class StationNode {
  const StationNode({
    required this.id,
    required this.label,
    required this.zoneId,
    required this.position,
    required this.status,
    required this.pipelineId,
    this.isBottleneck = false,
  });

  final String id;
  final String label;
  final String zoneId;
  final Offset position;
  final PipelineStatus status;
  final String pipelineId;
  final bool isBottleneck;
}

class PipelineRoute {
  const PipelineRoute({
    required this.id,
    required this.pipelineId,
    required this.points,
    required this.status,
  });

  final String id;
  final String pipelineId;
  final List<Offset> points;
  final PipelineStatus status;
}

class FloorAlert {
  const FloorAlert({
    required this.severity,
    required this.title,
    required this.message,
    required this.position,
    this.relatedPipelineId,
  });

  final AlertSeverity severity;
  final String title;
  final String message;
  final Offset position;
  final String? relatedPipelineId;
}

class FloorOpsTokens {
  const FloorOpsTokens({
    required this.backgroundBase,
    required this.surfacePanel,
    required this.surfaceFloating,
    required this.surfaceCanvas,
    required this.mapGround,
    required this.mapDraftLine,
    required this.mapBlock,
    required this.mapBlockMuted,
    required this.mapBlockSelected,
    required this.mapBlockBorder,
    required this.mapRoute,
    required this.mapRouteSelected,
    required this.textPrimary,
    required this.textSecondary,
    required this.borderSubtle,
    required this.success,
    required this.warning,
    required this.danger,
    required this.selection,
    required this.muted,
  });

  final Color backgroundBase;
  final Color surfacePanel;
  final Color surfaceFloating;
  final Color surfaceCanvas;
  final Color mapGround;
  final Color mapDraftLine;
  final Color mapBlock;
  final Color mapBlockMuted;
  final Color mapBlockSelected;
  final Color mapBlockBorder;
  final Color mapRoute;
  final Color mapRouteSelected;
  final Color textPrimary;
  final Color textSecondary;
  final Color borderSubtle;
  final Color success;
  final Color warning;
  final Color danger;
  final Color selection;
  final Color muted;

  static const factoryMap = FloorOpsTokens(
    backgroundBase: Color(0xFFEEF1F2),
    surfacePanel: Color(0xFFFFFFFF),
    surfaceFloating: Color(0xF7FFFFFF),
    surfaceCanvas: Color(0xFFF5F6F3),
    mapGround: Color(0xFFF0F1EC),
    mapDraftLine: Color(0xFFDADDD6),
    mapBlock: Color(0xFFF9FAF7),
    mapBlockMuted: Color(0xFFE8EBE5),
    mapBlockSelected: Color(0xFFE7F0EE),
    mapBlockBorder: Color(0xFFCDD3CC),
    mapRoute: Color(0xFFBCC5C0),
    mapRouteSelected: Color(0xFF256D66),
    textPrimary: Color(0xFF263130),
    textSecondary: Color(0xFF6A7572),
    borderSubtle: Color(0xFFD9DEDA),
    success: Color(0xFF2F8069),
    warning: Color(0xFFB7791F),
    danger: Color(0xFFB84A45),
    selection: Color(0xFF256D66),
    muted: Color(0xFF94A09C),
  );

  Color pipelineStatus(PipelineStatus status) {
    return switch (status) {
      PipelineStatus.running => success,
      PipelineStatus.waiting => warning,
      PipelineStatus.blocked => danger,
      PipelineStatus.idle => muted,
    };
  }

  Color alertSeverity(AlertSeverity severity) {
    return switch (severity) {
      AlertSeverity.info => selection,
      AlertSeverity.warning => warning,
      AlertSeverity.danger => danger,
    };
  }
}

class FloorViewScreen extends StatefulWidget {
  const FloorViewScreen({
    super.key,
    this.tokens = FloorOpsTokens.factoryMap,
    this.onPipelineSelected,
    this.onOpenPipeline,
    this.onOpenAlert,
    this.onOpenFloorSettings,
  });

  final FloorOpsTokens tokens;
  final ValueChanged<String>? onPipelineSelected;
  final ValueChanged<String>? onOpenPipeline;
  final ValueChanged<FloorAlert>? onOpenAlert;
  final VoidCallback? onOpenFloorSettings;

  @override
  State<FloorViewScreen> createState() => _FloorViewScreenState();
}

class _FloorViewScreenState extends State<FloorViewScreen> {
  final _data = _FloorMockData();
  late String _selectedPipelineId;

  @override
  void initState() {
    super.initState();
    _selectedPipelineId = _data.floor.topBottleneckPipelineId;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final selectedPipeline = _data.pipelineById(_selectedPipelineId);

    return Scaffold(
      backgroundColor: tokens.backgroundBase,
      body: SafeArea(
        child: Column(
          children: [
            FloorTopBar(tokens: tokens, onDispatch: widget.onOpenFloorSettings),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 1040) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FloorNavRail(tokens: tokens),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              children: [
                                SizedBox(
                                  height: 272,
                                  child: FloorOperationsPane(
                                    tokens: tokens,
                                    floor: _data.floor,
                                    pipelines: _data.pipelines,
                                    selectedPipelineId: _selectedPipelineId,
                                    onPipelineSelected: _selectPipeline,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  height: 620,
                                  child: FloorMapCanvas(
                                    tokens: tokens,
                                    zones: _data.zones,
                                    routes: _data.routes,
                                    stations: _data.stations,
                                    alerts: _data.alerts,
                                    selectedPipelineId: _selectedPipelineId,
                                    onOpenPipeline: () => widget.onOpenPipeline
                                        ?.call(_selectedPipelineId),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                FloorTelemetryPane(
                                  tokens: tokens,
                                  floor: _data.floor,
                                  selectedPipeline: selectedPipeline,
                                  alerts: _data.alerts,
                                  onOpenAlert: widget.onOpenAlert,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  final leftWidth = constraints.maxWidth < 1280 ? 286.0 : 312.0;
                  final rightWidth = constraints.maxWidth < 1280
                      ? 300.0
                      : 330.0;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FloorNavRail(tokens: tokens),
                      SizedBox(
                        width: leftWidth,
                        child: FloorOperationsPane(
                          tokens: tokens,
                          floor: _data.floor,
                          pipelines: _data.pipelines,
                          selectedPipelineId: _selectedPipelineId,
                          onPipelineSelected: _selectPipeline,
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                          child: FloorMapCanvas(
                            tokens: tokens,
                            zones: _data.zones,
                            routes: _data.routes,
                            stations: _data.stations,
                            alerts: _data.alerts,
                            selectedPipelineId: _selectedPipelineId,
                            onOpenPipeline: () => widget.onOpenPipeline?.call(
                              _selectedPipelineId,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: rightWidth,
                        child: FloorTelemetryPane(
                          tokens: tokens,
                          floor: _data.floor,
                          selectedPipeline: selectedPipeline,
                          alerts: _data.alerts,
                          onOpenAlert: widget.onOpenAlert,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectPipeline(String pipelineId) {
    setState(() => _selectedPipelineId = pipelineId);
    widget.onPipelineSelected?.call(pipelineId);
  }
}

class FloorTopBar extends StatelessWidget {
  const FloorTopBar({super.key, required this.tokens, this.onDispatch});

  final FloorOpsTokens tokens;
  final VoidCallback? onDispatch;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: tokens.backgroundBase,
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tokens.textPrimary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.factory_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Floor Operations',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Factory / Floor 2 / Fabrication',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(width: 26),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: _MapSearchField(tokens: tokens),
            ),
          ),
          const Spacer(),
          _GhostButton(
            tokens: tokens,
            icon: Icons.help_outline_rounded,
            label: 'Help',
          ),
          const SizedBox(width: 8),
          _TimeRangeButton(tokens: tokens),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onDispatch,
            icon: const Icon(Icons.add_road_rounded, size: 16),
            label: const Text('Dispatch'),
            style: FilledButton.styleFrom(
              backgroundColor: tokens.selection,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapSearchField extends StatelessWidget {
  const _MapSearchField({required this.tokens});

  final FloorOpsTokens tokens;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search pipelines, stations, alerts',
          hintStyle: TextStyle(color: tokens.muted, fontSize: 13),
          prefixIcon: Icon(Icons.search_rounded, color: tokens.muted, size: 18),
          filled: true,
          fillColor: tokens.surfacePanel.withValues(alpha: 0.72),
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: tokens.borderSubtle),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: tokens.borderSubtle),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: tokens.selection),
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({
    required this.tokens,
    required this.icon,
    required this.label,
  });

  final FloorOpsTokens tokens;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {},
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.textPrimary,
        side: BorderSide(color: tokens.borderSubtle),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _TimeRangeButton extends StatelessWidget {
  const _TimeRangeButton({required this.tokens});

  final FloorOpsTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tokens.surfacePanel.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        children: [
          Text(
            'Current Shift',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            color: tokens.muted,
            size: 18,
          ),
        ],
      ),
    );
  }
}

class FloorNavRail extends StatelessWidget {
  const FloorNavRail({super.key, required this.tokens});

  final FloorOpsTokens tokens;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.public_rounded, 'Factory', false),
      (Icons.layers_rounded, 'Floors', true),
      (Icons.alt_route_rounded, 'Pipelines', false),
      (Icons.warning_amber_rounded, 'Alerts', false),
      (Icons.show_chart_rounded, 'Reports', false),
      (Icons.tune_rounded, 'Settings', false),
    ];

    return Container(
      width: 56,
      color: tokens.backgroundBase,
      child: Column(
        children: [
          const SizedBox(height: 12),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Tooltip(
                message: item.$2,
                child: Semantics(
                  label: '${item.$2} navigation',
                  selected: item.$3,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: item.$3
                          ? tokens.selection.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: item.$3
                          ? Border.all(
                              color: tokens.selection.withValues(alpha: 0.20),
                            )
                          : null,
                    ),
                    child: Icon(
                      item.$1,
                      size: 19,
                      color: item.$3 ? tokens.selection : tokens.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class FloorOperationsPane extends StatelessWidget {
  const FloorOperationsPane({
    super.key,
    required this.tokens,
    required this.floor,
    required this.pipelines,
    required this.selectedPipelineId,
    required this.onPipelineSelected,
  });

  final FloorOpsTokens tokens;
  final FloorSummary floor;
  final List<PipelineSummary> pipelines;
  final String selectedPipelineId;
  final ValueChanged<String> onPipelineSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 14, 0, 14),
      padding: const EdgeInsets.fromLTRB(14, 16, 10, 16),
      decoration: BoxDecoration(
        color: tokens.surfacePanel.withValues(alpha: 0.62),
        border: Border(
          right: BorderSide(color: tokens.borderSubtle),
          top: BorderSide(color: tokens.borderSubtle.withValues(alpha: 0.5)),
          bottom: BorderSide(color: tokens.borderSubtle.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      floor.name,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${floor.areaName} · Current Shift',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Filter pipelines',
                onPressed: () {},
                icon: Icon(
                  Icons.filter_list_rounded,
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _SmallSelector(tokens: tokens, label: 'Critical'),
              const Spacer(),
              Text(
                '${pipelines.length} routes',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.separated(
              itemCount: pipelines.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final pipeline = pipelines[index];
                return PipelineCard(
                  tokens: tokens,
                  pipeline: pipeline,
                  selected: pipeline.id == selectedPipelineId,
                  onTap: () => onPipelineSelected(pipeline.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallSelector extends StatelessWidget {
  const _SmallSelector({required this.tokens, required this.label});

  final FloorOpsTokens tokens;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tokens.surfaceFloating,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.expand_more_rounded,
            size: 16,
            color: tokens.textSecondary,
          ),
        ],
      ),
    );
  }
}

class PipelineCard extends StatelessWidget {
  const PipelineCard({
    super.key,
    required this.tokens,
    required this.pipeline,
    required this.selected,
    required this.onTap,
  });

  final FloorOpsTokens tokens;
  final PipelineSummary pipeline;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = tokens.pipelineStatus(pipeline.status);

    return Semantics(
      label:
          '${pipeline.name}, ${pipeline.status.label}, OEE ${pipeline.oee.toStringAsFixed(1)} percent',
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: selected
                  ? tokens.selection.withValues(alpha: 0.08)
                  : tokens.surfaceFloating.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? tokens.selection : tokens.borderSubtle,
                width: selected ? 1.3 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        pipeline.name,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    StatusChip(
                      tokens: tokens,
                      label: pipeline.status.label,
                      color: statusColor,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      '${pipeline.oee.toStringAsFixed(1)}% OEE',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Queue ${pipeline.queueMinutes}m',
                      style: TextStyle(
                        color: pipeline.queueMinutes >= 18
                            ? tokens.warning
                            : tokens.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                MiniMetricBar(
                  tokens: tokens,
                  value: pipeline.progress,
                  color: statusColor,
                  height: 6,
                ),
                const SizedBox(height: 8),
                Text(
                  '${_formatInt(pipeline.outputActual)} / ${_formatInt(pipeline.outputTarget)} units',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _TinyFact(
                      tokens: tokens,
                      text: '${pipeline.stationCount} stn',
                    ),
                    _TinyFact(
                      tokens: tokens,
                      text: '${pipeline.activeOperators} ops',
                    ),
                    _TinyFact(
                      tokens: tokens,
                      text: '${pipeline.alertCount} alerts',
                      color: pipeline.alertCount > 0 ? tokens.warning : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FloorMapCanvas extends StatelessWidget {
  const FloorMapCanvas({
    super.key,
    required this.tokens,
    required this.zones,
    required this.routes,
    required this.stations,
    required this.alerts,
    required this.selectedPipelineId,
    this.onOpenPipeline,
  });

  final FloorOpsTokens tokens;
  final List<ProductionZone> zones;
  final List<PipelineRoute> routes;
  final List<StationNode> stations;
  final List<FloorAlert> alerts;
  final String selectedPipelineId;
  final VoidCallback? onOpenPipeline;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaceCanvas,
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: FloorMapPainter(
                      tokens: tokens,
                      zones: zones,
                      routes: routes,
                      selectedPipelineId: selectedPipelineId,
                    ),
                  ),
                ),
                for (final station in stations)
                  _StationMarker(
                    tokens: tokens,
                    station: station,
                    size: size,
                    selected: station.pipelineId == selectedPipelineId,
                  ),
                for (final alert in alerts)
                  _AlertPin(
                    tokens: tokens,
                    alert: alert,
                    size: size,
                    emphasized: alert.relatedPipelineId == selectedPipelineId,
                  ),
                Positioned(
                  left: 20,
                  top: 18,
                  child: _MapFloatingLabel(
                    tokens: tokens,
                    selectedPipelineId: selectedPipelineId,
                  ),
                ),
                Positioned(
                  right: 20,
                  top: 18,
                  child: MapZoomControls(tokens: tokens),
                ),
                Positioned(
                  left: 20,
                  bottom: 18,
                  child: MapLegend(tokens: tokens),
                ),
                Positioned(
                  right: 20,
                  bottom: 18,
                  child: _OpenPipelineControl(
                    tokens: tokens,
                    onPressed: onOpenPipeline,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class FloorMapPainter extends CustomPainter {
  const FloorMapPainter({
    required this.tokens,
    required this.zones,
    required this.routes,
    required this.selectedPipelineId,
  });

  final FloorOpsTokens tokens;
  final List<ProductionZone> zones;
  final List<PipelineRoute> routes;
  final String selectedPipelineId;

  @override
  void paint(Canvas canvas, Size size) {
    _drawGround(canvas, size);
    _drawDraftingGrid(canvas, size);
    _drawFloorShell(canvas, size);
    _drawAisles(canvas, size);
    _drawZones(canvas, size);
    _drawRoutes(canvas, size, selected: false);
    _drawRoutes(canvas, size, selected: true);
  }

  void _drawGround(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = tokens.mapGround);
  }

  void _drawDraftingGrid(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = tokens.mapDraftLine.withValues(alpha: 0.38)
      ..strokeWidth = 0.7;
    final major = Paint()
      ..color = tokens.mapDraftLine.withValues(alpha: 0.72)
      ..strokeWidth = 1.0;

    const minorStep = 28.0;
    for (var x = 0.0; x <= size.width; x += minorStep) {
      final paint = (x / minorStep).round().isMultipleOf(4) ? major : minor;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += minorStep) {
      final paint = (y / minorStep).round().isMultipleOf(4) ? major : minor;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawFloorShell(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      size.width * 0.045,
      size.height * 0.085,
      size.width * 0.91,
      size.height * 0.82,
    );
    final shell = RRect.fromRectAndRadius(rect, const Radius.circular(30));
    canvas.drawRRect(
      shell,
      Paint()..color = Colors.white.withValues(alpha: 0.32),
    );
    canvas.drawRRect(
      shell,
      Paint()
        ..color = tokens.mapBlockBorder.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    final dockPaint = Paint()
      ..color = tokens.mapBlockMuted.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;
    for (var i = 0; i < 7; i += 1) {
      final dock = Rect.fromLTWH(
        rect.left + 36 + (i * 42),
        rect.bottom - 12,
        24,
        8,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(dock, const Radius.circular(2)),
        dockPaint,
      );
    }
  }

  void _drawAisles(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 34
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final aisle = Path()
      ..moveTo(size.width * 0.16, size.height * 0.30)
      ..lineTo(size.width * 0.48, size.height * 0.30)
      ..quadraticBezierTo(
        size.width * 0.58,
        size.height * 0.30,
        size.width * 0.60,
        size.height * 0.42,
      )
      ..lineTo(size.width * 0.62, size.height * 0.66)
      ..quadraticBezierTo(
        size.width * 0.63,
        size.height * 0.78,
        size.width * 0.76,
        size.height * 0.78,
      );
    canvas.drawPath(aisle, paint);

    final centerAisle = Path()
      ..moveTo(size.width * 0.20, size.height * 0.58)
      ..lineTo(size.width * 0.83, size.height * 0.58);
    canvas.drawPath(centerAisle, paint..strokeWidth = 28);
  }

  void _drawZones(Canvas canvas, Size size) {
    for (final zone in zones) {
      final rect = _scaleRect(zone.rect, size);
      final selected = _routeUsesZone(zone.id);
      final baseColor = selected ? tokens.mapBlockSelected : _zoneFill(zone);
      final shadowRect = rect.translate(0, 4);

      canvas.drawRRect(
        RRect.fromRectAndRadius(shadowRect, const Radius.circular(13)),
        Paint()..color = Colors.black.withValues(alpha: 0.035),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(13)),
        Paint()..color = baseColor,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(13)),
        Paint()
          ..color = selected
              ? tokens.selection.withValues(alpha: 0.44)
              : tokens.mapBlockBorder
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 1.5 : 1,
      );

      _drawZoneLabel(canvas, rect, zone, selected);
      _drawZoneHatch(canvas, rect, zone);
    }
  }

  void _drawZoneLabel(
    Canvas canvas,
    Rect rect,
    ProductionZone zone,
    bool selected,
  ) {
    final title = TextPainter(
      text: TextSpan(
        text: zone.name,
        style: TextStyle(
          color: tokens.textPrimary.withValues(alpha: selected ? 1 : 0.86),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
      maxLines: 2,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width - 20);
    title.paint(canvas, rect.topLeft + const Offset(10, 9));

    final type = TextPainter(
      text: TextSpan(
        text: zone.type.toUpperCase(),
        style: TextStyle(
          color: tokens.textSecondary.withValues(alpha: 0.78),
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width - 20);
    type.paint(canvas, Offset(rect.left + 10, rect.bottom - 22));
  }

  void _drawZoneHatch(Canvas canvas, Rect rect, ProductionZone zone) {
    if (zone.status == ZoneStatus.normal) return;
    final color = switch (zone.status) {
      ZoneStatus.active => tokens.success,
      ZoneStatus.constrained => tokens.warning,
      ZoneStatus.blocked => tokens.danger,
      ZoneStatus.normal => tokens.muted,
    };
    final paint = Paint()
      ..color = color.withValues(alpha: 0.24)
      ..strokeWidth = 1;
    for (var x = rect.left + 10; x < rect.right; x += 12) {
      canvas.drawLine(
        Offset(x, rect.bottom - 10),
        Offset(math.min(x + 10, rect.right - 8), rect.bottom - 20),
        paint,
      );
    }
  }

  Color _zoneFill(ProductionZone zone) {
    return switch (zone.status) {
      ZoneStatus.normal => tokens.mapBlock,
      ZoneStatus.active => tokens.mapBlock,
      ZoneStatus.constrained => const Color(0xFFFBF5EA),
      ZoneStatus.blocked => const Color(0xFFF9ECEA),
    };
  }

  bool _routeUsesZone(String zoneId) {
    final selectedRoute = routes.where(
      (route) => route.pipelineId == selectedPipelineId,
    );
    final zone = zones.where((candidate) => candidate.id == zoneId).firstOrNull;
    if (zone == null) return false;
    final touchRect = zone.rect.inflate(0.045);
    return selectedRoute.any((route) => route.points.any(touchRect.contains));
  }

  void _drawRoutes(Canvas canvas, Size size, {required bool selected}) {
    final targetRoutes = routes.where(
      (route) => selected
          ? route.pipelineId == selectedPipelineId
          : route.pipelineId != selectedPipelineId,
    );
    for (final route in targetRoutes) {
      _drawRoute(canvas, size, route, selected: selected);
    }
  }

  void _drawRoute(
    Canvas canvas,
    Size size,
    PipelineRoute route, {
    required bool selected,
  }) {
    if (route.points.length < 2) return;
    final points = route.points
        .map((point) => Offset(point.dx * size.width, point.dy * size.height))
        .toList(growable: false);
    final path = _smoothPath(points);

    if (selected) {
      canvas.drawPath(
        path,
        Paint()
          ..color = tokens.mapRouteSelected.withValues(alpha: 0.14)
          ..strokeWidth = 18
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = selected
            ? tokens.mapRouteSelected
            : tokens.mapRoute.withValues(alpha: 0.62)
        ..strokeWidth = selected ? 5.8 : 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    if (selected) {
      _drawFlowDashes(canvas, path);
    }
  }

  void _drawFlowDashes(Canvas canvas, Path path) {
    final metric = path.computeMetrics().isEmpty
        ? null
        : path.computeMetrics().first;
    if (metric == null) return;
    final dashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var distance = 20.0; distance < metric.length; distance += 42) {
      final segment = metric.extractPath(
        distance,
        math.min(distance + 11, metric.length),
      );
      canvas.drawPath(segment, dashPaint);
    }
  }

  Path _smoothPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i += 1) {
      final previous = points[i - 1];
      final current = points[i];
      final mid = Offset(
        (previous.dx + current.dx) / 2,
        (previous.dy + current.dy) / 2,
      );
      path.quadraticBezierTo(previous.dx, previous.dy, mid.dx, mid.dy);
      if (i == points.length - 1) {
        path.quadraticBezierTo(mid.dx, mid.dy, current.dx, current.dy);
      }
    }
    return path;
  }

  Rect _scaleRect(Rect rect, Size size) {
    return Rect.fromLTWH(
      rect.left * size.width,
      rect.top * size.height,
      rect.width * size.width,
      rect.height * size.height,
    );
  }

  @override
  bool shouldRepaint(covariant FloorMapPainter oldDelegate) {
    return oldDelegate.selectedPipelineId != selectedPipelineId ||
        oldDelegate.tokens != tokens ||
        oldDelegate.zones != zones ||
        oldDelegate.routes != routes;
  }
}

class _StationMarker extends StatelessWidget {
  const _StationMarker({
    required this.tokens,
    required this.station,
    required this.size,
    required this.selected,
  });

  final FloorOpsTokens tokens;
  final StationNode station;
  final Size size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = tokens.pipelineStatus(station.status);
    final center = Offset(
      station.position.dx * size.width,
      station.position.dy * size.height,
    );
    final markerSize = selected ? 22.0 : 14.0;
    return Positioned(
      left: center.dx - markerSize / 2,
      top: center.dy - markerSize / 2,
      child: Semantics(
        label:
            '${station.label}, ${station.status.label}${station.isBottleneck ? ', bottleneck' : ''}',
        child: Tooltip(
          message: '${station.label} · ${station.status.label}',
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (station.isBottleneck ||
                  station.status == PipelineStatus.blocked)
                Container(
                  width: markerSize + 22,
                  height: markerSize + 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        (station.status == PipelineStatus.blocked
                                ? tokens.danger
                                : tokens.warning)
                            .withValues(alpha: 0.14),
                  ),
                ),
              Container(
                width: markerSize,
                height: markerSize,
                decoration: BoxDecoration(
                  color: tokens.surfaceFloating,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: selected ? 4 : 3),
                ),
              ),
              if (station.status == PipelineStatus.blocked)
                Icon(Icons.close_rounded, size: 10, color: tokens.danger)
              else if (station.isBottleneck)
                Icon(
                  Icons.priority_high_rounded,
                  size: 11,
                  color: tokens.warning,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertPin extends StatelessWidget {
  const _AlertPin({
    required this.tokens,
    required this.alert,
    required this.size,
    required this.emphasized,
  });

  final FloorOpsTokens tokens;
  final FloorAlert alert;
  final Size size;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final color = tokens.alertSeverity(alert.severity);
    final position = Offset(
      alert.position.dx * size.width,
      alert.position.dy * size.height,
    );
    return Positioned(
      left: position.dx - 10,
      top: position.dy - 22,
      child: Semantics(
        label: '${alert.title}: ${alert.message}',
        child: Tooltip(
          message: alert.title,
          child: AnimatedScale(
            scale: emphasized ? 1.12 : 1,
            duration: const Duration(milliseconds: 180),
            child: Icon(
              Icons.location_on_rounded,
              size: emphasized ? 28 : 22,
              color: color.withValues(alpha: emphasized ? 0.95 : 0.72),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapFloatingLabel extends StatelessWidget {
  const _MapFloatingLabel({
    required this.tokens,
    required this.selectedPipelineId,
  });

  final FloorOpsTokens tokens;
  final String selectedPipelineId;

  @override
  Widget build(BuildContext context) {
    return _FloatingMapPanel(
      tokens: tokens,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: tokens.selection,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'LIVE ROUTE · ${selectedPipelineId.toUpperCase()}',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingMapPanel extends StatelessWidget {
  const _FloatingMapPanel({required this.tokens, required this.child});

  final FloorOpsTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceFloating.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: child,
      ),
    );
  }
}

class MapLegend extends StatelessWidget {
  const MapLegend({super.key, required this.tokens});

  final FloorOpsTokens tokens;

  @override
  Widget build(BuildContext context) {
    return _FloatingMapPanel(
      tokens: tokens,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendItem(tokens: tokens, color: tokens.success, label: 'Running'),
          _LegendItem(tokens: tokens, color: tokens.warning, label: 'Waiting'),
          _LegendItem(tokens: tokens, color: tokens.danger, label: 'Blocked'),
          _LegendItem(
            tokens: tokens,
            color: tokens.warning,
            label: 'Bottleneck',
            icon: Icons.priority_high_rounded,
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.tokens,
    required this.color,
    required this.label,
    this.icon,
  });

  final FloorOpsTokens tokens;
  final Color color;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tokens.surfaceFloating,
              border: Border.all(color: color, width: 3),
            ),
            child: icon == null ? null : Icon(icon, size: 7, color: color),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class MapZoomControls extends StatelessWidget {
  const MapZoomControls({super.key, required this.tokens});

  final FloorOpsTokens tokens;

  @override
  Widget build(BuildContext context) {
    return _FloatingMapPanel(
      tokens: tokens,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MapToolIcon(
            tokens: tokens,
            icon: Icons.remove_rounded,
            label: 'Zoom out',
          ),
          _MapToolIcon(
            tokens: tokens,
            icon: Icons.add_rounded,
            label: 'Zoom in',
          ),
          _MapToolIcon(
            tokens: tokens,
            icon: Icons.fit_screen_rounded,
            label: 'Fit floor',
          ),
        ],
      ),
    );
  }
}

class _MapToolIcon extends StatelessWidget {
  const _MapToolIcon({
    required this.tokens,
    required this.icon,
    required this.label,
  });

  final FloorOpsTokens tokens;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: SizedBox.square(
        dimension: 28,
        child: IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: () {},
          icon: Icon(icon, size: 17, color: tokens.textPrimary),
        ),
      ),
    );
  }
}

class _OpenPipelineControl extends StatelessWidget {
  const _OpenPipelineControl({required this.tokens, this.onPressed});

  final FloorOpsTokens tokens;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return _FloatingMapPanel(
      tokens: tokens,
      child: InkWell(
        onTap: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Open Pipeline',
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.north_east_rounded, size: 14, color: tokens.selection),
          ],
        ),
      ),
    );
  }
}

class FloorTelemetryPane extends StatelessWidget {
  const FloorTelemetryPane({
    super.key,
    required this.tokens,
    required this.floor,
    required this.selectedPipeline,
    required this.alerts,
    this.onOpenAlert,
  });

  final FloorOpsTokens tokens;
  final FloorSummary floor;
  final PipelineSummary selectedPipeline;
  final List<FloorAlert> alerts;
  final ValueChanged<FloorAlert>? onOpenAlert;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 14, 14, 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfacePanel.withValues(alpha: 0.72),
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(24),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Floor Performance',
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${floor.name} · ${floor.areaName}',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            KpiCard(
              tokens: tokens,
              title: 'OEE',
              value: '${floor.oee.toStringAsFixed(1)}%',
              secondary:
                  '${floor.oeeTrend.delta.toStringAsFixed(1)}% ${floor.oeeTrend.label}',
              semanticLabel:
                  'Floor OEE ${floor.oee.toStringAsFixed(1)} percent',
              child: Column(
                children: [
                  _KpiBreakdown(
                    tokens: tokens,
                    label: 'Availability',
                    value: 0.86,
                  ),
                  _KpiBreakdown(
                    tokens: tokens,
                    label: 'Performance',
                    value: 0.79,
                  ),
                  _KpiBreakdown(tokens: tokens, label: 'Quality', value: 0.91),
                ],
              ),
            ),
            KpiCard(
              tokens: tokens,
              title: 'Total Yield Today',
              value: '${_formatInt(floor.totalYield)} units',
              secondary: 'Target ${_formatInt(floor.yieldTarget)}',
              semanticLabel: 'Total yield today ${floor.totalYield} units',
              child: MiniMetricBar(
                tokens: tokens,
                value: floor.totalYield / floor.yieldTarget,
                color: tokens.success,
                height: 7,
              ),
            ),
            KpiCard(
              tokens: tokens,
              title: 'Floor Utilization',
              value: '${(floor.utilization * 100).round()}%',
              secondary:
                  '${floor.activeMachines} / ${floor.totalMachines} machines active',
              semanticLabel:
                  'Floor utilization ${(floor.utilization * 100).round()} percent',
              child: MiniMetricBar(
                tokens: tokens,
                value: floor.utilization,
                color: tokens.selection,
                height: 7,
              ),
            ),
            KpiCard(
              tokens: tokens,
              title: 'Top Bottleneck Pipeline',
              value: selectedPipeline.name,
              secondary: selectedPipeline.bottleneckReason,
              semanticLabel: 'Top bottleneck pipeline ${selectedPipeline.name}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusChip(
                    tokens: tokens,
                    label: 'WARNING',
                    color: tokens.warning,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    selectedPipeline.bottleneckImpact,
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            KpiCard(
              tokens: tokens,
              title: 'Operator Headcount',
              value: '${floor.operatorHeadcount} active',
              secondary: '6 welding · 8 cutting · 5 QA · 15 handling',
              semanticLabel:
                  '${floor.operatorHeadcount} active floor operators',
              child: const SizedBox.shrink(),
            ),
            const SizedBox(height: 8),
            Text(
              'Alerts Summary',
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            for (final alert in alerts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AlertSummaryItem(
                  tokens: tokens,
                  alert: alert,
                  onTap: () => onOpenAlert?.call(alert),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.tokens,
    required this.title,
    required this.value,
    required this.secondary,
    required this.semanticLabel,
    required this.child,
  });

  final FloorOpsTokens tokens;
  final String title;
  final String value;
  final String secondary;
  final String semanticLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 11),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tokens.surfaceFloating.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 23,
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              secondary,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (child is! SizedBox) ...[const SizedBox(height: 12), child],
          ],
        ),
      ),
    );
  }
}

class _KpiBreakdown extends StatelessWidget {
  const _KpiBreakdown({
    required this.tokens,
    required this.label,
    required this.value,
  });

  final FloorOpsTokens tokens;
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final color = value < 0.82 ? tokens.warning : tokens.success;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: MiniMetricBar(
              tokens: tokens,
              value: value,
              color: color,
              height: 5,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(value * 100).round()}%',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class MiniMetricBar extends StatelessWidget {
  const MiniMetricBar({
    super.key,
    required this.tokens,
    required this.value,
    required this.color,
    this.height = 6,
  });

  final FloorOpsTokens tokens;
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: tokens.borderSubtle.withValues(alpha: 0.55),
              ),
            ),
            FractionallySizedBox(
              widthFactor: value.clamp(0, 1).toDouble(),
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.tokens,
    required this.label,
    required this.color,
  });

  final FloorOpsTokens tokens;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.35,
        ),
      ),
    );
  }
}

class AlertSummaryItem extends StatelessWidget {
  const AlertSummaryItem({
    super.key,
    required this.tokens,
    required this.alert,
    this.onTap,
  });

  final FloorOpsTokens tokens;
  final FloorAlert alert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = tokens.alertSeverity(alert.severity);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_alertIcon(alert.severity), color: color, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.title,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alert.message,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
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
  }

  IconData _alertIcon(AlertSeverity severity) {
    return switch (severity) {
      AlertSeverity.info => Icons.info_outline_rounded,
      AlertSeverity.warning => Icons.warning_amber_rounded,
      AlertSeverity.danger => Icons.block_rounded,
    };
  }
}

class _TinyFact extends StatelessWidget {
  const _TinyFact({required this.tokens, required this.text, this.color});

  final FloorOpsTokens tokens;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? tokens.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: tone,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

extension on PipelineStatus {
  String get label {
    return switch (this) {
      PipelineStatus.running => 'RUNNING',
      PipelineStatus.waiting => 'WAITING',
      PipelineStatus.blocked => 'BLOCKED',
      PipelineStatus.idle => 'IDLE',
    };
  }
}

extension on int {
  bool isMultipleOf(int value) => this % value == 0;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

String _formatInt(num value) {
  final text = value.round().toString();
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

class _FloorMockData {
  final floor = const FloorSummary(
    id: 'floor-2',
    name: 'Floor 2',
    areaName: 'Fabrication',
    oee: 82.4,
    oeeTrend: KpiTrend(label: 'vs last shift', delta: -3.1),
    totalYield: 18420,
    yieldTarget: 22000,
    activeMachines: 19,
    totalMachines: 25,
    operatorHeadcount: 34,
    topBottleneckPipelineId: 'press-brake',
  );

  final pipelines = const [
    PipelineSummary(
      id: 'laser-line-a',
      name: 'Laser Cutting Line A',
      status: PipelineStatus.running,
      oee: 86.8,
      outputActual: 4820,
      outputTarget: 6000,
      queueMinutes: 12,
      stationCount: 6,
      activeOperators: 8,
      alertCount: 1,
      bottleneckReason: 'Deburr buffer is close to queue limit',
      bottleneckImpact: 'Estimated -180 units by shift end',
    ),
    PipelineSummary(
      id: 'press-brake',
      name: 'Press Brake Cell B',
      status: PipelineStatus.blocked,
      oee: 68.5,
      outputActual: 3150,
      outputTarget: 5500,
      queueMinutes: 24,
      stationCount: 5,
      activeOperators: 7,
      alertCount: 3,
      bottleneckReason: 'Press Brake queue exceeds 18m',
      bottleneckImpact: 'Estimated -640 units by shift end',
    ),
    PipelineSummary(
      id: 'welding-main',
      name: 'Welding Cells 1-4',
      status: PipelineStatus.waiting,
      oee: 77.2,
      outputActual: 2680,
      outputTarget: 4200,
      queueMinutes: 18,
      stationCount: 4,
      activeOperators: 6,
      alertCount: 2,
      bottleneckReason: 'Fixtures waiting after brake release',
      bottleneckImpact: 'Estimated -310 units by shift end',
    ),
    PipelineSummary(
      id: 'qa-pack',
      name: 'QA + Packing Flow',
      status: PipelineStatus.running,
      oee: 91.4,
      outputActual: 5240,
      outputTarget: 5600,
      queueMinutes: 6,
      stationCount: 4,
      activeOperators: 5,
      alertCount: 0,
      bottleneckReason: 'No active bottleneck',
      bottleneckImpact: 'Tracking within shift plan',
    ),
    PipelineSummary(
      id: 'punch-press',
      name: 'Punch Press Loop',
      status: PipelineStatus.idle,
      oee: 0,
      outputActual: 0,
      outputTarget: 2200,
      queueMinutes: 0,
      stationCount: 3,
      activeOperators: 0,
      alertCount: 0,
      bottleneckReason: 'Idle by schedule',
      bottleneckImpact: 'No shift impact',
    ),
  ];

  final zones = const [
    ProductionZone(
      id: 'raw-sheet',
      name: 'Raw Material Storage',
      rect: Rect.fromLTWH(0.08, 0.16, 0.19, 0.16),
      type: 'Inbound',
      status: ZoneStatus.normal,
    ),
    ProductionZone(
      id: 'laser',
      name: 'Laser Cutting',
      rect: Rect.fromLTWH(0.36, 0.13, 0.21, 0.18),
      type: 'Cutting',
      status: ZoneStatus.active,
    ),
    ProductionZone(
      id: 'punch',
      name: 'Punch Press',
      rect: Rect.fromLTWH(0.08, 0.45, 0.20, 0.17),
      type: 'Press',
      status: ZoneStatus.normal,
    ),
    ProductionZone(
      id: 'brake',
      name: 'Press Brake',
      rect: Rect.fromLTWH(0.37, 0.45, 0.21, 0.18),
      type: 'Forming',
      status: ZoneStatus.blocked,
    ),
    ProductionZone(
      id: 'welding',
      name: 'Welding Cells',
      rect: Rect.fromLTWH(0.66, 0.19, 0.23, 0.22),
      type: 'Assembly',
      status: ZoneStatus.constrained,
    ),
    ProductionZone(
      id: 'deburr',
      name: 'Deburr / Grind',
      rect: Rect.fromLTWH(0.66, 0.52, 0.20, 0.15),
      type: 'Surface prep',
      status: ZoneStatus.constrained,
    ),
    ProductionZone(
      id: 'qa',
      name: 'QA',
      rect: Rect.fromLTWH(0.43, 0.76, 0.17, 0.13),
      type: 'Inspection',
      status: ZoneStatus.active,
    ),
    ProductionZone(
      id: 'packing',
      name: 'Packing',
      rect: Rect.fromLTWH(0.74, 0.75, 0.19, 0.14),
      type: 'Outbound',
      status: ZoneStatus.active,
    ),
  ];

  final routes = const [
    PipelineRoute(
      id: 'route-laser',
      pipelineId: 'laser-line-a',
      points: [
        Offset(0.17, 0.24),
        Offset(0.47, 0.23),
        Offset(0.76, 0.59),
        Offset(0.52, 0.82),
        Offset(0.83, 0.82),
      ],
      status: PipelineStatus.running,
    ),
    PipelineRoute(
      id: 'route-brake',
      pipelineId: 'press-brake',
      points: [
        Offset(0.17, 0.24),
        Offset(0.47, 0.23),
        Offset(0.48, 0.54),
        Offset(0.76, 0.59),
        Offset(0.52, 0.82),
      ],
      status: PipelineStatus.blocked,
    ),
    PipelineRoute(
      id: 'route-welding',
      pipelineId: 'welding-main',
      points: [
        Offset(0.48, 0.54),
        Offset(0.77, 0.31),
        Offset(0.76, 0.59),
        Offset(0.52, 0.82),
      ],
      status: PipelineStatus.waiting,
    ),
    PipelineRoute(
      id: 'route-qa',
      pipelineId: 'qa-pack',
      points: [Offset(0.76, 0.59), Offset(0.52, 0.82), Offset(0.83, 0.82)],
      status: PipelineStatus.running,
    ),
    PipelineRoute(
      id: 'route-punch',
      pipelineId: 'punch-press',
      points: [Offset(0.17, 0.24), Offset(0.18, 0.54), Offset(0.48, 0.54)],
      status: PipelineStatus.idle,
    ),
  ];

  final stations = const [
    StationNode(
      id: 'st-raw',
      label: 'Sheet pick',
      zoneId: 'raw-sheet',
      position: Offset(0.17, 0.24),
      status: PipelineStatus.running,
      pipelineId: 'laser-line-a',
    ),
    StationNode(
      id: 'st-laser',
      label: 'Cutting output',
      zoneId: 'laser',
      position: Offset(0.47, 0.23),
      status: PipelineStatus.running,
      pipelineId: 'laser-line-a',
    ),
    StationNode(
      id: 'st-deburr',
      label: 'Deburr buffer',
      zoneId: 'deburr',
      position: Offset(0.76, 0.59),
      status: PipelineStatus.waiting,
      pipelineId: 'laser-line-a',
      isBottleneck: true,
    ),
    StationNode(
      id: 'st-brake',
      label: 'Brake queue',
      zoneId: 'brake',
      position: Offset(0.48, 0.54),
      status: PipelineStatus.blocked,
      pipelineId: 'press-brake',
      isBottleneck: true,
    ),
    StationNode(
      id: 'st-weld',
      label: 'Welding intake',
      zoneId: 'welding',
      position: Offset(0.77, 0.31),
      status: PipelineStatus.waiting,
      pipelineId: 'welding-main',
      isBottleneck: true,
    ),
    StationNode(
      id: 'st-qa',
      label: 'QA gate',
      zoneId: 'qa',
      position: Offset(0.52, 0.82),
      status: PipelineStatus.running,
      pipelineId: 'qa-pack',
    ),
    StationNode(
      id: 'st-pack',
      label: 'Packing release',
      zoneId: 'packing',
      position: Offset(0.83, 0.82),
      status: PipelineStatus.running,
      pipelineId: 'qa-pack',
    ),
    StationNode(
      id: 'st-punch',
      label: 'Punch loop',
      zoneId: 'punch',
      position: Offset(0.18, 0.54),
      status: PipelineStatus.idle,
      pipelineId: 'punch-press',
    ),
  ];

  final alerts = const [
    FloorAlert(
      severity: AlertSeverity.warning,
      title: 'Press Brake queue',
      message: 'Queue exceeds 18m and is holding downstream welding.',
      position: Offset(0.48, 0.47),
      relatedPipelineId: 'press-brake',
    ),
    FloorAlert(
      severity: AlertSeverity.danger,
      title: 'Blocked transfer route',
      message: 'Brake-to-deburr transfer blocked by WIP stack.',
      position: Offset(0.61, 0.56),
      relatedPipelineId: 'press-brake',
    ),
    FloorAlert(
      severity: AlertSeverity.warning,
      title: 'Quality hold',
      message: 'QA sampling frequency increased for formed brackets.',
      position: Offset(0.52, 0.75),
      relatedPipelineId: 'qa-pack',
    ),
    FloorAlert(
      severity: AlertSeverity.info,
      title: 'Tooling warnings',
      message: 'Two floor-level tooling warnings active this shift.',
      position: Offset(0.39, 0.16),
    ),
  ];

  PipelineSummary pipelineById(String id) {
    return pipelines.firstWhere(
      (pipeline) => pipeline.id == id,
      orElse: () => pipelines.first,
    );
  }
}
