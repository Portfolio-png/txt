import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../production_pipelines/domain/node_run_status.dart';
import '../../production_pipelines/domain/process_node.dart';
import '../../production_pipelines/domain/pipeline_run.dart';
import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../providers/production_provider.dart';
import '../providers/production_run_provider.dart';
import '../domain/models/floor_view_models.dart';
import '../domain/utils/stage_input_resolver.dart';
import 'editable_metric_box.dart';
import 'stage_reconciliation_dialog.dart';

class FloorNodeTerminal extends StatelessWidget {
  const FloorNodeTerminal({
    super.key,
    required this.node,
    required this.tokens,
    required this.onClose,
    this.startedAt,
  });

  final ProcessNode node;
  final FloorOpsTokens tokens;
  final VoidCallback onClose;
  final DateTime? startedAt;

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[date.month - 1];
    final day = date.day;
    final hour = date.hour > 12
        ? date.hour - 12
        : (date.hour == 0 ? 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final amPm = date.hour >= 12 ? 'PM' : 'AM';
    return '$month $day, $hour:$minute $amPm';
  }

  @override
  Widget build(BuildContext context) {
    final inputName =
        node.inputItem?.itemName ??
        (node.inputs.isNotEmpty ? node.inputs.first : null);
    final outputName =
        node.outputItem?.itemName ??
        (node.outputs.isNotEmpty ? node.outputs.first : null);

    return Container(
      margin: const EdgeInsets.only(bottom: 24, left: 24, right: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          if (node.status == 'active' || node.status == 'running')
            Positioned.fill(
              child: _ProcessingAnimationOverlay(color: node.statusColor),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Section 1: Node identity
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: node.statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              node.name.isEmpty ? 'Unnamed Station' : node.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          node.processType.isEmpty ? 'Generic Process' : node.processType,
                          if (node.hasMachineAssignment) node.machineAssignmentLabel,
                          if (node.durationHours > 0) '${node.durationHours}h',
                          if (startedAt != null) _formatDate(startedAt!),
                        ].join('  •  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Vertical divider
                Container(
                  width: 1,
                  height: 40,
                  color: const Color(0xFFE2E8F0),
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                ),
                // Section 2: Metrics row
                Expanded(
                  flex: 7,
                  child: Row(
                    children: [
                      _MetricBox(
                        label: 'STATUS',
                        value: node.status.toUpperCase(),
                        valueColor: node.statusColor,
                      ),
                      const SizedBox(width: 24),
                      _AssignedStockMetric(node: node, flex: 2),
                      const SizedBox(width: 24),
                      EditableMetricBox(
                        nodeId: node.id,
                        metricKey: 'output',
                        label: 'OUTPUT QTY',
                      ),
                      const SizedBox(width: 24),
                      EditableMetricBox(
                        nodeId: node.id,
                        metricKey: 'remaining',
                        label: 'LEFTOVER',
                      ),
                      const SizedBox(width: 24),
                      EditableMetricBox(
                        nodeId: node.id,
                        metricKey: 'scrap',
                        label: 'SCRAP',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (node.processType != 'Input' && node.processType != 'Output')
                  _StageControls(node: node),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF94A3B8),
                  ),
                  onPressed: onClose,
                  tooltip: 'Close Panel',
                  splashRadius: 20,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricBox extends StatelessWidget {
  const _MetricBox({required this.label, required this.value, this.valueColor, this.flex = 1});

  final String label;
  final String value;
  final Color? valueColor;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignedStockMetric extends StatefulWidget {
  const _AssignedStockMetric({required this.node, this.flex = 1});

  final ProcessNode node;
  final int flex;

  @override
  State<_AssignedStockMetric> createState() => _AssignedStockMetricState();
}

class _AssignedStockMetricState extends State<_AssignedStockMetric> {
  Future<PipelineRun?>? _runFuture;
  String? _lastRunId;
  int _lastRefreshCount = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final runProvider = Provider.of<ProductionRunProvider>(context);
    final runId = runProvider.runId;
    final refreshCount = runProvider.refreshCount;

    if (runId != _lastRunId || refreshCount != _lastRefreshCount) {
      _lastRunId = runId;
      _lastRefreshCount = refreshCount;
      if (runId != null) {
        _runFuture = context.read<PipelineRunRepository>().getRun(runId);
      } else {
        _runFuture = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_runFuture == null) {
      return _MetricBox(label: 'ASSIGNED', value: '—', flex: widget.flex);
    }
    return FutureBuilder<PipelineRun?>(
      future: _runFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _MetricBox(label: 'ASSIGNED', value: '...', flex: widget.flex);
        }
        final run = snapshot.data;
        if (run == null) return _MetricBox(label: 'ASSIGNED', value: '—', flex: widget.flex);
        final inputs = effectiveStageInputs(
          run: run,
          node: widget.node,
          template: context.read<ProductionProvider>().template,
        );
        if (inputs.isEmpty)
          return _MetricBox(label: 'ASSIGNED', value: 'None', flex: widget.flex);
        return _MetricBox(
          label: 'ASSIGNED',
          flex: widget.flex,
          value: inputs
              .map((b) {
                if (b.quantity != null) {
                  final unitStr = b.unit != null && b.unit!.isNotEmpty
                      ? ' ${b.unit}'
                      : '';
                  return '${b.barcode} (${b.quantity}$unitStr)';
                }
                return b.barcode;
              })
              .join(', '),
        );
      },
    );
  }
}

class _ProcessingAnimationOverlay extends StatefulWidget {
  final Color color;
  const _ProcessingAnimationOverlay({required this.color});

  @override
  State<_ProcessingAnimationOverlay> createState() =>
      _ProcessingAnimationOverlayState();
}

class _ProcessingAnimationOverlayState
    extends State<_ProcessingAnimationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return FractionallySizedBox(
          widthFactor: 0.3,
          alignment: Alignment(-1.5 + (_controller.value * 3.0), 0),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.0),
                  widget.color.withValues(alpha: 0.08),
                  Colors.white.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Per-stage controls for the engineer: start, complete, or skip a stage and
/// reconcile its material — everything the floor operator would otherwise do.
/// Marking a stage done first forces reconciliation when the allotted
/// material has not been fully accounted for.
class _StageControls extends StatefulWidget {
  const _StageControls({required this.node});

  final ProcessNode node;

  @override
  State<_StageControls> createState() => _StageControlsState();
}

class _StageControlsState extends State<_StageControls> {
  bool _isBusy = false;

  @override
  Widget build(BuildContext context) {
    final runId = context.watch<ProductionRunProvider>().runId;
    final enabled = runId != null && !_isBusy;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ControlIcon(
          icon: Icons.play_arrow_rounded,
          tooltip: 'Start stage',
          color: const Color(0xFF2563EB),
          onPressed: enabled ? () => _setStatus(NodeRunStatus.active) : null,
        ),
        const SizedBox(width: 4),
        _ControlIcon(
          icon: Icons.check_circle_outline_rounded,
          tooltip: 'Mark stage done',
          color: const Color(0xFF10B981),
          onPressed: enabled ? () => _setStatus(NodeRunStatus.done) : null,
        ),
        const SizedBox(width: 4),
        _ControlIcon(
          icon: Icons.skip_next_rounded,
          tooltip: 'Skip stage',
          color: const Color(0xFF64748B),
          onPressed: enabled ? () => _setStatus(NodeRunStatus.skipped) : null,
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: enabled
              ? () => StageReconciliationDialog.show(
                  context,
                  node: widget.node,
                  runId: runId,
                )
              : null,
          icon: _isBusy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.fact_check_rounded, size: 16),
          label: const Text('Reconcile'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _setStatus(NodeRunStatus status) async {
    final runProvider = context.read<ProductionRunProvider>();
    final production = context.read<ProductionProvider>();
    final repo = context.read<PipelineRunRepository>();
    final runId = runProvider.runId;
    if (runId == null || _isBusy) return;

    // The engineer must account for the material before closing the stage.
    if (status == NodeRunStatus.done) {
      final reconciled = await _ensureReconciled(repo, runId);
      if (!reconciled || !mounted) return;
    }

    setState(() => _isBusy = true);
    try {
      await repo.updateNodeStatus(
        runId: runId,
        nodeId: widget.node.id,
        status: status,
      );
      switch (status) {
        case NodeRunStatus.active:
          production.setNodeStatus(widget.node.id, 'Active');
        case NodeRunStatus.done:
          production.setNodeStatus(widget.node.id, 'Done');
        case NodeRunStatus.skipped:
          production.skipNode(widget.node.id);
        case NodeRunStatus.pending:
          production.setNodeStatus(widget.node.id, 'Queued');
      }
      runProvider.triggerRefresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update stage: $e')));
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// Returns true when the stage's allotted material is fully accounted for
  /// (output + leftover + scrap), prompting the reconciliation dialog if not.
  Future<bool> _ensureReconciled(
    PipelineRunRepository repo,
    String runId,
  ) async {
    PipelineRun? run;
    final template = context.read<ProductionProvider>().template;
    try {
      run = await repo.getRun(runId);
    } catch (_) {}
    final inputs = effectiveStageInputs(
      run: run,
      node: widget.node,
      template: template,
    );
    double allotted = 0;
    for (final input in inputs) {
      allotted += input.quantity ?? 0;
    }
    if (allotted <= 0) {
      // Nothing was allotted to this stage; nothing to account for.
      return true;
    }
    final metrics = run?.nodeMetrics[widget.node.id] ?? const {};
    final output = (metrics['output'] as num?)?.toDouble();
    final remaining = (metrics['remaining'] as num?)?.toDouble() ?? 0;
    final scrap = (metrics['scrap'] as num?)?.toDouble() ?? 0;
    final accounted =
        output != null &&
        ((output + remaining + scrap) - allotted).abs() <= 0.001;
    if (accounted) return true;
    if (!mounted) return false;
    final committed = await StageReconciliationDialog.show(
      context,
      node: widget.node,
      runId: runId,
    );
    return committed == true;
  }
}

class _ControlIcon extends StatelessWidget {
  const _ControlIcon({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      splashRadius: 18,
      style: IconButton.styleFrom(
        foregroundColor: color,
        backgroundColor: color.withValues(alpha: 0.08),
        side: BorderSide(color: color.withValues(alpha: 0.25)),
      ),
    );
  }
}
