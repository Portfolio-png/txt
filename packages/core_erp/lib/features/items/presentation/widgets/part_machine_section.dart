import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/app_flow_hooks.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/force_capacity_field.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../../core/widgets/fit_to_text.dart';
import '../../../groups/domain/group_inputs.dart';
import '../../../groups/presentation/group_picker_field.dart';
import '../../../groups/presentation/providers/groups_provider.dart';
import '../../../machines/domain/machine_no.dart';
import '../../domain/item_definition.dart';

/// The "Machine in Plant" sheet, beside the part that runs on it.
///
/// | Machine Type | Machine Make | D O M | Feeder | Running Hrs | Stroke/Min |
/// | Capacity | Machine No | Die Type |
///
/// **A part runs on as many machines as it needs** — a press and a punching
/// machine, or two presses of different tonnage. They are listed above the
/// sheet, and tapping one loads it in to be corrected, exactly as the Die
/// section works. The sheet is one form with two jobs and its heading says
/// which.
///
/// A machine entered here is a **row in the machines master**: it shows up on
/// the Machines screen, can be found by its number, and can be linked to
/// another part later. Taking it off a part **unlinks** it — a press is a
/// press, and not running this part is not being scrapped.
///
/// The write goes through [AppFlowHooks.createMachineFromSheet] because
/// `Machine` lives in the app, not in this package. Linking is this package's
/// job, since `ItemsProvider` is here, and the two steps stay separate so a
/// link that fails cannot lose a machine that was already made.
class PartMachineSection extends StatefulWidget {
  const PartMachineSection({
    super.key,
    required this.part,
    required this.partCode,
    required this.partLabel,
    required this.busy,
    required this.staged,
    required this.onStage,
    required this.onUnstage,
    required this.onMachinesChanged,
  });

  /// The part the sheet is about, or null while it is still being typed.
  ///
  /// Null no longer means "wait": it means everything Add does is HELD until
  /// the part is made.
  final ItemDefinition? part;

  /// The code the part has, or the one being suggested as its name is typed.
  /// Only used for the heading here — a machine's number comes from its type.
  final String partCode;
  final String partLabel;

  final bool busy;

  /// Machines held for a part that does not exist yet, newest last.
  final List<MachineSheetDraft> staged;

  /// Holds one. The wizard owns the list, because the create path flushes it
  /// and the close path warns about it.
  final ValueChanged<MachineSheetDraft> onStage;
  final ValueChanged<int> onUnstage;

  /// Replaces the machines on the part. Returns null on success, or what went
  /// wrong — a machine that was just made exists either way.
  final Future<String?> Function(List<String> machineIds) onMachinesChanged;

  @override
  State<PartMachineSection> createState() => _PartMachineSectionState();
}

class _PartMachineSectionState extends State<PartMachineSection> {
  final TextEditingController _noController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _makeController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _feederController = TextEditingController();
  final TextEditingController _hoursController = TextEditingController();
  final TextEditingController _strokesController = TextEditingController();
  final TextEditingController _capacityController = TextEditingController();
  final TextEditingController _feedTypeController = TextEditingController();

  int? _groupId;
  String _capacityUnit = 'Ton';
  CapacityKind _capacityKind = CapacityKind.unknown;

  /// The machine being corrected, or null when the sheet is for a new one.
  String? _editingMachineId;

  /// The HELD machine being corrected, by position, or null.
  int? _editingStagedIndex;

  /// Set once the number is typed over, after which it stops re-deriving — the
  /// same pin the part code and the die code have.
  bool _noPinned = false;

  MachineSheetSuggestions _suggestions = const MachineSheetSuggestions();

  bool _saving = false;
  String? _error;
  String? _notice;
  String? _capacityError;

