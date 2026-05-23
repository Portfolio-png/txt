import 'package:excel/excel.dart' as xls;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/soft_erp_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../features/delivery_challans/data/delivery_challan_repository.dart';
import '../../../features/delivery_challans/domain/delivery_challan.dart';
import '../../../features/delivery_challans/presentation/providers/delivery_challan_provider.dart';
import '../domain/reconciliation_report.dart';
import 'item_pricing_dialog.dart';

class ClientReportGeneratorDialog extends StatefulWidget {
  const ClientReportGeneratorDialog({super.key});

  static Future<void> open(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const ClientReportGeneratorDialog(),
    );
  }

  @override
  State<ClientReportGeneratorDialog> createState() =>
      _ClientReportGeneratorDialogState();
}

class _ClientReportGeneratorDialogState
    extends State<ClientReportGeneratorDialog> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedChallanIds = <String>{};
  final Set<String> _selectedReceptionChallanIds = <String>{};
  final Map<String, DeliveryChallan> _challansByNo =
      <String, DeliveryChallan>{};
  final Map<String, DeliveryChallan> _receptionChallansByNo =
      <String, DeliveryChallan>{};

  String? _focusedChallanId;
  bool _isLoading = true;
  bool _isExporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadChallans());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  ChallanRepository get _repository =>
      context.read<DeliveryChallanProvider>().repository;

  List<DeliveryChallan> get _challans {
    final query = _searchController.text.trim().toLowerCase();
    final values = _challansByNo.values.toList(growable: false)
      ..sort((a, b) {
        final usedCompare = (a.usedInReport ? 1 : 0).compareTo(
          b.usedInReport ? 1 : 0,
        );
        if (usedCompare != 0) {
          return usedCompare;
        }
        final dateCompare = b.date.compareTo(a.date);
        return dateCompare == 0 ? b.id.compareTo(a.id) : dateCompare;
      });
    if (query.isEmpty) {
      return values;
    }
    return values
        .where((challan) {
          final haystack = <String>[
            challan.customerName,
            challan.orderNo,
            challan.orderNos.join(' '),
            challan.challanNo,
            ...challan.items.expand(
              (item) => <String>[item.particulars, item.hsnCode, item.note],
            ),
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  List<DeliveryChallan> get _receptionChallans {
    final query = _searchController.text.trim().toLowerCase();
    final values = _receptionChallansByNo.values.toList(growable: false)
      ..sort((a, b) {
        final usedCompare = (a.usedInReport ? 1 : 0).compareTo(
          b.usedInReport ? 1 : 0,
        );
        if (usedCompare != 0) {
          return usedCompare;
        }
        final dateCompare = b.date.compareTo(a.date);
        return dateCompare == 0 ? b.id.compareTo(a.id) : dateCompare;
      });
    if (query.isEmpty) {
      return values;
    }
    return values
        .where((challan) {
          final haystack = <String>[
            challan.customerName,
            challan.orderNo,
            challan.orderNos.join(' '),
            challan.challanNo,
            ...challan.items.expand(
              (item) => <String>[item.particulars, item.hsnCode, item.note],
            ),
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  DeliveryChallan? get _focusedChallan {
    if (_focusedChallanId == null) {
      return null;
    }
    return _challansByNo[_focusedChallanId!] ??
        _receptionChallansByNo[_focusedChallanId!];
  }

  Future<void> _loadChallans() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final summaries = await _repository.getChallans(
        type: ChallanType.delivery,
        status: DeliveryChallanStatus.issued,
      );
      final fullChallans = await Future.wait(
        summaries.map((challan) => _repository.getChallan(challan.id)),
      );

      final receptionSummaries = await _repository.getChallans(
        type: ChallanType.reception,
        status: DeliveryChallanStatus.issued,
      );
      final fullReceptions = await Future.wait(
        receptionSummaries.map((challan) => _repository.getChallan(challan.id)),
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _challansByNo
          ..clear()
          ..addEntries(
            fullChallans.map((challan) => MapEntry(challan.challanNo, challan)),
          );
        _receptionChallansByNo
          ..clear()
          ..addEntries(
            fullReceptions.map(
              (challan) => MapEntry(challan.challanNo, challan),
            ),
          );
        _selectedChallanIds.removeWhere(
          (challanNo) => !_challansByNo.containsKey(challanNo),
        );
        _selectedReceptionChallanIds.removeWhere(
          (challanNo) => !_receptionChallansByNo.containsKey(challanNo),
        );
        if (_focusedChallanId != null &&
            !_challansByNo.containsKey(_focusedChallanId) &&
            !_receptionChallansByNo.containsKey(_focusedChallanId)) {
          _focusedChallanId = null;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<ClientStatementReport?> _generateReport() async {
    if (_selectedChallanIds.isEmpty && _selectedReceptionChallanIds.isEmpty) {
      return null;
    }
    setState(() => _isExporting = true);
    try {
      final selectedNos = _selectedChallanIds.toList(growable: false)..sort();
      final selectedReceptionNos = _selectedReceptionChallanIds.toList(
        growable: false,
      )..sort();
      final report = await _repository.generateClientStatementReport(
        reportGroupCode: _selectedReportGroupCode(),
        challanNos: selectedNos,
        receptionChallanNos: selectedReceptionNos,
      );
      if (mounted) {
        setState(() {
          for (final challanNo in selectedNos) {
            final challan = _challansByNo[challanNo];
            if (challan != null) {
              _challansByNo[challanNo] = challan.copyWith(usedInReport: true);
            }
          }
          for (final challanNo in selectedReceptionNos) {
            final challan = _receptionChallansByNo[challanNo];
            if (challan != null) {
              _receptionChallansByNo[challanNo] = challan.copyWith(
                usedInReport: true,
              );
            }
          }
        });
      }
      return report;
    } catch (error) {
      if (mounted) {
        _showSnack(error.toString());
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _exportXlsx() async {
    final report = await _generateReport();
    if (report == null || report.rows.isEmpty) {
      return;
    }
    final uniqueItems =
        report.rows
            .map((r) => r.itemName)
            .where((n) => n.trim().isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();

    if (!mounted) {
      return;
    }
    final pricingRules = await ItemPricingDialog.open(context, uniqueItems);
    if (pricingRules == null) {
      return;
    }

    try {
      final excel = xls.Excel.createExcel();
      final sheet = excel['Client Statement'];
      sheet.appendRow([
        xls.TextCellValue('Date'),
        xls.TextCellValue('Challan No'),
        xls.TextCellValue('Client'),
        xls.TextCellValue('Order'),
        xls.TextCellValue('Item Name'),
        xls.TextCellValue('Note'),
        xls.TextCellValue('Qty'),
        xls.TextCellValue('Weight'),
        xls.TextCellValue('Unit Price'),
        xls.TextCellValue('Total Amount'),
      ]);

      double grandTotal = 0;

      for (final row in report.rows) {
        final rule = pricingRules[row.itemName];
        double total = 0;
        String priceText = '';

        if (rule != null) {
          final factor = rule.metric == PricingMetric.pcs
              ? row.quantityPcs
              : row.weight;
          total = factor * rule.price;
          grandTotal += total;
          priceText =
              '₹${_fmtCurrency(rule.price)} (per ${rule.metric == PricingMetric.pcs ? 'Pc' : 'Kg'})';
        }

        sheet.appendRow([
          xls.TextCellValue(_date(row.date)),
          xls.TextCellValue(row.challanNo),
          xls.TextCellValue(row.clientName),
          xls.TextCellValue(row.orderNo),
          xls.TextCellValue(row.itemName),
          xls.TextCellValue(row.note),
          xls.DoubleCellValue(row.quantityPcs),
          xls.DoubleCellValue(row.weight),
          xls.TextCellValue(priceText),
          xls.DoubleCellValue(total),
        ]);
      }

      // Append summary row
      sheet.appendRow([
        xls.TextCellValue(''),
        xls.TextCellValue(''),
        xls.TextCellValue(''),
        xls.TextCellValue(''),
        xls.TextCellValue(''),
        xls.TextCellValue('GRAND TOTAL:'),
        xls.DoubleCellValue(report.totalQuantityPcs),
        xls.DoubleCellValue(report.totalWeight),
        xls.TextCellValue(''),
        xls.DoubleCellValue(grandTotal),
      ]);

      if (excel.sheets.containsKey('Sheet1') && excel.sheets.length > 1) {
        excel.delete('Sheet1');
      }
      final bytes = excel.encode();
      if (bytes == null) {
        throw StateError('Failed to encode client statement.');
      }
      final fileName = 'client-statement-${_timestamp()}.xlsx';
      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Excel workbook',
            extensions: ['xlsx'],
            mimeTypes: [
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ],
          ),
        ],
      );
      if (location == null) {
        return;
      }
      await XFile.fromData(
        Uint8List.fromList(bytes),
        name: fileName,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ).saveTo(location.path);
      if (mounted) {
        _showSnack('Exported ${location.path}.');
      }
    } catch (error) {
      if (mounted) {
        _showSnack(error.toString());
      }
    }
  }

  Future<void> _printPdf() async {
    final report = await _generateReport();
    if (report == null || report.rows.isEmpty) {
      return;
    }

    if (!mounted) {
      return;
    }

    // 1. Prompt for options
    final options = await _ReportOptionsDialog.open(context);
    if (options == null) {
      return;
    }

    // 2. Filter unique items for pricing dialog (exclude scrap)
    final scrapKeyword = options.scrapItemKeyword.toLowerCase();
    final uniqueItems =
        report.rows
            .map((r) => r.itemName)
            .where(
              (n) =>
                  n.trim().isNotEmpty &&
                  !n.toLowerCase().contains(scrapKeyword),
            )
            .toSet()
            .toList(growable: false)
          ..sort();

    if (!mounted) {
      return;
    }

    final pricingRules = uniqueItems.isEmpty
        ? <String, PricingRule>{}
        : await ItemPricingDialog.open(context, uniqueItems);

    if (uniqueItems.isNotEmpty && pricingRules == null) {
      return;
    }

    try {
      final profile = await _repository.getCompanyProfile();

      double subtotal = 0;
      double totalWastageWeight = 0;

      final document = pw.Document();

      // Helper function to build cells
      pw.Widget buildCell(
        pw.Widget childWidget, {
        pw.Alignment alignment = pw.Alignment.centerLeft,
        bool showRightDivider = false,
        bool showBottomLine = true,
        PdfColor? bgColor,
        double paddingHorizontal = 3,
        double paddingVertical = 3,
      }) {
        return pw.Container(
          alignment: alignment,
          padding: pw.EdgeInsets.symmetric(
            horizontal: paddingHorizontal,
            vertical: paddingVertical,
          ),
          decoration: pw.BoxDecoration(
            color: bgColor,
            border: pw.Border(
              right: showRightDivider
                  ? const pw.BorderSide(color: PdfColors.black, width: 1.2)
                  : const pw.BorderSide(color: PdfColors.grey300, width: 0.5),
              bottom: showBottomLine
                  ? const pw.BorderSide(color: PdfColors.grey300, width: 0.5)
                  : pw.BorderSide.none,
            ),
          ),
          child: childWidget,
        );
      }

      pw.Widget buildTextCell(
        String text, {
        pw.Alignment alignment = pw.Alignment.centerLeft,
        pw.TextStyle? style,
        bool showRightDivider = false,
        bool showBottomLine = true,
        PdfColor? bgColor,
        double paddingHorizontal = 3,
        double paddingVertical = 3,
      }) {
        return buildCell(
          pw.Text(
            text,
            style: style ?? const pw.TextStyle(fontSize: 8),
            maxLines: 2,
            overflow: pw.TextOverflow.clip,
          ),
          alignment: alignment,
          showRightDivider: showRightDivider,
          showBottomLine: showBottomLine,
          bgColor: bgColor,
          paddingHorizontal: paddingHorizontal,
          paddingVertical: paddingVertical,
        );
      }

      final headerStyle = pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 8,
      );
      final headerRow = pw.TableRow(
        children: [
          buildTextCell("", alignment: pw.Alignment.center, style: headerStyle),
          buildTextCell(
            "Date",
            alignment: pw.Alignment.center,
            style: headerStyle,
          ),
          buildTextCell(
            "Size",
            alignment: pw.Alignment.center,
            style: headerStyle,
          ),
          buildTextCell(
            "Weight",
            alignment: pw.Alignment.center,
            style: headerStyle,
            showRightDivider: true,
          ),
          buildTextCell(
            "Date",
            alignment: pw.Alignment.center,
            style: headerStyle,
          ),
          buildTextCell(
            "CHLL.No.",
            alignment: pw.Alignment.center,
            style: headerStyle,
          ),
          buildTextCell(
            "Particulars",
            alignment: pw.Alignment.center,
            style: headerStyle,
          ),
          buildTextCell(
            "Weight",
            alignment: pw.Alignment.center,
            style: headerStyle,
          ),
          buildTextCell(
            "Pcs",
            alignment: pw.Alignment.center,
            style: headerStyle,
          ),
          buildTextCell(
            "Rate",
            alignment: pw.Alignment.center,
            style: headerStyle,
          ),
          buildTextCell(
            "Amount",
            alignment: pw.Alignment.center,
            style: headerStyle,
          ),
        ],
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      );

      final groupWidgets = <pw.Widget>[];

      for (final group in report.receptionGroups) {
        double groupTotalPcs = 0;
        double groupTotalAmount = 0;
        final tableRows = <pw.TableRow>[];

        tableRows.add(headerRow);

        final deliveries = group.deliveries;
        final n = deliveries.isNotEmpty ? deliveries.length : 1;

        for (int i = 0; i < n; i++) {
          final item = deliveries.isNotEmpty ? deliveries[i] : null;
          final isScrap =
              item != null &&
              item.particulars.toLowerCase().contains(scrapKeyword);

          double itemAmount = 0;
          double itemPcs = 0;
          String rateText = "";
          String amountText = "";

          if (item != null) {
            itemPcs = item.quantityPcs;
            if (isScrap) {
              totalWastageWeight += item.weight;
            } else {
              final rule = pricingRules?[item.particulars];
              if (rule != null) {
                final factor = rule.metric == PricingMetric.pcs
                    ? item.quantityPcs
                    : item.weight;
                itemAmount = factor * rule.price;
                subtotal += itemAmount;
                groupTotalAmount += itemAmount;
                rateText = _fmtCurrency(rule.price);
                amountText = _fmtCurrency(itemAmount);
              }
              groupTotalPcs += item.quantityPcs;
            }
          }

          tableRows.add(
            pw.TableRow(
              children: [
                // Reception Checkbox
                buildCell(
                  i == 0
                      ? pw.Center(
                          child: pw.Container(
                            width: 7,
                            height: 7,
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(
                                color: PdfColors.black,
                                width: 0.8,
                              ),
                            ),
                            alignment: pw.Alignment.center,
                            child: pw.Text(
                              'x',
                              style: pw.TextStyle(
                                fontSize: 5,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                        )
                      : pw.SizedBox.shrink(),
                  alignment: pw.Alignment.center,
                ),
                // Reception Date
                buildTextCell(
                  i == 0 ? _date(group.receptionDate) : "",
                  alignment: pw.Alignment.center,
                ),
                // Reception Size
                buildTextCell(i == 0 ? group.receptionSize : ""),
                // Reception Weight
                buildTextCell(
                  i == 0 ? _fmt(group.receptionWeight) : "",
                  alignment: pw.Alignment.centerRight,
                  showRightDivider: true,
                ),
                // Delivery Date
                buildTextCell(
                  item != null ? _date(item.date) : "",
                  alignment: pw.Alignment.center,
                ),
                // Delivery CHLL.No.
                buildTextCell(
                  item != null ? item.challanNo : "",
                  alignment: pw.Alignment.center,
                ),
                // Delivery Particulars
                buildCell(
                  item != null
                      ? pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              item.particulars,
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                            if (item.note.trim().isNotEmpty)
                              pw.Text(
                                item.note.trim(),
                                style: pw.TextStyle(
                                  fontSize: 6,
                                  fontStyle: pw.FontStyle.italic,
                                  color: PdfColors.grey700,
                                ),
                              ),
                          ],
                        )
                      : pw.SizedBox.shrink(),
                ),
                // Delivery Weight
                buildTextCell(
                  item != null ? _fmt(item.weight) : "",
                  alignment: pw.Alignment.centerRight,
                ),
                // Delivery Pcs
                buildTextCell(
                  item != null ? _fmt(itemPcs) : "",
                  alignment: pw.Alignment.centerRight,
                ),
                // Delivery Rate
                buildTextCell(rateText, alignment: pw.Alignment.centerRight),
                // Delivery Amount
                buildTextCell(amountText, alignment: pw.Alignment.centerRight),
              ],
            ),
          );
        }

        if (group.lessWeight > 0) {
          tableRows.add(
            pw.TableRow(
              children: [
                buildTextCell(""),
                buildTextCell(""),
                buildTextCell(""),
                buildTextCell("", showRightDivider: true),
                buildTextCell(""),
                buildTextCell(""),
                buildTextCell(
                  "LESS",
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700,
                  ),
                ),
                buildTextCell(
                  _fmt(group.lessWeight),
                  alignment: pw.Alignment.centerRight,
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700,
                  ),
                ),
                buildTextCell(""),
                buildTextCell(""),
                buildTextCell(""),
              ],
            ),
          );
        }

        final totalStyle = pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          fontSize: 8,
        );
        tableRows.add(
          pw.TableRow(
            children: [
              buildTextCell(""),
              buildTextCell(""),
              buildTextCell("TOTAL", style: totalStyle),
              buildTextCell(
                _fmt(group.receptionWeight),
                alignment: pw.Alignment.centerRight,
                style: totalStyle,
                showRightDivider: true,
              ),
              buildTextCell(""),
              buildTextCell(""),
              buildTextCell("TOTAL", style: totalStyle),
              buildTextCell(
                _fmt(group.totalWeight),
                alignment: pw.Alignment.centerRight,
                style: totalStyle,
              ),
              buildTextCell(
                _fmt(groupTotalPcs),
                alignment: pw.Alignment.centerRight,
                style: totalStyle,
              ),
              buildTextCell(""),
              buildTextCell(
                _fmtCurrency(groupTotalAmount),
                alignment: pw.Alignment.centerRight,
                style: totalStyle,
              ),
            ],
            decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
        );

        final superHeader = pw.Row(
          children: [
            pw.Container(
              width: 170,
              alignment: pw.Alignment.center,
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  top: pw.BorderSide(color: PdfColors.black, width: 1),
                  left: pw.BorderSide(color: PdfColors.black, width: 1),
                  right: pw.BorderSide(color: PdfColors.black, width: 1.5),
                  bottom: pw.BorderSide(color: PdfColors.black, width: 1),
                ),
                color: PdfColors.grey100,
              ),
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Text(
                'RECEPTION (INPUT)',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8,
                ),
              ),
            ),
            pw.Container(
              width: 381,
              alignment: pw.Alignment.center,
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  top: pw.BorderSide(color: PdfColors.black, width: 1),
                  right: pw.BorderSide(color: PdfColors.black, width: 1),
                  bottom: pw.BorderSide(color: PdfColors.black, width: 1),
                ),
                color: PdfColors.grey100,
              ),
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Text(
                'DELIVERY (OUTPUT)',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8,
                ),
              ),
            ),
          ],
        );

        final table = pw.Table(
          columnWidths: const {
            0: pw.FixedColumnWidth(15.0),
            1: pw.FixedColumnWidth(50.0),
            2: pw.FixedColumnWidth(60.0),
            3: pw.FixedColumnWidth(45.0),
            4: pw.FixedColumnWidth(50.0),
            5: pw.FixedColumnWidth(45.0),
            6: pw.FixedColumnWidth(116.0),
            7: pw.FixedColumnWidth(45.0),
            8: pw.FixedColumnWidth(35.0),
            9: pw.FixedColumnWidth(40.0),
            10: pw.FixedColumnWidth(50.0),
          },
          border: const pw.TableBorder(
            bottom: pw.BorderSide(color: PdfColors.black, width: 1),
            left: pw.BorderSide(color: PdfColors.black, width: 1),
            right: pw.BorderSide(color: PdfColors.black, width: 1),
            horizontalInside: pw.BorderSide(
              color: PdfColors.grey300,
              width: 0.5,
            ),
          ),
          children: tableRows,
        );

        groupWidgets.add(
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [superHeader, table, pw.SizedBox(height: 12)],
            ),
          ),
        );
      }

      double wastageCredit = totalWastageWeight * options.scrapRate;
      double netTotal = subtotal - wastageCredit;
      int grandTotal = netTotal.round();
      double rdOff = grandTotal - netTotal;

      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(22),
          header: (context) {
            if (context.pageNumber == 1) {
              return pw.Column(
                children: [
                  pw.Center(
                    child: pw.Text(
                      profile.companyName.toUpperCase(),
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Center(
                    child: pw.Text(
                      profile.address,
                      style: const pw.TextStyle(fontSize: 8),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Center(
                    child: pw.Text(
                      'Mobile: ${profile.mobile}    GSTIN: ${profile.gstin}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Divider(color: PdfColors.black, thickness: 1),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Client: ${report.rows.firstOrNull?.clientName ?? ""}',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                      pw.Text(
                        'Date: ${_date(report.generatedAt ?? DateTime.now())}    Page: ${context.pageNumber}',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  pw.Center(
                    child: pw.Text(
                      'STATEMENT',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 10),
                ],
              );
            } else {
              return pw.Column(
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Client Statement: ${report.rows.firstOrNull?.clientName ?? ""}',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9,
                        ),
                      ),
                      pw.Text(
                        'Page ${context.pageNumber}',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Divider(color: PdfColors.grey300, thickness: 0.5),
                  pw.SizedBox(height: 8),
                ],
              );
            }
          },
          build: (context) => [
            ...groupWidgets,
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${options.scrapLabel} (${_fmt(totalWastageWeight)} Kg @ Rs ${_fmt(options.scrapRate)}/Kg):',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 9,
                  ),
                ),
                pw.Text(
                  '(-) Rs ${_fmtCurrency(wastageCredit)}',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(color: PdfColors.black, thickness: 1),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Row(
                      children: [
                        pw.Text(
                          'Subtotal:  ',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                        pw.SizedBox(
                          width: 80,
                          child: pw.Text(
                            'Rs ${_fmtCurrency(subtotal)}',
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      children: [
                        pw.Text(
                          'Wastage Credit:  ',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                        pw.SizedBox(
                          width: 80,
                          child: pw.Text(
                            'Rs ${_fmtCurrency(wastageCredit)}',
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      children: [
                        pw.Text(
                          'Total:  ',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 9,
                          ),
                        ),
                        pw.SizedBox(
                          width: 80,
                          child: pw.Text(
                            'Rs ${_fmtCurrency(netTotal)}',
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      children: [
                        pw.Text(
                          'RD OFF:  ',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                        pw.SizedBox(
                          width: 80,
                          child: pw.Text(
                            '${rdOff >= 0 ? "+" : ""}${_fmtCurrency(rdOff)}',
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(color: PdfColors.black, width: 1),
                          bottom: pw.BorderSide(
                            color: PdfColors.black,
                            width: 1,
                          ),
                        ),
                      ),
                      child: pw.Row(
                        children: [
                          pw.Text(
                            'Grand Total:  ',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          pw.SizedBox(
                            width: 80,
                            child: pw.Text(
                              'Rs $grandTotal',
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

      final bytes = await document.save();
      await Printing.layoutPdf(
        name: 'client-statement-${_timestamp()}.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (error) {
      if (mounted) {
        _showSnack(error.toString());
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _selectedReportGroupCode() {
    final codes = <String>{};
    for (final challanNo in _selectedChallanIds) {
      codes.addAll(_challansByNo[challanNo]?.reportGroupCodes ?? const []);
    }
    for (final challanNo in _selectedReceptionChallanIds) {
      codes.addAll(
        _receptionChallansByNo[challanNo]?.reportGroupCodes ?? const [],
      );
    }
    return codes.length == 1 ? codes.single : '';
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focusedChallan;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rightOpen = focused != null;
          final maxWidth = MediaQuery.sizeOf(context).width - 48;
          final leftWidth = maxWidth < 980 ? 440.0 : 500.0;
          final rightWidth = rightOpen
              ? (maxWidth - leftWidth - 20).clamp(0, 560).toDouble()
              : 0.0;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: rightOpen ? leftWidth + 20 + rightWidth : leftWidth,
                maxHeight: MediaQuery.sizeOf(context).height - 48,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _FloatingCard(
                    width: leftWidth,
                    child: _SelectionPane(
                      controller: _searchController,
                      challans: _challans,
                      receptionChallans: _receptionChallans,
                      selectedChallanIds: _selectedChallanIds,
                      selectedReceptionChallanIds: _selectedReceptionChallanIds,
                      focusedChallanId: _focusedChallanId,
                      isLoading: _isLoading,
                      error: _error,
                      onSearchChanged: (_) => setState(() {}),
                      onRefresh: _loadChallans,
                      onClose: () => Navigator.of(context).pop(),
                      onToggle: (challanNo, selected) {
                        setState(() {
                          if (selected) {
                            _selectedChallanIds.add(challanNo);
                          } else {
                            _selectedChallanIds.remove(challanNo);
                          }
                        });
                      },
                      onToggleReception: (challanNo, selected) {
                        setState(() {
                          if (selected) {
                            _selectedReceptionChallanIds.add(challanNo);
                          } else {
                            _selectedReceptionChallanIds.remove(challanNo);
                          }
                        });
                      },
                      onFocus: (challanNo) =>
                          setState(() => _focusedChallanId = challanNo),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    width: rightOpen ? 20 : 0,
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    width: rightWidth,
                    child: ClipRect(
                      child: SizedBox(
                        width: rightWidth,
                        child: rightOpen
                            ? _FloatingCard(
                                width: rightWidth,
                                child: _PreviewPane(
                                  challan: focused,
                                  selectedCount: _selectedChallanIds.length,
                                  selectedReceptionCount:
                                      _selectedReceptionChallanIds.length,
                                  isExporting: _isExporting,
                                  onExport:
                                      (_selectedChallanIds.isEmpty &&
                                          _selectedReceptionChallanIds.isEmpty)
                                      ? null
                                      : _exportXlsx,
                                  onPrint:
                                      (_selectedChallanIds.isEmpty &&
                                          _selectedReceptionChallanIds.isEmpty)
                                      ? null
                                      : _printPdf,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FloatingCard extends StatelessWidget {
  const _FloatingCard({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 680,
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(20), child: child),
    );
  }
}

class _SelectionPane extends StatelessWidget {
  const _SelectionPane({
    required this.controller,
    required this.challans,
    required this.receptionChallans,
    required this.selectedChallanIds,
    required this.selectedReceptionChallanIds,
    required this.focusedChallanId,
    required this.isLoading,
    required this.error,
    required this.onSearchChanged,
    required this.onRefresh,
    required this.onClose,
    required this.onToggle,
    required this.onToggleReception,
    required this.onFocus,
  });

  final TextEditingController controller;
  final List<DeliveryChallan> challans;
  final List<DeliveryChallan> receptionChallans;
  final Set<String> selectedChallanIds;
  final Set<String> selectedReceptionChallanIds;
  final String? focusedChallanId;
  final bool isLoading;
  final String? error;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onRefresh;
  final VoidCallback onClose;
  final void Function(String challanNo, bool selected) onToggle;
  final void Function(String challanNo, bool selected) onToggleReception;
  final ValueChanged<String> onFocus;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Client Report',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Select deliveries and receptions.',
                        style: TextStyle(color: SoftErpTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: isLoading ? null : onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: controller,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Search client, order, or challan',
                filled: true,
                fillColor: SoftErpTheme.cardSurfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: SoftErpTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: SoftErpTheme.border),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const TabBar(
            tabs: [
              Tab(text: 'Deliveries'),
              Tab(text: 'Receptions'),
            ],
            indicatorColor: SoftErpTheme.accent,
            labelColor: SoftErpTheme.textPrimary,
            unselectedLabelColor: SoftErpTheme.textSecondary,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              children: [
                _buildList(
                  context,
                  challans,
                  selectedChallanIds,
                  onToggle,
                  'No issued delivery challans',
                  'Issue delivery challans first, then generate client reports.',
                ),
                _buildList(
                  context,
                  receptionChallans,
                  selectedReceptionChallanIds,
                  onToggleReception,
                  'No issued reception challans',
                  'Create and issue reception challans first.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    List<DeliveryChallan> list,
    Set<String> selectedIds,
    void Function(String challanNo, bool selected) toggleCallback,
    String emptyTitle,
    String emptyMessage,
  ) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return _PaneMessage(
        icon: Icons.warning_amber_rounded,
        title: 'Failed to load challans',
        message: error!,
      );
    }
    if (list.isEmpty) {
      return _PaneMessage(
        icon: Icons.inbox_outlined,
        title: emptyTitle,
        message: emptyMessage,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final challan = list[index];
        return _ChallanSelectionRow(
          challan: challan,
          selected: selectedIds.contains(challan.challanNo),
          focused: focusedChallanId == challan.challanNo,
          onToggle: (selected) => toggleCallback(challan.challanNo, selected),
          onFocus: () => onFocus(challan.challanNo),
        );
      },
    );
  }
}

class _ChallanSelectionRow extends StatefulWidget {
  const _ChallanSelectionRow({
    required this.challan,
    required this.selected,
    required this.focused,
    required this.onToggle,
    required this.onFocus,
  });

  final DeliveryChallan challan;
  final bool selected;
  final bool focused;
  final ValueChanged<bool> onToggle;
  final VoidCallback onFocus;

  @override
  State<_ChallanSelectionRow> createState() => _ChallanSelectionRowState();
}

class _ChallanSelectionRowState extends State<_ChallanSelectionRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final quantity = widget.challan.items.fold<double>(
      0,
      (sum, item) => sum + (double.tryParse(item.quantityPcs) ?? 0),
    );
    final weight = widget.challan.items.fold<double>(
      0,
      (sum, item) => sum + (double.tryParse(item.weight) ?? 0),
    );

    Widget cardContent = Column(
      children: [
        Row(
          children: [
            Checkbox(
              value: widget.selected,
              onChanged: (value) => widget.onToggle(value == true),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  widget.onFocus();
                  setState(() {
                    _expanded = !_expanded;
                  });
                },
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    4,
                    10,
                    widget.challan.maintainStocks ? 12 : 24,
                    10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.challan.challanNo,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.challan.customerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: SoftErpTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _date(widget.challan.date),
                              style: const TextStyle(
                                color: SoftErpTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            if (widget.challan.usedInReport)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: SoftErpTheme.border,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'USED IN REPORT',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: SoftErpTheme.textSecondary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                          top: widget.challan.maintainStocks ? 0 : 12,
                        ),
                        child: Text(
                          'Qty ${_fmt(quantity)}\nWt ${_fmt(weight)}',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            color: SoftErpTheme.textSecondary,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_expanded) ...[
          if (widget.challan.items.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(50, 0, 14, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No line items in this challan.',
                  style: TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(50, 0, 14, 12),
              child: Column(
                children: widget.challan.items
                    .map((item) => _OrderItemPreviewRow(item: item))
                    .toList(growable: false),
              ),
            ),
        ],
      ],
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: widget.focused
            ? SoftErpTheme.accent.withValues(alpha: 0.08)
            : SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.focused ? SoftErpTheme.accent : SoftErpTheme.border,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          children: [
            cardContent,
            if (!widget.challan.maintainStocks)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: const BoxDecoration(
                    color: SoftErpTheme.dangerBg,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'STOCK: OFF',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: SoftErpTheme.dangerText,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OrderItemPreviewRow extends StatelessWidget {
  const _OrderItemPreviewRow({required this.item});

  final DeliveryChallanItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 16,
            color: SoftErpTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.particulars.trim().isEmpty
                      ? 'Unnamed item'
                      : item.particulars.trim(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                if (item.note.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.note.trim(),
                    style: const TextStyle(
                      color: SoftErpTheme.textSecondary,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _TinyInfoPill(
                      label: 'HSN',
                      value: item.hsnCode.trim().isEmpty
                          ? '-'
                          : item.hsnCode.trim(),
                    ),
                    _TinyInfoPill(
                      label: 'Qty',
                      value: item.quantityPcs.trim().isEmpty
                          ? '0'
                          : item.quantityPcs.trim(),
                    ),
                    _TinyInfoPill(
                      label: 'Wt',
                      value: item.weight.trim().isEmpty
                          ? '0'
                          : item.weight.trim(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyInfoPill extends StatelessWidget {
  const _TinyInfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Text(
        '$label $value',
        style: const TextStyle(
          color: SoftErpTheme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({
    required this.challan,
    required this.selectedCount,
    required this.selectedReceptionCount,
    required this.isExporting,
    required this.onExport,
    required this.onPrint,
  });

  final DeliveryChallan challan;
  final int selectedCount;
  final int selectedReceptionCount;
  final bool isExporting;
  final VoidCallback? onExport;
  final VoidCallback? onPrint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$selectedCount Del. / $selectedReceptionCount Rec. Selected',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              if (selectedCount == 0 && selectedReceptionCount == 0)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: SoftErpTheme.dangerBg.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: SoftErpTheme.dangerText.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: SoftErpTheme.dangerText,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Select at least one delivery or reception challan.',
                          style: const TextStyle(
                            color: SoftErpTheme.dangerText,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppButton(
                    label: isExporting ? 'Working...' : 'Export XLSX',
                    icon: Icons.table_view_outlined,
                    variant: AppButtonVariant.secondary,
                    isLoading: isExporting,
                    onPressed: onExport,
                  ),
                  AppButton(
                    label: 'Print PDF',
                    icon: Icons.print_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: isExporting ? null : onPrint,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Previewing ${challan.challanNo} for ${challan.customerName}.',
                style: const TextStyle(color: SoftErpTheme.textSecondary),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: SoftErpTheme.border),
        Expanded(
          child: challan.items.isEmpty
              ? const _PaneMessage(
                  icon: Icons.receipt_long_outlined,
                  title: 'No items',
                  message: 'This challan has no line items to preview.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(18),
                  itemCount: challan.items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = challan.items[index];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: SoftErpTheme.cardSurfaceAlt,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: SoftErpTheme.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.particulars,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (item.note.trim().isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    item.note.trim(),
                                    style: const TextStyle(
                                      color: SoftErpTheme.textSecondary,
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            'Qty ${item.quantityPcs.isEmpty ? '0' : item.quantityPcs}\nWt ${item.weight.isEmpty ? '0' : item.weight}',
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              color: SoftErpTheme.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PaneMessage extends StatelessWidget {
  const _PaneMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 38, color: SoftErpTheme.textSecondary),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: const TextStyle(color: SoftErpTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime? value) {
  if (value == null) {
    return '-';
  }
  return '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';
}

String _timestamp() {
  final now = DateTime.now();
  return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
}

String _fmt(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(2);
}

String _fmtCurrency(double value) {
  return value.toStringAsFixed(2);
}

class _ReportOptions {
  final double scrapRate;
  final String scrapLabel;
  final String scrapItemKeyword;

  const _ReportOptions({
    required this.scrapRate,
    required this.scrapLabel,
    required this.scrapItemKeyword,
  });
}

class _ReportOptionsDialog extends StatefulWidget {
  const _ReportOptionsDialog();

  static Future<_ReportOptions?> open(BuildContext context) {
    return showDialog<_ReportOptions?>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _ReportOptionsDialog(),
    );
  }

  @override
  State<_ReportOptionsDialog> createState() => _ReportOptionsDialogState();
}

class _ReportOptionsDialogState extends State<_ReportOptionsDialog> {
  late final TextEditingController _scrapRateController;
  late final TextEditingController _scrapLabelController;
  late final TextEditingController _scrapItemKeywordController;

  @override
  void initState() {
    super.initState();
    _scrapRateController = TextEditingController(text: '170.00');
    _scrapLabelController = TextEditingController(
      text: 'ALUMINIUM WASTAGE LESS',
    );
    _scrapItemKeywordController = TextEditingController(text: 'wastage');
  }

  @override
  void dispose() {
    _scrapRateController.dispose();
    _scrapLabelController.dispose();
    _scrapItemKeywordController.dispose();
    super.dispose();
  }

  void _submit() {
    final rate = double.tryParse(_scrapRateController.text.trim()) ?? 170.0;
    final label = _scrapLabelController.text.trim();
    final keyword = _scrapItemKeywordController.text.trim();
    Navigator.of(context).pop(
      _ReportOptions(
        scrapRate: rate,
        scrapLabel: label.isEmpty ? 'ALUMINIUM WASTAGE LESS' : label,
        scrapItemKeyword: keyword.isEmpty ? 'wastage' : keyword,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: SoftErpTheme.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Report Options',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Configure waste deduction and identification options.',
                      style: TextStyle(color: SoftErpTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: SoftErpTheme.border),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Scrap Rate (₹/Kg)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _scrapRateController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*'),
                        ),
                      ],
                      decoration: InputDecoration(
                        prefixText: '₹ ',
                        hintText: '170.00',
                        filled: true,
                        fillColor: SoftErpTheme.cardSurfaceAlt,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: SoftErpTheme.border,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: SoftErpTheme.border,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Scrap Label',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _scrapLabelController,
                      decoration: InputDecoration(
                        hintText: 'ALUMINIUM WASTAGE LESS',
                        filled: true,
                        fillColor: SoftErpTheme.cardSurfaceAlt,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: SoftErpTheme.border,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: SoftErpTheme.border,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Scrap Item Name Keyword',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _scrapItemKeywordController,
                      decoration: InputDecoration(
                        hintText: 'wastage',
                        filled: true,
                        fillColor: SoftErpTheme.cardSurfaceAlt,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: SoftErpTheme.border,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: SoftErpTheme.border,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: SoftErpTheme.border),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AppButton(
                      label: 'Cancel',
                      variant: AppButtonVariant.secondary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    AppButton(label: 'Continue', onPressed: _submit),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
