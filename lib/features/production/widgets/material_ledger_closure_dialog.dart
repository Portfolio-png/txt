import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/domain/inventory_control_tower.dart';
import 'package:core_erp/features/inventory/domain/material_inputs.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/inventory/domain/material_record.dart';

import '../domain/utils/material_ledger_distributor.dart';
import '../providers/production_provider.dart';
import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';

class MaterialLedgerClosureDialog extends StatefulWidget {
  const MaterialLedgerClosureDialog({super.key});

  @override
  State<MaterialLedgerClosureDialog> createState() =>
      _MaterialLedgerClosureDialogState();
}

class _MaterialLedgerClosureDialogState
    extends State<MaterialLedgerClosureDialog> {
  late LedgerWeights _weights;
  bool _isCommitting = false;
  String? _selectedParentBarcode;
  double _remainingKg = 0.0;
  double _assignedKg = 0.0;

  @override
  void initState() {
    super.initState();
    final provider = context.read<ProductionProvider>();
    _assignedKg = provider.parentReelConsumedKg;
    _weights = MaterialLedgerDistributor.initialDistribution(
      parentKg: _assignedKg,
      initialYieldCount: provider.goodYieldCount == 0
          ? 0
          : provider.goodYieldCount,
      initialScrapWeightKg: provider.scrapWeightKg,
    );
  }

  void _recalcParentKg() {
    final consumed = (_assignedKg - _remainingKg).clamp(0.0, double.infinity);
    _weights = MaterialLedgerDistributor.updateParent(_weights, consumed);
  }

  void _update({
    double? parentKg,
    int? yieldUnits,
    double? scrapKg,
    double? goodKg,
    double? setupKg,
    double? processKg,
  }) {
    setState(() {
      if (parentKg != null) {
        // Manually editing Consumed overrides Assigned -> Remaining logic,
        // or we can just say _remainingKg = _assignedKg - parentKg
        _weights = MaterialLedgerDistributor.updateParent(_weights, parentKg);
        _remainingKg = (_assignedKg - parentKg).clamp(0.0, double.infinity);
      } else if (yieldUnits != null) {
        _weights = MaterialLedgerDistributor.updateYield(_weights, yieldUnits);
      } else if (scrapKg != null) {
        _weights = MaterialLedgerDistributor.updateScrap(_weights, scrapKg);
      } else if (goodKg != null) {
        _weights = MaterialLedgerDistributor.adjustWeights(
          _weights,
          goodKg: goodKg,
        );
      } else if (setupKg != null) {
        _weights = MaterialLedgerDistributor.adjustWeights(
          _weights,
          setupKg: setupKg,
        );
      } else if (processKg != null) {
        _weights = MaterialLedgerDistributor.adjustWeights(
          _weights,
          processKg: processKg,
        );
      }
    });
    _syncProvider();
  }

  void _syncProvider() {
    context.read<ProductionProvider>().updateClosureValues(
      parentReelConsumedKg: _weights.parentKg,
      goodYieldCount: _weights.yieldUnits,
      scrapWeightKg: _weights.scrapKg,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductionProvider>();

    return Dialog(
      shape: const RoundedRectangleBorder(),
      backgroundColor: const Color(0xFF09090B),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(
                    Icons.analytics_outlined,
                    color: Color(0xFF22C55E),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'MATERIAL LEDGER CLOSURE',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF18181B),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      provider.activeRun?.id ?? 'NO-RUN',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Color(0xFFA1A1AA),
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Content Area
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 850;
                    final inventory = context.watch<InventoryProvider>();
                    final editor = _LedgerEditor(
                      materials: inventory.materials,
                      selectedParentBarcode: _selectedParentBarcode,
                      assignedKg: _assignedKg,
                      remainingKg: _remainingKg,
                      parentKg: _weights.parentKg,
                      yieldUnits: _weights.yieldUnits,
                      scrapKg: _weights.scrapKg,
                      goodKg: _weights.goodKg,
                      setupKg: _weights.setupKg,
                      processKg: _weights.processKg,
                      onParentBarcodeSelected: (val) =>
                          setState(() => _selectedParentBarcode = val),
                      onRemainingChanged: (value) {
                        setState(() {
                          _remainingKg = value.clamp(0.0, _assignedKg);
                          _recalcParentKg();
                        });
                        _syncProvider();
                      },
                      onParentChanged: (value) => _update(parentKg: value),
                      onYieldChanged: (value) => _update(yieldUnits: value),
                      onScrapChanged: (value) => _update(scrapKg: value),
                      onGoodKgChanged: (value) => _update(goodKg: value),
                      onSetupKgChanged: (value) => _update(setupKg: value),
                      onProcessKgChanged: (value) => _update(processKg: value),
                    );

                    final preview = _DiffPreview(
                      lines: provider.ledgerPreview.diffLines,
                    );

                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 3, child: editor),
                          Container(
                            width: 1,
                            color: const Color(0xFF27272A),
                            margin: const EdgeInsets.symmetric(horizontal: 20),
                          ),
                          Expanded(flex: 2, child: preview),
                        ],
                      );
                    }
                    return SingleChildScrollView(
                      child: Column(
                        children: [
                          editor,
                          const Divider(height: 32, color: Color(0xFF27272A)),
                          SizedBox(height: 260, child: preview),
                        ],
                      ),
                    );
                  },
                ),
              ),

              const Divider(height: 24, color: Color(0xFF27272A)),

              // Footer Actions
              Row(
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFA1A1AA),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        foregroundColor: const Color(0xFF09090B),
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onPressed: _isCommitting ? null : _commitLedger,
                      icon: _isCommitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF09090B),
                              ),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(
                        _isCommitting ? 'Committing...' : 'Commit Ledger',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _commitLedger() async {
    if (_isCommitting) return;
    setState(() => _isCommitting = true);

    try {
      final provider = context.read<ProductionProvider>();
      final repo = context.read<InventoryRepository>();
      final pipelineRepo = context.read<PipelineRunRepository>();
      final activeOperator = provider.activeOperator;
      final activeRun = provider.activeRun;
      final selectedNodeId = provider.selectedNode?.id;

      // Sync local provider UI values just in case
      _syncProvider();

      if (_selectedParentBarcode == null) {
        throw Exception(
          'Please select the consumed material from the dropdown.',
        );
      }

      // 1. Consume Parent Stock
      await repo.createInventoryMovement(
        CreateInventoryMovementInput(
          materialBarcode: _selectedParentBarcode!,
          movementType: InventoryMovementType.consume,
          qty: _weights.parentKg,
          reasonCode: 'PRODUCTION_CONSUME',
          actor: activeOperator,
        ),
      );

      // 2. Handle Scrap. Scrap always goes to the scrap ledger (attributed
      // to the stage's configured Scrap item), never back into inventory.
      if (_weights.scrapKg > 0) {
        if (activeRun != null && selectedNodeId != null) {
          final run = await pipelineRepo.getRun(activeRun.id);
          await pipelineRepo.logProductionScrap(
            runId: activeRun.id,
            nodeId: selectedNodeId,
            materialBarcode: _selectedParentBarcode!,
            scrapQty: _weights.scrapKg,
            orderNo: run?.orderNo,
          );
        } else {
          await repo.createInventoryMovement(
            CreateInventoryMovementInput(
              materialBarcode: _selectedParentBarcode!,
              movementType: InventoryMovementType.adjust,
              qty: -_weights.scrapKg,
              reasonCode: 'SCRAP_WASTAGE',
              actor: activeOperator,
            ),
          );
        }
      }

      // 3. Receive Yield
      if (_weights.yieldUnits > 0) {
        // Create a new child material for this yield lot
        final yieldLot = await repo.createChildMaterial(
          CreateChildMaterialInput(
            parentBarcode: _selectedParentBarcode!,
            name: 'Yield from Run ${provider.activeRun?.id ?? "UNKNOWN"}',
          ),
        );

        final outputItem = provider.selectedNode?.outputItem;
        if (outputItem != null) {
          await repo.linkMaterialToItem(yieldLot.barcode, outputItem.itemId);
        }

        // Receive the output into inventory
        await repo.createInventoryMovement(
          CreateInventoryMovementInput(
            materialBarcode: yieldLot.barcode,
            movementType: InventoryMovementType.receive,
            qty: _weights.yieldUnits.toDouble(),
            reasonCode: 'PRODUCTION_YIELD',
            actor: activeOperator,
          ),
        );
      }

      if (!mounted) return;

      if (activeRun != null && selectedNodeId != null) {
        try {
          await pipelineRepo.updateNodeMetrics(
            runId: activeRun.id,
            nodeId: selectedNodeId,
            metrics: {'remaining': _remainingKg, 'scrap': _weights.scrapKg},
          );
        } catch (e) {
          debugPrint('Failed to save node metrics: $e');
        }
      }

      context.read<ProductionProvider>().commitClosure();
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('Failed to commit ledger to inventory: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to commit ledger: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCommitting = false);
      }
    }
  }
}

