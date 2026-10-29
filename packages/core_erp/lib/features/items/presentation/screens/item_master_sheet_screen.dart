import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/network/sitting_scope.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/services/entity_photos.dart';
import '../../../../core/widgets/mini_photo.dart';
import '../../../../sheet/sheet.dart';
import '../../../clients/presentation/providers/clients_provider.dart';
import '../../../groups/presentation/providers/groups_provider.dart';
import '../../../materials/presentation/providers/materials_provider.dart';
import '../../../process_routes/data/process_route_service.dart';
import '../../../process_routes/domain/part_route.dart';
import '../../../process_routes/presentation/widgets/route_creation_panel.dart';
import '../../../production_pipelines/domain/pen_paper_baseline.dart';
import '../../../production_pipelines/domain/pipeline_stage_node.dart';
import '../../../production_pipelines/domain/sheet_part.dart';
import '../../../production_pipelines/presentation/widgets/master_data_dialog.dart';
import '../../data/item_sheet_binding.dart';
import '../../domain/sheet_property.dart';
import '../providers/sheet_properties_provider.dart';
import '../../domain/developed_for.dart';
import '../../domain/item_definition.dart';
import '../providers/items_provider.dart';
import '../widgets/margin_health_badge.dart';
import '../widgets/part_die_section.dart';
import '../widgets/part_machine_section.dart';
import '../widgets/deal_people_form.dart';
import '../../../../core/app_flow_hooks.dart';

/// The item master as a sheet — the real screen behind the PM prototype.
///
/// The prototype (`PMItemMasterDetailScreen`) is the UI reference and stays as
/// one: it holds its records in four in-memory lists, seeds five groups and
/// four companies nobody created, and its save toasted a hardcoded part code.
/// This screen is the same layout over the real masters, through
/// [ItemSheetBinding].
///
/// Four sections down one scroll, with a rail that jumps between them. The
/// Client / Vendor section is only shown for a part developed for someone else
/// — but its draft is kept either way, so unticking the box and changing your
/// mind does not lose what was typed.
class ItemMasterSheetScreen extends StatefulWidget {
  const ItemMasterSheetScreen({
    super.key,
    this.initialItems = const [],
    this.title = 'New part',
  });

  /// Parts to open for editing. Empty means a new part.
  final List<ItemDefinition> initialItems;

  /// The last breadcrumb.
  final String title;

  /// Opens the sheet as a full-screen route.
  ///
  /// A route and not a dialog: Express was a dialog, and a dialog over the
  /// masters list meant the sheet could never be as wide as the sheet wants to
  /// be — it is a spreadsheet with a rail beside it, not a form.
  static Future<void> open(
    BuildContext context, {
    List<ItemDefinition> initialItems = const [],
    String title = 'New part',
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ItemMasterSheetScreen(
          initialItems: initialItems,
          title: title,
        ),
      ),
    );
  }

  @override
  State<ItemMasterSheetScreen> createState() => _ItemMasterSheetScreenState();
}

class _ItemMasterSheetScreenState extends State<ItemMasterSheetScreen> {
  late final ItemMasterController _controller;
  late final ItemSheetBinding _binding;

  /// This window's sitting, so everything saved here is attributable to one
  /// opening of one screen. Begun in `initState` and ended on dispose by id,
  /// because disposal order is not guaranteed to reverse opening order.
  String? _sittingId;

  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _sectionKeys = {
    'group_item': GlobalKey(),
    'client_vendor': GlobalKey(),
    'die_master': GlobalKey(),
    'machine_master': GlobalKey(),
  };

  bool _showRoutePanel = false;

  /// Sections folded shut. Folding one hides everything nested under it, the
  /// way a closed folder hides its subfolders.
  final Set<String> _collapsed = <String>{};

  /// How this part's sections are nested: section → parent. Data, not layout —
  /// saving it re-links the part's client, dies and machines (migration 057).
  static const Map<String, String> _defaultTree = {
    'client_vendor': 'group_item',
    'die_master': 'client_vendor',
    'machine_master': 'die_master',
  };
  Map<String, String> _parentOf = Map<String, String>.of(_defaultTree);

  /// What is stored, so a change can be seen and undone.
  Map<String, String> _savedTree = Map<String, String>.of(_defaultTree);
  int? _treeLoadedFor;
  bool _savingTree = false;
  bool get _treeDirty => !mapEquals(_parentOf, _savedTree);

  /// The raw sheet & strips panel on the right: open (null = decide from the
  /// window width), being edited, and a counter that resets it on Cancel.
  bool? _rawPanelOpen;
  bool _rawEditing = false;
  int _rawEpoch = 0;

  /// A raw sheet save in flight, and the part the panel was last drawn for —
  /// so moving to another part does not carry edit mode across to it.
  bool _rawSaving = false;
  int? _rawPartId;
  static const double _rawPanelWidth = 520;

  /// The part's authored route, which IS its pipeline — Author route is only
  /// the way a pipeline is drawn. Read for the raw sheet panel, so its stages
  /// and its "attached to" follow the route rather than the legacy
  /// `defaultPipelineId`, which a routed part never sets.
  PartRoute? _route;
  int? _routeForPartId;

  /// The left rail folded to an icon strip (remembered on this device).
  bool _railCollapsed = false;
  static const _railPrefKey = 'item_sheet.rail_collapsed';


  /// Dies and machines entered before their row's part exists, held per row
  /// and written onto THAT row's part once it does. One list for the screen
  /// put a die held on row 2 onto whichever part was open when something
  /// saved.
  final Map<Object, List<DieSheetDraft>> _heldDies = Map.identity();
  final Map<Object, List<MachineSheetDraft>> _heldMachines = Map.identity();

  Object get _cursorRowKey => _controller.groupItemController.draft.rowKey;

  /// The cursor row's held dies and machines — what the sections show.
  List<DieSheetDraft> get _stagedDies =>
      _heldDies.putIfAbsent(_cursorRowKey, () => []);
  List<MachineSheetDraft> get _stagedMachines =>
      _heldMachines.putIfAbsent(_cursorRowKey, () => []);
  final Set<int> _madeHere = <int>{};

  static const _sections = [
    SheetSection(
      id: 'group_item',
      title: 'Group Item',
      subtitle: 'Identity, hierarchy & properties',
      icon: Icons.table_rows_rounded,
    ),
    SheetSection(
      id: 'client_vendor',
      title: 'Client / Vendor',
      subtitle: 'Party, contact & the development deal',
      icon: Icons.storefront_rounded,
    ),
    SheetSection(
      id: 'die_master',
      title: 'Die Process Master',
      subtitle: 'Press tooling & progressive dies',
      icon: Icons.precision_manufacturing_rounded,
    ),
    SheetSection(
      id: 'machine_master',
      title: 'Machines & Routing',
      subtitle: 'Shop floor routing & specs',
      icon: Icons.settings_suggest_rounded,
    ),
  ];

  /// The masters the pickers are built from. Watched, not read once.
  ItemsProvider? _items;
  GroupsProvider? _groups;
  MaterialsProvider? _materials;
  ClientsProvider? _clients;

  /// The sheet's saved property columns (061), shared by every window.
  SheetPropertiesProvider? _sheetProps;

  /// Keys of the stored columns last put on the sheet — so a column removed
  /// elsewhere is taken off, while Alloy and Thickness (not stored) never are.
  Set<String> _storedKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _sittingId = SittingScope.begin();

    _controller = ItemMasterController.live(binding: _buildBinding());
    _controller.addListener(_onControllerChanged);

    // Reference data is loaded again whenever the masters change, not once at
    // open. The screen can be opened before the providers have finished their
    // first fetch — and it was, in the running app: the Group picker opened
    // offering nothing at all, for a workspace with three groups in it. A
    // single post-frame load has no way to recover from that.
    //
    // This also keeps the running numbers and taken codes current after a
    // save, since `ItemsProvider` notifies on one.
    _items = context.read<ItemsProvider>()..addListener(_onMastersChanged);
    _groups = context.read<GroupsProvider>()..addListener(_onMastersChanged);

    // The Alloy column offers the materials master, and the master is lazy:
    // nothing in this screen or the app warm-up ever loaded it, so the picker
    // was empty on a cold launch and full only if the user had happened to
    // open Masters → Materials earlier in the same session. The listener is the
    // load-bearing half — `ensureLoaded` is a future, and reference data built
    // before it lands has to be rebuilt when it does.
    _materials = _maybeRead<MaterialsProvider>()
      ?..addListener(_onMastersChanged);

    // The Company dropdown is the clients master. Without this a company added
    // anywhere else — the Clients screen, another window — did not appear here
    // until the sheet was reopened.
    _clients = _maybeRead<ClientsProvider>()?..addListener(_onMastersChanged);
    _sheetProps = _maybeRead<SheetPropertiesProvider>()
      ?..addListener(_onSheetPropsChanged);

    // Saves elsewhere show up through the providers above. A die or machine
    // edited anywhere arrives as a change to every part that uses it
    // (migration 060), which ItemsProvider fetches fresh. This used to call
    // ItemsProvider.refresh() itself — a read of the local replica, which had
    // not applied the change yet, so it answered with the old die.

