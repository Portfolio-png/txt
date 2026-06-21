import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/material_batch.dart';
import '../../production_pipelines/domain/process_node.dart';
import '../providers/batch_flow_provider.dart';
import '../providers/production_provider.dart';
import '../providers/production_run_provider.dart';

/// Tabulates the run's batches like the floor's ledger sheet (batch × stage),
/// parking each batch's quantity under the stage it currently occupies.
///
/// Reads the same live [BatchFlowProvider] tokens the canvas chips draw from, so
/// the panel and the canvas always agree on where each batch is. If the run
/// isn't seeded yet (e.g. opened on a screen without the canvas), it seeds from
/// the saved run so batches show up without re-opening the run.
class BatchTrainPanel extends StatefulWidget {
  const BatchTrainPanel({super.key});

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
          material: batches[i].materialName.trim().isNotEmpty
              ? batches[i].materialName
              : batches[i].barcode,
          qty: batches[i].quantity,
          unit: batches[i].unitLabel,
          leftover: batches[i].leftover,
          scrap: batches[i].scrap,
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
    final itemCount = rows.map((r) => r.material).toSet().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
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
                    '$itemCount item${itemCount == 1 ? "" : "s"} • ${rows.length} batch${rows.length == 1 ? "" : "es"}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                ),
            ],
          ),
        ),
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
    );
  }
}

class _BatchRow {
  const _BatchRow({
    required this.label,
    required this.material,
    required this.qty,
    required this.unit,
    required this.leftover,
    required this.scrap,
    required this.stageIndex,
    required this.colorIndex,
    this.at,
  });

  final String label;
  final String material;
  final double qty;
  final String unit;
  final double leftover;
  final double scrap;
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

/// Floor ledger: batches grouped by their output item. Within a group, one
/// row per batch and one column per pipeline stage; a batch's quantity shows
/// under the stage it currently occupies, with a subtotal per item group.
///
/// Compact fixed-width layout (not a DataTable) so it stays dense — the bulky
/// row heights made a small run look empty.
class _BatchLedger extends StatelessWidget {
  const _BatchLedger({
    required this.stages,
    required this.rows,
    required this.colors,
  });

  final List<String> stages;
  final List<_BatchRow> rows;
  final List<Color> colors;

  static const _batchW = 168.0;
  static const _stageW = 84.0;
  static const _totalW = 60.0;

  static const _muted = Color(0xFF94A3B8);
  static const _ink = Color(0xFF1E293B);

  @override
  Widget build(BuildContext context) {
    // Group by item, preserving first-seen order (Dart Maps keep insertion order).
    final groups = <String, List<_BatchRow>>{};
    for (final r in rows) {
      groups.putIfAbsent(r.material, () => []).add(r);
    }

    final tableW = _batchW + stages.length * _stageW + _totalW;

    Widget cell(double w, Widget child, {Alignment align = Alignment.centerRight}) =>
        SizedBox(width: w, child: Align(alignment: align, child: child));

    Widget num(double v, {bool strong = false}) => Text(
      v == 0 ? '·' : fmtQty(v),
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
        color: v == 0
            ? const Color(0xFFCBD5E1)
            : (strong ? _ink : const Color(0xFF334155)),
      ),
    );

    // Occupied stage: qty, optional leftover (L, sky) / scrap (S, yellow), time.
    Widget stageCell(_BatchRow r, int i) {
      if (i != r.stageIndex) return num(0);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          num(r.qty),
          if (r.leftover > 0 || r.scrap > 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (r.leftover > 0)
                  Text('L ${fmtQty(r.leftover)}',
                      style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0284C7))),
                if (r.leftover > 0 && r.scrap > 0) const SizedBox(width: 6),
                if (r.scrap > 0)
                  Text('S ${fmtQty(r.scrap)}',
                      style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFCA8A04))),
              ],
            ),
          Text(fmtTime(r.at),
              style: const TextStyle(
                  fontSize: 9.5, color: _muted, fontWeight: FontWeight.w600)),
        ],
      );
    }

    const headStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: Color(0xFF64748B),
      letterSpacing: 0.3,
    );

    final children = <Widget>[
      // Column header
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          cell(_batchW, const Text('BATCH', style: headStyle),
              align: Alignment.centerLeft),
          for (final s in stages)
            cell(_stageW,
                Text(s, style: headStyle, maxLines: 1, overflow: TextOverflow.ellipsis)),
          cell(_totalW, const Text('TOTAL', style: headStyle)),
        ]),
      ),
    ];

    groups.forEach((item, groupRows) {
      final groupQty = groupRows.fold<double>(0, (s, r) => s + r.qty);
      final unit = groupRows
          .map((r) => r.unit)
          .firstWhere((u) => u.isNotEmpty, orElse: () => '');
      final stageTotals = List<double>.filled(stages.length, 0);
      for (final r in groupRows) {
        if (r.stageIndex >= 0 && r.stageIndex < stages.length) {
          stageTotals[r.stageIndex] += r.qty;
        }
      }

      // Group header: ─ Item ───── (qty unit)
      children.add(Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Row(children: [
          const Text('─ ',
              style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1))),
          Flexible(
            child: Text(item.isEmpty ? '—' : item,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w800, color: _ink)),
          ),
          const SizedBox(width: 8),
          // ponytail: solid hairline reads as the section rule at this density;
          // swap for a dashed CustomPaint only if design insists on dashes.
          const Expanded(child: Divider(height: 1, color: Color(0xFFE2E8F0))),
          const SizedBox(width: 8),
          Text('(${fmtQty(groupQty)}${unit.isNotEmpty ? " $unit" : ""})',
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: _muted)),
        ]),
      ));

      // Batch rows
      for (final r in groupRows) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            cell(
              _batchW,
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 7),
                  decoration: BoxDecoration(
                      color: colors[r.colorIndex % colors.length],
                      shape: BoxShape.circle),
                ),
                Text(r.label,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _ink)),
              ]),
              align: Alignment.centerLeft,
            ),
            for (var i = 0; i < stages.length; i++)
              cell(_stageW, stageCell(r, i)),
            cell(_totalW, num(r.qty, strong: true)),
          ]),
        ));
      }

      // Subtotal row
      children.add(Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: Row(children: [
          cell(_batchW, const Text('subtotal',
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w800, color: _muted)),
              align: Alignment.centerLeft),
          for (final t in stageTotals) cell(_stageW, num(t, strong: true)),
          cell(_totalW, num(groupQty, strong: true)),
        ]),
      ));
    });

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: tableW,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
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
