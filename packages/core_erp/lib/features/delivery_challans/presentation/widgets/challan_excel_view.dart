import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../domain/delivery_challan.dart';
import '../providers/delivery_challan_provider.dart';

class ChallanExcelView extends StatefulWidget {
  const ChallanExcelView({
    super.key,
    required this.challans,
    required this.title,
  });

  final List<DeliveryChallan> challans;
  final String title;

  static Future<void> show(
    BuildContext context, {
    required List<DeliveryChallan> challans,
    required String title,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => ChallanExcelView(challans: challans, title: title),
    );
  }

  @override
  State<ChallanExcelView> createState() => _ChallanExcelViewState();
}

class _ChallanExcelViewState extends State<ChallanExcelView> {
  final List<DeliveryChallan> _fullChallans = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFullDetails();
  }

  Future<void> _loadFullDetails() async {
    try {
      final provider = context.read<DeliveryChallanProvider>();
      final futures = widget.challans.map((c) async {
        if (c.items.isNotEmpty && c.items.length == c.itemsCount) {
          return c;
        }
        final full = await provider.loadChallan(c.id);
        return full ?? c;
      });

      final results = await Future.wait(futures);
      if (mounted) {
        setState(() {
          _fullChallans.addAll(results);
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
            label: '${widget.challans.length} Challans',
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
        rows.add(_FlattenedRow(challan: challan));
      } else {
        for (final item in challan.items) {
          rows.add(_FlattenedRow(challan: challan, item: item));
        }
      }
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
          columns: const [
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Challan No')),
            DataColumn(label: Text('Party Name')),
            DataColumn(label: Text('Item Particulars')),
            DataColumn(label: Text('Qty')),
            DataColumn(label: Text('Weight')),
            DataColumn(label: Text('Purpose')),
          ],
          rows: rows.map((row) {
            final date = row.challan.date;
            final dateStr = '${date.day.toString().padLeft(2, '0')} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][date.month - 1]} ${date.year}';
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
                DataCell(Text(row.challan.purpose.name)),
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
}
