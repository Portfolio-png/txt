/// The Item Sets master.
///
/// A set is a bill of materials with quantities — a kit. This list used to be
/// a view inside the items master, reachable only from a segmented control, so
/// it had no search, no row actions, and it listed the sets production mints
/// for itself among the ones people build by hand. It is its own master now,
/// with its own sidebar entry under Items.
///
/// Writes go through `InventoryProvider`, which is where the two traps a set
/// save has to dodge are documented: the server writes `photo_url` on every
/// update (so an omitted photo clears the picture) and an absent `groupId`
/// means "leave the link alone". Regrouping is the one case that *means* to
/// speak about the group, and it is the only thing here that sends it.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/navigation/app_navigation.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../../core/widgets/soft_master_data.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../groups/presentation/group_picker_field.dart';
import '../../../groups/presentation/group_type_style.dart';
import '../../../items/domain/item_definition.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../../items/presentation/widgets/membership_chrome.dart';
import '../../../items/presentation/widgets/set_overview_dialog.dart';
import '../../domain/inventory_set_definition.dart';
import '../../domain/set_membership.dart';
import '../providers/inventory_provider.dart';
import '../widgets/inventory_set_editor_dialog.dart';

/// Which sets the list is showing.
///
/// Production mints a set per assembly run (`is_temporary`, named
/// `Temporary · … · <runId>`) to record what came off the floor. Those are run
/// output, not catalogue — the link picker already refuses to offer them — so
/// the master opens on the ones somebody defined.
enum _SetsFilter {
  defined('defined', 'Defined'),
  produced('produced', 'From production'),
  all('all', 'All');

  const _SetsFilter(this.wire, this.label);

  final String wire;
  final String label;

  bool matches(InventorySetDefinition set) {
    switch (this) {
      case _SetsFilter.defined:
        return !set.isTemporary;
      case _SetsFilter.produced:
        return set.isTemporary;
      case _SetsFilter.all:
        return true;
    }
  }
}

class SetsScreen extends StatefulWidget {
  const SetsScreen({super.key});

  /// The create/edit form. Same dialog the inventory screen and the items
  /// master open, so a set has one editor wherever it is reached from.
  static Future<void> openEditor(
    BuildContext context, {
    InventorySetDefinition? set,
  }) {
    return InventorySetEditorDialog.open(context, setDefinition: set);
  }

  @override
  State<SetsScreen> createState() => _SetsScreenState();
}

class _SetsScreenState extends State<SetsScreen> {
  bool _isGridView = false;
  _SetsFilter _filter = _SetsFilter.defined;
  final Set<int> _expandedSetIds = <int>{};

