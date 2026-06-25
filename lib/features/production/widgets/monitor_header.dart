import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/features/orders/presentation/providers/orders_provider.dart';
import '../providers/production_provider.dart';
import '../providers/production_run_provider.dart';
import '../providers/batch_flow_provider.dart';
import 'order_fulfillment_prompt_dialog.dart';
import 'floor_toast.dart';

class MonitorHeader extends StatelessWidget {
  const MonitorHeader({super.key, required this.provider});

  final ProductionProvider provider;

  @override
  Widget build(BuildContext context) {
    final runState = context.select<ProductionRunProvider, ProductionState>(
      (p) => p.state,
    );
    final running = runState == ProductionState.running;
    final paused = runState == ProductionState.paused;
    final text = running
        ? 'LIVE'
        : paused
            ? 'PAUSED'
            : 'STANDBY';
    final runId = context.select<ProductionRunProvider, String>(
      (p) => p.runId ?? 'NO-RUN',
    );
    final operatorName = context.select<ProductionProvider, String>(
      (p) => p.activeOperator,
    );
    final orderNo = provider.linkedOrderNo;
    final clientName = provider.linkedClientName;

    final Color statusColor;
    switch (runState) {
      case ProductionState.running:
        statusColor = const Color(0xFF10B981);
      case ProductionState.paused:
      case ProductionState.idle:
      case ProductionState.setup:
      case ProductionState.completed:
        statusColor = const Color(0xFFF59E0B);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF94A3B8).withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
            color: const Color(0xFF64748B),
            tooltip: 'Exit Production Canvas',
          ),
          const SizedBox(width: 8),
          _PulsingDot(color: statusColor, isPulsing: running),
          const SizedBox(width: 16),
          _HeaderData(label: 'SYSTEM STATE', value: text, color: statusColor),
          const SizedBox(width: 32),
          _HeaderData(label: 'ACTIVE RUN', value: runId, color: const Color(0xFF0F172A)),
          const SizedBox(width: 32),
          _HeaderData(
            label: 'LEAD ENGINEER',
            value: operatorName.isEmpty ? 'ENG-ADMIN' : operatorName,
            color: const Color(0xFF64748B),
          ),
          const SizedBox(width: 32),
          _HeaderData(
            label: 'ORDER',
            value: orderNo != null ? '$orderNo ($clientName)' : '—',
            color: const Color(0xFF64748B),
          ),
          const Spacer(),
          AppButton(
            onPressed: () => _completeOrder(context),
            icon: Icons.task_alt_rounded,
            label: 'Complete Order',
          ),
        ],
      ),
    );
  }

  /// Marks the order complete — but only once every batch has reached an
  /// Output node. Lots still on any stage block completion.
  Future<void> _completeOrder(BuildContext context) async {
    final runProvider = context.read<ProductionRunProvider>();
    final batchProvider = context.read<BatchFlowProvider>();
    final production = context.read<ProductionProvider>();
    final runId = runProvider.runId;
    if (runId == null) {
      showFloorToast(context, 'No active run.', kind: FloorToastKind.error);
      return;
    }

    final outputIds = production.template.nodes
        .where((n) => n.processType == 'Output')
        .map((n) => n.id)
        .toSet();
    final batches = batchProvider.batchesForRun(runId);
    final inFlight = batches
        .where((b) => b.isLive && !outputIds.contains(b.currentNodeId))
        .toList();

    if (inFlight.isNotEmpty) {
      final total = inFlight.fold<double>(0, (s, b) => s + b.quantity);
      showFloorToast(
        context,
        '${inFlight.length} lot(s) ($total) still on the floor — move them '
        'to Output before completing the order.',
      );
      return;
    }

    final produced = batches
        .where((b) => b.isLive && outputIds.contains(b.currentNodeId))
        .fold<double>(0, (s, b) => s + b.quantity);

    final orderId = production.linkedOrderId;
    final order = orderId == null
        ? null
        : context
              .read<OrdersProvider>()
              .orders
              .where((o) => o.id == orderId)
              .firstOrNull;

    if (order != null) {
      await showDialog<void>(
        context: context,
        builder: (_) => OrderFulfillmentPromptDialog(
          order: order,
          yieldProduced: produced.round(),
        ),
      );
    }
    await runProvider.completeRun();
  }
}

class _HeaderData extends StatelessWidget {
  const _HeaderData({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color, required this.isPulsing});

  final Color color;
  final bool isPulsing;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.isPulsing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulsingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPulsing && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isPulsing) {
      _controller.stop();
    }
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
        return Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: widget.isPulsing
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.4 * _controller.value),
                      blurRadius: 8 + 4 * _controller.value,
                      spreadRadius: 2 * _controller.value,
                    )
                  ]
                : null,
          ),
        );
      },
    );
  }
}

