import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/features/inventory/domain/material_record.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/domain/inventory_control_tower.dart';
import 'package:core_erp/features/inventory/domain/material_inputs.dart';
import 'package:core_erp/features/orders/presentation/providers/orders_provider.dart';
import 'package:core_erp/features/orders/domain/order_entry.dart';
import '../providers/production_provider.dart';
import '../providers/production_run_provider.dart';
import '../providers/batch_flow_provider.dart';
import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/pipeline_template.dart';
import '../../production_pipelines/domain/pipeline_run.dart';
import '../../production_pipelines/domain/barcode_input.dart';
import '../../production_pipelines/domain/material_batch.dart';
import '../../production_pipelines/domain/process_node.dart';
import '../../production_pipelines/domain/node_run_status.dart';
import 'graph_edges_painter.dart';
import 'flow_stage_block.dart';
import 'batch_chip.dart';
import 'node_batch_tray.dart';
import 'floor_toast.dart';
import 'stage_reconciliation_dialog.dart';
import '../domain/utils/stage_input_resolver.dart';

class PipelineCanvas extends StatefulWidget {
  const PipelineCanvas({
    super.key,
    required this.template,
    required this.selectedNodeId,
    required this.onNodeSelected,
    this.onNodeDoubleTap,
  });

  final PipelineTemplate template;
  final String? selectedNodeId;
  final ValueChanged<String> onNodeSelected;
  final ValueChanged<String>? onNodeDoubleTap;

  @override
  State<PipelineCanvas> createState() => _PipelineCanvasState();
}

class _PipelineCanvasState extends State<PipelineCanvas> {
  late final TransformationController _controller;
  Future<PipelineRun?>? _runFuture;
  int? _lastRefreshCount;
  String? _lastRunId;

  static const double nodeWidth = 160;
  static const double nodeHeight = 52;
  static const double columnWidth = 240;
  static const double rowHeight = 112;

