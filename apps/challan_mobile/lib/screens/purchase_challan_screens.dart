import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/features/delivery_challans/domain/delivery_challan.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/items/presentation/providers/favorites_provider.dart';
import 'package:core_erp/features/vendors/domain/vendor_definition.dart';
import 'package:core_erp/features/vendors/presentation/providers/vendors_provider.dart';
import 'package:core_erp/features/vendors/presentation/providers/vendor_history_provider.dart';
import 'package:core_erp/widgets/variation_path_selector_dialog.dart';

import 'challan_mobile_editor_screen.dart';
import 'use_item_screens.dart';

final List<DeliveryChallanItem> activePurchaseLines = [];

/// Challan tab entry point: choose Purchase (reception) or Sale (delivery).
/// Only Purchase is enabled for now; Sale is shown as "coming soon".
class ChallanTabScreen extends StatelessWidget {
  const ChallanTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vendors = context.watch<VendorsProvider>().vendors.where((v) => !v.isArchived).toList(growable: false);

    return Scaffold(
      backgroundColor: SoftErpTheme.shellSurface,
      appBar: AppBar(
        title: const Text('New Challan', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              // Keep the tiles a sensible size on wide tablets instead of
              // stretching each square to half the screen.
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  // Purchase and Sale share the first row (two square tiles);
                  // Vendor takes the left tile of the second row when present.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: _ChoiceCard(
                            title: 'Purchase',
                            subtitle: 'Receive goods from a vendor',
                            icon: Icons.call_received_rounded,
                            color: SoftErpTheme.accent,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const PurchaseGroupBrowseScreen()),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: _ChoiceCard(
                            title: 'Use',
                            subtitle: 'Consume raw materials',
                            icon: Icons.precision_manufacturing_rounded,
                            color: Colors.orange,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const UseInventoryBrowseScreen()),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (vendors.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: _ChoiceCard(
                              title: 'Vendor',
                              subtitle: 'Re-order past purchases',
                              icon: Icons.storefront_rounded,
                              color: const Color(0xFFE57373),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => VendorBrowseScreen(lines: activePurchaseLines),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.disabled = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: disabled ? null : onTap,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE8ECF5), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
                      child: Icon(icon, color: color, size: 28),
                    ),
                    if (disabled) ...[
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(999)),
                        child: Text('SOON', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey.shade600)),
                      ),
                    ],
                  ],
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: SoftErpTheme.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Confirms discarding the whole in-progress purchase challan, clears the
/// collected [lines], and exits the flow back to the Purchase/Sale start.
Future<void> confirmDiscardChallan(BuildContext context, List<DeliveryChallanItem> lines) async {
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
  if (ok == true && context.mounted) {
    lines.clear();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

/// Step 1 of Purchase: pick an item group. Only groups that contain at least one
/// purchase-available item are shown. Collected lines accumulate across groups.
class PurchaseGroupBrowseScreen extends StatefulWidget {
  const PurchaseGroupBrowseScreen({super.key});

  @override
  State<PurchaseGroupBrowseScreen> createState() => _PurchaseGroupBrowseScreenState();
}

class _PurchaseGroupBrowseScreenState extends State<PurchaseGroupBrowseScreen> {
  bool _reviewing = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _expandAll = false;

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
          initialItems: List<DeliveryChallanItem>.of(activePurchaseLines),
          lockedType: ChallanType.reception,
        ),
      ),
    );
    _reviewing = false;
    if (!mounted) return;
    if (done == true) {
      setState(() => activePurchaseLines.clear());
    } else if (done is List<DeliveryChallanItem>) {
      setState(() {
        activePurchaseLines.clear();
        activePurchaseLines.addAll(done);
      });
    }
  }

  Future<void> _pickItem(ItemDefinition item) async {
    final favProvider = context.read<FavoritesProvider>();
    VariationPathSelectionResult? variation;
    if (item.topLevelProperties.isNotEmpty) {
      variation = await showDialog<VariationPathSelectionResult>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.all(24),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: VariationPathSelectorDialog(
                item: item,
                initialRootPropertyId: null,
                initialValueNodeIds: const [],
                useTilesForValues: true,
                onCreateValue: ({required item, required propertyNodeId, required propertyLabel, required valueName}) {
                  return context.read<ItemsProvider>().appendVariationValue(
                    itemId: item.id,
                    propertyNodeId: propertyNodeId,
                    valueName: valueName,
                  );
                },
                isFavorite: (result) => favProvider.isFavorite(item.id, result.valueNodeIds),
                onFavoriteToggled: (result, isFav) {
                  final dummyItem = DeliveryChallanItem(
                    id: 0,
                    orderItemId: null,
                    productionRunId: null,
                    itemId: item.id,
                    variationLeafNodeId: result.leaf?.id ?? 0,
                    variationPathLabel: result.summaryLabel,
                    variationPathNodeIds: result.valueNodeIds,
                    particulars: item.displayName,
                    quantityPcs: '1',
                    weight: '0.0',
                    lineNo: 0,
                    hsnCode: '',
                    note: '',
                  );
                  favProvider.toggleFavorite(dummyItem, isFav);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isFav ? 'Variation saved to favorites' : 'Variation removed from favorites'),
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.only(top: 10, left: 10, right: 10),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      if (variation == null || !mounted) return;
    }

    final leafNodeId = variation?.leaf?.id ?? 0;

    showPurchaseQuantitySheet(
      context,
      onConfirm: (qty, weight) {
        final newItem = DeliveryChallanItem(
          id: 0,
          orderItemId: null,
          productionRunId: null,
          itemId: item.id,
          variationLeafNodeId: leafNodeId,
          variationPathLabel: variation?.summaryLabel ?? '',
          variationPathNodeIds: variation?.valueNodeIds ?? const <int>[],
          customVariationValues: variation?.customVariationValues ?? const <int, String>{},
          particulars: item.displayName,
          quantityPcs: qty,
          weight: weight,
          lineNo: activePurchaseLines.length + 1,
          hsnCode: '',
          note: '',
        );

        activePurchaseLines.add(newItem);
        setState(() {});
        _goToChallan();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final itemsProvider = context.watch<ItemsProvider>();
    final groupsProvider = context.watch<GroupsProvider>();
    final favPurchases = context.watch<FavoritesProvider>().favorites;

    final purchaseItems = itemsProvider.items
        .where((i) => i.availableForPurchase && !i.isArchived)
        .toList(growable: false);
        
    final filteredItems = _searchQuery.isEmpty 
        ? purchaseItems 
        : purchaseItems.where((i) => i.displayName.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    final groupIdsWithPurchase = filteredItems.map((i) => i.groupId).toSet();
    final groups = groupsProvider.itemGroups
        .where((g) => !g.isArchived && groupIdsWithPurchase.contains(g.id))
        .toList(growable: false);

    final bool isSingleGroup = groups.length == 1;

    return Scaffold(
      backgroundColor: SoftErpTheme.shellSurface,
      appBar: AppBar(
        title: Text(isSingleGroup ? groups.first.name : 'Purchase — Groups', style: const TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: !isSingleGroup 
            ? IconButton(
                icon: Icon(_expandAll ? Icons.unfold_less_rounded : Icons.unfold_more_rounded, color: SoftErpTheme.accent),
                onPressed: () => setState(() => _expandAll = !_expandAll),
                tooltip: 'Toggle Groups',
              )
            : const BackButton(),
        actions: [
          if (activePurchaseLines.isNotEmpty)
            IconButton(
              tooltip: 'Discard challan',
              icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFD64545)),
              onPressed: () => confirmDiscardChallan(context, activePurchaseLines),
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
                hintText: 'Search items...',
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
            child: groups.isEmpty && favPurchases.isEmpty
                ? const _EmptyHint(
                    icon: Icons.category_outlined,
                    title: 'No purchase items',
                    message: 'No items found matching your criteria.',
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (favPurchases.isNotEmpty && _searchQuery.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _BrowseTile(
                            icon: Icons.favorite_rounded,
                            title: 'Favorites',
                            subtitle: '${favPurchases.length} item${favPurchases.length == 1 ? '' : 's'}',
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => FavoriteItemBrowseScreen(lines: activePurchaseLines),
                                ),
                              );
                              if (mounted) setState(() {});
                            },
                          ),
                        ),

                        ...groups.map((group) {
                          final groupItems = filteredItems.where((i) => i.groupId == group.id).toList();
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                            color: Colors.white,
                            child: ExpansionTile(
                              initiallyExpanded: _expandAll || isSingleGroup,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: SoftErpTheme.accent.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                                child: const Icon(Icons.folder_open_rounded, color: SoftErpTheme.accent),
                              ),
                              title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text('${groupItems.length} items', style: const TextStyle(fontSize: 12, color: SoftErpTheme.textSecondary)),
                              children: groupItems.map((item) => ListTile(
                                leading: const Icon(Icons.inventory_2_rounded, color: Colors.grey),
                                title: Text(item.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('ID: ${item.id}'),
                                trailing: const Icon(Icons.add_circle_outline_rounded, color: SoftErpTheme.accent),
                                onTap: () => _pickItem(item),
                              )).toList(),
                            ),
                          );
                        }),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: activePurchaseLines.isEmpty
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
                label: Text('Review Challan (${activePurchaseLines.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                onPressed: _goToChallan,
              ),
            ),
    );
  }
}

class FavoriteItemBrowseScreen extends StatefulWidget {
  const FavoriteItemBrowseScreen({super.key, required this.lines, this.group});

  final List<DeliveryChallanItem> lines;
  final GroupDefinition? group;

  @override
  State<FavoriteItemBrowseScreen> createState() => _FavoriteItemBrowseScreenState();
}

class _FavoriteItemBrowseScreenState extends State<FavoriteItemBrowseScreen> {
  bool _reviewing = false;

  Future<void> _goToChallan() async {
    if (_reviewing) return;
    _reviewing = true;
    final done = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => ChallanMobileEditorScreen(
          initialItems: List<DeliveryChallanItem>.of(widget.lines),
          lockedType: ChallanType.reception,
        ),
      ),
    );
    _reviewing = false;
    if (!mounted) return;
    if (done == true) {
      widget.lines.clear();
      Navigator.of(context).pop();
    } else if (done is List<DeliveryChallanItem>) {
      setState(() {
        widget.lines.clear();
        widget.lines.addAll(done);
      });
    }
  }

  void _pickFav(DeliveryChallanItem favItem) {
    showPurchaseQuantitySheet(
      context,
      onConfirm: (qty, weight) {
        final newItem = DeliveryChallanItem(
          id: 0,
          orderItemId: null,
          productionRunId: null,
          itemId: favItem.itemId,
          variationLeafNodeId: favItem.variationLeafNodeId,
          variationPathLabel: favItem.variationPathLabel,
          variationPathNodeIds: favItem.variationPathNodeIds,
          customVariationValues: favItem.customVariationValues,
          particulars: favItem.particulars,
          quantityPcs: qty,
          weight: weight,
          lineNo: widget.lines.length + 1,
          hsnCode: '',
          note: '',
        );
        
        widget.lines.add(newItem);
        setState(() {});
        _goToChallan();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final itemsProvider = context.watch<ItemsProvider>();
    final favProvider = context.watch<FavoritesProvider>();
    final favPurchases = favProvider.favorites;
    final addedInGroup = widget.lines.length;

    final displayFavs = widget.group == null
        ? favPurchases
        : favPurchases.where((f) {
            return itemsProvider.items.any((item) => item.id == f.itemId && item.groupId == widget.group!.id);
          }).toList(growable: false);

    return Scaffold(
      backgroundColor: SoftErpTheme.shellSurface,
      appBar: AppBar(
        title: Text(widget.group == null ? 'Favorites' : 'Fav ${widget.group!.name}', style: const TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        actions: [
          if (addedInGroup > 0)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: SoftErpTheme.accent.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
                child: Text('$addedInGroup in challan', style: const TextStyle(color: SoftErpTheme.accent, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ),
          if (widget.lines.isNotEmpty)
            IconButton(
              tooltip: 'Discard challan',
              icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFD64545)),
              onPressed: () => confirmDiscardChallan(context, widget.lines),
            ),
        ],
      ),
      bottomNavigationBar: widget.lines.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(16),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: SoftErpTheme.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text('Next  ·  Review Challan (${widget.lines.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                onPressed: _goToChallan,
              ),
            ),
      body: displayFavs.isEmpty
          ? const _EmptyHint(
              icon: Icons.favorite_border_rounded,
              title: 'No favorite items',
              message: 'Favorite items when entering quantity to see them here.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: displayFavs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = displayFavs[index];
                return _BrowseTile(
                  icon: Icons.favorite_rounded,
                  title: item.particulars,
                  subtitle: item.variationPathLabel.isNotEmpty ? item.variationPathLabel : 'Standard',
                  trailing: const Icon(Icons.add_circle_outline_rounded, color: SoftErpTheme.accent),
                  onTap: () => _pickFav(item),
                );
              },
            ),
    );
  }
}

