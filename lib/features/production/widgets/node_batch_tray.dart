import 'package:flutter/material.dart';

import '../../production_pipelines/domain/material_batch.dart';
import 'batch_chip.dart';

class NodeBatchTray extends StatelessWidget {
  const NodeBatchTray({
    super.key,
    required this.batches,
    required this.width,
    this.onRevert,
  });

  final List<MaterialBatch> batches;
  final double width;
  final ValueChanged<MaterialBatch>? onRevert;

  @override
  Widget build(BuildContext context) {
    if (batches.isEmpty) return const SizedBox.shrink();

    // Group batches by material name
    final grouped = <String, List<MaterialBatch>>{};
    for (final b in batches) {
      grouped.putIfAbsent(b.materialName, () => []).add(b);
    }

    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: grouped.values.map((group) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: BatchStack(
              batches: group,
              width: width,
              onRevert: onRevert,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class BatchStack extends StatefulWidget {
  const BatchStack({
    super.key,
    required this.batches,
    required this.width,
    this.onRevert,
  });

  final List<MaterialBatch> batches;
  final double width;
  final ValueChanged<MaterialBatch>? onRevert;

  @override
  State<BatchStack> createState() => _BatchStackState();
}

class _BatchStackState extends State<BatchStack> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final batches = widget.batches;
    final total = batches.fold<double>(0, (sum, b) => sum + b.quantity);
    final unitLabel = batches.first.unitLabel;
    final unitStr = unitLabel == '-' ? '' : ' $unitLabel';
    final materialName = batches.first.materialName;

    return Container(
      width: widget.width,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0), // Slate 200
        borderRadius: BorderRadius.circular(6), // Smooth outer border radius
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _expanded = !_expanded;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0EA5E9), // The blue color
                  borderRadius: BorderRadius.circular(4), // Slightly rounded inner block
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            materialName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${fmtQty(total)}$unitStr',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.9),
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Expanded Items
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < batches.length; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: i < batches.length - 1 ? 3 : 0),
                      child: BatchChip(
                        batch: batches[i],
                        compact: true,
                        onRevert: widget.onRevert == null ? null : () => widget.onRevert!(batches[i]),
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
