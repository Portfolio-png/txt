import 'dart:async';
import 'dart:ui' show AppExitResponse;

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
import '../widgets/item_report.dart';
import '../widgets/part_rows_form.dart';
import '../widgets/part_photo_gallery.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/app_flow_hooks.dart';
import '../../../../core/utils/stamp_format.dart';

/// The item master as a sheet — the real screen behind the PM prototype.
///
/// The prototype (`PMItemMasterDetailScreen`) is the UI reference and stays as
/// one: it holds its records in four in-memory lists, seeds five groups and
/// four companies nobody created, and its save toasted a hardcoded part code.
/// This screen is the same layout over the real masters, through
/// [ItemSheetBinding].
///
/// Four sections down one scroll, with a rail that jumps between them. The
/// Client section is only shown for a part developed for someone else
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

  /// The row whose own Save is running, so only its button spins.
  SheetDraft? _savingDraft;
  bool get _treeDirty => !mapEquals(_parentOf, _savedTree);

  /// The raw sheet & strips panel on the right: open (null = decide from the
  /// window width), being edited, and a counter that resets it on Cancel.
  bool? _rawPanelOpen;
  bool _rawEditing = false;

  /// The editing raw sheet holds changes its own Save has not written.
  bool _rawDirty = false;

  /// The route panel, to save its stages from Save and close.
  final GlobalKey<RouteCreationPanelState> _routePanelKey =
      GlobalKey<RouteCreationPanelState>();

  /// Stages laid out on the route panel that its Save has not written.
  bool _routeDirty = false;

  /// A die, or a machine, typed into its sheet and not held or saved.
  bool _dieTyping = false;
  bool _machineTyping = false;

  /// Reads what the raw panel's Save would write now — held so an unsaved
  /// plan can still be written when the panel is about to lose it.
  PenPaperBaseline Function()? _rawDraft;
  int _rawEpoch = 0;

  /// A raw sheet save in flight, and the part the panel was last drawn for —
  /// so moving to another part does not carry edit mode across to it.
  bool _rawSaving = false;
  int? _rawPartId;
  static const double _rawPanelWidth = 520;

  /// Raw material rolled up to its heading by its chevron. The right column
  /// holds one thing at a time: raw material open, or — rolled up — the
  /// part's photos under its heading. Open, the photos are big on the part's
  /// own line instead.
  bool _rawRolled = false;

  /// What the die and machine forms are on ("New die for SADP48", "Die
  /// D-12"), shown in their sections' title bars.
  ({String label, String? value})? _dieHeading;
  ({String label, String? value})? _machineHeading;

  /// Whether the part's photos are in the right column (raw material rolled
  /// up) rather than big on the part's line.
  bool get _photosInColumn => _photosOn && _rawPanelShown && _rawRolled;

  /// The part whose raw sheet opens in edit mode once the panel is drawn for
  /// it — set by that part's Save. Without it the panel's own part-change
  /// reset would close edit mode again on the very next build.
  int? _rawEditFor;

  /// The raw panel's Next: Tab past a page's last field turns the page.
  bool Function()? _rawNextPage;

  /// Raw material's place in the keyboard's way down the sheet.
  static const Object _rawStep = 'raw_material';

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
      // The card's own heading: the rail, the card and the status bar used
      // to say "Group Item", "Item Master" and "Group Item".
      title: 'Item Master',
      subtitle: 'Identity, hierarchy & properties',
      icon: Icons.category_rounded,
    ),
    SheetSection(
      id: 'client_vendor',
      title: 'Client',
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

  bool _altPressed = false;
  bool _ctrlPressed = false;

  bool _handleGlobalKey(KeyEvent event) {
    if (!mounted) return false;
    final keyboard = HardwareKeyboard.instance;
    final alt = keyboard.isAltPressed;
    final ctrl = keyboard.isControlPressed || keyboard.isMetaPressed;

    if (_altPressed != alt || _ctrlPressed != ctrl) {
      setState(() {
        _altPressed = alt;
        _ctrlPressed = ctrl;
      });
    }

    if (event is KeyDownEvent && alt) {
      return _handleAltShortcut(event.logicalKey);
    }
    return false;
  }

  bool _handleAltShortcut(LogicalKeyboardKey key) {
    final sheet = _controller.groupItemController;
    final def = sheet.sheetDef;
    ColumnDef? col;

    if (key == LogicalKeyboardKey.keyG) {
      col = def.columns.where((c) => c.bindsTo == SheetBindsTo.group).firstOrNull;
    } else if (key == LogicalKeyboardKey.keyT) {
      col = def.columns.where((c) => c.bindsTo == SheetBindsTo.set).firstOrNull;
    } else if (key == LogicalKeyboardKey.keyN) {
      col = def.columns.where((c) => c.bindsTo == SheetBindsTo.name).firstOrNull;
    } else if (key == LogicalKeyboardKey.keyC) {
      col = def.columns.where((c) => c.bindsTo == SheetBindsTo.partCode).firstOrNull;
    } else if (key == LogicalKeyboardKey.keyP) {
      col = def.columns.where((c) => c.bindsTo == SheetBindsTo.partNo).firstOrNull;
    } else if (key == LogicalKeyboardKey.keyA) {
      col = def.columns.where((c) => c.label.toLowerCase().contains('alloy')).firstOrNull;
    } else if (key == LogicalKeyboardKey.keyK) {
      col = def.columns.where((c) => c.label.toLowerCase().contains('thick')).firstOrNull;
    } else if (key == LogicalKeyboardKey.keyR) {
      col = def.columns.where((c) => c.label.toLowerCase().contains('grade')).firstOrNull;
    } else if (key == LogicalKeyboardKey.keyH) {
      col = def.columns.where((c) => c.label.toLowerCase().contains('hard')).firstOrNull;
    }

    if (col != null) {
      sheet.focusCell(col.id, row: sheet.row);
      return true;
    }

    if (key == LogicalKeyboardKey.keyS) {
      _handleSave();
      return true;
    } else if (key == LogicalKeyboardKey.digit1) {
      sheet.addRow();
      final first = PartRowsForm.lineColumns(sheet.sheetDef).firstOrNull;
      if (first != null) sheet.focusCell(first.id, row: sheet.rowCount - 1);
      return true;
    } else if (key == LogicalKeyboardKey.keyD) {
      _addProperty();
      return true;
    } else if (key == LogicalKeyboardKey.keyX) {
      final row = sheet.row;
      final id = sheet.draftAt(row).entityId;
      if (id != null) _archivePart(id);
      return true;
    } else if (key == LogicalKeyboardKey.keyM) {
      setState(() => _rawPanelOpen = !_rawPanelShown);
      return true;
    } else if (key == LogicalKeyboardKey.keyE) {
      _controller.setExternal(!_controller.isExternal);
      return true;
    }

    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
    _sittingId = SittingScope.begin();

    _controller = ItemMasterController.live(binding: _buildBinding());
    _controller.addListener(_onControllerChanged);
    // A row holding dies or machines for its part is never dropped on the
    // controller's own say-so (picking an existing part's name on it).
    _controller.rowHoldsWork = (rowKey) =>
        (_heldDies[rowKey]?.isNotEmpty ?? false) ||
        (_heldMachines[rowKey]?.isNotEmpty ?? false);
    // Quitting the app — Cmd+Q, or the window's close button, which the
    // window turns into a quit — asks the same question as Back.
    _exitListener = AppLifecycleListener(onExitRequested: _onExitRequested);
    // The keyboard starts on the first thing to fill in: the part line's
    // Group (or the first field of whatever step comes first).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _flow.focusFirst();
    });

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
        title: 'Item Master',
        columns: itemSheetColumns,
      ),
      // The controller's copy is the one a + adds properties to.
      liveItemSheet: () => _controller.groupItemController.sheetDef,
      sheetProperties: () => _sheetProps?.properties ?? const [],
      partySheet: SheetDef(
        id: 2,
        key: 'item_party',
        title: 'Client',
        columns: dealSheetColumns,
      ),
      // The deal is one record for the screen, and the binding reads it live
      // at each save rather than being handed a copy taken at build time —
      // which is what the old `partyDraft: null` here amounted to: the deal
      // was drawn, typed into, and never once saved.
      dealDraft: () => _controller.dealDraftForSave(),
      dealContactIds: () => _controller.dealContactIdsForSave(),
      dealCleared: () => _controller.dealClearedForSave(),
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
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    _exitListener.dispose();
    _controller.rowHoldsWork = null;
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
      final left = _controller.groupItemController.draftAt(row);
      final ok = await _controller.commitRow(row);
      if (!mounted) return;
      if (ok) {
        // The row just left, not the cursor's: that has moved on.
        final id = _committedPartId;
        if (id != null) _madeHere.add(id);
        await _flushStaged();
        // A nesting arranged before the part existed is saved with it now.
        if (mounted && _treeDirty) await _saveTree();
      } else {
        // The line keeps everything typed; what stopped it is said once.
        final at = _controller.groupItemController.indexOfDraft(left);
        final why = at < 0 ? null : _controller.rowError(at);
        if (why != null) _toast('Part ${at + 1}: $why', isError: true);
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
    final partName =
        part.displayName.trim().isEmpty ? part.name : part.displayName;
    final held = _heldDies[rowKey] ?? <DieSheetDraft>[];
    final dieIds = <String>[for (final d in part.dies) d.id];
    final diesMade = <DieSheetDraft>[];
    for (final draft in List<DieSheetDraft>.from(held)) {
      if (!mounted) return;
      // Made on an earlier save whose link failed: link it, do not make it
      // a second time.
      var id = _madeDies[draft];
      if (id == null) {
        final outcome =
            await AppFlowHooks.createDieFromSheet?.call(context, draft);
        id = outcome?.record?.id;
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
        _madeDies[draft] = id;
      }
      if (!dieIds.contains(id)) dieIds.add(id);
      diesMade.add(draft);
    }

    final heldMachines = _heldMachines[rowKey] ?? <MachineSheetDraft>[];
    final machineIds = <String>[for (final m in part.machines) m.id];
    final machinesMade = <MachineSheetDraft>[];
    for (final draft in List<MachineSheetDraft>.from(heldMachines)) {
      if (!mounted) return;
      var id = _madeMachines[draft];
      if (id == null) {
        final outcome =
            await AppFlowHooks.createMachineFromSheet?.call(context, draft);
        id = outcome?.record?.id;
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
        _madeMachines[draft] = id;
      }
      if (!machineIds.contains(id)) machineIds.add(id);
      machinesMade.add(draft);
    }

    if (!mounted) return;
    // A held die leaves the list only once it is ON the part. It used to
    // leave as soon as it was made, so a failed link left a die in the master
    // that no part had, with nothing held to warn about and nothing said.
    if (diesMade.isNotEmpty) {
      final error = await _setDiesOn(part.id, dieIds);
      if (!mounted) return;
      if (error == null) {
        setState(() {
          for (final draft in diesMade) {
            held.remove(draft);
            _madeDies.remove(draft);
          }
        });
      } else {
        _toast(
          '${diesMade.length == 1 ? 'Die ${diesMade.single.toolCode} was' : '${diesMade.length} dies were'} '
          'made but not attached to $partName — Save part again to attach '
          '${diesMade.length == 1 ? 'it' : 'them'}. ($error)',
          isError: true,
        );
      }
    }
    if (machinesMade.isNotEmpty) {
      final error = await _setMachinesOn(part.id, machineIds);
      if (!mounted) return;
      if (error == null) {
        setState(() {
          for (final draft in machinesMade) {
            heldMachines.remove(draft);
            _madeMachines.remove(draft);
          }
        });
      } else {
        _toast(
          '${machinesMade.length == 1 ? 'Machine ${machinesMade.single.assetId} was' : '${machinesMade.length} machines were'} '
          'made but not attached to $partName — Save part again to attach '
          '${machinesMade.length == 1 ? 'it' : 'them'}. ($error)',
          isError: true,
        );
      }
    }
  }

  /// Held dies and machines already made in the master, by draft, whose link
  /// to the part has not gone through yet — so a retry links them rather than
  /// making them again.
  final Map<DieSheetDraft, String> _madeDies = Map.identity();
  final Map<MachineSheetDraft, String> _madeMachines = Map.identity();

  /// Every save and every refusal on this screen is said here, in the app's
  /// own toast — nothing on the lines is drawn red.
  void _toast(String message, {bool isError = false}) {
    if (message.trim().isEmpty) return;
    showAppToast(
      context,
      message,
      kind: isError ? AppToastKind.error : AppToastKind.success,
    );
  }

  bool get _hasUnsavedWork => _unsavedWork().isNotEmpty;

  /// What would be lost by leaving now, in the words the dialog uses. The
  /// section layout and an open raw sheet used to be left out, so the screen
  /// closed on them without a word.
  List<String> _unsavedWork() => [
        if (_controller.hasUnsavedWork) 'rows or edits to parts',
        if (_heldDies.values.any((held) => held.isNotEmpty) ||
            _heldMachines.values.any((held) => held.isNotEmpty))
          'dies or machines waiting for their part',
        if (_treeDirty && _livePart != null) 'the section layout',
        if (_rawEditing && _rawDirty) 'the raw sheet',
        if (_showRoutePanel && _routeDirty) 'the route',
        if (_dieTyping) 'a die being typed',
        if (_machineTyping) 'a machine being typed',
      ];

  /// Back with something unwritten. Rows commit as the cursor leaves them,
  /// but the row under the cursor, an edit to a saved row and held dies were
  /// all dropped without a word when the screen closed.
  /// Asks whether to leave with unsaved work — Keep editing, Discard, or
  /// Save and close — and answers whether leaving is now all right. Back and
  /// quitting the app both ask through here.
  Future<bool> _askToLeave() async {
    // One question at a time: Back and then Cmd+Q put two on screen.
    if (_askingToLeave) return false;
    _askingToLeave = true;
    try {
      return await _askToLeaveOnce();
    } finally {
      _askingToLeave = false;
    }
  }

  bool _askingToLeave = false;

  Future<bool> _askToLeaveOnce() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave with unsaved work?'),
        content: Text(
          'Not saved yet: ${_unsavedWork().join(', ')}.',
          style: const TextStyle(fontSize: 14),
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
    if (!mounted || choice == null || choice == 'stay') return false;
    if (choice == 'save') {
      await _handleSave();
      if (!mounted) return false;
      // The part's Save does not write the raw sheet or the route — each has
      // its own — so Save and close writes them too, once the part exists.
      final read = _rawDraft;
      if (_rawEditing && _rawDirty && read != null && _livePart != null) {
        await _saveRawSheet(read());
        if (!mounted) return false;
      }
      final route = _routePanelKey.currentState;
      if (_showRoutePanel && _routeDirty && route != null) {
        await route.save();
        if (!mounted) return false;
      }
      final left = _unsavedWork();
      if (left.isNotEmpty) {
        _toast('Still not saved: ${left.join(', ')}.', isError: true);
        return false;
      }
    }
    _leaving = true;
    return true;
  }

  /// Back with something unwritten.
  Future<void> _confirmLeave() async {
    if (await _askToLeave() && mounted) Navigator.of(context).pop();
  }

  late final AppLifecycleListener _exitListener;

  /// The app is being quit. Nothing unsaved: let it. Otherwise the same
  /// question as Back — and Keep editing, or a save that did not finish,
  /// keeps the app open.
  Future<AppExitResponse> _onExitRequested() async {
    if (!mounted || _leaving || !_hasUnsavedWork) return AppExitResponse.exit;
    return await _askToLeave() ? AppExitResponse.exit : AppExitResponse.cancel;
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
              // Tab goes through what is typed on the sheet, and only that:
              // the top bar, the rail and the raw panel are clicked.
              SheetStep.noTab(_topBar()),
              Expanded(
                child: Row(
                  children: [
                    if (_railCollapsed)
                      SheetStep.noTab(_collapsedRail())
                    else
                      SheetStep.noTab(Stack(
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
                      )),
                    Expanded(child: _body()),
                    // Raw material is a keyboard step of its own (_rawStep); its
                    // fold strip and headings are clicked.
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
      // Edge to edge: in the screen's Column it took its content's width and
      // sat centred, its white and its rule stopping short of either side.
      width: double.infinity,
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
            _crumb(_crumbTitle(), isLast: true),
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
                if (_altPressed) ...[
                  const SizedBox(width: 4),
                  const KeyTipBadge(label: 'Alt+E'),
                ],
              ],
            ),
            const SizedBox(width: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _archiveButton(),
                if (_altPressed) ...[
                  const SizedBox(width: 4),
                  const KeyTipBadge(label: 'Alt+X'),
                ],
              ],
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: 'Saves every row: the part, its deal and people, dies '
                      'and machines waiting to be added, and the section layout. '
                      'The raw sheet and the route have their own Save.',
                  child: AppButton(
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
                ),
                if (_altPressed || _ctrlPressed) ...[
                  const SizedBox(width: 4),
                  const KeyTipBadge(label: 'Alt+S'),
                ],
              ],
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
  /// Whether the raw sheet panel is drawn open beside the sections.
  bool get _rawPanelShown =>
      _rawPanelOpen ?? MediaQuery.sizeOf(context).width >= 1500;

  Widget _rawSheetPanel() {
    final part = _livePart;
    if (part?.id != _rawPartId) {
      // The cursor moved to another part with this one's raw sheet edited and
      // not saved. The panel is about to be rebuilt for the new part, which
      // threw the edits away; they are written to the part they were made on,
      // the way a part line saves when it is left.
      final leftId = _rawPartId;
      final read = _rawDraft;
      if (_rawEditing && _rawDirty && leftId != null && read != null) {
        final draft = read();
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => unawaited(_saveRawSheetOn(leftId, draft)),
        );
      }
      _rawPartId = part?.id;
      _rawEditing = part != null && part.id == _rawEditFor;
      if (_rawEditing) _rawEditFor = null;
      _rawDirty = false;
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
          ? '${route.title} v${route.version}'
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
      // A blank Thickness cell says nothing — handing the panel '' made it
      // read the part's thickness as 0 and wipe the one typed there.
      thickness: _cellNow(SheetBindsTo.variation('Thickness')).trim().isEmpty
          ? null
          : _cellNow(SheetBindsTo.variation('Thickness')),
      onThicknessChanged: _setThickness,
      saving: _rawSaving,
      onEdit: part != null && !_rawEditing
          ? () => setState(() => _rawEditing = true)
          : null,
      onDirtyChanged: (dirty) {
        if (mounted && dirty != _rawDirty) setState(() => _rawDirty = dirty);
      },
      onDraftSource: (read, alive) {
        if (alive) {
          _rawDraft = read;
        } else if (identical(_rawDraft, read)) {
          _rawDraft = null;
        }
      },
      onPagerSource: (next, alive) {
        if (alive) {
          _rawNextPage = next;
        } else if (identical(_rawNextPage, next)) {
          _rawNextPage = null;
        }
      },
      onSave: (saved) => unawaited(_saveRawSheet(saved)),
      onCancel: _rawEditing
          ? () => setState(() {
                _rawEditing = false;
                _rawDirty = false;
                _rawEpoch += 1;
              })
          : null,
    );

    final strip = SheetStep.noTab(Container(
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
          if (_altPressed) ...[
            const SizedBox(height: 4),
            const KeyTipBadge(label: 'Alt+M'),
          ],
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
    ));
    final shown = _rawPanelShown;
    // Folded — by its button, or a window under 1500 wide — while editing:
    // the panel is kept, hidden, so folding is not a way to lose the edits.
    // The open panel sits at the same place in the tree either way, so
    // hiding it does not rebuild it from nothing.
    if (!shown && !_rawEditing) return strip;
    return Stack(
      children: [
        Offstage(offstage: !shown, child: _rawPanelFrame(part, panel)),
        if (!shown) strip,
      ],
    );
  }

  Widget _rawPanelFrame(ItemDefinition? part, Widget panel) {
    final name = part == null
        ? _partLabelNow
        : (part.displayName.trim().isEmpty ? part.name : part.displayName.trim());
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
          // Headings are clicked; Tab goes through what is typed.
          SheetStep.noTab(Padding(
            padding: const EdgeInsets.fromLTRB(SheetStyle.cardPadding, 10, 8, 6),
            child: Row(
              children: [
                SheetStyle.iconTile(Icons.grid_on_rounded),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Raw material', style: SheetStyle.sectionTitle),
                ),
                if (_rawEditing && _rawDirty) ...[
                  Tooltip(
                    message: 'Not saved yet — Save raw sheet at the bottom '
                        'writes it. Save part does not.',
                    child: SheetStyle.unsavedPill(
                      key: const ValueKey<String>('raw_unsaved'),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                _rollButton(
                  key: 'raw_roll',
                  what: 'raw material',
                  rolled: _rawRolled,
                  onPressed: () => setState(() => _rawRolled = !_rawRolled),
                ),
                // Its Edit is the panel's own, at the foot where Save will be —
                // the way a part line's Save becomes its Edit in one place.
                IconButton(
                  key: const ValueKey<String>('raw_panel_close'),
                  tooltip: 'Fold the raw sheet panel',
                  onPressed: () => setState(() => _rawPanelOpen = false),
                  icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
                ),
                if (_altPressed) ...[
                  const SizedBox(width: 4),
                  const KeyTipBadge(label: 'Alt+M'),
                ],
              ],
            ),
          )),
          if (part == null)
            const Padding(
              padding: EdgeInsets.fromLTRB(SheetStyle.cardPadding, 0, SheetStyle.cardPadding, 8),
              child: Text(
                'Save the part to plan its raw sheet.',
                style: SheetStyle.hint,
              ),
            ),
          const Divider(height: 1),
          // Rolled up, it keeps its place and its state — Offstage, at a
          // sliver of the room — so rolling is never a way to lose an edit.
          Flexible(
            flex: _rawRolled ? 1 : 1000,
            child: _rolled(
              _rawRolled,
              SheetStep(
                key: const ValueKey<String>('raw_step'),
                // Only a saved part has a raw sheet to type into.
                flow: part == null ? null : _flow,
                id: _rawStep,
                actions: _rawStepActions(),
                child: part == null
                    // Drawn so the shape of the step is visible, but not
                    // usable until there is a part to store it on.
                    ? IgnorePointer(child: Opacity(opacity: 0.5, child: panel))
                    : panel,
              ),
            ),
          ),
          if (_photosInColumn) ...[
            const Divider(height: 1),
            SheetStep.noTab(Padding(
              padding: const EdgeInsets.fromLTRB(SheetStyle.cardPadding, 8, 8, 6),
              child: Row(
                children: [
                  SheetStyle.iconTile(Icons.photo_library_outlined),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Photos', style: SheetStyle.sectionTitle),
                  ),
                ],
              ),
            )),
            Flexible(
              flex: 1000,
              child: SheetStep.noTab(_PartPhotosSection(
                key: const ValueKey<String>('part_photos_section'),
                partId: part?.id,
                partName: name,
              )),
            ),
          ],
        ],
      ),
    );
  }

  /// Raw material, [rolled] up or not. Rolled, it is laid out
  /// at a size it fits (it would overflow the sliver it is given) and not
  /// drawn; the widgets stay the same either way, so their state does too.
  Widget _rolled(bool rolled, Widget child) => Offstage(
        offstage: rolled,
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: rolled ? 0 : null,
          maxHeight: rolled ? 640 : null,
          child: child,
        ),
      );

  /// A section's chevron: up rolls it to its heading, down opens it again.
  Widget _rollButton({
    required String key,
    required String what,
    required bool rolled,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      key: ValueKey<String>(key),
      tooltip: rolled ? 'Roll $what down' : 'Roll $what up',
      onPressed: onPressed,
      icon: Icon(
        rolled ? Icons.expand_more_rounded : Icons.expand_less_rounded,
        size: 24,
      ),
    );
  }

  /// Raw material as a keyboard step: Tab through a page, past its last
  /// field to the next page, past Review to "Save raw material?", then on.
  SheetStepActions _rawStepActions() => SheetStepActions(
        title: () => 'Save raw material?',
        isDirty: () => _rawEditing && _rawDirty,
        save: () async {
          final read = _rawDraft;
          if (read == null) return true;
          await _saveRawSheet(read());
          return mounted && !_rawEditing;
        },
        discard: () => setState(() {
          _rawEditing = false;
          _rawDirty = false;
          _rawEpoch += 1;
        }),
        isLocked: () => !_rawEditing,
        unlock: () {
          if (_livePart != null) setState(() => _rawEditing = true);
        },
        nextPage: () => _rawNextPage?.call() ?? false,
      );

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

  /// Writes a raw sheet left unsaved on [partId] when the cursor moved off
  /// that part, and says so — the panel on screen is the new part's now.
  Future<void> _saveRawSheetOn(int partId, PenPaperBaseline baseline) async {
    if (!mounted) return;
    final items = context.read<ItemsProvider>();
    final part = items.findById(partId);
    final name = part == null
        ? 'part #$partId'
        : (part.displayName.trim().isEmpty ? part.name : part.displayName);
    final saved = await items.setItemPenPaperBaseline(partId, baseline);
    if (!mounted) return;
    _toast(
      saved == null
          ? 'The raw sheet for $name did not save: '
              '${items.errorMessage ?? 'try again from that part'}.'
          : 'Raw material saved on $name.',
      isError: saved == null,
    );
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
      if (saved != null) {
        _rawEditing = false;
        _rawDirty = false;
      }
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
  /// Client is left out for an in-house part; whatever was nested
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
          ? (items.errorMessage ?? 'The section layout did not save.')
          : 'Section layout saved — the part\'s client, dies and machines now follow it.',
      isError: saved == null,
    );
  }

  Widget _tree() {
    _syncTreeFromPart();
    // Half the step when room is short: three levels at 28 px took 84 px from
    // the die and machine forms, which then wrapped and cut their helpers.
    // Read from the window, not a LayoutBuilder — the sections below hold
    // reorderable lists, which a LayoutBuilder above them breaks.
    final width = MediaQuery.sizeOf(context).width;
    final indent = _rawPanelShown || width < 1300
        ? _TreeNode.compactIndent
        : _TreeNode.wideIndent;
    final nodes = <Widget>[];
    void visit(String id, int depth, List<bool> continues, bool isLast) {
      final collapsed = _collapsed.contains(id);
      nodes.add(_TreeNode(
        indent: indent,
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
        if (_treeDirty) SheetStep.noTab(_treeDirtyBar()),
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
                  ? 'Section layout changed — save it so this part\'s client, dies and machines follow it.'
                  : 'Section layout changed — it is saved with the part.',
              style: const TextStyle(fontSize: 14, color: SoftErpTheme.warningText),
            ),
          ),
          TextButton(
            key: const ValueKey<String>('tree_undo'),
            onPressed: () => setState(() => _parentOf = Map.of(_savedTree)),
            child: const Text('Undo', style: TextStyle(fontSize: 14)),
          ),
          if (saved)
            AppButton(
              key: const ValueKey<String>('tree_save'),
              label: 'Save section layout',
              icon: Icons.save_outlined,
              variant: AppButtonVariant.secondary,
              dense: true,
              isLoading: _savingTree,
              onPressed: _saveTree,
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
    final ok = await showConfirmDialog(
      context,
      title: title,
      message: detail,
      confirmLabel: 'Clear',
      cancelLabel: 'Keep',
    );
    if (!ok || !mounted) return;

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

  /// What a folded section shows instead of its body: everything entered, as
  /// label–value pairs on one line, with the date and time of anything that
  /// was stamped. A pair with no label is the record's own name (a die's
  /// code, a machine's number). An empty section is one plain sentence.
  List<(String?, String)> _sectionSummary(String id) {
    final out = <(String?, String)>[];
    void add(String? label, Object? value) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) out.add((label, text));
    }

    String? cell(SheetController sheet, String binds) {
      final column = sheet.sheetDef.columnBoundTo(binds);
      if (column == null) return null;
      final value = sheet.draft.get(column.id);
      return value?.optionLabel ?? value?.textValue ?? value?.intValue?.toString();
    }

    String? money(double? amount) => amount == null ? null : rupeeStamp(amount);
    String? stamp(DateTime? at) => at == null ? null : partStamp(at);

    switch (id) {
      case 'client_vendor':
        final company = _controller.dealPartyName;
        if (company.isEmpty) return const [(null, 'No company chosen yet')];
        add('Company', company);
        add('Quotation', money(_moneyBoundTo(SheetBindsTo.developedForQuotation)));
        add('Cost', money(_moneyBoundTo(SheetBindsTo.developedForCost)));
        final people = _controller.peopleController;
        final tick = people.sheetDef.columnBoundTo(SheetBindsTo.personDealtWith);
        final name = people.sheetDef.columnBoundTo(SheetBindsTo.personName);
        final role = people.sheetDef.columnBoundTo(SheetBindsTo.personDesignation);
        final dealtWith = <String>[
          for (final d in people.drafts)
            if (tick != null && name != null && d.get(tick.id)?.intValue == 1)
              [
                (d.get(name.id)?.textValue ?? '').trim(),
                if (role != null)
                  (d.get(role.id)?.optionLabel ?? d.get(role.id)?.textValue ?? '').trim(),
              ].where((p) => p.isNotEmpty).join(', '),
        ].where((p) => p.isNotEmpty);
        add('Dealt with', dealtWith.join('; '));
        add('Recorded', stamp(_livePart?.developedFor.at));
      case 'die_master':
        final dies = [
          for (final d in _livePart?.dies ?? const <ItemDieLink>[]) (d, false),
          for (final d in _stagedDies) (heldDieLink(d), true),
        ];
        if (dies.isEmpty) return const [(null, 'No dies yet')];
        // The same lines the item report prints.
        for (final (die, held) in dies) {
          out.addAll(dieLines(die, held: held));
        }
      case 'machine_master':
        final groups = context.read<GroupsProvider>();
        final machines = [
          for (final m in _livePart?.machines ?? const <ItemMachineLink>[]) (m, false),
          for (final m in _stagedMachines)
            (
              heldMachineLink(
                m,
                typeName: m.groupId == null ? '' : groups.findById(m.groupId!)?.name ?? '',
              ),
              true,
            ),
        ];
        final route = _route;
        if (machines.isEmpty && route == null) return const [(null, 'No machines yet')];
        for (final (machine, held) in machines) {
          out.addAll(machineLines(machine, held: held));
        }
        if (route != null) add('Route', routeLine(route));
      default:
        final sheet = _controller.groupItemController;
        final nameColumn = sheet.sheetDef.columnBoundTo(SheetBindsTo.name) ?? sheet.sheetDef.itemColumn;
        add('Group', nameColumn == null ? null : SheetEngine.groupPathString(sheet.sheetDef, sheet.draft, nameColumn.id));
        add('Part', cell(sheet, SheetBindsTo.name));
        add('Part No', cell(sheet, SheetBindsTo.partNo));
        add('Code', _partCodeNow);
        for (final column in sheet.sheetDef.columns) {
          if (!SheetBindsTo.isVariation(column.bindsTo)) continue;
          final value = sheet.draft.get(column.id);
          add(column.label, value?.optionLabel ?? value?.textValue);
        }
        final part = _livePart;
        add('Created', stamp(part?.createdAt));
        // Only when it says something the created stamp does not.
        if (part != null && part.updatedAt.difference(part.createdAt).inMinutes.abs() >= 1) {
          add('Updated', stamp(part.updatedAt));
        }
        if (out.isEmpty) return const [(null, 'Nothing entered yet')];
    }
    return out;
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
          icon: Icons.subdirectory_arrow_left_rounded,
          tip: canOutdent ? 'Move $heading one level out' : 'Already directly under the part',
          onPressed: canOutdent ? () => _outdent(id) : null,
        ),
        action(
          key: 'section_indent_$id',
          icon: Icons.subdirectory_arrow_right_rounded,
          tip: above == null
              ? 'Nothing above it at this level to nest under'
              : 'Nest $heading under the section above',
          onPressed: above == null ? null : () => _nest(id, above),
        ),
      ],
      // Not on the part itself: it was never pressable there, and the part
      // goes through Archive part in the top bar, not a bin on its section.
      if (!root)
        action(
          key: 'section_clear_$id',
          icon: Icons.delete_outline_rounded,
          tip: 'Clear $heading for this part',
          onPressed: () => _clearSection(id),
          // Grey like the icons beside it and the × on a line; it asks
          // before it clears, so it need not shout.
        ),
    ];
  }

  Widget _sectionFor(String id, {required bool collapsed}) {
    switch (id) {
      case 'client_vendor':
        return _section(
          id: 'client_vendor',
          icon: Icons.storefront_rounded,
          heading: 'Client',
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
          trailing: _formHeading('die_heading', _dieHeading),
          child: _dieSheet(),
        );
      case 'machine_master':
        return _section(
          id: 'machine_master',
          icon: Icons.settings_suggest_rounded,
          heading: 'Machines & Routing',
          collapsed: collapsed,
          trailing: _formHeading('machine_heading', _machineHeading),
          child: _machinesAndRouting(),
        );
      default:
        return _section(
          id: 'group_item',
          icon: Icons.category_rounded,
          heading: 'Item Master',
          collapsed: collapsed,
          trailing: _partHeading(),
          child: _groupItemSheet(),
        );
    }
  }

  /// A die or machine form's heading, on the right of its section's title
  /// bar, drawn as Item Master's "Part code" chip is.
  Widget? _formHeading(String key, ({String label, String? value})? heading) {
    if (heading == null) return null;
    return Align(
      alignment: Alignment.centerRight,
      child: _codeChip(heading.label, heading.value, key: ValueKey<String>(key)),
    );
  }

  /// "Part code: SADP48" — the words muted, the code bold in the accent; a
  /// code not there yet reads "assigned on save", muted.
  Widget _codeChip(String label, String? code, {Key? key}) {
    final none = code == null || code.isEmpty;
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: label,
              style: const TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary),
            ),
            TextSpan(
              text: none ? 'assigned on save' : code,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: none ? SoftErpTheme.textMuted : SoftErpTheme.accent,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
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
      onHeading: (text) => setState(() => _dieHeading = text),
      lineKey: _cursorRowKey,
      flow: _flow,
      onDirtyChanged: (dirty) {
        if (mounted && dirty != _dieTyping) setState(() => _dieTyping = dirty);
      },
      part: _livePart,
      partCode: _partCodeNow,
      partLabel: _partLabelNow,
      busy: _controller.isSavingNow,
      staged: _stagedDies,
      onStage: (draft) => setState(() => _stagedDies.add(draft)),
      onUnstage: (index) => setState(() => _stagedDies.removeAt(index)),
      onDiesChanged: _setDies,
      // A held die is written with its part, so its row offers the part's
      // own Save — the cursor row's, which is the row these dies are held on.
      heldSaveBuilder: (index) => _savePartButton(
        _controller.groupItemController.row,
        key: 'die_held_save_$index',
        readyTip: 'Save the part, and this die with it',
      ),
    );
  }

  Widget _machinesAndRouting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PartMachineSection(
          framed: false,
          onHeading: (text) => setState(() => _machineHeading = text),
          lineKey: _cursorRowKey,
          flow: _flow,
          onDirtyChanged: (dirty) {
            if (mounted && dirty != _machineTyping) {
              setState(() => _machineTyping = dirty);
            }
          },
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
        // Routing is laid out with the mouse; Tab ends at the machine form.
        SheetStep.noTab(_routing()),
      ],
    );
  }

  /// Dies and machines are written as two calls, not one.
  ///
  /// Each list is a full replace on the item, so sending only one of them in a
  /// single write would clear the other.
  Future<String?> _setDies(List<String> dieIds) async {
    final part = _livePart;
    if (part == null) return 'Save the part to link its dies.';
    return _setDiesOn(part.id, dieIds);
  }

  Future<String?> _setDiesOn(int partId, List<String> dieIds) async {
    final items = context.read<ItemsProvider>();
    final saved = await items.setItemLinks(partId, dieIds: dieIds);
    return saved == null ? (items.errorMessage ?? 'That did not save.') : null;
  }

  Future<String?> _setMachines(List<String> machineIds) async {
    final part = _livePart;
    if (part == null) return 'Save the part to link its machines.';
    return _setMachinesOn(part.id, machineIds);
  }

  Future<String?> _setMachinesOn(int partId, List<String> machineIds) async {
    final items = context.read<ItemsProvider>();
    final saved = await items.setItemLinks(partId, machineIds: machineIds);
    return saved == null ? (items.errorMessage ?? 'That did not save.') : null;
  }

  /// The heading's right end: the part's code, then when the part was made.
  Widget _partHeading() => Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 6,
        children: [_identityChip(), _stampChip()],
      );

  /// When the part under the cursor was saved — the Date and Time its line
  /// leaves out. A part not saved yet shows the time now, muted: its save is
  /// what stamps it.
  Widget _stampChip() {
    final sheet = _controller.groupItemController.sheetDef;
    final draft = _controller.groupItemController.draft;
    String? stamped(String binds) {
      final column = sheet.columnBoundTo(binds);
      final text = column == null ? null : draft.get(column.id)?.textValue?.trim();
      return (text == null || text.isEmpty) ? null : text;
    }

    final date = stamped(SheetBindsTo.createdDate);
    if (date == null) return const _HeadingStamp.now();
    return _HeadingStamp(date: date, time: stamped(SheetBindsTo.createdTime));
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
          const Text('Part code: ',
              style: TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary)),
          Text(
            (code == null || code.isEmpty) ? 'assigned on save' : code,
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

  /// The parts, one line each, drawn like the people under a company: see
  /// [PartRowsForm]. It replaced a grid of titled tables whose Save sat in an
  /// "Action" table of its own, which wrapped off the part's line.
  Widget _groupItemSheet() {
    final sheet = _controller.groupItemController;
    return PartRowsForm(
      sheet: sheet,
      photoBuilder: _photosOn ? _rowPhoto : null,
      // Raw material open: the part's photo is big on its own line. Rolled
      // up, the photos fill the right column and the line keeps a small one.
      showcaseRow: _photosOn && !_photosInColumn ? sheet.row : null,
      showcasePhotoBuilder: (row, side) => _rowPhoto(row, size: side),
      statusBuilder: _rowStatus,
      actionBuilder: (row) => _rowEndAction(row) ?? const SizedBox.shrink(),
      onAddPart: () {
        sheet.addRow();
        final first = PartRowsForm.lineColumns(sheet.sheetDef).firstOrNull;
        if (first != null) sheet.focusCell(first.id, row: sheet.rowCount - 1);
      },
      onAddProperty: _addProperty,
      onRemoveRow: _removeLine,
      flow: _flow,
      lineActions: _lineActions,
      showShortcuts: _altPressed,
    );
  }

  /// The keyboard's way down the sheet: part lines, the company and its
  /// people, the die form, the machine form — in the order the sections are
  /// drawn, which the user can rearrange.
  late final SheetFlow _flow = SheetFlow(
    order: _stepOrder,
    reveal: (section) {
      if (section == 'raw') {
        // Raw material is open to whoever arrives.
        if (_rawRolled) setState(() => _rawRolled = false);
        return;
      }
      if (_collapsed.contains(section)) setState(() => _collapsed.remove(section));
    },
    onEnd: () => _toast('End of the sheet — Ctrl+S saves everything.'),
  );

  List<SheetStepPlace> _stepOrder() {
    final out = <SheetStepPlace>[];
    void visit(String id) {
      switch (id) {
        case 'group_item':
          final sheet = _controller.groupItemController;
          for (final (at, draft) in sheet.drafts.indexed) {
            out.add((id: PartRowsForm.stepId(draft.rowKey), section: id));
            // Raw material is the part under the cursor's: from its line the
            // keyboard goes into the panel, then on down the sheet.
            if (at == sheet.row) out.add((id: _rawStep, section: 'raw'));
          }
        case 'client_vendor':
          if (_controller.isExternal) {
            out.add((id: DealPeopleForm.companyStep, section: id));
            for (final draft in _controller.peopleController.drafts) {
              out.add((id: DealPeopleForm.personStep(draft.rowKey), section: id));
            }
          }
        case 'die_master':
          out.add((id: PartDieSection.step, section: id));
        case 'machine_master':
          out.add((id: PartMachineSection.step, section: id));
      }
      for (final kid in _childrenOf(id)) {
        visit(kid);
      }
    }

    visit('group_item');
    return out;
  }

  /// A part line's save prompt: Save writes the line (its held dies and
  /// machines with it), Discard puts it back, Ctrl+Enter saves and opens the
  /// next line.
  SheetStepActions _lineActions(int row) {
    final sheet = _controller.groupItemController;
    final rowKey = sheet.draftAt(row).rowKey;
    int at() => sheet.indexOfRowKey(rowKey);
    bool saved() {
      final i = at();
      return i >= 0 &&
          sheet.draftAt(i).entityId != null &&
          !sheet.draftAt(i).isDirtySinceSave;
    }

    Future<bool> save({bool openRaw = true}) async {
      final i = at();
      if (i < 0) return false;
      await _saveRow(i, openRaw: openRaw);
      return saved();
    }

    return SheetStepActions(
      title: () => 'Save part ${at() + 1}?',
      isDirty: () {
        final i = at();
        if (i < 0 || sheet.isRowLocked(i)) return false;
        final held = (_heldDies[rowKey]?.isNotEmpty ?? false) ||
            (_heldMachines[rowKey]?.isNotEmpty ?? false);
        return !saved() && (!sheet.isRowBlank(i) || held);
      },
      blockedReason: () {
        final i = at();
        if (i < 0) return null;
        final errors = sheet.errorsForRow(i);
        return errors.isEmpty ? null : errors.values.first.message;
      },
      save: save,
      discard: () {
        final i = at();
        if (i >= 0) _controller.discardRow(i);
      },
      saveAndAddAnother: () async {
        // Straight on to the next part: raw material waits.
        if (!await save(openRaw: false)) return;
        sheet.addRow();
        final first = PartRowsForm.lineColumns(sheet.sheetDef).firstOrNull;
        if (first != null) sheet.focusCell(first.id, row: sheet.rowCount - 1);
      },
      isLocked: () {
        final i = at();
        return i >= 0 && sheet.isRowLocked(i);
      },
      unlock: () {
        final i = at();
        if (i < 0) return;
        sheet.setRowLocked(i, false);
        sheet.selectRow(i);
        setState(() {});
      },
    );
  }

  /// The line's ×. A blank line goes at once; one holding anything — typed
  /// cells, or dies and machines waiting for its part — asks first, naming
  /// what goes with it. Those used to go without a word, the held dies on the
  /// next save.
  Future<void> _removeLine(int row) async {
    final sheet = _controller.groupItemController;
    if (row < 0 || row >= sheet.rowCount) return;
    final draft = sheet.draftAt(row);
    final key = draft.rowKey;
    final dies = _heldDies[key]?.length ?? 0;
    final machines = _heldMachines[key]?.length ?? 0;
    final typed = !sheet.isRowBlank(row);
    if (typed || dies > 0 || machines > 0) {
      String count(int n, String one) => '$n $one${n == 1 ? '' : 's'}';
      final held = [
        if (dies > 0) count(dies, 'die'),
        if (machines > 0) count(machines, 'machine'),
      ].join(' and ');
      final what = [
        if (typed) 'what was typed on this line',
        if (held.isNotEmpty) '$held waiting for it',
      ].join(', and ');
      final sure = await showConfirmDialog(
        context,
        title: 'Remove part ${row + 1}?',
        message: '${what[0].toUpperCase()}${what.substring(1)} '
            '${typed || dies + machines > 1 ? 'are' : 'is'} removed. '
            'None of it has been saved.',
        confirmLabel: 'Remove',
        destructive: true,
      );
      if (!mounted || sure != true) return;
    }
    // Looked up again: the line may have moved while the dialog was open.
    final at = sheet.indexOfDraft(draft);
    if (at < 0) return;
    setState(() {
      for (final die in _heldDies.remove(key) ?? const <DieSheetDraft>[]) {
        _madeDies.remove(die);
      }
      for (final machine
          in _heldMachines.remove(key) ?? const <MachineSheetDraft>[]) {
        _madeMachines.remove(machine);
      }
    });
    sheet.removeRow(at);
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

  /// A part line's photo — the size a person's is. A click opens the part's
  /// gallery: its views, up to five.
  Widget _rowPhoto(int row, {double size = 48}) {
    final id = _controller.groupItemController.draftAt(row).entityId;
    final part = id == null ? null : _partById(id);
    final name = part == null
        ? 'this part'
        : (part.displayName.trim().isEmpty ? part.name : part.displayName.trim());
    return MiniPhoto(
      owner: PhotoOwner.item,
      id: id?.toString(),
      size: size,
      what: 'part photo',
      fallbackUrl: part?.photoUrl,
      disabledReason: 'Save the part to add its photos',
      onOpen: id == null
          ? null
          : () => showPartPhotoGallery(context, itemId: '$id', partName: name),
    );
  }

  /// What a row's gutter chip says: saved, failed, or gone — status only.
  ///
  /// Rows commit one at a time, so without this a typist cannot tell which of
  /// fifty rows landed — every other signal on screen describes the sheet.
  /// The row's Save, and its Edit once saved, are at the END of the row
  /// ([_rowEndAction]); this gutter used to carry a second Save icon.
  Widget? _rowStatus(int row) {
    final sheet = _controller.groupItemController;
    final error = _controller.rowError(row);
    Widget chip({
      required String key,
      required IconData icon,
      required String tip,
      required Color color,
    }) => Tooltip(
      message: tip,
      child: SizedBox(
        key: ValueKey<String>(key),
        width: 28,
        height: 28,
        child: Icon(icon, size: 18, color: color),
      ),
    );

    if (_controller.isRowGone(row)) {
      return chip(
        key: 'row_gone_$row',
        icon: Icons.block_rounded,
        tip: error ?? 'This part is no longer in the catalogue.',
        color: SoftErpTheme.textMuted,
      );
    }
    if (error != null) {
      return chip(
        key: 'row_error_$row',
        icon: Icons.error_outline_rounded,
        tip: error,
        color: SoftErpTheme.dangerText,
      );
    }
    if (_controller.savedRows.contains(row)) {
      return chip(
        key: 'row_saved_$row',
        icon: Icons.check_circle_outline_rounded,
        tip: 'Saved as item #${sheet.draftAt(row).entityId}',
        color: SoftErpTheme.successText,
      );
    }
    return null;
  }

  /// The row's one Save, at the end of the row — and its Edit once saved.
  ///
  /// Save is drawn disabled, never hidden, until the row's required cells are
  /// filled; its tooltip names the first one missing. A saved row is closed
  /// (it shows its values and takes no input) until this same button's Edit.
  Widget? _rowEndAction(int row) {
    final sheet = _controller.groupItemController;
    if (row < 0 || row >= sheet.rowCount) return null;
    final saved = _controller.savedRows.contains(row);
    final locked = sheet.isRowLocked(row);

    // Deleted or archived (here or anywhere): there is nothing to edit, so
    // the button says why instead of offering an Edit that cannot save.
    final gone = _controller.isRowGone(row);
    if ((saved && locked) || gone) {
      return Tooltip(
        message: gone
            ? (_controller.rowError(row) ??
                  'This part is no longer in the catalogue.')
            : _savedLine(row),
        child: OutlinedButton.icon(
          key: ValueKey<String>('row_edit_$row'),
          onPressed: gone
              ? null
              : () {
                  sheet.setRowLocked(row, false);
                  sheet.selectRow(row);
                  setState(() {});
                },
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Edit', style: TextStyle(fontSize: 14)),
        ),
      );
    }

    return _savePartButton(
      row,
      key: 'row_save_$row',
      readyTip:
          saved ? 'Save the changes to this part' : 'Save this row\'s part',
    );
  }

  /// The Save part button: the row's own, and the one a held die's row shows,
  /// since a held die is written only with its part. Enabled once the row's
  /// required cells are filled; disabled, it names the first one missing.
  Widget _savePartButton(
    int row, {
    required String key,
    required String readyTip,
  }) {
    final sheet = _controller.groupItemController;
    final busy = _controller.isSavingNow;
    final savingThis = busy && identical(_savingDraft, sheet.draftAt(row));
    final blank = sheet.isRowBlank(row);
    final errors = sheet.errorsForRow(row);
    final String tip;
    if (blank) {
      tip = 'Type a part name first';
    } else if (errors.isNotEmpty) {
      tip = errors.values.first.message;
    } else if (busy) {
      tip = 'Still saving';
    } else {
      tip = readyTip;
    }
    // The same button as a person's Save contact, so the Saves on this page
    // look alike.
    return Tooltip(
      message: tip,
      child: AppButton(
        key: ValueKey<String>(key),
        label: 'Save part',
        icon: Icons.save_outlined,
        variant: AppButtonVariant.secondary,
        dense: true,
        isLoading: savingThis,
        onPressed: !blank && errors.isEmpty && !busy
            ? () => _saveRow(row)
            : null,
      ),
    );
  }

  /// "Saved as item #500 on 03 Nov 2026, 10:05" — the stamps the save wrote,
  /// which the line no longer draws as fields of their own.
  String _savedLine(int row) {
    final sheet = _controller.groupItemController;
    final draft = sheet.draftAt(row);
    final when = [
      for (final column in sheet.sheetDef.columns.where((c) => c.isStamp))
        draft.get(column.id)?.textValue?.trim() ?? '',
    ].where((t) => t.isNotEmpty && t != 'Set on save').join(', ');
    final what = 'Saved as item #${draft.entityId}';
    return when.isEmpty ? '$what — Edit to change it' : '$what on $when — Edit to change it';
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
  /// [openRaw]: once saved, raw material opens for it, editing, with the
  /// keyboard in it — the part is filled in, its sheet comes next.
  Future<void> _saveRow(int row, {bool openRaw = true}) async {
    final sheet = _controller.groupItemController;
    if (row < 0 || row >= sheet.rowCount) return;
    final before = sheet.draftAt(row);
    setState(() => _savingDraft = before);
    final bool ok;
    try {
      ok = await _controller.commitRow(row);
    } finally {
      _savingDraft = null;
    }
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
    } else if (before.entityId != null && !before.isDirtySinceSave) {
      // A saved part with nothing of its own to write: its Save still
      // attaches what is held for it — a die made on the last save whose link
      // did not go through is attached here, as the toast told them to do.
      await _flushStaged();
    }
    if (!mounted) return;
    final error = at < 0 ? null : _controller.rowError(at);
    // Saved — or already saved with nothing changed — closes the row. Not
    // while it holds an edit made during the save; that is still to write.
    final savedNow = at >= 0 &&
        error == null &&
        _controller.savedRows.contains(at) &&
        !sheet.draftAt(at).isDirtySinceSave;
    if (savedNow) sheet.setRowLocked(at, true);
    // The part is filled in and saved: raw material opens, editing, with the
    // keyboard in it.
    final rawFor = openRaw && savedNow && at == sheet.row
        ? sheet.draftAt(at).entityId
        : null;
    setState(() {
      if (rawFor != null) {
        _rawPanelOpen = true;
        _rawRolled = false;
        if (_rawPartId == rawFor) {
          _rawEditing = true;
        } else {
          _rawEditFor = rawFor;
        }
      }
    });
    _toast(error ?? _controller.statusBarMessage, isError: error != null);
    if (rawFor != null) {
      // Drawn for the part first: a part saved for the first time had no
      // raw step for the keyboard to move into until now.
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) _flow.focusStep(_rawStep);
    }
  }

  /// The deal line's Save on a saved part: the deal travels with its part's
  /// row, so re-commit it.
  Future<bool> _saveDeal() async {
    final row = _controller.dealRow ?? _controller.groupItemController.row;
    await _handleSave();
    if (!mounted) return false;
    return _controller.rowError(row) == null;
  }

  /// The breadcrumb's last step: the part the cursor is on, by name and
  /// code — "New part" only while that line is not saved. It used to be the
  /// title the screen was opened with, so a saved part read as new.
  String _crumbTitle() {
    if (_controller.groupItemController.draft.entityId == null) {
      return widget.title;
    }
    final name = _pinnedPartName().trim();
    final code = _partCodeNow.trim();
    if (name.isEmpty) return widget.title;
    return code.isEmpty ? name : '$name · $code';
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
        lineKey: _cursorRowKey,
        partSaved: _livePart != null,
        recordedAt: _livePart?.developedFor.at,
        flow: _flow,
        onSaveDeal: _saveDeal,
      );

  /// Cancel on the route panel. Stages laid out and not saved are asked
  /// about first — Cancel used to drop them without a word.
  Future<void> _cancelRoute() async {
    if (_routeDirty) {
      final discard = await showConfirmDialog(
        context,
        title: 'Discard route changes?',
        message: 'The stages laid out here are not saved. Discarding puts the '
            'part\'s route back as it was.',
        confirmLabel: 'Discard',
        destructive: true,
      );
      if (!mounted || discard != true) return;
    }
    setState(() {
      _showRoutePanel = false;
      _routeDirty = false;
    });
  }

  Widget _routing() {
    // The cursor row's own part — not `savedItemId`, which falls back to
    // whatever was saved last, so a new unsaved row read as saved and opened
    // the panel on somebody else's part.
    final rowPartId = _controller.groupItemController.draft.entityId;
    if (_showRoutePanel) {
      // Rebuilt with the row's id on every frame, so a save while the panel
      // is open lands in its Part field without closing it.
      return RouteCreationPanel(
        key: _routePanelKey,
        initialPartId: rowPartId,
        pendingPartName: rowPartId == null ? _pinnedPartName() : null,
        madeHereItemIds: _madeHere,
        onDirtyChanged: (dirty) {
          if (mounted && dirty != _routeDirty) setState(() => _routeDirty = dirty);
        },
        onSaved: (record) {
          setState(() {
            _showRoutePanel = false;
            _routeDirty = false;
          });
          _toast('Saved ${record.title}.');
          final id = _controller.groupItemController.draft.entityId;
          if (id != null) unawaited(_loadRoute(id));
        },
        onCancel: () => unawaited(_cancelRoute()),
      );
    }

    final hasPart = rowPartId != null;
    return Row(
      children: [
        Expanded(
          child: Text(
            hasPart
                ? 'This part can be routed through the process stages.'
                : 'Save the part to attach a route — you can lay out the '
                    'stages now.',
            style: const TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
          ),
        ),
        const SizedBox(width: 12),
        Tooltip(
          message: hasPart
              ? 'Author the stage order for this part'
              : 'Lay out the stages now; it attaches once the part is saved',
          child: AppButton(
            label: 'Author route',
            icon: Icons.route_rounded,
            variant: AppButtonVariant.secondary,
            dense: true,
            onPressed: () => setState(() => _showRoutePanel = true),
          ),
        ),
      ],
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
          // The heading's controls are clicked; Tab is for the fields below.
          SheetStep.noTab(Row(
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
                // Most of the room, so a narrow card wraps its chips rather
                // than pushing the actions off the end.
                Flexible(flex: 3, child: trailing),
              ],
              const SizedBox(width: 8),
              ..._sectionActions(id, heading),
            ],
          )),
          if (collapsed)
            // Folded: one row of what is in it. Tap to open.
            // Tab into a folded section unfolds it (the keyboard flow does).
            SheetStep.noTab(InkWell(
              key: ValueKey<String>('section_summary_$id'),
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
              onTap: () => _toggle(id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
                child: _SummaryLine(_sectionSummary(id)),
              ),
            )),
          // Folded is hidden, not thrown away: a route being laid out, a die
          // half typed, a raw sheet being edited all live in the body, and
          // building it only when open disposed them on every fold.
          Visibility(
            visible: !collapsed,
            maintainState: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [const SizedBox(height: 12), body],
            ),
          ),
        ],
      ),
    );
  }
}