class _LedgerEditor extends StatelessWidget {
  const _LedgerEditor({
    required this.materials,
    required this.selectedParentBarcode,
    required this.assignedKg,
    required this.remainingKg,
    required this.parentKg,
    required this.yieldUnits,
    required this.scrapKg,
    required this.goodKg,
    required this.setupKg,
    required this.processKg,
    required this.onParentBarcodeSelected,
    required this.onRemainingChanged,
    required this.onParentChanged,
    required this.onYieldChanged,
    required this.onScrapChanged,
    required this.onGoodKgChanged,
    required this.onSetupKgChanged,
    required this.onProcessKgChanged,
  });

  final List<MaterialRecord> materials;
  final String? selectedParentBarcode;

  final double assignedKg;
  final double remainingKg;
  final double parentKg;
  final int yieldUnits;
  final double scrapKg;
  final double goodKg;
  final double setupKg;
  final double processKg;

  final ValueChanged<String?> onParentBarcodeSelected;
  final ValueChanged<double> onRemainingChanged;
  final ValueChanged<double> onParentChanged;
  final ValueChanged<int> onYieldChanged;
  final ValueChanged<double> onScrapChanged;
  final ValueChanged<double> onGoodKgChanged;
  final ValueChanged<double> onSetupKgChanged;
  final ValueChanged<double> onProcessKgChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _LedgerHeader(),
          const SizedBox(height: 16),
          _MaterialSelector(
            materials: materials,
            selectedBarcode: selectedParentBarcode,
            onChanged: onParentBarcodeSelected,
          ),
          const SizedBox(height: 8),

