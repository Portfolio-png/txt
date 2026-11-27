import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../sheet/sheet_engine.dart';
import '../../../../sheet/sheet_style.dart';
import '../../../../sheet/widgets/sheet_step.dart';
import '../../../../sheet/widgets/coloured_tabs.dart';
import 'package:provider/provider.dart';

import '../../../../core/app_flow_hooks.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/services/entity_photos.dart';
import '../../../../core/widgets/mini_photo.dart';
import '../../../../core/utils/stamp_format.dart';
import '../../../../sheet/widgets/sheet_save_button.dart';
import '../../../../sheet/widgets/tucked_save_row.dart';
import '../../../../core/widgets/length_unit_field.dart';
import '../../../../core/widgets/fit_to_text.dart';
import '../../../../core/widgets/pick_or_type_field.dart';
import '../../../die_makers/presentation/providers/die_makers_provider.dart';
import '../../../die_makers/presentation/widgets/die_maker_picker_field.dart';
import '../../../dies/domain/die_code.dart';
import '../../../items/domain/part_code.dart';
import '../../domain/item_definition.dart';
import 'part_photo_gallery.dart';

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
    this.lineKey,
    required this.part,
    required this.partCode,
    required this.partLabel,
    required this.busy,
    required this.staged,
    required this.onStage,
    required this.onUnstage,
    required this.onDiesChanged,
    this.framed = true,
    this.onHeading,
    this.onTypeChanged,
    this.heldSaveBuilder,
    this.onDirtyChanged,
    this.flow,
  });

  /// The keyboard's order of the screen's steps; the die form is one.
  final SheetFlow? flow;

  /// The die form's step id.
  static const Object step = 'die';

  /// Told when the sheet starts or stops holding a die that is typed but not
  /// held or saved — so the host can warn before leaving with it.
  final ValueChanged<bool>? onDirtyChanged;

  /// The host's Save for a held die's row — the part row's own Save part,
  /// since a held die is written only with its part. Null (the quick-entry
  /// dialog) keeps the row's "Saves with the part" note.
  final Widget Function(int index)? heldSaveBuilder;

  /// Whether the section draws its own card. Off where a host already frames
  /// it — the item sheet's section card — so it is not a card inside a card.
  final bool framed;

  /// Where the host shows the section's heading — the item sheet's title
  /// bar, as a chip like the part's own code: [label] muted, [value] (a
  /// code; null while there is none yet) bold. "New die for part code:
  /// SADP48", "Editing die: D-12". Set, the section stops drawing it
  /// itself and reports it here whenever it changes.
  final ValueChanged<({String label, String? value})>? onHeading;

  /// The type picked or typed on the form ("Cutting", "Deep Drawing"), each
  /// time it changes — the item sheet fills the machine's Die Type with it.
  final ValueChanged<String>? onTypeChanged;

  /// The sheet line this is typed for. A different line is a different part
  /// — saved or not — so what was typed for the last one is cleared.
  final Object? lineKey;

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
  final TextEditingController _cavityController = TextEditingController();
  final TextEditingController _storeAreaController = TextEditingController();
  final TextEditingController _rackController = TextEditingController();

  DieTypeChoice? _type;
  int? _dieMakerId;

  /// The die maker master, when the host registered one.
  ///
  /// Optional on purpose: this section is mounted by the item master sheet AND
  /// by the older quick-entry dialog, and every widget test that predates the
  /// master builds it with neither. A null provider keeps the text field.
  DieMakersProvider? _dieMakers;
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

  /// What earlier dies were given, for the dropdowns. Loaded on open and
  /// again after each save, so a value typed here is offered on the next die.
  DieSheetSuggestions _suggestions = const DieSheetSuggestions();

  bool _saving = false;
  String? _error;
  String? _notice;
  String? _linerError;

  /// A die that was created and could not be linked. Kept so a retry links it
  /// instead of making a second one.
  String? _unlinkedDieId;

  /// The form as it stood when last cleared — what "typed since" means for
  /// the keyboard's save prompt. The code counts only once typed over; it
  /// re-derives from the part by itself.
  String? _clean;

  String _snapshot() => [
    _codePinned ? _codeController.text : '',
    _madeByController.text,
    _linerController.text,
    _setsController.text,
    _cavityController.text,
    _storeAreaController.text,
    _rackController.text,
    _type?.slug ?? '',
    _type?.label ?? '',
    '$_dieMakerId',
    _linerUnit,
    '$_poAt',
    '$_dateInAt',
  ].join('|');

  /// Anything typed or picked since the form was last cleared, or a die
  /// open for correcting: something Tab past the form should ask about.
  bool get _hasTyped =>
      _unlinkedDieId != null || _snapshot() != (_clean ??= _snapshot());

  /// What the host was last told.
  bool _reportedDirty = false;

  /// A die typed and not held or saved: a measured field filled, or one
  /// open for correcting, or one made and not yet linked. What repeats down
  /// the sheet (type, maker, dates…) stays after each save on purpose, so it
  /// alone is not unsaved work.
  bool get isDirty {
    if (_unlinkedDieId != null) return true;
    // Open for correcting (its tab chosen): unsaved only once changed.
    // Opening a tab is looking at it, and counted as work it held the sheet
    // open on leaving.
    if (_editingDieId != null || _editingStagedIndex != null) {
      return _snapshot() != (_clean ??= _snapshot());
    }
    return _linerController.text.trim().isNotEmpty ||
        _setsController.text.trim().isNotEmpty ||
        _cavityController.text.trim().isNotEmpty;
  }

  void _reportDirty() {
    final report = widget.onDirtyChanged;
    final dirty = isDirty;
    if (report == null || dirty == _reportedDirty) return;
    _reportedDirty = dirty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) report(dirty);
    });
  }

  @override
  void initState() {
    super.initState();
    _linerController.addListener(_reportDirty);
    _setsController.addListener(_reportDirty);
    _cavityController.addListener(_reportDirty);
    _clean = _snapshot();

    // The master is lazy and nothing else on this screen fetches it, so an
    // unfetched picker would be indistinguishable from a shop with no die
    // makers. Listened to as well as loaded: the fetch lands after the first
    // frame, and the field has to redraw when it does.
    try {
      _dieMakers = Provider.of<DieMakersProvider>(context, listen: false)
        ..addListener(_onDieMakersChanged);
    } catch (_) {
      _dieMakers = null;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSuggestions();
      unawaited(_dieMakers?.ensureLoaded());
    });
  }

  void _onDieMakersChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(PartDieSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different part means a different code, and a half-filled sheet that
    // belonged to the part being left behind.
    if (oldWidget.part?.id != widget.part?.id) {
      _corrected.clear();
      // The part being typed was just saved: what is typed here is for it, so
      // it stays. Only moving to another part clears the sheet.
      // (Same line only: from a new, unsaved line onto another part is not
      // that part being saved, and what was typed stayed for the wrong one.)
      if (oldWidget.part == null &&
          isDirty &&
          oldWidget.lineKey == widget.lineKey) {
        _rederiveCode();
        return;
      }
      _resetSheet();
      return;
    }
    // From one new line to another: both have no part yet, but they are not
    // the same part — and a held one being edited belonged to the other line.
    if (oldWidget.lineKey != widget.lineKey) {
      _resetSheet();
      return;
    }
    _forgetCaughtUp();
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
    _dieMakers?.removeListener(_onDieMakersChanged);
    _madeByController.dispose();
    _linerController.dispose();
    _setsController.dispose();
    _cavityController.dispose();
    _storeAreaController.dispose();
    _rackController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    final hook = AppFlowHooks.dieSheetSuggestions;
    if (hook == null || !mounted) return;
    final suggestions = await hook(context);
    if (!mounted) return;
    setState(() {
      _suggestions = suggestions;
      _rederiveCode();
    });
  }

  List<ItemDieLink> get _dies {
    final stored = widget.part?.dies ?? const <ItemDieLink>[];
    if (_corrected.isEmpty) return stored;
    return [for (final die in stored) _corrected[die.id] ?? die];
  }

  /// Dies corrected here that the part's own read has not caught up with.
  ///
  /// The part's die list is a snapshot, so opening a die again straight after
  /// correcting it loaded the OLD values — and saving that wrote them back
  /// over the correction. Held until the part reads the same, the way
  /// `ItemsProvider` holds its own writes over a lagging read.
  final Map<String, ItemDieLink> _corrected = {};

  void _rememberCorrection(String id, DieSheetDraft sent) {
    final before = (widget.part?.dies ?? const <ItemDieLink>[])
        .where((die) => die.id == id)
        .firstOrNull;
    _corrected[id] = ItemDieLink(
      id: id,
      toolCode: sent.toolCode,
      photoUrl: before?.photoUrl,
      dieType: sent.dieType,
      dieTypeLabel: sent.dieTypeLabel,
      madeBy: sent.madeBy,
      dieMakerId: sent.dieMakerId,
      poAt: sent.poAt,
      dateInAt: sent.dateInAt,
      linerSizeNm: sent.linerSizeNm,
      linerSizeUnit: sent.linerSizeUnit,
      noOfSet: sent.noOfSet,
      numberOfCavities: sent.numberOfCavities,
      storeArea: sent.storeArea,
      rackNo: sent.rackNo,
    );
  }

  /// Drops corrections the part now reads back itself.
  void _forgetCaughtUp() {
    if (_corrected.isEmpty) return;
    final stored = {
      for (final die in widget.part?.dies ?? const <ItemDieLink>[]) die.id: die,
    };
    _corrected.removeWhere((id, mine) {
      final fresh = stored[id];
      return fresh == null ||
          (fresh.toolCode == mine.toolCode &&
              fresh.dieType == mine.dieType &&
              fresh.dieTypeLabel == mine.dieTypeLabel &&
              fresh.madeBy == mine.madeBy &&
              fresh.dieMakerId == mine.dieMakerId &&
              fresh.linerSizeNm == mine.linerSizeNm &&
              fresh.noOfSet == mine.noOfSet &&
              fresh.numberOfCavities == mine.numberOfCavities &&
              fresh.storeArea == mine.storeArea &&
              fresh.rackNo == mine.rackNo &&
              fresh.poAt == mine.poAt &&
              fresh.dateInAt == mine.dateInAt);
    });
  }

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
    _cavityController.clear();
    if (!keepRepeating) {
      _type = null;
      _dieMakerId = null;
      _madeByController.clear();
      _storeAreaController.clear();
      _rackController.clear();
      _poAt = null;
      _dateInAt = null;
    }
    _rederiveCode();
    _clean = _snapshot();
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
      _type = DieTypeChoice.fromStored(draft.dieType, draft.dieTypeLabel);
      _dieMakerId = draft.dieMakerId;
      _codePinned = true;
      _codeController.text = draft.toolCode;
      _madeByController.text = draft.madeBy;
      _linerUnit = draft.linerSizeUnit;
      _linerController.text = formatLengthFromNanometres(
        draft.linerSizeNm,
        draft.linerSizeUnit,
      );
      _setsController.text = draft.noOfSet?.toString() ?? '';
      _cavityController.text = draft.numberOfCavities?.toString() ?? '';
      _storeAreaController.text = draft.storeArea;
      _rackController.text = draft.rackNo;
      _poAt = draft.poAt;
      _dateInAt = draft.dateInAt;
      // Opened as stored: only a change to it is unsaved work.
      _clean = _snapshot();
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
      _type = DieTypeChoice.fromStored(die.dieType, die.dieTypeLabel);
      _dieMakerId = die.dieMakerId;
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
      _cavityController.text = die.numberOfCavities?.toString() ?? '';
      _storeAreaController.text = die.storeArea;
      _rackController.text = die.rackNo;
      _poAt = die.poAt;
      _dateInAt = die.dateInAt;
      // Opened as stored: only a change to it is unsaved work.
      _clean = _snapshot();
    });
  }

  /// The code a NEW die on this part would take.
  ///
  /// A second cutting die on the same part derives the same code as the first,
  /// so the free one in the series is offered up front rather than after a
  /// refusal. So does a die on ANOTHER part: a typed "Blanking" codes BD like
  /// Bending, and the code is unique across the factory. The server still has
  /// the last word — the master read here can be a moment old.
  String _suggestedCode() {
    final base = buildDieCodeFor(choice: _type, partCode: widget.partCode);
    if (base.isEmpty) return '';
    final taken = <String>{
      ..._suggestions.toolCodes,
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

  /// "No. of Sets" holding something that is not a whole number. It used to
  /// parse to null and replace the stored count.
  String? get _setsProblem {
    final text = _setsController.text.trim();
    if (text.isNotEmpty && SheetEngine.parseWhole(text) == null) {
      return 'No. of sets takes a whole number.';
    }
    final cavity = _cavityController.text.trim();
    return cavity.isNotEmpty && SheetEngine.parseWhole(cavity) == null
        ? 'Cavity takes a whole number.'
        : null;
  }

  /// What the sheet currently describes, or null with [_error] set.
  DieSheetDraft? _draftFromSheet({String? dieId, required String partCode}) {
    if (_setsProblem != null) {
      setState(() => _error = _setsProblem);
      return null;
    }
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
      dieTypeLabel: _type!.storedLabel,
      madeBy: _madeByController.text.trim(),
      dieMakerId: _dieMakerId,
      poAt: _poAt,
      dateInAt: _dateInAt,
      linerSizeNm: liner.nanometres,
      linerSizeUnit: _linerUnit,
      noOfSet: SheetEngine.parseWhole(_setsController.text),
      numberOfCavities: SheetEngine.parseWhole(_cavityController.text),
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
      _notice = 'Die ${draft.toolCode} will be saved with the part.';
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

    if (_setsProblem != null) {
      setState(() => _error = _setsProblem);
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
      final sent = DieSheetDraft(
        dieId: editing,
        toolCode: code,
        dieType: _type!.slug,
        dieTypeLabel: _type!.storedLabel,
        madeBy: _madeByController.text.trim(),
        dieMakerId: _dieMakerId,
        poAt: _poAt,
        dateInAt: _dateInAt,
        linerSizeNm: liner.nanometres,
        linerSizeUnit: _linerUnit,
        noOfSet: SheetEngine.parseWhole(_setsController.text),
        numberOfCavities: SheetEngine.parseWhole(_cavityController.text),
        storeArea: _storeAreaController.text.trim(),
        rackNo: _rackController.text.trim(),
        partCode: part.partCode,
        partName: part.displayName.trim().isEmpty
            ? part.name
            : part.displayName,
      );
      final outcome = await hook(context, sent);
      if (!mounted) return;
      if (outcome.isCreated && editing != null)
        _rememberCorrection(editing, sent);
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
    // What was just typed is now an answer used before, and its code is taken.
    unawaited(_loadSuggestions());
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

  /// "for part HH1" — which part this row belongs to, on the phone.
  String? get _photoNote {
    final code = widget.partCode.trim();
    final label = code.isNotEmpty ? code : widget.partLabel.trim();
    return label.isEmpty ? null : 'for part $label';
  }

  @override
  Widget build(BuildContext context) {
    _reportDirty();
    _reportType();
    final part = widget.part;
    // Open with no part: everything Add does is held until the part is made.
    final enabled = !widget.busy && !_saving;
    final editing = _editingDieId;
    final holding = part == null;

    return Container(
      padding: widget.framed ? const EdgeInsets.all(14) : EdgeInsets.zero,
      decoration: widget.framed
          ? BoxDecoration(
              color: SoftErpTheme.cardSurface,
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
              border: Border.all(color: SoftErpTheme.border),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onHeading == null) ...[
            Text(
              _heading(editing),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: SoftErpTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
          ] else
            _reportHeading(_chipHeading(editing)),
          if (AppFlowHooks.createDieFromSheet == null)
            const Text(
              'Dies cannot be made from here in this build.',
              style: TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
            )
          else ...[
            // One tab per die — held ones, then the part's own — round the
            // one form that edits the open tab; + opens a blank die.
            _dieTabs(
              enabled,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _formStep(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _typeRow(enabled),
                        const SizedBox(height: 10),
                        // Each field as wide as what it holds, side by side, wrapping only
                        // when the row is full — not a stack of page-wide bars.
                        Wrap(
                          spacing: 10,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.start,
                          children: [
                            SheetStyle.labelled(
                              label: 'Die Code',
                              child: FitToText(
                                controller: _codeController,
                                heading: 'Die Code',
                                helper: _codeHelper(),
                                minWidth: 180,
                                child: TextField(
                                  key: const ValueKey<String>(
                                    'quick-entry-die-code-field',
                                  ),
                                  controller: _codeController,
                                  enabled: enabled,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  onChanged: (_) =>
                                      setState(() => _codePinned = true),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  decoration: SheetStyle.field(
                                    helper: _codeHelper(),
                                  ),
                                ),
                              ),
                            ),
                            SheetStyle.labelled(
                              label: 'Die Made By',
                              child: FitToText(
                                dropdown: true,
                                controller: _madeByController,
                                heading: 'Die Made By',
                                helper:
                                    'Whoever cut it — a fitter here, or an outside toolroom',
                                minWidth: 240,
                                chrome:
                                    84, // padding, the arrow (48), the border
                                child: _madeByField(enabled),
                              ),
                            ),
                            SheetStyle.labelled(
                              label: 'Liner Size',
                              // As wide as the figure, beside its unit picker.
                              // The figure is a dropdown: its padding, arrow
                              // and border (84, as Die Made By) — with 30 for
                              // padding alone a typed 45.8 showed as "4…" (user,
                              // 2026-11-24).
                              child: FitToText(
                                dropdown: true,
                                controller: _linerController,
                                texts: const ['0.000'],
                                chrome: 84 + 8 + unitPickerWidth,
                                minWidth: 200,
                                maxWidth: 360,
                                child: LengthUnitField(
                                  fieldKey: const ValueKey<String>(
                                    'quick-entry-die-liner-field',
                                  ),
                                  unitKey: const ValueKey<String>(
                                    'quick-entry-die-liner-unit',
                                  ),
                                  controller: _linerController,
                                  unitSymbol: _linerUnit,
                                  enabled: enabled,
                                  label: 'Liner Size',
                                  floatLabel: false,
                                  helperText: 'Optional',
                                  decoration: SheetStyle.field(),
                                  errorText: _linerError,
                                  suggestions: _linerSuggestions,
                                  onUnitChanged: (symbol) => setState(() {
                                    _linerUnit = symbol;
                                    _linerError = null;
                                  }),
                                  onChanged: () =>
                                      setState(() => _linerError = null),
                                ),
                              ),
                            ),
                            // How many sets, and the pieces each makes a stroke: one pair.
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _pick(
                                  slug: 'sets',
                                  label: 'No. of Sets',
                                  controller: _setsController,
                                  options: _suggestions.noOfSets,
                                  enabled: enabled,
                                  numeric: true,
                                ),
                                const SizedBox(width: 10),
                                _pick(
                                  slug: 'cavity',
                                  label: 'Cavity',
                                  controller: _cavityController,
                                  options: _suggestions.cavities,
                                  enabled: enabled,
                                  numeric: true,
                                ),
                              ],
                            ),
                            // Where the die is kept reads as one place — area, then
                            // rack — so the two never wrap apart.
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _pick(
                                  slug: 'area',
                                  label: 'Store Area',
                                  controller: _storeAreaController,
                                  options: _suggestions.storeAreas,
                                  enabled: enabled,
                                ),
                                const SizedBox(width: 10),
                                _pick(
                                  slug: 'rack',
                                  label: 'Rack No.',
                                  controller: _rackController,
                                  options: _suggestions.rackNos,
                                  enabled: enabled,
                                ),
                              ],
                            ),
                            // The paper sheet calls these "PO-Date" and "Date in", which
                            // name the columns without saying what they are: the first is
                            // when the die was ORDERED from the maker, the second when the
                            // made die ARRIVED.
                            _momentField(
                              slug: 'po',
                              label: 'Ordered (PO)',
                              value: _poAt,
                              enabled: enabled,
                              onPicked: (value) =>
                                  setState(() => _poAt = value),
                              onCleared: () => setState(() => _poAt = null),
                            ),
                            SaveRowAnchorMark(
                              anchor: _lastFieldAnchor,
                              child: _momentField(
                                slug: 'date-in',
                                label: 'Arrived',
                                value: _dateInAt,
                                enabled: enabled,
                                onPicked: (value) =>
                                    setState(() => _dateInAt = value),
                                onCleared: () =>
                                    setState(() => _dateInAt = null),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: SoftErpTheme.warningText,
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
                ],
              ),
              SheetStep.noTab(
                SheetSaveRow(
                  // Up on the last line of fields when there is room.
                  shrinkWrap: true,
                  // At the sheet's save column, under Save Part.
                  children: [
                    // While any die is held, the part's own Save part sits here
                    // (it was in each held die's row): saving the part writes
                    // the held dies with it.
                    if (widget.staged.isNotEmpty &&
                        widget.heldSaveBuilder != null) ...[
                      widget.heldSaveBuilder!(
                        _editingStagedIndex != null &&
                                _editingStagedIndex! < widget.staged.length
                            ? _editingStagedIndex!
                            : 0,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (editing != null || _editingStagedIndex != null)
                      SheetActionButton(
                        buttonKey: const ValueKey<String>(
                          'quick-entry-die-cancel',
                        ),
                        label: 'Cancel',
                        icon: Icons.close_rounded,
                        onPressed: enabled ? () => setState(_resetSheet) : null,
                      ),
                    const SizedBox(width: 8),
                    SheetSaveButton(
                      buttonKey: const ValueKey<String>('quick-entry-add-die'),
                      // One label in every state (owner, 2026-11-25: "instead of
                      // Add die … show Save Die"); what the save does when
                      // there is no part yet, or when it links one on file, is
                      // in the tooltip.
                      label: 'Save Die',
                      tooltip: _unlinkedDieId != null
                          ? 'Attaches this die to the part'
                          : (holding &&
                                    editing == null &&
                                    _editingStagedIndex == null
                                ? 'Kept with the part: written when the part is saved'
                                : null),
                      isLoading: _saving,
                      onPressed: enabled ? _saveDie : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  final PartTabColors _tabColors = PartTabColors(offset: 1);

  /// The last field and the photo, for the save row to go beside the one
  /// without landing on the other.
  final SaveRowAnchor _lastFieldAnchor = SaveRowAnchor();
  final SaveRowAnchor _photoAnchor = SaveRowAnchor();
  final Object _newTabKey = Object();

  /// The dies as tabs round [form]: held ones first (what this screen is
  /// about to write), then the part's, then "New die" while the form is blank.
  /// [actions] is the save row: under the photo column too, not beside
  /// it, so Save Die ends at the sheet's save column with Save Company
  /// and Save Part (owner, 2026-11-25).
  Widget _dieTabs(bool enabled, Widget form, Widget actions) {
    final staged = widget.staged;
    final held =
        _editingStagedIndex != null && _editingStagedIndex! < staged.length
        ? _editingStagedIndex
        : null;
    final savedAt = _editingDieId == null
        ? -1
        : _dies.indexWhere((d) => d.id == _editingDieId);
    final blank = held == null && savedAt < 0;
    const busy = 'Busy — one moment';
    String titleOf(String code, String fallback) =>
        code.trim().isEmpty ? fallback : code.trim();
    final tabs = <TabSpec>[
      for (var i = 0; i < staged.length; i += 1)
        TabSpec(
          key: staged[i],
          title: titleOf(staged[i].toolCode, 'Held die ${i + 1}'),
          code:
              DieTypeChoice.fromStored(
                staged[i].dieType,
                staged[i].dieTypeLabel,
              )?.label ??
              '',
          closeWhy: enabled ? null : busy,
          closeTip: 'Drop this held die — nothing was written for it',
          keyName: 'die_tab_held_$i',
        ),
      for (final die in _dies)
        TabSpec(
          key: 'die:${die.id}',
          title: titleOf(die.toolCode, 'Die ${die.id}'),
          code:
              DieTypeChoice.fromStored(die.dieType, die.dieTypeLabel)?.label ??
              '',
          saved: true,
          closeWhy: enabled ? null : busy,
          closeTip: 'Take off this part — the die stays in the dies master',
          keyName: 'die_tab_${die.id}',
        ),
      if (blank)
        TabSpec(
          key: _newTabKey,
          title: titleOf(_codeController.text, 'New die'),
          closeWhy: staged.isEmpty && _dies.isEmpty
              ? 'The part has no other die to show'
              : null,
          closeTip: 'Close the new die without keeping it',
          keyName: 'die_tab_new',
        ),
    ];
    final selected =
        held ?? (savedAt >= 0 ? staged.length + savedAt : tabs.length - 1);
    void open(int i) {
      if (i < staged.length) {
        _editStaged(i);
      } else if (i < staged.length + _dies.length) {
        _editDie(_dies[i - staged.length]);
      }
    }

    return ColouredTabs(
      strip: TabList(
        tabs: tabs,
        selected: selected,
        onSelect: (i) {
          if (enabled) open(i);
        },
      ),
      colors: _tabColors,
      noun: 'die',
      plural: 'dies',
      keyPrefix: 'die',
      addWhy: !enabled ? busy : (blank ? 'The new die is open below' : null),
      onAdd: () => setState(() => _resetSheet(keepRepeating: false)),
      onClose: (i) async {
        if (i < staged.length) {
          widget.onUnstage(i);
        } else if (i < staged.length + _dies.length) {
          await _unlink(_dies[i - staged.length]);
        } else {
          open(0);
        }
      },
      // The die's photos in the column at the right, as the part's are on
      // its line (user, 2026-11-24).
      child: Padding(
        padding: SheetSaveRow.framedPadding,
        child: TuckedSaveRow(
          anchor: _lastFieldAnchor,
          avoid: [_photoAnchor],
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: form),
              if (MiniPhoto.isAvailable(context)) ...[
                const SizedBox(width: 16),
                SaveRowAnchorMark(
                  anchor: _photoAnchor,
                  child: SheetStep.noTab(_diePhotoTile()),
                ),
              ],
            ],
          ),
          actions: actions,
        ),
      ),
    );
  }

  /// The open die's photos — up to five, in its own gallery. A die not in
  /// the master yet (held, or new) has nowhere to keep them: drawn, with why.
  Widget _diePhotoTile() {
    final id = _editingDieId;
    final die = id == null ? null : _dies.where((d) => d.id == id).firstOrNull;
    final name = die == null
        ? 'this die'
        : (die.toolCode.trim().isEmpty ? 'Die ${die.id}' : die.toolCode.trim());
    return MiniPhoto(
      key: ValueKey<String>('die_photos_${die?.id ?? 'unsaved'}'),
      owner: PhotoOwner.die,
      id: die?.id,
      size: _kPhotoSize,
      label: 'Die photos',
      what: 'die photo',
      note: _photoNote,
      fallbackUrl: die?.photoUrl,
      disabledReason: _editingStagedIndex != null
          ? 'Held for the part — save the part, then add this die’s photos'
          : 'Save the die, then add its photos',
      onOpen: die == null
          ? null
          : () => showDiePhotoGallery(context, dieId: die.id, dieName: name),
    );
  }

  /// Liner sizes used before, read in the unit picked now — so switching to
  /// inches re-lists the same sizes in inches rather than offering mm figures.
  List<String> get _linerSuggestions {
    final seen = <String>{};
    return [
      for (final nm in _suggestions.linerSizesNm)
        if (seen.add(formatLengthFromNanometres(nm, _linerUnit)))
          formatLengthFromNanometres(nm, _linerUnit),
    ];
  }

  /// One pick-or-type field, as wide as its label and longest answer — the
  /// machine sheet's, so the two sheets beside a part read the same.
  Widget _pick({
    required String slug,
    required String label,
    required TextEditingController controller,
    required List<String> options,
    required bool enabled,
    bool numeric = false,
  }) {
    return SheetStyle.labelled(
      label: label,
      child: FitToText(
        dropdown: true,
        controller: controller,
        // As wide as what is in it (or its heading), not as its longest
        // suggestion: "4" under "No. Of Sets" was a 140 px box.
        heading: label,
        minWidth: numeric ? 80 : 120,
        chrome: 84, // padding, the arrow (48), the border
        child: PickOrTypeField(
          fieldKey: ValueKey<String>('quick-entry-die-$slug-field'),
          controller: controller,
          label: label,
          floatLabel: false,
          options: options,
          enabled: enabled,
          searchKeyboardType: numeric ? TextInputType.number : null,
          decoration: SheetStyle.field(),
          onChanged: () => setState(() {}),
        ),
      ),
    );
  }

  ({String label, String? value})? _reportedHeading;

  String? _reportedType;

  /// Hands the type to [PartDieSection.onTypeChanged] once it has changed —
  /// after the frame, since the host rebuilds on it.
  void _reportType() {
    final report = widget.onTypeChanged;
    final type = _type?.label ?? '';
    if (report == null || type == _reportedType) return;
    _reportedType = type;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) report(type);
    });
  }

  /// Hands [heading] to [PartDieSection.onHeading] once it has changed — after
  /// the frame, since the host's title bar is already built by then.
  Widget _reportHeading(({String label, String? value}) heading) {
    final report = widget.onHeading;
    if (report != null && heading != _reportedHeading) {
      _reportedHeading = heading;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) report(heading);
      });
    }
    return const SizedBox.shrink();
  }

  /// [_heading] for a title bar: the words, then the code they are about.
  ({String label, String? value}) _chipHeading(String? editing) {
    final partCode = widget.partCode.isEmpty ? null : widget.partCode;
    if (widget.part == null)
      return (label: 'Item part code: ', value: partCode);
    if (editing == null)
      return (label: 'New die for part code: ', value: partCode);
    final code = _codeController.text.trim();
    return code.isEmpty
        ? (label: 'Die for part code: ', value: partCode)
        : (label: 'Editing die: ', value: code);
  }

  String _heading(String? editing) {
    final label = widget.partCode.isNotEmpty
        ? widget.partCode
        : (widget.partLabel.isNotEmpty ? widget.partLabel : 'this part');
    if (widget.part == null) return 'Dies for $label — not saved yet';
    if (editing == null) return 'New die for $label';
    final code = _codeController.text.trim();
    return code.isEmpty ? 'Die for $label' : 'Die $code';
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

  /// Asks for a die type in the shop's own words.
  ///
  /// The four built-ins are the common ones, not the only ones — a press shop
  /// runs deep drawing, coining and forming dies too, and before this the only
  /// way to record one was to file it under a type it is not. Typing the name
  /// of a built-in gives the built-in rather than a second one that reads the
  /// same, which `DieTypeChoice.custom` enforces.
  Future<void> _askForCustomType() async {
    final typed = await showDialog<String>(
      context: context,
      builder: (_) => const _CustomDieTypeDialog(),
    );
    if (!mounted || typed == null) return;

    final choice = DieTypeChoice.custom(typed);
    if (choice == null) return;
    setState(() {
      _type = choice;
      _rederiveCode();
    });
  }

  /// The die form as one keyboard step: Type, Die Code, Die Made By, Liner,
  /// Sets, Store Area, Rack No., the two dates — then "Add this die?".
  Widget _formStep(Widget fields) {
    Future<bool> save() async {
      await _saveDie();
      return mounted && _error == null && _linerError == null && !_hasTyped;
    }

    return SheetStep(
      flow: widget.flow,
      id: PartDieSection.step,
      actions: SheetStepActions(
        title: () => 'Save this die?',
        isDirty: () => _hasTyped,
        blockedReason: () {
          if (_type == null) return 'Pick a type — the code is built from it.';
          return _setsProblem;
        },
        save: save,
        discard: () => setState(() => _resetSheet(keepRepeating: false)),
        // Another die for the same part: the form clears and Type takes focus.
        saveAndAddAnother: () async {
          if (await save()) widget.flow?.focusStep(PartDieSection.step);
        },
      ),
      child: fields,
    );
  }

  /// The type as one Tab stop: ← → move the choice through the four built
  /// in types. The chips stay clickable; a typed type is added with the mouse.
  Widget _typeRow(bool enabled) {
    return Focus(
      key: const ValueKey<String>('quick-entry-die-type'),
      canRequestFocus: enabled,
      onKeyEvent: (node, event) {
        if (!enabled || event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        final step = key == LogicalKeyboardKey.arrowRight
            ? 1
            : key == LogicalKeyboardKey.arrowLeft
            ? -1
            : 0;
        if (step == 0) return KeyEventResult.ignored;
        const types = DieType.values;
        final at = types.indexWhere((t) => t.slug == _type?.slug);
        final next = at < 0
            ? (step > 0 ? 0 : types.length - 1)
            : (at + step) % types.length;
        setState(() {
          _type = DieTypeChoice.of(types[next]);
          _rederiveCode();
        });
        return KeyEventResult.handled;
      },
      child: Builder(
        builder: (context) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusControl),
            border: Border.all(
              color: Focus.of(context).hasFocus
                  ? SoftErpTheme.accent
                  : Colors.transparent,
              width: 1.6,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: SheetStep.noTab(_typeChips(enabled)),
          ),
        ),
      ),
    );
  }

  Widget _typeChips(bool enabled) {
    // A heading over its choices, as every field on the sheet has.
    return SheetStyle.labelled(
      label: 'Type',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final type in DieType.values)
            ChoiceChip(
              label: Text(type.label, style: const TextStyle(fontSize: 14)),
              selected: _type?.slug == type.slug,
              onSelected: !enabled
                  ? null
                  : (selected) => setState(() {
                      _type = selected ? DieTypeChoice.of(type) : null;
                      _rederiveCode();
                    }),
            ),

          // Types typed on earlier dies, so "Deep Drawing" is typed once
          // and picked after that — not retyped, and not spelt two ways.
          for (final typed in _suggestions.typedTypes)
            if (_type?.slug != typed.slug)
              ChoiceChip(
                key: ValueKey<String>(
                  'quick-entry-die-used-type-${typed.slug}',
                ),
                label: Text(typed.label, style: const TextStyle(fontSize: 14)),
                selected: false,
                onSelected: !enabled
                    ? null
                    : (_) => setState(() {
                        _type = DieTypeChoice.fromStored(
                          typed.slug,
                          typed.label,
                        );
                        _rederiveCode();
                      }),
              ),

          // The one the shop typed, shown as a chip beside the built-ins
          // so it reads as what it is: a type on the same footing, not an
          // "other" bucket. Tapping it re-opens the words for editing.
          if (_type != null && !_type!.builtIn)
            InputChip(
              key: const ValueKey<String>('quick-entry-die-custom-type'),
              label: Text(_type!.label, style: const TextStyle(fontSize: 14)),
              selected: true,
              onSelected: enabled ? (_) => _askForCustomType() : null,
              onDeleted: !enabled
                  ? null
                  : () => setState(() {
                      _type = null;
                      _rederiveCode();
                    }),
            ),

          ActionChip(
            key: const ValueKey<String>('quick-entry-die-add-type'),
            avatar: const Icon(Icons.add_rounded, size: 16),
            label: Text(
              _type != null && !_type!.builtIn ? 'Change type' : 'Add type',
              style: const TextStyle(fontSize: 14),
            ),
            onPressed: enabled ? _askForCustomType : null,
          ),
        ],
      ),
    );
  }

  /// Who made this die, from the die maker master.
  ///
  /// This was a plain text field with up to five "names used before" chips
  /// (migration 048: "the useful half of a master without the maintenance").
  /// The shop reversed that call. What the chips could not do is tell you the
  /// toolroom's number when a die is late, which is the point of the master.
  ///
  /// The free text still rides along. A die whose maker was never a record
  /// keeps its typed name and shows it here as an unresolved option, so
  /// nothing that exists today reads as blank — and picking a real maker is
  /// how those dies get attached over time, one at a time, by hand.
  Widget _madeByField(bool enabled) {
    final provider = _dieMakers;
    if (provider == null) {
      // No master registered — a host that mounts this section without the
      // provider (the older quick-entry dialog, and every widget test that
      // predates this) keeps the field it had rather than losing it.
      return _madeByTextField(enabled);
    }

    return ChangeNotifierProvider<DieMakersProvider>.value(
      value: provider,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Opacity(
          opacity: enabled ? 1 : 0.6,
          child: DieMakerPickerField(
            tapTargetKey: const ValueKey<String>(
              'quick-entry-die-made-by-field',
            ),
            value: _dieMakerId,
            fallbackName: _madeByController.text,
            floatLabel: false,
            decoration: SheetStyle.field(),
            onChanged: (maker) => setState(() {
              _dieMakerId = maker?.id;
              // The text follows the pick so the two never disagree about who
              // made the die. Clearing the pick leaves the words alone — they
              // may be the only record of a fitter's name.
              if (maker != null) _madeByController.text = maker.name;
            }),
          ),
        ),
      ),
    );
  }

  /// The pre-master field, kept for hosts with no die maker provider.
  Widget _madeByTextField(bool enabled) {
    final typed = _madeByController.text.trim().toLowerCase();
    final suggestions = _suggestions.madeBy
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
          decoration: SheetStyle.field(
            helper: 'Whoever cut it — a fitter here, or an outside toolroom',
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
                  label: Text(name, style: const TextStyle(fontSize: 14)),
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

  /// A date and time, as a box like every other field: the date when
  /// picked, "Pick a date" when not, with a × to clear it. It was a row label
  /// and a "Pick" button, unlike anything else on the sheet.
  Widget _momentField({
    required String slug,
    required String label,
    required DateTime? value,
    required bool enabled,
    required ValueChanged<DateTime> onPicked,
    required VoidCallback onCleared,
  }) {
    return SheetStyle.labelled(
      label: label,
      // As wide as the date and time it shows, with its icon or ×.
      child: FitToText(
        texts: [value == null ? 'Pick a date' : partStamp(value)],
        chrome: 30 + 44,
        minWidth: 150,
        maxWidth: 260,
        child: InkWell(
          key: ValueKey<String>('quick-entry-die-$slug-field'),
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusControl),
          onTap: enabled
              ? () => _pickMoment(current: value, onPicked: onPicked)
              : null,
          child: InputDecorator(
            isEmpty: false,
            decoration: SheetStyle.field(
              suffixIcon: enabled && value != null
                  ? IconButton(
                      tooltip: 'Clear $label',
                      onPressed: onCleared,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    )
                  : const Icon(
                      Icons.event_outlined,
                      size: 18,
                      color: SoftErpTheme.textSecondary,
                    ),
            ),
            child: Text(
              // Always through partStamp: the instant is stored in UTC and a
              // shop at +05:30 must not read 11.30 AM as 6.00 AM.
              value == null ? 'Pick a date' : partStamp(value),
              style: value == null
                  ? SheetStyle.muted
                  : const TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
    );
  }
}

/// The die photo tile's side, in the column at the right of its form.
const double _kPhotoSize = 132;

/// Asks for a die type in the shop's own words.
///
/// A `StatefulWidget` rather than a `StatefulBuilder` because of the text
/// controller: a dialog keeps rebuilding through its exit transition, so
/// disposing a controller on the line after `await showDialog` adds a listener
/// to a dead object — which surfaces as a six-figure RenderFlex overflow that
/// names nothing. Owning it here ties its life to the route's.
class _CustomDieTypeDialog extends StatefulWidget {
  const _CustomDieTypeDialog();

  @override
  State<_CustomDieTypeDialog> createState() => _CustomDieTypeDialogState();
}

class _CustomDieTypeDialogState extends State<_CustomDieTypeDialog> {
  final TextEditingController _words = TextEditingController();

  @override
  void dispose() {
    _words.dispose();
    super.dispose();
  }

  void _submit() {
    final typed = _words.text.trim();
    if (typed.isEmpty) return;
    Navigator.of(context).pop(typed);
  }

  @override
  Widget build(BuildContext context) {
    final preview = DieTypeChoice.custom(_words.text);
    return AlertDialog(
      title: const Text(
        'Name the die type',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cutting, bending, riveting and assembly are already here. '
              'Anything else the press runs — deep drawing, coining, forming '
              '— goes in as the words you use for it.',
              style: TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey<String>('quick-entry-die-type-input'),
              controller: _words,
              autofocus: true,
              style: const TextStyle(fontSize: 15),
              decoration: SheetStyle.field(
                label: 'Die type',
                hint: 'Deep Drawing, Coining, Forming…',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            // The code is built from the type's initials, so showing it is
            // showing the consequence rather than describing it.
            Text(
              preview == null
                  ? 'The die code is built from the first letter of each word.'
                  : 'A die of this type is coded '
                        '${partCodeInitials(preview.label)}D + the part code.',
              style: const TextStyle(
                fontSize: 13,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(fontSize: 14)),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Use this type', style: TextStyle(fontSize: 14)),
        ),
      ],
    );
  }
}

/// A held draft, shaped like a linked die so one row (or one summary line)
/// describes both.
ItemDieLink heldDieLink(DieSheetDraft draft) => ItemDieLink(
  id: '',
  toolCode: draft.toolCode,
  dieType: draft.dieType,
  dieTypeLabel: draft.dieTypeLabel,
  madeBy: draft.madeBy,
  poAt: draft.poAt,
  dateInAt: draft.dateInAt,
  linerSizeNm: draft.linerSizeNm,
  linerSizeUnit: draft.linerSizeUnit,
  noOfSet: draft.noOfSet,
  numberOfCavities: draft.numberOfCavities,
  storeArea: draft.storeArea,
  rackNo: draft.rackNo,
);