/// Step 2 of Purchase: pick items from a group. Tapping an item runs the shared
/// variation picker, then a quantity sheet, then adds the line to [lines].
class PurchaseItemBrowseScreen extends StatefulWidget {
  const PurchaseItemBrowseScreen({super.key, required this.group, required this.lines});

  final GroupDefinition group;
  final List<DeliveryChallanItem> lines;

  @override
  State<PurchaseItemBrowseScreen> createState() => _PurchaseItemBrowseScreenState();
}

class _PurchaseItemBrowseScreenState extends State<PurchaseItemBrowseScreen> {
  bool _reviewing = false;

  // "Next": leave item selection and go to the reception challan editor with
  // everything collected so far. On a successful submit the cart is cleared and
  // we pop back to the group screen (which refreshes to an empty cart).
  Future<void> _goToChallan() async {
    if (_reviewing) return;
    _reviewing = true;
    final done = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => ChallanMobileEditorScreen(
          initialItems: List<DeliveryChallanItem>.of(widget.lines),
          lockedType: ChallanType.reception,
        ),
      ),
    );
    _reviewing = false;
    if (!mounted) return;
    if (done == true) {
      widget.lines.clear();
      Navigator.of(context).pop();
    } else if (done is List<DeliveryChallanItem>) {
      setState(() {
        widget.lines.clear();
        widget.lines.addAll(done);
      });
    }
  }

  Future<void> _pickItem(ItemDefinition item) async {
    final favProvider = context.read<FavoritesProvider>();
    VariationPathSelectionResult? variation;
    // Items with no variation properties skip the picker entirely — the dialog
    // can never resolve a leaf for them, so its Confirm button would stay
    // disabled and the item could never be added.
    if (item.topLevelProperties.isNotEmpty) {
      variation = await showDialog<VariationPathSelectionResult>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.all(24),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: VariationPathSelectorDialog(
                item: item,
                initialRootPropertyId: null,
                initialValueNodeIds: const [],
                useTilesForValues: true,
                onCreateValue: ({required item, required propertyNodeId, required propertyLabel, required valueName}) {
                  return context.read<ItemsProvider>().appendVariationValue(
                    itemId: item.id,
                    propertyNodeId: propertyNodeId,
                    valueName: valueName,
                  );
                },
                isFavorite: (result) => favProvider.isFavorite(item.id, result.valueNodeIds),
                onFavoriteToggled: (result, isFav) {
                  // Create dummy item just for favorite toggling
                  final dummyItem = DeliveryChallanItem(
                    id: 0,
                    orderItemId: null,
                    productionRunId: null,
                    itemId: item.id,
                    variationLeafNodeId: result.leaf?.id ?? 0,
                    variationPathLabel: result.summaryLabel,
                    variationPathNodeIds: result.valueNodeIds,
                    particulars: item.displayName,
                    quantityPcs: '1',
                    weight: '0.0',
                    lineNo: 0,
                    hsnCode: '',
                    note: '',
                  );
                  favProvider.toggleFavorite(dummyItem, isFav);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isFav ? 'Variation saved to favorites' : 'Variation removed from favorites'),
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.only(top: 10, left: 10, right: 10),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      if (variation == null || !mounted) return;
    }

    final leafNodeId = variation?.leaf?.id ?? 0;

    showPurchaseQuantitySheet(
      context,
      onConfirm: (qty, weight) {
        final newItem = DeliveryChallanItem(
          id: 0,
          orderItemId: null,
          productionRunId: null,
          itemId: item.id,
          variationLeafNodeId: leafNodeId,
          variationPathLabel: variation?.summaryLabel ?? '',
          variationPathNodeIds: variation?.valueNodeIds ?? const <int>[],
          customVariationValues: variation?.customVariationValues ?? const <int, String>{},
          particulars: item.displayName,
          quantityPcs: qty,
          weight: weight,
          lineNo: widget.lines.length + 1,
          hsnCode: '',
          note: '',
        );

        widget.lines.add(newItem);
        setState(() {});
        _goToChallan();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final itemsProvider = context.watch<ItemsProvider>();
    final favProvider = context.watch<FavoritesProvider>();
    final favPurchases = favProvider.favorites;
    final items = itemsProvider.items
        .where((i) => i.availableForPurchase && !i.isArchived && i.groupId == widget.group.id)
        .toList(growable: false);
    final addedInGroup = widget.lines.length;

    final groupFavs = favPurchases.where((f) {
      return itemsProvider.items.any((item) => item.id == f.itemId && item.groupId == widget.group.id);
    }).toList(growable: false);

    return Scaffold(
      backgroundColor: SoftErpTheme.shellSurface,
      appBar: AppBar(
        title: Text(widget.group.name, style: const TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        actions: [
          if (addedInGroup > 0)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: SoftErpTheme.accent.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
                child: Text('$addedInGroup in challan', style: const TextStyle(color: SoftErpTheme.accent, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ),
          if (widget.lines.isNotEmpty)
            IconButton(
              tooltip: 'Discard challan',
              icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFD64545)),
              onPressed: () => confirmDiscardChallan(context, widget.lines),
            ),
        ],
      ),
      bottomNavigationBar: widget.lines.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(16),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: SoftErpTheme.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text('Next  ·  Review Challan (${widget.lines.length})',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                onPressed: _goToChallan,
              ),
            ),
      body: items.isEmpty && groupFavs.isEmpty
          ? const _EmptyHint(
              icon: Icons.inventory_2_outlined,
              title: 'No purchase items in this group',
              message: 'Mark items as "Available for purchase" in the desktop app.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length + (groupFavs.isNotEmpty ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (groupFavs.isNotEmpty && index == 0) {
                  return _BrowseTile(
                    icon: Icons.favorite_rounded,
                    title: 'Favorites in ${widget.group.name}',
                    subtitle: '${groupFavs.length} item${groupFavs.length == 1 ? '' : 's'}',
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FavoriteItemBrowseScreen(
                            lines: widget.lines,
                            group: widget.group,
                          ),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                  );
                }

                final itemIndex = groupFavs.isNotEmpty ? index - 1 : index;
                final item = items[itemIndex];
                return _BrowseTile(
                  icon: Icons.inventory_2_rounded,
                  title: item.displayName,
                  subtitle: 'ID: ${item.id}',
                  trailing: const Icon(Icons.add_circle_outline_rounded, color: SoftErpTheme.accent),
                  onTap: () => _pickItem(item),
                );
              },
            ),
    );
  }
}

