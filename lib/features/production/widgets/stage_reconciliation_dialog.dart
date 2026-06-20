import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/domain/inventory_control_tower.dart';

import 'package:core_erp/shared/widgets/exact_item_variation_select_field.dart';
import 'output_item_picker_dialog.dart';

import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/material_batch.dart';
import '../../production_pipelines/domain/pipeline_run.dart';
import '../../production_pipelines/domain/process_node.dart';
import '../domain/utils/stage_input_resolver.dart';
import '../providers/production_provider.dart';
import '../providers/production_run_provider.dart';

/// Asks the engineer to account for the difference between the material
/// allotted to a stage and the stage's output. The difference can only be
/// split between leftover material and scrap. Scrap ships to the stage's
/// configured scrap item (an item in the "Scrap" item group); leftover is
/// either returned to inventory as the original material or scrapped too.
class StageReconciliationDialog extends StatefulWidget {
  const StageReconciliationDialog({
    super.key,
    required this.node,
    required this.runId,
    this.batchOutput,
    this.batchAllottedMax,
    this.batchReconcileQty,
    this.batchUnit,
    this.batchBarcode,
    this.batchLabel,
    this.onCommitted,
    this.onClose,
  });

  final ProcessNode node;
  final String runId;

  /// e.g. "Batch 2" — shown in the title so the centred popout says which
  /// batch it reconciles. Null for a whole-stage reconcile.
  final String? batchLabel;

  /// When set, the widget renders inline (no Dialog chrome) and calls [onClose]
  /// instead of popping a route on commit/cancel. Used by the strip that opens
  /// above the stages on double-click.
  final VoidCallback? onClose;

  /// When set (double-clicking a parked batch), reconciles that batch at rest:
  /// input material is fixed to the batch quantity and output is editable.
  final double? batchReconcileQty;

  /// When set, the dialog runs in batch mode: [batchOutput] is the quantity
  /// that just advanced out of this stage (locked as the output), allotted is
  /// editable up to [batchAllottedMax] (the source chip's original size), and
  /// the unit/barcode come from the moved batch. [onCommitLoss] is invoked with
  /// the reconciled loss (allotted − output) so the caller can deduct it from
  /// the source chip.
  final double? batchOutput;
  final double? batchAllottedMax;
  final String? batchUnit;
  final String? batchBarcode;
  final ValueChanged<ReconcileResult>? onCommitted;

  static Future<bool?> show(
    BuildContext context, {
    required ProcessNode node,
    required String runId,
    double? batchOutput,
    double? batchAllottedMax,
    String? batchUnit,
    String? batchBarcode,
    ValueChanged<ReconcileResult>? onCommitted,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => StageReconciliationDialog(
        node: node,
        runId: runId,
        batchOutput: batchOutput,
        batchAllottedMax: batchAllottedMax,
        batchUnit: batchUnit,
        batchBarcode: batchBarcode,
        onCommitted: onCommitted,
      ),
    );
  }

  @override
  State<StageReconciliationDialog> createState() =>
      _StageReconciliationDialogState();
}

class _StageReconciliationDialogState extends State<StageReconciliationDialog> {
  final _allottedCtrl = TextEditingController();
  final _outputCtrl = TextEditingController();
  final _leftoverCtrl = TextEditingController();
  final _scrapCtrl = TextEditingController();

  PipelineRun? _run;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isCommitting = false;
  bool _allottedFromBarcodes = false;
  String _unit = '';
  String? _firstBarcode;
  final LeftoverAction _leftoverAction = LeftoverAction.returnToInventory;
  String? _errorText;

  // Manual event times — operators logging from paper enter when material
  // actually entered/left the stage rather than relying on the PC clock.
  // Input time defaults to the upstream stage's output time (carried forward,
  // still editable); it can't predate the upstream stage's input time.
  DateTime _inputTime = DateTime.now();
  DateTime _outputTime = DateTime.now();
  DateTime? _inputFloor;

  @override
  void initState() {
    super.initState();
    _load();
  }


