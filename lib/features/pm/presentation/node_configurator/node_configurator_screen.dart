import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/core/widgets/app_card.dart';
import 'package:core_erp/core/widgets/searchable_select.dart';
import 'package:flutter/material.dart';

import 'domain/node_blueprint.dart';
import 'widgets/node_blueprint_cards.dart';
import 'widgets/slot_controls.dart';

/// The Node Configurator — a shelf of reusable pipeline nodes and the editor
/// that authors them.
///
/// A node answers three questions: what runs it, what it mounts, and where its
/// loss goes. Each is a slot with a mode, because a blank field is ambiguous —
/// an empty die means both "no tooling" and "nobody picked one yet", and only
/// the second should stop a run.
///
/// Quantities are not configured here. How much scrap comes off is settled at
/// reconciliation; this screen only says where it lands.
class NodeConfiguratorScreen extends StatefulWidget {
  const NodeConfiguratorScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NodeConfiguratorScreen()),
    );
  }

  @override
  State<NodeConfiguratorScreen> createState() => _NodeConfiguratorScreenState();
}

class _NodeConfiguratorScreenState extends State<NodeConfiguratorScreen> {
  late List<NodeBlueprint> _library;
  late NodeBlueprint _draft;

  /// Seeded from the catalogue, then grown by whoever is configuring. Most
  /// floors run processes the eight defaults never name, so the picker creates
  /// as readily as it selects.
  late List<String> _processTypes;
  String? _selectedId;
  bool _dirty = false;

  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _searchController = TextEditingController();

  String _libraryFilter = 'all';
  bool _showLibraryPane = true;

