import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/features/inventory/domain/variation_stock_record.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/orders/domain/order_entry.dart';
import 'package:core_erp/features/orders/presentation/providers/orders_provider.dart';
import 'package:core_erp/features/delivery_challans/domain/delivery_challan.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';

import 'purchase_challan_screens.dart' show showPurchaseQuantitySheet;
import 'challan_mobile_editor_screen.dart';

/// Lines collected for the in-progress internal-use challan, and the order they
/// are booked against. The two are one unit: a challan carries a single order,
/// so the order is chosen once in [UseOrderSelectScreen] and every line in
/// [activeUseLines] belongs to it.
final List<DeliveryChallanItem> activeUseLines = [];
OrderGroup? activeUseOrderGroup;

/// Step 1 of Use: pick the order the raw materials are consumed for. The whole
/// challan is scoped to this order, so it's asked once here rather than per
/// line — a challan can only carry one, and the last answer would otherwise
/// silently rebook every line already collected.
class UseOrderSelectScreen extends StatefulWidget {
  const UseOrderSelectScreen({super.key});

  @override
  State<UseOrderSelectScreen> createState() => _UseOrderSelectScreenState();
}

class _UseOrderSelectScreenState extends State<UseOrderSelectScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortBy = 'date_desc'; // date_desc, date_asc, name_asc, name_desc

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openOrder(OrderGroup group) async {
    final active = activeUseOrderGroup;
    // Anything already collected was consumed for the previously picked order.
    // Moving to a different one can't carry those lines across, so make the
    // loss explicit instead of rebooking them.
    if (activeUseLines.isNotEmpty && active != null && active.orderNo != group.orderNo) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Switch order?', style: TextStyle(fontWeight: FontWeight.w700)),
          content: Text(
            'The ${activeUseLines.length} item${activeUseLines.length == 1 ? '' : 's'} you added '
            'are being consumed for ${active.orderNo}. Switching to ${group.orderNo} clears them.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Stay on ${active.orderNo}'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD64545)),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Switch & clear'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      activeUseLines.clear();
    }

    activeUseOrderGroup = group;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UseInventoryBrowseScreen(orderGroup: group)),
    );
    if (mounted) setState(() {});
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
        title: const Text('Use — Select Order', style: TextStyle(fontWeight: FontWeight.w900)),
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
      body: Column(
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
                      final isActive = activeUseLines.isNotEmpty &&
                          activeUseOrderGroup?.orderNo == group.orderNo;
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
                        trailing: isActive
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: SoftErpTheme.accent.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${activeUseLines.length} in challan',
                                  style: const TextStyle(
                                    color: SoftErpTheme.accent,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              )
                            : const Icon(Icons.chevron_right_rounded, color: SoftErpTheme.textSecondary),
                        onTap: () => _openOrder(group),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Step 2 of Use: add raw materials consumed for [orderGroup]. The order is
/// fixed for the whole challan, so lines accumulate here and the editor is only
/// opened once, on Review.
class UseInventoryBrowseScreen extends StatefulWidget {
  const UseInventoryBrowseScreen({super.key, required this.orderGroup});

  /// The order every line collected here is booked against.
  final OrderGroup orderGroup;

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
          initialOrderGroup: widget.orderGroup,
        ),
      ),
    );
    _reviewing = false;
    if (!mounted) return;
    if (done == true) {
      // Submitted. The order stays selected so another challan can be started
      // for it without walking back out to the order list.
      setState(() => activeUseLines.clear());
    } else if (done is List<DeliveryChallanItem>) {
      setState(() {
        activeUseLines
          ..clear()
          ..addAll(done);
      });
    }
  }

  void _addLine(VariationStockRecord record, String qtyStr, String weightStr) {
    activeUseLines.add(
      DeliveryChallanItem(
        id: 0,
        orderItemId: null,
        productionRunId: null,
        itemId: record.itemId,
        variationLeafNodeId: record.variationLeafNodeId,
        variationPathLabel: record.variationPathLabel,
        variationPathNodeIds: record.variationPathNodeIds,
        customVariationValues: record.customVariationValues.map(
          (k, v) => MapEntry(int.tryParse(k) ?? 0, v),
        )..removeWhere((k, v) => k == 0),
        particulars: record.itemName,
        quantityPcs: qtyStr,
        weight: weightStr,
        lineNo: activeUseLines.length + 1,
        hsnCode: '',
        note: 'Consumed for order ${widget.orderGroup.orderNo}',
      ),
    );
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added ${record.itemName} (total: ${activeUseLines.length})'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  Future<void> _discardChallan() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Discard challan?', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('The items you\'ve added will be cleared.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD64545)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => activeUseLines.clear());
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Use Raw Material', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 2),
            Text(
              '${widget.orderGroup.orderNo} · ${widget.orderGroup.clientName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ],
        ),
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
          if (activeUseLines.isNotEmpty)
            IconButton(
              tooltip: 'Discard challan',
              icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFD64545)),
              onPressed: _discardChallan,
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
                        trailing: const Icon(Icons.add_circle_outline_rounded, color: SoftErpTheme.accent),
                        onTap: () => showPurchaseQuantitySheet(
                          context,
                          onConfirm: (qtyStr, weightStr) => _addLine(r, qtyStr, weightStr),
                        ),
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
