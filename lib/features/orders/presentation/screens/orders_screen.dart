import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../../clients/domain/client_definition.dart';
import '../../../clients/presentation/providers/clients_provider.dart';
import '../../../groups/presentation/screens/groups_screen.dart';
import '../../../items/domain/item_definition.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../../items/presentation/screens/items_screen.dart';
import '../../domain/order_entry.dart';
import '../../domain/order_inputs.dart';
import '../providers/orders_provider.dart';

Map<ShortcutActivator, VoidCallback> _submitShortcutBindings(
  VoidCallback onSubmit,
) {
  return <ShortcutActivator, VoidCallback>{
    const SingleActivator(LogicalKeyboardKey.enter, control: true): onSubmit,
    const SingleActivator(LogicalKeyboardKey.enter, meta: true): onSubmit,
  };
}

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

enum _OrdersCreateMode { group, item }

enum _OrdersQuickCreateAction { group, item }

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
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OrdersHeader(
                    onPrimaryCreate: () {
                      _handlePrimaryCreate();
                    },
                    onQuickCreateSelected: (action) {
                      _handleQuickCreate(action);
                    },
                  ),
                  const SizedBox(height: 18),
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
                      hasAnyOrders: orders.isNotEmpty,
                      hasActiveFilters:
                          _partyFilterClientId != null ||
                          _itemFilterId != null ||
                          _statusFilter != null ||
                          ordersProvider.searchQuery.trim().isNotEmpty,
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
                      onCreateOrder: () => OrdersScreen.openEditor(context),
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
    final filtered = orders
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

    filtered.sort((a, b) {
      final urgencyCompare = _urgencyWeight(
        _resolveOrderUrgency(b),
      ).compareTo(_urgencyWeight(_resolveOrderUrgency(a)));
      if (urgencyCompare != 0) {
        return urgencyCompare;
      }
      final statusCompare = _statusPriorityWeight(
        b.status,
      ).compareTo(_statusPriorityWeight(a.status));
      if (statusCompare != 0) {
        return statusCompare;
      }
      final aEnd = a.endDate;
      final bEnd = b.endDate;
      if (aEnd == null && bEnd != null) {
        return 1;
      }
      if (aEnd != null && bEnd == null) {
        return -1;
      }
      if (aEnd != null && bEnd != null) {
        final dueCompare = aEnd.compareTo(bEnd);
        if (dueCompare != 0) {
          return dueCompare;
        }
      }
      return b.createdAt.compareTo(a.createdAt);
    });
    return filtered;
  }

  Future<void> _handlePrimaryCreate() async {
    await OrdersScreen.openEditor(context);
  }

  Future<void> _handleQuickCreate(_OrdersQuickCreateAction action) async {
    switch (action) {
      case _OrdersQuickCreateAction.group:
        await GroupsScreen.openEditor(context);
      case _OrdersQuickCreateAction.item:
        await ItemsScreen.openEditor(context);
    }
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
  const _OrdersHeader({
    required this.onPrimaryCreate,
    required this.onQuickCreateSelected,
  });

  final VoidCallback onPrimaryCreate;
  final ValueChanged<_OrdersQuickCreateAction> onQuickCreateSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final button = _OrdersPrimaryButton(
          key: const Key('orders-new-order-button'),
          label: 'New Order',
          onPressed: onPrimaryCreate,
        );
        final createButton = _OrdersCreateMenuButton(
          onSelected: onQuickCreateSelected,
        );
        final title = Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            'Order Book',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: SoftErpTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
          ),
        );
        final filtersButton = Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: SoftErpTheme.cardSurface,
            border: Border.all(color: SoftErpTheme.accentDark.withAlpha(50)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.filter_list_rounded,
                size: 18,
                color: SoftErpTheme.accentDark,
              ),
              SizedBox(width: 8),
              Text(
                'Filters',
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'Segoe UI',
                  fontWeight: FontWeight.w600,
                  color: SoftErpTheme.accentDark,
                ),
              ),
            ],
          ),
        );
        final actions = Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [filtersButton, createButton, button],
        );

        final content =
            !constraints.hasBoundedWidth || constraints.maxWidth < 980
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 16), actions],
              )
            : constraints.maxWidth < 1320
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  const SizedBox(height: 16),
                  Align(alignment: Alignment.centerLeft, child: actions),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  title,
                  const SizedBox(width: 14),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: actions,
                    ),
                  ),
                ],
              );

        return content;
      },
    );
  }
}

class _OrdersCreateMenuButton extends StatelessWidget {
  const _OrdersCreateMenuButton({required this.onSelected});