  @override
  void initState() {
    super.initState();
    _library = NodeConfiguratorCatalog.seedLibrary();
    _processTypes = [...NodeConfiguratorCatalog.processTypes];
    _loadIntoEditor(_library.first);
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Editor plumbing
  // -------------------------------------------------------------------------

  NodeBlueprint get _live =>
      _draft.copyWith(name: _nameController.text, notes: _notesController.text);

  void _loadIntoEditor(NodeBlueprint blueprint) {
    if (!_processTypes.contains(blueprint.processType)) {
      _processTypes.add(blueprint.processType);
    }
    _draft = blueprint;
    _selectedId = blueprint.id;
    _nameController.text = blueprint.name;
    _notesController.text = blueprint.notes;
    _dirty = false;
  }

  void _mutate(NodeBlueprint next) {
    setState(() {
      _draft = next;
      _dirty = true;
    });
  }

  void _startNewNode() {
    setState(() {
      _loadIntoEditor(
        NodeBlueprint(
          id: 'nb_${DateTime.now().microsecondsSinceEpoch}',
          name: '',
          processType: NodeConfiguratorCatalog.processTypes.first,
          machineMode: MachineSlotMode.open,
          dieMode: DieSlotMode.none,
        ),
      );
      _selectedId = null;
      _dirty = true;
      _showLibraryPane = false;
    });
  }

  void _save({bool asCopy = false}) {
    var candidate = _live;
    if (asCopy) {
      final name = candidate.name.trim();
      candidate = candidate.copyWith(
        id: 'nb_${DateTime.now().microsecondsSinceEpoch}',
        name: name.isEmpty ? 'Untitled copy' : '$name (copy)',
      );
    }
    if (!NodeBindingRules.isSaveable(candidate)) return;

    setState(() {
      final index = _library.indexWhere((item) => item.id == candidate.id);
      if (index == -1) {
        _library.insert(0, candidate);
      } else {
        _library[index] = candidate;
      }
      _loadIntoEditor(candidate);
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(asCopy ? 'Saved as a new node.' : 'Saved.'),
          behavior: SnackBarBehavior.floating,
          width: 320,
          backgroundColor: SoftErpTheme.accentDeeper,
        ),
      );
  }

  // -------------------------------------------------------------------------
  // Cross-slot compatibility
  //
  // `Die.compatibleMachineGroupIds` runs both ways: a pinned die fences which
  // machines are legal, a pinned machine fences which dies are. Illegal options
  // stay visible and locked with the reason rather than being filtered out.
  // -------------------------------------------------------------------------

  CatalogDie? get _pinnedDie => _draft.dieMode == DieSlotMode.specific
      ? NodeConfiguratorCatalog.dieById(_draft.dieId)
      : null;

  List<AssetChoice> _machineChoices() {
    final die = _pinnedDie;
    return [
      for (final machine in NodeConfiguratorCatalog.machines)
        () {
          final group = NodeConfiguratorCatalog.groupById(machine.groupId);
          final fits =
              die == null || die.compatibleGroupIds.contains(machine.groupId);
          return AssetChoice(
            id: machine.id,
            title: machine.assetCode,
            subtitle: group?.name ?? '',
            enabled: fits,
            disabledReason: fits
                ? null
                : '${die.name} does not mount in a ${group?.name ?? 'machine of this group'}.',
          );
        }(),
    ];
  }

  List<AssetChoice> _groupChoices() {
    final die = _pinnedDie;
    return [
      for (final group in NodeConfiguratorCatalog.machineGroups)
        () {
          final count = NodeConfiguratorCatalog.machines
              .where((machine) => machine.groupId == group.id)
              .length;
          final fits = die == null || die.compatibleGroupIds.contains(group.id);
          return AssetChoice(
            id: group.id,
            title: group.name,
            subtitle: '$count',
            enabled: fits,
            disabledReason: fits
                ? null
                : '${die.name} does not fit anything in ${group.name}.',
          );
        }(),
    ];
  }

  List<AssetChoice> _dieChoices() {
    final groupId = NodeBindingRules.boundGroupId(_draft);
    final boundGroup = NodeConfiguratorCatalog.groupById(groupId);
    return [
      for (final die in NodeConfiguratorCatalog.dies)
        () {
          final fits =
              groupId == null || die.compatibleGroupIds.contains(groupId);
          return AssetChoice(
            id: die.id,
            title: die.name,
            subtitle: die.toolCode,
            enabled: fits,
            disabledReason: fits
                ? null
                : 'Does not fit ${boundGroup?.name ?? 'the bound group'}.',
          );
        }(),
    ];
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SoftErpTheme.shellSurface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1040;

            return Column(
              children: [
                _ConfiguratorHeader(
                  isWide: isWide,
                  showLibraryPane: _showLibraryPane,
                  dirty: _dirty,
                  onToggleLibrary: () => setState(() {
                    _showLibraryPane = !_showLibraryPane;
                  }),
                  onNewNode: _startNewNode,
                ),
                Expanded(
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: 300, child: _buildLibraryPane()),
                            const VerticalDivider(
                              width: 1,
                              color: SoftErpTheme.border,
                            ),
                            Expanded(child: _buildConfiguratorPane()),
                          ],
                        )
                      : (_showLibraryPane
                            ? _buildLibraryPane()
                            : _buildConfiguratorPane()),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Library rail
  // -------------------------------------------------------------------------

  List<NodeBlueprint> get _visibleLibrary {
    final query = _searchController.text.trim().toLowerCase();
    return _library.where((blueprint) {
      if (query.isNotEmpty) {
        final haystack =
            '${blueprint.name} ${blueprint.processType}'.toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return switch (_libraryFilter) {
        'open' => NodeBindingRules.runtimePrompts(blueprint).isNotEmpty,
        'noloss' => blueprint.lossRoutes.isEmpty,
        _ => true,
      };
    }).toList(growable: false);
  }

  Widget _buildLibraryPane() {
    final visible = _visibleLibrary;

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search ${_library.length} nodes',
                    prefixIcon: const Icon(Icons.search, size: 17),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    filled: true,
                    fillColor: SoftErpTheme.sectionSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _FilterPill(
                        label: 'All',
                        selected: _libraryFilter == 'all',
                        onTap: () => setState(() => _libraryFilter = 'all'),
                      ),
                      _FilterPill(
                        label: 'Asks at run time',
                        selected: _libraryFilter == 'open',
                        onTap: () => setState(() => _libraryFilter = 'open'),
                      ),
                      _FilterPill(
                        label: 'No loss route',
                        selected: _libraryFilter == 'noloss',
                        onTap: () => setState(() => _libraryFilter = 'noloss'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: SoftErpTheme.border),
          Expanded(
            child: visible.isEmpty
                ? const Center(
                    child: Text(
                      'Nothing matches.',
                      style: TextStyle(
                        fontSize: 12,
                        color: SoftErpTheme.textSecondary,
                      ),
                    ),
                  )
                : ListView.separated(
                    key: const PageStorageKey<String>(
                      'node_configurator_library',
                    ),
                    padding: const EdgeInsets.all(12),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final blueprint = visible[index];
                      return NodeBlueprintLibraryCard(
                        blueprint: blueprint,
                        selected: blueprint.id == _selectedId,
                        onTap: () => setState(() {
                          _loadIntoEditor(blueprint);
                          _showLibraryPane = false;
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Configurator pane
  // -------------------------------------------------------------------------

  Widget _buildConfiguratorPane() {
    return ListView(
      key: const PageStorageKey<String>('node_configurator_pane'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        NodeBlueprintPreview(blueprint: _live),
        const SizedBox(height: 14),
        _buildIdentityCard(),
        const SizedBox(height: 12),
        _buildMachineSlotCard(),
        const SizedBox(height: 12),
        _buildDieSlotCard(),
        const SizedBox(height: 12),
        _buildLossCard(),
        const SizedBox(height: 14),
        _buildActionBar(),
      ],
    );
  }

  Widget _buildIdentityCard() {
    return _SectionCard(
      title: 'Identity',
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _nameController,
                  onChanged: (_) => setState(() => _dirty = true),
                  decoration: _fieldDecoration('Node name'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SearchableSelectField<String>(
                  tapTargetKey: const Key('process_type_field'),
                  value: _draft.processType,
                  decoration: _fieldDecoration('Process'),
                  dialogTitle: 'Process',
                  searchHintText: 'Search or type a new process',
                  emptyText: 'No process by that name yet.',
                  options: [
                    for (final type in _processTypes)
                      SearchableSelectOption(value: type, label: type),
                  ],
                  canCreateOption: (query, _) => _canCreateProcess(query),
                  createOptionLabelBuilder: (query) =>
                      'Create process "${query.trim()}"',
                  onCreateOption: _createProcess,
                  onChanged: (value) {
                    if (value != null) {
                      _mutate(_draft.copyWith(processType: value));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesController,
            onChanged: (_) => setState(() => _dirty = true),
            decoration: _fieldDecoration('Shop-floor note (optional)'),
          ),
        ],
      ),
    );
  }

  /// Offer creation for anything that is not already on the list, matched
  /// case-insensitively so "punching" does not become a second Punching.
  bool _canCreateProcess(String query) {
    final name = query.trim();
    if (name.isEmpty) return false;
    return !_processTypes.any(
      (type) => type.toLowerCase() == name.toLowerCase(),
    );
  }

  Future<SearchableSelectOption<String>?> _createProcess(String query) async {
    final name = query.trim();
    if (name.isEmpty) return null;
    setState(() => _processTypes.add(name));
    return SearchableSelectOption<String>(value: name, label: name);
  }

  Widget _buildMachineSlotCard() {
    return _SectionCard(
      title: 'Machine',
      trailing: SlotChip(
        icon: _draft.machineMode.icon,
        label: NodeBindingRules.machineSummary(_draft),
        tone: _draft.machineMode.tone,
        dense: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SlotModeSelector<MachineSlotMode>(
            value: _draft.machineMode,
            caption: _machineCaption(),
            onChanged: (mode) => _mutate(
              _draft.copyWith(
                machineMode: mode,
                machineId: mode == MachineSlotMode.specific
                    ? _draft.machineId
                    : null,
                machineGroupId: mode == MachineSlotMode.group
                    ? _draft.machineGroupId
                    : null,
              ),
            ),
            options: [
              for (final mode in MachineSlotMode.values)
                SlotModeOption<MachineSlotMode>(
                  value: mode,
                  label: mode.label,
                  blurb: mode.blurb,
                  icon: mode.icon,
                  tone: mode.tone,
                ),
            ],
          ),
          if (_draft.machineMode == MachineSlotMode.specific) ...[
            const SizedBox(height: 12),
            AssetChoicePicker(
              choices: _machineChoices(),
              selectedId: _draft.machineId,
              onChanged: (id) => _mutate(_draft.copyWith(machineId: id)),
              emptyLabel: 'No machines.',
            ),
          ] else if (_draft.machineMode == MachineSlotMode.group) ...[
            const SizedBox(height: 12),
            AssetChoicePicker(
              choices: _groupChoices(),
              selectedId: _draft.machineGroupId,
              onChanged: (id) => _mutate(_draft.copyWith(machineGroupId: id)),
              emptyLabel: 'No machine groups.',
            ),
          ],
        ],
      ),
    );
  }

  /// The caption earns its line by saying something the mode name does not.
  String? _machineCaption() {
    switch (_draft.machineMode) {
      case MachineSlotMode.open:
        final allowed = NodeBindingRules.groupsAllowedByDie(_draft);
        return allowed.isEmpty
            ? null
            : 'The die fences it to ${allowed.map((g) => g.name).join(' or ')}.';
      case MachineSlotMode.group:
        final group = NodeConfiguratorCatalog.groupById(_draft.machineGroupId);
        if (group == null) return null;
        final count = NodeConfiguratorCatalog.machines
            .where((machine) => machine.groupId == group.id)
            .length;
        return 'Operator picks one of $count in ${group.name}.';
      case MachineSlotMode.none:
      case MachineSlotMode.specific:
        return null;
    }
  }

  Widget _buildDieSlotCard() {
    return _SectionCard(
      title: 'Die',
      trailing: SlotChip(
        icon: _draft.dieMode.icon,
        label: NodeBindingRules.dieSummary(_draft),
        tone: _draft.dieMode.tone,
        dense: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SlotModeSelector<DieSlotMode>(
            value: _draft.dieMode,
            caption: _dieCaption(),
            onChanged: (mode) => _mutate(
              _draft.copyWith(
                dieMode: mode,
                dieId: mode == DieSlotMode.specific ? _draft.dieId : null,
              ),
            ),
            options: [
              for (final mode in DieSlotMode.values)
                SlotModeOption<DieSlotMode>(
                  value: mode,
                  label: mode.label,
                  blurb: mode.blurb,
                  icon: mode.icon,
                  tone: mode.tone,
                ),
            ],
          ),
          if (_draft.dieMode == DieSlotMode.specific) ...[
            const SizedBox(height: 12),
            AssetChoicePicker(
              choices: _dieChoices(),
              selectedId: _draft.dieId,
              onChanged: (id) => _mutate(_draft.copyWith(dieId: id)),
              emptyLabel: 'No dies.',
            ),
          ],
        ],
      ),
    );
  }

  String? _dieCaption() {
    if (_draft.dieMode != DieSlotMode.open) return null;
    final groupId = NodeBindingRules.boundGroupId(_draft);
    final group = NodeConfiguratorCatalog.groupById(groupId);
    if (group == null) return null;
    final count = NodeConfiguratorCatalog.diesForGroup(groupId!).length;
    return 'Operator picks from the $count dies that fit ${group.name}.';
  }

  // -------------------------------------------------------------------------
  // Loss — scrap and rejection
  // -------------------------------------------------------------------------

  Widget _buildLossCard() {
    final routes = _draft.lossRoutes;

    return _SectionCard(
      title: 'Loss',
      trailing: SlotChip(
        icon: Icons.recycling,
        label: NodeBindingRules.lossSummary(_draft),
        tone: NodeBindingRules.lossTone(_draft),
        dense: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (routes.isEmpty)
            const Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 13,
                  color: SoftErpTheme.textSecondary,
                ),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Nothing routed. Reconciliation will refuse scrap on this '
                    'node.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            )
          else
            for (var i = 0; i < routes.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _LossRouteRow(
                route: routes[i],
                onChanged: (next) => _replaceRoute(i, next),
                onRemove: () => _removeRoute(i),
              ),
            ],
          const SizedBox(height: 12),
          Row(
            children: [
              _AddLossButton(
                key: const Key('add_loss_scrap'),
                icon: Icons.recycling,
                label: 'Scrap',
                onTap: () => _addRoute(LossKind.scrap),
              ),
              const SizedBox(width: 8),
              _AddLossButton(
                key: const Key('add_loss_rejection'),
                icon: Icons.thumb_down_alt_outlined,
                label: 'Rejection',
                onTap: () => _addRoute(LossKind.rejection),
              ),

            ],
          ),
        ],
      ),
    );
  }

  void _addRoute(LossKind kind) {
    final route = LossRoute(
      id: 'l_${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      // Pre-pick the first destination that is not already spoken for, so a new
      // row is useful rather than an empty obligation.
      scrapItemId: kind == LossKind.scrap ? _firstFreeScrapItemId() : null,
      rejection: kind == LossKind.rejection ? RejectionRoute.rework : null,
    );
    _mutate(_draft.copyWith(lossRoutes: [..._draft.lossRoutes, route]));
  }

  String? _firstFreeScrapItemId() {
    final taken = _draft.lossRoutes
        .where((route) => route.kind == LossKind.scrap)
        .map((route) => route.scrapItemId)
        .toSet();
    for (final item in NodeConfiguratorCatalog.scrapItems) {
      if (!taken.contains(item.id)) return item.id;
    }
    return null;
  }

  void _replaceRoute(int index, LossRoute next) {
    final routes = [..._draft.lossRoutes];
    routes[index] = next;
    _mutate(_draft.copyWith(lossRoutes: routes));
  }

  void _removeRoute(int index) {
    final routes = [..._draft.lossRoutes]..removeAt(index);
    _mutate(_draft.copyWith(lossRoutes: routes));
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  Widget _buildActionBar() {
    final issues = NodeBindingRules.validate(_live);
    final errors = issues
        .where((issue) => issue.level == IssueLevel.error)
        .toList();
    final warnings = issues
        .where((issue) => issue.level == IssueLevel.warning)
        .toList();
    final isNew = !_library.any((item) => item.id == _draft.id);

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Problems live next to the disabled button that they disable,
          // rather than in a panel of their own.
          for (final issue in [...errors, ...warnings])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    issue.level == IssueLevel.error
                        ? Icons.error_outline
                        : Icons.warning_amber_rounded,
                    size: 14,
                    color: issue.level == IssueLevel.error
                        ? SoftErpTheme.dangerText
                        : SoftErpTheme.warningText,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      issue.message,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: issue.level == IssueLevel.error
                            ? SoftErpTheme.dangerText
                            : SoftErpTheme.warningText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppButton(
                label: isNew ? 'Add to library' : 'Save',
                icon: Icons.save_outlined,
                onPressed: errors.isEmpty ? () => _save() : null,
              ),
              AppButton(
                label: 'Save as new',
                icon: Icons.copy_all_outlined,
                variant: AppButtonVariant.secondary,
                onPressed: errors.isEmpty ? () => _save(asCopy: true) : null,
              ),
              if (_dirty && errors.isEmpty)
                const Text(
                  'Unsaved changes',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: SoftErpTheme.warningText,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

InputDecoration _fieldDecoration(String label) {
  return InputDecoration(
    isDense: true,
    labelText: label,
    floatingLabelBehavior: FloatingLabelBehavior.auto,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    filled: true,
    fillColor: SoftErpTheme.sectionSurface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: BorderSide.none,
    ),
  );
}

// ---------------------------------------------------------------------------
// Loss route row
// ---------------------------------------------------------------------------

class _LossRouteRow extends StatelessWidget {
  const _LossRouteRow({
    required this.route,
    required this.onChanged,
    required this.onRemove,
  });

  final LossRoute route;
  final ValueChanged<LossRoute> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isScrap = route.kind == LossKind.scrap;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        children: [
          _KindToggle(
            kind: route.kind,
            onChanged: (kind) => onChanged(
              // Destinations do not survive a kind change — a scrap item is not
              // a place to send bad pieces.
              LossRoute(
                id: route.id,
                kind: kind,
                rejection: kind == LossKind.rejection
                    ? RejectionRoute.rework
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(
            Icons.arrow_right_alt,
            size: 16,
            color: SoftErpTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: isScrap
                ? _Dropdown<String>(
                    value: route.scrapItemId,
                    hint: 'Scrap item',
                    items: [
                      for (final item in NodeConfiguratorCatalog.scrapItems)
                        DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                    ],
                    onChanged: (value) =>
                        onChanged(route.copyWith(scrapItemId: value)),
                  )
                : _Dropdown<RejectionRoute>(
                    value: route.rejection,
                    hint: 'Where to',
                    items: [
                      for (final option in RejectionRoute.values)
                        DropdownMenuItem(
                          value: option,
                          child: Text(
                            '${option.label} — ${option.detail}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        onChanged(route.copyWith(rejection: value)),
                  ),
          ),
          const SizedBox(width: 8),
          _UnitPicker(
            unitId: route.effectiveUnitId,
            onChanged: (id) => onChanged(route.copyWith(unitId: id)),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'Remove',
            color: SoftErpTheme.textSecondary,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _KindToggle extends StatelessWidget {
  const _KindToggle({required this.kind, required this.onChanged});

  final LossKind kind;
  final ValueChanged<LossKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in LossKind.values) ...[
          if (option != LossKind.values.first) const SizedBox(width: 4),
          InkWell(
            onTap: () => onChanged(option),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: option == kind ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: option == kind
                      ? SoftErpTheme.accent
                      : Colors.transparent,
                ),
              ),
              child: Text(
                option.label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: option == kind
                      ? SoftErpTheme.accentDeeper
                      : SoftErpTheme.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The unit a loss route is recorded in.
///
/// Defaulted by kind but never locked by it — a rejection is often counted in
/// gross rather than pieces, and reel trim is sometimes measured in running
/// metres. The menu groups by family because conversion is only a fixed factor
/// inside one; crossing families needs a per-piece weight.
class _UnitPicker extends StatelessWidget {
  const _UnitPicker({required this.unitId, required this.onChanged});

  final String unitId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final unit = NodeConfiguratorCatalog.unitById(unitId);

    return PopupMenuButton<String>(
      tooltip: 'Unit',
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final family in UnitFamily.values) ...[
          PopupMenuItem<String>(
            enabled: false,
            height: 26,
            child: Text(
              family.label.toUpperCase(),
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ),
          for (final option in NodeConfiguratorCatalog.unitsIn(family))
            PopupMenuItem<String>(
              value: option.id,
              height: 34,
              child: Row(
                children: [
                  SizedBox(
                    width: 46,
                    child: Text(
                      option.symbol,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: option.id == unitId
                            ? SoftErpTheme.accentDeeper
                            : SoftErpTheme.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    option.name,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: SoftErpTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              unit?.symbol ?? unitId,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: SoftErpTheme.textPrimary,
              ),
            ),
            const Icon(
              Icons.expand_more,
              size: 14,
              color: SoftErpTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddLossButton extends StatelessWidget {
  const _AddLossButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: SoftErpTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 14, color: SoftErpTheme.accentDeeper),
            const SizedBox(width: 5),
            Icon(icon, size: 13, color: SoftErpTheme.textSecondary),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
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

// ---------------------------------------------------------------------------
// Header and shared bits
// ---------------------------------------------------------------------------

class _ConfiguratorHeader extends StatelessWidget {
  const _ConfiguratorHeader({
    required this.isWide,
    required this.showLibraryPane,
    required this.dirty,
    required this.onToggleLibrary,
    required this.onNewNode,
  });

  final bool isWide;
  final bool showLibraryPane;
  final bool dirty;
  final VoidCallback onToggleLibrary;
  final VoidCallback onNewNode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: SoftErpTheme.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to PM',
            color: SoftErpTheme.textPrimary,
          ),
          const SizedBox(width: 2),
          const Flexible(
            child: Text(
              'Node Configurator',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: SoftErpTheme.textPrimary,
              ),
            ),
          ),
          if (dirty) ...[
            const SizedBox(width: 8),
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: SoftErpTheme.warningText,
              ),
            ),
          ],
          const Spacer(),
          if (!isWide) ...[
            OutlinedButton.icon(
              onPressed: onToggleLibrary,
              icon: Icon(
                showLibraryPane ? Icons.tune : Icons.grid_view,
                size: 16,
              ),
              label: Text(showLibraryPane ? 'Configure' : 'Library'),
              style: OutlinedButton.styleFrom(
                foregroundColor: SoftErpTheme.textPrimary,
                side: const BorderSide(color: SoftErpTheme.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          FilledButton.icon(
            onPressed: onNewNode,
            icon: const Icon(Icons.add, size: 17),
            label: Text(isWide ? 'New node' : 'New'),
            style: FilledButton.styleFrom(
              backgroundColor: SoftErpTheme.accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
              const Spacer(),
              if (trailing != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: trailing!,
                ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// A dropdown that matches the filled text fields around it.
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  final T? value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(
            hint,
            style: const TextStyle(
              fontSize: 12.5,
              color: SoftErpTheme.textSecondary,
            ),
          ),
          isExpanded: true,
          icon: const Icon(Icons.expand_more, size: 18),
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: SoftErpTheme.textPrimary,
          ),
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
          items: items,
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? SoftErpTheme.accentSoft : const Color(0xFFFDFDFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? SoftErpTheme.accent : SoftErpTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected
                ? SoftErpTheme.accentDeeper
                : SoftErpTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
