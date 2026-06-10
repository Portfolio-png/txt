import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/production_provider.dart';
import '../providers/production_run_provider.dart';

class MonitorHeader extends StatelessWidget {
  const MonitorHeader({
    super.key,
    required this.provider,
    this.showTestPanel = false,
    this.onToggleTestPanel,
  });

  final ProductionProvider provider;
  final bool showTestPanel;
  final VoidCallback? onToggleTestPanel;

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
          const _ElapsedClockLight(),
          if (onToggleTestPanel != null) ...[
            const SizedBox(width: 16),
            IconButton(
              icon: Icon(
                Icons.science_rounded,
                color: showTestPanel ? const Color(0xFF2563EB) : const Color(0xFF64748B),
              ),
              onPressed: onToggleTestPanel,
              tooltip: 'Toggle Developer Simulator',
            ),
          ],
        ],
      ),
    );
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

class _ElapsedClockLight extends StatelessWidget {
  const _ElapsedClockLight();

  @override
  Widget build(BuildContext context) {
    return Selector<ProductionRunProvider, String>(
      selector: (context, provider) => provider.elapsedDisplay,
      builder: (context, elapsedDisplay, child) {
        return Text(
          elapsedDisplay,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontFamily: 'monospace',
            fontSize: 28,
            fontWeight: FontWeight.w300,
            letterSpacing: 2,
          ),
        );
      },
    );
  }
}