  @override
  void didUpdateWidget(StageReconciliationDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.node.id != oldWidget.node.id || widget.runId != oldWidget.runId) {
      setState(() {
        _isRefreshing = true;
      });
      _load();
    }
  }

  @override
  void dispose() {
    _allottedCtrl.dispose();
    _outputCtrl.dispose();
    _leftoverCtrl.dispose();
    _scrapCtrl.dispose();
    super.dispose();
  }

  bool get _isOutputStage {
    try {
      final template = context.read<ProductionProvider>().template;
      if (template == null) return false;
      return !template.flows.any((f) => f.fromNodeId == widget.node.id);
    } catch (_) {
      return false;
    }
  }

  Future<void> _load() async {
    try {
      final repo = context.read<PipelineRunRepository>();
      final template = context.read<ProductionProvider>().template;
      final run = await repo.getRun(widget.runId);
      if (!mounted) return;
      final inputs = effectiveStageInputs(
        run: run,
        node: widget.node,
        template: template,
      );
      double allotted = 0;
      for (final input in inputs) {
        allotted += input.quantity ?? 0;
      }
      final metrics = run?.nodeMetrics[widget.node.id] ?? const {};

      // Default the event times: carry the upstream stage's output time into
      // this stage's input time; the floor is the upstream input time.
      DateTime? upstreamOutput;
      DateTime? upstreamInput;
      for (final flow in template.flows) {
        if (flow.toNodeId != widget.node.id) continue;
        final m = run?.nodeMetrics[flow.fromNodeId] ?? const {};
        final o = _parseTime(m['outputTime']);
        final i = _parseTime(m['inputTime']);
        if (o != null && (upstreamOutput == null || o.isAfter(upstreamOutput))) {
          upstreamOutput = o;
        }
        if (i != null && (upstreamInput == null || i.isAfter(upstreamInput))) {
          upstreamInput = i;
        }
      }
      final existingInput = _parseTime(metrics['inputTime']);
      final existingOutput = _parseTime(metrics['outputTime']);

      setState(() {
        _run = run;
        _isLoading = false;
        _isRefreshing = false;
        _inputFloor = upstreamInput;
        _inputTime =
            existingInput ?? upstreamOutput ?? run?.startedAt ?? DateTime.now();
        _outputTime = existingOutput ?? DateTime.now();
        if (_batchMode) {
          // The moved quantity is the (locked) output; allotted is editable
          // from there up to the source chip's original size.
          final moved = widget.batchOutput!;
          _allottedFromBarcodes = false;
          _firstBarcode = widget.batchBarcode;
          _unit = widget.batchUnit?.isNotEmpty == true
              ? widget.batchUnit!
              : (inputs.isNotEmpty
                    ? (inputs.first.unit ?? '')
                    : (widget.node.inputItem?.unitSymbol ?? ''));
          _outputCtrl.text = fmtQty(moved);
          _allottedCtrl.text = fmtQty(moved);
        } else if (_batchReconcileMode) {
          // Reconcile a parked batch: input fixed to the batch quantity,
          // output editable (defaults to the full quantity).
          final qty = widget.batchReconcileQty!;
          _allottedFromBarcodes = true; // input material is read-only here
          _firstBarcode = widget.batchBarcode;
          _unit = widget.batchUnit?.isNotEmpty == true
              ? widget.batchUnit!
              : (inputs.isNotEmpty
                    ? (inputs.first.unit ?? '')
                    : (widget.node.inputItem?.unitSymbol ?? ''));
          _allottedCtrl.text = fmtQty(qty);
          _outputCtrl.text = fmtQty(qty);
        } else {
          _allottedFromBarcodes = allotted > 0;
          _firstBarcode = inputs.isNotEmpty ? inputs.first.barcode : null;
          _unit = inputs.isNotEmpty
              ? (inputs.first.unit ?? '')
              : (widget.node.inputItem?.unitSymbol ?? '');
          _allottedCtrl.text = allotted > 0
              ? fmtQty(allotted)
              : fmtQty((metrics['allotted'] as num?)?.toDouble() ?? 0);
          _outputCtrl.text = fmtQty((metrics['output'] as num?)?.toDouble() ?? 0);
        }
        _recalculate(keepScrap: true);
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _batchMode => widget.batchOutput != null;
  bool get _batchReconcileMode => widget.batchReconcileQty != null;
  bool get _inline => widget.onClose != null;

  void _dismiss(bool committed) {
    if (widget.onClose != null) {
      widget.onClose!();
    } else if (mounted) {
      Navigator.of(context).pop(committed);
    }
  }

  static DateTime? _parseTime(dynamic value) =>
      value is String ? DateTime.tryParse(value) : null;

  static String _fmtDateTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${two(t.day)} ${months[t.month - 1]} ${t.year}, '
        '${two(t.hour)}:${two(t.minute)}';
  }

  static String _fmtTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  /// Time-only edit: keeps the (carried) date and just changes the clock time,
  /// which is all an operator logging a same-day shift needs.
  Future<DateTime?> _pickTime(DateTime initial) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(
      initial.year,
      initial.month,
      initial.day,
      time.hour,
      time.minute,
    );
  }

  double get _allotted => double.tryParse(_allottedCtrl.text.trim()) ?? 0;
  double get _output => double.tryParse(_outputCtrl.text.trim()) ?? 0;
  double get _leftover => double.tryParse(_leftoverCtrl.text.trim()) ?? 0;
  double get _scrap => double.tryParse(_scrapCtrl.text.trim()) ?? 0;
  double get _difference =>
      (_allotted - _output) < 0 ? 0 : (_allotted - _output);

  /// Keeps leftover + scrap equal to the difference. When [keepScrap] the
  /// scrap entry is preserved and leftover absorbs the rest; otherwise the
  /// leftover entry is preserved and scrap absorbs the rest.
  void _recalculate({required bool keepScrap}) {
    final difference = _difference;
    if (keepScrap) {
      final scrap = _scrap.clamp(0, difference).toDouble();
      _scrapCtrl.text = fmtQty(scrap);
      _leftoverCtrl.text = fmtQty(difference - scrap);
    } else {
      final leftover = _leftover.clamp(0, difference).toDouble();
      _leftoverCtrl.text = fmtQty(leftover);
      _scrapCtrl.text = fmtQty(difference - leftover);
    }
    _errorText = null;
  }

  // While the user types in scrap/leftover, only update the *other* field —
  // never rewrite the one being edited, or partial decimals like "0." get
  // reformatted to "0" and you can never enter 0.xxx values.
  void _syncLeftoverFromScrap() {
    final difference = _difference;
    _leftoverCtrl.text = fmtQty(
      (difference - _scrap).clamp(0, difference).toDouble(),
    );
    _errorText = null;
  }

  void _syncScrapFromLeftover() {
    final difference = _difference;
    _scrapCtrl.text = fmtQty(
      (difference - _leftover).clamp(0, difference).toDouble(),
    );
    _errorText = null;
  }

  Future<void> _commit() async {
    if (_isCommitting) return;
    final difference = _difference;
    if (_output > _allotted) {
      setState(
        () => _errorText =
            'Output cannot exceed the allotted material (${fmtQty(_allotted)} $_unit).',
      );
      return;
    }
    if (_batchMode &&
        widget.batchAllottedMax != null &&
        _allotted > widget.batchAllottedMax! + 0.001) {
      setState(
        () => _errorText =
            'Consumed cannot exceed the ${fmtQty(widget.batchAllottedMax!)} $_unit '
            'available at this stage.',
      );
      return;
    }
    if ((_leftover + _scrap - difference).abs() > 0.001) {
      setState(
        () => _errorText =
            'Leftover + scrap must account for the full difference of ${fmtQty(difference)} $_unit.',
      );
      return;
    }
    if (_outputTime.isBefore(_inputTime)) {
      setState(
        () => _errorText =
            'Output time can’t be before the input time (${_fmtDateTime(_inputTime)}).',
      );
      return;
    }
    if (_inputFloor != null && _inputTime.isBefore(_inputFloor!)) {
      setState(
        () => _errorText =
            'Input time can’t be before the previous stage’s input time '
            '(${_fmtDateTime(_inputFloor!)}).',
      );
      return;
    }
    final scrappedLeftover = _leftoverAction == LeftoverAction.scrap
        ? _leftover
        : 0.0;
    final returnedLeftover = _leftoverAction == LeftoverAction.returnToInventory
        ? _leftover
        : 0.0;
    final totalScrap = _scrap + scrappedLeftover;
    if (totalScrap > 0 && widget.node.scrapItemId == null) {
      setState(
        () => _errorText =
            'No scrap destination is set for this stage. Pick a Scrap item for '
            '"${widget.node.name}" in the pipeline editor first.',
      );
      return;
    }

    setState(() {
      _isCommitting = true;
      _errorText = null;
    });
    try {
      final pipelineRepo = context.read<PipelineRunRepository>();
      final production = context.read<ProductionProvider>();
      final runProvider = context.read<ProductionRunProvider>();
      InventoryRepository? inventoryRepo;
      try {
        inventoryRepo = context.read<InventoryRepository>();
      } catch (_) {}

      await pipelineRepo.updateNodeMetrics(
        runId: widget.runId,
        nodeId: widget.node.id,
        metrics: {
          'allotted': _allotted,
          'output': _output,
          'remaining': returnedLeftover,
          'scrap': totalScrap,
          if (widget.node.scrapItemId != null)
            'scrapItemId': widget.node.scrapItemId,
          if (widget.node.scrapItemName != null)
            'scrapItem': widget.node.scrapItemName,
          'leftoverAction': _leftover <= 0
              ? 'none'
              : (_leftoverAction == LeftoverAction.returnToInventory
                    ? 'returned_to_inventory'
                    : 'scrapped'),
          'inputTime': _inputTime.toIso8601String(),
          'outputTime': _outputTime.toIso8601String(),
        },
      );

      if (totalScrap > 0) {
        await pipelineRepo.logProductionScrap(
          runId: widget.runId,
          nodeId: widget.node.id,
          materialBarcode:
              _firstBarcode ?? widget.node.scrapItemName ?? 'unassigned',
          scrapQty: totalScrap,
          orderNo: _run?.orderNo,
        );
      }

      if (returnedLeftover > 0 &&
          _firstBarcode != null &&
          inventoryRepo != null) {
        await inventoryRepo.createInventoryMovement(
          CreateInventoryMovementInput(
            materialBarcode: _firstBarcode!,
            movementType: InventoryMovementType.adjust,
            qty: returnedLeftover,
            reasonCode: 'LEFTOVER_RETURN',
            actor: production.activeOperator,
          ),
        );
      }

      widget.onCommitted?.call(
        ReconcileResult(
          loss: _allotted - _output,
          scrapLogged: totalScrap,
          leftoverReturned: returnedLeftover,
          barcode: _firstBarcode,
        ),
      );
      runProvider.triggerRefresh();
      if (mounted) _dismiss(true);
    } catch (e) {
      if (mounted) {
        setState(() => _errorText = 'Failed to commit reconciliation: $e');
      }
    } finally {
      if (mounted) setState(() => _isCommitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _isLoading
              ? const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isRefreshing)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8.0),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    Text(
                      widget.batchLabel == null
                          ? 'Reconcile "${widget.node.name}"'
                          : 'Reconcile "${widget.node.name}" · ${widget.batchLabel}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: SoftErpTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _QtyField(
                            label: _batchMode
                                ? 'Consumed ($_unit)'
                                : 'Input material ($_unit)',
                            controller: _allottedCtrl,
                            enabled: !_allottedFromBarcodes,
                            autofocus: _batchMode,
                            onChanged: (_) =>
                                setState(() => _recalculate(keepScrap: true)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _QtyField(
                            label: _batchMode
                                ? 'Advanced ($_unit)'
                                : 'Stage Output ($_unit)',
                            controller: _outputCtrl,
                            enabled: !_batchMode,
                            autofocus: !_batchMode,
                            onChanged: (_) =>
                                setState(() => _recalculate(keepScrap: true)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _QtyField(
                            label: 'Leftover ($_unit)',
                            controller: _leftoverCtrl,
                            onChanged: (_) => setState(
                              () => _syncScrapFromLeftover(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _QtyField(
                            label: 'Scrap ($_unit)',
                            controller: _scrapCtrl,
                            onChanged: (_) => setState(
                              () => _syncLeftoverFromScrap(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _TimeField(
                            label: 'Input time',
                            value: _fmtTime(_inputTime),
                            onTap: () async {
                              final picked = await _pickTime(_inputTime);
                              if (picked != null) {
                                setState(() {
                                  _inputTime = picked;
                                  if (_outputTime.isBefore(_inputTime)) {
                                    _outputTime = _inputTime;
                                  }
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TimeField(
                            label: 'Output time',
                            value: _fmtTime(_outputTime),
                            onTap: () async {
                              final picked = await _pickTime(_outputTime);
                              if (picked != null) {
                                setState(() => _outputTime = picked);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Leftover material will be sent to original inventory stock.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_errorText != null) ...[
                      Text(
                        _errorText!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        AppButton(
                          label: 'Cancel',
                          variant: AppButtonVariant.secondary,
                          onPressed: _isCommitting ? null : () => _dismiss(false),
                        ),
                        AppButton(
                          label: _isOutputStage 
                              ? (widget.node.outputItem != null 
                                  ? 'Commit & Send to Inventory' 
                                  : 'Define Output & Send to Inventory')
                              : 'Commit & Move to Next Stage',
                          icon: Icons.fact_check_rounded,
                          isLoading: _isCommitting,
                          onPressed: (_isCommitting || _isRefreshing) ? null : _commit,
                        ),
                      ],
                    ),
                  ],
                );

    if (_inline) {
      return Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: body,
        ),
      );
    }
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: body,
        ),
      ),
    );
  }
}

class _QtyField extends StatelessWidget {
  const _QtyField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.enabled = true,
    this.autofocus = false,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: enabled ? const Color(0xFFF8FAFC) : const Color(0xFFF1F5F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
    );
  }
}

/// Tappable date+time field matching [_QtyField]'s look. Opens a date then
/// time picker so operators can log when material actually moved.
class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          suffixIcon: const Icon(Icons.schedule_rounded, size: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
        child: Text(
          value,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
      ),
    );
  }
}


class _SidebarSection extends StatelessWidget {
  const _SidebarSection({
    required this.title,
    required this.icon,
    required this.child,
    this.initiallyExpanded = true,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Icon(icon, size: 18, color: const Color(0xFF64748B)),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            letterSpacing: 0.3,
          ),
        ),
        children: [child],
      ),
    );
  }
}
