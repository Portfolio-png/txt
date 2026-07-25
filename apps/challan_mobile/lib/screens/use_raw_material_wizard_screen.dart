import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/features/inventory/domain/variation_stock_record.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/items/presentation/utils/naming_format_helper.dart';
import 'package:core_erp/features/orders/domain/order_entry.dart';
import 'package:core_erp/features/orders/presentation/providers/orders_provider.dart';
import 'package:core_erp/features/delivery_challans/domain/delivery_challan.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';

import '../widgets/wizard_progress.dart';
import 'purchase_challan_screens.dart' show showPurchaseQuantitySheet;
import 'challan_mobile_editor_screen.dart';

class UseRawMaterialWizardScreen extends StatefulWidget {
  const UseRawMaterialWizardScreen({super.key});

  @override
  State<UseRawMaterialWizardScreen> createState() => _UseRawMaterialWizardScreenState();
}

enum _Step { order, items, done }
const _stepLabels = <String>['Order', 'Items', 'Done'];

class _UseRawMaterialWizardScreenState extends State<UseRawMaterialWizardScreen> {
  _Step _step = _Step.order;

  OrderGroup? _orderGroup;
  final List<DeliveryChallanItem> _lines = [];

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortBy = 'date_desc';

  void _goTo(_Step step) {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      if (step == _Step.order) {
        _sortBy = 'date_desc';
      } else if (step == _Step.items) {
        _sortBy = 'name_asc';
      }
      _step = step;
    });
  }

  Future<bool> _confirmDiscard() async {
    if (_lines.isEmpty && _orderGroup == null) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete challan?', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Everything you\'ve added will be cleared.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD64545)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _handleBack() async {
    switch (_step) {
      case _Step.order:
        if (await _confirmDiscard() && mounted) Navigator.of(context).pop();
        break;
      case _Step.items:
        _goTo(_Step.order);
        break;
      case _Step.done:
        Navigator.of(context).pop(true);
        break;
    }
  }

  void _jumpTo(int index) {
    if (_step == _Step.done) return;
    if (index == 0) _goTo(_Step.order);
    if (index == 1 && _orderGroup != null) _goTo(_Step.items);
  }

  // --- Step 1: Order ---

  Future<void> _pickOrder(OrderGroup group) async {
    if (_lines.isNotEmpty && _orderGroup != null && _orderGroup!.orderNo != group.orderNo) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Switch order?', style: TextStyle(fontWeight: FontWeight.w700)),
          content: Text(
            'The ${_lines.length} item${_lines.length == 1 ? '' : 's'} you added '
            'are being consumed for ${_orderGroup!.orderNo}. Switching to ${group.orderNo} clears them.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Stay on ${_orderGroup!.orderNo}'),
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
      _lines.clear();
    }
    _orderGroup = group;
    _goTo(_Step.items);
  }

  Widget _buildOrderStep() {
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

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
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
                    final isActive = _lines.isNotEmpty && _orderGroup?.orderNo == group.orderNo;
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
                                '${_lines.length} in challan',
                                style: const TextStyle(
                                  color: SoftErpTheme.accent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          : const Icon(Icons.chevron_right_rounded, color: SoftErpTheme.textSecondary),
                      onTap: () => _pickOrder(group),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // --- Step 2: Items ---

  /// Values-only variation name recomposed from the live item tree — stored
  /// stock labels predate the values-only format and may still carry
  /// "Property: value" prefixes or backend pipe-joined fallbacks.
  String _recordVariationLabel(VariationStockRecord record) {
    final item = context.read<ItemsProvider>().findById(record.itemId);
    if (item == null) return record.variationPathLabel;
    final customValues = <int, String>{
      for (final entry in record.customVariationValues.entries)
        if (int.tryParse(entry.key) != null)
          int.parse(entry.key): entry.value,
    };
    final label = NamingFormatHelper.buildVariationSelectionLabel(
      item,
      record.variationPathNodeIds,
      customValues,
      false,
    );
    return label.trim().isEmpty ? record.variationPathLabel : label.trim();
  }

  void _addLine(VariationStockRecord record, String qtyStr, String weightStr) {
    setState(() {
      _lines.add(
        DeliveryChallanItem(
          id: 0,
          orderItemId: null,
          productionRunId: null,
          itemId: record.itemId,
          variationLeafNodeId: record.variationLeafNodeId,
          variationPathLabel: _recordVariationLabel(record),
          variationPathNodeIds: record.variationPathNodeIds,
          customVariationValues: record.customVariationValues.map(
            (k, v) => MapEntry(int.tryParse(k) ?? 0, v),
          )..removeWhere((k, v) => k == 0),
          particulars: record.itemName,
          quantityPcs: qtyStr,
          weight: weightStr,
          lineNo: _lines.length + 1,
          hsnCode: '',
          note: 'Consumed for order ${_orderGroup!.orderNo}',
        ),
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added ${record.itemName} (total: ${_lines.length})'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  Future<void> _goToChallanEditor() async {
    final done = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => ChallanMobileEditorScreen(
          initialItems: List<DeliveryChallanItem>.of(_lines),
          lockedType: ChallanType.internal,
          initialOrderGroup: _orderGroup,
        ),
      ),
    );
    if (!mounted) return;
    if (done == true) {
      setState(() {
        _lines.clear();
        _goTo(_Step.done);
      });
    } else if (done is List<DeliveryChallanItem>) {
      setState(() {
        _lines.clear();
        _lines.addAll(done);
      });
    }
  }

  Widget _buildItemsStep() {
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

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
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
                      subtitle: Text('${_recordVariationLabel(r)}\nAvailable: ${r.quantity}$unitStr'),
                      trailing: const Icon(Icons.add_circle_outline_rounded, color: SoftErpTheme.accent),
                      onTap: () => showPurchaseQuantitySheet(
                        context,
                        onConfirm: (qtyStr, weightStr) => _addLine(r, qtyStr, weightStr),
                      ),
                    );
                  },
                ),
        ),
        if (_lines.isNotEmpty)
          SafeArea(
            minimum: const EdgeInsets.all(16),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: SoftErpTheme.accent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              icon: const Icon(Icons.receipt_long_rounded),
              label: Text('Review ${_lines.length} Item${_lines.length == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              onPressed: _goToChallanEditor,
            ),
          ),
      ],
    );
  }

  // --- Step 3: Done ---

  Widget _buildDoneStep() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 80),
          const SizedBox(height: 16),
          const Text('Challan saved!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to Menu'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<InventoryProvider>().refresh();
        context.read<UnitsProvider>().refresh();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: SoftErpTheme.shellSurface,
        appBar: AppBar(
          title: Text(
            _step == _Step.order
                ? 'Select Order'
                : _step == _Step.items
                    ? 'Select Raw Materials'
                    : 'Done',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          leading: BackButton(onPressed: _handleBack),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.only(bottom: 12),
              child: WizardProgress(
                labels: _stepLabels,
                currentIndex: _step.index,
                onStepTapped: _jumpTo,
              ),
            ),
          ),
        ),
        body: switch (_step) {
          _Step.order => _buildOrderStep(),
          _Step.items => _buildItemsStep(),
          _Step.done => _buildDoneStep(),
        },
      ),
    );
  }
}
