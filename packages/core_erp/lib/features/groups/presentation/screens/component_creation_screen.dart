import '../../../../core/app_flow_hooks.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../items/domain/item_definition.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../../items/presentation/screens/items_screen.dart';
import '../../../units/presentation/providers/units_provider.dart';
import '../../domain/group_definition.dart';
import '../../domain/group_inputs.dart';
import '../providers/groups_provider.dart';
import 'creation_wizard_kinds.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Builds the item editor for the middle tile, filing into [groupId] when
/// there is one. [onClosed] gets the saved item, or null when the editor was
/// closed without one.
typedef ComponentItemEditorBuilder =
    Widget Function(
      BuildContext context, {
      required int? groupId,
      required ValueChanged<ItemDefinition?> onClosed,
    });

/// Component creation, onboarding shape: three bento tiles for someone who
/// arrives with a spreadsheet's worth of data and wants it in fast.
///
/// Left picks the form (Item / Die / Machine), middle hosts the full editor
/// for it — the same item workflow, die editor and machine editor as their own
/// masters — and the right views the component's items: photo, code, unit,
/// variation tree, and a chevron that opens its dies and machines with a way to
/// add one more. After every save the editor comes back empty for the next.
class ComponentCreationWorkspace extends StatefulWidget {
  const ComponentCreationWorkspace({
    super.key,
    this.component,
    this.onComponentChanged,
    this.itemEditorBuilder,
    this.itemsOnly = false,
  });

  /// The component to add to. Null starts by naming a new one, unless
  /// [itemsOnly].
  final GroupDefinition? component;

  /// The item master's Add Item: no component to name, the item editor picks
  /// its own group, and the last column lists what was added in this window.
  final bool itemsOnly;

  /// Fires once a new component has been named and saved.
  final ValueChanged<GroupDefinition>? onComponentChanged;

  /// Replaces the item workflow window; tests use it to stay light.
  final ComponentItemEditorBuilder? itemEditorBuilder;

  @override
  State<ComponentCreationWorkspace> createState() =>
      _ComponentCreationWorkspaceState();
}

/// The workspace in a dialog over the item master.
class ComponentCreationDialog extends StatefulWidget {
  const ComponentCreationDialog({
    super.key,
    this.component,
    this.itemEditorBuilder,
    this.itemsOnly = false,
  });

  final GroupDefinition? component;

  /// See [ComponentCreationWorkspace.itemsOnly].
  final bool itemsOnly;

  /// Passed through to the workspace; tests use it to stay light.
  final ComponentItemEditorBuilder? itemEditorBuilder;

  static Future<void> open(BuildContext context, {GroupDefinition? component}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ComponentCreationDialog(component: component),
    );
  }

  /// The item master's Add Item: the same window, without a component.
  static Future<void> openForItems(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ComponentCreationDialog(itemsOnly: true),
    );
  }

  @override
  State<ComponentCreationDialog> createState() =>
      _ComponentCreationDialogState();
}

