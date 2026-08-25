import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/navigation/app_navigation.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/soft_master_data.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../../units/domain/unit_definition.dart';
import '../../../units/presentation/providers/units_provider.dart';
import '../../../items/domain/item_definition.dart';
import '../../domain/group_definition.dart';
import '../group_type_style.dart';
import '../providers/groups_provider.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../widgets/group_collage_card.dart';
import '../widgets/group_view_dialog.dart';
import '../widgets/structured_group_editor_dialog.dart';
import '../../../../core/widgets/export_preview_dialog.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key, this.mode = 'items'});

  final String mode;

  /// Opens the group view — what this group is, rather than how to change it.
  ///
  /// Clicking a group lands here; editing is a button inside. Following a
  /// child group or a breadcrumb reopens this same view on the next group, so
  /// a hierarchy can be walked without going back to the list.
  static Future<void> openView(
    BuildContext context, {
    required GroupDefinition group,
  }) {
    return showGroupViewDialog(
      context,
      group: group,
      onEdit: (target) async {
        await GroupsScreen.openEditor(
          context,
          group: target,
          groupType: target.groupType,
        );
      },
      onOpenGroup: (groupId) {
        final next = context
            .read<GroupsProvider>()
            .groups
            .where((candidate) => candidate.id == groupId)
            .firstOrNull;
        if (next == null) return;
        Navigator.of(context).pop();
        GroupsScreen.openView(context, group: next);
      },
    );
  }

  /// Stays on the widget, not the state: the shell and shortcut handlers open
  /// the group editor with no GroupsScreen mounted.
  static Future<GroupDefinition?> openEditor(
    BuildContext context, {
    GroupDefinition? group,
    String groupType = 'item',
    String initialName = '',
    StructuredGroupEditorCreateMode createMode =
        StructuredGroupEditorCreateMode.groupsOnly,
  }) async {
    final result = await StructuredGroupEditorDialog.open(
      context,
      group: group,
      groupType: groupType,
      initialName: initialName,
      createMode: createMode,
    );
    if (result != null && context.mounted) {
      try {
        context.read<InventoryProvider>().refresh();
      } catch (_) {}
      try {
        context.read<ItemsProvider>().refresh();
      } catch (_) {}
    }
    return result;
  }

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  /// Card view is offered for item groups only: a card is a mosaic of the items
  /// inside the group, and machine groups hold no items to draw from.
  bool _isGridView = false;

  String get mode => widget.mode;

  bool get _supportsCards => mode == 'items';

  Future<void> _setGridView(bool value) async {
    setState(() => _isGridView = value);
    if (value) {
      // Covers are fetched the first time cards are opened, not on every load.
      await context.read<GroupsProvider>().ensureCovers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<GroupsProvider, UnitsProvider>(
      builder: (context, groups, units, _) {
        if ((groups.isLoading && groups.groups.isEmpty) ||
            (units.isLoading && units.units.isEmpty)) {
          return const Center(child: CircularProgressIndicator());
        }

        return FocusableActionDetector(
          autofocus: true,
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.keyP, control: true):
                PrintIntent(),
            SingleActivator(LogicalKeyboardKey.keyP, meta: true): PrintIntent(),
          },
          actions: {
            PrintIntent: CallbackAction<PrintIntent>(
              onInvoke: (intent) {
                final currentGroupType = mode == 'machines'
                    ? 'machine'
                    : 'item';
                final data = groups.filteredGroupsByType(currentGroupType).map((
                  g,
                ) {
                  final parentName =
                      groups.parentNameFor(g.parentGroupId) ?? 'Primary Group';
                  final unitName =
                      units.units
                          .where((entry) => entry.id == g.unitId)
                          .firstOrNull
                          ?.displayLabel ??
                      'Unknown unit';
                  return {
                    'id': g.id,
                    'name': g.name,
                    'parent_group': parentName,
                    'unit': unitName,
                    'status': 'Active',
                  };
                }).toList();
                ExportPreviewDialog.show(
                  context,
                  title: mode == 'machines' ? 'Machine Groups' : 'Groups',
                  data: data,
                );
                return null;
              },
            ),
          },
          child: SoftMasterDataPage(
            title: mode == 'machines' ? 'Machine Groups' : 'Groups',
            // Says what a click does, once, rather than repeating it on every
            // row: the tree is the point of the screen and the panel is the
            // second gesture, so both have to be findable.
            subtitle: mode == 'machines'
                ? 'Create nestable groups for machine classification. Click a '
                      'group to open it, double-click to see what is in it.'
                : 'Click a group to unfold what is nested inside it, or '
                      'double-click to open it.',
            action: AppButton(
              label: 'Add Group',
              icon: Icons.add,
              isLoading: groups.isSaving,
              onPressed: () => GroupsScreen.openEditor(
                context,
                groupType: mode == 'machines' ? 'machine' : 'item',
                // Item groups use the same rich (inventory-backed) creation
                // flow as the Inventory screen; machine groups stay simple.
                createMode: mode == 'machines'
                    ? StructuredGroupEditorCreateMode.groupsOnly
                    : StructuredGroupEditorCreateMode.inventoryBacked,
              ),
            ),
            toolbar: _GroupsToolbar(
              mode: mode,
              isGridView: _isGridView,
              onToggleView: _supportsCards
                  ? () => _setGridView(!_isGridView)
                  : null,
            ),
            messages: [
              if (groups.errorMessage != null)
                _GroupsMessageBanner(
                  message: groups.errorMessage!,
                  isError: true,
                ),
            ],
            body:
                groups
                    .filteredGroupsByType(
                      mode == 'machines' ? 'machine' : 'item',
                    )
                    .isEmpty
                ? const AppEmptyState(
                    title: 'No groups found',
                    message:
                        'Create a top-level group like Paper, then add child groups beneath it as needed.',
                    icon: Icons.grid_view_outlined,
                  )
                : _isGridView && _supportsCards
                ? _GroupsCardGrid(
                    groups: groups.filteredGroupsByType('item'),
                    isLoading: groups.isLoading,
                  )
                : _GroupsTable(
                    groups: groups.filteredGroupsByType(
                      mode == 'machines' ? 'machine' : 'item',
                    ),
                    // A search narrows the list, and a group whose parent was
                    // filtered out would have nothing to hang under. While one
                    // is running the list goes flat so every match is visible.
                    isSearching: groups.searchQuery.trim().isNotEmpty,
                  ),
          ),
        );
      },
    );
  }
}

