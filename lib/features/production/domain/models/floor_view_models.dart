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
    backgroundBase: Color(0xFFF1F5F9),
    surfacePanel: Color(0xFFFFFFFF),
    surfaceFloating: Color(0xF7FFFFFF),
    surfaceCanvas: Color(0xFFF8FAFC),
    mapGround: Color(0xFFF1F5F9),
    mapDraftLine: Color(0xFFE2E8F0),
    mapBlock: Color(0xFFFFFFFF),
    mapBlockMuted: Color(0xFFF8FAFC),
    mapBlockSelected: Color(0xFFEFF6FF),
    mapBlockBorder: Color(0xFFE2E8F0),
    mapRoute: Color(0xFFCBD5E1),
    mapRouteSelected: Color(0xFF3B82F6),
    textPrimary: Color(0xFF1E293B),
    textSecondary: Color(0xFF64748B),
    borderSubtle: Color(0xFFE2E8F0),
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    selection: Color(0xFF3B82F6),
    muted: Color(0xFF94A3B8),
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

extension PipelineStatusExtension on PipelineStatus {
  String get label {
    return switch (this) {
      PipelineStatus.running => 'RUNNING',
      PipelineStatus.waiting => 'WAITING',
      PipelineStatus.blocked => 'BLOCKED',
      PipelineStatus.idle => 'IDLE',
    };
  }
}
