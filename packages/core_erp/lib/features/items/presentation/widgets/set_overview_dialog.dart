import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/app_flow_hooks.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../inventory/domain/inventory_set_definition.dart';
import '../../../inventory/presentation/widgets/inventory_set_editor_dialog.dart';
import '../../../production_pipelines/domain/pipeline_stage_node.dart';
import '../../domain/item_definition.dart';
import '../providers/items_provider.dart';
import '../screens/items_screen.dart';

/// What a set actually commits the floor to.
///
/// A set names items; the items name pipelines; the pipelines name machines and
/// dies. Nobody had drawn that chain, so "which presses does the Starter Pack
/// need" meant opening every member by hand. This rolls it up: each machine and
/// die appears once, however many members reach it.
///
/// Everything here is derived — nothing new is stored. It reads set lines ->
/// items -> `defaultPipelineId` -> that template's nodes.
class SetOverviewDialog extends StatefulWidget {
  const SetOverviewDialog({super.key, required this.set});

  final InventorySetDefinition set;

  static Future<void> open(
    BuildContext context, {
    required InventorySetDefinition set,
  }) {
    return showErpFormDialog<void>(
      context,
      maxWidth: 1180,
      maxHeight: 820,
      child: SetOverviewDialog(set: set),
    );
  }

  @override
  State<SetOverviewDialog> createState() => _SetOverviewDialogState();
}

class _SetOverviewDialogState extends State<SetOverviewDialog> {
  Map<String, List<PipelineStageNode>> _stageNodes =
      const <String, List<PipelineStageNode>>{};
  bool _loading = true;

  /// Which pipeline column is open. Null keeps the board at two columns.
  String? _selectedGroupKey;

  @override
  void initState() {
    super.initState();
    _loadStageNodes();
  }

  Future<void> _loadStageNodes() async {
    final nodes = await context.read<ItemsProvider>().fetchPipelineStageNodes();
    if (!mounted) return;
    setState(() {
      _stageNodes = nodes;
      _loading = false;
    });
  }