class _GroupsToolbar extends StatelessWidget {
  const _GroupsToolbar({
    required this.mode,
    this.isGridView = false,
    this.onToggleView,
  });

  final String mode;
  final bool isGridView;

  /// Null for machine groups, which have no items to build a card from.
  final VoidCallback? onToggleView;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GroupsProvider>();
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    final tabSegment = SoftSegmentedFilter<String>(
      selected: 'groups',
      onChanged: (value) {
        if (mode == 'items') {
          if (value == 'items') {
            try {
              context.read<AppNavigation>().select('configurator_items');
            } catch (_) {}
          } else if (value == 'sets') {
            // Sets live on the items screen; this tab hands over to it already
            // switched rather than duplicating the list here.
            try {
              context.read<AppNavigation>().select('configurator_sets');
            } catch (_) {}
          }
        } else if (mode == 'machines') {
          if (value == 'machines') {
            try {
              context.read<AppNavigation>().select('configurator_machines');
            } catch (_) {}
          }
        }
      },
      options: mode == 'items'
          // The same three tabs the items screen shows. Sets used to vanish on
          // the way here, which made the strip look like it had lost a tab.
          ? const [
              SoftSegmentOption<String>(value: 'items', label: 'Items'),
              SoftSegmentOption<String>(value: 'groups', label: 'Item Groups'),
              SoftSegmentOption<String>(value: 'sets', label: 'Sets'),
            ]
          : const [
              SoftSegmentOption<String>(
                value: 'machines',
                label: 'Machines Catalog',
              ),
              SoftSegmentOption<String>(
                value: 'groups',
                label: 'Machine Groups',
              ),
            ],
    );

