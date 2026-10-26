import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/app_flow_hooks.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../../core/utils/stamp_format.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../groups/domain/group_definition.dart';
import '../../../groups/domain/group_inputs.dart';
import '../../../groups/presentation/group_picker_field.dart';
import '../../../groups/presentation/providers/groups_provider.dart';
import '../../../inventory/domain/inventory_set_definition.dart';
import '../../../inventory/domain/set_membership.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../units/presentation/providers/units_provider.dart';
import '../../domain/developed_for.dart';
import '../../domain/item_definition.dart';
import '../../domain/item_inputs.dart';
import '../../domain/part_code.dart';
import '../providers/items_provider.dart';
import 'part_die_section.dart';
import 'part_machine_section.dart';
import 'developed_for_form.dart';

/// Quick entry for a group, a set and the items that go in them — three
/// cascading columns, each listing what exists with a type-a-name row pinned at
/// its foot.
///
/// The point is pace. Doing this through the masters costs a group editor, a
/// set editor whose every composition row needs a picker, and an item editor
/// per item. Here a name and a tick is the whole gesture, and each tick writes
/// immediately so what you see on the list is real.
///
/// The one exception is a set, which has no legal empty state: the backend
/// refuses a set with no lines. So a ticked set name is a local draft, drawn as
/// PENDING, and the first item that goes into it is what creates it.
class CatalogQuickEntryDialog extends StatefulWidget {
  const CatalogQuickEntryDialog({super.key, this.initialGroupId});

  /// The group to open on, when the caller already knows which one.
  final int? initialGroupId;

  static Future<void> open(BuildContext context, {int? initialGroupId}) {
    return showErpFormDialog<void>(
      context,
      // The whole screen, bar the dialog's own 24px gutter. Three columns and
      // the Developed For panel under them do not fit in a 1180x760 box, and
      // the point of this screen is seeing where a part lands and who it is
      // for at the same time.
      //
      // Deliberately uncapped, unlike _creationDialogWidth in
      // component_creation_screen.dart, which stops widening at 1760.
      //
      // The sizes are read as: width becomes a fixed
      // `min(maxWidth, screen - insets)`, so infinity means "as wide as there
      // is"; height is only a CAP, and this dialog fills it because its body
      // is a Column with an Expanded in it under `bodyScrollable: false`. Keep
      // that Expanded or the card silently shrink-wraps again.
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      child: CatalogQuickEntryDialog(initialGroupId: initialGroupId),
    );
  }

  @override
  State<CatalogQuickEntryDialog> createState() =>
      _CatalogQuickEntryDialogState();
}

/// The made-just-now rail, and the width the sections are held to.
///
/// Sections are capped rather than filling a full-screen dialog: a text field
/// 2000px wide on a 2560 monitor is unreadable, and the room this screen won
/// by dropping the columns is meant for more sections, not wider ones.
const double _railWidth = 320;
const double _sectionsMaxWidth = 900;

/// `showErpFormDialog`'s own mobile breakpoint. Below it the dialog is a
/// bottom sheet with no bounded height, so the rail goes under the sections
/// instead of beside them.
const double _narrowBelow = 900;

/// The value the Set field carries while a set has been named but not created.
///
/// A sentinel rather than null, because "no set" and "a set that does not
/// exist yet" are different answers and the field has to show the second one.
/// No real set has a negative id.
const int kPendingSetId = -1;

/// A set name someone has ticked that has no items yet, so it does not exist on
/// the server. It remembers its group, so it shows only under the group it was
/// typed for.
class _PendingSet {
  const _PendingSet({required this.name, required this.groupId});

  final String name;
  final int groupId;
}

class _CatalogQuickEntryDialogState extends State<CatalogQuickEntryDialog> {
  int? _selectedGroupId;
  int? _selectedSetId;
  _PendingSet? _pendingSet;

  /// The name of the part being staged. The Part dropdown's create row fills
  /// it rather than writing, so the code can be watched filling in while it is
  /// checked — groups and sets are created from inside their own pickers and
  /// need no controller here.
  final TextEditingController _itemNameController = TextEditingController();
  final FocusNode _itemNameFocus = FocusNode();

  /// Sticky across ticks: having chosen Pieces once, the next five rows should
  /// not ask again.
  int? _groupRowUnitId;
  int? _itemRowUnitId;

  /// Whether a new group nests under the selection. True by default — the
  /// cascade's premise is that you are working inside the selected group.
  bool _nestUnderSelection = true;

  /// The part's identity: the number it is issued and the code read off a
  /// drawing. Both are filled in from the server's suggestion and both can be
  /// typed over.
  final TextEditingController _partNoController = TextEditingController();
  final TextEditingController _partCodeController = TextEditingController();
  final FocusNode _partNoFocus = FocusNode();
  final FocusNode _partCodeFocus = FocusNode();

  /// Set once the user types in the field, after which the wizard stops
  /// rewriting it. Two flags, not one: editing the number re-derives the code,
  /// so without its own pin a hand-typed number would be discarded the next
  /// time the set changed.
  bool _partNoPinned = false;
  bool _partCodePinned = false;

  /// What the code would be once the part has a name. Shown as a hint rather
  /// than held in the field, so it cannot be ticked as though it were typed.
  String _partCodeHint = '';

  /// Guards the async suggestion against its own history. The user keeps
  /// typing while a request is in flight, and an answer for "Patt" must not
  /// land on top of "Patti". Separate from [_busy], which is the write guard
  /// and would grey the row out on every keystroke.
  int _suggestSeq = 0;

  /// One write at a time. `ItemsProvider` returns a bare null when a save is
  /// already running, and `saveSet` has no re-entrancy guard at all — two
  /// overlapping merges would both compute against the pre-write snapshot and
  /// the second would drop the first's line.
  bool _busy = false;

  String? _error;
  String? _notice;

  /// Dies and machines filled in for a part that does not exist yet.
  ///
  /// Held here rather than inside the sections because the create path has to
  /// flush them and the close path has to warn about them; a section holding
  /// its own would be a second truth this would then have to ask for.
  final List<DieSheetDraft> _stagedDies = <DieSheetDraft>[];
  final List<MachineSheetDraft> _stagedMachines = <MachineSheetDraft>[];

  /// Dies and machines that were written with a part and could not be attached
  /// to it. Kept so the retry only links, and never makes a second one.
  List<String> _unlinkedDieIds = const <String>[];
  List<String> _unlinkedMachineIds = const <String>[];

  /// Everything made in this sitting, newest first.
  ///
  /// What the three columns used to answer — "what is in here, and what have I
  /// just done" — now that they are dropdowns. Each row goes back to its part.
  final List<_MadeRow> _madeRows = <_MadeRow>[];

  /// Who the NEXT part ticked will have been developed for.
  ///
  /// Session state, like the unit already is: fill it once and every part
  /// ticked afterwards carries it. That is why the amount is labelled
  /// "Quotation for this part" — three ticks at 85000 record 85000 three
  /// times, which is the intended reading and worth saying out loud.
  ///
  /// Distinct from [_editedDevelopedFor], which is about a part that already
  /// exists. Selecting a part must never disturb this one, or walking over to
  /// an old part to read who it was for would quietly rewrite what the next
  /// tick stamps.
  DevelopedFor _draftDevelopedFor = DevelopedFor.empty;

  /// The part whose Developed For the panel is editing, or null for the next
  /// part to be ticked. Cleared whenever the scope moves out from under it.
  int? _selectedItemId;

  /// The staged edit for [_selectedItemId]. Null means nothing has been
  /// touched since that part was selected, which is also how the panel knows
  /// not to offer Save.
  DevelopedFor? _editedDevelopedFor;

