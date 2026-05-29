import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/pipeline_template.dart';
import '../../production_pipelines/domain/process_node.dart';
import '../domain/models/floor_view_models.dart';
import '../widgets/floor_map_painter.dart';
import '../widgets/floor_widgets.dart';
import '../data/mock_floor_data.dart';

class FloorViewScreen extends StatefulWidget {
  const FloorViewScreen({
    super.key,
    this.tokens = FloorOpsTokens.factoryMap,
    this.shopFloorId,
    this.pipelineTemplates,
    this.reloadToken,
    this.onPipelineSelected,
    this.onOpenPipeline,
    this.onOpenAlert,
    this.onOpenFloorSettings,
  });

  final FloorOpsTokens tokens;
  final String? shopFloorId;
  final List<PipelineTemplate>? pipelineTemplates;
  final Object? reloadToken;
  final ValueChanged<String>? onPipelineSelected;
  final ValueChanged<String>? onOpenPipeline;
  final ValueChanged<FloorAlert>? onOpenAlert;
  final VoidCallback? onOpenFloorSettings;

  @override
  State<FloorViewScreen> createState() => _FloorViewScreenState();
}

class _FloorViewScreenState extends State<FloorViewScreen> {
  final _data = FloorMockData();
  late String _selectedPipelineId;
  List<PipelineTemplate> _loadedTemplates = const [];
  bool _isLoadingTemplates = false;
  String? _templateLoadError;

  @override
  void initState() {
    super.initState();
    _selectedPipelineId = _data.floor.topBottleneckPipelineId;
    _loadTemplatesForShopFloor();
  }

