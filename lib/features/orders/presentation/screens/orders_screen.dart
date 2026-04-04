import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../clients/domain/client_definition.dart';
import '../../../clients/presentation/providers/clients_provider.dart';
import '../../../items/domain/item_definition.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../domain/order_entry.dart';
import '../../domain/order_inputs.dart';
import '../providers/orders_provider.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  static Future<void> openEditor(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 900;
    final body = const _OrderEditorSheet();
    if (isNarrow) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: body,
        ),
      );
    }

    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: body,
        ),
      ),
    );
  }

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  static const double _contentHorizontalPadding = 18;
  final Set<int> _selectedOrderIds = <int>{};
  int? _partyFilterClientId;
  int? _itemFilterId;
  OrderStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final ordersProvider = context.watch<OrdersProvider>();
    final clients = context
        .watch<ClientsProvider>()
        .clients
        .where((client) => !client.isArchived)
        .toList(growable: false);
    final items = context
        .watch<ItemsProvider>()
        .items
        .where((item) => !item.isArchived)
        .toList(growable: false);
    final orders = ordersProvider.orders;
    final visibleOrders = _applyFilters(ordersProvider.filteredOrders);
    final summary = _OrderSummary.fromOrders(orders);

    _selectedOrderIds.removeWhere(
      (id) => !orders.any((order) => order.id == id),
    );

    return Container(
      color: const Color(0xFFF5F6FA),
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.fromLTRB(0, 14, 0, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _contentHorizontalPadding,
                      0,
                      _contentHorizontalPadding,
                      18,
                    ),
                    child: _OrdersHeader(
                      onNewOrder: () => OrdersScreen.openEditor(context),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _contentHorizontalPadding,
                    ),
                    child: _OrdersControlRow(
                      partyFilterClientId: _partyFilterClientId,
                      itemFilterId: _itemFilterId,
                      statusFilter: _statusFilter,
                      clients: clients,
                      items: items,
                      selectedCount: _selectedOrderIds.length,
                      onPartySelected: (value) {
                        setState(() {
                          _partyFilterClientId = value;
                        });
                      },
                      onItemSelected: (value) {
                        setState(() {
                          _itemFilterId = value;
                        });
                      },
                      onStatusSelected: (value) {
                        setState(() {
                          _statusFilter = value;
                        });
                      },
                      onClearSelection: () {
                        setState(_selectedOrderIds.clear);
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: Color(0xFFE9E9EE)),
                  const SizedBox(height: 18),
                  if (ordersProvider.errorMessage != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: _contentHorizontalPadding,
                      ),
                      child: _OrdersMessageBanner(
                        message: ordersProvider.errorMessage!,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _contentHorizontalPadding,
                    ),
                    child: _OrdersSummaryRow(
                      summary: summary,
                      activeStatus: _statusFilter,
                      onStatusSelected: (value) {
                        setState(() {
                          _statusFilter = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _OrdersTableCard(
                      orders: visibleOrders,
                      selectedOrderIds: _selectedOrderIds,
                      onToggleSelection: (orderId, selected) {
                        setState(() {
                          if (selected) {
                            _selectedOrderIds.add(orderId);
                          } else {
                            _selectedOrderIds.remove(orderId);
                          }
                        });
                      },
                      onRowTap: (order) => _openLifecycleEditor(context, order),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<OrderEntry> _applyFilters(List<OrderEntry> orders) {
    return orders
        .where((order) {
          if (_partyFilterClientId != null &&
              order.clientId != _partyFilterClientId) {
            return false;
          }
          if (_itemFilterId != null && order.itemId != _itemFilterId) {
            return false;
          }
          if (_statusFilter != null && order.status != _statusFilter) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  Future<void> _openLifecycleEditor(BuildContext context, OrderEntry order) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Order details',
      barrierColor: const Color(0x7D100D1F),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 12, right: 12, bottom: 12),
              child: SizedBox(
                height: double.infinity,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 757,
                    minWidth: 520,
                  ),
                  child: _OrderDetailsSheet(
                    order: order,
                    onEdit: () {
                      Navigator.of(context).pop();
                      Future<void>.microtask(() {
                        if (!mounted) {
                          return;
                        }
                        showDialog<void>(
                          context: this.context,
                          builder: (context) => Dialog(
                            insetPadding: const EdgeInsets.all(32),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: _OrderLifecycleEditorSheet(order: order),
                            ),
                          ),
                        );
                      });
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }
}

class _OrdersHeader extends StatelessWidget {
  const _OrdersHeader({required this.onNewOrder});

  final VoidCallback onNewOrder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = Text(
          'Order Book',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF3F3F3F),
          ),
        );
        final button = _OrdersPrimaryButton(
          key: const Key('orders-new-order-button'),
          label: 'New Order',
          onPressed: onNewOrder,
        );

        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: button),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: 16),
            button,
          ],
        );
      },
    );
  }
}

