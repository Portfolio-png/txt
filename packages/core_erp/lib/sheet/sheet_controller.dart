import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'column_def.dart';
import 'column_option.dart';
import 'sheet_def.dart';
import 'sheet_draft.dart';
import 'sheet_engine.dart';
import 'sheet_binding.dart';

class SheetController extends ChangeNotifier {
  SheetController({
    required SheetDef sheetDef,
    SheetDraft? initialDraft,
    List<SheetDraft>? initialDrafts,
    List<ColumnOption>? options,
    List<Party>? parties,
    List<Contact>? contacts,
    Map<String, int>? counters,
    Set<String>? existingCodes,
    Set<String>? existingPaths,
  }) : _sheetDef = sheetDef,
       _drafts = _seedDrafts(sheetDef, initialDraft, initialDrafts),
       _options = List<ColumnOption>.from(options ?? []),
       _parties = List<Party>.from(parties ?? []),
       _contacts = List<Contact>.from(contacts ?? []),
       _counters = Map<String, int>.from(counters ?? {}),
       _existingCodes = Set<String>.from(existingCodes ?? {}),
       _existingPaths = Set<String>.from(existingPaths ?? {}) {
    _deriveAndValidate();
  }

  /// There is always at least one row, so `draft` never has to be nullable.
  ///
  /// This used to be a single `final SheetDraft`. The widgets rendered extra
  /// rows from a `rowDrafts` list passed in from outside, but every write went
  /// to the one shared draft whatever row was clicked — so typing in a cell and
  /// then selecting another row silently discarded the edit. Rows live here
  /// now, and the cursor decides which one a write lands on.
  static List<SheetDraft> _seedDrafts(
    SheetDef sheetDef,
    SheetDraft? single,
    List<SheetDraft>? many,
  ) {
    if (many != null && many.isNotEmpty) return List<SheetDraft>.from(many);
    return [single ?? SheetDraft(sheetKey: sheetDef.key)];
  }

  SheetDef _sheetDef;
  final List<SheetDraft> _drafts;
  final List<ColumnOption> _options;
  final List<Party> _parties;
  final List<Contact> _contacts;
  final Map<String, int> _counters;
  final Set<String> _existingCodes;
  final Set<String> _existingPaths;

  /// The cursor: which row and which column a write lands on.
  ///
  /// These were two half-cursors that could never be set together — the column
  /// lived here and was sheet-global, while the row lived in the parent widget
  /// as `selectedRowIndex`. A cell is one place; it is one pair.
  int _row = 0;
  int? _focusedColumnId;

  bool _isHeaderFocused = false;

  /// Keyed by row, then by column. `errors` answers for the selected row so
  /// every existing reader keeps meaning what it meant.
  Map<int, Map<int, ValidationError>> _errorsByRow = {};
  String? _lastActionResult;

  SheetDef get sheetDef => _sheetDef;

  /// The selected row's draft. Unchanged in meaning for every caller that had
  /// only one row to begin with.
  SheetDraft get draft => _drafts[_row];

  List<SheetDraft> get drafts => List.unmodifiable(_drafts);
  int get rowCount => _drafts.length;
  int get row => _row;

  SheetDraft draftAt(int row) =>
      row >= 0 && row < _drafts.length ? _drafts[row] : _drafts[_row];

