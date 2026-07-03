import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../domain/delivery_challan.dart';
import '../providers/delivery_challan_provider.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../../units/domain/unit_definition.dart';
import '../../../units/presentation/providers/units_provider.dart';

class ChallanExcelView extends StatefulWidget {
  const ChallanExcelView({
    super.key,
    this.challans,
    this.filterItemId,
    this.filterVariationLeafNodeId,
    this.filterCustomVariationValues,
    required this.title,
    this.isEmbedded = false,
    this.onClose,
  });

  final List<DeliveryChallan>? challans;
  final int? filterItemId;
  final int? filterVariationLeafNodeId;
  final Map<String, String>? filterCustomVariationValues;
  final String title;
  final bool isEmbedded;
  final VoidCallback? onClose;

  static Future<DeliveryChallan?> show(
    BuildContext context, {
    List<DeliveryChallan>? challans,
    int? filterItemId,
    int? filterVariationLeafNodeId,
    Map<String, String>? filterCustomVariationValues,
    required String title,
  }) async {
    return await showDialog<DeliveryChallan>(
      context: context,
      barrierColor: const Color(0x66100D1F),
      builder: (context) => ChallanExcelView(
        challans: challans,
        filterItemId: filterItemId,
        filterVariationLeafNodeId: filterVariationLeafNodeId,
        filterCustomVariationValues: filterCustomVariationValues,
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
  DeliveryChallan? _selectedPreviewChallan;
  bool _isPreviewOpen = false;

  // Navigation State
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  List<_FlattenedRow> _currentRows = [];
  int _selectedIndex = -1;

  bool _customVariationMatches(DeliveryChallanItem item) {
    final filterValues = widget.filterCustomVariationValues;
    if (filterValues == null) {
      return true;
    }
    final itemValues = item.customVariationValues;
    if (itemValues.length != filterValues.length) {
      return false;
    }
    for (final entry in filterValues.entries) {
      final propertyId = int.tryParse(entry.key);
      if (propertyId == null || itemValues[propertyId] != entry.value) {
        return false;
      }
    }
    return true;
  }

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
        challansToLoad = await provider.repository.getChallans(
          itemId: widget.filterItemId,
          variationLeafNodeId: widget.filterVariationLeafNodeId,
        );
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
    // Real-time listeners: rebuild whenever the challans OR the underlying item /
    // unit definitions change, so edits to the item (units, symbols, naming,
    // variations) are reflected in this ledger live — without reopening it.
    final provider = context.watch<DeliveryChallanProvider>();
    context.watch<ItemsProvider>();
    context.watch<UnitsProvider>();
    for (int i = 0; i < _fullChallans.length; i++) {
      final updated = provider.challans
          .where((c) => c.id == _fullChallans[i].id)
          .firstOrNull;
      if (updated != null && updated.itemsCount == updated.items.length) {
        _fullChallans[i] = updated;
      }
    }
    if (widget.filterItemId != null ||
        widget.filterVariationLeafNodeId != null ||
        widget.filterCustomVariationValues != null) {
      for (final c in provider.challans) {
        if (c.items.any((item) {
              final itemMatch =
                  widget.filterItemId == null ||
                  item.itemId == widget.filterItemId;
              final varMatch =
                  widget.filterVariationLeafNodeId == null ||
                  item.variationLeafNodeId == widget.filterVariationLeafNodeId;

              final customMatch = _customVariationMatches(item);

              return itemMatch && varMatch && customMatch;
            }) &&
            c.itemsCount == c.items.length) {
          if (!_fullChallans.any((existing) => existing.id == c.id)) {
            _fullChallans.add(c);
          }
        }
      }
    }

    _buildRows(); // Rebuild rows dynamically on every build

    final content = Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            if (_currentRows.isNotEmpty) {
              setState(() {
                _selectedIndex = (_selectedIndex + 1).clamp(
                  0,
                  _currentRows.length - 1,
                );
                _selectedPreviewChallan = _currentRows[_selectedIndex].challan;
                _isPreviewOpen = true;
              });
              _scrollToSelectedIndex();
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            if (_currentRows.isNotEmpty) {
              setState(() {
                _selectedIndex = (_selectedIndex - 1).clamp(
                  0,
                  _currentRows.length - 1,
                );
                _selectedPreviewChallan = _currentRows[_selectedIndex].challan;
                _isPreviewOpen = true;
              });
              _scrollToSelectedIndex();
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.enter) {
            if (_selectedIndex >= 0 && _selectedIndex < _currentRows.length) {
              setState(() {
                _selectedPreviewChallan = _currentRows[_selectedIndex].challan;
                _isPreviewOpen = !_isPreviewOpen;
              });
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        width: widget.isEmbedded
            ? null
            : MediaQuery.of(context).size.width * 0.95,
        height: widget.isEmbedded
            ? null
            : MediaQuery.of(context).size.height * 0.95,
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
                  : GestureDetector(
                      onTap: () {
                        if (!_focusNode.hasFocus) _focusNode.requestFocus();
                      },
                      child: _buildTableWithPreview(),
                    ),
            ),
          ],
        ),
      ),
    );

    if (widget.isEmbedded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
      });
      return content;
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: content,
    );
  }

  void _scrollToSelectedIndex() {
    if (!_scrollController.hasClients || _selectedIndex < 0) return;
    // Estimate row height (approx 48-72px, header is 56px)
    final offset = _selectedIndex * 60.0;
    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  void _buildRows() {
    final rows = <_FlattenedRow>[];
    for (final challan in _fullChallans) {
      if (challan.items.isEmpty) {
        if (widget.filterItemId == null) {
          rows.add(_FlattenedRow(challan: challan));
        }
      } else {
        for (final item in challan.items) {
          final itemMatch =
              widget.filterItemId == null || item.itemId == widget.filterItemId;
          final varMatch =
              widget.filterVariationLeafNodeId == null ||
              item.variationLeafNodeId == widget.filterVariationLeafNodeId;
          final customMatch = _customVariationMatches(item);
          if (itemMatch && varMatch && customMatch) {
            rows.add(_FlattenedRow(challan: challan, item: item));
          }
        }
      }
    }

    rows.sort((a, b) => a.challan.date.compareTo(b.challan.date));

    final balanceQtyMap = <String, double>{};
    final balanceWtMap = <String, double>{};
    for (var row in rows) {
      final key = row.item?.particulars ?? '-';
      final qty = double.tryParse(row.item?.quantityPcs ?? '') ?? 0;
      final wt = double.tryParse(row.item?.weight ?? '') ?? 0;

      double bQty = balanceQtyMap[key] ?? 0.0;
      double bWt = balanceWtMap[key] ?? 0.0;

      if (row.challan.isReception) {
        bQty += qty;
        bWt += wt;
      } else if (row.challan.isDelivery) {
        bQty -= qty;
        bWt -= wt;
      }

      balanceQtyMap[key] = bQty;
      balanceWtMap[key] = bWt;

      row.balanceQty = bQty;
      row.balanceWt = bWt;
    }

    _currentRows = rows;
  }

  Widget _buildTableWithPreview() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final target = _isPreviewOpen && _selectedPreviewChallan != null
            ? 1.0
            : 0.0;
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: target),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          onEnd: () {
            if (!_isPreviewOpen && _selectedPreviewChallan != null && mounted) {
              setState(() => _selectedPreviewChallan = null);
            }
          },
          builder: (context, value, child) {
            final totalWidth = constraints.maxWidth;
            final maxPreviewWidth = (totalWidth - 520)
                .clamp(0.0, totalWidth)
                .toDouble();
            final expandedPreviewWidth = (totalWidth * 0.42)
                .clamp(0.0, maxPreviewWidth)
                .toDouble();
            final previewWidth = expandedPreviewWidth * value;
            final dividerWidth = previewWidth > 0.5 ? 1.0 : 0.0;
            final tableWidth = (totalWidth - previewWidth - dividerWidth)
                .clamp(0.0, totalWidth)
                .toDouble();
            final previewChallan = _selectedPreviewChallan;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: tableWidth, child: _buildTable()),
                if (previewWidth > 0.5) ...[
                  SizedBox(
                    width: dividerWidth,
                    child: const VerticalDivider(width: 1, thickness: 1),
                  ),
                  ClipRect(
                    child: SizedBox(
                      width: previewWidth,
                      child: Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset((1 - value) * 24, 0),
                          child: previewChallan == null
                              ? const SizedBox.shrink()
                              : _ChallanPrintPreviewPanel(
                                  challan: previewChallan,
                                  onCollapse: () {
                                    setState(() => _isPreviewOpen = false);
                                  },
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
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
            onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
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

    final ledgerUnits = _resolveLedgerUnits(_currentRows);
    final showSecondary = _currentRows.any(
      (row) => _hasLedgerValue(row.item?.quantityPcs),
    );

    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            headingRowColor: WidgetStateProperty.all(
              SoftErpTheme.cardSurfaceAlt,
            ),
            dataRowMinHeight: 48,
            dataRowMaxHeight: showSecondary ? 72 : 56,
            headingRowHeight: showSecondary ? 74 : 52,
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
              DataColumn(
                label: _LedgerMeasureHeader(
                  title: 'In',
                  primaryLabel: ledgerUnits.primaryLabel,
                  secondaryLabel: showSecondary
                      ? ledgerUnits.secondaryLabel
                      : null,
                ),
              ),
              DataColumn(
                label: _LedgerMeasureHeader(
                  title: 'Out',
                  primaryLabel: ledgerUnits.primaryLabel,
                  secondaryLabel: showSecondary
                      ? ledgerUnits.secondaryLabel
                      : null,
                ),
              ),
              DataColumn(
                label: _LedgerMeasureHeader(
                  title: 'Balance',
                  primaryLabel: ledgerUnits.primaryLabel,
                  secondaryLabel: showSecondary
                      ? ledgerUnits.secondaryLabel
                      : null,
                ),
              ),
            ],
            rows: _currentRows.asMap().entries.map((entry) {
              final index = entry.key;
              final row = entry.value;
              final date = row.challan.date;
              final dateStr =
                  '${date.day.toString().padLeft(2, '0')} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][date.month - 1]} ${date.year}';

              // Format balances nicely
              final bQtyStr =
                  row.balanceQty == row.balanceQty.truncateToDouble()
                  ? row.balanceQty.toInt().toString()
                  : row.balanceQty.toStringAsFixed(2);
              final bWtStr = row.balanceWt == row.balanceWt.truncateToDouble()
                  ? row.balanceWt.toInt().toString()
                  : row.balanceWt.toStringAsFixed(3);
              final secondaryValue = row.item?.quantityPcs ?? '';
              final primaryValue = row.item?.weight ?? '';

              return DataRow(
                selected:
                    index == _selectedIndex ||
                    (_isPreviewOpen &&
                        _selectedPreviewChallan?.id == row.challan.id),
                onSelectChanged: (_) {
                  if (!_focusNode.hasFocus) _focusNode.requestFocus();
                  setState(() {
                    _selectedIndex = index;
                    if (_isPreviewOpen &&
                        _selectedPreviewChallan?.id == row.challan.id) {
                      _isPreviewOpen = false;
                    } else {
                      _selectedPreviewChallan = row.challan;
                      _isPreviewOpen = true;
                    }
                  });
                },
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
                  DataCell(
                    _LedgerMeasureCell(
                      primary: row.challan.isReception
                          ? _formatLedgerAmount(
                              primaryValue,
                              ledgerUnits.primarySymbol,
                            )
                          : '',
                      secondary: showSecondary && row.challan.isReception
                          ? _formatLedgerAmount(
                              secondaryValue,
                              ledgerUnits.secondarySymbol,
                            )
                          : null,
                    ),
                  ),
                  DataCell(
                    _LedgerMeasureCell(
                      primary: row.challan.isDelivery
                          ? _formatLedgerAmount(
                              primaryValue,
                              ledgerUnits.primarySymbol,
                            )
                          : '',
                      secondary: showSecondary && row.challan.isDelivery
                          ? _formatLedgerAmount(
                              secondaryValue,
                              ledgerUnits.secondarySymbol,
                            )
                          : null,
                    ),
                  ),
                  DataCell(
                    _LedgerMeasureCell(
                      primary: _formatLedgerAmount(
                        bWtStr,
                        ledgerUnits.primarySymbol,
                      ),
                      secondary: showSecondary
                          ? _formatLedgerAmount(
                              bQtyStr,
                              ledgerUnits.secondarySymbol,
                            )
                          : null,
                      isBalance: true,
                      isNegative: row.balanceQty < 0 || row.balanceWt < 0,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  _LedgerUnitPresentation _resolveLedgerUnits(List<_FlattenedRow> rows) {
    final itemIds = <int>{};
    for (final row in rows) {
      final itemId = row.item?.itemId;
      if (itemId != null) {
        itemIds.add(itemId);
      }
    }
    final targetItemId =
        widget.filterItemId ?? (itemIds.length == 1 ? itemIds.first : null);
    if (targetItemId == null) {
      return const _LedgerUnitPresentation(
        primaryLabel: 'Primary unit',
        primarySymbol: '',
        secondaryLabel: 'Secondary unit',
        secondarySymbol: '',
      );
    }

    final itemsProv = context.watch<ItemsProvider>();
    final unitsProv = context.watch<UnitsProvider>();
    final item = itemsProv.items
        .where((entry) => entry.id == targetItemId)
        .firstOrNull;
    if (item == null) {
      return const _LedgerUnitPresentation(
        primaryLabel: 'Primary unit',
        primarySymbol: '',
        secondaryLabel: 'Secondary unit',
        secondarySymbol: '',
      );
    }

    final primary = unitsProv.findById(item.unitId);
    final conversions = item.unitConversions
        .map((conversion) => unitsProv.findById(conversion.unitId))
        .whereType<UnitDefinition>()
        .toList(growable: false);
    final secondary = conversions.firstOrNull;
    final secondaryInput = item.unitConversions.firstOrNull;
    final secondaryUnitName = secondaryInput?.unitName.trim() ?? '';
    final secondaryUnitSymbol = secondaryInput?.unitSymbol.trim() ?? '';
    return _LedgerUnitPresentation(
      primaryLabel: _unitFamilyLabel(primary, fallback: 'Primary unit'),
      primarySymbol: _cleanUnitSymbol(primary?.symbol, fallback: ''),
      secondaryLabel: _unitFamilyLabel(
        secondary,
        fallback: secondaryUnitName.isEmpty
            ? 'Secondary unit'
            : secondaryUnitName,
      ),
      secondarySymbol: _cleanUnitSymbol(
        secondary?.symbol,
        fallback: secondaryUnitSymbol,
      ),
    );
  }

  String _cleanUnitSymbol(String? value, {required String fallback}) {
    final cleaned = (value ?? '').trim();
    return cleaned.isEmpty ? fallback : cleaned;
  }

  String _unitFamilyLabel(UnitDefinition? unit, {required String fallback}) {
    if (unit == null) {
      return fallback;
    }
    final groupName = unit.unitGroupName?.trim() ?? '';
    if (groupName.isNotEmpty) {
      return groupName;
    }
    final name = unit.name.trim();
    if (name.isNotEmpty) {
      return name;
    }
    final symbol = unit.symbol.trim();
    return symbol.isEmpty ? fallback : symbol;
  }

  String _formatLedgerAmount(String value, String unitSymbol) {
    final cleaned = value.trim();
    if (cleaned.isEmpty || cleaned == '-') {
      return '';
    }
    if (RegExp(r'[A-Za-z]').hasMatch(cleaned) || unitSymbol.trim().isEmpty) {
      return cleaned;
    }
    return '$cleaned ${unitSymbol.trim()}';
  }

  bool _hasLedgerValue(String? value) {
    final cleaned = value?.trim() ?? '';
    return cleaned.isNotEmpty && cleaned != '-';
  }
}

class _LedgerUnitPresentation {
  const _LedgerUnitPresentation({
    required this.primaryLabel,
    required this.primarySymbol,
    required this.secondaryLabel,
    required this.secondarySymbol,
  });

  final String primaryLabel;
  final String primarySymbol;
  final String secondaryLabel;
  final String secondarySymbol;
}

// Unit colour coding: the primary unit (e.g. weight) and the secondary unit
// use distinct hues so a stacked "primary over secondary" cell reads clearly.
// Kept separate from the balance sign colours (green/red) to avoid clashing.
const Color _kLedgerPrimaryUnitColor = SoftErpTheme.infoText; // e.g. weight
const Color _kLedgerSecondaryUnitColor = SoftErpTheme.warningText; // e.g. pcs

class _LedgerMeasureHeader extends StatelessWidget {
  const _LedgerMeasureHeader({
    required this.title,
    required this.primaryLabel,
    required this.secondaryLabel,
  });

  final String title;
  final String primaryLabel;
  final String? secondaryLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Text(
              title,
              style: const TextStyle(
                color: SoftErpTheme.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _unitLegendLabel(primaryLabel, _kLedgerPrimaryUnitColor),
          if (secondaryLabel != null)
            _unitLegendLabel(secondaryLabel!, _kLedgerSecondaryUnitColor),
        ],
      ),
    );
  }

  Widget _unitLegendLabel(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerMeasureCell extends StatelessWidget {
  const _LedgerMeasureCell({
    required this.primary,
    required this.secondary,
    this.isBalance = false,
    this.isNegative = false,
  });

  final String primary;
  final String? secondary;
  final bool isBalance;
  final bool isNegative;

  @override
  Widget build(BuildContext context) {
    // Balance keeps its sign semantics (green up / red down). In/Out values are
    // tinted by unit so the primary (top) and secondary (bottom) lines are
    // instantly distinguishable and match the colour-coded column headers.
    final Color primaryColor = isBalance
        ? (isNegative ? Colors.red : Colors.green.shade700)
        : _kLedgerPrimaryUnitColor;
    final Color secondaryColor = isBalance
        ? (isNegative ? Colors.red : Colors.green.shade700)
        : _kLedgerSecondaryUnitColor;
    final weight = isBalance ? FontWeight.w900 : FontWeight.w600;
    return SizedBox(
      width: 132,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            primary.isEmpty ? '-' : primary,
            style: TextStyle(color: primaryColor, fontWeight: weight),
          ),
          // Only render the secondary line when it actually carries a value —
          // no empty "-" placeholder when there's no secondary-unit amount.
          if (secondary != null && secondary!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              secondary!,
              style: TextStyle(color: secondaryColor, fontWeight: weight),
            ),
          ],
        ],
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

class _ChallanPrintPreviewPanel extends StatelessWidget {
  const _ChallanPrintPreviewPanel({
    required this.challan,
    required this.onCollapse,
  });

  final DeliveryChallan challan;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF3F4F8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                const Icon(
                  Icons.print_outlined,
                  size: 18,
                  color: SoftErpTheme.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Challan Print Preview',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: SoftErpTheme.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Collapse preview',
                  onPressed: onCollapse,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Align(
                alignment: Alignment.topCenter,
                child: FittedBox(
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.topCenter,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: _ChallanPrintableDocument(challan: challan),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChallanPrintableDocument extends StatelessWidget {
  const _ChallanPrintableDocument({required this.challan});

  final DeliveryChallan challan;

  @override
  Widget build(BuildContext context) {
    final profile =
        challan.companyProfileSnapshot ??
        context.watch<DeliveryChallanProvider>().companyProfile ??
        CompanyProfile.empty();
    final isReception = challan.isReception;
    final docTitle = _challanTypeTitle(challan);
    final partyLabel = isReception ? 'Vendor' : 'M/s';
    final partyName = isReception ? challan.vendorName : challan.customerName;
    final partyGstin = isReception
        ? challan.vendorGstin
        : challan.customerGstin;
    final referenceLabel = isReception ? 'Source Ref.' : 'Challan No.';
    final referenceValue = isReception
        ? (challan.sourceReference.trim().isEmpty
              ? challan.challanNo
              : challan.sourceReference)
        : challan.challanNo;

    return Container(
      width: 760,
      color: Colors.white,
      padding: const EdgeInsets.all(18),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black, width: 1.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(child: SizedBox()),
                      Expanded(
                        flex: 2,
                        child: Text(
                          docTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          profile.mobile.isEmpty
                              ? ''
                              : 'Mobile: ${profile.mobile}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    profile.companyName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (profile.businessDescription.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      profile.businessDescription,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (profile.address.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(profile.address, textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
            const Divider(color: Colors.black, height: 1),
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _docCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$partyLabel: $partyName'),
                          const SizedBox(height: 8),
                          Text('GSTIN: $partyGstin'),
                        ],
                      ),
                    ),
                  ),
                  Container(width: 1, color: Colors.black),
                  SizedBox(
                    width: 230,
                    child: _docCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$referenceLabel: $referenceValue'),
                          const SizedBox(height: 8),
                          Text('Challan No.: ${challan.challanNo}'),
                          const SizedBox(height: 8),
                          Text('Date: ${_formatDate(challan.date)}'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.black, height: 1),
            Table(
              border: TableBorder.all(color: Colors.black),
              columnWidths: const {
                0: FlexColumnWidth(4),
                1: FlexColumnWidth(1.4),
                2: FlexColumnWidth(1.4),
                3: FlexColumnWidth(1.3),
              },
              children: [
                _tableRow([
                  'Particulars',
                  'HSN Code',
                  'QTY. Pcs.',
                  'Weight',
                ], header: true),
                ...challan.items.map(
                  (item) => _tableRow([
                    _itemParticulars(item),
                    item.hsnCode,
                    item.quantityPcs,
                    item.weight,
                  ]),
                ),
                for (var i = challan.items.length; i < 9; i++)
                  _tableRow(['', '', '', '']),
              ],
            ),
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _docCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('State Code: ${profile.stateCode}'),
                          const SizedBox(height: 8),
                          Text('GSTIN: ${profile.gstin}'),
                          const SizedBox(height: 52),
                          const Text('Receiver\'s Signature'),
                        ],
                      ),
                    ),
                  ),
                  Container(width: 1, color: Colors.black),
                  SizedBox(
                    width: 270,
                    child: _docCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'For ${profile.companyName}',
                            textAlign: TextAlign.right,
                          ),
                          const SizedBox(height: 64),
                          Text(
                            profile.signatureLabel.isEmpty
                                ? 'Checked by / Authorized Signatory'
                                : profile.signatureLabel,
                            textAlign: TextAlign.right,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _docCell(Widget child) {
    return Padding(padding: const EdgeInsets.all(10), child: child);
  }

  TableRow _tableRow(List<String> values, {bool header = false}) {
    return TableRow(
      children: values
          .map(
            (value) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              child: Text(
                value,
                style: TextStyle(
                  fontWeight: header ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  String _itemParticulars(DeliveryChallanItem item) {
    final custom = item.customVariationValues.values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' / ');
    return [
      item.particulars.trim().isEmpty ? 'Item' : item.particulars.trim(),
      if (item.variationPathLabel.trim().isNotEmpty)
        item.variationPathLabel.trim(),
      if (custom.isNotEmpty) custom,
      if (item.note.trim().isNotEmpty) item.note.trim(),
    ].join('\n');
  }
}

String _challanTypeTitle(DeliveryChallan challan) {
  if (challan.isReception) return 'RECEPTION CHALLAN';
  if (challan.isInternal) return 'INTERNAL CHALLAN';
  return 'DELIVERY CHALLAN';
}

String _formatDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day-$month-${value.year}';
}
