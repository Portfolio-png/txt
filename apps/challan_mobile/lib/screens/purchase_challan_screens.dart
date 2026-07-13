import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/features/delivery_challans/domain/delivery_challan.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/widgets/variation_path_selector_dialog.dart';

import 'challan_mobile_editor_screen.dart';

/// Challan tab entry point: choose Purchase (reception) or Sale (delivery).
/// Only Purchase is enabled for now; Sale is shown as "coming soon".
class ChallanTabScreen extends StatelessWidget {
  const ChallanTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
          child: Column(
            children: [
              const SizedBox(height: 8),
              _ChoiceCard(
                title: 'Purchase',
                subtitle: 'Receive goods from a vendor (reception challan)',
                icon: Icons.call_received_rounded,
                color: SoftErpTheme.accent,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PurchaseGroupBrowseScreen()),
                ),
              ),
              const SizedBox(height: 16),
              _ChoiceCard(
                title: 'Sale',
                subtitle: 'Deliver goods to a client — coming soon',
                icon: Icons.call_made_rounded,
                color: Colors.grey,
                disabled: true,
                onTap: () {},
              ),
            ],
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
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE8ECF5), width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: SoftErpTheme.textPrimary)),
                          if (disabled) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(999)),
                              child: Text('SOON', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey.shade600)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle, style: const TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                if (!disabled) const Icon(Icons.chevron_right_rounded, color: SoftErpTheme.textSecondary),
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
  final List<DeliveryChallanItem> _lines = [];
  bool _reviewing = false;

  @override
  Widget build(BuildContext context) {
    final itemsProvider = context.watch<ItemsProvider>();
    final groupsProvider = context.watch<GroupsProvider>();

    final purchaseItems = itemsProvider.items
        .where((i) => i.availableForPurchase && !i.isArchived)
        .toList(growable: false);
    final groupIdsWithPurchase = purchaseItems.map((i) => i.groupId).toSet();
    final groups = groupsProvider.itemGroups
        .where((g) => !g.isArchived && groupIdsWithPurchase.contains(g.id))
        .toList(growable: false);

    return Scaffold(
      backgroundColor: SoftErpTheme.shellSurface,
      appBar: AppBar(
        title: const Text('Purchase — Groups', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        actions: [
          if (_lines.isNotEmpty)
            IconButton(
              tooltip: 'Discard challan',
              icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFD64545)),
              onPressed: () => confirmDiscardChallan(context, _lines),
            ),
        ],
      ),
      body: groups.isEmpty
          ? const _EmptyHint(
              icon: Icons.category_outlined,
              title: 'No purchase items yet',
              message: 'Mark items as "Available for purchase" in the desktop app to see them here.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final group = groups[index];
                final count = purchaseItems.where((i) => i.groupId == group.id).length;
                return _BrowseTile(
                  icon: Icons.folder_open_rounded,
                  title: group.name,
                  subtitle: '$count item${count == 1 ? '' : 's'}',
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PurchaseItemBrowseScreen(group: group, lines: _lines),
                      ),
                    );
                    if (mounted) setState(() {}); // refresh cart count
                  },
                );
              },
            ),
      bottomNavigationBar: _lines.isEmpty
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
                label: Text('Review Challan (${_lines.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                onPressed: () async {
                  if (_reviewing) return; // guard against a double-tap opening two editors
                  _reviewing = true;
                  final done = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => ChallanMobileEditorScreen(
                        initialItems: List<DeliveryChallanItem>.of(_lines),
                        lockedType: ChallanType.reception,
                      ),
                    ),
                  );
                  _reviewing = false;
                  if (done == true && mounted) setState(() => _lines.clear());
                },
              ),
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
    final done = await Navigator.of(context).push<bool>(
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
    }
  }

  Future<void> _pickItem(ItemDefinition item) async {
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
              ),
            ),
          ),
        ),
      );
      if (variation == null || !mounted) return;
    }

    showPurchaseQuantitySheet(context, (qty, weight) {
      widget.lines.add(
        DeliveryChallanItem(
          id: 0,
          orderItemId: null,
          productionRunId: null,
          itemId: item.id,
          variationLeafNodeId: variation?.leaf?.id ?? 0,
          variationPathLabel: variation?.leaf?.displayName ?? '',
          variationPathNodeIds: variation?.valueNodeIds ?? const <int>[],
          customVariationValues: variation?.customVariationValues ?? const <int, String>{},
          particulars: item.displayName,
          quantityPcs: qty,
          weight: weight,
          lineNo: widget.lines.length + 1,
          hsnCode: '',
          note: '',
        ),
      );
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${item.displayName}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 900),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final itemsProvider = context.watch<ItemsProvider>();
    final items = itemsProvider.items
        .where((i) => i.availableForPurchase && !i.isArchived && i.groupId == widget.group.id)
        .toList(growable: false);
    final addedInGroup = widget.lines.length;

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
      body: items.isEmpty
          ? const _EmptyHint(
              icon: Icons.inventory_2_outlined,
              title: 'No purchase items in this group',
              message: 'Mark items as "Available for purchase" in the desktop app.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = items[index];
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
  BuildContext context,
  void Function(String qty, String weight) onConfirm,
) {
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
                const Text('Set Quantity', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: SoftErpTheme.textPrimary)),
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
                TextField(
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
            Icon(icon, size: 56, color: SoftErpTheme.textSecondary),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: SoftErpTheme.textPrimary)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: SoftErpTheme.textSecondary, fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
