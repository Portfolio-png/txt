import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../production_pipelines/domain/material_batch.dart';
import '../providers/production_run_provider.dart';

/// A tactile, draggable token representing a [MaterialBatch] parked at a node.
class BatchChip extends StatelessWidget {
  const BatchChip({
    super.key,
    required this.batch,
    this.compact = false,
    this.onRevert,
  });

  final MaterialBatch batch;
  final bool compact;
  final VoidCallback? onRevert;

  @override
  Widget build(BuildContext context) {
    final unitStr = batch.unitLabel == '-' ? '' : ' ${batch.unitLabel}';
    
    final body = _ChipBody(
      label: '${fmtQty(batch.quantity)}$unitStr'.trim(),
      sub: batch.materialName,
      compact: compact,
      onRevert: onRevert,
    );

    return Draggable<MaterialBatch>(
      data: batch,
      axis: Axis.horizontal,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Transform.translate(
        offset: const Offset(-40, -12),
        child: Material(
          color: Colors.transparent,
          child: Transform.scale(
            scale: 1.05,
            child: _ChipBody(
              label: '${fmtQty(batch.quantity)}$unitStr'.trim(),
              sub: batch.materialName,
              elevated: true,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: body),
      child: GestureDetector(
        onDoubleTap: () => context
            .read<ProductionRunProvider>()
            .openBatchActions(batch.currentNodeId, batch),
        child: Tooltip(
          message: 'Drag to move • double-click to reconcile',
          waitDuration: const Duration(milliseconds: 600),
          child: body,
        ),
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
    this.onRevert,
  });

  final String label;
  final String sub;
  final bool compact;
  final bool elevated;
  final VoidCallback? onRevert;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 160),
      height: 22, // smaller than the 48px node card
      padding: const EdgeInsets.only(left: 7),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11), // Pill shape
        border: Border.all(color: const Color(0xFF0EA5E9), width: 1.25),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: const Color(0xFF0EA5E9).withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: Color(0xFF0EA5E9),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          if (onRevert != null)
            Tooltip(
              message: 'Revert this lot’s last move',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onRevert,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(11),
                    bottomRight: Radius.circular(11),
                  ),
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: Color(0xFFE2E8F0),
                          width: 1,
                        ),
                      ),
                    ),
                    child: const Icon(
                      Icons.undo_rounded,
                      size: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
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
      barrierDismissible: false,
      builder: (_) =>
          BatchSplitDialog(batch: batch, targetNodeName: targetNodeName),
    );
  }

  @override
  State<BatchSplitDialog> createState() => _BatchSplitDialogState();
}

class _BatchSplitDialogState extends State<BatchSplitDialog> {
  late double _qty = widget.batch.quantity;

  @override
  Widget build(BuildContext context) {
    final max = widget.batch.quantity;
    final unitStr = widget.batch.unitLabel == '-' ? '' : ' ${widget.batch.unitLabel}';
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
                '${widget.batch.materialName} • ${fmtQty(max)}$unitStr available',
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
                    '${fmtQty(_qty)}$unitStr',
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
                label: fmtQty(_qty),
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
                      'Splits • ${fmtQty(max - _qty)}$unitStr stays',
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
