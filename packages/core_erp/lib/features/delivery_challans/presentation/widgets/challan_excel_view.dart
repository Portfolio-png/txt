import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../domain/delivery_challan.dart';
import '../providers/delivery_challan_provider.dart';
import '../utils/challan_item_labels.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../../units/presentation/providers/units_provider.dart';

class ChallanExcelView extends StatefulWidget {
  const ChallanExcelView({
    super.key,
    this.challans,
    this.filterItemId,
    this.filterVariationLeafNodeId,
    required this.title,
  });

  final List<DeliveryChallan>? challans;
  final int? filterItemId;
  final int? filterVariationLeafNodeId;
  final String title;

  static Future<void> show(
    BuildContext context, {
    List<DeliveryChallan>? challans,
    int? filterItemId,
    int? filterVariationLeafNodeId,
    required String title,
  }) async {
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0x66100D1F),
      builder: (context) => ChallanExcelView(
        challans: challans,
        filterItemId: filterItemId,
        filterVariationLeafNodeId: filterVariationLeafNodeId,
        title: title,
      ),
    );
  }

  @override
  State<ChallanExcelView> createState() => _ChallanExcelViewState();
}

class _ChallanExcelViewState extends State<ChallanExcelView> {
  final List<DeliveryChallan> _fullChallans = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _qtyHeader = 'Qty';
  String _wtHeader = 'Weight';

  @override
  void initState() {
    super.initState();
    _loadFullDetails();
  }