/// A folded section's one line: labels muted, what was entered in the ink,
/// pairs split by a dot. Clipped at the card's edge, so the whole of it is on
/// the tooltip — one pair per line.
class _SummaryLine extends StatelessWidget {
  const _SummaryLine(this.pairs);

  final List<(String?, String)> pairs;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    for (final (i, (label, value)) in pairs.indexed) {
      if (i > 0) {
        spans.add(TextSpan(
          // A record's own name starts a new one: a wider gap before it.
          text: label == null ? '   |   ' : '  ·  ',
          style: const TextStyle(color: SoftErpTheme.textMuted),
        ));
      }
      if (label != null) {
        spans.add(TextSpan(
          text: '$label ',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: SoftErpTheme.textSecondary,
          ),
        ));
      }
      spans.add(TextSpan(
        text: value,
        style: TextStyle(
          fontWeight: label == null ? FontWeight.w800 : FontWeight.w700,
          color: SoftErpTheme.textPrimary,
        ),
      ));
    }
    return Tooltip(
      message: [
        for (final (label, value) in pairs) label == null ? value : '$label: $value',
      ].join('\n'),
      waitDuration: const Duration(milliseconds: 400),
      child: Text.rich(
        TextSpan(children: spans),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
    );
  }
}

/// One level of the section tree: indented by [depth], with the guides a file
/// tree draws — `├─` / `└─` into this section, and a `│` for each ancestor
/// that still has a sibling to come.
class _TreeNode extends StatelessWidget {
  const _TreeNode({
    required this.indent,
    required this.depth,
    required this.continues,
    required this.isLast,
    required this.child,
  });