class _ComponentCreationDialogState extends State<ComponentCreationDialog> {
  late GroupDefinition? _component = widget.component;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      backgroundColor: SoftErpTheme.shellSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusXl),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        // Wide enough for the full item, die and machine editors to sit in
        // the middle tile, but still a window over the item master.
        constraints: BoxConstraints(
          maxWidth: size.width - 56 >= 1800 ? 1760 : size.width - 56,
          maxHeight: size.height - 56,
        ),
        child: Column(
          children: [
            _Header(
              title: widget.itemsOnly ? 'Item creation' : 'Component creation',
              componentName: _component?.name,
              onClose: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ComponentCreationWorkspace(
                  component: widget.component,
                  itemEditorBuilder: widget.itemEditorBuilder,
                  itemsOnly: widget.itemsOnly,
                  onComponentChanged: (component) =>
                      setState(() => _component = component),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

CreationKindSpec get _dieKind => CreationKinds.byKey(CreationKinds.die);
CreationKindSpec get _machineKind => CreationKinds.byKey(CreationKinds.machine);

bool _isAssetKey(String key) =>
    key == CreationKinds.die || key == CreationKinds.machine;

class _ComponentCreationWorkspaceState
    extends State<ComponentCreationWorkspace> {
  GroupDefinition? _component;

  /// The first column, in order. Its top tile is what the last column shows.
  /// Starts as Item / Die / Machine; tiles can be removed, dragged, and added
  /// from the + menu. Lives as long as the window.
  final List<String> _lineup = [...CreationKinds.defaults];
  String _activeKey = CreationKinds.item;

  /// Everything the middle column saved in this window, newest first.
  final Map<String, List<CreatedRecord>> _added = {};

  /// Drives the item editor's steps from the Item tile's sub-tabs.
  final ItemWorkflowController _itemWorkflow = ItemWorkflowController();
  bool _itemStepsOpen = true;
  String? _flashRecordKey;

  /// The item a die or machine editor is adding to, chosen with the + buttons
  /// under that item's chevron.
  int? _targetItemId;
  final Set<int> _expandedIds = {};
  int? _flashId;
  bool _busy = false;

  /// Items saved in this window; what the last column lists in [itemsOnly].
  final Set<int> _addedItemIds = {};

  /// Bumped after every save or cancel so the editor remounts empty.
  int _editorGeneration = 0;

  /// The item editor's own generation. It stays mounted (offstage) while
  /// another tile is open, so what was typed survives a trip to the die
  /// editor; only a finished item gives it a fresh form.
  int _itemEditorGeneration = 0;

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _component = widget.component;
    _nameController.addListener(() => setState(() {}));
    _searchController.addListener(() => setState(() {}));
    _itemWorkflow.addListener(_onItemWorkflowChanged);
    Future<void>.microtask(() {
      if (!mounted) return;
      context.read<UnitsProvider>().initialize();
      context.read<ItemsProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    _itemWorkflow
      ..removeListener(_onItemWorkflowChanged)
      ..dispose();
    super.dispose();
  }

  void _onItemWorkflowChanged() {
    if (mounted) setState(() {});
  }

  bool get _naming => !widget.itemsOnly && _component == null;

  CreationKindSpec get _active => CreationKinds.byKey(_activeKey);

  List<ItemDefinition> _componentItems(List<ItemDefinition> all) {
    final component = _component;
    if (component == null && !widget.itemsOnly) return const [];
    return all
        .where(
          (item) =>
              !item.isArchived &&
              (component == null
                  ? _addedItemIds.contains(item.id) ||
                        item.id == _itemWorkflow.savedItemId
                  : item.groupId == component.id),
        )
        .toList()
      ..sort((a, b) => b.id.compareTo(a.id));
  }

  /// Dies and machines count what the items carry plus what was added here
  /// without an item; everything else counts what was added here.
  int _countOf(String key, List<ItemDefinition> items) {
    final added = {for (final record in _added[key] ?? const []) record.id};
    return switch (key) {
      CreationKinds.item => items.length,
      CreationKinds.die => {
        ...added,
        for (final item in items) ...item.dies.map((die) => die.id),
      }.length,
      CreationKinds.machine => {
        ...added,
        for (final item in items) ...item.machines.map((machine) => machine.id),
      }.length,
      _ => added.length,
    };
  }

  /// From the right column: switches the editor, keeping the target item when
  /// moving between die and machine.
  void _selectKind(String key) {
    if (key == _activeKey || _naming) return;
    setState(() {
      _activeKey = key;
      if (!_isAssetKey(key)) _targetItemId = null;
      _editorGeneration++;
    });
  }

  /// A sub-tab under Item, from wherever the wizard is: brings the item
  /// editor back and opens that page.
  void _openItemStep(int index) {
    if (_activeKey != CreationKinds.item) _selectKind(CreationKinds.item);
    _itemWorkflow.open(index);
  }

  /// The + menu: puts another master's editor in the lineup and opens it.
  void _addKind(String key) {
    if (_lineup.contains(key)) return;
    setState(() {
      _lineup.add(key);
      _activeKey = key;
      _targetItemId = null;
      _editorGeneration++;
    });
  }

  /// A tile's ×. The lineup never goes empty.
  void _removeKind(String key) {
    if (_lineup.length <= 1) return;
    setState(() {
      _lineup.remove(key);
      if (_activeKey == key) {
        _activeKey = _lineup.first;
        _targetItemId = null;
        _editorGeneration++;
      }
    });
  }

  void _reorderKinds(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      _lineup.insert(newIndex, _lineup.removeAt(oldIndex));
    });
  }

  /// From an item's + Die / + Machine: opens that editor, aimed at the item.
  void _addUnder(int itemId, String key) {
    setState(() {
      _activeKey = key;
      _targetItemId = itemId;
      _expandedIds.add(itemId);
      _editorGeneration++;
    });
  }

  void _toggleExpanded(int itemId) {
    setState(() {
      if (!_expandedIds.remove(itemId)) _expandedIds.add(itemId);
    });
  }

  void _toast(String message) =>
      showAppToast(context, message, kind: AppToastKind.error);

  Future<void> _createComponent() async {
    if (_busy || _nameController.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final groups = context.read<GroupsProvider>();
    try {
      final created = await groups.createGroup(
        CreateGroupInput(
          name: _nameController.text.trim(),
          groupType: 'item',
          groupStructure: 'component',
          description: _descriptionController.text.trim(),
        ),
      );
      if (!mounted) return;
      if (created == null || groups.errorMessage != null) {
        _toast(groups.errorMessage ?? 'Could not create the component.');
        return;
      }
      setState(() {
        _component = created;
        _activeKey = _lineup.first;
      });
      widget.onComponentChanged?.call(created);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onItemClosed(ItemDefinition? saved) {
    setState(() {
      if (saved != null) {
        _flashId = saved.id;
        _addedItemIds.add(saved.id);
      }
      _itemEditorGeneration++;
    });
  }

  /// The middle column saved a record: list it on the right straight away, and
  /// for a die or machine aimed at an item, attach it there too.
  void _onRecordSaved(String key, CreatedRecord record) {
    setState(() {
      (_added[key] ??= []).insert(0, record);
      _flashRecordKey = '$key:${record.id}';
      _editorGeneration++;
    });
    if (_isAssetKey(key)) _linkToTarget(key, record.id);
  }

  /// Attaches a saved die or machine to the target item, keeping whatever the
  /// item already carries.
  Future<void> _linkToTarget(String key, String id) async {
    final kind = CreationKinds.byKey(key);
    final items = context.read<ItemsProvider>();
    final target = items.items
        .where((item) => item.id == _targetItemId)
        .firstOrNull;
    if (target == null) return;
    final saved = key == CreationKinds.die
        ? await items.setItemLinks(
            target.id,
            dieIds: [...target.dies.map((die) => die.id), id],
          )
        : await items.setItemLinks(
            target.id,
            machineIds: [...target.machines.map((machine) => machine.id), id],
          );
    if (!mounted || saved != null) return;
    _toast(
      'The ${kind.label.toLowerCase()} was saved, but could not be added '
      'to ${target.name}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _componentItems(context.watch<ItemsProvider>().items);
    final units = context.watch<UnitsProvider>().activeUnits;
    final unitSymbols = {for (final unit in units) unit.id: unit.symbol};

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 250, child: _BentoTile(child: _buildKindColumn(items))),
        const SizedBox(width: 14),
        Expanded(child: _BentoTile(child: _buildMiddle(items))),
        const SizedBox(width: 14),
        SizedBox(
          width: 380,
          child: _BentoTile(
            // Whatever the top tile is, viewed: the first column picks, the
            // last one shows what picking it has produced.
            child: _lineup.first == CreationKinds.item
                ? _buildItemsColumn(items, unitSymbols)
                : _buildRecordsColumn(CreationKinds.byKey(_lineup.first)),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Right — view the component's items
  // -------------------------------------------------------------------------

  Widget _buildItemsColumn(
    List<ItemDefinition> items,
    Map<int, String> unitSymbols,
  ) {
    final liveDraft = _itemWorkflow.draft;
    // Only until it is saved; then it is one of [items].
    final draft = liveDraft != null && !liveDraft.saved ? liveDraft : null;
    final query = _searchController.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? items
        : items
              .where(
                (item) =>
                    item.name.toLowerCase().contains(query) ||
                    item.alias.toLowerCase().contains(query) ||
                    item.shortCode.toLowerCase().contains(query),
              )
              .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
          child: Row(
            children: [
              const Text(
                'Items',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              _CountBadge(count: items.length),
            ],
          ),
        ),
        if (items.length > 4)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 14.5),
              decoration: _inputDecoration(
                'Search name or code',
              ).copyWith(prefixIcon: const Icon(Icons.search, size: 20)),
            ),
          ),
        Expanded(
          child: items.isEmpty && draft == null
              ? _EmptyReference(
                  text: _naming
                      ? 'Name the component, then its items show up here.'
                      : 'Items you add show up here.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: visible.length + (draft == null ? 0 : 1),
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    // The item being typed, live, ahead of the saved ones.
                    if (draft != null) {
                      if (index == 0) return _DraftItemCard(draft: draft);
                      index -= 1;
                    }
                    final item = visible[index];
                    return _ItemViewCard(
                      item: item,
                      unitSymbol: unitSymbols[item.unitId] ?? '',
                      expanded: _expandedIds.contains(item.id),
                      targeted:
                          _isAssetKey(_activeKey) && item.id == _targetItemId,
                      flash: item.id == _flashId,
                      onToggle: () => _toggleExpanded(item.id),
                      onAddDie: _lineup.contains(CreationKinds.die)
                          ? () => _addUnder(item.id, CreationKinds.die)
                          : null,
                      onAddMachine: _lineup.contains(CreationKinds.machine)
                          ? () => _addUnder(item.id, CreationKinds.machine)
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Middle — the editor
  // -------------------------------------------------------------------------

  Widget _buildMiddle(List<ItemDefinition> items) {
    if (_naming) return _buildComponentForm();
    final itemActive = _activeKey == CreationKinds.item;
    return Stack(
      children: [
        if (_lineup.contains(CreationKinds.item))
          Positioned.fill(
            child: Offstage(
              offstage: !itemActive,
              child: TickerMode(enabled: itemActive, child: _buildItemEditor()),
            ),
          ),
        if (!itemActive) Positioned.fill(child: _buildRecordEditor(items)),
      ],
    );
  }

  Widget _buildItemEditor() {
    final groupId = _component?.id;
    final builder = widget.itemEditorBuilder;
    return KeyedSubtree(
      key: ValueKey('item-editor-$_itemEditorGeneration'),
      child: builder != null
          ? builder(context, groupId: groupId, onClosed: _onItemClosed)
          : ItemsScreen.workflowPanel(
              initialGroupId: groupId,
              onCreatePipeline: AppFlowHooks.createPipelineFor(context),
              onClosed: _onItemClosed,
              controller: _itemWorkflow,
            ),
    );
  }

  Widget _buildRecordEditor(List<ItemDefinition> items) {
    final editorKey = ValueKey('$_activeKey-editor-$_editorGeneration');
    final kind = _active;
    final builder = kind.editor?.call();
    final target = items.where((item) => item.id == _targetItemId).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isAssetKey(kind.key) && target != null) ...[
          _TargetBar(
            kind: kind,
            item: target,
            onClear: () => setState(() => _targetItemId = null),
          ),
          const Divider(height: 1, color: SoftErpTheme.border),
        ],
        Expanded(
          child: builder == null
              ? Center(
                  child: Text(
                    '${kind.label}s can only be created inside the app.',
                    style: const TextStyle(
                      fontSize: 15,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                )
              : KeyedSubtree(
                  key: editorKey,
                  child: SubmitFormShortcuts(
                    child: builder(
                      context,
                      onSaved: (record) => _onRecordSaved(kind.key, record),
                      onCancel: () => setState(() => _editorGeneration++),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildComponentForm() {
    final canCreate = !_busy && _nameController.text.trim().isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: 26,
                    color: SoftErpTheme.accent,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Name the component',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: SoftErpTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Its items, dies and machines are added next.',
                style: TextStyle(
                  fontSize: 15,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              const _FieldLabel('Component name'),
              TextField(
                key: const ValueKey('creation_name_field'),
                controller: _nameController,
                autofocus: true,
                style: const TextStyle(fontSize: 16),
                textInputAction: TextInputAction.next,
                decoration: _inputDecoration('e.g. Cone Assembly'),
              ),
              const SizedBox(height: 16),
              const _FieldLabel('Description'),
              TextField(
                controller: _descriptionController,
                style: const TextStyle(fontSize: 16),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _createComponent(),
                decoration: _inputDecoration('Optional'),
              ),
              const SizedBox(height: 28),
              Align(
                alignment: Alignment.centerRight,
                child: AppButton(
                  label: 'Create component',
                  icon: Icons.arrow_forward,
                  isLoading: _busy,
                  onPressed: canCreate ? _createComponent : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Left — which editor
  // -------------------------------------------------------------------------

  Widget _buildKindColumn(List<ItemDefinition> items) {
    final addable = CreationKinds.catalog
        .where((spec) => !_lineup.contains(spec.key))
        .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: _lineup.length,
              onReorder: _reorderKinds,
              itemBuilder: (context, index) {
                final key = _lineup[index];
                // The item editor's own steps, as sub-tabs under Item.
                final steps = key == CreationKinds.item
                    ? _itemWorkflow.steps
                    : const <String>[];
                return Padding(
                  key: ValueKey('creation_tile_$key'),
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _KindButton(
                        kind: CreationKinds.byKey(key),
                        index: index,
                        count: _countOf(key, items),
                        selected: !_naming && key == _activeKey,
                        onTap: _naming ? null : () => _selectKind(key),
                        onRemove: _lineup.length > 1
                            ? () => _removeKind(key)
                            : null,
                        expanded: steps.isEmpty ? null : _itemStepsOpen,
                        onToggleExpanded: () =>
                            setState(() => _itemStepsOpen = !_itemStepsOpen),
                      ),
                      if (steps.isNotEmpty && _itemStepsOpen)
                        for (var i = 0; i < steps.length; i++)
                          _StepTab(
                            key: ValueKey('creation_step_${steps[i]}'),
                            label: steps[i],
                            active:
                                _activeKey == CreationKinds.item &&
                                i == _itemWorkflow.activeIndex,
                            onTap: _itemWorkflow.canOpen(i)
                                ? () => _openItemStep(i)
                                : null,
                          ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (_naming)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Name the component first.',
                style: TextStyle(
                  fontSize: 14,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
            ),
          if (addable.isNotEmpty)
            _AddKindButton(
              options: addable,
              enabled: !_naming,
              onPick: _addKind,
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Right, when the first tile is not Item — what this window added of it
  // -------------------------------------------------------------------------

  Widget _buildRecordsColumn(CreationKindSpec kind) {
    final records = _added[kind.key] ?? const <CreatedRecord>[];
    final query = _searchController.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? records
        : records
              .where(
                (record) =>
                    record.title.toLowerCase().contains(query) ||
                    (record.subtitle ?? '').toLowerCase().contains(query),
              )
              .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
          child: Row(
            children: [
              Icon(kind.icon, size: 22, color: SoftErpTheme.textSecondary),
              const SizedBox(width: 8),
              Text(
                kind.pluralLabel,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              _CountBadge(count: records.length),
            ],
          ),
        ),
        if (records.length > 4)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 14.5),
              decoration: _inputDecoration(
                'Search',
              ).copyWith(prefixIcon: const Icon(Icons.search, size: 20)),
            ),
          ),
        Expanded(
          child: records.isEmpty
              ? _EmptyReference(
                  text: '${kind.pluralLabel} you add show up here.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final record = visible[index];
                    return _RecordCard(
                      key: ValueKey('creation_record_${kind.key}_${record.id}'),
                      kind: kind,
                      record: record,
                      flash: _flashRecordKey == '${kind.key}:${record.id}',
                    );
                  },
                ),
        ),
      ],
    );
  }
}

InputDecoration _inputDecoration(String hint) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
    borderSide: const BorderSide(color: SoftErpTheme.border),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 15),
    filled: true,
    fillColor: Colors.white,
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: SoftErpTheme.accent, width: 1.4),
    ),
  );
}

/// One rounded cell of the bento grid.
class _BentoTile extends StatelessWidget {
  const _BentoTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusLg),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusLg),
        child: child,
      ),
    );
  }
}

/// "Component creation" with the component's name beside it, large and in
/// capitals, once it has one.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.componentName,
    required this.onClose,
  });

  final String title;
  final String? componentName;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final name = componentName?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 16, 14, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: SoftErpTheme.textSecondary,
            ),
          ),
          if (name.isNotEmpty) ...[
            const SizedBox(width: 16),
            Container(width: 2, height: 30, color: SoftErpTheme.border),
            const SizedBox(width: 16),
            Flexible(
              child: Text(
                name.toUpperCase(),
                key: const ValueKey('creation_component_title'),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
            ),
          ],
          const Spacer(),
          IconButton(
            tooltip: 'Close',
            iconSize: 26,
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// Which item the die or machine editor below is adding to.
class _TargetBar extends StatelessWidget {
  const _TargetBar({
    required this.kind,
    required this.item,
    required this.onClear,
  });

  final CreationKindSpec kind;
  final ItemDefinition? item;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final target = item!;
    return Container(
      color: SoftErpTheme.accentSurface,
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              key: const ValueKey('creation_target_bar'),
              TextSpan(
                children: [
                  const TextSpan(text: 'For '),
                  TextSpan(
                    text: target.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                color: SoftErpTheme.textPrimary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Not for this item',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            onPressed: onClear,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: SoftErpTheme.shellSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: SoftErpTheme.textSecondary),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: SoftErpTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: SoftErpTheme.textSecondary,
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: SoftErpTheme.accentSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
          color: SoftErpTheme.accentDeeper,
        ),
      ),
    );
  }
}

class _KindButton extends StatefulWidget {
  const _KindButton({
    required this.kind,
    required this.index,
    required this.count,
    required this.selected,
    required this.onTap,
    required this.onRemove,
    this.expanded,
    this.onToggleExpanded,
  });

  final CreationKindSpec kind;

  /// Position in the lineup; 0 is the one the last column shows.
  final int index;
  final int count;
  final bool selected;
  final VoidCallback? onTap;

  /// Null when this is the last tile left.
  final VoidCallback? onRemove;

  /// Non-null when the tile has sub-tabs: whether they are showing.
  final bool? expanded;
  final VoidCallback? onToggleExpanded;

  @override
  State<_KindButton> createState() => _KindButtonState();
}

/// Icon, name, and a count once there is one. The drag handle and × stay
/// out of sight until the pointer is over the tile.
class _KindButtonState extends State<_KindButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final selected = widget.selected;
    final foreground = selected
        ? Colors.white
        : widget.onTap != null
        ? SoftErpTheme.textPrimary
        : SoftErpTheme.textSecondary;
    final muted = selected ? Colors.white70 : SoftErpTheme.textSecondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: selected ? SoftErpTheme.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        child: InkWell(
          key: ValueKey('creation_kind_${kind.key}'),
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                AnimatedOpacity(
                  opacity: _hovered ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: ReorderableDragStartListener(
                    index: widget.index,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.drag_indicator,
                          key: ValueKey('creation_drag_${kind.key}'),
                          size: 18,
                          color: muted,
                        ),
                      ),
                    ),
                  ),
                ),
                Icon(kind.icon, color: foreground, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    kind.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ),
                if (widget.expanded case final expanded?)
                  IconButton(
                    key: ValueKey('creation_expand_${kind.key}'),
                    tooltip: expanded ? 'Hide steps' : 'Show steps',
                    visualDensity: VisualDensity.compact,
                    iconSize: 22,
                    color: muted,
                    onPressed: widget.onToggleExpanded,
                    icon: AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: const Icon(Icons.expand_more),
                    ),
                  ),
                if (widget.count > 0)
                  Text(
                    '${widget.count}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                AnimatedOpacity(
                  opacity: _hovered && widget.onRemove != null ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: IconButton(
                    key: ValueKey('creation_remove_${kind.key}'),
                    tooltip: widget.onRemove == null
                        ? null
                        : 'Remove ${kind.label}',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    color: muted,
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the item editor's steps, indented under the Item tile.
class _StepTab extends StatelessWidget {
  const _StepTab({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? SoftErpTheme.accent
        : onTap != null
        ? SoftErpTheme.textPrimary
        : SoftErpTheme.textSecondary.withValues(alpha: 0.6);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 9, 8, 9),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 20,
              decoration: BoxDecoration(
                color: active ? SoftErpTheme.accent : SoftErpTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The + under the lineup: pulls another master's editor into the wizard.
class _AddKindButton extends StatelessWidget {
  const _AddKindButton({
    required this.options,
    required this.enabled,
    required this.onPick,
  });

  final List<CreationKindSpec> options;
  final bool enabled;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const ValueKey('creation_add_kind'),
      enabled: enabled,
      tooltip: 'Add a form',
      onSelected: onPick,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (final spec in options)
          PopupMenuItem<String>(
            key: ValueKey('creation_add_kind_${spec.key}'),
            value: spec.key,
            child: Row(
              children: [
                Icon(spec.icon, size: 22, color: SoftErpTheme.textSecondary),
                const SizedBox(width: 12),
                Text(spec.label, style: const TextStyle(fontSize: 15.5)),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
          border: Border.all(color: SoftErpTheme.borderStrong, width: 1.4),
        ),
        child: Icon(
          Icons.add,
          size: 28,
          color: enabled ? SoftErpTheme.accent : SoftErpTheme.textSecondary,
        ),
      ),
    );
  }
}

/// A saved record on the right when the first tile is not Item.
class _RecordCard extends StatelessWidget {
  const _RecordCard({
    super.key,
    required this.kind,
    required this.record,
    required this.flash,
  });

  final CreationKindSpec kind;
  final CreatedRecord record;
  final bool flash;

  @override
  Widget build(BuildContext context) {
    final subtitle = (record.subtitle ?? '').trim();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: flash ? SoftErpTheme.accentSurface : Colors.white,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(
          color: flash ? SoftErpTheme.accent : SoftErpTheme.border,
        ),
      ),
      child: Row(
        children: [
          Icon(kind.icon, size: 24, color: SoftErpTheme.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyReference extends StatelessWidget {
  const _EmptyReference({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            color: SoftErpTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// The item still being typed in the middle, shown as it fills in.
class _DraftItemCard extends StatelessWidget {
  const _DraftItemCard({required this.draft});

  final ({String name, String group, String unit, bool saved}) draft;

  @override
  Widget build(BuildContext context) {
    final details = [
      draft.group,
      draft.unit,
    ].where((part) => part.trim().isNotEmpty).join(' · ');
    return Container(
      key: const ValueKey('creation_draft_item'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SoftErpTheme.accentSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.accent, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  draft.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
              ),
              const Text(
                'Not saved',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: SoftErpTheme.accent,
                ),
              ),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              details,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One item as it reads on the right: photo, name, code, unit and variation
/// tree, with a chevron that opens its dies and machines.
class _ItemViewCard extends StatelessWidget {
  const _ItemViewCard({
    required this.item,
    required this.unitSymbol,
    required this.expanded,
    required this.targeted,
    required this.flash,
    required this.onToggle,
    required this.onAddDie,
    required this.onAddMachine,
  });

  final ItemDefinition item;
  final String unitSymbol;
  final bool expanded;
  final bool targeted;
  final bool flash;
  final VoidCallback onToggle;

  /// Null when that tile is not in the lineup.
  final VoidCallback? onAddDie;
  final VoidCallback? onAddMachine;

  @override
  Widget build(BuildContext context) {
    final code = item.alias.trim().isNotEmpty
        ? item.alias.trim()
        : item.shortCode.trim();
    final variations = item.variationTree
        .where((node) => !node.isArchived)
        .toList(growable: false);
    final borderColor = targeted
        ? SoftErpTheme.accent
        : flash
        ? SoftErpTheme.entityItemBorder
        : SoftErpTheme.border;

    return Container(
      decoration: BoxDecoration(
        color: flash && !targeted ? SoftErpTheme.entityItemBg : Colors.white,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: borderColor, width: targeted ? 1.6 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('creation_item_${item.id}'),
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ItemThumb(item: item),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: SoftErpTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (code.isNotEmpty)
                              _Pill(icon: Icons.tag, label: code),
                            if (unitSymbol.isNotEmpty) _Pill(label: unitSymbol),
                            if (item.dies.isNotEmpty)
                              _Pill(
                                icon: _dieKind.icon,
                                label: '${item.dies.length}',
                              ),
                            if (item.machines.isNotEmpty)
                              _Pill(
                                icon: _machineKind.icon,
                                label: '${item.machines.length}',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: const Icon(
                      Icons.expand_more,
                      size: 28,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (variations.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _VariationSummary(roots: variations),
            ),
          if (expanded) ...[
            const Divider(height: 1, color: SoftErpTheme.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final die in item.dies)
                    _AssetRow(
                      kind: _dieKind,
                      title: die.toolCode.trim().isEmpty ? 'Die' : die.toolCode,
                    ),
                  for (final machine in item.machines)
                    _AssetRow(
                      kind: _machineKind,
                      title: machine.name,
                      subtitle: machine.assetId,
                    ),
                  if (item.dies.isEmpty && item.machines.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        'No dies or machines yet.',
                        style: TextStyle(
                          fontSize: 14,
                          color: SoftErpTheme.textSecondary,
                        ),
                      ),
                    ),
                  if (onAddDie != null || onAddMachine != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (onAddDie case final onAddDie?)
                          Expanded(
                            child: _AddUnderButton(
                              key: ValueKey('creation_add_die_${item.id}'),
                              kind: _dieKind,
                              onPressed: onAddDie,
                            ),
                          ),
                        if (onAddDie != null && onAddMachine != null)
                          const SizedBox(width: 8),
                        if (onAddMachine case final onAddMachine?)
                          Expanded(
                            child: _AddUnderButton(
                              key: ValueKey('creation_add_machine_${item.id}'),
                              kind: _machineKind,
                              onPressed: onAddMachine,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemThumb extends StatelessWidget {
  const _ItemThumb({required this.item});

  final ItemDefinition item;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: SoftErpTheme.accentSoft,
      alignment: Alignment.center,
      child: Text(
        item.name.trim().isEmpty ? '?' : item.name.trim()[0].toUpperCase(),
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: SoftErpTheme.accentDeeper,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
      child: SizedBox(
        width: 64,
        height: 64,
        child: item.photoUrl.trim().isEmpty
            ? placeholder
            : Image.network(
                item.photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

/// The variation tree, read-only and compact: each property with its values,
/// nested properties indented under the value they hang from.
class _VariationSummary extends StatelessWidget {
  const _VariationSummary({required this.roots});

  final List<ItemVariationNodeDefinition> roots;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: SoftErpTheme.shellSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final node in roots) ..._rows(node, 0)],
      ),
    );
  }

  List<Widget> _rows(ItemVariationNodeDefinition node, int depth) {
    if (node.kind == ItemVariationNodeKind.value) {
      // A value on its own at the root: show it, then what hangs under it.
      return [
        _row(depth, null, [node.displayName]),
        for (final child in node.activeChildren) ..._rows(child, depth + 1),
      ];
    }
    final values = node.activeChildren
        .where((child) => child.kind == ItemVariationNodeKind.value)
        .toList(growable: false);
    return [
      _row(depth, node.displayName, [
        for (final value in values)
          value.displayName.trim().isEmpty ? value.name : value.displayName,
        if (node.hasNumericRange) node.numericRangeLabel,
      ]),
      for (final value in values)
        for (final child in value.activeChildren) ..._rows(child, depth + 1),
    ];
  }

  Widget _row(int depth, String? property, List<String> values) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 14.0, top: 3, bottom: 3),
      child: Text.rich(
        TextSpan(
          children: [
            if (property != null)
              TextSpan(
                text: '$property  ',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
            TextSpan(
              text: values.isEmpty ? '—' : values.join(' · '),
              style: const TextStyle(color: SoftErpTheme.textPrimary),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 14),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({required this.kind, required this.title, this.subtitle});

  final CreationKindSpec kind;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(kind.icon, size: 20, color: SoftErpTheme.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              [
                title,
                if ((subtitle ?? '').trim().isNotEmpty) subtitle!.trim(),
              ].join(' · '),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
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

class _AddUnderButton extends StatelessWidget {
  const _AddUnderButton({
    super.key,
    required this.kind,
    required this.onPressed,
  });

  final CreationKindSpec kind;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add, size: 20),
      label: Text(kind.label),
      style: OutlinedButton.styleFrom(
        foregroundColor: SoftErpTheme.accentDeeper,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        side: const BorderSide(color: SoftErpTheme.border),
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        ),
      ),
    );
  }
}
