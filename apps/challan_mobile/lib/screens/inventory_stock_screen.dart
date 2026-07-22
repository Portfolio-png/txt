import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/features/inventory/domain/variation_stock_record.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';

/// Simplest mobile stock view: each item grouped as a card showing its total
/// stock, with the per-variation breakdown beneath — mirroring the desktop
/// Inventory item → variation hierarchy. Pull to refresh.
class InventoryStockScreen extends StatefulWidget {
  const InventoryStockScreen({super.key});

  static String _formatQty(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  static List<_ItemStock> _buildGroups(
    List<VariationStockRecord> records,
    Map<int, String> unitSymbolById,
    ItemsProvider itemsProvider,
  ) {
    final byItem = <int, _ItemStock>{};
    for (final r in records) {
      final symbol = (unitSymbolById[r.unitId] ?? '').trim();
      final item = byItem.putIfAbsent(
        r.itemId,
        () {
          final def = itemsProvider.findById(r.itemId);
          String secondaryUnitSymbol = 'kg';
          double factor = 1.0;
          if (def != null && def.unitConversions.isNotEmpty) {
            secondaryUnitSymbol = def.unitConversions.first.unitSymbol;
            factor = def.unitConversions.first.factorToPrimary;
            if (factor <= 0) factor = 1.0;
          }
          return _ItemStock(
            itemName: r.itemName,
            unitSymbol: symbol,
            secondaryUnitSymbol: secondaryUnitSymbol,
            factorToPrimary: factor,
          );
        },
      );
      if (item.unitSymbol.isEmpty && symbol.isNotEmpty) item.unitSymbol = symbol;

      final existing = item.variations[r.variationLeafNodeId];
      if (existing == null) {
        item.variations[r.variationLeafNodeId] = _VariationStock(
          label: r.variationPathLabel,
          quantity: r.quantity,
        );
      } else {
        existing.quantity += r.quantity;
      }
    }

    final groups = byItem.values.toList()
      ..sort((a, b) =>
          a.itemName.toLowerCase().compareTo(b.itemName.toLowerCase()));
    return groups;
  }

  @override
  State<InventoryStockScreen> createState() => _InventoryStockScreenState();
}

class _InventoryStockScreenState extends State<InventoryStockScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<InventoryProvider>().refresh();
        context.read<UnitsProvider>().refresh();
        context.read<ItemsProvider>().refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();

    final unitSymbolById = <int, String>{
      for (final unit in context.watch<UnitsProvider>().activeUnits)
        unit.id: unit.symbol.trim().isNotEmpty ? unit.symbol : unit.name,
    };

    final itemsProvider = context.watch<ItemsProvider>();

    final groups = InventoryStockScreen._buildGroups(inventory.variationStock, unitSymbolById, itemsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<InventoryProvider>().refresh(),
          ),
          if (groups.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${groups.length} items',
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<InventoryProvider>().refresh(),
        child: _buildBody(inventory, groups),
      ),
    );
  }

  Widget _buildBody(InventoryProvider inventory, List<_ItemStock> groups) {
    if (inventory.isLoading && inventory.variationStock.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (inventory.errorMessage != null && inventory.variationStock.isEmpty) {
      return _CenteredMessage(
        icon: Icons.error_outline,
        title: 'Could not load stock',
        message: inventory.errorMessage!,
      );
    }

    if (groups.isEmpty) {
      return const _CenteredMessage(
        icon: Icons.inventory_2_outlined,
        title: 'No stock yet',
        message: 'Materials you add will appear here.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _ItemStockCard(item: groups[index]),
    );
  }
}

class _ItemStock {
  _ItemStock({
    required this.itemName,
    required this.unitSymbol,
    this.secondaryUnitSymbol = '',
    this.factorToPrimary = 1.0,
  });

  final String itemName;
  String unitSymbol;
  String secondaryUnitSymbol;
  double factorToPrimary;
  final Map<int, _VariationStock> variations = {};

  double get total =>
      variations.values.fold(0.0, (sum, v) => sum + v.quantity);
}

class _VariationStock {
  _VariationStock({required this.label, required this.quantity});

  final String label;
  double quantity;
}

class _ItemStockCard extends StatelessWidget {
  const _ItemStockCard({required this.item});

  final _ItemStock item;

  @override
  Widget build(BuildContext context) {
    final title =
        item.itemName.trim().isEmpty ? 'Unnamed item' : item.itemName.trim();
    final unit = item.unitSymbol;
    final variations = item.variations.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    return Container(
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        children: [
          // Item header with total.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: SoftErpTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  InventoryStockScreen._formatQty(item.total),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: SoftErpTheme.accent,
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    unit,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                ],
                if (item.secondaryUnitSymbol.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    '| ${InventoryStockScreen._formatQty(item.total / item.factorToPrimary)} ${item.secondaryUnitSymbol}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: SoftErpTheme.border),
          // Per-variation breakdown.
          for (final v in variations)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                children: [
                  const Icon(Icons.subdirectory_arrow_right,
                      size: 16, color: SoftErpTheme.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      v.label.trim().isEmpty ? 'Default' : v.label.trim(),
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: SoftErpTheme.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    InventoryStockScreen._formatQty(v.quantity) +
                        (unit.isEmpty ? '' : ' $unit'),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: SoftErpTheme.textPrimary,
                    ),
                  ),
                  if (item.secondaryUnitSymbol.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      '(${InventoryStockScreen._formatQty(v.quantity / item.factorToPrimary)} ${item.secondaryUnitSymbol})',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: SoftErpTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
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
    // Wrapped in a scrollable so pull-to-refresh works even when empty.
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.28),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: SoftErpTheme.textSecondary),
          ),
        ),
      ],
    );
  }
}
