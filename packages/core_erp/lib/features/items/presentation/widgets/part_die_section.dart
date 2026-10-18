import 'package:flutter/material.dart';

import '../../../../core/app_flow_hooks.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/utils/stamp_format.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/length_unit_field.dart';
import '../../../dies/domain/die_code.dart';
import '../../domain/item_definition.dart';

/// The die sheet, beside the part it was made for.
///
/// | PO-Date | Time | Die Made By | Type | Liner Size | Die Code | No of Set |
/// | Store Area | Rack No | Date in | Time |
///
/// **A part holds as many dies as it needs** — a cutting die and a bending
/// die, or two of a kind. They are listed above the sheet, and tapping one
/// loads it in to be corrected, the way the Developed For panel retargets to
/// whichever part is picked. The sheet is therefore one form with two jobs,
/// and its heading always says which.
///
/// A die made here is a **row in the dies master**, linked to this part: it
/// shows up on the Dies screen, can be found by its code, and can be linked to
/// another part later. Taking it off a part **unlinks** it — a die is a
/// physical tool on a rack, and no longer making this part is not the same as
/// being scrapped.
///
/// The write goes through [AppFlowHooks.createDieFromSheet] because `Die`
/// lives in the app, not in this package. Linking is this package's job, since
/// `ItemsProvider` is here, and the two steps stay separate so a link that
/// fails cannot lose a die that was already made.
class PartDieSection extends StatefulWidget {
  const PartDieSection({
    super.key,
    required this.part,
    required this.partCode,
    required this.partLabel,
    required this.busy,
    required this.staged,
    required this.onStage,
    required this.onUnstage,
    required this.onDiesChanged,
  });

  /// The part the sheet is about, or null while it is still being typed.
  ///
  /// Null no longer means "wait": it means everything Add does is HELD until
  /// the part is made. Making someone save halfway through a thought is the
  /// thing this section used to do and no longer does.
  final ItemDefinition? part;

  /// The code the part has, or the one being suggested for it as its name is
  /// typed. The die code is built from this rather than from [part], which is
  /// what lets a die be filled in before the part exists.
  final String partCode;

  /// What to call the part in this section's heading.
  final String partLabel;

  final bool busy;

  /// Dies held for a part that does not exist yet, newest last.
  final List<DieSheetDraft> staged;

  /// Holds one. The wizard owns the list, because the create path flushes it
  /// and the close path warns about it.
  final ValueChanged<DieSheetDraft> onStage;

  /// Drops a held one by its position.
  final ValueChanged<int> onUnstage;

  /// Replaces the dies on the part. Returns null on success, or what went
  /// wrong — a die that was just made exists either way, so the section is
  /// told rather than left to guess.
  final Future<String?> Function(List<String> dieIds) onDiesChanged;

  @override
  State<PartDieSection> createState() => _PartDieSectionState();
}