  /// Where [draft] sits now, by identity, or -1 once it has been removed.
  ///
  /// A save captures its row's draft and looks it up again afterwards: the
  /// index it started with can point at a different row by then (Remove, or a
  /// reload), and stamping the saved id onto THAT row made its next edit
  /// overwrite somebody else's part.
  int indexOfDraft(SheetDraft draft) {
    for (var i = 0; i < _drafts.length; i += 1) {
      if (identical(_drafts[i], draft)) return i;
    }
    return -1;
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    // A save that finishes after the screen closed still reports back; that
    // must not throw "used after being disposed".
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  List<ColumnOption> get options => List.unmodifiable(_options);
  List<Party> get parties => List.unmodifiable(_parties);
  List<Contact> get contacts => List.unmodifiable(_contacts);
  int? get focusedColumnId => _focusedColumnId;
  bool get isHeaderFocused => _isHeaderFocused;
  Map<int, ValidationError> get errors =>
      Map.unmodifiable(_errorsByRow[_row] ?? const {});

  Map<int, ValidationError> errorsForRow(int row) =>
      Map.unmodifiable(_errorsByRow[row] ?? const {});

  /// Every row's errors, for a save that must refuse the whole sheet.
  int get errorCount =>
      _errorsByRow.values.fold<int>(0, (sum, row) => sum + row.length);
  String? get lastActionResult => _lastActionResult;

  /// Called with the row the cursor just left.
  ///
  /// The hook a host commits on. Set here rather than wired to one widget's
  /// callback because the cursor leaves a row by **three** routes — clicking
  /// another row, Tab or Enter running past the end of this one, and Add row —
  /// and a host that only heard about the first silently skipped the other two.
  /// That was visible in an e2e run where the first row still read NEW RECORD
  /// after Add row had moved on from it.
  ValueChanged<int>? onRowLeft;

  /// The one place the cursor's row changes.
  void _setRow(int next) {
    final clamped = next.clamp(0, _drafts.length - 1);
    if (clamped == _row) return;
    final left = _row;
    _row = clamped;
    onRowLeft?.call(left);
  }

  void focusCell(int columnId, {bool isHeader = false, int? row}) {
    if (row != null) _setRow(row);
    _focusedColumnId = columnId;
    _isHeaderFocused = isHeader;
    notifyListeners();
  }

  /// Moves the cursor to a row without changing which column is focused.
  void selectRow(int row) {
    final next = row.clamp(0, _drafts.length - 1);
    if (next == _row) return;
    _setRow(next);
    notifyListeners();
  }

  /// Rows that are saved and closed: shown as they are, but they take no
  /// input until their Edit is pressed. Keyed by row index, kept in step when
  /// a row is removed.
  final Set<int> _lockedRows = <int>{};

  bool isRowLocked(int row) => _lockedRows.contains(row);

  /// Closes [row] for editing (its Save landed) or opens it again (its Edit).
  void setRowLocked(int row, bool locked) {
    final changed = locked ? _lockedRows.add(row) : _lockedRows.remove(row);
    if (changed) notifyListeners();
  }

  /// Whether Enter past the last cell may append a row. False for a sheet
  /// that is one record by nature — the development deal is one per part, and
  /// a second deal row would be typed into and silently never saved.
  bool canAddRows = true;

  /// Appends an empty row and selects it.
  int addRow({SheetDraft? draft}) {
    _drafts.add(draft ?? SheetDraft(sheetKey: _sheetDef.key));
    _setRow(_drafts.length - 1);
    _deriveAndValidate();
    notifyListeners();
    return _row;
  }

  /// Removes a row. The last one is never removed — a sheet with no rows has
  /// nowhere to type.
  void removeRow(int row) {
    if (_drafts.length <= 1 || row < 0 || row >= _drafts.length) return;
    _drafts.removeAt(row);
    // Rows below the removed one move up a place, and so do their locks.
    final shifted = {
      for (final locked in _lockedRows)
        if (locked != row) locked > row ? locked - 1 : locked,
    };
    _lockedRows
      ..clear()
      ..addAll(shifted);
    if (_row >= _drafts.length) _row = _drafts.length - 1;
    _deriveAndValidate();
    notifyListeners();
  }

  /// Replaces every row, for a load. Keeps the cursor in range.
  void replaceRows(List<SheetDraft> rows) {
    _lockedRows.clear();
    _drafts
      ..clear()
      ..addAll(rows.isEmpty ? [SheetDraft(sheetKey: _sheetDef.key)] : rows);
    _row = _row.clamp(0, _drafts.length - 1);
    _deriveAndValidate();
    notifyListeners();
  }

  /// Swaps in the options, parties and uniqueness sets a sheet picks from.
  ///
  /// These were constructor-only, which meant the only way to get real pickers
  /// was to build the controller after the providers had loaded. A sheet opens
  /// before its reference data arrives, so it has to be able to take it late.
  void applyReferenceData(SheetReferenceData data) {
    // Options the user minted here and has not saved yet are their unsaved
    // work, not the server's list — a refresh must not take them away. Without
    // this, reference data arriving late (or an item save, which notifies the
    // provider) wiped a typed-new value's option and validation then called it
    // "not a part name under this path".
    final minted = [
      for (final option in _options)
        if (option.isNew) option,
    ];
    _optionIndex = null;
    _options
      ..clear()
      ..addAll(data.options)
      ..addAll(
        minted.where(
          (m) => !data.options.any(
            (o) =>
                o.columnId == m.columnId &&
                o.label.toLowerCase() == m.label.toLowerCase(),
          ),
        ),
      );
    _parties
      ..clear()
      ..addAll(data.parties);
    _contacts
      ..clear()
      ..addAll(data.contacts);
    _counters
      ..clear()
      ..addAll(data.counters);
    _existingCodes
      ..clear()
      ..addAll(data.existingCodes);
    _existingPaths
      ..clear()
      ..addAll(data.existingPaths);
    _forgetOwnIdentities();
    _deriveAndValidate();
    notifyListeners();
  }

  /// Loads rows that are **existing records** rather than new ones.
  ///
  /// Distinct from [replaceRows] because of one trap: `existingCodes` and
  /// `existingPaths` come from the live table, so a part loaded for editing is
  /// in them — and the row would be flagged as colliding with itself, on a
  /// sheet the user has not touched. Loading a record withdraws its own code
  /// and path from the taken sets.
  void loadRecords(List<SheetDraft> rows) {
    _drafts
      ..clear()
      ..addAll(rows.isEmpty ? [SheetDraft(sheetKey: _sheetDef.key)] : rows);
    // A record as loaded has no unsaved changes — without this every loaded
    // row read as edited, so a save re-wrote untouched parts and a change
    // made elsewhere was never shown in them.
    for (final draft in _drafts) {
      if (draft.entityId != null) draft.markClean();
    }
    // Records come in saved, so they come in closed — Edit opens one.
    _lockedRows
      ..clear()
      ..addAll([
        for (var i = 0; i < _drafts.length; i += 1)
          if (_drafts[i].entityId != null) i,
      ]);
    _row = _row.clamp(0, _drafts.length - 1);
    _forgetOwnIdentities();
    _deriveAndValidate();
    notifyListeners();
  }

  /// True when no reference data has arrived at all.
  ///
  /// Lets a dropdown tell "the masters have not loaded" apart from "nothing
  /// has ever been entered here", which are different problems with different
  /// next actions.
  bool get isReferenceDataEmpty =>
      _options.isEmpty && _parties.isEmpty && _contacts.isEmpty;

  /// Picks a contact into [columnId] and fills the columns it projects into.
  ///
  /// A contact column is the only cell on the sheet whose choice fills others:
  /// designation, phone and email are **read-only projections** of the chosen
  /// person, resolved server-side on every read, so the sheet shows them and
  /// never writes them.
  ///
  /// This existed as `ItemMasterController.pickContact` and **nothing in the
  /// app called it** — the cell wrote the name with `updateValue` and the three
  /// columns beside it stayed blank. Keyed off `bindsTo` rather than column ids
  /// so a sheet that leaves one of them out simply has nothing to fill.
  /// Adds a person at a party and answers them. Set by the host from its
  /// binding, the way [onRowLeft] is — a cell cannot see the binding.
  ///
  /// Null means this sheet cannot add people, and the picker then offers only
  /// what is already on file.
  Future<Contact?> Function(int partyId, String name)? onAddContact;

  void applyContact(int columnId, Contact contact, {int? row}) {
    final target = row ?? _row;

    updateValue(
      columnId,
      CellValue(
        columnId: columnId,
        refId: contact.id,
        optionLabel: contact.name,
      ),
      row: target,
    );

    void project(String binds, String? value) {
      final column = _sheetDef.columnBoundTo(binds);
      if (column == null) return;
      updateValue(
        column.id,
        CellValue(columnId: column.id, textValue: value ?? ''),
        row: target,
      );
    }

    project(SheetBindsTo.developedForDesignation, contact.designation);
    project(SheetBindsTo.developedForPhone, contact.phone);
    project(SheetBindsTo.developedForEmail, contact.email);
  }

  /// Copies the cell above [row] in [columnId] into it.
  ///
  /// Twenty parts in a group share an alloy, a gauge and a finish, so this is
  /// the single biggest saving available to somebody typing a catalogue. Does
  /// nothing on the first row, on a derived cell (which computes itself) or on
  /// a saved row (whose values are the server's).
  bool fillDown(int columnId, {int? row}) {
    final target = (row ?? _row).clamp(0, _drafts.length - 1);
    if (target == 0) return false;
    if (_drafts[target].entityId != null) return false;

    final column = _sheetDef.getColumn(columnId);
    if (column == null) return false;
    if (column.kind == ColumnKind.seq ||
        column.kind == ColumnKind.code ||
        column.isStamp) {
      return false;
    }

    final above = _drafts[target - 1].get(columnId);
    if (above == null || above.isEmpty) return false;

    _drafts[target].set(columnId, above.copyWith(columnId: columnId));
    _deriveAndValidate();
    notifyListeners();
    return true;
  }

  /// Validates one row and answers whether it is clean.
  bool validateRow(int row) {
    _deriveAndValidate();
    notifyListeners();
    return (_errorsByRow[row.clamp(0, _drafts.length - 1)] ?? {}).isEmpty;
  }

  /// The first refusal on [row], in column order, or null when it has none.
  String? firstErrorOn(int row) {
    final errors = _errorsByRow[row.clamp(0, _drafts.length - 1)] ?? {};
    if (errors.isEmpty) return null;
    for (final column in _sheetDef.columns) {
      final error = errors[column.id];
      if (error != null) return error.message;
    }
    return errors.values.first.message;
  }

  /// Records that [row] is now a saved record.
  ///
  /// The write lives here rather than on the draft because the controller owns
  /// the rows — and because a committed row needs three things done together:
  /// it takes the entity's id, its own code and path stop counting as taken
  /// (or it collides with itself), and from now on it is never re-derived.
  ///
  /// [sent] is what the save carried. When the row has been typed into since
  /// — the save took a second or two and the user kept going — it takes the id
  /// but stays dirty and open, so the edit is written next rather than shown
  /// as saved when it never was.
  void markRowSaved(
    int row,
    int entityId, {
    String? partCode,
    String? createdDate,
    String? createdTime,
    Map<int, CellValue>? sent,
  }) {
    if (row < 0 || row >= _drafts.length) return;
    final index = row;
    final current = _drafts[index];
    final editedSince = sent != null && !_sameTyped(sent, current.values);

    final next = SheetDraft(
      sheetKey: current.sheetKey,
      entityId: entityId,
      values: current.values,
      newOptions: current.newOptions,
    );

    if (partCode != null && partCode.trim().isNotEmpty) {
      final column = _sheetDef.columnBoundTo(SheetBindsTo.partCode);
      if (column != null) {
        next.set(
          column.id,
          CellValue(
            columnId: column.id,
            textValue: partCode,
            // The server's answer, not a suggestion — so it is no longer an
            // auto cell and derive will not touch it.
            mode: ValueMode.ok,
          ),
        );
      }
    }

    void stamp(String binds, String? value) {
      if (value == null) return;
      final column = _sheetDef.columnBoundTo(binds);
      if (column == null) return;
      next.set(
        column.id,
        CellValue(columnId: column.id, textValue: value, mode: ValueMode.ok),
      );
    }

    stamp(SheetBindsTo.createdDate, createdDate);
    stamp(SheetBindsTo.createdTime, createdTime);

    if (editedSince) {
      next.markDirty();
    } else {
      next.markClean();
      // Saved, so closed until somebody presses its Edit.
      _lockedRows.add(index);
    }
    _drafts[index] = next;
    _forgetOwnIdentities();
    _deriveAndValidate();
    notifyListeners();
  }

  /// Whether two rows hold the same TYPED values. The derived columns — the
  /// running number and the code — and the stamps are left out: they change
  /// whenever the counters move or the server answers, which is not an edit.
  bool _sameTyped(Map<int, CellValue> a, Map<int, CellValue> b) {
    final keys = {...a.keys, ...b.keys};
    for (final key in keys) {
      final column = _sheetDef.getColumn(key);
      if (column != null &&
          (column.kind == ColumnKind.seq ||
              column.kind == ColumnKind.code ||
              column.isStamp)) {
        continue;
      }
      final x = a[key];
      final y = b[key];
      final xEmpty = x == null || x.isEmpty;
      final yEmpty = y == null || y.isEmpty;
      if (xEmpty && yEmpty) continue;
      if (xEmpty != yEmpty) return false;
      if (x!.optionId != y!.optionId ||
          x.optionLabel != y.optionLabel ||
          x.refId != y.refId ||
          x.textValue != y.textValue ||
          x.intValue != y.intValue) {
        return false;
      }
    }
    return true;
  }

  /// Puts [draft] in place of row [row] — a saved record re-read after it
  /// changed somewhere else. Keeps the row's lock and the cursor where they
  /// are; never call it on a row somebody is editing.
  void replaceRowAt(int row, SheetDraft draft) {
    if (row < 0 || row >= _drafts.length) return;
    draft.markClean();
    _drafts[row] = draft;
    _forgetOwnIdentities();
    _deriveAndValidate();
    notifyListeners();
  }

  /// Rows that have been written, by index.
  Set<int> get savedRows => {
    for (var i = 0; i < _drafts.length; i += 1)
      if (_drafts[i].entityId != null) i,
  };

  /// Whether [row] holds anything at all.
  bool isRowBlank(int row) {
    final draft = draftAt(row);
    for (final value in draft.values.values) {
      if (value.isNotEmpty && value.mode != ValueMode.auto) return false;
    }
    // An auto cell on its own is derived, not typed — a blank row still has a
    // running number in it.
    for (final column in _sheetDef.columns) {
      if (column.kind == ColumnKind.seq || column.kind == ColumnKind.code) {
        continue;
      }
      if (column.isStamp) continue;
      final value = draft.get(column.id);
      if (value != null && value.isNotEmpty) return false;
    }
    return true;
  }

  /// Drops the loaded rows' own codes and paths from the taken sets.
  void _forgetOwnIdentities() {
    final codeColumn = _sheetDef.columnBoundTo(SheetBindsTo.partCode);
    final nameColumn =
        _sheetDef.columnBoundTo(SheetBindsTo.name) ?? _sheetDef.itemColumn;

    for (final draft in _drafts) {
      // Only a SAVED row is the record its own code belongs to. An unsaved row
      // withdrawing its typed code erased a genuine collision with a stored
      // part — and reference data reloads constantly, so it erased it often.
      if (draft.entityId == null) continue;
      if (codeColumn != null) {
        final code = draft.get(codeColumn.id)?.textValue?.trim();
        if (code != null && code.isNotEmpty) {
          _existingCodes.remove(code.toUpperCase());
          _existingCodes.remove(code);
        }
      }
      if (nameColumn != null) {
        final value = draft.get(nameColumn.id);
        final label = value?.optionLabel ?? value?.textValue;
        if (label == null || label.trim().isEmpty) continue;
        final path = SheetEngine.groupPathString(
          _sheetDef,
          draft,
          nameColumn.id,
        );
        final full = path.isEmpty ? label : '$path › $label';
        _existingPaths.remove(full.toLowerCase());
      }
    }
  }

  /// Which row a write lands on: the one named, or the cursor's.
  SheetDraft _draftFor(int? row) => row == null ? _drafts[_row] : draftAt(row);

  void setLastAction(String action) {
    _lastActionResult = action;
    notifyListeners();
  }

  void updateValue(int columnId, CellValue value, {int? row}) {
    _draftFor(row).set(columnId, value);
    _deriveAndValidate();
    notifyListeners();
  }

  void updateTextValue(int columnId, String text, {int? row}) {
    final col = _sheetDef.getColumn(columnId);
    if (col == null) return;

    final target = _draftFor(row);
    final existing = target.get(columnId) ?? CellValue(columnId: columnId);
    // Whole numbers keep their sign and refuse a decimal point (null, which
    // validation names) instead of reading "12.5" as 125. Money keeps the
    // paise in the text and carries intValue only for a whole amount.
    int? parsedInt;
    if (col.kind == ColumnKind.number || col.kind == ColumnKind.seq) {
      parsedInt = SheetEngine.parseWhole(text);
    } else if (col.kind == ColumnKind.money) {
      final amount = SheetEngine.parseMoney(text);
      parsedInt = amount != null && amount == amount.truncateToDouble()
          ? amount.toInt()
          : null;
    }

    final mode = col.kind == ColumnKind.seq || col.kind == ColumnKind.code
        ? ValueMode.edit
        : existing.mode;

    target.set(
      columnId,
      existing.copyWith(
        textValue: text,
        intValue: parsedInt,
        // copyWith keeps the old number when handed null, so "12" then "12.5"
        // would have kept 12.
        clearIntValue: parsedInt == null,
        mode: mode,
      ),
    );

    _deriveAndValidate();
    notifyListeners();
  }

  void setOption(int columnId, ColumnOption option, {int? row}) {
    final target = _draftFor(row);
    final existing = target.get(columnId) ?? CellValue(columnId: columnId);
    target.set(
      columnId,
      existing.copyWith(
        optionId: option.id,
        optionLabel: option.label,
        isNew: option.isNew,
      ),
    );

    SheetEngine.cascade(_sheetDef, target, columnId, _options);
    _deriveAndValidate();
    notifyListeners();
  }

  void addNewOption(int columnId, String label, {int? row}) {
    final col = _sheetDef.getColumn(columnId);
    if (col == null || label.trim().isEmpty) return;

    final target = _draftFor(row);
    final parentOptId = SheetEngine.parentOptionIdFor(
      _sheetDef,
      target,
      columnId,
    );

    final maxId = _options.fold<int>(
      500,
      (prev, o) => o.id > prev ? o.id : prev,
    );
    final newOption = ColumnOption(
      id: maxId + 1,
      columnId: columnId,
      parentOptionId: parentOptId,
      label: label.trim(),
      isNew: true,
      createdAt: DateTime.now().toIso8601String(),
    );

    _options.add(newOption);
    _optionIndex = null;
    target.addNewOption(newOption);

    final existing = target.get(columnId) ?? CellValue(columnId: columnId);
    target.set(
      columnId,
      existing.copyWith(
        optionId: newOption.id,
        optionTmp: 'n${newOption.id}',
        optionLabel: newOption.label,
        isNew: true,
      ),
    );

    _deriveAndValidate();
    _lastActionResult =
        'Added "$label" under ${SheetEngine.groupPathString(_sheetDef, target, columnId)}.';
    notifyListeners();
  }

  void setMode(int columnId, ValueMode mode, {int? row}) {
    final target = _draftFor(row);
    final existing = target.get(columnId) ?? CellValue(columnId: columnId);
    target.set(columnId, existing.copyWith(mode: mode));
    _deriveAndValidate();
    notifyListeners();
  }

  void addColumn({
    required String label,
    required ColumnKind kind,
    int? parentId,
    ColumnSource source = ColumnSource.options,
    int? familyId,
    String? bindsTo,
  }) {
    _sheetDef = _sheetDef.addColumn(
      label: label,
      kind: kind,
      parentId: parentId,
      source: source,
      familyId: familyId,
      bindsTo: bindsTo,
    );
    _lastActionResult = 'Added column "$label".';
    _deriveAndValidate();
    notifyListeners();
  }

  /// Adds a top-level variation property, which is what the Properties table
  /// holds.
  ///
  /// The binding keys off `bindsTo`, so a column added without one would be a
  /// cell that goes nowhere: typed into, saved, and absent from the part.
  void addPropertyColumn(String label, {ColumnKind kind = ColumnKind.list}) {
    final name = label.trim();
    if (name.isEmpty) return;
    addColumn(label: name, kind: kind, bindsTo: SheetBindsTo.variation(name));
  }

  void addSubGroupLevel(String label) {
    _sheetDef = _sheetDef.addSubGroupLevel(label);
    _lastActionResult = 'Added sub-group level "$label".';
    _deriveAndValidate();
    notifyListeners();
  }

  void removeColumn(int columnId) {
    final col = _sheetDef.getColumn(columnId);
    if (col == null) return;
    final (allowed, reason) = _sheetDef.canRemove(columnId);
    if (!allowed) {
      _lastActionResult = reason;
      notifyListeners();
      return;
    }

    _sheetDef = _sheetDef.removeColumn(columnId);
    // Every row, not just the selected one — the column is gone from the sheet.
    for (final draft in _drafts) {
      draft.clear(columnId);
    }
    _lastActionResult = 'Removed column "${col.label}".';
    _deriveAndValidate();
    notifyListeners();
  }

  void moveColumn(int columnId, int delta) {
    final col = _sheetDef.getColumn(columnId);
    if (col == null) return;
    final (allowed, reason) = delta < 0
        ? _sheetDef.canMoveLeft(columnId)
        : _sheetDef.canMoveRight(columnId);

    if (!allowed) {
      _lastActionResult = reason;
      notifyListeners();
      return;
    }

    _sheetDef = _sheetDef.moveColumn(columnId, delta);
    _lastActionResult = 'Moved "${col.label}" ${delta < 0 ? 'left' : 'right'}.';
    notifyListeners();
  }

  void renameColumn(int columnId, String newLabel) {
    if (newLabel.trim().isEmpty) return;
    _sheetDef = _sheetDef.renameColumn(columnId, newLabel.trim());
    _lastActionResult = 'Renamed column to "$newLabel".';
    notifyListeners();
  }

  void reparentColumn(int columnId, int? newParentId) {
    final (allowed, reason) = _sheetDef.canReparent(columnId, newParentId);
    if (!allowed) {
      _lastActionResult = reason;
      notifyListeners();
      return;
    }

    _sheetDef = _sheetDef.reparentColumn(columnId, newParentId);
    final col = _sheetDef.getColumn(columnId);
    _lastActionResult = newParentId == null
        ? '${col?.label} is now in Primary Group.'
        : '${col?.label} now sits under ${_sheetDef.getColumn(newParentId)?.label}.';
    _deriveAndValidate();
    notifyListeners();
  }

  OptionIndex? _optionIndex;
  OptionIndex get _optionLookup => _optionIndex ??= OptionIndex(_options);

  void _deriveAndValidate() {
    final next = <int, Map<int, ValidationError>>{};
    for (final draft in _drafts) {
      SheetEngine.derive(_sheetDef, draft, counters: _counters);
    }
    // A row must not collide with the OTHER rows on screen, not just with
    // what is already stored. Two rows typed to the same code would both
    // look fine and the second would be refused by the unique index on save.
    //
    // Counted once for the whole sheet. This used to copy every stored code
    // and walk every row once PER row, on every keystroke.
    final typed = _typedCodes();
    final counts = <String, int>{};
    for (final code in typed) {
      if (code != null) counts[code] = (counts[code] ?? 0) + 1;
    }
    for (var i = 0; i < _drafts.length; i += 1) {
      final own = typed[i];
      final takenByOthers = own != null && (counts[own] ?? 0) > 1;
      next[i] = SheetEngine.validate(
        _sheetDef,
        _drafts[i],
        allOptions: _options,
        parties: _parties,
        contacts: _contacts,
        counters: _counters,
        existingCodes: takenByOthers
            ? _CodesWith(_existingCodes, own)
            : _existingCodes,
        existingPaths: _existingPaths,
        optionIndex: _optionLookup,
      );
    }
    _errorsByRow = next;
  }

  /// Each row's TYPED code, upper-cased, or null.
  ///
  /// Derived previews are identical across rows under one group, so counting
  /// them made every row collide with every other row over a value nobody
  /// typed.
  List<String?> _typedCodes() {
    final codeCol = _sheetDef.columns
        .where((c) => c.kind == ColumnKind.code)
        .map((c) => c.id)
        .firstOrNull;
    return [
      for (final draft in _drafts)
        () {
          if (codeCol == null) return null;
          final value = draft.get(codeCol);
          if (value?.mode != ValueMode.edit) return null;
          final code = value?.textValue?.trim();
          return code == null || code.isEmpty ? null : code.toUpperCase();
        }(),
    ];
  }

  /// True only when EVERY row is clean — a save writes them all.
  bool validateAll() {
    _deriveAndValidate();
    notifyListeners();
    return errorCount == 0;
  }

  String get currentStatusLocation {
    if (_focusedColumnId == null) return _sheetDef.title;
    final col = _sheetDef.getColumn(_focusedColumnId!);
    if (col == null) return _sheetDef.title;
    return '${_sheetDef.title} › ${col.label}';
  }

  String get currentStatusMessage {
    if (_focusedColumnId != null) {
      final err = errors[_focusedColumnId!];
      if (err != null) return err.message;
      return SheetEngine.hintFor(
        _sheetDef,
        draft,
        _focusedColumnId!,
        counters: _counters,
      );
    }
    if (_lastActionResult != null) return _lastActionResult!;
    return 'Ready.';
  }
}

/// The stored codes plus, at most, the one code another row on screen also
/// holds — without copying the stored set for every row.
class _CodesWith extends SetBase<String> {
  _CodesWith(this._base, this._extra);

  final Set<String> _base;
  final String? _extra;

  @override
  bool contains(Object? element) =>
      element == _extra || _base.contains(element);

  @override
  bool add(String value) => throw UnsupportedError('read-only');

  @override
  bool remove(Object? value) => throw UnsupportedError('read-only');

  @override
  Iterator<String> get iterator =>
      {..._base, if (_extra != null) _extra}.iterator;

  @override
  int get length =>
      _base.length + (_extra != null && !_base.contains(_extra) ? 1 : 0);

  @override
  String? lookup(Object? element) =>
      contains(element) ? element as String : null;

  @override
  Set<String> toSet() => {..._base, if (_extra != null) _extra};
}
