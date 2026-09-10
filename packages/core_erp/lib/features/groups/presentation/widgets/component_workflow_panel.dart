import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/app_flow_hooks.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../items/data/services/item_link_options_service.dart';
import '../../../items/domain/item_definition.dart';
import '../../../items/domain/item_expression.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../../items/presentation/screens/items_screen.dart';
import '../../../items/presentation/widgets/item_expression_field.dart';
import '../../domain/group_definition.dart';

/// The component, drilled down: its items, each item's pipeline, and the
/// machines and dies that pipeline runs on.
///
/// A component does not own a pipeline — its items do, one each. So the board
/// reads left to right: pick an item, see what routes it, then see what that
/// route needs. Attaching a machine or a die here *is* the assignment; the
/// pipeline editor later offers the same set when filling in individual nodes.
///
/// Everything is addable in place, existing or new, because the person typing
/// a factory's books into this should never have to leave to make the next
/// thing they need.
class ComponentWorkflowPanel extends StatefulWidget {
  const ComponentWorkflowPanel({
    super.key,
    required this.component,
    this.onEditGroup,
  });

  final GroupDefinition component;

  /// Returns to the group form, which is step one of the same flow. When set,
  /// the stepper shows Group ahead of its own steps so the whole workflow
  /// reads as one thing rather than two.
  final VoidCallback? onEditGroup;

  @override
  State<ComponentWorkflowPanel> createState() => _ComponentWorkflowPanelState();
}

class _ComponentWorkflowPanelState extends State<ComponentWorkflowPanel> {
  final TextEditingController _itemQuery = TextEditingController();

  int? _selectedItemId;
  List<Map<String, String>> _pipelines = const [];
  List<ItemLinkOption> _machineOptions = const [];
  List<ItemLinkOption> _dieOptions = const [];
  bool _busy = false;

