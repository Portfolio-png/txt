import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/searchable_select.dart';
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
          constraints: const BoxConstraints(maxWidth: 847, maxHeight: 680),
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
  OrderStatus? _timelineStatusFilter;
  _OrdersView _activeView = _OrdersView.table;

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
    _handleExternalOrderFocus(
      provider: ordersProvider,
      allOrders: orders,
      visibleOrders: visibleOrders,
    );

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
                borderRadius: BorderRadius.circular(10),
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
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _contentHorizontalPadding,
                    ),
                    child: _OrdersViewSwitcher(
                      selectedView: _activeView,
                      onViewChanged: (value) {
                        setState(() {
                          _activeView = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _OrdersViewContent(
                      activeView: _activeView,
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
                      onBoardMove: (order, toStatus) =>
                          _moveOrderFromBoard(order, toStatus),
                      timelineStatusFilter: _timelineStatusFilter,
                      onTimelineStatusFilterChanged: (value) {
                        setState(() {
                          _timelineStatusFilter = value;
                        });
                      },
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

  void _handleExternalOrderFocus({
    required OrdersProvider provider,
    required List<OrderEntry> allOrders,
    required List<OrderEntry> visibleOrders,
  }) {
    final focusedOrderId = provider.focusedOrderId;
    if (focusedOrderId == null) {
      return;
    }
    final shouldOpenDetails = provider.openFocusedOrderDetails;
    provider.clearExternalOrderFocus();
    OrderEntry? target;
    for (final order in allOrders) {
      if (order.id == focusedOrderId) {
        target = order;
        break;
      }
    }
    if (target == null || !mounted) {
      return;
    }
    final isVisible = visibleOrders.any((order) => order.id == focusedOrderId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (isVisible) {
        setState(() {
          _selectedOrderIds
            ..clear()
            ..add(focusedOrderId);
        });
      }
      if (shouldOpenDetails) {
        _openLifecycleEditor(context, target!);
      }
    });
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

  Future<void> _moveOrderFromBoard(
    OrderEntry order,
    OrderStatus toStatus,
  ) async {
    final action = _actionForBoardMove(from: order.status, to: toStatus);
    if (action == null) {
      return;
    }
    final result = await context.read<OrdersProvider>().transitionOrderByAction(
      orderId: order.id,
      action: action,
    );
    if (!mounted) {
      return;
    }
    if (result == null) {
      final message =
          context.read<OrdersProvider>().errorMessage ??
          'Unable to move order right now.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Order moved to ${toStatus.label}.')),
    );
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
    return InkWell(
      borderRadius: BorderRadius.horizontal(
        left: Radius.circular(isFirst ? 10 : 0),
        right: Radius.circular(isLast ? 10 : 0),
      ),
      onTap: () async {
        final selected = await showSearchableSelectDialog<T>(
          context: context,
          title: label,
          searchHintText: 'Search $label',
          options: values
              .map(
                (entry) => SearchableSelectOption<T>(
                  value: entry.value,
                  label: entry.label,
                ),
              )
              .toList(growable: false),
        );
        if (selected != null) {
          onSelected(selected.value);
        }
      },
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
          mainAxisSize: MainAxisSize.max,
          children: [
            if (isFirst) ...[
              const Icon(
                Icons.filter_alt_outlined,
                size: 15,
                color: Color(0xFF6A7280),
              ),
              const SizedBox(width: 7),
            ],
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                '$label: ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF5F6775),
                  fontFamily: 'Segoe UI',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Flexible(
              child: Text(
                valueLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF1C2632),
                  fontFamily: 'Segoe UI',
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
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
    const cardWidth = 220.0;
    return SizedBox(
      height: 66,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
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
            const SizedBox(width: 12),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'Draft',
                value: summary.draft,
                isActive: activeStatus == OrderStatus.draft,
                onTap: () => onStatusSelected(OrderStatus.draft),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'Confirmed',
                value: summary.confirmed,
                isActive: activeStatus == OrderStatus.confirmed,
                onTap: () => onStatusSelected(OrderStatus.confirmed),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'In Production',
                value: summary.inProduction,
                isActive: activeStatus == OrderStatus.inProduction,
                onTap: () => onStatusSelected(OrderStatus.inProduction),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'Completed',
                value: summary.completed,
                isActive: activeStatus == OrderStatus.completed,
                onTap: () => onStatusSelected(OrderStatus.completed),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'On Hold',
                value: summary.onHold,
                isActive: activeStatus == OrderStatus.onHold,
                onTap: () => onStatusSelected(OrderStatus.onHold),
              ),
            ),
          ],
        ),
      ),
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

enum _OrdersView { priority, board, timeline, table }

class _OrdersViewSwitcher extends StatelessWidget {
  const _OrdersViewSwitcher({
    required this.selectedView,
    required this.onViewChanged,
  });

  final _OrdersView selectedView;
  final ValueChanged<_OrdersView> onViewChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_OrdersView>(
      showSelectedIcon: false,
      segments: const <ButtonSegment<_OrdersView>>[
        ButtonSegment<_OrdersView>(
          value: _OrdersView.priority,
          label: Text('Priority'),
          icon: Icon(Icons.priority_high_rounded, size: 16),
        ),
        ButtonSegment<_OrdersView>(
          value: _OrdersView.board,
          label: Text('Board'),
          icon: Icon(Icons.view_kanban_outlined, size: 16),
        ),
        ButtonSegment<_OrdersView>(
          value: _OrdersView.timeline,
          label: Text('Timeline'),
          icon: Icon(Icons.schedule_outlined, size: 16),
        ),
        ButtonSegment<_OrdersView>(
          value: _OrdersView.table,
          label: Text('Table'),
          icon: Icon(Icons.table_rows_outlined, size: 16),
        ),
      ],
      selected: <_OrdersView>{selectedView},
      onSelectionChanged: (selected) {
        if (selected.isNotEmpty) {
          onViewChanged(selected.first);
        }
      },
    );
  }
}

class _OrdersViewContent extends StatelessWidget {
  const _OrdersViewContent({
    required this.activeView,
    required this.orders,
    required this.selectedOrderIds,
    required this.onToggleSelection,
    required this.onRowTap,
    required this.onBoardMove,
    required this.timelineStatusFilter,
    required this.onTimelineStatusFilterChanged,
  });

  final _OrdersView activeView;
  final List<OrderEntry> orders;
  final Set<int> selectedOrderIds;
  final void Function(int orderId, bool selected) onToggleSelection;
  final ValueChanged<OrderEntry> onRowTap;
  final Future<void> Function(OrderEntry order, OrderStatus toStatus)
  onBoardMove;
  final OrderStatus? timelineStatusFilter;
  final ValueChanged<OrderStatus?> onTimelineStatusFilterChanged;

  @override
  Widget build(BuildContext context) {
    return switch (activeView) {
      _OrdersView.table => _OrdersTableCard(
        orders: orders,
        selectedOrderIds: selectedOrderIds,
        onToggleSelection: onToggleSelection,
        onRowTap: onRowTap,
      ),
      _OrdersView.priority => _OrdersPriorityView(
        orders: orders,
        onTapOrder: onRowTap,
      ),
      _OrdersView.timeline => _OrdersTimelineView(
        orders: orders,
        onTapOrder: onRowTap,
        activeStatus: timelineStatusFilter,
        onStatusSelected: onTimelineStatusFilterChanged,
      ),
      _OrdersView.board => _OrdersBoardView(
        orders: orders,
        onTapOrder: onRowTap,
        onMoveOrder: onBoardMove,
      ),
    };
  }
}

class _OrdersPriorityView extends StatelessWidget {
  const _OrdersPriorityView({required this.orders, required this.onTapOrder});

  final List<OrderEntry> orders;
  final ValueChanged<OrderEntry> onTapOrder;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const AppEmptyState(
        title: 'No orders found',
        message: 'No orders match the current filters.',
        icon: Icons.list_alt_rounded,
      );
    }
    final sorted = List<OrderEntry>.from(orders)
      ..sort((a, b) => _priorityScore(b).compareTo(_priorityScore(a)));
    return ListView.separated(
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final order = sorted[index];
        return _OrderOperationalCard(
          order: order,
          subtitle:
              '${order.clientName} • ${order.itemName} • due ${_formatDate(order.endDate)}',
          trailing: Text(
            'Score ${_priorityScore(order)}',
            style: const TextStyle(
              color: Color(0xFF5F6780),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          onTap: () => onTapOrder(order),
        );
      },
    );
  }
}

class _OrdersTimelineView extends StatelessWidget {
  const _OrdersTimelineView({
    required this.orders,
    required this.onTapOrder,
    required this.activeStatus,
    required this.onStatusSelected,
  });

  final List<OrderEntry> orders;
  final ValueChanged<OrderEntry> onTapOrder;
  final OrderStatus? activeStatus;
  final ValueChanged<OrderStatus?> onStatusSelected;

  static const List<OrderStatus> _timelineStatuses = <OrderStatus>[
    OrderStatus.draft,
    OrderStatus.confirmed,
    OrderStatus.allocated,
    OrderStatus.inProduction,
    OrderStatus.completed,
    OrderStatus.dispatched,
    OrderStatus.cancelled,
  ];

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const AppEmptyState(
        title: 'No timeline entries',
        message: 'No orders available for schedule view.',
        icon: Icons.schedule_outlined,
      );
    }
    final filteredOrders = activeStatus == null
        ? orders
        : orders.where((order) => order.status == activeStatus).toList(
            growable: false,
          );
    final buckets = _buildTimelineBuckets(filteredOrders);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _TimelineStatusChip(
                label: 'All',
                selected: activeStatus == null,
                onTap: () => onStatusSelected(null),
              ),
              const SizedBox(width: 8),
              ..._timelineStatuses
                  .map(
                    (status) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _TimelineStatusChip(
                        label: status.label,
                        selected: activeStatus == status,
                        onTap: () => onStatusSelected(status),
                      ),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: buckets.isEmpty
              ? const AppEmptyState(
                  title: 'No timeline entries',
                  message: 'No orders found for this status filter.',
                  icon: Icons.schedule_outlined,
                )
              : ListView.separated(
                  itemCount: buckets.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final bucket = buckets[index];
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBFCFF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE6E9F2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${bucket.label} (${bucket.orders.length})',
                            style: const TextStyle(
                              color: Color(0xFF323A4E),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...bucket.orders.map(
                            (order) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _OrderOperationalCard(
                                order: order,
                                subtitle:
                                    '${order.clientName} • ${order.itemName} • ${order.status.label}',
                                trailing: Text(
                                  _formatDate(order.endDate),
                                  style: const TextStyle(
                                    color: Color(0xFF5F6780),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onTap: () => onTapOrder(order),
                              ),
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

class _TimelineStatusChip extends StatelessWidget {
  const _TimelineStatusChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? const Color(0xFF6C63FF)
                : const Color(0xFFD5DAE5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF4338CA) : const Color(0xFF4B5563),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _OrdersBoardView extends StatelessWidget {
  const _OrdersBoardView({
    required this.orders,
    required this.onTapOrder,
    required this.onMoveOrder,
  });

  final List<OrderEntry> orders;
  final ValueChanged<OrderEntry> onTapOrder;
  final Future<void> Function(OrderEntry order, OrderStatus toStatus)
  onMoveOrder;

  static const List<OrderStatus> _boardStatuses = <OrderStatus>[
    OrderStatus.draft,
    OrderStatus.confirmed,
    OrderStatus.allocated,
    OrderStatus.inProduction,
    OrderStatus.completed,
    OrderStatus.dispatched,
  ];

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const AppEmptyState(
        title: 'No orders found',
        message: 'No orders match the current filters.',
        icon: Icons.view_kanban_outlined,
      );
    }
    final grouped = <OrderStatus, List<OrderEntry>>{
      for (final status in _boardStatuses) status: <OrderEntry>[],
    };
    for (final order in orders) {
      if (grouped.containsKey(order.status)) {
        grouped[order.status]!.add(order);
      }
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _boardStatuses
            .map((status) {
              final entries = grouped[status] ?? const <OrderEntry>[];
              return Container(
                width: 280,
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBFCFF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE6E9F2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            status.label,
                            style: const TextStyle(
                              color: Color(0xFF323A4E),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _MetricBadge(value: '${entries.length}'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DragTarget<OrderEntry>(
                      onWillAcceptWithDetails: (details) =>
                          _actionForBoardMove(
                            from: details.data.status,
                            to: status,
                          ) !=
                          null,
                      onAcceptWithDetails: (details) {
                        onMoveOrder(details.data, status);
                      },
                      builder: (context, candidateData, rejectedData) {
                        final isHovering = candidateData.isNotEmpty;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          constraints: const BoxConstraints(minHeight: 280),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isHovering
                                ? const Color(0xFFF3EEFF)
                                : const Color(0xFFF9FAFE),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isHovering
                                  ? const Color(0xFF7D64FF)
                                  : const Color(0xFFE4E7F0),
                            ),
                          ),
                          child: entries.isEmpty
                              ? const SizedBox(
                                  height: 52,
                                  child: Center(
                                    child: Text(
                                      'Drop valid orders here',
                                      style: TextStyle(
                                        color: Color(0xFF9097A8),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                )
                              : Column(
                                  children: entries
                                      .map(
                                        (order) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: LongPressDraggable<OrderEntry>(
                                            data: order,
                                            feedback: Material(
                                              color: Colors.transparent,
                                              child: SizedBox(
                                                width: 240,
                                                child: _OrderOperationalCard(
                                                  order: order,
                                                  subtitle:
                                                      '${order.clientName} • ${order.quantity} pcs',
                                                  trailing: const Icon(
                                                    Icons
                                                        .drag_indicator_rounded,
                                                    size: 16,
                                                    color: Color(0xFF6D7486),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            child: _OrderOperationalCard(
                                              order: order,
                                              subtitle:
                                                  '${order.clientName} • ${order.quantity} pcs • due ${_formatDate(order.endDate)}',
                                              trailing: _BoardCardActions(
                                                order: order,
                                                onTapOrder: () =>
                                                    onTapOrder(order),
                                                onMoveNext: () {
                                                  final nextAction =
                                                      _defaultActionForStatus(
                                                        order.status,
                                                      );
                                                  final nextStatus =
                                                      _targetStatusForAction(
                                                        nextAction,
                                                      );
                                                  if (nextStatus != null) {
                                                    onMoveOrder(
                                                      order,
                                                      nextStatus,
                                                    );
                                                  }
                                                },
                                              ),
                                              onTap: () => onTapOrder(order),
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(growable: false),
                                ),
                        );
                      },
                    ),
                  ],
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _BoardCardActions extends StatelessWidget {
  const _BoardCardActions({
    required this.order,
    required this.onTapOrder,
    required this.onMoveNext,
  });

  final OrderEntry order;
  final VoidCallback onTapOrder;
  final VoidCallback onMoveNext;

  @override
  Widget build(BuildContext context) {
    final action = _defaultActionForStatus(order.status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onTapOrder,
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          visualDensity: VisualDensity.compact,
          tooltip: 'Open details',
        ),
        if (action != null)
          TextButton(onPressed: onMoveNext, child: Text(_actionLabel(action))),
      ],
    );
  }
}

class _OrderOperationalCard extends StatelessWidget {
  const _OrderOperationalCard({
    required this.order,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final OrderEntry order;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE3E6EF)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.orderNo,
                    style: const TextStyle(
                      color: Color(0xFF2F3241),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF656C7D),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _PriorityBadge(priority: order.priority),
                      if (order.hasMaterialShortage)
                        const _FlagBadge(
                          label: 'Shortage',
                          color: Color(0xFFB42318),
                          bg: Color(0xFFFFF4F2),
                          border: Color(0xFFFFD2CC),
                        ),
                      if (order.procurementPending)
                        const _FlagBadge(
                          label: 'Procurement',
                          color: Color(0xFF6941C6),
                          bg: Color(0xFFF5F3FF),
                          border: Color(0xFFE3D9FF),
                        ),
                      if (_isDelayed(order))
                        const _FlagBadge(
                          label: 'Delayed',
                          color: Color(0xFFB42318),
                          bg: Color(0xFFFFF4F2),
                          border: Color(0xFFFFD2CC),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});

  final OrderPriority priority;

  @override
  Widget build(BuildContext context) {
    final scheme = switch (priority) {
      OrderPriority.low => (
        bg: const Color(0xFFF2F4F7),
        border: const Color(0xFFE4E7EC),
        text: const Color(0xFF475467),
      ),
      OrderPriority.normal => (
        bg: const Color(0xFFEFF8FF),
        border: const Color(0xFFB2DDFF),
        text: const Color(0xFF175CD3),
      ),
      OrderPriority.high => (
        bg: const Color(0xFFFFF6ED),
        border: const Color(0xFFFDDCAB),
        text: const Color(0xFFB54708),
      ),
      OrderPriority.urgent => (
        bg: const Color(0xFFFEF3F2),
        border: const Color(0xFFFDA29B),
        text: const Color(0xFFB42318),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.border),
      ),
      child: Text(
        priority.label,
        style: TextStyle(
          color: scheme.text,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FlagBadge extends StatelessWidget {
  const _FlagBadge({
    required this.label,
    required this.color,
    required this.bg,
    required this.border,
  });

  final String label;
  final Color color;
  final Color bg;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        value,
        style: const TextStyle(
          color: Color(0xFF475467),
          fontSize: 12,
          fontWeight: FontWeight.w700,
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
          final layout = _OrdersTableLayout.fromContainerWidth(
            constraints.maxWidth,
          );

          return Column(
            children: [
              _TableHeaderRow(layout: layout),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.separated(
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    return _OrderDataRow(
                      order: order,
                      layout: layout,
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
          );
        },
      ),
    );
  }
}

class _TableHeaderRow extends StatelessWidget {
  const _TableHeaderRow({required this.layout});

  final _OrdersTableLayout layout;

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
      child: Row(
        children: [
          _HeaderCell('Order ID', width: layout.orderIdWidth),
          _HeaderCell('Date', width: layout.dateWidth),
          _HeaderCell('Party', width: layout.partyWidth),
          _HeaderCell('Item', width: layout.itemWidth),
          _HeaderCell('Purchase Order Number', width: layout.poWidth),
          _HeaderCell('Order Quantity', width: layout.quantityWidth),
          _HeaderCell('Start Date', width: layout.startDateWidth),
          _HeaderCell('End Date', width: layout.endDateWidth),
          _HeaderCell('Status', width: layout.statusWidth),
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
    required this.layout,
    required this.isSelected,
    required this.isStriped,
    required this.onSelectionChanged,
    required this.onTap,
  });

  final OrderEntry order;
  final _OrdersTableLayout layout;
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
                    width: layout.orderIdWidth,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  _DataCell(
                    _formatDate(order.createdAt),
                    width: layout.dateWidth,
                  ),
                  _DataCell(
                    order.clientName,
                    width: layout.partyWidth,
                    overflow: TextOverflow.ellipsis,
                  ),
                  _DataCell(
                    order.variationPathLabel.isEmpty ||
                            order.variationPathLabel == order.itemName
                        ? order.itemName
                        : '${order.itemName} · ${order.variationPathLabel}',
                    width: layout.itemWidth,
                    overflow: TextOverflow.ellipsis,
                  ),
                  _DataCell(
                    order.poNumber.isEmpty ? '—' : order.poNumber,
                    width: layout.poWidth,
                    overflow: TextOverflow.ellipsis,
                  ),
                  _DataCell(
                    '${order.quantity} Pieces',
                    width: layout.quantityWidth,
                    overflow: TextOverflow.ellipsis,
                  ),
                  _DataCell(
                    _formatDate(order.startDate),
                    width: layout.startDateWidth,
                  ),
                  _DataCell(
                    _formatDate(order.endDate),
                    width: layout.endDateWidth,
                  ),
                  SizedBox(
                    width: layout.statusWidth,
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
      OrderStatus.draft => (
        bg: const Color(0xFFFDF5F0),
        border: const Color(0xFFF8DBB9),
        text: const Color(0xFF824C00),
      ),
      OrderStatus.confirmed => (
        bg: const Color(0xFFF0F4FF),
        border: const Color(0xFFC8D4FF),
        text: const Color(0xFF2F4FB8),
      ),
      OrderStatus.allocated => (
        bg: const Color(0xFFF0FBFF),
        border: const Color(0xFFBFE9F8),
        text: const Color(0xFF0B6B8B),
      ),
      OrderStatus.inProduction => (
        bg: const Color(0xFFF0F6FD),
        border: const Color(0xFFB9CFF8),
        text: const Color(0xFF003BFB),
      ),
      OrderStatus.completed => (
        bg: const Color(0xFFEFFBF2),
        border: const Color(0xFFB5E5C0),
        text: const Color(0xFF007D30),
      ),
      OrderStatus.dispatched => (
        bg: const Color(0xFFF4F6FF),
        border: const Color(0xFFD4DAFF),
        text: const Color(0xFF4B50B9),
      ),
      OrderStatus.closed => (
        bg: const Color(0xFFF4F4F5),
        border: const Color(0xFFD4D4D8),
        text: const Color(0xFF3F3F46),
      ),
      OrderStatus.onHold => (
        bg: const Color(0xFFFDF0F0),
        border: const Color(0xFFFF8C8C),
        text: const Color(0xFFDC0000),
      ),
      OrderStatus.cancelled => (
        bg: const Color(0xFFFEF2F2),
        border: const Color(0xFFFECACA),
        text: const Color(0xFFB91C1C),
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

class _OrdersTableLayout {
  const _OrdersTableLayout({
    required this.orderIdWidth,
    required this.dateWidth,
    required this.partyWidth,
    required this.itemWidth,
    required this.poWidth,
    required this.quantityWidth,
    required this.startDateWidth,
    required this.endDateWidth,
    required this.statusWidth,
  });

  final double orderIdWidth;
  final double dateWidth;
  final double partyWidth;
  final double itemWidth;
  final double poWidth;
  final double quantityWidth;
  final double startDateWidth;
  final double endDateWidth;
  final double statusWidth;

  static _OrdersTableLayout fromContainerWidth(double containerWidth) {
    final contentWidth =
        (containerWidth - (_OrdersTableMetrics.horizontalPadding * 2)).clamp(
          0.0,
          double.infinity,
        );
    final baseContentWidth =
        _OrdersTableMetrics.totalWidth -
        (_OrdersTableMetrics.horizontalPadding * 2);
    final scale = baseContentWidth == 0 ? 1.0 : contentWidth / baseContentWidth;

    return _OrdersTableLayout(
      orderIdWidth: _OrdersTableMetrics.orderIdWidth * scale,
      dateWidth: _OrdersTableMetrics.dateWidth * scale,
      partyWidth: _OrdersTableMetrics.partyWidth * scale,
      itemWidth: _OrdersTableMetrics.itemWidth * scale,
      poWidth: _OrdersTableMetrics.poWidth * scale,
      quantityWidth: _OrdersTableMetrics.quantityWidth * scale,
      startDateWidth: _OrdersTableMetrics.startDateWidth * scale,
      endDateWidth: _OrdersTableMetrics.endDateWidth * scale,
      statusWidth: _OrdersTableMetrics.statusWidth * scale,
    );
  }
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
  DateTime? _startDate;
  DateTime? _endDate;
  OrderPriority _selectedPriority = OrderPriority.normal;
  late List<_CompletionShortcutPreset> _completionShortcuts;

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
    _completionShortcuts = const <_CompletionShortcutPreset>[
      _CompletionShortcutPreset(amount: 3, unit: _CompletionShortcutUnit.days),
      _CompletionShortcutPreset(amount: 3, unit: _CompletionShortcutUnit.weeks),
    ];
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE2E2E2))),
              ),
              child: Text(
                'Create New Order',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF3F3F3F),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(56, 18, 56, 18),
                child: clients.isEmpty || items.isEmpty
                    ? _DependencyMessage(
                        hasClients: clients.isNotEmpty,
                        hasItems: items.isNotEmpty,
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final fieldWidth = ((constraints.maxWidth - 24) / 2)
                              .clamp(260.0, 300.0);
                          final children = <Widget>[
                            SizedBox(
                              width: fieldWidth,
                              child: _OrderEditorField(
                                label: 'Order No',
                                child: TextFormField(
                                  key: const ValueKey<String>(
                                    'orders-editor-order-no-field',
                                  ),
                                  controller: _orderNoController,
                                  decoration: _inputDecoration(
                                    hintText: 'Enter',
                                  ),
                                  textInputAction: TextInputAction.next,
                                  validator: (value) {
                                    if ((value ?? '').trim().isEmpty) {
                                      return 'Enter an order number.';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: _OrderEditorField(
                                label: 'Purchase Order No.',
                                child: TextFormField(
                                  key: const ValueKey<String>(
                                    'orders-editor-po-number-field',
                                  ),
                                  controller: _poNumberController,
                                  decoration: _inputDecoration(
                                    hintText: 'Enter',
                                  ),
                                  textInputAction: TextInputAction.next,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: _OrderEditorField(
                                label: 'Client',
                                child: SearchableSelectField<int>(
                                  key: const ValueKey<String>(
                                    'orders-editor-client-field',
                                  ),
                                  tapTargetKey: const ValueKey<String>(
                                    'orders-editor-client-field',
                                  ),
                                  value: _selectedClientId,
                                  decoration: _inputDecoration(
                                    hintText: 'Select',
                                  ),
                                  dialogTitle: 'Client',
                                  searchHintText: 'Search client',
                                  options: clients
                                      .map(
                                        (client) => SearchableSelectOption<int>(
                                          value: client.id,
                                          label: client.displayLabel,
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedClientId = value;
                                      final selected = _selectedClient(clients);
                                      _clientCodeController.text =
                                          _resolveClientCode(selected);
                                    });
                                  },
                                  validator: (value) {
                                    if (value == null) {
                                      return 'Select a client.';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: _OrderEditorField(
                                label: 'Client Code',
                                child: TextFormField(
                                  key: const ValueKey<String>(
                                    'orders-editor-client-code-field',
                                  ),
                                  controller: _clientCodeController,
                                  readOnly: true,
                                  decoration: _inputDecoration(
                                    hintText: 'Enter',
                                    errorText: _clientCodeError,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: _OrderEditorField(
                                label: 'Item',
                                child: SearchableSelectField<int>(
                                  key: const ValueKey<String>(
                                    'orders-editor-item-field',
                                  ),
                                  tapTargetKey: const ValueKey<String>(
                                    'orders-editor-item-field',
                                  ),
                                  value: _selectedItemId,
                                  decoration: _inputDecoration(
                                    hintText: 'Select',
                                  ),
                                  dialogTitle: 'Item',
                                  searchHintText: 'Search item',
                                  options: items
                                      .map(
                                        (item) => SearchableSelectOption<int>(
                                          value: item.id,
                                          label: item.displayName,
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
                              ),
                            ),
                            ..._buildVariationSelectors(items, fieldWidth),
                            SizedBox(
                              width: fieldWidth,
                              child: _OrderEditorField(
                                label: 'Quantity / Unit',
                                child: TextFormField(
                                  key: const ValueKey<String>(
                                    'orders-editor-quantity-field',
                                  ),
                                  controller: _quantityController,
                                  decoration: _inputDecoration(
                                    hintText: 'Enter',
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (value) {
                                    final quantity = int.tryParse(
                                      (value ?? '').trim(),
                                    );
                                    if (quantity == null || quantity <= 0) {
                                      return 'Enter a valid quantity.';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: _OrderEditorField(
                                label: 'Priority',
                                child: DropdownButtonFormField<OrderPriority>(
                                  key: ValueKey<OrderPriority>(_selectedPriority),
                                  initialValue: _selectedPriority,
                                  decoration: _inputDecoration(),
                                  items: OrderPriority.values
                                      .map(
                                        (priority) =>
                                            DropdownMenuItem<OrderPriority>(
                                              value: priority,
                                              child: Text(priority.label),
                                            ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setState(() {
                                      _selectedPriority = value;
                                    });
                                  },
                                ),
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: _OrderEditorField(
                                label: 'Status',
                                child: TextFormField(
                                  initialValue: OrderStatus.draft.label,
                                  readOnly: true,
                                  decoration: _inputDecoration(),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: _DateField(
                                key: const ValueKey<String>(
                                  'orders-editor-start-date-field',
                                ),
                                label: 'Start Date',
                                controller: _startDateController,
                                onTap: () => _pickDate(
                                  context,
                                  initial: _startDate ?? DateTime.now(),
                                  onSelected: (value) {
                                    setState(() {
                                      _startDate = value;
                                      _startDateController.text = _formatDate(
                                        value,
                                      );
                                    });
                                  },
                                ),
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _DateField(
                                    key: const ValueKey<String>(
                                      'orders-editor-end-date-field',
                                    ),
                                    label: 'Estimated Completion Date',
                                    controller: _endDateController,
                                    onTap: () => _pickDate(
                                      context,
                                      initial:
                                          _endDate ??
                                          _startDate ??
                                          DateTime.now(),
                                      onSelected: (value) {
                                        setState(() {
                                          _endDate = value;
                                          _endDateController.text = _formatDate(
                                            value,
                                          );
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (
                                        var index = 0;
                                        index < _completionShortcuts.length;
                                        index++
                                      )
                                        _CompletionShortcutButton(
                                          key: ValueKey<String>(
                                            'orders-editor-shortcut-$index',
                                          ),
                                          label:
                                              _completionShortcuts[index].label,
                                          onTap: () => _applyCompletionShortcut(
                                            _completionShortcuts[index],
                                          ),
                                        ),
                                      _CompletionShortcutButton(
                                        key: const ValueKey<String>(
                                          'orders-editor-shortcut-add',
                                        ),
                                        label: 'Add',
                                        isGhost: true,
                                        onTap: _openCompletionShortcutEditor,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ];
                          return Wrap(
                            spacing: 24,
                            runSpacing: 18,
                            children: children,
                          );
                        },
                      ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE2E2E2))),
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
                  AppButton(
                    label: 'Create Order',
                    onPressed: clients.isEmpty || items.isEmpty
                        ? null
                        : () => _submit(context, clients, items),
                  ),
                ],
              ),
            ),
          ],
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
        status: OrderStatus.draft,
        priority: _selectedPriority,
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

  List<Widget> _buildVariationSelectors(
    List<ItemDefinition> items,
    double fieldWidth,
  ) {
    final selectedItem = _selectedItem(items);
    if (selectedItem == null) {
      return [
        SizedBox(
          width: fieldWidth,
          child: _OrderEditorField(
            label: 'Variation Path',
            child: SearchableSelectField<int>(
              key: const ValueKey<String>('orders-editor-variation-path-field'),
              tapTargetKey: const ValueKey<String>(
                'orders-editor-variation-path-field',
              ),
              value: null,
              decoration: _inputDecoration(hintText: 'Select'),
              options: const <SearchableSelectOption<int>>[],
              fieldEnabled: false,
              onChanged: (_) {},
              validator: (value) {
                if (value == null) {
                  return 'Select an item first.';
                }
                return null;
              },
            ),
          ),
        ),
      ];
    }

    final steps = _buildSelectionSteps(selectedItem);
    if (steps.isEmpty) {
      return [
        SizedBox(
          width: fieldWidth,
          child: Container(
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
        ),
      ];
    }

    final widgets = <Widget>[];
    for (var index = 0; index < steps.length; index++) {
      final step = steps[index];
      widgets.add(
        SizedBox(
          width: fieldWidth,
          child: _OrderEditorField(
            label: step.label,
            child: SearchableSelectField<int>(
              key: ValueKey<String>(
                'orders-editor-${step.label.toLowerCase().replaceAll(' ', '-')}-field',
              ),
              tapTargetKey: ValueKey<String>(
                'orders-editor-${step.label.toLowerCase().replaceAll(' ', '-')}-field',
              ),
              value: step.selectedId,
              decoration: _inputDecoration(hintText: 'Select'),
              dialogTitle: step.label,
              searchHintText: 'Search ${step.label.toLowerCase()}',
              options: step.options
                  .map(
                    (node) => SearchableSelectOption<int>(
                      value: node.id,
                      label: node.name,
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
          ),
        ),
      );
    }
    final selectedLeaf = _selectedLeafValue(selectedItem);
    if (selectedLeaf != null) {
      widgets.add(
        SizedBox(
          width: fieldWidth,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text('Selected Path: ${selectedLeaf.displayName}'),
          ),
        ),
      );
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

  InputDecoration _inputDecoration({String? hintText, String? errorText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: Color(0xFF9D9D9D), fontSize: 14),
      errorText: errorText,
      filled: false,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF6049E3)),
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

  void _applyCompletionShortcut(_CompletionShortcutPreset preset) {
    final anchorDate = _startDate ?? DateTime.now();
    final dayOffset = switch (preset.unit) {
      _CompletionShortcutUnit.days => preset.amount,
      _CompletionShortcutUnit.weeks => preset.amount * 7,
    };
    final estimatedDate = anchorDate.add(Duration(days: dayOffset));
    setState(() {
      _endDate = estimatedDate;
      _endDateController.text = _formatDate(estimatedDate);
    });
  }

  Future<void> _openCompletionShortcutEditor() async {
    final updatedShortcuts = await showDialog<List<_CompletionShortcutPreset>>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _CompletionShortcutEditorDialog(
            initialShortcuts: _completionShortcuts,
          ),
        ),
      ),
    );
    if (updatedShortcuts == null || updatedShortcuts.isEmpty) {
      return;
    }
    setState(() {
      _completionShortcuts = updatedShortcuts.take(3).toList(growable: false);
    });
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
  late OrderEntry _currentOrder;
  late Future<List<OrderTransitionOption>> _transitionOptionsFuture;
  late final TextEditingController _startDateController;
  late final TextEditingController _endDateController;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
    _transitionOptionsFuture = context
        .read<OrdersProvider>()
        .getOrderTransitionOptions(widget.order.id);
    _startDate = _currentOrder.startDate;
    _endDate = _currentOrder.endDate;
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
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Current Status',
                style: TextStyle(
                  color: Color(0xFF4B5563),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              _StatusPill(status: _currentOrder.status),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Allowed Actions',
            style: TextStyle(
              color: Color(0xFF4B5563),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          FutureBuilder<List<OrderTransitionOption>>(
            future: _transitionOptionsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _buildTransitionActions(
                  context,
                  snapshot.data ?? const <OrderTransitionOption>[],
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _DateField(
                  label: 'Start Date',
                  controller: _startDateController,
                  onTap: () => _pickDate(
                    context,
                    initial: _startDate ?? _currentOrder.createdAt,
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
                    initial: _endDate ?? _startDate ?? _currentOrder.createdAt,
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
                label: 'Close',
                onPressed: () async {
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTransitionActions(
    BuildContext context,
    List<OrderTransitionOption> actions,
  ) {
    if (actions.isEmpty) {
      return const <Widget>[
        Text(
          'No actions available for this state.',
          style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
        ),
      ];
    }

    return actions
        .map((action) {
          return OutlinedButton(
            onPressed: () => _performTransition(
              context,
              action: action.action,
              toStatus: action.toStatus,
              needsReason: action.needsReason,
            ),
            child: Text(action.label),
          );
        })
        .toList(growable: false);
  }

  Future<void> _performTransition(
    BuildContext context, {
    required String action,
    required OrderStatus toStatus,
    required bool needsReason,
  }) async {
    String? reason;
    if (needsReason) {
      reason = await _promptReason(context, toStatus);
      if (reason == null) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    final result = await this.context
        .read<OrdersProvider>()
        .transitionOrderByAction(
          orderId: _currentOrder.id,
          action: action,
          reason: reason,
          startDate: _startDate,
          endDate: _endDate,
        );
    if (!context.mounted) {
      return;
    }
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order moved to ${toStatus.label}.')),
      );
      setState(() {
        _currentOrder = result;
        _transitionOptionsFuture = this.context
            .read<OrdersProvider>()
            .getOrderTransitionOptions(_currentOrder.id);
      });
      await context.read<OrdersProvider>().refresh();
      return;
    }
    final message =
        context.read<OrdersProvider>().errorMessage ??
        'Unable to update order. Please try again.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _promptReason(
    BuildContext context,
    OrderStatus toStatus,
  ) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${toStatus.label} Reason'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter reason'),
          minLines: 2,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                return;
              }
              Navigator.of(context).pop(text);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
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

class _OrderDetailsSheet extends StatefulWidget {
  const _OrderDetailsSheet({required this.order, required this.onEdit});

  final OrderEntry order;
  final VoidCallback onEdit;

  @override
  State<_OrderDetailsSheet> createState() => _OrderDetailsSheetState();
}

class _OrderDetailsSheetState extends State<_OrderDetailsSheet> {
  late OrderEntry _order;
  late Future<List<OrderActivityEntry>> _activityFuture;
  late Future<List<OrderStatusHistoryEntry>> _historyFuture;
  late Future<OrderMaterialSnapshot?> _materialsFuture;
  late Future<List<OrderProcurementSuggestionEntry>> _procurementFuture;
  bool _isUpdatingPriority = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _reloadTrails();
  }

  void _reloadTrails() {
    final provider = context.read<OrdersProvider>();
    _activityFuture = provider.getOrderActivity(_order.id);
    _historyFuture = provider.getOrderStatusHistory(_order.id);
    _materialsFuture = provider.getOrderMaterialRequirements(_order.id);
    _procurementFuture = provider.getOrderProcurementSuggestions(_order.id);
  }

  @override
  Widget build(BuildContext context) {
    final detailRows = <({String label, String value})>[
      (label: 'Order Code', value: _order.orderNo),
      (label: 'Purchase order no.', value: _emptyFallback(_order.poNumber)),
      (label: 'Item', value: _order.itemName),
      (label: 'Purchase order item Code', value: '—'),
      (label: 'Quantity / Unit', value: '${_order.quantity} Pieces'),
      (label: 'Start Date', value: _formatDate(_order.startDate)),
      (label: 'Estimated completion date', value: _formatDate(_order.endDate)),
    ];

    return Material(
      color: Colors.transparent,
      child: DefaultTabController(
        length: 4,
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
              Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: Color(0xFF3F3F3F),
                  unselectedLabelColor: Color(0xFF8A8A8A),
                  indicatorColor: Color(0xFF6049E3),
                  dividerColor: Color(0xFFEDEDED),
                  tabs: [
                    Tab(text: 'Details'),
                    Tab(text: 'Materials'),
                    Tab(text: 'Timeline'),
                    Tab(text: 'Audit'),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: TabBarView(
                    children: [
                      Column(
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
                                      padding: const EdgeInsets.only(
                                        bottom: 18,
                                      ),
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
                                    child: _StatusPill(status: _order.status),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: 360,
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 220,
                                  child: Text(
                                    'Priority',
                                    style: TextStyle(
                                      color: Color(0xFF888888),
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _isUpdatingPriority
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : DropdownButtonHideUnderline(
                                            child:
                                                DropdownButton<OrderPriority>(
                                                  value: _order.priority,
                                                  items: OrderPriority.values
                                                      .map(
                                                        (priority) =>
                                                            DropdownMenuItem<
                                                              OrderPriority
                                                            >(
                                                              value: priority,
                                                              child: Text(
                                                                priority.label,
                                                              ),
                                                            ),
                                                      )
                                                      .toList(growable: false),
                                                  onChanged: (value) {
                                                    if (value == null) {
                                                      return;
                                                    }
                                                    _updatePriority(value);
                                                  },
                                                ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      FutureBuilder<OrderMaterialSnapshot?>(
                        future: _materialsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final data = snapshot.data;
                          final requirements =
                              data?.requirements ??
                              const <OrderMaterialRequirementEntry>[];
                          final summary = data?.summary;
                          if (summary == null || requirements.isEmpty) {
                            return const Center(
                              child: Text(
                                'No material requirements linked yet.',
                                style: TextStyle(
                                  color: Color(0xFF7A7A7A),
                                  fontSize: 13,
                                ),
                              ),
                            );
                          }
                          final tableHeight = requirements.length <= 2
                              ? (requirements.length * 68.0) + 24.0
                              : 240.0;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _MaterialSummaryChip(
                                    label: 'Required',
                                    value: _formatQty(summary.requiredQty),
                                  ),
                                  _MaterialSummaryChip(
                                    label: 'Allocated',
                                    value: _formatQty(summary.allocatedQty),
                                  ),
                                  _MaterialSummaryChip(
                                    label: 'Shortage',
                                    value: _formatQty(summary.shortageQty),
                                    danger: summary.shortageQty > 0,
                                  ),
                                  _MaterialSummaryChip(
                                    label: 'Readiness',
                                    value: summary.readiness,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton(
                                      onPressed: _checkAvailability,
                                      child: const Text('Check'),
                                    ),
                                    FilledButton(
                                      onPressed: _allocateMaterials,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF6049E3,
                                        ),
                                      ),
                                      child: const Text('Allocate'),
                                    ),
                                    OutlinedButton(
                                      onPressed: _releaseMaterials,
                                      child: const Text('Release'),
                                    ),
                                    OutlinedButton(
                                      onPressed: _consumeMaterials,
                                      child: const Text('Consume'),
                                    ),
                                    OutlinedButton(
                                      onPressed: _refreshProcurementSuggestions,
                                      child: const Text('Refresh Suggestions'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: tableHeight,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFAFAFC),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFFE7E7ED),
                                    ),
                                  ),
                                  child: ListView.separated(
                                    itemCount: requirements.length,
                                    separatorBuilder: (_, _) => const Divider(
                                      height: 1,
                                      color: Color(0xFFE7E7ED),
                                    ),
                                    itemBuilder: (context, index) {
                                      final requirement = requirements[index];
                                      return Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          12,
                                          10,
                                          12,
                                          10,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              flex: 4,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    requirement.materialName,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Color(0xFF313131),
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    requirement.materialBarcode,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Color(0xFF8A8A8A),
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  if ((requirement.procurementRequestNumber ??
                                                              '')
                                                          .trim()
                                                          .isNotEmpty ||
                                                      requirement
                                                              .procurementRequestedQty >
                                                          0) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Req ${requirement.procurementRequestNumber ?? 'Unlinked'} • ${_procurementStateLabel(requirement.procurementRequestStatus ?? 'not_ordered')} • Rcv ${_formatQty(requirement.procurementReceivedQty)} / Pend ${_formatQty(requirement.procurementPendingQty)}',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF7A5A28,
                                                        ),
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            _MaterialCell(
                                              label: 'Req',
                                              value: _formatQty(
                                                requirement.requiredQty,
                                              ),
                                            ),
                                            _MaterialCell(
                                              label: 'Alloc',
                                              value: _formatQty(
                                                requirement.allocatedQty,
                                              ),
                                            ),
                                            _MaterialCell(
                                              label: 'Avail',
                                              value: _formatQty(
                                                requirement.availableQty,
                                              ),
                                            ),
                                            _MaterialCell(
                                              label: 'Short',
                                              value: _formatQty(
                                                requirement.shortageQty,
                                              ),
                                              danger:
                                                  requirement.shortageQty > 0,
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              FutureBuilder<
                                List<OrderProcurementSuggestionEntry>
                              >(
                                future: _procurementFuture,
                                builder: (context, procurementSnapshot) {
                                  if (procurementSnapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const SizedBox(
                                      height: 44,
                                      child: Center(
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  final suggestions =
                                      procurementSnapshot.data ??
                                      const <OrderProcurementSuggestionEntry>[];
                                  if (suggestions.isEmpty) {
                                    return const SizedBox(
                                      height: 28,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          'No procurement suggestions. Shortages are clear.',
                                          style: TextStyle(
                                            color: Color(0xFF7A7A7A),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  return Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFFBF3),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(0xFFF2D9A8),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Procurement Suggestions',
                                          style: TextStyle(
                                            color: Color(0xFF8A5A00),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        ...suggestions.take(3).map((
                                          suggestion,
                                        ) {
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 6,
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '${suggestion.materialName} • ${_emptyFallback(suggestion.supplier)}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Color(0xFF5D3A00),
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  '${_formatQty(suggestion.suggestedQty)} ${suggestion.unitSymbol}',
                                                  style: const TextStyle(
                                                    color: Color(0xFF7A5A28),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  _procurementStateLabel(
                                                    suggestion.procurementState,
                                                  ),
                                                  style: const TextStyle(
                                                    color: Color(0xFF9A6F22),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
                      FutureBuilder<List<OrderActivityEntry>>(
                        future: _activityFuture,
                        builder: (context, snapshot) {
                          final entries =
                              snapshot.data ?? const <OrderActivityEntry>[];
                          return Column(
                            children: [
                              Align(
                                alignment: Alignment.centerRight,
                                child: OutlinedButton(
                                  onPressed: _addNote,
                                  child: const Text('Add Note'),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child:
                                    snapshot.connectionState ==
                                        ConnectionState.waiting
                                    ? const Center(
                                        child: CircularProgressIndicator(),
                                      )
                                    : entries.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'No activity yet.',
                                          style: TextStyle(
                                            color: Color(0xFF7A7A7A),
                                            fontSize: 13,
                                          ),
                                        ),
                                      )
                                    : ListView.separated(
                                        itemCount: entries.length,
                                        separatorBuilder: (_, _) =>
                                            const SizedBox(height: 10),
                                        itemBuilder: (context, index) {
                                          final entry = entries[index];
                                          return Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFAFAFC),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: const Color(0xFFE7E7ED),
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  entry.title,
                                                  style: const TextStyle(
                                                    color: Color(0xFF313131),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                if (entry.description
                                                    .trim()
                                                    .isNotEmpty) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    entry.description,
                                                    style: const TextStyle(
                                                      color: Color(0xFF616161),
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ],
                                                const SizedBox(height: 6),
                                                Text(
                                                  '${entry.actorName}${entry.actorRole == null ? '' : ' • ${entry.actorRole}'} • ${_formatDateTime(entry.createdAt)}',
                                                  style: const TextStyle(
                                                    color: Color(0xFF8A8A8A),
                                                    fontSize: 12,
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
                        },
                      ),
                      FutureBuilder<List<OrderStatusHistoryEntry>>(
                        future: _historyFuture,
                        builder: (context, snapshot) {
                          final entries =
                              snapshot.data ??
                              const <OrderStatusHistoryEntry>[];
                          return snapshot.connectionState ==
                                  ConnectionState.waiting
                              ? const Center(child: CircularProgressIndicator())
                              : entries.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No status audit entries yet.',
                                    style: TextStyle(
                                      color: Color(0xFF7A7A7A),
                                      fontSize: 13,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: entries.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final entry = entries[index];
                                    final fromLabel =
                                        entry.fromStatus?.label ?? '—';
                                    final toLabel = entry.toStatus.label;
                                    return Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFAFAFC),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: const Color(0xFFE7E7ED),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '$fromLabel -> $toLabel',
                                            style: const TextStyle(
                                              color: Color(0xFF313131),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${entry.changedByName}${entry.changedByRole == null ? '' : ' • ${entry.changedByRole}'} • ${_formatDateTime(entry.changedAt)}',
                                            style: const TextStyle(
                                              color: Color(0xFF7A7A7A),
                                              fontSize: 12,
                                            ),
                                          ),
                                          if ((entry.reason ?? '')
                                              .trim()
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Reason: ${entry.reason}',
                                              style: const TextStyle(
                                                color: Color(0xFF616161),
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                );
                        },
                      ),
                    ],
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
                    _OrderDetailActionButton(
                      label: 'Edit',
                      onPressed: widget.onEdit,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addNote() async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Write a note for this order timeline',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) {
                return;
              }
              Navigator.of(context).pop(value);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || note == null) {
      return;
    }
    final result = await context.read<OrdersProvider>().addOrderNote(
      AddOrderNoteInput(orderId: _order.id, note: note),
    );
    if (!mounted) {
      return;
    }
    if (result == null) {
      final message =
          context.read<OrdersProvider>().errorMessage ??
          'Unable to add note. Please try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    setState(_reloadTrails);
  }

  Future<void> _checkAvailability() async {
    final result = await context
        .read<OrdersProvider>()
        .checkOrderMaterialAvailability(_order.id);
    if (!mounted) {
      return;
    }
    if (result == null) {
      _showErrorToast();
      return;
    }
    setState(_reloadTrails);
  }

  Future<void> _allocateMaterials() async {
    final result = await context.read<OrdersProvider>().allocateOrderMaterials(
      _order.id,
    );
    if (!mounted) {
      return;
    }
    if (result == null) {
      _showErrorToast();
      return;
    }
    setState(_reloadTrails);
  }

  Future<void> _releaseMaterials() async {
    final result = await context.read<OrdersProvider>().releaseOrderMaterials(
      _order.id,
    );
    if (!mounted) {
      return;
    }
    if (result == null) {
      _showErrorToast();
      return;
    }
    setState(_reloadTrails);
  }

  Future<void> _consumeMaterials() async {
    final result = await context.read<OrdersProvider>().consumeOrderMaterials(
      _order.id,
    );
    if (!mounted) {
      return;
    }
    if (result == null) {
      _showErrorToast();
      return;
    }
    setState(_reloadTrails);
  }

  Future<void> _refreshProcurementSuggestions() async {
    final provider = context.read<OrdersProvider>();
    await provider.checkOrderMaterialAvailability(_order.id);
    final suggestions = await provider.refreshOrderProcurementSuggestions(
      _order.id,
    );
    if (!mounted) {
      return;
    }
    if (suggestions.isEmpty) {
      final message = provider.errorMessage;
      if (message != null && message.isNotEmpty) {
        _showErrorToast();
      }
    }
    setState(_reloadTrails);
  }

  Future<void> _updatePriority(OrderPriority priority) async {
    if (_isUpdatingPriority || priority == _order.priority) {
      return;
    }
    setState(() {
      _isUpdatingPriority = true;
    });
    final result = await context.read<OrdersProvider>().updateOrderPriority(
      orderId: _order.id,
      priority: priority,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isUpdatingPriority = false;
      if (result != null) {
        _order = result;
      }
      _reloadTrails();
    });
    if (result == null) {
      final message =
          context.read<OrdersProvider>().errorMessage ??
          'Unable to update priority right now.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Priority changed to ${priority.label}.')),
    );
  }

  void _showErrorToast() {
    final message =
        context.read<OrdersProvider>().errorMessage ??
        'Unable to update material state. Please try again.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatDateTime(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day-$month-${value.year} $hour:$minute';
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

  String _formatQty(double value) {
    if ((value - value.roundToDouble()).abs() < 0.001) {
      return value.round().toString();
    }
    return value.toStringAsFixed(2);
  }

  String _procurementStateLabel(String value) {
    switch (value.trim().toLowerCase()) {
      case 'ordered':
        return 'Ordered';
      case 'received_partial':
        return 'Partial Received';
      case 'received_complete':
        return 'Received';
      case 'not_ordered':
      default:
        return 'Not Ordered';
    }
  }
}

class _MaterialSummaryChip extends StatelessWidget {
  const _MaterialSummaryChip({
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 128),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: danger ? const Color(0xFFFFF1F1) : const Color(0xFFF6F7FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: danger ? const Color(0xFFF3B4B4) : const Color(0xFFE0E3EC),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF6A6A6A),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: danger ? const Color(0xFFB42318) : const Color(0xFF2F2F2F),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MaterialCell extends StatelessWidget {
  const _MaterialCell({
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: danger ? const Color(0xFFB42318) : const Color(0xFF2F2F2F),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
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

class _OrderEditorField extends StatelessWidget {
  const _OrderEditorField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 14,
            color: const Color(0xFF373737),
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    super.key,
    required this.label,
    required this.controller,
    required this.onTap,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _OrderEditorField(
      label: label,
      child: TextFormField(
        key: key,
        controller: controller,
        readOnly: true,
        onTap: onTap,
        decoration: InputDecoration(
          hintText: 'Enter',
          hintStyle: const TextStyle(color: Color(0xFF9D9D9D), fontSize: 14),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 11,
          ),
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF6049E3)),
          ),
        ),
      ),
    );
  }
}

class _CompletionShortcutButton extends StatelessWidget {
  const _CompletionShortcutButton({
    super.key,
    required this.label,
    required this.onTap,
    this.isGhost = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool isGhost;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isGhost ? Colors.white : const Color(0xFFF5F2FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isGhost ? const Color(0xFFD7DBE7) : const Color(0xFFD9D2FF),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isGhost ? const Color(0xFF4B5563) : const Color(0xFF6049E3),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _CompletionShortcutEditorDialog extends StatefulWidget {
  const _CompletionShortcutEditorDialog({required this.initialShortcuts});

  final List<_CompletionShortcutPreset> initialShortcuts;

  @override
  State<_CompletionShortcutEditorDialog> createState() =>
      _CompletionShortcutEditorDialogState();
}

class _CompletionShortcutEditorDialogState
    extends State<_CompletionShortcutEditorDialog> {
  late final List<TextEditingController> _amountControllers;
  late final List<_CompletionShortcutUnit> _units;
  late bool _showThirdShortcut;

  @override
  void initState() {
    super.initState();
    final drafts = List<_CompletionShortcutDraft>.generate(3, (index) {
      if (index < widget.initialShortcuts.length) {
        final shortcut = widget.initialShortcuts[index];
        return _CompletionShortcutDraft(
          amountText: shortcut.amount.toString(),
          unit: shortcut.unit,
        );
      }
      return const _CompletionShortcutDraft(
        amountText: '',
        unit: _CompletionShortcutUnit.days,
      );
    });
    _amountControllers = drafts
        .map((draft) => TextEditingController(text: draft.amountText))
        .toList(growable: false);
    _units = drafts.map((draft) => draft.unit).toList(growable: false);
    _showThirdShortcut = widget.initialShortcuts.length > 2;
  }

  @override
  void dispose() {
    for (final controller in _amountControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleCount = _showThirdShortcut ? 3 : 2;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Edit Completion Buttons',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF2F3441),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Set quick completion presets for common lead times. People can still enter a date manually when the job runs longer.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF6B7280),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < visibleCount; index++) ...[
            _buildShortcutCard(index),
            if (index != visibleCount - 1) const SizedBox(height: 8),
          ],
          if (!_showThirdShortcut) ...[
            const SizedBox(height: 8),
            InkWell(
              key: const ValueKey<String>('orders-editor-add-third-shortcut'),
              onTap: () {
                setState(() {
                  _showThirdShortcut = true;
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.add_circle_outline_rounded,
                      size: 18,
                      color: Color(0xFF6049E3),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Add third shortcut',
                      style: TextStyle(
                        color: Color(0xFF374151),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
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
                onPressed: () {
                  final shortcuts = <_CompletionShortcutPreset>[];
                  for (var index = 0; index < visibleCount; index++) {
                    final amount = int.tryParse(
                      _amountControllers[index].text.trim(),
                    );
                    if (amount == null || amount <= 0) {
                      continue;
                    }
                    shortcuts.add(
                      _CompletionShortcutPreset(
                        amount: amount,
                        unit: _units[index],
                      ),
                    );
                  }
                  Navigator.of(context).pop(shortcuts);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutCard(int index) {
    final amountController = _amountControllers[index];
    final previewAmount = int.tryParse(amountController.text.trim());
    final previewLabel = previewAmount == null || previewAmount <= 0
        ? 'Not set'
        : '$previewAmount ${_units[index].label}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                index == 0
                    ? 'Primary Button'
                    : index == 1
                    ? 'Secondary Button'
                    : 'Extra Button',
                style: const TextStyle(
                  color: Color(0xFF2F3441),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2EEFF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  previewLabel,
                  style: const TextStyle(
                    color: Color(0xFF6049E3),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              if (index == 2) ...[
                InkWell(
                  onTap: () {
                    setState(() {
                      _showThirdShortcut = false;
                      _amountControllers[index].clear();
                      _units[index] = _CompletionShortcutUnit.days;
                    });
                  },
                  borderRadius: BorderRadius.circular(999),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 84,
                child: TextFormField(
                  key: ValueKey<String>('orders-editor-shortcut-amount-$index'),
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Days',
                    hintText: index == 0
                        ? '3'
                        : index == 1
                        ? '3'
                        : '7',
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _CompletionShortcutUnit.values
                      .map((unit) {
                        final isSelected = _units[index] == unit;
                        return InkWell(
                          key: unit == _CompletionShortcutUnit.days
                              ? ValueKey<String>(
                                  'orders-editor-shortcut-unit-$index',
                                )
                              : null,
                          onTap: () {
                            setState(() {
                              _units[index] = unit;
                            });
                          },
                          borderRadius: BorderRadius.circular(999),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF6049E3)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF6049E3)
                                    : const Color(0xFFD7DBE7),
                              ),
                            ),
                            child: Text(
                              unit.label,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF374151),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompletionShortcutPreset {
  const _CompletionShortcutPreset({required this.amount, required this.unit});

  final int amount;
  final _CompletionShortcutUnit unit;

  String get label => '$amount ${unit.label}';
}

class _CompletionShortcutDraft {
  const _CompletionShortcutDraft({
    required this.amountText,
    required this.unit,
  });

  final String amountText;
  final _CompletionShortcutUnit unit;
}

enum _CompletionShortcutUnit {
  days('days'),
  weeks('weeks');

  const _CompletionShortcutUnit(this.label);

  final String label;
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

class _TimelineBucket {
  const _TimelineBucket({required this.label, required this.orders});

  final String label;
  final List<OrderEntry> orders;
}

List<_TimelineBucket> _buildTimelineBuckets(List<OrderEntry> orders) {
  final now = DateUtils.dateOnly(DateTime.now());
  final tomorrow = now.add(const Duration(days: 1));
  final weekEnd = now.add(const Duration(days: 7));
  final groups = <String, List<OrderEntry>>{
    'Overdue': <OrderEntry>[],
    'Today': <OrderEntry>[],
    'Tomorrow': <OrderEntry>[],
    'This Week': <OrderEntry>[],
    'Later': <OrderEntry>[],
    'No Due Date': <OrderEntry>[],
  };
  for (final order in orders) {
    final due = order.endDate == null
        ? null
        : DateUtils.dateOnly(order.endDate!);
    if (due == null) {
      groups['No Due Date']!.add(order);
    } else if (due.isBefore(now)) {
      groups['Overdue']!.add(order);
    } else if (due == now) {
      groups['Today']!.add(order);
    } else if (due == tomorrow) {
      groups['Tomorrow']!.add(order);
    } else if (!due.isAfter(weekEnd)) {
      groups['This Week']!.add(order);
    } else {
      groups['Later']!.add(order);
    }
  }
  for (final entries in groups.values) {
    entries.sort((a, b) => _compareOrderUrgency(a, b));
  }
  return groups.entries
      .where((entry) => entry.value.isNotEmpty)
      .map((entry) => _TimelineBucket(label: entry.key, orders: entry.value))
      .toList(growable: false);
}

String _formatDate(DateTime? value) {
  if (value == null) {
    return '—';
  }
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day-$month-${value.year}';
}

bool _isDelayed(OrderEntry order) {
  final due = order.endDate == null ? null : DateUtils.dateOnly(order.endDate!);
  if (due == null) {
    return false;
  }
  final today = DateUtils.dateOnly(DateTime.now());
  if (!due.isBefore(today)) {
    return false;
  }
  return order.status != OrderStatus.closed &&
      order.status != OrderStatus.cancelled &&
      order.status != OrderStatus.dispatched;
}

int _priorityScore(OrderEntry order) {
  var score = 0;
  final today = DateUtils.dateOnly(DateTime.now());
  final due = order.endDate == null ? null : DateUtils.dateOnly(order.endDate!);
  if (due != null && due.isBefore(today)) {
    score += 100;
  } else if (due != null && due == today) {
    score += 80;
  } else if (due != null && !due.isAfter(today.add(const Duration(days: 7)))) {
    score += 45;
  }
  score += switch (order.priority) {
    OrderPriority.low => 0,
    OrderPriority.normal => 20,
    OrderPriority.high => 50,
    OrderPriority.urgent => 70,
  };
  if (order.hasMaterialShortage) {
    score += 30;
  }
  if (order.procurementPending) {
    score += 15;
  }
  score += switch (order.status) {
    OrderStatus.draft => 0,
    OrderStatus.confirmed => 30,
    OrderStatus.allocated => 35,
    OrderStatus.inProduction => 25,
    OrderStatus.completed => 10,
    OrderStatus.onHold => 40,
    OrderStatus.dispatched => 0,
    OrderStatus.closed => 0,
    OrderStatus.cancelled => 0,
  };
  return score;
}

int _compareOrderUrgency(OrderEntry a, OrderEntry b) {
  final scoreDiff = _priorityScore(b).compareTo(_priorityScore(a));
  if (scoreDiff != 0) {
    return scoreDiff;
  }
  final aDue = a.endDate;
  final bDue = b.endDate;
  if (aDue == null && bDue == null) {
    return b.createdAt.compareTo(a.createdAt);
  }
  if (aDue == null) {
    return 1;
  }
  if (bDue == null) {
    return -1;
  }
  final dueDiff = aDue.compareTo(bDue);
  if (dueDiff != 0) {
    return dueDiff;
  }
  return b.createdAt.compareTo(a.createdAt);
}

String? _defaultActionForStatus(OrderStatus status) {
  return switch (status) {
    OrderStatus.draft => 'confirm',
    OrderStatus.confirmed => 'allocate',
    OrderStatus.allocated => 'start-production',
    OrderStatus.inProduction => 'complete',
    OrderStatus.completed => 'dispatch',
    OrderStatus.dispatched => 'close',
    OrderStatus.closed => null,
    OrderStatus.onHold => 'resume',
    OrderStatus.cancelled => null,
  };
}

String _actionLabel(String action) {
  return switch (action) {
    'confirm' => 'Confirm',
    'allocate' => 'Allocate',
    'start-production' => 'Start',
    'complete' => 'Complete',
    'dispatch' => 'Dispatch',
    'close' => 'Close',
    'resume' => 'Resume',
    _ => 'Move',
  };
}

OrderStatus? _targetStatusForAction(String? action) {
  return switch (action) {
    'confirm' => OrderStatus.confirmed,
    'allocate' => OrderStatus.allocated,
    'start-production' => OrderStatus.inProduction,
    'complete' => OrderStatus.completed,
    'dispatch' => OrderStatus.dispatched,
    'close' => OrderStatus.closed,
    'resume' => OrderStatus.confirmed,
    _ => null,
  };
}

String? _actionForBoardMove({
  required OrderStatus from,
  required OrderStatus to,
}) {
  if (from == to) {
    return null;
  }
  return switch ((from, to)) {
    (OrderStatus.draft, OrderStatus.confirmed) => 'confirm',
    (OrderStatus.confirmed, OrderStatus.allocated) => 'allocate',
    (OrderStatus.allocated, OrderStatus.inProduction) => 'start-production',
    (OrderStatus.inProduction, OrderStatus.completed) => 'complete',
    (OrderStatus.completed, OrderStatus.dispatched) => 'dispatch',
    (OrderStatus.dispatched, OrderStatus.closed) => 'close',
    _ => null,
  };
}

class _OrderSummary {
  const _OrderSummary({
    required this.total,
    required this.draft,
    required this.confirmed,
    required this.inProduction,
    required this.completed,
    required this.onHold,
  });

  final int total;
  final int draft;
  final int confirmed;
  final int inProduction;
  final int completed;
  final int onHold;

  factory _OrderSummary.fromOrders(List<OrderEntry> orders) {
    var draft = 0;
    var confirmed = 0;
    var inProduction = 0;
    var completed = 0;
    var onHold = 0;

    for (final order in orders) {
      switch (order.status) {
        case OrderStatus.draft:
          draft += 1;
        case OrderStatus.confirmed:
          confirmed += 1;
        case OrderStatus.inProduction:
          inProduction += 1;
        case OrderStatus.completed:
          completed += 1;
        case OrderStatus.onHold:
          onHold += 1;
        case OrderStatus.allocated:
        case OrderStatus.dispatched:
        case OrderStatus.closed:
        case OrderStatus.cancelled:
      }
    }

    return _OrderSummary(
      total: orders.length,
      draft: draft,
      confirmed: confirmed,
      inProduction: inProduction,
      completed: completed,
      onHold: onHold,
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
}

extension on OrderPriority {
  String get label {
    return switch (this) {
      OrderPriority.low => 'Low',
      OrderPriority.normal => 'Normal',
      OrderPriority.high => 'High',
      OrderPriority.urgent => 'Urgent',
    };
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