/// Lean quantity + weight sheet. Calls [onConfirm] with the entered values as
/// strings (matching DeliveryChallanItem's quantityPcs/weight).
void showPurchaseQuantitySheet(
  BuildContext context, {
  required void Function(String qty, String weight) onConfirm,
}) {
  int qty = 1;
  final weightController = TextEditingController();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 50,
                    height: 6,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Set Quantity', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: SoftErpTheme.textPrimary)),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Pieces', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    Row(
                      children: [
                        _StepButton(icon: Icons.remove, color: Colors.red, onTap: () => setModalState(() { if (qty > 1) qty--; })),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text('$qty', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                        ),
                        _StepButton(icon: Icons.add, color: Colors.green, onTap: () => setModalState(() => qty++)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: weightController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                        decoration: InputDecoration(
                          labelText: 'Weight (kg) — optional',
                          filled: true,
                          fillColor: const Color(0xFFF8F9FD),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        backgroundColor: SoftErpTheme.accent.withOpacity(0.1),
                        foregroundColor: SoftErpTheme.accent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Fetching weight...'), behavior: SnackBarBehavior.floating),
                        );
                      },
                      icon: const Icon(Icons.bluetooth_connected_rounded, size: 20),
                      label: const Text('Fetch\nWeight', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.1, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    backgroundColor: SoftErpTheme.accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: () {
                    final weight = double.tryParse(weightController.text.trim()) ?? 0.0;
                    Navigator.of(ctx).pop();
                    onConfirm('$qty', weight == 0 ? '0.0' : '$weight');
                  },
                  child: const Text('Confirm Details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.color, required this.onTap});
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, color: color, size: 22)),
      ),
    );
  }
}