    return SoftMasterToolbar(
      children: [
        tabSegment,
        if (isDesktop)
          Container(
            width: 1,
            height: 28,
            color: SoftErpTheme.border,
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
        if (!isDesktop)
          SoftMasterSearchField(
            width: 300,
            hintText: 'Search groups or parent groups',
            onChanged: provider.setSearchQuery,
          ),
        if (onToggleView != null)
          SoftViewToggleButton(isGridView: isGridView, onTap: onToggleView!),
      ],
    );
  }
}

/// Groups as cards, each faced with a mosaic of the items inside it.
class _GroupsCardGrid extends StatelessWidget {
  const _GroupsCardGrid({required this.groups, this.isLoading = false});

  final List<GroupDefinition> groups;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final units = context.watch<UnitsProvider>();
    final provider = context.watch<GroupsProvider>();
    // The first switch to cards fetches the covers; until they land the cards
    // would all read "No items yet", which is wrong rather than merely empty.
    if (isLoading && !provider.hasCovers) {
      return const Center(child: CircularProgressIndicator());
    }
    return SoftEntityCardGrid(
      itemCount: groups.length,
      maxCardWidth: 260,
      cardHeight: 238,
      itemBuilder: (context, index) {
        final group = groups[index];
        return GroupCollageCard(
          key: ValueKey<String>('group-card-${group.id}'),
          name: group.name,
          covers: group.coverItems,
          basis: group.coverBasis,
          itemCount: group.itemCount,
          parentName: provider.parentNameFor(group.parentGroupId) ?? '',
          unitLabel:
              units.units
                  .where((unit) => unit.id == group.unitId)
                  .firstOrNull
                  ?.displayLabel ??
              '',
          onTap: () => GroupsScreen.openView(context, group: group),
          onOpenItems: () {
            try {
              context.read<AppNavigation>().select('configurator_items');
            } catch (_) {}
          },
        );
      },
    );
  }
}

class _GroupsTable extends StatefulWidget {
  const _GroupsTable({required this.groups, this.isSearching = false});

  final List<GroupDefinition> groups;
  final bool isSearching;

  @override
  State<_GroupsTable> createState() => _GroupsTableState();
}

/// One row of the tree: either a group, or an item sitting inside one.
///
/// Groups nest as groups all the way down, and only the last one in a chain
/// opens onto its items — the same shape the items list has, with the group
/// hierarchy put back in between.
class _GroupTreeEntry {
  const _GroupTreeEntry.group(
    GroupDefinition this.group,
    this.depth,
    this.childCount,
  ) : item = null;

  const _GroupTreeEntry.item(
    ItemDefinition this.item,
    this.depth, {
    this.childCount = 0,
  }) : group = null;

  final GroupDefinition? group;
  final ItemDefinition? item;
  final int depth;

  /// Sub-groups under a group row, or variants under an item row.
  final int childCount;

  bool get isGroup => group != null;
}

class _GroupsTableState extends State<_GroupsTable> {
  /// Groups whose children are showing. Collapsed by default, the way the
  /// items list opens on its groups rather than on everything inside them.
  final Set<int> _expanded = <int>{};

  /// The double-click is recognised here rather than by handing the row an
  /// `onDoubleTap`.
  ///
  /// A widget that answers to both holds the single tap until the double-tap
  /// window closes — roughly a third of a second of nothing happening on the
  /// gesture people use constantly. Unfolding the tree is the primary action
  /// and it has to be immediate, so the first click always unfolds and a second
  /// click landing quickly on the same row opens the panel as well.
  int? _lastTappedGroupId;
  DateTime? _lastTappedAt;

  /// Hands an item over to the items screen, opened on the row.
  ///
  /// The groups tree lists items so that a group's contents are visible from
  /// the structure; it is not where an item is worked on. Clicking one goes to
  /// the screen that owns it rather than growing a second, worse copy of that
  /// screen inside this one.
  void _openInItems(ItemDefinition item) {
    context.read<ItemsProvider>().revealItem(item.id);
    try {
      context.read<AppNavigation>().select('configurator_items');
    } catch (_) {
      // No navigator above us (a test harness, a preview) — the reveal request
      // stands, and the items list will honour it whenever it is next built.
    }
  }