  /// One row per set line, resolved against the item master.
  List<_MemberView> _members(List<ItemDefinition> items) {
    return [
      for (final line in widget.set.lines)
        () {
          final item = items
              .where((candidate) => candidate.id == line.itemId)
              .firstOrNull;
          final pipelineId = item?.defaultPipelineId;
          final nodes = pipelineId == null
              ? const <PipelineStageNode>[]
              : (_stageNodes[pipelineId] ?? const <PipelineStageNode>[]);
          return _MemberView(line: line, item: item, nodes: nodes);
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final items = context.watch<ItemsProvider>().items;
    final members = _members(items);
    final groups = _pipelineGroups(members);
    final selected = groups
        .where((group) => group.key == _selectedGroupKey)
        .firstOrNull;

    final totalPieces = widget.set.lines.fold<int>(
      0,
      (sum, line) => sum + line.quantity,
    );
    final pipelineCount = groups.where((group) => group.id != null).length;

    return ErpFormScaffold(
      leading: _SetAvatar(photoUrl: widget.set.photoUrl?.trim() ?? ''),
      title: widget.set.name,
      subtitle:
          '${members.length} item${members.length == 1 ? '' : 's'} · '
          '$totalPieces piece${totalPieces == 1 ? '' : 's'} per set · '
          '$pipelineCount pipeline${pipelineCount == 1 ? '' : 's'}',
      onClose: () => Navigator.of(context).pop(),
      bodyScrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: _Board(
        members: members,
        groups: groups,
        selected: selected,
        loading: _loading,
        onSelectGroup: (key) => setState(
          () => _selectedGroupKey = _selectedGroupKey == key ? null : key,
        ),
        onEditMember: _editItem,
      ),
      footer: Row(
        children: [
          const Spacer(),
          AppButton(
            label: 'Close',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: 'Edit composition',
            icon: Icons.tune,
            onPressed: () => InventorySetEditorDialog.open(
              context,
              setDefinition: widget.set,
            ),
          ),
        ],
      ),
    );
  }

  /// Members gathered by the pipeline they run on. Members with none are kept
  /// together rather than hidden — their items still name machines and dies,
  /// and a set where nothing has a pipeline is exactly when you want to see
  /// that stated.
  List<_PipelineGroup> _pipelineGroups(List<_MemberView> members) {
    final byKey = <String, _PipelineGroup>{};
    for (final member in members) {
      final id = member.item?.defaultPipelineId?.trim();
      final name = member.item?.defaultPipelineName?.trim() ?? '';
      final key = (id == null || id.isEmpty) ? '__none__' : id;
      final group = byKey.putIfAbsent(
        key,
        () => _PipelineGroup(
          key: key,
          id: (id == null || id.isEmpty) ? null : id,
          name: name.isEmpty ? 'No pipeline' : name,
        ),
      );
      group.members.add(member);
      group.machines.addAll(member.machines);
      group.dies.addAll(member.dies);
    }
    final groups = byKey.values.toList();
    // Real pipelines first; the unassigned bucket sits last.
    groups.sort((a, b) {
      if ((a.id == null) != (b.id == null)) return a.id == null ? 1 : -1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return groups;
  }

  Future<void> _editItem(_MemberView member) async {
    final item = member.item;
    if (item == null) return;
    // Deliberately the ordinary single-item editor: a member is a normal item
    // that happens to be in a set, and editing it here must mean the same
    // thing as editing it anywhere else — its own pipeline included.
    await ItemsScreen.openEditor(
      context,
      item: item,
      onCreatePipeline: AppFlowHooks.createPipelineFor(context),
    );
  }
}

/// Members, then pipelines, then what a chosen pipeline runs on.
///
/// The columns drill down rather than sit side by side: machines and dies only
/// mean something once a pipeline is named, so they stay closed until one is.
class _Board extends StatelessWidget {
  const _Board({
    required this.members,
    required this.groups,
    required this.selected,
    required this.loading,
    required this.onSelectGroup,
    required this.onEditMember,
  });

  final List<_MemberView> members;
  final List<_PipelineGroup> groups;
  final _PipelineGroup? selected;
  final bool loading;
  final ValueChanged<String> onSelectGroup;
  final ValueChanged<_MemberView> onEditMember;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BoardColumn(
            icon: Icons.inventory_2_outlined,
            title: 'Members',
            count: members.length,
            caption: 'Each keeps its own pipeline',
            children: [
              for (final member in members)
                _MemberCard(
                  member: member,
                  onEdit: () => onEditMember(member),
                ),
            ],
          ),
          const _BoardArrow(),
          _BoardColumn(
            icon: Icons.account_tree_outlined,
            title: 'Pipelines',
            count: groups.where((group) => group.id != null).length,
            caption: 'Pick one to see what it runs on',
            children: [
              for (final group in groups)
                _PipelineCard(
                  group: group,
                  selected: identical(group, selected),
                  onTap: () => onSelectGroup(group.key),
                ),
            ],
          ),
          if (selected != null) ...[
            const _BoardArrow(),
            _BoardColumn(
              icon: Icons.precision_manufacturing_outlined,
              title: 'Machines',
              count: selected!.machines.length,
              caption: selected!.name,
              children: [
                if (loading)
                  const _ColumnHint('Loading pipeline nodes…')
                else if (selected!.machines.isEmpty)
                  const _ColumnHint('Nothing on this pipeline names a machine.')
                else
                  for (final machine in selected!.machines)
                    _ChipCard(
                      icon: Icons.precision_manufacturing_outlined,
                      label: machine,
                    ),
              ],
            ),
            const _BoardArrow(),
            _BoardColumn(
              icon: Icons.hexagon_outlined,
              title: 'Dies',
              count: selected!.dies.length,
              caption: selected!.name,
              children: [
                if (loading)
                  const _ColumnHint('Loading pipeline nodes…')
                else if (selected!.dies.isEmpty)
                  const _ColumnHint('No tooling on this pipeline.')
                else
                  for (final die in selected!.dies)
                    _ChipCard(icon: Icons.hexagon_outlined, label: die),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PipelineGroup {
  _PipelineGroup({required this.key, required this.id, required this.name});

  final String key;

  /// Null for the bucket holding members with no pipeline set.
  final String? id;
  final String name;
  final List<_MemberView> members = [];
  final Set<String> machines = <String>{};
  final Set<String> dies = <String>{};
}

class _MemberView {
  const _MemberView({
    required this.line,
    required this.item,
    required this.nodes,
  });

  final InventorySetLineDefinition line;
  final ItemDefinition? item;
  final List<PipelineStageNode> nodes;

  /// An item names its machines twice over: directly, through the links on the
  /// item master, and indirectly through the nodes of its pipeline. Both are
  /// real and neither is complete on its own, so the rollup takes the union.
  List<String> get machines => <String>{
    for (final link in item?.machines ?? const <ItemMachineLink>[])
      if (link.assetId.trim().isNotEmpty)
        '${link.assetId} · ${link.name}'
      else if (link.name.trim().isNotEmpty)
        link.name,
    for (final node in nodes)
      if (node.machineLabel.isNotEmpty) node.machineLabel,
  }.toList(growable: false);

  List<String> get dies => <String>{
    for (final link in item?.dies ?? const <ItemDieLink>[])
      if (link.toolCode.trim().isNotEmpty) link.toolCode,
    for (final node in nodes)
      if (node.dieCode.isNotEmpty) node.dieCode,
  }.toList(growable: false);
}

class _SetAvatar extends StatelessWidget {
  const _SetAvatar({required this.photoUrl});

  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: SoftErpTheme.accentSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: photoUrl.isEmpty
          ? const Icon(
              Icons.widgets_outlined,
              size: 20,
              color: SoftErpTheme.accentDeeper,
            )
          : Image.network(
              photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(
                Icons.widgets_outlined,
                size: 20,
                color: SoftErpTheme.accentDeeper,
              ),
            ),
    );
  }
}

class _BoardColumn extends StatelessWidget {
  const _BoardColumn({
    required this.icon,
    required this.title,
    required this.count,
    required this.caption,
    required this.children,
  });

  final IconData icon;
  final String title;
  final int count;
  final String caption;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 268,
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 15, color: SoftErpTheme.accentDeeper),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: SoftErpTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: SoftErpTheme.border),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: SoftErpTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: SoftErpTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Says the columns are a drill-down, not four independent lists.
class _BoardArrow extends StatelessWidget {
  const _BoardArrow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 6),
      child: Center(
        child: Icon(
          Icons.chevron_right,
          size: 18,
          color: SoftErpTheme.textSecondary,
        ),
      ),
    );
  }
}

class _ColumnHint extends StatelessWidget {
  const _ColumnHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          height: 1.35,
          fontStyle: FontStyle.italic,
          color: SoftErpTheme.textSecondary,
        ),
      ),
    );
  }
}