class _OrdersPrimaryButton extends StatelessWidget {
  const _OrdersPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: const Color(0xFF6C5AF3),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, size: 18),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrdersControlRow extends StatelessWidget {
  const _OrdersControlRow({
    required this.partyFilterClientId,
    required this.itemFilterId,
    required this.statusFilter,
    required this.clients,
    required this.items,
    required this.selectedCount,
    required this.onPartySelected,
    required this.onItemSelected,
    required this.onStatusSelected,
    required this.onClearSelection,
  });

  final int? partyFilterClientId;
  final int? itemFilterId;
  final OrderStatus? statusFilter;
  final List<ClientDefinition> clients;
  final List<ItemDefinition> items;
  final int selectedCount;
  final ValueChanged<int?> onPartySelected;
  final ValueChanged<int?> onItemSelected;
  final ValueChanged<OrderStatus?> onStatusSelected;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final filters = [
          _FilterChipButton<int?>(
            label: 'Party',
            valueLabel:
                clients
                        .where((client) => client.id == partyFilterClientId)
                        .firstOrNull
                        ?.alias
                        .trim()
                        .isNotEmpty ==
                    true
                ? clients
                      .where((client) => client.id == partyFilterClientId)
                      .first
                      .alias
                : 'All',
            isFirst: true,
            values: [
              const _MenuValue<int?>(value: null, label: 'All'),
              ...clients.map(
                (client) => _MenuValue<int?>(
                  value: client.id,
                  label: client.alias.isEmpty ? client.name : client.alias,
                ),
              ),
            ],
            onSelected: onPartySelected,
          ),
          _FilterChipButton<int?>(
            label: 'Item',
            valueLabel:
                items
                    .where((item) => item.id == itemFilterId)
                    .firstOrNull
                    ?.name ??
                'Anytime',
            values: [
              const _MenuValue<int?>(value: null, label: 'Anytime'),
              ...items.map(
                (item) => _MenuValue<int?>(value: item.id, label: item.name),
              ),
            ],
            onSelected: onItemSelected,
          ),
          _FilterChipButton<OrderStatus?>(
            label: 'Status',
            valueLabel: statusFilter?.label ?? 'All',
            isLast: true,
            values: [
              const _MenuValue<OrderStatus?>(value: null, label: 'All'),
              ...OrderStatus.values.map(
                (status) => _MenuValue<OrderStatus?>(
                  value: status,
                  label: status.label,
                ),
              ),
            ],
            onSelected: onStatusSelected,
          ),
        ];

        final trailing = Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            if (selectedCount > 0) ...[
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '$selectedCount Selected',
                  style: const TextStyle(
                    color: Color(0xFF5E6572),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              InkWell(
                onTap: onClearSelection,
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F4F7),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: Color(0xFF6A6A6A),
                  ),
                ),
              ),
            ],
            const _ActionChip(
              label: 'Newest',
              icon: Icons.keyboard_arrow_down_rounded,
            ),
            const _ActionChip(
              label: 'Filters',
              icon: Icons.filter_list_rounded,
            ),
          ],
        );

        if (constraints.maxWidth < 980) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 0, runSpacing: 8, children: filters),
              const SizedBox(height: 12),
              trailing,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: Wrap(spacing: 0, runSpacing: 8, children: filters)),
            const SizedBox(width: 12),
            trailing,
          ],
        );
      },
    );
  }
}