  @override
  void initState() {
    super.initState();
    // Sets live on the inventory provider, which this screen may be the first
    // thing in the session to touch. Idempotent.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<InventoryProvider>().initialize();
    });
  }

  /// Whether this user may change a set at all.
  ///
  /// Tolerant of a missing provider the way the item editor's Sets card is, so
  /// a widget test that pumps this screen alone still renders.
  bool _can(String permission) {
    try {
      return context.read<AuthProvider>().can(permission);
    } catch (_) {
      return true;
    }
  }

  Future<void> _delete(InventorySetDefinition set) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete "${set.name}"?',
      // Said plainly: unlike a group or an item, a deleted set does not land in
      // the Action Center — the row and its lines go for good.
      message:
          'The set and its ${set.lines.length} '
          'line${set.lines.length == 1 ? '' : 's'} are deleted outright — this '
          'cannot be undone and it will not be in the Action Center to '
          'restore. The items themselves are not touched.',
      confirmLabel: 'Delete set',
    );
    if (!confirmed || !mounted) return;
    await context.read<InventoryProvider>().deleteSet(set.id);
  }

  Future<void> _regroup(InventorySetDefinition set) async {
    final picked = await _RegroupSetDialog.open(context, set: set);
    if (picked == null || !mounted) return;

    final inventory = context.read<InventoryProvider>();
    // Read the set again first: its version is the only thing standing between
    // this save and someone else's edit.
    await inventory.reloadSets();
    if (!mounted) return;
    final current = inventory.sets
        .where((candidate) => candidate.id == set.id)
        .firstOrNull;
    if (current == null) return;

    await inventory.regroupSet(
      setId: current.id,
      name: current.name,
      photoUrl: current.photoUrl ?? '',
      expectedVersion: current.version,
      lines: linesFrom(current),
      groupId: picked.groupId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final items = context.watch<ItemsProvider>().items;
    final sets = inventory.filteredSets
        .where(_filter.matches)
        .toList(growable: false);
    final canEdit = _can('inventory.update');
    final canDelete = _can('inventory.delete');

    return SoftMasterDataPage(
      title: 'Item Sets',
      subtitle:
          'A set bundles items and variants as quantity lines. Orders expand '
          'a set into its parts rather than pointing at it.',
      action: AppButton(
        label: 'Add Set',
        icon: Icons.add,
        onPressed: canEdit ? () => SetsScreen.openEditor(context) : null,
      ),
      toolbar: _SetsToolbar(
        filter: _filter,
        onFilterChanged: (value) => setState(() => _filter = value),
        isGridView: _isGridView,
        onToggleView: () => setState(() => _isGridView = !_isGridView),
        definedCount: inventory.sets.where(_SetsFilter.defined.matches).length,
        producedCount: inventory.sets.where(_SetsFilter.produced.matches).length,
      ),
      messages: [
        if (inventory.errorMessage != null)
          _ErrorBanner(message: inventory.errorMessage!),
      ],
      body: _body(
        inventory: inventory,
        items: items,
        sets: sets,
        canEdit: canEdit,
        canDelete: canDelete,
      ),
    );
  }

  Widget _body({
    required InventoryProvider inventory,
    required List<ItemDefinition> items,
    required List<InventorySetDefinition> sets,
    required bool canEdit,
    required bool canDelete,
  }) {
    if (inventory.isLoading && inventory.sets.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (sets.isEmpty) {
      return AppEmptyState(
        title: inventory.setsQuery.trim().isNotEmpty
            ? 'Nothing matches "${inventory.setsQuery.trim()}"'
            : (_filter == _SetsFilter.produced
                  ? 'No sets have come off a run yet'
                  : 'No sets yet'),
        message: inventory.setsQuery.trim().isNotEmpty
            // The search looks inside the sets too, so say so — otherwise this
            // reads as "there are no sets".
            ? 'Searched set names and the items inside them.'
            : (_filter == _SetsFilter.produced
                  ? 'Production records what each assembly run actually '
                        'produced as a set of its own. None have been made.'
                  : 'A set bundles items and variants as quantity lines — a '
                        'kit. Add one here, or build one while spawning '
                        'variants in the item workflow.'),
        icon: Icons.inventory_2_outlined,
      );
    }

    if (_isGridView) {
      return GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisExtent: 260,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: sets.length,
        itemBuilder: (context, index) => _SetCard(
          set: sets[index],
          variantCount: _variantCountOf(sets[index], items),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      itemCount: sets.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final set = sets[index];
        return _SetRow(
          key: ValueKey<int>(set.id),
          set: set,
          items: items,
          expanded: _expandedSetIds.contains(set.id),
          canEdit: canEdit,
          canDelete: canDelete,
          onTogglePeek: () => setState(() {
            if (!_expandedSetIds.remove(set.id)) _expandedSetIds.add(set.id);
          }),
          onEdit: () => SetsScreen.openEditor(context, set: set),
          onRegroup: () => _regroup(set),
          onDelete: () => _delete(set),
        );
      },
    );
  }

  /// Lines pointing at spawned "basic" items rather than base items.
  static int _variantCountOf(
    InventorySetDefinition set,
    List<ItemDefinition> items,
  ) {
    return set.lines.where((line) {
      final item = items
          .where((candidate) => candidate.id == line.itemId)
          .firstOrNull;
      return item?.isBasicItem ?? false;
    }).length;
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFB91C1C),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SetsToolbar extends StatelessWidget {
  const _SetsToolbar({
    required this.filter,
    required this.onFilterChanged,
    required this.isGridView,
    required this.onToggleView,
    required this.definedCount,
    required this.producedCount,
  });

  final _SetsFilter filter;
  final ValueChanged<_SetsFilter> onFilterChanged;
  final bool isGridView;
  final VoidCallback onToggleView;
  final int definedCount;
  final int producedCount;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    // Items, Item Groups and Item Sets are three masters now, each with its own
    // sidebar entry. The switch stays because it is how people already move
    // between them, and every arm navigates so the sidebar follows.
    final tabSegment = SoftSegmentedFilter<String>(
      selected: 'sets',
      onChanged: (value) {
        if (value == 'sets') return;
        try {
          context.read<AppNavigation>().select(
            value == 'groups' ? 'configurator_groups' : 'configurator_items',
          );
        } catch (_) {}
      },
      options: const [
        SoftSegmentOption<String>(value: 'items', label: 'Items'),
        SoftSegmentOption<String>(value: 'groups', label: 'Item Groups'),
        SoftSegmentOption<String>(value: 'sets', label: 'Item Sets'),
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
        SoftSegmentedFilter<_SetsFilter>(
          selected: filter,
          onChanged: onFilterChanged,
          options: [
            SoftSegmentOption<_SetsFilter>(
              value: _SetsFilter.defined,
              label: _SetsFilter.defined.label,
              count: definedCount,
            ),
            SoftSegmentOption<_SetsFilter>(
              value: _SetsFilter.produced,
              label: _SetsFilter.produced.label,
              count: producedCount,
            ),
            SoftSegmentOption<_SetsFilter>(
              value: _SetsFilter.all,
              label: _SetsFilter.all.label,
            ),
          ],
        ),
        // On desktop the search box lives in the top strip, as it does for
        // every other master.
        if (!isDesktop)
          SoftMasterSearchField(
            hintText: 'Search sets or the items in them',
            onChanged: context.read<InventoryProvider>().setSetsQuery,
          ),
        SoftViewToggleButton(isGridView: isGridView, onTap: onToggleView),
      ],
    );
  }
}

/// One set in the list: what it holds, and the ways to change it.
class _SetRow extends StatelessWidget {
  const _SetRow({
    super.key,
    required this.set,
    required this.items,
    required this.expanded,
    required this.canEdit,
    required this.canDelete,
    required this.onTogglePeek,
    required this.onEdit,
    required this.onRegroup,
    required this.onDelete,
  });

  final InventorySetDefinition set;
  final List<ItemDefinition> items;
  final bool expanded;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onTogglePeek;
  final VoidCallback onEdit;
  final VoidCallback onRegroup;
  final VoidCallback onDelete;

  bool _isVariant(int itemId) {
    final item = items.where((candidate) => candidate.id == itemId).firstOrNull;
    return item?.isBasicItem ?? false;
  }

  /// A control is drawn whatever the answer, and says why when it is off —
  /// never hidden, or nobody can tell a missing permission from a missing
  /// feature.
  Widget _action({
    required String label,
    required bool enabled,
    required String disabledReason,
    required VoidCallback onTap,
  }) {
    final link = SoftActionLink(label: label, onTap: enabled ? onTap : null);
    if (enabled) return link;
    return Tooltip(message: disabledReason, child: link);
  }

  @override
  Widget build(BuildContext context) {
    final variantCount = set.lines.where((l) => _isVariant(l.itemId)).length;
    final produced = set.isTemporary;

    return SoftMasterRow(
      onTap: () => SetOverviewDialog.open(context, set: set),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: onTogglePeek,
                    borderRadius: BorderRadius.circular(6),
                    child: Tooltip(
                      message: expanded ? 'Collapse' : 'Peek inside',
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          expanded
                              ? Icons.folder_open_rounded
                              : Icons.inventory_2_outlined,
                          size: 18,
                          color: expanded
                              ? SoftErpTheme.accent
                              : SoftErpTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      set.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: expanded
                            ? SoftErpTheme.accentDeeper
                            : SoftErpTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (produced) ...[
                    const _ProducedChip(),
                    const SizedBox(width: 8),
                  ],
                  if (set.groupId != null &&
                      (set.groupName?.trim().isNotEmpty ?? false)) ...[
                    _SetGroupChip(set: set),
                    const SizedBox(width: 8),
                  ],
                  EntityCountPill(
                    count: set.lines.length - variantCount,
                    label: 'items',
                    color: SoftErpTheme.entityItem,
                    background: SoftErpTheme.entityItemBg,
                    border: SoftErpTheme.entityItemBorder,
                  ),
                  if (variantCount > 0) ...[
                    const SizedBox(width: 8),
                    EntityCountPill(
                      count: variantCount,
                      label: variantCount == 1 ? 'variant' : 'variants',
                      color: SoftErpTheme.entityVariant,
                      background: SoftErpTheme.entityVariantBg,
                      border: SoftErpTheme.entityVariantBorder,
                    ),
                  ],
                  const SizedBox(width: 10),
                  Text(
                    '${set.totalItemCount} total',
                    style: const TextStyle(
                      color: SoftErpTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _action(
                    label: 'Edit',
                    // A produced set belongs to the run that made it; editing
                    // its composition would make it a record of something that
                    // did not happen.
                    enabled: canEdit && !produced,
                    disabledReason: produced
                        ? 'This set is what a production run made. Its '
                              'composition is a record, so it cannot be edited.'
                        : 'You do not have permission to change sets '
                              '(inventory.update).',
                    onTap: onEdit,
                  ),
                  const SizedBox(width: 6),
                  _action(
                    label: 'Regroup',
                    enabled: canEdit && !produced,
                    disabledReason: produced
                        ? 'A set made by a run is not filed under a group.'
                        : 'You do not have permission to change sets '
                              '(inventory.update).',
                    onTap: onRegroup,
                  ),
                  const SizedBox(width: 6),
                  _action(
                    label: 'Delete',
                    enabled: canDelete,
                    disabledReason:
                        'You do not have permission to delete sets '
                        '(inventory.delete).',
                    onTap: onDelete,
                  ),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 12),
                const Divider(height: 1, color: SoftErpTheme.border),
                const SizedBox(height: 10),
                if (set.lines.isEmpty)
                  const Text(
                    'Empty set.',
                    style: TextStyle(
                      color: SoftErpTheme.textSecondary,
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else
                  for (final line in set.lines)
                    EntityMemberRow(
                      label: line.itemDisplayName.trim().isNotEmpty
                          ? line.itemDisplayName
                          : (line.itemName.trim().isNotEmpty
                                ? line.itemName
                                : 'Item #${line.itemId}'),
                      isVariant: _isVariant(line.itemId),
                      quantity: line.quantity,
                    ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Says a set came off the floor rather than being defined by hand.
class _ProducedChip extends StatelessWidget {
  const _ProducedChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.precision_manufacturing_outlined,
            size: 14,
            color: SoftErpTheme.textSecondary,
          ),
          SizedBox(width: 5),
          Text(
            'From production',
            style: TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Where a set is filed, asked on its own.
///
/// The full editor can change this too, but opening a form with three columns
/// of composition to move one set into a group is not the shape of the job.
class _RegroupSetDialog extends StatefulWidget {
  const _RegroupSetDialog({required this.set});

  final InventorySetDefinition set;

  static Future<({int? groupId})?> open(
    BuildContext context, {
    required InventorySetDefinition set,
  }) {
    return showErpFormDialog<({int? groupId})>(
      context,
      maxWidth: 520,
      maxHeight: 420,
      child: _RegroupSetDialog(set: set),
    );
  }

  @override
  State<_RegroupSetDialog> createState() => _RegroupSetDialogState();
}

class _RegroupSetDialogState extends State<_RegroupSetDialog> {
  int? _groupId;

  @override
  void initState() {
    super.initState();
    _groupId = widget.set.groupId;
  }

  @override
  Widget build(BuildContext context) {
    return ErpFormScaffold(
      title: 'File "${widget.set.name}"',
      subtitle:
          'A set files under a group the same way an item does. Leaving it '
          'ungrouped is a real answer — it simply will not show under a group.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          GroupPickerField(
            value: _groupId,
            onChanged: (value) => setState(() => _groupId = value),
            tapTargetKey: const ValueKey<String>('sets-regroup-field'),
            nullOptionLabel: 'Ungrouped',
            decoration: const InputDecoration(
              labelText: 'Group',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      onClose: () => Navigator.of(context).pop(),
      footer: Row(
        children: [
          const Spacer(),
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: 'File set',
            icon: Icons.folder_outlined,
            onPressed: () => Navigator.of(context).pop((groupId: _groupId)),
          ),
        ],
      ),
    );
  }
}

/// The group a set is filed under, drawn from the set itself rather than from
/// GroupsProvider: the name travels on the DTO, so a surface that shows a set
/// never has to depend on the groups master being loaded.
class _SetGroupChip extends StatelessWidget {
  const _SetGroupChip({required this.set});

  final InventorySetDefinition set;

  @override
  Widget build(BuildContext context) {
    final name = set.groupName?.trim() ?? '';
    if (set.groupId == null || name.isEmpty) return const SizedBox.shrink();
    final archived = set.groupIsArchived;
    // The ordinary item-group palette. A set carries its group's name but not
    // its type, and the plain folder is the right thing to read as "a group".
    const style = GroupTypeStyle.hierarchical;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: archived ? SoftErpTheme.cardSurface : style.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: archived ? SoftErpTheme.border : style.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_outlined,
            size: 14,
            color: archived ? SoftErpTheme.textSecondary : style.folder,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              archived ? '$name · archived' : name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: archived ? SoftErpTheme.textSecondary : style.folder,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A set on a card, led by its own photo. Falls back to initials on a soft
/// ground when none has been uploaded — same treatment an item card gives a
/// picture-less item, so a mixed grid reads evenly.
class _SetCard extends StatelessWidget {
  const _SetCard({required this.set, required this.variantCount});

  final InventorySetDefinition set;
  final int variantCount;

  @override
  Widget build(BuildContext context) {
    final photoUrl = set.photoUrl;
    final baseCount = set.lines.length - variantCount;
    return AppCard(
      onTap: () => SetOverviewDialog.open(context, set: set),
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: photoUrl == null || photoUrl.isEmpty
                  ? _SetCardPlaceholder(name: set.name)
                  : Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _SetCardPlaceholder(name: set.name),
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              color: SoftErpTheme.cardSurface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    set.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SoftErpTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (set.groupId != null &&
                      (set.groupName?.trim().isNotEmpty ?? false)) ...[
                    const SizedBox(height: 6),
                    _SetGroupChip(set: set),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      EntityCountPill(
                        count: baseCount,
                        label: 'items',
                        color: SoftErpTheme.entityItem,
                        background: SoftErpTheme.entityItemBg,
                        border: SoftErpTheme.entityItemBorder,
                      ),
                      if (variantCount > 0)
                        EntityCountPill(
                          count: variantCount,
                          label: variantCount == 1 ? 'variant' : 'variants',
                          color: SoftErpTheme.entityVariant,
                          background: SoftErpTheme.entityVariantBg,
                          border: SoftErpTheme.entityVariantBorder,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetCardPlaceholder extends StatelessWidget {
  const _SetCardPlaceholder({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .take(2)
        .map((part) => part.substring(0, 1).toUpperCase());
    final token = parts.isEmpty ? 'ST' : parts.join();
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFDFBF6), Color(0xFFF1F5F9)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              token,
              style: const TextStyle(
                color: SoftErpTheme.accentDark,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'No photo yet',
              style: TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