  @override
  void initState() {
    super.initState();
    _selectedGroupId = widget.initialGroupId;
    // Sets live on the inventory provider, which the Items view of the master
    // never touches — without this, column 2 reads "no sets" under every
    // group. Idempotent.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<InventoryProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _itemNameController.dispose();
    _partNoController.dispose();
    _partCodeController.dispose();
    _itemNameFocus.dispose();
    _partNoFocus.dispose();
    _partCodeFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------------

  /// The only way the group changes. Clearing the set selection here is what
  /// stops an item created in one group being appended to a set filed under
  /// another — nothing on the server would refuse that.
  void _selectGroup(int? groupId) {
    setState(() {
      _selectedGroupId = groupId;
      _selectedSetId = null;
      // The selected part belongs to the group that was showing, so it goes
      // with it rather than leaving the panel editing something off-screen.
      _clearItemSelection();
      _error = null;
      _notice = null;
      _itemNameController.clear();
      _nestUnderSelection = true;
      _resetPartIdentity();
    });
    _refreshPartIdentity();
  }

  /// Picking a set — including [kPendingSetId], the one that does not exist
  /// yet. Discarding the draft is the chip's ✕, never this.
  void _selectSet(int? setId) {
    setState(() {
      _selectedSetId = setId;
      _clearItemSelection();
      _error = null;
      _notice = null;
    });
    // The scope changed, so the number does: 48 of Dolly is not 48 of Chakri.
    _refreshPartIdentity();
  }

  // ---------------------------------------------------------------------------
  // Part identity
  // ---------------------------------------------------------------------------

  /// Back to automatic. Called after a successful tick and whenever the scope
  /// moves out from under what was typed.
  void _resetPartIdentity() {
    _partNoPinned = false;
    _partCodePinned = false;
    _partNoController.clear();
    _partCodeController.clear();
    _partCodeHint = '';
  }

  /// Asks the server what the next part here should be called, and fills in
  /// whatever the user has not taken over.
  Future<void> _refreshPartIdentity() async {
    final groupId = _selectedGroupId;
    if (groupId == null) return;
    if (_partNoPinned && _partCodePinned) return;

    final seq = ++_suggestSeq;
    final pending = _visiblePendingSet;
    final suggestion = await context.read<ItemsProvider>().nextPartIdentity(
      groupId: groupId,
      // Never the sentinel: a set that does not exist has an empty scope, and
      // `setPending` is how that is said.
      setId: pending != null || _selectedSetId == kPendingSetId
          ? null
          : _selectedSetId,
      setPending: pending != null,
      setName: pending?.name ?? '',
      name: _itemNameController.text.trim(),
    );
    // A later keystroke already asked a newer question.
    if (!mounted || seq != _suggestSeq || suggestion == null) return;

    final named = _itemNameController.text.trim().isNotEmpty;
    setState(() {
      if (!_partNoPinned) _partNoController.text = '${suggestion.partNo}';
      if (_partCodePinned) return;
      // Without a name the code is only a prospect, so it waits in the hint.
      _partCodeHint = suggestion.partCode;
      _partCodeController.text = named ? suggestion.partCode : '';
    });
  }

  /// The code for what is on screen right now, derived locally so the field
  /// keeps up with typing. The number comes from the server; the letters do
  /// not need to.
  String _derivedPartCode({required GroupsProvider groups, required InventoryProvider inventory}) {
    final group = _selectedGroup(groups);
    final pending = _visiblePendingSet;
    final set = pending == null ? _selectedSet(inventory) : null;
    return buildPartCode(
      groupName: group?.name,
      setName: pending?.name ?? set?.name,
      itemName: _itemNameController.text.trim(),
      partNo: int.tryParse(_partNoController.text.trim()),
    );
  }

  /// The name changed, so the letters do. The number stands — it belongs to
  /// the scope, not to the name.
  void _onItemNameChanged({
    required GroupsProvider groups,
    required InventoryProvider inventory,
  }) {
    setState(() {
      if (_partCodePinned) return;
      final derived = _derivedPartCode(groups: groups, inventory: inventory);
      _partCodeHint = derived;
      _partCodeController.text = _itemNameController.text.trim().isEmpty
          ? ''
          : derived;
    });
  }

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  GroupDefinition? _selectedGroup(GroupsProvider groups) =>
      _selectedGroupId == null ? null : groups.findById(_selectedGroupId);

  List<InventorySetDefinition> _setsInGroup(InventoryProvider inventory) {
    final groupId = _selectedGroupId;
    if (groupId == null) return const <InventorySetDefinition>[];
    // Strict equality, not descendants: this column has to list exactly the
    // population its add row would create. A set produced by a run is a record
    // of what fed that run, not something to hand-edit here.
    return inventory.sets
        .where((set) => set.groupId == groupId && !set.isTemporary)
        .toList(growable: false);
  }

  int _ungroupedSetCount(InventoryProvider inventory) => inventory.sets
      .where((set) => set.groupId == null && !set.isTemporary)
      .length;

  List<ItemDefinition> _itemsInGroup(ItemsProvider items) {
    final groupId = _selectedGroupId;
    if (groupId == null) return const <ItemDefinition>[];
    // ItemsProvider.items carries archived items; the server would refuse one
    // as a set line, and nobody means to add one anyway.
    return items.items
        .where((item) => item.groupId == groupId && !item.isArchived)
        .toList(growable: false);
  }

  /// The set in play, or null — including when the field is showing a set that
  /// has only been named, which no stored row can match.
  InventorySetDefinition? _selectedSet(InventoryProvider inventory) =>
      _selectedSetId == null || _selectedSetId == kPendingSetId
      ? null
      : inventory.sets.where((set) => set.id == _selectedSetId).firstOrNull;

  /// The draft, but only while its own group is the one on screen.
  _PendingSet? get _visiblePendingSet =>
      _pendingSet != null && _pendingSet!.groupId == _selectedGroupId
      ? _pendingSet
      : null;

  List<SearchableSelectOption<int>> _unitOptions(UnitsProvider units) {
    // Offer and seed from the SAME list. Seeding a preselected id from a list
    // the picker does not offer is how every quick-created item once ended up
    // with the same unit.
    return units.activeUnits
        .map(
          (unit) => SearchableSelectOption<int>(
            value: unit.id,
            // displayLabel is already 'Name (sym)'; appending the symbol again
            // renders "Piece (pcs) (pcs)".
            label: unit.displayLabel,
          ),
        )
        .toList(growable: false);
  }

  int? _seedUnitId({
    required UnitsProvider units,
    required GroupsProvider groups,
    required int? sticky,
  }) {
    final active = units.activeUnits;
    if (active.isEmpty) return null;
    bool isActive(int? id) => id != null && active.any((u) => u.id == id);
    if (isActive(sticky)) return sticky;
    final group = _selectedGroup(groups);
    if (isActive(group?.unitId)) return group!.unitId;
    return active.first.id;
  }

  /// What a part is called and when it was stamped, with [trailing] after it.
  ///
  /// The number never appears on its own — "48" says nothing without "of
  /// Dolly" — and a part with no code shows no separator standing where one
  /// would have been.
  String? _identityLine(ItemDefinition item, {String? trailing}) {
    final parts = <String>[
      if (item.partCode.trim().isNotEmpty) item.partCode.trim(),
      partStampDate(item.createdAt),
      if (trailing != null && trailing.isNotEmpty) trailing,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  /// Creates a group from a name typed into the Group picker.
  ///
  /// Returns it, so the picker can select what it just made. Null means it was
  /// refused, and [_error] says why — but see the caller: a refusal inside a
  /// picker route has to be spoken through a toast, because the error banner
  /// is behind it.
  Future<GroupDefinition?> _createGroup(String rawName) async {
    if (_busy) return null;
    final name = rawName.trim();
    if (name.isEmpty) return null;

    final groups = context.read<GroupsProvider>();
    final units = context.read<UnitsProvider>();
    final unitId = _seedUnitId(
      units: units,
      groups: groups,
      sticky: _groupRowUnitId,
    );
    if (unitId == null) {
      setState(() => _error = 'No active unit exists — create one in Units first.');
      return null;
    }

    final selected = _selectedGroup(groups);
    // A combination group neither auto-parents nor requires a unit on the
    // server, and it is not a container in the sense this column means, so a
    // new group never nests under one.
    final nests =
        _nestUnderSelection &&
        selected != null &&
        !selected.isCombination;
    final parentGroupId = nests ? selected.id : null;

    // The server auto-parents a new top-level hierarchical group under Primary
    // Group, so for a top-level add the duplicate check has to be run against
    // Primary Group — not against the null parent the client is sending.
    final resolvedParentId = parentGroupId ?? _primaryGroupId(groups);
    if (groups
        .checkDuplicate(name: name, parentGroupId: resolvedParentId)
        .blockingDuplicate) {
      setState(
        () => _error =
            'A group called "$name" already exists there. '
            'Pick it from the list, or use another name.',
      );
      return null;
    }

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    final created = await groups.createGroup(
      CreateGroupInput(
        name: name,
        groupType: 'item',
        groupStructure: 'hierarchical',
        unitId: unitId,
        parentGroupId: parentGroupId,
      ),
    );
    if (!mounted) return null;

    if (created == null) {
      setState(() {
        _busy = false;
        // A null with nothing to say is the re-entrancy guard, not a rejection.
        _error = groups.errorMessage ?? _kConcurrentWrite;
      });
      return null;
    }
    setState(() {
      _busy = false;
      _groupRowUnitId = unitId;
    });
    _selectGroup(created.id);
    return created;
  }

  int? _primaryGroupId(GroupsProvider groups) => groups.groups
      .where(
        (group) =>
            group.parentGroupId == null &&
            group.groupType == 'item' &&
            group.name == 'Primary Group',
      )
      .firstOrNull
      ?.id;

  /// Naming a set writes nothing — it cannot, with no lines to send. The draft
  /// is selected straight away so the next part created lands in it.
  void _namePendingSet(String rawName) {
    if (_busy) return;
    final name = rawName.trim();
    final groupId = _selectedGroupId;
    if (name.isEmpty || groupId == null) return;

    final dropped = _pendingSet != null && _pendingSet!.groupId != groupId
        ? _pendingSet!.name
        : null;
    setState(() {
      _pendingSet = _PendingSet(name: name, groupId: groupId);
      // The sentinel, not null: the field has to show the named set.
      _selectedSetId = kPendingSetId;
      _error = null;
      _notice = null;
    });
    // A set that has only been named holds nothing, so this part is its first.
    _refreshPartIdentity();
    // One invisible draft is tolerable; two are not.
    if (dropped != null) {
      showAppToast(
        context,
        '"$dropped" was never created — it had no items.',
        kind: AppToastKind.warning,
      );
    }
  }

  Future<void> _createItem() async {
    if (_busy) return;
    final name = _itemNameController.text.trim();
    final groupId = _selectedGroupId;
    if (name.isEmpty || groupId == null) return;

    final items = context.read<ItemsProvider>();
    final groups = context.read<GroupsProvider>();
    final units = context.read<UnitsProvider>();
    final unitId = _seedUnitId(
      units: units,
      groups: groups,
      sticky: _itemRowUnitId,
    );
    if (unitId == null) {
      setState(() => _error = 'No active unit exists — create one in Units first.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    final typedPartNo = int.tryParse(_partNoController.text.trim());
    final typedPartCode = _partCodeController.text.trim();
    final created = await items.createItem(
      CreateItemInput(
        name: name,
        // What every list, challan line and invoice prints. The name as typed,
        // never a composed one.
        displayName: name,
        groupId: groupId,
        unitId: unitId,
        partNo: typedPartNo,
        // Empty is a real answer — a part may have no code — so it is sent as
        // '' rather than omitted, which would mean "say nothing".
        partCode: typedPartCode,
        // Goes out with the part, in the one write that creates it. Null when
        // nothing has been filled in, which leaves the column alone rather
        // than writing an empty answer over it.
        developedFor: _draftDevelopedFor.isEmpty ? null : _draftDevelopedFor,
      ),
    );
    if (!mounted) return;

    if (created == null) {
      final takenCode = items.errorCode == 'part_code_duplicate';
      setState(() {
        _busy = false;
        // Keep the typed name and unit: clearing on failure throws away the
        // user's typing.
        _error = items.errorMessage ?? _kConcurrentWrite;
      });
      if (takenCode) {
        // Somebody else took it between the suggestion and the tick. Offer a
        // fresh one and let the user tick again — never retry the write, which
        // is how two parts get created when only the response was lost.
        _resetPartIdentity();
        await _refreshPartIdentity();
      }
      return;
    }

    final pendingAtCreate = _visiblePendingSet;
    setState(() {
      _madeRows.insert(
        0,
        _MadeRow(
          itemId: created.id,
          groupId: groupId,
          groupName: _selectedGroup(groups)?.name ?? '',
          // Null while the set is only a draft; _fileIntoSetIfAny fills it in
          // the moment the set becomes real, or a row would point at a scope
          // that never existed.
          setId: pendingAtCreate != null || _selectedSetId == kPendingSetId
              ? null
              : _selectedSetId,
          setName: pendingAtCreate?.name ??
              _selectedSet(context.read<InventoryProvider>())?.name ??
              '',
          partLabel: created.displayName.trim().isEmpty
              ? created.name
              : created.displayName,
          partCode: created.partCode,
        ),
      );
      _itemRowUnitId = unitId;
      _itemNameController.clear();
      _resetPartIdentity();
    });
    await _fileIntoSetIfAny(created, itemWasJustCreated: true);
    if (!mounted) return;
    await _flushStaged(created);
    if (!mounted) return;
    setState(() {
      _busy = false;
      // Stay on the part just made, so a third die is one more Add away
      // rather than a save, a hunt through the list and a tap. The sticky
      // draft is safe: the create above already consumed it.
      _selectedItemId = created.id;
      _editedDevelopedFor = null;
    });
    // The part just created is in the scope now, so the next number moved.
    await _refreshPartIdentity();
  }

  /// Writes the dies and machines that were held for a part that did not
  /// exist, then attaches them — all of it after the part itself is real.
  ///
  /// Each draft leaves the held list the moment it lands, so a second Create
  /// part after a failure writes only what is still outstanding. Nothing is
  /// retried blindly: that is how two dies get made when only one response
  /// was lost.
  Future<void> _flushStaged(ItemDefinition part) async {
    if (_stagedDies.isEmpty && _stagedMachines.isEmpty) return;
    final dieHook = AppFlowHooks.createDieFromSheet;
    final machineHook = AppFlowHooks.createMachineFromSheet;

    final dieIds = <String>[];
    final machineIds = <String>[];
    String? failure;

    for (final draft in List<DieSheetDraft>.of(_stagedDies)) {
      if (dieHook == null) break;
      // With the part's FINAL code, not the one it was held with: the
      // suggestion it was filled in against may have moved.
      final outcome = await dieHook(
        context,
        DieSheetDraft(
          toolCode: draft.toolCode,
          dieType: draft.dieType,
          // Both carried: a typed type without its label is refused, and the
          // upsert stores a missing maker id as "no maker".
          dieTypeLabel: draft.dieTypeLabel,
          madeBy: draft.madeBy,
          dieMakerId: draft.dieMakerId,
          poAt: draft.poAt,
          dateInAt: draft.dateInAt,
          linerSizeNm: draft.linerSizeNm,
          linerSizeUnit: draft.linerSizeUnit,
          noOfSet: draft.noOfSet,
          storeArea: draft.storeArea,
          rackNo: draft.rackNo,
          partCode: part.partCode,
          partName: part.displayName.trim().isEmpty
              ? part.name
              : part.displayName,
        ),
      );
      if (!mounted) return;
      if (!outcome.isCreated) {
        failure =
            'Die ${draft.toolCode} was not made — '
            '${outcome.message ?? 'it was refused'}.';
        break;
      }
      dieIds.add(outcome.record!.id);
      setState(() => _stagedDies.remove(draft));
    }

    for (final draft in List<MachineSheetDraft>.of(_stagedMachines)) {
      if (machineHook == null || failure != null) break;
      final outcome = await machineHook(context, draft);
      if (!mounted) return;
      if (!outcome.isCreated) {
        failure =
            'Machine ${draft.assetId} was not made — '
            '${outcome.message ?? 'it was refused'}.';
        break;
      }
      machineIds.add(outcome.record!.id);
      setState(() => _stagedMachines.remove(draft));
    }

    if (dieIds.isNotEmpty || machineIds.isNotEmpty) {
      // One call carrying both, because each list is a full replace: two calls
      // would have the second undo the first.
      final items = context.read<ItemsProvider>();
      final saved = await items.setItemLinks(
        part.id,
        dieIds: dieIds,
        machineIds: machineIds,
      );
      if (!mounted) return;
      if (saved == null) {
        setState(() {
          _unlinkedDieIds = dieIds;
          _unlinkedMachineIds = machineIds;
          _error =
              '${part.name} was made, and so were its dies and machines — but '
              'they could not be attached to it. Use Attach them below; they '
              'will not be made again.';
        });
        return;
      }
    }

    if (failure != null) {
      setState(() {
        _error =
            '${part.name} was created and the rest is still held. $failure';
      });
    }
  }

  /// Attaches what was made with a part but could not be linked to it.
  Future<void> _attachUnlinked() async {
    final items = context.read<ItemsProvider>();
    final part = _selectedItem(items);
    if (part == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final saved = await items.setItemLinks(
      part.id,
      dieIds: <String>[...part.dies.map((die) => die.id), ..._unlinkedDieIds],
      machineIds: <String>[
        ...part.machines.map((machine) => machine.id),
        ..._unlinkedMachineIds,
      ],
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (saved == null) {
        _error = items.errorMessage ?? _kConcurrentWrite;
        return;
      }
      _unlinkedDieIds = const <String>[];
      _unlinkedMachineIds = const <String>[];
      _notice = 'Attached to ${part.name}.';
    });
  }

  /// Appends an item that already exists to the set in play.
  Future<void> _appendExistingItem(ItemDefinition item) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    await _fileIntoSetIfAny(item, itemWasJustCreated: false);
    if (mounted) setState(() => _busy = false);
  }

  /// The second half of a tick: the set, if one is in play at all.
  ///
  /// Read the set back from the provider here rather than capturing it before
  /// the item write — the item write refreshes the lists.
  Future<void> _fileIntoSetIfAny(
    ItemDefinition item, {
    required bool itemWasJustCreated,
  }) async {
    final inventory = context.read<InventoryProvider>();
    final groupId = _selectedGroupId;
    final pending = _visiblePendingSet;

    if (pending != null) {
      final saved = await inventory.saveSet(
        SaveInventorySetInput(
          name: pending.name,
          // A create owns the group question outright.
          groupId: pending.groupId,
          groupIdSpecified: true,
          lines: <SaveInventorySetLineInput>[newSetLineFor(item, position: 0)],
        ),
      );
      if (!mounted) return;
      if (saved == null) {
        setState(() {
          // The item exists and the set does not. Say exactly that, and leave
          // the draft standing — the item is now in column 3's "not in this
          // set" section, so the retry appends instead of creating a duplicate.
          _error = itemWasJustCreated
              ? 'Created "${item.displayName}" in the group, but "${pending.name}" '
                    'could not be created: ${inventory.errorMessage ?? _kConcurrentWrite} '
                    'Tap the item in the list to try again — its part no '
                    '${item.partNo ?? '-'} stays reserved for "${pending.name}" '
                    'until you do.'
              : (inventory.errorMessage ?? _kConcurrentWrite);
        });
        return;
      }
      setState(() {
        _pendingSet = null;
        _selectedSetId = saved.id;
        for (final row in _madeRows) {
          if (row.setId == null && row.setName == saved.name) {
            row.setId = saved.id;
          }
        }
      });
      return;
    }

    // Read the sets back first: this dialog's copy is as old as the time it has
    // been open, and the version sent below has to be current or a wizard left
    // open would refuse every tick.
    await inventory.reloadSets();
    if (!mounted) return;
    final existing = _selectedSet(inventory);
    if (existing == null) return;
    // Belt and braces for invariant 6: a set filed elsewhere must never take a
    // line from this group.
    if (existing.groupId != groupId) {
      setState(
        () => _error =
            '"${existing.name}" is filed under another group now. '
            'Pick it again to add to it.',
      );
      return;
    }
    if (existing.lines.any(
      (line) => line.itemId == item.id && line.variationLeafNodeId == 0,
    )) {
      setState(
        () => _notice = '"${item.displayName}" is already in "${existing.name}".',
      );
      return;
    }

    await inventory.saveSet(
      SaveInventorySetInput(
        id: existing.id,
        name: existing.name,
        // Carried deliberately: the server writes photo_url on every update, so
        // leaving it out clears the set's photo.
        photoUrl: existing.photoUrl ?? '',
        // No groupId key at all. Absent means "leave the link alone"; sending
        // it here would re-file the set.
        expectedVersion: existing.version,
        lines: mergeSetLines(existing, added: item),
      ),
    );
    if (!mounted) return;
    if (inventory.errorMessage != null) {
      setState(() => _error = inventory.errorMessage);
    }
  }

  static const String _kConcurrentWrite =
      'Another save was already running — try again.';

  // ---------------------------------------------------------------------------
  // Close
  // ---------------------------------------------------------------------------

  Future<void> _close() async {
    final pending = _pendingSet;
    if (pending != null) {
      final discard = await showConfirmDialog(
        context,
        title: 'Discard "${pending.name}"?',
        message:
            '"${pending.name}" has no items yet, so it was never created. '
            'Close anyway?',
        confirmLabel: 'Discard',
      );
      if (!discard || !mounted) return;
    }
    // A held die is as invisible and as losable as a named set, and it is the
    // only other thing on this screen that exists nowhere but the screen.
    final held = _stagedDies.length + _stagedMachines.length;
    if (held > 0) {
      final what = <String>[
        if (_stagedDies.isNotEmpty)
          '${_stagedDies.length} die${_stagedDies.length == 1 ? '' : 's'}',
        if (_stagedMachines.isNotEmpty)
          '${_stagedMachines.length} '
              'machine${_stagedMachines.length == 1 ? '' : 's'}',
      ].join(' and ');
      final discard = await showConfirmDialog(
        context,
        title: 'Discard $what?',
        message:
            'They are filled in but held, waiting for a part to be created. '
            'Nothing has been written. Close anyway?',
        confirmLabel: 'Discard',
      );
      if (!discard || !mounted) return;
    }
    // Creating an item does not refresh the groups list, so a group's item
    // count would stay stale behind the dialog. Once, on the way out.
    if (_madeRows.isNotEmpty) {
      await context.read<GroupsProvider>().refresh();
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// Esc clears what is being typed before it closes anything — the cross's
  /// job. Only once the part being staged is empty does it fall through to the
  /// close path, which confirms if a draft set is live.
  void _onDismiss() {
    final typed = <TextEditingController>[
      _itemNameController,
      _partNoController,
      _partCodeController,
    ];
    if (typed.any((controller) => controller.text.isNotEmpty)) {
      setState(() {
        _itemNameController.clear();
        _resetPartIdentity();
      });
      return;
    }
    _close();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final groups = context.watch<GroupsProvider>();
    final items = context.watch<ItemsProvider>();
    final inventory = context.watch<InventoryProvider>();
    final units = context.watch<UnitsProvider>();

    // From MediaQuery, never a LayoutBuilder: a LayoutBuilder around a row
    // carrying overlay-bearing lists — which these pickers are — once put one
    // inside a layout callback and tripped a mid-layout assert. It does not
    // reproduce in a widget test, so the rule is structural.
    final narrow = MediaQuery.sizeOf(context).width < _narrowBelow;

    final sections = <Widget>[
      _buildPartSection(groups, items, inventory, units),
      const SizedBox(height: 14),
      _buildDevelopedForPanel(items, scrollable: false),
      const SizedBox(height: 14),
      PartDieSection(
        part: _selectedItem(items),
        partCode: _sheetPartCode(items),
        partLabel: _sheetPartLabel(items),
        busy: _busy,
        staged: _stagedDies,
        onStage: (draft) => setState(() => _stagedDies.add(draft)),
        onUnstage: (index) => setState(() => _stagedDies.removeAt(index)),
        onDiesChanged: _setDiesOnSelectedPart,
      ),
      const SizedBox(height: 14),
      PartMachineSection(
        part: _selectedItem(items),
        partCode: _sheetPartCode(items),
        partLabel: _sheetPartLabel(items),
        busy: _busy,
        staged: _stagedMachines,
        onStage: (draft) => setState(() => _stagedMachines.add(draft)),
        onUnstage: (index) => setState(() => _stagedMachines.removeAt(index)),
        onMachinesChanged: _setMachinesOnSelectedPart,
      ),
    ];

    return ErpFormScaffold(
      title: 'Quick entry',
      subtitle:
          'Where the part goes, what it is called, and everything else about '
          'it — on one screen.',
      onClose: _close,
      // The scaffold's own scroll is off so this body can keep an Expanded in
      // it: the dialog fills the screen only because something inside takes
      // the height. Lose that and the card shrink-wraps to its content, which
      // `items_reveal_test` measures.
      //
      // It also buys the better arrangement — the three dropdowns stay put
      // while the sections under them scroll.
      bodyScrollable: false,
      errorBanner: _error != null
          ? ErpFormMessageBanner(message: _error!)
          : (_notice != null
                ? ErpFormMessageBanner(message: _notice!, isError: false)
                : null),
      headerActions: _unlinkedDieIds.isEmpty && _unlinkedMachineIds.isEmpty
          ? null
          : AppButton(
              key: const ValueKey<String>('quick-entry-attach-unlinked'),
              label: 'Attach them',
              icon: Icons.link_rounded,
              variant: AppButtonVariant.secondary,
              onPressed: _busy ? null : _attachUnlinked,
            ),
      body: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              _onDismiss();
              return null;
            },
          ),
        },
        child: narrow
            // A bottom sheet has no bounded height to divide, so the rail goes
            // above the sections and the whole thing scrolls as one.
            ? SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildScopeRow(
                      groups,
                      items,
                      inventory,
                      units,
                      narrow: true,
                    ),
                    const SizedBox(height: 16),
                    _buildMadeList(),
                    const SizedBox(height: 14),
                    ...sections,
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildScopeRow(
                    groups,
                    items,
                    inventory,
                    units,
                    narrow: false,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: _railWidth,
                          child: SingleChildScrollView(child: _buildMadeList()),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: _sectionsMaxWidth,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: sections,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      footer: Row(
        children: [
          if (_busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          const Spacer(),
          // The only primary AppButton in this subtree, deliberately:
          // SubmitFormShortcuts fires the LAST enabled primary AppButton in the
          // tree on Cmd/Ctrl+Enter, regardless of what has focus. Were Create
          // part or Add die primary, that shortcut would write whatever
          // happened to be half-typed.
          AppButton(label: 'Done', icon: Icons.check, onPressed: _close),
        ],
      ),
    );
  }

  /// Group · set · part, as three dropdowns and a line saying where a tick
  /// lands. What three Miller columns used to answer in a third of the screen.
  Widget _buildScopeRow(
    GroupsProvider groups,
    ItemsProvider items,
    InventoryProvider inventory,
    UnitsProvider units, {
    required bool narrow,
  }) {
    final fields = <Widget>[
      _buildGroupField(groups, units),
      _buildSetField(inventory),
      _buildPartField(items, inventory),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (narrow)
          Column(
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                fields[i],
              ],
            ],
          )
        else
          Row(
            key: const ValueKey<String>('quick-entry-scope-row'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: fields[i]),
              ],
            ],
          ),
        const SizedBox(height: 8),
        Text(_scopeLine(groups, inventory), style: _scopeLineStyle),
      ],
    );
  }