    // Commit whichever row the cursor leaves, however it left — a click, Tab
    // or Enter past the end, or Add row.
    // The property columns' hooks: a value typed in joins the column's list,
    // and removing, renaming or editing a stored column changes it for all.
    _controller.groupItemController
      ..onOptionAdded = _onOptionAdded
      ..removalFor = _optionRemovalFor
      ..confirmRemoveColumn = _confirmRemoveColumn
      ..onColumnRemoved = _onColumnRemoved
      ..onColumnRenamed = _onColumnRenamed
      ..canEditOptions = ((column) => _storedFor(column) != null)
      ..onEditOptions = _editOptions
      ..onRowLeft = (row) => unawaited(_commitOnLeave(row));

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      unawaited(_materials?.ensureLoaded());
      final clients = _clients;
      if (clients != null && clients.clients.isEmpty && !clients.isLoading) {
        unawaited(clients.refresh());
      }
      // The stored property columns go on before the pickers are built, so
      // their options are built with them.
      await _sheetProps?.ensureLoaded();
      if (!mounted) return;
      final props = _sheetProps;
      if (props != null && !props.isLoaded) {
        // Said, not swallowed: the columns stay off the sheet until a read
        // gets through, and nobody should think the sheet has none.
        _toast(
          'The sheet\'s property columns did not load: '
          '${props.errorMessage ?? 'no answer from the server'}',
          isError: true,
        );
      }
      _syncPropertyColumns();
      await _controller.loadReferenceData();
      if (!mounted) return;
      unawaited(_loadRailPreference());
      if (widget.initialItems.isNotEmpty) {
        _controller.loadItems(widget.initialItems);
      }
    });
  }

  bool _mastersReloadScheduled = false;

  void _onMastersChanged() {
    if (!mounted || _mastersReloadScheduled) return;
    // One save notifies three or four times, and each notification rebuilt
    // every option and re-validated every row. Collapsed to one per frame.
    _mastersReloadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mastersReloadScheduled = false;
      if (!mounted) return;
      // A saved part changed elsewhere: show it in the rows that are closed —
      // never in one somebody is typing in.
      final items = _items;
      if (items != null) _controller.refreshLockedRows(items.items);
      _controller.loadReferenceData();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  ItemSheetBinding _buildBinding() {
    _binding = ItemSheetBinding(
      items: context.read<ItemsProvider>(),
      groups: context.read<GroupsProvider>(),
      clients: _maybeRead<ClientsProvider>(),
      materials: _maybeRead<MaterialsProvider>(),
      itemSheet: SheetDef(
        id: 1,
        key: 'item',
        title: 'Group Item',
        columns: itemSheetColumns,
      ),
      // The controller's copy is the one a + adds properties to.
      liveItemSheet: () => _controller.groupItemController.sheetDef,
      sheetProperties: () => _sheetProps?.properties ?? const [],
      partySheet: SheetDef(
        id: 2,
        key: 'item_party',
        title: 'Client / Vendor',
        columns: dealSheetColumns,
      ),
      // The deal is one record for the screen, and the binding reads it live
      // at each save rather than being handed a copy taken at build time —
      // which is what the old `partyDraft: null` here amounted to: the deal
      // was drawn, typed into, and never once saved.
      dealDraft: () => _controller.dealDraftForSave(),
      dealContactIds: () => _controller.dealContactIdsForSave(),
      peopleSheet: SheetDef(
        id: 3,
        key: 'item_people',
        title: 'People',
        columns: peopleSheetColumns,
      ),
    );
    return _binding;
  }

  /// A provider the host may not have registered. The binding takes both as
  /// optional, so a missing materials master means an empty Alloy picker
  /// rather than a crash on open.
  T? _maybeRead<T>() {
    try {
      return Provider.of<T>(context, listen: false);
    } catch (_) {
      return null;
    }
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.groupItemController
      ..onRowLeft = null
      ..onOptionAdded = null
      ..removalFor = null
      ..confirmRemoveColumn = null
      ..onColumnRemoved = null
      ..onColumnRenamed = null
      ..canEditOptions = null
      ..onEditOptions = null;
    _sheetProps?.removeListener(_onSheetPropsChanged);
    _items?.removeListener(_onMastersChanged);
    _groups?.removeListener(_onMastersChanged);
    _materials?.removeListener(_onMastersChanged);
    _clients?.removeListener(_onMastersChanged);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _scroll.dispose();
    final sitting = _sittingId;
    if (sitting != null) SittingScope.end(sitting);
    super.dispose();
  }

  /// Commits every row that is ready.
  ///
  /// Rows normally commit on their own as the cursor leaves them; this is the
  /// explicit pass, and the only way the row still under the cursor gets
  /// written without moving off it.
  Future<void> _handleSave() async {
    // Ctrl+S is not disabled the way the button is, and a second pass while
    // the first runs would count every busy row as "nothing to do".
    if (_controller.isSavingNow) {
      _toast('Still saving — one moment.');
      return;
    }
    final written = await _controller.commitAllRows();
    if (!mounted) return;
    for (final id in _controller.savedItemIds) {
      _madeHere.add(id);
    }
    // Held dies and machines go with the part. Only leaving a row wrote them
    // before, so a part saved with Ctrl+S and closed lost them.
    await _flushStaged();
    if (!mounted) return;
    // The nesting rides along with a save once there is a part to save it on.
    if (_treeDirty && _livePart != null) await _saveTree();
    if (!mounted) return;
    _toast(_controller.statusBarMessage, isError: written == 0);
  }

  /// Commits [row] as the cursor leaves it.
  ///
  /// A row is written when it is complete and you move on, which is the whole
  /// of "catalogue at speed": fifty parts are fifty independent writes, and a
  /// refusal costs only the row it refused.
  Future<void> _commitOnLeave(int row) async {
    if (!_controller.savedRows.contains(row)) {
      final ok = await _controller.commitRow(row);
      if (!mounted) return;
      if (ok) {
        // The row just left, not the cursor's: that has moved on.
        final id = _committedPartId;
        if (id != null) _madeHere.add(id);
        await _flushStaged();
        // A nesting arranged before the part existed is saved with it now.
        if (mounted && _treeDirty) await _saveTree();
      }
    }
  }

  /// The part the last successful row save wrote, wherever its row is now.
  int? get _committedPartId {
    final at = _controller.lastCommittedRow;
    final sheet = _controller.groupItemController;
    if (at == null || at < 0 || at >= sheet.rowCount) return null;
    return sheet.draftAt(at).entityId;
  }

  ItemDefinition? _partById(int id) {
    for (final item in context.read<ItemsProvider>().items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Writes the dies and machines held on every row whose part now exists,
  /// each onto its own row's part. A row removed takes what it held with it.
  Future<void> _flushStaged() async {
    if (!AppFlowHooks.canCreateDieFromSheet &&
        !AppFlowHooks.canCreateMachineFromSheet) {
      return;
    }
    final sheet = _controller.groupItemController;
    final keys = {..._heldDies.keys, ..._heldMachines.keys}.toList();
    for (final key in keys) {
      if (!mounted) return;
      final dies = _heldDies[key] ?? const <DieSheetDraft>[];
      final machines = _heldMachines[key] ?? const <MachineSheetDraft>[];
      if (dies.isEmpty && machines.isEmpty) continue;
      final at = sheet.indexOfRowKey(key);
      if (at < 0) {
        _heldDies.remove(key);
        _heldMachines.remove(key);
        continue;
      }
      final id = sheet.draftAt(at).entityId;
      final part = id == null ? null : _partById(id);
      if (part == null) continue;
      await _flushHeldOnto(part, key);
    }
  }

  /// Two calls, because each list is a full replace on the item. Held records
  /// are created first and only then linked, so a create that succeeded but a
  /// link that failed leaves the record in its master rather than losing it.
  Future<void> _flushHeldOnto(ItemDefinition part, Object rowKey) async {
    final held = _heldDies[rowKey] ?? <DieSheetDraft>[];
    final dieIds = <String>[for (final d in part.dies) d.id];
    var diesAdded = false;
    for (final draft in List<DieSheetDraft>.from(held)) {
      if (!mounted) return;
      final outcome = await AppFlowHooks.createDieFromSheet?.call(context, draft);
      final id = outcome?.record?.id;
      if (id == null) {
        // Still held, so it is tried again on the next save — but say why it
        // did not go, or it just sits in the list looking pending forever.
        if (mounted) {
          _toast(
            'Die ${draft.toolCode} was not made: '
            '${outcome?.message ?? 'no reason given'}.',
            isError: true,
          );
        }
        continue;
      }
      dieIds.add(id);
      diesAdded = true;
      if (mounted) setState(() => held.remove(draft));
    }

    final heldMachines = _heldMachines[rowKey] ?? <MachineSheetDraft>[];
    final machineIds = <String>[for (final m in part.machines) m.id];
    var machinesAdded = false;
    for (final draft in List<MachineSheetDraft>.from(heldMachines)) {
      if (!mounted) return;
      final outcome =
          await AppFlowHooks.createMachineFromSheet?.call(context, draft);
      final id = outcome?.record?.id;
      if (id == null) {
        if (mounted) {
          _toast(
            'Machine ${draft.assetId} was not made: '
            '${outcome?.message ?? 'no reason given'}.',
            isError: true,
          );
        }
        continue;
      }
      machineIds.add(id);
      machinesAdded = true;
      if (mounted) setState(() => heldMachines.remove(draft));
    }

    if (!mounted) return;
    if (diesAdded) await _setDiesOn(part.id, dieIds);
    if (machinesAdded) await _setMachinesOn(part.id, machineIds);
  }

  void _toast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 14)),
        backgroundColor:
            isError ? SoftErpTheme.dangerText : SoftErpTheme.successText,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  bool get _hasUnsavedWork =>
      _controller.hasUnsavedWork ||
      _heldDies.values.any((held) => held.isNotEmpty) ||
      _heldMachines.values.any((held) => held.isNotEmpty);

  /// Back with something unwritten. Rows commit as the cursor leaves them,
  /// but the row under the cursor, an edit to a saved row and held dies were
  /// all dropped without a word when the screen closed.
  Future<void> _confirmLeave() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave with unsaved work?', style: TextStyle(fontSize: 18)),
        content: const Text(
          'Some rows, edits or held dies and machines have not been saved yet.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('stay'),
            child: const Text('Keep editing', style: TextStyle(fontSize: 14)),
          ),
          TextButton(
            key: const ValueKey<String>('leave_discard'),
            onPressed: () => Navigator.of(dialogContext).pop('discard'),
            child: const Text('Discard', style: TextStyle(fontSize: 14)),
          ),
          FilledButton(
            key: const ValueKey<String>('leave_save'),
            onPressed: () => Navigator.of(dialogContext).pop('save'),
            child: const Text('Save and close', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'stay') return;
    if (choice == 'save') {
      await _handleSave();
      if (!mounted || _hasUnsavedWork) return;
    }
    _leaving = true;
    Navigator.of(context).pop();
  }

  /// Set once the user has chosen to go, so the pop is not intercepted again.
  bool _leaving = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _leaving || !_hasUnsavedWork,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmLeave());
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: SoftErpTheme.shellSurface,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true):
              _handleSave,
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
              _handleSave,
        },
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              _topBar(),
              Expanded(
                child: Row(
                  children: [
                    if (_railCollapsed)
                      _collapsedRail()
                    else
                      Stack(
                        children: [
                          SheetSidebar(
                      controller: _controller.groupItemController,
                      sections: [
                        for (final section in _sections)
                          if (section.id != 'client_vendor' ||
                              _controller.isExternal)
                            section,
                      ],
                      activeSection: _controller.activeSection,
                      onSelectSection: _goTo,
                      // The part is pinned above the content now, so the
                      // sidebar naming it too would say it twice.
                      showIdentity: false,
                    ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: IconButton(
                              key: const ValueKey<String>('rail_collapse'),
                              tooltip: 'Fold the side column to icons',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _setRailCollapsed(true),
                              icon: const Icon(
                                Icons.keyboard_double_arrow_left_rounded,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    Expanded(child: _body()),
                    _rawSheetPanel(),
                  ],
                ),
              ),
              SheetStatusBar(
                isEditing: _controller.isEditing,
                // The section's name — this printed its id, `group_item`.
                location: _sectionTitle(_controller.activeSection),
                message: _controller.statusBarMessage,
                isError: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sectionTitle(String id) {
    for (final section in _sections) {
      if (section.id == id) return section.title;
    }
    return id;
  }

  /// Who the part was developed for, named only when a party is actually
  /// chosen. The prototype's sidebar read
  /// `draft.get(20)?.optionLabel ?? 'Gold Medal'`, so a part developed for
  /// nobody claimed a real company.
  String? _developedForLine() {
    if (!_controller.isExternal) return 'Developed for: Self';
    final sheet = _controller.clientVendorController.sheetDef;
    final column = sheet.columnBoundTo(SheetBindsTo.developedForParty);
    if (column == null) return null;
    final value = _controller.clientVendorController.draft.get(column.id);
    final name = value?.optionLabel ?? value?.textValue;
    if (name == null || name.trim().isEmpty) {
      return 'Developed for: not chosen yet';
    }
    return 'Developed for: $name';
  }

  Widget _topBar() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: SoftErpTheme.cardSurface,
        border: Border(bottom: BorderSide(color: SoftErpTheme.border)),
        boxShadow: SoftErpTheme.insetShadow,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 8),
            _crumb('Masters'),
            _crumbSep(),
            _crumb('Items'),
            _crumbSep(),
            _crumb(widget.title, isLast: true),
            const SizedBox(width: 20),
            if (_controller.isLoading)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _controller.isExternal,
                  activeColor: SoftErpTheme.accent,
                  onChanged: (val) {
                    if (val != null) _controller.setExternal(val);
                  },
                ),
                const Text(
                  'Developed for an external party',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            _archiveButton(),
            const SizedBox(width: 8),
            AppButton(
              key: const ValueKey('save_item_sheet_btn'),
              label: _controller.isSavingNow
                  ? 'Saving…'
                  : (_controller.isSaved ? 'Save changes (Ctrl+S)' : 'Save part (Ctrl+S)'),
              icon: _controller.isSaved
                  ? Icons.check_circle_rounded
                  : Icons.save_rounded,
              isLoading: _controller.isSavingNow,
              onPressed: _controller.isSavingNow ? null : _handleSave,
            ),
          ],
        ),
      ),
    );
  }

  Widget _crumb(String text, {bool isLast = false}) => Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isLast ? FontWeight.w800 : FontWeight.w600,
          color: isLast ? SoftErpTheme.textPrimary : SoftErpTheme.textSecondary,
        ),
      );

  Widget _crumbSep() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Text('›', style: TextStyle(fontSize: 14, color: SoftErpTheme.textMuted)),
      );

  /// The section the rail has selected, and only that one.
  ///
  /// This was all four stacked down one scroll, which is what made the screen
  /// feel cramped: four sections competing for one width, every grid truncating
  /// its headers, and 320px of card spent to show 92px of content. The rail
  /// already drove `activeSection` — it only ever scrolled to it.
  // --- raw sheet & strips (right-hand panel) ---------------------------------

  /// The raw material a part is cut from — sheet size, gauge, the strips laid
  /// across it, the cut plan, yields and weights — drawn as the animated sheet
  /// from the old Master Data dialog. The last step after item → client → die
  /// → machine, so it sits to the right of them. Stored on the part
  /// (`pen_paper_baseline`), so it opens once the part exists.
  Widget _rawSheetPanel() {
    final open = _rawPanelOpen ?? MediaQuery.sizeOf(context).width >= 1500;
    if (!open) {
      return Container(
        key: const ValueKey<String>('raw_panel_closed'),
        width: 44,
        decoration: const BoxDecoration(
          color: SoftErpTheme.cardSurface,
          border: Border(left: BorderSide(color: SoftErpTheme.border)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            IconButton(
              key: const ValueKey<String>('raw_panel_open'),
              tooltip: 'Open the raw sheet & strips',
              onPressed: () => setState(() => _rawPanelOpen = true),
              icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
            ),
            const SizedBox(height: 8),
            const RotatedBox(
              quarterTurns: 1,
              child: Text(
                'Raw material',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final part = _livePart;
    if (part?.id != _rawPartId) {
      _rawPartId = part?.id;
      _rawEditing = false;
    }
    if (part?.id != _routeForPartId) {
      _routeForPartId = part?.id;
      _route = null;
      final id = part?.id;
      if (id != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_loadRoute(id)));
      }
    }
    final route = _route;
    final baseline = part?.penPaperBaseline ?? PenPaperBaseline.createDefault();
    final panel = MasterDataPanel(
      // Bumped on Cancel, so the edits are thrown away with the old state.
      key: ValueKey<String>('raw_${part?.id ?? 0}_$_rawEpoch'),
      baseline: baseline,
      embedded: true,
      showHeader: false,
      readOnly: part == null || !_rawEditing,
      // The saved part's own name: the Output row of Material data and the
      // review are about the part, not whichever row the cursor is on.
      itemName: part == null
          ? _partLabelNow
          : (part.displayName.trim().isEmpty ? part.name : part.displayName),
      // A new version is a new route id, so a baseline recorded on the old
      // one is flagged to be re-recorded.
      pipelineId: route != null ? 'route:${route.id}' : part?.defaultPipelineId,
      pipelineName: route != null
          ? 'Route v${route.version} · '
              '${route.steps.map((step) => step.stageName).join(' → ')}'
          : part?.defaultPipelineName ?? '',
      stageNodes: [
        for (final step in route?.steps ?? const <RouteStep>[])
          PipelineStageNode(
            id: 'route-step-${step.seq}',
            name: step.stageName,
            stageIndex: step.seq - 1,
          ),
      ],
      unattachedHint: 'No route yet — use Author route below, so stages and '
          'yields have a route to describe.',
      parts: _plannableParts(),
      // Alloy and the sheet's material are one thing: the panel shows the
      // part's Alloy cell and is not given a picker of its own.
      alloy: _alloyNow,
      // Grade is a property column like any other; the panel shows it.
      grade: _propertyNow('grade'),
      // One thickness in two places: the part's Thickness cell, edited from
      // either side.
      thickness: _cellNow(SheetBindsTo.variation('Thickness')),
      onThicknessChanged: _setThickness,
      saving: _rawSaving,
      onEdit: part != null && !_rawEditing
          ? () => setState(() => _rawEditing = true)
          : null,
      onSave: (saved) => unawaited(_saveRawSheet(saved)),
      onCancel: _rawEditing
          ? () => setState(() {
                _rawEditing = false;
                _rawEpoch += 1;
              })
          : null,
    );

    return Container(
      key: const ValueKey<String>('raw_panel'),
      width: _rawPanelWidth,
      decoration: const BoxDecoration(
        color: SoftErpTheme.cardSurface,
        border: Border(left: BorderSide(color: SoftErpTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SheetStyle.cardPadding, 10, 8, 6),
            child: Row(
              children: [
                SheetStyle.iconTile(Icons.grid_on_rounded),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Raw material', style: SheetStyle.sectionTitle),
                ),
                if (part != null && !_rawEditing)
                  OutlinedButton.icon(
                    key: const ValueKey<String>('raw_edit'),
                    onPressed: () => setState(() => _rawEditing = true),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit', style: TextStyle(fontSize: 14)),
                  ),
                IconButton(
                  key: const ValueKey<String>('raw_panel_close'),
                  tooltip: 'Fold the raw sheet panel',
                  onPressed: () => setState(() => _rawPanelOpen = false),
                  icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
                ),
              ],
            ),
          ),
          if (part == null)
            const Padding(
              padding: EdgeInsets.fromLTRB(SheetStyle.cardPadding, 0, SheetStyle.cardPadding, 8),
              child: Text(
                'Opens once the part is saved — the raw sheet is stored on the part.',
                style: SheetStyle.hint,
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: part == null
                // Drawn so the shape of the step is visible, but not usable
                // until there is a part to store it on.
                ? IgnorePointer(child: Opacity(opacity: 0.5, child: panel))
                : panel,
          ),
        ],
      ),
    );
  }

  /// Reads [partId]'s route — the active one, else the newest draft, which is
  /// the order the service answers in. A build with no route service, or a
  /// read that fails, leaves the part unrouted rather than throwing.
  Future<void> _loadRoute(int partId) async {
    PartRoute? route;
    try {
      final routes = await context.read<ProcessRouteService>().routesFor(partId);
      route = routes.firstOrNull;
    } catch (_) {
      route = null;
    }
    if (!mounted || _livePart?.id != partId) return;
    setState(() => _route = route);
  }

  Future<void> _saveRawSheet(PenPaperBaseline baseline) async {
    final part = _livePart;
    if (part == null) return;
    if (_rawSaving) return;
    final items = context.read<ItemsProvider>();
    setState(() => _rawSaving = true);
    // A thickness typed in the panel went into the part's row; it is saved
    // with the plan rather than waiting for the cursor to leave the row.
    // commitRow turns an edited saved row into an update of its part.
    final sheet = _controller.groupItemController;
    if (sheet.draft.isDirtySinceSave) {
      await _controller.commitRow(sheet.row);
      if (!mounted) return;
    }
    final saved = await items.setItemPenPaperBaseline(part.id, baseline);
    if (!mounted) return;
    setState(() {
      _rawSaving = false;
      // A failed save stays in edit mode, so what was typed is not lost.
      if (saved != null) _rawEditing = false;
    });
    _toast(
      saved == null
          ? (items.errorMessage ?? 'The raw sheet did not save.')
          : 'Raw material saved on ${saved.displayName.isEmpty ? saved.name : saved.displayName}.',
      isError: saved == null,
    );
  }

  /// Parts with a blank size, this one first — what the cut plan can be laid
  /// out for. The items screen offers the same list.
  List<SheetPart>? _plannableCache;
  List<ItemDefinition>? _plannableFrom;
  int? _plannableFor;

  List<SheetPart> _plannableParts() {
    final current = _livePart?.id;
    // Built on every rebuild — every keystroke — from the whole catalogue.
    // The provider swaps its list on any change, so identity says when.
    final all = context.read<ItemsProvider>().items;
    final cached = _plannableCache;
    if (cached != null &&
        identical(all, _plannableFrom) &&
        current == _plannableFor) {
      return cached;
    }
    _plannableFrom = all;
    _plannableFor = current;
    final parts = [
      for (final item in all)
        if (!item.isArchived && item.hasBlankSize)
          SheetPart(
            id: item.id,
            name: item.displayName.trim().isEmpty ? item.name : item.displayName,
            widthMm: item.blankWidthMm,
            heightMm: item.blankHeightMm,
          ),
    ];
    parts.sort((a, b) {
      if (a.id == current) return -1;
      if (b.id == current) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return _plannableCache = parts;
  }

  Future<void> _loadRailPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final collapsed = prefs.getBool(_railPrefKey) ?? false;
      if (mounted && collapsed != _railCollapsed) {
        setState(() => _railCollapsed = collapsed);
      }
    } catch (_) {
      // No preferences store (a test host): the rail simply starts open.
    }
  }

  Future<void> _setRailCollapsed(bool collapsed) async {
    setState(() => _railCollapsed = collapsed);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_railPrefKey, collapsed);
    } catch (_) {}
  }

  /// The rail folded to a strip of section icons: hover for the name, tap to
  /// go there, the chevron at the top opens it again.
  Widget _collapsedRail() {
    final sections = [
      for (final section in _sections)
        if (section.id != 'client_vendor' || _controller.isExternal) section,
    ];
    return Container(
      key: const ValueKey<String>('rail_collapsed'),
      width: 56,
      decoration: const BoxDecoration(
        color: SoftErpTheme.cardSurface,
        border: Border(right: BorderSide(color: SoftErpTheme.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          IconButton(
            key: const ValueKey<String>('rail_expand'),
            tooltip: 'Open the side column',
            onPressed: () => _setRailCollapsed(false),
            icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
          ),
          const Divider(height: 16),
          for (final section in sections)
            Tooltip(
              message: section.title,
              child: IconButton(
                key: ValueKey<String>('rail_icon_${section.id}'),
                onPressed: () => _goTo(section.id),
                isSelected: _controller.activeSection == section.id,
                icon: Icon(
                  section.icon,
                  color: _controller.activeSection == section.id
                      ? SoftErpTheme.accent
                      : SoftErpTheme.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pinnedPart(),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: _tree(),
          ),
        ),
      ],
    );
  }


  static const List<String> _sectionIds = [
    'group_item',
    'client_vendor',
    'die_master',
    'machine_master',
  ];

  /// Every section on one page, nested like a file tree. The nesting is the
  /// part's own (loaded from it, re-arranged by drag and drop or the indent
  /// buttons) and it is data: Die under Client links that client to these
  /// dies, Machine under Die links the machines to the dies, and so on.
  ///
  /// Client / Vendor is left out for an in-house part; whatever was nested
  /// under it shows under its parent, so the tree never has a gap.
  bool _visible(String id) => id != 'client_vendor' || _controller.isExternal;

  /// Where [id] shows: its parent, or the nearest visible ancestor.
  String _shownParentOf(String id) {
    var at = _parentOf[id] ?? 'group_item';
    while (at != 'group_item' && !_visible(at)) {
      at = _parentOf[at] ?? 'group_item';
    }
    return at;
  }

  List<String> _childrenOf(String id) => [
        for (final child in _sectionIds)
          if (child != 'group_item' && _visible(child) && _shownParentOf(child) == id)
            child,
      ];

  /// [id] and everything nested under it.
  Set<String> _subtree(String id) {
    final out = <String>{id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final child in _sectionIds) {
        if (child == 'group_item' || out.contains(child)) continue;
        if (out.contains(_parentOf[child])) {
          out.add(child);
          grew = true;
        }
      }
    }
    return out;
  }

  bool _canNest(String child, String parent) =>
      child != 'group_item' &&
      child != parent &&
      _parentOf[child] != parent &&
      !_subtree(child).contains(parent);

  void _nest(String child, String parent) {
    if (!_canNest(child, parent)) return;
    setState(() {
      _parentOf = {..._parentOf, child: parent};
      _collapsed.remove(parent);
    });
  }

  /// One level out: becomes a sibling of its parent.
  void _outdent(String id) {
    final parent = _parentOf[id];
    if (parent == null || parent == 'group_item') return;
    _nest(id, _parentOf[parent] ?? 'group_item');
  }

  /// One level in: becomes a child of the sibling just above it.
  String? _siblingAbove(String id) {
    final siblings = _childrenOf(_shownParentOf(id));
    final at = siblings.indexOf(id);
    return at > 0 ? siblings[at - 1] : null;
  }

  /// Follows the part's stored nesting, unless a change is waiting to be
  /// saved here.
  ///
  /// Loaded once per part, it used to be: a nesting changed in another window
  /// never showed, and saving this one's then quietly put the old one back.
  void _syncTreeFromPart() {
    final part = _livePart;
    if (part == null || _treeDirty) return;
    final stored = {..._defaultTree, ...?part.sectionTree};
    if (part.id == _treeLoadedFor && mapEquals(stored, _savedTree)) return;
    _treeLoadedFor = part.id;
    _parentOf = Map<String, String>.of(stored);
    _savedTree = Map<String, String>.of(stored);
  }

  Future<void> _saveTree() async {
    final part = _livePart;
    if (part == null || _savingTree) return;
    setState(() => _savingTree = true);
    final items = context.read<ItemsProvider>();
    final saved = await items.saveSectionTree(part.id, Map.of(_parentOf));
    if (!mounted) return;
    setState(() {
      _savingTree = false;
      if (saved != null) {
        _savedTree = Map<String, String>.of(_parentOf);
        _treeLoadedFor = saved.id;
      }
    });
    _toast(
      saved == null
          ? (items.errorMessage ?? 'The nesting did not save.')
          : 'Nesting saved — the part\'s records are re-linked to match.',
      isError: saved == null,
    );
  }

  Widget _tree() {
    _syncTreeFromPart();
    final nodes = <Widget>[];
    void visit(String id, int depth, List<bool> continues, bool isLast) {
      final collapsed = _collapsed.contains(id);
      nodes.add(_TreeNode(
        depth: depth,
        continues: continues,
        isLast: isLast,
        child: _dropTarget(id, _sectionFor(id, collapsed: collapsed)),
      ));
      // Folding a section folds only that section: what is nested under it
      // stays on the page.
      final kids = _childrenOf(id);
      for (var i = 0; i < kids.length; i += 1) {
        visit(
          kids[i],
          depth + 1,
          // Below the root, a line keeps running for every ancestor that still
          // has a sibling to come — the `│` in a file tree.
          depth == 0 ? const [] : [...continues, !isLast],
          i == kids.length - 1,
        );
      }
    }

    visit('group_item', 0, const [], true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_treeDirty) _treeDirtyBar(),
        ...nodes,
      ],
    );
  }

  Widget _treeDirtyBar() {
    final saved = _livePart != null;
    return Container(
      key: const ValueKey<String>('tree_dirty_bar'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: SoftErpTheme.warningBg,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(color: SoftErpTheme.warningBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_tree_outlined, size: 18, color: SoftErpTheme.warningText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              saved
                  ? 'Nesting changed — save to re-link this part\'s client, dies and machines to match.'
                  : 'Nesting changed — it is saved with the part.',
              style: const TextStyle(fontSize: 14, color: SoftErpTheme.warningText),
            ),
          ),
          TextButton(
            key: const ValueKey<String>('tree_undo'),
            onPressed: () => setState(() => _parentOf = Map.of(_savedTree)),
            child: const Text('Undo', style: TextStyle(fontSize: 14)),
          ),
          if (saved)
            FilledButton.icon(
              key: const ValueKey<String>('tree_save'),
              onPressed: _savingTree ? null : _saveTree,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save nesting', style: TextStyle(fontSize: 14)),
            ),
        ],
      ),
    );
  }

  /// Every section is somewhere another can be dropped — "nest under this".
  Widget _dropTarget(String id, Widget child) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => _canNest(details.data, id),
      onAcceptWithDetails: (details) => _nest(details.data, id),
      builder: (context, candidates, rejected) {
        final hovering = candidates.isNotEmpty;
        final refused = rejected.isNotEmpty;
        if (!hovering && !refused) return child;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
            border: Border.all(
              color: hovering ? SoftErpTheme.accent : SoftErpTheme.dangerText,
              width: 2,
            ),
          ),
          child: child,
        );
      },
    );
  }

  void _toggle(String id) => setState(() {
        if (!_collapsed.remove(id)) _collapsed.add(id);
      });

  /// The rail is a table of contents: open the section (and every one it is
  /// nested in) and bring it into view.
  void _goTo(String id) {
    // A folded section no longer hides what is nested under it, so only the
    // one asked for needs opening.
    setState(() => _collapsed.remove(id));
    _controller.setActiveSection(id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _sectionKeys[id]?.currentContext;
      if (target == null || !mounted) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  // --- per-section edit / save / clear ---------------------------------------

  Future<void> _clearSection(String id) async {
    final part = _livePart;
    final (title, detail) = switch (id) {
      'client_vendor' => (
          'Clear who this part was developed for?',
          'Removes the company, the quotation and the people ticked on this part. '
              'The company and its people stay in the clients master.',
        ),
      'die_master' => (
          'Take every die off this part?',
          'The dies stay in the die master — only their link to this part goes.',
        ),
      _ => (
          'Take every machine off this part?',
          'The machines stay in the machine master. The route is left as it is.',
        ),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 17)),
        content: Text(detail, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep', style: TextStyle(fontSize: 14)),
          ),
          FilledButton(
            key: const ValueKey<String>('section_clear_confirm'),
            style: FilledButton.styleFrom(backgroundColor: SoftErpTheme.dangerText),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    String? error;
    if (id == 'client_vendor') {
      if (part == null) {
        _controller.clearDeal();
      } else {
        final items = context.read<ItemsProvider>();
        final saved = await items.setItemDevelopedFor(part.id, DevelopedFor.empty);
        if (!mounted) return;
        if (saved == null) {
          error = items.errorMessage ?? 'That did not clear.';
        } else {
          _controller.dealClearedOnServer();
        }
      }
    } else if (id == 'die_master') {
      if (part == null) {
        setState(_stagedDies.clear);
      } else {
        error = await _setDies(const []);
      }
    } else {
      if (part == null) {
        setState(_stagedMachines.clear);
      } else {
        error = await _setMachines(const []);
      }
    }
    if (!mounted) return;
    _toast(error ?? 'Cleared.', isError: error != null);
  }

  /// What a folded section shows instead of its body: what was entered, on
  /// one line.
  String _sectionSummary(String id) {
    String join(Iterable<String> parts) =>
        parts.where((p) => p.trim().isNotEmpty).join('  ·  ');
    switch (id) {
      case 'client_vendor':
        final company = _controller.dealPartyName;
        if (company.isEmpty) return 'No company chosen yet';
        final deal = _controller.clientVendorController;
        final q = deal.sheetDef.columnBoundTo(SheetBindsTo.developedForQuotation);
        final quotation = q == null ? '' : (deal.draft.get(q.id)?.textValue ?? '').trim();
        final people = _controller.peopleController;
        final tick = people.sheetDef.columnBoundTo(SheetBindsTo.personDealtWith);
        final name = people.sheetDef.columnBoundTo(SheetBindsTo.personName);
        final ticked = <String>[
          for (final d in people.drafts)
            if (tick != null && name != null && d.get(tick.id)?.intValue == 1)
              (d.get(name.id)?.textValue ?? '').trim(),
        ].where((n) => n.isNotEmpty).toList();
        return join([
          company,
          if (quotation.isNotEmpty) '₹$quotation',
          if (ticked.isNotEmpty) 'Dealt with ${ticked.join(', ')}',
        ]);
      case 'die_master':
        final codes = [
          for (final d in _livePart?.dies ?? const <ItemDieLink>[]) d.toolCode,
          for (final d in _stagedDies) '${d.toolCode} (held)',
        ].where((c) => c.trim().isNotEmpty).toList();
        if (codes.isEmpty) return 'No dies yet';
        return '${codes.length} ${codes.length == 1 ? 'die' : 'dies'}: ${codes.join(', ')}';
      case 'machine_master':
        final names = [
          for (final m in _livePart?.machines ?? const <ItemMachineLink>[])
            m.name.isNotEmpty ? m.name : m.assetId,
          for (final m in _stagedMachines)
            '${m.name.isNotEmpty ? m.name : m.assetId} (held)',
        ].where((n) => n.trim().isNotEmpty).toList();
        if (names.isEmpty) return 'No machines yet';
        return '${names.length} ${names.length == 1 ? 'machine' : 'machines'}: ${names.join(', ')}';
      default:
        final sheet = _controller.groupItemController.sheetDef;
        final draft = _controller.groupItemController.draft;
        final nameColumn = sheet.columnBoundTo(SheetBindsTo.name) ?? sheet.itemColumn;
        final path = nameColumn == null
            ? ''
            : SheetEngine.groupPathString(sheet, draft, nameColumn.id);
        final properties = [
          for (final column in sheet.columns)
            if (SheetBindsTo.isVariation(column.bindsTo))
              (draft.get(column.id)?.optionLabel ?? draft.get(column.id)?.textValue ?? '').trim(),
        ].where((v) => v.isNotEmpty);
        final summary = join([path, _partCodeNow, ...properties]);
        return summary.isEmpty ? 'Nothing entered yet' : summary;
    }
  }

  /// The header controls of a section: move it, edit it, clear it.
  List<Widget> _sectionActions(String id, String heading) {
    final root = id == 'group_item';
    final above = root ? null : _siblingAbove(id);
    final canOutdent = !root && (_parentOf[id] ?? 'group_item') != 'group_item';
    Widget action({
      required String key,
      required IconData icon,
      required String tip,
      VoidCallback? onPressed,
      Color? color,
    }) =>
        IconButton(
          key: ValueKey<String>(key),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          onPressed: onPressed,
          icon: Icon(icon, size: 20, color: onPressed == null ? null : color),
        );

    return [
      if (!root) ...[
        action(
          key: 'section_outdent_$id',
          icon: Icons.format_indent_decrease_rounded,
          tip: canOutdent ? 'Move $heading one level out' : 'Already directly under the part',
          onPressed: canOutdent ? () => _outdent(id) : null,
        ),
        action(
          key: 'section_indent_$id',
          icon: Icons.format_indent_increase_rounded,
          tip: above == null
              ? 'Nothing above it at this level to nest under'
              : 'Nest $heading under the section above',
          onPressed: above == null ? null : () => _nest(id, above),
        ),
      ],
      action(
        key: 'section_clear_$id',
        icon: Icons.delete_outline_rounded,
        tip: root ? 'The part itself is deleted from the Items list' : 'Clear $heading for this part',
        onPressed: root ? null : () => _clearSection(id),
        color: SoftErpTheme.dangerText,
      ),
    ];
  }

  Widget _sectionFor(String id, {required bool collapsed}) {
    switch (id) {
      case 'client_vendor':
        return _section(
          id: 'client_vendor',
          icon: Icons.storefront_rounded,
          heading: 'Client / Vendor',
          collapsed: collapsed,
          trailing: MarginHealthBadge(
            quotation: _moneyBoundTo(SheetBindsTo.developedForQuotation),
            cost: _moneyBoundTo(SheetBindsTo.developedForCost),
          ),
          child: _partySheet(),
        );
      case 'die_master':
        return _section(
          id: 'die_master',
          icon: Icons.precision_manufacturing_rounded,
          heading: 'Die Process Master',
          collapsed: collapsed,
          child: _dieSheet(),
        );
      case 'machine_master':
        return _section(
          id: 'machine_master',
          icon: Icons.settings_suggest_rounded,
          heading: 'Machines & Routing',
          collapsed: collapsed,
          child: _machinesAndRouting(),
        );
      default:
        return _section(
          id: 'group_item',
          icon: Icons.inventory_2_rounded,
          heading: 'Item Master',
          collapsed: collapsed,
          trailing: _identityChip(),
          child: _groupItemSheet(),
        );
    }
  }

  /// The part, kept in view whichever section the rail is on.
  ///
  /// Switching to Dies has to keep saying which part they belong to. It also
  /// retires the strip's own pinned badge, which faked a frozen first column by
  /// jumping the scroll padding 0 to 190 mid-scroll and shoving every table
  /// sideways.
  Widget _pinnedPart() {
    final sheet = _controller.groupItemController.sheetDef;
    final draft = _controller.groupItemController.draft;
    final nameColumn =
        sheet.columnBoundTo(SheetBindsTo.name) ?? sheet.itemColumn;
    final value = nameColumn == null ? null : draft.get(nameColumn.id);
    final name = value?.optionLabel ?? value?.textValue;
    final path = nameColumn == null
        ? ''
        : SheetEngine.groupPathString(sheet, draft, nameColumn.id);
    final codeColumn = sheet.columnBoundTo(SheetBindsTo.partCode);
    final code =
        codeColumn == null ? null : draft.get(codeColumn.id)?.textValue;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: const BoxDecoration(
        color: SoftErpTheme.cardSurface,
        border: Border(bottom: BorderSide(color: SoftErpTheme.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _controller.isSaved
                  ? SoftErpTheme.successBg
                  : SoftErpTheme.warningBg,
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
            ),
            child: Text(
              _controller.isSaved
                  ? 'SAVED #${_controller.savedItemId}'
                  : 'NEW RECORD',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _controller.isSaved
                    ? SoftErpTheme.successText
                    : SoftErpTheme.warningText,
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (path.isNotEmpty) ...[
            Flexible(
              child: Text(
                path,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text('›', style: TextStyle(color: SoftErpTheme.textMuted)),
            ),
          ],
          Flexible(
            child: Text(
              (name == null || name.trim().isEmpty) ? 'Unnamed' : name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: (name == null || name.trim().isEmpty)
                    ? SoftErpTheme.textMuted
                    : SoftErpTheme.textPrimary,
              ),
            ),
          ),
          if (code != null && code.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text(
              code,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: SoftErpTheme.accent,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Adds a top-level property to the sheet.
  ///
  /// Properties ARE the variation tree, so a column added here becomes a
  /// top-level property on every part the sheet writes — and is folded into
  /// the part code beside it, which is why a new one lands before the code
  /// rather than after.
  Future<void> _addProperty() async {
    final result = await showDialog<_NewProperty>(
      context: context,
      builder: (ctx) => const _AddPropertyDialog(),
    );

    if (!mounted || result == null) return;
    final provider = _sheetProps;
    if (provider == null) {
      // No store in this host (a test harness): a column for this session.
      _controller.groupItemController.addPropertyColumn(
        result.name,
        kind: _columnKindFor(result.kind),
      );
      return;
    }
    // Saved first, so the column is everyone's before anything is typed in
    // it. A name already on the sheet answers with that column.
    final saved = await provider.create(
      name: result.name,
      kind: result.kind,
      options: result.options,
    );
    if (!mounted) return;
    if (saved == null) {
      _toast(provider.errorMessage ?? 'The column was not added.', isError: true);
      return;
    }
    _syncPropertyColumns();
    await _controller.loadReferenceData();
  }

  // --- the sheet's stored property columns --------------------------------

  static String _keyOf(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  /// A list and a free-text property are both a dropdown that takes a new
  /// value: what is typed joins the list for everyone, so the two differ only
  /// in what was picked when the column was added.
  static ColumnKind _columnKindFor(String kind) => switch (kind) {
        'material' => ColumnKind.material,
        'gauge' => ColumnKind.gauge,
        _ => ColumnKind.list,
      };

  /// The stored column [column] is, or null for one that is not stored
  /// (Alloy, Thickness, the identity columns).
  SheetProperty? _storedFor(ColumnDef column) {
    final binds = column.bindsTo;
    if (!SheetBindsTo.isVariation(binds)) return null;
    return _sheetProps?.byKey(SheetBindsTo.variationProperty(binds!));
  }

  /// Puts the stored columns on the sheet and takes off the ones removed.
  ///
  /// A column somebody has typed into and not saved stays until it is saved,
  /// rather than vanishing under them because another window removed it.
  ///
  /// A column it holds goes on even before a full read has succeeded — one
  /// just added here, say. Only removal waits for a successful read: an
  /// empty list that merely failed to load must not take columns off.
  void _syncPropertyColumns() {
    final provider = _sheetProps;
    if (provider == null) return;
    final sheet = _controller.groupItemController;
    final onSheet = <String, ColumnDef>{
      for (final column in sheet.sheetDef.columns)
        if (SheetBindsTo.isVariation(column.bindsTo))
          _keyOf(SheetBindsTo.variationProperty(column.bindsTo!)): column,
    };
    final stored = [...provider.properties]
      ..sort((a, b) => a.position.compareTo(b.position));
    for (final property in stored) {
      final existing = onSheet[property.key];
      if (existing == null) {
        sheet.addColumn(
          label: property.name,
          kind: _columnKindFor(property.kind),
          bindsTo: SheetBindsTo.variation(property.propertyName),
        );
      } else if (existing.label != property.name) {
        sheet.renameColumn(existing.id, property.name);
      }
    }
    final keep = {for (final property in stored) property.key};
    if (!provider.isLoaded) {
      _storedKeys = _storedKeys.union(keep);
      return;
    }
    for (final key in _storedKeys.difference(keep)) {
      final column = onSheet[key];
      if (column == null || _hasUnsavedTyping(column)) continue;
      sheet.removeColumn(column.id);
    }
    _storedKeys = keep;
  }

  bool _hasUnsavedTyping(ColumnDef column) {
    final sheet = _controller.groupItemController;
    for (var row = 0; row < sheet.rowCount; row += 1) {
      final draft = sheet.draftAt(row);
      final value = draft.get(column.id);
      if (value != null && value.isNotEmpty && draft.isDirtySinceSave) {
        return true;
      }
    }
    return false;
  }

  void _onSheetPropsChanged() {
    if (!mounted) return;
    _syncPropertyColumns();
    _onMastersChanged();
  }

  void _onOptionAdded(ColumnDef column, String label) {
    final property = _storedFor(column);
    if (property == null) return;
    unawaited(_sheetProps!.addOption(property.id, label));
  }

  /// The delete button on a value in a stored column's dropdown.
  ///
  /// The dropdown is the column's list plus every value a saved part
  /// carries, so a value still on a part cannot be deleted — it would be back
  /// on the next read. Drawn disabled, saying how many parts hold it.
  OptionRemoval? _optionRemovalFor(ColumnDef column, ColumnOption option) {
    final property = _storedFor(column);
    final provider = _sheetProps;
    if (property == null || provider == null) return null;
    // Gauges and materials are masters of their own, not this list.
    if (column.kind == ColumnKind.gauge || column.kind == ColumnKind.material) {
      return null;
    }
    final wanted = _keyOf(option.label);
    final parts = context
        .read<ItemsProvider>()
        .items
        .where((item) => !item.isArchived)
        .where((item) {
          final value =
              ItemSheetBinding.propertyValueOf(item, property.propertyName);
          return value != null && _keyOf(value) == wanted;
        })
        .length;
    if (parts > 0) {
      return OptionRemoval.blocked(
        'On $parts saved part${parts == 1 ? '' : 's'} — change '
        '${parts == 1 ? 'it' : 'them'} first',
      );
    }
    return OptionRemoval(() async {
      final sure = await showConfirmDialog(
        context,
        title: 'Delete “${option.label}”?',
        message: 'It leaves the ${column.label} list for everyone.',
        confirmLabel: 'Delete',
      );
      if (!sure || !mounted) return false;
      final saved = await provider.removeOption(property.id, option.label);
      if (!mounted) return false;
      if (saved == null) {
        _toast(provider.errorMessage ?? 'The option was not deleted.', isError: true);
        return false;
      }
      return true;
    });
  }

  Future<bool> _confirmRemoveColumn(ColumnDef column) async {
    if (_storedFor(column) == null) return true;
    return showConfirmDialog(
      context,
      title: 'Remove ${column.label} from the sheet?',
      message: 'It goes for everyone, with its list of options. Parts keep '
          'the values they were saved with.',
      confirmLabel: 'Remove',
    );
  }

  void _onColumnRemoved(ColumnDef column) {
    final provider = _sheetProps;
    final property = _storedFor(column);
    if (provider == null || property == null) return;
    _storedKeys = {..._storedKeys}..remove(property.key);
    unawaited(() async {
      final done = await provider.remove(property.id);
      if (!done && mounted) {
        _toast(provider.errorMessage ?? 'The column was not removed.', isError: true);
      }
    }());
  }

  void _onColumnRenamed(ColumnDef column, String label) {
    final property = _storedFor(column);
    if (property == null || property.name == label) return;
    unawaited(_sheetProps!.rename(property.id, label));
  }

  Future<void> _editOptions(ColumnDef column) async {
    final property = _storedFor(column);
    final provider = _sheetProps;
    if (property == null || provider == null) return;
    final result = await showDialog<_NewProperty>(
      context: context,
      builder: (ctx) => _AddPropertyDialog(editing: property),
    );
    if (!mounted || result == null) return;
    final saved = await provider.replaceOptions(property.id, result.options);
    if (!mounted) return;
    if (saved == null) {
      _toast(provider.errorMessage ?? 'The options were not saved.', isError: true);
      return;
    }
    await _controller.loadReferenceData();
  }

  /// The part this screen is working on, as stored — null until it is saved.
  ///
  /// The die and machine sections key everything off this: with no part they
  /// hold what you enter and write it once the part exists.
  ItemDefinition? get _livePart {
    final id = _controller.savedItemId;
    if (id == null) return null;
    for (final item in context.read<ItemsProvider>().items) {
      if (item.id == id) return item;
    }
    return null;
  }

  String get _partCodeNow {
    final sheet = _controller.groupItemController.sheetDef;
    final column = sheet.columnBoundTo(SheetBindsTo.partCode);
    if (column == null) return '';
    return _controller.groupItemController.draft.get(column.id)?.textValue ?? '';
  }

  /// The part's Alloy as the sheet shows it now — typed or picked, saved or
  /// not — so the raw sheet panel never names a different alloy.
  String get _alloyNow => _cellNow(SheetBindsTo.variation('Alloy'));

  /// What the cursor row's cell bound to [binds] holds now, saved or not.
  String _cellNow(String binds) {
    final column = _controller.groupItemController.sheetDef.columnBoundTo(
      binds,
    );
    if (column == null) return '';
    final value = _controller.groupItemController.draft.get(column.id);
    return (value?.optionLabel ?? value?.textValue ?? '').trim();
  }

  /// The cursor row's value for the property column called [key] (any case),
  /// or empty when there is no such column or nothing in it.
  String _propertyNow(String key) {
    for (final column in _controller.groupItemController.sheetDef.columns) {
      final binds = column.bindsTo;
      if (!SheetBindsTo.isVariation(binds)) continue;
      if (_keyOf(SheetBindsTo.variationProperty(binds!)) != _keyOf(key)) {
        continue;
      }
      return _cellNow(binds);
    }
    return '';
  }

  /// A thickness typed in the raw material panel, into the part's Thickness
  /// cell: the gauge option itself when it is one ("23 Gauge"), else the
  /// measurement as text, the way a typed thickness is kept.
  void _setThickness(String label) {
    final sheet = _controller.groupItemController;
    final column = sheet.sheetDef.columnBoundTo(
      SheetBindsTo.variation('Thickness'),
    );
    if (column == null) return;
    if (label.isEmpty) {
      sheet.updateValue(column.id, CellValue(columnId: column.id));
      return;
    }
    final wanted = label.toLowerCase();
    final option = sheet.options
        .where((o) => o.columnId == column.id && o.label.toLowerCase() == wanted)
        .firstOrNull;
    if (option != null) {
      sheet.setOption(column.id, option);
      return;
    }
    sheet.updateValue(
      column.id,
      CellValue(columnId: column.id, optionLabel: label),
    );
  }

  String get _partLabelNow {
    final sheet = _controller.groupItemController.sheetDef;
    final column = sheet.columnBoundTo(SheetBindsTo.name) ?? sheet.itemColumn;
    if (column == null) return 'this part';
    final value = _controller.groupItemController.draft.get(column.id);
    final name = value?.optionLabel ?? value?.textValue;
    return (name == null || name.trim().isEmpty) ? 'this part' : name;
  }

  /// The floor's die sheet, as it already exists.
  ///
  /// `PartDieSection` is migrations 048's eleven columns column for column —
  /// PO date, made by, type, liner size, code, sets, store area, rack — with a
  /// die code derived from the part's own and a collision-avoiding suggestion
  /// behind it. It was written for the quick-entry dialog and mounted nowhere
  /// else; this section was a note saying it was not wired.
  Widget _dieSheet() {
    return PartDieSection(
      // The section card is the frame here; the die list draws its own only
      // where it stands alone, in the quick-entry dialog.
      framed: false,
      part: _livePart,
      partCode: _partCodeNow,
      partLabel: _partLabelNow,
      busy: _controller.isSavingNow,
      staged: _stagedDies,
      onStage: (draft) => setState(() => _stagedDies.add(draft)),
      onUnstage: (index) => setState(() => _stagedDies.removeAt(index)),
      onDiesChanged: _setDies,
    );
  }

  Widget _machinesAndRouting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PartMachineSection(
          framed: false,
          part: _livePart,
          partCode: _partCodeNow,
          partLabel: _partLabelNow,
          busy: _controller.isSavingNow,
          staged: _stagedMachines,
          onStage: (draft) => setState(() => _stagedMachines.add(draft)),
          onUnstage: (index) => setState(() => _stagedMachines.removeAt(index)),
          onMachinesChanged: _setMachines,
        ),
        const SizedBox(height: 20),
        _routing(),
      ],
    );
  }

  /// Dies and machines are written as two calls, not one.
  ///
  /// Each list is a full replace on the item, so sending only one of them in a
  /// single write would clear the other.
  Future<String?> _setDies(List<String> dieIds) async {
    final part = _livePart;
    if (part == null) return 'Save the part first.';
    return _setDiesOn(part.id, dieIds);
  }

  Future<String?> _setDiesOn(int partId, List<String> dieIds) async {
    final items = context.read<ItemsProvider>();
    final saved = await items.setItemLinks(partId, dieIds: dieIds);
    return saved == null ? (items.errorMessage ?? 'That did not save.') : null;
  }

  Future<String?> _setMachines(List<String> machineIds) async {
    final part = _livePart;
    if (part == null) return 'Save the part first.';
    return _setMachinesOn(part.id, machineIds);
  }

  Future<String?> _setMachinesOn(int partId, List<String> machineIds) async {
    final items = context.read<ItemsProvider>();
    final saved = await items.setItemLinks(partId, machineIds: machineIds);
    return saved == null ? (items.errorMessage ?? 'That did not save.') : null;
  }

  /// The identity chip. Shows only what the sheet holds — the prototype's read
  /// `activeItem?.variantCode ?? 'SADPB2248'`, printing a variant code for a
  /// part that had none.
  Widget _identityChip() {
    final sheet = _controller.groupItemController.sheetDef;
    final column = sheet.columnBoundTo(SheetBindsTo.partCode);
    final code = column == null
        ? null
        : _controller.groupItemController.draft.get(column.id)?.textValue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Identity: ',
              style: TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary)),
          Text(
            (code == null || code.isEmpty) ? 'stamped on save' : code,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: (code == null || code.isEmpty)
                  ? SoftErpTheme.textMuted
                  : SoftErpTheme.accent,
            ),
          ),
        ],
      ),
    );
  }

  double? _moneyBoundTo(String binds) {
    final sheet = _controller.clientVendorController.sheetDef;
    final column = sheet.columnBoundTo(binds);
    if (column == null) return null;
    final value = _controller.clientVendorController.draft.get(column.id);
    if (value == null) return null;
    // Rupees as typed, paise included — the text is the figure, and intValue
    // is only there for a whole amount. Stripping to digits and dots read
    // "Rs. 85,000" as 0.85 (the dot of "Rs." led).
    return SheetEngine.parseMoney(value.textValue) ?? value.intValue?.toDouble();
  }

  Widget _groupItemSheet() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _rowToolbar(
          label: 'Parts on this sheet',
          count: _controller.groupItemController.rowCount,
          onAdd: () => _controller.groupItemController.addRow(),
          onRemove: _controller.groupItemController.rowCount > 1
              ? () => _controller.groupItemController.removeRow(
                    _controller.groupItemController.row,
                  )
              : null,
        ),
        const SizedBox(height: 8),
        // No fixed height: the strip is as tall as the rows it holds, so the
        // box cannot drift from the cells the way `96 + 50n` did against a
        // real 46px row.
        TableRowStrip(
          sheetDef: _controller.groupItemController.sheetDef,
          controller: _controller.groupItemController,
          selectedRowIndex: _controller.groupItemController.row,
          onRowSelected: _controller.groupItemController.selectRow,
          rowStatusBuilder: _photosOn ? _rowGutter : _rowStatus,
          gutterExtra: _photosOn ? _rowPhotoSize + 6 : 0,
          onAddPropertyColumn: _addProperty,
        ),
      ],
    );
  }

  /// Whether this app keeps photos (an [EntityPhotosProvider] is provided).
  bool get _photosOn {
    try {
      Provider.of<EntityPhotosProvider>(context, listen: false);
      return true;
    } on ProviderNotFoundException {
      return false;
    }
  }

  static const double _rowPhotoSize = 32;

  /// A part row's photo beside its status chip.
  Widget _rowGutter(int row) {
    final sheet = _controller.groupItemController;
    final id = sheet.draftAt(row).entityId;
    final part = id == null ? null : _partById(id);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MiniPhoto(
          owner: PhotoOwner.item,
          id: id?.toString(),
          size: _rowPhotoSize,
          what: 'part photo',
          fallbackUrl: part?.photoUrl,
          disabledReason: 'Save the part first to add its photo',
        ),
        const SizedBox(width: 2),
        SizedBox(width: 28, child: _rowStatus(row)),
      ],
    );
  }

  /// What a row's gutter chip says.
  ///
  /// Rows commit one at a time, so without this a typist cannot tell which of
  /// fifty rows landed — every other signal on screen describes the sheet.
  /// Each part row's own Save, or its Edit once saved.
  ///
  /// A row is still written when the cursor leaves it (catalogue at speed);
  /// this is the explicit way, and the only way to reopen a saved row: saved
  /// rows are closed — they show their values and take no input — until their
  /// Edit.
  Widget? _rowStatus(int row) {
    final sheet = _controller.groupItemController;
    final error = _controller.rowError(row);
    final saved = _controller.savedRows.contains(row);
    final locked = sheet.isRowLocked(row);
    Widget button({
      required String key,
      required IconData icon,
      required String tip,
      required Color color,
      VoidCallback? onPressed,
    }) =>
        Tooltip(
          message: tip,
          child: IconButton(
            key: ValueKey<String>(key),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            iconSize: 18,
            onPressed: onPressed,
            icon: Icon(icon, color: color),
          ),
        );

    // Deleted or archived (here or anywhere): there is nothing to edit, so
    // the row says why instead of offering an Edit that cannot save.
    if (_controller.isRowGone(row)) {
      return button(
        key: 'row_gone_$row',
        icon: Icons.block_rounded,
        tip: error ?? 'This part is no longer in the catalogue.',
        color: SoftErpTheme.textMuted,
      );
    }
    if (saved && locked) {
      final id = sheet.draftAt(row).entityId;
      return button(
        key: 'row_edit_$row',
        icon: Icons.edit_outlined,
        tip: 'Saved as item #$id — Edit',
        color: SoftErpTheme.accent,
        onPressed: () {
          sheet.setRowLocked(row, false);
          sheet.selectRow(row);
        },
      );
    }
    if (sheet.isRowBlank(row) && !saved) return null;
    return button(
      key: 'row_save_$row',
      icon: error != null ? Icons.error_outline_rounded : Icons.save_outlined,
      tip: error ?? (saved ? 'Save the changes to this part' : 'Save this part'),
      color: error != null ? SoftErpTheme.dangerText : SoftErpTheme.successText,
      onPressed: _controller.isSavingNow ? null : () => _saveRow(row),
    );
  }

  /// Archive for the part on the selected row. Drawn always, disabled with
  /// why when there is nothing to archive — the sheet could create and edit a
  /// part but never retire one, and "Remove row" only took it off the screen.
  Widget _archiveButton() {
    final sheet = _controller.groupItemController;
    final row = sheet.row;
    final id = sheet.draftAt(row).entityId;
    final String? why = id == null
        ? 'Select a saved part to archive it'
        : (_controller.isRowGone(row)
            ? _controller.rowError(row)
            : (_controller.isSavingNow ? 'Still saving' : null));
    return Tooltip(
      message: why ?? 'Archive item #$id — kept, restorable from the Items screen',
      child: OutlinedButton.icon(
        key: const ValueKey('archive_part_btn'),
        onPressed: why == null ? () => _archivePart(id!) : null,
        icon: const Icon(Icons.archive_outlined, size: 18),
        label: const Text('Archive part', style: TextStyle(fontSize: 14)),
      ),
    );
  }

  Future<void> _archivePart(int id) async {
    final label = _partCodeNow.trim().isEmpty ? 'this part' : _partCodeNow;
    final ok = await showConfirmDialog(
      context,
      title: 'Archive $label?',
      message: 'It leaves every picker and list but is kept, and can be '
          'restored from the Items screen.',
      confirmLabel: 'Archive',
    );
    if (!ok || !mounted) return;
    final items = context.read<ItemsProvider>();
    final done = await items.archiveItem(id);
    if (!mounted) return;
    _toast(
      done
          ? 'Archived $label.'
          : (items.errorMessage ?? 'The part could not be archived.'),
      isError: !done,
    );
  }

  /// One row's Save: write it, carry the held dies and machines and the
  /// nesting with it, then close it until its Edit.
  Future<void> _saveRow(int row) async {
    final sheet = _controller.groupItemController;
    if (row < 0 || row >= sheet.rowCount) return;
    final before = sheet.draftAt(row);
    final ok = await _controller.commitRow(row);
    if (!mounted) return;
    // Where that row is NOW: the index passed in can name a different row by
    // the time the save answers, and locking that one closed the wrong part.
    final at = ok
        ? (_controller.lastCommittedRow ?? -1)
        : sheet.indexOfDraft(before);
    if (ok) {
      final id = _committedPartId;
      if (id != null) _madeHere.add(id);
      await _flushStaged();
      if (mounted && _treeDirty) await _saveTree();
    }
    if (!mounted) return;
    final error = at < 0 ? null : _controller.rowError(at);
    // Saved — or already saved with nothing changed — closes the row. Not
    // while it holds an edit made during the save; that is still to write.
    if (at >= 0 &&
        error == null &&
        _controller.savedRows.contains(at) &&
        !sheet.draftAt(at).isDirtySinceSave) {
      sheet.setRowLocked(at, true);
    }
    setState(() {});
    _toast(error ?? _controller.statusBarMessage, isError: error != null);
  }

  /// The deal line's Save on a saved part: the deal travels with its part's
  /// row, so re-commit it.
  Future<bool> _saveDeal() async {
    final row = _controller.dealRow ?? _controller.groupItemController.row;
    await _handleSave();
    if (!mounted) return false;
    return _controller.rowError(row) == null;
  }

  String _pinnedPartName() {
    final sheet = _controller.groupItemController.sheetDef;
    final column = sheet.columnBoundTo(SheetBindsTo.name) ?? sheet.itemColumn;
    if (column == null) return '';
    final value = _controller.groupItemController.draft.get(column.id);
    return value?.optionLabel ?? value?.textValue ?? '';
  }

  /// The deal and the people at that company, as ordinary text fields. The
  /// spreadsheet cells here ate keystrokes (each rebuild re-selected the cell,
  /// so 85000 became 0) and were cramped pills; see [DealPeopleForm].
  Widget _partySheet() => DealPeopleForm(
        controller: _controller,
        partSaved: _livePart != null,
        onSaveDeal: _saveDeal,
      );

  Widget _routing() {
    if (_showRoutePanel) {
      return RouteCreationPanel(
        initialPartId: _controller.savedItemId,
        madeHereItemIds: _madeHere,
        onSaved: (record) {
          setState(() => _showRoutePanel = false);
          _toast('Route saved for ${record.title}.');
          final id = _livePart?.id;
          if (id != null) unawaited(_loadRoute(id));
        },
        onCancel: () => setState(() => _showRoutePanel = false),
      );
    }

    final hasPart = _controller.savedItemId != null;
    return Row(
      children: [
        Expanded(
          child: Text(
            hasPart
                ? 'This part can be routed through the process stages.'
                : 'Save the part first — a route attaches to a part, so there '
                    'is nothing to attach one to yet.',
            style: const TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
          ),
        ),
        const SizedBox(width: 12),
        // Drawn disabled with the reason rather than hidden: a control that
        // appears only once its precondition holds reads as a missing feature.
        Tooltip(
          message: hasPart
              ? 'Author the stage order for this part'
              : 'Available once the part is saved',
          child: AppButton(
            label: 'Author route',
            icon: Icons.route_rounded,
            variant: AppButtonVariant.secondary,
            onPressed:
                hasPart ? () => setState(() => _showRoutePanel = true) : null,
          ),
        ),
      ],
    );
  }

  Widget _rowToolbar({
    required String label,
    required int count,
    required VoidCallback onAdd,
    VoidCallback? onRemove,
    String addLabel = 'Add row',
    String removeLabel = 'Remove',
    String removeDisabledReason = 'A sheet always keeps one row',
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              '$label: $count',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(addLabel, style: const TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: onRemove == null
                ? removeDisabledReason
                : 'Remove the selected row',
            child: TextButton.icon(
              onPressed: onRemove,
              icon: const Icon(Icons.remove_rounded, size: 18),
              label: Text(removeLabel, style: const TextStyle(fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notYetWired(String heading, String detail) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SoftErpTheme.warningBg,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(color: SoftErpTheme.warningBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: SoftErpTheme.warningText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: const TextStyle(fontSize: 14, color: SoftErpTheme.warningText),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String id,
    required IconData icon,
    required String heading,
    required Widget child,
    Widget? trailing,
    bool collapsed = false,
  }) {
    // Saving and editing are per row now (each row's own Save, then Edit), so
    // the section itself is never locked.
    final body = child;
    return Container(
      key: _sectionKeys[id],
      margin: const EdgeInsets.only(bottom: SheetStyle.cardGap),
      padding: const EdgeInsets.all(SheetStyle.cardPadding),
      decoration: SheetStyle.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The part itself is the root and stays put; everything else can
              // be dragged onto another section to nest under it.
              if (id != 'group_item')
                Draggable<String>(
                  data: id,
                  feedback: Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Text(
                        heading,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  child: Tooltip(
                    message: 'Drag onto another section to nest $heading under it',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        key: ValueKey<String>('section_drag_$id'),
                        size: 22,
                        color: SoftErpTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              // Fold / unfold, like a folder in a file tree.
              IconButton(
                key: ValueKey<String>('section_toggle_$id'),
                tooltip: collapsed ? 'Open $heading' : 'Fold $heading',
                visualDensity: VisualDensity.compact,
                onPressed: () => _toggle(id),
                icon: Icon(
                  collapsed
                      ? Icons.chevron_right_rounded
                      : Icons.expand_more_rounded,
                  size: 22,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 4),
              SheetStyle.iconTile(icon),
              const SizedBox(width: 10),
              Expanded(child: Text(heading, style: SheetStyle.sectionTitle)),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing,
              ],
              const SizedBox(width: 8),
              ..._sectionActions(id, heading),
            ],
          ),
          if (collapsed)
            // Folded: one row of what is in it. Tap to open.
            InkWell(
              key: ValueKey<String>('section_summary_$id'),
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
              onTap: () => _toggle(id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
                child: Text(
                  _sectionSummary(id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
              ),
            ),
          if (!collapsed) ...[
            const SizedBox(height: 12),
            body,
          ],
        ],
      ),
    );
  }
}

/// One level of the section tree: indented by [depth], with the guides a file
/// tree draws — `├─` / `└─` into this section, and a `│` for each ancestor
/// that still has a sibling to come.
class _TreeNode extends StatelessWidget {
  const _TreeNode({
    required this.depth,
    required this.continues,
    required this.isLast,
    required this.child,
  });

  static const double indent = 28;

  final int depth;
  final List<bool> continues;
  final bool isLast;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (depth == 0) return child;
    // A Stack rather than a Row with IntrinsicHeight: the sections hold
    // LayoutBuilders, which cannot answer intrinsic sizes.
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _TreeGuidePainter(depth: depth, continues: continues, isLast: isLast),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: depth * indent),
          child: child,
        ),
      ],
    );
  }
}