  void _onQueryChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _itemQuery.addListener(_onQueryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOptions());
  }

  @override
  void dispose() {
    _itemQuery.removeListener(_onQueryChanged);

    _itemQuery.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    if (!mounted) return;
    final items = context.read<ItemsProvider>();
    final pipelines = await items.fetchPipelineTemplates();
    List<ItemLinkOption> machines = const [];
    List<ItemLinkOption> dies = const [];
    try {
      final service = context.read<ItemLinkOptionsService>();
      machines = await service.fetchMachines();
      dies = await service.fetchDies();
    } catch (_) {
      // A lean embedding may not provide the service; those columns then offer
      // nothing to pick rather than failing the panel.
    }
    if (!mounted) return;
    setState(() {
      _pipelines = pipelines;
      _machineOptions = machines;
      _dieOptions = dies;
    });
  }

  List<ItemDefinition> get _members => context
      .watch<ItemsProvider>()
      .items
      .where((item) => item.groupId == widget.component.id && !item.isArchived)
      .toList(growable: false);

  ItemDefinition? get _selected {
    final members = _members;
    for (final item in members) {
      if (item.id == _selectedItemId) return item;
    }
    return null;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- items -----------------------------------------------------------

  /// Files an existing item into this component.
  ///
  /// Only selects it once the move actually succeeded — selecting regardless
  /// lit the Next button while the item never arrived, which read as the add
  /// having worked when it had not.
  Future<void> _addExistingItem(int itemId) async {
    final provider = context.read<ItemsProvider>();
    await _run(() async {
      final moved = await provider.reassignItemGroup(
        itemId,
        widget.component.id,
      );
      if (!mounted) return;
      if (moved == null) {
        final reason = provider.errorMessage ?? 'Could not add that item.';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(reason)));
        return;
      }
      setState(() {
        _selectedItemId = itemId;
        _itemQuery.clear();
      });
    });
  }

  Future<void> _createItem({String initialName = ''}) async {
    // The full item workflow, pre-filed into this component — so a new item
    // arrives already belonging here, with its pipeline reachable in the same
    // pass rather than as a second errand.
    final created = await ItemsScreen.openWorkflow(
      context,
      initialName: initialName,
      initialGroupId: widget.component.id,
      onCreatePipeline: AppFlowHooks.createPipelineFor(context),
    );
    if (created == null || !mounted) return;
    setState(() {
      _selectedItemId = created.id;
      _itemQuery.clear();
    });
  }

  // --- pipeline --------------------------------------------------------

  Future<void> _choosePipeline(ItemDefinition item, String pipelineId) async {
    final provider = context.read<ItemsProvider>();
    await _run(() async {
      final saved = await provider.setItemPipeline(item.id, pipelineId);
      if (!mounted) return;
      if (saved == null) {
        final reason = provider.errorMessage ?? 'Could not set the pipeline.';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(reason)));
        return;
      }
      setState(() {});
    });
  }

  Future<void> _clearPipeline(ItemDefinition item) async {
    final provider = context.read<ItemsProvider>();
    await _run(() async {
      final saved = await provider.setItemPipeline(item.id, null);
      if (!mounted) return;
      if (saved == null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                provider.errorMessage ?? 'Could not clear the pipeline.',
              ),
            ),
          );
      }
    });
  }

  Future<void> _createPipeline(ItemDefinition item) async {
    final create = AppFlowHooks.createPipelineFor(context);
    if (create == null) return;
    final id = await create();
    if (id == null || !mounted) return;
    await _run(() async {
      await context.read<ItemsProvider>().setItemPipeline(item.id, id);
      await _loadOptions();
      if (mounted) setState(() {});
    });
  }

  // --- machines and dies ------------------------------------------------

  Future<void> _detach(ItemDefinition item, String linkId, {required bool machines}) async {
    final attached = machines
        ? item.machines.map((m) => m.id).toList()
        : item.dies.map((d) => d.id).toList();
    if (!attached.contains(linkId)) return;
    attached.remove(linkId);

    await _run(
      () => context.read<ItemsProvider>().setItemLinks(
        item.id,
        machineIds: machines ? attached : null,
        dieIds: machines ? null : attached,
      ),
    );
  }

  Future<void> _promptDetachOrDelete({
    required ItemDefinition item,
    required String id,
    required String name,
    required bool machines,
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${machines ? "Machine" : "Die"}'),
        content: Text(
          'Do you want to just detach $name from this component, or permanently delete it from the system?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('detach'),
            child: const Text('Just Detach'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop('delete'),
            style: ElevatedButton.styleFrom(
              backgroundColor: SoftErpTheme.dangerText,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (result == 'detach') {
      await _detach(item, id, machines: machines);
    } else if (result == 'delete') {
      final deleteFn = machines
          ? AppFlowHooks.deleteMachineFor(context)
          : AppFlowHooks.deleteDieFor(context);
      if (deleteFn != null) {
        await _run(() => deleteFn(id));
        await _detach(item, id, machines: machines);
      } else {
        await _detach(item, id, machines: machines);
      }
    }
  }

  Future<void> _addLink(
    ItemDefinition item,
    String linkId, {
    required bool machines,
  }) async {
    final attached = machines
        ? item.machines.map((machine) => machine.id).toList()
        : item.dies.map((die) => die.id).toList();
    if (attached.contains(linkId)) return;
    
    await _run(
      () => context.read<ItemsProvider>().setItemLinks(
        item.id,
        machineIds: machines ? <String>[...attached, linkId] : null,
        dieIds: machines ? null : <String>[...attached, linkId],
      ),
    );
    if (mounted) {
      // The searchable dropdown automatically clears its query, we just rebuild.
      setState(() {});
    }
  }

  Future<void> _createLinked({required bool machines}) async {
    final create = machines
        ? AppFlowHooks.createMachineFor(context)
        : AppFlowHooks.createDieFor(context);
    if (create == null) return;
    final made = await create();
    if (!made || !mounted) return;
    // The new one is not attached yet — reload so it can be picked.
    await _loadOptions();
  }

  @override
  Widget build(BuildContext context) {
    final members = _members;
    final selected = _selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onEditGroup != null) ...[
          _AddAction(
            icon: Icons.chevron_left,
            label: 'Back to Group Details',
            onTap: widget.onEditGroup!,
          ),
          const SizedBox(height: 16),
        ],
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column: Items
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Component Items',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: SoftErpTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'What this component is made of.',
                      style: TextStyle(
                        fontSize: 13,
                        color: SoftErpTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.only(right: 12),
                        children: _itemsStep(members),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                color: SoftErpTheme.border,
                margin: const EdgeInsets.symmetric(horizontal: 16),
              ),
              // Right Column: Configuration
              Expanded(
                flex: 7,
                child: selected == null
                    ? const Center(
                        child: Text(
                          'Pick an item on the left to configure it.',
                          style: TextStyle(color: SoftErpTheme.textSecondary),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Configuring ${selected.displayName.trim().isEmpty ? selected.name : selected.displayName}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: SoftErpTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.only(right: 12),
                              children: [
                                const Text(
                                  'Pipeline',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: SoftErpTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ..._pipelineStep(selected),
                                const SizedBox(height: 24),
                                const Text(
                                  'Machines',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: SoftErpTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ..._linksStep(selected, machines: true),
                                const SizedBox(height: 24),
                                const Text(
                                  'Dies',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: SoftErpTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ..._linksStep(selected, machines: false),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _itemsStep(List<ItemDefinition> members) {
    final query = _itemQuery.text.trim();
    final lower = query.toLowerCase();
    final candidates = context
        .watch<ItemsProvider>()
        .items
        .where(
          (item) => item.groupId != widget.component.id && !item.isArchived,
        )
        // Only once something is typed: an empty field listing the whole
        // catalogue is noise, not help.
        .where(
          (item) =>
              lower.isNotEmpty &&
              '${item.name} ${item.alias} ${item.displayName}'
                  .toLowerCase()
                  .contains(lower),
        )
        .take(6)
        .toList(growable: false);

    final exactExists = context.watch<ItemsProvider>().items.any(
      (item) => item.displayName.trim().toLowerCase() == lower,
    );
    // `+` means the expression language, the same as everywhere else it is
    // offered — so the field is one way in, not two.
    final isExpression = query.contains(ItemExpression.separator);

    return [
      for (final item in members) ...[
        _ItemCard(
          item: item,
          selected: item.id == _selectedItemId,
          onTap: () => setState(() => _selectedItemId = item.id),
        ),
        const SizedBox(height: 6),
      ],
      const SizedBox(height: 2),
      TextField(
        controller: _itemQuery,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 17),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 34,
          ),
          hintText: 'Search items, or type a new name — use + to add values',
          hintStyle: const TextStyle(fontSize: 12),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: SoftErpTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: SoftErpTheme.border),
          ),
        ),
      ),
      const SizedBox(height: 8),
      if (isExpression)
        ItemExpressionField(
          text: _itemQuery.text,
          onTextChanged: (next) => _itemQuery.text = next,
        )
      else ...[
        for (final item in candidates) ...[
          _PickRow(
            icon: Icons.inventory_2_outlined,
            label: item.displayName.trim().isEmpty
                ? item.name
                : item.displayName,
            detail: 'Add to this component',
            onTap: () => _addExistingItem(item.id),
          ),
          const SizedBox(height: 4),
        ],
        if (query.isNotEmpty && !exactExists)
          _PickRow(
            icon: Icons.add_circle_outline,
            label: 'Create item "$query"',
            detail: 'Opens the item workflow, filed here',
            onTap: () => _createItem(initialName: query),
          )
        else if (query.isEmpty)
          const _Hint('Search for an item, or type a name to create one.')
        else if (candidates.isEmpty && query.isNotEmpty)
          const _Hint('Nothing else matches.'),
      ],
    ];
  }

  List<Widget> _pipelineStep(ItemDefinition? selected) {
    if (selected == null) return const [_Hint('Pick an item first.')];
    
    return [
      SearchableSelectField<String>(
        value: selected.defaultPipelineId,
        onChanged: (val) {
          if (val != null && val.isNotEmpty) {
            _choosePipeline(selected, val);
          } else {
            _clearPipeline(selected);
          }
        },
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search pipelines, or create one',
          hintStyle: const TextStyle(fontSize: 12),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: SoftErpTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: SoftErpTheme.border),
          ),
        ),
        searchHintText: 'Search pipelines...',
        emptyText: 'No pipelines match.',
        options: _pipelines
            .map((p) => SearchableSelectOption<String>(
                  value: p['id'] ?? '',
                  label: p['name'] ?? 'Untitled',
                ))
            .toList(growable: false),
        canCreateOption: AppFlowHooks.canCreatePipeline ? (query, _) => true : null,
        createOptionLabelBuilder: (query) => 'New pipeline',
        onCreateOption: AppFlowHooks.canCreatePipeline
            ? (query) async {
                await _createPipeline(selected);
                return null;
              }
            : null,
      ),
    ];
  }

  List<Widget> _linksStep(ItemDefinition? selected, {required bool machines}) {
    if (selected == null) return const [_Hint('Pick an item first.')];
    final canCreate = machines
        ? AppFlowHooks.createMachine != null
        : AppFlowHooks.createDie != null;
    
    final attachedIds = machines
        ? selected.machines.map((m) => m.id).toSet()
        : selected.dies.map((d) => d.id).toSet();

    final attached = machines
        ? [
            for (final machine in selected.machines)
              _MachineCard(
                machine: machine,
                onRemove: () => _promptDetachOrDelete(
                  item: selected,
                  id: machine.id,
                  name: machine.name,
                  machines: true,
                ),
              ),
          ]
        : [
            for (final die in selected.dies)
              _DieCard(
                die: die,
                onRemove: () => _promptDetachOrDelete(
                  item: selected,
                  id: die.id,
                  name: die.toolCode.trim().isNotEmpty ? die.toolCode : 'Die',
                  machines: false,
                ),
              ),
          ];

    final options = machines ? _machineOptions : _dieOptions;

    return [
      if (attached.isEmpty)
        const _Hint('Nothing attached yet.')
      else
        for (final chip in attached) ...[chip, const SizedBox(height: 6)],
      const SizedBox(height: 4),
      SearchableSelectField<String>(
        value: null,
        onChanged: (val) {
          if (val != null) {
            _addLink(selected, val, machines: machines);
          }
        },
        decoration: InputDecoration(
          isDense: true,
          hintText: attached.isEmpty
              ? (machines ? 'Search machines, or create one' : 'Search dies, or create one')
              : (machines ? 'Search to add another machine' : 'Search to add another die'),
          hintStyle: const TextStyle(fontSize: 12),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: SoftErpTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: SoftErpTheme.border),
          ),
        ),
        searchHintText: machines ? 'Search machines...' : 'Search dies...',
        emptyText: machines ? 'No machines available.' : 'No dies available.',
        options: options
            .where((opt) => !attachedIds.contains(opt.id))
            .map((opt) => SearchableSelectOption<String>(
                  value: opt.id,
                  label: opt.subtitle.isNotEmpty ? '${opt.label} · ${opt.subtitle}' : opt.label,
                ))
            .toList(growable: false),
        canCreateOption: canCreate ? (query, _) => true : null,
        createOptionLabelBuilder: (query) => machines ? 'New machine' : 'New die',
        onCreateOption: canCreate
            ? (query) async {
                await _createLinked(machines: machines);
                return null;
              }
            : null,
      ),
    ];
  }
}


