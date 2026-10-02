import '../../../../core/app_flow_hooks.dart';
import '../../../../core/services/feature_flags.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../items/domain/item_definition.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../../items/presentation/screens/items_screen.dart';
import '../../../links/data/entity_link_service.dart';
import '../../../links/domain/entity_link.dart';
import '../../../links/presentation/widgets/link_columns.dart';
import '../../../units/presentation/providers/units_provider.dart';
import '../../domain/group_definition.dart';
import '../../domain/group_inputs.dart';
import '../providers/groups_provider.dart';
import 'creation_sessions.dart';
import 'creation_wizard_kinds.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Builds the item editor for the middle tile, filing into [groupId] when
/// there is one. [onClosed] gets the saved item, or null when the editor was
/// closed without one.
typedef ComponentItemEditorBuilder =
    Widget Function(
      BuildContext context, {
      required int? groupId,
      required ItemDefinition? item,
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
    this.sessions,
    this.linkService,
  });

  /// The recents list in the title bar: this workspace files what it saves
  /// into it, and answers when one is picked.
  final CreationSessionController? sessions;

  /// The link graph behind the last column. Read from the Provider tree when
  /// null; passed in by tests, and by a host that has no Provider for it.
  final EntityLinkService? linkService;

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
    this.linkService,
  });

  final GroupDefinition? component;

  /// See [ComponentCreationWorkspace.linkService].
  final EntityLinkService? linkService;

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
  late final CreationSessionController _sessions = CreationSessionController()
    ..load();

  @override
  void dispose() {
    _sessions.dispose();
    super.dispose();
  }

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
          maxWidth: _creationDialogWidth(size.width),
          maxHeight: size.height - 56,
        ),
        child: Column(
          children: [
            _Header(
              title: widget.itemsOnly ? 'Item creation' : 'Component creation',
              componentName: _component?.name,
              sessions: _sessions,
              onClose: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ComponentCreationWorkspace(
                  sessions: _sessions,
                  component: widget.component,
                  itemEditorBuilder: widget.itemEditorBuilder,
                  itemsOnly: widget.itemsOnly,
                  linkService: widget.linkService,
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

/// A link-graph master -> the creation wizard's editor for it.
///
/// The two catalogs are declared apart on purpose: the server's says what can
/// be linked, this app's says what has an editor here, and they are not the
/// same list. A master missing from this map simply has no "New …" button in
/// the + menu — its existing records can still be attached.
///
/// The item is absent deliberately: this window's middle column IS the item
/// editor, so there is no second one to open over it.
const Map<String, String> _linkTypeToKind = {
  CreationKinds.die: CreationKinds.die,
  CreationKinds.machine: CreationKinds.machine,
  'material': 'material',
  'unit': 'unit',
  'client': 'client',
  'vendor': 'vendor',
  'employee': 'employee',
  'department': 'department',
  'group': 'item_group',
};

/// The same pairing read the other way: a tile's kind -> the master it is in
/// the link graph. Mostly the same word; the wizard's two group editors both
/// land on the graph's single `group`.
String? _linkTypeOf(String kindKey) {
  if (kindKey == CreationKinds.item) return 'item';
  if (kindKey == 'item_group' || kindKey == 'machine_group') return 'group';
  for (final entry in _linkTypeToKind.entries) {
    if (entry.value == kindKey) return entry.key;
  }
  return null;
}

/// The lineup column. Wider than it was, because its rows carry a drag handle,
/// an icon, a label, a chevron, a count and now three buttons.
///
/// The width is not cosmetic. At 264 the label's Expanded was squeezed to
/// about 44pt, which pushed the link button onto the row's CENTRE — so
/// clicking the middle of a tile to select it opened the link menu instead.
/// A row has to leave its label enough space that the buttons stay at the end
/// of it, where they look like they are.
const double _lineupWidth = 296;

/// The reference tile on the right. Narrowed to pay for the lineup's extra
/// width: the editor could not pay, because its own footer buttons overflow
/// below roughly 1016 and that is the one panel with no give in it.
const double _referenceWidth = 356;

/// The Miller columns that branch off the lineup: the gap between two of them,
/// the rail that carries the chevron, and the gaps that set the whole strip
/// off from the lineup it grows out of.
const double _branchColumnGap = 12;
const double _branchRailWidth = 30;
const double _branchLeadGap = 14;
const double _branchRailGap = 10;
const double _branchChrome =
    _branchLeadGap + _branchRailWidth + _branchRailGap;

/// Shut, the strip is just the rail — enough to get it open again.
const double _branchShutWidth = _branchLeadGap + _branchRailWidth;

/// How narrow a link column may get before it stops being readable, and how
/// wide it is worth making on a big screen.
const double _branchColumnMin = 218;
const double _branchColumnMax = 300;

/// How many link columns fit on a window this wide, and how wide each may be.
/// Null when not even one fits.
///
/// Sized rather than fixed, because a fixed width that fits a 1760pt window
/// silently falls back to one column on a 1710pt one — which is the size of
/// laptop this gets used on, and the fallback is invisible: you just never see
/// the second column and have no way to tell why.
///
/// The reference tile is NOT in the reserved sum, because it stands down while
/// the columns are open — see [_ComponentCreationWorkspaceState.build]. Its
/// 380 is most of what two readable columns cost, and the alternative was
/// squeezing the editor until the item form overflowed its own fields.
({int columns, double width})? _branchFit(double shell) {
  // The lineup, the gaps around the editor, and the editor's own floor. The
  // floor is measured, not chosen: the real item form overflows its own fields
  // below roughly 690, and a test pumps it at the laptop width to keep that
  // honest.
  const reserved = _lineupWidth + 28 + 700;
  // (the reference tile is not here: it stands down while the columns are up)
  final forColumns = shell - reserved - _branchChrome;
  final two = (forColumns - _branchColumnGap) / 2;
  if (two >= _branchColumnMin) {
    return (columns: 2, width: math.min(two, _branchColumnMax));
  }
  if (forColumns >= _branchColumnMin) {
    return (columns: 1, width: math.min(forColumns, _branchColumnMax));
  }
  return null;
}

/// How wide the strip is with that many columns of that width open.
double _branchWidth(int columns, double columnWidth) =>
    _branchChrome +
    columns * columnWidth +
    (columns - 1) * _branchColumnGap;

/// How wide the creation window's content is on a screen this wide.
///
/// The dialog sizes itself from this and the workspace reads it back, rather
/// than measuring: measuring would mean a LayoutBuilder around the row, which
/// is what broke the lineup (see [_ComponentCreationWorkspaceState.build]).
/// One formula, so the two cannot disagree about the box.
double _creationDialogWidth(double screenWidth) =>
    screenWidth - 56 >= 1800 ? 1760 : screenWidth - 56;

/// The same, minus the padding the workspace sits in.
double _shellWidth(BuildContext context) =>
    _creationDialogWidth(MediaQuery.sizeOf(context).width) - 32;

CreationKindSpec get _dieKind => CreationKinds.byKey(CreationKinds.die);
CreationKindSpec get _machineKind => CreationKinds.byKey(CreationKinds.machine);

bool _isAssetKey(String key) =>
    key == CreationKinds.die || key == CreationKinds.machine;

/// One tile in the first column: an open form, with whatever is half-typed in
/// it. A kind can appear more than once — a second item that shares the die
/// you just made is a second Item tile, not a second window.
class _LineupEntry {
  _LineupEntry({required this.id, required this.kind});

  final String id;
  final String kind;

  /// Bumped after a save or cancel so this tile's form comes back empty.
  int generation = 0;

  /// Die and machine tiles: the item this one is being added to.
  int? targetItemId;

  /// Item tiles: the saved item reopened here (null means a new one), and the
  /// controller behind its sub-tabs.
  ItemDefinition? editingItem;
  ItemWorkflowController? controller;

  /// The record this tile currently stands for, once it has saved or opened
  /// one: what a link made from this tile attaches, and what the column that
  /// hangs off it is about. Null while the form is still blank — there is
  /// nothing yet to link.
  LinkRef? subject;

  bool get isItem => kind == CreationKinds.item;
}

class _ComponentCreationWorkspaceState
    extends State<ComponentCreationWorkspace> {
  GroupDefinition? _component;

  /// The first column, in order. Its top tile is what the last column shows.
  /// Starts as Item / Die / Machine; tiles can be removed, dragged, duplicated
  /// and added from the + menu. Lives as long as the window.
  late final List<_LineupEntry> _lineup = [
    for (final kind in CreationKinds.defaults) _makeEntry(kind),
  ];
  late String _activeId = _lineup.first.id;

  /// The item tile whose sub-tabs are listed: the open one, or the one that
  /// was open last, so they stay clickable while a die sits in front.
  late String? _stepsOwnerId = _lineup.first.id;
  int _entrySeq = 0;

  /// Everything the middle column saved in this window, newest first.
  final Map<String, List<CreatedRecord>> _added = {};

  bool _itemStepsOpen = true;
  String? _flashRecordKey;

  /// How many links each record this window has shown is known to have, so the
  /// columns can stay out of the way until there IS something in them. Fed by
  /// the columns' own reads and bumped straight away when this window makes a
  /// link itself.
  final Map<String, int> _linkCounts = {};
  final Set<String> _linkCountsInFlight = {};

  /// Whether the link columns are open. Shut, the strip is just its rail and
  /// the editor has the width back; the chevron on the rail toggles it.
  bool _branchOpen = true;

  /// A tile is being dragged sideways out of the lineup. The 1.1 column opens
  /// on the gesture rather than on the drop, so the place to let go is on
  /// screen before the pointer gets there.
  bool _dragging = false;

  final Set<int> _expandedIds = {};
  int? _flashId;
  bool _busy = false;

  /// Items saved in this window; what the last column lists in [itemsOnly].
  final Set<int> _addedItemIds = {};

  /// The group the last saved item went into; seeds the next one.
  int? _lastItemGroupId;

  /// This sitting, as the recents list will remember it.
  late CreationSession _session = CreationSession(
    id: 's${DateTime.now().microsecondsSinceEpoch}',
    savedAt: DateTime.now(),
    records: const [],
  );

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();

  /// Tells the link columns to re-read after this window changes the graph by
  /// its own means — saving a die in the middle editor and attaching it to the
  /// item a column is showing.
  final LinkColumnsController _linkColumns = LinkColumnsController();

  @override
  void initState() {
    super.initState();
    _component = widget.component;
    _nameController.addListener(() => setState(() {}));
    _searchController.addListener(() => setState(() {}));
    widget.sessions?.onRestore = _restoreSession;
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
    _linkColumns.dispose();
    if (widget.sessions?.onRestore == _restoreSession) {
      widget.sessions?.onRestore = null;
    }
    for (final entry in _lineup) {
      entry.controller
        ?..removeListener(_onItemWorkflowChanged)
        ..dispose();
    }
    super.dispose();
  }

  void _onItemWorkflowChanged() {
    if (mounted) setState(() {});
  }

  /// A fresh tile. Item tiles get their own step controller, so two of them
  /// can sit in the lineup with separate progress.
  _LineupEntry _makeEntry(String kind) {
    final entry = _LineupEntry(id: '$kind#${_entrySeq++}', kind: kind);
    if (entry.isItem) {
      entry.controller = ItemWorkflowController()
        ..addListener(_onItemWorkflowChanged);
    }
    return entry;
  }

  _LineupEntry get _activeEntry =>
      _lineup.firstWhere((e) => e.id == _activeId, orElse: () => _lineup.first);

  Iterable<_LineupEntry> get _itemEntries => _lineup.where((e) => e.isItem);

  bool get _naming => !widget.itemsOnly && _component == null;

  List<ItemDefinition> _componentItems(List<ItemDefinition> all) {
    final component = _component;
    if (component == null && !widget.itemsOnly) return const [];
    return all
        .where(
          (item) =>
              !item.isArchived &&
              (component == null
                  ? _addedItemIds.contains(item.id) ||
                        _itemEntries.any(
                          (entry) => entry.controller?.savedItemId == item.id,
                        )
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

  /// From the first column: brings that tile's form forward. Every tile stays
  /// mounted, so what is half-typed in the others is still there on return.
  void _selectEntry(String id) {
    if (id == _activeId || _naming) return;
    setState(() {
      _activeId = id;
      if (_activeEntry.isItem) _stepsOwnerId = id;
    });
  }

  /// A sub-tab under an Item tile, from wherever the wizard is: brings that
  /// tile forward and opens the page.
  void _openItemStep(_LineupEntry entry, int index) {
    _selectEntry(entry.id);
    entry.controller?.open(index);
  }

  /// The + menu, or a tile's own +: another form of that kind, opened. A kind
  /// already in the lineup gets a second tile rather than being refused —
  /// a second item that shares the die you just made needs one.
  void _addKind(String kind) {
    setState(() {
      final entry = _makeEntry(kind);
      _lineup.add(entry);
      _activeId = entry.id;
      if (entry.isItem) _stepsOwnerId = entry.id;
    });
  }

  /// A tile's ×. The lineup never goes empty.
  void _removeEntry(_LineupEntry entry) {
    if (_lineup.length <= 1) return;
    setState(() {
      _lineup.remove(entry);
      entry.controller
        ?..removeListener(_onItemWorkflowChanged)
        ..dispose();
      if (_activeId == entry.id) _activeId = _lineup.first.id;
      if (_stepsOwnerId == entry.id)
        _stepsOwnerId = _itemEntries.firstOrNull?.id;
    });
  }

  void _reorderKinds(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      _lineup.insert(newIndex, _lineup.removeAt(oldIndex));
    });
  }

  /// From an item's + Die / + Machine: opens that editor, aimed at the item.
  /// Reuses the first tile of that kind, or adds one when there is none.
  void _addUnder(int itemId, String kind) {
    final existing = _lineup.where((entry) => entry.kind == kind).firstOrNull;
    setState(() {
      final entry = existing ?? _makeEntry(kind);
      if (existing == null) _lineup.add(entry);
      entry.targetItemId = itemId;
      entry.generation++;
      _activeId = entry.id;
      _expandedIds.add(itemId);
    });
  }

  void _setDragging(bool dragging) {
    if (_dragging == dragging) return;
    setState(() => _dragging = dragging);
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
        _activeId = _lineup.first.id;
      });
      widget.onComponentChanged?.call(created);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Files a save into this sitting, so the recents list can bring the whole
  /// combination back later.
  void _remember(String kind, String id, String title) {
    _session = _session.plus(
      CreationSessionRecord(kind: kind, id: id, title: title),
    );
    widget.sessions?.remember(_session);
  }

  void _onItemClosed(_LineupEntry entry, ItemDefinition? saved) {
    if (saved != null) {
      _remember(CreationKinds.item, '${saved.id}', saved.displayName);
      _linkColumns.refresh();
    }
    setState(() {
      if (saved != null) {
        // The tile now stands for what it just saved, so the column beside it
        // is about that item rather than about nothing.
        entry.subject = _refForItem(saved);
        _flashId = saved.id;
        _addedItemIds.add(saved.id);
        // Saved and done with: the form comes back blank for the next one.
        entry.editingItem = null;
        // A run of items usually goes into the same group, so the next form
        // starts where the last one did.
        _lastItemGroupId = saved.groupId;
      }
      entry.generation++;
    });
  }

  /// The middle column saved a record: list it on the right straight away, and
  /// for a die or machine aimed at an item, attach it there too.
  void _onRecordSaved(_LineupEntry entry, CreatedRecord record) {
    _remember(entry.kind, record.id, record.title);
    setState(() {
      (_added[entry.kind] ??= []).insert(0, record);
      _flashRecordKey = '${entry.kind}:${record.id}';
      if (_linkTypeOf(entry.kind) case final type?) {
        entry.subject = LinkRef(
          type: type,
          id: record.id,
          label: record.title,
          subtitle: record.subtitle ?? '',
        );
      }
      entry.generation++;
    });
    if (_isAssetKey(entry.kind)) {
      _linkToTarget(entry, record.id);
    } else {
      // A record saved here may be linked to something a column is showing.
      _linkColumns.refresh();
    }
  }

  /// Attaches a saved die or machine to the target item, keeping whatever the
  /// item already carries.
  Future<void> _linkToTarget(_LineupEntry entry, String id) async {
    final kind = CreationKinds.byKey(entry.kind);
    final items = context.read<ItemsProvider>();
    final target = items.items
        .where((item) => item.id == entry.targetItemId)
        .firstOrNull;
    if (target == null) return;
    final saved = entry.kind == CreationKinds.die
        ? await items.setItemLinks(
            target.id,
            dieIds: [...target.dies.map((die) => die.id), id],
          )
        : await items.setItemLinks(
            target.id,
            machineIds: [...target.machines.map((machine) => machine.id), id],
          );
    if (!mounted) return;
    if (saved != null) {
      // The item a column may be showing just gained a die or a machine.
      _linkColumns.refresh();
      return;
    }
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
    final linkService = _linkService;

    // The links hang off the FIRST column, not the last: a tile there is the
    // record being worked on, so the column that opens beside it is that
    // record's own — a 1.1 to the lineup's 1. The reference tile on the right
    // keeps its place.
    final subject = _activeEntry.subject;

    // How many link columns fit beside the editor, and how wide. Taken from
    // the window, NOT from a LayoutBuilder around this row.
    //
    // It was a LayoutBuilder, and that put the lineup's ReorderableListView
    // inside a layout callback: any width change rebuilt its items during
    // layout, and reactivating an item's global key brings its tooltips'
    // OverlayPortals back with it, which marks the overlay dirty while a
    // _RenderLayoutBuilder is mid-performLayout. Flutter asserts on that. The
    // window's width is a plain dependency and answers the same question, so
    // there is nothing to put the list inside.
    final fit = linkService == null ? null : _branchFit(_shellWidth(context));
    // The columns are for reading a chain, so they wait until there is a chain
    // to read. Before that the way in is the link button on the tile's own
    // row — a column standing empty teaches less than a button that says what
    // it does, and costs the editor its width to do it.
    _ensureLinkCount(subject);
    final linked = subject != null && (_linkCounts[subject.key] ?? 0) > 0;
    // A drag is the exception: it needs somewhere to let go, and that has to
    // be on screen before the pointer gets there.
    final open = fit != null && (linked || _dragging) && (_branchOpen || _dragging);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _lineupWidth,
          child: _BentoTile(
            child: _buildKindColumn(items, fit != null, linkService != null),
          ),
        ),
        // The strip is here from the start, not only once something has been
        // saved. Its whole job is to show what links to what, and a control
        // that shows up only after you have already done the thing it is for
        // cannot teach you it exists — which is how the chevron and the second
        // column went unseen.
        if (fit != null && (linked || _dragging))
          _buildLinkBranch(linkService!, subject, fit, open),
        const SizedBox(width: 14),
        Expanded(child: _BentoTile(child: _buildMiddle(items))),
        // The reference tile gives way to the columns rather than sharing the
        // row with them. Its 380 is most of what a second readable column
        // costs, and the editor cannot give that up — squeezed to 430 the item
        // form overflows its own fields. The chevron swaps between the two.
        if (!open) ...[
          const SizedBox(width: 14),
          SizedBox(
            width: _referenceWidth,
            child: _BentoTile(
              // Whatever the top tile is, viewed: the first column picks, the
              // last one shows what picking it has produced.
              child: _lineup.first.isItem
                  ? _buildItemsColumn(items, unitSymbols)
                  : _buildRecordsColumn(
                      CreationKinds.byKey(_lineup.first.kind),
                    ),
            ),
          ),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 1.1 — the link column that branches off the selected tile
  // -------------------------------------------------------------------------

  /// The column that rises beside the lineup, and the drop zone over it.
  ///
  /// It is a drag target as well as a column: a tile dragged sideways out of
  /// the lineup lands here and is linked to whatever the lineup has selected,
  /// which is the quickest way to say "this die belongs to that item" when
  /// both were just made in this window.
  /// The strip that branches off the lineup: a rail carrying the chevron, and
  /// behind it the Miller columns themselves.
  ///
  /// Two columns, so a chain reads without being walked: the selected tile's
  /// links in the first, and the links of whatever is picked there in the
  /// second. An item's dies, then that die's machines — or a die's items, then
  /// that item's machines, since nothing here privileges a direction.
  ///
  /// It is a drag target as well: a tile dragged sideways out of the lineup
  /// lands here and is linked to whatever the lineup has selected, which is
  /// the quickest way to say "this die belongs to that item" when both were
  /// just made in this window.
  Widget _buildLinkBranch(
    EntityLinkService service,
    LinkRef? subject,
    ({int columns, double width}) fit,
    bool open,
  ) {
    final full = _branchWidth(fit.columns, fit.width);
    final columnsWidth = full - _branchChrome;

    return AnimatedContainer(
      key: const ValueKey('creation_link_branch'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: open ? full : _branchShutWidth,
      child: ClipRect(
        // Laid out at its full width whatever the animation is doing, so the
        // columns do not reflow on every frame of opening.
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: full,
          maxWidth: full,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(width: _branchLeadGap),
              SizedBox(
                width: _branchRailWidth,
                child: _BranchRail(
                  open: open,
                  onToggle: () => setState(() => _branchOpen = !_branchOpen),
                ),
              ),
              const SizedBox(width: _branchRailGap),
              SizedBox(
                width: columnsWidth,
                child: AnimatedOpacity(
                  // Sits back a little while it is only showing where a
                  // record's links WOULD go.
                  opacity: subject == null ? 0.7 : 1,
                  duration: const Duration(milliseconds: 180),
                  child: _buildBranchColumns(service, subject, fit),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBranchColumns(
    EntityLinkService service,
    LinkRef? subject,
    ({int columns, double width}) fit,
  ) {
    return DragTarget<LinkRef>(
      onWillAcceptWithDetails: (details) =>
          subject != null && details.data != subject && details.data.id.isNotEmpty,
      onAcceptWithDetails: (details) => _linkDropped(service, details.data),
      builder: (context, candidate, _) {
        final hovering = candidate.isNotEmpty;
        return Stack(
          children: [
            if (subject != null)
              Positioned.fill(
                child: LinkColumns(
                  key: const ValueKey('creation_link_columns'),
                  service: service,
                  anchor: subject,
                  controller: _linkColumns,
                  columnWidth: fit.width,
                  minColumns: fit.columns,
                  onAnchorTotal: (total) => _noteLinkCount(subject, total),
                  addAtBottom: true,
                  onCreate: _createForLink,
                ),
              )
            else
              Positioned.fill(
                key: const ValueKey('creation_link_hint'),
                child: _LinkBranchHint(fit: fit),
              ),
            if (hovering)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: SoftErpTheme.accentSoft.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(
                        SoftErpTheme.radiusLg,
                      ),
                      border: Border.all(color: SoftErpTheme.accent, width: 2),
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Link to ${subject?.label ?? ''}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: SoftErpTheme.accentDeeper,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Asks how many links a record has, once per record.
  ///
  /// The columns cannot answer this: they are only built when the answer is
  /// already known to be more than zero, so leaving it to them would mean they
  /// never appeared at all. This is the one read that has to happen whether
  /// they are on screen or not.
  void _ensureLinkCount(LinkRef? subject) {
    final service = _linkService;
    if (service == null || subject == null) return;
    if (_linkCounts.containsKey(subject.key) ||
        !_linkCountsInFlight.add(subject.key)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final links = await service.fetchLinks(subject.type, subject.id);
        if (mounted) setState(() => _linkCounts[subject.key] = links.total);
      } catch (_) {
        // Links this user cannot read, or a server that did not answer. Not
        // worth interrupting item creation over: the row's link button still
        // works and says so itself if the link is refused.
        if (mounted) setState(() => _linkCounts[subject.key] = 0);
      } finally {
        _linkCountsInFlight.remove(subject.key);
      }
    });
  }

  void _noteLinkCount(LinkRef? subject, int total) {
    if (subject == null || _linkCounts[subject.key] == total) return;
    // Out of a build, since this arrives from the columns' own fetch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _linkCounts[subject.key] = total);
    });
  }

  /// The link button on a lineup row: the same gesture as a column's +, from
  /// a tile that may not have a column open at all. This is how the first link
  /// on a record gets made, which is why it does not depend on the columns
  /// being there.
  Future<void> _linkFromTile(_LineupEntry entry, Offset at) async {
    final service = _linkService;
    final subject = entry.subject;
    if (service == null || subject == null) return;
    final picked = await showLinkAttach(
      context,
      service: service,
      subject: subject,
      at: at,
      onCreate: _createForLink,
    );
    if (picked == null || !mounted) return;
    setState(() {
      // Optimistic, so the columns open on the link that was just made rather
      // than a frame later; the columns' own read corrects it either way.
      _linkCounts[subject.key] = (_linkCounts[subject.key] ?? 0) + 1;
    });
    _linkColumns.refresh();
  }

  /// A tile dropped on the link columns: link what it stands for to whatever the
  /// lineup has selected.
  Future<void> _linkDropped(EntityLinkService service, LinkRef dropped) async {
    final subject = _activeEntry.subject;
    if (subject == null) return;
    try {
      await service.link(
        fromType: subject.type,
        fromId: subject.id,
        toType: dropped.type,
        toId: dropped.id,
      );
    } catch (error) {
      if (mounted) _toast('$error');
      return;
    }
    if (!mounted) return;
    showAppToast(
      context,
      '${dropped.label} linked to ${subject.label}.',
      kind: AppToastKind.success,
    );
    setState(() {
      _linkCounts[subject.key] = (_linkCounts[subject.key] ?? 0) + 1;
    });
    _linkColumns.refresh();
  }

  /// The link graph, or null when this window should not show it: the flag is
  /// off, or no service was given and none is in the Provider tree.
  EntityLinkService? get _linkService {
    if (!FeatureFlags.isEnabled(FeatureKeys.mastersLinkColumns)) return null;
    final injected = widget.linkService;
    if (injected != null) return injected;
    try {
      return context.read<EntityLinkService>();
    } catch (_) {
      // No provider: the host has not wired the link API, so the reference
      // tile stays. Not an error — a host that does not provide a flow
      // degrades to hiding it, as with the editor hooks.
      return null;
    }
  }

  /// The + menu's "New …" entry for a master: opens that master's real editor
  /// over the window and hands back the saved record for the column to link.
  Future<LinkRef?> _createForLink(BuildContext context, String type) async {
    final kindKey = _linkTypeToKind[type];
    if (kindKey == null) return null;
    final kind = CreationKinds.catalog
        .where((spec) => spec.key == kindKey)
        .firstOrNull;
    final builder = kind?.editor?.call();
    if (kind == null || builder == null) return null;

    final created = await showDialog<CreatedRecord>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: SoftErpTheme.shellSurface,
        insetPadding: const EdgeInsets.all(32),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusLg),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
          child: builder(
            dialogContext,
            onSaved: (record) => Navigator.of(dialogContext).pop(record),
            onCancel: () => Navigator.of(dialogContext).pop(),
          ),
        ),
      ),
    );
    if (created == null) return null;
    // Filed into this sitting like any other save, so the recents list can
    // bring the whole combination back.
    _remember(kind.key, created.id, created.title);
    if (mounted) {
      setState(() {
        (_added[kind.key] ??= []).insert(0, created);
      });
    }
    return LinkRef(
      type: type,
      id: created.id,
      label: created.title,
      subtitle: created.subtitle ?? '',
    );
  }

  // -------------------------------------------------------------------------
  // Right — view the component's items
  // -------------------------------------------------------------------------

  Widget _buildItemsColumn(
    List<ItemDefinition> items,
    Map<int, String> unitSymbols,
  ) {
    // One per open item form, so two half-typed items both show.
    final drafts = [
      for (final entry in _itemEntries)
        if (entry.controller?.draft case final draft?)
          if (!draft.saved) draft,
    ];
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
              const Spacer(),
              // Back to a blank form after looking at a saved one.
              IconButton(
                key: const ValueKey('creation_new_item'),
                tooltip: 'New item',
                onPressed: _naming
                    ? null
                    : () => _newItem(
                        _activeEntry.isItem ? _activeEntry : _itemEntries.first,
                      ),
                iconSize: 24,
                color: SoftErpTheme.accent,
                icon: const Icon(Icons.add),
              ),
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
          child: items.isEmpty && drafts.isEmpty
              ? _EmptyReference(
                  text: _naming
                      ? 'Name the component, then its items show up here.'
                      : 'Items you add show up here.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: visible.length + drafts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    // The items being typed, live, ahead of the saved ones.
                    if (index < drafts.length) {
                      return _DraftItemCard(draft: drafts[index]);
                    }
                    final item = visible[index - drafts.length];
                    return _ItemViewCard(
                      item: item,
                      unitSymbol: unitSymbols[item.unitId] ?? '',
                      expanded: _expandedIds.contains(item.id),
                      targeted:
                          _isAssetKey(_activeEntry.kind) &&
                          item.id == _activeEntry.targetItemId,
                      flash: item.id == _flashId,
                      onOpen: () => _openItem(item),
                      onToggle: () => _toggleExpanded(item.id),
                      onAddDie: () => _addUnder(item.id, CreationKinds.die),
                      onAddMachine: () =>
                          _addUnder(item.id, CreationKinds.machine),
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
    // Every open form stays mounted, so switching tiles — to make the die a
    // second item also needs — leaves neither of them half-lost.
    return Stack(
      children: [
        for (final entry in _lineup)
          Positioned.fill(
            child: Offstage(
              offstage: entry.id != _activeId,
              child: TickerMode(
                enabled: entry.id == _activeId,
                child: entry.isItem
                    ? _buildItemEditor(entry)
                    : _buildRecordEditor(entry, items),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildItemEditor(_LineupEntry entry) {
    final editing = entry.editingItem;
    final groupId = _component?.id ?? _lastItemGroupId;
    final builder = widget.itemEditorBuilder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (editing != null) ...[
          _EditingBar(item: editing, onNew: () => _newItem(entry)),
          const Divider(height: 1, color: SoftErpTheme.border),
        ],
        Expanded(
          child: KeyedSubtree(
            // The item is part of the key: opening another one has to rebuild
            // the form around it, not leave the last one's fields in place.
            key: ValueKey(
              'item-editor-${entry.id}-${entry.generation}-${editing?.id}',
            ),
            child: builder != null
                ? builder(
                    context,
                    groupId: groupId,
                    item: editing,
                    onClosed: (saved) => _onItemClosed(entry, saved),
                  )
                : ItemsScreen.workflowPanel(
                    item: editing,
                    initialGroupId: groupId,
                    onCreatePipeline: AppFlowHooks.createPipelineFor(context),
                    onClosed: (saved) => _onItemClosed(entry, saved),
                    controller: entry.controller,
                  ),
          ),
        ),
      ],
    );
  }

  /// Puts a remembered sitting back on screen: its tiles in the first column,
  /// its records in the last one. Items open in their editor from there; the
  /// other masters have no editor that takes an existing record yet, so they
  /// are listed rather than reopened.
  void _restoreSession(CreationSession session) {
    setState(() {
      _session = session;
      _added.clear();
      _addedItemIds.clear();
      for (final record in session.records) {
        if (record.kind == CreationKinds.item) {
          final id = int.tryParse(record.id);
          if (id != null) _addedItemIds.add(id);
        } else {
          (_added[record.kind] ??= []).insert(
            0,
            CreatedRecord(id: record.id, title: record.title),
          );
        }
      }
      // One tile per kind that was saved, in the order they were saved, so the
      // window comes back in the shape it was left in.
      final kinds = <String>{
        for (final record in session.records) record.kind,
      }.where((kind) => CreationKinds.catalog.any((s) => s.key == kind));
      if (kinds.isNotEmpty) {
        for (final entry in _lineup) {
          entry.controller
            ?..removeListener(_onItemWorkflowChanged)
            ..dispose();
        }
        _lineup
          ..clear()
          ..addAll([for (final kind in kinds) _makeEntry(kind)]);
        _activeId = _lineup.first.id;
        _stepsOwnerId = _itemEntries.firstOrNull?.id;
      }
      _flashId = null;
      _flashRecordKey = null;
    });
  }

  /// Opens a saved item back in the middle column, in the active item tile
  /// when there is one, else a new tile of its own.
  void _openItem(ItemDefinition item) {
    final entry = _activeEntry.isItem
        ? _activeEntry
        : (_itemEntries.firstOrNull ?? _makeEntry(CreationKinds.item));
    setState(() {
      if (!_lineup.contains(entry)) _lineup.add(entry);
      entry.editingItem = item;
      entry.subject = _refForItem(item);
      entry.generation++;
      _activeId = entry.id;
      _stepsOwnerId = entry.id;
    });
  }

  LinkRef _refForItem(ItemDefinition item) => LinkRef(
    type: 'item',
    id: '${item.id}',
    label: item.displayName.trim().isEmpty ? item.name : item.displayName,
    subtitle: item.shortCode,
  );

  /// Back to a blank form, from the + beside the item list or the editing bar.
  void _newItem(_LineupEntry entry) {
    setState(() {
      entry.editingItem = null;
      entry.generation++;
      _activeId = entry.id;
      _stepsOwnerId = entry.id;
    });
  }

  Widget _buildRecordEditor(_LineupEntry entry, List<ItemDefinition> items) {
    final kind = CreationKinds.byKey(entry.kind);
    final builder = kind.editor?.call();
    final target = items
        .where((item) => item.id == entry.targetItemId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isAssetKey(kind.key) && target != null) ...[
          _TargetBar(
            kind: kind,
            item: target,
            onClear: () => setState(() => entry.targetItemId = null),
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
                  key: ValueKey('${entry.id}-editor-${entry.generation}'),
                  child: SubmitFormShortcuts(
                    child: builder(
                      context,
                      onSaved: (record) => _onRecordSaved(entry, record),
                      onCancel: () => setState(() => entry.generation++),
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

  /// [canDrag] is false when the window is too narrow for the columns to open:
  /// a tile must not offer a drag to a place that is not on screen. [canLink]
  /// is about the API being wired at all, and does not care about width —
  /// the row's link button opens a menu, not a column.
  Widget _buildKindColumn(
    List<ItemDefinition> items,
    bool canDrag,
    bool canLink,
  ) {
    // Every kind, always: picking one already open adds a second form of it.
    final addable = CreationKinds.catalog;
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
                final entry = _lineup[index];
                final selected = !_naming && entry.id == _activeId;
                // The item editor's own steps, as sub-tabs under Item. Only
                // one item tile lists them — two tiles each repeating
                // Details/Variations would be a wall of the same words — and
                // they stay clickable from the die or machine tile.
                final owner = _stepsOwnerId ?? _itemEntries.firstOrNull?.id;
                final steps = entry.isItem && entry.id == owner
                    ? entry.controller?.steps ?? const <String>[]
                    : const <String>[];
                final tile = _KindButton(
                  kind: CreationKinds.byKey(entry.kind),
                  index: index,
                  count: _countOf(entry.kind, items),
                  selected: selected,
                  onTap: _naming ? null : () => _selectEntry(entry.id),
                  onRemove: _lineup.length > 1
                      ? () => _removeEntry(entry)
                      : null,
                  onAddAnother: _naming ? null : () => _addKind(entry.kind),
                  canLink: canLink,
                  onLink: _naming || entry.subject == null || !canLink
                      ? null
                      : (at) => _linkFromTile(entry, at),
                  expanded: steps.isEmpty ? null : _itemStepsOpen,
                  onToggleExpanded: () =>
                      setState(() => _itemStepsOpen = !_itemStepsOpen),
                );
                return Padding(
                  key: ValueKey('creation_tile_${entry.id}'),
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DraggableTile(
                        entry: entry,
                        enabled: canDrag,
                        onDragging: _setDragging,
                        child: tile,
                      ),
                      if (steps.isNotEmpty && _itemStepsOpen)
                        for (var i = 0; i < steps.length; i++)
                          _StepTab(
                            key: ValueKey('creation_step_${steps[i]}'),
                            label: steps[i],
                            active:
                                selected && i == entry.controller!.activeIndex,
                            onTap: entry.controller!.canOpen(i)
                                ? () => _openItemStep(entry, i)
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
    required this.sessions,
    required this.onClose,
  });

  final String title;
  final String? componentName;
  final CreationSessionController sessions;
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
          _RecentSessionsField(sessions: sessions),
          const SizedBox(width: 8),
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

/// The title bar's way back into a recent sitting: type to narrow the list,
/// pick one to put that whole combination back on screen.
class _RecentSessionsField extends StatefulWidget {
  const _RecentSessionsField({required this.sessions});

  final CreationSessionController sessions;

  @override
  State<_RecentSessionsField> createState() => _RecentSessionsFieldState();
}

class _RecentSessionsFieldState extends State<_RecentSessionsField> {
  final _controller = TextEditingController();
  final _link = LayerLink();
  OverlayEntry? _overlay;

  @override
  void dispose() {
    _hide();
    _controller.dispose();
    super.dispose();
  }

  void _hide() {
    _overlay?.remove();
    _overlay = null;
  }

  void _show() {
    if (_overlay != null) return;
    _overlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // A tap anywhere else puts the list away.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => setState(_hide),
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 6),
            child: Align(
              alignment: Alignment.topLeft,
              child: _RecentSessionsList(
                sessions: widget.sessions,
                query: _controller.text,
                onPick: (session) {
                  setState(_hide);
                  _controller.clear();
                  widget.sessions.restore(session);
                },
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlay!);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: SizedBox(
        width: 260,
        child: TextField(
          key: const ValueKey('creation_recents_field'),
          controller: _controller,
          style: const TextStyle(fontSize: 15),
          onTap: () => setState(_show),
          onChanged: (_) {
            _overlay?.markNeedsBuild();
            setState(_show);
          },
          decoration: _inputDecoration('Recent saves').copyWith(
            prefixIcon: const Icon(Icons.history, size: 20),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentSessionsList extends StatelessWidget {
  const _RecentSessionsList({
    required this.sessions,
    required this.query,
    required this.onPick,
  });

  final CreationSessionController sessions;
  final String query;
  final ValueChanged<CreationSession> onPick;

  static String _ago(DateTime when) {
    final gap = DateTime.now().difference(when);
    if (gap.inMinutes < 1) return 'just now';
    if (gap.inHours < 1) return '${gap.inMinutes}m ago';
    if (gap.inDays < 1) return '${gap.inHours}h ago';
    return '${gap.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: sessions,
      builder: (context, _) {
        final matches = sessions.recent
            .where((session) => session.matches(query.trim()))
            .toList(growable: false);
        return Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
          child: Container(
            width: 380,
            constraints: const BoxConstraints(maxHeight: 360),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
              border: Border.all(color: SoftErpTheme.border),
            ),
            child: matches.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'What you save here shows up in this list.',
                      style: TextStyle(
                        fontSize: 15,
                        color: SoftErpTheme.textSecondary,
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: matches.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: SoftErpTheme.border),
                    itemBuilder: (context, index) {
                      final session = matches[index];
                      return InkWell(
                        key: ValueKey('creation_recent_${session.id}'),
                        onTap: () => onPick(session),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: SoftErpTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${session.records.length} saved · '
                                '${_ago(session.savedAt)}',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  color: SoftErpTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        );
      },
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

/// Every button in a lineup row sits in the same small box. IconButton's
/// default 48pt square times four leaves the label nothing on a 264pt column.
const BoxConstraints _tileButtonBox = BoxConstraints.tightFor(
  width: 28,
  height: 28,
);

class _KindButton extends StatefulWidget {
  const _KindButton({
    required this.kind,
    required this.index,
    required this.count,
    required this.selected,
    required this.onTap,
    required this.onRemove,
    required this.onAddAnother,
    required this.canLink,
    required this.onLink,
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

  /// Another form of this kind, beside this one.
  final VoidCallback? onAddAnother;

  /// Whether this window can link at all — the API is wired. The button is
  /// drawn whenever it is, even on a tile that has saved nothing: an
  /// affordance that only appears once you have done the thing it leads to
  /// cannot tell you it is there, which is how it went unseen twice.
  final bool canLink;

  /// Link something to what this tile stands for; gets the button's position
  /// so the master menu opens under it. Null while the tile has saved nothing
  /// — there is no record yet to link, so the button is drawn but disabled.
  final ValueChanged<Offset>? onLink;

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
                    padding: EdgeInsets.zero,
                    constraints: _tileButtonBox,
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
                // Not hover-revealed like the + and ×, and drawn even before
                // the tile has anything to link: a tile that can be linked
                // should say so without being touched first, and a button that
                // only turns up after the first save cannot teach anyone that
                // linking exists.
                if (widget.canLink)
                  Builder(
                    builder: (buttonContext) => IconButton(
                      key: ValueKey('creation_link_${kind.key}'),
                      tooltip: widget.onLink == null
                          ? 'Save this ${kind.label.toLowerCase()} first, '
                                'then link to it'
                          : 'Link something to this ${kind.label.toLowerCase()}',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: _tileButtonBox,
                      iconSize: 18,
                      color: selected ? Colors.white : SoftErpTheme.accent,
                      disabledColor: selected
                          ? Colors.white38
                          : SoftErpTheme.textSecondary.withValues(alpha: 0.45),
                      onPressed: widget.onLink == null
                          ? null
                          : () {
                              final box =
                                  buttonContext.findRenderObject() as RenderBox?;
                              widget.onLink!(
                                box == null
                                    ? Offset.zero
                                    : box.localToGlobal(
                                        box.size.bottomLeft(Offset.zero),
                                      ),
                              );
                            },
                      icon: const Icon(Icons.add_link),
                    ),
                  ),
                AnimatedOpacity(
                  opacity: _hovered ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: IconButton(
                    key: ValueKey('creation_another_${kind.key}'),
                    tooltip: 'Another ${kind.label.toLowerCase()}',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: _tileButtonBox,
                    iconSize: 18,
                    color: muted,
                    onPressed: widget.onAddAnother,
                    icon: const Icon(Icons.add),
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
                    padding: EdgeInsets.zero,
                    constraints: _tileButtonBox,
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

/// A lineup tile that can be dragged sideways onto the 1.1 column to link
/// what it stands for.
///
/// `affinity: Axis.horizontal` is what makes the gesture share the tile with
/// everything else already on it: a vertical pan still scrolls the lineup, a
/// tap still selects, and the small handle inside the tile still reorders —
/// only a sideways pull, towards where the column opens, means "link this".
///
/// A tile with nothing saved in it yet has nothing to link, so it does not
/// drag at all rather than dragging to a refusal.
class _DraggableTile extends StatelessWidget {
  const _DraggableTile({
    required this.entry,
    required this.enabled,
    required this.onDragging,
    required this.child,
  });

  final _LineupEntry entry;

  /// False where there is nowhere to drop: too narrow a window for the 1.1
  /// column to open.
  final bool enabled;

  final ValueChanged<bool> onDragging;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final subject = entry.subject;
    // The Draggable is here whether or not it can drag, and the Opacity is in
    // both of its branches. Swapping either one in and out would change the
    // shape of the element tree under a ReorderableListView item, whose global
    // key then carries its tooltips' OverlayPortals through a deactivate /
    // activate — and reactivating one of those marks the overlay dirty. Keep
    // the shape fixed and only the values vary.
    return Draggable<LinkRef>(
      affinity: Axis.horizontal,
      // A tile with nothing saved in it has nothing to link, so it does not
      // drag rather than dragging to a refusal.
      maxSimultaneousDrags: enabled && subject != null ? 1 : 0,
      data: subject ?? const LinkRef(type: '', id: '', label: ''),
      onDragStarted: () => onDragging(true),
      onDragEnd: (_) => onDragging(false),
      onDraggableCanceled: (_, _) => onDragging(false),
      feedback: Material(
        color: Colors.transparent,
        child: _DragChip(
          icon: CreationKinds.byKey(entry.kind).icon,
          label: subject?.label ?? '',
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      child: Opacity(opacity: 1, child: child),
    );
  }
}

/// The rail down the side of the link columns, carrying the chevron that
/// opens and shuts them.
///
/// It stays put when they are shut — which is the whole point of it: a
/// chevron inside the columns would go away with them and leave no way back.
/// The V turns to point at what the click does, left to shut, right to open.
class _BranchRail extends StatelessWidget {
  const _BranchRail({required this.open, required this.onToggle});

  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: open ? 'Hide the link columns' : 'Show the link columns',
      child: Material(
        color: SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        child: InkWell(
          key: const ValueKey('creation_branch_chevron'),
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
          onTap: onToggle,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
              border: Border.all(color: SoftErpTheme.border),
            ),
            alignment: Alignment.center,
            child: AnimatedRotation(
              turns: open ? 0.25 : -0.25,
              duration: const Duration(milliseconds: 180),
              child: const Icon(
                Icons.expand_more,
                size: 22,
                color: SoftErpTheme.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What follows the pointer while a tile is being dragged to the columns.
class _DragChip extends StatelessWidget {
  const _DragChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: SoftErpTheme.accent,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        boxShadow: SoftErpTheme.raisedShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: Colors.white),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// The columns before there is anything to hang them off.
///
/// Drawn as the columns they will become rather than as one empty panel: the
/// shape is the explanation. You can see there are two of them, that the first
/// answers what the selected tile is linked to and the second what THAT is
/// linked to, before you have saved a thing.
class _LinkBranchHint extends StatelessWidget {
  const _LinkBranchHint({required this.fit});

  final ({int columns, double width}) fit;

  @override
  Widget build(BuildContext context) {
    const lines = [
      'Pick a tile on the left once it has saved something, and what it is '
          'linked to shows here.',
      'Pick one of those, and what IT is linked to shows here.',
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var column = 0; column < fit.columns; column++) ...[
          if (column > 0) const SizedBox(width: _branchColumnGap),
          SizedBox(
            width: fit.width,
            child: Container(
              decoration: BoxDecoration(
                color: SoftErpTheme.cardSurface,
                borderRadius: BorderRadius.circular(SoftErpTheme.radiusLg),
                border: Border.all(color: SoftErpTheme.borderStrong),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Text(
                    lines[column.clamp(0, lines.length - 1)],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14.5,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
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

/// Says the middle column is showing a saved item rather than a new one, and
/// offers the way back to a blank form.
class _EditingBar extends StatelessWidget {
  const _EditingBar({required this.item, required this.onNew});

  final ItemDefinition item;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('creation_editing_bar'),
      color: SoftErpTheme.accentSurface,
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Editing '),
                  TextSpan(
                    text: item.name,
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
          TextButton.icon(
            key: const ValueKey('creation_editing_new'),
            onPressed: onNew,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('New item', style: TextStyle(fontSize: 15)),
          ),
        ],
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
    required this.onOpen,
    required this.onToggle,
    required this.onAddDie,
    required this.onAddMachine,
  });

  final ItemDefinition item;
  final String unitSymbol;
  final bool expanded;
  final bool targeted;
  final bool flash;

  /// Opens the item in the editor; the chevron expands it in place instead.
  final VoidCallback onOpen;
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
            onTap: onOpen,
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
                  IconButton(
                    key: ValueKey('creation_expand_item_${item.id}'),
                    tooltip: expanded
                        ? 'Hide dies and machines'
                        : 'Show dies and machines',
                    onPressed: onToggle,
                    iconSize: 28,
                    color: SoftErpTheme.textSecondary,
                    icon: AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: const Icon(Icons.expand_more),
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