  final ValueChanged<_OrdersQuickCreateAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: PopupMenuButton<_OrdersQuickCreateAction>(
        tooltip: 'Create',
        onSelected: onSelected,
        color: SoftErpTheme.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        itemBuilder: (context) => const [
          PopupMenuItem<_OrdersQuickCreateAction>(
            value: _OrdersQuickCreateAction.group,
            child: Text('Create Group'),
          ),
          PopupMenuItem<_OrdersQuickCreateAction>(
            value: _OrdersQuickCreateAction.item,
            child: Text('Create Item'),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: SoftErpTheme.cardSurface,
            border: Border.all(color: SoftErpTheme.accentDark.withAlpha(50)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Create',
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'Segoe UI',
                  fontWeight: FontWeight.w600,
                  color: SoftErpTheme.accentDark,
                ),
              ),
              SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: SoftErpTheme.accentDark,
              ),
            ],
          ),
        ),
      ),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF6A66F2), Color(0xFF5C6BF2)],
        ),
        boxShadow: SoftErpTheme.subtleShadow,
      ),
      child: SizedBox(
        height: 52,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            elevation: 0,
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, size: 18),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
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
                    color: SoftErpTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              InkWell(
                onTap: onClearSelection,
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: SoftErpTheme.cardSurfaceAlt,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: SoftErpTheme.border),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: SoftErpTheme.textSecondary,
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

        final strip = constraints.maxWidth < 980
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 10, runSpacing: 10, children: filters),
                  const SizedBox(height: 12),
                  trailing,
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Wrap(spacing: 10, runSpacing: 10, children: filters),
                  ),
                  const SizedBox(width: 14),
                  trailing,
                ],
              );

        return SoftSurface(
          radius: 24,
          color: SoftErpTheme.sectionSurface,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          elevated: true,
          child: strip,
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
    final radius = BorderRadius.circular(
      isFirst || isLast ? SoftErpTheme.radiusLg : SoftErpTheme.radiusMd,
    );
    return InkWell(
      borderRadius: radius,
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
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: SoftErpTheme.cardSurface,
          border: Border.all(color: const Color(0xFFD4DBEE)),
          borderRadius: radius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isFirst) ...[
              const Icon(
                Icons.filter_alt_outlined,
                size: 15,
                color: SoftErpTheme.textSecondary,
              ),
              const SizedBox(width: 7),
            ],
            Text(
              '$label: ',
              style: const TextStyle(
                color: SoftErpTheme.textSecondary,
                fontFamily: 'Segoe UI',
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              valueLabel,
              style: const TextStyle(
                color: SoftErpTheme.textPrimary,
                fontFamily: 'Segoe UI',
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: SoftErpTheme.textSecondary,
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
    return SoftPill(
      label: label,
      leading: Icon(icon, size: 16, color: SoftErpTheme.textSecondary),
      background: SoftErpTheme.cardSurfaceAlt,
      borderColor: SoftErpTheme.border,
      foreground: SoftErpTheme.textPrimary,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
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
    return SizedBox(
      height: 90,
      child: Row(
        children: [
          Expanded(
            child: _SummaryCard(
              label: 'All',
              value: summary.total,
              isActive: activeStatus == null,
              onTap: () => onStatusSelected(null),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _SummaryCard(
              label: 'Not Started',
              value: summary.notStarted,
              isActive: activeStatus == OrderStatus.notStarted,
              onTap: () => onStatusSelected(OrderStatus.notStarted),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _SummaryCard(
              label: 'In Progress',
              value: summary.inProgress,
              isActive: activeStatus == OrderStatus.inProgress,
              onTap: () => onStatusSelected(OrderStatus.inProgress),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _SummaryCard(
              label: 'Completed',
              value: summary.completed,
              isActive: activeStatus == OrderStatus.completed,
              onTap: () => onStatusSelected(OrderStatus.completed),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _SummaryCard(
              label: 'Delayed',
              value: summary.delayed,
              isActive: activeStatus == OrderStatus.delayed,
              onTap: () => onStatusSelected(OrderStatus.delayed),
            ),
          ),
        ],
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
      borderRadius: BorderRadius.circular(22),
      child: SoftSurface(
        radius: 22,
        color: isActive ? const Color(0xFFF7F8FC) : SoftErpTheme.cardSurface,
        strongBorder: isActive,
        elevated: true,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Text(
              '$value',
              style: const TextStyle(
                color: SoftErpTheme.textPrimary,
                fontSize: 32,
                fontFamily: 'Segoe UI',
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
    required this.hasAnyOrders,
    required this.hasActiveFilters,
    required this.selectedOrderIds,
    required this.onToggleSelection,
    required this.onRowTap,
    required this.onCreateOrder,
  });

  final List<OrderEntry> orders;
  final bool hasAnyOrders;
  final bool hasActiveFilters;
  final Set<int> selectedOrderIds;
  final void Function(int orderId, bool selected) onToggleSelection;
  final ValueChanged<OrderEntry> onRowTap;
  final VoidCallback onCreateOrder;

  @override
  Widget build(BuildContext context) {
    final hasUrgentOrders = orders.any(
      (order) => _resolveOrderUrgency(order) != _OrderUrgency.none,
    );
    if (orders.isEmpty) {
      final title = hasActiveFilters
          ? 'No orders in this state'
          : 'No orders found';
      final message = hasActiveFilters
          ? hasAnyOrders
                ? 'No matching orders for the current filters.'
                : 'Try another filter or create a new order.'
          : 'Create your first order to populate the order book.';

      return SoftSurface(
        radius: 28,
        color: Colors.transparent,
        elevated: false,
        showBorder: false,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.receipt_long_outlined,
                  size: 42,
                  color: SoftErpTheme.accentDark,
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                AppButton(
                  key: const ValueKey<String>('orders-empty-create-order'),
                  label: 'Create Order',
                  icon: Icons.add_rounded,
                  onPressed: onCreateOrder,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = _OrdersTableLayout.fromContainerWidth(
            constraints.maxWidth,
          );

          return Column(
            children: [
              if (!hasUrgentOrders) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F8EF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFCFE2CC)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 16,
                        color: Color(0xFF3E9152),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'No urgent orders — all on track',
                        style: TextStyle(
                          color: Color(0xFF3E9152),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              _TableHeaderRow(layout: layout),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 22),
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    return _OrderDataRow(
                      order: order,
                      layout: layout,
                      isSelected: selectedOrderIds.contains(order.id),
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
      padding: const EdgeInsets.only(
        left: _OrdersTableMetrics.leftPadding,
        right: _OrdersTableMetrics.rightPadding,
      ),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const SizedBox(width: _OrdersTableMetrics.prioritySlotWidth),
          _HeaderCell('Order / Date', width: layout.orderDateGroupWidth),
          _HeaderCell('Party / Item', width: layout.partyItemGroupWidth),
          _HeaderCell('Purchase Order Number', width: layout.poWidth),
          _HeaderCell('Qty', width: layout.quantityWidth),
          _HeaderCell('Start Date', width: layout.startDateWidth),
          _HeaderCell('End Date', width: layout.endDateWidth),
          _HeaderCell('Status', width: layout.statusWidth),
          _HeaderCell('Actions', width: layout.actionsWidth),
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
          color: SoftErpTheme.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _OrderDataRow extends StatefulWidget {
  const _OrderDataRow({
    required this.order,
    required this.layout,
    required this.isSelected,
    required this.onSelectionChanged,
    required this.onTap,
  });

  final OrderEntry order;
  final _OrdersTableLayout layout;
  final bool isSelected;
  final ValueChanged<bool> onSelectionChanged;
  final VoidCallback onTap;

  @override
  State<_OrderDataRow> createState() => _OrderDataRowState();
}

class _OrderDataRowState extends State<_OrderDataRow> {
  bool _hovered = false;
  bool _updatingLifecycle = false;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final layout = widget.layout;
    final urgency = _resolveOrderUrgency(order);
    final edgeTint = _rowEdgeTint(order.status, urgency);
    final markerColor = _priorityMarkerColor(urgency);
    final quickAction = _primaryQuickAction(order, urgency);
    final isCompleted = order.status == OrderStatus.completed;
    final baseColor = isCompleted
        ? const Color(0xFFF9FBFF)
        : SoftErpTheme.cardSurface;
    final hoverColor = isCompleted
        ? const Color(0xFFF5F7FD)
        : const Color(0xFFFDFDFF);
    final selectedColor = isCompleted
        ? const Color(0xFFF1F5FF)
        : const Color(0xFFF2EFFF);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(
        children: [
          SoftRowCard(
            isSelected: widget.isSelected,
            onTap: widget.onTap,
            baseColor: baseColor,
            hoverColor: hoverColor,
            selectedColor: selectedColor,
            child: SizedBox(
              height: 74,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onLongPress: () =>
                    widget.onSelectionChanged(!widget.isSelected),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          width: 150,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                edgeTint.withAlpha(0),
                                edgeTint.withAlpha(12),
                              ],
                            ),
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(22),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: _OrdersTableMetrics.leftPadding,
                        right: _OrdersTableMetrics.rightPadding,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: _OrdersTableMetrics.prioritySlotWidth,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: 2.5,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: markerColor,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                          ),
                          _GroupedDataCell(
                            width: layout.orderDateGroupWidth,
                            primary: order.orderNo,
                            secondary: _formatDate(order.createdAt),
                            primaryStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5,
                            ),
                            secondaryStyle: const TextStyle(
                              color: Color(0xFF8892A8),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          _GroupedDataCell(
                            width: layout.partyItemGroupWidth,
                            primary: order.clientName,
                            secondary:
                                order.variationPathLabel.isEmpty ||
                                    order.variationPathLabel == order.itemName
                                ? order.itemName
                                : '${order.itemName} · ${order.variationPathLabel}',
                            primaryStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          _DataCell(
                            order.poNumber.isEmpty ? '—' : order.poNumber,
                            width: layout.poWidth,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: SoftErpTheme.textSecondary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          _DataCell(
                            '${order.quantity} Pieces',
                            width: layout.quantityWidth,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                          _DataCell(
                            _formatDate(order.startDate),
                            width: layout.startDateWidth,
                            style: const TextStyle(
                              color: SoftErpTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          _DueDateCell(
                            orderId: order.id,
                            value: order.endDate,
                            width: layout.endDateWidth,
                            urgency: urgency,
                          ),
                          SizedBox(
                            width: layout.statusWidth,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _StatusPill(status: order.status),
                            ),
                          ),
                          SizedBox(
                            width: layout.actionsWidth,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: _InlineRowActions(
                                hovered: _hovered,
                                busy: _updatingLifecycle,
                                quickAction: quickAction,
                                onQuickAction: () =>
                                    _performQuickAction(quickAction),
                                onView: widget.onTap,
                                onMenu: widget.onTap,
                              ),
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
        ],
      ),
    );
  }

  Future<void> _performQuickAction(_QuickRowAction action) async {
    if (action.kind == _QuickRowActionKind.view ||
        action.kind == _QuickRowActionKind.edit) {
      widget.onTap();
      return;
    }
    if (_updatingLifecycle) {
      return;
    }
    setState(() => _updatingLifecycle = true);
    final order = widget.order;
    final now = DateTime.now();
    final result = await context.read<OrdersProvider>().updateOrderLifecycle(
      UpdateOrderLifecycleInput(
        id: order.id,
        status: action.targetStatus ?? order.status,
        startDate: action.kind == _QuickRowActionKind.start
            ? (order.startDate ?? now)
            : order.startDate,
        endDate: action.kind == _QuickRowActionKind.complete
            ? (order.endDate ?? now)
            : order.endDate,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _updatingLifecycle = false);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update order right now. Please retry.'),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${action.label} applied to ${order.orderNo}.')),
    );
  }

  Color _rowEdgeTint(OrderStatus status, _OrderUrgency urgency) {
    if (urgency == _OrderUrgency.overdue) {
      return const Color(0x22D35A5A);
    }
    return switch (status) {
      OrderStatus.draft => SoftErpTheme.draftRowEdgeTint,
      OrderStatus.notStarted => SoftErpTheme.notStartedRowEdgeTint,
      OrderStatus.inProgress => SoftErpTheme.inProgressRowEdgeTint,
      OrderStatus.completed => SoftErpTheme.completedRowEdgeTint,
      OrderStatus.delayed => SoftErpTheme.delayedRowEdgeTint,
    };
  }

  Color _priorityMarkerColor(_OrderUrgency urgency) {
    return switch (urgency) {
      _OrderUrgency.overdue => const Color(0xFFD15D5D),
      _OrderUrgency.nearDue => const Color(0xFFD08A2A),
      _OrderUrgency.none => const Color(0xFFCAD2E8),
    };
  }

  _QuickRowAction _primaryQuickAction(OrderEntry order, _OrderUrgency urgency) {
    if (order.status == OrderStatus.completed) {
      return const _QuickRowAction(
        kind: _QuickRowActionKind.view,
        label: 'View',
      );
    }
    if (order.status == OrderStatus.draft) {
      return const _QuickRowAction(
        kind: _QuickRowActionKind.edit,
        label: 'Edit',
      );
    }
    if (order.status == OrderStatus.inProgress) {
      return const _QuickRowAction(
        kind: _QuickRowActionKind.complete,
        label: 'Mark Complete',
        targetStatus: OrderStatus.completed,
      );
    }
    if (order.status == OrderStatus.notStarted ||
        order.status == OrderStatus.delayed ||
        urgency == _OrderUrgency.overdue) {
      return const _QuickRowAction(
        kind: _QuickRowActionKind.start,
        label: 'Start',
        targetStatus: OrderStatus.inProgress,
      );
    }
    return const _QuickRowAction(kind: _QuickRowActionKind.view, label: 'View');
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

enum _QuickRowActionKind { start, complete, view, edit }

class _QuickRowAction {
  const _QuickRowAction({
    required this.kind,
    required this.label,
    this.targetStatus,
  });

  final _QuickRowActionKind kind;
  final String label;
  final OrderStatus? targetStatus;
}

class _QuickHintButton extends StatelessWidget {
  const _QuickHintButton({
    required this.label,
    required this.onTap,
    this.emphasized = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool emphasized;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 26),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: emphasized
                ? const Color(0xFFEDF0FF)
                : const Color(0xFFF6F7FC),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: emphasized ? const Color(0xFFC6CCF6) : SoftErpTheme.border,
            ),
          ),
          child: busy
              ? const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: SoftErpTheme.accentDark,
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    color: emphasized
                        ? SoftErpTheme.accentDark
                        : SoftErpTheme.textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}

class _InlineRowActions extends StatelessWidget {
  const _InlineRowActions({
    required this.hovered,
    required this.busy,
    required this.quickAction,
    required this.onQuickAction,
    required this.onView,
    required this.onMenu,
  });

  final bool hovered;
  final bool busy;
  final _QuickRowAction quickAction;
  final VoidCallback onQuickAction;
  final VoidCallback onView;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showQuick = hovered || busy;
        final maxWidth = constraints.maxWidth;
        final showBothQuick = showQuick && maxWidth >= 190;
        final showPrimaryOnly = showQuick && maxWidth >= 146 && !showBothQuick;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showBothQuick || showPrimaryOnly)
              IgnorePointer(
                ignoring: !showQuick,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: showQuick ? 1 : 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _QuickHintButton(
                        label: quickAction.label,
                        emphasized: true,
                        busy: busy,
                        onTap: onQuickAction,
                      ),
                      if (showBothQuick) ...[
                        const SizedBox(width: 6),
                        _QuickHintButton(label: 'View', onTap: onView),
                      ],
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            _RowActionButton(onTap: onMenu),
          ],
        );
      },
    );
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
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Text(
          text,
          softWrap: false,
          maxLines: 1,
          overflow: overflow,
          style: const TextStyle(
            color: SoftErpTheme.textPrimary,
            fontSize: 14,
          ).merge(style),
        ),
      ),
    );
  }
}

class _GroupedDataCell extends StatelessWidget {
  const _GroupedDataCell({
    required this.width,
    required this.primary,
    required this.secondary,
    this.primaryStyle,
    this.secondaryStyle,
  });

  final double width;
  final String primary;
  final String secondary;
  final TextStyle? primaryStyle;
  final TextStyle? secondaryStyle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.only(right: 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              primary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SoftErpTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ).merge(primaryStyle),
            ),
            const SizedBox(height: 4),
            Text(
              secondary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ).merge(secondaryStyle),
            ),
          ],
        ),
      ),
    );
  }
}

class _DueDateCell extends StatelessWidget {
  const _DueDateCell({
    required this.orderId,
    required this.value,
    required this.width,
    required this.urgency,
  });

  final int orderId;
  final DateTime? value;
  final double width;
  final _OrderUrgency urgency;

  @override
  Widget build(BuildContext context) {
    final urgencyColor = switch (urgency) {
      _OrderUrgency.none => SoftErpTheme.textSecondary,
      _OrderUrgency.nearDue => const Color(0xFFB37310),
      _OrderUrgency.overdue => const Color(0xFFC76565),
    };
    final keySuffix = switch (urgency) {
      _OrderUrgency.none => 'none',
      _OrderUrgency.nearDue => 'near',
      _OrderUrgency.overdue => 'overdue',
    };

    return SizedBox(
      width: width,
      child: Row(
        children: [
          if (urgency != _OrderUrgency.none)
            Container(
              key: ValueKey<String>('orders-row-urgency-$keySuffix-$orderId'),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: urgencyColor,
                shape: BoxShape.circle,
              ),
            ),
          if (urgency != _OrderUrgency.none) const SizedBox(width: 7),
          Expanded(
            child: Text(
              _formatDate(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: urgency == _OrderUrgency.none
                    ? SoftErpTheme.textSecondary
                    : urgencyColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? entry) {
    if (entry == null) {
      return '—';
    }
    final day = entry.day.toString().padLeft(2, '0');
    final month = entry.month.toString().padLeft(2, '0');
    return '$day-$month-${entry.year}';
  }
}

class _RowActionButton extends StatefulWidget {
  const _RowActionButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_RowActionButton> createState() => _RowActionButtonState();
}

class _RowActionButtonState extends State<_RowActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _hovered
                ? const Color(0xFFEAEFFF)
                : SoftErpTheme.cardSurfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SoftErpTheme.border),
            boxShadow: _hovered
                ? const [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            Icons.more_horiz_rounded,
            size: 18,
            color: _hovered
                ? SoftErpTheme.accentDark
                : SoftErpTheme.textSecondary,
          ),
        ),
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
        bg: const Color(0xFFF1EEF8),
        border: const Color(0x00FFFFFF),
        text: const Color(0xFF6D5E8C),
      ),
      OrderStatus.notStarted => (
        bg: const Color(0xFFFDF1E3),
        border: const Color(0x00FFFFFF),
        text: const Color(0xFF9A6100),
      ),
      OrderStatus.inProgress => (
        bg: const Color(0xFFEAF2FF),
        border: const Color(0x00FFFFFF),
        text: const Color(0xFF3056BA),
      ),
      OrderStatus.completed => (
        bg: const Color(0xFFE9F8EE),
        border: const Color(0x00FFFFFF),
        text: const Color(0xFF13894A),
      ),
      OrderStatus.delayed => (
        bg: const Color(0xFFFDEDEE),
        border: const Color(0x00FFFFFF),
        text: SoftErpTheme.dangerText,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.border, width: 0.5),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: scheme.text,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _OrdersTableMetrics {
  static const double leftPadding = 34;
  static const double rightPadding = 20;
  static const double prioritySlotWidth = 14;
  static const double orderDateGroupWidth = 232;
  static const double partyItemGroupWidth = 352;
  static const double poWidth = 204;
  static const double quantityWidth = 146;
  static const double startDateWidth = 136;
  static const double endDateWidth = 136;
  static const double statusWidth = 140;
  static const double actionsWidth = 188;

  static const double totalWidth =
      leftPadding +
      rightPadding +
      prioritySlotWidth +
      orderDateGroupWidth +
      partyItemGroupWidth +
      poWidth +
      quantityWidth +
      startDateWidth +
      endDateWidth +
      statusWidth +
      actionsWidth;
}

class _OrdersTableLayout {
  const _OrdersTableLayout({
    required this.orderDateGroupWidth,
    required this.partyItemGroupWidth,
    required this.poWidth,
    required this.quantityWidth,
    required this.startDateWidth,
    required this.endDateWidth,
    required this.statusWidth,
    required this.actionsWidth,
  });

  final double orderDateGroupWidth;
  final double partyItemGroupWidth;
  final double poWidth;
  final double quantityWidth;
  final double startDateWidth;
  final double endDateWidth;
  final double statusWidth;
  final double actionsWidth;

  static _OrdersTableLayout fromContainerWidth(double containerWidth) {
    final contentWidth =
        (containerWidth -
                _OrdersTableMetrics.leftPadding -
                _OrdersTableMetrics.rightPadding -
                16)
            .clamp(0.0, double.infinity);
    final baseContentWidth =
        _OrdersTableMetrics.totalWidth -
        _OrdersTableMetrics.leftPadding -
        _OrdersTableMetrics.rightPadding;
    final scale = baseContentWidth == 0 ? 1.0 : contentWidth / baseContentWidth;

    return _OrdersTableLayout(
      orderDateGroupWidth: _OrdersTableMetrics.orderDateGroupWidth * scale,
      partyItemGroupWidth: _OrdersTableMetrics.partyItemGroupWidth * scale,
      poWidth: _OrdersTableMetrics.poWidth * scale,
      quantityWidth: _OrdersTableMetrics.quantityWidth * scale,
      startDateWidth: _OrdersTableMetrics.startDateWidth * scale,
      endDateWidth: _OrdersTableMetrics.endDateWidth * scale,
      statusWidth: _OrdersTableMetrics.statusWidth * scale,
      actionsWidth: _OrdersTableMetrics.actionsWidth * scale,
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
  OrderStatus _selectedStatus = OrderStatus.notStarted;
  DateTime? _startDate;
  DateTime? _endDate;
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
    final canSubmit = clients.isNotEmpty && items.isNotEmpty;

    return CallbackShortcuts(
      bindings: _submitShortcutBindings(() {
        if (canSubmit) {
          _submit(context, clients, items);
        }
      }),
      child: Container(
        decoration: BoxDecoration(
          color: SoftErpTheme.cardSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: SoftErpTheme.border),
          boxShadow: SoftErpTheme.raisedShadow,
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
                  border: Border(
                    bottom: BorderSide(color: SoftErpTheme.border),
                  ),
                ),
                child: Text(
                  'Create New Order',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(56, 18, 56, 18),
                  child: !canSubmit
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
                                          (client) =>
                                              SearchableSelectOption<int>(
                                                value: client.id,
                                                label: client.displayLabel,
                                              ),
                                        )
                                        .toList(growable: false),
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedClientId = value;
                                        final selected = _selectedClient(
                                          clients,
                                        );
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
                                  label: 'Status',
                                  child: SearchableSelectField<OrderStatus>(
                                    key: const ValueKey<String>(
                                      'orders-editor-status-field',
                                    ),
                                    tapTargetKey: const ValueKey<String>(
                                      'orders-editor-status-field',
                                    ),
                                    value: _selectedStatus,
                                    decoration: _inputDecoration(
                                      hintText: 'Select',
                                    ),
                                    dialogTitle: 'Status',
                                    searchHintText: 'Search status',
                                    options: OrderStatus.values
                                        .map(
                                          (status) =>
                                              SearchableSelectOption<
                                                OrderStatus
                                              >(
                                                value: status,
                                                label: status.label,
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
                                            _endDateController.text =
                                                _formatDate(value);
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
                                            label: _completionShortcuts[index]
                                                .label,
                                            onTap: () =>
                                                _applyCompletionShortcut(
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
                  border: Border(top: BorderSide(color: SoftErpTheme.border)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    AppButton(
                      label: 'Cancel',
                      variant: AppButtonVariant.secondary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    AppButton(
                      key: const ValueKey<String>('orders-editor-save-draft'),
                      label: 'Save Draft',
                      variant: AppButtonVariant.secondary,
                      onPressed: canSubmit
                          ? () => _submit(
                              context,
                              clients,
                              items,
                              statusOverride: OrderStatus.draft,
                              successMessage: 'Draft saved successfully.',
                            )
                          : null,
                    ),
                    AppButton(
                      key: const ValueKey<String>('orders-editor-create-order'),
                      label: 'Create Order',
                      onPressed: canSubmit
                          ? () => _submit(context, clients, items)
                          : null,
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

  Future<void> _submit(
    BuildContext context,
    List<ClientDefinition> clients,
    List<ItemDefinition> items, {
    OrderStatus? statusOverride,
    String successMessage = 'Order created successfully.',
  }) async {
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
        status: statusOverride ?? _selectedStatus,
        startDate: _startDate,
        endDate: _endDate,
      ),
    );

    if (!context.mounted) {
      return;
    }

    if (result != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
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
      hintStyle: const TextStyle(
        color: SoftErpTheme.textSecondary,
        fontSize: 14,
      ),
      errorText: errorText,
      filled: true,
      fillColor: SoftErpTheme.cardSurfaceAlt,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SoftErpTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SoftErpTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SoftErpTheme.accent),
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
    return CallbackShortcuts(
      bindings: _submitShortcutBindings(() => _save(context)),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: SoftErpTheme.cardSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: SoftErpTheme.border),
          boxShadow: SoftErpTheme.raisedShadow,
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: SoftErpTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            SearchableSelectField<OrderStatus>(
              key: const ValueKey<String>('orders-lifecycle-status-field'),
              tapTargetKey: const ValueKey<String>(
                'orders-lifecycle-status-field',
              ),
              value: _status,
              decoration: const InputDecoration(
                labelText: 'Status',
                filled: true,
                fillColor: SoftErpTheme.cardSurfaceAlt,
              ),
              dialogTitle: 'Status',
              searchHintText: 'Search status',
              options: OrderStatus.values
                  .map(
                    (status) => SearchableSelectOption<OrderStatus>(
                      value: status,
                      label: status.label,
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
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 10,
              children: [
                AppButton(
                  label: 'Close',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                AppButton(label: 'Save', onPressed: () => _save(context)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    final result = await context.read<OrdersProvider>().updateOrderLifecycle(
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
        const SnackBar(content: Text('Order updated successfully.')),
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
          color: SoftErpTheme.cardSurface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            bottomLeft: Radius.circular(24),
          ),
          border: Border.all(color: SoftErpTheme.border),
          boxShadow: SoftErpTheme.raisedShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Container(
              height: 60,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: const BoxDecoration(
                color: SoftErpTheme.shellSurface,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(24)),
              ),
              alignment: Alignment.centerLeft,
              child: const Text(
                'Order Details',
                style: TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
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
                            bottom: BorderSide(color: SoftErpTheme.border),
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
                                              color: SoftErpTheme.textSecondary,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            entry.value,
                                            style: const TextStyle(
                                              color: SoftErpTheme.textPrimary,
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
                                  color: SoftErpTheme.textSecondary,
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
                border: Border(top: BorderSide(color: SoftErpTheme.border)),
              ),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: [
                  AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
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
      height: 44,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          elevation: 1.5,
          backgroundColor: SoftErpTheme.accent,
          foregroundColor: Colors.white,
          shadowColor: const Color(0x14000000),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
        color: const Color(0xFFFFF2EF),
        borderRadius: BorderRadius.circular(16),
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
            color: SoftErpTheme.textSecondary,
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
          hintStyle: const TextStyle(
            color: SoftErpTheme.textSecondary,
            fontSize: 14,
          ),
          filled: true,
          fillColor: SoftErpTheme.cardSurfaceAlt,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          suffixIcon: const Icon(
            Icons.calendar_today_outlined,
            size: 18,
            color: SoftErpTheme.textSecondary,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: SoftErpTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: SoftErpTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: SoftErpTheme.accent),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isGhost ? SoftErpTheme.cardSurface : const Color(0xFFF1EEFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isGhost ? SoftErpTheme.border : const Color(0xFFD9D2FF),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isGhost ? SoftErpTheme.textSecondary : SoftErpTheme.accent,
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
    return CallbackShortcuts(
      bindings: _submitShortcutBindings(() => _save(context, visibleCount)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SoftErpTheme.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SoftErpTheme.border),
          boxShadow: SoftErpTheme.raisedShadow,
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
                color: SoftErpTheme.textSecondary,
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
                    color: SoftErpTheme.cardSurfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: SoftErpTheme.border),
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
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 10,
              children: [
                AppButton(
                  label: 'Cancel',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                AppButton(
                  label: 'Save',
                  onPressed: () => _save(context, visibleCount),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _save(BuildContext context, int visibleCount) {
    final shortcuts = <_CompletionShortcutPreset>[];
    for (var index = 0; index < visibleCount; index++) {
      final amount = int.tryParse(_amountControllers[index].text.trim());
      if (amount == null || amount <= 0) {
        continue;
      }
      shortcuts.add(
        _CompletionShortcutPreset(amount: amount, unit: _units[index]),
      );
    }
    Navigator.of(context).pop(shortcuts);
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
        color: SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SoftErpTheme.border),
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
                    fillColor: SoftErpTheme.cardSurface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: SoftErpTheme.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: SoftErpTheme.border),
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
                                  ? SoftErpTheme.accent
                                  : SoftErpTheme.cardSurface,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: isSelected
                                    ? SoftErpTheme.accent
                                    : SoftErpTheme.border,
                              ),
                            ),
                            child: Text(
                              unit.label,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : SoftErpTheme.textSecondary,
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
        color: SoftErpTheme.warningBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6CC9D)),
      ),
      child: Text(
        'Orders need $missing before a record can be created.',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: SoftErpTheme.warningText),
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
    required this.draft,
    required this.notStarted,
    required this.inProgress,
    required this.completed,
    required this.delayed,
  });

  final int total;
  final int draft;
  final int notStarted;
  final int inProgress;
  final int completed;
  final int delayed;

  factory _OrderSummary.fromOrders(List<OrderEntry> orders) {
    var draft = 0;
    var notStarted = 0;
    var inProgress = 0;
    var completed = 0;
    var delayed = 0;

    for (final order in orders) {
      switch (order.status) {
        case OrderStatus.draft:
          draft += 1;
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
      draft: draft,
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
      OrderStatus.draft => 'Draft',
      OrderStatus.notStarted => 'Not Started',
      OrderStatus.inProgress => 'In Progress',
      OrderStatus.completed => 'Completed',
      OrderStatus.delayed => 'Delayed',
    };
  }
}

_OrderUrgency _resolveOrderUrgency(OrderEntry entry) {
  if (entry.status == OrderStatus.completed || entry.endDate == null) {
    return _OrderUrgency.none;
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final dueDate = DateTime(
    entry.endDate!.year,
    entry.endDate!.month,
    entry.endDate!.day,
  );
  if (dueDate.isBefore(today)) {
    return _OrderUrgency.overdue;
  }
  final nearDueDate = today.add(const Duration(days: 3));
  if (!dueDate.isAfter(nearDueDate)) {
    return _OrderUrgency.nearDue;
  }
  return _OrderUrgency.none;
}

int _urgencyWeight(_OrderUrgency urgency) {
  return switch (urgency) {
    _OrderUrgency.overdue => 3,
    _OrderUrgency.nearDue => 2,
    _OrderUrgency.none => 1,
  };
}

int _statusPriorityWeight(OrderStatus status) {
  return switch (status) {
    OrderStatus.inProgress => 3,
    OrderStatus.notStarted => 2,
    OrderStatus.draft => 2,
    OrderStatus.delayed => 2,
    OrderStatus.completed => 0,
  };
}

enum _OrderUrgency { none, nearDue, overdue }

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
