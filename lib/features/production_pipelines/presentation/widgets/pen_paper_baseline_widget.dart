import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/pen_paper_baseline.dart';

enum PipelineGraphView { materialFlow, massBreakdown, efficiencyYield }

class PenPaperBaselineWidget extends StatefulWidget {
  const PenPaperBaselineWidget({
    super.key,
    required this.baseline,
    required this.onChanged,
    this.readOnly = false,
    this.stageNames = const [],
  });

  final PenPaperBaseline baseline;
  final ValueChanged<PenPaperBaseline> onChanged;
  final bool readOnly;
  final List<String> stageNames;

  @override
  State<PenPaperBaselineWidget> createState() => _PenPaperBaselineWidgetState();
}

class _PenPaperBaselineWidgetState extends State<PenPaperBaselineWidget> {
  PipelineGraphView _currentView = PipelineGraphView.materialFlow;

  @override
  void initState() {
    super.initState();
    _ensureStageReconciliations();
  }

  @override
  void didUpdateWidget(PenPaperBaselineWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stageNames != oldWidget.stageNames) {
      _ensureStageReconciliations();
    }
  }

  void _ensureStageReconciliations() {
    final currentList = widget.baseline.stageReconciliations;
    final stages = widget.stageNames.isNotEmpty
        ? widget.stageNames
        : const ['Stage 1 (Cutting)', 'Stage 2 (Molding)', 'Stage 3 (Finishing)'];

    if (currentList.isEmpty || currentList.length != stages.length) {
      final newBaseline = PenPaperBaseline.createDefaultForStages(stages);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onChanged(newBaseline);
      });
    }
  }

  void _updateStageReconciliation(int index, PenPaperStageReconciliation updated) {
    final list = List<PenPaperStageReconciliation>.from(widget.baseline.stageReconciliations);
    if (index >= 0 && index < list.length) {
      list[index] = updated;

      // Automatically carry forward output kg to next stage input kg
      if (index + 1 < list.length) {
        final nextStage = list[index + 1];
        list[index + 1] = nextStage.copyWith(inputKg: updated.outputKg);
      }

      widget.onChanged(widget.baseline.copyWith(stageReconciliations: list));
    }
  }

  void _openStageEditorModal(int index) {
    final stages = widget.baseline.stageReconciliations;
    if (index < 0 || index >= stages.length) return;
    final current = stages[index];

    bool recordScrap = current.recordScrap;
    bool recordRejection = current.recordRejection;
    bool recordWeightLoss = current.recordWeightLoss;

    final inputCtrl = TextEditingController(text: current.inputKg.toStringAsFixed(1));
    final outputCtrl = TextEditingController(text: current.outputKg.toStringAsFixed(1));
    final scrapCtrl = TextEditingController(text: current.scrapKg.toStringAsFixed(1));
    final rejectionCtrl = TextEditingController(text: current.rejectionKg.toStringAsFixed(1));
    final lossCtrl = TextEditingController(text: current.weightLossKg.toStringAsFixed(1));
    final notesCtrl = TextEditingController(text: current.notes);
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: const Color(0xFF1E88E5).withValues(alpha: 0.15),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E88E5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Stage ${index + 1}: ${current.stageName} Reconciliation',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select recorded loss categories for this stage:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('Record Scrap (kg)'),
                            selected: recordScrap,
                            onSelected: (val) {
                              setModalState(() => recordScrap = val);
                            },
                          ),
                          FilterChip(
                            label: const Text('Record Rejection (kg)'),
                            selected: recordRejection,
                            onSelected: (val) {
                              setModalState(() => recordRejection = val);
                            },
                          ),
                          FilterChip(
                            label: const Text('Record Weight Loss (kg)'),
                            selected: recordWeightLoss,
                            onSelected: (val) {
                              setModalState(() => recordWeightLoss = val);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: inputCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Stage Inflow (kg)',
                                suffixText: 'kg',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) => double.tryParse(v ?? '') == null ? 'Enter kg' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: outputCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Good Output (kg)',
                                suffixText: 'kg',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) => double.tryParse(v ?? '') == null ? 'Enter kg' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (recordScrap) ...[
                        TextFormField(
                          controller: scrapCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Scrap Material (kg)',
                            suffixText: 'kg',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (recordRejection) ...[
                        TextFormField(
                          controller: rejectionCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Rejection Material (kg)',
                            suffixText: 'kg',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (recordWeightLoss) ...[
                        TextFormField(
                          controller: lossCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Process / Burning Loss (kg)',
                            suffixText: 'kg',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: notesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Stage Remarks / Notes',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() == true) {
                      final updated = current.copyWith(
                        recordScrap: recordScrap,
                        recordRejection: recordRejection,
                        recordWeightLoss: recordWeightLoss,
                        inputKg: double.parse(inputCtrl.text),
                        outputKg: double.parse(outputCtrl.text),
                        scrapKg: recordScrap ? (double.tryParse(scrapCtrl.text) ?? 0.0) : 0.0,
                        rejectionKg: recordRejection ? (double.tryParse(rejectionCtrl.text) ?? 0.0) : 0.0,
                        weightLossKg: recordWeightLoss ? (double.tryParse(lossCtrl.text) ?? 0.0) : 0.0,
                        notes: notesCtrl.text.trim(),
                      );
                      _updateStageReconciliation(index, updated);
                      Navigator.pop(ctx);
                    }
                  },
                  child: Text(index + 1 < stages.length ? 'Done & Next Stage ➔' : 'Save Reconciliation'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stages = widget.baseline.stageReconciliations;
    final totalInput = widget.baseline.totalInputKg;
    final finalGoodOutput = widget.baseline.totalFinalOutputKg;
    final netRecoveryPercent = widget.baseline.overallYieldPercentage;

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

    final averageStageEfficiency = stages.isNotEmpty ? sumStageYield / stages.length : 0.0;
    final scrapPercent = totalInput > 0 ? (totalScrap / totalInput) * 100.0 : 0.0;
    final rejectionPercent = totalInput > 0 ? (totalRejection / totalInput) * 100.0 : 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with Title & Graph View Toggle
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.analytics_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Production Pipeline Mass Balance & Efficiency',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    Text(
                      'Whole-pipeline material reconciliation, yield, scrap, and mass flow analytics.',
                      style: TextStyle(color: theme.hintColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Wholesome KPI Summary Cards Row
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildKpiCard(
                label: 'Pipeline Net Recovery',
                value: '${netRecoveryPercent.toStringAsFixed(1)}%',
                subtitle: 'End-to-End Good Yield',
                icon: Icons.verified_rounded,
                color: const Color(0xFF2E7D32),
                backgroundColor: const Color(0xFFE8F5E9),
              ),
              _buildKpiCard(
                label: 'Average Efficiency',
                value: '${averageStageEfficiency.toStringAsFixed(1)}%',
                subtitle: 'Across ${stages.length} Stages',
                icon: Icons.trending_up_rounded,
                color: const Color(0xFF1976D2),
                backgroundColor: const Color(0xFFE3F2FD),
              ),
              _buildKpiCard(
                label: 'Total Scrap Loss',
                value: '${totalScrap.toStringAsFixed(1)} kg',
                subtitle: '${scrapPercent.toStringAsFixed(1)}% of Raw Inflow',
                icon: Icons.delete_outline_rounded,
                color: const Color(0xFFEF6C00),
                backgroundColor: const Color(0xFFFFF3E0),
              ),
              _buildKpiCard(
                label: 'Total Rejection',
                value: '${totalRejection.toStringAsFixed(1)} kg',
                subtitle: '${rejectionPercent.toStringAsFixed(1)}% of Raw Inflow',
                icon: Icons.warning_amber_rounded,
                color: const Color(0xFFD32F2F),
                backgroundColor: const Color(0xFFFFEBEE),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Graph View Switcher (Material Flow Waterfall vs Mass Breakdown vs Efficiency Curve)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark ? Colors.grey.shade800 : Colors.grey.shade100,
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

          // Wholesome Garnished Graph Visualizer Canvas
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
              border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),
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

          const SizedBox(height: 18),

          // Stage Reconciliation List Header & Actions
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 4,
            children: [
              Text(
                'Stage Reconciliation Fill-ups (${stages.length} Stages)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Text(
                'In: ${totalInput.toStringAsFixed(1)} kg ➔ Out: ${finalGoodOutput.toStringAsFixed(1)} kg',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: theme.hintColor),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Stage Cards
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: stages.length,
            separatorBuilder: (ctx, i) => const SizedBox(height: 8),
            itemBuilder: (ctx, index) {
              final stage = stages[index];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark ? Colors.grey.shade900 : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: const Color(0xFF1E88E5).withValues(alpha: 0.15),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E88E5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stage.stageName,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 3),
                          Wrap(
                            spacing: 8,
                            children: [
                              Text(
                                'In: ${stage.inputKg.toStringAsFixed(1)} kg ➔ Out: ${stage.outputKg.toStringAsFixed(1)} kg',
                                style: TextStyle(fontSize: 11, color: theme.hintColor),
                              ),
                              if (stage.effectiveScrapKg > 0)
                                Text(
                                  'Scrap: ${stage.scrapKg.toStringAsFixed(1)} kg',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFFEF6C00)),
                                ),
                              if (stage.effectiveRejectionKg > 0)
                                Text(
                                  'Rejection: ${stage.rejectionKg.toStringAsFixed(1)} kg',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFFD32F2F)),
                                ),
                              if (stage.effectiveWeightLossKg > 0)
                                Text(
                                  'Loss: ${stage.weightLossKg.toStringAsFixed(1)} kg',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF8E24AA)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: stage.yieldPercentage >= 85.0
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${stage.yieldPercentage.toStringAsFixed(1)}% Yield',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: stage.yieldPercentage >= 85.0
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFEF6C00),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (!widget.readOnly)
                      ElevatedButton.icon(
                        onPressed: () => _openStageEditorModal(index),
                        icon: const Icon(Icons.edit_note_rounded, size: 16),
                        label: const Text('Reconcile'),
                        style: ElevatedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String label,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color backgroundColor,
  }) {
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color),
          ),
          Text(
            subtitle,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: color.withValues(alpha: 0.8)),
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
    return GestureDetector(
      onTap: () => setState(() => _currentView = view),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? const Color(0xFF1E88E5) : Colors.grey,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? const Color(0xFF1E88E5) : Colors.grey.shade700,
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
    final leftPad = 40.0;
    final rightPad = 20.0;
    final topPad = 24.0;
    final bottomPad = 32.0;

    final width = size.width - leftPad - rightPad;
    final height = size.height - topPad - bottomPad;

    final double maxKg = math.max(1.0, totalInputKg * 1.15);

    // Grid lines in KG
    final gridPaint = Paint()
      ..color = theme.dividerColor.withValues(alpha: 0.12)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = topPad + height * (1 - i / 4);
      final kgVal = (maxKg * (i / 4)).toStringAsFixed(0);

      canvas.drawLine(Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);

      final tp = TextPainter(
        text: TextSpan(text: '$kgVal kg', style: TextStyle(fontSize: 9, color: theme.hintColor)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 6, y - tp.height / 2));
    }

    // 5 Columns: Raw Inflow, Good Product, Scrap Loss, Rejections, Burning Loss
    final labels = ['Raw Inflow', 'Good Product', 'Scrap', 'Rejection', 'Process Loss'];
    final values = [totalInputKg, finalGoodOutputKg, totalScrapKg, totalRejectionKg, totalWeightLossKg];
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
      final barH = height * (val / maxKg);
      final barY = topPad + height - barH;

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors[i].withValues(alpha: 0.85), colors[i]],
        ).createShader(Rect.fromLTWH(colX, barY, barWidth, barH));

      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(colX, barY, barWidth, barH), const Radius.circular(5)),
        paint,
      );

      // Value label on top
      final valTp = TextPainter(
        text: TextSpan(
          text: '${val.toStringAsFixed(1)}k',
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: colors[i]),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      valTp.paint(canvas, Offset(colX + (barWidth - valTp.width) / 2, barY - valTp.height - 2));

      // Category label below
      final labelTp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: theme.hintColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelTp.paint(canvas, Offset(colX + (barWidth - labelTp.width) / 2, size.height - bottomPad + 6));
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
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, height: 1.1),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    centerTp.paint(canvas, Offset(center.dx - centerTp.width / 2, center.dy - centerTp.height / 2));

    // Legend on the Right Hand Side
    final legendX = size.width * 0.60;
    final items = [
      {'label': 'Good Yield (${(goodRatio * 100).toStringAsFixed(1)}%)', 'color': const Color(0xFF43A047), 'kg': '${finalGoodOutputKg.toStringAsFixed(1)} kg'},
      {'label': 'Scrap Material (${(scrapRatio * 100).toStringAsFixed(1)}%)', 'color': const Color(0xFFFB8C00), 'kg': '${totalScrapKg.toStringAsFixed(1)} kg'},
      {'label': 'Rejections (${(rejRatio * 100).toStringAsFixed(1)}%)', 'color': const Color(0xFFE53935), 'kg': '${totalRejectionKg.toStringAsFixed(1)} kg'},
      {'label': 'Process Loss (${(lossRatio * 100).toStringAsFixed(1)}%)', 'color': const Color(0xFF8E24AA), 'kg': '${totalWeightLossKg.toStringAsFixed(1)} kg'},
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
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: theme.hintColor),
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
      canvas.drawLine(Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);

      final tp = TextPainter(
        text: TextSpan(text: '${i * 25}%', style: TextStyle(fontSize: 9, color: theme.hintColor)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 6, y - tp.height / 2));
    }

    if (stages.isEmpty) return;

    // Average Yield Benchmark Line (Dashed)
    final avgY = topPad + height * (1 - (averageEfficiency / 100.0).clamp(0.0, 1.0));
    final dashPaint = Paint()
      ..color = const Color(0xFF1E88E5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    double curX = leftPad;
    while (curX < size.width - rightPad) {
      canvas.drawLine(Offset(curX, avgY), Offset(math.min(curX + 5, size.width - rightPad), avgY), dashPaint);
      curX += 9;
    }

    // Benchmark Label
    final benchTp = TextPainter(
      text: TextSpan(
        text: 'Average Pipeline Efficiency (${averageEfficiency.toStringAsFixed(1)}%)',
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1E88E5)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    benchTp.paint(canvas, Offset(size.width - rightPad - benchTp.width - 4, avgY - benchTp.height - 3));

    // Smooth Yield Line Curve across stages
    final points = <Offset>[];
    final stepW = width / (stages.length > 1 ? (stages.length - 1) : 1);

    for (int i = 0; i < stages.length; i++) {
      final s = stages[i];
      final px = stages.length > 1 ? leftPad + i * stepW : leftPad + width / 2;
      final py = topPad + height * (1 - (s.yieldPercentage / 100.0).clamp(0.0, 1.0));
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
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      valTp.paint(canvas, Offset(pt.dx - valTp.width / 2, pt.dy - valTp.height - 4));

      final nameTp = TextPainter(
        text: TextSpan(
          text: 'Stage ${i + 1}',
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: theme.hintColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      nameTp.paint(canvas, Offset(pt.dx - nameTp.width / 2, size.height - bottomPad + 5));
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