  /// A machine that was created and could not be linked. Kept so a retry links
  /// it instead of making a second one.
  String? _unlinkedMachineId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSuggestions());
  }

  @override
  void didUpdateWidget(PartMachineSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.part?.id != widget.part?.id) {
      _resetSheet();
      return;
    }
    if (oldWidget.staged.length != widget.staged.length) _rederiveNo();
    // The machines on the part changed under us. The suggested number counts
    // them, so it has to be recomputed: the second press cannot be offered the
    // first one's number.
    final before = oldWidget.part?.machines.map((m) => m.id).join(',');
    final now = widget.part?.machines.map((m) => m.id).join(',');
    if (before != now && _editingMachineId == null) _rederiveNo();
  }

  @override
  void dispose() {
    _noController.dispose();
    _nameController.dispose();
    _makeController.dispose();
    _yearController.dispose();
    _feederController.dispose();
    _hoursController.dispose();
    _strokesController.dispose();
    _capacityController.dispose();
    _feedTypeController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    final hook = AppFlowHooks.machineSheetSuggestions;
    if (hook == null || !mounted) return;
    final suggestions = await hook(context);
    if (!mounted) return;
    setState(() => _suggestions = suggestions);
  }

  List<ItemMachineLink> get _machines =>
      widget.part?.machines ?? const <ItemMachineLink>[];

  /// Back to a blank sheet for the next machine.
  ///
  /// What repeats down a column of the physical sheet sticks — the type, the
  /// make, the feeder, the tooling. What is read off the machine in front of
  /// you does not.
  void _resetSheet() {
    _editingMachineId = null;
    _editingStagedIndex = null;
    _unlinkedMachineId = null;
    _error = null;
    _notice = null;
    _capacityError = null;
    _noPinned = false;
    _nameController.clear();
    _yearController.clear();
    _hoursController.clear();
    _strokesController.clear();
    _capacityController.clear();
    _capacityKind = CapacityKind.unknown;
    _rederiveNo();
  }

  /// Loads a HELD machine back into the sheet. Add then replaces it rather
  /// than holding a second one.
  void _editStaged(int index) {
    final draft = widget.staged[index];
    setState(() {
      _editingMachineId = null;
      _editingStagedIndex = index;
      _unlinkedMachineId = null;
      _error = null;
      _notice = null;
      _capacityError = null;
      _noPinned = true;
      _noController.text = draft.assetId;
      _nameController.text = draft.name;
      _groupId = draft.groupId;
      _makeController.text = draft.machineMake;
      _yearController.text = draft.manufacturedYear?.toString() ?? '';
      _feederController.text = draft.feederMake;
      _hoursController.text = draft.runningHours?.toString() ?? '';
      _strokesController.text = draft.strokesPerMinute?.toString() ?? '';
      _capacityKind = CapacityKind.fromWire(draft.capacityKind);
      _capacityController.text = formatCapacityFromKgf(
        draft.capacityKgf,
        _capacityUnit,
      );
      _feedTypeController.text = draft.dieFeedType;
    });
  }

  void _editMachine(ItemMachineLink machine) {
    setState(() {
      _editingStagedIndex = null;
      _editingMachineId = machine.id;
      _unlinkedMachineId = null;
      _error = null;
      _notice = null;
      _capacityError = null;
      // Pinned, because it is a number that exists: re-deriving it from the
      // type would quietly renumber a machine that is painted on the frame.
      _noPinned = true;
      _noController.text = machine.assetId;
      _nameController.text = machine.name;
      _groupId = machine.groupId;
      _makeController.text = machine.machineMake;
      _yearController.text = machine.manufacturedYear?.toString() ?? '';
      _feederController.text = machine.feederMake;
      _hoursController.text = machine.runningHours?.toString() ?? '';
      _strokesController.text = machine.strokesPerMinute?.toString() ?? '';
      _capacityKind = CapacityKind.fromWire(machine.capacityKind);
      _capacityController.text = formatCapacityFromKgf(
        machine.capacityKgf,
        _capacityUnit,
      );
      _feedTypeController.text = machine.dieFeedType;
    });
  }

  /// The number a NEW machine of this type would take.
  ///
  /// Counts what the part already holds so a second press is not offered the
  /// first one's number before anything is sent. The server still has the last
  /// word — it is the only thing that can see every machine in the plant.
  String _suggestedNo() {
    final groups = context.read<GroupsProvider>();
    final group = _groupId == null ? null : groups.findById(_groupId);
    if (group == null) return '';
    // Held machines count too, or two presses waiting on the same part would
    // both be offered PP-1.
    final sameType =
        _machines.where((m) => m.groupId == _groupId).length +
        widget.staged.where((m) => m.groupId == _groupId).length;
    final base = buildMachineNo(
      typeName: group.name,
      nextNumber: sameType + (_editingStagedIndex == null ? 1 : 0),
    );
    if (base.isEmpty) return '';
    return nextFreeMachineNo(base, <String>[
      for (final machine in _machines)
        if (machine.id != _editingMachineId) machine.assetId,
      for (var i = 0; i < widget.staged.length; i += 1)
        if (i != _editingStagedIndex) widget.staged[i].assetId,
    ]);
  }

  void _rederiveNo() {
    if (_noPinned) return;
    _noController.text = _suggestedNo();
  }

  /// What the sheet currently describes, or null with [_error] set.
  MachineSheetDraft? _draftFromSheet({String? machineId}) {
    final capacity = parseCapacityToKgf(
      _capacityController.text,
      _capacityUnit,
    );
    if (capacity.isFailure) {
      setState(() => _capacityError = capacity.error);
      return null;
    }
    final assetId = _noController.text.trim().toUpperCase();
    if (_groupId == null || assetId.isEmpty) {
      setState(() => _error = 'Pick a type — the number is built from it.');
      return null;
    }
    // Free hand wins over a figure left in the box: the two would be two
    // answers to one question.
    final kind = _capacityKind == CapacityKind.freeHand
        ? CapacityKind.freeHand
        : (capacity.kgf == null ? CapacityKind.unknown : CapacityKind.rated);
    return MachineSheetDraft(
      machineId: machineId,
      assetId: assetId,
      name: _nameController.text.trim().isEmpty
          ? assetId
          : _nameController.text.trim(),
      groupId: _groupId,
      machineMake: _makeController.text.trim(),
      manufacturedYear: int.tryParse(_yearController.text.trim()),
      feederMake: _feederController.text.trim(),
      runningHours: int.tryParse(_hoursController.text.trim()),
      strokesPerMinute: int.tryParse(_strokesController.text.trim()),
      capacityKind: kind.wire,
      capacityKgf: kind == CapacityKind.rated ? capacity.kgf : null,
      dieFeedType: _feedTypeController.text.trim(),
    );
  }

  /// Holds the sheet for a part that does not exist yet.
  void _stageMachine() {
    final draft = _draftFromSheet();
    if (draft == null) return;
    final replacing = _editingStagedIndex;
    setState(() {
      _error = null;
      if (replacing != null) widget.onUnstage(replacing);
      widget.onStage(draft);
      _resetSheet();
      _notice = 'Machine ${draft.assetId} is held until the part is made.';
    });
  }

  Future<void> _saveMachine() async {
    final part = widget.part;
    final hook = AppFlowHooks.createMachineFromSheet;
    if (hook == null || _saving) return;
    // No part yet: hold it. Writing one would mean creating the part behind
    // the user's back.
    if (part == null) {
      _stageMachine();
      return;
    }

    final capacity = parseCapacityToKgf(
      _capacityController.text,
      _capacityUnit,
    );
    if (capacity.isFailure) {
      setState(() => _capacityError = capacity.error);
      return;
    }
    final assetId = _noController.text.trim().toUpperCase();
    if (_groupId == null || assetId.isEmpty) {
      setState(() => _error = 'Pick a type — the number is built from it.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
      _capacityError = null;
    });

    // A machine that exists and is not linked yet is retried as a LINK, never
    // as a second create.
    var machineId = _unlinkedMachineId;
    final editing = _editingMachineId;
    if (machineId == null) {
      // Free hand wins over a figure left in the box: the two would be two
      // answers to one question.
      final kind = _capacityKind == CapacityKind.freeHand
          ? CapacityKind.freeHand
          : (capacity.kgf == null ? CapacityKind.unknown : CapacityKind.rated);
      final outcome = await hook(
        context,
        MachineSheetDraft(
          machineId: editing,
          assetId: assetId,
          name: _nameController.text.trim().isEmpty
              ? assetId
              : _nameController.text.trim(),
          groupId: _groupId,
          machineMake: _makeController.text.trim(),
          manufacturedYear: int.tryParse(_yearController.text.trim()),
          feederMake: _feederController.text.trim(),
          runningHours: int.tryParse(_hoursController.text.trim()),
          strokesPerMinute: int.tryParse(_strokesController.text.trim()),
          capacityKind: kind.wire,
          capacityKgf: kind == CapacityKind.rated ? capacity.kgf : null,
          dieFeedType: _feedTypeController.text.trim(),
        ),
      );
      if (!mounted) return;
      if (!outcome.isCreated) {
        setState(() {
          _saving = false;
          _error = outcome.message ?? 'The machine could not be saved.';
          // Offer the free number rather than retrying the write, which is how
          // two machines get made when only the response was lost.
          final suggested = outcome.suggestedAssetId;
          if (suggested != null && suggested.isNotEmpty) {
            _noController.text = suggested;
            _noPinned = true;
          }
        });
        return;
      }
      machineId = outcome.record!.id;
    }

    if (editing == null) {
      final linkError = await widget.onMachinesChanged(<String>[
        ..._machines.map((m) => m.id),
        if (!_machines.any((m) => m.id == machineId)) machineId,
      ]);
      if (!mounted) return;
      if (linkError != null) {
        setState(() {
          _saving = false;
          _unlinkedMachineId = machineId;
          _error =
              'Machine $assetId was made, but it could not be attached to '
              'this part — $linkError. Try again and it will only attach it.';
        });
        return;
      }
    }

    setState(() {
      _saving = false;
      final wasEditing = editing != null;
      // Written, so no longer held — or it would draw as pending and be made
      // again for the next part created.
      final wasHeld = _editingStagedIndex;
      if (wasHeld != null) widget.onUnstage(wasHeld);
      _resetSheet();
      _notice = wasEditing
          ? 'Machine $assetId is saved.'
          : 'Machine $assetId is on this part.';
    });
    await _loadSuggestions();
  }

  Future<void> _unlink(ItemMachineLink machine) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    final error = await widget.onMachinesChanged(
      _machines.where((m) => m.id != machine.id).map((m) => m.id).toList(),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (error != null) {
        _error = 'That machine is still on this part — $error.';
        return;
      }
      if (_editingMachineId == machine.id) _resetSheet();
      _notice =
          '${machine.assetId} is off this part. It is still in the machines '
          'master.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final part = widget.part;
    // Open with no part: everything Add does is held until the part is made.
    final enabled = !widget.busy && !_saving;
    final editing = _editingMachineId;
    final holding = part == null;

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
          Text(
            _heading(editing),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: SoftErpTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          if (AppFlowHooks.createMachineFromSheet == null)
            const Text(
              'Machines cannot be added from here in this build.',
              style: TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
            )
          else ...[
            if (holding) ...[
              const Text(
                'Fill this in now — each machine is held until you create the '
                'part, then written with it.',
                style: TextStyle(
                  fontSize: 14,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
            ],
            _machineList(enabled),
            const SizedBox(height: 12),
            // Each field as wide as what it holds, side by side, wrapping only
            // when the row is full — a stack of page-wide bars for answers
            // like "2011" and "60" was most of this card's height.
            Wrap(
              spacing: 10,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: [
                FitToText(
                  texts: ['Machine Type', _typeNameFor(_groupId)],
                  helper: 'Power Press, Punching M… type a new one to add it',
                  minWidth: 220,
                  chrome: 72,
                  child: GroupPickerField(
                    key: const ValueKey<String>('quick-entry-machine-type-field'),
                    value: _groupId,
                    groupType: 'machine',
                    scope: GroupPickerScope.all,
                    fieldEnabled: enabled,
                    dialogTitle: 'Machine Type',
                    searchHintText: 'Search or type a new machine type',
                    decoration: const InputDecoration(
                      labelText: 'Machine Type',
                      // There are no machine groups on a fresh system, so this
                      // is not a convenience — it is the only way the list
                      // ever fills.
                      helperText:
                          'Power Press, Punching M… type a new one to add it',
                      helperMaxLines: 2,
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (id) => setState(() {
                      _groupId = id;
                      _rederiveNo();
                    }),
                    canCreateOption: (query, _) => query.trim().isNotEmpty,
                    createOptionLabelBuilder: (query) => 'Add type "$query"',
                    onCreateOption: (query) async {
                      final groups = context.read<GroupsProvider>();
                      final created = await groups.createGroup(
                        CreateGroupInput(
                          name: query.trim(),
                          groupType: 'machine',
                          groupStructure: 'hierarchical',
                        ),
                      );
                      if (created == null) return null;
                      return SearchableSelectOption<int?>(
                        value: created.id,
                        label: created.name,
                      );
                    },
                  ),
                ),
                FitToText(
                  controller: _noController,
                  texts: const ['Machine No.'],
                  helper: _noHelper(),
                  child: TextField(
                    key: const ValueKey<String>('quick-entry-machine-no-field'),
                    controller: _noController,
                    enabled: enabled,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setState(() => _noPinned = true),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Machine No.',
                      helperText: _noHelper(),
                      helperMaxLines: 2,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                FitToText(
                  controller: _nameController,
                  texts: const ['Name'],
                  helper: 'Optional — the number is used if blank',
                  child: TextField(
                    key: const ValueKey<String>('quick-entry-machine-name-field'),
                    controller: _nameController,
                    enabled: enabled,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      helperText: 'Optional — the number is used if blank',
                      helperMaxLines: 2,
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                FitToText(
                  controller: _makeController,
                  texts: const ['Machine Make'],
                  helper: 'Who built it',
                  child: _SuggestingField(
                    fieldKey: const ValueKey<String>('quick-entry-machine-make-field'),
                    controller: _makeController,
                    enabled: enabled,
                    label: 'Machine Make',
                    helper: 'Who built it',
                    suggestions: _suggestions.makes,
                    onChanged: () => setState(() {}),
                  ),
                ),
                FitToText(
                  controller: _yearController,
                  texts: const ['D.O.M.', '2011'],
                  helper: 'Year it was built',
                  minWidth: 120,
                  child: TextField(
                    key: const ValueKey<String>('quick-entry-machine-dom-field'),
                    controller: _yearController,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'D.O.M.',
                      hintText: '2011',
                      // A year, because that is what anyone knows about a
                      // machine this old.
                      helperText: 'Year it was built',
                      helperMaxLines: 2,
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                FitToText(
                  controller: _hoursController,
                  texts: const ['Running Hrs'],
                  helper: 'The meter now',
                  minWidth: 120,
                  child: TextField(
                    key: const ValueKey<String>('quick-entry-machine-hours-field'),
                    controller: _hoursController,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'Running Hrs',
                      helperText: 'The meter now',
                      helperMaxLines: 2,
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                FitToText(
                  controller: _strokesController,
                  texts: const ['Stroke / Min'],
                  minWidth: 120,
                  child: TextField(
                    key: const ValueKey<String>('quick-entry-machine-strokes-field'),
                    controller: _strokesController,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'Stroke / Min',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                // A figure, a unit and a "free hand" tick: one compact block.
                SizedBox(
                  width: 340,
                  child: ForceCapacityField(
                    fieldKey: const ValueKey<String>('quick-entry-machine-capacity-field'),
                    freeHandKey: const ValueKey<String>('quick-entry-machine-free-hand'),
                    controller: _capacityController,
                    unitSymbol: _capacityUnit,
                    kind: _capacityKind,
                    enabled: enabled,
                    errorText: _capacityError,
                    onUnitChanged: (symbol) => setState(() {
                      _capacityUnit = symbol;
                      _capacityError = null;
                    }),
                    onKindChanged: (kind) => setState(() {
                      _capacityKind = kind;
                      _capacityError = null;
                    }),
                    onChanged: () {
                      if (_capacityError != null) {
                        setState(() => _capacityError = null);
                      }
                    },
                  ),
                ),
                FitToText(
                  controller: _feederController,
                  texts: const ['Feeder make'],
                  helper: 'The feeder on this machine, if it has one',
                  child: _SuggestingField(
                    fieldKey: const ValueKey<String>('quick-entry-machine-feeder-field'),
                    controller: _feederController,
                    enabled: enabled,
                    label: 'Feeder make',
                    // Named "make" because everywhere else in this system a
                    // feeder is an upstream node in a pipeline, and the sheet
                    // uses the word for both.
                    helper: 'The feeder on this machine, if it has one',
                    suggestions: _suggestions.feederMakes,
                    onChanged: () => setState(() {}),
                  ),
                ),
                FitToText(
                  controller: _feedTypeController,
                  texts: const ['Die Type'],
                  helper: 'What tooling it takes — Manual, Semi Prog, Progressive',
                  child: _SuggestingField(
                    fieldKey: const ValueKey<String>('quick-entry-machine-feed-field'),
                    controller: _feedTypeController,
                    enabled: enabled,
                    label: 'Die Type',
                    helper: 'What tooling it takes — Manual, Semi Prog, Progressive',
                    suggestions: _suggestions.dieFeedTypes,
                    onChanged: () => setState(() {}),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB45309),
                ),
              ),
            ],
            if (_notice != null) ...[
              const SizedBox(height: 10),
              Text(
                _notice!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (editing != null || _editingStagedIndex != null)
                  TextButton(
                    key: const ValueKey<String>('quick-entry-machine-cancel'),
                    onPressed: enabled ? () => setState(_resetSheet) : null,
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                const SizedBox(width: 8),
                AppButton(
                  key: const ValueKey<String>('quick-entry-add-machine'),
                  label: _unlinkedMachineId != null
                      ? 'Attach the machine'
                      : (editing != null || _editingStagedIndex != null
                            ? 'Save machine'
                            : (holding ? 'Hold machine' : 'Add machine')),
                  icon: Icons.precision_manufacturing_outlined,
                  // Secondary, like every write on this screen: Cmd/Ctrl+Enter
                  // fires the last enabled PRIMARY button in the tree, and that
                  // must stay Done.
                  variant: AppButtonVariant.secondary,
                  isLoading: _saving,
                  onPressed: enabled ? _saveMachine : null,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _noHelper() {
    if (_editingMachineId != null) {
      return 'Renumbering this renumbers the machine itself';
    }
    if (_noPinned) return 'Typed over — it will not follow the type any more';
    if (_groupId == null) return 'Pick a type and it fills in';
    return 'The next in this type';
  }

  String _heading(String? editing) {
    final label = widget.partCode.isNotEmpty
        ? widget.partCode
        : (widget.partLabel.isNotEmpty ? widget.partLabel : 'this part');
    if (widget.part == null) return 'Machines · $label · held';
    if (editing == null) return 'Machines · $label · new';
    return 'Machines · $label · ${_noController.text}';
  }

  /// A held draft, shaped like a linked machine so one row widget draws both.
  ItemMachineLink _linkFromDraft(MachineSheetDraft draft) => ItemMachineLink(
    id: '',
    name: draft.name,
    assetId: draft.assetId,
    groupId: draft.groupId,
    machineType: _typeNameFor(draft.groupId),
    machineMake: draft.machineMake,
    manufacturedYear: draft.manufacturedYear,
    feederMake: draft.feederMake,
    runningHours: draft.runningHours,
    strokesPerMinute: draft.strokesPerMinute,
    capacityKind: draft.capacityKind,
    capacityKgf: draft.capacityKgf,
    dieFeedType: draft.dieFeedType,
  );

  String _typeNameFor(int? groupId) {
    if (groupId == null) return '';
    return context.read<GroupsProvider>().findById(groupId)?.name ?? '';
  }

  Widget _machineList(bool enabled) {
    if (_machines.isEmpty && widget.staged.isEmpty) {
      return const Text(
        'No machines on this part yet. Fill the sheet below and add one — a '
        'part can run on as many as it needs.',
        style: TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _MachineHeaderStrip(),
        const SizedBox(height: 4),
        // Held first: they are what this screen is about to write.
        for (var i = 0; i < widget.staged.length; i += 1)
          _MachineRow(
            key: ValueKey<String>('quick-entry-staged-machine-$i'),
            machine: _linkFromDraft(widget.staged[i]),
            selected: i == _editingStagedIndex,
            pending: true,
            partExists: widget.part != null,
            onTap: enabled ? () => _editStaged(i) : null,
            onUnlink: enabled ? () => widget.onUnstage(i) : null,
          ),
        for (final machine in _machines)
          _MachineRow(
            key: ValueKey<String>('quick-entry-machine-row-${machine.id}'),
            machine: machine,
            selected: machine.id == _editingMachineId,
            onTap: enabled ? () => _editMachine(machine) : null,
            onUnlink: enabled ? () => _unlink(machine) : null,
          ),
      ],
    );
  }
}

/// A text field with the answers already used offered beneath it.
///
/// Chips rather than an Autocomplete overlay: an overlay inside a dialog
/// inside a scroll view is a positioning fight this codebase has already lost
/// once.
class _SuggestingField extends StatelessWidget {
  const _SuggestingField({
    required this.controller,
    required this.label,
    required this.helper,
    required this.suggestions,
    required this.enabled,
    this.onChanged,
    this.fieldKey,
  });

  final TextEditingController controller;
  final String label;
  final String helper;
  final List<String> suggestions;
  final bool enabled;
  final VoidCallback? onChanged;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final typed = controller.text.trim().toLowerCase();
    final offered = suggestions
        .where((name) => typed.isEmpty || name.toLowerCase().contains(typed))
        .where((name) => name.toLowerCase() != typed)
        .take(5)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: fieldKey,
          controller: controller,
          enabled: enabled,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => onChanged?.call(),
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            helperText: helper,
            helperMaxLines: 2,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        if (offered.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final name in offered)
                ActionChip(
                  label: Text(name, style: const TextStyle(fontSize: 14)),
                  onPressed: !enabled
                      ? null
                      : () {
                          controller.text = name;
                          controller.selection = TextSelection.collapsed(
                            offset: name.length,
                          );
                          onChanged?.call();
                        },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One machine on the part: what tells it from the others, and the way off.
class _MachineRow extends StatelessWidget {
  const _MachineRow({
    super.key,
    required this.machine,
    required this.selected,
    this.pending = false,
    this.partExists = false,
    this.onTap,
    this.onUnlink,
  });

  final ItemMachineLink machine;
  final bool selected;

  /// Held and not written. Says so on the row, because a machine that looks
  /// saved and is not is the worst of both.
  final bool pending;

  /// Whether the part it is held for exists yet — the difference between
  /// "waiting on the part" and "the part was made, this one was refused".
  final bool partExists;
  final VoidCallback? onTap;
  final VoidCallback? onUnlink;

  @override
  Widget build(BuildContext context) {
    final capacity = capacityLabel(
      CapacityKind.fromWire(machine.capacityKind),
      machine.capacityKgf,
      'Ton',
    );
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
            child: Row(
              children: [
                // Aligned under the strip above, rather than one joined
                // sentence that stops being readable past a machine or two.
                _MachineCell(
                  machine.assetId.isEmpty ? machine.name : machine.assetId,
                  flex: _kMachineFlex[0],
                  strong: true,
                  selected: selected,
                ),
                _MachineCell(machine.machineType, flex: _kMachineFlex[1]),
                _MachineCell(machine.machineMake, flex: _kMachineFlex[2]),
                _MachineCell(capacity, flex: _kMachineFlex[3]),
                _MachineCell(
                  machine.strokesPerMinute == null
                      ? ''
                      : '${machine.strokesPerMinute}',
                  flex: _kMachineFlex[4],
                ),
                _MachineCell(machine.dieFeedType, flex: _kMachineFlex[5]),
                if (pending)
                  _MachineCell(
                    partExists ? 'held' : 'held for the part',
                    flex: _kMachineFlex[6],
                    muted: true,
                  )
                else
                  Spacer(flex: _kMachineFlex[6]),
                const SizedBox(width: 6),
                // Its Edit, said out loud: a saved row opens in the form above,
                // whose button is then this row's Save.
                Tooltip(
                  message: selected
                      ? 'Being edited above — Save there'
                      : 'Edit this machine',
                  child: IconButton(
                    key: ValueKey<String>('machine_row_edit_${machine.name}'),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    visualDensity: VisualDensity.compact,
                    color: SoftErpTheme.accent,
                    onPressed: selected ? null : onTap,
                  ),
                ),
                Tooltip(
                  // Said in full, because "remove" reads as "destroy" and this
                  // one does not.
                  message: pending
                      ? 'Drop this one — it has not been made yet'
                      : 'Take off this part — the machine stays in the master',
                  child: IconButton(
                    icon: Icon(
                      pending ? Icons.close_rounded : Icons.link_off_rounded,
                      size: 20,
                    ),
                    visualDensity: VisualDensity.compact,
                    color: SoftErpTheme.textSecondary,
                    onPressed: onUnlink,
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

/// Column weights shared by the header strip and every row, so they line up.
const List<int> _kMachineFlex = [24, 20, 22, 18, 10, 18, 16];
const List<String> _kMachineHeads = [
  'Machine No',
  'Type',
  'Make',
  'Capacity',
  'Str/min',
  'Feed',
  '',
];

class _MachineHeaderStrip extends StatelessWidget {
  const _MachineHeaderStrip();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 44, 4),
      child: Row(
        children: [
          for (var i = 0; i < _kMachineHeads.length; i += 1)
            Expanded(
              flex: _kMachineFlex[i],
              child: Text(
                _kMachineHeads[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
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
}

class _MachineCell extends StatelessWidget {
  const _MachineCell(
    this.text, {
    required this.flex,
    this.strong = false,
    this.selected = false,
    this.muted = false,
  });

  final String text;
  final int flex;
  final bool strong;
  final bool selected;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text.isEmpty ? '—' : text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: strong ? 15 : 14,
          fontWeight: strong
              ? (selected ? FontWeight.w800 : FontWeight.w700)
              : FontWeight.w600,
          color: muted || text.isEmpty
              ? SoftErpTheme.textSecondary
              : (strong ? SoftErpTheme.textPrimary : SoftErpTheme.textSecondary),
        ),
      ),
    );
  }
}