  Future<void> _loadFullDetails() async {
    try {
      final provider = context.read<DeliveryChallanProvider>();
      final initialChallans = widget.challans ?? [];
      
      // If we only have filterItemId, we should fetch challans for it
      List<DeliveryChallan> challansToLoad = List.from(initialChallans);
      if (initialChallans.isEmpty && widget.filterItemId != null) {
        challansToLoad = await provider.repository.getChallans(itemId: widget.filterItemId);
      }

      final futures = challansToLoad.map((c) async {
        if (c.items.isNotEmpty && c.items.length == c.itemsCount) {
          return c;
        }
        final full = await provider.loadChallan(c.id);
        return full ?? c;
      });

      final results = await Future.wait(futures);
      if (mounted) {
        final itemsProv = context.read<ItemsProvider>();
        final unitsProv = context.read<UnitsProvider>();

        final Set<int> itemIds = {};
        for (final challan in results) {
          for (final item in challan.items) {
            if (item.itemId != null) {
              itemIds.add(item.itemId!);
            }
          }
        }

        if (widget.filterItemId != null || itemIds.length == 1) {
          final targetItemId = widget.filterItemId ?? itemIds.first;
          final labels = ChallanItemLabels.getDynamicLabels(
            itemId: targetItemId,
            itemsProv: itemsProv,
            unitsProv: unitsProv,
          );
          _qtyHeader = labels.$1;
          _wtHeader = labels.$2;
        }

        setState(() {
          for (final r in results) {
            if (!_fullChallans.any((existing) => existing.id == r.id)) {
              _fullChallans.add(r);
            }
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Real-time listener
    final provider = context.watch<DeliveryChallanProvider>();
    for (int i = 0; i < _fullChallans.length; i++) {
      final updated = provider.challans.where((c) => c.id == _fullChallans[i].id).firstOrNull;
      if (updated != null && updated.itemsCount == updated.items.length) {
        _fullChallans[i] = updated;
      }
    }
    if (widget.filterItemId != null || widget.filterVariationLeafNodeId != null) {
      for (final c in provider.challans) {
        if (c.items.any((item) {
          final itemMatch = widget.filterItemId == null || item.itemId == widget.filterItemId;
          final varMatch = widget.filterVariationLeafNodeId == null || item.variationLeafNodeId == widget.filterVariationLeafNodeId;
          return itemMatch && varMatch;
        }) && c.itemsCount == c.items.length) {
          if (!_fullChallans.any((existing) => existing.id == c.id)) {
            _fullChallans.add(c);
          }
        }
      }
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        height: MediaQuery.of(context).size.height * 0.95,
        color: SoftErpTheme.cardSurface,
        child: Column(
          children: [
            _buildHeader(context),
            const Divider(height: 1),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(child: Text(_errorMessage!))
                      : _buildTable(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          const Icon(Icons.grid_on_rounded, color: SoftErpTheme.accent),
          const SizedBox(width: 12),
          Text(
            widget.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: SoftErpTheme.textPrimary,
                ),
          ),
          const Spacer(),
          SoftPill(
            label: '${_fullChallans.length} Challans',
            background: SoftErpTheme.accent.withValues(alpha: 0.1),
            foreground: SoftErpTheme.accent,
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    if (_fullChallans.isEmpty) {
      return const Center(child: Text('No data available'));
    }

    // Flatten challans into rows based on items
    final rows = <_FlattenedRow>[];
    for (final challan in _fullChallans) {
      if (challan.items.isEmpty) {
        if (widget.filterItemId == null) {
          rows.add(_FlattenedRow(challan: challan));
        }
      } else {
        for (final item in challan.items) {
          final itemMatch = widget.filterItemId == null || item.itemId == widget.filterItemId;
          final varMatch = widget.filterVariationLeafNodeId == null || item.variationLeafNodeId == widget.filterVariationLeafNodeId;
          if (itemMatch && varMatch) {
            rows.add(_FlattenedRow(challan: challan, item: item));
          }
        }
      }
    }

    rows.sort((a, b) => a.challan.date.compareTo(b.challan.date));

    double balanceQty = 0;
    double balanceWt = 0;
    for (var row in rows) {
      final qty = double.tryParse(row.item?.quantityPcs ?? '') ?? 0;
      final wt = double.tryParse(row.item?.weight ?? '') ?? 0;
      if (row.challan.isReception) {
        balanceQty += qty;
        balanceWt += wt;
      } else if (row.challan.isDelivery) {
        balanceQty -= qty;
        balanceWt -= wt;
      }
      row.balanceQty = balanceQty;
      row.balanceWt = balanceWt;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(SoftErpTheme.cardSurfaceAlt),
          dataRowMinHeight: 48,
          dataRowMaxHeight: 56,
          headingTextStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            color: SoftErpTheme.textPrimary,
          ),
          border: TableBorder.all(
            color: SoftErpTheme.border.withValues(alpha: 0.5),
            width: 1,
          ),
          columns: [
            const DataColumn(label: Text('Date')),
            const DataColumn(label: Text('Challan No')),
            const DataColumn(label: Text('Party Name')),
            const DataColumn(label: Text('Item Particulars')),
            DataColumn(label: Text(_qtyHeader)),
            DataColumn(label: Text(_wtHeader)),
            DataColumn(label: Text('Balance Qty')),
            DataColumn(label: Text('Balance Wt')),
          ],
          rows: rows.map((row) {
            final date = row.challan.date;
            final dateStr = '${date.day.toString().padLeft(2, '0')} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][date.month - 1]} ${date.year}';
            
            // Format balances nicely
            final bQtyStr = row.balanceQty == row.balanceQty.truncateToDouble() ? row.balanceQty.toInt().toString() : row.balanceQty.toStringAsFixed(2);
            final bWtStr = row.balanceWt == row.balanceWt.truncateToDouble() ? row.balanceWt.toInt().toString() : row.balanceWt.toStringAsFixed(3);

            return DataRow(
              cells: [
                DataCell(Text(dateStr)),
                DataCell(Text(row.challan.challanNo)),
                DataCell(
                  Text(
                    row.challan.isDelivery
                        ? row.challan.customerName
                        : (row.challan.isReception
                            ? row.challan.vendorName
                            : 'Internal'),
                  ),
                ),
                DataCell(Text(row.item?.particulars ?? '-')),
                DataCell(Text(row.item?.quantityPcs ?? '-')),
                DataCell(Text(row.item?.weight ?? '-')),
                DataCell(Text(bQtyStr, style: TextStyle(color: row.balanceQty < 0 ? Colors.red : Colors.green.shade700, fontWeight: FontWeight.bold))),
                DataCell(Text(bWtStr, style: TextStyle(color: row.balanceWt < 0 ? Colors.red : Colors.green.shade700, fontWeight: FontWeight.bold))),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _FlattenedRow {
  _FlattenedRow({required this.challan, this.item});
  final DeliveryChallan challan;
  final DeliveryChallanItem? item;
  double balanceQty = 0;
  double balanceWt = 0;
}
