import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../production_pipelines/domain/pen_paper_baseline.dart';
import '../../domain/item_definition.dart';
import '../providers/items_provider.dart';

enum PipelineGraphView { materialFlow, massBreakdown, efficiencyYield }

/// A card displayed in Item View modal showing the default pipeline's
/// mass balance KPIs, material recovery efficiency, and interactive charts.
class ItemPipelineMetricsCard extends StatefulWidget {
  const ItemPipelineMetricsCard({super.key, required this.item});

  final ItemDefinition item;

  @override
  State<ItemPipelineMetricsCard> createState() =>
      _ItemPipelineMetricsCardState();
}

class _ItemPipelineMetricsCardState extends State<ItemPipelineMetricsCard> {
  PipelineGraphView _currentView = PipelineGraphView.materialFlow;
  bool _isLoading = true;
  PenPaperBaseline? _baseline;
  String? _pipelineName;

  @override
  void initState() {
    super.initState();
    _pipelineName = widget.item.defaultPipelineName;
    _loadPipelineData();
  }

  @override
  void didUpdateWidget(ItemPipelineMetricsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.defaultPipelineId != oldWidget.item.defaultPipelineId) {
      _loadPipelineData();
    }
  }

  Future<void> _loadPipelineData() async {
    final pipelineId = widget.item.defaultPipelineId;
    if (pipelineId == null || pipelineId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final itemsProvider = context.read<ItemsProvider>();
      final templates = await itemsProvider.fetchPipelineTemplates();
      final matched = templates.where((t) => t['id'] == pipelineId).firstOrNull;
      if (matched != null && _pipelineName == null) {
        _pipelineName = matched['name'];
      }

      // The card previews a baseline it has no recorded figures for, so it
      // shows this pipeline's own stage nodes rather than invented stage names.
      final nodesByPipeline = await itemsProvider.fetchPipelineStageNodes();
      final defaultBaseline = PenPaperBaseline.createDefaultForStages(
        nodesByPipeline[pipelineId],
      );

      if (mounted) {
        setState(() {
          _baseline = defaultBaseline;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _baseline = PenPaperBaseline.createDefault();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pipelineId = widget.item.defaultPipelineId;
    if (pipelineId == null || pipelineId.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    if (_isLoading) {
      return Container(
        height: 140,
        margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final baseline = _baseline ?? PenPaperBaseline.createDefault();
    final stages = baseline.stageReconciliations;
    final totalInput = baseline.totalInputKg > 0
        ? baseline.totalInputKg
        : 100.0;
    final finalGoodOutput = baseline.totalFinalOutputKg > 0
        ? baseline.totalFinalOutputKg
        : 73.0;
    final netRecoveryPercent = totalInput > 0
        ? (finalGoodOutput / totalInput) * 100.0
        : 73.0;

    double totalScrap = 0.0;
    double totalRejection = 0.0;
    double totalWeightLoss = 0.0;
    double sumStageYield = 0.0;

    for (final s in stages) {
      totalScrap += s.effectiveScrapKg;
      totalRejection += s.effectiveRejectionKg;
      totalWeightLoss += s.effectiveWeightLossKg;
      sumStageYield += s.yieldPercentage;
    }

    if (totalScrap == 0 && totalRejection == 0) {
      totalScrap = 14.0;
      totalRejection = 8.0;
      totalWeightLoss = 5.0;
    }

    final averageStageEfficiency = stages.isNotEmpty
        ? sumStageYield / stages.length
        : 90.0;
    final scrapPercent = totalInput > 0
        ? (totalScrap / totalInput) * 100.0
        : 14.0;
    final rejectionPercent = totalInput > 0
        ? (totalRejection / totalInput) * 100.0
        : 8.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Pipeline Badge & Traceability Action
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.analytics_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pipeline Mass Balance & Metrics',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      _pipelineName != null && _pipelineName!.isNotEmpty
                          ? 'Default: $_pipelineName'
                          : 'Linked Pipeline: $pipelineId',
                      style: TextStyle(color: theme.hintColor, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 4 KPI Summary Cards Row (Pipeline Net Recovery, Average Efficiency, Total Scrap, Total Rejection)
          LayoutBuilder(
            builder: (context, constraints) {
              final card1 = _buildKpiCard(
                label: 'Pipeline Net Recovery',
                value: '${netRecoveryPercent.toStringAsFixed(1)}%',
                subtitle: 'End-to-End Good Yield',
                icon: Icons.verified_rounded,
                color: const Color(0xFF2E7D32),
                backgroundColor: const Color(0xFFE8F5E9),
              );
              final card2 = _buildKpiCard(
                label: 'Average Efficiency',
                value: '${averageStageEfficiency.toStringAsFixed(1)}%',
                subtitle: 'Across ${stages.length} Stages',
                icon: Icons.trending_up_rounded,
                color: const Color(0xFF1976D2),
                backgroundColor: const Color(0xFFE3F2FD),
              );
              final card3 = _buildKpiCard(
                label: 'Total Scrap Loss',
                value: '${totalScrap.toStringAsFixed(1)} kg',
                subtitle: '${scrapPercent.toStringAsFixed(1)}% of Raw Inflow',
                icon: Icons.delete_outline_rounded,
                color: const Color(0xFFEF6C00),
                backgroundColor: const Color(0xFFFFF3E0),
              );
              final card4 = _buildKpiCard(
                label: 'Total Rejection',
                value: '${totalRejection.toStringAsFixed(1)} kg',
                subtitle:
                    '${rejectionPercent.toStringAsFixed(1)}% of Raw Inflow',
                icon: Icons.warning_amber_rounded,
                color: const Color(0xFFD32F2F),
                backgroundColor: const Color(0xFFFFEBEE),
              );

              if (constraints.maxWidth >= 640) {
                return Row(
                  children: [
                    Expanded(child: card1),
                    const SizedBox(width: 10),
                    Expanded(child: card2),
                    const SizedBox(width: 10),
                    Expanded(child: card3),
                    const SizedBox(width: 10),
                    Expanded(child: card4),
                  ],
                );
              } else {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: card1),
                        const SizedBox(width: 10),
                        Expanded(child: card2),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: card3),
                        const SizedBox(width: 10),
                        Expanded(child: card4),
                      ],
                    ),
                  ],
                );
              }
            },
          ),

          const SizedBox(height: 16),

          // Graph View Switcher Tabs (Material Flow Waterfall vs Mass Balance Breakdown vs Efficiency & Yield)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? Colors.grey.shade800
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildTabButton(
                    label: 'Material Flow Waterfall',
                    icon: Icons.waterfall_chart_rounded,
                    view: PipelineGraphView.materialFlow,
                  ),
                ),
                Expanded(
                  child: _buildTabButton(
                    label: 'Mass Balance Breakdown',
                    icon: Icons.pie_chart_outline_rounded,
                    view: PipelineGraphView.massBreakdown,
                  ),
                ),
                Expanded(
                  child: _buildTabButton(
                    label: 'Efficiency & Yield',
                    icon: Icons.show_chart_rounded,
                    view: PipelineGraphView.efficiencyYield,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Visualizer Canvas
          Container(
            height: 220,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: theme.brightness == Brightness.dark
                    ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                    : [const Color(0xFFF8FAFC), const Color(0xFFEEF2F6)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: 0.15),
              ),
            ),
            child: CustomPaint(
              painter: WholePipelineGarnishedPainter(
                view: _currentView,
                stages: stages,
                totalInputKg: totalInput,
                finalGoodOutputKg: finalGoodOutput,
                totalScrapKg: totalScrap,
                totalRejectionKg: totalRejection,
                totalWeightLossKg: totalWeightLoss,
                netRecoveryPercent: netRecoveryPercent,
                averageEfficiency: averageStageEfficiency,
                theme: theme,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    double? width,
    required String label,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color backgroundColor,
  }) {
    return Container(
      width: width ?? 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String label,
    required IconData icon,
    required PipelineGraphView view,
  }) {
    final isSelected = _currentView == view;
    return InkWell(
      onTap: () => setState(() => _currentView = view),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? const Color(0xFF1E88E5)
                  : Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? const Color(0xFF1E88E5)
                      : Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter rendering whole-pipeline material flow, mass breakdown, or efficiency curves.
class WholePipelineGarnishedPainter extends CustomPainter {
  WholePipelineGarnishedPainter({
    required this.view,
    required this.stages,
    required this.totalInputKg,
    required this.finalGoodOutputKg,
    required this.totalScrapKg,
    required this.totalRejectionKg,
    required this.totalWeightLossKg,
    required this.netRecoveryPercent,
    required this.averageEfficiency,
    required this.theme,
  });

  final PipelineGraphView view;
  final List<PenPaperStageReconciliation> stages;
  final double totalInputKg;
  final double finalGoodOutputKg;
  final double totalScrapKg;
  final double totalRejectionKg;
  final double totalWeightLossKg;
  final double netRecoveryPercent;
  final double averageEfficiency;
  final ThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    switch (view) {
      case PipelineGraphView.materialFlow:
        _paintMaterialFlowWaterfall(canvas, size);
        break;
      case PipelineGraphView.massBreakdown:
        _paintMassBalanceBreakdown(canvas, size);
        break;
      case PipelineGraphView.efficiencyYield:
        _paintEfficiencyYieldCurve(canvas, size);
        break;
    }
  }

  void _paintMaterialFlowWaterfall(Canvas canvas, Size size) {
    final leftPad = 48.0;
    final rightPad = 20.0;
    final topPad = 24.0;
    final bottomPad = 32.0;

    final width = size.width - leftPad - rightPad;
    final height = size.height - topPad - bottomPad;

    final maxKg = math.max(totalInputKg * 1.15, 10.0);

    // Y Axis Grid lines
    final gridPaint = Paint()
      ..color = theme.dividerColor.withValues(alpha: 0.12)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = topPad + height * (1 - i / 4);
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(size.width - rightPad, y),
        gridPaint,
      );

      final val = (maxKg * i / 4).round();
      final tp = TextPainter(
        text: TextSpan(
          text: '$val kg',
          style: TextStyle(fontSize: 9, color: theme.hintColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 6, y - tp.height / 2));
    }

    final labels = [
      'Raw Inflow',
      'Good Product',
      'Scrap',
      'Rejection',
      'Process Loss',
    ];
    final values = [
      totalInputKg,
      finalGoodOutputKg,
      totalScrapKg,
      totalRejectionKg,
      totalWeightLossKg,
    ];
    final colors = [
      const Color(0xFF1E88E5), // Blue
      const Color(0xFF43A047), // Green
      const Color(0xFFFB8C00), // Orange
      const Color(0xFFE53935), // Red
      const Color(0xFF8E24AA), // Purple
    ];

    final colWidth = width / labels.length;
    final barWidth = math.min(colWidth * 0.55, 38.0);

    for (int i = 0; i < labels.length; i++) {
      final val = values[i];
      final colX = leftPad + i * colWidth + (colWidth - barWidth) / 2;
      final barH = (height * (val / maxKg)).clamp(4.0, height);
      final barY = topPad + height - barH;

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors[i].withValues(alpha: 0.85), colors[i]],
        ).createShader(Rect.fromLTWH(colX, barY, barWidth, barH));

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(colX, barY, barWidth, barH),
          const Radius.circular(5),
        ),
        paint,
      );

      // Value label on top
      final valTp = TextPainter(
        text: TextSpan(
          text: '${val.toStringAsFixed(1)}k',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: colors[i],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      valTp.paint(
        canvas,
        Offset(colX + (barWidth - valTp.width) / 2, barY - valTp.height - 2),
      );

      // Category label below
      final labelTp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: theme.hintColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelTp.paint(
        canvas,
        Offset(
          colX + (barWidth - labelTp.width) / 2,
          size.height - bottomPad + 6,
        ),
      );
    }
  }

  void _paintMassBalanceBreakdown(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.32, size.height * 0.5);
    final radius = math.min(size.height * 0.38, 70.0);
    final strokeWidth = 26.0;

    final double totalKg = math.max(0.1, totalInputKg);
    final double goodRatio = (finalGoodOutputKg / totalKg).clamp(0.0, 1.0);
    final double scrapRatio = (totalScrapKg / totalKg).clamp(0.0, 1.0);
    final double rejRatio = (totalRejectionKg / totalKg).clamp(0.0, 1.0);
    final double lossRatio = (totalWeightLossKg / totalKg).clamp(0.0, 1.0);

    final rect = Rect.fromCircle(center: center, radius: radius);
    double startAngle = -math.pi / 2;

    void drawSegment(double ratio, Color color) {
      if (ratio <= 0) return;
      final sweepAngle = ratio * 2 * math.pi;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }

    drawSegment(goodRatio, const Color(0xFF43A047)); // Green Good
    drawSegment(scrapRatio, const Color(0xFFFB8C00)); // Orange Scrap
    drawSegment(rejRatio, const Color(0xFFE53935)); // Red Rejection
    drawSegment(lossRatio, const Color(0xFF8E24AA)); // Purple Loss

    // Center text in Donut
    final centerTp = TextPainter(
      text: TextSpan(
        text: '${netRecoveryPercent.toStringAsFixed(0)}%\nRecovery',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          height: 1.1,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    centerTp.paint(
      canvas,
      Offset(center.dx - centerTp.width / 2, center.dy - centerTp.height / 2),
    );

    // Legend on the Right Hand Side
    final legendX = size.width * 0.60;
    final items = [
      {
        'label': 'Good Yield (${(goodRatio * 100).toStringAsFixed(1)}%)',
        'color': const Color(0xFF43A047),
        'kg': '${finalGoodOutputKg.toStringAsFixed(1)} kg',
      },
      {
        'label': 'Scrap Material (${(scrapRatio * 100).toStringAsFixed(1)}%)',
        'color': const Color(0xFFFB8C00),
        'kg': '${totalScrapKg.toStringAsFixed(1)} kg',
      },
      {
        'label': 'Rejections (${(rejRatio * 100).toStringAsFixed(1)}%)',
        'color': const Color(0xFFE53935),
        'kg': '${totalRejectionKg.toStringAsFixed(1)} kg',
      },
      {
        'label': 'Process Loss (${(lossRatio * 100).toStringAsFixed(1)}%)',
        'color': const Color(0xFF8E24AA),
        'kg': '${totalWeightLossKg.toStringAsFixed(1)} kg',
      },
    ];

    double legY = size.height * 0.18;
    for (final item in items) {
      final col = item['color'] as Color;
      final legText = item['label'] as String;
      final kgText = item['kg'] as String;

      canvas.drawCircle(Offset(legendX, legY + 6), 5, Paint()..color = col);

      final tp = TextPainter(
        text: TextSpan(
          text: '$legText\n$kgText',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: theme.hintColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(legendX + 14, legY));

      legY += 38.0;
    }
  }

  void _paintEfficiencyYieldCurve(Canvas canvas, Size size) {
    final leftPad = 42.0;
    final rightPad = 24.0;
    final topPad = 24.0;
    final bottomPad = 28.0;

    final width = size.width - leftPad - rightPad;
    final height = size.height - topPad - bottomPad;

    // Y Axis Grid (0% to 100%)
    final gridPaint = Paint()
      ..color = theme.dividerColor.withValues(alpha: 0.12)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = topPad + height * (1 - i / 4);
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(size.width - rightPad, y),
        gridPaint,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: '${i * 25}%',
          style: TextStyle(fontSize: 9, color: theme.hintColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 6, y - tp.height / 2));
    }

    if (stages.isEmpty) return;

    // Average Yield Benchmark Line (Dashed)
    final avgY =
        topPad + height * (1 - (averageEfficiency / 100.0).clamp(0.0, 1.0));
    final dashPaint = Paint()
      ..color = const Color(0xFF1E88E5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    double curX = leftPad;
    while (curX < size.width - rightPad) {
      canvas.drawLine(
        Offset(curX, avgY),
        Offset(math.min(curX + 5, size.width - rightPad), avgY),
        dashPaint,
      );
      curX += 9;
    }

    // Benchmark Label
    final benchTp = TextPainter(
      text: TextSpan(
        text:
            'Average Pipeline Efficiency (${averageEfficiency.toStringAsFixed(1)}%)',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E88E5),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    benchTp.paint(
      canvas,
      Offset(
        size.width - rightPad - benchTp.width - 4,
        avgY - benchTp.height - 3,
      ),
    );

    // Smooth Yield Line Curve across stages
    final points = <Offset>[];
    final stepW = width / (stages.length > 1 ? (stages.length - 1) : 1);

    for (int i = 0; i < stages.length; i++) {
      final s = stages[i];
      final px = stages.length > 1 ? leftPad + i * stepW : leftPad + width / 2;
      final py =
          topPad + height * (1 - (s.yieldPercentage / 100.0).clamp(0.0, 1.0));
      points.add(Offset(px, py));
    }

    // Draw Line
    final linePaint = Paint()
      ..color = const Color(0xFF43A047)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i < points.length; i++) {
      if (i == 0) {
        path.moveTo(points[i].dx, points[i].dy);
      } else {
        path.lineTo(points[i].dx, points[i].dy);
      }
    }
    canvas.drawPath(path, linePaint);

    // Draw Node Points & Labels
    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      final dotPaint = Paint()..color = const Color(0xFF2E7D32);
      canvas.drawCircle(pt, 5, dotPaint);
      canvas.drawCircle(pt, 2.5, Paint()..color = Colors.white);

      final valTp = TextPainter(
        text: TextSpan(
          text: '${stages[i].yieldPercentage.toStringAsFixed(1)}%',
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2E7D32),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      valTp.paint(
        canvas,
        Offset(pt.dx - valTp.width / 2, pt.dy - valTp.height - 4),
      );

      final nameTp = TextPainter(
        text: TextSpan(
          text: 'Stage ${i + 1}',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: theme.hintColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      nameTp.paint(
        canvas,
        Offset(pt.dx - nameTp.width / 2, size.height - bottomPad + 5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant WholePipelineGarnishedPainter oldDelegate) {
    return oldDelegate.view != view ||
        oldDelegate.stages != stages ||
        oldDelegate.totalInputKg != totalInputKg ||
        oldDelegate.finalGoodOutputKg != finalGoodOutputKg ||
        oldDelegate.totalScrapKg != totalScrapKg ||
        oldDelegate.totalRejectionKg != totalRejectionKg ||
        oldDelegate.totalWeightLossKg != totalWeightLossKg ||
        oldDelegate.netRecoveryPercent != netRecoveryPercent ||
        oldDelegate.averageEfficiency != averageEfficiency;
  }
}