class _TreeGuidePainter extends CustomPainter {
  _TreeGuidePainter({required this.depth, required this.continues, required this.isLast});

  final int depth;
  final List<bool> continues;
  final bool isLast;

  static const double _offset = 22;
  // Level with the middle of a section's header row, which sits one card
  // padding below the card's top edge.
  static const double _elbowY = SheetStyle.cardPadding + 18;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SoftErpTheme.textMuted
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    // Ancestors with siblings still to come keep their line running past.
    for (var level = 0; level < continues.length; level += 1) {
      if (!continues[level]) continue;
      final x = level * _TreeNode.indent + _offset;
      canvas.drawLine(Offset(x, -18), Offset(x, size.height), paint);
    }
    // This node: down from the parent, across into the card; on past it when
    // a sibling follows (├), stopping at the elbow when it is the last (└).
    final x = (depth - 1) * _TreeNode.indent + _offset;
    canvas.drawLine(Offset(x, -18), Offset(x, isLast ? _elbowY : size.height), paint);
    canvas.drawLine(Offset(x, _elbowY), Offset(depth * _TreeNode.indent, _elbowY), paint);
  }

  @override
  bool shouldRepaint(_TreeGuidePainter old) =>
      old.depth != depth || old.isLast != isLast || !listEquals(old.continues, continues);
}

