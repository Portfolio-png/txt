import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:barcode_widget/barcode_widget.dart';

import 'package:core_erp/core/services/feature_flags.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:core_erp/core/widgets/app_toast.dart';
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

import 'challan_book_screen.dart';
import 'challan_mobile_editor_screen.dart';
import 'internal_use_reconciliation_screens.dart';
import 'purchase_wizard_screens.dart';
import 'use_raw_material_wizard_screen.dart';

final List<DeliveryChallanItem> activePurchaseLines = [];

/// Challan tab entry point: choose Purchase (reception) or Sale (delivery).
/// Only Purchase is enabled for now; Sale is shown as "coming soon".
class ChallanTabScreen extends StatelessWidget {
  const ChallanTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vendors = context.watch<VendorsProvider>().vendors.where((v) => !v.isArchived).toList(growable: false);
    // Gate each action by permission so a read-only staff member never taps a
    // flow that 403s (which is what was crashing on In-use).
    final auth = context.watch<AuthProvider>();
    final canCreate = auth.can('challans.create');
    final canReconcile = auth.can('challans.reconcile');
    final canRead = auth.can('challans.read');

    return Scaffold(
      backgroundColor: SoftErpTheme.shellSurface,
      appBar: AppBar(
        title: const Text('New Challan', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        // Scrolls so the square tiles never overflow once the persistent bottom
        // nav and app bar have taken their share of the height.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              // Keep the tiles a sensible size on wide tablets instead of
              // stretching each square to half the screen.
              constraints: const BoxConstraints(maxWidth: 640),
              child: Builder(
                builder: (context) {
                  // Tiles flow two-per-row: Purchase + Use, then Vendor (when
                  // there are vendors) and In-use (when the reconciliation flag
                  // is on) fill the next row. Building a list keeps the layout
                  // correct for any combination instead of nesting conditionals.
                  final tiles = <Widget>[
                    if (canCreate)
                    _ChoiceCard(
                      title: 'Purchase',
                      subtitle: 'Receive goods from a supplier',
                      icon: Icons.call_received_rounded,
                      color: SoftErpTheme.accent,
                      // Single entry point for Purchase: the flag selects the
                      // implementation. v1 below stays live code so turning the
                      // flag off returns a working flow.
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PurchaseWizardScreen(),
                        ),
                      ),
                    ),
                    if (canCreate)
                    _ChoiceCard(
                      title: 'Use Raw material',
                      subtitle: 'Consume raw materials',
                      icon: Icons.precision_manufacturing_rounded,
                      color: Colors.orange,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const UseRawMaterialWizardScreen()),
                      ),
                    ),

                    // In-use: lists internal-use challans created by the Use
                    // flow and opens the reconciliation screen. Additive and
                    // flag-gated — hidden (Use flow unchanged) when off.
                    if (FeatureFlags.isEnabled(FeatureKeys.challanReconciliation) &&
                        canReconcile)
                      _ChoiceCard(
                        title: 'Settle Production',
                        subtitle: 'Settle used materials',
                        icon: Icons.fact_check_rounded,
                        color: const Color(0xFF2F7DD1),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const InUseReconciliationWizard(),
                          ),
                        ),
                      ),
                    // Challan Book: every challan this person created.
                    if (canRead)
                      _ChoiceCard(
                        title: 'Challan Book',
                        subtitle: 'Challans you created',
                        icon: Icons.menu_book_rounded,
                        color: const Color(0xFF6B5BD2),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ChallanBookScreen(),
                          ),
                        ),
                      ),
                  ];

                  if (tiles.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Column(
                        children: [
                          Icon(Icons.lock_outline_rounded,
                              size: 42, color: SoftErpTheme.textSecondary),
                          SizedBox(height: 12),
                          Text('No challan actions available',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                          SizedBox(height: 6),
                          Text('Ask your admin to grant challan access.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: SoftErpTheme.textSecondary)),
                        ],
                      ),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      for (var i = 0; i < tiles.length; i += 2) ...[
                        if (i > 0) const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: AspectRatio(aspectRatio: 1, child: tiles[i]),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: i + 1 < tiles.length
                                  ? AspectRatio(aspectRatio: 1, child: tiles[i + 1])
                                  : const SizedBox(),
                            ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
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
      title: const Text('Delete challan?', style: TextStyle(fontWeight: FontWeight.w700)),
      content: const Text('The items you\'ve added will be cleared.'),
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

                allowCustomValues: false,
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
                  showAppToast(
                    context, 
                    isFav ? 'Variation saved to favorites' : 'Variation removed from favorites',
                    kind: AppToastKind.success,
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
      onConfirm: (qty, weight, _) {
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
              tooltip: 'Delete challan',
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
      onConfirm: (qty, weight, _) {
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
              tooltip: 'Delete challan',
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
                final itemIdx = itemsProvider.items.indexWhere((i) => i.id == item.itemId);
                final displayName = itemIdx >= 0 ? itemsProvider.items[itemIdx].displayName : item.particulars;
                return _BrowseTile(
                  icon: Icons.favorite_rounded,
                  title: displayName.isEmpty ? 'Unknown Item' : displayName,
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

                allowCustomValues: false,
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
                  showAppToast(
                    context, 
                    isFav ? 'Variation saved to favorites' : 'Variation removed from favorites',
                    kind: AppToastKind.success,
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
      onConfirm: (qty, weight, _) {
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
              tooltip: 'Delete challan',
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

/// Quantity + weight sheet. Calls [onConfirm] with the entered values as strings
/// (matching DeliveryChallanItem's quantityPcs/weight) plus the per-sheet weight
/// breakdown. When [sheetMode] is on, weight is required and the total is spread
/// across one card per sheet — each sheet's weight is editable and Confirm stays
/// disabled until they sum to the allocated total (total-in = total-out). When
/// off (raw-material / legacy flows) it behaves as a lean optional-weight sheet
/// and returns an empty sheet list.
void showPurchaseQuantitySheet(
  BuildContext context, {
  required void Function(String qty, String weight, List<double> sheetWeights) onConfirm,
  String itemName = '',
  bool sheetMode = false,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PurchaseQuantitySheet(
      itemName: itemName,
      sheetMode: sheetMode,
      onConfirm: onConfirm,
    ),
  );
}

class _PurchaseQuantitySheet extends StatefulWidget {
  const _PurchaseQuantitySheet({
    required this.itemName,
    required this.sheetMode,
    required this.onConfirm,
  });

  final String itemName;
  final bool sheetMode;
  final void Function(String qty, String weight, List<double> sheetWeights) onConfirm;

  @override
  State<_PurchaseQuantitySheet> createState() => _PurchaseQuantitySheetState();
}

class _PurchaseQuantitySheetState extends State<_PurchaseQuantitySheet> {
  int _qty = 1;
  // Only used in the legacy/raw-material (non-sheet) flow — a single optional
  // weight. In sheet mode the total is derived from the per-sheet weights below.
  final TextEditingController _totalWeightController = TextEditingController();
  final List<TextEditingController> _sheetControllers = <TextEditingController>[];

  @override
  void initState() {
    super.initState();
    if (!widget.sheetMode) _totalWeightController.addListener(_rebuild);
    _syncControllers();
  }

  @override
  void dispose() {
    _totalWeightController.removeListener(_rebuild);
    _totalWeightController.dispose();
    for (final controller in _sheetControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _rebuild() => setState(() {});

  double _sheetWeightAt(int i) =>
      double.tryParse(_sheetControllers[i].text.trim()) ?? 0.0;

  // Total weight is the sum of the individually weighed sheets — so the operator
  // can weigh each sheet on the spot and immediately see a shortfall vs. what
  // the vendor claims (miscalculation / theft surfaces at the point of delivery).
  double get _sheetSum {
    var sum = 0.0;
    for (final controller in _sheetControllers) {
      sum += double.tryParse(controller.text.trim()) ?? 0.0;
    }
    return sum;
  }

  double get _total => widget.sheetMode
      ? _sheetSum
      : (double.tryParse(_totalWeightController.text.trim()) ?? 0.0);

  int get _weighedCount {
    var count = 0;
    for (final controller in _sheetControllers) {
      if ((double.tryParse(controller.text.trim()) ?? 0.0) > 0) count++;
    }
    return count;
  }

  // Every sheet must be weighed before the line can be confirmed; legacy flows
  // keep weight optional.
  bool get _allWeighed => _qty > 0 && _weighedCount == _qty;

  bool get _canConfirm => widget.sheetMode ? _allWeighed : true;

  void _syncControllers() {
    while (_sheetControllers.length < _qty) {
      _sheetControllers.add(TextEditingController());
    }
    while (_sheetControllers.length > _qty) {
      _sheetControllers.removeLast().dispose();
    }
  }

  String _fmt(double value) {
    final rounded = double.parse(value.toStringAsFixed(3));
    if (rounded == rounded.roundToDouble()) return rounded.toStringAsFixed(0);
    return rounded.toString();
  }

  void _changeQty(int next) {
    // Adding/removing sheets preserves the weights already typed; new sheets
    // start blank for the operator to weigh.
    setState(() {
      _qty = next < 1 ? 1 : next;
      _syncControllers();
    });
  }

  void _confirm() {
    if (!_canConfirm) return;
    final qtyStr = '$_qty';
    if (widget.sheetMode) {
      final sheets = List<double>.generate(_qty, _sheetWeightAt);
      Navigator.of(context).pop();
      widget.onConfirm(qtyStr, _fmt(_sheetSum), sheets);
    } else {
      final weight = _total;
      Navigator.of(context).pop();
      widget.onConfirm(qtyStr, weight == 0 ? '0.0' : _fmt(weight), const <double>[]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allWeighed = _allWeighed;
    final total = _total;
    final weighed = _weighedCount;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
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
          const Text('Set Quantity', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: SoftErpTheme.textPrimary)),
          const SizedBox(height: 20),
          // Sheets pile up here at the top, scrolling within their own region —
          // so adding sheets never pushes the +/- stepper or Confirm around.
          if (widget.sheetMode) ...[
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _qty,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _SheetWeightCard(
                  itemName: widget.itemName,
                  index: i + 1,
                  controller: _sheetControllers[i],
                  onChanged: () => setState(() {}),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Live total = sum of the sheets weighed so far. Turns green once
            // every sheet has a weight; until then it shows how many are left.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: allWeighed ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: allWeighed ? Colors.green.shade200 : Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    allWeighed ? Icons.check_circle_rounded : Icons.scale_rounded,
                    size: 20,
                    color: allWeighed ? Colors.green.shade700 : Colors.orange.shade800,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total weight',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                        ),
                        Text(
                          '${_fmt(total)} kg',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: allWeighed ? Colors.green.shade900 : Colors.orange.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    allWeighed ? '$_qty sheets' : 'weighed $weighed of $_qty',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: allWeighed ? Colors.green.shade800 : Colors.orange.shade900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.sheetMode ? 'Sheets' : 'Pieces', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Row(
                children: [
                  _StepButton(icon: Icons.remove, color: Colors.red, onTap: () => _changeQty(_qty - 1)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text('$_qty', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  ),
                  _StepButton(icon: Icons.add, color: Colors.green, onTap: () => _changeQty(_qty + 1)),
                ],
              ),
            ],
          ),
          if (!widget.sheetMode) ...[
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _totalWeightController,
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Fetching weight...'), behavior: SnackBarBehavior.floating),
                    );
                  },
                  icon: const Icon(Icons.bluetooth_connected_rounded, size: 20),
                  label: const Text('Fetch\nWeight', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.1, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              backgroundColor: SoftErpTheme.accent,
              disabledBackgroundColor: Colors.grey.shade300,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            onPressed: _canConfirm ? _confirm : null,
            child: const Text('Confirm Details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

/// One sheet's card in the quantity overlay: item short code (= item name) and a
/// barcode glyph on top, `Sheet N` and an editable weight field below. The real
/// scannable barcode is minted on the Done step (it needs the challan number);
/// this preview is purely visual.
class _SheetWeightCard extends StatelessWidget {
  const _SheetWeightCard({
    required this.itemName,
    required this.index,
    required this.controller,
    required this.onChanged,
  });

  final String itemName;
  final int index;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final label = itemName.trim().isEmpty ? 'Item' : itemName.trim();
    final previewData =
        '${label.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '')}-$index';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8ECF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: SoftErpTheme.textPrimary),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 96,
                height: 30,
                child: BarcodeWidget(
                  barcode: Barcode.code128(),
                  data: previewData.isEmpty ? 'ITEM-$index' : previewData,
                  drawText: false,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text('Sheet $index', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: controller,
                  onChanged: (_) => onChanged(),
                  textAlign: TextAlign.right,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'weigh',
                    suffixText: 'kg',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Circular +/- button. A tap steps by one; press-and-hold auto-repeats and
/// accelerates so large sheet counts are quick to reach.
class _StepButton extends StatefulWidget {
  const _StepButton({required this.icon, required this.color, required this.onTap});
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  Timer? _holdTimer;
  int _ticks = 0;
  bool _suppressTap = false;

  void _startHold() {
    _ticks = 0;
    _suppressTap = false;
    _scheduleNext(const Duration(milliseconds: 320));
  }

  void _scheduleNext(Duration delay) {
    _holdTimer?.cancel();
    _holdTimer = Timer(delay, () {
      widget.onTap();
      _ticks++;
      // Accelerate as the hold continues, flooring the interval at 40 ms.
      final next = (300 - _ticks * 25).clamp(40, 300);
      _scheduleNext(Duration(milliseconds: next));
    });
  }

  void _stopHold() {
    if (_holdTimer != null) {
      _holdTimer!.cancel();
      _holdTimer = null;
    }
    // If the hold produced any repeats, swallow the tap-up that follows so the
    // count doesn't gain one extra step.
    _suppressTap = _ticks > 0;
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: widget.color.withOpacity(0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTapDown: (_) => _startHold(),
        onTapUp: (_) => _stopHold(),
        onTapCancel: _stopHold,
        onTap: () {
          if (_suppressTap) {
            _suppressTap = false;
            return;
          }
          widget.onTap();
        },
        child: Padding(padding: const EdgeInsets.all(10), child: Icon(widget.icon, color: widget.color, size: 22)),
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
                hintText: 'Search suppliers...',
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
                    title: 'No suppliers found',
                    message: 'Add suppliers in the desktop app first.',
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
                        subtitle: v.gstNumber.isNotEmpty ? 'GST: ${v.gstNumber}' : 'Supplier',
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
      onConfirm: (qty, weight, _) {
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
                  message: 'You have not purchased anything from this supplier yet.',
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

