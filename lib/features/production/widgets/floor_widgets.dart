import 'package:flutter/material.dart';
import '../domain/models/floor_view_models.dart';

class PipelineCard extends StatelessWidget {
  const PipelineCard({
    super.key,
    required this.tokens,
    required this.pipeline,
    required this.selected,
    required this.onTap,
    this.onOrderTapped,
  });

  final FloorOpsTokens tokens;
  final PipelineSummary pipeline;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<String>? onOrderTapped;

  @override
  Widget build(BuildContext context) {
    final statusColor = tokens.pipelineStatus(pipeline.status);

    return Semantics(
      label:
          '${pipeline.name}, ${pipeline.status.label}, OEE ${pipeline.oee.toStringAsFixed(1)} percent',
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: selected
                  ? tokens.selection.withValues(alpha: 0.08)
                  : tokens.surfaceFloating.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? tokens.selection : tokens.borderSubtle,
                width: selected ? 1.3 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        pipeline.name,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    StatusChip(
                      tokens: tokens,
                      label: pipeline.status.label,
                      color: statusColor,
                    ),
                  ],
                ),
                if (pipeline.orderNo != null && pipeline.orderNo!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => onOrderTapped?.call(pipeline.orderNo!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: tokens.selection.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: tokens.selection.withOpacity(0.2)),
                      ),
                      child: Text(
                        'Order #${pipeline.orderNo}${pipeline.clientName != null && pipeline.clientName!.isNotEmpty ? ' • ${pipeline.clientName}' : ''}',
                        style: TextStyle(
                          color: tokens.selection,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      '${pipeline.oee.toStringAsFixed(1)}% OEE',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Queue ${pipeline.queueMinutes}m',
                      style: TextStyle(
                        color: pipeline.queueMinutes >= 18
                            ? tokens.warning
                            : tokens.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                MiniMetricBar(
                  tokens: tokens,
                  value: pipeline.progress,
                  color: statusColor,
                  height: 6,
                ),
                const SizedBox(height: 8),
                Text(
                  '${formatInt(pipeline.outputActual)} / ${formatInt(pipeline.outputTarget)} units',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _TinyFact(
                      tokens: tokens,
                      text: '${pipeline.stationCount} stn',
                    ),
                    _TinyFact(
                      tokens: tokens,
                      text: '${pipeline.activeOperators} ops',
                    ),
                    _TinyFact(
                      tokens: tokens,
                      text: '${pipeline.alertCount} alerts',
                      color: pipeline.alertCount > 0 ? tokens.warning : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.tokens,
    required this.label,
    required this.color,
  });

  final FloorOpsTokens tokens;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.35,
        ),
      ),
    );
  }
}

class MiniMetricBar extends StatelessWidget {
  const MiniMetricBar({
    super.key,
    required this.tokens,
    required this.value,
    required this.color,
    this.height = 6,
  });

  final FloorOpsTokens tokens;
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: tokens.borderSubtle.withValues(alpha: 0.55),
              ),
            ),
            FractionallySizedBox(
              widthFactor: value.clamp(0, 1).toDouble(),
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.tokens,
    required this.title,
    required this.value,
    required this.secondary,
    required this.semanticLabel,
    required this.child,
  });

  final FloorOpsTokens tokens;
  final String title;
  final String value;
  final String secondary;
  final String semanticLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 11),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tokens.surfaceFloating.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 23,
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              secondary,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (child is! SizedBox) ...[const SizedBox(height: 12), child],
          ],
        ),
      ),
    );
  }
}

class AlertSummaryItem extends StatelessWidget {
  const AlertSummaryItem({
    super.key,
    required this.tokens,
    required this.alert,
    this.onTap,
  });

  final FloorOpsTokens tokens;
  final FloorAlert alert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = tokens.alertSeverity(alert.severity);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_alertIcon(alert.severity), color: color, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.title,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alert.message,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _alertIcon(AlertSeverity severity) {
    return switch (severity) {
      AlertSeverity.info => Icons.info_outline_rounded,
      AlertSeverity.warning => Icons.warning_amber_rounded,
      AlertSeverity.danger => Icons.block_rounded,
    };
  }
}

class MapZoomControls extends StatelessWidget {
  const MapZoomControls({
    super.key,
    required this.tokens,
    this.onZoomIn,
    this.onZoomOut,
    this.onFit,
  });

  final FloorOpsTokens tokens;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onFit;

  @override
  Widget build(BuildContext context) {
    return _FloatingMapPanel(
      tokens: tokens,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MapToolIcon(
            tokens: tokens,
            icon: Icons.remove_rounded,
            label: 'Zoom out',
            onPressed: onZoomOut,
          ),
          _MapToolIcon(
            tokens: tokens,
            icon: Icons.add_rounded,
            label: 'Zoom in',
            onPressed: onZoomIn,
          ),
          _MapToolIcon(
            tokens: tokens,
            icon: Icons.fit_screen_rounded,
            label: 'Fit floor',
            onPressed: onFit,
          ),
        ],
      ),
    );
  }
}

class MapLegend extends StatelessWidget {
  const MapLegend({super.key, required this.tokens});

  final FloorOpsTokens tokens;

  @override
  Widget build(BuildContext context) {
    return _FloatingMapPanel(
      tokens: tokens,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendItem(tokens: tokens, color: tokens.success, label: 'Running'),
          _LegendItem(tokens: tokens, color: tokens.warning, label: 'Waiting'),
          _LegendItem(tokens: tokens, color: tokens.danger, label: 'Blocked'),
          _LegendItem(
            tokens: tokens,
            color: tokens.warning,
            label: 'Bottleneck',
            icon: Icons.priority_high_rounded,
          ),
        ],
      ),
    );
  }
}

class _TinyFact extends StatelessWidget {
  const _TinyFact({required this.tokens, required this.text, this.color});

  final FloorOpsTokens tokens;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? tokens.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: tone,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MapToolIcon extends StatelessWidget {
  const _MapToolIcon({
    required this.tokens,
    required this.icon,
    required this.label,
    this.onPressed,
  });

  final FloorOpsTokens tokens;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: SizedBox.square(
        dimension: 28,
        child: IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: onPressed ?? () {},
          icon: Icon(icon, size: 17, color: tokens.textPrimary),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.tokens,
    required this.color,
    required this.label,
    this.icon,
  });

  final FloorOpsTokens tokens;
  final Color color;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tokens.surfaceFloating,
              border: Border.all(color: color, width: 3),
            ),
            child: icon == null ? null : Icon(icon, size: 7, color: color),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingMapPanel extends StatelessWidget {
  const _FloatingMapPanel({required this.tokens, required this.child});

  final FloorOpsTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceFloating.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: child,
      ),
    );
  }
}

String formatInt(num value) {
  final text = value.round().toString();
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