  static const TextStyle _scopeLineStyle = TextStyle(
    fontSize: 13.5,
    color: SoftErpTheme.textSecondary,
    fontWeight: FontWeight.w600,
  );

  String _scopeLine(GroupsProvider groups, InventoryProvider inventory) {
    final group = _selectedGroup(groups);
    if (group == null) return 'Pick a group to start — or type a new name into it.';
    final set = _selectedSet(inventory);
    final pending = _visiblePendingSet;
    if (set != null) return 'Goes into ${group.name} · line of ${set.name}';
    if (pending != null) {
      return 'Goes into ${group.name} · creates ${pending.name}';
    }
    return 'Goes into ${group.name}';
  }

  /// Everything made in this sitting. Each row goes back to its part.
  Widget _buildMadeList() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeading(label: 'Made just now'),
          const SizedBox(height: 8),
          if (_madeRows.isEmpty)
            const Text(
              'Nothing yet. What you create here is listed so you can go back '
              'to it and keep filling it in.',
              style: TextStyle(
                fontSize: 13,
                color: SoftErpTheme.textSecondary,
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _madeRows.length,
                itemBuilder: (context, index) {
                  final row = _madeRows[index];
                  return _MadeRowTile(
                    key: ValueKey<String>('quick-entry-made-row-${row.itemId}'),
                    row: row,
                    selected: row.itemId == _selectedItemId,
                    onTap: _busy ? null : () => _restoreMadeRow(row),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  /// Goes back to a part made earlier in this sitting, and to the scope it was
  /// made in.
  ///
  /// Deliberately not through [_selectGroup], which clears the set and the
  /// part selection by design — here the whole point is to restore all three.
  void _restoreMadeRow(_MadeRow row) {
    setState(() {
      _selectedGroupId = row.groupId;
      _selectedSetId = row.setId;
      _selectedItemId = row.itemId;
      // The staged edit belonged to the part being left behind.
      _editedDevelopedFor = null;
      _error = null;
      _notice = null;
      _resetPartIdentity();
    });
    _refreshPartIdentity();
  }

  /// The part the panel is editing, or null when it is about the next tick.
  ItemDefinition? _selectedItem(ItemsProvider items) {
    final id = _selectedItemId;
    if (id == null) return null;
    return items.items.where((item) => item.id == id).firstOrNull;
  }

  /// Back to editing what the next tick will stamp. Always paired with the
  /// staged edit, which belongs to the part being left behind.
  void _clearItemSelection() {
    _selectedItemId = null;
    _editedDevelopedFor = null;
  }

  /// Developed For, for whichever part the screen is about.
  ///
  /// Two different things are edited here and the heading says which: the
  /// NEXT part to be ticked, which is staged and written by the tick itself,
  /// or a part that already exists, which is written by Save. Keeping them
  /// apart is what stops a look at an old part rewriting what the next tick
  /// stamps.
  Widget _buildDevelopedForPanel(ItemsProvider items, {required bool scrollable}) {
    final selected = _selectedItem(items);
    final stored = selected?.developedFor ?? DevelopedFor.empty;
    final value = selected == null
        ? _draftDevelopedFor
        : (_editedDevelopedFor ?? stored);
    final dirty = selected != null &&
        _editedDevelopedFor != null &&
        _editedDevelopedFor != stored;
    final name = selected == null
        ? null
        : (selected.displayName.trim().isEmpty
              ? selected.name
              : selected.displayName);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _SectionHeading(
                label: name == null
                    ? 'Developed For · next part'
                    : 'Developed For · $name',
              ),
            ),
            if (dirty) ...[
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _editedDevelopedFor = null),
                child: const Text('Cancel', style: TextStyle(fontSize: 13.5)),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: value.needsParty
                    ? 'Pick the ${value.kind == DevelopedForKind.contractor ? 'contractor' : 'client'} '
                          'first — the server refuses a part developed for '
                          'nobody in particular.'
                    : 'Save who this part was developed for.',
                child: AppButton(
                  key: const ValueKey<String>('quick-entry-developed-for-save'),
                  label: 'Save',
                  icon: Icons.check_rounded,
                  variant: AppButtonVariant.secondary,
                  isLoading: _busy,
                  onPressed: _busy || value.needsParty
                      ? null
                      : () => _saveDevelopedFor(selected.id, value),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          name == null
              ? 'Stays filled for the next part you tick. Tap a part in the '
                    'third column to edit one that already exists.'
              : 'Editing this part on its own. The next part you tick still '
                    'carries what was filled in before.',
          style: const TextStyle(
            fontSize: 13,
            color: SoftErpTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        DevelopedForForm(
          // Rebuilt from scratch when the subject changes, so the quotation
          // field cannot carry one part's figure over to the next.
          key: ValueKey<String>('developed-for-${selected?.id ?? 'draft'}'),
          value: value,
          enabled: !_busy,
          quotationLabel: 'Quotation for this part',
          quotationHelper: name == null
              ? 'Recorded on each part ticked, not split between them.'
              : 'What was quoted for $name.',
          onChanged: (next) => setState(() {
            if (selected == null) {
              _draftDevelopedFor = next;
            } else {
              _editedDevelopedFor = next;
            }
          }),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: scrollable ? SingleChildScrollView(child: body) : body,
    );
  }

  /// The code the sheets below build their own codes from: the selected
  /// part's, or the one filling in live while a new part's name is typed.
  String _sheetPartCode(ItemsProvider items) =>
      _selectedItem(items)?.partCode ?? _partCodeController.text.trim();

  String _sheetPartLabel(ItemsProvider items) {
    final selected = _selectedItem(items);
    if (selected != null) {
      return selected.displayName.trim().isEmpty
          ? selected.name
          : selected.displayName;
    }
    return _itemNameController.text.trim();
  }

  /// Says which machines the part on screen runs on.
  ///
  /// The twin of [_setDiesOnSelectedPart], and separate from it on purpose:
  /// `setItemLinks` replaces only the list it is given, so naming machines
  /// leaves the dies alone and the other way round.
  Future<String?> _setMachinesOnSelectedPart(List<String> machineIds) async {
    final items = context.read<ItemsProvider>();
    final part = _selectedItem(items);
    if (part == null) return 'no part is selected any more';
    final saved = await items.setItemLinks(part.id, machineIds: machineIds);
    if (saved == null) return items.errorMessage ?? _kConcurrentWrite;
    return null;
  }

  /// Says which dies the part on screen is made with.
  ///
  /// Returns null on success, or what went wrong. A die that was just made
  /// exists either way — the host wrote it before this is called — so the
  /// section is told rather than left to guess, and its retry attaches instead
  /// of creating a second one.
  ///
  /// The whole list is sent because this is a full-replace write: the section
  /// composes it, which is also how taking one die off a part works.
  Future<String?> _setDiesOnSelectedPart(List<String> dieIds) async {
    final items = context.read<ItemsProvider>();
    final part = _selectedItem(items);
    if (part == null) return 'no part is selected any more';
    final saved = await items.setItemLinks(part.id, dieIds: dieIds);
    if (saved == null) return items.errorMessage ?? _kConcurrentWrite;
    return null;
  }

  /// One PATCH, about one part, carrying everything else it already had.
  Future<void> _saveDevelopedFor(int itemId, DevelopedFor value) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    final saved = await context.read<ItemsProvider>().setItemDevelopedFor(
      itemId,
      value,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (saved == null) {
        // Keep the staged edit: clearing it on failure throws away the typing.
        _error = context.read<ItemsProvider>().errorMessage ?? _kConcurrentWrite;
        return;
      }
      // Spent — the part now carries it, and the panel re-seeds from the row.
      _editedDevelopedFor = null;
      _notice = 'Saved who that part was developed for.';
    });
  }


  // ---------------------------------------------------------------------------
  // The three dropdowns
  // ---------------------------------------------------------------------------
  //
  // Each one can CREATE from what was typed into its own search box, through
  // `inlinePanelBuilder` — a panel drawn inside the picker, above the list.
  // That is what keeps the pace of the old type-a-name-and-tick rows without
  // stacking a second dialog on the dialog you are already in.
  //
  // Two rules the panels have to obey:
  //
  //   * anything that can be decided FROM THE TYPED NAME renders in the panel,
  //     as a disabled Create with the reason. The panel rebuilds on every
  //     keystroke but NOT on this widget's setState, so nothing stateful may
  //     be read from inside it;
  //   * an async refusal is spoken through a toast, never the error banner —
  //     the banner is behind the picker's route and would not be seen until it
  //     closed.

  Widget _buildGroupField(GroupsProvider groups, UnitsProvider units) {
    return GroupPickerField(
      key: const ValueKey<String>('quick-entry-group-field'),
      value: _selectedGroupId,
      onChanged: (id) => _selectGroup(id),
      fieldEnabled: !_busy,
      dialogTitle: 'Group',
      searchHintText: 'Search or type a new group',
      decoration: const InputDecoration(
        labelText: 'Group',
        helperText: 'Where everything here is filed',
        border: OutlineInputBorder(),
      ),
      // Withheld rather than offered-and-refused: the panel below says why,
      // and an enabled Create that cannot work is worse than no Create.
      canCreateOption: (query, _) =>
          query.trim().isNotEmpty && _newGroupBlockedReason(groups, query) == null,
      createOptionLabelBuilder: (query) => 'Create group "$query"',
      onCreateOption: (query) async {
        final created = await _createGroup(query);
        if (created == null) {
          final reason = _error;
          if (reason != null && mounted) {
            showAppToast(context, reason, kind: AppToastKind.warning);
            setState(() => _error = null);
          }
          // Null leaves the picker open with the query intact, which is what
          // someone who has just been refused needs.
          return null;
        }
        return SearchableSelectOption<int?>(
          value: created.id,
          label: GroupPickerField.labelFor(created, 0),
        );
      },
      inlinePanelBuilder: (context, panel) => _GroupCreatePanel(
        query: panel.query,
        unitLabel: _unitLabelFor(units, groups, _groupRowUnitId),
        parentLabel: _newGroupParentLabel(groups),
        onToggleParent: _canNestNewGroup(groups)
            ? () => setState(() => _nestUnderSelection = !_nestUnderSelection)
            : null,
        blockedReason: _newGroupBlockedReason(groups, panel.query),
      ),
    );
  }

  /// Why a group with this name cannot be created here, or null.
  ///
  /// A pure function of the typed name, which is what lets it render inside
  /// the picker. The parent is resolved the same way [_createGroup] resolves
  /// it, including the Primary Group rule, or the two would disagree.
  String? _newGroupBlockedReason(GroupsProvider groups, String query) {
    final name = query.trim();
    if (name.isEmpty) return null;
    final selected = _selectedGroup(groups);
    final nests =
        _nestUnderSelection && selected != null && !selected.isCombination;
    final resolved = (nests ? selected.id : null) ?? _primaryGroupId(groups);
    return groups
            .checkDuplicate(name: name, parentGroupId: resolved)
            .blockingDuplicate
        ? 'A group called "$name" already exists there.'
        : null;
  }

  bool _canNestNewGroup(GroupsProvider groups) {
    final selected = _selectedGroup(groups);
    return selected != null && !selected.isCombination && !_busy;
  }

  String _newGroupParentLabel(GroupsProvider groups) {
    final selected = _selectedGroup(groups);
    if (selected == null || selected.isCombination) return 'top level';
    return _nestUnderSelection ? 'under ${selected.name}' : 'top level';
  }

  String _unitLabelFor(
    UnitsProvider units,
    GroupsProvider groups,
    int? sticky,
  ) {
    final id = _seedUnitId(units: units, groups: groups, sticky: sticky);
    final unit = units.activeUnits.where((u) => u.id == id).firstOrNull;
    return unit?.displayLabel ?? 'no active unit';
  }

  Widget _buildSetField(InventoryProvider inventory) {
    final sets = _setsInGroup(inventory);
    final pending = _visiblePendingSet;
    final ungrouped = _ungroupedSetCount(inventory);

    final options = <SearchableSelectOption<int>>[
      for (final set in sets)
        SearchableSelectOption<int>(
          value: set.id,
          label: set.name,
          searchText: '${set.name} ${set.lines.length} parts',
        ),
      if (pending != null)
        SearchableSelectOption<int>(
          value: kPendingSetId,
          label: '${pending.name} · new',
          searchText: pending.name,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchableSelectField<int>(
          key: const ValueKey<String>('quick-entry-set-field'),
          options: options,
          value: _selectedSetId,
          fieldEnabled: !_busy && _selectedGroupId != null,
          dialogTitle: 'Set',
          searchHintText: 'Search or type a new set',
          emptyText: 'No sets in this group yet',
          decoration: InputDecoration(
            labelText: 'Set',
            helperText: _selectedGroupId == null
                ? 'Pick a group first'
                : (ungrouped == 0
                      ? 'Optional — a part can sit in the group alone'
                      : '$ungrouped ungrouped set'
                            '${ungrouped == 1 ? '' : 's'} — file them from the '
                            'Sets tab'),
            border: const OutlineInputBorder(),
          ),
          onChanged: (id) => _selectSet(id),
          canCreateOption: (query, _) =>
              query.trim().isNotEmpty &&
              _newSetBlockedReason(inventory, query) == null,
          createOptionLabelBuilder: (query) => 'Name a new set "$query"',
          onCreateOption: (query) async {
            if (_newSetBlockedReason(inventory, query) != null) return null;
            _namePendingSet(query);
            final named = _visiblePendingSet;
            if (named == null) return null;
            return SearchableSelectOption<int>(
              value: kPendingSetId,
              label: '${named.name} · new',
            );
          },
          inlinePanelBuilder: (context, panel) => _SetCreatePanel(
            query: panel.query,
            blockedReason: _newSetBlockedReason(inventory, panel.query),
          ),
        ),
        if (pending != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _PendingSetChip(
              name: pending.name,
              onDiscard: _busy ? null : _discardPendingSet,
            ),
          ),
      ],
    );
  }

  /// Why a set with this name cannot be named here, or null. Pure function of
  /// the query, like the group's.
  String? _newSetBlockedReason(InventoryProvider inventory, String query) {
    final name = query.trim();
    if (name.isEmpty) return null;
    if (_selectedGroupId == null) return 'Pick a group first.';
    final clashes =
        _setsInGroup(inventory).any(
          (set) => set.name.toLowerCase() == name.toLowerCase(),
        ) ||
        (_visiblePendingSet?.name.toLowerCase() == name.toLowerCase());
    return clashes ? 'A set called "$name" is already filed here.' : null;
  }

  void _discardPendingSet() {
    final name = _pendingSet?.name;
    setState(() {
      _pendingSet = null;
      if (_selectedSetId == kPendingSetId) _selectedSetId = null;
    });
    _refreshPartIdentity();
    if (name != null) {
      showAppToast(
        context,
        '"$name" was never created — it had no parts.',
        kind: AppToastKind.warning,
      );
    }
  }

  Widget _buildPartField(ItemsProvider items, InventoryProvider inventory) {
    final inGroup = _itemsInGroup(items);
    final set = _selectedSet(inventory);
    final memberIds = set == null
        ? const <int>{}
        : set.lines.map((line) => line.itemId).toSet();

    String subtitleFor(ItemDefinition item) {
      // A dropdown has no section headings, so what the two headings used to
      // say ("in this set" / "in the group, not in this set") each row says
      // for itself.
      final where = set == null
          ? null
          : (memberIds.contains(item.id)
                ? 'in ${set.name}'
                : (canFileAtLeafZero(item)
                      ? 'not in ${set.name}'
                      : 'has variations — add it from the set editor'));
      return _identityLine(item, trailing: where) ?? (where ?? '');
    }

    return SearchableSelectField<int?>(
      key: const ValueKey<String>('quick-entry-part-field'),
      options: <SearchableSelectOption<int?>>[
        // The way back. Without it, picking a part is a one-way door: the
        // section below switches to what is stored and there is nowhere left
        // to type the next part's name.
        const SearchableSelectOption<int?>(
          value: null,
          label: 'New part…',
          searchText: 'new part create',
        ),
        ...inGroup
          .map(
            (item) => SearchableSelectOption<int?>(
              value: item.id,
              label: item.displayName.trim().isEmpty
                  ? item.name
                  : item.displayName,
              subtitle: subtitleFor(item),
              searchText:
                  '${item.name} ${item.displayName} ${item.partCode} '
                  '${subtitleFor(item)}',
            ),
          ),
      ],
      value: _selectedItemId,
      fieldEnabled: !_busy && _selectedGroupId != null,
      dialogTitle: 'Part',
      searchHintText: 'Search or type a new part',
      emptyText: 'Nothing in this group yet',
      decoration: InputDecoration(
        labelText: 'Part',
        helperText: _selectedGroupId == null
            ? 'Pick a group first'
            : 'Pick one to fill in its details, or type a new name',
        border: const OutlineInputBorder(),
      ),
      onChanged: (id) {
        if (id == null) {
          setState(_clearItemSelection);
        } else {
          _selectItemById(id);
        }
      },
      createOptionLabelBuilder: (query) => 'Start a new part "$query"',
      // Staging, not writing: the part is created from the section below, so
      // its number and code can be watched filling in and checked before
      // anything is stamped.
      onCreateOption: (query) async {
        _stagePartName(query);
        return null;
      },
      inlinePanelBuilder: (context, panel) => _PartStagePanel(
        query: panel.query,
        onStage: panel.query.trim().isEmpty
            ? null
            : () {
                _stagePartName(panel.query);
                // Closing the picker is the point: the fields it stages into
                // are behind it.
                panel.setQuery('');
                Navigator.of(context).pop();
              },
      ),
    );
  }

  /// Puts a name into the Part identity section without writing anything.
  void _stagePartName(String query) {
    final name = query.trim();
    if (name.isEmpty) return;
    setState(() {
      _clearItemSelection();
      _itemNameController.text = name;
    });
    _onItemNameChanged(
      groups: context.read<GroupsProvider>(),
      inventory: context.read<InventoryProvider>(),
    );
    _refreshPartIdentity();
  }

  void _selectItemById(int itemId) {
    if (_selectedItemId == itemId) return;
    setState(() {
      _selectedItemId = itemId;
      _editedDevelopedFor = null;
      _error = null;
      _notice = null;
    });
  }

  // ---------------------------------------------------------------------------
  // The part section
  // ---------------------------------------------------------------------------

  /// One section with two faces, saying which in its heading — the same
  /// discipline the Developed For panel uses. Creating keeps the fields
  /// editable; a selected part reads back what is stored and offers the one
  /// action that is still about placement.
  Widget _buildPartSection(
    GroupsProvider groups,
    ItemsProvider items,
    InventoryProvider inventory,
    UnitsProvider units,
  ) {
    final selected = _selectedItem(items);
    final name = selected == null
        ? null
        : (selected.displayName.trim().isEmpty
              ? selected.name
              : selected.displayName);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading(
            label: name == null ? 'New part' : 'Part · $name',
          ),
          const SizedBox(height: 10),
          if (selected == null)
            ..._newPartFields(groups, inventory, units)
          else
            ..._selectedPartFacts(selected, inventory),
        ],
      ),
    );
  }