  void _handleRowTap(GroupDefinition group, VoidCallback? toggle) {
    final now = DateTime.now();
    final isSecondClick =
        _lastTappedGroupId == group.id &&
        _lastTappedAt != null &&
        now.difference(_lastTappedAt!) < const Duration(milliseconds: 400);
    _lastTappedGroupId = group.id;
    _lastTappedAt = now;

    if (isSecondClick) {
      GroupsScreen.openView(context, group: group);
      return;
    }
    // Nothing to unfold means the click has only one thing left to mean.
    if (toggle == null) {
      GroupsScreen.openView(context, group: group);
      return;
    }
    toggle();
  }

  /// Items filed under [groupId] — the items themselves, not their variants.
  ///
  /// Read from the items provider rather than fetched: it is already loaded,
  /// already live on the socket, and a second source would disagree with the
  /// items screen sooner or later.
  List<ItemDefinition> _itemsIn(int groupId) {
    return context
        .watch<ItemsProvider>()
        .items
        .where(
          (item) =>
              item.groupId == groupId &&
              !item.isArchived &&
              item.baseItemId == null,
        )
        .toList(growable: false);
  }

  /// The variants struck from [baseItemId] and filed in the same group.
  ///
  /// A variant that has been moved to a group of its own belongs to that
  /// group's list, not to this one — it would otherwise appear twice, under two
  /// different parents.
  List<ItemDefinition> _variantsOf(int baseItemId, int groupId) {
    return context
        .watch<ItemsProvider>()
        .items
        .where(
          (item) =>
              item.baseItemId == baseItemId &&
              item.groupId == groupId &&
              !item.isArchived,
        )
        .toList(growable: false);
  }

  /// The list as a tree — roots first, each open group followed by its own
  /// children, and the last group in a chain followed by the items inside it.
  /// A group whose parent is not in the list stands as a root rather than
  /// disappearing, which is also what keeps a filtered list complete.
  List<_GroupTreeEntry> _rows() {
    final groups = widget.groups;
    final childrenOf = <int?, List<GroupDefinition>>{};
    final present = <int>{for (final group in groups) group.id};

    if (widget.isSearching) {
      return <_GroupTreeEntry>[
        for (final group in groups) _GroupTreeEntry.group(group, 0, 0),
      ];
    }

    for (final group in groups) {
      final parentId =
          group.parentGroupId != null &&
              group.parentGroupId != group.id &&
              present.contains(group.parentGroupId)
          ? group.parentGroupId
          : null;
      childrenOf.putIfAbsent(parentId, () => <GroupDefinition>[]).add(group);
    }
    for (final siblings in childrenOf.values) {
      siblings.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }

    final rows = <_GroupTreeEntry>[];
    // Parent links are cycle-checked server-side; a walk that trusts that and
    // is wrong would hang the screen, so it is guarded here too.
    final visited = <int>{};
    void walk(int? parentId, int depth) {
      for (final group in childrenOf[parentId] ?? const <GroupDefinition>[]) {
        if (!visited.add(group.id)) continue;
        final children = childrenOf[group.id] ?? const <GroupDefinition>[];
        rows.add(_GroupTreeEntry.group(group, depth, children.length));
        if (!_expanded.contains(group.id)) continue;
        walk(group.id, depth + 1);
        // Items come after any nested groups, so a chain of groups reads as a
        // chain of groups and the contents appear at the end of it. A group
        // holding both still shows both — hiding rows that exist would be a
        // worse lie than an extra level of nesting.
        //
        // The tree stops at the item. Variants belong to the items screen,
        // which exists to show an item and everything struck from it — putting
        // them here as well meant two places to look and a dozen near-identical
        // names in the middle of the one view whose job is structure.
        for (final item in _itemsIn(group.id)) {
          rows.add(
            _GroupTreeEntry.item(
              item,
              depth + 1,
              childCount: _variantsOf(item.id, group.id).length,
            ),
          );
        }
      }
    }

    walk(null, 0);
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    return SoftMasterTable(
      minWidth: 980,
      // No "Parent Group" column: where a row sits in the tree says it, and
      // repeating it made every row read "Primary Group" whatever it was.
      columns: const [
        SoftTableColumn('Name', flex: 5),
        SoftTableColumn('Unit', flex: 2),
        SoftTableColumn('Status', flex: 1),
        SoftTableColumn('Actions', flex: 2),
      ],
      itemCount: rows.length,
      rowBuilder: (context, index) {
        final entry = rows[index];
        if (!entry.isGroup) {
          final item = entry.item!;
          return _GroupItemRow(
            item: item,
            depth: entry.depth,
            variantCount: entry.childCount,
            onTap: () => _openInItems(item),
          );
        }
        final group = entry.group!;
        final itemCount = group.itemCount;
        // A group opens if there is anything inside it — sub-groups, items, or
        // both. Before, only sub-groups counted, so a leaf group looked like it
        // held nothing at all.
        final canOpen = entry.childCount > 0 || itemCount > 0;
        final toggle = !canOpen
            ? null
            : () => setState(() {
                if (!_expanded.remove(group.id)) {
                  _expanded.add(group.id);
                }
              });
        return _GroupRow(
          group: group,
          depth: entry.depth,
          childCount: entry.childCount,
          expanded: _expanded.contains(group.id),
          canOpen: canOpen,
          onTap: () => _handleRowTap(group, toggle),
        );
      },
    );
  }
}