  @override
  void didUpdateWidget(covariant FloorViewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shopFloorId != widget.shopFloorId ||
        oldWidget.pipelineTemplates != widget.pipelineTemplates ||
        oldWidget.reloadToken != widget.reloadToken) {
      _loadTemplatesForShopFloor();
    }
  }

  Future<void> _loadTemplatesForShopFloor() async {
    if (widget.pipelineTemplates != null) {
      setState(() {
        _templateLoadError = null;
        _isLoadingTemplates = false;
      });
      return;
    }

    if (widget.shopFloorId == null) {
      setState(() {
        _loadedTemplates = const [];
        _templateLoadError = null;
        _isLoadingTemplates = false;
      });
      return;
    }

    setState(() {
      _loadedTemplates = const [];
      _isLoadingTemplates = true;
      _templateLoadError = null;
    });

    try {
      final repo = context.read<PipelineRunRepository>();
      final templates = await repo.getTemplates();
      final floorTemplates = templates
          .where((template) => template.shopFloorId == widget.shopFloorId)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _loadedTemplates = floorTemplates;
        if (floorTemplates.isNotEmpty &&
            !floorTemplates.any(
              (template) => template.id == _selectedPipelineId,
            )) {
          _selectedPipelineId = floorTemplates.first.id;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _templateLoadError =
            'Pipeline routes could not be loaded. Showing floor demo routes.';
      });
    } finally {
      if (mounted) setState(() => _isLoadingTemplates = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final templates = widget.pipelineTemplates ?? _loadedTemplates;
    final hasTemplateRoutes = templates.isNotEmpty;
    final pipelines = hasTemplateRoutes
        ? _pipelineSummariesFromTemplates(templates)
        : _data.pipelines;
    final routes = hasTemplateRoutes
        ? _routesFromTemplates(templates)
        : _data.routes;
    final stations = hasTemplateRoutes
        ? _stationsFromTemplates(templates)
        : _data.stations;
    final alerts = hasTemplateRoutes
        ? _alertsFromTemplates(templates)
        : _data.alerts;
    final floor = hasTemplateRoutes
        ? _floorSummaryFromPipelines(pipelines)
        : _data.floor;
    final selectedPipelineId =
        pipelines.any((pipeline) => pipeline.id == _selectedPipelineId)
            ? _selectedPipelineId
            : pipelines.first.id;
    final selectedPipeline = pipelines
            .where((pipeline) => pipeline.id == selectedPipelineId)
            .firstOrNull ??
        pipelines.first;

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
                                    floor: floor,
                                    pipelines: pipelines,
                                    selectedPipelineId: selectedPipelineId,
                                    onPipelineSelected: _selectPipeline,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  height: 620,
                                  child: FloorMapCanvas(
                                    tokens: tokens,
                                    zones: _data.zones,
                                    routes: routes,
                                    stations: stations,
                                    alerts: alerts,
                                    selectedPipelineId: selectedPipelineId,
                                    routeSourceLabel: _routeSourceLabel(
                                      hasTemplateRoutes,
                                    ),
                                    loadMessage: _isLoadingTemplates
                                        ? 'Loading saved pipeline routes...'
                                        : _templateLoadError,
                                    onPipelineSelected: _selectPipeline,
                                    onOpenPipeline: () => widget.onOpenPipeline
                                        ?.call(selectedPipelineId),
                                    onOpenAlert: widget.onOpenAlert,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                FloorTelemetryPane(
                                  tokens: tokens,
                                  floor: floor,
                                  selectedPipeline: selectedPipeline,
                                  alerts: alerts,
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
                  final rightWidth = constraints.maxWidth < 1280 ? 300.0 : 330.0;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FloorNavRail(tokens: tokens),
                      SizedBox(
                        width: leftWidth,
                        child: FloorOperationsPane(
                          tokens: tokens,
                          floor: floor,
                          pipelines: pipelines,
                          selectedPipelineId: selectedPipelineId,
                          onPipelineSelected: _selectPipeline,
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                          child: FloorMapCanvas(
                            tokens: tokens,
                            zones: _data.zones,
                            routes: routes,
                            stations: stations,
                            alerts: alerts,
                            selectedPipelineId: selectedPipelineId,
                            routeSourceLabel: _routeSourceLabel(
                              hasTemplateRoutes,
                            ),
                            loadMessage: _isLoadingTemplates
                                ? 'Loading saved pipeline routes...'
                                : _templateLoadError,
                            onPipelineSelected: _selectPipeline,
                            onOpenPipeline: () =>
                                widget.onOpenPipeline?.call(selectedPipelineId),
                            onOpenAlert: widget.onOpenAlert,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: rightWidth,
                        child: FloorTelemetryPane(
                          tokens: tokens,
                          floor: floor,
                          selectedPipeline: selectedPipeline,
                          alerts: alerts,
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

  String _routeSourceLabel(bool hasTemplateRoutes) {
    return hasTemplateRoutes
        ? 'Saved shop-floor pipelines'
        : 'Demo floor routes';
  }

  List<PipelineSummary> _pipelineSummariesFromTemplates(
    List<PipelineTemplate> templates,
  ) {
    return templates.map((template) {
      final status = _statusForTemplate(template);
      final nodeCount = template.nodes.length;
      final requiredFlows = math.max(1, nodeCount - 1);
      final progress = nodeCount == 0
          ? 0.0
          : (template.flows.length / requiredFlows).clamp(0, 1).toDouble();
      final target = math.max(1000, nodeCount * 1200);
      final statusFactor = switch (status) {
        PipelineStatus.running => 0.84,
        PipelineStatus.waiting => 0.58,
        PipelineStatus.blocked => 0.36,
        PipelineStatus.idle => 0.0,
      };
      final queueMinutes = switch (status) {
        PipelineStatus.running => 6,
        PipelineStatus.waiting => 14,
        PipelineStatus.blocked => 26,
        PipelineStatus.idle => 0,
      };
      final alertCount = template.nodes
              .where((node) => _nodeStatus(node) != PipelineStatus.running)
              .length +
          (nodeCount > 1 && template.flows.isEmpty ? 1 : 0);

      return PipelineSummary(
        id: template.id,
        name: template.name.trim().isEmpty ? 'Unnamed Pipeline' : template.name,
        status: status,
        oee: nodeCount == 0 ? 0 : (statusFactor * 100).clamp(0, 96).toDouble(),
        outputActual: (target * math.max(progress, 0.35) * statusFactor).round(),
        outputTarget: target,
        queueMinutes: queueMinutes,
        stationCount: nodeCount,
        activeOperators: math.max(1, (nodeCount / 2).ceil()),
        alertCount: alertCount,
        bottleneckReason: _bottleneckReason(template, status),
        bottleneckImpact: _bottleneckImpact(status),
      );
    }).toList(growable: false);
  }

  FloorSummary _floorSummaryFromPipelines(List<PipelineSummary> pipelines) {
    final topBottleneck = pipelines.where((pipeline) {
          return pipeline.status == PipelineStatus.blocked ||
              pipeline.status == PipelineStatus.waiting;
        }).firstOrNull ??
        pipelines.first;
    final totalYield = pipelines.fold<int>(
      0,
      (sum, pipeline) => sum + pipeline.outputActual,
    );
    final yieldTarget = pipelines.fold<int>(
      0,
      (sum, pipeline) => sum + pipeline.outputTarget,
    );
    final totalStations = pipelines.fold<int>(
      0,
      (sum, pipeline) => sum + pipeline.stationCount,
    );
    final activeStations = pipelines.fold<int>(
      0,
      (sum, pipeline) =>
          sum +
          (pipeline.status == PipelineStatus.idle ? 0 : pipeline.stationCount),
    );
    final oee = pipelines.isEmpty
        ? 0.0
        : pipelines.fold<double>(0, (sum, pipeline) => sum + pipeline.oee) /
            pipelines.length;

    return FloorSummary(
      id: widget.shopFloorId ?? 'selected-floor',
      name: 'Selected Floor',
      areaName: 'Mapped Pipelines',
      oee: oee,
      oeeTrend: const KpiTrend(label: 'from saved routes', delta: 0),
      totalYield: totalYield,
      yieldTarget: math.max(yieldTarget, 1),
      activeMachines: activeStations,
      totalMachines: math.max(totalStations, 1),
      operatorHeadcount: math.max(1, (activeStations / 2).ceil()),
      topBottleneckPipelineId: topBottleneck.id,
    );
  }

  List<PipelineRoute> _routesFromTemplates(List<PipelineTemplate> templates) {
    return [
      for (var index = 0; index < templates.length; index += 1)
        if (templates[index].nodes.isNotEmpty)
          PipelineRoute(
            id: 'route-${templates[index].id}',
            pipelineId: templates[index].id,
            points: _routeNodes(templates[index])
                .map(
                  (node) => _nodeMapPosition(
                    node,
                    templates[index],
                    index,
                    templates.length,
                  ),
                )
                .toList(growable: false),
            status: _statusForTemplate(templates[index]),
          ),
    ];
  }

  List<StationNode> _stationsFromTemplates(List<PipelineTemplate> templates) {
    return [
      for (var templateIndex = 0;
          templateIndex < templates.length;
          templateIndex += 1)
        for (final node in templates[templateIndex].nodes)
          StationNode(
            id: node.id,
            label: node.name.trim().isEmpty ? 'Process' : node.name,
            zoneId: _zoneIdForStage(node.stageIndex),
            position: _nodeMapPosition(
              node,
              templates[templateIndex],
              templateIndex,
              templates.length,
            ),
            status: _nodeStatus(node),
            pipelineId: templates[templateIndex].id,
            isBottleneck: _nodeStatus(node) == PipelineStatus.blocked ||
                node.status.toLowerCase().contains('bottleneck'),
          ),
    ];
  }

  List<FloorAlert> _alertsFromTemplates(List<PipelineTemplate> templates) {
    final alerts = <FloorAlert>[];
    for (var templateIndex = 0;
        templateIndex < templates.length;
        templateIndex += 1) {
      final template = templates[templateIndex];
      for (final node in template.nodes) {
        final status = _nodeStatus(node);
        if (status == PipelineStatus.running || status == PipelineStatus.idle) {
          continue;
        }
        alerts.add(
          FloorAlert(
            severity: status == PipelineStatus.blocked
                ? AlertSeverity.danger
                : AlertSeverity.warning,
            title: status == PipelineStatus.blocked
                ? 'Blocked station'
                : 'Queued station',
            message: '${node.name} in ${template.name}',
            position: _nodeMapPosition(
              node,
              template,
              templateIndex,
              templates.length,
            ),
            relatedPipelineId: template.id,
          ),
        );
      }
      if (template.nodes.length > 1 && template.flows.isEmpty) {
        final firstNode = _orderedNodes(template).first;
        alerts.add(
          FloorAlert(
            severity: AlertSeverity.warning,
            title: 'Route not connected',
            message: '${template.name} has stations but no material flow links',
            position: _nodeMapPosition(
              firstNode,
              template,
              templateIndex,
              templates.length,
            ),
            relatedPipelineId: template.id,
          ),
        );
      }
    }
    return alerts;
  }

  List<ProcessNode> _orderedNodes(PipelineTemplate template) {
    return List<ProcessNode>.of(template.nodes)
      ..sort((a, b) {
        final stageCompare = a.stageIndex.compareTo(b.stageIndex);
        if (stageCompare != 0) return stageCompare;
        return a.laneIndex.compareTo(b.laneIndex);
      });
  }

  List<ProcessNode> _routeNodes(PipelineTemplate template) {
    final ordered = _orderedNodes(template);
    if (template.flows.isEmpty) return ordered;

    final nodeById = {for (final node in template.nodes) node.id: node};
    final incoming = template.flows.map((flow) => flow.toNodeId).toSet();
    final sources = ordered
        .where((node) => !incoming.contains(node.id))
        .toList(growable: false);
    final start = sources.isNotEmpty ? sources.first : ordered.first;
    final visited = <String>{};
    final route = <ProcessNode>[];
    var current = start;

    while (visited.add(current.id)) {
      route.add(current);
      final nextFlows = template.flows
          .where((flow) => flow.fromNodeId == current.id)
          .where((flow) => nodeById.containsKey(flow.toNodeId))
          .toList()
        ..sort((a, b) {
          final aNode = nodeById[a.toNodeId]!;
          final bNode = nodeById[b.toNodeId]!;
          final stageCompare = aNode.stageIndex.compareTo(bNode.stageIndex);
          if (stageCompare != 0) return stageCompare;
          return aNode.laneIndex.compareTo(bNode.laneIndex);
        });
      final next = nextFlows
          .map((flow) => nodeById[flow.toNodeId]!)
          .where((node) => !visited.contains(node.id))
          .firstOrNull;
      if (next == null) break;
      current = next;
    }

    for (final node in ordered) {
      if (visited.add(node.id)) route.add(node);
    }
    return route;
  }

  Offset _nodeMapPosition(
    ProcessNode node,
    PipelineTemplate template,
    int templateIndex,
    int templateCount,
  ) {
    final maxStage = math.max(
      1,
      [
        ...template.nodes.map((node) => node.stageIndex),
        template.stageLabels.length - 1,
      ].reduce(math.max),
    );
    final maxLane = math.max(
      1,
      [
        ...template.nodes.map((node) => node.laneIndex),
        template.laneLabels.length - 1,
      ].reduce(math.max),
    );
    final laneY = 0.24 + (node.laneIndex / maxLane) * 0.52;
    final routeOffset = (templateIndex - ((templateCount - 1) / 2)) * 0.035;
    return Offset(
      (0.12 + (node.stageIndex / maxStage) * 0.76).clamp(0.08, 0.92).toDouble(),
      (laneY + routeOffset).clamp(0.16, 0.84).toDouble(),
    );
  }

  PipelineStatus _statusForTemplate(PipelineTemplate template) {
    if (template.nodes.isEmpty) return PipelineStatus.idle;
    final statuses = template.nodes.map(_nodeStatus).toList(growable: false);
    if (statuses.contains(PipelineStatus.blocked)) {
      return PipelineStatus.blocked;
    }
    if (template.nodes.length > 1 && template.flows.isEmpty) {
      return PipelineStatus.waiting;
    }
    if (statuses.contains(PipelineStatus.waiting)) {
      return PipelineStatus.waiting;
    }
    if (statuses.every((status) => status == PipelineStatus.idle)) {
      return PipelineStatus.idle;
    }
    return PipelineStatus.running;
  }

  PipelineStatus _nodeStatus(ProcessNode node) {
    final value = node.status.toLowerCase();
    if (value.contains('block') || value.contains('hold')) {
      return PipelineStatus.blocked;
    }
    if (value.contains('idle')) return PipelineStatus.idle;
    if (value.contains('queue') || value.contains('wait')) {
      return PipelineStatus.waiting;
    }
    return PipelineStatus.running;
  }

  String _bottleneckReason(PipelineTemplate template, PipelineStatus status) {
    final blockedNode = template.nodes
        .where((node) => _nodeStatus(node) == PipelineStatus.blocked)
        .firstOrNull;
    if (blockedNode != null) {
      return '${blockedNode.name} is blocked';
    }
    if (template.nodes.length > 1 && template.flows.isEmpty) {
      return 'Route stations are not linked yet';
    }
    return switch (status) {
      PipelineStatus.waiting => 'One or more stations are waiting',
      PipelineStatus.idle => 'Idle by route state',
      _ => 'No active bottleneck',
    };
  }

  String _bottleneckImpact(PipelineStatus status) {
    return switch (status) {
      PipelineStatus.blocked => 'Production output is at risk until cleared',
      PipelineStatus.waiting => 'Throughput may drop if queue remains',
      PipelineStatus.idle => 'No active shift impact',
      PipelineStatus.running => 'Tracking within mapped route plan',
    };
  }

  String _zoneIdForStage(int stageIndex) {
    const zones = [
      'raw-sheet',
      'laser',
      'punch',
      'brake',
      'welding',
      'deburr',
      'qa',
      'packing',
    ];
    final index = stageIndex.clamp(0, zones.length - 1).toInt();
    return zones[index];
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

class FloorMapCanvas extends StatefulWidget {
  const FloorMapCanvas({
    super.key,
    required this.tokens,
    required this.zones,
    required this.routes,
    required this.stations,
    required this.alerts,
    required this.selectedPipelineId,
    required this.routeSourceLabel,
    this.loadMessage,
    this.onPipelineSelected,
    this.onOpenPipeline,
    this.onOpenAlert,
  });

  final FloorOpsTokens tokens;
  final List<ProductionZone> zones;
  final List<PipelineRoute> routes;
  final List<StationNode> stations;
  final List<FloorAlert> alerts;
  final String selectedPipelineId;
  final String routeSourceLabel;
  final String? loadMessage;
  final ValueChanged<String>? onPipelineSelected;
  final VoidCallback? onOpenPipeline;
  final ValueChanged<FloorAlert>? onOpenAlert;

  @override
  State<FloorMapCanvas> createState() => _FloorMapCanvasState();
}

class _FloorMapCanvasState extends State<FloorMapCanvas>
    with SingleTickerProviderStateMixin {
  late TransformationController _transformationController;
  late AnimationController _flowController;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _flowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _flowController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _zoomIn() {
    final matrix = _transformationController.value.clone();
    matrix.scaleByDouble(1.2, 1.2, 1.2, 1);
    _transformationController.value = matrix;
  }

  void _zoomOut() {
    final matrix = _transformationController.value.clone();
    matrix.scaleByDouble(1 / 1.2, 1 / 1.2, 1 / 1.2, 1);
    _transformationController.value = matrix;
  }

  void _fitFloor() {
    _transformationController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.tokens.surfaceCanvas,
          border: Border.all(color: widget.tokens.borderSubtle),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final selectedStations = widget.stations
                .where(
                  (station) => station.pipelineId == widget.selectedPipelineId,
                )
                .toList(growable: false);
            return Stack(
              children: [
                AnimatedBuilder(
                  animation: _flowController,
                  builder: (context, child) {
                    return InteractiveViewer(
                      transformationController: _transformationController,
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      minScale: 0.1,
                      maxScale: 5.0,
                      constrained: false,
                      child: SizedBox(
                        width: size.width,
                        height: size.height,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: FloorMapPainter(
                                  tokens: widget.tokens,
                                  zones: widget.zones,
                                  routes: widget.routes,
                                  selectedPipelineId: widget.selectedPipelineId,
                                  flowProgress: _flowController.value,
                                ),
                              ),
                            ),
                            for (final station in widget.stations)
                              _StationMarker(
                                tokens: widget.tokens,
                                station: station,
                                size: size,
                                selected:
                                    station.pipelineId ==
                                    widget.selectedPipelineId,
                                onTap: () => widget.onPipelineSelected?.call(
                                  station.pipelineId,
                                ),
                              ),
                            for (final alert in widget.alerts)
                              _AlertPin(
                                tokens: widget.tokens,
                                alert: alert,
                                size: size,
                                emphasized:
                                    alert.relatedPipelineId ==
                                    widget.selectedPipelineId,
                                onTap: () => widget.onOpenAlert?.call(alert),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                Positioned(
                  left: 20,
                  top: 18,
                  child: _MapFloatingLabel(
                    tokens: widget.tokens,
                    selectedPipelineId: widget.selectedPipelineId,
                    stationCount: selectedStations.length,
                    blockedCount: selectedStations
                        .where(
                          (station) => station.status == PipelineStatus.blocked,
                        )
                        .length,
                    bottleneckCount: selectedStations
                        .where((station) => station.isBottleneck)
                        .length,
                  ),
                ),
                Positioned(
                  left: 20,
                  top: 78,
                  child: _RoutePulsePanel(
                    tokens: widget.tokens,
                    progress: _flowController.value,
                    status:
                        selectedStations.any(
                          (station) => station.status == PipelineStatus.blocked,
                        )
                        ? PipelineStatus.blocked
                        : selectedStations.any(
                            (station) =>
                                station.status == PipelineStatus.waiting,
                          )
                        ? PipelineStatus.waiting
                        : PipelineStatus.running,
                  ),
                ),
                Positioned(
                  right: 20,
                  top: 18,
                  child: MapZoomControls(
                    tokens: widget.tokens,
                    onZoomIn: _zoomIn,
                    onZoomOut: _zoomOut,
                    onFit: _fitFloor,
                  ),
                ),
                Positioned(
                  right: 20,
                  top: 76,
                  child: _RouteSourcePanel(
                    tokens: widget.tokens,
                    label: widget.routeSourceLabel,
                    message: widget.loadMessage,
                  ),
                ),
                Positioned(
                  left: 20,
                  bottom: 18,
                  child: MapLegend(tokens: widget.tokens),
                ),
                Positioned(
                  right: 20,
                  bottom: 18,
                  child: _OpenPipelineControl(
                    tokens: widget.tokens,
                    onPressed: widget.onOpenPipeline,
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

class _StationMarker extends StatelessWidget {
  const _StationMarker({
    required this.tokens,
    required this.station,
    required this.size,
    required this.selected,
    this.onTap,
  });

  final FloorOpsTokens tokens;
  final StationNode station;
  final Size size;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = tokens.pipelineStatus(station.status);
    final center = Offset(
      station.position.dx * size.width,
      station.position.dy * size.height,
    );
    final markerSize = selected ? 22.0 : 14.0;
    return Positioned(
      left: center.dx - markerSize / 2 - 10,
      top: center.dy - markerSize / 2 - 10,
      child: Semantics(
        label:
            '${station.label}, ${station.status.label}${station.isBottleneck ? ', bottleneck' : ''}',
        child: Tooltip(
          message: '${station.label} · ${station.status.label}',
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(10),
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
                        color: (station.status == PipelineStatus.blocked
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
    this.onTap,
  });

  final FloorOpsTokens tokens;
  final FloorAlert alert;
  final Size size;
  final bool emphasized;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = tokens.alertSeverity(alert.severity);
    final position = Offset(
      alert.position.dx * size.width,
      alert.position.dy * size.height,
    );
    return Positioned(
      left: position.dx - 20,
      top: position.dy - 32,
      child: Semantics(
        label: '${alert.title}: ${alert.message}',
        child: Tooltip(
          message: alert.title,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(10),
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
        ),
      ),
    );
  }
}

class _MapFloatingLabel extends StatelessWidget {
  const _MapFloatingLabel({
    required this.tokens,
    required this.selectedPipelineId,
    required this.stationCount,
    required this.blockedCount,
    required this.bottleneckCount,
  });

  final FloorOpsTokens tokens;
  final String selectedPipelineId;
  final int stationCount;
  final int blockedCount;
  final int bottleneckCount;

  @override
  Widget build(BuildContext context) {
    return _FloatingMapPanel(
      tokens: tokens,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: blockedCount > 0 ? tokens.danger : tokens.selection,
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
          const SizedBox(height: 5),
          Text(
            '$stationCount stations · $bottleneckCount bottleneck · $blockedCount blocked',
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePulsePanel extends StatelessWidget {
  const _RoutePulsePanel({
    required this.tokens,
    required this.progress,
    required this.status,
  });

  final FloorOpsTokens tokens;
  final double progress;
  final PipelineStatus status;

  @override
  Widget build(BuildContext context) {
    final color = tokens.pipelineStatus(status);
    return _FloatingMapPanel(
      tokens: tokens,
      child: SizedBox(
        width: 196,
        child: Row(
          children: [
            SizedBox.square(
              dimension: 24,
              child: CustomPaint(
                painter: _RoutePulseMiniPainter(
                  color: color,
                  progress: progress,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    status == PipelineStatus.blocked
                        ? 'Transfer interrupted'
                        : status == PipelineStatus.waiting
                            ? 'Queue building'
                            : 'Material moving',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'Selected route telemetry',
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteSourcePanel extends StatelessWidget {
  const _RouteSourcePanel({
    required this.tokens,
    required this.label,
    this.message,
  });

  final FloorOpsTokens tokens;
  final String label;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final hasMessage = message != null && message!.trim().isNotEmpty;
    return _FloatingMapPanel(
      tokens: tokens,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 230),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.route_rounded,
                  size: 15,
                  color: hasMessage ? tokens.warning : tokens.selection,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            if (hasMessage) ...[
              const SizedBox(height: 5),
              Text(
                message!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoutePulseMiniPainter extends CustomPainter {
  const _RoutePulseMiniPainter({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ringPaint = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final dotPaint = Paint()..color = color;
    canvas.drawCircle(center, size.width * 0.38, ringPaint);
    final angle = (progress * math.pi * 2) - math.pi / 2;
    final position = center + Offset(math.cos(angle), math.sin(angle)) * 8;
    canvas.drawCircle(position, 4, dotPaint);
    canvas.drawCircle(
      center,
      2.4,
      dotPaint..color = color.withValues(alpha: 0.62),
    );
  }

  @override
  bool shouldRepaint(covariant _RoutePulseMiniPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.progress != progress;
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
              value: '${formatInt(floor.totalYield)} units',
              secondary: 'Target ${formatInt(floor.yieldTarget)}',
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
