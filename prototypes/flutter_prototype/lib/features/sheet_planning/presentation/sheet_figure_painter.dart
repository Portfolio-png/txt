import 'package:flutter/material.dart';
import '../domain/sheet_plan.dart';

class SheetFigureWidget extends StatelessWidget {
  final SheetPlan plan;
  final double width;
  final double height;
  final int highlightedStage; // 0: Raw, 1: Slit, 2: Blanked, 3: Plated, 4: Assembled

  const SheetFigureWidget({
    super.key,
    required this.plan,
    this.width = double.infinity,
    this.height = double.infinity,
    this.highlightedStage = 2,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width == double.infinity ? null : width,
      height: height == double.infinity ? null : height,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: CustomPaint(
          size: Size(width == double.infinity ? 300 : width, height == double.infinity ? 200 : height),
          painter: SheetFigurePainter(
            plan: plan,
            stage: highlightedStage,
          ),
        ),
      ),
    );
  }
}

class SheetFigurePainter extends CustomPainter {
  final SheetPlan plan;
  final int stage;

  SheetFigurePainter({required this.plan, required this.stage});

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 16.0;
    final drawAreaW = size.width - 2 * padding;
    final drawAreaH = size.height - 2 * padding;

    if (drawAreaW <= 0 || drawAreaH <= 0) return;

    final sheetAspect = plan.widthMm / plan.heightMm;
    final areaAspect = drawAreaW / drawAreaH;

    double sheetPxW, sheetPxH;
    if (sheetAspect > areaAspect) {
      sheetPxW = drawAreaW;
      sheetPxH = sheetPxW / sheetAspect;
    } else {
      sheetPxH = drawAreaH;
      sheetPxW = sheetPxH * sheetAspect;
    }

    final originX = padding + (drawAreaW - sheetPxW) / 2;
    final originY = padding + (drawAreaH - sheetPxH) / 2;
    final scale = sheetPxW / plan.widthMm;

    // Draw Sheet Metal Background
    final Color metalColor = switch (stage) {
      3 => const Color(0xFF38BDF8), // Zinc Blue Passivated
      4 => const Color(0xFF818CF8), // Assembled Part
      _ => const Color(0xFF94A3B8), // Raw Steel MS
    };

    final sheetRect = Rect.fromLTWH(originX, originY, sheetPxW, sheetPxH);
    final sheetPaint = Paint()
      ..color = metalColor.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(RRect.fromRectAndRadius(sheetRect, const Radius.circular(3)), sheetPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFFF8FAFC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(RRect.fromRectAndRadius(sheetRect, const Radius.circular(3)), borderPaint);

    // Trim Margins
    final trimPx = plan.edgeTrimMm * scale;
    final usableRect = Rect.fromLTWH(
      originX + trimPx,
      originY + trimPx,
      sheetPxW - 2 * trimPx,
      sheetPxH - 2 * trimPx,
    );

    final trimPaint = Paint()
      ..color = const Color(0xFFEF4444).withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(usableRect, trimPaint);

    // If stage 0: only show raw sheet with trim
    if (stage == 0) {
      _drawDimensionLabels(canvas, originX, originY, sheetPxW, sheetPxH, plan);
      return;
    }

    // Draw Slit Bands & Sub-cuts
    final partPaint = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final partBorderPaint = Paint()
      ..color = const Color(0xFF60A5FA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    double currentX = originX + trimPx;
    final kerfPx = plan.kerfMm * scale;

    for (int b = 0; b < plan.bands.length; b++) {
      final band = plan.bands[b];
      final bandWidthPx = band.sizeMm * scale;
      final cuts = plan.subCuts[b] ?? [];

      for (int i = 0; i < band.count; i++) {
        if (currentX + bandWidthPx > originX + sheetPxW - trimPx) break;

        final bandRect = Rect.fromLTWH(
          currentX,
          originY + trimPx,
          bandWidthPx,
          usableRect.height,
        );

        // In Stage 1: only slitting lines are drawn
        if (stage == 1 || cuts.isEmpty) {
          canvas.drawRect(bandRect, partPaint);
          canvas.drawRect(bandRect, partBorderPaint);
        } else {
          // Stage 2+: Guillotine sub-cuts
          double currentY = originY + trimPx;
          for (final cut in cuts) {
            final cutHeightPx = cut.sizeMm * scale;
            for (int c = 0; c < cut.count; c++) {
              if (currentY + cutHeightPx > originY + sheetPxH - trimPx) break;

              final pieceRect = Rect.fromLTWH(
                currentX,
                currentY,
                bandWidthPx,
                cutHeightPx,
              );

              canvas.drawRect(pieceRect, partPaint);
              canvas.drawRect(pieceRect, partBorderPaint);

              currentY += cutHeightPx + kerfPx;
            }
          }
        }

        currentX += bandWidthPx + kerfPx;
      }
    }

    _drawDimensionLabels(canvas, originX, originY, sheetPxW, sheetPxH, plan);
  }

  void _drawDimensionLabels(
    Canvas canvas,
    double x,
    double y,
    double w,
    double h,
    SheetPlan plan,
  ) {
    const textStyle = TextStyle(
      color: Color(0xFF94A3B8),
      fontSize: 10,
      fontWeight: FontWeight.bold,
    );

    final textSpanW = TextSpan(
      text: '${plan.sheetWidthInches.toStringAsFixed(0)}" (${plan.widthMm.toStringAsFixed(0)}mm)',
      style: textStyle,
    );
    final textPainterW = TextPainter(
      text: textSpanW,
      textDirection: TextDirection.ltr,
    )..layout();
    textPainterW.paint(canvas, Offset(x + (w - textPainterW.width) / 2, y - 14));

    final textSpanH = TextSpan(
      text: '${plan.sheetHeightInches.toStringAsFixed(0)}"',
      style: textStyle,
    );
    final textPainterH = TextPainter(
      text: textSpanH,
      textDirection: TextDirection.ltr,
    )..layout();
    textPainterH.paint(canvas, Offset(x - textPainterH.width - 4, y + (h - textPainterH.height) / 2));
  }

  @override
  bool shouldRepaint(covariant SheetFigurePainter oldDelegate) {
    return oldDelegate.plan != plan || oldDelegate.stage != stage;
  }
}
