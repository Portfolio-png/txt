import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../../core/widgets/page_container.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../../clients/domain/client_definition.dart';
import '../../../clients/presentation/providers/clients_provider.dart';
import '../../../items/domain/item_definition.dart';
import '../../../items/presentation/screens/items_screen.dart';
import '../../../items/presentation/providers/items_provider.dart';
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
      builder: (context) {
        final size = MediaQuery.of(context).size;
        final dialogWidth = math.min(1499.0, size.width - 32);
        final dialogHeight = math.min(873.0, size.height - 40);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 20,
          ),
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: body,
          ),
        );
      },
    );
  }

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  static const double _contentHorizontalPadding = 0;
  final Set<int> _selectedOrderIds = <int>{};
  int? _partyFilterClientId;
  int? _itemFilterId;
  OrderStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final ordersProvider = context.watch<OrdersProvider>();
    final orders = ordersProvider.orders;
    final visibleOrders = _applyFilters(ordersProvider.filteredOrders);
    final summary = _OrderSummary.fromOrders(orders);

    _selectedOrderIds.removeWhere(
      (id) => !orders.any((order) => order.id == id),
    );

    return PageContainer(
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
  const _OrdersHeader({required this.onPrimaryCreate});

  final VoidCallback onPrimaryCreate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final button = _OrdersPrimaryButton(
          key: const Key('orders-new-order-button'),
          label: 'New Order',
          onPressed: onPrimaryCreate,
        );
        final title = Padding(
          padding: const EdgeInsets.only(left: 0),
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
          children: [filtersButton, button],
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

// ignore: unused_element
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

        final strip = constraints.maxWidth < 1040
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
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
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
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
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
              height: 86,
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
  late final TextEditingController _startDateController;
  late final TextEditingController _endDateController;

  int? _selectedClientId;
  late final List<_OrderLineDraft> _lines;
  bool _itemWiseCompletionDate = true;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _orderCompletionError;
  bool _showUploadPanel = false;

  @override
  void initState() {
    super.initState();
    _orderNoController = TextEditingController();
    _poNumberController = TextEditingController();
    _startDateController = TextEditingController();
    _endDateController = TextEditingController();
    _lines = <_OrderLineDraft>[
      _OrderLineDraft(id: DateTime.now().microsecondsSinceEpoch),
    ];
  }

  @override
  void dispose() {
    _orderNoController.dispose();
    _poNumberController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SoftErpTheme.border),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              SizedBox(
                height: 64,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compactActions = constraints.maxWidth < 1080;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Center(
                          child: Text(
                            'Create New Order',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: SoftErpTheme.textPrimary,
                                ),
                          ),
                        ),
                        Positioned(
                          right: 24,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _OrderHeaderActionButton(
                                icon: Icons.print_outlined,
                                label: 'Print',
                                compact: compactActions,
                                onTap: _handlePrintOrder,
                              ),
                              const SizedBox(width: 8),
                              _OrderHeaderActionButton(
                                icon: Icons.upload_file_outlined,
                                label: 'Upload PO',
                                compact: compactActions,
                                isActive: _showUploadPanel,
                                onTap: _toggleUploadPanel,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const Divider(height: 1, color: SoftErpTheme.border),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(36, 18, 36, 22),
                  child: !canSubmit
                      ? _DependencyMessage(
                          hasClients: clients.isNotEmpty,
                          hasItems: items.isNotEmpty,
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final isCompact = constraints.maxWidth < 720;
                            final detailsPanel = _buildOrderDetailsPanel(
                              context,
                              clients,
                            );
                            final itemsPanel = _buildOrderItemsPanel(
                              context,
                              items,
                              isCompact: isCompact,
                            );
                            final canShowUploadColumn =
                                _showUploadPanel && constraints.maxWidth >= 980;
                            final showStackedUploadPanel =
                                _showUploadPanel &&
                                !isCompact &&
                                !canShowUploadColumn;
                            if (isCompact) {
                              return Column(
                                children: [
                                  detailsPanel,
                                  const SizedBox(height: 10),
                                  itemsPanel,
                                  if (_showUploadPanel) ...[
                                    const SizedBox(height: 10),
                                    _OrderUploadPanel(
                                      onClose: _toggleUploadPanel,
                                      onAddDocument: _handleAddDocument,
                                    ),
                                  ],
                                ],
                              );
                            }
                            if (showStackedUploadPanel) {
                              return SizedBox(
                                height: 860,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            flex: 4,
                                            child: detailsPanel,
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(flex: 9, child: itemsPanel),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    SizedBox(
                                      height: 220,
                                      child: _OrderUploadPanel(
                                        onClose: _toggleUploadPanel,
                                        onAddDocument: _handleAddDocument,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return SizedBox(
                              height: 704,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: canShowUploadColumn ? 3 : 4,
                                    child: detailsPanel,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    flex: canShowUploadColumn ? 6 : 9,
                                    child: itemsPanel,
                                  ),
                                  if (canShowUploadColumn) ...[
                                    const SizedBox(width: 14),
                                    Expanded(
                                      flex: 3,
                                      child: _OrderUploadPanel(
                                        onClose: _toggleUploadPanel,
                                        onAddDocument: _handleAddDocument,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
              const Divider(height: 1, color: SoftErpTheme.border),
              Container(
                width: double.infinity,
                height: 82,
                padding: const EdgeInsets.fromLTRB(32, 16, 28, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _OrderEditorFooterButton(
                      label: 'Cancel',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 10),
                    _OrderEditorFooterButton(
                      key: const ValueKey<String>('orders-editor-save-draft'),
                      label: 'Save Draft',
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
                    const SizedBox(width: 10),
                    _OrderEditorFooterButton(
                      key: const ValueKey<String>('orders-editor-create-order'),
                      label: 'Save',
                      isPrimary: true,
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

  void _toggleUploadPanel() {
    setState(() {
      _showUploadPanel = !_showUploadPanel;
    });
  }

  void _handlePrintOrder() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Print order coming soon')));
  }

  void _handleAddDocument() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Document upload coming soon')),
    );
  }

  Widget _buildOrderDetailsPanel(
    BuildContext context,
    List<ClientDefinition> clients,
  ) {
    return _OrderEditorPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OrderEditorField(
            label: 'Order Code',
            child: TextFormField(
              key: const ValueKey<String>('orders-editor-order-no-field'),
              controller: _orderNoController,
              decoration: _inputDecoration(
                hintText: '123456',
                suffixIcon: Icons.edit_outlined,
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
          const SizedBox(height: 28),
          _OrderEditorField(
            label: 'Client Name',
            child: SearchableSelectField<int>(
              key: const ValueKey<String>('orders-editor-client-field'),
              tapTargetKey: const ValueKey<String>(
                'orders-editor-client-field',
              ),
              value: _selectedClientId,
              decoration: _inputDecoration(hintText: 'Select'),
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
          if (_selectedClientId != null &&
              _resolveClientCode(_selectedClient(clients)).isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Selected client has no client code in master.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: SoftErpTheme.dangerText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 28),
          _OrderEditorField(
            label: 'Purchase Order No.',
            child: TextFormField(
              key: const ValueKey<String>('orders-editor-po-number-field'),
              controller: _poNumberController,
              decoration: _inputDecoration(hintText: 'PO-123'),
              textInputAction: TextInputAction.next,
            ),
          ),
          const SizedBox(height: 28),
          _DateField(
            key: const ValueKey<String>('orders-editor-start-date-field'),
            label: 'Start Date',
            controller: _startDateController,
            onTap: () => _pickDate(
              context,
              initial: _startDate ?? DateTime.now(),
              onSelected: (value) {
                setState(() {
                  _startDate = value;
                  _startDateController.text = _formatDate(value);
                  _clearCompletionErrors();
                });
              },
            ),
          ),
          const SizedBox(height: 28),
          _OrderEditorField(
            label: 'Order Completion Date',
            child: TextFormField(
              key: const ValueKey<String>('orders-editor-end-date-field'),
              controller: _endDateController,
              onFieldSubmitted: (_) => _normalizeOrderCompletionDate(),
              onTapOutside: (_) => _normalizeOrderCompletionDate(),
              readOnly: _itemWiseCompletionDate,
              enabled: !_itemWiseCompletionDate,
              decoration: _inputDecoration(
                hintText: '25 - 05 - 2026',
                errorText: _orderCompletionError,
                suffixIcon: Icons.calendar_today_outlined,
                onSuffixTap: _itemWiseCompletionDate
                    ? null
                    : () => _pickDate(
                        context,
                        initial: _endDate ?? _startDate ?? DateTime.now(),
                        onSelected: (value) {
                          setState(() {
                            _endDate = value;
                            _endDateController.text = _formatDate(value);
                            _orderCompletionError = null;
                            _syncLineCompletionDates(value);
                          });
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          _ItemWiseCompletionToggle(
            value: _itemWiseCompletionDate,
            onChanged: (value) {
              setState(() {
                _itemWiseCompletionDate = value ?? false;
                if (_itemWiseCompletionDate) {
                  _orderCompletionError = null;
                  _recalculateOrderCompletionFromLines();
                } else if (_endDate != null) {
                  _syncLineCompletionDates(_endDate);
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItemsPanel(
    BuildContext context,
    List<ItemDefinition> items, {
    required bool isCompact,
  }) {
    return _OrderEditorPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hasBoundedHeight = constraints.maxHeight.isFinite;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Orders Items',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SoftErpTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (!isCompact) ...[
                _OrderItemsHeader(showCompletionDate: _itemWiseCompletionDate),
                const SizedBox(height: 20),
              ],
              if (hasBoundedHeight && !isCompact)
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      for (var index = 0; index < _lines.length; index++) ...[
                        _buildDesktopOrderItemSection(context, items, index),
                        if (index != _lines.length - 1)
                          const SizedBox(height: 14),
                      ],
                    ],
                  ),
                )
              else
                Column(
                  children: [
                    for (var index = 0; index < _lines.length; index++) ...[
                      if (isCompact)
                        _buildCompactOrderItemSection(context, items, index)
                      else
                        _buildDesktopOrderItemSection(context, items, index),
                      if (index != _lines.length - 1)
                        SizedBox(height: isCompact ? 18 : 14),
                    ],
                  ],
                ),
              const SizedBox(height: 10),
              _AddOrderItemButton(onPressed: _addLine),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCompactOrderItemSection(
    BuildContext context,
    List<ItemDefinition> items,
    int index,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OrderEditorField(
          label: 'Item',
          child: _buildItemSelectForLine(items, index),
        ),
        const SizedBox(height: 10),
        _OrderEditorField(label: 'Unit', child: _buildUnitField()),
        if (_itemWiseCompletionDate) ...[
          const SizedBox(height: 10),
          _OrderEditorField(
            label: 'Completion Date',
            child: _buildCompletionDateFieldForLine(context, index),
          ),
        ],
        if (index > 0) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _removeLine(index),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Remove item'),
              style: TextButton.styleFrom(
                foregroundColor: SoftErpTheme.dangerText,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDesktopOrderItemSection(
    BuildContext context,
    List<ItemDefinition> items,
    int index,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OrderItemsRow(
          itemField: _buildItemSelectForLine(items, index),
          unitField: _buildUnitField(),
          completionDateField: _itemWiseCompletionDate
              ? _buildCompletionDateFieldForLine(context, index)
              : null,
          onDelete: index == 0 ? null : () => _removeLine(index),
        ),
      ],
    );
  }

  Widget _buildItemSelectForLine(List<ItemDefinition> items, int index) {
    final line = _lines[index];
    final fieldKey = index == 0
        ? const ValueKey<String>('orders-editor-item-field')
        : ValueKey<String>('orders-editor-item-field-${line.id}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SearchableSelectField<int>(
          key: fieldKey,
          tapTargetKey: fieldKey,
          value: line.selectedItemId,
          decoration: _inputDecoration(hintText: 'Dolly'),
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
          onCreateOption: (query) =>
              _quickCreateItemForLine(context, lineIndex: index, name: query),
          createOptionLabelBuilder: (query) => 'Create item "$query"',
          onChanged: (value) {
            setState(() {
              line.selectedItemId = value;
              final latestItems = context.read<ItemsProvider>().items;
              final item = _selectedItemForLine(latestItems, value);
              _syncVariationSelectionForLine(line, item);
            });
          },
          validator: (value) {
            if (value == null) {
              return 'Select an item.';
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        _buildVariationPathFieldForLine(items, index),
        if (line.variationPathError != null) ...[
          const SizedBox(height: 6),
          Text(
            line.variationPathError!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildVariationPathFieldForLine(
    List<ItemDefinition> items,
    int index,
  ) {
    final line = _lines[index];
    final item = _selectedItemForLine(items, line.selectedItemId);
    final variationBaseKey = index == 0
        ? 'orders-editor-variation-path-field'
        : 'orders-editor-line-${line.id}-variation';

    if (item == null) {
      return SearchableSelectField<int>(
        key: ValueKey<String>(variationBaseKey),
        tapTargetKey: ValueKey<String>(variationBaseKey),
        value: null,
        decoration: _inputDecoration(hintText: 'Select item first'),
        fieldEnabled: false,
        options: const <SearchableSelectOption<int>>[],
        onChanged: (_) {},
      );
    }

    final topLevelProperties = item.topLevelProperties;
    if (topLevelProperties.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF4C98B)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This item has no variation structure yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF9A3412),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Open the item and create its first property/variation on the go.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF9A3412)),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _openItemVariationEditorForLine(
                  context,
                  items: items,
                  lineIndex: index,
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Open Item to Add Variation'),
              ),
            ),
          ],
        ),
      );
    }

    final selectedRootProperty = _selectedRootPropertyForLine(item, line);
    final selectedLeaf = _selectedLeafForLine(
      item,
      line.selectedVariationLeafId,
    );
    final selectedPropertyCount = line.selectedVariationValueNodeIds.length;

    return InkWell(
      key: ValueKey<String>(variationBaseKey),
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openVariationPathSelectorForLine(
        context,
        items: items,
        lineIndex: index,
      ),
      child: InputDecorator(
        decoration: _inputDecoration(
          hintText: 'Select variation path',
          suffixIcon: Icons.route_rounded,
        ),
        isEmpty: selectedLeaf == null && selectedRootProperty == null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  selectedPropertyCount == 0
                      ? 'Select variation path'
                      : 'Selected $selectedPropertyCount ${selectedPropertyCount == 1 ? 'property' : 'properties'}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: selectedPropertyCount == 0
                        ? SoftErpTheme.textSecondary
                        : SoftErpTheme.textPrimary,
                    fontWeight: selectedPropertyCount == 0
                        ? FontWeight.w500
                        : FontWeight.w600,
                  ),
                ),
                if (selectedRootProperty != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3EFFD),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: SoftErpTheme.border),
                    ),
                    child: Text(
                      selectedRootProperty.name.trim().isEmpty
                          ? 'Group selected'
                          : selectedRootProperty.name.trim(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SoftErpTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              selectedLeaf == null
                  ? 'Open selector to choose properties horizontally.'
                  : 'Tap to edit the variation path.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitField() {
    return TextFormField(
      initialValue: 'Pieces',
      readOnly: true,
      decoration: _inputDecoration(
        hintText: 'Pieces',
        suffixIcon: Icons.keyboard_arrow_down_rounded,
      ),
    );
  }

  Widget _buildCompletionDateFieldForLine(BuildContext context, int index) {
    final line = _lines[index];
    final fieldKey = index == 0
        ? const ValueKey<String>('orders-editor-completion-date-field')
        : ValueKey<String>('orders-editor-completion-date-field-${line.id}');
    return TextFormField(
      key: fieldKey,
      controller: line.completionDateController,
      enabled: _itemWiseCompletionDate,
      onFieldSubmitted: (_) => _normalizeCompletionDateLine(index),
      onTapOutside: (_) => _normalizeCompletionDateLine(index),
      decoration: _inputDecoration(
        hintText: '25 - 05 - 2026',
        errorText: line.completionDateError,
        suffixIcon: Icons.calendar_today_outlined,
        onSuffixTap: !_itemWiseCompletionDate
            ? null
            : () => _pickDate(
                context,
                initial:
                    line.completionDate ??
                    _endDate ??
                    _startDate ??
                    DateTime.now(),
                onSelected: (value) {
                  setState(() {
                    line.completionDate = value;
                    line.completionDateController.text = _formatDate(value);
                    line.completionDateError = null;
                    if (_itemWiseCompletionDate) {
                      _recalculateOrderCompletionFromLines();
                    }
                  });
                },
              ),
      ),
    );
  }

  Future<SearchableSelectOption<int>?> _quickCreateItemForLine(
    BuildContext context, {
    required int lineIndex,
    required String name,
  }) async {
    final created = await ItemsScreen.openEditor(
      context,
      initialName: name.trim(),
    );
    if (!mounted || created == null) {
      return null;
    }
    setState(() {
      _syncVariationSelectionForLine(_lines[lineIndex], created);
    });
    return SearchableSelectOption<int>(
      value: created.id,
      label: created.displayName,
    );
  }

  Future<void> _openItemVariationEditorForLine(
    BuildContext context, {
    required List<ItemDefinition> items,
    required int lineIndex,
  }) async {
    final line = _lines[lineIndex];
    final item = _selectedItemForLine(items, line.selectedItemId);
    if (item == null) {
      return;
    }
    final updated = await ItemsScreen.openEditor(context, item: item);
    if (!mounted || updated == null) {
      return;
    }
    setState(() {
      line.selectedItemId = updated.id;
      _syncVariationSelectionForLine(line, updated);
    });
  }

  Future<void> _openVariationPathSelectorForLine(
    BuildContext context, {
    required List<ItemDefinition> items,
    required int lineIndex,
  }) async {
    final line = _lines[lineIndex];
    final item = _selectedItemForLine(items, line.selectedItemId);
    if (item == null) {
      return;
    }
    final result = await showDialog<_VariationPathSelectionResult>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 560),
          child: _VariationPathSelectorDialog(
            item: item,
            initialRootPropertyId: line.selectedRootPropertyId,
            initialValueNodeIds: line.selectedVariationValueNodeIds,
            onCreateValue:
                ({
                  required item,
                  required propertyNodeId,
                  required propertyLabel,
                  required valueName,
                }) {
                  return _appendVariationValue(
                    context,
                    item: item,
                    propertyNodeId: propertyNodeId,
                    propertyLabel: propertyLabel,
                    valueName: valueName,
                  );
                },
          ),
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    setState(() {
      line.selectedItemId = result.item.id;
      _syncVariationSelectionForLine(
        line,
        result.item,
        rootPropertyId: result.rootPropertyId,
        valueNodeIds: result.valueNodeIds,
        leaf: result.leaf,
      );
    });
  }

  Future<QuickCreateVariationValueResult?> _appendVariationValue(
    BuildContext context, {
    required ItemDefinition item,
    required int propertyNodeId,
    required String propertyLabel,
    required String valueName,
  }) async {
    final itemsProvider = context.read<ItemsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await itemsProvider.appendVariationValue(
      itemId: item.id,
      propertyNodeId: propertyNodeId,
      valueName: valueName,
    );
    if (!mounted) {
      return null;
    }
    if (result == null) {
      final message =
          itemsProvider.errorMessage ?? 'Unable to create variation.';
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return null;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text('Variation "$valueName" added to $propertyLabel.'),
      ),
    );
    return result;
  }

  void _syncLineCompletionDates(DateTime? value) {
    _endDate = value;
    _endDateController.text = value == null ? '' : _formatDate(value);
    for (final line in _lines) {
      line.completionDate = value;
      line.completionDateController.text = value == null
          ? ''
          : _formatDate(value);
      line.completionDateError = null;
    }
  }

  void _addLine() {
    setState(() {
      final line = _OrderLineDraft(id: DateTime.now().microsecondsSinceEpoch);
      if (!_itemWiseCompletionDate && _endDate != null) {
        line.completionDate = _endDate;
        line.completionDateController.text = _formatDate(_endDate!);
      }
      _lines.add(line);
      if (_itemWiseCompletionDate) {
        _recalculateOrderCompletionFromLines();
      }
    });
  }

  void _removeLine(int index) {
    if (index <= 0 || index >= _lines.length) {
      return;
    }
    setState(() {
      final line = _lines.removeAt(index);
      line.dispose();
      if (_itemWiseCompletionDate) {
        _recalculateOrderCompletionFromLines();
      }
    });
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
    final completionInputsValid = _normalizeCompletionDateInputs();
    if (!completionInputsValid) {
      return;
    }

    final selectedClient = _selectedClient(clients);
    final clientCode = _resolveClientCode(selectedClient);
    final isDraft = statusOverride == OrderStatus.draft;
    if (!isDraft && clientCode.isEmpty) {
      setState(() {});
      return;
    }
    if (selectedClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a client before saving.')),
      );
      return;
    }

    final orderLines = <CreateOrderInput>[];
    for (var index = 0; index < _lines.length; index++) {
      final line = _lines[index];
      final item = _selectedItemForLine(items, line.selectedItemId);
      final leaf = _selectedLeafForLine(item, line.selectedVariationLeafId);
      final requiresVariation = item?.leafVariationNodes.isNotEmpty == true;
      if (item == null || (requiresVariation && leaf == null)) {
        setState(() {
          line.variationPathError = item == null
              ? 'Select an item first.'
              : 'Select a variation path.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              index == 0
                  ? 'Complete the first order item path.'
                  : 'Each added item row needs an item and variation path.',
            ),
          ),
        );
        return;
      }
      orderLines.add(
        CreateOrderInput(
          orderNo: _orderNoController.text,
          clientId: selectedClient.id,
          clientName: selectedClient.name,
          poNumber: _poNumberController.text,
          clientCode: clientCode,
          itemId: item.id,
          itemName: item.displayName,
          variationLeafNodeId: leaf?.id ?? 0,
          variationPathLabel: leaf == null
              ? ''
              : _variationPathOptionLabel(item, leaf),
          variationPathNodeIds: leaf == null
              ? const <int>[]
              : _pathNodeIdsForLeaf(item, leaf),
          quantity: 1,
          status: statusOverride ?? OrderStatus.notStarted,
          startDate: _startDate,
          endDate: _itemWiseCompletionDate
              ? line.completionDate ?? _endDate
              : _endDate,
        ),
      );
    }

    OrderEntry? result;
    for (final input in orderLines) {
      result = await context.read<OrdersProvider>().createOrder(input);
      if (!context.mounted) {
        return;
      }
      if (result == null) {
        break;
      }
    }

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

  bool _normalizeCompletionDateInputs() {
    var isValid = true;
    if (_itemWiseCompletionDate) {
      for (var index = 0; index < _lines.length; index++) {
        if (!_normalizeCompletionDateLine(index)) {
          isValid = false;
        }
      }
      _recalculateOrderCompletionFromLines();
    } else {
      if (!_normalizeOrderCompletionDate()) {
        isValid = false;
      }
    }
    return isValid;
  }

  bool _normalizeOrderCompletionDate() {
    final result = _resolveCompletionDateInput(_endDateController.text);
    setState(() {
      _orderCompletionError = result.error;
      if (result.date != null || _endDateController.text.trim().isEmpty) {
        _endDate = result.date;
        _endDateController.text = result.formattedText;
        if (!_itemWiseCompletionDate) {
          _syncLineCompletionDates(result.date);
        }
      }
    });
    return result.error == null;
  }

  bool _normalizeCompletionDateLine(int index) {
    if (!_itemWiseCompletionDate) {
      return true;
    }
    final line = _lines[index];
    final result = _resolveCompletionDateInput(
      line.completionDateController.text,
    );
    setState(() {
      line.completionDateError = result.error;
      if (result.date != null ||
          line.completionDateController.text.trim().isEmpty) {
        line.completionDate = result.date;
        line.completionDateController.text = result.formattedText;
        if (_itemWiseCompletionDate) {
          _recalculateOrderCompletionFromLines();
        }
      }
    });
    return result.error == null;
  }

  void _recalculateOrderCompletionFromLines() {
    final dates = _lines
        .map((line) => line.completionDate)
        .whereType<DateTime>()
        .toList(growable: false);
    if (dates.isEmpty) {
      _endDate = null;
      _endDateController.text = '';
      return;
    }
    final maxDate = dates.reduce(
      (current, next) => next.isAfter(current) ? next : current,
    );
    _endDate = maxDate;
    _endDateController.text = _formatDate(maxDate);
  }

  _CompletionDateResolution _resolveCompletionDateInput(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return const _CompletionDateResolution(date: null, formattedText: '');
    }
    final parsedDate = _tryParseFormattedDate(trimmed);
    if (parsedDate != null) {
      return _CompletionDateResolution(
        date: parsedDate,
        formattedText: _formatDate(parsedDate),
      );
    }
    final shortcutMatch = RegExp(
      r'^(\d+(?:\.\d+)?)\s*([dDmM])$',
    ).firstMatch(trimmed);
    if (shortcutMatch == null) {
      return const _CompletionDateResolution(
        error: 'Enter a valid date, 14d, or 1.5M.',
      );
    }
    if (_startDate == null) {
      return const _CompletionDateResolution(error: 'Select start date first.');
    }
    final amount = double.tryParse(shortcutMatch.group(1) ?? '');
    final unit = shortcutMatch.group(2);
    if (amount == null || amount <= 0 || unit == null) {
      return const _CompletionDateResolution(
        error: 'Enter a valid date, 14d, or 1.5M.',
      );
    }
    final dayMultiplier = unit.toLowerCase() == 'm' ? 30.0 : 1.0;
    final totalDays = (amount * dayMultiplier).round();
    final resolved = _startDate!.add(Duration(days: totalDays));
    return _CompletionDateResolution(
      date: resolved,
      formattedText: _formatDate(resolved),
    );
  }

  DateTime? _tryParseFormattedDate(String value) {
    final match = RegExp(
      r'^(\d{1,2})\s*[-/]\s*(\d{1,2})\s*[-/]\s*(\d{4})$',
    ).firstMatch(value);
    if (match == null) {
      return null;
    }
    final day = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final year = int.tryParse(match.group(3) ?? '');
    if (day == null || month == null || year == null) {
      return null;
    }
    final candidate = DateTime(year, month, day);
    if (candidate.year != year ||
        candidate.month != month ||
        candidate.day != day) {
      return null;
    }
    return candidate;
  }

  void _clearCompletionErrors() {
    _orderCompletionError = null;
    for (final line in _lines) {
      line.completionDateError = null;
    }
  }

  ItemDefinition? _selectedItemForLine(
    List<ItemDefinition> items,
    int? itemId,
  ) {
    for (final item in items) {
      if (item.id == itemId) {
        return item;
      }
    }
    return null;
  }

  ClientDefinition? _selectedClient(List<ClientDefinition> clients) {
    for (final client in clients) {
      if (client.id == _selectedClientId) {
        return client;
      }
    }
    return null;
  }

  ItemVariationNodeDefinition? _selectedLeafForLine(
    ItemDefinition? item,
    int? leafId,
  ) {
    if (item == null || leafId == null) {
      return null;
    }
    return item.leafVariationNodes
        .where((leaf) => leaf.id == leafId)
        .firstOrNull;
  }

  void _syncVariationSelectionForLine(
    _OrderLineDraft line,
    ItemDefinition? item, {
    int? rootPropertyId,
    List<int>? valueNodeIds,
    ItemVariationNodeDefinition? leaf,
  }) {
    if (item == null) {
      line.selectedRootPropertyId = null;
      line.selectedVariationValueNodeIds = const <int>[];
      line.selectedVariationLeafId = null;
      line.variationPathError = null;
      return;
    }

    final resolvedLeaf =
        leaf ?? _selectedLeafForLine(item, _defaultLeafIdForItem(item));
    final resolvedRootProperty = resolvedLeaf == null
        ? null
        : _rootPropertyForLeaf(item, resolvedLeaf);
    final nextRootPropertyId =
        rootPropertyId ??
        resolvedRootProperty?.id ??
        (item.topLevelProperties.length == 1
            ? item.topLevelProperties.first.id
            : null);
    final nextValueNodeIds =
        valueNodeIds ??
        (resolvedLeaf == null
            ? const <int>[]
            : _valueNodeIdsForLeaf(item, resolvedLeaf));
    final nextLeaf = _resolveLeafFromSelection(
      item,
      nextRootPropertyId,
      nextValueNodeIds,
    );

    line.selectedRootPropertyId = nextRootPropertyId;
    line.selectedVariationValueNodeIds = nextValueNodeIds;
    line.selectedVariationLeafId = nextLeaf?.id;
    line.variationPathError = null;
  }

  int? _defaultLeafIdForItem(ItemDefinition? item) {
    if (item == null) {
      return null;
    }
    final leaves = item.leafVariationNodes;
    if (leaves.length == 1) {
      return leaves.first.id;
    }
    return null;
  }

  ItemVariationNodeDefinition? _selectedRootPropertyForLine(
    ItemDefinition item,
    _OrderLineDraft line,
  ) {
    final roots = item.topLevelProperties;
    if (roots.isEmpty) {
      return null;
    }
    if (roots.length == 1) {
      return roots.first;
    }
    return roots
        .where((root) => root.id == line.selectedRootPropertyId)
        .firstOrNull;
  }

  ItemVariationNodeDefinition? _rootPropertyForLeaf(
    ItemDefinition item,
    ItemVariationNodeDefinition leaf,
  ) {
    return _pathNodesForLeaf(
      item,
      leaf,
    ).where((node) => node.kind == ItemVariationNodeKind.property).firstOrNull;
  }

  List<int> _valueNodeIdsForLeaf(
    ItemDefinition item,
    ItemVariationNodeDefinition leaf,
  ) {
    return _pathNodesForLeaf(item, leaf)
        .where((node) => node.kind == ItemVariationNodeKind.value)
        .map((node) => node.id)
        .toList(growable: false);
  }

  ItemVariationNodeDefinition? _resolveLeafFromSelection(
    ItemDefinition item,
    int? rootPropertyId,
    List<int> valueNodeIds,
  ) {
    if (rootPropertyId == null) {
      return null;
    }
    final root = item.topLevelProperties
        .where((property) => property.id == rootPropertyId)
        .firstOrNull;
    if (root == null) {
      return null;
    }
    if (valueNodeIds.isEmpty) {
      return null;
    }

    ItemVariationNodeDefinition? currentValue;
    ItemVariationNodeDefinition currentProperty = root;
    for (final valueId in valueNodeIds) {
      currentValue = currentProperty.activeChildren
          .where((node) => node.kind == ItemVariationNodeKind.value)
          .where((node) => node.id == valueId)
          .firstOrNull;
      if (currentValue == null) {
        return null;
      }
      final nextProperty = currentValue.activeChildren
          .where((node) => node.kind == ItemVariationNodeKind.property)
          .firstOrNull;
      if (nextProperty == null) {
        return currentValue.isLeafValue ? currentValue : null;
      }
      currentProperty = nextProperty;
    }
    return currentValue != null && currentValue.isLeafValue
        ? currentValue
        : null;
  }

  List<int> _pathNodeIdsForLeaf(
    ItemDefinition item,
    ItemVariationNodeDefinition leaf,
  ) {
    return _pathNodesForLeaf(item, leaf).map((node) => node.id).toList();
  }

  List<String> _variationBreadcrumbSegments(
    ItemDefinition item,
    ItemVariationNodeDefinition leaf,
  ) {
    final pathNodes = _pathNodesForLeaf(
      item,
      leaf,
    ).where((node) => node.name.trim().isNotEmpty).toList(growable: false);
    final segments = <String>[];

    for (var index = 0; index < pathNodes.length; index++) {
      final node = pathNodes[index];
      if (node.kind != ItemVariationNodeKind.property) {
        continue;
      }

      final propertyName = node.name.trim();
      final nextNode = index + 1 < pathNodes.length
          ? pathNodes[index + 1]
          : null;
      if (nextNode != null && nextNode.kind == ItemVariationNodeKind.value) {
        final valueName = nextNode.name.trim();
        segments.add(
          valueName.isEmpty ? propertyName : '$propertyName: $valueName',
        );
        index += 1;
        continue;
      }
      segments.add(propertyName);
    }

    if (segments.isNotEmpty) {
      return segments;
    }
    final fallback = leaf.displayName.trim().isNotEmpty
        ? leaf.displayName.trim()
        : leaf.name.trim();
    return fallback.isEmpty ? const <String>[] : <String>[fallback];
  }

  String _variationPathOptionLabel(
    ItemDefinition item,
    ItemVariationNodeDefinition leaf,
  ) {
    final segments = _variationBreadcrumbSegments(item, leaf);
    if (segments.isNotEmpty) {
      return segments.join(' / ');
    }
    final fallback = leaf.displayName.trim().isNotEmpty
        ? leaf.displayName.trim()
        : leaf.name.trim();
    return fallback.isEmpty ? 'Variation ${leaf.id}' : fallback;
  }

  List<ItemVariationNodeDefinition> _pathNodesForLeaf(
    ItemDefinition item,
    ItemVariationNodeDefinition leaf,
  ) {
    final path = <ItemVariationNodeDefinition>[];

    void visit(
      ItemVariationNodeDefinition node,
      List<ItemVariationNodeDefinition> current,
    ) {
      final next = [...current, node];
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

    for (final root in item.variationTree) {
      visit(root, const []);
    }
    return path;
  }

  String _resolveClientCode(ClientDefinition? client) {
    return client?.alias.trim() ?? '';
  }

  InputDecoration _inputDecoration({
    String? hintText,
    String? errorText,
    IconData? suffixIcon,
    VoidCallback? onSuffixTap,
  }) {
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
      suffixIcon: suffixIcon == null
          ? null
          : IconButton(
              onPressed: onSuffixTap,
              splashRadius: 18,
              icon: Icon(
                suffixIcon,
                size: 18,
                color: SoftErpTheme.textSecondary,
              ),
            ),
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

// ignore: unused_element
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

class _OrderLineDraft {
  _OrderLineDraft({required this.id})
    : completionDateController = TextEditingController();

  final int id;
  int? selectedItemId;
  int? selectedRootPropertyId;
  List<int> selectedVariationValueNodeIds = const <int>[];
  int? selectedVariationLeafId;
  DateTime? completionDate;
  String? completionDateError;
  String? variationPathError;
  final TextEditingController completionDateController;

  void dispose() {
    completionDateController.dispose();
  }
}

class _VariationStep {
  const _VariationStep({
    required this.propertyRoot,
    required this.property,
    required this.values,
    required this.selectedValueId,
  });

  final ItemVariationNodeDefinition propertyRoot;
  final ItemVariationNodeDefinition property;
  final List<ItemVariationNodeDefinition> values;
  final int? selectedValueId;
}

class _VariationPathSelectionResult {
  const _VariationPathSelectionResult({
    required this.item,
    required this.rootPropertyId,
    required this.valueNodeIds,
    required this.leaf,
  });

  final ItemDefinition item;
  final int? rootPropertyId;
  final List<int> valueNodeIds;
  final ItemVariationNodeDefinition? leaf;
}

typedef _VariationValueCreator =
    Future<QuickCreateVariationValueResult?> Function({
      required ItemDefinition item,
      required int propertyNodeId,
      required String propertyLabel,
      required String valueName,
    });

class _VariationPathSelectorDialog extends StatefulWidget {
  const _VariationPathSelectorDialog({
    required this.item,
    required this.initialRootPropertyId,
    required this.initialValueNodeIds,
    required this.onCreateValue,
  });

  final ItemDefinition item;
  final int? initialRootPropertyId;
  final List<int> initialValueNodeIds;
  final _VariationValueCreator onCreateValue;

  @override
  State<_VariationPathSelectorDialog> createState() =>
      _VariationPathSelectorDialogState();
}

class _VariationPathSelectorDialogState
    extends State<_VariationPathSelectorDialog> {
  late ItemDefinition _item;
  late int? _selectedRootPropertyId;
  late List<int> _selectedValueNodeIds;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _selectedRootPropertyId = widget.initialRootPropertyId;
    _selectedValueNodeIds = List<int>.from(widget.initialValueNodeIds);
    if (_selectedRootPropertyId == null &&
        _item.topLevelProperties.length == 1) {
      _selectedRootPropertyId = _item.topLevelProperties.first.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedRootProperty = _selectedRootProperty();
    final steps = _variationSteps(selectedRootProperty);
    final selectedLeaf = _resolveLeafFromSelection();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Variation Path',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _item.displayName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: SoftErpTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: SoftErpTheme.cardSurfaceAlt,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: SoftErpTheme.border),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_item.topLevelProperties.length > 1) ...[
                      _buildStepCard(
                        title: 'Variation Group',
                        child: _buildRootPropertyField(),
                        width: 250,
                      ),
                      if (selectedRootProperty != null) _buildArrow(),
                    ],
                    if (selectedRootProperty == null &&
                        _item.topLevelProperties.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 42),
                        child: Text(
                          'Select a variation group to continue.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: SoftErpTheme.textSecondary),
                        ),
                      )
                    else
                      for (
                        var stepIndex = 0;
                        stepIndex < steps.length;
                        stepIndex++
                      ) ...[
                        _buildStepCard(
                          title: steps[stepIndex].property.name.trim().isEmpty
                              ? 'Property ${steps[stepIndex].property.id}'
                              : steps[stepIndex].property.name.trim(),
                          child: _buildStepField(steps[stepIndex], stepIndex),
                          width: 280,
                        ),
                        if (stepIndex != steps.length - 1) _buildArrow(),
                      ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SoftErpTheme.border),
            ),
            child: Text(
              selectedLeaf == null
                  ? 'Complete the path by selecting each property.'
                  : _variationPathOptionLabel(_item, selectedLeaf),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: selectedLeaf == null
                    ? SoftErpTheme.textSecondary
                    : SoftErpTheme.textPrimary,
                fontWeight: selectedLeaf == null
                    ? FontWeight.w500
                    : FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 20),
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
                label: 'Apply Path',
                onPressed: selectedLeaf == null ? null : _submit,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRootPropertyField() {
    return SearchableSelectField<int>(
      value: _selectedRootPropertyId,
      decoration: const InputDecoration(
        hintText: 'Select variation group',
        filled: true,
        fillColor: Colors.white,
      ),
      dialogTitle: 'Variation Group',
      searchHintText: 'Search variation group',
      options: _item.topLevelProperties
          .map(
            (property) => SearchableSelectOption<int>(
              value: property.id,
              label: property.name.trim().isEmpty
                  ? 'Property ${property.id}'
                  : property.name.trim(),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        setState(() {
          _selectedRootPropertyId = value;
          _selectedValueNodeIds = const <int>[];
        });
      },
    );
  }

  Widget _buildStepField(_VariationStep step, int stepIndex) {
    return SearchableSelectField<int>(
      value: step.selectedValueId,
      decoration: const InputDecoration(
        hintText: 'Select value',
        filled: true,
        fillColor: Colors.white,
      ),
      dialogTitle: step.property.name.trim().isEmpty
          ? 'Variation Value'
          : step.property.name.trim(),
      searchHintText: 'Search value',
      createOptionLabelBuilder: (query) => 'Create value "$query"',
      onCreateOption: (query) async {
        final result = await widget.onCreateValue(
          item: _item,
          propertyNodeId: step.property.id,
          propertyLabel: step.property.name.trim().isEmpty
              ? 'Property ${step.property.id}'
              : step.property.name.trim(),
          valueName: query,
        );
        if (!mounted || result == null) {
          return null;
        }
        setState(() {
          _item = result.item;
          _selectedRootPropertyId = _rootPropertyForLeaf(
            result.item,
            result.createdValueNode,
          )?.id;
          _selectedValueNodeIds = List<int>.from(result.selectedValueNodeIds);
        });
        return SearchableSelectOption<int>(
          value: result.createdValueNode.id,
          label: result.createdValueNode.name.trim().isEmpty
              ? result.createdValueNode.displayName
              : result.createdValueNode.name.trim(),
        );
      },
      options: step.values
          .map(
            (value) => SearchableSelectOption<int>(
              value: value.id,
              label: value.name.trim().isEmpty
                  ? value.displayName
                  : value.name.trim(),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        setState(() {
          final nextValueIds = <int>[..._selectedValueNodeIds.take(stepIndex)];
          if (value != null) {
            nextValueIds.add(value);
          }
          _selectedValueNodeIds = nextValueIds;
        });
      },
    );
  }

  Widget _buildStepCard({
    required String title,
    required Widget child,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: SoftErpTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildArrow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 42, 14, 0),
      child: Icon(
        Icons.arrow_forward_rounded,
        size: 20,
        color: SoftErpTheme.textSecondary,
      ),
    );
  }

  ItemVariationNodeDefinition? _selectedRootProperty() {
    final roots = _item.topLevelProperties;
    if (roots.isEmpty) {
      return null;
    }
    if (roots.length == 1) {
      return roots.first;
    }
    return roots
        .where((root) => root.id == _selectedRootPropertyId)
        .firstOrNull;
  }

  List<_VariationStep> _variationSteps(
    ItemVariationNodeDefinition? rootProperty,
  ) {
    if (rootProperty == null) {
      return const <_VariationStep>[];
    }
    final steps = <_VariationStep>[];
    var currentProperty = rootProperty;
    var depth = 0;
    while (true) {
      final values = currentProperty.activeChildren
          .where((node) => node.kind == ItemVariationNodeKind.value)
          .toList(growable: false);
      final selectedValueId = depth < _selectedValueNodeIds.length
          ? _selectedValueNodeIds[depth]
          : null;
      final selectedValue = values
          .where((node) => node.id == selectedValueId)
          .firstOrNull;
      steps.add(
        _VariationStep(
          propertyRoot: rootProperty,
          property: currentProperty,
          values: values,
          selectedValueId: selectedValue?.id,
        ),
      );
      final nextProperty = selectedValue?.activeChildren
          .where((node) => node.kind == ItemVariationNodeKind.property)
          .firstOrNull;
      if (nextProperty == null) {
        break;
      }
      currentProperty = nextProperty;
      depth += 1;
    }
    return steps;
  }

  ItemVariationNodeDefinition? _resolveLeafFromSelection() {
    final rootProperty = _selectedRootProperty();
    if (rootProperty == null || _selectedValueNodeIds.isEmpty) {
      return null;
    }
    ItemVariationNodeDefinition? currentValue;
    ItemVariationNodeDefinition currentProperty = rootProperty;
    for (final valueId in _selectedValueNodeIds) {
      currentValue = currentProperty.activeChildren
          .where((node) => node.kind == ItemVariationNodeKind.value)
          .where((node) => node.id == valueId)
          .firstOrNull;
      if (currentValue == null) {
        return null;
      }
      final nextProperty = currentValue.activeChildren
          .where((node) => node.kind == ItemVariationNodeKind.property)
          .firstOrNull;
      if (nextProperty == null) {
        return currentValue.isLeafValue ? currentValue : null;
      }
      currentProperty = nextProperty;
    }
    return currentValue != null && currentValue.isLeafValue
        ? currentValue
        : null;
  }

  ItemVariationNodeDefinition? _rootPropertyForLeaf(
    ItemDefinition item,
    ItemVariationNodeDefinition leaf,
  ) {
    return _pathNodesForLeaf(
      item,
      leaf,
    ).where((node) => node.kind == ItemVariationNodeKind.property).firstOrNull;
  }

  List<ItemVariationNodeDefinition> _pathNodesForLeaf(
    ItemDefinition item,
    ItemVariationNodeDefinition leaf,
  ) {
    final path = <ItemVariationNodeDefinition>[];
    void visit(
      ItemVariationNodeDefinition node,
      List<ItemVariationNodeDefinition> current,
    ) {
      final next = [...current, node];
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

    for (final root in item.variationTree) {
      visit(root, const []);
    }
    return path;
  }

  String _variationPathOptionLabel(
    ItemDefinition item,
    ItemVariationNodeDefinition leaf,
  ) {
    final pathNodes = _pathNodesForLeaf(
      item,
      leaf,
    ).where((node) => node.name.trim().isNotEmpty).toList(growable: false);
    final segments = <String>[];
    for (var index = 0; index < pathNodes.length; index++) {
      final node = pathNodes[index];
      if (node.kind != ItemVariationNodeKind.property) {
        continue;
      }
      final propertyName = node.name.trim();
      final nextNode = index + 1 < pathNodes.length
          ? pathNodes[index + 1]
          : null;
      if (nextNode != null && nextNode.kind == ItemVariationNodeKind.value) {
        final valueName = nextNode.name.trim();
        segments.add(
          valueName.isEmpty ? propertyName : '$propertyName: $valueName',
        );
        index += 1;
        continue;
      }
      segments.add(propertyName);
    }
    if (segments.isNotEmpty) {
      return segments.join(' / ');
    }
    final fallback = leaf.displayName.trim().isNotEmpty
        ? leaf.displayName.trim()
        : leaf.name.trim();
    return fallback.isEmpty ? 'Variation ${leaf.id}' : fallback;
  }

  void _submit() {
    final leaf = _resolveLeafFromSelection();
    Navigator.of(context).pop(
      _VariationPathSelectionResult(
        item: _item,
        rootPropertyId: _selectedRootPropertyId,
        valueNodeIds: List<int>.from(_selectedValueNodeIds),
        leaf: leaf,
      ),
    );
  }
}

class _CompletionDateResolution {
  const _CompletionDateResolution({
    this.date,
    this.formattedText = '',
    this.error,
  });

  final DateTime? date;
  final String formattedText;
  final String? error;
}

class _OrderEditorPanel extends StatelessWidget {
  const _OrderEditorPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(32, 34, 32, 24),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFBFF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

class _OrderHeaderActionButton extends StatelessWidget {
  const _OrderHeaderActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = isActive
        ? SoftErpTheme.accentDark
        : SoftErpTheme.textPrimary;
    final backgroundColor = isActive
        ? const Color(0xFFF1EDFF)
        : const Color(0xFFFDFDFF);
    final borderColor = isActive
        ? const Color(0xFFD7CCFF)
        : SoftErpTheme.border;
    final child = compact
        ? Tooltip(
            message: label,
            child: Icon(icon, size: 18, color: foregroundColor),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: foregroundColor),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 40,
          padding: EdgeInsets.symmetric(horizontal: compact ? 11 : 14),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _OrderUploadPanel extends StatelessWidget {
  const _OrderUploadPanel({required this.onClose, required this.onAddDocument});

  final VoidCallback onClose;
  final VoidCallback onAddDocument;

  @override
  Widget build(BuildContext context) {
    final emptyStateCard = Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 180),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_upload_outlined,
            size: 48,
            color: SoftErpTheme.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            'No documents uploaded yet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: SoftErpTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Document upload will be added later',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: SoftErpTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
    return _OrderEditorPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hasBoundedHeight = constraints.maxHeight.isFinite;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Uploaded Documents',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: SoftErpTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: SoftErpTheme.textSecondary,
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (hasBoundedHeight)
                Expanded(child: emptyStateCard)
              else
                emptyStateCard,
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onAddDocument,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('Add Document'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                    foregroundColor: SoftErpTheme.textPrimary,
                    side: const BorderSide(color: SoftErpTheme.borderStrong),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OrderItemsHeader extends StatelessWidget {
  const _OrderItemsHeader({required this.showCompletionDate});

  static const double _columnGap = 14;
  static const double _actionSlotWidth = 50;
  final bool showCompletionDate;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: SoftErpTheme.textPrimary,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFF3EFFD),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Expanded(flex: 32, child: Text('Item', style: style)),
          const SizedBox(width: _OrderItemsHeader._columnGap),
          const Expanded(flex: 18, child: Text('Unit', style: style)),
          if (showCompletionDate) ...[
            const SizedBox(width: _OrderItemsHeader._columnGap),
            const Expanded(
              flex: 24,
              child: Text('Completion Date', style: style),
            ),
          ],
          const SizedBox(width: _OrderItemsHeader._actionSlotWidth),
        ],
      ),
    );
  }
}

class _OrderItemsRow extends StatelessWidget {
  const _OrderItemsRow({
    required this.itemField,
    required this.unitField,
    this.completionDateField,
    this.onDelete,
  });

  final Widget itemField;
  final Widget unitField;
  final Widget? completionDateField;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF0EEF8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 32, child: itemField),
          const SizedBox(width: _OrderItemsHeader._columnGap),
          Expanded(flex: 18, child: unitField),
          if (completionDateField != null) ...[
            const SizedBox(width: _OrderItemsHeader._columnGap),
            Expanded(flex: 24, child: completionDateField!),
          ],
          const SizedBox(width: 12),
          SizedBox(
            width: 36,
            height: 52,
            child: IconButton(
              tooltip: 'Remove item',
              padding: EdgeInsets.zero,
              onPressed: onDelete,
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: Color(0xFFEF4444),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemWiseCompletionToggle extends StatelessWidget {
  const _ItemWiseCompletionToggle({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: SoftErpTheme.accent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: const BorderSide(color: Color(0xFFD4CEFA)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Enable Item Wise Completion Date',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: SoftErpTheme.textPrimary,
                fontSize: 11,
                height: 1.25,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddOrderItemButton extends StatelessWidget {
  const _AddOrderItemButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add_rounded, size: 16),
        label: const Text('Add More Items'),
        style: OutlinedButton.styleFrom(
          foregroundColor: SoftErpTheme.accent,
          backgroundColor: const Color(0xFFFDFCFF),
          side: const BorderSide(color: Color(0xFFD4CEFA)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          alignment: Alignment.centerLeft,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _OrderEditorFooterButton extends StatelessWidget {
  const _OrderEditorFooterButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final width = switch (label) {
      'Save Draft' => 124.0,
      'Cancel' || 'Save' => 96.0,
      _ => 112.0,
    };
    return SizedBox(
      width: width,
      height: 44,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: isPrimary ? SoftErpTheme.accent : Colors.white,
          disabledBackgroundColor: isPrimary
              ? SoftErpTheme.accent.withValues(alpha: 0.45)
              : Colors.white,
          foregroundColor: isPrimary ? Colors.white : SoftErpTheme.textPrimary,
          disabledForegroundColor: isPrimary
              ? Colors.white70
              : SoftErpTheme.textSecondary,
          side: BorderSide(
            color: isPrimary ? SoftErpTheme.accent : SoftErpTheme.borderStrong,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
        ),
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
