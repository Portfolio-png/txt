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
          width: 1020,
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
    widgets.add(const SizedBox(height: 16));

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

      widgets.add(_runHeader(run, item));
      widgets.add(const SizedBox(height: 10));

      widgets.add(
        _sectionCard(
          title: 'Materials',
          children: [
            _tableHeader(),
            ..._materialRows(run, item),
            _blankSubtotal('Subtotal Materials'),
          ],
        ),
      );
      widgets.add(const SizedBox(height: 12));

      widgets.add(
        _sectionCard(
          title: 'Process',
          children: [
            _tableHeader(),
            ..._processRows(run),
            _blankSubtotal('Subtotal Process'),
          ],
        ),
      );
      widgets.add(const SizedBox(height: 12));

      widgets.add(
        _sectionCard(
          title: 'Waste & Adjustments',
          children: [
            _tableHeader(),
            ..._wasteRows(run),
            _reportRow(
              label: 'Waste Adjustment',
              qty: '____',
              detail: 'manual',
              rateUnit: '',
            ),
            _blankSubtotal('Subtotal Waste'),
          ],
        ),
      );
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
    final totalQtyByUnit = <String, double>{};
    for (final item in report.items) {
      totalQtyByUnit.update(
        item.unitSymbol,
        (value) => value + item.quantity,
        ifAbsent: () => item.quantity,
      );
    }
    final totalQty = totalQtyByUnit.entries
        .map((entry) => '${_fmtQty(entry.value)} ${entry.key}')
        .join(' + ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ORDER ${report.orderNo}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (report.clientName.isNotEmpty)
                      Text(
                        report.clientName,
                        style: const TextStyle(
                          color: SoftErpTheme.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              _summaryPill(
                'PO',
                report.poNumber.isEmpty ? '-' : report.poNumber,
              ),
              const SizedBox(width: 8),
              _summaryPill('Qty', totalQty.isEmpty ? '-' : totalQty),
              const SizedBox(width: 8),
              _summaryPill('Runs', report.runs.length.toString()),
            ],
          ),
          if (report.items.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in report.items)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_fmtQty(item.quantity)} ${item.unitSymbol} · ${item.itemName}'
                      '${item.variationPathLabel.isEmpty ? '' : ' · ${item.variationPathLabel}'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryPill(String label, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 86),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _runHeader(OrderReportRun run, OrderReportItem? item) {
    final runName = run.runName.isEmpty ? run.runId : run.runName;
    final itemName = item == null
        ? ''
        : '${item.itemName}${item.variationPathLabel.isEmpty ? '' : ' · ${item.variationPathLabel}'}';
    return Row(
      children: [
        Expanded(
          child: Text(
            runName.isEmpty ? 'Production Run' : runName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ),
        if (itemName.isNotEmpty)
          Flexible(
            child: Text(
              itemName,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SoftErpTheme.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_sectionTitle(title), ...children],
      ),
    );
  }

  Widget _tableHeader() {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8),
      child: Row(
        children: const [
          Expanded(child: Text('Line', style: _tableHeaderStyle)),
          SizedBox(
            width: 116,
            child: Text(
              'Total Qty',
              textAlign: TextAlign.right,
              style: _tableHeaderStyle,
            ),
          ),
          SizedBox(
            width: 126,
            child: Text(
              'Basis',
              textAlign: TextAlign.right,
              style: _tableHeaderStyle,
            ),
          ),
          SizedBox(
            width: 132,
            child: Text(
              'Rate',
              textAlign: TextAlign.right,
              style: _tableHeaderStyle,
            ),
          ),
          SizedBox(
            width: 118,
            child: Text(
              'Amount',
              textAlign: TextAlign.right,
              style: _tableHeaderStyle,
            ),
          ),
        ],
      ),
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

  List<Widget> _materialRows(OrderReportRun run, OrderReportItem? item) {
    final rows = <Widget>[];
    final orderQty = item?.quantity ?? 0;
    final orderUnit = item?.unitSymbol ?? 'pc';
    for (final stage in run.stages) {
      if (stage.material.isEmpty) continue;
      rows.add(_materialLine(stage, orderQty, orderUnit));
    }
    if (rows.isEmpty) {
      rows.add(_mutedLine('No material stages on this pipeline.'));
    }
    return rows;
  }

  List<Widget> _processRows(OrderReportRun run) {
    final rows = <Widget>[];
    for (final stage in run.stages) {
      if (stage.machine.isNotEmpty) {
        final detailParts = <String>[
          if ((stage.machineSetupMinutes ?? 0) > 0)
            '${_fmtQty(stage.machineSetupMinutes!)} min setup',
          if ((stage.machineOutputPerHour ?? 0) > 0)
            '${_fmtQty(stage.machineOutputPerHour!)} output/hr',
          if ((stage.machineLaborCount ?? 0) > 0)
            '${_fmtQty(stage.machineLaborCount!)} labor',
          if ((stage.machinePowerKw ?? 0) > 0)
            '${_fmtQty(stage.machinePowerKw!)} kW',
        ];
        rows.add(
          _processLine(
            '${stage.machine} (${stage.name})',
            _fmtHours(stage.workedHours ?? stage.plannedHours),
            'hr',
            detail: detailParts.join(' · '),
          ),
        );
        if (stage.machineReportNotes.trim().isNotEmpty) {
          rows.add(_mutedLine(stage.machineReportNotes.trim()));
        }
      }
      if (stage.dieId.isNotEmpty || stage.dieToolCode.isNotEmpty) {
        final strokes = _dieStrokeQty(stage);
        final detailParts = <String>[
          if ((stage.dieStrokesPerPiece ?? 0) > 0)
            '${_fmtQty(stage.dieStrokesPerPiece!)} strk/pc',
          if ((stage.dieCavities ?? 0) > 0) '${stage.dieCavities} cavities',
          if ((stage.dieMaxStrokes ?? 0) > 0)
            'life ${_fmtQty(stage.dieMaxStrokes!.toDouble())}',
          if ((stage.dieSetupMinutes ?? 0) > 0)
            '${_fmtQty(stage.dieSetupMinutes!)} min setup',
        ];
        rows.add(
          _processLine(
            'Die ${stage.dieToolCode.isEmpty ? stage.dieId : stage.dieToolCode}',
            strokes == null ? '____' : _fmtQty(strokes),
            'strk',
            detail: detailParts.join(' · '),
          ),
        );
        if (stage.dieReportNotes.trim().isNotEmpty) {
          rows.add(_mutedLine(stage.dieReportNotes.trim()));
        }
      }
    }
    rows.add(_processLine('Labor', '____', 'hr', detail: 'manual'));
    rows.add(
      _processLine('Process Cost', '____', '', detail: 'machine + labor + die'),
    );
    if (rows.length == 2) {
      rows.insert(0, _mutedLine('No machines or dies on this pipeline.'));
    }
    return rows;
  }

  List<Widget> _wasteRows(OrderReportRun run) {
    final rows = <Widget>[];
    for (final stage in run.stages) {
      final scrap = stage.scrap ?? 0;
      if (scrap <= 0) continue;
      rows.add(_wasteLine(stage, scrap));
    }
    if (rows.isEmpty) {
      rows.add(_mutedLine('No scrap reconciled yet.'));
    }
    return rows;
  }

  Widget _materialLine(
    OrderReportStage stage,
    double orderQty,
    String orderUnit,
  ) {
    final unit = stage.materialUnit;
    final qty = _materialTotalQty(stage, orderQty);
    final perUnit =
        stage.quantityPerUnit ??
        ((qty != null && orderQty > 0) ? qty / orderQty : null);
    return _reportRow(
      label:
          'Stage ${stage.stageIndex + 1} · ${stage.name} — ${stage.material}',
      qty: qty != null ? '${_fmtQty(qty)} $unit' : '____ $unit',
      detail: perUnit != null ? '${_fmtQty(perUnit)} $unit/$orderUnit' : null,
      rateUnit: '/$unit',
    );
  }

  Widget _processLine(String label, String qty, String unit, {String? detail}) {
    final displayQty = unit.isEmpty ? qty : '$qty $unit';
    return _reportRow(
      label: label,
      qty: displayQty,
      detail: detail?.isEmpty ?? true ? null : detail,
      rateUnit: unit.isEmpty ? '' : '/$unit',
    );
  }

  Widget _wasteLine(OrderReportStage stage, double scrap) {
    return _reportRow(
      label:
          '${stage.name} — ${stage.material.isEmpty ? 'scrap' : '${stage.material} scrap'}',
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
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
          SizedBox(
            width: 116,
            child: Text(
              qty,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(
            width: 126,
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
            width: 132,
            child: Text('× ₹______$rateUnit', textAlign: TextAlign.right),
          ),
          const SizedBox(
            width: 118,
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
          Text(
            '$label:  ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
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
        row('COST PER UNIT (÷ ${_fmtQty(totalQty)})', '₹__________'),
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

  double? _materialTotalQty(OrderReportStage stage, double orderQty) {
    if (stage.allotted != null) return stage.allotted;
    if (stage.plannedMaterialQty != null) return stage.plannedMaterialQty;
    if (stage.quantityPerUnit != null && orderQty > 0) {
      return stage.quantityPerUnit! * orderQty;
    }
    return null;
  }

  double? _dieStrokeQty(OrderReportStage stage) {
    if (stage.output != null && stage.output! > 0) {
      if ((stage.dieStrokesPerPiece ?? 0) > 0) {
        return stage.output! * stage.dieStrokesPerPiece!;
      }
      if ((stage.dieCavities ?? 0) > 0) {
        return stage.output! / stage.dieCavities!;
      }
      return stage.output;
    }
    return null;
  }
}

const TextStyle _tableHeaderStyle = TextStyle(
  color: SoftErpTheme.textSecondary,
  fontSize: 11,
  fontWeight: FontWeight.w900,
);

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

double? _pdfMaterialTotalQty(OrderReportStage stage, double orderQty) {
  if (stage.allotted != null) return stage.allotted;
  if (stage.plannedMaterialQty != null) return stage.plannedMaterialQty;
  if (stage.quantityPerUnit != null && orderQty > 0) {
    return stage.quantityPerUnit! * orderQty;
  }
  return null;
}

double? _pdfDieStrokeQty(OrderReportStage stage) {
  if (stage.output != null && stage.output! > 0) {
    if ((stage.dieStrokesPerPiece ?? 0) > 0) {
      return stage.output! * stage.dieStrokesPerPiece!;
    }
    if ((stage.dieCavities ?? 0) > 0) {
      return stage.output! / stage.dieCavities!;
    }
    return stage.output;
  }
  return null;
}

String _pdfMachineDetail(OrderReportStage stage) {
  final parts = <String>[
    if ((stage.machineSetupMinutes ?? 0) > 0)
      '${_fmtQty(stage.machineSetupMinutes!)} min setup',
    if ((stage.machineOutputPerHour ?? 0) > 0)
      '${_fmtQty(stage.machineOutputPerHour!)} output/hr',
    if ((stage.machineLaborCount ?? 0) > 0)
      '${_fmtQty(stage.machineLaborCount!)} labor',
    if ((stage.machinePowerKw ?? 0) > 0) '${_fmtQty(stage.machinePowerKw!)} kW',
  ];
  return parts.join(' | ');
}

String _pdfDieDetail(OrderReportStage stage) {
  final parts = <String>[
    if ((stage.dieStrokesPerPiece ?? 0) > 0)
      '${_fmtQty(stage.dieStrokesPerPiece!)} strk/pc',
    if ((stage.dieCavities ?? 0) > 0) '${stage.dieCavities} cavities',
    if ((stage.dieMaxStrokes ?? 0) > 0)
      'life ${_fmtQty(stage.dieMaxStrokes!.toDouble())}',
    if ((stage.dieSetupMinutes ?? 0) > 0)
      '${_fmtQty(stage.dieSetupMinutes!)} min setup',
  ];
  return parts.join(' | ');
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
          if (report.poNumber.isNotEmpty) pw.Text('PO: ${report.poNumber}'),
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

          content.add(
            sectionTitle(
              report.runs.length > 1
                  ? 'MATERIALS — ${run.runName.isEmpty ? run.runId : run.runName}'
                  : 'MATERIALS',
            ),
          );
          for (final stage in run.stages) {
            if (stage.material.isEmpty) continue;
            final qty = _pdfMaterialTotalQty(stage, orderQty);
            final perUnit =
                stage.quantityPerUnit ??
                ((qty != null && orderQty > 0) ? qty / orderQty : null);
            content.add(
              line(
                label:
                    'Stage ${stage.stageIndex + 1} - ${stage.name} — ${stage.material}',
                qty: qty != null
                    ? '${_fmtQty(qty)} ${stage.materialUnit}'
                    : '____ ${stage.materialUnit}',
                detail: perUnit != null
                    ? '${_fmtQty(perUnit)} ${stage.materialUnit}/${item?.unitSymbol ?? 'pc'}'
                    : '',
                rateUnit: '/${stage.materialUnit}',
              ),
            );
          }
          content.add(subtotal('Subtotal Materials'));

          content.add(sectionTitle('PROCESS'));
          for (final stage in run.stages) {
            if (stage.machine.isNotEmpty) {
              content.add(
                line(
                  label: '${stage.machine} (${stage.name})',
                  qty:
                      '${_fmtHours(stage.workedHours ?? stage.plannedHours)} hr',
                  detail: _pdfMachineDetail(stage),
                  rateUnit: '/hr',
                ),
              );
            }
            if (stage.dieId.isNotEmpty) {
              final strokes = _pdfDieStrokeQty(stage);
              content.add(
                line(
                  label:
                      'Die ${stage.dieToolCode.isEmpty ? stage.dieId : stage.dieToolCode}',
                  qty: '${strokes == null ? '____' : _fmtQty(strokes)} strk',
                  detail: _pdfDieDetail(stage),
                  rateUnit: '/strk',
                ),
              );
            }
          }
          content.add(line(label: 'Labor', qty: '____ hr', rateUnit: '/hr'));
          content.add(
            line(
              label: 'Process Cost',
              qty: '____',
              detail: 'machine + labor + die',
              rateUnit: '',
            ),
          );
          content.add(subtotal('Subtotal Process'));

          content.add(sectionTitle('WASTE'));
          for (final stage in run.stages) {
            final scrap = stage.scrap ?? 0;
            if (scrap <= 0) continue;
            content.add(
              line(
                label:
                    '${stage.name} — ${stage.material.isEmpty ? 'scrap' : '${stage.material} scrap'}',
                qty: '${_fmtQty(scrap)} ${stage.materialUnit}',
                rateUnit: '/${stage.materialUnit}',
              ),
            );
          }
          content.add(
            line(
              label: 'Waste Adjustment',
              qty: '____',
              detail: 'manual',
              rateUnit: '',
            ),
          );
          content.add(subtotal('Subtotal Waste'));
        }

        content.add(pw.Divider());
        content.add(subtotal('GRAND TOTAL'));
        content.add(subtotal('COST PER UNIT (/ ${_fmtQty(totalQty)})'));
        content.add(
          pw.Padding(
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
          ),
        );
        content.add(subtotal('MARGIN PER UNIT'));
        content.add(subtotal('MARGIN %'));
        return content;
      },
    ),
  );

  return doc.save();
}