          // Assigned Row (Read-Only)
          _EditableLedgerRow<double>(
            code: selectedParentBarcode ?? 'ASSIGNED_STOCK',
            label: 'Assigned',
            value: assignedKg,
            unit: 'Kg',
            formatter: (value) => value.toStringAsFixed(2),
            parser: (value) => double.tryParse(value) ?? assignedKg,
            onChanged: (val) {}, // Read-only
            onIncrement: () {},
            onDecrement: () {},
          ),

          // Remaining Row
          _EditableLedgerRow<double>(
            code: 'REMAINING_STOCK',
            label: 'Remaining',
            value: remainingKg,
            unit: 'Kg',
            formatter: (value) => value.toStringAsFixed(2),
            parser: (value) => double.tryParse(value) ?? remainingKg,
            onChanged: onRemainingChanged,
            onIncrement: () =>
                onRemainingChanged((remainingKg + 1.0).clamp(0.0, assignedKg)),
            onDecrement: () =>
                onRemainingChanged((remainingKg - 1.0).clamp(0.0, assignedKg)),
          ),

          // Consumed Row
          _EditableLedgerRow<double>(
            code: selectedParentBarcode ?? 'CONSUMED_MATERIAL',
            label: 'Consumed',
            value: parentKg,
            unit: 'Kg',
            formatter: (value) => value.toStringAsFixed(2),
            parser: (value) => double.tryParse(value) ?? parentKg,
            onChanged: onParentChanged,
            onIncrement: () => onParentChanged(parentKg + 10.0),
            onDecrement: () =>
                onParentChanged((parentKg - 10.0).clamp(1.0, double.infinity)),
          ),

          // Produced Row
          _EditableLedgerRow<int>(
            code: 'WIP_BOARD_LOT_B42',
            label: 'Produced',
            value: yieldUnits,
            unit: 'Pcs',
            formatter: (value) => _formatInt(value),
            parser: (value) =>
                int.tryParse(value.replaceAll(',', '')) ?? yieldUnits,
            onChanged: onYieldChanged,
            onIncrement: () => onYieldChanged(yieldUnits + 100),
            onDecrement: () =>
                onYieldChanged((yieldUnits - 100).clamp(0, 99999999)),
          ),

