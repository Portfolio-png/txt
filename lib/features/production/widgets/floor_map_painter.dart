import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/models/floor_view_models.dart';

class FloorMapPainter extends CustomPainter {
  const FloorMapPainter({
    required this.tokens,
    required this.zones,
    required this.routes,
    required this.selectedPipelineId,
    required this.flowProgress,
  });

  final FloorOpsTokens tokens;
  final List<ProductionZone> zones;
  final List<PipelineRoute> routes;
  final String selectedPipelineId;
  final double flowProgress;

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
      _drawFlowDashes(canvas, path, route.status);
      _drawFlowPackets(canvas, path, route.status);
    }
  }

  void _drawFlowDashes(Canvas canvas, Path path, PipelineStatus status) {
    final metrics = path.computeMetrics().toList(growable: false);
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final dashPaint = Paint()
      ..color = _routePulseColor(status).withValues(alpha: 0.82)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final phase = flowProgress * 42;
    for (var distance = phase; distance < metric.length; distance += 42) {
      final segment = metric.extractPath(
        distance,
        math.min(distance + 11, metric.length),
      );
      canvas.drawPath(segment, dashPaint);
    }
  }

  void _drawFlowPackets(Canvas canvas, Path path, PipelineStatus status) {
    final metrics = path.computeMetrics().toList(growable: false);
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final packetPaint = Paint()..color = _routePulseColor(status);
    final haloPaint = Paint()
      ..color = _routePulseColor(status).withValues(alpha: 0.16);
    for (var i = 0; i < 4; i += 1) {
      final distance = metric.length * ((flowProgress + (i * 0.25)) % 1);
      final tangent = metric.getTangentForOffset(distance);
      if (tangent == null) continue;
      canvas.drawCircle(tangent.position, 9, haloPaint);
      canvas.drawCircle(tangent.position, 3.6, packetPaint);
    }
  }

  Color _routePulseColor(PipelineStatus status) {
    return switch (status) {
      PipelineStatus.running => Colors.white,
      PipelineStatus.waiting => const Color(0xFFFFF0C2),
      PipelineStatus.blocked => const Color(0xFFFFD6D2),
      PipelineStatus.idle => Colors.white.withValues(alpha: 0.72),
    };
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
        oldDelegate.flowProgress != flowProgress ||
        oldDelegate.tokens != tokens ||
        oldDelegate.zones != zones ||
        oldDelegate.routes != routes;
  }
}

extension on int {
  bool isMultipleOf(int value) => this % value == 0;
}
