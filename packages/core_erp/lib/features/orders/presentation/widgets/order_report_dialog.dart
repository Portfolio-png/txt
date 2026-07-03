import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../domain/order_entry.dart';
import '../../domain/order_production_report.dart';
import '../providers/orders_provider.dart';

/// Production report for one order: pipeline stages with actual quantities
/// from stage reconciliations. Rates and amounts render as blanks by design —
/// the user fills them in on paper. Values refresh live while the dialog is
/// open, so floor commits show up as they happen.
class OrderReportDialog extends StatefulWidget {
  const OrderReportDialog({super.key, required this.group});

  final OrderGroup group;

  static Future<void> show(BuildContext context, OrderGroup group) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 860,
          height: math.min(MediaQuery.of(context).size.height - 40, 820),
          child: OrderReportDialog(group: group),
        ),
      ),
    );
  }

  @override
  State<OrderReportDialog> createState() => _OrderReportDialogState();
}

class _OrderReportDialogState extends State<OrderReportDialog> {
  OrderProductionReport? _report;
  String? _error;
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _fetch();
    // ponytail: 5s poll = "realtime enough" for floor reconciliation commits.
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetch());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final report = await context.read<OrdersProvider>().loadProductionReport(
        widget.group.orderNo,
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (_report == null) _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _print() async {
    final report = _report;
    if (report == null) return;
    final bytes = await _buildReportPdf(report);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 860,
          height: math.min(MediaQuery.of(context).size.height - 40, 820),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Report Print Preview',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: PdfPreview(
                  build: (_) async => bytes,
                  allowPrinting: true,
                  allowSharing: true,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  canDebug: false,
                  pdfFileName: 'report-${report.orderNo}.pdf',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Report — ${widget.group.orderNo}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_report != null) ...[
                const _LiveDot(),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _print,
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('Print'),
                ),
                const SizedBox(width: 4),
              ],
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading && _report == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Text(
          'Could not load report:\n$error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
    final report = _report!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          fontSize: 13.5,
          color: SoftErpTheme.textPrimary,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _buildSheet(report),
        ),
      ),
    );
  }

  List<Widget> _buildSheet(OrderProductionReport report) {
    final widgets = <Widget>[];

    widgets.add(_headerBlock(report));
    widgets.add(const SizedBox(height: 18));

    if (report.runs.isEmpty) {
      widgets.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'No production runs are linked to this order yet. '
            'Quantities appear here as stages are reconciled on the floor.',
            style: TextStyle(color: SoftErpTheme.textSecondary),
          ),
        ),
      );
    }

    for (final run in report.runs) {
      final item = _itemForRun(report, run);
      final orderQty = item?.quantity ?? 0;

      widgets.add(_sectionTitle(
        report.runs.length > 1
            ? 'MATERIALS — ${run.runName.isEmpty ? run.runId : run.runName}'
            : 'MATERIALS',
      ));
      var hasMaterialLine = false;
      for (final stage in run.stages) {
        if (stage.material.isEmpty) continue;
        hasMaterialLine = true;
        widgets.add(_materialLine(stage, orderQty));
      }
      if (!hasMaterialLine) {
        widgets.add(_mutedLine('No material stages on this pipeline.'));
      }
      widgets.add(_blankSubtotal('Subtotal Materials'));
      widgets.add(const SizedBox(height: 14));

      widgets.add(_sectionTitle('PROCESS'));
      var hasProcessLine = false;
      for (final stage in run.stages) {
        if (stage.machine.isNotEmpty) {
          hasProcessLine = true;
          widgets.add(_processLine(
            '${stage.machine} (${stage.name})',
            _fmtHours(stage.workedHours ?? stage.plannedHours),
            'hr',
          ));
        }
        if (stage.dieId.isNotEmpty) {
          hasProcessLine = true;
          widgets.add(_processLine(
            'Die ${stage.dieId}',
            stage.output != null ? _fmtQty(stage.output!) : '____',
            'strk',
          ));
        }
      }
      widgets.add(_processLine('Labor', '____', 'hr'));
      if (!hasProcessLine) {
        widgets.add(_mutedLine('No machines or dies on this pipeline.'));
      }
      widgets.add(_blankSubtotal('Subtotal Process'));
      widgets.add(const SizedBox(height: 14));

      widgets.add(_sectionTitle('WASTE'));
      var hasWasteLine = false;
      for (final stage in run.stages) {
        final scrap = stage.scrap ?? 0;
        if (scrap <= 0) continue;
        hasWasteLine = true;
        widgets.add(_wasteLine(stage, scrap));
      }
      if (!hasWasteLine) {
        widgets.add(_mutedLine('No scrap reconciled yet.'));
      }
      widgets.add(_blankSubtotal('Subtotal Waste'));
      widgets.add(const SizedBox(height: 18));
    }

    widgets.add(const Divider());
    widgets.add(_totalsBlock(report));
    return widgets;
  }

  OrderReportItem? _itemForRun(
    OrderProductionReport report,
    OrderReportRun run,
  ) {
    for (final item in report.items) {
      if (item.orderItemId == run.orderItemId) return item;
    }
    return report.items.isEmpty ? null : report.items.first;
  }

  Widget _headerBlock(OrderProductionReport report) {
    final lines = <String>[
      if (report.clientName.isNotEmpty) report.clientName,
      for (final item in report.items)
        '${_fmtQty(item.quantity)} ${item.unitSymbol}  '
            '${item.itemName}'
            '${item.variationPathLabel.isEmpty ? '' : ' · ${item.variationPathLabel}'}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              line,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12.5,
          letterSpacing: 1.1,
          color: SoftErpTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _mutedLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(color: SoftErpTheme.textSecondary),
      ),
    );
  }

  /// `Stage · Material    23.5 kg   (0.047/pc)   × ₹____ = ₹______`
  Widget _materialLine(OrderReportStage stage, double orderQty) {
    final unit = stage.materialUnit;
    final qty = stage.allotted;
    final perUnit = (qty != null && orderQty > 0) ? qty / orderQty : null;
    return _reportRow(
      label: 'Stage ${stage.stageIndex + 1} · ${stage.name} — ${stage.material}',
      qty: qty != null ? '${_fmtQty(qty)} $unit' : '____ $unit',
      detail: perUnit != null ? '${_fmtQty(perUnit)} $unit/pc' : null,
      rateUnit: '/$unit',
    );
  }

  Widget _processLine(String label, String qty, String unit) {
    return _reportRow(label: label, qty: '$qty $unit', rateUnit: '/$unit');
  }

  Widget _wasteLine(OrderReportStage stage, double scrap) {
    return _reportRow(
      label: '${stage.name} — ${stage.material.isEmpty ? 'scrap' : '${stage.material} scrap'}',
      qty: '${_fmtQty(scrap)} ${stage.materialUnit}',
      rateUnit: '/${stage.materialUnit}',
    );
  }

  Widget _reportRow({
    required String label,
    required String qty,
    String? detail,
    required String rateUnit,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(label, overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 110,
            child: Text(
              qty,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              detail ?? '',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          SizedBox(
            width: 130,
            child: Text('× ₹______$rateUnit', textAlign: TextAlign.right),
          ),
          const SizedBox(
            width: 110,
            child: Text('= ₹________', textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _blankSubtotal(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('$label:  ', style: const TextStyle(fontWeight: FontWeight.w700)),
          const Text('₹__________'),
        ],
      ),
    );
  }

  Widget _totalsBlock(OrderProductionReport report) {
    final totalQty = report.items.fold<double>(0, (sum, i) => sum + i.quantity);
    final knownPrice = report.items.every((i) => i.unitPrice > 0);
    final sellingTotal = report.items.fold<double>(
      0,
      (sum, i) => sum + i.unitPrice * i.quantity,
    );
    Widget row(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '$label:  ',
                style: TextStyle(
                  fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
              SizedBox(
                width: 140,
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontWeight: bold ? FontWeight.w900 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row('GRAND TOTAL', '₹__________', bold: true),
        row(
          'COST PER UNIT (÷ ${_fmtQty(totalQty)})',
          '₹__________',
        ),
        row(
          'SELLING PRICE (from order)',
          knownPrice && sellingTotal > 0
              ? '₹${_fmtQty(sellingTotal)}'
              : '₹__________',
        ),
        row('MARGIN PER UNIT', '₹__________'),
        row('MARGIN %', '_____%'),
      ],
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.circle, size: 9, color: Color(0xFF16A34A)),
        SizedBox(width: 5),
        Text(
          'Live',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF16A34A),
          ),
        ),
      ],
    );
  }
}