  List<Widget> _newPartFields(
    GroupsProvider groups,
    InventoryProvider inventory,
    UnitsProvider units,
  ) {
    final unitOptions = _unitOptions(units);
    final canCreate =
        !_busy &&
        _selectedGroupId != null &&
        _itemNameController.text.trim().isNotEmpty;
    return <Widget>[
      TextField(
        key: const ValueKey<String>('quick-entry-part-name-field'),
        controller: _itemNameController,
        focusNode: _itemNameFocus,
        enabled: !_busy && _selectedGroupId != null,
        onChanged: (_) =>
            _onItemNameChanged(groups: groups, inventory: inventory),
        onSubmitted: (_) {
          if (canCreate) _createItem();
        },
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        decoration: const InputDecoration(
          labelText: 'Part name',
          hintText: 'What this part is called',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 10),
      _PartIdentityFields(
        partNoController: _partNoController,
        partCodeController: _partCodeController,
        partNoFocus: _partNoFocus,
        partCodeFocus: _partCodeFocus,
        enabled: !_busy && _selectedGroupId != null,
        partCodeHint: _partCodeHint,
        onPartNoChanged: (value) {
          setState(() {
            _partNoPinned = true;
            if (!_partCodePinned) {
              _partCodeController.text = _derivedPartCode(
                groups: groups,
                inventory: inventory,
              );
            }
          });
        },
        onPartCodeChanged: (_) => setState(() => _partCodePinned = true),
        onSubmit: _createItem,
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: SearchableSelectField<int>(
              key: const ValueKey<String>('quick-entry-part-unit-field'),
              options: unitOptions,
              value: _seedUnitId(
                units: units,
                groups: groups,
                sticky: _itemRowUnitId,
              ),
              fieldEnabled: !_busy && unitOptions.isNotEmpty,
              dialogTitle: 'Unit',
              decoration: InputDecoration(
                labelText: 'Unit',
                hintText: unitOptions.isEmpty ? 'No active unit' : null,
                // Here rather than inside a picker overlay: a unit chosen in
                // something that then closes is a setting nobody can see they
                // made, and this one is stamped on every part created.
                helperText: 'Stays chosen for the next part',
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _itemRowUnitId = value),
            ),
          ),
          const SizedBox(width: 12),
          AppButton(
            key: const ValueKey<String>('quick-entry-create-part'),
            label: 'Create part',
            icon: Icons.check_rounded,
            // Secondary, like every other write on this screen: see the
            // footer's comment about SubmitFormShortcuts.
            variant: AppButtonVariant.secondary,
            onPressed: canCreate ? _createItem : null,
          ),
        ],
      ),
    ];
  }

  List<Widget> _selectedPartFacts(
    ItemDefinition part,
    InventoryProvider inventory,
  ) {
    final set = _selectedSet(inventory);
    final alreadyIn =
        set != null && set.lines.any((line) => line.itemId == part.id);
    final canFile = set != null && !alreadyIn && canFileAtLeafZero(part);

    return <Widget>[
      _PartFactRow(label: 'Part No.', value: part.partNo?.toString() ?? '—'),
      _PartFactRow(
        label: 'Part Code',
        value: part.partCode.trim().isEmpty ? '—' : part.partCode,
      ),
      _PartFactRow(label: 'Stamped', value: partStamp(part.createdAt)),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: Text(
              set == null
                  ? 'No set is in play, so this part sits in the group alone.'
                  : (alreadyIn
                        ? 'Already a line of ${set.name}.'
                        : 'Not in ${set.name} yet.'),
              style: _scopeLineStyle,
            ),
          ),
          if (set != null && !alreadyIn)
            Tooltip(
              // Drawn disabled with the reason rather than hidden: the server
              // refuses a leaf-zero line for a part with variations, and the
              // row is the only place that can say so.
              message: canFileAtLeafZero(part)
                  ? 'Add this part to ${set.name}'
                  : 'This part has variations, so a set line has to name one. '
                        'Add it from the set editor.',
              child: AppButton(
                key: const ValueKey<String>('quick-entry-file-into-set'),
                label: 'File into ${set.name}',
                icon: Icons.add_rounded,
                variant: AppButtonVariant.secondary,
                onPressed: _busy || !canFile
                    ? null
                    : () => _appendExistingItem(part),
              ),
            ),
        ],
      ),
    ];
  }
}

