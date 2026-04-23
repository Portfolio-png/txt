import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/shell/navigation_provider.dart';
import '../../../orders/domain/order_entry.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../providers/procurement_provider.dart';
import '../../domain/procurement_models.dart';

class ProcurementScreen extends StatefulWidget {
  const ProcurementScreen({super.key});

  @override
  State<ProcurementScreen> createState() => _ProcurementScreenState();
}

class _ProcurementScreenState extends State<ProcurementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<ProcurementProvider>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProcurementProvider>();
    return Container(
      color: const Color(0xFFF1F1F1),
      padding: const EdgeInsets.all(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8E8EF)),
        ),
        child: Column(
          children: [
            if (provider.errorMessage != null)
              Container(
                width: double.infinity,
                color: const Color(0xFFFFF3F3),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Text(
                  provider.errorMessage!,
                  style: const TextStyle(
                    color: Color(0xFF9C1C1C),
                    fontSize: 13,
                  ),
                ),
              ),
            const Expanded(child: _ProcurementTabs()),
          ],
        ),
      ),
    );
  }
}

class _ProcurementTabs extends StatelessWidget {
  const _ProcurementTabs();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Text(
                  'Procurement',
                  style: TextStyle(
                    color: Color(0xFF2F2F2F),
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Queue'),
              Tab(text: 'Requests'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [_ProcurementQueueTab(), _ProcurementRequestsTab()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProcurementQueueTab extends StatelessWidget {
  const _ProcurementQueueTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProcurementProvider>();
    final rows = provider.queueRows;
    final totalUncovered = rows.fold<double>(
      0,
      (sum, row) => sum + row.uncoveredQty,
    );
    final suppliers = rows.map((row) => row.supplierName).toSet().length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(label: 'Rows', value: rows.length.toString()),
              _MetricChip(label: 'Suppliers', value: suppliers.toString()),
              _MetricChip(
                label: 'Uncovered',
                value: _qty(totalUncovered),
                danger: totalUncovered > 0,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.icon(
                onPressed:
                    provider.selectedQueueKeys.isEmpty || provider.isSaving
                    ? null
                    : () async {
                        await context
                            .read<ProcurementProvider>()
                            .createDraftFromSelection();
                      },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create Draft Request'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: provider.isLoading
                    ? null
                    : () => provider.refreshQueue(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
              const Spacer(),
              Text(
                '${provider.selectedQueueKeys.length} selected',
                style: const TextStyle(color: Color(0xFF606779), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: rows.isEmpty
                ? const Center(
                    child: Text(
                      'No actionable shortages in queue.',
                      style: TextStyle(color: Color(0xFF737C8E), fontSize: 13),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBFCFF),
                      border: Border.all(color: const Color(0xFFE5E8F1)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: Color(0xFFE5E8F1)),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final selected = provider.isQueueSelected(row);
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          leading: Checkbox(
                            value: selected,
                            onChanged: (_) =>
                                provider.toggleQueueSelection(row),
                          ),
                          title: Text(
                            '${row.supplierName} • ${row.materialName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${row.materialBarcode} • ${row.affectedOrderCount} orders • due ${_dateLabel(row.earliestOrderEndDate)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: SizedBox(
                            width: 180,
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _MetricChip(
                                  label: 'Open',
                                  value: _qty(row.openRequestedQty),
                                ),
                                _MetricChip(
                                  label: 'Need',
                                  value: _qty(row.uncoveredQty),
                                  danger: row.uncoveredQty > 0,
                                ),
                              ],
                            ),
                          ),
                          onTap: () => provider.toggleQueueSelection(row),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProcurementRequestsTab extends StatelessWidget {
  const _ProcurementRequestsTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProcurementProvider>();
    final requests = provider.requests;
    final detail = provider.selectedRequest;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        children: [
          SizedBox(
            width: 380,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFBFCFF),
                border: Border.all(color: const Color(0xFFE5E8F1)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: requests.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No procurement requests yet.',
                          style: TextStyle(color: Color(0xFF737C8E)),
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: requests.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: Color(0xFFE5E8F1)),
                      itemBuilder: (context, index) {
                        final request = requests[index];
                        final selected = detail?.request.id == request.id;
                        return ListTile(
                          selected: selected,
                          selectedTileColor: const Color(0xFFEFF2FF),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                          title: Text(
                            '${request.requestNumber} • ${request.supplierName}',
                          ),
                          subtitle: Text(
                            '${request.lineCount} lines • ${_qty(request.totalReceivedQty)}/${_qty(request.totalRequestedQty)}',
                          ),
                          trailing: _StatusBadge(status: request.status),
                          onTap: () => provider.selectRequest(request.id),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: detail == null
                ? const Center(
                    child: Text(
                      'Select a request to view details.',
                      style: TextStyle(color: Color(0xFF737C8E)),
                    ),
                  )
                : _ProcurementRequestDetailView(detail: detail),
          ),
        ],
      ),
    );
  }
}

class _ProcurementRequestDetailView extends StatelessWidget {
  const _ProcurementRequestDetailView({required this.detail});

  final ProcurementRequestDetail detail;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProcurementProvider>();
    final request = detail.request;
    final canRaise = request.status == 'draft';
    final canEditMetadata =
        request.status == 'draft' ||
        request.status == 'raised' ||
        request.status == 'partially_received';
    final canReceive =
        request.status == 'raised' || request.status == 'partially_received';
    final canClose =
        request.status == 'partially_received' &&
        request.totalPendingQty <= 0.0001;
    final linkedOrderIds = <int>{
      for (final line in detail.lines) ...line.linkedOrderIds,
    }.toList(growable: false)..sort();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFF),
        border: Border.all(color: const Color(0xFFE5E8F1)),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                request.requestNumber,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              _StatusBadge(status: request.status),
              if (canRaise)
                FilledButton(
                  onPressed: provider.isSaving
                      ? null
                      : () => provider.raiseSelectedRequest(),
                  child: const Text('Raise'),
                ),
              if (canEditMetadata)
                OutlinedButton(
                  onPressed: provider.isSaving
                      ? null
                      : () => _showEditDraftDialog(context, request),
                  child: const Text('Edit Metadata'),
                ),
              if (canClose) ...[
                FilledButton(
                  onPressed: provider.isSaving
                      ? null
                      : () => provider.closeSelectedRequest(),
                  child: const Text('Close'),
                ),
              ],
              OutlinedButton(
                onPressed: provider.isSaving
                    ? null
                    : () => _showCancelDialog(context),
                child: const Text('Cancel'),
              ),
              if (canReceive)
                OutlinedButton(
                  onPressed: provider.isSaving
                      ? null
                      : () => _showReceiveDialog(context, detail.lines),
                  child: const Text('Receive Materials'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${request.supplierName} • Requested ${_qty(request.totalRequestedQty)} • Received ${_qty(request.totalReceivedQty)} • Pending ${_qty(request.totalPendingQty)}',
            style: const TextStyle(color: Color(0xFF61697A), fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(label: 'Lines', value: request.lineCount.toString()),
              _MetricChip(
                label: 'Linked Orders',
                value: linkedOrderIds.length.toString(),
              ),
              if (request.expectedDate != null &&
                  request.expectedDate!.isNotEmpty)
                _MetricChip(
                  label: 'Expected',
                  value: _dateLabel(request.expectedDate),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _DetailSectionCard(
                    title: 'Request Lines',
                    child: ListView.separated(
                      itemCount: detail.lines.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: Color(0xFFE5E8F1)),
                      itemBuilder: (context, index) {
                        final line = detail.lines[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${line.materialName} (${line.materialBarcode})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            'Req ${_qty(line.requestedQty)} • Rec ${_qty(line.receivedQty)} • Pending ${_qty(line.pendingQty)}',
                          ),
                          trailing: canReceive && line.pendingQty > 0
                              ? OutlinedButton(
                                  onPressed: provider.isSaving
                                      ? null
                                      : () => provider.receiveOnSelectedRequest(
                                          requestLineId: line.id,
                                          receivedQty: line.pendingQty,
                                        ),
                                  child: const Text('Receive All'),
                                )
                              : _StatusBadge(status: line.status),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      Expanded(
                        child: _DetailSectionCard(
                          title: 'Linked Orders',
                          child: linkedOrderIds.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No linked orders.',
                                    style: TextStyle(
                                      color: Color(0xFF737C8E),
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: linkedOrderIds.length,
                                  separatorBuilder: (_, _) => const Divider(
                                    height: 1,
                                    color: Color(0xFFE5E8F1),
                                  ),
                                  itemBuilder: (context, index) {
                                    final orderId = linkedOrderIds[index];
                                    final order = _findOrderById(
                                      context,
                                      orderId,
                                    );
                                    final title = order == null
                                        ? 'Order #$orderId'
                                        : '${order.orderNo} • ${order.clientName}';
                                    final subtitle = order == null
                                        ? 'Open in Orders'
                                        : '${order.itemName} • ${_statusLabel(order.status)}';
                                    return ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(
                                        Icons.receipt_long_outlined,
                                        size: 16,
                                        color: Color(0xFF636D85),
                                      ),
                                      title: Text(
                                        title,
                                        style: const TextStyle(fontSize: 12),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        subtitle,
                                        style: const TextStyle(
                                          color: Color(0xFF6B7280),
                                          fontSize: 11,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: 'Quick preview',
                                            visualDensity:
                                                VisualDensity.compact,
                                            icon: const Icon(
                                              Icons.visibility_outlined,
                                              size: 16,
                                              color: Color(0xFF6B7280),
                                            ),
                                            onPressed: () =>
                                                _showLinkedOrderQuickView(
                                                  context: context,
                                                  orderId: orderId,
                                                  order: order,
                                                ),
                                          ),
                                          const SizedBox(width: 2),
                                          const Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 16,
                                            color: Color(0xFF6C63FF),
                                          ),
                                        ],
                                      ),
                                      onTap: () => _goToOrder(
                                        context: context,
                                        orderId: orderId,
                                        order: order,
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: _DetailSectionCard(
                          title: 'Activity',
                          child: detail.activity.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No activity yet.',
                                    style: TextStyle(
                                      color: Color(0xFF737C8E),
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: detail.activity.length,
                                  separatorBuilder: (_, _) => const Divider(
                                    height: 1,
                                    color: Color(0xFFE5E8F1),
                                  ),
                                  itemBuilder: (context, index) {
                                    final event = detail.activity[index];
                                    return ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        event.title,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      subtitle: Text(
                                        '${event.actorName} • ${_dateLabel(event.createdAt)}',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  OrderEntry? _findOrderById(BuildContext context, int orderId) {
    final orders = context.read<OrdersProvider>().orders;
    for (final order in orders) {
      if (order.id == orderId) {
        return order;
      }
    }
    return null;
  }

  String _statusLabel(OrderStatus status) {
    return switch (status) {
      OrderStatus.draft => 'Draft',
      OrderStatus.confirmed => 'Confirmed',
      OrderStatus.allocated => 'Allocated',
      OrderStatus.inProduction => 'In Production',
      OrderStatus.completed => 'Completed',
      OrderStatus.dispatched => 'Dispatched',
      OrderStatus.closed => 'Closed',
      OrderStatus.onHold => 'On Hold',
      OrderStatus.cancelled => 'Cancelled',
    };
  }

  Future<void> _showLinkedOrderQuickView({
    required BuildContext context,
    required int orderId,
    required OrderEntry? order,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(order == null ? 'Order #$orderId' : order.orderNo),
        content: SizedBox(
          width: 420,
          child: order == null
              ? const Text(
                  'Order details are not loaded in memory yet. You can still jump directly to Orders.',
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _QuickRow(label: 'Client', value: order.clientName),
                    _QuickRow(label: 'Item', value: order.itemName),
                    _QuickRow(label: 'P.O. No.', value: order.poNumber),
                    _QuickRow(
                      label: 'Qty',
                      value: _qty(order.quantity.toDouble()),
                    ),
                    _QuickRow(
                      label: 'Status',
                      value: _statusLabel(order.status),
                    ),
                    _QuickRow(
                      label: 'Start',
                      value: _dateLabel(order.startDate?.toIso8601String()),
                    ),
                    _QuickRow(
                      label: 'End',
                      value: _dateLabel(order.endDate?.toIso8601String()),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _goToOrder(context: context, orderId: orderId, order: order);
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Open in Orders'),
          ),
        ],
      ),
    );
  }

  void _goToOrder({
    required BuildContext context,
    required int orderId,
    required OrderEntry? order,
  }) {
    final navigation = context.read<NavigationProvider>();
    final orders = context.read<OrdersProvider>();
    final query = (order?.orderNo.trim().isNotEmpty ?? false)
        ? order!.orderNo
        : orderId.toString();
    orders.focusOrderFromExternal(
      orderId: orderId,
      query: query,
      openDetails: true,
    );
    navigation.select('orders');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opened $query in Orders details'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showCancelDialog(BuildContext context) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Request'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Why is this request being cancelled?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) {
      return;
    }
    await context.read<ProcurementProvider>().cancelSelectedRequest(reason);
  }

  Future<void> _showEditDraftDialog(
    BuildContext context,
    ProcurementRequestSummary request,
  ) async {
    final dateController = TextEditingController(
      text: request.expectedDate?.split('T').first ?? '',
    );
    final notesController = TextEditingController(text: request.notes);
    final payload = await showDialog<({String? expectedDate, String? notes})>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Request Metadata'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: dateController,
                decoration: const InputDecoration(
                  labelText: 'Expected Date',
                  hintText: 'YYYY-MM-DD',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop((
              expectedDate: dateController.text.trim().isEmpty
                  ? null
                  : dateController.text.trim(),
              notes: notesController.text.trim(),
            )),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (payload == null) {
      return;
    }
    await context.read<ProcurementProvider>().updateSelectedRequest(
      expectedDate: payload.expectedDate,
      notes: payload.notes,
    );
  }

  Future<void> _showReceiveDialog(
    BuildContext context,
    List<ProcurementRequestLine> lines,
  ) async {
    final pendingLines = lines
        .where((line) => line.pendingQty > 0)
        .toList(growable: false);
    if (pendingLines.isEmpty) {
      return;
    }
    final controllers = <int, TextEditingController>{
      for (final line in pendingLines)
        line.id: TextEditingController(text: _qty(line.pendingQty)),
    };
    final payload = await showDialog<List<ProcurementReceiveLineInput>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Receive Materials'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final line in pendingLines) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          line.materialName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: controllers[line.id],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Qty',
                            helperText: 'max ${_qty(line.pendingQty)}',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () {
              final input = <ProcurementReceiveLineInput>[];
              for (final line in pendingLines) {
                final raw = double.tryParse(
                  controllers[line.id]?.text.trim() ?? '',
                );
                if (raw == null || raw <= 0) {
                  continue;
                }
                final qty = raw > line.pendingQty ? line.pendingQty : raw;
                input.add(
                  ProcurementReceiveLineInput(
                    requestLineId: line.id,
                    receivedQty: qty,
                  ),
                );
              }
              Navigator.of(context).pop(input);
            },
            child: const Text('Receive'),
          ),
        ],
      ),
    );
    if (payload == null || payload.isEmpty) {
      return;
    }
    await context.read<ProcurementProvider>().receiveOnSelectedRequestLines(
      lines: payload,
    );
  }
}

class _DetailSectionCard extends StatelessWidget {
  const _DetailSectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E8F1)),
        color: const Color(0xFFFBFCFF),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _QuickRow extends StatelessWidget {
  const _QuickRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '—' : value,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFB42318) : const Color(0xFF3F4A5E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: danger ? const Color(0xFFFFF4F2) : const Color(0xFFF5F7FB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: danger ? const Color(0xFFF1B5AE) : const Color(0xFFDEE4F0),
        ),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toLowerCase();
    final palette = switch (normalized) {
      'draft' => (const Color(0xFFEEF2FF), const Color(0xFF4F46E5)),
      'raised' => (const Color(0xFFE0F2FE), const Color(0xFF0369A1)),
      'partially_received' => (
        const Color(0xFFFFF4E5),
        const Color(0xFFB45309),
      ),
      'closed' => (const Color(0xFFECFDF3), const Color(0xFF047857)),
      'cancelled' => (const Color(0xFFFEF2F2), const Color(0xFFB91C1C)),
      _ => (const Color(0xFFF3F4F6), const Color(0xFF4B5563)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: palette.$1,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        normalized.replaceAll('_', ' '),
        style: TextStyle(
          color: palette.$2,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

String _qty(double value) {
  final rounded = value.roundToDouble();
  if ((value - rounded).abs() < 0.001) {
    return rounded.toInt().toString();
  }
  return value.toStringAsFixed(2);
}

String _dateLabel(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'N/A';
  }
  return value.split('T').first;
}
