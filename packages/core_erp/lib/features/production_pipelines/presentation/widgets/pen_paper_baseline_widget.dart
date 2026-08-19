import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../../core/widgets/pm_segmented_control.dart';
import '../../domain/pen_paper_baseline.dart';

/// Write-only record for a sample production run's material flow, in kilograms.
/// Either the pipeline as a whole, or stage by stage.
class PenPaperBaselineWidget extends StatefulWidget {
  const PenPaperBaselineWidget({
    super.key,
    required this.baseline,
    required this.onChanged,
    this.readOnly = false,
    this.stageNames = const [],
    this.showChrome = true,
    this.pipelineId,
    this.pipelineName = '',
  });

  final PenPaperBaseline baseline;
  final ValueChanged<PenPaperBaseline> onChanged;
  final bool readOnly;
  final List<String> stageNames;

  /// Whether to draw the surrounding card and the title row. Hosts that already
  /// sit the widget inside their own titled section pass false, so the heading
  /// is not printed twice.
  final bool showChrome;

  /// The pipeline this sample is being recorded against. Stamped onto the
  /// baseline so the weights stay interpretable if the item is later moved to
  /// a different route.
  final String? pipelineId;
  final String pipelineName;

  @override
  State<PenPaperBaselineWidget> createState() => _PenPaperBaselineWidgetState();
}

class _PenPaperBaselineWidgetState extends State<PenPaperBaselineWidget> {
  late bool _isGranular;

  late TextEditingController _wholeInputCtrl;
  late TextEditingController _wholeOutputCtrl;
  late TextEditingController _wholeScrapCtrl;
  late TextEditingController _wholeRejectionCtrl;
  late TextEditingController _wholeLossCtrl;
  late TextEditingController _wholeNotesCtrl;

  bool _wholeRecordScrap = true;
  bool _wholeRecordRejection = true;
  bool _wholeRecordWeightLoss = true;

  @override
  void initState() {
    super.initState();
    _isGranular = widget.baseline.isGranular;
    _initWholePipelineControllers();
    _ensureStageReconciliations();
  }