/// A row you can pick from, rendered inline under the field rather than in a
/// dialog of its own — a picker that opens somewhere else loses the row you
/// were filling in.
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(9),
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
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              detail,
              style: const TextStyle(
                fontSize: 10.5,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        height: 1.35,
        fontStyle: FontStyle.italic,
        color: SoftErpTheme.textSecondary,
      ),
    ),
  );
}

class _AddAction extends StatelessWidget {
  const _AddAction({
    required this.label,
    required this.onTap,
    this.icon = Icons.add,
  });

  final String label;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: SoftErpTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: SoftErpTheme.accentDeeper),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: SoftErpTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.onRemove});

  final IconData icon;
  final String label;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(10, 8, onRemove == null ? 10 : 4, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: SoftErpTheme.accentDeeper),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: SoftErpTheme.textPrimary,
              ),
            ),
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 13),
              tooltip: 'Detach',
              visualDensity: VisualDensity.compact,
              color: SoftErpTheme.textSecondary,
            ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ItemDefinition item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final routed = (item.defaultPipelineName ?? '').trim().isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? SoftErpTheme.accentSoft : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? SoftErpTheme.accent : SoftErpTheme.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.displayName.trim().isEmpty ? item.name : item.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: SoftErpTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              routed
                  ? '${item.defaultPipelineName} · '
                        '${item.machines.length}M ${item.dies.length}D'
                  : 'No pipeline',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                color: routed
                    ? SoftErpTheme.textSecondary
                    : SoftErpTheme.warningText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MachineCard extends StatelessWidget {
  const _MachineCard({
    required this.machine,
    required this.onRemove,
  });

  final ItemMachineLink machine;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        children: [
          if (machine.photoUrl != null && machine.photoUrl!.isNotEmpty)
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                image: DecorationImage(
                  image: NetworkImage(machine.photoUrl!),
                  fit: BoxFit.cover,
                ),
              ),
            )
          else
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.precision_manufacturing_outlined,
                size: 16,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  machine.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
                if (machine.assetId.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    machine.assetId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: SoftErpTheme.textSecondary,
            onPressed: onRemove,
            splashRadius: 20,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
          ),
        ],
      ),
    );
  }
}

class _DieCard extends StatelessWidget {
  const _DieCard({
    required this.die,
    required this.onRemove,
  });

  final ItemDieLink die;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        children: [
          if (die.photoUrl != null && die.photoUrl!.isNotEmpty)
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                image: DecorationImage(
                  image: NetworkImage(die.photoUrl!),
                  fit: BoxFit.cover,
                ),
              ),
            )
          else
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.hexagon_outlined,
                size: 16,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  die.toolCode,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: SoftErpTheme.textSecondary,
            onPressed: onRemove,
            splashRadius: 20,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
          ),
        ],
      ),
    );
  }
}