String _fmtQty(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  var text = value.toStringAsFixed(4);
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return text;
}

String _fmtHours(double? hours) {
  if (hours == null || hours <= 0) return '____';
  return _fmtQty(double.parse(hours.toStringAsFixed(2)));
}

/// PDF mirror of the on-screen sheet. Uses "Rs." because the built-in PDF
/// fonts have no ₹ glyph.
Future<Uint8List> _buildReportPdf(OrderProductionReport report) {
  final doc = pw.Document();

  pw.Widget line({
    required String label,
    required String qty,
    String detail = '',
    required String rateUnit,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(left: 10, bottom: 3),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Text(label, maxLines: 1)),
          pw.SizedBox(
            width: 80,
            child: pw.Text(qty, textAlign: pw.TextAlign.right),
          ),
          pw.SizedBox(
            width: 75,
            child: pw.Text(
              detail,
              textAlign: pw.TextAlign.right,
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
          pw.SizedBox(
            width: 95,
            child: pw.Text(
              'x Rs.______$rateUnit',
              textAlign: pw.TextAlign.right,
            ),
          ),
          pw.SizedBox(
            width: 80,
            child: pw.Text('= Rs.________', textAlign: pw.TextAlign.right),
          ),
        ],
      ),
    );
  }

  pw.Widget sectionTitle(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
        child: pw.Text(
          title,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
        ),
      );

  pw.Widget subtotal(String label) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text(
              '$label:  ',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text('Rs.__________'),
          ],
        ),
      );

  final totalQty = report.items.fold<double>(0, (sum, i) => sum + i.quantity);
  final knownPrice = report.items.every((i) => i.unitPrice > 0);
  final sellingTotal = report.items.fold<double>(
    0,
    (sum, i) => sum + i.unitPrice * i.quantity,
  );

  doc.addPage(
    pw.MultiPage(
      build: (context) {
        final content = <pw.Widget>[
          pw.Text(
            'REPORT — ${report.orderNo}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
          ),
          if (report.clientName.isNotEmpty) pw.Text(report.clientName),
          for (final item in report.items)
            pw.Text(
              '${_fmtQty(item.quantity)} ${item.unitSymbol}  ${item.itemName}'
              '${item.variationPathLabel.isEmpty ? '' : ' - ${item.variationPathLabel}'}',
            ),
          pw.Divider(),
        ];

        for (final run in report.runs) {
          OrderReportItem? item;
          for (final candidate in report.items) {
            if (candidate.orderItemId == run.orderItemId) item = candidate;
          }
          item ??= report.items.isEmpty ? null : report.items.first;
          final orderQty = item?.quantity ?? 0;

          content.add(sectionTitle(
            report.runs.length > 1
                ? 'MATERIALS — ${run.runName.isEmpty ? run.runId : run.runName}'
                : 'MATERIALS',
          ));
          for (final stage in run.stages) {
            if (stage.material.isEmpty) continue;
            final qty = stage.allotted;
            final perUnit =
                (qty != null && orderQty > 0) ? qty / orderQty : null;
            content.add(line(
              label:
                  'Stage ${stage.stageIndex + 1} - ${stage.name} — ${stage.material}',
              qty: qty != null
                  ? '${_fmtQty(qty)} ${stage.materialUnit}'
                  : '____ ${stage.materialUnit}',
              detail: perUnit != null
                  ? '${_fmtQty(perUnit)} ${stage.materialUnit}/pc'
                  : '',
              rateUnit: '/${stage.materialUnit}',
            ));
          }
          content.add(subtotal('Subtotal Materials'));

          content.add(sectionTitle('PROCESS'));
          for (final stage in run.stages) {
            if (stage.machine.isNotEmpty) {
              content.add(line(
                label: '${stage.machine} (${stage.name})',
                qty: '${_fmtHours(stage.workedHours ?? stage.plannedHours)} hr',
                rateUnit: '/hr',
              ));
            }
            if (stage.dieId.isNotEmpty) {
              content.add(line(
                label: 'Die ${stage.dieId}',
                qty:
                    '${stage.output != null ? _fmtQty(stage.output!) : '____'} strk',
                rateUnit: '/strk',
              ));
            }
          }
          content.add(line(label: 'Labor', qty: '____ hr', rateUnit: '/hr'));
          content.add(subtotal('Subtotal Process'));

          content.add(sectionTitle('WASTE'));
          for (final stage in run.stages) {
            final scrap = stage.scrap ?? 0;
            if (scrap <= 0) continue;
            content.add(line(
              label:
                  '${stage.name} — ${stage.material.isEmpty ? 'scrap' : '${stage.material} scrap'}',
              qty: '${_fmtQty(scrap)} ${stage.materialUnit}',
              rateUnit: '/${stage.materialUnit}',
            ));
          }
          content.add(subtotal('Subtotal Waste'));
        }

        content.add(pw.Divider());
        content.add(subtotal('GRAND TOTAL'));
        content.add(subtotal('COST PER UNIT (/ ${_fmtQty(totalQty)})'));
        content.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text(
                'SELLING PRICE (from order):  ',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                knownPrice && sellingTotal > 0
                    ? 'Rs.${_fmtQty(sellingTotal)}'
                    : 'Rs.__________',
              ),
            ],
          ),
        ));
        content.add(subtotal('MARGIN PER UNIT'));
        content.add(subtotal('MARGIN %'));
        return content;
      },
    ),
  );

  return doc.save();
}