class _ChipCard extends StatelessWidget {
  const _ChipCard({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: SoftErpTheme.accentDeeper),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: SoftErpTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PipelineCard extends StatelessWidget {
  const _PipelineCard({
    required this.group,
    required this.selected,
    required this.onTap,
  });

  final _PipelineGroup group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unassigned = group.id == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? SoftErpTheme.accentSoft : Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? SoftErpTheme.accent : SoftErpTheme.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: unassigned
                          ? SoftErpTheme.textSecondary
                          : SoftErpTheme.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  selected ? Icons.expand_less : Icons.chevron_right,
                  size: 16,
                  color: SoftErpTheme.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Tag(
                  icon: Icons.inventory_2_outlined,
                  label: '${group.members.length} member'
                      '${group.members.length == 1 ? '' : 's'}',
                  muted: true,
                ),
                _Tag(
                  icon: Icons.precision_manufacturing_outlined,
                  label: '${group.machines.length}',
                  muted: group.machines.isEmpty,
                ),
                _Tag(
                  icon: Icons.hexagon_outlined,
                  label: '${group.dies.length}',
                  muted: group.dies.isEmpty,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member, required this.onEdit});

  final _MemberView member;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final line = member.line;
    final label = line.itemDisplayName.trim().isNotEmpty
        ? line.itemDisplayName
        : line.itemName;
    final variation = line.variationPathLabel.trim();
    final missing = member.item == null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: SoftErpTheme.sectionSurface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '×${line.quantity}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: missing
                        ? SoftErpTheme.textSecondary
                        : SoftErpTheme.textPrimary,
                  ),
                ),
              ),
              IconButton(
                onPressed: missing ? null : onEdit,
                icon: const Icon(Icons.edit_outlined, size: 15),
                tooltip: 'Edit item',
                visualDensity: VisualDensity.compact,
                color: SoftErpTheme.accentDeeper,
              ),
            ],
          ),
          if (variation.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                variation,
                style: const TextStyle(
                  fontSize: 11,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
            ),
          if (missing)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'This item is no longer in the master.',
                style: TextStyle(fontSize: 11, color: SoftErpTheme.dangerText),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label, this.muted = false});

  final IconData icon;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted
        ? SoftErpTheme.textSecondary
        : SoftErpTheme.accentDeeper;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: muted ? SoftErpTheme.sectionSurface : SoftErpTheme.accentSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