class _BrowseTile extends StatelessWidget {
  const _BrowseTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE8ECF5), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: SoftErpTheme.accent.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(icon, color: SoftErpTheme.accent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: SoftErpTheme.textPrimary)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: SoftErpTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              trailing ?? const Icon(Icons.chevron_right_rounded, color: SoftErpTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          ],
        ),
      ),
    );
  }
}

class VendorBrowseScreen extends StatefulWidget {
  final List<DeliveryChallanItem> lines;
  const VendorBrowseScreen({super.key, required this.lines});

  @override
  State<VendorBrowseScreen> createState() => _VendorBrowseScreenState();
}

class _VendorBrowseScreenState extends State<VendorBrowseScreen> {
  bool _reviewing = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

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
          initialItems: List<DeliveryChallanItem>.of(widget.lines),
          lockedType: ChallanType.reception,
        ),
      ),
    );
    _reviewing = false;
    if (!mounted) return;
    if (done == true) {
      widget.lines.clear();
      Navigator.of(context).pop();
    } else if (done is List<DeliveryChallanItem>) {
      setState(() {
        widget.lines.clear();
        widget.lines.addAll(done);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final allVendors = context.watch<VendorsProvider>().vendors.where((v) => !v.isArchived).toList(growable: false);
    final vendors = _searchQuery.isEmpty 
        ? allVendors 
        : allVendors.where((v) => v.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList(growable: false);
    final addedInGroup = widget.lines.length;

    return Scaffold(
      backgroundColor: SoftErpTheme.shellSurface,
      appBar: AppBar(
        title: const Text('Browse Vendors', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search vendors...',
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
            child: vendors.isEmpty
                ? const _EmptyHint(
                    icon: Icons.storefront_outlined,
                    title: 'No vendors found',
                    message: 'Add vendors in the desktop app first.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: vendors.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final v = vendors[index];
                      return _BrowseTile(
                        icon: Icons.storefront_rounded,
                        title: v.name,
                        subtitle: v.gstNumber.isNotEmpty ? 'GST: ${v.gstNumber}' : 'Vendor',
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => VendorHistoryBrowseScreen(vendor: v, lines: widget.lines),
                            ),
                          );
                          if (mounted) setState(() {});
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: addedInGroup == 0
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
                label: Text('Review $addedInGroup Item${addedInGroup == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                onPressed: _goToChallan,
              ),
            ),
    );
  }
}

class VendorHistoryBrowseScreen extends StatefulWidget {
  final VendorDefinition vendor;
  final List<DeliveryChallanItem> lines;

  const VendorHistoryBrowseScreen({super.key, required this.vendor, required this.lines});

  @override
  State<VendorHistoryBrowseScreen> createState() => _VendorHistoryBrowseScreenState();
}

class _VendorHistoryBrowseScreenState extends State<VendorHistoryBrowseScreen> {
  bool _reviewing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VendorHistoryProvider>().loadHistoryForVendor(widget.vendor.id);
    });
  }

  Future<void> _goToChallan() async {
    if (_reviewing) return;
    _reviewing = true;
    final done = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => ChallanMobileEditorScreen(
          initialItems: List<DeliveryChallanItem>.of(widget.lines),
          lockedType: ChallanType.reception,
          initialVendorId: widget.vendor.id,
        ),
      ),
    );
    _reviewing = false;
    if (!mounted) return;
    if (done == true) {
      widget.lines.clear();
      // Reload the history so the newly submitted purchase appears
      context.read<VendorHistoryProvider>().loadHistoryForVendor(widget.vendor.id);
      
      // pop twice to go back to groups screen
      Navigator.of(context).pop();
      Navigator.of(context).pop();
    } else if (done is List<DeliveryChallanItem>) {
      setState(() {
        widget.lines.clear();
        widget.lines.addAll(done);
      });
    }
  }

  void _pickHistoryItem(DeliveryChallanItem historyItem) {
    showPurchaseQuantitySheet(
      context,
      onConfirm: (qty, weight) {
        final newItem = DeliveryChallanItem(
          id: 0,
          orderItemId: null,
          productionRunId: null,
          itemId: historyItem.itemId,
          variationLeafNodeId: historyItem.variationLeafNodeId,
          variationPathLabel: historyItem.variationPathLabel,
          variationPathNodeIds: historyItem.variationPathNodeIds,
          customVariationValues: historyItem.customVariationValues,
          particulars: historyItem.particulars,
          quantityPcs: qty,
          weight: weight,
          lineNo: widget.lines.length + 1,
          hsnCode: '',
          note: '',
        );

        widget.lines.add(newItem);
        setState(() {});
        _goToChallan();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final historyProvider = context.watch<VendorHistoryProvider>();
    final history = historyProvider.getHistoryForVendor(widget.vendor.id);
    final addedInGroup = widget.lines.length;

    return Scaffold(
      backgroundColor: SoftErpTheme.shellSurface,
      appBar: AppBar(
        title: Text(widget.vendor.name, style: const TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      body: historyProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : history.isEmpty
              ? const _EmptyHint(
                  icon: Icons.history_rounded,
                  title: 'No past purchases',
                  message: 'You have not purchased anything from this vendor yet.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: history.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final h = history[index];
                    return _BrowseTile(
                      icon: Icons.history_rounded,
                      title: h.particulars,
                      subtitle: h.variationPathLabel.isNotEmpty ? h.variationPathLabel : 'Standard',
                      onTap: () => _pickHistoryItem(h),
                    );
                  },
                ),
      bottomNavigationBar: addedInGroup == 0
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
                label: Text('Review $addedInGroup Item${addedInGroup == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                onPressed: _goToChallan,
              ),
            ),
    );
  }
}