  @override
  void didUpdateWidget(PenPaperBaselineWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stageNames != oldWidget.stageNames) {
      _ensureStageReconciliations();
    }
  }

  void _initWholePipelineControllers() {
    final first = widget.baseline.stageReconciliations.isNotEmpty
        ? widget.baseline.stageReconciliations.first
        : const PenPaperStageReconciliation(
            stageId: 'whole_pipeline',
            stageName: 'Entire Pipeline',
            inputKg: 100.0,
            outputKg: 90.0,
            scrapKg: 5.0,
            rejectionKg: 3.0,
            weightLossKg: 2.0,
          );

    _wholeRecordScrap = first.recordScrap;
    _wholeRecordRejection = first.recordRejection;
    _wholeRecordWeightLoss = first.recordWeightLoss;

    _wholeInputCtrl = TextEditingController(text: _kg(first.inputKg));
    _wholeOutputCtrl = TextEditingController(text: _kg(first.outputKg));
    _wholeScrapCtrl = TextEditingController(text: _kg(first.scrapKg));
    _wholeRejectionCtrl = TextEditingController(text: _kg(first.rejectionKg));
    _wholeLossCtrl = TextEditingController(text: _kg(first.weightLossKg));
    _wholeNotesCtrl = TextEditingController(
      text: first.notes.isNotEmpty ? first.notes : widget.baseline.notes,
    );
  }

  static String _kg(double value) => value.toStringAsFixed(1);

  /// Records which pipeline the weights were measured on. Only stamps when a
  /// pipeline is actually selected, so an unattached record keeps whatever it
  /// already had rather than being blanked.
  PenPaperBaseline _stamped(PenPaperBaseline baseline) {
    if (widget.pipelineId == null || widget.pipelineId!.trim().isEmpty) {
      return baseline;
    }
    return baseline.copyWith(
      pipelineId: widget.pipelineId,
      pipelineName: widget.pipelineName,
    );
  }

  /// True when the record was captured on a different pipeline than the one the
  /// item now uses — the yields no longer describe the current route.
  bool get _pipelineDrifted {
    final recorded = widget.baseline.pipelineId;
    final current = widget.pipelineId;
    if (recorded == null || recorded.isEmpty) return false;
    if (current == null || current.isEmpty) return false;
    return recorded != current;
  }

  @override
  void dispose() {
    _wholeInputCtrl.dispose();
    _wholeOutputCtrl.dispose();
    _wholeScrapCtrl.dispose();
    _wholeRejectionCtrl.dispose();
    _wholeLossCtrl.dispose();
    _wholeNotesCtrl.dispose();
    super.dispose();
  }

  void _ensureStageReconciliations() {
    final currentList = widget.baseline.stageReconciliations;
    final stages = widget.stageNames.isNotEmpty
        ? widget.stageNames
        : const ['Stage 1 (Cutting)', 'Stage 2 (Molding)', 'Stage 3 (Finishing)'];

    if (currentList.isEmpty ||
        (_isGranular && currentList.length != stages.length)) {
      final newBaseline = PenPaperBaseline.createDefaultForStages(
        stages,
      ).copyWith(isGranular: _isGranular);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onChanged(_stamped(newBaseline));
      });
    }
  }

  void _saveWholePipelineBaseline() {
    final inputKg = double.tryParse(_wholeInputCtrl.text) ?? 100.0;
    final outputKg = double.tryParse(_wholeOutputCtrl.text) ?? 90.0;
    final scrapKg = _wholeRecordScrap
        ? (double.tryParse(_wholeScrapCtrl.text) ?? 0.0)
        : 0.0;
    final rejectionKg = _wholeRecordRejection
        ? (double.tryParse(_wholeRejectionCtrl.text) ?? 0.0)
        : 0.0;
    final weightLossKg = _wholeRecordWeightLoss
        ? (double.tryParse(_wholeLossCtrl.text) ?? 0.0)
        : 0.0;
    final notes = _wholeNotesCtrl.text.trim();

    final singleReconciliation = PenPaperStageReconciliation(
      stageId: 'whole_pipeline',
      stageName: 'Entire Pipeline',
      recordScrap: _wholeRecordScrap,
      recordRejection: _wholeRecordRejection,
      recordWeightLoss: _wholeRecordWeightLoss,
      inputKg: inputKg,
      outputKg: outputKg,
      scrapKg: scrapKg,
      rejectionKg: rejectionKg,
      weightLossKg: weightLossKg,
      notes: notes,
    );

    widget.onChanged(
      _stamped(
        widget.baseline.copyWith(
          isGranular: false,
          stageReconciliations: [singleReconciliation],
          notes: notes,
        ),
      ),
    );
  }

  void _updateStageReconciliation(
    int index,
    PenPaperStageReconciliation updated,
  ) {
    final list = List<PenPaperStageReconciliation>.from(
      widget.baseline.stageReconciliations,
    );
    if (index >= 0 && index < list.length) {
      list[index] = updated;

      // Carry forward output kg to next stage input kg
      if (index + 1 < list.length) {
        final nextStage = list[index + 1];
        list[index + 1] = nextStage.copyWith(inputKg: updated.outputKg);
      }

      widget.onChanged(
        _stamped(
          widget.baseline.copyWith(isGranular: true, stageReconciliations: list),
        ),
      );
    }
  }

  /// The current whole-pipeline entry, read straight off the controllers so the
  /// balance strip tracks typing rather than the last committed value.
  PenPaperStageReconciliation get _wholeDraft => PenPaperStageReconciliation(
    stageId: 'whole_pipeline',
    stageName: 'Entire Pipeline',
    recordScrap: _wholeRecordScrap,
    recordRejection: _wholeRecordRejection,
    recordWeightLoss: _wholeRecordWeightLoss,
    inputKg: double.tryParse(_wholeInputCtrl.text) ?? 0,
    outputKg: double.tryParse(_wholeOutputCtrl.text) ?? 0,
    scrapKg: double.tryParse(_wholeScrapCtrl.text) ?? 0,
    rejectionKg: double.tryParse(_wholeRejectionCtrl.text) ?? 0,
    weightLossKg: double.tryParse(_wholeLossCtrl.text) ?? 0,
  );

  // --- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final stages = widget.baseline.stageReconciliations;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showChrome) ...[
          _buildHeader(),
          const SizedBox(height: 14),
        ] else ...[
          Align(alignment: Alignment.centerLeft, child: _buildModeToggle()),
          const SizedBox(height: 14),
        ],
        _buildAttachmentStrip(),
        const SizedBox(height: 12),
        if (!_isGranular)
          _buildWholePipelineForm()
        else
          _buildStageByStageForm(stages),
      ],
    );

    if (!widget.showChrome) {
      return body;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: body,
    );
  }

  /// Says what this record is attached to. A sample baseline is only meaningful
  /// against a route, so the pipeline is stated rather than implied.
  Widget _buildAttachmentStrip() {
    final attached =
        widget.pipelineId != null && widget.pipelineId!.trim().isNotEmpty;
    final recordedName = widget.baseline.pipelineName.trim();
    final drifted = _pipelineDrifted;

    final (Color tone, Color toneBg, IconData icon, String text) = !attached
        ? (
            SoftErpTheme.warningText,
            SoftErpTheme.warningBg,
            Icons.link_off_rounded,
            'Not attached to a pipeline — pick a default pipeline so stages '
                'and yields have a route to describe.',
          )
        : drifted
        ? (
            SoftErpTheme.warningText,
            SoftErpTheme.warningBg,
            Icons.warning_amber_rounded,
            'Recorded on ${recordedName.isEmpty ? 'another pipeline' : recordedName}, '
                'but this item now runs on ${widget.pipelineName}. Re-record to '
                'match the current route.',
          )
        : (
            SoftErpTheme.infoText,
            SoftErpTheme.infoBg,
            Icons.account_tree_outlined,
            'Attached to ${widget.pipelineName}',
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: toneBg,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(color: tone.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: tone,
                fontSize: 11.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: SoftErpTheme.accentSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.science_outlined,
            color: SoftErpTheme.accent,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sample Baseline Record',
                style: TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Weights from a trial run, in kilograms, for yield calculations.',
                style: TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _buildModeToggle(),
      ],
    );
  }

  Widget _buildModeToggle() {
    return IgnorePointer(
      ignoring: widget.readOnly,
      child: Opacity(
        opacity: widget.readOnly ? 0.55 : 1,
        child: PMFigmaSegmentedControl(
          variant: PMFigmaSegmentedControlVariant.soft,
          segmentWidth: 128,
          segmentHeight: 32,
          labelFontSize: 12.5,
          semanticLabel: 'Baseline detail level',
          value: _isGranular ? 'granular' : 'whole',
          segments: const [
            PMFigmaSegmentOption(key: 'whole', label: 'Whole Pipeline'),
            PMFigmaSegmentOption(key: 'granular', label: 'Stage by Stage'),
          ],
          onChanged: (key) {
            setState(() => _isGranular = key == 'granular');
            if (_isGranular) {
              _ensureStageReconciliations();
            } else {
              _saveWholePipelineBaseline();
            }
          },
        ),
      ),
    );
  }

  // --- whole pipeline ------------------------------------------------------

  Widget _buildWholePipelineForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 420;
            final input = _kgField(
              controller: _wholeInputCtrl,
              label: 'Input material',
              hint: '100.0',
              onChanged: _saveWholePipelineBaseline,
            );
            final output = _kgField(
              controller: _wholeOutputCtrl,
              label: 'Good output',
              hint: '90.0',
              onChanged: _saveWholePipelineBaseline,
            );
            if (stacked) {
              return Column(
                children: [input, const SizedBox(height: 10), output],
              );
            }
            return Row(
              children: [
                Expanded(child: input),
                const SizedBox(width: 12),
                Expanded(child: output),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        _fieldLabel('Account for'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _LossToggle(
              label: 'Scrap',
              selected: _wholeRecordScrap,
              onTap: widget.readOnly
                  ? null
                  : () {
                      setState(() => _wholeRecordScrap = !_wholeRecordScrap);
                      _saveWholePipelineBaseline();
                    },
            ),
            _LossToggle(
              label: 'Rejection',
              selected: _wholeRecordRejection,
              onTap: widget.readOnly
                  ? null
                  : () {
                      setState(
                        () => _wholeRecordRejection = !_wholeRecordRejection,
                      );
                      _saveWholePipelineBaseline();
                    },
            ),
            _LossToggle(
              label: 'Weight loss',
              selected: _wholeRecordWeightLoss,
              onTap: widget.readOnly
                  ? null
                  : () {
                      setState(
                        () => _wholeRecordWeightLoss = !_wholeRecordWeightLoss,
                      );
                      _saveWholePipelineBaseline();
                    },
            ),
          ],
        ),
        if (_wholeRecordScrap ||
            _wholeRecordRejection ||
            _wholeRecordWeightLoss) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              if (_wholeRecordScrap)
                SizedBox(
                  width: 168,
                  child: _kgField(
                    controller: _wholeScrapCtrl,
                    label: 'Scrap',
                    hint: '0.0',
                    onChanged: _saveWholePipelineBaseline,
                  ),
                ),
              if (_wholeRecordRejection)
                SizedBox(
                  width: 168,
                  child: _kgField(
                    controller: _wholeRejectionCtrl,
                    label: 'Rejection',
                    hint: '0.0',
                    onChanged: _saveWholePipelineBaseline,
                  ),
                ),
              if (_wholeRecordWeightLoss)
                SizedBox(
                  width: 168,
                  child: _kgField(
                    controller: _wholeLossCtrl,
                    label: 'Weight loss',
                    hint: '0.0',
                    onChanged: _saveWholePipelineBaseline,
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        _BalanceStrip(entry: _wholeDraft),
        const SizedBox(height: 12),
        _notesField(
          controller: _wholeNotesCtrl,
          onChanged: _saveWholePipelineBaseline,
        ),
      ],
    );
  }

  // --- stage by stage ------------------------------------------------------

  Widget _buildStageByStageForm(List<PenPaperStageReconciliation> stages) {
    if (stages.isEmpty) {
      return const Text(
        'No stages to record yet.',
        style: TextStyle(color: SoftErpTheme.textSecondary, fontSize: 12.5),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < stages.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          _StageRow(
            index: index,
            stage: stages[index],
            readOnly: widget.readOnly,
            onEdit: () => _openStageEditor(index),
          ),
        ],
      ],
    );
  }

  Future<void> _openStageEditor(int index) async {
    final stages = widget.baseline.stageReconciliations;
    if (index < 0 || index >= stages.length) return;
    final updated = await showErpFormDialog<PenPaperStageReconciliation>(
      context,
      maxWidth: 560,
      maxHeight: 720,
      child: _StageEditorDialog(
        index: index,
        stageCount: stages.length,
        stage: stages[index],
      ),
    );
    if (updated == null || !mounted) return;
    _updateStageReconciliation(index, updated);
  }
}

