import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/features/orders/domain/order_entry.dart';
import 'package:core_erp/features/orders/presentation/providers/orders_provider.dart';

class OrderPickerDialog extends StatefulWidget {
  const OrderPickerDialog({super.key});

  @override
  State<OrderPickerDialog> createState() => _OrderPickerDialogState();
}

class _OrderPickerDialogState extends State<OrderPickerDialog> {
  // Asked for, not filtered out of every order ever placed.
  //
  // This dialog only ever wanted the orders still worth putting on a machine.
  // Scanning a resident copy of the whole workspace to find them cost 5.9 KB
  // where 1.9 KB would do, and got worse with every order the shop completed.
  late Future<List<OrderEntry>> _openOrders;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _openOrders = context.read<OrdersProvider>().openOrders();
    _openOrders.whenComplete(() {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<OrderEntry>>(
      future: _openOrders,
      builder: (context, snapshot) => _buildDialog(
        context,
        snapshot.data ?? const <OrderEntry>[],
      ),
    );
  }

  Widget _buildDialog(BuildContext context, List<OrderEntry> activeOrders) {
    return AlertDialog(
      title: const Text('Link Order to Production Run'),
      content: SizedBox(
        width: 600,
        height: 400,
        child: _isLoading && activeOrders.isEmpty
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
        AppButton(
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.pop(context, null),
          label: 'Skip (Run Without Order)',
        ),
      ],
    );
  }
}