/// What [_AddPropertyDialog] answers with.
class _NewProperty {
  const _NewProperty(this.name, this.kind, this.options);

  final String name;

  /// What the user picked: 'list', 'text', 'material' or 'gauge'.
  final String kind;
  final List<String> options;
}

/// Names a new property, says what kind of answer it takes and, for free
/// text, lists the answers to offer. Opened with [editing] it edits
/// that column's options only.
///
/// A `StatefulWidget` rather than a `StatefulBuilder` because of the text
/// controllers. The caller used to make one, `await showDialog`, then dispose
/// it on the next line — but a dialog keeps rebuilding through its **exit**
/// transition, so `_AnimatedState.didUpdateWidget` called `addListener` on a
/// controller that had already been disposed. That threw, and the half-built
/// frame surfaced as `A RenderFlex overflowed by 99284 pixels on the bottom`
/// and `Tried to build dirty widget in the wrong build scope` — none of which
/// name the controller. Owning them here ties their life to the route's.
class _AddPropertyDialog extends StatefulWidget {
  const _AddPropertyDialog({this.editing});

  /// The column whose options are being edited, or null to add one.
  final SheetProperty? editing;

  @override
  State<_AddPropertyDialog> createState() => _AddPropertyDialogState();
}

class _AddPropertyDialogState extends State<_AddPropertyDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _option = TextEditingController();
  String _kind = 'list';
  late final List<String> _options = [...?widget.editing?.options];

  bool get _editing => widget.editing != null;
  bool get _takesOptions => _kind == 'text';

  @override
  void dispose() {
    _name.dispose();
    _option.dispose();
    super.dispose();
  }

  /// Adds what is in the option box — several at once when pasted with
  /// commas — skipping blanks and ones already listed (ignoring case).
  void _addOption() {
    final typed = _option.text;
    if (typed.trim().isEmpty) return;
    setState(() {
      for (final raw in typed.split(',')) {
        final label = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (label.isEmpty) continue;
        if (_options.any((o) => o.toLowerCase() == label.toLowerCase())) {
          continue;
        }
        _options.add(label);
      }
      _option.clear();
    });
  }

  void _submit() {
    // An option still in the box counts — nobody should lose the last one
    // for not pressing Enter.
    _addOption();
    if (_editing) {
      final editing = widget.editing!;
      Navigator.of(
        context,
      ).pop(_NewProperty(editing.name, editing.kind, List.of(_options)));
      return;
    }
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      _NewProperty(name, _kind, _takesOptions ? List.of(_options) : const []),
    );
  }

  static const _heading = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: SoftErpTheme.textSecondary,
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _editing ? 'Options for ${widget.editing!.name}' : 'Add a property',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_editing) ...[
                TextField(
                  key: const ValueKey('property_name'),
                  controller: _name,
                  autofocus: true,
                  style: const TextStyle(fontSize: 15),
                  decoration: const InputDecoration(
                    labelText: 'Property name',
                    hintText: 'Plating, Temper, Coating…',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 20),
                const Text('Answer type', style: _heading),
                const SizedBox(height: 8),
                // Two equal rows rather than a Wrap: picking one never
                // reflows the others.
                for (final row in const [
                  [('list', 'A list of values'), ('material', 'A material')],
                  [('gauge', 'A gauge'), ('text', 'Free text')],
                ]) ...[
                  Row(
                    children: [
                      for (final (i, option) in row.indexed) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _KindTile(
                            label: option.$2,
                            selected: _kind == option.$1,
                            onTap: () => setState(() => _kind = option.$1),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ],
              AnimatedSize(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _editing || _takesOptions
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!_editing) ...[
                            const SizedBox(height: 12),
                            const Text('Options', style: _heading),
                            const SizedBox(height: 8),
                          ],
                          TextField(
                            key: const ValueKey('property_option'),
                            controller: _option,
                            autofocus: _editing,
                            style: const TextStyle(fontSize: 15),
                            decoration: InputDecoration(
                              labelText: 'Add an option',
                              hintText: 'Nickel, Chrome… then Enter',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip: 'Add',
                                icon: const Icon(Icons.add_rounded),
                                onPressed: _addOption,
                              ),
                            ),
                            onSubmitted: (_) => _addOption(),
                          ),
                          if (_options.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final option in _options)
                                  InputChip(
                                    key: ValueKey('property_option_$option'),
                                    label: Text(
                                      option,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                    onDeleted: () =>
                                        setState(() => _options.remove(option)),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(fontSize: 14)),
        ),
        // A new property needs a name before it can be added.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _name,
          builder: (context, name, _) => FilledButton(
            key: const ValueKey('property_submit'),
            onPressed: _editing || name.text.trim().isNotEmpty ? _submit : null,
            child: Text(
              _editing ? 'Save options' : 'Add',
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}

/// One answer type in [_AddPropertyDialog]'s picker: fills its half of the
/// row, so selecting it changes colour and weight but never its size.
class _KindTile extends StatelessWidget {
  const _KindTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? SoftErpTheme.accent.withValues(alpha: 0.10)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        side: BorderSide(
          color: selected ? SoftErpTheme.accent : SoftErpTheme.borderStrong,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? SoftErpTheme.accent : SoftErpTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