class _FilterChipButton<T> extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.valueLabel,
    required this.values,
    required this.onSelected,
    this.isFirst = false,
    this.isLast = false,
  });

  final String label;
  final String valueLabel;
  final List<_MenuValue<T>> values;
  final ValueChanged<T> onSelected;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => values
          .map(
            (entry) =>
                PopupMenuItem<T>(value: entry.value, child: Text(entry.label)),
          )
          .toList(growable: false),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFD8DDE7)),
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(isFirst ? 10 : 0),
            right: Radius.circular(isLast ? 10 : 0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isFirst) ...[
              const Icon(
                Icons.filter_alt_outlined,
                size: 15,
                color: Color(0xFF6A7280),
              ),
              const SizedBox(width: 7),
            ],
            Text(
              '$label: ',
              style: const TextStyle(
                color: Color(0xFF5F6775),
                fontFamily: 'Segoe UI',
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              valueLabel,
              style: const TextStyle(
                color: Color(0xFF1C2632),
                fontFamily: 'Segoe UI',
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: Color(0xFF6A7280),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF6A7280)),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF4F5561),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrdersSummaryRow extends StatelessWidget {
  const _OrdersSummaryRow({
    required this.summary,
    required this.activeStatus,
    required this.onStatusSelected,
  });

  final _OrderSummary summary;
  final OrderStatus? activeStatus;
  final ValueChanged<OrderStatus?> onStatusSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth >= 1100
            ? (constraints.maxWidth - 40) / 5
            : 220.0;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'All',
                value: summary.total,
                isActive: activeStatus == null,
                onTap: () => onStatusSelected(null),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'Not Started',
                value: summary.notStarted,
                isActive: activeStatus == OrderStatus.notStarted,
                onTap: () => onStatusSelected(OrderStatus.notStarted),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'In Progress',
                value: summary.inProgress,
                isActive: activeStatus == OrderStatus.inProgress,
                onTap: () => onStatusSelected(OrderStatus.inProgress),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'Completed',
                value: summary.completed,
                isActive: activeStatus == OrderStatus.completed,
                onTap: () => onStatusSelected(OrderStatus.completed),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'Delayed',
                value: summary.delayed,
                isActive: activeStatus == OrderStatus.delayed,
                onTap: () => onStatusSelected(OrderStatus.delayed),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final int value;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFFCFAFF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? const Color(0xFF7B61FF) : const Color(0xFFE4E7EE),
            width: isActive ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF474747),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 72),
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFFF5F2FF)
                    : const Color(0xFFFCFCFE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$value',
                style: const TextStyle(
                  color: Color(0xFF303030),
                  fontSize: 17,
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

class _OrdersTableCard extends StatelessWidget {
  const _OrdersTableCard({
    required this.orders,
    required this.selectedOrderIds,
    required this.onToggleSelection,
    required this.onRowTap,
  });

  final List<OrderEntry> orders;
  final Set<int> selectedOrderIds;
  final void Function(int orderId, bool selected) onToggleSelection;
  final ValueChanged<OrderEntry> onRowTap;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const AppEmptyState(
        title: 'No orders found',
        message:
            'Try a different filter or create a new order to populate the order book.',
        icon: Icons.receipt_long_outlined,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth > _OrdersTableMetrics.totalWidth
              ? constraints.maxWidth
              : _OrdersTableMetrics.totalWidth;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Column(
                children: [
                  _TableHeaderRow(),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: orders.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final order = orders[index];
                        return _OrderDataRow(
                          order: order,
                          isSelected: selectedOrderIds.contains(order.id),
                          isStriped: index.isOdd,
                          onSelectionChanged: (selected) =>
                              onToggleSelection(order.id, selected),
                          onTap: () => onRowTap(order),
                        );
                      },
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

class _TableHeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(
        horizontal: _OrdersTableMetrics.horizontalPadding,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F2FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          _HeaderCell('Order ID', width: _OrdersTableMetrics.orderIdWidth),
          _HeaderCell('Date', width: _OrdersTableMetrics.dateWidth),
          _HeaderCell('Party', width: _OrdersTableMetrics.partyWidth),
          _HeaderCell('Item', width: _OrdersTableMetrics.itemWidth),
          _HeaderCell(
            'Purchase Order Number',
            width: _OrdersTableMetrics.poWidth,
          ),
          _HeaderCell(
            'Order Quantity',
            width: _OrdersTableMetrics.quantityWidth,
          ),
          _HeaderCell('Start Date', width: _OrdersTableMetrics.startDateWidth),
          _HeaderCell('End Date', width: _OrdersTableMetrics.endDateWidth),
          _HeaderCell('Status', width: _OrdersTableMetrics.statusWidth),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF616779),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _OrderDataRow extends StatelessWidget {
  const _OrderDataRow({
    required this.order,
    required this.isSelected,
    required this.isStriped,
    required this.onSelectionChanged,
    required this.onTap,
  });

  final OrderEntry order;
  final bool isSelected;
  final bool isStriped;
  final ValueChanged<bool> onSelectionChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => onSelectionChanged(!isSelected),
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 48,
          child: Ink(
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFF5F2FF)
                  : isStriped
                  ? const Color(0xFFFBFBFD)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _OrdersTableMetrics.horizontalPadding,
              ),
              child: Row(
                children: [
                  _DataCell(
                    order.orderNo,
                    width: _OrdersTableMetrics.orderIdWidth,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  _DataCell(
                    _formatDate(order.createdAt),
                    width: _OrdersTableMetrics.dateWidth,
                  ),
                  _DataCell(
                    order.clientName,
                    width: _OrdersTableMetrics.partyWidth,
                    overflow: TextOverflow.ellipsis,
                  ),
                  _DataCell(
                    order.variationPathLabel.isEmpty ||
                            order.variationPathLabel == order.itemName
                        ? order.itemName
                        : '${order.itemName} · ${order.variationPathLabel}',
                    width: _OrdersTableMetrics.itemWidth,
                    overflow: TextOverflow.ellipsis,
                  ),
                  _DataCell(
                    order.poNumber.isEmpty ? '—' : order.poNumber,
                    width: _OrdersTableMetrics.poWidth,
                  ),
                  _DataCell(
                    '${order.quantity} Pieces',
                    width: _OrdersTableMetrics.quantityWidth,
                  ),
                  _DataCell(
                    _formatDate(order.startDate),
                    width: _OrdersTableMetrics.startDateWidth,
                  ),
                  _DataCell(
                    _formatDate(order.endDate),
                    width: _OrdersTableMetrics.endDateWidth,
                  ),
                  SizedBox(
                    width: _OrdersTableMetrics.statusWidth,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _StatusPill(status: order.status),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '—';
    }
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day-$month-${value.year}';
  }
}

class _DataCell extends StatelessWidget {
  const _DataCell(
    this.text, {
    required this.width,
    this.style,
    this.overflow = TextOverflow.clip,
  });

  final String text;
  final double width;
  final TextStyle? style;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        softWrap: false,
        maxLines: 1,
        overflow: overflow,
        style: const TextStyle(
          color: Color(0xFF3C3C3C),
          fontSize: 13,
        ).merge(style),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = switch (status) {
      OrderStatus.notStarted => (
        bg: const Color(0xFFFDF5F0),
        border: const Color(0xFFF8DBB9),
        text: const Color(0xFF824C00),
      ),
      OrderStatus.inProgress => (
        bg: const Color(0xFFF0F6FD),
        border: const Color(0xFFB9CFF8),
        text: const Color(0xFF003BFB),
      ),
      OrderStatus.completed => (
        bg: const Color(0xFFEFFBF2),
        border: const Color(0xFFB5E5C0),
        text: const Color(0xFF007D30),
      ),
      OrderStatus.delayed => (
        bg: const Color(0xFFFDF0F0),
        border: const Color(0xFFFF8C8C),
        text: const Color(0xFFDC0000),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.border),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: scheme.text,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _OrdersTableMetrics {
  static const double horizontalPadding = 18;
  static const double orderIdWidth = 112;
  static const double dateWidth = 124;
  static const double partyWidth = 190;
  static const double itemWidth = 242;
  static const double poWidth = 198;
  static const double quantityWidth = 150;
  static const double startDateWidth = 136;
  static const double endDateWidth = 136;
  static const double statusWidth = 116;

  static const double totalWidth =
      horizontalPadding * 2 +
      orderIdWidth +
      dateWidth +
      partyWidth +
      itemWidth +
      poWidth +
      quantityWidth +
      startDateWidth +
      endDateWidth +
      statusWidth;
}

class _OrderEditorSheet extends StatefulWidget {
  const _OrderEditorSheet();

  @override
  State<_OrderEditorSheet> createState() => _OrderEditorSheetState();
}

class _OrderEditorSheetState extends State<_OrderEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _orderNoController;
  late final TextEditingController _poNumberController;
  late final TextEditingController _clientCodeController;
  late final TextEditingController _quantityController;
  late final TextEditingController _startDateController;
  late final TextEditingController _endDateController;

  int? _selectedClientId;
  int? _selectedItemId;
  final Map<String, int> _selectionState = <String, int>{};
  OrderStatus _selectedStatus = OrderStatus.notStarted;
  DateTime? _startDate;
  DateTime? _endDate;

  String? get _clientCodeError {
    final text = _clientCodeController.text.trim();
    if (_selectedClientId == null) {
      return null;
    }
    if (text.isEmpty) {
      return 'Selected client has no client code in master.';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _orderNoController = TextEditingController();
    _poNumberController = TextEditingController();
    _clientCodeController = TextEditingController();
    _quantityController = TextEditingController(text: '1');
    _startDateController = TextEditingController();
    _endDateController = TextEditingController();
  }

  @override
  void dispose() {
    _orderNoController.dispose();
    _poNumberController.dispose();
    _clientCodeController.dispose();
    _quantityController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clients = context
        .watch<ClientsProvider>()
        .clients
        .where((client) => !client.isArchived)
        .toList(growable: false);
    final items = context
        .watch<ItemsProvider>()
        .items
        .where((item) => !item.isArchived)
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Add Order',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Client Code is pulled automatically from the selected client master alias, and orders store both the item and its exact variation.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 24),
              if (clients.isEmpty || items.isEmpty)
                _DependencyMessage(
                  hasClients: clients.isNotEmpty,
                  hasItems: items.isNotEmpty,
                )
              else ...[
                TextFormField(
                  controller: _orderNoController,
                  decoration: _inputDecoration('Order No.'),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Enter an order number.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _selectedClientId,
                  decoration: _inputDecoration('Client'),
                  items: clients
                      .map(
                        (client) => DropdownMenuItem<int>(
                          value: client.id,
                          child: Text(client.displayLabel),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    setState(() {
                      _selectedClientId = value;
                      final selected = _selectedClient(clients);
                      _clientCodeController.text = _resolveClientCode(selected);
                    });
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Select a client.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _poNumberController,
                  decoration: _inputDecoration('P.O. No.'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _clientCodeController,
                  readOnly: true,
                  decoration: _inputDecoration(
                    'Client Code',
                    errorText: _clientCodeError,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _selectedItemId,
                  decoration: _inputDecoration('Item'),
                  items: items
                      .map(
                        (item) => DropdownMenuItem<int>(
                          value: item.id,
                          child: Text(item.displayName),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    setState(() {
                      _selectedItemId = value;
                      _selectionState.clear();
                    });
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Select an item.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                ..._buildVariationSelectors(items),
                TextFormField(
                  controller: _quantityController,
                  decoration: _inputDecoration('Qty'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final quantity = int.tryParse((value ?? '').trim());
                    if (quantity == null || quantity <= 0) {
                      return 'Enter a valid quantity.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<OrderStatus>(
                  initialValue: _selectedStatus,
                  decoration: _inputDecoration('Status'),
                  items: OrderStatus.values
                      .map(
                        (status) => DropdownMenuItem<OrderStatus>(
                          value: status,
                          child: Text(status.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _selectedStatus = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _DateField(
                        label: 'Start Date',
                        controller: _startDateController,
                        onTap: () => _pickDate(
                          context,
                          initial: _startDate ?? DateTime.now(),
                          onSelected: (value) {
                            setState(() {
                              _startDate = value;
                              _startDateController.text = _formatDate(value);
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _DateField(
                        label: 'End Date',
                        controller: _endDateController,
                        onTap: () => _pickDate(
                          context,
                          initial: _endDate ?? _startDate ?? DateTime.now(),
                          onSelected: (value) {
                            setState(() {
                              _endDate = value;
                              _endDateController.text = _formatDate(value);
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  AppButton(
                    label: 'Create Order',
                    onPressed: clients.isEmpty || items.isEmpty
                        ? null
                        : () => _submit(context, clients, items),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit(
    BuildContext context,
    List<ClientDefinition> clients,
    List<ItemDefinition> items,
  ) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final selectedClient = _selectedClient(clients);
    final selectedItem = _selectedItem(items);
    final selectedLeaf = _selectedLeafValue(selectedItem);
    if (selectedClient == null ||
        selectedItem == null ||
        selectedLeaf == null) {
      return;
    }
    final clientCode = _resolveClientCode(selectedClient);
    if (clientCode.isEmpty) {
      setState(() {});
      return;
    }

    final result = await context.read<OrdersProvider>().createOrder(
      CreateOrderInput(
        orderNo: _orderNoController.text,
        clientId: selectedClient.id,
        clientName: selectedClient.name,
        poNumber: _poNumberController.text,
        clientCode: clientCode,
        itemId: selectedItem.id,
        itemName: selectedItem.displayName,
        variationLeafNodeId: selectedLeaf.id,
        variationPathLabel: selectedLeaf.displayName,
        variationPathNodeIds: _selectedPathNodeIds(selectedLeaf),
        quantity: int.parse(_quantityController.text.trim()),
        status: _selectedStatus,
        startDate: _startDate,
        endDate: _endDate,
      ),
    );

    if (!context.mounted) {
      return;
    }

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order created successfully.')),
      );
      Navigator.of(context).pop();
      return;
    }

    final message =
        context.read<OrdersProvider>().errorMessage ??
        'Unable to create order. Please try again.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  ClientDefinition? _selectedClient(List<ClientDefinition> clients) {
    for (final client in clients) {
      if (client.id == _selectedClientId) {
        return client;
      }
    }
    return null;
  }

  ItemDefinition? _selectedItem(List<ItemDefinition> items) {
    for (final item in items) {
      if (item.id == _selectedItemId) {
        return item;
      }
    }
    return null;
  }

  List<Widget> _buildVariationSelectors(List<ItemDefinition> items) {
    final selectedItem = _selectedItem(items);
    if (selectedItem == null) {
      return [
        DropdownButtonFormField<int>(
          initialValue: null,
          decoration: _inputDecoration('Variation Path'),
          items: const [],
          onChanged: null,
          validator: (value) {
            if (value == null) {
              return 'Select an item first.';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
      ];
    }

    final steps = _buildSelectionSteps(selectedItem);
    if (steps.isEmpty) {
      return [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF4C98B)),
          ),
          child: const Text(
            'This item does not have any active orderable leaf paths yet.',
          ),
        ),
        const SizedBox(height: 16),
      ];
    }

    final widgets = <Widget>[];
    for (var index = 0; index < steps.length; index++) {
      final step = steps[index];
      widgets.add(
        DropdownButtonFormField<int>(
          initialValue: step.selectedId,
          decoration: _inputDecoration(step.label),
          items: step.options
              .map(
                (node) => DropdownMenuItem<int>(
                  value: node.id,
                  child: Text(node.name),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            setState(() {
              if (value == null) {
                _selectionState.remove(step.stateKey);
              } else {
                _selectionState[step.stateKey] = value;
              }
              _clearSelectionAfter(steps, index);
            });
          },
          validator: (value) {
            if (step.required && value == null) {
              return 'Select ${step.label.toLowerCase()}.';
            }
            return null;
          },
        ),
      );
      widgets.add(const SizedBox(height: 16));
    }
    final selectedLeaf = _selectedLeafValue(selectedItem);
    if (selectedLeaf != null) {
      widgets.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Text('Selected Path: ${selectedLeaf.displayName}'),
        ),
      );
      widgets.add(const SizedBox(height: 16));
    }
    return widgets;
  }

  List<_OrderSelectionStep> _buildSelectionSteps(ItemDefinition item) {
    final steps = <_OrderSelectionStep>[];
    List<ItemVariationNodeDefinition> propertyOptions = item.topLevelProperties;
    String branchKey = 'root';
    while (propertyOptions.isNotEmpty) {
      ItemVariationNodeDefinition propertyNode;
      if (propertyOptions.length > 1) {
        final propertySelectionKey = 'property:$branchKey';
        final selectedPropertyId = _selectionState[propertySelectionKey];
        steps.add(
          _OrderSelectionStep(
            label: 'Property Group',
            stateKey: propertySelectionKey,
            selectedId:
                propertyOptions.any((node) => node.id == selectedPropertyId)
                ? selectedPropertyId
                : null,
            options: propertyOptions,
            required: true,
          ),
        );
        propertyNode =
            propertyOptions
                .where((node) => node.id == selectedPropertyId)
                .firstOrNull ??
            propertyOptions.first;
        if (selectedPropertyId == null) {
          break;
        }
      } else {
        propertyNode = propertyOptions.first;
      }

      final valueSelectionKey = 'value:${propertyNode.id}';
      final valueOptions = propertyNode.activeChildren
          .where((node) => node.kind == ItemVariationNodeKind.value)
          .toList(growable: false);
      final selectedValueId = _selectionState[valueSelectionKey];
      steps.add(
        _OrderSelectionStep(
          label: propertyNode.name,
          stateKey: valueSelectionKey,
          selectedId: valueOptions.any((node) => node.id == selectedValueId)
              ? selectedValueId
              : null,
          options: valueOptions,
          required: true,
        ),
      );
      final selectedValue = valueOptions
          .where((node) => node.id == selectedValueId)
          .firstOrNull;
      if (selectedValue == null) {
        break;
      }
      propertyOptions = selectedValue.activeChildren
          .where((node) => node.kind == ItemVariationNodeKind.property)
          .toList(growable: false);
      branchKey = selectedValue.id.toString();
    }
    return steps;
  }

  void _clearSelectionAfter(List<_OrderSelectionStep> steps, int index) {
    for (var cursor = index + 1; cursor < steps.length; cursor++) {
      _selectionState.remove(steps[cursor].stateKey);
    }
  }

  ItemVariationNodeDefinition? _selectedLeafValue(ItemDefinition? item) {
    if (item == null) {
      return null;
    }
    List<ItemVariationNodeDefinition> propertyOptions = item.topLevelProperties;
    var branchKey = 'root';
    while (propertyOptions.isNotEmpty) {
      ItemVariationNodeDefinition propertyNode;
      if (propertyOptions.length > 1) {
        final propertySelection = _selectionState['property:$branchKey'];
        propertyNode =
            propertyOptions
                .where((node) => node.id == propertySelection)
                .firstOrNull ??
            propertyOptions.first;
        if (propertySelection == null) {
          return null;
        }
      } else {
        propertyNode = propertyOptions.first;
      }
      final selectedValueId = _selectionState['value:${propertyNode.id}'];
      final selectedValue = propertyNode.activeChildren
          .where((node) => node.kind == ItemVariationNodeKind.value)
          .where((node) => node.id == selectedValueId)
          .firstOrNull;
      if (selectedValue == null) {
        return null;
      }
      final nextProperties = selectedValue.activeChildren
          .where((node) => node.kind == ItemVariationNodeKind.property)
          .toList(growable: false);
      if (nextProperties.isEmpty) {
        return selectedValue;
      }
      propertyOptions = nextProperties;
      branchKey = selectedValue.id.toString();
    }
    return null;
  }

  List<int> _selectedPathNodeIds(ItemVariationNodeDefinition leaf) {
    final path = <int>[];

    void visit(ItemVariationNodeDefinition node, List<int> current) {
      final next = [...current, node.id];
      if (node.id == leaf.id) {
        path
          ..clear()
          ..addAll(next);
        return;
      }
      for (final child in node.children) {
        visit(child, next);
      }
    }

    final item = _selectedItem(
      context
          .read<ItemsProvider>()
          .items
          .where((entry) => !entry.isArchived)
          .toList(growable: false),
    );
    if (item != null) {
      for (final root in item.variationTree) {
        visit(root, const []);
      }
    }
    return path;
  }

  String _resolveClientCode(ClientDefinition? client) {
    return client?.alias.trim() ?? '';
  }

  InputDecoration _inputDecoration(String label, {String? errorText}) {
    return InputDecoration(
      labelText: label,
      errorText: errorText,
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
      ),
    );
  }

  Future<void> _pickDate(
    BuildContext context, {
    required DateTime initial,
    required ValueChanged<DateTime> onSelected,
  }) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (picked != null) {
      onSelected(picked);
    }
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day-$month-${value.year}';
  }
}

class _OrderLifecycleEditorSheet extends StatefulWidget {
  const _OrderLifecycleEditorSheet({required this.order});

  final OrderEntry order;

  @override
  State<_OrderLifecycleEditorSheet> createState() =>
      _OrderLifecycleEditorSheetState();
}

class _OrderLifecycleEditorSheetState
    extends State<_OrderLifecycleEditorSheet> {
  late OrderStatus _status;
  late final TextEditingController _startDateController;
  late final TextEditingController _endDateController;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _status = widget.order.status;
    _startDate = widget.order.startDate;
    _endDate = widget.order.endDate;
    _startDateController = TextEditingController(
      text: _startDate == null ? '' : _formatDate(_startDate!),
    );
    _endDateController = TextEditingController(
      text: _endDate == null ? '' : _formatDate(_endDate!),
    );
  }

  @override
  void dispose() {
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Update Order',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.order.orderNo} • ${widget.order.clientName}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7280)),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<OrderStatus>(
            initialValue: _status,
            decoration: const InputDecoration(
              labelText: 'Status',
              filled: true,
              fillColor: Color(0xFFF9FAFB),
            ),
            items: OrderStatus.values
                .map(
                  (status) => DropdownMenuItem<OrderStatus>(
                    value: status,
                    child: Text(status.label),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _status = value;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _DateField(
                  label: 'Start Date',
                  controller: _startDateController,
                  onTap: () => _pickDate(
                    context,
                    initial: _startDate ?? widget.order.createdAt,
                    onSelected: (value) {
                      setState(() {
                        _startDate = value;
                        _startDateController.text = _formatDate(value);
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _DateField(
                  label: 'End Date',
                  controller: _endDateController,
                  onTap: () => _pickDate(
                    context,
                    initial: _endDate ?? _startDate ?? widget.order.createdAt,
                    onSelected: (value) {
                      setState(() {
                        _endDate = value;
                        _endDateController.text = _formatDate(value);
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: 'Close',
                variant: AppButtonVariant.secondary,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 12),
              AppButton(
                label: 'Save',
                onPressed: () async {
                  final result = await context
                      .read<OrdersProvider>()
                      .updateOrderLifecycle(
                        UpdateOrderLifecycleInput(
                          id: widget.order.id,
                          status: _status,
                          startDate: _startDate,
                          endDate: _endDate,
                        ),
                      );
                  if (!context.mounted) {
                    return;
                  }

                  if (result != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Order updated successfully.'),
                      ),
                    );
                    Navigator.of(context).pop();
                    return;
                  }

                  final message =
                      context.read<OrdersProvider>().errorMessage ??
                      'Unable to update order. Please try again.';
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(message)));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(
    BuildContext context, {
    required DateTime initial,
    required ValueChanged<DateTime> onSelected,
  }) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (picked != null) {
      onSelected(picked);
    }
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day-$month-${value.year}';
  }
}

class _OrderDetailsSheet extends StatelessWidget {
  const _OrderDetailsSheet({required this.order, required this.onEdit});

  final OrderEntry order;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final detailRows = <({String label, String value})>[
      (label: 'Order Code', value: order.orderNo),
      (label: 'Purchase order no.', value: _emptyFallback(order.poNumber)),
      (label: 'Item', value: order.itemName),
      (label: 'Purchase order item Code', value: '—'),
      (label: 'Quantity / Unit', value: '${order.quantity} Pieces'),
      (label: 'Start Date', value: _formatDate(order.startDate)),
      (label: 'Estimated completion date', value: _formatDate(order.endDate)),
    ];

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            bottomLeft: Radius.circular(16),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Container(
              height: 60,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: const BoxDecoration(
                color: Color(0xFFFBFBFB),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(16)),
              ),
              alignment: Alignment.centerLeft,
              child: const Text(
                'Order Details',
                style: TextStyle(
                  color: Color(0xFF3F3F3F),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.only(bottom: 24),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFEDEDED)),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: detailRows
                              .map(
                                (entry) => Padding(
                                  padding: const EdgeInsets.only(bottom: 18),
                                  child: SizedBox(
                                    width: 360,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: 220,
                                          child: Text(
                                            entry.label,
                                            style: const TextStyle(
                                              color: Color(0xFF888888),
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            entry.value,
                                            style: const TextStyle(
                                              color: Color(0xFF282828),
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 360,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 220,
                              child: Text(
                                'Status',
                                style: TextStyle(
                                  color: Color(0xFF888888),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Flexible(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _StatusPill(status: order.status),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEDEDED))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  _OrderDetailActionButton(label: 'Edit', onPressed: onEdit),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _emptyFallback(String value) {
    return value.trim().isEmpty ? '—' : value;
  }

  static String _formatDate(DateTime? value) {
    if (value == null) {
      return '—';
    }
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day-$month-${value.year}';
  }
}

class _OrderDetailActionButton extends StatelessWidget {
  const _OrderDetailActionButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: const Color(0xFF6049E3),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

class _OrdersMessageBanner extends StatelessWidget {
  const _OrdersMessageBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1B8AE)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFC2410C),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF9A3412),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.controller,
    required this.onTap,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
        ),
      ),
    );
  }
}

class _DependencyMessage extends StatelessWidget {
  const _DependencyMessage({required this.hasClients, required this.hasItems});

  final bool hasClients;
  final bool hasItems;

  @override
  Widget build(BuildContext context) {
    final missing = <String>[
      if (!hasClients) 'at least one active client',
      if (!hasItems) 'at least one active item',
    ].join(' and ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF4C98B)),
      ),
      child: Text(
        'Orders need $missing before a record can be created.',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF9A5B13)),
      ),
    );
  }
}

class _OrderSelectionStep {
  const _OrderSelectionStep({
    required this.label,
    required this.stateKey,
    required this.selectedId,
    required this.options,
    required this.required,
  });

  final String label;
  final String stateKey;
  final int? selectedId;
  final List<ItemVariationNodeDefinition> options;
  final bool required;
}

class _OrderSummary {
  const _OrderSummary({
    required this.total,
    required this.notStarted,
    required this.inProgress,
    required this.completed,
    required this.delayed,
  });

  final int total;
  final int notStarted;
  final int inProgress;
  final int completed;
  final int delayed;

  factory _OrderSummary.fromOrders(List<OrderEntry> orders) {
    var notStarted = 0;
    var inProgress = 0;
    var completed = 0;
    var delayed = 0;

    for (final order in orders) {
      switch (order.status) {
        case OrderStatus.notStarted:
          notStarted += 1;
        case OrderStatus.inProgress:
          inProgress += 1;
        case OrderStatus.completed:
          completed += 1;
        case OrderStatus.delayed:
          delayed += 1;
      }
    }

    return _OrderSummary(
      total: orders.length,
      notStarted: notStarted,
      inProgress: inProgress,
      completed: completed,
      delayed: delayed,
    );
  }
}

class _MenuValue<T> {
  const _MenuValue({required this.value, required this.label});

  final T value;
  final String label;
}

extension on OrderStatus {
  String get label {
    return switch (this) {
      OrderStatus.notStarted => 'Not Started',
      OrderStatus.inProgress => 'In Progress',
      OrderStatus.completed => 'Completed',
      OrderStatus.delayed => 'Delayed',
    };
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
