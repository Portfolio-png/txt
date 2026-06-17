import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/material_batch.dart';
import '../../production_pipelines/domain/process_node.dart';
import '../providers/batch_flow_provider.dart';
import '../providers/production_provider.dart';
import '../providers/production_run_provider.dart';

/// Lays the whole pipeline out as stations and parks each batch at the stage it
/// currently sits in. A batch that leaves mid-pipeline (e.g. the client sells
/// the part after a stage) simply stays parked at that stage — no need to reach
/// the output. Below the lane, the same batches are tabulated like the floor's
/// ledger sheet (batch × stage).
///
/// Reads the same live [BatchFlowProvider] tokens the canvas chips draw from, so
/// the panel and the canvas always agree on where each batch is. If the run
/// isn't seeded yet (e.g. opened on a screen without the canvas), it seeds from
/// the saved run so batches show up without re-opening the run.
class BatchTrainPanel extends StatefulWidget {
  const BatchTrainPanel({
    super.key,
    required this.node,
    required this.expanded,
    required this.onToggle,
  });

  final ProcessNode node;

  /// Whether the lane + ledger are shown. The header always shows and toggles
  /// this via [onToggle].
  final bool expanded;
  final VoidCallback onToggle;

  @override
  State<BatchTrainPanel> createState() => _BatchTrainPanelState();
}

class _BatchTrainPanelState extends State<BatchTrainPanel> {
  String? _seedingRunId;

  static const _batchColors = [
    Color(0xFF6366F1),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF06B6D4),
    Color(0xFF8B5CF6),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureSeeded();
  }

  /// Seed the in-memory batches from the saved run when this screen has none
  /// yet, so the lane isn't empty just because the canvas hasn't run here.
  Future<void> _ensureSeeded() async {
    final runId = context.read<ProductionRunProvider>().runId;
    final flow = context.read<BatchFlowProvider>();
    if (runId == null || flow.isSeeded(runId) || _seedingRunId == runId) return;
    _seedingRunId = runId;
    try {
      final run = await context.read<PipelineRunRepository>().getRun(runId);
      if (run != null && mounted) flow.seedFromRun(run);
    } catch (_) {
      // Leave empty-state showing; a canvas visit will seed it.
    }
  }

  @override
  Widget build(BuildContext context) {
    final runId = context.watch<ProductionRunProvider>().runId;
    final flow = context.watch<BatchFlowProvider>();
    final template = context.read<ProductionProvider>().template;
    final stageNodes = List<ProcessNode>.from(template.nodes)
      ..sort((a, b) => a.stageIndex.compareTo(b.stageIndex));

    final batches = runId == null
        ? const <MaterialBatch>[]
        : flow.batchesForRun(runId).where((b) => b.isLive).toList();

    final rows = [
      for (var i = 0; i < batches.length; i++)
        _BatchRow(
          label: 'Batch ${i + 1}',
          lot: batches[i].barcode,
          qty: batches[i].quantity,
          unit: batches[i].unitLabel,
          // Park at the stage the batch is actually parked at on the canvas.
          stageIndex: () {
            final s = stageNodes.indexWhere(
              (n) => n.id == batches[i].currentNodeId,
            );
            return s < 0 ? 0 : s;
          }(),
          colorIndex: i,
          at: batches[i].createdAt,
        ),
    ];
    final total = rows.fold<double>(0, (s, r) => s + r.qty);
    final unit = batches
        .map((b) => b.unitLabel)
        .firstWhere((u) => u.isNotEmpty, orElse: () => '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The header is the toggle: click it to open/close the lane + ledger.
        InkWell(
          onTap: widget.onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.account_tree_rounded,
                  size: 16,
                  color: Color(0xFF475569),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Batch flow',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 8),
                if (rows.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${rows.length} batch${rows.length == 1 ? "" : "es"} • ${fmtQty(total)}${unit.isNotEmpty ? " $unit" : ""}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4F46E5),
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(
                  widget.expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: const Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
        ),
        if (!widget.expanded)
          const SizedBox.shrink()
        else ...[
          const SizedBox(height: 12),
          if (rows.isEmpty)
            const Expanded(child: _EmptyState())
          else
            // Lane graph dropped — the canvas above already shows batch
            // positions. The ledger is the unique, per-stage view.
            Expanded(
              child: SingleChildScrollView(
                child: _BatchLedger(
                  stages: [
                    for (final n in stageNodes)
                      n.name.isEmpty ? n.processType : n.name,
                  ],
                  rows: rows,
                  colors: _batchColors,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _BatchRow {
  const _BatchRow({
    required this.label,
    required this.lot,
    required this.qty,
    required this.unit,
    required this.stageIndex,
    required this.colorIndex,
    this.at,
  });

  final String label;
  final String lot;
  final double qty;
  final String unit;
  final int stageIndex;
  final int colorIndex;
  final DateTime? at;
}

String fmtTime(DateTime? d) {
  if (d == null) return '—';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
}

/// Floor ledger: one row per batch, one column per pipeline stage, plus a
/// totals row. A batch's quantity shows under the stage it currently occupies.
class _BatchLedger extends StatelessWidget {
  const _BatchLedger({
    required this.stages,
    required this.rows,
    required this.colors,
  });

  final List<String> stages;
  final List<_BatchRow> rows;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final stageTotals = List<double>.filled(stages.length, 0);
    for (final r in rows) {
      if (r.stageIndex >= 0 && r.stageIndex < stages.length) {
        stageTotals[r.stageIndex] += r.qty;
      }
    }
    final grand = rows.fold<double>(0, (s, r) => s + r.qty);

    Widget num(double v, {bool strong = false}) => Text(
      v == 0 ? '·' : fmtQty(v),
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
        color: v == 0
            ? const Color(0xFFCBD5E1)
            : (strong ? const Color(0xFF1E293B) : const Color(0xFF334155)),
      ),
    );

    // A stage cell: the batch's qty plus when it arrived at this stage, but
    // only for the stage the batch currently occupies.
    Widget stageCell(_BatchRow r, int i) {
      if (i != r.stageIndex) return num(0);
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          num(r.qty),
          Text(
            fmtTime(r.at),
            style: const TextStyle(
              fontSize: 9.5,
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 44,
        dataRowMaxHeight: 52,
        columnSpacing: 26,
        headingTextStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFF64748B),
          letterSpacing: 0.4,
        ),
        columns: [
          const DataColumn(label: Text('BATCH')),
          for (final s in stages) DataColumn(label: Text(s), numeric: true),
          const DataColumn(label: Text('TOTAL'), numeric: true),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              cells: [
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        margin: const EdgeInsets.only(right: 7),
                        decoration: BoxDecoration(
                          color: colors[r.colorIndex % colors.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(
                        r.label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < stages.length; i++)
                  DataCell(stageCell(r, i)),
                DataCell(num(r.qty, strong: true)),
              ],
            ),
          DataRow(
            color: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
            cells: [
              const DataCell(
                Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
              for (final t in stageTotals) DataCell(num(t, strong: true)),
              DataCell(num(grand, strong: true)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_rounded, size: 32, color: Color(0xFFCBD5E1)),
          SizedBox(height: 8),
          Text(
            'No batches assigned to this run yet.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}