          // Scrap Row
          _EditableLedgerRow<double>(
            code: 'SCRAP_SHRED_CORE',
            label: 'Wastage',
            value: scrapKg,
            unit: 'Kg',
            formatter: (value) => value.toStringAsFixed(2),
            parser: (value) => double.tryParse(value) ?? scrapKg,
            onChanged: onScrapChanged,
            onIncrement: () => onScrapChanged(scrapKg + 1.0),
            onDecrement: () =>
                onScrapChanged((scrapKg - 1.0).clamp(0.0, parentKg)),
          ),

          const SizedBox(height: 24),

          // Graphical Segmented Bar
          _SegmentedBar(
            goodKg: goodKg,
            setupKg: setupKg,
            processKg: processKg,
            totalKg: parentKg,
          ),

          const SizedBox(height: 24),
          const Text(
            'BALANCED MATERIAL RATIO ADJUSTMENT',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: Color(0xFFA1A1AA),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          // Good Yield Slider
          _RatioSliderRow(
            label: 'Good Yield Weight',
            value: goodKg,
            max: parentKg,
            color: const Color(0xFF22C55E),
            onChanged: onGoodKgChanged,
          ),

          // Setup Scrap Slider
          _RatioSliderRow(
            label: 'Setup Scrap Weight',
            value: setupKg,
            max: parentKg,
            color: const Color(0xFFF59E0B),
            onChanged: onSetupKgChanged,
          ),

          // Process Waste Slider
          _RatioSliderRow(
            label: 'Process Waste Weight',
            value: processKg,
            max: parentKg,
            color: const Color(0xFFEF4444),
            onChanged: onProcessKgChanged,
          ),
        ],
      ),
    );
  }
}

class _LedgerHeader extends StatelessWidget {
  const _LedgerHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('ACCOUNT', style: _headerStyle)),
          Expanded(
            flex: 4,
            child: Text('VALUE (DOUBLE TAP TO TYPE)', style: _headerStyle),
          ),
          Expanded(flex: 2, child: Text('CLASS', style: _headerStyle)),
        ],
      ),
    );
  }
}

class _EditableLedgerRow<T extends num> extends StatefulWidget {
  const _EditableLedgerRow({
    required this.code,
    required this.label,
    required this.value,
    required this.unit,
    required this.formatter,
    required this.parser,
    required this.onChanged,
    required this.onIncrement,
    required this.onDecrement,
  });

  final String code;
  final String label;
  final T value;
  final String unit;
  final String Function(T value) formatter;
  final T Function(String value) parser;
  final ValueChanged<T> onChanged;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  State<_EditableLedgerRow<T>> createState() => _EditableLedgerRowState<T>();
}

class _EditableLedgerRowState<T extends num>
    extends State<_EditableLedgerRow<T>> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.formatter(widget.value));
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _EditableLedgerRow<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.value != widget.value) {
      _controller.text = widget.formatter(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF27272A))),
      ),
      child: Row(
        children: [
          // Account Code
          Expanded(
            flex: 4,
            child: Text(
              widget.code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),

          // Value + Tactile buttons
          Expanded(
            flex: 4,
            child: Row(
              children: [
                // Decrement button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onDecrement,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.remove_rounded,
                        color: Color(0xFFEF4444),
                        size: 18,
                      ),
                    ),
                  ),
                ),

                // Numerical text display / field
                Expanded(
                  child: GestureDetector(
                    onDoubleTap: _startEditing,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF18181B),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: _editing
                          ? TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              autofocus: true,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onSubmitted: (_) => _commit(),
                              onEditingComplete: _commit,
                              decoration: InputDecoration(
                                suffixText: widget.unit,
                                suffixStyle: const TextStyle(
                                  color: Color(0xFF71717A),
                                ),
                                isDense: true,
                                border: InputBorder.none,
                              ),
                            )
                          : Text(
                              '${widget.formatter(widget.value)} ${widget.unit}',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF22C55E),
                              ),
                            ),
                    ),
                  ),
                ),

                // Increment button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onIncrement,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.add_rounded,
                        color: Color(0xFF22C55E),
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Label
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                widget.label,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF71717A),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _startEditing() {
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _commit() {
    widget.onChanged(widget.parser(_controller.text.trim()));
    setState(() => _editing = false);
  }
}

