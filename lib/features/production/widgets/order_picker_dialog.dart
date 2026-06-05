import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/features/orders/domain/order_entry.dart';
import 'package:core_erp/features/orders/presentation/providers/orders_provider.dart';

class OrderPickerDialog extends StatefulWidget {
  const OrderPickerDialog({super.key});

  @override
  State<OrderPickerDialog> createState() => _OrderPickerDialogState();
}

class _OrderPickerDialogState extends State<OrderPickerDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OrdersProvider>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrdersProvider>();
    final activeOrders = provider.orders.where((o) =>
        o.status == OrderStatus.inProgress ||
        o.status == OrderStatus.notStarted ||
        o.status == OrderStatus.draft).toList();

    return AlertDialog(
      title: const Text('Link Order to Production Run'),
      content: SizedBox(
        width: 600,
        height: 400,
        child: provider.isLoading && activeOrders.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : activeOrders.isEmpty
                ? const Center(child: Text('No active orders found.', style: TextStyle(color: SoftErpTheme.textSecondary)))
                : ListView.separated(
                    itemCount: activeOrders.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final order = activeOrders[index];
                      return ListTile(
                        title: Text('${order.orderNo} - ${order.clientName}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${order.itemName} (${order.quantity} ${order.unitDisplayLabel})'),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: SoftErpTheme.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            order.status.name.toUpperCase(),
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: SoftErpTheme.accent),
                          ),
                        ),
                        onTap: () => Navigator.pop(context, order),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Skip (Run Without Order)', style: TextStyle(color: SoftErpTheme.textSecondary)),
        ),
      ],
    );
  }
}
