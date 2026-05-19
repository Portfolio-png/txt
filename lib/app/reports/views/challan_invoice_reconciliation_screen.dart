import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/soft_erp_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/page_container.dart';
import '../../../core/widgets/soft_primitives.dart';
import '../../../features/delivery_challans/presentation/providers/delivery_challan_provider.dart';
import '../../reports/domain/reconciliation_report.dart';
import '../../shell/navigation_provider.dart';

enum _ReportTab { auditor, clientStatement, misc }

class ChallanInvoiceReconciliationScreen extends StatefulWidget {
  const ChallanInvoiceReconciliationScreen({super.key});

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
  String? _error;

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

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot ?? ReconciliationReportSnapshot.empty();
    final query = _searchController.text.trim().toLowerCase();
    final auditorRows = snapshot.internalAuditor
        .where((row) {
          return query.isEmpty ||
              '${row.dcNumber} ${row.clientName} ${row.itemName} ${row.status}'
                  .toLowerCase()
                  .contains(query);
        })
        .toList(growable: false);
    final clientRows = snapshot.clientStatement
        .where((row) {
          return query.isEmpty ||
              '${row.clientName} ${row.itemName} ${row.status}'
                  .toLowerCase()
                  .contains(query);
        })
        .toList(growable: false);
    final miscRows = snapshot.misc
        .where((row) {
          return query.isEmpty ||
              '${row.clientName} ${row.itemName} ${row.challanNo} ${row.source}'
                  .toLowerCase()
                  .contains(query);
        })
        .toList(growable: false);

    return PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReportHeader(
            activeTab: _activeTab,
            onBack: () =>
                context.read<NavigationProvider>().select('delivery_challans'),
            onRefresh: _loadReport,
            onTabChanged: (tab) => setState(() => _activeTab = tab),
          ),
          const SizedBox(height: 14),
          _ReportToolbar(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
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
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _ReportErrorState(message: _error!, onRetry: _loadReport)
                  : _ReportBody(
                      activeTab: _activeTab,
                      auditorRows: auditorRows,
                      clientRows: clientRows,
                      miscRows: miscRows,
                      onGenerateInvoice: _showInvoicePayload,
                    ),
            ),
          ),
        ],
      ),
    );
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
      setState(() => _snapshot = snapshot);
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

  void _showInvoicePayload(InternalAuditorRow row) {
    final payload = <String, Object?>{
      'clientName': row.clientName,
      'gstin': row.gstin,
      'status': 'draft',
      'lines': [
        {
          'challanId': row.challanId,
          'challanItemId': row.challanItemId,
          'itemName': row.itemName,
          'hsnCode': row.hsnCode,
          'quantity': row.unbilledQuantity,
          'unitPrice': 0,
          'cgstRate': 0,
          'sgstRate': 0,
        },
      ],
    };
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Generate Invoice Payload'),
          content: SingleChildScrollView(
            child: SelectableText(_prettyPayload(payload)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({
    required this.activeTab,
    required this.onBack,
    required this.onRefresh,
    required this.onTabChanged,
  });

  final _ReportTab activeTab;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final ValueChanged<_ReportTab> onTabChanged;

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
              Text('Report', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Reconcile challan dispatch, invoices, material balance, and waste audit.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SoftErpTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              _TabToggle(activeTab: activeTab, onChanged: onTabChanged),
            ],
          ),
        ),
        AppButton(
          label: 'Refresh',
          icon: Icons.refresh_rounded,
          variant: AppButtonVariant.secondary,
          onPressed: onRefresh,
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
  const _ReportToolbar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        hintText: 'Search client, challan, item, status...',
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.72),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: SoftErpTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: SoftErpTheme.border),
        ),
      ),
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
    required this.onGenerateInvoice,
  });

  final _ReportTab activeTab;
  final List<InternalAuditorRow> auditorRows;
  final List<ClientStatementRow> clientRows;
  final List<WasteAuditRow> miscRows;
  final ValueChanged<InternalAuditorRow> onGenerateInvoice;

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
          : _MiscTable(rows: miscRows);
    }
    return auditorRows.isEmpty
        ? const _EmptyReportState(message: 'No issued delivery challans yet.')
        : _AuditorTable(
            rows: auditorRows,
            onGenerateInvoice: onGenerateInvoice,
          );
  }
}