class _SegmentedBar extends StatelessWidget {
  const _SegmentedBar({
    required this.goodKg,
    required this.setupKg,
    required this.processKg,
    required this.totalKg,
  });

  final double goodKg;
  final double setupKg;
  final double processKg;
  final double totalKg;

  @override
  Widget build(BuildContext context) {
    final goodPct = totalKg > 0 ? (goodKg / totalKg) : 0.0;
    final setupPct = totalKg > 0 ? (setupKg / totalKg) : 0.0;
    final processPct = totalKg > 0 ? (processKg / totalKg) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MATERIAL DISTRIBUTION BALANCE',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: Color(0xFFA1A1AA),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: const Color(0xFF18181B),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              if (goodPct > 0)
                Expanded(
                  flex: (goodPct * 1000).round().clamp(1, 1000),
                  child: Container(
                    color: const Color(0xFF22C55E),
                    alignment: Alignment.center,
                    child: Text(
                      '${(goodPct * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: Color(0xFF09090B),
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              if (setupPct > 0)
                Expanded(
                  flex: (setupPct * 1000).round().clamp(1, 1000),
                  child: Container(
                    color: const Color(0xFFF59E0B),
                    alignment: Alignment.center,
                    child: Text(
                      '${(setupPct * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: Color(0xFF09090B),
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              if (processPct > 0)
                Expanded(
                  flex: (processPct * 1000).round().clamp(1, 1000),
                  child: Container(
                    color: const Color(0xFFEF4444),
                    alignment: Alignment.center,
                    child: Text(
                      '${(processPct * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _LegendItem(
              color: const Color(0xFF22C55E),
              label: 'Yield: ${goodKg.toStringAsFixed(1)} Kg',
            ),
            _LegendItem(
              color: const Color(0xFFF59E0B),
              label: 'Setup: ${setupKg.toStringAsFixed(1)} Kg',
            ),
            _LegendItem(
              color: const Color(0xFFEF4444),
              label: 'Process: ${processKg.toStringAsFixed(1)} Kg',
            ),
          ],
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFA1A1AA),
            fontSize: 10,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _RatioSliderRow extends StatelessWidget {
  const _RatioSliderRow({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFA1A1AA),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${value.toStringAsFixed(1)} Kg',
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color,
              inactiveTrackColor: const Color(0xFF18181B),
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.12),
              trackHeight: 4,
            ),
            child: Slider(
              value: value,
              min: 0.0,
              max: max > 0 ? max : 1.0,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffPreview extends StatelessWidget {
  const _DiffPreview({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('REAL-TIME ACCOUNT LEDGER PREVIEW', style: _headerStyle),
        const SizedBox(height: 14),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF18181B),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF27272A)),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '--- AUTO-DEDUCT TRANSACTION BATCH ---',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFF52525B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...lines.map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        line,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: line.startsWith('-')
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF22C55E),
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'STATUS: PENDING COMMIT',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFFF59E0B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const TextStyle _headerStyle = TextStyle(
  fontFamily: 'monospace',
  fontSize: 10,
  fontWeight: FontWeight.w900,
  color: Color(0xFF71717A),
  letterSpacing: 0.5,
);

String _formatInt(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i += 1) {
    final fromEnd = text.length - i;
    buffer.write(text[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}

class _MaterialSelector extends StatelessWidget {
  const _MaterialSelector({
    required this.materials,
    required this.selectedBarcode,
    required this.onChanged,
  });

  final List<MaterialRecord> materials;
  final String? selectedBarcode;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SELECT CONSUMED MATERIAL',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: Color(0xFFA1A1AA),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: selectedBarcode,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF18181B),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
          dropdownColor: const Color(0xFF18181B),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          items: materials.map((m) {
            return DropdownMenuItem<String>(
              value: m.barcode,
              child: Text('${m.name} (${m.barcode})'),
            );
          }).toList(),
          onChanged: onChanged,
          hint: const Text(
            'Select Material',
            style: TextStyle(color: Color(0xFFA1A1AA)),
          ),
        ),
      ],
    );
  }
}
