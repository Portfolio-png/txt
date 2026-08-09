import 'package:flutter/material.dart';
import '../../domain/pen_paper_baseline.dart';

/// Pure write-only record widget for capturing sample/historical baseline material flow.
/// Supports switching between [Whole Pipeline] (abstract) and [Stage by Stage] (granular) modes.
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

    _wholeInputCtrl = TextEditingController(text: first.inputKg.toStringAsFixed(1));
    _wholeOutputCtrl = TextEditingController(text: first.outputKg.toStringAsFixed(1));
    _wholeScrapCtrl = TextEditingController(text: first.scrapKg.toStringAsFixed(1));
    _wholeRejectionCtrl = TextEditingController(text: first.rejectionKg.toStringAsFixed(1));
    _wholeLossCtrl = TextEditingController(text: first.weightLossKg.toStringAsFixed(1));
    _wholeNotesCtrl = TextEditingController(text: first.notes.isNotEmpty ? first.notes : widget.baseline.notes);
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

    if (currentList.isEmpty || (_isGranular && currentList.length != stages.length)) {
      final newBaseline = PenPaperBaseline.createDefaultForStages(stages).copyWith(isGranular: _isGranular);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onChanged(newBaseline);
      });
    }
  }

  void _saveWholePipelineBaseline() {
    final inputKg = double.tryParse(_wholeInputCtrl.text) ?? 100.0;
    final outputKg = double.tryParse(_wholeOutputCtrl.text) ?? 90.0;
    final scrapKg = _wholeRecordScrap ? (double.tryParse(_wholeScrapCtrl.text) ?? 0.0) : 0.0;
    final rejectionKg = _wholeRecordRejection ? (double.tryParse(_wholeRejectionCtrl.text) ?? 0.0) : 0.0;
    final weightLossKg = _wholeRecordWeightLoss ? (double.tryParse(_wholeLossCtrl.text) ?? 0.0) : 0.0;
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
      widget.baseline.copyWith(
        isGranular: false,
        stageReconciliations: [singleReconciliation],
        notes: notes,
      ),
    );
  }

  void _updateStageReconciliation(int index, PenPaperStageReconciliation updated) {
    final list = List<PenPaperStageReconciliation>.from(widget.baseline.stageReconciliations);
    if (index >= 0 && index < list.length) {
      list[index] = updated;

      // Carry forward output kg to next stage input kg
      if (index + 1 < list.length) {
        final nextStage = list[index + 1];
        list[index + 1] = nextStage.copyWith(inputKg: updated.outputKg);
      }

      widget.onChanged(
        widget.baseline.copyWith(
          isGranular: true,
          stageReconciliations: list,
        ),
      );
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
                      'Stage ${index + 1}: ${current.stageName}',
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
                        'Record material quantities in kilograms (kg):',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 14),

                      // Input & Good Output
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: inputCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Input Material (kg)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (v) => (double.tryParse(v ?? '') == null || (double.tryParse(v ?? '')! <= 0))
                                  ? 'Enter valid kg'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: outputCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Good Output (kg)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (v) => (double.tryParse(v ?? '') == null) ? 'Enter valid kg' : null,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        'Process Losses & Reconciliations:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),

                      // Scrap Checkbox & Field
                      CheckboxListTile(
                        value: recordScrap,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Record Scrap Loss'),
                        onChanged: (v) => setModalState(() => recordScrap = v ?? true),
                      ),
                      if (recordScrap) ...[
                        TextFormField(
                          controller: scrapCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Scrap (kg)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // Rejection Checkbox & Field
                      CheckboxListTile(
                        value: recordRejection,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Record Rejection'),
                        onChanged: (v) => setModalState(() => recordRejection = v ?? true),
                      ),
                      if (recordRejection) ...[
                        TextFormField(
                          controller: rejectionCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Rejection (kg)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // Weight Loss Checkbox & Field
                      CheckboxListTile(
                        value: recordWeightLoss,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Record Process / Weight Loss'),
                        onChanged: (v) => setModalState(() => recordWeightLoss = v ?? true),
                      ),
                      if (recordWeightLoss) ...[
                        TextFormField(
                          controller: lossCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Weight Loss (kg)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      const SizedBox(height: 10),
                      TextFormField(
                        controller: notesCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          border: OutlineInputBorder(),
                          isDense: true,
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
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() == true) {
                      final updated = current.copyWith(
                        recordScrap: recordScrap,
                        recordRejection: recordRejection,
                        recordWeightLoss: recordWeightLoss,
                        inputKg: double.tryParse(inputCtrl.text) ?? current.inputKg,
                        outputKg: double.tryParse(outputCtrl.text) ?? current.outputKg,
                        scrapKg: recordScrap ? (double.tryParse(scrapCtrl.text) ?? 0.0) : 0.0,
                        rejectionKg: recordRejection ? (double.tryParse(rejectionCtrl.text) ?? 0.0) : 0.0,
                        weightLossKg: recordWeightLoss ? (double.tryParse(lossCtrl.text) ?? 0.0) : 0.0,
                        notes: notesCtrl.text.trim(),
                      );
                      _updateStageReconciliation(index, updated);
                      Navigator.pop(ctx);
                    }
                  },
                  child: Text(index + 1 < stages.length ? 'Save & Next Stage ➔' : 'Save Stage'),
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mode Toggle Header: Whole Pipeline vs Stage by Stage
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E88E5).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.tune_rounded, color: Color(0xFF1E88E5), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sample Baseline Record',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    Text(
                      'Record sample baseline in kilograms (kg) for yield calculations',
                      style: TextStyle(color: theme.hintColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Toggle button
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Whole Pipeline'),
                    icon: Icon(Icons.all_inclusive_rounded, size: 16),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Stage by Stage'),
                    icon: Icon(Icons.format_list_numbered_rounded, size: 16),
                  ),
                ],
                selected: {_isGranular},
                onSelectionChanged: widget.readOnly
                    ? null
                    : (newSelection) {
                        setState(() {
                          _isGranular = newSelection.first;
                        });
                        if (_isGranular) {
                          _ensureStageReconciliations();
                        } else {
                          _saveWholePipelineBaseline();
                        }
                      },
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Render selected mode
          if (!_isGranular)
            _buildWholePipelineForm(theme)
          else
            _buildStageByStageForm(theme, stages),
        ],
      ),
    );
  }

  Widget _buildWholePipelineForm(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _wholeInputCtrl,
                enabled: !widget.readOnly,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Input Material (kg)',
                  hintText: 'e.g. 100.0',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => _saveWholePipelineBaseline(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _wholeOutputCtrl,
                enabled: !widget.readOnly,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Good Output (kg)',
                  hintText: 'e.g. 90.0',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => _saveWholePipelineBaseline(),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Losses & checkboxes
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              label: const Text('Scrap'),
              selected: _wholeRecordScrap,
              onSelected: widget.readOnly
                  ? null
                  : (v) {
                      setState(() => _wholeRecordScrap = v);
                      _saveWholePipelineBaseline();
                    },
            ),
            FilterChip(
              label: const Text('Rejection'),
              selected: _wholeRecordRejection,
              onSelected: widget.readOnly
                  ? null
                  : (v) {
                      setState(() => _wholeRecordRejection = v);
                      _saveWholePipelineBaseline();
                    },
            ),
            FilterChip(
              label: const Text('Weight Loss'),
              selected: _wholeRecordWeightLoss,
              onSelected: widget.readOnly
                  ? null
                  : (v) {
                      setState(() => _wholeRecordWeightLoss = v);
                      _saveWholePipelineBaseline();
                    },
            ),
          ],
        ),

        const SizedBox(height: 10),

        // Numeric loss fields if selected
        Row(
          children: [
            if (_wholeRecordScrap) ...[
              Expanded(
                child: TextFormField(
                  controller: _wholeScrapCtrl,
                  enabled: !widget.readOnly,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Scrap (kg)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _saveWholePipelineBaseline(),
                ),
              ),
              const SizedBox(width: 10),
            ],
            if (_wholeRecordRejection) ...[
              Expanded(
                child: TextFormField(
                  controller: _wholeRejectionCtrl,
                  enabled: !widget.readOnly,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Rejection (kg)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _saveWholePipelineBaseline(),
                ),
              ),
              const SizedBox(width: 10),
            ],
            if (_wholeRecordWeightLoss) ...[
              Expanded(
                child: TextFormField(
                  controller: _wholeLossCtrl,
                  enabled: !widget.readOnly,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Weight Loss (kg)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _saveWholePipelineBaseline(),
                ),
              ),
            ],
          ],
        ),

        const SizedBox(height: 10),

        TextFormField(
          controller: _wholeNotesCtrl,
          enabled: !widget.readOnly,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            hintText: 'e.g. Sample production trial from batch #1',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => _saveWholePipelineBaseline(),
        ),
      ],
    );
  }

  Widget _buildStageByStageForm(ThemeData theme, List<PenPaperStageReconciliation> stages) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stages.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final stage = stages[index];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark ? Colors.grey.shade900 : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: const Color(0xFF1E88E5).withValues(alpha: 0.15),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E88E5)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stage.stageName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        Text(
                          'In: ${stage.inputKg.toStringAsFixed(1)} kg ➔ Out: ${stage.outputKg.toStringAsFixed(1)} kg | Yield: ${stage.yieldPercentage.toStringAsFixed(1)}%',
                          style: TextStyle(fontSize: 11, color: theme.hintColor),
                        ),
                      ],
                    ),
                  ),
                  if (!widget.readOnly)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      ),
                      onPressed: () => _openStageEditorModal(index),
                      icon: const Icon(Icons.edit_note_rounded, size: 16),
                      label: const Text('Edit Stage'),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