  /// The step per level, with room to spare and without.
  static const double wideIndent = 28;
  static const double compactIndent = 14;

  final double indent;
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
            painter: _TreeGuidePainter(
              indent: indent,
              depth: depth,
              continues: continues,
              isLast: isLast,
            ),
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
  _TreeGuidePainter({
    required this.indent,
    required this.depth,
    required this.continues,
    required this.isLast,
  });

  final double indent;
  final int depth;
  final List<bool> continues;
  final bool isLast;

  /// Where a level's line runs: most of the way across its step (22 of 28).
  double get _offset => indent * 22 / 28;
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
      final x = level * indent + _offset;
      canvas.drawLine(Offset(x, -18), Offset(x, size.height), paint);
    }
    // This node: down from the parent, across into the card; on past it when
    // a sibling follows (├), stopping at the elbow when it is the last (└).
    final x = (depth - 1) * indent + _offset;
    canvas.drawLine(Offset(x, -18), Offset(x, isLast ? _elbowY : size.height), paint);
    canvas.drawLine(Offset(x, _elbowY), Offset(depth * indent, _elbowY), paint);
  }

  @override
  bool shouldRepaint(_TreeGuidePainter old) =>
      old.indent != indent ||
      old.depth != depth ||
      old.isLast != isLast ||
      !listEquals(old.continues, continues);
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

  static const _heading = SheetStyle.subHeading;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _editing ? 'Options for ${widget.editing!.name}' : 'Add a property',
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

