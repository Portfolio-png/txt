import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/inventory_repository.dart';
import '../../domain/variation_stock_entry.dart';
import '../../domain/variation_stock_record.dart';

/// v2 inventory view: groups the flat per-item/variation stock rows returned by
/// `GET /api/inventory/stock`.
class VariationStockView extends StatefulWidget {
  const VariationStockView({super.key});

  @override
  State<VariationStockView> createState() => _VariationStockViewState();
}

class _VariationStockViewState extends State<VariationStockView> {
  late Future<List<VariationStockEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<VariationStockEntry>> _load() async {
    final records = await context
        .read<InventoryRepository>()
        .getVariationStock();
    return _groupVariationStock(records);
  }

  void _refresh() {
    // Block body (not an arrow): the setState callback must return void, not the
    // assignment's Future.
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Stock'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<VariationStockEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Failed to load stock: ${snapshot.error}'),
            );
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return const Center(child: Text('No stock on hand.'));
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) => _ItemTile(item: items[index]),
            ),
          );
        },
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final VariationStockEntry item;

  @override
  Widget build(BuildContext context) {
    // Base-only item (single leaf, no variation path) reads better as a plain
    // row than a one-child expander.
    final isBaseOnly = item.variations.length <= 1;
    if (isBaseOnly) {
      return ListTile(
        title: Text(item.itemName),
        trailing: Text(_fmtQty(item.total)),
      );
    }
    return ExpansionTile(
      initiallyExpanded: true,
      title: Text(item.itemName),
      trailing: Text(_fmtQty(item.total)),
      children: [
        for (final leaf in item.variations)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            title: Text(leaf.label.isEmpty ? item.itemName : leaf.label),
            trailing: Text(_fmtQty(leaf.totalQuantity)),
          ),
      ],
    );
  }
}

String _fmtQty(double quantity) => quantity == quantity.roundToDouble()
    ? quantity.toInt().toString()
    : quantity.toStringAsFixed(2);

List<VariationStockEntry> _groupVariationStock(
  List<VariationStockRecord> records,
) {
  final grouped = <int, List<VariationStockRecord>>{};
  for (final record in records) {
    grouped
        .putIfAbsent(record.itemId, () => <VariationStockRecord>[])
        .add(record);
  }

  final entries = <VariationStockEntry>[];
  for (final itemRecords in grouped.values) {
    itemRecords.sort(
      (a, b) => a.variationLeafNodeId.compareTo(b.variationLeafNodeId),
    );
    final first = itemRecords.first;
    entries.add(
      VariationStockEntry(
        itemId: first.itemId,
        itemName: first.itemName,
        variations: [
          for (final record in itemRecords)
            VariationStockLeaf(
              leafNodeId: record.variationLeafNodeId,
              label: record.variationPathValues.join(' > '),
              totalQuantity: record.quantity,
            ),
        ],
      ),
    );
  }
  entries.sort((a, b) => a.itemName.compareTo(b.itemName));
  return entries;
}
