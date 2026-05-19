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
import '../../../core/widgets/page_container.dart';
import '../../../core/widgets/soft_primitives.dart';
import '../../../features/delivery_challans/presentation/providers/delivery_challan_provider.dart';
import '../../../features/delivery_challans/presentation/screens/delivery_challan_screen.dart';
import '../../reports/domain/reconciliation_report.dart';
import '../../reports/widgets/client_report_generator_dialog.dart';
import '../../shell/navigation_provider.dart';

enum _ReportTab { auditor, clientStatement, misc }

enum _AuditorSort {
  dcNumber,
  date,
  client,
  item,
  dispatchedWeight,
  convertedUnits,
  invoicedQuantity,
  unbilledQuantity,
  exposure,
  status,
}

class ChallanInvoiceReconciliationScreen extends StatefulWidget {
  const ChallanInvoiceReconciliationScreen({
    super.key,
    this.embedded = false,
    this.onClose,
  });

  final bool embedded;
  final VoidCallback? onClose;

  static Future<void> openDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 1280,
            maxHeight: MediaQuery.sizeOf(context).height - 48,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: SoftErpTheme.cardSurface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 32,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: ChallanInvoiceReconciliationScreen(
                embedded: true,
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<ChallanInvoiceReconciliationScreen> createState() =>
      _ChallanInvoiceReconciliationScreenState();
}

class _ChallanInvoiceReconciliationScreenState
    extends State<ChallanInvoiceReconciliationScreen> {
  final TextEditingController _searchController = TextEditingController();
  _ReportTab _activeTab = _ReportTab.auditor;
  ReconciliationReportSnapshot? _snapshot;
  bool _isLoading = false;
  bool _isExporting = false;
  bool _isPrinting = false;
  String? _error;
  String _clientFilter = _allFilter;
  String _statusFilter = _allFilter;
  bool _attentionOnly = false;
  bool _unbilledOnly = false;
  bool _directPrintOnly = false;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  _AuditorSort _auditorSort = _AuditorSort.dcNumber;
  bool _sortAscending = true;
  final Set<int> _selectedAuditorRows = <int>{};

  static const String _allFilter = 'All';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadReport();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  ReconciliationReportSnapshot get _report =>
      _snapshot ?? ReconciliationReportSnapshot.empty();

  @override
  Widget build(BuildContext context) {
    final auditorRows = _filteredAuditorRows();
    final clientRows = _filteredClientRows();
    final miscRows = _filteredMiscRows();
    final selectedRows = auditorRows
        .where((row) => _selectedAuditorRows.contains(row.challanItemId))
        .toList(growable: false);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReportHeader(
          activeTab: _activeTab,
          generatedAt: _report.generatedAt,
          isLoading: _isLoading,
          isExporting: _isExporting,
          isPrinting: _isPrinting,
          selectedCount: selectedRows.length,
          onBack:
              widget.onClose ??
              () => context.read<NavigationProvider>().select(
                'delivery_challans',
              ),
          onRefresh: _loadReport,
          onTabChanged: (tab) => setState(() => _activeTab = tab),
          onExport: _showExportOptions,
          onPrint: _printCurrentReport,
          onOpenClientReport: () => ClientReportGeneratorDialog.open(context),
          onBulkInvoice: selectedRows.isEmpty
              ? null
              : () => _openInvoiceDraft(selectedRows),
        ),
        const SizedBox(height: 14),
        _ReportToolbar(
          controller: _searchController,
          clients: _clientOptions,
          statuses: _statusOptions,
          selectedClient: _clientFilter,
          selectedStatus: _statusFilter,
          attentionOnly: _attentionOnly,
          unbilledOnly: _unbilledOnly,
          directPrintOnly: _directPrintOnly,
          dateFrom: _dateFrom,
          dateTo: _dateTo,
          onChanged: (_) => setState(() {}),
          onClientChanged: (value) =>
              setState(() => _clientFilter = value ?? _allFilter),
          onStatusChanged: (value) =>
              setState(() => _statusFilter = value ?? _allFilter),
          onAttentionOnlyChanged: (value) =>
              setState(() => _attentionOnly = value),
          onUnbilledOnlyChanged: (value) =>
              setState(() => _unbilledOnly = value),
          onDirectPrintOnlyChanged: (value) =>
              setState(() => _directPrintOnly = value),
          onPickDateFrom: () => _pickDate(isFrom: true),
          onPickDateTo: () => _pickDate(isFrom: false),
          onClearDates: () => setState(() {
            _dateFrom = null;
            _dateTo = null;
          }),
        ),
        const SizedBox(height: 14),
        _SummaryStrip(
          activeTab: _activeTab,
          auditorRows: auditorRows,
          clientRows: clientRows,
          miscRows: miscRows,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: SoftSurface(
            clipContent: true,
            padding: EdgeInsets.zero,
            child: _isLoading && _snapshot == null
                ? const _ReportLoadingState()
                : _error != null
                ? _ReportErrorState(message: _error!, onRetry: _loadReport)
                : _ReportBody(
                    activeTab: _activeTab,
                    auditorRows: auditorRows,
                    clientRows: clientRows,
                    miscRows: miscRows,
                    selectedAuditorRows: _selectedAuditorRows,
                    sort: _auditorSort,
                    sortAscending: _sortAscending,
                    onSort: _sortAuditorRows,
                    onToggleRow: _toggleAuditorRow,
                    onToggleAll: _toggleAllVisibleAuditorRows,
                    onGenerateInvoice: (row) => _openInvoiceDraft([row]),
                    onEditConversion: _openConversionDialog,
                    onOpenChallan: _openChallan,
                    onViewInvoices: _showLinkedInvoices,
                    onViewWasteAudit: _showWasteAuditDetails,
                  ),
          ),
        ),
      ],
    );
    if (widget.embedded) {
      return Padding(padding: const EdgeInsets.all(24), child: content);
    }
    return PageContainer(child: content);
  }

  List<String> get _clientOptions {
    final clients = <String>{};
    for (final row in _report.internalAuditor) {
      if (row.clientName.trim().isNotEmpty) {
        clients.add(row.clientName.trim());
      }
    }
    for (final row in _report.clientStatement) {
      if (row.clientName.trim().isNotEmpty) {
        clients.add(row.clientName.trim());
      }
    }
    for (final row in _report.misc) {
      if (row.clientName.trim().isNotEmpty) {
        clients.add(row.clientName.trim());
      }
    }
    return <String>[_allFilter, ...clients.toList()..sort()];
  }

  List<String> get _statusOptions {
    final statuses = <String>{};
    for (final row in _report.internalAuditor) {
      if (row.status.trim().isNotEmpty) {
        statuses.add(row.status.trim());
      }
    }
    for (final row in _report.clientStatement) {
      if (row.status.trim().isNotEmpty) {
        statuses.add(row.status.trim());
      }
    }
    return <String>[_allFilter, ...statuses.toList()..sort()];
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final snapshot = await context
          .read<DeliveryChallanProvider>()
          .repository
          .getReconciliationReport();
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _selectedAuditorRows.removeWhere(
          (id) =>
              !snapshot.internalAuditor.any((row) => row.challanItemId == id),
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<InternalAuditorRow> _filteredAuditorRows() {
    final query = _searchController.text.trim().toLowerCase();
    final rows = _report.internalAuditor
        .where((row) {
          if (!_passesCommonFilters(
            row.clientName,
            row.status,
            row.challanDate,
          )) {
            return false;
          }
          if (_attentionOnly && !row.isAttentionRequired) {
            return false;
          }
          if (_unbilledOnly && !row.isUnbilled) {
            return false;
          }
          if (_directPrintOnly && !row.isDirectPrint) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return [
            row.dcNumber,
            row.clientName,
            row.itemName,
            row.hsnCode,
            row.status,
            row.gstin,
          ].join(' ').toLowerCase().contains(query);
        })
        .toList(growable: false);
    final sorted = rows.toList();
    sorted.sort((a, b) {
      final result = switch (_auditorSort) {
        _AuditorSort.dcNumber => a.dcNumber.compareTo(b.dcNumber),
        _AuditorSort.date => _compareDate(a.challanDate, b.challanDate),
        _AuditorSort.client => a.clientName.compareTo(b.clientName),
        _AuditorSort.item => a.itemName.compareTo(b.itemName),
        _AuditorSort.dispatchedWeight => a.totalDispatchedWeightKg.compareTo(
          b.totalDispatchedWeightKg,
        ),
        _AuditorSort.convertedUnits => a.convertedUnits.compareTo(
          b.convertedUnits,
        ),
        _AuditorSort.invoicedQuantity => a.invoicedQuantity.compareTo(
          b.invoicedQuantity,
        ),
        _AuditorSort.unbilledQuantity => a.unbilledQuantity.compareTo(
          b.unbilledQuantity,
        ),
        _AuditorSort.exposure => a.financialExposure.compareTo(
          b.financialExposure,
        ),
        _AuditorSort.status => a.status.compareTo(b.status),
      };
      return _sortAscending ? result : -result;
    });
    return sorted;
  }

  List<ClientStatementRow> _filteredClientRows() {
    final query = _searchController.text.trim().toLowerCase();
    return _report.clientStatement
        .where((row) {
          if (!_passesCommonFilters(row.clientName, row.status, null)) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return [
            row.clientName,
            row.itemName,
            row.status,
          ].join(' ').toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  List<WasteAuditRow> _filteredMiscRows() {
    final query = _searchController.text.trim().toLowerCase();
    return _report.misc
        .where((row) {
          if (_clientFilter != _allFilter && row.clientName != _clientFilter) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return [
            row.clientName,
            row.itemName,
            row.challanNo,
            row.source,
          ].join(' ').toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  bool _passesCommonFilters(String clientName, String status, DateTime? date) {
    if (_clientFilter != _allFilter && clientName != _clientFilter) {
      return false;
    }
    if (_statusFilter != _allFilter && status != _statusFilter) {
      return false;
    }
    if (date != null && _dateFrom != null && date.isBefore(_dateFrom!)) {
      return false;
    }
    if (date != null &&
        _dateTo != null &&
        date.isAfter(_dateTo!.add(const Duration(days: 1)))) {
      return false;
    }
    return true;
  }

  void _sortAuditorRows(_AuditorSort sort) {
    setState(() {
      if (_auditorSort == sort) {
        _sortAscending = !_sortAscending;
      } else {
        _auditorSort = sort;
        _sortAscending = true;
      }
    });
  }

  void _toggleAuditorRow(InternalAuditorRow row, bool selected) {
    setState(() {
      if (selected) {
        _selectedAuditorRows.add(row.challanItemId);
      } else {
        _selectedAuditorRows.remove(row.challanItemId);
      }
    });
  }

  void _toggleAllVisibleAuditorRows(
    List<InternalAuditorRow> rows,
    bool selected,
  ) {
    setState(() {
      if (selected) {
        _selectedAuditorRows.addAll(
          rows.where((row) => row.isUnbilled).map((row) => row.challanItemId),
        );
      } else {
        _selectedAuditorRows.removeAll(rows.map((row) => row.challanItemId));
      }
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _dateFrom : _dateTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      if (isFrom) {
        _dateFrom = picked;
      } else {
        _dateTo = picked;
      }
    });
  }

  Future<void> _openInvoiceDraft(List<InternalAuditorRow> rows) async {
    final invoiceableRows = rows.where((row) => row.isUnbilled).toList();
    if (invoiceableRows.isEmpty) {
      _showSnack('Select at least one unbilled row.');
      return;
    }
    final clientKey =
        invoiceableRows.first.clientId?.toString() ??
        invoiceableRows.first.clientName.toLowerCase();
    final mixedClient = invoiceableRows.any((row) {
      final key = row.clientId?.toString() ?? row.clientName.toLowerCase();
      return key != clientKey;
    });
    if (mixedClient) {
      _showSnack('Bulk invoice can include one client only.');
      return;
    }
    final input = await showDialog<InvoiceDraftInput>(
      context: context,
      builder: (context) => _InvoiceDraftDialog(rows: invoiceableRows),
    );
    if (input == null || !mounted) {
      return;
    }
    setState(() => _isLoading = true);
    try {
      final invoice = await context
          .read<DeliveryChallanProvider>()
          .repository
          .createInvoice(input);
      if (!mounted) {
        return;
      }
      _showSnack('Draft invoice ${invoice.invoiceNo} created.');
      await _loadReport();
    } catch (error) {
      if (mounted) {
        _showSnack(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openConversionDialog(InternalAuditorRow row) async {
    if (row.itemId == null || row.itemId! <= 0) {
      _showSnack('Conversion can be edited only for linked item rows.');
      return;
    }
    final input = await showDialog<ConversionOverrideInput>(
      context: context,
      builder: (context) => _ConversionOverrideDialog(row: row),
    );
    if (input == null || !mounted) {
      return;
    }
    try {
      await context
          .read<DeliveryChallanProvider>()
          .repository
          .saveConversionOverride(input);
      if (!mounted) {
        return;
      }
      _showSnack('Conversion override updated.');
      await _loadReport();
    } catch (error) {
      if (mounted) {
        _showSnack(error.toString());
      }
    }
  }

  Future<void> _openChallan(int? challanId) async {
    if (challanId == null || challanId <= 0) {
      _showSnack('No source challan is linked to this row.');
      return;
    }
    final provider = context.read<DeliveryChallanProvider>();
    final challan = await provider.loadChallan(challanId);
    if (challan == null || !mounted) {
      _showSnack(provider.errorMessage ?? 'Unable to open challan.');
      return;
    }
    await ChallanScreen.openEditor(context, challan: challan);
  }

  Future<void> _showLinkedInvoices(InternalAuditorRow row) async {
    if (row.linkedInvoices.isEmpty) {
      _showSnack('No linked invoices yet.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Linked invoices for ${row.dcNumber}'),
        content: SizedBox(
          width: 460,
          child: ListView.separated(
            shrinkWrap: true,
            itemBuilder: (context, index) {
              final invoice = row.linkedInvoices[index];
              return ListTile(
                title: Text(invoice.invoiceNo),
                subtitle: Text(
                  '${invoice.status} • ${_date(invoice.invoiceDate)}',
                ),
                trailing: const Icon(Icons.receipt_long_outlined),
              );
            },
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemCount: row.linkedInvoices.length,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showWasteAuditDetails(WasteAuditRow row) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Waste Audit Detail'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailLine('Audit ID', '#${row.id}'),
              _DetailLine('Client', row.clientName),
              _DetailLine('Item', row.itemName),
              _DetailLine('Challan', row.challanNo),
              _DetailLine('Input Weight', '${_fmt(row.inputWeightKg)} kg'),
              _DetailLine('Shipped Weight', '${_fmt(row.shippedWeightKg)} kg'),
              _DetailLine('Waste Weight', '${_fmt(row.wasteWeightKg)} kg'),
              _DetailLine('Waste %', '${_fmt(row.wastePercentage)}%'),
              _DetailLine('Source', row.source),
            ],
          ),
        ),
        actions: [
          if (row.challanId != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openChallan(row.challanId);
              },
              child: const Text('Open Challan'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showExportOptions() async {
    final allTabs = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export XLSX'),
        content: const Text(
          'Export the current filtered tab or all filtered tabs?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Current Tab'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('All Tabs'),
          ),
        ],
      ),
    );
    if (allTabs == null) {
      return;
    }
    await _exportXlsx(allTabs: allTabs);
  }

  Future<void> _exportXlsx({required bool allTabs}) async {
    setState(() => _isExporting = true);
    try {
      final excel = xls.Excel.createExcel();
      if (allTabs || _activeTab == _ReportTab.auditor) {
        _appendAuditorSheet(excel, _filteredAuditorRows());
      }
      if (allTabs || _activeTab == _ReportTab.clientStatement) {
        _appendClientSheet(excel, _filteredClientRows());
      }
      if (allTabs || _activeTab == _ReportTab.misc) {
        _appendMiscSheet(excel, _filteredMiscRows());
      }
      if (excel.sheets.containsKey('Sheet1') && excel.sheets.length > 1) {
        excel.delete('Sheet1');
      }
      final bytes = excel.encode();
      if (bytes == null) {
        throw StateError('Failed to encode XLSX report.');
      }
      final fileName =
          'challan-reconciliation-${DateTime.now().millisecondsSinceEpoch}.xlsx';
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
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _printCurrentReport() async {
    setState(() => _isPrinting = true);
    try {
      final pdf = pw.Document();
      final title = switch (_activeTab) {
        _ReportTab.auditor => 'Internal Auditor Reconciliation',
        _ReportTab.clientStatement => 'Client Material Statement',
        _ReportTab.misc => 'Waste Audit',
      };
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(18),
          build: (context) => [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Generated: ${_dateTime(DateTime.now())}'),
            pw.SizedBox(height: 14),
            _buildPdfTable(),
          ],
        ),
      );
      final bytes = await pdf.save();
      await Printing.layoutPdf(
        name: 'challan-reconciliation-report.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (error) {
      if (mounted) {
        _showSnack(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isPrinting = false);
      }
    }
  }

  pw.Widget _buildPdfTable() {
    if (_activeTab == _ReportTab.clientStatement) {
      return pw.TableHelper.fromTextArray(
        headers: const [
          'Client',
          'Item',
          'Input Kg',
          'Delivered',
          'Balance Kg',
          'Status',
        ],
        data: _filteredClientRows()
            .map(
              (row) => [
                row.clientName,
                row.itemName,
                _fmt(row.materialReceivedInputKg),
                _fmt(row.totalFinishedUnitsDelivered),
                _fmt(row.netBalanceMaterialRemainingKg),
                row.status,
              ],
            )
            .toList(),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 8),
      );
    }
    if (_activeTab == _ReportTab.misc) {
      return pw.TableHelper.fromTextArray(
        headers: const [
          'Audit Time',
          'Client',
          'Item',
          'DC',
          'Input',
          'Shipped',
          'Waste',
          'Waste %',
          'Source',
        ],
        data: _filteredMiscRows()
            .map(
              (row) => [
                _date(row.auditTime),
                row.clientName,
                row.itemName,
                row.challanNo,
                _fmt(row.inputWeightKg),
                _fmt(row.shippedWeightKg),
                _fmt(row.wasteWeightKg),
                _fmt(row.wastePercentage),
                row.source,
              ],
            )
            .toList(),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 8),
      );
    }
    return pw.TableHelper.fromTextArray(
      headers: const [
        'DC',
        'Date',
        'Client',
        'Item',
        'Weight',
        'Units',
        'Invoiced',
        'Unbilled',
        'Exposure',
        'Status',
      ],
      data: _filteredAuditorRows()
          .map(
            (row) => [
              row.dcNumber,
              _date(row.challanDate),
              row.clientName,
              row.itemName,
              _fmt(row.totalDispatchedWeightKg),
              _fmt(row.convertedUnits),
              _fmt(row.invoicedQuantity),
              _fmt(row.unbilledQuantity),
              _money(row.financialExposure),
              row.status,
            ],
          )
          .toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8),
    );
  }

  void _appendAuditorSheet(xls.Excel excel, List<InternalAuditorRow> rows) {
    final sheet = excel['Internal Auditor'];
    sheet.appendRow(
      _xlsxRow([
        'DC Number',
        'Date',
        'Client',
        'Item',
        'HSN',
        'Dispatched Weight Kg',
        'Converted Units',
        'Invoiced Qty',
        'Unbilled Qty',
        'Unit Price',
        'Financial Exposure',
        'GSTIN',
        'CGST',
        'SGST',
        'Variance %',
        'Status',
      ]),
    );
    for (final row in rows) {
      sheet.appendRow(
        _xlsxRow([
          row.dcNumber,
          _date(row.challanDate),
          row.clientName,
          row.itemName,
          row.hsnCode,
          row.totalDispatchedWeightKg,
          row.convertedUnits,
          row.invoicedQuantity,
          row.unbilledQuantity,
          row.unitPrice,
          row.financialExposure,
          row.gstin,
          row.cgst,
          row.sgst,
          row.variancePercent,
          row.status,
        ]),
      );
    }
  }

  void _appendClientSheet(xls.Excel excel, List<ClientStatementRow> rows) {
    final sheet = excel['Client Statement'];
    sheet.appendRow(
      _xlsxRow([
        'Client',
        'Item',
        'Material Received Input Kg',
        'Finished Units Delivered',
        'Net Balance Material Kg',
        'Status',
      ]),
    );
    for (final row in rows) {
      sheet.appendRow(
        _xlsxRow([
          row.clientName,
          row.itemName,
          row.materialReceivedInputKg,
          row.totalFinishedUnitsDelivered,
          row.netBalanceMaterialRemainingKg,
          row.status,
        ]),
      );
    }
  }

  void _appendMiscSheet(xls.Excel excel, List<WasteAuditRow> rows) {
    final sheet = excel['Waste Audit'];
    sheet.appendRow(
      _xlsxRow([
        'Audit ID',
        'Audit Time',
        'Client',
        'Item',
        'DC Number',
        'Input Weight Kg',
        'Shipped Weight Kg',
        'Waste Weight Kg',
        'Waste %',
        'Source',
      ]),
    );
    for (final row in rows) {
      sheet.appendRow(
        _xlsxRow([
          row.id,
          _dateTime(row.auditTime),
          row.clientName,
          row.itemName,
          row.challanNo,
          row.inputWeightKg,
          row.shippedWeightKg,
          row.wasteWeightKg,
          row.wastePercentage,
          row.source,
        ]),
      );
    }
  }

  List<xls.CellValue?> _xlsxRow(List<Object?> values) {
    return values
        .map((value) {
          if (value is int) {
            return xls.IntCellValue(value);
          }
          if (value is num) {
            return xls.DoubleCellValue(value.toDouble());
          }
          return xls.TextCellValue(value?.toString() ?? '');
        })
        .toList(growable: false);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({
    required this.activeTab,
    required this.generatedAt,
    required this.isLoading,
    required this.isExporting,
    required this.isPrinting,
    required this.selectedCount,
    required this.onBack,
    required this.onRefresh,
    required this.onTabChanged,
    required this.onExport,
    required this.onPrint,
    required this.onOpenClientReport,
    required this.onBulkInvoice,
  });

  final _ReportTab activeTab;
  final DateTime? generatedAt;
  final bool isLoading;
  final bool isExporting;
  final bool isPrinting;
  final int selectedCount;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final ValueChanged<_ReportTab> onTabChanged;
  final VoidCallback onExport;
  final VoidCallback onPrint;
  final VoidCallback onOpenClientReport;
  final VoidCallback? onBulkInvoice;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          tooltip: 'Back to Challans',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Report',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (selectedCount > 0)
                    AppButton(
                      label: 'Bulk Invoice ($selectedCount)',
                      icon: Icons.receipt_long_outlined,
                      onPressed: onBulkInvoice,
                    ),
                  AppButton(
                    label: 'Client Report',
                    icon: Icons.assignment_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: onOpenClientReport,
                  ),
                  AppButton(
                    label: isExporting ? 'Exporting...' : 'Export XLSX',
                    icon: Icons.table_view_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: isExporting ? null : onExport,
                  ),
                  AppButton(
                    label: isPrinting ? 'Printing...' : 'Print',
                    icon: Icons.print_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: isPrinting ? null : onPrint,
                  ),
                  AppButton(
                    label: isLoading ? 'Refreshing...' : 'Refresh',
                    icon: Icons.refresh_rounded,
                    variant: AppButtonVariant.secondary,
                    onPressed: isLoading ? null : onRefresh,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Reconcile challan dispatch, invoices, material balance, and waste audit.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SoftErpTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                generatedAt == null
                    ? 'No snapshot loaded yet.'
                    : 'Snapshot generated ${_dateTime(generatedAt)}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: SoftErpTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              _TabToggle(activeTab: activeTab, onChanged: onTabChanged),
            ],
          ),
        ),
      ],
    );
  }
}

class _TabToggle extends StatelessWidget {
  const _TabToggle({required this.activeTab, required this.onChanged});

  final _ReportTab activeTab;
  final ValueChanged<_ReportTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TabPill(
            label: 'Internal Auditor',
            selected: activeTab == _ReportTab.auditor,
            onTap: () => onChanged(_ReportTab.auditor),
          ),
          _TabPill(
            label: 'Client Statement',
            selected: activeTab == _ReportTab.clientStatement,
            onTap: () => onChanged(_ReportTab.clientStatement),
          ),
          _TabPill(
            label: 'Misc',
            selected: activeTab == _ReportTab.misc,
            onTap: () => onChanged(_ReportTab.misc),
          ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? SoftErpTheme.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: SoftErpTheme.accent.withValues(alpha: 0.22),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? Colors.white : SoftErpTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportToolbar extends StatelessWidget {
  const _ReportToolbar({
    required this.controller,
    required this.clients,
    required this.statuses,
    required this.selectedClient,
    required this.selectedStatus,
    required this.attentionOnly,
    required this.unbilledOnly,
    required this.directPrintOnly,
    required this.dateFrom,
    required this.dateTo,
    required this.onChanged,
    required this.onClientChanged,
    required this.onStatusChanged,
    required this.onAttentionOnlyChanged,
    required this.onUnbilledOnlyChanged,
    required this.onDirectPrintOnlyChanged,
    required this.onPickDateFrom,
    required this.onPickDateTo,
    required this.onClearDates,
  });

  final TextEditingController controller;
  final List<String> clients;
  final List<String> statuses;
  final String selectedClient;
  final String selectedStatus;
  final bool attentionOnly;
  final bool unbilledOnly;
  final bool directPrintOnly;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final ValueChanged<String> onChanged;
  final ValueChanged<String?> onClientChanged;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<bool> onAttentionOnlyChanged;
  final ValueChanged<bool> onUnbilledOnlyChanged;
  final ValueChanged<bool> onDirectPrintOnlyChanged;
  final VoidCallback onPickDateFrom;
  final VoidCallback onPickDateTo;
  final VoidCallback onClearDates;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      padding: const EdgeInsets.all(14),
      color: Colors.white.withValues(alpha: 0.72),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 360,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Search client, challan, item, status...',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: SoftErpTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: SoftErpTheme.border),
                ),
              ),
            ),
          ),
          _FilterDropdown(
            label: 'Client',
            value: clients.contains(selectedClient) ? selectedClient : 'All',
            values: clients,
            onChanged: onClientChanged,
          ),
          _FilterDropdown(
            label: 'Status',
            value: statuses.contains(selectedStatus) ? selectedStatus : 'All',
            values: statuses,
            onChanged: onStatusChanged,
          ),
          _FilterChip(
            label: 'Attention',
            selected: attentionOnly,
            onSelected: onAttentionOnlyChanged,
          ),
          _FilterChip(
            label: 'Unbilled',
            selected: unbilledOnly,
            onSelected: onUnbilledOnlyChanged,
          ),
          _FilterChip(
            label: 'Direct Print',
            selected: directPrintOnly,
            onSelected: onDirectPrintOnlyChanged,
          ),
          OutlinedButton.icon(
            onPressed: onPickDateFrom,
            icon: const Icon(Icons.event_outlined),
            label: Text(dateFrom == null ? 'From' : _date(dateFrom)),
          ),
          OutlinedButton.icon(
            onPressed: onPickDateTo,
            icon: const Icon(Icons.event_available_outlined),
            label: Text(dateTo == null ? 'To' : _date(dateTo)),
          ),
          if (dateFrom != null || dateTo != null)
            TextButton(
              onPressed: onClearDates,
              child: const Text('Clear Dates'),
            ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        ),
        items: values
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(growable: false),
        onChanged: onChanged,
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      selectedColor: SoftErpTheme.accent.withValues(alpha: 0.14),
      checkmarkColor: SoftErpTheme.accent,
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.activeTab,
    required this.auditorRows,
    required this.clientRows,
    required this.miscRows,
  });

  final _ReportTab activeTab;
  final List<InternalAuditorRow> auditorRows;
  final List<ClientStatementRow> clientRows;
  final List<WasteAuditRow> miscRows;

  @override
  Widget build(BuildContext context) {
    if (activeTab == _ReportTab.clientStatement) {
      return Row(
        children: [
          Expanded(
            child: _MetricCard(
              title: 'Material Input',
              value:
                  '${_fmt(clientRows.fold<double>(0, (s, r) => s + r.materialReceivedInputKg))} kg',
              icon: Icons.inventory_2_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _MetricCard(
              title: 'Finished Delivered',
              value: _fmt(
                clientRows.fold<double>(
                  0,
                  (s, r) => s + r.totalFinishedUnitsDelivered,
                ),
              ),
              icon: Icons.local_shipping_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _MetricCard(
              title: 'Material Balance',
              value:
                  '${_fmt(clientRows.fold<double>(0, (s, r) => s + r.netBalanceMaterialRemainingKg))} kg',
              icon: Icons.account_tree_outlined,
            ),
          ),
        ],
      );
    }
    if (activeTab == _ReportTab.misc) {
      final waste = miscRows.fold<double>(
        0,
        (sum, row) => sum + row.wasteWeightKg,
      );
      final double avgWaste = miscRows.isEmpty
          ? 0
          : miscRows.fold<double>(0, (sum, row) => sum + row.wastePercentage) /
                miscRows.length;
      return Row(
        children: [
          Expanded(
            child: _MetricCard(
              title: 'Waste Audit Rows',
              value: '${miscRows.length}',
              icon: Icons.fact_check_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _MetricCard(
              title: 'Waste Weight',
              value: '${_fmt(waste)} kg',
              icon: Icons.scale_outlined,
              color: SoftErpTheme.warningBg,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _MetricCard(
              title: 'Average Waste',
              value: '${_fmt(avgWaste)}%',
              icon: Icons.percent_rounded,
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            title: 'Dispatched Weight',
            value:
                '${_fmt(auditorRows.fold<double>(0, (s, r) => s + r.totalDispatchedWeightKg))} kg',
            icon: Icons.monitor_weight_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(
            title: 'Unbilled / In-Transit',
            value: _fmt(
              auditorRows.fold<double>(0, (s, r) => s + r.unbilledQuantity),
            ),
            icon: Icons.receipt_long_outlined,
            color: SoftErpTheme.warningBg,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(
            title: 'Financial Exposure',
            value: _money(
              auditorRows.fold<double>(0, (s, r) => s + r.financialExposure),
            ),
            icon: Icons.currency_rupee_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(
            title: 'Attention Required',
            value:
                '${auditorRows.where((row) => row.isAttentionRequired).length}',
            icon: Icons.report_problem_outlined,
            color: SoftErpTheme.dangerBg,
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      padding: const EdgeInsets.all(18),
      color: color ?? Colors.white.withValues(alpha: 0.78),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: SoftErpTheme.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: SoftErpTheme.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.activeTab,
    required this.auditorRows,
    required this.clientRows,
    required this.miscRows,
    required this.selectedAuditorRows,
    required this.sort,
    required this.sortAscending,
    required this.onSort,
    required this.onToggleRow,
    required this.onToggleAll,
    required this.onGenerateInvoice,
    required this.onEditConversion,
    required this.onOpenChallan,
    required this.onViewInvoices,
    required this.onViewWasteAudit,
  });

  final _ReportTab activeTab;
  final List<InternalAuditorRow> auditorRows;
  final List<ClientStatementRow> clientRows;
  final List<WasteAuditRow> miscRows;
  final Set<int> selectedAuditorRows;
  final _AuditorSort sort;
  final bool sortAscending;
  final ValueChanged<_AuditorSort> onSort;
  final void Function(InternalAuditorRow row, bool selected) onToggleRow;
  final void Function(List<InternalAuditorRow> rows, bool selected) onToggleAll;
  final ValueChanged<InternalAuditorRow> onGenerateInvoice;
  final ValueChanged<InternalAuditorRow> onEditConversion;
  final ValueChanged<int?> onOpenChallan;
  final ValueChanged<InternalAuditorRow> onViewInvoices;
  final ValueChanged<WasteAuditRow> onViewWasteAudit;

  @override
  Widget build(BuildContext context) {
    if (activeTab == _ReportTab.clientStatement) {
      return clientRows.isEmpty
          ? const _EmptyReportState(message: 'No client material balances yet.')
          : _ClientStatementTable(rows: clientRows);
    }
    if (activeTab == _ReportTab.misc) {
      return miscRows.isEmpty
          ? const _EmptyReportState(message: 'No waste audit snapshots yet.')
          : _MiscTable(
              rows: miscRows,
              onOpenChallan: onOpenChallan,
              onViewWasteAudit: onViewWasteAudit,
            );
    }
    return auditorRows.isEmpty
        ? const _EmptyReportState(message: 'No issued delivery challans yet.')
        : _AuditorTable(
            rows: auditorRows,
            selectedRows: selectedAuditorRows,
            sort: sort,
            sortAscending: sortAscending,
            onSort: onSort,
            onToggleRow: onToggleRow,
            onToggleAll: onToggleAll,
            onGenerateInvoice: onGenerateInvoice,
            onEditConversion: onEditConversion,
            onOpenChallan: onOpenChallan,
            onViewInvoices: onViewInvoices,
          );
  }
}

class _AuditorTable extends StatelessWidget {
  const _AuditorTable({
    required this.rows,
    required this.selectedRows,
    required this.sort,
    required this.sortAscending,
    required this.onSort,
    required this.onToggleRow,
    required this.onToggleAll,
    required this.onGenerateInvoice,
    required this.onEditConversion,
    required this.onOpenChallan,
    required this.onViewInvoices,
  });

  final List<InternalAuditorRow> rows;
  final Set<int> selectedRows;
  final _AuditorSort sort;
  final bool sortAscending;
  final ValueChanged<_AuditorSort> onSort;
  final void Function(InternalAuditorRow row, bool selected) onToggleRow;
  final void Function(List<InternalAuditorRow> rows, bool selected) onToggleAll;
  final ValueChanged<InternalAuditorRow> onGenerateInvoice;
  final ValueChanged<InternalAuditorRow> onEditConversion;
  final ValueChanged<int?> onOpenChallan;
  final ValueChanged<InternalAuditorRow> onViewInvoices;

  @override
  Widget build(BuildContext context) {
    final selectableRows = rows.where((row) => row.isUnbilled).toList();
    final allSelected =
        selectableRows.isNotEmpty &&
        selectableRows.every((row) => selectedRows.contains(row.challanItemId));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      primary: false,
      child: SingleChildScrollView(
        primary: false,
        child: DataTable(
          sortAscending: sortAscending,
          sortColumnIndex: _sortColumnIndex(sort),
          dataRowMinHeight: 92,
          dataRowMaxHeight: 132,
          headingRowColor: WidgetStateProperty.all(SoftErpTheme.cardSurfaceAlt),
          columns: [
            DataColumn(
              label: Checkbox(
                value: allSelected,
                onChanged: selectableRows.isEmpty
                    ? null
                    : (value) => onToggleAll(rows, value == true),
              ),
            ),
            _sortableColumn('DC Number', _AuditorSort.dcNumber),
            _sortableColumn('Date', _AuditorSort.date),
            _sortableColumn('Client / Item', _AuditorSort.client),
            _sortableColumn('Weight', _AuditorSort.dispatchedWeight),
            _sortableColumn('Units', _AuditorSort.convertedUnits),
            _sortableColumn('Invoiced', _AuditorSort.invoicedQuantity),
            _sortableColumn('Unbilled', _AuditorSort.unbilledQuantity),
            _sortableColumn('Exposure', _AuditorSort.exposure),
            const DataColumn(label: Text('Variance')),
            _sortableColumn('Status', _AuditorSort.status),
            const DataColumn(label: Text('Actions')),
          ],
          rows: rows
              .map((row) {
                final selected = selectedRows.contains(row.challanItemId);
                return DataRow(
                  selected: selected,
                  color: WidgetStateProperty.resolveWith((states) {
                    if (row.isAttentionRequired || row.isDirectPrint) {
                      return SoftErpTheme.dangerBg.withValues(alpha: 0.55);
                    }
                    if (row.isUnbilled) {
                      return SoftErpTheme.warningBg.withValues(alpha: 0.55);
                    }
                    return null;
                  }),
                  cells: [
                    DataCell(
                      Checkbox(
                        value: selected,
                        onChanged: row.isUnbilled
                            ? (value) => onToggleRow(row, value == true)
                            : null,
                      ),
                    ),
                    DataCell(_DcCell(row: row)),
                    DataCell(Text(_date(row.challanDate))),
                    DataCell(_ClientItemCell(row: row)),
                    DataCell(Text('${_fmt(row.totalDispatchedWeightKg)} kg')),
                    DataCell(
                      Text('${_fmt(row.convertedUnits)} ${row.toUnitLabel}'),
                    ),
                    DataCell(Text(_fmt(row.invoicedQuantity))),
                    DataCell(Text(_fmt(row.unbilledQuantity))),
                    DataCell(Text(_money(row.financialExposure))),
                    DataCell(Text('${_fmt(row.variancePercent)}%')),
                    DataCell(_StatusBadge(row.status)),
                    DataCell(
                      _AuditorActions(
                        row: row,
                        onGenerateInvoice: onGenerateInvoice,
                        onEditConversion: onEditConversion,
                        onOpenChallan: onOpenChallan,
                        onViewInvoices: onViewInvoices,
                      ),
                    ),
                  ],
                );
              })
              .toList(growable: false),
        ),
      ),
    );
  }

  DataColumn _sortableColumn(String label, _AuditorSort sortKey) {
    return DataColumn(label: Text(label), onSort: (_, _) => onSort(sortKey));
  }
}

class _ClientItemCell extends StatelessWidget {
  const _ClientItemCell({required this.row});

  final InternalAuditorRow row;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            row.clientName,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(row.itemName, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(
            'HSN ${row.hsnCode.isEmpty ? '-' : row.hsnCode} • 1 kg = ${_fmt(row.conversionRatio)} ${row.toUnitLabel}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: SoftErpTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _DcCell extends StatelessWidget {
  const _DcCell({required this.row});

  final InternalAuditorRow row;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            row.dcNumber,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (row.isDirectPrint) ...[
            const SizedBox(height: 4),
            const _WarningBadge('Direct Print / Unlinked'),
          ],
          if (row.unlinkedReason.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              row.unlinkedReason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: SoftErpTheme.dangerText),
            ),
          ],
        ],
      ),
    );
  }
}

class _AuditorActions extends StatelessWidget {
  const _AuditorActions({
    required this.row,
    required this.onGenerateInvoice,
    required this.onEditConversion,
    required this.onOpenChallan,
    required this.onViewInvoices,
  });

  final InternalAuditorRow row;
  final ValueChanged<InternalAuditorRow> onGenerateInvoice;
  final ValueChanged<InternalAuditorRow> onEditConversion;
  final ValueChanged<int?> onOpenChallan;
  final ValueChanged<InternalAuditorRow> onViewInvoices;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (row.isUnbilled)
            TextButton(
              onPressed: () => onGenerateInvoice(row),
              child: const Text('Open Draft Invoice'),
            ),
          TextButton(
            onPressed: row.itemId == null ? null : () => onEditConversion(row),
            child: const Text('Edit Conversion'),
          ),
          TextButton(
            onPressed: () => onOpenChallan(row.challanId),
            child: const Text('Open Challan'),
          ),
          TextButton(
            onPressed: row.linkedInvoices.isEmpty
                ? null
                : () => onViewInvoices(row),
            child: const Text('View Invoices'),
          ),
        ],
      ),
    );
  }
}

class _ClientStatementTable extends StatelessWidget {
  const _ClientStatementTable({required this.rows});

  final List<ClientStatementRow> rows;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      primary: false,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(SoftErpTheme.cardSurfaceAlt),
        columns: const [
          DataColumn(label: Text('Client')),
          DataColumn(label: Text('Item')),
          DataColumn(label: Text('Material Received (Input)')),
          DataColumn(label: Text('Finished Units Delivered')),
          DataColumn(label: Text('Net Balance Material')),
          DataColumn(label: Text('Status')),
        ],
        rows: rows
            .map((row) {
              return DataRow(
                color: WidgetStateProperty.resolveWith((states) {
                  if (row.status.toLowerCase().contains('over')) {
                    return SoftErpTheme.dangerBg.withValues(alpha: 0.55);
                  }
                  if (row.status.toLowerCase().contains('remaining')) {
                    return SoftErpTheme.warningBg.withValues(alpha: 0.5);
                  }
                  return null;
                }),
                cells: [
                  DataCell(Text(row.clientName)),
                  DataCell(Text(row.itemName)),
                  DataCell(Text('${_fmt(row.materialReceivedInputKg)} kg')),
                  DataCell(Text(_fmt(row.totalFinishedUnitsDelivered))),
                  DataCell(
                    Text('${_fmt(row.netBalanceMaterialRemainingKg)} kg'),
                  ),
                  DataCell(_StatusBadge(row.status)),
                ],
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _MiscTable extends StatelessWidget {
  const _MiscTable({
    required this.rows,
    required this.onOpenChallan,
    required this.onViewWasteAudit,
  });

  final List<WasteAuditRow> rows;
  final ValueChanged<int?> onOpenChallan;
  final ValueChanged<WasteAuditRow> onViewWasteAudit;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      primary: false,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(SoftErpTheme.cardSurfaceAlt),
        columns: const [
          DataColumn(label: Text('Audit ID')),
          DataColumn(label: Text('Audit Time')),
          DataColumn(label: Text('Client')),
          DataColumn(label: Text('Item')),
          DataColumn(label: Text('DC Number')),
          DataColumn(label: Text('Input Weight')),
          DataColumn(label: Text('Shipped Weight')),
          DataColumn(label: Text('Waste Weight')),
          DataColumn(label: Text('Waste %')),
          DataColumn(label: Text('Source')),
          DataColumn(label: Text('Actions')),
        ],
        rows: rows
            .map((row) {
              return DataRow(
                cells: [
                  DataCell(Text('#${row.id}')),
                  DataCell(Text(_dateTime(row.auditTime))),
                  DataCell(Text(row.clientName)),
                  DataCell(Text(row.itemName)),
                  DataCell(Text(row.challanNo)),
                  DataCell(Text('${_fmt(row.inputWeightKg)} kg')),
                  DataCell(Text('${_fmt(row.shippedWeightKg)} kg')),
                  DataCell(Text('${_fmt(row.wasteWeightKg)} kg')),
                  DataCell(Text('${_fmt(row.wastePercentage)}%')),
                  DataCell(Text(row.source)),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => onViewWasteAudit(row),
                          child: const Text('Details'),
                        ),
                        TextButton(
                          onPressed: row.challanId == null
                              ? null
                              : () => onOpenChallan(row.challanId),
                          child: const Text('Open Challan'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _InvoiceDraftDialog extends StatefulWidget {
  const _InvoiceDraftDialog({required this.rows});

  final List<InternalAuditorRow> rows;

  @override
  State<_InvoiceDraftDialog> createState() => _InvoiceDraftDialogState();
}

class _InvoiceDraftDialogState extends State<_InvoiceDraftDialog> {
  final TextEditingController _invoiceNoController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  late final List<_InvoiceLineControllers> _lineControllers;
  late DateTime _invoiceDate;

  @override
  void initState() {
    super.initState();
    _invoiceDate = DateTime.now();
    _dateController.text = _date(_invoiceDate);
    _lineControllers = widget.rows
        .map(
          (row) => _InvoiceLineControllers(
            row: row,
            quantity: row.unbilledQuantity,
            unitPrice: row.unitPrice,
            cgstRate: row.cgstRate,
            sgstRate: row.sgstRate,
          ),
        )
        .toList(growable: false);
  }

  @override
  void dispose() {
    _invoiceNoController.dispose();
    _dateController.dispose();
    for (final controller in _lineControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.rows.first;
    final totals = _totals();
    return AlertDialog(
      title: const Text('Draft Invoice'),
      content: SizedBox(
        width: 980,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _invoiceNoController,
                      decoration: const InputDecoration(
                        labelText: 'Invoice No',
                        helperText: 'Blank auto-generates',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: TextField(
                      controller: _dateController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Invoice Date',
                      ),
                      onTap: _pickDate,
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: _ReadOnlyField(
                      label: 'Client',
                      value: row.clientName,
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: _ReadOnlyField(
                      label: 'GSTIN',
                      value: row.gstin.isEmpty ? '-' : row.gstin,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              DataTable(
                headingRowColor: WidgetStateProperty.all(
                  SoftErpTheme.cardSurfaceAlt,
                ),
                columns: const [
                  DataColumn(label: Text('Source')),
                  DataColumn(label: Text('Item')),
                  DataColumn(label: Text('Qty')),
                  DataColumn(label: Text('Unit Price')),
                  DataColumn(label: Text('CGST %')),
                  DataColumn(label: Text('SGST %')),
                  DataColumn(label: Text('Total')),
                ],
                rows: _lineControllers
                    .map((controller) {
                      final lineTotal =
                          controller.taxableValue +
                          controller.cgstAmount +
                          controller.sgstAmount;
                      return DataRow(
                        cells: [
                          DataCell(Text(controller.row.dcNumber)),
                          DataCell(
                            SizedBox(
                              width: 220,
                              child: Text(
                                controller.row.itemName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            _NumberCell(
                              controller.quantityController,
                              onChanged: _recalc,
                            ),
                          ),
                          DataCell(
                            _NumberCell(
                              controller.unitPriceController,
                              onChanged: _recalc,
                            ),
                          ),
                          DataCell(
                            _NumberCell(
                              controller.cgstController,
                              onChanged: _recalc,
                            ),
                          ),
                          DataCell(
                            _NumberCell(
                              controller.sgstController,
                              onChanged: _recalc,
                            ),
                          ),
                          DataCell(Text(_money(lineTotal))),
                        ],
                      );
                    })
                    .toList(growable: false),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Taxable ${_money(totals.taxable)}  •  CGST ${_money(totals.cgst)}  •  SGST ${_money(totals.sgst)}  •  Total ${_money(totals.total)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Create Draft Invoice'),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _invoiceDate = picked;
      _dateController.text = _date(picked);
    });
  }

  void _recalc() => setState(() {});

  void _submit() {
    final lines = <InvoiceDraftLineInput>[];
    for (final controller in _lineControllers) {
      final quantity = controller.quantity;
      if (quantity <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice quantity must be positive.')),
        );
        return;
      }
      lines.add(
        InvoiceDraftLineInput(
          orderId: controller.row.orderId,
          challanId: controller.row.challanId,
          challanItemId: controller.row.challanItemId,
          itemId: controller.row.itemId,
          variationLeafNodeId: controller.row.variationLeafNodeId,
          itemName: controller.row.itemName,
          hsnCode: controller.row.hsnCode,
          quantity: quantity,
          unitPrice: controller.unitPrice,
          cgstRate: controller.cgstRate,
          sgstRate: controller.sgstRate,
        ),
      );
    }
    final row = widget.rows.first;
    Navigator.of(context).pop(
      InvoiceDraftInput(
        invoiceNo: _invoiceNoController.text,
        clientId: row.clientId,
        clientName: row.clientName,
        gstin: row.gstin,
        invoiceDate: _invoiceDate,
        lines: lines,
      ),
    );
  }

  _InvoiceTotals _totals() {
    final taxable = _lineControllers.fold<double>(
      0,
      (sum, line) => sum + line.taxableValue,
    );
    final cgst = _lineControllers.fold<double>(
      0,
      (sum, line) => sum + line.cgstAmount,
    );
    final sgst = _lineControllers.fold<double>(
      0,
      (sum, line) => sum + line.sgstAmount,
    );
    return _InvoiceTotals(taxable: taxable, cgst: cgst, sgst: sgst);
  }
}

class _InvoiceLineControllers {
  _InvoiceLineControllers({
    required this.row,
    required double quantity,
    required double unitPrice,
    required double cgstRate,
    required double sgstRate,
  }) : quantityController = TextEditingController(text: _fmt(quantity)),
       unitPriceController = TextEditingController(text: _fmt(unitPrice)),
       cgstController = TextEditingController(text: _fmt(cgstRate)),
       sgstController = TextEditingController(text: _fmt(sgstRate));

  final InternalAuditorRow row;
  final TextEditingController quantityController;
  final TextEditingController unitPriceController;
  final TextEditingController cgstController;
  final TextEditingController sgstController;

  double get quantity => _parseNumber(quantityController.text);
  double get unitPrice => _parseNumber(unitPriceController.text);
  double get cgstRate => _parseNumber(cgstController.text);
  double get sgstRate => _parseNumber(sgstController.text);
  double get taxableValue => quantity * unitPrice;
  double get cgstAmount => taxableValue * cgstRate / 100;
  double get sgstAmount => taxableValue * sgstRate / 100;

  void dispose() {
    quantityController.dispose();
    unitPriceController.dispose();
    cgstController.dispose();
    sgstController.dispose();
  }
}

class _InvoiceTotals {
  const _InvoiceTotals({
    required this.taxable,
    required this.cgst,
    required this.sgst,
  });

  final double taxable;
  final double cgst;
  final double sgst;
  double get total => taxable + cgst + sgst;
}

class _ConversionOverrideDialog extends StatefulWidget {
  const _ConversionOverrideDialog({required this.row});

  final InternalAuditorRow row;

  @override
  State<_ConversionOverrideDialog> createState() =>
      _ConversionOverrideDialogState();
}

class _ConversionOverrideDialogState extends State<_ConversionOverrideDialog> {
  late final TextEditingController _ratioController;
  late final TextEditingController _unitController;

  @override
  void initState() {
    super.initState();
    _ratioController = TextEditingController(
      text: _fmt(widget.row.conversionRatio),
    );
    _unitController = TextEditingController(text: widget.row.toUnitLabel);
  }

  @override
  void dispose() {
    _ratioController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Conversion'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailLine('Item', widget.row.itemName),
            _DetailLine('Variation Leaf', '${widget.row.variationLeafNodeId}'),
            const SizedBox(height: 14),
            TextField(
              controller: _ratioController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Conversion Ratio',
                prefixText: '1 kg = ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unitController,
              decoration: const InputDecoration(labelText: 'To Unit Label'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final ratio = _parseNumber(_ratioController.text);
            if (ratio <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Conversion ratio must be positive.'),
                ),
              );
              return;
            }
            Navigator.of(context).pop(
              ConversionOverrideInput(
                itemId: widget.row.itemId!,
                variationLeafNodeId: widget.row.variationLeafNodeId,
                conversionRatio: ratio,
                toUnitLabel: _unitController.text,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Text(value, overflow: TextOverflow.ellipsis),
    );
  }
}

class _NumberCell extends StatelessWidget {
  const _NumberCell(this.controller, {required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => onChanged(),
        decoration: const InputDecoration(isDense: true),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final lower = label.toLowerCase();
    final isAttention = lower.contains('attention') || lower.contains('over');
    final isGood = lower.contains('auto') || lower.contains('balanced');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isAttention
            ? SoftErpTheme.dangerBg
            : isGood
            ? SoftErpTheme.successBg
            : SoftErpTheme.warningBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: isAttention
              ? SoftErpTheme.dangerText
              : isGood
              ? SoftErpTheme.successText
              : SoftErpTheme.warningText,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _WarningBadge extends StatelessWidget {
  const _WarningBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: SoftErpTheme.dangerBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: SoftErpTheme.dangerText,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ReportLoadingState extends StatelessWidget {
  const _ReportLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _ReportErrorState extends StatelessWidget {
  const _ReportErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 42),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          AppButton(
            label: 'Retry',
            variant: AppButtonVariant.secondary,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _EmptyReportState extends StatelessWidget {
  const _EmptyReportState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: SoftErpTheme.textSecondary),
      ),
    );
  }
}

int _compareDate(DateTime? a, DateTime? b) {
  if (a == null && b == null) {
    return 0;
  }
  if (a == null) {
    return -1;
  }
  if (b == null) {
    return 1;
  }
  return a.compareTo(b);
}

int _sortColumnIndex(_AuditorSort sort) {
  return switch (sort) {
    _AuditorSort.dcNumber => 1,
    _AuditorSort.date => 2,
    _AuditorSort.client => 3,
    _AuditorSort.item => 3,
    _AuditorSort.dispatchedWeight => 4,
    _AuditorSort.convertedUnits => 5,
    _AuditorSort.invoicedQuantity => 6,
    _AuditorSort.unbilledQuantity => 7,
    _AuditorSort.exposure => 8,
    _AuditorSort.status => 10,
  };
}

double _parseNumber(String value) => double.tryParse(value.trim()) ?? 0;

String _fmt(double value) {
  if (value.abs() >= 100) {
    return value.toStringAsFixed(0);
  }
  if (value.abs() >= 10) {
    return value.toStringAsFixed(1);
  }
  return value.toStringAsFixed(2);
}

String _money(double value) => '₹${value.toStringAsFixed(2)}';

String _date(DateTime? value) {
  if (value == null) {
    return '-';
  }
  return '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';
}

String _dateTime(DateTime? value) {
  if (value == null) {
    return '-';
  }
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${_date(value)} $hour:$minute';
}