class _AuditorTable extends StatelessWidget {
  const _AuditorTable({required this.rows, required this.onGenerateInvoice});

  final List<InternalAuditorRow> rows;
  final ValueChanged<InternalAuditorRow> onGenerateInvoice;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      primary: false,
      child: SingleChildScrollView(
        primary: false,
        child: DataTable(
          dataRowMinHeight: 88,
          dataRowMaxHeight: 116,
          headingRowColor: WidgetStateProperty.all(SoftErpTheme.cardSurfaceAlt),
          columns: const [
            DataColumn(label: Text('DC Number')),
            DataColumn(label: Text('Dispatched Weight')),
            DataColumn(label: Text('Converted Units')),
            DataColumn(label: Text('Invoiced Qty')),
            DataColumn(label: Text('GSTIN')),
            DataColumn(label: Text('CGST')),
            DataColumn(label: Text('SGST')),
            DataColumn(label: Text('Waste %')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Actions')),
          ],
          rows: rows
              .map((row) {
                return DataRow(
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
                    DataCell(_DcCell(row: row)),
                    DataCell(Text('${_fmt(row.totalDispatchedWeightKg)} kg')),
                    DataCell(Text(_fmt(row.convertedUnits))),
                    DataCell(Text(_fmt(row.invoicedQuantity))),
                    DataCell(Text(row.gstin.isEmpty ? '-' : row.gstin)),
                    DataCell(Text(_money(row.cgst))),
                    DataCell(Text(_money(row.sgst))),
                    DataCell(Text('${_fmt(row.wastePercentage)}%')),
                    DataCell(_StatusBadge(row.status)),
                    DataCell(
                      row.isUnbilled
                          ? TextButton(
                              onPressed: () => onGenerateInvoice(row),
                              child: const Text('Generate Invoice'),
                            )
                          : const Text('-'),
                    ),
                  ],
                );
              })
              .toList(growable: false),
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
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            row.dcNumber,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            row.clientName,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: SoftErpTheme.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            row.itemName,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (row.isDirectPrint) ...[
            const SizedBox(height: 4),
            const _WarningBadge('Direct Print / Unlinked'),
          ],
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
  const _MiscTable({required this.rows});

  final List<WasteAuditRow> rows;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      primary: false,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(SoftErpTheme.cardSurfaceAlt),
        columns: const [
          DataColumn(label: Text('Audit Time')),
          DataColumn(label: Text('Client')),
          DataColumn(label: Text('Item')),
          DataColumn(label: Text('DC Number')),
          DataColumn(label: Text('Input Weight')),
          DataColumn(label: Text('Shipped Weight')),
          DataColumn(label: Text('Waste Weight')),
          DataColumn(label: Text('Waste %')),
          DataColumn(label: Text('Source')),
        ],
        rows: rows
            .map((row) {
              return DataRow(
                cells: [
                  DataCell(Text(_date(row.auditTime))),
                  DataCell(Text(row.clientName)),
                  DataCell(Text(row.itemName)),
                  DataCell(Text(row.challanNo)),
                  DataCell(Text('${_fmt(row.inputWeightKg)} kg')),
                  DataCell(Text('${_fmt(row.shippedWeightKg)} kg')),
                  DataCell(Text('${_fmt(row.wasteWeightKg)} kg')),
                  DataCell(Text('${_fmt(row.wastePercentage)}%')),
                  DataCell(Text(row.source)),
                ],
              );
            })
            .toList(growable: false),
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

String _prettyPayload(Object? value, [int indent = 0]) {
  final pad = '  ' * indent;
  if (value is Map) {
    final lines = value.entries
        .map((entry) {
          return '$pad${entry.key}: ${_prettyPayload(entry.value, indent + 1)}';
        })
        .join('\n');
    return '\n$lines';
  }
  if (value is List) {
    return value
        .map((item) => '\n$pad- ${_prettyPayload(item, indent + 1)}')
        .join();
  }
  return value?.toString() ?? 'null';
}