/// A labelled divider inside a column's list.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
        color: SoftErpTheme.textSecondary,
      ),
    ),
  );
}

/// The part's number and code, and the note that the date and time are the
/// server's to stamp.
class _PartIdentityFields extends StatelessWidget {
  const _PartIdentityFields({
    required this.partNoController,
    required this.partCodeController,
    required this.partNoFocus,
    required this.partCodeFocus,
    required this.enabled,
    required this.partCodeHint,
    required this.onPartNoChanged,
    required this.onPartCodeChanged,
    required this.onSubmit,
  });

  final TextEditingController partNoController;
  final TextEditingController partCodeController;
  final FocusNode partNoFocus;
  final FocusNode partCodeFocus;
  final bool enabled;

  /// What the code would be once the part has a name. Shown behind an empty
  /// field so the user can see where it is going without it being a value they
  /// could tick, or pin by touching.
  final String partCodeHint;
  final ValueChanged<String> onPartNoChanged;
  final ValueChanged<String> onPartCodeChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 92,
              child: _field(
                key: const ValueKey<String>('quick-entry-item-part-no-field'),
                controller: partNoController,
                focusNode: partNoFocus,
                label: 'Part No',
                keyboardType: TextInputType.number,
                onChanged: onPartNoChanged,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _field(
                key: const ValueKey<String>('quick-entry-item-part-code-field'),
                controller: partCodeController,
                focusNode: partCodeFocus,
                label: 'Part Code',
                hintText: partCodeHint,
                onChanged: onPartCodeChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(
              Icons.schedule_outlined,
              size: 14,
              color: SoftErpTheme.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              // No clock here on purpose: this machine's time is not the one
              // that gets written. The stamp shows on the row once the server
              // has made it.
              'Date and time stamped on save',
              style: TextStyle(
                fontSize: 13,
                color: SoftErpTheme.textSecondary.withValues(alpha: 0.95),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required ValueChanged<String> onChanged,
    TextInputType? keyboardType,
    String hintText = '',
  }) {
    return TextField(
      key: key,
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      keyboardType: keyboardType,
      onChanged: onChanged,
      onSubmitted: (_) => onSubmit(),
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        hintText: hintText.isEmpty ? null : hintText,
        isDense: true,
        filled: true,
        fillColor: SoftErpTheme.cardSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
          borderSide: const BorderSide(color: SoftErpTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
          borderSide: const BorderSide(color: SoftErpTheme.border),
        ),
      ),
    );
  }
}

/// Where a new group will land — a toggle, so "actually, top level" is one tap.
class _DestinationChip extends StatelessWidget {
  const _DestinationChip({
    required this.label,
    required this.tooltip,
    this.onTap,
  });