/// The date and time in the Item Master heading. Given a [date], it is the
/// part's stamp; without one it is the clock, moved on each minute, for a part
/// the save has not stamped yet.
class _HeadingStamp extends StatefulWidget {
  const _HeadingStamp({required String this.date, this.time});
  const _HeadingStamp.now()
      : date = null,
        time = null;

  final String? date;
  final String? time;

  @override
  State<_HeadingStamp> createState() => _HeadingStampState();
}

class _HeadingStampState extends State<_HeadingStamp> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(_HeadingStamp old) {
    super.didUpdateWidget(old);
    _schedule();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Wakes at the next minute — only while it is showing the clock.
  void _schedule() {
    _tick?.cancel();
    _tick = null;
    if (widget.date != null) return;
    final now = DateTime.now();
    _tick = Timer(Duration(seconds: 60 - now.second), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  Widget build(BuildContext context) {
    final saved = widget.date != null;
    final now = DateTime.now();
    final date = widget.date ?? partStampDate(now);
    final time = saved ? widget.time : partStampTime(now);
    final colour = saved ? SoftErpTheme.textPrimary : SoftErpTheme.textMuted;
    return Tooltip(
      message: saved
          ? 'Saved on $date${time == null ? '' : ' at $time'}'
          : 'Not saved yet — saving stamps the date and time',
      child: Container(
        key: const ValueKey<String>('part_heading_stamp'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: SoftErpTheme.sectionSurface,
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
          border: Border.all(color: SoftErpTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_rounded, size: 16, color: colour),
            const SizedBox(width: 6),
            Text(
              date,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colour),
            ),
            if (time != null) ...[
              const SizedBox(width: 10),
              Icon(Icons.schedule_rounded, size: 16, color: colour),
              const SizedBox(width: 6),
              Text(
                time,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colour),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The part's photos beside the sheet while it is being worked on: one large,
/// the other views under it, and the gallery a click away. The same photos
/// as the line's thumbnail — read from the part's gallery, and read again
/// when they change ([EntityPhotosProvider.revisionOf]: a phone shot, a
/// gallery Save).
class _PartPhotosSection extends StatefulWidget {
  const _PartPhotosSection({
    super.key,
    required this.partId,
    required this.partName,
  });

  /// Null until the part is saved: photos are kept on a part.
  final int? partId;
  final String partName;

  @override
  State<_PartPhotosSection> createState() => _PartPhotosSectionState();
}

class _PartPhotosSectionState extends State<_PartPhotosSection> {
  EntityPhotosProvider? _store;
  List<PartPhoto> _photos = const [];
  bool _loading = false;
  String? _error;
  int _revision = -1;

  /// The photo drawn large: the one clicked, else the main one.
  int? _shownId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.read<EntityPhotosProvider>();
    if (!identical(store, _store)) {
      _store?.removeListener(_onStoreChanged);
      _store = store..addListener(_onStoreChanged);
      _revision = -1;
      _reload();
    }
  }

  @override
  void didUpdateWidget(covariant _PartPhotosSection old) {
    super.didUpdateWidget(old);
    if (old.partId != widget.partId) {
      _photos = const [];
      _shownId = null;
      _error = null;
      _revision = -1;
      _reload();
    }
  }

  @override
  void dispose() {
    _store?.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() => _reload();

  /// Reads the part's photos when there is a part and its photos changed.
  void _reload() {
    final id = widget.partId;
    final store = _store;
    if (id == null || store == null) return;
    final revision = store.revisionOf(PhotoOwner.item, '$id');
    if (revision == _revision) return;
    _revision = revision;
    unawaited(_load(id));
  }

  Future<void> _load(int id) async {
    if (_photos.isEmpty) setState(() => _loading = true);
    try {
      final photos = await _store!.partPhotos('$id');
      // Another part was picked meanwhile: its own read answers for it.
      if (!mounted || widget.partId != id) return;
      setState(() {
        _photos = photos;
        _loading = false;
        _error = null;
        if (!photos.any((p) => p.id == _shownId)) _shownId = null;
      });
    } catch (error) {
      if (!mounted || widget.partId != id) return;
      setState(() {
        _loading = false;
        _error = 'The photos did not load: $error';
      });
    }
  }

  Future<void> _openGallery() async {
    final id = widget.partId;
    if (id == null) return;
    await showPartPhotoGallery(
      context,
      itemId: '$id',
      partName: widget.partName,
      openOn: _shownId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.partId;
    if (id == null) {
      return _note(
        Icons.add_a_photo_outlined,
        'Save the part to add its photos',
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) return _note(Icons.broken_image_outlined, error);
    if (_photos.isEmpty) {
      return _note(
        Icons.add_a_photo_outlined,
        'No photos of ${widget.partName} yet',
        action: 'Add photos',
      );
    }
    final shown = _photos.where((p) => p.id == _shownId).firstOrNull ??
        _photos.where((p) => p.isPrimary).firstOrNull ??
        _photos.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(SheetStyle.cardPadding, 4, SheetStyle.cardPadding, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: InkWell(
              key: const ValueKey<String>('part_photos_large'),
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
              onTap: _openGallery,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
                child: ColoredBox(
                  color: SoftErpTheme.sectionSurface,
                  child: Image.network(
                    shown.viewUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(Icons.broken_image_outlined, size: 32, color: SoftErpTheme.textMuted),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final photo in _photos) ...[
                _thumb(photo, selected: identical(photo, shown)),
                const SizedBox(width: 8),
              ],
              const Spacer(),
              TextButton.icon(
                key: const ValueKey<String>('part_photos_manage'),
                onPressed: _openGallery,
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: Text(
                  '${_photos.length} of $maxPartPhotos',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _thumb(PartPhoto photo, {required bool selected}) {
    return Tooltip(
      message: photo.isPrimary ? 'The main photo' : 'Show this view',
      child: InkWell(
        key: ValueKey<String>('part_photos_thumb_${photo.id}'),
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        onTap: () => setState(() => _shownId = photo.id),
        child: Container(
          width: 52,
          height: 52,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
            border: Border.all(
              color: selected ? SoftErpTheme.accent : SoftErpTheme.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Image.network(
            photo.thumbUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, size: 18),
          ),
        ),
      ),
    );
  }

  /// Nothing to show yet: why, and the way to add some when there is one.
  Widget _note(IconData icon, String text, {String? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SheetStyle.cardPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: SoftErpTheme.textMuted),
            const SizedBox(height: 8),
            Text(
              text,
              key: const ValueKey<String>('part_photos_note'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
            ),
            if (action != null) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const ValueKey<String>('part_photos_add'),
                onPressed: _openGallery,
                icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                label: Text(action, style: const TextStyle(fontSize: 14)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
