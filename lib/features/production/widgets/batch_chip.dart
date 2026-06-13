import 'package:flutter/material.dart';

import '../../production_pipelines/domain/material_batch.dart';

/// A tactile, draggable token representing a [MaterialBatch] parked at a node.
///
/// Uses [LongPressDraggable] so "lifting a chip" is a deliberate press-and-hold
/// gesture — it reads as picking up a physical token and never fights the
/// canvas's pan/zoom. While dragging, the source chip ghosts out and a larger
/// elevated chip follows the finger.
class BatchChip extends StatelessWidget {
  const BatchChip({super.key, required this.batch, this.compact = false});

  final MaterialBatch batch;
  final bool compact;

  String _fmtQty(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final body = _ChipBody(
      label: '${_fmtQty(batch.quantity)} ${batch.unitLabel}'.trim(),
      sub: batch.materialName,
      compact: compact,
    );

    return LongPressDraggable<MaterialBatch>(
      data: batch,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Transform.translate(
        offset: const Offset(-40, -24),
        child: Material(
          color: Colors.transparent,
          child: Transform.scale(
            scale: 1.12,
            child: _ChipBody(
              label: '${_fmtQty(batch.quantity)} ${batch.unitLabel}'.trim(),
              sub: batch.materialName,
              elevated: true,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: body),
      child: Tooltip(
        message: 'Hold to lift • drop on a station to move',
        waitDuration: const Duration(milliseconds: 600),
        child: body,
      ),
    );
  }
}

class _ChipBody extends StatelessWidget {
  const _ChipBody({
    required this.label,
    required this.sub,
    this.compact = false,
    this.elevated = false,
  });

  final String label;
  final String sub;
  final bool compact;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: elevated ? 0.45 : 0.2),
            blurRadius: elevated ? 16 : 6,
            offset: Offset(0, elevated ? 6 : 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.token_rounded, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                if (!compact && sub.isNotEmpty)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks how much of [batch] to move forward. Returns the chosen quantity, or
/// null if cancelled. Defaults to moving the whole batch.
class BatchSplitDialog extends StatefulWidget {
  const BatchSplitDialog({
    super.key,
    required this.batch,
    required this.targetNodeName,
  });

  final MaterialBatch batch;
  final String targetNodeName;

  static Future<double?> show(
    BuildContext context, {
    required MaterialBatch batch,
    required String targetNodeName,
  }) {
    return showDialog<double>(
      context: context,
      builder: (_) =>
          BatchSplitDialog(batch: batch, targetNodeName: targetNodeName),
    );
  }

  @override
  State<BatchSplitDialog> createState() => _BatchSplitDialogState();
}

class _BatchSplitDialogState extends State<BatchSplitDialog> {
  late double _qty = widget.batch.quantity;

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final max = widget.batch.quantity;
    final unit = widget.batch.unitLabel;
    final isPartial = _qty < max;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Move to "${widget.targetNodeName}"',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${widget.batch.materialName} · ${_fmt(max)} $unit available',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Quantity to move',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                    ),
                  ),
                  Text(
                    '${_fmt(_qty)} $unit',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ],
              ),
              Slider(
                value: _qty.clamp(0, max).toDouble(),
                min: 0,
                max: max,
                divisions: max >= 1 ? max.round().clamp(1, 1000) : null,
                label: _fmt(_qty),
                onChanged: (v) => setState(() => _qty = v),
              ),
              Row(
                children: [
                  _PresetButton(
                    label: 'Half',
                    onTap: () => setState(() => _qty = max / 2),
                  ),
                  const SizedBox(width: 8),
                  _PresetButton(
                    label: 'All',
                    onTap: () => setState(() => _qty = max),
                  ),
                  const Spacer(),
                  if (isPartial)
                    Text(
                      'Splits • ${_fmt(max - _qty)} $unit stays',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _qty <= 0
                        ? null
                        : () => Navigator.of(context).pop(_qty),
                    icon: const Icon(Icons.east_rounded, size: 18),
                    label: const Text('Move'),
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

class _PresetButton extends StatelessWidget {
  const _PresetButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        minimumSize: Size.zero,
        side: const BorderSide(color: Color(0xFFCBD5E1)),
        foregroundColor: const Color(0xFF475569),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}
