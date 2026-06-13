import 'package:flutter/material.dart';

import '../../production_pipelines/domain/material_batch.dart';
import 'batch_chip.dart';

/// The dock of batch chips parked at a single node, shown beneath the node
/// block on the pipeline canvas. Renders a small header with a count badge and
/// the live total, then the chips themselves.
class NodeBatchTray extends StatelessWidget {
  const NodeBatchTray({
    super.key,
    required this.batches,
    required this.width,
  });

  final List<MaterialBatch> batches;
  final double width;

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    if (batches.isEmpty) return const SizedBox.shrink();

    final total = batches.fold<double>(0, (sum, b) => sum + b.quantity);
    final unit = batches.first.unitLabel;

    return Container(
      width: width,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${batches.length}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2563EB),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${batches.length == 1 ? 'batch' : 'batches'} · ${_fmt(total)} $unit'
                      .trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF94A3B8),
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final batch in batches)
                BatchChip(batch: batch, compact: batches.length > 2),
            ],
          ),
        ],
      ),
    );
  }
}
