import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/domain/inventory_control_tower.dart';

import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/pipeline_run.dart';
import '../../production_pipelines/domain/process_node.dart';
import '../domain/utils/stage_input_resolver.dart';
import '../providers/production_provider.dart';
import '../providers/production_run_provider.dart';

enum LeftoverAction { returnToInventory, scrap }

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
  });

  final ProcessNode node;
  final String runId;

  static Future<bool?> show(
    BuildContext context, {
    required ProcessNode node,
    required String runId,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => StageReconciliationDialog(node: node, runId: runId),
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
  bool _isCommitting = false;
  bool _allottedFromBarcodes = false;
  String _unit = '';
  String? _firstBarcode;
  LeftoverAction _leftoverAction = LeftoverAction.returnToInventory;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _allottedCtrl.dispose();
    _outputCtrl.dispose();
    _leftoverCtrl.dispose();
    _scrapCtrl.dispose();
    super.dispose();
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
      setState(() {
        _run = run;
        _isLoading = false;
        _allottedFromBarcodes = allotted > 0;
        _firstBarcode = inputs.isNotEmpty ? inputs.first.barcode : null;
        _unit = inputs.isNotEmpty
            ? (inputs.first.unit ?? '')
            : (widget.node.inputItem?.unitSymbol ?? '');
        _allottedCtrl.text = allotted > 0
            ? _fmt(allotted)
            : _fmt((metrics['allotted'] as num?)?.toDouble() ?? 0);
        _outputCtrl.text = _fmt((metrics['output'] as num?)?.toDouble() ?? 0);
        _recalculate(keepScrap: true);
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double get _allotted => double.tryParse(_allottedCtrl.text.trim()) ?? 0;
  double get _output => double.tryParse(_outputCtrl.text.trim()) ?? 0;
  double get _leftover => double.tryParse(_leftoverCtrl.text.trim()) ?? 0;
  double get _scrap => double.tryParse(_scrapCtrl.text.trim()) ?? 0;
  double get _difference =>
      (_allotted - _output) < 0 ? 0 : (_allotted - _output);

  String _fmt(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  /// Keeps leftover + scrap equal to the difference. When [keepScrap] the
  /// scrap entry is preserved and leftover absorbs the rest; otherwise the
  /// leftover entry is preserved and scrap absorbs the rest.
  void _recalculate({required bool keepScrap}) {
    final difference = _difference;
    if (keepScrap) {
      final scrap = _scrap.clamp(0, difference).toDouble();
      _scrapCtrl.text = _fmt(scrap);
      _leftoverCtrl.text = _fmt(difference - scrap);
    } else {
      final leftover = _leftover.clamp(0, difference).toDouble();
      _leftoverCtrl.text = _fmt(leftover);
      _scrapCtrl.text = _fmt(difference - leftover);
    }
    _errorText = null;
  }

  Future<void> _commit() async {
    if (_isCommitting) return;
    final difference = _difference;
    if (_output > _allotted) {
      setState(
        () => _errorText =
            'Output cannot exceed the allotted material (${_fmt(_allotted)} $_unit).',
      );
      return;
    }
    if ((_leftover + _scrap - difference).abs() > 0.001) {
      setState(
        () => _errorText =
            'Leftover + scrap must account for the full difference of ${_fmt(difference)} $_unit.',
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

      runProvider.triggerRefresh();
      if (mounted) Navigator.of(context).pop(true);
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

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: _isLoading
              ? const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Reconcile "${widget.node.name}"',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _QtyField(
                            label: 'Allotted ($_unit)',
                            controller: _allottedCtrl,
                            enabled: !_allottedFromBarcodes,
                            onChanged: (_) =>
                                setState(() => _recalculate(keepScrap: true)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _QtyField(
                            label: 'Stage Output ($_unit)',
                            controller: _outputCtrl,
                            autofocus: true,
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
                              () => _recalculate(keepScrap: false),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _QtyField(
                            label: 'Scrap ($_unit)',
                            controller: _scrapCtrl,
                            onChanged: (_) => setState(
                              () => _recalculate(keepScrap: true),
                            ),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: _isCommitting ? null : _commit,
                          icon: _isCommitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.fact_check_rounded, size: 18),
                          label: const Text('Commit Reconciliation'),
                        ),
                      ],
                    ),
                  ],
                ),
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
