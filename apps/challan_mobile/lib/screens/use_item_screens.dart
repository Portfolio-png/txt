import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/features/inventory/domain/variation_stock_record.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/orders/domain/order_entry.dart';
import 'package:core_erp/features/orders/presentation/providers/orders_provider.dart';
import 'package:core_erp/features/delivery_challans/domain/delivery_challan.dart';
import 'package:core_erp/features/delivery_challans/data/delivery_challan_repository.dart';
import 'package:core_erp/features/delivery_challans/presentation/providers/delivery_challan_provider.dart';

import 'purchase_challan_screens.dart' show showPurchaseQuantitySheet;

class UseInventoryBrowseScreen extends StatefulWidget {
  const UseInventoryBrowseScreen({super.key});

  @override
  State<UseInventoryBrowseScreen> createState() => _UseInventoryBrowseScreenState();
}

class _UseInventoryBrowseScreenState extends State<UseInventoryBrowseScreen> {
  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final records = inventory.variationStock.where((r) => r.quantity > 0).toList();

    return Scaffold(
      backgroundColor: SoftErpTheme.shellSurface,
      appBar: AppBar(
        title: const Text('Use Raw Material', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      body: records.isEmpty
          ? const Center(child: Text('No raw materials available in inventory.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: records.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final r = records[index];
                return ListTile(
                  tileColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  leading: const Icon(Icons.inventory_2_rounded, color: SoftErpTheme.accent),
                  title: Text(r.itemName, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${r.variationPathLabel}\nAvailable: ${r.quantity}'),
                  onTap: () {
                    showPurchaseQuantitySheet(
                      context,
                      onConfirm: (qtyStr, weightStr, _) {
                        Navigator.of(context).pop(); // close sheet
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => UseOrderSelectScreen(
                              stockRecord: r,
                              qtyStr: qtyStr,
                              weightStr: weightStr,
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}

class UseOrderSelectScreen extends StatefulWidget {
  const UseOrderSelectScreen({
    super.key,
    required this.stockRecord,
    required this.qtyStr,
    required this.weightStr,
  });

  final VariationStockRecord stockRecord;
  final String qtyStr;
  final String weightStr;

  @override
  State<UseOrderSelectScreen> createState() => _UseOrderSelectScreenState();
}

class _UseOrderSelectScreenState extends State<UseOrderSelectScreen> {
  bool _creating = false;

  Future<void> _createInternalChallan(BuildContext context, OrderGroup orderGroup) async {
    if (_creating) return;
    setState(() => _creating = true);

    try {
      final challanProvider = context.read<DeliveryChallanProvider>();
      
      final item = DeliveryChallanItem(
        id: 0,
        orderItemId: null,
        productionRunId: null,
        itemId: widget.stockRecord.itemId,
        variationLeafNodeId: widget.stockRecord.variationLeafNodeId,
        variationPathLabel: widget.stockRecord.variationPathLabel,
        variationPathNodeIds: widget.stockRecord.variationPathNodeIds,
        customVariationValues: widget.stockRecord.customVariationValues.map(
          (k, v) => MapEntry(int.tryParse(k) ?? 0, v),
        )..removeWhere((k, v) => k == 0),
        particulars: widget.stockRecord.itemName,
        quantityPcs: widget.qtyStr,
        weight: widget.weightStr,
        lineNo: 1,
        hsnCode: '',
        note: '',
      );

      final input = DeliveryChallanDraftInput(
        type: ChallanType.internal,
        purpose: ChallanPurpose.manufacturing,
        internalPurpose: 'Consumption for order ${orderGroup.orderNo}',
        challanNo: '',
        orderId: 0,
        orderIds: const [],
        vendorId: 0,
        date: DateTime.now(),
        location: widget.stockRecord.locationId,
        sourceReference: '',
        notes: 'Used for order ${orderGroup.orderNo}',
        maintainStocks: true,
        customerName: '',
        customerGstin: '',
        vendorName: '',
        vendorGstin: '',
        items: [item],
      );

      final created = await challanProvider.createChallan(input);
      if (created != null && context.mounted) {
        context.read<InventoryProvider>().refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Raw material usage recorded successfully')),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersProvider = context.watch<OrdersProvider>();
    final groups = ordersProvider.filteredOrderGroups;

    return Scaffold(
      backgroundColor: SoftErpTheme.shellSurface,
      appBar: AppBar(
        title: const Text('Select Order', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      body: _creating
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final group = groups[index];
                return ListTile(
                  tileColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  leading: const Icon(Icons.receipt_long_rounded, color: SoftErpTheme.accent),
                  title: Text(group.orderNo, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(group.clientName),
                  onTap: () => _createInternalChallan(context, group),
                );
              },
            ),
    );
  }
}