// --- shared field styling ---------------------------------------------------

Widget _fieldLabel(String text) => Text(
  text.toUpperCase(),
  style: const TextStyle(
    color: SoftErpTheme.textSecondary,
    fontSize: 10,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.6,
  ),
);

InputDecoration _softDecoration({
  required String label,
  String? hint,
  String? suffix,
}) {
  OutlineInputBorder border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: color),
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixText: suffix,
    isDense: true,
    filled: true,
    fillColor: SoftErpTheme.cardSurfaceAlt,
    labelStyle: const TextStyle(
      color: SoftErpTheme.textSecondary,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
    hintStyle: const TextStyle(
      color: SoftErpTheme.textSecondary,
      fontSize: 13,
    ),
    suffixStyle: const TextStyle(
      color: SoftErpTheme.textSecondary,
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    border: border(SoftErpTheme.border),
    enabledBorder: border(SoftErpTheme.border),
    focusedBorder: border(SoftErpTheme.accent),
  );
}

Widget _kgField({
  required TextEditingController controller,
  required String label,
  required String hint,
  required VoidCallback onChanged,
  bool enabled = true,
  String? Function(String?)? validator,
}) {
  return TextFormField(
    controller: controller,
    enabled: enabled,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'^[0-9]*\.?[0-9]*')),
    ],
    style: const TextStyle(
      color: SoftErpTheme.textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
    decoration: _softDecoration(label: label, hint: hint, suffix: 'kg'),
    validator: validator,
    onChanged: (_) => onChanged(),
  );
}

