import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/features/orders/domain/order_entry.dart';
import 'package:core_erp/features/orders/presentation/providers/orders_provider.dart';

/// Simplest mobile order view: one row per order (grouped by order no.),
/// filtered to ongoing orders by default. Pull to refresh.
class OrdersListScreen extends StatefulWidget {
  const OrdersListScreen({super.key});

  @override
  State<OrdersListScreen> createState() => _OrdersListScreenState();
}

enum _OrderFilter { ongoing, completed, all }

class _OrdersListScreenState extends State<OrdersListScreen> {
  _OrderFilter _filter = _OrderFilter.ongoing;

  static const _ongoingStatuses = {
    OrderStatus.notStarted,
    OrderStatus.inProgress,
    OrderStatus.delayed,
  };

  bool _matchesFilter(OrderGroup group) {
    switch (_filter) {
      case _OrderFilter.ongoing:
        return _ongoingStatuses.contains(group.overallStatus);
      case _OrderFilter.completed:
        return group.overallStatus == OrderStatus.completed;
      case _OrderFilter.all:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrdersProvider>();
    final groups = orders.filteredOrderGroups.where(_matchesFilter).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => context.read<OrdersProvider>().refresh(),
              child: _buildBody(orders, groups),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: SoftErpTheme.shellSurface,
      child: Row(
        children: [
          for (final f in _OrderFilter.values) ...[
            _FilterChip(
              label: switch (f) {
                _OrderFilter.ongoing => 'Ongoing',
                _OrderFilter.completed => 'Completed',
                _OrderFilter.all => 'All',
              },
              selected: _filter == f,
              onTap: () => setState(() => _filter = f),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(OrdersProvider orders, List<OrderGroup> groups) {
    if (orders.isLoading && orders.orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (orders.errorMessage != null && orders.orders.isEmpty) {
      return _CenteredMessage(
        icon: Icons.error_outline,
        title: 'Could not load orders',
        message: orders.errorMessage!,
      );
    }

    if (groups.isEmpty) {
      return _CenteredMessage(
        icon: Icons.receipt_long_outlined,
        title: switch (_filter) {
          _OrderFilter.ongoing => 'No ongoing orders',
          _OrderFilter.completed => 'No completed orders',
          _OrderFilter.all => 'No orders yet',
        },
        message: 'Pull down to refresh.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _OrderCard(group: groups[index]),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.group});

  final OrderGroup group;

  int get _totalQty =>
      group.items.fold(0, (sum, item) => sum + item.quantity);

  @override
  Widget build(BuildContext context) {
    final itemCount = group.items.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.orderNo.trim().isEmpty
                          ? 'Order #${group.clientId}'
                          : group.orderNo,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: SoftErpTheme.textPrimary,
                      ),
                    ),
                    if (group.clientName.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        group.clientName,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: SoftErpTheme.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _StatusBadge(status: group.overallStatus),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Metric(
                icon: Icons.category_outlined,
                label: itemCount == 1 ? '1 item' : '$itemCount items',
              ),
              const SizedBox(width: 16),
              _Metric(
                icon: Icons.numbers,
                label: '$_totalQty qty',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: SoftErpTheme.textSecondary),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            color: SoftErpTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final OrderStatus status;

  ({Color bg, Color fg, String label}) get _style {
    switch (status) {
      case OrderStatus.draft:
        return (bg: SoftErpTheme.sectionSurface, fg: SoftErpTheme.textSecondary, label: 'Draft');
      case OrderStatus.notStarted:
        return (bg: SoftErpTheme.infoBg, fg: SoftErpTheme.accent, label: 'Not started');
      case OrderStatus.inProgress:
        return (bg: SoftErpTheme.warningBg, fg: SoftErpTheme.warningText, label: 'In progress');
      case OrderStatus.completed:
        return (bg: SoftErpTheme.successBg, fg: SoftErpTheme.successText, label: 'Completed');
      case OrderStatus.delayed:
        return (bg: const Color(0xFFFDECEC), fg: const Color(0xFFC0392B), label: 'Delayed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        s.label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: s.fg,
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? SoftErpTheme.accent : SoftErpTheme.cardSurface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? SoftErpTheme.accent : SoftErpTheme.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : SoftErpTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.24),
        Icon(icon, size: 44, color: SoftErpTheme.textSecondary),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: SoftErpTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: SoftErpTheme.textSecondary),
        ),
      ],
    );
  }
}
