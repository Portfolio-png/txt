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
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';

import 'purchase_challan_screens.dart' show showPurchaseQuantitySheet;
import 'challan_mobile_editor_screen.dart';

final List<DeliveryChallanItem> activeUseLines = [];
OrderGroup? activeUseOrderGroup;

class UseInventoryBrowseScreen extends StatefulWidget {
  const UseInventoryBrowseScreen({super.key});

  @override
  State<UseInventoryBrowseScreen> createState() => _UseInventoryBrowseScreenState();
}

class _UseInventoryBrowseScreenState extends State<UseInventoryBrowseScreen> {
  bool _reviewing = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortBy = 'name_asc'; // name_asc, name_desc, qty_desc, qty_asc

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _goToChallan() async {
    if (_reviewing) return;
    _reviewing = true;
    final done = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => ChallanMobileEditorScreen(
          initialItems: List<DeliveryChallanItem>.of(activeUseLines),
          lockedType: ChallanType.internal,
          initialOrderGroup: activeUseOrderGroup,
        ),
      ),
    );
    _reviewing = false;
    if (!mounted) return;
    if (done == true) {
      setState(() {
        activeUseLines.clear();
        activeUseOrderGroup = null;
      });
    } else if (done is List<DeliveryChallanItem>) {
      setState(() {
        activeUseLines.clear();
        activeUseLines.addAll(done);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final invProvider = context.watch<InventoryProvider>();
    final unitsProvider = context.watch<UnitsProvider>();
    final allRecords = invProvider.variationStock.where((r) => r.quantity > 0).toList();
    var records = _searchQuery.isEmpty 
        ? List<VariationStockRecord>.of(allRecords)
        : allRecords.where((r) => r.itemName.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    records.sort((a, b) {
      switch (_sortBy) {
        case 'name_desc':
          return b.itemName.compareTo(a.itemName);
        case 'qty_desc':
          return b.quantity.compareTo(a.quantity);
        case 'qty_asc':
          return a.quantity.compareTo(b.quantity);
        case 'name_asc':
        default:
          return a.itemName.compareTo(b.itemName);
      }
    });

    return Scaffold(
      backgroundColor: SoftErpTheme.shellSurface,
      appBar: AppBar(
        title: const Text('Use Raw Material', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded, color: SoftErpTheme.accent),
            onSelected: (val) => setState(() => _sortBy = val),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'name_asc', child: Text('Name (A-Z)')),
              PopupMenuItem(value: 'name_desc', child: Text('Name (Z-A)')),
              PopupMenuItem(value: 'qty_desc', child: Text('Quantity (High to Low)')),
              PopupMenuItem(value: 'qty_asc', child: Text('Quantity (Low to High)')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search raw materials...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: SoftErpTheme.shellSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
          ),
          Expanded(
            child: records.isEmpty
                ? const Center(child: Text('No raw materials available in inventory.'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: records.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final r = records[index];
                      final unit = unitsProvider.findById(r.unitId);
                      final unitStr = unit != null ? ' ${unit.symbol}' : '';

                      return ListTile(
                        tileColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        leading: const Icon(Icons.inventory_2_rounded, color: SoftErpTheme.accent),
                        title: Text(r.itemName, style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text('${r.variationPathLabel}\nAvailable: ${r.quantity}$unitStr'),
                        onTap: () {
                          showPurchaseQuantitySheet(
                            context,
                            onConfirm: (qtyStr, weightStr) async {
                              final added = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => UseOrderSelectScreen(
                                    stockRecord: r,
                                    qtyStr: qtyStr,
                                    weightStr: weightStr,
                                  ),
                                ),
                              );
                              if (added == true && mounted) {
                                setState(() {});
                                _goToChallan();
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: activeUseLines.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(16),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: SoftErpTheme.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                icon: const Icon(Icons.receipt_long_rounded),
                label: Text('Review ${activeUseLines.length} Item${activeUseLines.length == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                onPressed: _goToChallan,
              ),
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortBy = 'date_desc'; // date_desc, date_asc, name_asc, name_desc

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _addToChallan(BuildContext context, OrderGroup orderGroup) {
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
      lineNo: activeUseLines.length + 1,
      hsnCode: '',
      note: 'Consumed for order ${orderGroup.orderNo}',
    );

    activeUseLines.add(item);
    
    // Store the selected order group globally so the editor can use it
    activeUseOrderGroup = orderGroup;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added to challan (total: ${activeUseLines.length})'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    Navigator.of(context).pop(true); // Back to UseInventoryBrowseScreen
  }

  @override
  Widget build(BuildContext context) {
    final ordersProvider = context.watch<OrdersProvider>();
    final allGroups = ordersProvider.filteredOrderGroups;
    
    var groups = _searchQuery.isEmpty 
        ? List<OrderGroup>.of(allGroups)
        : allGroups.where((g) => 
            g.orderNo.toLowerCase().contains(_searchQuery.toLowerCase()) || 
            g.clientName.toLowerCase().contains(_searchQuery.toLowerCase())
          ).toList();
          
    groups.sort((a, b) {
      switch (_sortBy) {
        case 'date_asc':
          return a.createdAt.compareTo(b.createdAt);
        case 'name_asc':
          return a.clientName.compareTo(b.clientName);
        case 'name_desc':
          return b.clientName.compareTo(a.clientName);
        case 'date_desc':
        default:
          return b.createdAt.compareTo(a.createdAt);
      }
    });

    return Scaffold(
      backgroundColor: SoftErpTheme.shellSurface,
      appBar: AppBar(
        title: const Text('Select Order', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded, color: SoftErpTheme.accent),
            onSelected: (val) => setState(() => _sortBy = val),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'date_desc', child: Text('Newest First')),
              PopupMenuItem(value: 'date_asc', child: Text('Oldest First')),
              PopupMenuItem(value: 'name_asc', child: Text('Client Name (A-Z)')),
              PopupMenuItem(value: 'name_desc', child: Text('Client Name (Z-A)')),
            ],
          ),
        ],
      ),
      body: _creating
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search orders...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: SoftErpTheme.shellSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  ),
                ),
                Expanded(
                  child: groups.isEmpty
                      ? const Center(child: Text('No orders found.'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: groups.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final group = groups[index];
                            final dateStr = "${group.createdAt.day.toString().padLeft(2, '0')}/${group.createdAt.month.toString().padLeft(2, '0')}/${group.createdAt.year}";
                            return ListTile(
                              tileColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              leading: const Icon(Icons.receipt_long_rounded, color: SoftErpTheme.accent),
                              title: Text(group.orderNo, style: const TextStyle(fontWeight: FontWeight.w800)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(group.clientName),
                                  const SizedBox(height: 4),
                                  Text('Date: $dateStr', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                              isThreeLine: true,
                              onTap: () => _addToChallan(context, group),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
