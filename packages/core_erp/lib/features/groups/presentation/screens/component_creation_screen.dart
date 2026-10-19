import '../../../../core/app_flow_hooks.dart';
import '../../../../core/network/sitting_scope.dart';
import '../../../../core/services/feature_flags.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../items/domain/item_definition.dart';
import '../../../items/domain/item_form_sections.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../../process_routes/presentation/widgets/route_editor.dart';
import '../../../items/presentation/screens/items_screen.dart';
import '../../../links/data/entity_link_service.dart';
import '../../../links/domain/entity_link.dart';
import '../../../links/presentation/widgets/link_columns.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/widgets/track_panel.dart';
import '../../../units/domain/starter_units.dart';
import '../../../units/presentation/providers/units_provider.dart';
import '../../domain/group_definition.dart';
import '../../domain/group_inputs.dart';
import '../providers/groups_provider.dart';
import 'creation_guided_run.dart';
import 'creation_sessions.dart';
import 'creation_wizard_kinds.dart';
import '../widgets/factory_sheet_wizard.dart';
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
    this.initialKinds,
    this.onLineupChanged,
    this.sittingId,
    this.initialFactorySheetMode = false,
    this.factorySheetActive,
    this.onSwitchToBench,
  });

  /// Whether the workspace starts in Factory Sheet Wizard mode.
  final bool initialFactorySheetMode;

  /// External override for whether Factory Sheet Wizard is active.
  final bool? factorySheetActive;

  /// Callback when switching out of Factory Sheet Wizard back to bench.
  final VoidCallback? onSwitchToBench;

  /// This opening of the window, as the server groups it.
  ///
  /// Also used as the recents entry's id, so the local memory of the bench and
  /// the server's record of it name the same opening. Null only in a test that
  /// builds the workspace directly.
  final String? sittingId;

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

  /// The tiles to open with. Null is the usual Item / Die / Machine.
  ///
  /// Only the Express door passes this, together with [onLineupChanged] —
  /// Add Item starts fresh every time on purpose.
  final List<String>? initialKinds;

  /// Fires whenever the lineup gains, loses or reorders a tile, with the kinds
  /// in their new order. Null means nobody is remembering it.
  final ValueChanged<List<String>>? onLineupChanged;

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
    this.title,
    this.initialKinds,
    this.onLineupChanged,
    this.initialFactorySheetMode = false,
  });

  final GroupDefinition? component;

  /// What the title bar says. Null keeps the name the mode gives it.
  final String? title;

  /// See [ComponentCreationWorkspace.initialKinds].
  final List<String>? initialKinds;

  /// See [ComponentCreationWorkspace.onLineupChanged].
  final ValueChanged<List<String>>? onLineupChanged;

  /// See [ComponentCreationWorkspace.linkService].
  final EntityLinkService? linkService;

  /// See [ComponentCreationWorkspace.itemsOnly].
  final bool itemsOnly;

  /// Passed through to the workspace; tests use it to stay light.
  final ComponentItemEditorBuilder? itemEditorBuilder;

  /// Whether to open directly into the Unified Factory Sheet Wizard.
  final bool initialFactorySheetMode;

  /// Opens directly into the Unified Factory Sheet Wizard.
  static Future<void> openFactorySheet(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ComponentCreationDialog(
        itemsOnly: true,
        title: 'Factory Sheet Wizard',
        initialFactorySheetMode: true,
      ),
    );
  }

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

  /// The Masters header's Express: the same window, opened on whatever the
  /// person was entering last time.
  ///
  /// Everything `itemsOnly` gives is what Express wants — no component to
  /// name, the item editor picking its own group, the last column listing what
  /// this sitting saved. What differs is the title and that the lineup is
  /// remembered, so those two travel as arguments rather than as a third mode.
  ///
  /// The lineup is read **before** the window is shown: opening on the right
  /// tiles and then rebuilding a frame later would be a flicker on the thing
  /// the person came to use.
  static Future<void> openExpress(
    BuildContext context, {
    CreationLineupStore? store,
  }) async {
    final lineupStore = store ?? CreationLineupStore();
    final remembered = CreationKinds.sanitizeLineup(await lineupStore.load());
    if (!context.mounted) return;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ComponentCreationDialog(
        itemsOnly: true,
        title: 'Express entry',
        initialKinds: remembered,
        onLineupChanged: lineupStore.save,
      ),
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
  late bool _factorySheetActive = widget.initialFactorySheetMode;

  /// This opening of the window, as the server will group it.
  ///
  /// Minted here rather than in the workspace because the *window* is the
  /// sitting: both doors — Add Item and Express — build this dialog, and a
  /// nested editor opened from inside it keeps writing under the same id,
  /// which is right, because that is where it happened. The workspace's own
  /// `_session.id` is a different thing: it names an entry in the recents list.
  late final String _sittingId;

  @override
  void initState() {
    super.initState();
    _sittingId = SittingScope.begin();
  }

  @override
  void dispose() {
    // Passing the id, not clearing outright: Add Item can open over Express,
    // and the inner window closing must not strand the outer one's writes.
    SittingScope.end(_sittingId);
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
              title:
                  widget.title ??
                  (widget.itemsOnly ? 'Item creation' : 'Component creation'),
              componentName: _component?.name,
              sessions: _sessions,
              sittingId: _sittingId,
              factorySheetActive: _factorySheetActive,
              onToggleFactorySheet: () =>
                  setState(() => _factorySheetActive = !_factorySheetActive),
              onClose: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ComponentCreationWorkspace(
                  sessions: _sessions,
                  sittingId: _sittingId,
                  component: widget.component,
                  itemEditorBuilder: widget.itemEditorBuilder,
                  itemsOnly: widget.itemsOnly,
                  linkService: widget.linkService,
                  initialKinds: widget.initialKinds,
                  onLineupChanged: widget.onLineupChanged,
                  initialFactorySheetMode: widget.initialFactorySheetMode,
                  factorySheetActive: _factorySheetActive,
                  onSwitchToBench: () =>
                      setState(() => _factorySheetActive = false),
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
    for (final kind in widget.initialKinds ?? CreationKinds.defaults)
      _makeEntry(kind),
  ];
  /// The tile in front, or null when the bench is empty — which it is every
  /// time Express is opened with nothing remembered.
  late String? _activeId = _lineup.firstOrNull?.id;

  /// The item tile whose sub-tabs are listed: the open one, or the one that
  /// was open last, so they stay clickable while a die sits in front.
  late String? _stepsOwnerId = _lineup.firstOrNull?.id;
  int _entrySeq = 0;

  /// Everything the middle column saved in this window, newest first.
  final Map<String, List<CreatedRecord>> _added = {};

  bool _itemStepsOpen = true;

  /// The standard-units offer was waved away for this opening of the window.
  bool _starterUnitsDismissed = false;

  /// Whether the Unified Factory Sheet Wizard is active.
  late bool _factorySheetActive =
      widget.factorySheetActive ?? widget.initialFactorySheetMode;

  @override
  void didUpdateWidget(ComponentCreationWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.factorySheetActive != null &&
        widget.factorySheetActive != oldWidget.factorySheetActive) {
      _factorySheetActive = widget.factorySheetActive!;
    }
  }

  /// Whether this opening is a guided first run.
  ///
  /// **Decided once, on the first build, and then left alone.** It cannot be a
  /// live `items.isEmpty` — saving the part in step 1 makes that false and
  /// would yank the run away mid-flow. Null means not yet decided.
  bool? _guidedActive;

  GuidedStep _guidedStep = GuidedStep.part;

  /// The part step 1 produced, and the answers to steps 2 and 3. A null
  /// machine or die means the step was skipped, which is a real answer.
  ItemDefinition? _guidedPart;
  CreatedRecord? _guidedMachine;
  CreatedRecord? _guidedDie;

  /// What the current step offers to attach, and which one is being written.
  List<LinkRef> _guidedCandidates = const <LinkRef>[];
  bool _guidedLoading = false;
  String? _guidedBusy;

  /// Pairs this window has already joined — whether from the + Die under an
  /// item or from the offer below — so neither is proposed twice.
  final Set<String> _joinedPairs = <String>{};

  /// Records somebody said to leave unattached, keyed `<kind>:<recordId>`.
  ///
  /// Per record, not per pair: the question asked is "is this die attached to
  /// anything?", so the answer is about the die. Persisted, because an answer
  /// that dies with the window means nothing the next time it opens.
  final Set<String> _declinedRecords = <String>{};
  final CreationDeclinedStore _declinedStore = CreationDeclinedStore();

  /// A record being attached, so its row can say so and cannot be
  /// double-tapped.
  String? _joiningPair;
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
  ///
  /// The id is the dialog's sitting id, so the entry in the recents list and
  /// the server's row group are one and the same opening — which is what stops
  /// the header's count and the panel it opens from being able to disagree.
  /// `CreationSession.id` is only ever compared for equality, never parsed, so
  /// the format change costs nothing.
  late CreationSession _session = CreationSession(
    id: widget.sittingId ?? 's${DateTime.now().microsecondsSinceEpoch}',
    savedAt: DateTime.now(),
    records: const [],
  );

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();

  /// Whether the right rail is showing the live sitting activity timeline
  /// or local session records.
  bool _showTimeline = false;

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
    Future<void>.microtask(() async {
      if (!mounted) return;
      context.read<UnitsProvider>().initialize();
      context.read<ItemsProvider>().initialize();
      final declined = await _declinedStore.load();
      if (!mounted || declined.isEmpty) return;
      setState(() => _declinedRecords.addAll(declined));
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

  /// The tile in front. Null on an empty bench — and the fallback for a stale
  /// id is the first tile, which is why this cannot simply be a firstWhere:
  /// its own orElse was the thing that threw.
  _LineupEntry? get _activeEntry {
    if (_lineup.isEmpty) return null;
    return _lineup.firstWhere(
      (e) => e.id == _activeId,
      orElse: () => _lineup.first,
    );
  }

  Iterable<_LineupEntry> get _itemEntries => _lineup.where((e) => e.isItem);

  /// The item tile to put an item in: the one in front if it is an item, else
  /// the first item tile there is, else a new one.
  ///
  /// Both callers used to work this out themselves and only one of them did it
  /// safely — the + beside the Items list reached for `_itemEntries.first`,
  /// which threw whenever the bench held tiles but no Item among them.
  _LineupEntry _itemTileToUse() {
    final active = _activeEntry;
    if (active != null && active.isItem) return active;
    return _itemEntries.firstOrNull ?? _makeEntry(CreationKinds.item);
  }

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
      if (_activeEntry?.isItem ?? false) _stepsOwnerId = id;
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
  /// Says what the lineup now holds, for whoever is remembering it.
  ///
  /// Called from every path that changes it — the + menu, a tile's ×, a drag,
  /// and the + Die / + Machine under an item, which adds a tile when there is
  /// none of that kind yet.
  void _lineupChanged() {
    widget.onLineupChanged?.call([
      for (final entry in _lineup) entry.kind,
    ]);
  }

  /// Every master not already on the bench, in catalogue order.
  ///
  /// One setState and **one** [_lineupChanged], not a loop over [_addKind]:
  /// that would announce a different lineup per kind and write the remembered
  /// one that many times.
  void _addAllKinds() {
    final present = {for (final entry in _lineup) entry.kind};
    final missing = CreationKinds.catalog
        .map((spec) => spec.key)
        .where((key) => !present.contains(key))
        .toList(growable: false);
    if (missing.isEmpty) return;
    setState(() {
      for (final kind in missing) {
        final entry = _makeEntry(kind);
        _lineup.add(entry);
        // The first one added comes forward; the half-typed tile someone was
        // already on would be rude to replace.
        _activeId ??= entry.id;
        if (entry.isItem) _stepsOwnerId ??= entry.id;
      }
    });
    _lineupChanged();
  }

  void _addKind(String kind) {
    setState(() {
      final entry = _makeEntry(kind);
      _lineup.add(entry);
      _activeId = entry.id;
      if (entry.isItem) _stepsOwnerId = entry.id;
    });
    _lineupChanged();
  }

  /// A tile's ×. Taking the last one off is allowed: it leaves the bench
  /// empty, which puts the chooser back in the middle.
  void _removeEntry(_LineupEntry entry) {
    setState(() {
      _lineup.remove(entry);
      entry.controller
        ?..removeListener(_onItemWorkflowChanged)
        ..dispose();
      if (_activeId == entry.id) _activeId = _lineup.firstOrNull?.id;
      if (_stepsOwnerId == entry.id)
        _stepsOwnerId = _itemEntries.firstOrNull?.id;
    });
    _lineupChanged();
  }

  void _reorderKinds(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      _lineup.insert(newIndex, _lineup.removeAt(oldIndex));
    });
    _lineupChanged();
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
    if (existing == null) _lineupChanged();
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
        _activeId = _lineup.firstOrNull?.id;
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
      // Already joined, so the offer below must not propose it again.
      _joinedPairs.add(_pairKey(target.id, entry.kind, id));
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
    final itemsProvider = context.watch<ItemsProvider>();
    final allItems = itemsProvider.items;
    // Decided once, but NOT before the answer is known.
    //
    // `_componentItems` below answers a different question — in Express it
    // lists only what THIS window added, so it is empty on every opening and
    // would start a guided run every time. That much was already handled. What
    // was not: an empty `items` ALSO means "nobody has loaded them yet", and
    // because this is a `??=` the first build's answer is permanent. Open
    // Express before the items have arrived and the guided first run took over
    // a workspace with a full catalogue in it, for good. Found by the first
    // integration test to drive the real app.
    if (_guidedActive == null &&
        itemsProvider.isInitialized &&
        !itemsProvider.isLoading) {
      _guidedActive = widget.itemsOnly && allItems.isEmpty;
    }
    final items = _componentItems(allItems);
    // What was made on this bench and is still attached to nothing — worked
    // out once, so the reference column and its list agree.
    final looseEnds = _looseEndsFor(items);
    final units = context.watch<UnitsProvider>().activeUnits;
    final unitSymbols = {for (final unit in units) unit.id: unit.symbol};
    final linkService = _linkService;

    // The links hang off the FIRST column, not the last: a tile there is the
    // record being worked on, so the column that opens beside it is that
    // record's own — a 1.1 to the lineup's 1. The reference tile on the right
    // keeps its place.
    final subject = _activeEntry?.subject;

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
              // last one shows what picking it has produced. With nothing on
              // the bench there is nothing to have produced anything.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                    child: Row(
                      children: [
                        _buildRailTab(
                          label: 'Records',
                          icon: Icons.list_alt_rounded,
                          selected: !_showTimeline,
                          onTap: () => setState(() => _showTimeline = false),
                          key: const ValueKey('creation_rail_tab_records'),
                        ),
                        const SizedBox(width: 8),
                        _buildRailTab(
                          label: 'Timeline',
                          icon: Icons.timeline_rounded,
                          selected: _showTimeline,
                          onTap: () => setState(() => _showTimeline = true),
                          key: const ValueKey('creation_rail_tab_timeline'),
                        ),
                      ],
                    ),
                  ),
                  if (!_showTimeline) ...[
                    // Above the list, because it is about what is in the list.
                    if (looseEnds.isNotEmpty) _buildLooseEnds(looseEnds),
                    Expanded(
                      child: _lineup.isEmpty
                          ? const _EmptyReference(
                              text: 'What you add shows up here.',
                            )
                          : _lineup.first.isItem
                          ? _buildItemsColumn(items, unitSymbols)
                          : _buildRecordsColumn(
                              CreationKinds.byKey(_lineup.first.kind),
                            ),
                    ),
                  ] else ...[
                    Expanded(
                      child: _buildSittingTimeline(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSittingTimeline() {
    final sittingId = widget.sittingId ?? _session.id;
    bool canAudit = true;
    try {
      canAudit = context.read<AuthProvider>().can('audit.read');
    } catch (_) {
      canAudit = true;
    }
    if (!canAudit) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 32, color: SoftErpTheme.textSecondary),
            const SizedBox(height: 12),
            const Text(
              'Timeline requires audit.read permission.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: SoftErpTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() => _showTimeline = false),
              child: const Text('View local session records'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: TrackPanel.sitting(
        key: ValueKey('creation_sitting_track_$sittingId'),
        sittingId: sittingId,
        showHeader: false,
      ),
    );
  }

  Widget _buildRailTab({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    Key? key,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? SoftErpTheme.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
          border: Border.all(
            color: selected ? SoftErpTheme.accent : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? SoftErpTheme.accent : SoftErpTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? SoftErpTheme.accent : SoftErpTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
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
    final subject = _activeEntry?.subject;
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
                    : () => _newItem(_itemTileToUse()),
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
                          _isAssetKey(_activeEntry?.kind ?? '') &&
                          item.id == _activeEntry?.targetItemId,
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
    if (_factorySheetActive) {
      return FactorySheetWizard(
        initialGroupName: _component?.name,
        onSwitchToBench: () {
          widget.onSwitchToBench?.call();
          setState(() => _factorySheetActive = false);
        },
        onSaved: (item) {
          _onItemClosed(_itemTileToUse(), item);
        },
      );
    }
    // A workspace with no items at all has nothing to copy from, so three
    // questions in the factory's own words beat thirteen cards. Ahead of the
    // chooser because it answers the same "nothing yet" state, better.
    if (_guidedActive == true) return _buildGuidedRun();
    // Nothing on the bench: ask what is being added, rather than showing an
    // empty panel beside a + that has to be found first.
    if (_lineup.isEmpty) return _buildKindChooser();
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
      // A remembered sitting is a bench, not a guided run: it arrives with
      // tiles and records already in it, which is the opposite of the empty
      // workspace the guided run exists for.
      _guidedActive = false;
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
        _activeId = _lineup.firstOrNull?.id;
        _stepsOwnerId = _itemEntries.firstOrNull?.id;
      }
      _flashId = null;
      _flashRecordKey = null;
    });
  }

  /// Opens a saved item back in the middle column, in the active item tile
  /// when there is one, else a new tile of its own.
  void _openItem(ItemDefinition item) {
    final entry = _itemTileToUse();
    final added = !_lineup.contains(entry);
    setState(() {
      if (added) _lineup.add(entry);
      entry.editingItem = item;
      entry.subject = _refForItem(item);
      entry.generation++;
      _activeId = entry.id;
      _stepsOwnerId = entry.id;
    });
    if (added) _lineupChanged();
  }

  LinkRef _refForItem(ItemDefinition item) => LinkRef(
    type: 'item',
    id: '${item.id}',
    label: item.displayName.trim().isEmpty ? item.name : item.displayName,
    subtitle: item.shortCode,
  );

  /// Back to a blank form, from the + beside the item list or the editing bar.
  void _newItem(_LineupEntry entry) {
    // [_itemTileToUse] can hand back a tile that is not on the bench yet —
    // there may not have been an Item tile at all. Selecting one that is not
    // in the lineup would leave the middle column blank.
    final added = !_lineup.contains(entry);
    setState(() {
      if (added) _lineup.add(entry);
      entry.editingItem = null;
      entry.generation++;
      _activeId = entry.id;
      _stepsOwnerId = entry.id;
    });
    if (added) _lineupChanged();
  }

  // ---------------------------------------------------------------------
  // Joining what was made together
  // ---------------------------------------------------------------------

  String _pairKey(int itemId, String kind, String assetId) =>
      'item:$itemId|$kind:$assetId';

  /// The pairs on this bench that could plausibly be joined.
  ///
  /// Only item↔die and item↔machine. Those two are facts the system already
  /// has a home for — `item_dies` and `item_machines` — and the words for them
  /// are plain: this part is cut by that die, this part runs on that press.
  ///
  /// A client is deliberately NOT offered against an item: the item already
  /// carries Developed For, so a link would be a second claim on the same
  /// fact — the trap `modules/links/catalog.js` documents for these very
  /// tables. A set and a group are not offered either: filing a set is a SOLE
  /// link, and an additive one would leave the set filed under two groups.
  /// Whether [item] already holds this die or machine.
  bool _holds(ItemDefinition item, String kind, String recordId) =>
      _joinedPairs.contains(_pairKey(item.id, kind, recordId)) ||
      (kind == CreationKinds.die
          ? item.dies.any((die) => die.id == recordId)
          : item.machines.any((machine) => machine.id == recordId));

  /// The dies and machines made on this bench that nothing here holds.
  ///
  /// One row per **record**, not per pair. The pair version of this was a
  /// triple loop — kinds x records x items — so three parts and two dies made
  /// six rows in a 356px column that fits about two, and the overflow was hidden
  /// by truncating the list. Folding it this way bounds the list by how many
  /// records were made, which is a dozen at the very worst.
  List<_LooseEnd> _looseEndsFor(List<ItemDefinition> items) {
    final made = items
        .where((item) => _addedItemIds.contains(item.id))
        .toList(growable: false);
    if (made.isEmpty) return const <_LooseEnd>[];

    final out = <_LooseEnd>[];
    // A part with no ROUTE is deliberately not listed here, though it was
    // tried. This panel is about "records still attached to nothing", and it
    // has to be empty once everything is attached — two tests pin exactly
    // that ('an item on its own cannot be a loose end', and the offer being
    // gone after a quick attach). A routeless part is a different kind of
    // incompleteness and would have made every new part nag immediately. The
    // Route card is found through the chooser and the + menu, like every other
    // kind.
    for (final kind in const [CreationKinds.die, CreationKinds.machine]) {
      for (final record in _added[kind] ?? const <CreatedRecord>[]) {
        if (_declinedRecords.contains(_recordKey(kind, record.id))) continue;
        // Held by anything made here — by the + Die under an item, by this
        // list, or by any other path — so it is not a loose end.
        if (made.any((item) => _holds(item, kind, record.id))) continue;
        out.add(
          _LooseEnd(
            kind: kind,
            recordId: record.id,
            recordLabel: record.title,
            candidates: made,
          ),
        );
      }
    }
    return out;
  }

  String _recordKey(String kind, String recordId) => '$kind:$recordId';

  /// Remembers that somebody chose to leave this record unattached.
  void _leaveUnattached(_LooseEnd end) {
    setState(() => _declinedRecords.add(end.key));
    _declinedStore.save(_declinedRecords);
  }

  /// Writes one accepted pair, through the same path the rest of this window
  /// uses for the fact — `setItemLinks`, which is a full replace, so whatever
  /// the item already carries travels with it.
  Future<void> _attach(_LooseEnd end, int itemId) async {
    if (_joiningPair != null) return;
    setState(() => _joiningPair = end.key);
    final items = context.read<ItemsProvider>();
    // Read the row as it is NOW, not as it was when this list was built.
    // `setItemLinks` replaces the whole list, so sending a snapshot taken when
    // the window drew would drop anything attached in between.
    final item = items.items.where((row) => row.id == itemId).firstOrNull;
    if (item == null) {
      setState(() => _joiningPair = null);
      _toast('That part is no longer on the bench.');
      return;
    }
    final saved = end.kind == CreationKinds.die
        ? await items.setItemLinks(
            item.id,
            dieIds: [
              ...item.dies.map((die) => die.id),
              if (!item.dies.any((die) => die.id == end.recordId)) end.recordId,
            ],
          )
        : await items.setItemLinks(
            item.id,
            machineIds: [
              ...item.machines.map((machine) => machine.id),
              if (!item.machines.any((m) => m.id == end.recordId)) end.recordId,
            ],
          );
    if (!mounted) return;
    setState(() {
      _joiningPair = null;
      if (saved != null) {
        _joinedPairs.add(_pairKey(item.id, end.kind, end.recordId));
      }
    });
    if (saved == null) {
      _toast(items.errorMessage ?? 'That could not be attached.');
      return;
    }
    _linkColumns.refresh();
  }

  /// Whether this user may attach anything. Tolerant of a missing provider,
  /// the way the rest of this screen is.
  bool get _canJoin {
    try {
      return context.read<AuthProvider>().can('items.update');
    } catch (_) {
      return true;
    }
  }

  /// Whether to bring the standard units forward here.
  ///
  /// An item cannot be created without a unit — the contract refuses it — and
  /// a fresh workspace holds only the server's `Primary Unit` placeholder. So
  /// the one thing that would stop somebody is offered before they start,
  /// rather than after a refused save. Dismissible, and the same action lives
  /// permanently in the Units master either way.
  bool get _showStarterUnitsOffer {
    if (_starterUnitsDismissed) return false;
    try {
      return unitsLookUnset(
        activeUnitNames: context
            .watch<UnitsProvider>()
            .activeUnits
            .map((unit) => unit.name),
      );
    } catch (_) {
      return false;
    }
  }

  Widget _buildStarterUnitsOffer() {
    final units = context.watch<UnitsProvider>();
    return Container(
      key: const ValueKey<String>('creation_starter_units'),
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: SoftErpTheme.accentSoft,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'This workspace has no units yet, and an item needs one.',
              style: TextStyle(fontSize: 14.5, color: SoftErpTheme.textPrimary),
            ),
          ),
          const SizedBox(width: 12),
          AppButton(
            key: const ValueKey<String>('creation_load_starter_units'),
            label: 'Load standard units',
            variant: AppButtonVariant.secondary,
            isLoading: units.isSaving,
            onPressed: () async {
              final added = await units.seedStarterUnits();
              if (!mounted || added == 0) return;
              showAppToast(
                context,
                'Added $added units.',
                kind: AppToastKind.success,
              );
            },
          ),
          IconButton(
            key: const ValueKey<String>('creation_dismiss_starter_units'),
            tooltip: 'Not now',
            iconSize: 18,
            color: SoftErpTheme.textSecondary,
            onPressed: () => setState(() => _starterUnitsDismissed = true),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  /// What was made here and is still attached to nothing.
  ///
  /// Nothing is written until a part is picked. Co-occurrence is evidence, not
  /// a relationship — two things made in the same sitting are not thereby
  /// related, and a window that decided they were would fill the link graph
  /// with accidents nobody could tell from intentions. So the row states only
  /// what is true (this die holds no part) and the menu is where a person says
  /// what is so.
  ///
  /// One row per record. As pairs this was kinds x records x items, which
  /// outgrew a 356px column at three parts and two dies and hid the rest
  /// behind a truncation.
  Widget _buildLooseEnds(List<_LooseEnd> ends) {
    final canJoin = _canJoin;
    return Container(
      key: const ValueKey<String>('creation_link_offer'),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: SoftErpTheme.accentSoft,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ends.length == 1 ? 'One loose end' : '${ends.length} loose ends',
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: SoftErpTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          // Every one of them, never a truncated few: the list is bounded by
          // how many records were made here, so there is nothing to hide.
          for (final end in ends)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          end.recordLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: SoftErpTheme.textPrimary,
                          ),
                        ),
                        Text(
                          end.sentence,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: SoftErpTheme.textSecondary,
                          ),
                        ),
                        if (end.candidates.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: InkWell(
                              key: ValueKey<String>('creation_quick_attach_${end.key}'),
                              onTap: canJoin
                                  ? () => _attach(end, end.candidates.first.id)
                                  : null,
                              borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.link,
                                      size: 14,
                                      color: canJoin
                                          ? SoftErpTheme.accent
                                          : SoftErpTheme.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        'Attach to ${_itemLabel(end.candidates.first)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: canJoin
                                              ? SoftErpTheme.accent
                                              : SoftErpTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_joiningPair == end.key)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    // One picker where the old row carried a Join link AND a
                    // close button. The parts are in the menu, not the row, so
                    // the row's width no longer depends on their names.
                    Tooltip(
                      message: canJoin
                          ? 'Say which part ${end.recordLabel} belongs to'
                          : 'You do not have permission to change items '
                                '(items.update).',
                      child: PopupMenuButton<int>(
                        key: ValueKey<String>('creation_attach_${end.key}'),
                        enabled: canJoin,
                        icon: const Icon(Icons.more_horiz, size: 20),
                        padding: EdgeInsets.zero,
                        onSelected: (itemId) {
                          if (itemId == _leaveUnattachedValue) {
                            _leaveUnattached(end);
                          } else {
                            _attach(end, itemId);
                          }
                        },
                        itemBuilder: (_) => <PopupMenuEntry<int>>[
                          for (final item in end.candidates)
                            PopupMenuItem<int>(
                              value: item.id,
                              child: Text(
                                _itemLabel(item),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          const PopupMenuDivider(),
                          const PopupMenuItem<int>(
                            value: _leaveUnattachedValue,
                            child: Text(
                              'Leave unattached',
                              style: TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _itemLabel(ItemDefinition item) => item.displayName.trim().isEmpty
      ? item.name
      : item.displayName;

  /// The link client, **ungated**.
  ///
  /// Distinct from [_linkService], which is behind `masters.linkColumns`
  /// because that flag governs the Miller columns. Writing one link is not the
  /// columns, and a build with the flag off must still be able to attach a
  /// machine to a part.
  EntityLinkService? get _links {
    final injected = widget.linkService;
    if (injected != null) return injected;
    try {
      return context.read<EntityLinkService>();
    } catch (_) {
      return null;
    }
  }

  /// Whether this user may attach records of [module].
  ///
  /// Linking counts as `update` on BOTH sides, so a machine needs
  /// `machines.update` as well as `items.update`. Nothing in this window asked
  /// this before — a user without the right got an enabled button and learned
  /// the refusal from the server.
  bool _mayLink(String module) {
    try {
      final auth = context.read<AuthProvider>();
      return auth.can('items.update') && auth.can('$module.update');
    } catch (_) {
      return true;
    }
  }

  void _leaveGuided() {
    setState(() => _guidedActive = false);
  }

  /// Loads what the current step can offer. `browse` is exactly this question.
  Future<void> _guidedLoadCandidates(String type) async {
    final links = _links;
    if (links == null) {
      setState(() => _guidedCandidates = const <LinkRef>[]);
      return;
    }
    setState(() => _guidedLoading = true);
    try {
      final found = await links.browse(type, limit: 25);
      if (!mounted) return;
      setState(() => _guidedCandidates = found);
    } catch (_) {
      // Nothing to offer is survivable — the step can still create one, and
      // skipping is a real answer.
      if (mounted) setState(() => _guidedCandidates = const <LinkRef>[]);
    } finally {
      if (mounted) setState(() => _guidedLoading = false);
    }
  }

  /// Step 1 saved. Everything else about the item editor is unchanged, so this
  /// mirrors `_onItemClosed`'s bookkeeping rather than replacing it.
  void _onGuidedPartSaved(ItemDefinition? saved) {
    if (saved == null) return;
    _remember(CreationKinds.item, '${saved.id}', saved.displayName);
    _linkColumns.refresh();
    setState(() {
      _guidedPart = saved;
      _addedItemIds.add(saved.id);
      _lastItemGroupId = saved.groupId;
      _guidedStep = GuidedStep.machine;
    });
    _guidedLoadCandidates('machine');
  }

  /// Attaches one pair, then moves on.
  ///
  /// `EntityLinkService.link`, not `setItemLinks`: POST /api/links is additive
  /// and INSERT OR IGNORE, so answering twice is harmless and there is no list
  /// to spread or snapshot to go stale.
  Future<void> _guidedAttach(String type, LinkRef target) async {
    final part = _guidedPart;
    final links = _links;
    if (part == null) return;
    setState(() => _guidedBusy = target.id);
    try {
      await links?.link(
        fromType: 'item',
        fromId: '${part.id}',
        toType: type,
        toId: target.id,
      );
      _joinedPairs.add(
        _pairKey(part.id, type == 'die' ? CreationKinds.die : CreationKinds.machine, target.id),
      );
      _linkColumns.refresh();
    } catch (error) {
      if (mounted) _toast('$error');
      if (mounted) setState(() => _guidedBusy = null);
      return;
    }
    if (!mounted) return;
    final record = CreatedRecord(
      id: target.id,
      title: target.label,
      subtitle: target.subtitle,
    );
    setState(() {
      _guidedBusy = null;
      if (type == 'machine') {
        _guidedMachine = record;
        _guidedStep = GuidedStep.die;
      } else {
        _guidedDie = record;
        _guidedStep = GuidedStep.done;
      }
    });
    if (type == 'machine') _guidedLoadCandidates('die');
  }

  /// "Add one" — reuses the dialog the link columns already use, so the record
  /// lands in this sitting and in `_added` exactly as any other save does.
  Future<void> _guidedCreate(String type) async {
    final made = await _createForLink(context, type);
    if (made == null || !mounted) return;
    await _guidedAttach(type, made);
  }

  void _guidedSkip() {
    setState(() {
      if (_guidedStep == GuidedStep.machine) {
        _guidedStep = GuidedStep.die;
      } else {
        _guidedStep = GuidedStep.done;
      }
    });
    if (_guidedStep == GuidedStep.die) _guidedLoadCandidates('die');
  }

  Widget _buildGuidedRun() {
    final step = _guidedStep;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GuidedStepChrome(step: step, onSwitchToBench: _leaveGuided),
        Expanded(child: _buildGuidedBody(step)),
      ],
    );
  }

  Widget _buildGuidedBody(GuidedStep step) {
    switch (step) {
      case GuidedStep.part:
        // A host that substitutes the item editor is honoured here too, the
        // same way `_buildItemEditor` honours it — otherwise the guided run
        // would be the one place in this window that ignored the seam, and a
        // host would get its editor everywhere except the first screen a new
        // workspace sees. Its own shape is then its own business.
        final builder = widget.itemEditorBuilder;
        if (builder != null) {
          return builder(
            context,
            groupId: _component?.id ?? _lastItemGroupId,
            item: null,
            onClosed: _onGuidedPartSaved,
          );
        }
        // The item editor itself, trimmed to what names a part. Nothing about
        // saving an item is reimplemented here.
        return ItemsScreen.workflowPanel(
          item: null,
          initialGroupId: _component?.id ?? _lastItemGroupId,
          overrideSections: const ItemFormSections(
            itemImage: false,
            cadFile: false,
            additionalFiles: false,
            developedFor: false,
            defaultPipeline: false,
            variationTree: false,
            machines: false,
            dies: false,
            sets: false,
          ),
          identityOnly: true,
          onClosed: _onGuidedPartSaved,
        );
      case GuidedStep.machine:
      case GuidedStep.die:
        final isMachine = step == GuidedStep.machine;
        final type = isMachine ? 'machine' : 'die';
        final module = isMachine ? 'machines' : 'dies';
        final may = _mayLink(module);
        if (_guidedLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        return GuidedPickOrCreate(
          step: step,
          candidates: [
            for (final ref in _guidedCandidates)
              GuidedCandidate(
                id: ref.id,
                label: ref.label,
                subtitle: ref.subtitle,
              ),
          ],
          busyId: _guidedBusy,
          onPick: (candidate) => _guidedAttach(
            type,
            _guidedCandidates.firstWhere((ref) => ref.id == candidate.id),
          ),
          onSkip: _guidedSkip,
          skipLabel: isMachine ? 'Not sure yet' : 'No die',
          createLabel: isMachine ? 'Add a machine' : 'Add a die',
          onCreate: may ? () => _guidedCreate(type) : null,
          denialReason:
              'You do not have permission to attach $module ($module.update).',
        );
      case GuidedStep.done:
        return GuidedFinishLine(
          partName: _guidedPart?.displayName ?? 'The part',
          machine: _guidedMachine,
          die: _guidedDie,
          records: [for (final record in _session.records) record.title],
          onOpenPart: () {
            final part = _guidedPart;
            _leaveGuided();
            if (part != null) _openItemOnBench(part);
          },
          onAddAnother: () {
            setState(() {
              _guidedPart = null;
              _guidedMachine = null;
              _guidedDie = null;
              _guidedCandidates = const <LinkRef>[];
              _guidedStep = GuidedStep.part;
            });
          },
          onSwitchToBench: _leaveGuided,
        );
    }
  }

  /// Leaves the guided run with the part open on the bench.
  void _openItemOnBench(ItemDefinition item) {
    setState(() {
      final entry = _makeEntry(CreationKinds.item);
      entry.editingItem = item;
      _lineup.add(entry);
      _activeId = entry.id;
      _stepsOwnerId = entry.id;
    });
    _lineupChanged();
  }

  /// The empty bench: every master, to pick from.
  ///
  /// A Wrap rather than a grid, and deliberately **not** inside a
  /// LayoutBuilder — the comment on `fit` in [build] explains what putting any
  /// of this window inside a layout callback did to the lineup's
  /// ReorderableListView.
  Widget _buildKindChooser() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What are you adding?',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: SoftErpTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Pick as many as you need — each one gets its own form, and they '
            'all stay open together.',
            style: TextStyle(fontSize: 15, color: SoftErpTheme.textSecondary),
          ),
          const SizedBox(height: 20),
          if (_showStarterUnitsOffer) _buildStarterUnitsOffer(),
          // Factory Sheet Wizard Banner
          Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SoftErpTheme.accentSurface,
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
              border: Border.all(
                color: SoftErpTheme.accent.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: SoftErpTheme.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.table_chart_outlined,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Factory Sheet Wizard (Unified Entry)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: SoftErpTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Enter Part Identity, Client Quote, Alloy Variations, Yield in Gross/Dozen, Tooling Dies & 9-Stage Routing in one flow.',
                        style: TextStyle(
                          fontSize: 13,
                          color: SoftErpTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                AppButton(
                  key: const ValueKey('open_factory_sheet_wizard_button'),
                  label: 'Open Factory Sheet Wizard',
                  icon: Icons.arrow_forward,
                  variant: AppButtonVariant.primary,
                  onPressed: () => setState(() => _factorySheetActive = true),
                ),
              ],
            ),
          ),
          // One labelled group per tier, in the order a factory has to set
          // things up. Groups, not literal rows: 168pt cards fit five across
          // at the 1760 dialog cap but only three on a 1440 laptop, so a tier
          // wraps onto a second line there and that is fine.
          for (final tier in CreationTier.values) ...[
            Text(
              tier.label,
              key: ValueKey<String>('creation_tier_${tier.name}'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: SoftErpTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tier.reason,
              style: const TextStyle(
                fontSize: 14,
                color: SoftErpTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final spec in CreationKinds.catalog.where(
                  (spec) => spec.tier == tier,
                ))
                  _KindChoiceCard(spec: spec, onTap: () => _addKind(spec.key)),
              ],
            ),
            const SizedBox(height: 22),
          ],
          const SizedBox(height: 2),
          AppButton(
            key: const ValueKey('creation_add_all'),
            // Says all N because here it IS all of them: this chooser renders
            // only when the bench is empty (see _buildMiddle). The + menu's
            // own entry keeps "Add them all", because from a populated bench
            // it opens fewer. Counted from the catalogue so a fourteenth kind
            // cannot make this a lie.
            label: 'Open all ${CreationKinds.catalog.length} forms',
            icon: Icons.library_add_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: _addAllKinds,
          ),
        ],
      ),
    );
  }

  Widget _buildRecordEditor(_LineupEntry entry, List<ItemDefinition> items) {
    final kind = CreationKinds.byKey(entry.kind);
    // A route is the one kind whose panel needs to know something about THIS
    // bench: which part it was opened for, and which parts were made here so
    // the picker can put them first. The catalogue's thunk takes no arguments
    // — widening it would touch all fourteen specs for one kind's sake — so
    // the route is built here instead, the same way `_isAssetKey` singles out
    // die and machine a few lines down.
    final builder = entry.kind == CreationKinds.route
        ? routeEditorPanel(
            initialPartId: entry.targetItemId,
            madeHereItemIds: _addedItemIds,
          )
        : kind.editor?.call();
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
          // At the top: it is the first thing to do on an empty bench, and
          // from here the menu opens downward over the tiles instead of being
          // flipped up off the bottom of the window.
          _AddKindButton(
            options: addable,
            enabled: !_naming,
            onPick: _addKind,
            onAddAll: _addAllKinds,
          ),
          const SizedBox(height: 10),
          // Says what the bench is for: these forms are open at once, not one
          // after another. Only from two upward — "These 1 forms open
          // together" is meaningless, and at zero the chooser is showing in
          // the middle instead of a lineup.
          if (_lineup.length >= 2) ...[
            Text(
              'These ${_lineup.length} forms open together',
              key: const ValueKey<String>('creation_lineup_header'),
              style: const TextStyle(
                fontSize: 14,
                color: SoftErpTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
          ],
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
                  onRemove: () => _removeEntry(entry),
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
              // Flexible, because this column is a fixed 356 wide and the
              // longest plural in the catalogue — "Sub-contractors" — ran 11
              // pixels past it. The count gives way last: how many you have
              // added is worth more than the end of a word you can already
              // read from the tile.
              Flexible(
                child: Text(
                  kind.pluralLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: SoftErpTheme.textPrimary,
                  ),
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
    required this.sittingId,
    required this.onClose,
    this.factorySheetActive = false,
    this.onToggleFactorySheet,
  });

  final String title;
  final String? componentName;
  final CreationSessionController sessions;

  /// This opening of the window — the id the server groups its rows by, and
  /// the id the recents entry carries, which are now the same string.
  final String sittingId;
  final VoidCallback onClose;
  final bool factorySheetActive;
  final VoidCallback? onToggleFactorySheet;

  /// How many records have been saved in this opening.
  ///
  /// Read off the recents entry for this sitting rather than counted
  /// separately, because the workspace already files every save there — one
  /// source, so this cannot drift from the bench.
  int get _savedHere => sessions.recent
      .where((session) => session.id == sittingId)
      .map((session) => session.records.length)
      .firstOrNull ??
      0;

  /// Whether this user may look at a sitting at all. `audit.read`, not the
  /// per-record feed's weaker guard: a sitting is minutes of somebody's work
  /// across every master. Tolerant of a missing provider the way the rest of
  /// this window is.
  bool _canRead(BuildContext context) {
    try {
      return context.read<AuthProvider>().can('audit.read');
    } catch (_) {
      return true;
    }
  }

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
          if (onToggleFactorySheet != null) ...[
            InkWell(
              key: const ValueKey('header_toggle_factory_sheet'),
              onTap: onToggleFactorySheet,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: factorySheetActive ? SoftErpTheme.accent : SoftErpTheme.accentSoft,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: SoftErpTheme.accent),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      factorySheetActive ? Icons.view_column_outlined : Icons.table_chart_outlined,
                      size: 16,
                      color: factorySheetActive ? Colors.white : SoftErpTheme.accent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      factorySheetActive ? 'Power Bench' : 'Factory Sheet Wizard',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: factorySheetActive ? Colors.white : SoftErpTheme.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          // Rebuilt on the controller, because the count has to climb as
          // records are saved. Nothing in this header watched it before — the
          // recents field reads it only when its dropdown opens, which is why
          // it never needed to.
          ListenableBuilder(
            listenable: sessions,
            builder: (context, _) {
              // Nothing drawn until something has been saved: a count of zero
              // is not news, and there would be nothing to open.
              if (_savedHere <= 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _SittingCountPill(
                  sittingId: sittingId,
                  savedHere: _savedHere,
                  canRead: _canRead(context),
                ),
              );
            },
          ),
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
/// "6 saved here" — what this opening has produced, and a way into the detail.
///
/// The count is of records SAVED in this window, which is what the local
/// session knows. The panel it opens is headed by the server's count of
/// CHANGES, a larger number because it includes edits and links. Two different
/// words for two different things, so neither has to lie to agree with the
/// other.
///
/// Sits in the header rather than the 356px reference column, which already
/// carries the loose-ends panel plus one list and is dropped from the row
/// entirely when the link branch opens.
class _SittingCountPill extends StatelessWidget {
  const _SittingCountPill({
    required this.sittingId,
    required this.savedHere,
    required this.canRead,
  });

  final String sittingId;
  final int savedHere;
  final bool canRead;

  @override
  Widget build(BuildContext context) {
    // Deliberately NOT "N saved": the recents dropdown on this same bar
    // already says that about a remembered combination, and two controls an
    // inch apart reading "2 saved" while meaning different things is worse
    // than either wording alone.
    final label = 'This sitting · $savedHere';
    return Tooltip(
      message: canRead
          ? 'Everything recorded in this window'
          : 'You do not have permission to view activity (audit.read).',
      child: TextButton.icon(
        key: const ValueKey<String>('creation_sitting_count'),
        // Drawn disabled rather than hidden: a control that vanishes reads as
        // a missing feature, which has cost rounds of "I don't see it" here.
        onPressed: canRead
            ? () => showSittingTrackDialog(context, sittingId: sittingId)
            : null,
        icon: const Icon(Icons.history_outlined, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

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
/// Two things made on the same bench that could be joined.
/// Menu value standing for "leave this one alone". No item has a negative id,
/// so it cannot collide with a part.
const int _leaveUnattachedValue = -1;

/// One die or machine made on this bench that nothing here holds.
///
/// It names a record and the parts it could belong to — not a pair. The row
/// states a fact ("not attached to any part") and the menu is where the answer
/// is given, which is what keeps the row a fixed width.
class _LooseEnd {
  const _LooseEnd({
    required this.kind,
    required this.recordId,
    required this.recordLabel,
    required this.candidates,
  });

  final String kind;
  final String recordId;
  final String recordLabel;

  /// The parts made on this bench, any of which could take it.
  final List<ItemDefinition> candidates;

  String get key => '$kind:$recordId';

  /// Said in the words of the floor, and said about this record.
  String get sentence => kind == CreationKinds.die
      ? 'not cutting any part yet'
      : 'not running any part yet';
}

/// One master on the empty bench's chooser.
class _KindChoiceCard extends StatelessWidget {
  const _KindChoiceCard({required this.spec, required this.onTap});

  final CreationKindSpec spec;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: Material(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        child: InkWell(
          key: ValueKey('creation_choose_${spec.key}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
              border: Border.all(color: SoftErpTheme.border),
            ),
            child: Row(
              children: [
                Icon(spec.icon, size: 24, color: SoftErpTheme.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    spec.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: SoftErpTheme.textPrimary,
                    ),
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

class _AddKindButton extends StatelessWidget {
  const _AddKindButton({
    required this.options,
    required this.enabled,
    required this.onPick,
    required this.onAddAll,
  });

  /// What the menu's "add them all" entry carries. Not a kind, so the handler
  /// branches on it rather than passing it to [onPick].
  static const String addAllValue = '__add_all__';

  final List<CreationKindSpec> options;
  final bool enabled;
  final ValueChanged<String> onPick;
  final VoidCallback onAddAll;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const ValueKey('creation_add_kind'),
      enabled: enabled,
      tooltip: 'Add a form',
      onSelected: (value) =>
          value == addAllValue ? onAddAll() : onPick(value),
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          key: const ValueKey('creation_add_kind_all'),
          value: addAllValue,
          child: const Row(
            children: [
              Icon(
                Icons.library_add_outlined,
                size: 22,
                color: SoftErpTheme.accent,
              ),
              SizedBox(width: 12),
              Text(
                'Add them all',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
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