  @override
  void initState() {
    super.initState();
    _controller = TransformationController();
    // Center it a bit initially
    _controller.value = Matrix4.identity()
      ..translateByDouble(-50.0, -50.0, 0.0, 1.0)
      ..scaleByDouble(0.9, 0.9, 1.0, 1.0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final runProvider = context.read<ProductionRunProvider>();
    final runId = runProvider.runId;
    if (runId != null) {
      final repo = context.read<PipelineRunRepository>();
      _runFuture = repo.getRun(runId);
      _lastRefreshCount = runProvider.refreshCount;
      _lastRunId = runId;
    } else {
      _runFuture = null;
      _lastRefreshCount = null;
      _lastRunId = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleEditStock(ProcessNode node, BarcodeInput input) async {
    final runProvider = context.read<ProductionRunProvider>();
    final repo = context.read<PipelineRunRepository>();
    if (runProvider.runId == null) return;

    try {
      final material = await context.read<InventoryProvider>().lookupBarcode(
        input.barcode,
      );
      if (material == null) {
        if (mounted) {
          showFloorToast(
            context,
            'Failed to locate material record for barcode ${input.barcode}',
            kind: FloorToastKind.error,
          );
        }
        return;
      }

      if (!mounted) return;

      final newQty = await showDialog<double>(
        context: context,
        builder: (context) => _StockEditQtyDialog(
          material: material,
          nodeName: node.name,
          currentQuantity: input.quantity ?? 0.0,
        ),
      );

      if (newQty == null) return;

      await repo.updateAttachedBarcodeQuantity(
        runId: runProvider.runId!,
        nodeId: node.id,
        barcode: input.barcode,
        quantity: newQty,
      );

      runProvider.triggerRefresh();

      if (mounted) {
        context.read<InventoryProvider>().refresh();
        showFloorToast(
          context,
          'Updated assigned quantity of ${input.barcode} to $newQty ${input.unit ?? ''}',
          kind: FloorToastKind.info,
        );
      }
    } catch (e) {
      if (mounted) {
        showFloorToast(
          context,
          'Failed to update quantity: $e',
          kind: FloorToastKind.error,
        );
      }
    }
  }

  Future<void> _handleDeleteStock(ProcessNode node, BarcodeInput input) async {
    final runProvider = context.read<ProductionRunProvider>();
    final repo = context.read<PipelineRunRepository>();
    if (runProvider.runId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Remove Assigned Stock',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'Are you sure you want to remove barcode "${input.barcode}" from step "${node.name}"?\nThis will return the assigned quantity back to inventory.',
          style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text(
              'Remove',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await repo.detachBarcodeFromRunNode(
        runId: runProvider.runId!,
        nodeId: node.id,
        barcode: input.barcode,
      );

      runProvider.triggerRefresh();

      if (mounted) {
        context.read<InventoryProvider>().refresh();
        showFloorToast(
          context,
          'Removed ${input.barcode} from ${node.name}',
          kind: FloorToastKind.info,
        );
      }
    } catch (e) {
      if (mounted) {
        showFloorToast(
          context,
          'Failed to remove stock: $e',
          kind: FloorToastKind.error,
        );
      }
    }
  }

  Widget _buildAssignedStockCard(ProcessNode node, BarcodeInput input) {
    return Container(
      width: nodeWidth,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.qr_code_2_rounded,
                size: 14,
                color: Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  input.barcode,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (input.quantity != null)
                Text(
                  '${input.quantity} ${input.unit ?? ''}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                )
              else
                const SizedBox.shrink(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TinyIconButton(
                    icon: Icons.edit_outlined,
                    onTap: () => _handleEditStock(node, input),
                    tooltip: 'Edit quantity',
                  ),
                  const SizedBox(width: 4),
                  _TinyIconButton(
                    icon: Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                    onTap: () => _handleDeleteStock(node, input),
                    tooltip: 'Remove stock',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Seeds the run's batch chips once from its assigned stock so the gamified
  /// token view has something to move. No-op if already seeded.
  void _seedBatchesIfNeeded(PipelineRun run, BatchFlowProvider batchProvider) {
    if (batchProvider.isSeeded(run.id)) return;

    // Persisted batches win — restore them as-is.
    if (run.batches.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) batchProvider.seedRun(run.id, run.batches);
      });
      return;
    }

    // First time: derive chips from assigned stock and persist them so the
    // positions survive a reload.
    final initial = <MaterialBatch>[];
    run.attachedBarcodeInputs.forEach((nodeId, inputs) {
      for (final input in inputs) {
        final qty = input.quantity ?? 0;
        if (qty <= 0) continue;
        initial.add(
          MaterialBatch(
            id: 'seed-${run.id}-$nodeId-${input.barcode}-${initial.length}',
            barcode: input.barcode,
            materialName: input.materialName,
            quantity: qty,
            unit: input.unit,
            currentNodeId: nodeId,
            createdAt: DateTime.now(),
          ),
        );
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      batchProvider.seedRun(run.id, initial);
      if (initial.isNotEmpty) _persistBatches(run.id, batchProvider);
    });
  }

  /// Write-through: persists the run's current batch list. Surfaces failures
  /// rather than silently losing a move.
  Future<void> _persistBatches(String runId, BatchFlowProvider bp) async {
    try {
      await context.read<PipelineRunRepository>().saveBatches(
        runId: runId,
        batches: bp.batchesForRun(runId),
      );
    } catch (e) {
      if (mounted) {
        showFloorToast(
          context,
          'Failed to save batch change: $e',
          kind: FloorToastKind.error,
        );
      }
    }
  }

  /// Builds the double-click popout content: first the action circles (start /
  /// mark done / skip, or batch actions), then the reconcile panel on "mark
  /// done". Rendered as a real overlay (see [_popoutOverlay]) so it's
  /// hit-testable — content above a zero-height/zoomed box can't receive taps.
  Widget _popoutContent(
    ProcessNode node,
    ProductionRunProvider runProvider,
    BatchFlowProvider batchProvider,
  ) {
    final runId = runProvider.runId;
    if (runId == null) return const SizedBox.shrink();
    final isReconcile = runProvider.popoutMode == StagePopoutMode.reconcile;
    final batch = runProvider.popoutBatch;

    final Widget content = isReconcile
        ? SizedBox(
            width: 320,
            child: StageReconciliationDialog(
              key: ValueKey('reconcile-${node.id}-${batch?.id ?? 'stage'}'),
              node: node,
              runId: runId,
              onClose: runProvider.closePopout,
              batchReconcileQty: batch?.quantity,
              batchUnit: batch?.unit,
              batchBarcode: batch?.barcode,
              onCommitted: (result) {
                if (batch != null) {
                  batchProvider.reduceBatch(
                    runId: runId,
                    batchId: batch.id,
                    amount: result.loss,
                    scrap: result.scrapLogged,
                    leftover: result.leftoverReturned,
                  );
                  _persistBatches(runId, batchProvider);
                } else {
                  // Reconciling the whole stage closes it out.
                  _setNodeStatus(node, NodeRunStatus.done);
                }
              },
            ),
          )
        : (batch != null
              ? _BatchActionCircles(
                  label: '${fmtQty(batch.quantity)}'
                      '${batch.unit != null && batch.unit!.isNotEmpty ? ' ${batch.unit}' : ''}',
                  onReconcile: runProvider.showReconcile,
                  onRevert: () {
                    runProvider.closePopout();
                    _revertBatchArrival(batch);
                  },
                  onClose: runProvider.closePopout,
                )
              : _StageActionCircles(
                  onStart: () {
                    _setNodeStatus(node, NodeRunStatus.active);
                    runProvider.closePopout();
                  },
                  onMarkDone: runProvider.showReconcile,
                  onSkip: () {
                    _setNodeStatus(node, NodeRunStatus.skipped);
                    runProvider.closePopout();
                  },
                  onClose: runProvider.closePopout,
                ));

    return content;
  }

  /// Hit-testable popout overlay anchored directly above its stage. Lives
  /// outside the InteractiveViewer (so taps land and it isn't scaled by zoom),
  /// but its screen position is derived by running the stage's canvas
  /// coordinates through the viewer's current transform so it tracks the column.
  Widget _popoutOverlay(
    ProductionRunProvider runProvider,
    BatchFlowProvider batchProvider,
  ) {
    final nodeId = runProvider.popoutNodeId;
    if (nodeId == null) return const SizedBox.shrink();
    ProcessNode? found;
    for (final n in widget.template.nodes) {
      if (n.id == nodeId) {
        found = n;
        break;
      }
    }
    if (found == null) return const SizedBox.shrink();
    final node = found;

    // Top-centre of the stage block in canvas coordinates → viewport pixels.
    final canvasPoint = Offset(
      100 + (node.stageIndex * columnWidth) + (nodeWidth / 2),
      100 + (node.laneIndex * rowHeight),
    );
    final p = MatrixUtils.transformPoint(_controller.value, canvasPoint);

    return Positioned(
      left: p.dx,
      top: p.dy - 12,
      child: FractionalTranslation(
        // Centre horizontally on the column and sit just above the stage.
        translation: const Offset(-0.5, -1.0),
        child: _popoutContent(node, runProvider, batchProvider),
      ),
    );
  }

  Future<void> _setNodeStatus(ProcessNode node, NodeRunStatus status) async {
    final runProvider = context.read<ProductionRunProvider>();
    final production = context.read<ProductionProvider>();
    final repo = context.read<PipelineRunRepository>();
    final runId = runProvider.runId;
    if (runId == null) return;
    try {
      await repo.updateNodeStatus(
        runId: runId,
        nodeId: node.id,
        status: status,
      );
      switch (status) {
        case NodeRunStatus.active:
          production.setNodeStatus(node.id, 'Active');
        case NodeRunStatus.done:
          production.setNodeStatus(node.id, 'Done');
        case NodeRunStatus.skipped:
          production.skipNode(node.id);
        case NodeRunStatus.pending:
          production.setNodeStatus(node.id, 'Queued');
      }
      runProvider.triggerRefresh();
    } catch (e) {
      if (mounted) {
        showFloorToast(
          context,
          'Failed to update stage: $e',
          kind: FloorToastKind.error,
        );
      }
    }
  }

  /// The order this run is fulfilling, if any (for output item resolution).
  OrderEntry? _orderForRun() {
    try {
      final orderId = context.read<ProductionProvider>().linkedOrderId;
      if (orderId == null) return null;
      return context
          .read<OrdersProvider>()
          .orders
          .where((o) => o.id == orderId)
          .firstOrNull;
    } catch (_) {
      return null;
    }
  }

  /// Books raw-material consumption when [qty] of [barcode] leaves the Input.
  Future<void> _bookRawConsume(String barcode, double qty) async {
    try {
      final repo = context.read<InventoryRepository>();
      await repo.createInventoryMovement(
        CreateInventoryMovementInput(
          materialBarcode: barcode,
          movementType: InventoryMovementType.consume,
          qty: qty,
          reasonCode: 'PRODUCTION_CONSUME',
          actor: context.read<ProductionProvider>().activeOperator,
        ),
      );
      if (mounted) context.read<InventoryProvider>().refresh();
    } catch (e) {
      if (mounted) {
        showFloorToast(
          context,
          'Could not book raw consumption: $e',
          kind: FloorToastKind.error,
        );
      }
    }
  }

  /// Receives produced goods into inventory when a batch lands at the Output
  /// node. The concrete item is the node's specific output item, or — when the
  /// output endpoint is a group — the run's order item.
  /// Returns the produced lot barcode (for revert), or null on failure.
  Future<String?> _receiveYieldAtOutput(
    ProcessNode node,
    MaterialBatch batch,
    double qty,
  ) async {
    try {
      final repo = context.read<InventoryRepository>();
      final production = context.read<ProductionProvider>();
      final runId = context.read<ProductionRunProvider>().runId;
      final endpoint = node.outputItem ?? node.inputItem;

      int? itemId;
      int? variationLeafNodeId;
      String name;
      if (endpoint != null && !endpoint.isGroup) {
        itemId = endpoint.itemId;
        name = endpoint.itemName;
      } else {
        final order = _orderForRun();
        itemId = order?.itemId;
        variationLeafNodeId = order?.variationLeafNodeId;
        name = order?.itemName ?? endpoint?.groupName ?? 'Yield';
      }

      final lot = await repo.createChildMaterial(
        CreateChildMaterialInput(
          parentBarcode: batch.barcode,
          name: 'Yield · $name',
        ),
      );
      if (itemId != null) {
        await repo.linkMaterialToItem(
          lot.barcode,
          itemId,
          variationLeafNodeId: variationLeafNodeId,
        );
      }
      await repo.createInventoryMovement(
        CreateInventoryMovementInput(
          materialBarcode: lot.barcode,
          movementType: InventoryMovementType.receive,
          qty: qty,
          reasonCode: 'PRODUCTION_YIELD',
          actor: production.activeOperator,
          // Manual provenance: receive movements require a reference, and
          // tying it to the run links the produced stock back to production.
          referenceType: 'pipeline_run',
          referenceId: runId ?? lot.barcode,
        ),
      );
      if (mounted) context.read<InventoryProvider>().refresh();
      return lot.barcode;
    } catch (e) {
      if (mounted) {
        showFloorToast(
          context,
          'Could not receive yield into inventory: $e',
          kind: FloorToastKind.error,
        );
      }
      return null;
    }
  }

  Future<void> _handleBatchDrop(
    ProcessNode node,
    MaterialBatch batch,
    BatchFlowProvider batchProvider,
    String runId,
  ) async {
    if (batch.currentNodeId == node.id) return;
    final qty = await BatchSplitDialog.show(
      context,
      batch: batch,
      targetNodeName: node.name.isEmpty ? 'station' : node.name,
    );
    if (qty == null || !mounted) return;

    // The stage the batch is leaving. Moving stock OUT of a processing stage
    // must be accounted for; issuing raw stock from an Input endpoint moves
    // quietly.
    final sourceNode = widget.template.nodes
        .where((n) => n.id == batch.currentNodeId)
        .firstOrNull;
    final fromNodeId = batch.currentNodeId;
    final wasSplit = qty < batch.quantity;

    final resultId = batchProvider.moveBatch(
      runId: runId,
      batchId: batch.id,
      toNodeId: node.id,
      quantity: qty,
    );
    if (resultId == null) return;
    await _persistBatches(runId, batchProvider);

    // Record the move so it can be reverted with all its side effects.
    final record = BatchMoveRecord(
      resultBatchId: resultId,
      fromNodeId: fromNodeId,
      toNodeId: node.id,
      qty: qty,
      wasSplit: wasSplit,
      parentBatchId: wasSplit ? batch.id : null,
    );
    batchProvider.recordMove(runId, record);

    // Raw consumption is booked as stock leaves the Input endpoint.
    if (mounted && sourceNode?.processType == 'Input') {
      await _bookRawConsume(batch.barcode, qty);
      record
        ..consumeBarcode = batch.barcode
        ..consumeQty = qty;
    }
    // Produced goods are received into inventory as each batch lands at Output.
    if (mounted && node.processType == 'Output') {
      final lot = await _receiveYieldAtOutput(node, batch, qty);
      if (lot != null) {
        record
          ..yieldLotBarcode = lot
          ..yieldQty = qty;
      }
    }

    if (!mounted) return;
    if (sourceNode != null &&
        sourceNode.processType != 'Input' &&
        sourceNode.processType != 'Output') {
      await StageReconciliationDialog.show(
        context,
        node: sourceNode,
        runId: runId,
        batchOutput: qty,
        batchAllottedMax: batch.quantity,
        batchUnit: batch.unit,
        batchBarcode: batch.barcode,
        onCommitted: (result) {
          // Scrap/leftover declared beyond what advanced leaves the source
          // chip too, keeping the chips consistent with the ledger.
          batchProvider.reduceBatch(
            runId: runId,
            batchId: batch.id,
            amount: result.loss,
            scrap: result.scrapLogged,
            leftover: result.leftoverReturned,
          );
          record
            ..scrapLogged = result.scrapLogged
            ..leftoverReturned = result.leftoverReturned
            ..reconcileBarcode = result.barcode
            ..lossQty = result.loss;
          _persistBatches(runId, batchProvider);
        },
      );
    }
  }

  /// Reverts a batch's last forward hop — unwinds the inventory side effects
  /// (consume, yield, leftover, scrap) then the chip move itself.
  Future<void> _revertBatchArrival(MaterialBatch batch) async {
    final runProvider = context.read<ProductionRunProvider>();
    final batchProvider = context.read<BatchFlowProvider>();
    final runId = runProvider.runId;
    if (runId == null) return;

    final rec = batchProvider.lastRecordForBatch(runId, batch.id);
    if (rec == null) {
      showFloorToast(context, 'Nothing to revert for this lot.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Revert this move?'),
        content: const Text(
          'The lot returns to the previous stage and the inventory it booked '
          '(consume / yield / leftover / scrap) is reversed.',
          style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Revert'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await _reverseInventory(rec);
    if (!mounted) return;
    final ok = batchProvider.revertChip(runId, rec);
    if (ok) await _persistBatches(runId, batchProvider);
    if (mounted) {
      showFloorToast(
        context,
        ok ? 'Move reverted.' : 'Could not revert this lot.',
        kind: ok ? FloorToastKind.info : FloorToastKind.error,
      );
    }
  }

  /// Posts compensating movements to unwind a move's inventory effects. The
  /// movement API requires qty > 0, so reversal is expressed by direction:
  /// `adjust` adds raw back, `issue` removes produced/leftover stock, and scrap
  /// is netted with a negative ledger entry.
  Future<void> _reverseInventory(BatchMoveRecord rec) async {
    try {
      final repo = context.read<InventoryRepository>();
      final actor = context.read<ProductionProvider>().activeOperator;
      final pipelineRepo = context.read<PipelineRunRepository>();
      final runId = context.read<ProductionRunProvider>().runId;

      if (rec.consumeBarcode != null && rec.consumeQty > 0) {
        await repo.createInventoryMovement(
          CreateInventoryMovementInput(
            materialBarcode: rec.consumeBarcode!,
            movementType: InventoryMovementType.adjust,
            qty: rec.consumeQty,
            reasonCode: 'PRODUCTION_REVERT_CONSUME',
            actor: actor,
          ),
        );
      }
      if (rec.yieldLotBarcode != null && rec.yieldQty > 0) {
        await repo.createInventoryMovement(
          CreateInventoryMovementInput(
            materialBarcode: rec.yieldLotBarcode!,
            movementType: InventoryMovementType.issue,
            qty: rec.yieldQty,
            reasonCode: 'PRODUCTION_REVERT_YIELD',
            actor: actor,
          ),
        );
      }
      if (rec.leftoverReturned > 0 && rec.reconcileBarcode != null) {
        await repo.createInventoryMovement(
          CreateInventoryMovementInput(
            materialBarcode: rec.reconcileBarcode!,
            movementType: InventoryMovementType.issue,
            qty: rec.leftoverReturned,
            reasonCode: 'PRODUCTION_REVERT_LEFTOVER',
            actor: actor,
          ),
        );
      }
      if (rec.scrapLogged > 0 &&
          rec.reconcileBarcode != null &&
          runId != null) {
        await pipelineRepo.logProductionScrap(
          runId: runId,
          nodeId: rec.fromNodeId,
          materialBarcode: rec.reconcileBarcode!,
          scrapQty: -rec.scrapLogged,
        );
      }
      if (mounted) context.read<InventoryProvider>().refresh();
    } catch (e) {
      if (mounted) {
        showFloorToast(
          context,
          'Inventory reversal failed: $e',
          kind: FloorToastKind.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final runProvider = context.watch<ProductionRunProvider>();
    final batchProvider = context.watch<BatchFlowProvider>();
    if (runProvider.refreshCount != _lastRefreshCount ||
        runProvider.runId != _lastRunId) {
      _lastRefreshCount = runProvider.refreshCount;
      _lastRunId = runProvider.runId;
      final runId = runProvider.runId;
      if (runId != null) {
        final repo = context.read<PipelineRunRepository>();
        _runFuture = repo.getRun(runId);
      } else {
        _runFuture = null;
      }
    }

    final nodes = widget.template.nodes;
    final flows = widget.template.flows;
    final stageLabels = widget.template.stageLabels;

    return FutureBuilder<PipelineRun?>(
      future: _runFuture,
      builder: (context, snapshot) {
        final activeRun = snapshot.data;
        if (activeRun != null) {
          _seedBatchesIfNeeded(activeRun, batchProvider);
        }
        final activeStockNodeId = _findActiveStockNodeId(
          activeRun,
          widget.template,
        );

        return Column(
          children: [
            _PipelineMetricsBar(
              runId: runProvider.runId,
              run: activeRun,
              template: widget.template,
              batches: runProvider.runId == null
                  ? const []
                  : batchProvider
                        .batchesForRun(runProvider.runId!)
                        .where((b) => b.isLive)
                        .toList(),
            ),
            Expanded(
              child: Stack(
                children: [
                  DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: InteractiveViewer(
                    transformationController: _controller,
                    boundaryMargin: const EdgeInsets.all(1500),
                    minScale: 0.1,
                    maxScale: 2.0,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CustomPaint(
                          size: const Size(4000, 4000),
                          painter: GraphEdgesPainter(
                            nodes: nodes,
                            flows: flows,
                            columnWidth: columnWidth,
                            rowHeight: rowHeight,
                            nodeWidth: nodeWidth,
                            nodeHeight: nodeHeight,
                          ),
                        ),
                        // Stage Labels
                        for (int s = 0; s < stageLabels.length; s++)
                          Positioned(
                            left: 100 + (s * columnWidth),
                            top: 50,
                            width: nodeWidth,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                stageLabels[s].toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  letterSpacing: 0.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ),
                        // Nodes
                        ...nodes.map((node) {
                          final isSelected = widget.selectedNodeId == node.id;
                          final left = 100 + (node.stageIndex * columnWidth);
                          final top = 100 + (node.laneIndex * rowHeight);
                          final runId = runProvider.runId;
                          final nodeBatches = runId != null
                              ? batchProvider.batchesAtNode(runId, node.id)
                              : const <MaterialBatch>[];
                          // Once a run is seeded, chips are the single source of
                          // truth. The legacy assigned-stock card is only a fallback
                          // for un-seeded (legacy) runs — otherwise it double-shows
                          // stock a chip already represents.
                          final seeded =
                              runId != null && batchProvider.isSeeded(runId);
                          final showBarcodeCard =
                              !seeded &&
                              activeStockNodeId == node.id &&
                              nodeBatches.isEmpty;
                          final assignedBarcodes = showBarcodeCard
                              ? effectiveStageInputs(
                                  run: activeRun,
                                  node: node,
                                  template: widget.template,
                                )
                              : null;

                          return Positioned(
                            left: left,
                            top: top,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DragTarget<Object>(
                                  onWillAcceptWithDetails: (details) =>
                                      details.data is MaterialRecord ||
                                      (details.data is MaterialBatch &&
                                          (details.data as MaterialBatch)
                                                  .currentNodeId !=
                                              node.id),
                                  onAcceptWithDetails: (details) async {
                                    final runProvider = context
                                        .read<ProductionRunProvider>();
                                    final runId = runProvider.runId;
                                    if (runId == null) return;

                                    // A batch chip dropped here advances stock.
                                    if (details.data is MaterialBatch) {
                                      await _handleBatchDrop(
                                        node,
                                        details.data as MaterialBatch,
                                        batchProvider,
                                        runId,
                                      );
                                      return;
                                    }

                                    final material =
                                        details.data as MaterialRecord;
                                    final repo = context
                                        .read<PipelineRunRepository>();
                                    final quantity = await showDialog<double>(
                                      context: context,
                                      builder: (context) =>
                                          _StockAssignQtyDialog(
                                            material: material,
                                            nodeName: node.name,
                                          ),
                                    );
                                    if (quantity == null) return;

                                    try {
                                      await repo.attachBarcodeToRunNode(
                                        runId: runId,
                                        nodeId: node.id,
                                        barcode: material.barcode,
                                        quantity: quantity,
                                      );
                                      batchProvider.addStockAtNode(
                                        runId: runId,
                                        nodeId: node.id,
                                        barcode: material.barcode,
                                        materialName: material.name,
                                        quantity: quantity,
                                        unit: material.unit,
                                      );
                                      await _persistBatches(
                                        runId,
                                        batchProvider,
                                      );
                                      runProvider.triggerRefresh();
                                      if (context.mounted) {
                                        context
                                            .read<InventoryProvider>()
                                            .refresh();
                                        showFloorToast(
                                          context,
                                          'Assigned $quantity ${material.unit} of ${material.barcode} to ${node.name}',
                                          kind: FloorToastKind.info,
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        showFloorToast(
                                          context,
                                          'Failed to assign stock: $e',
                                          kind: FloorToastKind.error,
                                        );
                                      }
                                    }
                                  },
                                  builder:
                                      (context, candidateData, rejectedData) {
                                        final isHovered =
                                            candidateData.isNotEmpty;
                                        return MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: GestureDetector(
                                            onTap: () =>
                                                widget.onNodeSelected(node.id),
                                            onDoubleTap: widget
                                                        .onNodeDoubleTap ==
                                                    null
                                                ? null
                                                : () => widget.onNodeDoubleTap!(
                                                    node.id),
                                            child: Container(
                                              foregroundDecoration: isHovered
                                                  ? BoxDecoration(
                                                      color: const Color(
                                                        0xFF10B981,
                                                      ).withValues(alpha: 0.2),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      border: Border.all(
                                                        color: const Color(
                                                          0xFF10B981,
                                                        ),
                                                        width: 2,
                                                      ),
                                                    )
                                                  : null,
                                              child: FlowStageBlock(
                                                width: nodeWidth,
                                                height: nodeHeight,
                                                node:
                                                    activeRun != null &&
                                                        activeRun.nodeStatuses
                                                            .containsKey(
                                                              node.id,
                                                            )
                                                    ? node.copyWith(
                                                        status: activeRun
                                                            .nodeStatuses[node
                                                                .id]!
                                                            .value,
                                                      )
                                                    : node,
                                                isSelected: isSelected,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                ),
                                if (nodeBatches.isNotEmpty)
                                  NodeBatchTray(
                                    batches: nodeBatches,
                                    width: nodeWidth,
                                    onRevert: _revertBatchArrival,
                                  )
                                else if (assignedBarcodes != null &&
                                    assignedBarcodes.isNotEmpty)
                                  for (final input in assignedBarcodes) ...[
                                    const SizedBox(height: 6),
                                    _buildAssignedStockCard(node, input),
                                  ],
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
                  _popoutOverlay(runProvider, batchProvider),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String? _findActiveStockNodeId(PipelineRun? run, PipelineTemplate template) {
    if (run == null) return null;

    // 1. If there's an active/running node, that's where the stock is.
    for (final node in template.nodes) {
      final status = run.nodeStatuses[node.id]?.value ?? 'pending';
      if (status == 'active' || status == 'running') {
        return node.id;
      }
    }

    // 2. If no active node, find the first pending node whose predecessor is done.
    for (final node in template.nodes) {
      final status = run.nodeStatuses[node.id]?.value ?? 'pending';
      if (status == 'pending') {
        bool hasDonePredecessor = false;
        for (final flow in template.flows) {
          if (flow.toNodeId == node.id) {
            final upstreamStatus =
                run.nodeStatuses[flow.fromNodeId]?.value ?? 'pending';
            if (upstreamStatus == 'done') {
              hasDonePredecessor = true;
              break;
            }
          }
        }
        if (hasDonePredecessor) {
          return node.id;
        }
      }
    }

    // 3. If all nodes are done or skipped, it's the Output node (node with no outgoing flows).
    bool allDone = true;
    for (final node in template.nodes) {
      final status = run.nodeStatuses[node.id]?.value ?? 'pending';
      if (status != 'done' && status != 'skipped') {
        allDone = false;
        break;
      }
    }
    if (allDone) {
      for (final node in template.nodes) {
        final hasOutgoing = template.flows.any((f) => f.fromNodeId == node.id);
        if (!hasOutgoing) {
          return node.id;
        }
      }
    }

    // 4. Default: Return the Input node (no incoming flows or type is Input).
    for (final node in template.nodes) {
      final hasIncoming = template.flows.any((f) => f.toNodeId == node.id);
      if (!hasIncoming || node.processType == 'Input') {
        return node.id;
      }
    }

    return template.nodes.firstOrNull?.id;
  }
}

/// Live, per-pipeline metrics strip above the canvas — flow/throughput figures
/// that are otherwise buried in paperwork, scoped to this run. The strip is
/// always-on; a "Run insights" toggle expands deeper, threshold-driven health
/// metrics (Phase 1: Flow & time + Stockout risk, all computed client-side).
class _PipelineMetricsBar extends StatefulWidget {
  const _PipelineMetricsBar({
    required this.runId,
    required this.run,
    required this.template,
    required this.batches,
  });

  final String? runId;
  final PipelineRun? run;
  final PipelineTemplate template;
  final List<MaterialBatch> batches;

  @override
  State<_PipelineMetricsBar> createState() => _PipelineMetricsBarState();
}

class _PipelineMetricsBarState extends State<_PipelineMetricsBar> {
  bool _open = false;

  // User-tunable thresholds — recompute on change (refresh on page).
  double _maxCycleH = 8; // cycle time red above this many hours
  double _stallMin = 30; // a batch idle this long flags a stall
  double _lowStock = 100; // input ATP amber below this, red at <= 0

  static const _green = Color(0xFF10B981);
  static const _amber = Color(0xFFEAB308); // warning (yellow)
  static const _red = Color(0xFFCA8A04); // worst case — amber, no red
  static const _grey = Color(0xFF94A3B8);

  static String _dur(Duration? d) {
    if (d == null) return '—';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.runId == null) return const SizedBox.shrink();
    final run = widget.run;
    final batches = widget.batches;

    final stages = List<ProcessNode>.from(widget.template.nodes)
      ..sort((a, b) => a.stageIndex.compareTo(b.stageIndex));
    final total = stages.length;
    final done = run == null
        ? 0
        : stages
              .where((n) => run.nodeStatuses[n.id] == NodeRunStatus.done)
              .length;
    final outputId = stages.isEmpty ? null : stages.last.id;

    final qtyByNode = <String, double>{};
    for (final b in batches) {
      qtyByNode[b.currentNodeId] =
          (qtyByNode[b.currentNodeId] ?? 0) + b.quantity;
    }
    final completed = outputId == null ? 0.0 : (qtyByNode[outputId] ?? 0);
    final inFlight = batches.where((b) => b.currentNodeId != outputId).toList();
    final inFlightQty = inFlight.fold<double>(0, (s, b) => s + b.quantity);

    String bottleneck = '—';
    double bnQty = 0;
    for (final n in stages) {
      if (n.id == outputId) continue;
      final q = qtyByNode[n.id] ?? 0;
      if (q > bnQty) {
        bnQty = q;
        bottleneck =
            '${n.name.isEmpty ? n.processType : n.name} · ${fmtQty(q)}';
      }
    }

    final elapsed = run == null
        ? null
        : DateTime.now().difference(run.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _metric('STAGES DONE', '$done / $total'),
              _divider(),
              _metric('RUNNING FOR', _dur(elapsed)),
              _divider(),
              _metric(
                'MOVING',
                '${inFlight.length} · ${fmtQty(inFlightQty)}',
              ),
              _divider(),
              _metric('BUSIEST STAGE', bottleneck),
              _divider(),
              _metric('DONE', fmtQty(completed)),
              const SizedBox(width: 12),
              _InsightsToggle(
                open: _open,
                onTap: () => setState(() => _open = !_open),
              ),
            ],
          ),
          if (_open) ...[
            const Divider(height: 26, color: Color(0xFFE2E8F0)),
            _thresholdsRow(),
            const SizedBox(height: 14),
            _insights(context, stages, inFlight, elapsed, done, total),
          ],
        ],
      ),
    );
  }

  Widget _insights(
    BuildContext context,
    List<ProcessNode> stages,
    List<MaterialBatch> inFlight,
    Duration? cycle,
    int done,
    int total,
  ) {
    final now = DateTime.now();

    // Oldest idle batch → dwell/stall signal.
    Duration? oldest;
    String oldestStage = '—';
    for (final b in inFlight) {
      final at = b.createdAt;
      if (at == null) continue;
      final age = now.difference(at);
      if (oldest == null || age > oldest) {
        oldest = age;
        final n = stages.firstWhereOrNull((s) => s.id == b.currentNodeId);
        oldestStage = n == null
            ? '—'
            : (n.name.isEmpty ? n.processType : n.name);
      }
    }
    final pending = total - done;
    final stalled =
        oldest != null && oldest.inMinutes >= _stallMin && pending > 0;

    // Stockout risk per distinct input material (ATP from inventory).
    final inv = context.watch<InventoryProvider>();
    final seen = <String>{};
    final stockCards = <Widget>[];
    for (final b in widget.batches) {
      if (!seen.add(b.barcode)) continue;
      final m = inv.materials.firstWhereOrNull((x) => x.barcode == b.barcode);
      final atp = m?.availableToPromise;
      final color = atp == null
          ? _grey
          : atp <= 0
          ? _red
          : atp < _lowStock
          ? _amber
          : _green;
      stockCards.add(
        _card(
          (m?.name.trim().isNotEmpty ?? false) ? m!.name : b.barcode,
          atp == null ? '—' : '${fmtQty(atp)} free',
          atp == null
              ? 'not tracked'
              : atp <= 0
              ? 'out of stock'
              : atp < _lowStock
              ? 'running low'
              : 'ok',
          color,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('SPEED'),
        const SizedBox(height: 8),
        Row(
          children: [
            _card(
              'Time taken',
              _dur(cycle),
              'so far',
              _band(
                (cycle?.inMinutes ?? 0) / 60.0,
                _maxCycleH * 0.8,
                _maxCycleH,
              ),
            ),
            const SizedBox(width: 12),
            _card(
              'Slowest batch',
              _dur(oldest),
              oldest == null ? 'nothing moving' : 'stuck at $oldestStage',
              _band(
                (oldest?.inMinutes ?? 0).toDouble(),
                _stallMin * 0.6,
                _stallMin,
              ),
            ),
            const SizedBox(width: 12),
            _card(
              'Moving?',
              stalled ? 'Stuck' : 'Moving',
              stalled ? 'stuck over ${_stallMin.toInt()}m' : 'all good',
              stalled ? _red : _green,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionLabel('STOCK'),
        const SizedBox(height: 8),
        if (stockCards.isEmpty)
          const Text(
            'No input materials yet.',
            style: TextStyle(
              fontSize: 12,
              color: _grey,
              fontWeight: FontWeight.w600,
            ),
          )
        else
          Row(
            children: [
              for (var i = 0; i < stockCards.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                stockCards[i],
              ],
            ],
          ),
      ],
    );
  }

  /// Green below [amberAt], amber up to [redAt], red beyond.
  Color _band(double v, double amberAt, double redAt) {
    if (v >= redAt) return _red;
    if (v >= amberAt) return _amber;
    return _green;
  }

  Widget _thresholdsRow() => Row(
    children: [
      _stepper('Too slow after', _maxCycleH, 'h', 1, () {
        setState(() => _maxCycleH = (_maxCycleH - 1).clamp(1, 999));
      }, () => setState(() => _maxCycleH += 1)),
      const SizedBox(width: 18),
      _stepper('Stuck after', _stallMin, 'm', 5, () {
        setState(() => _stallMin = (_stallMin - 5).clamp(5, 999));
      }, () => setState(() => _stallMin += 5)),
      const SizedBox(width: 18),
      _stepper('Low stock below', _lowStock, '', 10, () {
        setState(() => _lowStock = (_lowStock - 10).clamp(0, 99999));
      }, () => setState(() => _lowStock += 10)),
    ],
  );

  Widget _stepper(
    String label,
    double value,
    String suffix,
    double step,
    VoidCallback onMinus,
    VoidCallback onPlus,
  ) {
    Widget btn(IconData i, VoidCallback f) => InkWell(
      onTap: f,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(i, size: 16, color: const Color(0xFF64748B)),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label  ',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _grey,
          ),
        ),
        btn(Icons.remove_circle_outline_rounded, onMinus),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '${value.toInt()}$suffix',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E293B),
            ),
          ),
        ),
        btn(Icons.add_circle_outline_rounded, onPlus),
      ],
    );
  }

  Widget _sectionLabel(String t) => Text(
    t,
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.7,
      color: _grey,
    ),
  );

  Widget _card(String label, String value, String sub, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: color == _green ? const Color(0xFF1E293B) : color,
            ),
          ),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: _grey,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _divider() => Container(
    width: 1,
    height: 28,
    color: const Color(0xFFE2E8F0),
    margin: const EdgeInsets.symmetric(horizontal: 16),
  );

  Widget _metric(String label, String value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: _grey,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    ),
  );
}

class _InsightsToggle extends StatelessWidget {
  const _InsightsToggle({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF4F46E5);
    return Material(
      color: open ? accent : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Run health',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: open ? Colors.white : const Color(0xFF475569),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                open
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 17,
                color: open ? Colors.white : const Color(0xFF64748B),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockAssignQtyDialog extends StatefulWidget {
  const _StockAssignQtyDialog({required this.material, required this.nodeName});

  final MaterialRecord material;
  final String nodeName;

  @override
  State<_StockAssignQtyDialog> createState() => _StockAssignQtyDialogState();
}

class _StockAssignQtyDialogState extends State<_StockAssignQtyDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.material.onHand.toString(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_controller.text);
    if (value == null) {
      setState(() {
        _errorText = 'Please enter a valid number';
      });
      return;
    }
    if (value <= 0) {
      setState(() {
        _errorText = 'Quantity must be greater than zero';
      });
      return;
    }
    if (value > widget.material.onHand) {
      setState(() {
        _errorText =
            'Cannot exceed available stock (${widget.material.onHand})';
      });
      return;
    }

    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.assignment_turned_in_rounded,
                    color: Color(0xFF2563EB),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Assign Stock Quantity',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Assigning ${widget.material.name} (${widget.material.barcode}) to stage "${widget.nodeName}".',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Available Stock:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
                Text(
                  '${widget.material.onHand} ${widget.material.unit}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
              decoration: InputDecoration(
                labelText: 'Quantity to Assign',
                labelStyle: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 13,
                ),
                errorText: _errorText,
                suffixText: widget.material.unit,
                suffixStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: Color(0xFF2563EB),
                    width: 2,
                  ),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Assign',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StockEditQtyDialog extends StatefulWidget {
  const _StockEditQtyDialog({
    required this.material,
    required this.nodeName,
    required this.currentQuantity,
  });

  final MaterialRecord material;
  final String nodeName;
  final double currentQuantity;

  @override
  State<_StockEditQtyDialog> createState() => _StockEditQtyDialogState();
}

class _StockEditQtyDialogState extends State<_StockEditQtyDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.currentQuantity.toString(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_controller.text);
    if (value == null) {
      setState(() {
        _errorText = 'Please enter a valid number';
      });
      return;
    }
    if (value <= 0) {
      setState(() {
        _errorText = 'Quantity must be greater than zero';
      });
      return;
    }
    final maxAllowed = widget.material.onHand + widget.currentQuantity;
    if (value > maxAllowed) {
      setState(() {
        _errorText = 'Cannot exceed total available stock ($maxAllowed)';
      });
      return;
    }

    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final maxAllowed = widget.material.onHand + widget.currentQuantity;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    color: Color(0xFF2563EB),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Edit Stock Quantity',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Editing quantity of ${widget.material.name} (${widget.material.barcode}) assigned to stage "${widget.nodeName}".',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Available Stock:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
                Text(
                  '$maxAllowed ${widget.material.unit}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
              decoration: InputDecoration(
                labelText: 'Quantity',
                labelStyle: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 13,
                ),
                errorText: _errorText,
                suffixText: widget.material.unit,
                suffixStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: Color(0xFF2563EB),
                    width: 2,
                  ),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Update',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The stage-action circles that pop above a stage/batch on double-click:
/// start • mark done • skip. "Mark done" escalates to the reconcile panel.
class _StageActionCircles extends StatelessWidget {
  const _StageActionCircles({
    required this.onStart,
    required this.onMarkDone,
    required this.onSkip,
    required this.onClose,
  });

  final VoidCallback onStart;
  final VoidCallback onMarkDone;
  final VoidCallback onSkip;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      borderRadius: BorderRadius.circular(40),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _circle(
              Icons.play_arrow_rounded,
              const Color(0xFF2563EB),
              'Start stage',
              onStart,
            ),
            const SizedBox(width: 8),
            _circle(
              Icons.check_circle_outline_rounded,
              const Color(0xFF10B981),
              'Mark done',
              onMarkDone,
            ),
            const SizedBox(width: 8),
            _circle(
              Icons.skip_next_rounded,
              const Color(0xFF64748B),
              'Skip stage',
              onSkip,
            ),
            const SizedBox(width: 4),
            _circle(
              Icons.close_rounded,
              const Color(0xFF94A3B8),
              'Close',
              onClose,
              size: 30,
            ),
          ],
        ),
      ),
    );
  }

  Widget _circle(
    IconData icon,
    Color color,
    String tooltip,
    VoidCallback onTap, {
    double size = 40,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: color, size: size * 0.55),
          ),
        ),
      ),
    );
  }
}

/// Batch-flavored popout (blue, with the batch qty) so it reads clearly as a
/// per-batch action vs the stage circles: reconcile this batch • revert move.
class _BatchActionCircles extends StatelessWidget {
  const _BatchActionCircles({
    required this.label,
    required this.onReconcile,
    required this.onRevert,
    required this.onClose,
  });

  final String label;
  final VoidCallback onReconcile;
  final VoidCallback onRevert;
  final VoidCallback onClose;

  static const Color _blue = Color(0xFF2563EB);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEFF4FF),
      elevation: 3,
      borderRadius: BorderRadius.circular(40),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_rounded, size: 16, color: _blue),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _blue,
              ),
            ),
            const SizedBox(width: 10),
            _circle(
              Icons.fact_check_rounded,
              _blue,
              'Reconcile batch',
              onReconcile,
            ),
            const SizedBox(width: 8),
            _circle(
              Icons.undo_rounded,
              const Color(0xFFD97706),
              'Revert last move',
              onRevert,
            ),
            const SizedBox(width: 4),
            _circle(
              Icons.close_rounded,
              const Color(0xFF94A3B8),
              'Close',
              onClose,
              size: 30,
            ),
          ],
        ),
      ),
    );
  }

  Widget _circle(
    IconData icon,
    Color color,
    String tooltip,
    VoidCallback onTap, {
    double size = 40,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: color, size: size * 0.55),
          ),
        ),
      ),
    );
  }
}

class _TinyIconButton extends StatelessWidget {
  const _TinyIconButton({
    required this.icon,
    required this.onTap,
    this.color = const Color(0xFF64748B),
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget button = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 12, color: color),
        ),
      ),
    );
    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