/// The rails that show what a row is nested under.
///
/// Indentation alone stops working once a screen has three or four levels on it
/// at once: a row sitting further right says only "deeper than something", not
/// which thing. One rail per ancestor level draws the line back up to it, so a
/// long expanded run stays readable against the top-level rows around it.
class _IndentGuides extends StatelessWidget {
  const _IndentGuides({required this.depth});

  static const double step = 22;

  final int depth;

  @override
  Widget build(BuildContext context) {
    if (depth <= 0) return const SizedBox.shrink();
    return SizedBox(
      width: depth * step,
      height: 34,
      child: Row(
        children: <Widget>[
          for (var level = 0; level < depth; level++)
            SizedBox(
              width: step,
              child: Center(
                child: Container(width: 1.5, color: SoftErpTheme.border),
              ),
            ),
        ],
      ),
    );
  }
}

/// An item sitting inside a group, drawn at the end of the group chain.
///
/// A leaf, and deliberately so: it says what is in the group and how many
/// variants hang off it, then hands over to the items screen for anything more.
/// The variant count is there to say what a click is worth.
class _GroupItemRow extends StatelessWidget {
  const _GroupItemRow({
    required this.item,
    required this.depth,
    this.variantCount = 0,
    this.onTap,
  });

  final ItemDefinition item;
  final int depth;
  final int variantCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isVariant = item.baseItemId != null;
    final label = item.displayName.trim().isEmpty
        ? item.name
        : item.displayName;
    return SoftMasterRow(
      onTap: onTap,
      children: [
        Expanded(
          flex: 5,
          child: Row(
            children: [
              _IndentGuides(depth: depth),
              const SizedBox(width: 8),
              Icon(
                isVariant
                    ? Icons.subdirectory_arrow_right_rounded
                    : Icons.description_outlined,
                size: 16,
                color: isVariant
                    ? SoftErpTheme.entityVariant
                    : SoftErpTheme.textSecondary,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isVariant
                        ? SoftErpTheme.entityVariant
                        : SoftErpTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (variantCount > 0) ...[
                const SizedBox(width: 10),
                _GroupCountPill(
                  count: variantCount,
                  label: variantCount == 1 ? 'variant' : 'variants',
                  color: SoftErpTheme.entityVariant,
                  background: SoftErpTheme.entityVariantBg,
                  border: SoftErpTheme.entityVariantBorder,
                ),
              ],
              const SizedBox(width: 12),
              const Text(
                'Open in Items',
                style: TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const Expanded(flex: 2, child: SizedBox.shrink()),
        const Expanded(flex: 1, child: SizedBox.shrink()),
        const Expanded(flex: 2, child: SizedBox.shrink()),
      ],
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    this.depth = 0,
    this.childCount = 0,
    this.expanded = false,
    this.canOpen = false,
    this.onTap,
  });

  final GroupDefinition group;

  /// How far down the tree this group sits, in parent hops.
  final int depth;

  /// Sub-groups under it. Zero means the row has nothing to open.
  final int childCount;
  final bool expanded;

  /// Whether there is anything inside to unfold — sub-groups or items.
  final bool canOpen;

  /// One handler for the whole row: the table decides whether a click means
  /// unfold or open, because only it can tell a second click from a first.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final groupsProvider = context.watch<GroupsProvider>();
    final unitsProvider = context.watch<UnitsProvider>();
    final unitName =
        _unitLabel(unitsProvider.units, group.unitId) ?? 'Unknown unit';
    final style = GroupTypeStyle.of(group);

    return SoftMasterRow(
      // A click unfolds the group in place — sub-groups and then items, as
      // rows, exactly as clicking a group in the items list unfolds it there.
      // The whole row is the control; there is no separate chevron to hunt for.
      //
      // Reading the group itself is the second gesture, not the first: click
      // again and the detail panel opens. Making that the single click is what
      // stopped the tree ever being seen.
      onTap: onTap,
      children: [
        Expanded(
          flex: 5,
          child: Row(
            children: [
              _IndentGuides(depth: depth),
              Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  style.iconFor(expanded: expanded && canOpen),
                  size: 18,
                  color: style.folder,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      group.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: expanded
                            ? SoftErpTheme.accentDeeper
                            : SoftErpTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (group.usageCount > 0) ...[
                      const SizedBox(height: 4),
                      SoftInlineText(
                        'Used in ${group.usageCount} records',
                        color: SoftErpTheme.textSecondary,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _GroupCountPill(
                count: group.itemCount,
                label: group.itemCount == 1 ? 'item' : 'items',
                color: SoftErpTheme.entityItem,
                background: SoftErpTheme.entityItemBg,
                border: SoftErpTheme.entityItemBorder,
              ),
              if (childCount > 0) ...[
                const SizedBox(width: 8),
                _GroupCountPill(
                  count: childCount,
                  label: childCount == 1 ? 'sub-group' : 'sub-groups',
                  color: SoftErpTheme.entityVariant,
                  background: SoftErpTheme.entityVariantBg,
                  border: SoftErpTheme.entityVariantBorder,
                ),
              ],
              const SizedBox(width: 12),
              Text(
                !canOpen
                    ? 'Empty'
                    : (expanded ? 'Click to collapse' : 'Click to open'),
                style: const TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Expanded(flex: 2, child: SoftInlineText(unitName)),
        Expanded(
          flex: 1,
          child: SoftStatusPill(
            label: 'Active',
            background: const Color(0xFFECFDF5),
            textColor: const Color(0xFF0F766E),
            borderColor: const Color(0xFFBFEAD8),
          ),
        ),
        Expanded(
          flex: 2,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SoftActionLink(
                label: 'Edit',
                onTap: () => GroupsScreen.openEditor(
                  context,
                  group: group,
                  groupType: group.groupType,
                ),
              ),

              SoftActionLink(
                label: 'Delete',
                onTap: groupsProvider.isSaving
                    ? null
                    : () async {
                        final ok = await showConfirmDialog(
                          context,
                          title: 'Delete group?',
                          message:
                              'Permanently delete "${group.name}"? Items and sub-groups under it will need reassignment — check the Action Center afterward. You can restore the group from there too.',
                        );
                        if (ok) groupsProvider.deleteGroup(group.id);
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }

  String? _unitLabel(List<UnitDefinition> units, int? unitId) {
    if (unitId == null) return null;
    final unit = units.where((entry) => entry.id == unitId).firstOrNull;
    return unit?.displayLabel;
  }
}

/// The "N items" / "N sub-groups" tallies on a group row — the same shape the
/// items list uses for its own group headers, so the two read as one screen.
class _GroupCountPill extends StatelessWidget {
  const _GroupCountPill({
    required this.count,
    required this.label,
    required this.color,
    required this.background,
    required this.border,
  });

  final int count;
  final String label;
  final Color color;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _GroupsMessageBanner extends StatelessWidget {
  const _GroupsMessageBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0),
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isError ? const Color(0xFFB91C1C) : const Color(0xFF065F46),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
