import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../production_pipelines/domain/process_node.dart';
import '../../production_pipelines/domain/pipeline_run.dart';
import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../providers/production_run_provider.dart';
import '../domain/models/floor_view_models.dart';
import 'editable_metric_box.dart';

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
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[date.month - 1];
    final day = date.day;
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final amPm = date.hour >= 12 ? 'PM' : 'AM';
    return '$month $day, $hour:$minute $amPm';
  }

  @override
  Widget build(BuildContext context) {
    final inputName = node.inputItem?.itemName ?? (node.inputs.isNotEmpty ? node.inputs.first : null);
    final outputName = node.outputItem?.itemName ?? (node.outputs.isNotEmpty ? node.outputs.first : null);

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
            flex: 2,
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
                  node.processType.isEmpty ? 'Generic Process' : node.processType,
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
            flex: 5,
            child: Row(
              children: [
                _MetricBox(
                  label: 'STATUS',
                  value: node.status.toUpperCase(),
                  valueColor: node.statusColor,
                ),
                const SizedBox(width: 20),
                _MetricBox(
                  label: 'MACHINE',
                  value: node.hasMachineAssignment
                      ? node.machineAssignmentLabel
                      : 'Unassigned',
                ),
                const SizedBox(width: 20),
                _MetricBox(
                  label: 'INPUT',
                  value: inputName ?? '—',
                ),
                const SizedBox(width: 20),
                _AssignedStockMetric(nodeId: node.id),
                const SizedBox(width: 20),
                EditableMetricBox(nodeId: node.id, metricKey: 'remaining', label: 'REMAINING'),
                const SizedBox(width: 20),
                EditableMetricBox(nodeId: node.id, metricKey: 'scrap', label: 'SCRAP'),
                const SizedBox(width: 20),
                _MetricBox(
                  label: 'OUTPUT',
                  value: outputName ?? '—',
                ),
                const SizedBox(width: 20),
                _MetricBox(
                  label: 'DURATION',
                  value: '${node.durationHours}h',
                ),
                const SizedBox(width: 20),
                _MetricBox(
                  label: 'STARTED',
                  value: startedAt != null ? _formatDate(startedAt!) : '—',
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
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
  const _MetricBox({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
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
  const _AssignedStockMetric({required this.nodeId});

  final String nodeId;

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
      return const _MetricBox(label: 'ASSIGNED', value: '—');
    }
    return FutureBuilder<PipelineRun?>(
      future: _runFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _MetricBox(label: 'ASSIGNED', value: '...');
        }
        final run = snapshot.data;
        if (run == null) return const _MetricBox(label: 'ASSIGNED', value: '—');
        final inputs = run.attachedBarcodeInputs[widget.nodeId] ?? [];
        if (inputs.isEmpty) return const _MetricBox(label: 'ASSIGNED', value: 'None');
        return _MetricBox(
          label: 'ASSIGNED',
          value: inputs.map((b) {
            if (b.quantity != null) {
              final unitStr = b.unit != null && b.unit!.isNotEmpty ? ' ${b.unit}' : '';
              return '${b.barcode} (${b.quantity}$unitStr)';
            }
            return b.barcode;
          }).join(', '),
        );
      },
    );
  }
}

class _ProcessingAnimationOverlay extends StatefulWidget {
  final Color color;
  const _ProcessingAnimationOverlay({required this.color});

  @override
  State<_ProcessingAnimationOverlay> createState() => _ProcessingAnimationOverlayState();
}

class _ProcessingAnimationOverlayState extends State<_ProcessingAnimationOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat();
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
