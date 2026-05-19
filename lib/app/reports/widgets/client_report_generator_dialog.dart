import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/soft_erp_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../features/delivery_challans/data/delivery_challan_repository.dart';
import '../../../features/delivery_challans/domain/delivery_challan.dart';
import '../../../features/delivery_challans/presentation/providers/delivery_challan_provider.dart';
import '../domain/reconciliation_report.dart';

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
  final Map<String, DeliveryChallan> _challansByNo =
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
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  DeliveryChallan? get _focusedChallan =>
      _focusedChallanId == null ? null : _challansByNo[_focusedChallanId!];

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
      if (!mounted) {
        return;
      }
      setState(() {
        _challansByNo
          ..clear()
          ..addEntries(
            fullChallans.map((challan) => MapEntry(challan.challanNo, challan)),
          );
        _selectedChallanIds.removeWhere(
          (challanNo) => !_challansByNo.containsKey(challanNo),
        );
        if (_focusedChallanId != null &&
            !_challansByNo.containsKey(_focusedChallanId)) {
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
    if (_selectedChallanIds.isEmpty) {
      return null;
    }
    setState(() => _isExporting = true);
    try {
      return await _repository.generateClientStatementReport(
        _selectedChallanIds.toList(growable: false)..sort(),
      );
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
      ]);
      for (final row in report.rows) {
        sheet.appendRow([
          xls.TextCellValue(_date(row.date)),
          xls.TextCellValue(row.challanNo),
          xls.TextCellValue(row.clientName),
          xls.TextCellValue(row.orderNo),
          xls.TextCellValue(row.itemName),
          xls.TextCellValue(row.note),
          xls.DoubleCellValue(row.quantityPcs),
          xls.DoubleCellValue(row.weight),
        ]);
      }
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
    try {
      final document = pw.Document();
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(22),
          build: (context) => [
            pw.Text(
              'Client Statement',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Generated ${_dateTime(report.generatedAt ?? DateTime.now())}',
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: const [
                'Date',
                'Challan',
                'Order',
                'Item',
                'Note',
                'Qty',
                'Weight',
              ],
              data: report.rows
                  .map(
                    (row) => [
                      _date(row.date),
                      row.challanNo,
                      row.orderNo,
                      row.itemName,
                      row.note,
                      _fmt(row.quantityPcs),
                      _fmt(row.weight),
                    ],
                  )
                  .toList(growable: false),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerLeft,
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Total Qty: ${_fmt(report.totalQuantityPcs)}    Total Weight: ${_fmt(report.totalWeight)}',
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
                      groups: _buildGroups(_challans),
                      selectedChallanIds: _selectedChallanIds,
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
                                  isExporting: _isExporting,
                                  onExport: _selectedChallanIds.isEmpty
                                      ? null
                                      : _exportXlsx,
                                  onPrint: _selectedChallanIds.isEmpty
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

  List<_ChallanGroup> _buildGroups(List<DeliveryChallan> challans) {
    final grouped = <String, _ChallanGroup>{};
    for (final challan in challans) {
      final label = _groupLabel(challan);
      final group = grouped.putIfAbsent(label, () => _ChallanGroup(label));
      group.challans.add(challan);
    }
    return grouped.values.toList(growable: false)
      ..sort((a, b) => a.label.compareTo(b.label));
  }

  String _groupLabel(DeliveryChallan challan) {
    final client = challan.customerName.trim().isEmpty
        ? 'Unlinked Client'
        : challan.customerName.trim();
    if (challan.orderNos.length > 1) {
      return '$client / Multiple Orders: ${challan.orderNos.join(', ')}';
    }
    final orderNo = challan.orderNos.isNotEmpty
        ? challan.orderNos.first
        : challan.orderNo;
    if (orderNo.trim().isNotEmpty) {
      return '$client / $orderNo';
    }
    return '$client / Direct Print / Unlinked';
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
    required this.groups,
    required this.selectedChallanIds,
    required this.focusedChallanId,
    required this.isLoading,
    required this.error,
    required this.onSearchChanged,
    required this.onRefresh,
    required this.onClose,
    required this.onToggle,
    required this.onFocus,
  });

  final TextEditingController controller;
  final List<_ChallanGroup> groups;
  final Set<String> selectedChallanIds;
  final String? focusedChallanId;
  final bool isLoading;
  final String? error;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onRefresh;
  final VoidCallback onClose;
  final void Function(String challanNo, bool selected) onToggle;
  final ValueChanged<String> onFocus;

  @override
  Widget build(BuildContext context) {
    return Column(
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
                      'Select issued delivery challans grouped by order.',
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
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
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
    if (groups.isEmpty) {
      return const _PaneMessage(
        icon: Icons.inbox_outlined,
        title: 'No issued delivery challans',
        message: 'Issue delivery challans first, then generate client reports.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: index == 0,
            tilePadding: const EdgeInsets.symmetric(horizontal: 10),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text(
              group.label,
              style: const TextStyle(fontWeight: FontWeight.w800),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${group.challans.length} challan${group.challans.length == 1 ? '' : 's'}',
              style: const TextStyle(color: SoftErpTheme.textSecondary),
            ),
            children: group.challans
                .map(
                  (challan) => _ChallanSelectionRow(
                    challan: challan,
                    selected: selectedChallanIds.contains(challan.challanNo),
                    focused: focusedChallanId == challan.challanNo,
                    onToggle: (selected) =>
                        onToggle(challan.challanNo, selected),
                    onFocus: () => onFocus(challan.challanNo),
                  ),
                )
                .toList(growable: false),
          ),
        );
      },
    );
  }
}

class _ChallanSelectionRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final quantity = challan.items.fold<double>(
      0,
      (sum, item) => sum + (double.tryParse(item.quantityPcs) ?? 0),
    );
    final weight = challan.items.fold<double>(
      0,
      (sum, item) => sum + (double.tryParse(item.weight) ?? 0),
    );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: focused
            ? SoftErpTheme.accent.withValues(alpha: 0.08)
            : SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: focused ? SoftErpTheme.accent : SoftErpTheme.border,
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            onChanged: (value) => onToggle(value == true),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onFocus,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            challan.challanNo,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _date(challan.date),
                            style: const TextStyle(
                              color: SoftErpTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Qty ${_fmt(quantity)}\nWt ${_fmt(weight)}',
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        color: SoftErpTheme.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({
    required this.challan,
    required this.selectedCount,
    required this.isExporting,
    required this.onExport,
    required this.onPrint,
  });

  final DeliveryChallan challan;
  final int selectedCount;
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
                '$selectedCount Challans Selected',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
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

class _ChallanGroup {
  _ChallanGroup(this.label);

  final String label;
  final List<DeliveryChallan> challans = <DeliveryChallan>[];
}

String _date(DateTime? value) {
  if (value == null) {
    return '-';
  }
  return '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';
}

String _dateTime(DateTime value) {
  return '${_date(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
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
