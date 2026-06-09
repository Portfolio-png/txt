import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/features/inventory/domain/material_record.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import '../providers/production_run_provider.dart';
import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/pipeline_template.dart';
import '../../production_pipelines/domain/pipeline_run.dart';
import '../../production_pipelines/domain/barcode_input.dart';
import '../../production_pipelines/domain/process_node.dart';
import 'graph_edges_painter.dart';
import 'flow_stage_block.dart';

class PipelineCanvas extends StatefulWidget {
  const PipelineCanvas({
    super.key,
    required this.template,
    required this.selectedNodeId,
    required this.onNodeSelected,
  });

  final PipelineTemplate template;
  final String? selectedNodeId;
  final ValueChanged<String> onNodeSelected;

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
      final material = await context.read<InventoryProvider>().lookupBarcode(input.barcode);
      if (material == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to locate material record for barcode ${input.barcode}')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated assigned quantity of ${input.barcode} to $newQty ${input.unit ?? ''}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update quantity: $e')),
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
        title: const Text('Remove Assigned Stock', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text('Are you sure you want to remove barcode "${input.barcode}" from step "${node.name}"?\nThis will return the assigned quantity back to inventory.', style: const TextStyle(fontSize: 13, color: Color(0xFF475569))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove', style: TextStyle(fontWeight: FontWeight.bold)),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed ${input.barcode} from ${node.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove stock: $e')),
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

  @override
  Widget build(BuildContext context) {
    final runProvider = context.watch<ProductionRunProvider>();
    if (runProvider.refreshCount != _lastRefreshCount || runProvider.runId != _lastRunId) {
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

        return DecoratedBox(
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
                    final assignedBarcodes = activeRun?.attachedBarcodeInputs[node.id];

                    return Positioned(
                      left: left,
                      top: top,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DragTarget(
                            onAcceptWithDetails: (details) async {
                              final material = details.data as MaterialRecord;
                              final runProvider = context.read<ProductionRunProvider>();
                              final repo = context.read<PipelineRunRepository>();
                              if (runProvider.runId != null) {
                                final quantity = await showDialog<double>(
                                  context: context,
                                  builder: (context) => _StockAssignQtyDialog(
                                    material: material,
                                    nodeName: node.name,
                                  ),
                                );
                                if (quantity == null) return;

                                try {
                                  await repo.attachBarcodeToRunNode(
                                    runId: runProvider.runId!,
                                    nodeId: node.id,
                                    barcode: material.barcode,
                                    quantity: quantity,
                                  );
                                  runProvider.triggerRefresh();
                                  if (context.mounted) {
                                    context.read<InventoryProvider>().refresh();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Assigned $quantity ${material.unit} of ${material.barcode} to ${node.name}')),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Failed to assign stock: $e')),
                                    );
                                  }
                                }
                              }
                            },
                            builder: (context, candidateData, rejectedData) {
                              final isHovered = candidateData.isNotEmpty;
                              return MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () => widget.onNodeSelected(node.id),
                                  child: Container(
                                    foregroundDecoration: isHovered
                                        ? BoxDecoration(
                                            color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: const Color(0xFF10B981),
                                              width: 2,
                                            ),
                                          )
                                        : null,
                                    child: FlowStageBlock(
                                      width: nodeWidth,
                                      height: nodeHeight,
                                      node: node,
                                      isSelected: isSelected,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          if (assignedBarcodes != null && assignedBarcodes.isNotEmpty)
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
        );
      },
    );
  }
}

class _StockAssignQtyDialog extends StatefulWidget {
  const _StockAssignQtyDialog({
    required this.material,
    required this.nodeName,
  });

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
    _controller = TextEditingController(text: widget.material.onHand.toString());
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
        _errorText = 'Cannot exceed available stock (${widget.material.onHand})';
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
              decoration: InputDecoration(
                labelText: 'Quantity to Assign',
                labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                errorText: _errorText,
                suffixText: widget.material.unit,
                suffixStyle: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text(
                    'Assign',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
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
    _controller = TextEditingController(text: widget.currentQuantity.toString());
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
              decoration: InputDecoration(
                labelText: 'Quantity',
                labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                errorText: _errorText,
                suffixText: widget.material.unit,
                suffixStyle: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text(
                    'Update',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
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
          child: Icon(
            icon,
            size: 12,
            color: color,
          ),
        ),
      ),
    );
    if (tooltip != null) {
      button = Tooltip(
        message: tooltip!,
        child: button,
      );
    }
    return button;
  }
}