class _PartDieSectionState extends State<PartDieSection> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _madeByController = TextEditingController();
  final TextEditingController _linerController = TextEditingController();
  final TextEditingController _setsController = TextEditingController();
  final TextEditingController _storeAreaController = TextEditingController();
  final TextEditingController _rackController = TextEditingController();

  DieType? _type;
  String _linerUnit = 'mm';
  DateTime? _poAt;
  DateTime? _dateInAt;

  /// The die being corrected, or null when the sheet is for a new one.
  String? _editingDieId;

  /// The HELD die being corrected, by position, or null. Separate from
  /// [_editingDieId] because a held die has no id to name it by.
  int? _editingStagedIndex;

  /// Set once the code is typed over, after which it stops re-deriving — the
  /// same pin the part code has, and for the same reason.
  bool _codePinned = false;

  /// Names used on a die before, for the Made By suggestions. Loaded once.
  List<String> _madeByNames = const <String>[];

  bool _saving = false;
  String? _error;
  String? _notice;
  String? _linerError;

  /// A die that was created and could not be linked. Kept so a retry links it
  /// instead of making a second one.
  String? _unlinkedDieId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMadeByNames());
  }

  @override
  void didUpdateWidget(PartDieSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different part means a different code, and a half-filled sheet that
    // belonged to the part being left behind.
    if (oldWidget.part?.id != widget.part?.id) {
      _resetSheet();
      return;
    }
    // The part's code is still being typed, and the die's is built from it.
    if (oldWidget.partCode != widget.partCode && _editingDieId == null) {
      _rederiveCode();
    }
    if (oldWidget.staged.length != widget.staged.length) _rederiveCode();
    // The dies on the part changed under us — one was just added, or taken
    // off. The suggested code counts them, so it has to be recomputed: the
    // second cutting die on a part cannot be offered the first one's code.
    final before = oldWidget.part?.dies.map((die) => die.id).join(',');
    final now = widget.part?.dies.map((die) => die.id).join(',');
    if (before != now && _editingDieId == null) _rederiveCode();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _madeByController.dispose();
    _linerController.dispose();
    _setsController.dispose();
    _storeAreaController.dispose();
    _rackController.dispose();
    super.dispose();
  }

  Future<void> _loadMadeByNames() async {
    final hook = AppFlowHooks.dieMadeByNames;
    if (hook == null || !mounted) return;
    final names = await hook(context);
    if (!mounted) return;
    setState(() => _madeByNames = names);
  }

  List<ItemDieLink> get _dies => widget.part?.dies ?? const <ItemDieLink>[];

  // --- the sheet's two jobs --------------------------------------------------

  /// Back to a blank sheet for the next die.
  ///
  /// What repeats down a column of the physical sheet sticks — the type, the
  /// maker, the area and rack, the dates. What is measured per die does not.
  void _resetSheet({bool keepRepeating = true}) {
    _editingDieId = null;
    _editingStagedIndex = null;
    _unlinkedDieId = null;
    _error = null;
    _notice = null;
    _linerError = null;
    _codePinned = false;
    _linerController.clear();
    _setsController.clear();
    if (!keepRepeating) {
      _type = null;
      _madeByController.clear();
      _storeAreaController.clear();
      _rackController.clear();
      _poAt = null;
      _dateInAt = null;
    }
    _rederiveCode();
  }

  /// Loads a die that already exists into the sheet, to be corrected.
  /// Loads a HELD die back into the sheet. Add then replaces it rather than
  /// holding a second one.
  void _editStaged(int index) {
    final draft = widget.staged[index];
    setState(() {
      _editingDieId = null;
      _editingStagedIndex = index;
      _unlinkedDieId = null;
      _error = null;
      _notice = null;
      _linerError = null;
      _type = DieType.fromSlug(draft.dieType);
      _codePinned = true;
      _codeController.text = draft.toolCode;
      _madeByController.text = draft.madeBy;
      _linerUnit = draft.linerSizeUnit;
      _linerController.text = formatLengthFromNanometres(
        draft.linerSizeNm,
        draft.linerSizeUnit,
      );
      _setsController.text = draft.noOfSet?.toString() ?? '';
      _storeAreaController.text = draft.storeArea;
      _rackController.text = draft.rackNo;
      _poAt = draft.poAt;
      _dateInAt = draft.dateInAt;
    });
  }

  void _editDie(ItemDieLink die) {
    setState(() {
      _editingStagedIndex = null;
      _editingDieId = die.id;
      _unlinkedDieId = null;
      _error = null;
      _notice = null;
      _linerError = null;
      _type = DieType.fromSlug(die.dieType);
      // Pinned, because it is a code that exists: re-deriving it from the type
      // would quietly rename a die that is painted on a tool.
      _codePinned = true;
      _codeController.text = die.toolCode;
      _madeByController.text = die.madeBy;
      _linerUnit = die.linerSizeUnit;
      _linerController.text = formatLengthFromNanometres(
        die.linerSizeNm,
        die.linerSizeUnit,
      );
      _setsController.text = die.noOfSet?.toString() ?? '';
      _storeAreaController.text = die.storeArea;
      _rackController.text = die.rackNo;
      _poAt = die.poAt;
      _dateInAt = die.dateInAt;
    });
  }

  /// The code a NEW die on this part would take.
  ///
  /// A second cutting die on the same part derives the same code as the first,
  /// so the free one in the series is offered up front rather than after a
  /// refusal. The server still has the last word — it is the only thing that
  /// can see the other 400 dies in the factory.
  String _suggestedCode() {
    final base = buildDieCode(type: _type, partCode: widget.partCode);
    if (base.isEmpty) return '';
    final taken = <String>{
      for (final die in _dies)
        if (die.id != _editingDieId) die.toolCode.trim().toUpperCase(),
      // Held dies count too, or two cutting dies waiting on the same part
      // would both be offered the same code.
      for (var i = 0; i < widget.staged.length; i += 1)
        if (i != _editingStagedIndex)
          widget.staged[i].toolCode.trim().toUpperCase(),
    };
    if (!taken.contains(base)) return base;
    for (var suffix = 2; suffix < 50; suffix += 1) {
      final candidate = '$base-$suffix';
      if (!taken.contains(candidate)) return candidate;
    }
    return base;
  }

  void _rederiveCode() {
    if (_codePinned) return;
    _codeController.text = _suggestedCode();
  }

  Future<void> _pickMoment({
    required DateTime? current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final seed = current?.toLocal() ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: seed,
      firstDate: DateTime(2000),
      lastDate: DateTime(seed.year + 10),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(seed),
    );
    if (!mounted) return;
    onPicked(
      DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? seed.hour,
        time?.minute ?? seed.minute,
      ),
    );
  }

  // --- writes ----------------------------------------------------------------

  /// What the sheet currently describes, or null with [_error] set.
  DieSheetDraft? _draftFromSheet({String? dieId, required String partCode}) {
    final liner = parseLengthToNanometres(_linerController.text, _linerUnit);
    if (liner.isFailure) {
      setState(() => _linerError = liner.error);
      return null;
    }
    final code = _codeController.text.trim().toUpperCase();
    if (_type == null) {
      setState(() => _error = 'Pick a type — the code is built from it.');
      return null;
    }
    if (code.isEmpty) {
      // Two different missing things, and the old message only named one.
      setState(
        () => _error = partCode.isEmpty
            ? 'Name the part first — the die code is built from its code.'
            : 'The die needs a code.',
      );
      return null;
    }
    return DieSheetDraft(
      dieId: dieId,
      toolCode: code,
      dieType: _type!.slug,
      madeBy: _madeByController.text.trim(),
      poAt: _poAt,
      dateInAt: _dateInAt,
      linerSizeNm: liner.nanometres,
      linerSizeUnit: _linerUnit,
      noOfSet: int.tryParse(_setsController.text.trim()),
      storeArea: _storeAreaController.text.trim(),
      rackNo: _rackController.text.trim(),
      partCode: partCode,
      partName: widget.partLabel,
    );
  }

  /// Holds the sheet for a part that does not exist yet.
  void _stageDie() {
    final draft = _draftFromSheet(partCode: widget.partCode);
    if (draft == null) return;
    final replacing = _editingStagedIndex;
    setState(() {
      _error = null;
      if (replacing != null) widget.onUnstage(replacing);
      widget.onStage(draft);
      _resetSheet();
      _notice = 'Die ${draft.toolCode} is held until the part is made.';
    });
  }

  Future<void> _saveDie() async {
    final part = widget.part;
    final hook = AppFlowHooks.createDieFromSheet;
    if (hook == null || _saving) return;
    // No part yet: hold it. Writing one would mean creating the part behind
    // the user's back, which is how a half-typed name becomes a real part.
    if (part == null) {
      _stageDie();
      return;
    }

    final liner = parseLengthToNanometres(_linerController.text, _linerUnit);
    if (liner.isFailure) {
      setState(() => _linerError = liner.error);
      return;
    }
    final code = _codeController.text.trim().toUpperCase();
    if (_type == null || code.isEmpty) {
      setState(() => _error = 'Pick a type — the code is built from it.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
      _linerError = null;
    });

    // A die that exists and is not linked yet is retried as a LINK, never as a
    // second create — the rule the wizard already applies to a part whose set
    // could not be made.
    var dieId = _unlinkedDieId;
    final editing = _editingDieId;
    if (dieId == null) {
      final outcome = await hook(
        context,
        DieSheetDraft(
          dieId: editing,
          toolCode: code,
          dieType: _type!.slug,
          madeBy: _madeByController.text.trim(),
          poAt: _poAt,
          dateInAt: _dateInAt,
          linerSizeNm: liner.nanometres,
          linerSizeUnit: _linerUnit,
          noOfSet: int.tryParse(_setsController.text.trim()),
          storeArea: _storeAreaController.text.trim(),
          rackNo: _rackController.text.trim(),
          partCode: part.partCode,
          partName: part.displayName.trim().isEmpty
              ? part.name
              : part.displayName,
        ),
      );
      if (!mounted) return;
      if (!outcome.isCreated) {
        setState(() {
          _saving = false;
          _error = outcome.message ?? 'The die could not be saved.';
          // Offer the free code rather than retrying the write, which is how
          // two dies get made when only the response was lost.
          final suggested = outcome.suggestedToolCode;
          if (suggested != null && suggested.isNotEmpty) {
            _codeController.text = suggested;
            _codePinned = true;
          }
        });
        return;
      }
      dieId = outcome.record!.id;
    }

    // A die being corrected is already on the part; only a new one needs
    // linking, and the link carries every die already there because it is a
    // full replace.
    if (editing == null) {
      final linkError = await widget.onDiesChanged(<String>[
        ..._dies.map((die) => die.id),
        if (!_dies.any((die) => die.id == dieId)) dieId,
      ]);
      if (!mounted) return;
      if (linkError != null) {
        setState(() {
          _saving = false;
          _unlinkedDieId = dieId;
          _error =
              'Die $code was made, but it could not be attached to this part '
              '— $linkError. Try again and it will only attach it.';
        });
        return;
      }
    }

    setState(() {
      _saving = false;
      final wasEditing = editing != null;
      // A held draft that has just been written is no longer held. Leaving it
      // in the list would both show a pending row for a die that exists and
      // write it a second time onto the NEXT part created.
      final wasHeld = _editingStagedIndex;
      if (wasHeld != null) widget.onUnstage(wasHeld);
      _resetSheet();
      _notice = wasEditing
          ? 'Die $code is saved.'
          : 'Die $code is on this part.';
    });
  }

  Future<void> _unlink(ItemDieLink die) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    final error = await widget.onDiesChanged(
      _dies.where((row) => row.id != die.id).map((row) => row.id).toList(),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (error != null) {
        _error = 'That die is still on this part — $error.';
        return;
      }
      if (_editingDieId == die.id) _resetSheet();
      // Said plainly, because "remove" reads as "destroy" to most people and
      // this one does not.
      _notice =
          '${die.toolCode} is off this part. It is still in the dies master.';
    });
  }

  // --- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final part = widget.part;
    // Open with no part: everything Add does is held until the part is made.
    final enabled = !widget.busy && !_saving;
    final editing = _editingDieId;
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
          if (AppFlowHooks.createDieFromSheet == null)
            const Text(
              'Dies cannot be made from here in this build.',
              style: TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary),
            )
          else ...[
            if (holding) ...[
              const Text(
                'Fill this in now — each die is held until you create the '
                'part, then written with it.',
                style: TextStyle(
                  fontSize: 13,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
            ],
            _dieList(enabled),
            const SizedBox(height: 12),
            _typeRow(enabled),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey<String>('quick-entry-die-code-field'),
              controller: _codeController,
              enabled: enabled,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() => _codePinned = true),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                labelText: 'Die Code',
                helperText: _codeHelper(),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            _madeByField(enabled),
            const SizedBox(height: 10),
            LengthUnitField(
              fieldKey: const ValueKey<String>('quick-entry-die-liner-field'),
              controller: _linerController,
              unitSymbol: _linerUnit,
              enabled: enabled,
              label: 'Liner Size',
              helperText: 'Optional',
              errorText: _linerError,
              onUnitChanged: (symbol) => setState(() {
                _linerUnit = symbol;
                _linerError = null;
              }),
              onChanged: () {
                if (_linerError != null) setState(() => _linerError = null);
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('quick-entry-die-sets-field'),
                    controller: _setsController,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'No. of Sets',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('quick-entry-die-area-field'),
                    controller: _storeAreaController,
                    enabled: enabled,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'Store Area',
                      hintText: 'F206',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('quick-entry-die-rack-field'),
                    controller: _rackController,
                    enabled: enabled,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'Rack No.',
                      hintText: '23-4',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _momentRow(
              label: 'PO Date & Time',
              value: _poAt,
              enabled: enabled,
              onPicked: (value) => setState(() => _poAt = value),
              onCleared: () => setState(() => _poAt = null),
            ),
            const SizedBox(height: 8),
            _momentRow(
              label: 'Date In & Time',
              value: _dateInAt,
              enabled: enabled,
              onPicked: (value) => setState(() => _dateInAt = value),
              onCleared: () => setState(() => _dateInAt = null),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 13.5,
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
                  fontSize: 13.5,
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
                    key: const ValueKey<String>('quick-entry-die-cancel'),
                    onPressed: enabled ? () => setState(_resetSheet) : null,
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontSize: 13.5),
                    ),
                  ),
                const SizedBox(width: 8),
                AppButton(
                  key: const ValueKey<String>('quick-entry-add-die'),
                  label: _unlinkedDieId != null
                      ? 'Attach the die'
                      : (editing != null || _editingStagedIndex != null
                            ? 'Save die'
                            : (holding ? 'Hold die' : 'Add die')),
                  icon: Icons.precision_manufacturing_outlined,
                  // Secondary, like every write on this screen: Cmd/Ctrl+Enter
                  // fires the last enabled PRIMARY button in the tree, and that
                  // must stay Done.
                  variant: AppButtonVariant.secondary,
                  isLoading: _saving,
                  onPressed: enabled ? _saveDie : null,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _heading(String? editing) {
    final label = widget.partCode.isNotEmpty
        ? widget.partCode
        : (widget.partLabel.isNotEmpty ? widget.partLabel : 'this part');
    if (widget.part == null) return 'Dies · $label · held';
    if (editing == null) return 'Dies · $label · new';
    return 'Dies · $label · ${_codeController.text}';
  }

  String _codeHelper() {
    if (_editingDieId != null) return 'Renaming this die renames the tool';
    if (_codePinned) {
      return 'Typed over — it will not follow the type any more';
    }
    if (widget.partCode.isEmpty) {
      return 'Name the part above and its code fills in here';
    }
    return 'Built from the type and this part: ${widget.partCode}';
  }

  Widget _dieList(bool enabled) {
    if (_dies.isEmpty && widget.staged.isEmpty) {
      return const Text(
        'No dies on this part yet. Fill the sheet below and add one — a part '
        'can hold as many as it needs.',
        style: TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Held first: they are what this screen is about to write, and a row
        // nobody can see is a row nobody knows they staged.
        for (var i = 0; i < widget.staged.length; i += 1)
          _DieRow(
            key: ValueKey<String>('quick-entry-staged-die-$i'),
            die: _linkFromDraft(widget.staged[i]),
            selected: i == _editingStagedIndex,
            pending: true,
            partExists: widget.part != null,
            onTap: enabled ? () => _editStaged(i) : null,
            onUnlink: enabled ? () => widget.onUnstage(i) : null,
          ),
        for (final die in _dies)
          _DieRow(
            key: ValueKey<String>('quick-entry-die-row-${die.id}'),
            die: die,
            selected: die.id == _editingDieId,
            onTap: enabled ? () => _editDie(die) : null,
            onUnlink: enabled ? () => _unlink(die) : null,
          ),
      ],
    );
  }

  /// A held draft, shaped like a linked die so one row widget draws both.
  ItemDieLink _linkFromDraft(DieSheetDraft draft) => ItemDieLink(
    id: '',
    toolCode: draft.toolCode,
    dieType: draft.dieType,
    madeBy: draft.madeBy,
    poAt: draft.poAt,
    dateInAt: draft.dateInAt,
    linerSizeNm: draft.linerSizeNm,
    linerSizeUnit: draft.linerSizeUnit,
    noOfSet: draft.noOfSet,
    storeArea: draft.storeArea,
    rackNo: draft.rackNo,
  );

  Widget _typeRow(bool enabled) {
    return Row(
      children: [
        const SizedBox(
          width: 110,
          child: Text(
            'Type',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: SoftErpTheme.textPrimary,
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in DieType.values)
                ChoiceChip(
                  label: Text(
                    type.label,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                  selected: _type == type,
                  onSelected: !enabled
                      ? null
                      : (selected) => setState(() {
                          _type = selected ? type : null;
                          _rederiveCode();
                        }),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _madeByField(bool enabled) {
    final typed = _madeByController.text.trim().toLowerCase();
    final suggestions = _madeByNames
        .where((name) => typed.isEmpty || name.toLowerCase().contains(typed))
        .where((name) => name.toLowerCase() != typed)
        .take(5)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey<String>('quick-entry-die-made-by-field'),
          controller: _madeByController,
          enabled: enabled,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(
            labelText: 'Die Made By',
            helperText:
                'Whoever cut it — a fitter here, or an outside toolroom',
            border: OutlineInputBorder(),
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          // Chips rather than an Autocomplete overlay: an overlay inside a
          // dialog inside a scroll view is a positioning fight this codebase
          // has already lost once.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final name in suggestions)
                ActionChip(
                  label: Text(name, style: const TextStyle(fontSize: 13)),
                  onPressed: !enabled
                      ? null
                      : () => setState(() {
                          _madeByController.text = name;
                          _madeByController.selection = TextSelection.collapsed(
                            offset: name.length,
                          );
                        }),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _momentRow({
    required String label,
    required DateTime? value,
    required bool enabled,
    required ValueChanged<DateTime> onPicked,
    required VoidCallback onCleared,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: SoftErpTheme.textPrimary,
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: enabled
                    ? () => _pickMoment(current: value, onPicked: onPicked)
                    : null,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(
                  // Always through partStamp: the instant is stored in UTC and
                  // a shop at +05:30 must not read 11.30 AM as 6.00 AM.
                  value == null ? 'Pick' : partStamp(value),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              if (enabled && value != null)
                TextButton(
                  onPressed: onCleared,
                  child: const Text('Clear', style: TextStyle(fontSize: 13)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One die on the part: what tells it from the others, and the way off.
class _DieRow extends StatelessWidget {
  const _DieRow({
    super.key,
    required this.die,
    required this.selected,
    this.pending = false,
    this.partExists = false,
    this.onTap,
    this.onUnlink,
  });

  final ItemDieLink die;
  final bool selected;

  /// Held and not written. Says so on the row, because a die that looks
  /// saved and is not is the worst of both.
  final bool pending;

  /// Whether the part it is held for exists yet — which is the difference
  /// between "waiting on the part" and "the part was made, this one was
  /// refused", and the row should not claim the first when it is the second.
  final bool partExists;
  final VoidCallback? onTap;
  final VoidCallback? onUnlink;

  @override
  Widget build(BuildContext context) {
    final type = DieType.fromSlug(die.dieType);
    final facts = <String>[
      if (type != null) type.label,
      if (die.madeBy.trim().isNotEmpty) die.madeBy.trim(),
      if (die.linerSizeNm != null)
        '${formatLengthFromNanometres(die.linerSizeNm, die.linerSizeUnit)} '
            '${die.linerSizeUnit}',
      if (die.noOfSet != null)
        '${die.noOfSet} set${die.noOfSet == 1 ? '' : 's'}',
      if (die.whereKept.isNotEmpty) die.whereKept,
      if (pending)
        partExists ? 'held — not written yet' : 'held until the part is made',
    ];

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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        die.toolCode.isEmpty ? 'Die ${die.id}' : die.toolCode,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w700,
                          color: SoftErpTheme.textPrimary,
                        ),
                      ),
                      if (facts.isNotEmpty)
                        Text(
                          facts.join(' · '),
                          style: const TextStyle(
                            fontSize: 13,
                            color: SoftErpTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  // Said in full, because "remove" reads as "destroy": this
                  // takes the die off the part and leaves the tool alone.
                  message: pending
                      ? 'Drop this one — it has not been made yet'
                      : 'Take off this part — the die stays in the master',
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
