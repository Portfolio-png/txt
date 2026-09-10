import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../domain/group_definition.dart';
import '../../domain/group_overview.dart';
import '../providers/groups_provider.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../../items/domain/item_definition.dart';

/// What a group is, rather than how to change it.
///
/// Clicking a group used to open the editor, which answers the second question
/// when the first one was being asked. A group is more than a name and a
/// parent: it decides what properties its items carry, it may inherit more of
/// them from a lineage, and the items inside it say things about the group that
/// none of its own fields do.
///
/// Editing is still one button away, but it is no longer the only thing a click
/// can mean.
/// Opened as a panel down the right-hand edge rather than a dialog over the
/// middle of the screen — the same shape inventory uses for a record.
///
/// The difference is not decoration. A group is read *against* the list it came
/// from: which of its siblings it sits beside, what else is in the tree. A
/// centred dialog covers exactly that. The panel leaves the list in place, so
/// walking down it and reading each group in turn is one click per group
/// instead of open-read-close.
Future<void> showGroupViewDialog(
  BuildContext context, {
  required GroupDefinition group,
  Future<void> Function(GroupDefinition group)? onEdit,
  void Function(int groupId)? onOpenGroup,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Group details',
    barrierColor: const Color(0x66100D1F),
    pageBuilder: (context, animation, secondaryAnimation) {
      return SafeArea(
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 12, right: 12, bottom: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 560,
                minWidth: 420,
              ),
              child: _GroupViewSheet(
                group: group,
                onEdit: onEdit,
                onOpenGroup: onOpenGroup,
              ),
            ),
          ),
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.08, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

class _GroupViewSheet extends StatefulWidget {
  const _GroupViewSheet({required this.group, this.onEdit, this.onOpenGroup});

  final GroupDefinition group;
  final Future<void> Function(GroupDefinition group)? onEdit;
  final void Function(int groupId)? onOpenGroup;

  @override
  State<_GroupViewSheet> createState() => _GroupViewSheetState();
}

class _GroupViewSheetState extends State<_GroupViewSheet> {
  GroupOverview? _overview;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final overview = await context.read<GroupsProvider>().loadOverview(
      widget.group.id,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _overview = overview;
      _error = overview == null ? 'Could not open this group.' : null;
    });
  }

  /// What kind of group this is, in the words the editor uses for it.
  String get _structureLabel {
    if (widget.group.isCombination) return 'Combination group';
    if (widget.group.isComponent) return 'Component group';
    return widget.group.groupType == 'machine' ? 'Machine group' : 'Item group';
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    return ErpFormScaffold(
      title: widget.group.name,
      subtitle: _structureLabel,
      onClose: () => Navigator.of(context).pop(),
      eyebrow: overview == null || overview.ancestors.isEmpty
          ? null
          : _Breadcrumb(
              ancestors: overview.ancestors,
              onOpenGroup: widget.onOpenGroup,
            ),
      errorBanner: _error == null ? null : _ErrorBanner(message: _error!),
      body: _loading
          ? const SizedBox(
              height: 320,
              child: Center(child: CircularProgressIndicator()),
            )
          : overview == null
          ? const SizedBox.shrink()
          : _Body(overview: overview, onOpenGroup: widget.onOpenGroup),
      footer: Row(
        children: <Widget>[
          const Spacer(),
          AppButton(
            label: 'Close',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          if (widget.onEdit != null) ...<Widget>[
            const SizedBox(width: 12),
            AppButton(
              label: 'Edit Group',
              icon: Icons.edit_outlined,
              onPressed: () async {
                Navigator.of(context).pop();
                await widget.onEdit!(widget.group);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.overview, this.onOpenGroup});

  final GroupOverview overview;
  final void Function(int groupId)? onOpenGroup;

  @override
  Widget build(BuildContext context) {
    final description = overview.group.description.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (description.isNotEmpty) ...<Widget>[
          Text(
            description,
            style: const TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
        ],
        _SummaryStrip(summary: overview.summary),
        const SizedBox(height: 16),
        // Items first: they are what someone opening a group came to see, and
        // the sections below are about the group rather than its contents.
        if (overview.group.isComponent)
          _ComponentWorkflowTable(overview: overview)
        else ...[
          _Items(overview: overview),
          const SizedBox(height: 16),
          _Properties(overview: overview),
        ],
      ],
    );
  }
}

/// The figures the items add up to. Counted from the rows below, never from a
/// separate query that could drift away from them.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.summary});

  final GroupSummary summary;

  @override
  Widget build(BuildContext context) {
    final facts = <(String, String)>[
      ('Items', '${summary.itemCount}'),
      if (summary.orderedItemCount > 0)
        ('Ordered', '${summary.orderedItemCount} of ${summary.itemCount}'),
      if (summary.orderLineCount > 0)
        ('Order lines', '${summary.orderLineCount}'),
      if (summary.variantCount > 0) ('Variants', '${summary.variantCount}'),
      if (summary.withPipelineCount > 0)
        ('On a pipeline', '${summary.withPipelineCount}'),
      if (summary.withBaselineCount > 0)
        ('Master Data', '${summary.withBaselineCount}'),
      if (summary.units.isNotEmpty) ('Units', summary.units.join(', ')),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        for (final (label, value) in facts) _Fact(label: label, value: value),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: SoftErpTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// The chain this group hangs off, which is also the chain its properties are
/// inherited down.
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.ancestors, this.onOpenGroup});

  final List<GroupChild> ancestors;
  final void Function(int groupId)? onOpenGroup;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final ancestor in ancestors) ...<Widget>[
          InkWell(
            onTap: onOpenGroup == null
                ? null
                : () => onOpenGroup!(ancestor.groupId),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Text(
                ancestor.name,
                style: TextStyle(
                  color: onOpenGroup == null
                      ? SoftErpTheme.textSecondary
                      : SoftErpTheme.accent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 14,
            color: SoftErpTheme.textSecondary,
          ),
        ],
      ],
    );
  }
}

/// What every item in this group carries, and which group in the lineage said
/// so — the thing that makes a group more than a folder.
class _Properties extends StatelessWidget {
  const _Properties({required this.overview});

  final GroupOverview overview;

  @override
  Widget build(BuildContext context) {
    final own = overview.ownProperties;
    final inherited = overview.inheritedProperties;
    return ErpDialogSectionCard(
      title: 'Properties its items carry',
      subtitle: overview.properties.isEmpty
          ? 'None yet — items here have no group-defined properties'
          : '${overview.properties.length} in total, '
                '${inherited.length} inherited',
      child: overview.properties.isEmpty
          ? const Text(
              'Properties added to this group become fields on every item '
              'filed under it, and on every group beneath it.',
              style: TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 12.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final property in own)
                  _PropertyChip(property: property, inherited: false),
                for (final property in inherited)
                  _PropertyChip(property: property, inherited: true),
              ],
            ),
    );
  }
}

