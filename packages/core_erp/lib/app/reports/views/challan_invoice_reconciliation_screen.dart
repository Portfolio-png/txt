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
import '../../../features/delivery_challans/domain/challan_template.dart';
import '../../../features/delivery_challans/domain/delivery_challan.dart';
import '../../../features/delivery_challans/presentation/providers/delivery_challan_provider.dart';
import '../../../features/items/domain/item_definition.dart';
import '../../../features/items/presentation/providers/items_provider.dart';
import '../../../core/navigation/app_navigation.dart';
import '../../reports/domain/reconciliation_report.dart';

enum ReconciliationReportSection { auditor, clientStatement, misc }

enum _SidePaneMode { hidden, draftInvoice, challanPreview, invoices }

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
    this.initialSection = ReconciliationReportSection.auditor,
    this.showSectionToggle = false,
    this.title = 'Report',
    this.subtitle =
        'Reconcile challan dispatch, invoices, material balance, and waste audit.',
  });

  final bool embedded;
  final VoidCallback? onClose;
  final ReconciliationReportSection initialSection;
  final bool showSectionToggle;
  final String title;
  final String subtitle;

  static Future<void> openDialog(BuildContext context) {
    return _openSectionDialog(context);
  }

  static Future<void> openClientStatementDialog(BuildContext context) {
    return _openSectionDialog(
      context,
      initialSection: ReconciliationReportSection.clientStatement,
      title: 'Client Statement',
      subtitle:
          'Track client-owned material input, finished delivery, and remaining material balance.',
    );
  }

  static Future<void> openMiscDialog(BuildContext context) {
    return _openSectionDialog(
      context,
      initialSection: ReconciliationReportSection.misc,
      title: 'Misc Audit',
      subtitle:
          'Review internal waste snapshots and source challan audit references.',
    );
  }

  static Future<void> _openSectionDialog(
    BuildContext context, {
    ReconciliationReportSection initialSection =
        ReconciliationReportSection.auditor,
    String title = 'Report',
    String subtitle =
        'Reconcile challan dispatch, invoices, material balance, and waste audit.',
  }) {
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
                initialSection: initialSection,
                title: title,
                subtitle: subtitle,
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
  late ReconciliationReportSection _activeTab;
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

  _SidePaneMode _sidePaneMode = _SidePaneMode.hidden;
  int? _previewChallanId;
  List<InternalAuditorRow> _draftInvoiceRows = [];
  InternalAuditorRow? _invoicePreviewRow;

  static const String _allFilter = 'All';

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialSection;
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
          title: widget.title,
          subtitle: widget.subtitle,
          activeTab: _activeTab,
          showSectionToggle: widget.showSectionToggle,
          generatedAt: _report.generatedAt,
          isLoading: _isLoading,
          isExporting: _isExporting,
          isPrinting: _isPrinting,
          selectedCount: selectedRows.length,
          onBack:
              widget.onClose ??
              () => context.read<AppNavigation>().select(
                'delivery_challans',
              ),
          onRefresh: _loadReport,
          onTabChanged: (tab) => setState(() => _activeTab = tab),
          onExport: _showExportOptions,
          onPrint: _printCurrentReport,
          onBulkInvoice: selectedRows.isEmpty
              ? null
              : () {
                  final invoiceableRows = selectedRows
                      .where((row) => row.isUnbilled)
                      .toList();
                  if (invoiceableRows.isEmpty) {
                    _showSnack('Select at least one unbilled row.');
                    return;
                  }
                  setState(() {
                    _sidePaneMode = _SidePaneMode.draftInvoice;
                    _draftInvoiceRows = invoiceableRows;
                  });
                },
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
                    onGenerateInvoice: (row) {
                      setState(() {
                        _sidePaneMode = _SidePaneMode.draftInvoice;
                        _draftInvoiceRows = [row];
                      });
                    },
                    onEditConversion: _openConversionDialog,
                    onOpenChallan: (id) {
                      _openChallan(id);
                    },
                    onViewInvoices: _showLinkedInvoices,
                    onViewWasteAudit: _showWasteAuditDetails,
                  ),
          ),
        ),
      ],
    );

    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: content),
        if (_sidePaneMode != _SidePaneMode.hidden)
          SoftSurface(
            width: _sidePaneWidth,
            margin: const EdgeInsets.only(left: 16),
            padding: EdgeInsets.zero,
            radius: SoftErpTheme.radiusLg,
            clipContent: true,
            child: _buildSidePane(),
          ),
      ],
    );

    if (widget.embedded) {
      return Padding(padding: const EdgeInsets.all(24), child: body);
    }
    return PageContainer(child: body);
  }

  Widget _buildSidePane() {
    if (_sidePaneMode == _SidePaneMode.draftInvoice) {
      return _InvoiceDraftSidebar(
        rows: _draftInvoiceRows,
        onClose: () => setState(() => _sidePaneMode = _SidePaneMode.hidden),
        onInvoiceCreated: () {
          setState(() => _sidePaneMode = _SidePaneMode.hidden);
          _loadReport();
        },
      );
    }
    if (_sidePaneMode == _SidePaneMode.challanPreview &&
        _previewChallanId != null) {
      return _ChallanPreviewSidebar(
        challanId: _previewChallanId!,
        onClose: () => setState(() => _sidePaneMode = _SidePaneMode.hidden),
      );
    }
    if (_sidePaneMode == _SidePaneMode.invoices && _invoicePreviewRow != null) {
      return _InvoicesSidebar(
        row: _invoicePreviewRow!,
        onClose: () => setState(() => _sidePaneMode = _SidePaneMode.hidden),
        onInvoiceStatusChanged: _loadReport,
      );
    }
    return const SizedBox();
  }

  double get _sidePaneWidth {
    return switch (_sidePaneMode) {
      _SidePaneMode.challanPreview => 540,
      _SidePaneMode.invoices => 460,
      _SidePaneMode.draftInvoice => 420,
      _SidePaneMode.hidden => 0,
    };
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

  void _openChallan(int? challanId) {
    if (challanId == null || challanId <= 0) {
      _showSnack('No source challan is linked to this row.');
      return;
    }
    setState(() {
      _sidePaneMode = _SidePaneMode.challanPreview;
      _previewChallanId = challanId;
    });
  }

  void _showLinkedInvoices(InternalAuditorRow row) {
    if (row.linkedInvoices.isEmpty) {
      _showSnack('No linked invoices yet.');
      return;
    }
    setState(() {
      _sidePaneMode = _SidePaneMode.invoices;
      _invoicePreviewRow = row;
    });
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
    if (!widget.showSectionToggle) {
      await _exportXlsx(allTabs: false);
      return;
    }
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
      if (allTabs || _activeTab == ReconciliationReportSection.auditor) {
        _appendAuditorSheet(excel, _filteredAuditorRows());
      }
      if (allTabs ||
          _activeTab == ReconciliationReportSection.clientStatement) {
        _appendClientSheet(excel, _filteredClientRows());
      }
      if (allTabs || _activeTab == ReconciliationReportSection.misc) {
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
        ReconciliationReportSection.auditor =>
          'Internal Auditor Reconciliation',
        ReconciliationReportSection.clientStatement =>
          'Client Material Statement',
        ReconciliationReportSection.misc => 'Waste Audit',
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
    if (_activeTab == ReconciliationReportSection.clientStatement) {
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
    if (_activeTab == ReconciliationReportSection.misc) {
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
    required this.title,
    required this.subtitle,
    required this.activeTab,
    required this.showSectionToggle,
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
    required this.onBulkInvoice,
  });

  final String title;
  final String subtitle;
  final ReconciliationReportSection activeTab;
  final bool showSectionToggle;
  final DateTime? generatedAt;
  final bool isLoading;
  final bool isExporting;
  final bool isPrinting;
  final int selectedCount;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final ValueChanged<ReconciliationReportSection> onTabChanged;
  final VoidCallback onExport;
  final VoidCallback onPrint;
  final VoidCallback? onBulkInvoice;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SoftIconButton(
          tooltip: 'Back to Challans',
          onTap: onBack,
          icon: Icons.arrow_back_rounded,
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
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  if (selectedCount > 0)
                    AppButton(
                      label: '+ Invoice ($selectedCount)',
                      icon: Icons.receipt_long_outlined,
                      onPressed: onBulkInvoice,
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
                subtitle,
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
              if (showSectionToggle) ...[
                const SizedBox(height: 14),
                _TabToggle(activeTab: activeTab, onChanged: onTabChanged),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TabToggle extends StatelessWidget {
  const _TabToggle({required this.activeTab, required this.onChanged});

  final ReconciliationReportSection activeTab;
  final ValueChanged<ReconciliationReportSection> onChanged;

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
            selected: activeTab == ReconciliationReportSection.auditor,
            onTap: () => onChanged(ReconciliationReportSection.auditor),
          ),
          _TabPill(
            label: 'Client Statement',
            selected: activeTab == ReconciliationReportSection.clientStatement,
            onTap: () => onChanged(ReconciliationReportSection.clientStatement),
          ),
          _TabPill(
            label: 'Misc',
            selected: activeTab == ReconciliationReportSection.misc,
            onTap: () => onChanged(ReconciliationReportSection.misc),
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
      color: SoftErpTheme.cardSurface,
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
              decoration: _reportInputDecoration(
                hintText: 'Search client, challan, item, status...',
                prefixIcon: Icons.search_rounded,
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
          _ReportToolbarButton(
            onPressed: onPickDateFrom,
            icon: Icons.event_outlined,
            label: dateFrom == null ? 'From' : _date(dateFrom),
          ),
          _ReportToolbarButton(
            onPressed: onPickDateTo,
            icon: Icons.event_available_outlined,
            label: dateTo == null ? 'To' : _date(dateTo),
          ),
          if (dateFrom != null || dateTo != null)
            SoftPill(
              label: 'Clear Dates',
              leading: const Icon(
                Icons.close_rounded,
                size: 16,
                color: SoftErpTheme.textSecondary,
              ),
              onTap: onClearDates,
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
        decoration: _reportInputDecoration(labelText: label),
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
      backgroundColor: SoftErpTheme.cardSurfaceAlt,
      selectedColor: SoftErpTheme.accent.withValues(alpha: 0.14),
      checkmarkColor: SoftErpTheme.accent,
      side: const BorderSide(color: SoftErpTheme.border),
      labelStyle: TextStyle(
        color: selected ? SoftErpTheme.accent : SoftErpTheme.textSecondary,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }
}

InputDecoration _reportInputDecoration({
  String? labelText,
  String? hintText,
  IconData? prefixIcon,
  String? helperText,
  String? prefixText,
  String? suffixText,
  bool dense = false,
}) {
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    helperText: helperText,
    prefixText: prefixText,
    suffixText: suffixText,
    prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 18),
    isDense: dense,
    filled: true,
    fillColor: SoftErpTheme.cardSurface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: SoftErpTheme.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: SoftErpTheme.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: SoftErpTheme.accent, width: 1.4),
    ),
  );
}

class _ReportToolbarButton extends StatelessWidget {
  const _ReportToolbarButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SoftPill(
      label: label,
      leading: Icon(icon, size: 16, color: SoftErpTheme.textSecondary),
      background: SoftErpTheme.cardSurface,
      foreground: SoftErpTheme.textPrimary,
      onTap: onPressed,
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

  final ReconciliationReportSection activeTab;
  final List<InternalAuditorRow> auditorRows;
  final List<ClientStatementRow> clientRows;
  final List<WasteAuditRow> miscRows;

  @override
  Widget build(BuildContext context) {
    if (activeTab == ReconciliationReportSection.clientStatement) {
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
    if (activeTab == ReconciliationReportSection.misc) {
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

  final ReconciliationReportSection activeTab;
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
    if (activeTab == ReconciliationReportSection.clientStatement) {
      return clientRows.isEmpty
          ? const _EmptyReportState(message: 'No client material balances yet.')
          : _ClientStatementTable(rows: clientRows);
    }
    if (activeTab == ReconciliationReportSection.misc) {
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

    return Column(
      children: [
        _ReportTableHeader(
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Checkbox(
                  value: allSelected,
                  onChanged: selectableRows.isEmpty
                      ? null
                      : (value) => onToggleAll(rows, value == true),
                  activeColor: SoftErpTheme.accent,
                ),
              ),
              Expanded(
                flex: 2,
                child: _SortHeader(
                  'DC Number',
                  _AuditorSort.dcNumber,
                  sort,
                  sortAscending,
                  onSort,
                ),
              ),
              Expanded(
                flex: 2,
                child: _SortHeader(
                  'Date',
                  _AuditorSort.date,
                  sort,
                  sortAscending,
                  onSort,
                ),
              ),
              Expanded(
                flex: 3,
                child: _SortHeader(
                  'Client / Item',
                  _AuditorSort.client,
                  sort,
                  sortAscending,
                  onSort,
                ),
              ),
              Expanded(
                flex: 2,
                child: _SortHeader(
                  'Weight',
                  _AuditorSort.dispatchedWeight,
                  sort,
                  sortAscending,
                  onSort,
                ),
              ),
              Expanded(
                flex: 2,
                child: _SortHeader(
                  'Units',
                  _AuditorSort.convertedUnits,
                  sort,
                  sortAscending,
                  onSort,
                ),
              ),
              Expanded(
                flex: 2,
                child: _SortHeader(
                  'Invoiced',
                  _AuditorSort.invoicedQuantity,
                  sort,
                  sortAscending,
                  onSort,
                ),
              ),
              Expanded(
                flex: 2,
                child: _SortHeader(
                  'Unbilled',
                  _AuditorSort.unbilledQuantity,
                  sort,
                  sortAscending,
                  onSort,
                ),
              ),
              Expanded(
                flex: 2,
                child: _SortHeader(
                  'Exposure',
                  _AuditorSort.exposure,
                  sort,
                  sortAscending,
                  onSort,
                ),
              ),
              const Expanded(flex: 1, child: _ReportHeaderCell('Var')),
              Expanded(
                flex: 2,
                child: _SortHeader(
                  'Status',
                  _AuditorSort.status,
                  sort,
                  sortAscending,
                  onSort,
                ),
              ),
              const Expanded(flex: 5, child: _ReportHeaderCell('Actions')),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: rows.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final row = rows[index];
              final selected = selectedRows.contains(row.challanItemId);

              Color? bgColor;
              if (row.isAttentionRequired || row.isDirectPrint) {
                bgColor = SoftErpTheme.dangerBg.withValues(alpha: 0.55);
              } else if (row.isUnbilled) {
                bgColor = SoftErpTheme.warningBg.withValues(alpha: 0.55);
              }
              if (selected) {
                bgColor = SoftErpTheme.accent.withValues(alpha: 0.1);
              }

              return _AuditorReportRow(
                key: ValueKey<String>('auditor-row-${row.challanItemId}'),
                row: row,
                contextRows: rows
                    .where(
                      (candidate) => _sameAuditorOrderContext(row, candidate),
                    )
                    .toList(growable: false),
                selected: selected,
                color: bgColor,
                onToggleRow: onToggleRow,
                onGenerateInvoice: onGenerateInvoice,
                onEditConversion: onEditConversion,
                onOpenChallan: onOpenChallan,
                onViewInvoices: onViewInvoices,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AuditorReportRow extends StatefulWidget {
  const _AuditorReportRow({
    super.key,
    required this.row,
    required this.contextRows,
    required this.selected,
    required this.color,
    required this.onToggleRow,
    required this.onGenerateInvoice,
    required this.onEditConversion,
    required this.onOpenChallan,
    required this.onViewInvoices,
  });

  final InternalAuditorRow row;
  final List<InternalAuditorRow> contextRows;
  final bool selected;
  final Color? color;
  final void Function(InternalAuditorRow row, bool selected) onToggleRow;
  final ValueChanged<InternalAuditorRow> onGenerateInvoice;
  final ValueChanged<InternalAuditorRow> onEditConversion;
  final ValueChanged<int?> onOpenChallan;
  final ValueChanged<InternalAuditorRow> onViewInvoices;

  @override
  State<_AuditorReportRow> createState() => _AuditorReportRowState();
}

class _AuditorReportRowState extends State<_AuditorReportRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return Column(
      children: [
        _ReportDataRow(
          color: widget.color,
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Checkbox(
                  value: widget.selected,
                  onChanged: row.isUnbilled
                      ? (value) => widget.onToggleRow(row, value == true)
                      : null,
                  activeColor: SoftErpTheme.accent,
                ),
              ),
              Expanded(flex: 2, child: _DcCell(row: row)),
              Expanded(flex: 2, child: Text(_date(row.challanDate))),
              Expanded(
                flex: 3,
                child: _ClientItemCell(
                  row: row,
                  expanded: _expanded,
                  itemCount: widget.contextRows.length,
                  onToggle: () => setState(() => _expanded = !_expanded),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text('${_fmt(row.totalDispatchedWeightKg)} kg'),
              ),
              Expanded(
                flex: 2,
                child: Text('${_fmt(row.convertedUnits)} ${row.toUnitLabel}'),
              ),
              Expanded(flex: 2, child: Text(_fmt(row.invoicedQuantity))),
              Expanded(flex: 2, child: Text(_fmt(row.unbilledQuantity))),
              Expanded(flex: 2, child: Text(_money(row.financialExposure))),
              Expanded(flex: 1, child: Text('${_fmt(row.variancePercent)}%')),
              Expanded(flex: 2, child: _StatusBadge(row.status)),
              Expanded(
                flex: 5,
                child: _AuditorActions(
                  row: row,
                  onGenerateInvoice: widget.onGenerateInvoice,
                  onEditConversion: widget.onEditConversion,
                  onOpenChallan: widget.onOpenChallan,
                  onViewInvoices: widget.onViewInvoices,
                ),
              ),
            ],
          ),
        ),
        if (_expanded)
          _AuditorOrderItemsDropdown(sourceRow: row, rows: widget.contextRows),
      ],
    );
  }
}

class _AuditorOrderItemsDropdown extends StatelessWidget {
  const _AuditorOrderItemsDropdown({
    required this.sourceRow,
    required this.rows,
  });

  final InternalAuditorRow sourceRow;
  final List<InternalAuditorRow> rows;

  @override
  Widget build(BuildContext context) {
    final title = sourceRow.orderId != null && sourceRow.orderId! > 0
        ? 'Order #${sourceRow.orderId} items'
        : '${sourceRow.dcNumber} items';
    return Container(
      margin: const EdgeInsets.fromLTRB(56, 6, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_tree_outlined,
                size: 16,
                color: SoftErpTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
              ),
              Text(
                '${rows.length} line${rows.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final itemRow in rows) _AuditorOrderItemLine(row: itemRow),
        ],
      ),
    );
  }
}

class _AuditorOrderItemLine extends StatelessWidget {
  const _AuditorOrderItemLine({required this.row});

  final InternalAuditorRow row;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.itemName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  'HSN ${row.hsnCode.isEmpty ? '-' : row.hsnCode}',
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: _AuditorLineMetric(
              label: 'Weight',
              value: '${_fmt(row.totalDispatchedWeightKg)} kg',
            ),
          ),
          Expanded(
            flex: 2,
            child: _AuditorLineMetric(
              label: 'Units',
              value: '${_fmt(row.convertedUnits)} ${row.toUnitLabel}',
            ),
          ),
          Expanded(
            flex: 2,
            child: _AuditorLineMetric(
              label: 'Unbilled',
              value: _fmt(row.unbilledQuantity),
            ),
          ),
          Expanded(
            flex: 2,
            child: _AuditorLineMetric(
              label: 'Exposure',
              value: _money(row.financialExposure),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditorLineMetric extends StatelessWidget {
  const _AuditorLineMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: SoftErpTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
      ],
    );
  }
}

bool _sameAuditorOrderContext(
  InternalAuditorRow row,
  InternalAuditorRow candidate,
) {
  if (row.orderId != null && row.orderId! > 0) {
    return candidate.orderId == row.orderId;
  }
  if (row.challanId > 0) {
    return candidate.challanId == row.challanId;
  }
  return candidate.clientName == row.clientName &&
      candidate.dcNumber == row.dcNumber;
}

class _SortHeader extends StatelessWidget {
  const _SortHeader(
    this.label,
    this.sortKey,
    this.currentSort,
    this.ascending,
    this.onSort,
  );

  final String label;
  final _AuditorSort sortKey;
  final _AuditorSort currentSort;
  final bool ascending;
  final ValueChanged<_AuditorSort> onSort;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onSort(sortKey),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: _ReportHeaderCell(label)),
            if (currentSort == sortKey) ...[
              const SizedBox(width: 4),
              Icon(
                ascending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14,
                color: SoftErpTheme.accent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReportTableHeader extends StatelessWidget {
  const _ReportTableHeader({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: const BoxDecoration(
        color: SoftErpTheme.cardSurfaceAlt,
        border: Border(bottom: BorderSide(color: SoftErpTheme.border)),
      ),
      child: child,
    );
  }
}

class _ReportHeaderCell extends StatelessWidget {
  const _ReportHeaderCell(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: SoftErpTheme.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _ReportDataRow extends StatelessWidget {
  const _ReportDataRow({required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color ?? SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: child,
    );
  }
}

class _ClientItemCell extends StatelessWidget {
  const _ClientItemCell({
    required this.row,
    required this.expanded,
    required this.itemCount,
    required this.onToggle,
  });

  final InternalAuditorRow row;
  final bool expanded;
  final int itemCount;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onToggle,
      child: SizedBox(
        width: 260,
        child: Row(
          children: [
            Expanded(
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
                    'HSN ${row.hsnCode.isEmpty ? '-' : row.hsnCode} • $itemCount order item${itemCount == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: SoftErpTheme.accent,
            ),
          ],
        ),
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
            _ReportActionChip(
              label: 'Open Draft Invoice',
              icon: Icons.receipt_long_outlined,
              onTap: () => onGenerateInvoice(row),
            ),
          _ReportActionChip(
            label: 'Edit Conversion',
            icon: Icons.tune_rounded,
            onTap: row.itemId == null ? null : () => onEditConversion(row),
          ),
          _ReportActionChip(
            label: 'Open Challan',
            icon: Icons.open_in_new_rounded,
            onTap: () => onOpenChallan(row.challanId),
          ),
          _ReportActionChip(
            label: 'View Invoices',
            icon: Icons.list_alt_rounded,
            onTap: row.linkedInvoices.isEmpty
                ? null
                : () => onViewInvoices(row),
          ),
        ],
      ),
    );
  }
}

class _ReportActionChip extends StatelessWidget {
  const _ReportActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final foreground = enabled
        ? SoftErpTheme.accent
        : SoftErpTheme.textSecondary;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 152, minHeight: 32),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: foreground,
          backgroundColor: enabled
              ? SoftErpTheme.accent.withValues(alpha: 0.08)
              : SoftErpTheme.cardSurfaceAlt,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(
              color: enabled
                  ? SoftErpTheme.accent.withValues(alpha: 0.22)
                  : SoftErpTheme.border,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientStatementTable extends StatelessWidget {
  const _ClientStatementTable({required this.rows});

  final List<ClientStatementRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ReportTableHeader(
          child: const Row(
            children: [
              Expanded(flex: 2, child: _ReportHeaderCell('Client')),
              Expanded(flex: 2, child: _ReportHeaderCell('Item')),
              Expanded(
                flex: 2,
                child: _ReportHeaderCell('Material Received (Input)'),
              ),
              Expanded(flex: 2, child: _ReportHeaderCell('Units Delivered')),
              Expanded(flex: 2, child: _ReportHeaderCell('Balance Material')),
              Expanded(flex: 1, child: _ReportHeaderCell('Status')),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: rows.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final row = rows[index];
              Color? bgColor;
              if (row.status.toLowerCase().contains('over')) {
                bgColor = SoftErpTheme.dangerBg.withValues(alpha: 0.55);
              } else if (row.status.toLowerCase().contains('remaining')) {
                bgColor = SoftErpTheme.warningBg.withValues(alpha: 0.5);
              }
              return _ReportDataRow(
                color: bgColor,
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text(row.clientName)),
                    Expanded(flex: 2, child: Text(row.itemName)),
                    Expanded(
                      flex: 2,
                      child: Text('${_fmt(row.materialReceivedInputKg)} kg'),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(_fmt(row.totalFinishedUnitsDelivered)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${_fmt(row.netBalanceMaterialRemainingKg)} kg',
                      ),
                    ),
                    Expanded(flex: 1, child: _StatusBadge(row.status)),
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
    return Column(
      children: [
        _ReportTableHeader(
          child: const Row(
            children: [
              Expanded(flex: 1, child: _ReportHeaderCell('ID')),
              Expanded(flex: 2, child: _ReportHeaderCell('Audit Time')),
              Expanded(flex: 2, child: _ReportHeaderCell('Client / Item')),
              Expanded(flex: 2, child: _ReportHeaderCell('DC Number')),
              Expanded(
                flex: 3,
                child: _ReportHeaderCell('Input / Shipped / Waste'),
              ),
              Expanded(flex: 2, child: _ReportHeaderCell('Source')),
              Expanded(flex: 2, child: _ReportHeaderCell('Actions')),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: rows.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final row = rows[index];
              return _ReportDataRow(
                child: Row(
                  children: [
                    Expanded(flex: 1, child: Text('#${row.id}')),
                    Expanded(flex: 2, child: Text(_dateTime(row.auditTime))),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.clientName,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            row.itemName,
                            style: const TextStyle(
                              color: SoftErpTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(flex: 2, child: Text(row.challanNo)),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Input: ${_fmt(row.inputWeightKg)} kg',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            'Shipped: ${_fmt(row.shippedWeightKg)} kg',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            'Waste: ${_fmt(row.wasteWeightKg)} kg (${_fmt(row.wastePercentage)}%)',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: SoftErpTheme.dangerText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(flex: 2, child: Text(row.source)),
                    Expanded(
                      flex: 2,
                      child: Wrap(
                        spacing: 4,
                        children: [
                          _ReportActionChip(
                            label: 'Details',
                            icon: Icons.info_outline_rounded,
                            onTap: () => onViewWasteAudit(row),
                          ),
                          if (row.challanId != null)
                            _ReportActionChip(
                              label: 'Challan',
                              icon: Icons.open_in_new_rounded,
                              onTap: () => onOpenChallan(row.challanId),
                            ),
                        ],
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

class _InvoiceDraftSidebar extends StatefulWidget {
  const _InvoiceDraftSidebar({
    required this.rows,
    required this.onClose,
    required this.onInvoiceCreated,
  });

  final List<InternalAuditorRow> rows;
  final VoidCallback onClose;
  final VoidCallback onInvoiceCreated;

  @override
  State<_InvoiceDraftSidebar> createState() => _InvoiceDraftSidebarState();
}

class _InvoiceDraftSidebarState extends State<_InvoiceDraftSidebar> {
  final TextEditingController _invoiceNoController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  late final List<_InvoiceLineControllers> _lineControllers;
  late DateTime _invoiceDate;
  bool _isSaving = false;

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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Draft Invoice',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              SoftIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Close',
                onTap: widget.onClose,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _invoiceNoController,
                  decoration: _reportInputDecoration(
                    labelText: 'Invoice No',
                    helperText: 'Blank auto-generates',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _dateController,
                  readOnly: true,
                  decoration: _reportInputDecoration(
                    labelText: 'Invoice Date',
                    prefixIcon: Icons.event_outlined,
                  ),
                  onTap: _pickDate,
                ),
                const SizedBox(height: 12),
                _ReadOnlyField(label: 'Client', value: row.clientName),
                const SizedBox(height: 12),
                _ReadOnlyField(
                  label: 'GSTIN',
                  value: row.gstin.isEmpty ? '-' : row.gstin,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Line Items',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                for (final controller in _lineControllers) ...[
                  SoftSurface(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 8),
                    radius: SoftErpTheme.radiusSm,
                    elevated: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          controller.row.itemName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'DC: ${controller.row.dcNumber}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: SoftErpTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _NumberCell(
                                controller.quantityController,
                                label: 'Qty',
                                onChanged: _recalc,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _NumberCell(
                                controller.unitPriceController,
                                label: 'Price',
                                onChanged: _recalc,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _NumberCell(
                                controller.cgstController,
                                label: 'CGST%',
                                onChanged: _recalc,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _NumberCell(
                                controller.sgstController,
                                label: 'SGST%',
                                onChanged: _recalc,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Total: ${_money(controller.taxableValue + controller.cgstAmount + controller.sgstAmount)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SoftSurface(
                  padding: const EdgeInsets.all(12),
                  color: SoftErpTheme.accentSurface,
                  radius: SoftErpTheme.radiusSm,
                  elevated: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Taxable:'),
                          Text(_money(totals.taxable)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('CGST:'),
                          Text(_money(totals.cgst)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('SGST:'),
                          Text(_money(totals.sgst)),
                        ],
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Grand Total:',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            _money(totals.total),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: AppButton(
            label: 'Create Draft Invoice',
            icon: Icons.receipt_long_outlined,
            isLoading: _isSaving,
            onPressed: _submit,
          ),
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

  Future<void> _submit() async {
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
    final input = InvoiceDraftInput(
      invoiceNo: _invoiceNoController.text,
      clientId: row.clientId,
      clientName: row.clientName,
      gstin: row.gstin,
      invoiceDate: _invoiceDate,
      lines: lines,
    );

    setState(() => _isSaving = true);
    try {
      final invoice = await context
          .read<DeliveryChallanProvider>()
          .repository
          .createInvoice(input);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Draft invoice ${invoice.invoiceNo} created.')),
      );
      widget.onInvoiceCreated();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
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
  List<ItemUnitConversionDefinition> _predefinedConversions = [];

  @override
  void initState() {
    super.initState();
    _ratioController = TextEditingController(
      text: _fmt(widget.row.conversionRatio),
    );
    _unitController = TextEditingController(text: widget.row.toUnitLabel);
    _unitController.addListener(() {
      setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.row.itemId == null) return;
      final provider = context.read<ItemsProvider>();
      final item = provider.items
          .where((i) => i.id == widget.row.itemId)
          .firstOrNull;
      if (item != null && item.unitConversions.isNotEmpty) {
        setState(() {
          _predefinedConversions = item.unitConversions;
        });
      }
    });
  }

  @override
  void dispose() {
    _ratioController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: SoftSurface(
        width: 480,
        padding: const EdgeInsets.all(22),
        radius: SoftErpTheme.radiusLg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Edit Conversion',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
                SoftIconButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Close',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SoftSurface(
              padding: const EdgeInsets.all(12),
              color: SoftErpTheme.cardSurfaceAlt,
              elevated: false,
              radius: SoftErpTheme.radiusSm,
              child: Column(
                children: [
                  _DetailLine('Item', widget.row.itemName),
                  _DetailLine(
                    'Variation Leaf',
                    '${widget.row.variationLeafNodeId}',
                  ),
                ],
              ),
            ),
            if (_predefinedConversions.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Select from Item Master:',
                style: TextStyle(
                  fontSize: 12,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _predefinedConversions.map<Widget>((conv) {
                  return ActionChip(
                    label: Text(
                      '${conv.unitSymbol} (1 kg = ${conv.factorToPrimary})',
                    ),
                    onPressed: () {
                      _unitController.text = conv.unitSymbol;
                      _ratioController.text = _fmt(conv.factorToPrimary);
                    },
                    backgroundColor: SoftErpTheme.accentSoft,
                    side: BorderSide.none,
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _unitController,
              decoration: _reportInputDecoration(
                labelText: 'Target Unit (e.g. pcs, boxes)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ratioController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: _reportInputDecoration(
                labelText: 'Conversion Factor',
                prefixText: '1 kg = ',
                suffixText:
                    ' ${_unitController.text.trim().isEmpty ? 'units' : _unitController.text.trim()}',
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: 'Cancel',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 10),
                AppButton(
                  label: 'Save',
                  icon: Icons.save_outlined,
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
                ),
              ],
            ),
          ],
        ),
      ),
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
      decoration: _reportInputDecoration(labelText: label),
      child: Text(value, overflow: TextOverflow.ellipsis),
    );
  }
}

class _NumberCell extends StatelessWidget {
  const _NumberCell(this.controller, {this.label, required this.onChanged});

  final TextEditingController controller;
  final String? label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => onChanged(),
        decoration: _reportInputDecoration(labelText: label, dense: true),
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
    final isGood =
        lower.contains('auto') || lower.contains('balanced') || lower == 'paid';
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
    return Center(
      child: SoftSurface(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        color: SoftErpTheme.cardSurfaceAlt,
        elevated: false,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: SoftErpTheme.accent,
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Loading report...',
              style: TextStyle(
                color: SoftErpTheme.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
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
          const Icon(
            Icons.error_outline_rounded,
            size: 42,
            color: SoftErpTheme.dangerText,
          ),
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
      child: SoftSurface(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        color: SoftErpTheme.cardSurfaceAlt,
        elevated: false,
        child: Text(
          message,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: SoftErpTheme.textSecondary),
        ),
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

class _ChallanPreviewSidebar extends StatefulWidget {
  const _ChallanPreviewSidebar({
    required this.challanId,
    required this.onClose,
  });

  final int challanId;
  final VoidCallback onClose;

  @override
  State<_ChallanPreviewSidebar> createState() => _ChallanPreviewSidebarState();
}

class _ChallanPreviewSidebarState extends State<_ChallanPreviewSidebar> {
  DeliveryChallan? _challan;
  List<ChallanTemplate> _templates = const <ChallanTemplate>[];
  ChallanTemplate? _selectedTemplate;
  Uint8List? _templatePdfBytes;
  bool _isLoading = true;
  bool _isPdfLoading = false;
  String? _errorMessage;
  String? _templatePdfError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_ChallanPreviewSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.challanId != widget.challanId) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _templatePdfError = null;
      _templatePdfBytes = null;
    });
    try {
      final provider = context.read<DeliveryChallanProvider>();
      final challan = await provider.repository.getChallan(widget.challanId);
      final templates = await provider.loadTemplates(
        partyType: ChallanTemplatePartyType.generic,
        activeOnly: true,
      );
      final orderedTemplates = <ChallanTemplate>[
        ...templates.where((template) => template.challanType == challan.type),
        ...templates.where((template) => template.challanType != challan.type),
      ];
      if (mounted) {
        setState(() {
          _challan = challan;
          _templates = orderedTemplates;
          _selectedTemplate = orderedTemplates.isEmpty
              ? null
              : orderedTemplates.first;
          _isLoading = false;
        });
        await _loadTemplatePdf();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadTemplatePdf() async {
    final challan = _challan;
    if (challan == null || !mounted) {
      return;
    }
    setState(() {
      _isPdfLoading = true;
      _templatePdfError = null;
      _templatePdfBytes = null;
    });
    try {
      final bytes = await context
          .read<DeliveryChallanProvider>()
          .repository
          .fetchTemplatePreviewPdf(
            challanId: challan.id,
            templateId: _selectedTemplate?.id,
            mode: 'digital',
          );
      if (mounted) {
        setState(() => _templatePdfBytes = bytes);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _templatePdfError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isPdfLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Template Challan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              SoftIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Close',
                onTap: widget.onClose,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _isLoading
              ? const _ReportLoadingState()
              : _errorMessage != null
              ? _ReportErrorState(message: _errorMessage!, onRetry: _load)
              : _challan == null
              ? const Center(child: Text('Challan not found.'))
              : _buildPreview(_challan!),
        ),
      ],
    );
  }

  Widget _buildPreview(DeliveryChallan challan) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SoftSurface(
            padding: const EdgeInsets.all(14),
            radius: SoftErpTheme.radiusMd,
            elevated: false,
            color: SoftErpTheme.cardSurfaceAlt,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        challan.challanNo,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: SoftErpTheme.textPrimary,
                        ),
                      ),
                    ),
                    _StatusBadge(challan.status.name.toUpperCase()),
                  ],
                ),
                const SizedBox(height: 10),
                _DetailLine(
                  'Party',
                  challan.isReception
                      ? challan.vendorName
                      : challan.customerName,
                ),
                _DetailLine(
                  'GSTIN',
                  challan.isReception
                      ? (challan.vendorGstin.isEmpty
                            ? '-'
                            : challan.vendorGstin)
                      : (challan.customerGstin.isEmpty
                            ? '-'
                            : challan.customerGstin),
                ),
                _DetailLine('Date', _date(challan.date)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_templates.isNotEmpty)
            DropdownButtonFormField<int>(
              initialValue: _selectedTemplate?.id,
              isExpanded: true,
              decoration: _reportInputDecoration(
                labelText: 'Template',
                helperText:
                    'Digital preview uses this user-defined template layout.',
              ),
              items: _templates
                  .map(
                    (template) => DropdownMenuItem<int>(
                      value: template.id,
                      child: Text(
                        '${template.name} • ${template.stockSize} on ${template.paperSize}',
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (templateId) {
                final selected = _templates
                    .where((template) => template.id == templateId)
                    .firstOrNull;
                if (selected == null) {
                  return;
                }
                setState(() => _selectedTemplate = selected);
                _loadTemplatePdf();
              },
            )
          else
            SoftSurface(
              padding: const EdgeInsets.all(12),
              radius: SoftErpTheme.radiusSm,
              elevated: false,
              color: SoftErpTheme.warningBg.withValues(alpha: 0.55),
              child: const Text(
                'No active template is listed locally. If this challan was issued with a saved snapshot, the backend preview will still use that frozen template.',
                style: TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            height: 520,
            child: SoftSurface(
              padding: EdgeInsets.zero,
              radius: SoftErpTheme.radiusMd,
              clipContent: true,
              child: _isPdfLoading
                  ? const _ReportLoadingState()
                  : _templatePdfBytes != null
                  ? PdfPreview(
                      build: (_) async => _templatePdfBytes!,
                      allowPrinting: false,
                      allowSharing: false,
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                      canDebug: false,
                      useActions: false,
                      maxPageWidth: 430,
                    )
                  : _TemplateFallbackPreview(
                      challan: challan,
                      errorMessage: _templatePdfError,
                    ),
            ),
          ),
          const SizedBox(height: 12),
          _TemplateDataCard(challan: challan),
        ],
      ),
    );
  }
}

class _TemplateDataCard extends StatelessWidget {
  const _TemplateDataCard({required this.challan});

  final DeliveryChallan challan;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      padding: const EdgeInsets.all(14),
      radius: SoftErpTheme.radiusMd,
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Fields sent to template',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: SoftErpTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          _DetailLine(
            'Party Name',
            challan.isReception ? challan.vendorName : challan.customerName,
          ),
          _DetailLine(
            'GSTIN',
            challan.isReception
                ? (challan.vendorGstin.isEmpty ? '-' : challan.vendorGstin)
                : (challan.customerGstin.isEmpty ? '-' : challan.customerGstin),
          ),
          _DetailLine('Date', _date(challan.date)),
          const Divider(color: SoftErpTheme.border),
          for (final line in challan.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SoftSurface(
                padding: const EdgeInsets.all(10),
                radius: SoftErpTheme.radiusSm,
                elevated: false,
                color: SoftErpTheme.cardSurfaceAlt,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      line.particulars,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: SoftErpTheme.textPrimary,
                      ),
                    ),
                    if (line.note.isNotEmpty)
                      Text(
                        line.note,
                        style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: SoftErpTheme.textSecondary,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _MiniMetric(
                          label: 'HSN',
                          value: line.hsnCode.isEmpty ? '-' : line.hsnCode,
                        ),
                        _MiniMetric(
                          label: 'Qty',
                          value: _lineValue(line.quantityPcs),
                        ),
                        _MiniMetric(
                          label: 'Weight',
                          value: '${_lineValue(line.weight)} kg',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TemplateFallbackPreview extends StatelessWidget {
  const _TemplateFallbackPreview({
    required this.challan,
    required this.errorMessage,
  });

  final DeliveryChallan challan;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (errorMessage != null) ...[
            SoftSurface(
              padding: const EdgeInsets.all(10),
              radius: SoftErpTheme.radiusSm,
              elevated: false,
              color: SoftErpTheme.warningBg.withValues(alpha: 0.6),
              child: Text(
                'Template PDF unavailable: $errorMessage',
                style: const TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SoftErpTheme.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  challan.isReception
                      ? 'RECEPTION CHALLAN'
                      : 'DELIVERY CHALLAN',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 12),
                _DetailLine('No', challan.challanNo),
                _DetailLine('Date', _date(challan.date)),
                _DetailLine(
                  'Party',
                  challan.isReception
                      ? challan.vendorName
                      : challan.customerName,
                ),
                _DetailLine(
                  'GSTIN',
                  challan.isReception
                      ? (challan.vendorGstin.isEmpty
                            ? '-'
                            : challan.vendorGstin)
                      : (challan.customerGstin.isEmpty
                            ? '-'
                            : challan.customerGstin),
                ),
                const SizedBox(height: 14),
                const _TemplateTableHeader(),
                for (final line in challan.items) _TemplateTableRow(line: line),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateTableHeader extends StatelessWidget {
  const _TemplateTableHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(flex: 4, child: Text('Item', style: _tableHeaderStyle)),
        Expanded(flex: 2, child: Text('HSN', style: _tableHeaderStyle)),
        Expanded(flex: 2, child: Text('Qty', style: _tableHeaderStyle)),
        Expanded(flex: 2, child: Text('Weight', style: _tableHeaderStyle)),
      ],
    );
  }
}

class _TemplateTableRow extends StatelessWidget {
  const _TemplateTableRow({required this.line});

  final DeliveryChallanItem line;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SoftErpTheme.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.particulars),
                if (line.note.isNotEmpty)
                  Text(
                    line.note,
                    style: const TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(line.hsnCode.isEmpty ? '-' : line.hsnCode),
          ),
          Expanded(flex: 2, child: Text(_lineValue(line.quantityPcs))),
          Expanded(flex: 2, child: Text('${_lineValue(line.weight)} kg')),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: SoftErpTheme.textSecondary,
        ),
      ),
    );
  }
}

class _InvoicesSidebar extends StatefulWidget {
  const _InvoicesSidebar({
    required this.row,
    required this.onClose,
    required this.onInvoiceStatusChanged,
  });

  final InternalAuditorRow row;
  final VoidCallback onClose;
  final VoidCallback onInvoiceStatusChanged;

  @override
  State<_InvoicesSidebar> createState() => _InvoicesSidebarState();
}

class _InvoicesSidebarState extends State<_InvoicesSidebar> {
  int? _selectedInvoiceId;
  InvoiceHeader? _selectedInvoice;
  bool _isLoadingInvoice = false;
  String? _invoiceError;

  @override
  void initState() {
    super.initState();
    _selectedInvoiceId = widget.row.linkedInvoices.isEmpty
        ? null
        : widget.row.linkedInvoices.first.id;
    if (_selectedInvoiceId != null) {
      _loadInvoice(_selectedInvoiceId!);
    }
  }

  @override
  void didUpdateWidget(_InvoicesSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.challanItemId != widget.row.challanItemId) {
      _selectedInvoice = null;
      _invoiceError = null;
      _selectedInvoiceId = widget.row.linkedInvoices.isEmpty
          ? null
          : widget.row.linkedInvoices.first.id;
      if (_selectedInvoiceId != null) {
        _loadInvoice(_selectedInvoiceId!);
      }
    }
  }

  Future<void> _loadInvoice(int invoiceId) async {
    setState(() {
      _selectedInvoiceId = invoiceId;
      _isLoadingInvoice = true;
      _invoiceError = null;
    });
    try {
      final invoice = await context
          .read<DeliveryChallanProvider>()
          .repository
          .getInvoice(invoiceId);
      if (mounted) {
        setState(() => _selectedInvoice = invoice);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _invoiceError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingInvoice = false);
      }
    }
  }

  Future<void> _printInvoice(int invoiceId, String invoiceNo) async {
    final provider = context.read<DeliveryChallanProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await provider.repository.fetchInvoicePdf(invoiceId);
      await Printing.layoutPdf(
        name: 'Invoice-$invoiceNo.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to print invoice: $e'),
          backgroundColor: SoftErpTheme.dangerText,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Invoices • ${widget.row.dcNumber}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SoftIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Close',
                onTap: widget.onClose,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Linked invoices',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                for (final invoice in widget.row.linkedInvoices)
                  _InvoiceReferenceTile(
                    invoice: invoice,
                    selected: invoice.id == _selectedInvoiceId,
                    onTap: () => _loadInvoice(invoice.id),
                  ),
                const SizedBox(height: 14),
                if (_isLoadingInvoice)
                  const SizedBox(height: 220, child: _ReportLoadingState())
                else if (_invoiceError != null)
                  _ReportErrorState(
                    message: _invoiceError!,
                    onRetry: _selectedInvoiceId == null
                        ? () {}
                        : () => _loadInvoice(_selectedInvoiceId!),
                  )
                else if (_selectedInvoice != null)
                  _InvoiceDetailCard(
                    invoice: _selectedInvoice!,
                    onPrint: () => _printInvoice(
                      _selectedInvoice!.id,
                      _selectedInvoice!.invoiceNo,
                    ),
                    onToggleStatus: () async {
                      final newStatus =
                          _selectedInvoice!.status.toLowerCase() == 'paid'
                          ? 'issued'
                          : 'paid';
                      setState(() {
                        _isLoadingInvoice = true;
                      });
                      final provider = context.read<DeliveryChallanProvider>();
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await provider.updateInvoiceStatus(
                          _selectedInvoice!.id,
                          newStatus,
                        );
                        await _loadInvoice(_selectedInvoice!.id);
                        widget.onInvoiceStatusChanged();
                      } catch (e) {
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Failed to update status: $e'),
                              backgroundColor: SoftErpTheme.dangerText,
                            ),
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() {
                            _isLoadingInvoice = false;
                          });
                        }
                      }
                    },
                  )
                else
                  const _EmptyReportState(
                    message: 'Select an invoice to view details.',
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InvoiceReferenceTile extends StatelessWidget {
  const _InvoiceReferenceTile({
    required this.invoice,
    required this.selected,
    required this.onTap,
  });

  final InvoiceReference invoice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.zero,
      radius: SoftErpTheme.radiusSm,
      elevated: false,
      color: selected
          ? SoftErpTheme.accent.withValues(alpha: 0.1)
          : SoftErpTheme.cardSurfaceAlt,
      child: ListTile(
        onTap: onTap,
        selected: selected,
        dense: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        ),
        title: Text(
          invoice.invoiceNo,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text('${invoice.status} • ${_date(invoice.invoiceDate)}'),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: SoftErpTheme.textSecondary,
        ),
      ),
    );
  }
}

class _InvoiceDetailCard extends StatelessWidget {
  const _InvoiceDetailCard({
    required this.invoice,
    required this.onToggleStatus,
    required this.onPrint,
  });

  final InvoiceHeader invoice;
  final VoidCallback onToggleStatus;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      padding: const EdgeInsets.all(14),
      radius: SoftErpTheme.radiusMd,
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  invoice.invoiceNo,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
              ),
              _StatusBadge(invoice.status),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: invoice.status.toLowerCase() == 'paid'
                      ? 'Mark as Unpaid'
                      : 'Mark as Paid',
                  icon: invoice.status.toLowerCase() == 'paid'
                      ? Icons.cancel_outlined
                      : Icons.check_circle_outline_rounded,
                  variant: invoice.status.toLowerCase() == 'paid'
                      ? AppButtonVariant.secondary
                      : AppButtonVariant.primary,
                  onPressed: onToggleStatus,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: 'Print Invoice',
                  icon: Icons.print_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: onPrint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _DetailLine('Date', _date(invoice.invoiceDate)),
          _DetailLine('Client', invoice.clientName),
          _DetailLine('GSTIN', invoice.gstin.isEmpty ? '-' : invoice.gstin),
          const Divider(color: SoftErpTheme.border),
          for (final line in invoice.lines)
            SoftSurface(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              radius: SoftErpTheme.radiusSm,
              elevated: false,
              color: SoftErpTheme.cardSurfaceAlt,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    line.itemName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _MiniMetric(
                        label: 'HSN',
                        value: line.hsnCode.isEmpty ? '-' : line.hsnCode,
                      ),
                      _MiniMetric(label: 'Qty', value: _fmt(line.quantity)),
                      _MiniMetric(label: 'Rate', value: _money(line.unitPrice)),
                      _MiniMetric(
                        label: 'Taxable',
                        value: _money(line.taxableValue),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const Divider(color: SoftErpTheme.border),
          _DetailLine('Total Qty', _fmt(invoice.totalQuantity)),
          _DetailLine('Taxable', _money(invoice.taxableValue)),
          _DetailLine('CGST', _money(invoice.cgstAmount)),
          _DetailLine('SGST', _money(invoice.sgstAmount)),
          _DetailLine('Grand Total', _money(invoice.totalAmount)),
        ],
      ),
    );
  }
}

const TextStyle _tableHeaderStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w900,
  color: SoftErpTheme.textSecondary,
);

String _lineValue(String value) {
  final parsed = double.tryParse(value.trim());
  if (parsed == null) {
    return value.trim().isEmpty ? '-' : value.trim();
  }
  return _fmt(parsed);
}
