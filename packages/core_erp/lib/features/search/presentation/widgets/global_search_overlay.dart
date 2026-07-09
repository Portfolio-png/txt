import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../inventory/data/repositories/inventory_repository.dart';
import '../../../inventory/domain/variation_stock_record.dart';
import '../../../groups/presentation/providers/groups_provider.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../../items/domain/item_definition.dart';
import '../../../delivery_challans/presentation/widgets/challan_excel_view.dart';
import '../providers/search_provider.dart';
import '../../../../widgets/variation_path_selector_dialog.dart';

class GlobalSearchOverlay extends StatefulWidget {
  const GlobalSearchOverlay({super.key});

  @override
  State<GlobalSearchOverlay> createState() => _GlobalSearchOverlayState();
}

class _GlobalSearchOverlayState extends State<GlobalSearchOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  int? _selectedItemId;
  List<int> _selectedVariationValueNodeIds = [];
  Map<int, String> _customVariationValues = {};
  ItemVariationNodeDefinition? _leaf;
  int? _selectedRootPropertyId;

  List<VariationStockRecord> _allStock = [];
  bool _isLoadingStock = false;
  VariationStockRecord? _selectedStock;
  bool _isLeftPaneMinimized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed) {
          setState(() {
            _selectedItemId = null;
            _selectedVariationValueNodeIds = [];
            _customVariationValues = {};
            _selectedRootPropertyId = null;
            _leaf = null;
            _selectedStock = null;
          });
        }
      });
    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _fetchStock();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _fetchStock() async {
    setState(() {
      _isLoadingStock = true;
    });
    try {
      final records =
          await context.read<InventoryRepository>().getVariationStock();
      if (mounted) {
        setState(() {
          _allStock = records;
          _isLoadingStock = false;
          _updateSelectedStock();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingStock = false;
        });
      }
    }
  }

  ItemDefinition? _getSelectedItem(List<ItemDefinition> items) {
    if (_selectedItemId == null) return null;
    return items.where((i) => i.id == _selectedItemId).firstOrNull;
  }

  void _updateSelectedStock() {
    if (_selectedItemId == null) {
      _selectedStock = null;
      return;
    }
    _selectedStock = _allStock.where((record) {
      if (record.itemId != _selectedItemId) return false;
      if (_leaf != null) {
        return record.variationLeafNodeId == _leaf!.id;
      }
      return true;
    }).firstOrNull;
  }

  String _variationSelectionLabel(ItemDefinition item) {
    if (_leaf != null) {
      return _leaf!.displayName.isNotEmpty ? _leaf!.displayName : _leaf!.name;
    }
    if (_selectedVariationValueNodeIds.isEmpty &&
        _customVariationValues.isEmpty) {
      return '';
    }
    return 'Properties selected';
  }



  @override
  Widget build(BuildContext context) {
    return Consumer<SearchProvider>(
      builder: (context, provider, child) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (provider.isOverlayVisible &&
              !_controller.isAnimating &&
              _controller.status != AnimationStatus.completed) {
            _controller.forward();
          } else if (!provider.isOverlayVisible &&
              !_controller.isAnimating &&
              _controller.status != AnimationStatus.dismissed) {
            _controller.reverse();
          }
        });

        if (!provider.isOverlayVisible &&
            _controller.status == AnimationStatus.dismissed) {
          return const SizedBox.shrink();
        }

        final items = context.watch<ItemsProvider>().items;
        final groupsProvider = context.watch<GroupsProvider>();
        final selectedItem = _getSelectedItem(items);
        final hasVariations = selectedItem != null &&
            selectedItem.topLevelProperties.isNotEmpty;

        final bool isFullySelected = _selectedItemId != null && (!hasVariations || _leaf != null);
        
        final screenWidth = MediaQuery.of(context).size.width;
        final isTablet = screenWidth >= 600;
        final expandedWidth = screenWidth * 0.9;
        final narrowWidth = isTablet ? 450.0 : screenWidth * 0.9;
        final targetWidth = isFullySelected ? expandedWidth : narrowWidth;

        return Stack(
          children: [
            GestureDetector(
              onTap: () {
                provider.hideOverlay();
              },
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
                  child: Container(
                    color: SoftErpTheme.cardSurfaceAlt.withOpacity(0.4),
                  ),
                ),
              ),
            ),
            Center(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Material(
                    color: Colors.transparent,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      width: targetWidth,
                      height: MediaQuery.of(context).size.height * 0.9,
                      decoration: SoftErpTheme.surfaceDecoration(
                        radius: SoftErpTheme.radiusLg,
                        elevated: true,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20.0, vertical: 16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    if (_selectedItemId != null)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 12.0),
                                        child: IconButton(
                                          icon: Icon(
                                            _isLeftPaneMinimized
                                                ? Icons.keyboard_double_arrow_right_rounded
                                                : Icons.keyboard_double_arrow_left_rounded,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _isLeftPaneMinimized = !_isLeftPaneMinimized;
                                            });
                                          },
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          color: SoftErpTheme.textSecondary,
                                        ),
                                      ),
                                    Text(
                                      'Product & Stock Lookup',
                                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        color: SoftErpTheme.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () => provider.hideOverlay(),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Left Pane: Item Selection
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOutCubic,
                                  width: _isLeftPaneMinimized ? 0.0 : (narrowWidth - 2.0),
                                  clipBehavior: Clip.hardEdge,
                                  decoration: const BoxDecoration(
                                    color: SoftErpTheme.sectionSurface,
                                  ),
                                  child: OverflowBox(
                                    alignment: Alignment.topLeft,
                                    minWidth: narrowWidth - 2.0,
                                    maxWidth: narrowWidth - 2.0,
                                    child: Container(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Select Item',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: SoftErpTheme.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        SearchableSelectField<int>(
                                          value: _selectedItemId,
                                          decoration: InputDecoration(
                                            hintText: 'Search item...',
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 12),
                                          ),
                                          dialogTitle: 'Select Item',
                                          searchHintText: 'Search by name',
                                          options: items
                                              .map((item) {
                                                final primaryGroup = groupsProvider
                                                        .findById(item.groupId)
                                                        ?.name ??
                                                    'No primary group';
                                                final fullVariationName = item
                                                        .displayName.isNotEmpty
                                                    ? item.displayName
                                                    : item.name;
                                                return SearchableSelectOption<
                                                    int>(
                                                  value: item.id,
                                                  label: fullVariationName,
                                                  searchText:
                                                      '$fullVariationName $primaryGroup',
                                                );
                                              })
                                              .toList(growable: false),
                                          onChanged: (value) {
                                            setState(() {
                                              _selectedItemId = value;
                                              _selectedVariationValueNodeIds =
                                                  [];
                                              _customVariationValues = {};
                                              _selectedRootPropertyId = null;
                                              _leaf = null;
                                              _updateSelectedStock();
                                            });
                                            if (value != null) {
                                              final item = _getSelectedItem(items);
                                              if (item != null &&
                                                  item.topLevelProperties
                                                      .isNotEmpty) {
                                                if (item.topLevelProperties.length == 1) {
                                                  _selectedRootPropertyId = item.topLevelProperties.first.id;
                                                }
                                              }
                                            }
                                          },
                                        ),
                                        if (hasVariations) ...[
                                          const SizedBox(height: 16),
                                          const Text(
                                            'Variation Path',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: SoftErpTheme.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Expanded(
                                            child: VariationPathSelectorWidget(
                                              key: ValueKey(selectedItem.id),
                                              item: selectedItem,
                                              initialRootPropertyId: _selectedRootPropertyId,
                                              initialValueNodeIds: _selectedVariationValueNodeIds,
                                              initialCustomVariationValues: _customVariationValues,
                                              readOnly: false,
                                              showHeaderAndFooter: false,
                                              onChanged: (result) {
                                                setState(() {
                                                  _selectedVariationValueNodeIds = result.valueNodeIds;
                                                  _customVariationValues = result.customVariationValues;
                                                  _leaf = result.leaf;
                                                  if (selectedItem.topLevelProperties.length == 1) {
                                                      _selectedRootPropertyId = selectedItem.topLevelProperties.first.id;
                                                  }
                                                  _updateSelectedStock();
                                                });
                                              },
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                ),
                                if (isFullySelected) const VerticalDivider(width: 1),
                                // Right Pane: Stock & Ledger
                                Expanded(
                                  child: ClipRect(
                                    child: AnimatedOpacity(
                                      duration: const Duration(milliseconds: 300),
                                      opacity: isFullySelected ? 1.0 : 0.0,
                                      child: isFullySelected ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            // Stock Info Top
                                            Container(
                                              padding:
                                                  const EdgeInsets.all(24),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Container(
                                                    width: 60,
                                                    height: 60,
                                                    decoration: BoxDecoration(
                                                      color: SoftErpTheme.accent
                                                          .withOpacity(0.1),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(
                                                      Icons.inventory_2,
                                                      size: 30,
                                                      color:
                                                          SoftErpTheme.accent,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 20),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          selectedItem?.name ?? '',
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 20,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                        if (_leaf != null)
                                                          Text(
                                                            _leaf!.displayName.isNotEmpty ? _leaf!.displayName : _leaf!.name,
                                                            style:
                                                                const TextStyle(
                                                              fontSize: 14,
                                                              color: SoftErpTheme
                                                                  .textSecondary,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.end,
                                                    children: [
                                                      const Text(
                                                        'Stock Available',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: SoftErpTheme
                                                              .textSecondary,
                                                        ),
                                                      ),
                                                      if (_isLoadingStock)
                                                        const SizedBox(
                                                          width: 20,
                                                          height: 20,
                                                          child:
                                                              CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                        )
                                                      else
                                                        Text(
                                                          _selectedStock != null
                                                              ? '${_selectedStock!.quantity}'
                                                              : '0',
                                                          style: TextStyle(
                                                            fontSize: 24,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: _selectedStock !=
                                                                        null &&
                                                                    _selectedStock!
                                                                            .quantity >
                                                                        0
                                                                ? SoftErpTheme.successText
                                                                : SoftErpTheme.dangerText,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Divider(height: 1),
                                            // Ledger Below
                                            Expanded(
                                              child: ChallanExcelView(
                                                isEmbedded: true,
                                                filterItemId: _selectedItemId,
                                                filterVariationLeafNodeId:
                                                    _leaf?.id,
                                                title: 'In/Out Ledger',
                                                onClose: () {},
                                              ),
                                            ),
                                          ],
                                        ) : const SizedBox.shrink(),
                                      ),
                                    ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