class _PropertyChip extends StatelessWidget {
  const _PropertyChip({required this.property, required this.inherited});

  final GroupProperty property;
  final bool inherited;

  @override
  Widget build(BuildContext context) {
    final unit = property.unitSymbol.trim();
    return Tooltip(
      message: inherited
          ? 'Inherited from ${property.sourceGroupName}'
          : 'Defined on this group',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: inherited
              ? SoftErpTheme.sectionSurface
              : SoftErpTheme.accentSurface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: inherited
                ? SoftErpTheme.border
                : SoftErpTheme.accent.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (inherited) ...<Widget>[
              const Icon(
                Icons.subdirectory_arrow_right_rounded,
                size: 13,
                color: SoftErpTheme.textSecondary,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              unit.isEmpty
                  ? property.displayName
                  : '${property.displayName} ($unit)',
              style: TextStyle(
                color: inherited
                    ? SoftErpTheme.textPrimary
                    : SoftErpTheme.accentDeeper,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (property.mandatory) ...<Widget>[
              const SizedBox(width: 4),
              const Text(
                '*',
                style: TextStyle(
                  color: Color(0xFFB91C1C),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One base item and the variants filed under it, which land in the same group
/// as their base and would otherwise sit beside it as if they were peers.
class _ItemBranch {
  const _ItemBranch(this.item, this.variants);

  final GroupOverviewItem item;
  final List<GroupOverviewItem> variants;
}

class _Items extends StatefulWidget {
  const _Items({required this.overview});

  final GroupOverview overview;

  @override
  State<_Items> createState() => _ItemsState();
}

class _ItemsState extends State<_Items> {
  /// Base items whose variants are showing. Collapsed is the default: the point
  /// of nesting them is that the group reads as its items, not its variants.
  final Set<int> _expanded = <int>{};

  /// The flat list rearranged into base items with their own variants beneath.
  ///
  /// A variant whose base item is not in this list — moved to another group,
  /// archived, or filed here on its own — is left at the top level rather than
  /// dropped, so nothing disappears from the group it is actually in.
  List<_ItemBranch> _branches(List<GroupOverviewItem> items) {
    final present = <int>{for (final item in items) item.itemId};
    bool nestsUnderBase(GroupOverviewItem item) {
      final baseId = item.baseItemId;
      return baseId != null &&
          baseId != item.itemId &&
          present.contains(baseId);
    }

    final variantsByBase = <int, List<GroupOverviewItem>>{};
    for (final item in items) {
      if (!nestsUnderBase(item)) continue;
      variantsByBase
          .putIfAbsent(item.baseItemId!, () => <GroupOverviewItem>[])
          .add(item);
    }

    return <_ItemBranch>[
      for (final item in items)
        if (!nestsUnderBase(item))
          _ItemBranch(
            item,
            variantsByBase[item.itemId] ?? const <GroupOverviewItem>[],
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final overview = widget.overview;
    final items = overview.items;
    final branches = _branches(items);
    return ErpDialogSectionCard(
      title: overview.itemSource.label,
      subtitle: overview.itemSource.explanation,
      child: items.isEmpty
          ? const Text(
              'Nothing in this group yet.',
              style: TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            )
          : Column(
              children: <Widget>[
                for (final branch in branches) ...<Widget>[
                  _ItemRow(
                    item: branch.item,
                    variantCount: branch.variants.length,
                    isExpanded: _expanded.contains(branch.item.itemId),
                    onToggleVariants: branch.variants.isEmpty
                        ? null
                        : () => setState(() {
                            if (!_expanded.remove(branch.item.itemId)) {
                              _expanded.add(branch.item.itemId);
                            }
                          }),
                  ),
                  if (_expanded.contains(branch.item.itemId))
                    for (final variant in branch.variants)
                      _ItemRow(item: variant, isNested: true),
                ],
              ],
            ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    this.isNested = false,
    this.variantCount = 0,
    this.isExpanded = false,
    this.onToggleVariants,
  });

  final GroupOverviewItem item;

  /// Drawn under its base item rather than at the top level.
  final bool isNested;

  final int variantCount;
  final bool isExpanded;
  final VoidCallback? onToggleVariants;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey<String>('group-item-${item.itemId}'),
      padding: EdgeInsets.only(bottom: 8, left: isNested ? 24 : 0),
      child: Row(
        children: <Widget>[
          if (isNested) ...<Widget>[
            const Icon(
              Icons.subdirectory_arrow_right_rounded,
              size: 16,
              color: SoftErpTheme.textSecondary,
            ),
            const SizedBox(width: 6),
          ],
          _Thumb(item: item),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isNested
                        ? SoftErpTheme.entityVariant
                        : SoftErpTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: isNested ? FontWeight.w600 : FontWeight.w700,
                  ),
                ),
                if (_meta.isNotEmpty)
                  Text(
                    _meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SoftErpTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          if (onToggleVariants != null) ...<Widget>[
            const SizedBox(width: 8),
            _VariantToggle(
              count: variantCount,
              isExpanded: isExpanded,
              onTap: onToggleVariants!,
            ),
          ],
          const SizedBox(width: 8),
          Text(
            item.isOrdered
                ? '${item.orderCount} order${item.orderCount == 1 ? '' : 's'}'
                : 'Not ordered',
            style: TextStyle(
              color: item.isOrdered
                  ? SoftErpTheme.textPrimary
                  : SoftErpTheme.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String get _meta {
    final parts = <String>[
      // Nested under its base, the indent already says "variant"; standing at
      // the top level because its base is elsewhere, the word still has to.
      if (item.isVariant && !isNested) 'Variant',
      if (item.unitName.trim().isNotEmpty) item.unitName.trim(),
      if (item.hasPipeline) 'On a pipeline',
      if (item.hasBaseline) 'Master Data',
    ];
    return parts.join('  ·  ');
  }
}

/// The control that opens a base item's variants. Carries the count so the
/// group still says how many there are while they are folded away.
class _VariantToggle extends StatelessWidget {
  const _VariantToggle({
    required this.count,
    required this.isExpanded,
    required this.onTap,
  });

  final int count;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = '$count ${count == 1 ? 'variant' : 'variants'}';
    return Tooltip(
      message: isExpanded ? 'Hide variants' : 'Show variants',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                isExpanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 16,
                color: SoftErpTheme.entityVariant,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: SoftErpTheme.entityVariant,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.item});

  final GroupOverviewItem item;

  @override
  Widget build(BuildContext context) {
    final letters = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Text(
        item.name.isEmpty ? '?' : item.name.substring(0, 1).toUpperCase(),
        style: const TextStyle(
          color: SoftErpTheme.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    if (!item.hasPhoto) return letters;
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Image.network(
        item.photoUrl,
        width: 34,
        height: 34,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => letters,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13),
      ),
    );
  }
}

class _ComponentWorkflowTable extends StatelessWidget {
  const _ComponentWorkflowTable({required this.overview});

  final GroupOverview overview;

  @override
  Widget build(BuildContext context) {
    final items = context
        .watch<ItemsProvider>()
        .items
        .where((item) => item.groupId == overview.group.id && !item.isArchived)
        .toList(growable: false);

    return ErpDialogSectionCard(
      title: 'Component Workflow',
      subtitle: 'Pipelines and attachments assigned to these items.',
      child: items.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Nothing in this group yet.',
                  style: TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: items.map((item) => _WorkflowItemHierarchy(item: item)).toList(),
              ),
            ),
    );
  }
}

class _WorkflowItemHierarchy extends StatelessWidget {
  const _WorkflowItemHierarchy({required this.item});
  
  final ItemDefinition item;

  @override
  Widget build(BuildContext context) {
    final hasPipeline = (item.defaultPipelineName ?? '').trim().isNotEmpty;
    final hasAttachments = item.machines.isNotEmpty || item.dies.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: SoftErpTheme.surfaceDecoration(
        color: SoftErpTheme.cardSurface,
        showBorder: true,
        radius: SoftErpTheme.radiusSm,
        elevated: false,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WorkflowTimelineNode(
            icon: Icons.inventory_2_outlined,
            isLast: !hasPipeline && !hasAttachments,
            content: Text(
              item.name,
              style: const TextStyle(
                color: SoftErpTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          
          if (hasPipeline || hasAttachments)
            _WorkflowTimelineNode(
              icon: Icons.route_outlined,
              isLast: !hasAttachments,
              content: Text(
                hasPipeline ? item.defaultPipelineName!.trim() : 'Unrouted',
                style: TextStyle(
                  color: hasPipeline ? SoftErpTheme.textPrimary : SoftErpTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: hasPipeline ? FontWeight.w600 : FontWeight.w400,
                  fontStyle: hasPipeline ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ),

          if (item.machines.isNotEmpty)
            _WorkflowTimelineNode(
              icon: Icons.precision_manufacturing_outlined,
              isLast: item.dies.isEmpty,
              content: _AttachmentList(
                items: item.machines.map((m) => m.name).toList(),
              ),
            ),

          if (item.dies.isNotEmpty)
            _WorkflowTimelineNode(
              icon: Icons.hexagon_outlined,
              isLast: true,
              content: _AttachmentList(
                items: item.dies.map((d) => d.toolCode).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _WorkflowTimelineNode extends StatelessWidget {
  const _WorkflowTimelineNode({
    required this.icon,
    required this.content,
    this.isLast = false,
  });

  final IconData icon;
  final Widget content;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Icon(icon, size: 18, color: SoftErpTheme.textSecondary),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: SoftErpTheme.borderStrong,
                      margin: const EdgeInsets.only(top: 8, bottom: 4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: content,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentList extends StatelessWidget {
  const _AttachmentList({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((name) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          name,
          style: const TextStyle(
            color: SoftErpTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      )).toList(),
    );
  }
}