Widget _notesField({
  required TextEditingController controller,
  required VoidCallback onChanged,
  bool enabled = true,
}) {
  return TextFormField(
    controller: controller,
    enabled: enabled,
    maxLines: 2,
    style: const TextStyle(color: SoftErpTheme.textPrimary, fontSize: 13.5),
    decoration: _softDecoration(
      label: 'Notes',
      hint: 'e.g. Sample production trial from batch #1',
    ),
    onChanged: (_) => onChanged(),
  );
}

/// Pill toggle for which loss categories this record accounts for.
class _LossToggle extends StatelessWidget {
  const _LossToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? SoftErpTheme.accentSoft
                : SoftErpTheme.cardSurfaceAlt,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? SoftErpTheme.accent : SoftErpTheme.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 15,
                color: selected
                    ? SoftErpTheme.accent
                    : SoftErpTheme.textSecondary,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? SoftErpTheme.accentDeeper
                      : SoftErpTheme.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Yield and mass balance for the entry being edited. Recording input, output
/// and losses that do not add up is the mistake this record exists to catch, so
/// the discrepancy is shown rather than left to be derived later.
class _BalanceStrip extends StatelessWidget {
  const _BalanceStrip({required this.entry});

  final PenPaperStageReconciliation entry;

  @override
  Widget build(BuildContext context) {
    final delta = entry.balanceDeltaKg;
    final balanced = delta.abs() < 0.05;
    final tone = balanced ? SoftErpTheme.successText : SoftErpTheme.warningText;
    final toneBg = balanced ? SoftErpTheme.successBg : SoftErpTheme.warningBg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Wrap(
        spacing: 22,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _metric('Yield', '${entry.yieldPercentage.toStringAsFixed(1)}%'),
          _metric('Accounted', '${entry.totalAccountedKg.toStringAsFixed(1)} kg'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: toneBg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: tone.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  balanced
                      ? Icons.check_circle_rounded
                      : Icons.error_outline_rounded,
                  size: 14,
                  color: tone,
                ),
                const SizedBox(width: 6),
                Text(
                  balanced
                      ? 'Balances'
                      : '${delta > 0 ? 'Unaccounted' : 'Over-accounted'} '
                            '${delta.abs().toStringAsFixed(1)} kg',
                  style: TextStyle(
                    color: tone,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: SoftErpTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// One stage summary row in stage-by-stage mode.
class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.index,
    required this.stage,
    required this.readOnly,
    required this.onEdit,
  });

  final int index;
  final PenPaperStageReconciliation stage;
  final bool readOnly;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final delta = stage.balanceDeltaKg;
    final balanced = delta.abs() < 0.05;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: SoftErpTheme.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: SoftErpTheme.accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stage.stageName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${stage.inputKg.toStringAsFixed(1)} kg in · '
                  '${stage.outputKg.toStringAsFixed(1)} kg out · '
                  '${stage.yieldPercentage.toStringAsFixed(1)}% yield',
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          if (!balanced) ...[
            const SizedBox(width: 8),
            Tooltip(
              message:
                  '${delta.abs().toStringAsFixed(1)} kg '
                  '${delta > 0 ? 'unaccounted for' : 'over-accounted'}',
              child: const Icon(
                Icons.error_outline_rounded,
                size: 16,
                color: SoftErpTheme.warningText,
              ),
            ),
          ],
          if (!readOnly) ...[
            const SizedBox(width: 6),
            TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 15),
              label: const Text('Edit'),
              style: TextButton.styleFrom(
                foregroundColor: SoftErpTheme.accent,
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Stage editor, on the app's form-dialog scaffold rather than a raw
/// AlertDialog. Pops the edited entry, or null when cancelled.
class _StageEditorDialog extends StatefulWidget {
  const _StageEditorDialog({
    required this.index,
    required this.stageCount,
    required this.stage,
  });

  final int index;
  final int stageCount;
  final PenPaperStageReconciliation stage;

  @override
  State<_StageEditorDialog> createState() => _StageEditorDialogState();
}

class _StageEditorDialogState extends State<_StageEditorDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _inputCtrl;
  late final TextEditingController _outputCtrl;
  late final TextEditingController _scrapCtrl;
  late final TextEditingController _rejectionCtrl;
  late final TextEditingController _lossCtrl;
  late final TextEditingController _notesCtrl;

  late bool _recordScrap;
  late bool _recordRejection;
  late bool _recordWeightLoss;

  @override
  void initState() {
    super.initState();
    final stage = widget.stage;
    _recordScrap = stage.recordScrap;
    _recordRejection = stage.recordRejection;
    _recordWeightLoss = stage.recordWeightLoss;
    _inputCtrl = TextEditingController(text: stage.inputKg.toStringAsFixed(1));
    _outputCtrl = TextEditingController(text: stage.outputKg.toStringAsFixed(1));
    _scrapCtrl = TextEditingController(text: stage.scrapKg.toStringAsFixed(1));
    _rejectionCtrl = TextEditingController(
      text: stage.rejectionKg.toStringAsFixed(1),
    );
    _lossCtrl = TextEditingController(
      text: stage.weightLossKg.toStringAsFixed(1),
    );
    _notesCtrl = TextEditingController(text: stage.notes);
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _outputCtrl.dispose();
    _scrapCtrl.dispose();
    _rejectionCtrl.dispose();
    _lossCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  PenPaperStageReconciliation get _draft => widget.stage.copyWith(
    recordScrap: _recordScrap,
    recordRejection: _recordRejection,
    recordWeightLoss: _recordWeightLoss,
    inputKg: double.tryParse(_inputCtrl.text) ?? 0,
    outputKg: double.tryParse(_outputCtrl.text) ?? 0,
    scrapKg: _recordScrap ? (double.tryParse(_scrapCtrl.text) ?? 0) : 0,
    rejectionKg: _recordRejection
        ? (double.tryParse(_rejectionCtrl.text) ?? 0)
        : 0,
    weightLossKg: _recordWeightLoss ? (double.tryParse(_lossCtrl.text) ?? 0) : 0,
    notes: _notesCtrl.text.trim(),
  );

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(context).pop(_draft);
  }

  @override
  Widget build(BuildContext context) {
    return ErpFormScaffold(
      title: 'Stage ${widget.index + 1} · ${widget.stage.stageName}',
      subtitle: 'Record this stage\'s material quantities in kilograms.',
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _kgField(
                    controller: _inputCtrl,
                    label: 'Input material',
                    hint: '100.0',
                    onChanged: () => setState(() {}),
                    validator: (value) {
                      final parsed = double.tryParse(value ?? '');
                      if (parsed == null || parsed <= 0) {
                        return 'Enter a weight above 0';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _kgField(
                    controller: _outputCtrl,
                    label: 'Good output',
                    hint: '90.0',
                    onChanged: () => setState(() {}),
                    validator: (value) => double.tryParse(value ?? '') == null
                        ? 'Enter a weight'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _fieldLabel('Account for'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _LossToggle(
                  label: 'Scrap',
                  selected: _recordScrap,
                  onTap: () => setState(() => _recordScrap = !_recordScrap),
                ),
                _LossToggle(
                  label: 'Rejection',
                  selected: _recordRejection,
                  onTap: () =>
                      setState(() => _recordRejection = !_recordRejection),
                ),
                _LossToggle(
                  label: 'Weight loss',
                  selected: _recordWeightLoss,
                  onTap: () =>
                      setState(() => _recordWeightLoss = !_recordWeightLoss),
                ),
              ],
            ),
            if (_recordScrap || _recordRejection || _recordWeightLoss) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  if (_recordScrap)
                    SizedBox(
                      width: 152,
                      child: _kgField(
                        controller: _scrapCtrl,
                        label: 'Scrap',
                        hint: '0.0',
                        onChanged: () => setState(() {}),
                      ),
                    ),
                  if (_recordRejection)
                    SizedBox(
                      width: 152,
                      child: _kgField(
                        controller: _rejectionCtrl,
                        label: 'Rejection',
                        hint: '0.0',
                        onChanged: () => setState(() {}),
                      ),
                    ),
                  if (_recordWeightLoss)
                    SizedBox(
                      width: 152,
                      child: _kgField(
                        controller: _lossCtrl,
                        label: 'Weight loss',
                        hint: '0.0',
                        onChanged: () => setState(() {}),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            _BalanceStrip(entry: _draft),
            const SizedBox(height: 14),
            _notesField(
              controller: _notesCtrl,
              onChanged: () => setState(() {}),
            ),
          ],
        ),
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: widget.index + 1 < widget.stageCount
                ? 'Save stage'
                : 'Save stage',
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
