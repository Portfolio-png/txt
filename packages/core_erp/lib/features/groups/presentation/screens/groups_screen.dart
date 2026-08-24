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
import '../../domain/group_definition.dart';
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
            subtitle: mode == 'machines'
                ? 'Create nestable groups for machine classification.'
                : 'Create item and component groups, each mapped to a reusable unit from Configurator Units.',
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

/// One group and how deep it sits, so a row can indent itself.
class _GroupTreeEntry {
  const _GroupTreeEntry(this.group, this.depth, this.childCount);

  final GroupDefinition group;
  final int depth;
  final int childCount;
}

class _GroupsTableState extends State<_GroupsTable> {
  /// Groups whose children are showing. Collapsed by default, the way the
  /// items list opens on its groups rather than on everything inside them.
  final Set<int> _expanded = <int>{};

  /// The list as a tree — roots first, each open group followed by its own
  /// children. A group whose parent is not in the list stands as a root rather
  /// than disappearing, which is also what keeps a filtered list complete.
  List<_GroupTreeEntry> _rows() {
    final groups = widget.groups;
    final childrenOf = <int?, List<GroupDefinition>>{};
    final present = <int>{for (final group in groups) group.id};

    if (widget.isSearching) {
      return <_GroupTreeEntry>[
        for (final group in groups) _GroupTreeEntry(group, 0, 0),
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
        rows.add(_GroupTreeEntry(group, depth, children.length));
        if (_expanded.contains(group.id)) walk(group.id, depth + 1);
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
        return _GroupRow(
          group: entry.group,
          depth: entry.depth,
          childCount: entry.childCount,
          expanded: _expanded.contains(entry.group.id),
          onToggle: entry.childCount == 0
              ? null
              : () => setState(() {
                  if (!_expanded.remove(entry.group.id)) {
                    _expanded.add(entry.group.id);
                  }
                }),
        );
      },
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    this.depth = 0,
    this.childCount = 0,
    this.expanded = false,
    this.onToggle,
  });

  final GroupDefinition group;

  /// How far down the tree this group sits, in parent hops.
  final int depth;

  /// Sub-groups under it. Zero means the row has nothing to open.
  final int childCount;
  final bool expanded;

  /// Opens or closes the sub-groups. Null when there are none, which is what
  /// turns the folder into a plain one and drops the hint text.
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final groupsProvider = context.watch<GroupsProvider>();
    final unitsProvider = context.watch<UnitsProvider>();
    final unitName =
        _unitLabel(unitsProvider.units, group.unitId) ?? 'Unknown unit';
    final hasChildren = onToggle != null;
    final isCombination = group.groupStructure == 'combination';

    return SoftMasterRow(
      // Opening the group is what a click on the row means, the same as in the
      // items list. The folder itself is the control for unfolding it.
      onTap: () => GroupsScreen.openView(context, group: group),
      children: [
        Expanded(
          flex: 5,
          child: Padding(
            padding: EdgeInsets.only(left: depth * 22.0),
            child: Row(
              children: [
                if (hasChildren)
                  InkWell(
                    onTap: onToggle,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        expanded
                            ? Icons.folder_open_rounded
                            : Icons.folder_rounded,
                        size: 18,
                        color: expanded
                            ? SoftErpTheme.accent
                            : SoftErpTheme.textSecondary,
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      isCombination
                          ? Icons.folder_special_rounded
                          : Icons.folder_outlined,
                      size: 18,
                      color: SoftErpTheme.textSecondary,
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
                if (hasChildren) ...[
                  const SizedBox(width: 12),
                  Text(
                    expanded ? 'Click to collapse' : 'Click to open',
                    style: const TextStyle(
                      color: SoftErpTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
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