  final String label;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: SoftErpTheme.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.subdirectory_arrow_right_rounded,
                  size: 15,
                  color: SoftErpTheme.textSecondary,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: SoftErpTheme.textSecondary,
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

/// One thing made in this sitting.
///
/// [setId] and [setName] are not final: a part created into a set that had
/// only been NAMED gets its real id the moment that set exists, or tapping
/// this row later would restore a scope that never existed and number the next
/// part in the wrong one.
class _MadeRow {
  _MadeRow({
    required this.itemId,
    required this.groupId,
    required this.groupName,
    required this.setId,
    required this.setName,
    required this.partLabel,
    required this.partCode,
  });

  final int itemId;
  final int groupId;
  final String groupName;
  int? setId;
  String setName;
  final String partLabel;
  final String partCode;

  /// `Ash Trays › Bathroom Kit › Lid`, with the set left out when there is none.
  String get trail => <String>[
    if (groupName.isNotEmpty) groupName,
    if (setName.isNotEmpty) setName,
    partLabel,
  ].join(' › ');
}

class _MadeRowTile extends StatelessWidget {
  const _MadeRowTile({
    super.key,
    required this.row,
    required this.selected,
    this.onTap,
  });

  final _MadeRow row;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? SoftErpTheme.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
              border: Border.all(
                color: selected ? SoftErpTheme.accent : SoftErpTheme.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.trail,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
                if (row.partCode.trim().isNotEmpty)
                  Text(
                    row.partCode,
                    style: const TextStyle(
                      fontSize: 13,
                      color: SoftErpTheme.textSecondary,
                      fontWeight: FontWeight.w600,
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

/// What the Group picker shows above its list while something is typed: where
/// the new group would land, what unit it would take, and why it cannot be
/// made if it cannot.
class _GroupCreatePanel extends StatelessWidget {
  const _GroupCreatePanel({
    required this.query,
    required this.unitLabel,
    required this.parentLabel,
    required this.blockedReason,
    this.onToggleParent,
  });

  final String query;
  final String unitLabel;
  final String parentLabel;
  final String? blockedReason;
  final VoidCallback? onToggleParent;

  @override
  Widget build(BuildContext context) {
    if (query.trim().isEmpty) return const SizedBox.shrink();
    return _CreatePanelFrame(
      blockedReason: blockedReason,
      children: [
        _DestinationChip(
          label: parentLabel,
          tooltip: onToggleParent == null
              ? 'This group starts a branch of its own.'
              : 'Tap to switch between nesting and starting at the top.',
          onTap: onToggleParent,
        ),
        _CreatePanelFact(label: 'Unit', value: unitLabel),
      ],
    );
  }
}

/// The Set picker's panel. A named set writes nothing, and says so.
class _SetCreatePanel extends StatelessWidget {
  const _SetCreatePanel({required this.query, required this.blockedReason});

  final String query;
  final String? blockedReason;

  @override
  Widget build(BuildContext context) {
    if (query.trim().isEmpty) return const SizedBox.shrink();
    return _CreatePanelFrame(
      blockedReason: blockedReason,
      children: const [
        _CreatePanelFact(
          label: 'Note',
          value: 'Nothing is written until the first part goes into it',
        ),
      ],
    );
  }
}

/// The Part picker's panel. Staging, not writing — the fields below are where
/// a part is actually made.
class _PartStagePanel extends StatelessWidget {
  const _PartStagePanel({required this.query, this.onStage});

  final String query;
  final VoidCallback? onStage;

  @override
  Widget build(BuildContext context) {
    if (query.trim().isEmpty) return const SizedBox.shrink();
    return _CreatePanelFrame(
      blockedReason: null,
      children: [
        const _CreatePanelFact(
          label: 'Next',
          value: 'Its number and code fill in below before anything is stamped',
        ),
        AppButton(
          label: 'Start "${query.trim()}"',
          icon: Icons.east_rounded,
          variant: AppButtonVariant.secondary,
          onPressed: onStage,
        ),
      ],
    );
  }
}

class _CreatePanelFrame extends StatelessWidget {
  const _CreatePanelFrame({required this.children, this.blockedReason});

  final List<Widget> children;
  final String? blockedReason;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (blockedReason != null)
            Text(
              blockedReason!,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB45309),
              ),
            )
          else
            Wrap(spacing: 10, runSpacing: 8, children: children),
        ],
      ),
    );
  }
}

class _CreatePanelFact extends StatelessWidget {
  const _CreatePanelFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: $value',
      style: const TextStyle(
        fontSize: 13,
        color: SoftErpTheme.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// A set that has been named and not created, sitting under the Set field.
class _PendingSetChip extends StatelessWidget {
  const _PendingSetChip({required this.name, this.onDiscard});

  final String name;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '"$name" is not created yet — add a part to create it.',
            style: const TextStyle(
              fontSize: 13,
              color: SoftErpTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          key: const ValueKey<String>('quick-entry-discard-pending-set'),
          tooltip: 'Discard "$name"',
          icon: const Icon(Icons.close_rounded, size: 18),
          visualDensity: VisualDensity.compact,
          color: SoftErpTheme.textSecondary,
          onPressed: onDiscard,
        ),
      ],
    );
  }
}

/// One stored fact about the selected part.
class _PartFactRow extends StatelessWidget {
  const _PartFactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 15,
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
