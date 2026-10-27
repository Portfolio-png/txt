import 'package:flutter/foundation.dart';
import 'column_def.dart';
import 'column_option.dart';
import 'sheet_def.dart';
import 'sheet_draft.dart';
import 'sheet_binding.dart';
import 'item_sheet_columns.dart';
import 'sheet_controller.dart';

class ItemMasterController extends ChangeNotifier {
  ItemMasterController({this.binding, this.demoData = false}) {
    _initControllers();
  }

  /// A controller over the real masters: no fixture groups, no fixture parties,
  /// no seeded part. Its pickers are empty until [loadReferenceData] fills them
  /// from the binding.
  ItemMasterController.live({required SheetBinding<Object?> binding})
    : this(binding: binding, demoData: false);

  /// Whether to seed the prototype's fixture — Switch Action › Dolly › Patti,
  /// Gold Medal, SADP48.
  ///
  /// **Off by default, so fabricated data is opt-in.** It defaulted to true
  /// while Express existed, which meant any new caller silently got five
  /// invented groups, four companies nobody created and a part the factory
  /// never made. The PM prototype and the shared test vectors are written
  /// against that fixture and ask for it by name; nothing else should.
  final bool demoData;

  /// How rows become real records. Null means this controller can lay a sheet
  /// out but cannot save one — a demo or a test harness. `saveItem` then says
  /// so rather than reporting a success, which is what the literal id 5012 used
  /// to do.
  final SheetBinding<Object?>? binding;

  /// True while a save is in flight.
  ///
  /// `ItemsProvider._save` answers null with NO error set when a save is
  /// already running, so a second Ctrl+S would otherwise read as a silent
  /// failure. Guarding here means the second one never starts.
  bool _isSavingNow = false;
  bool get isSavingNow => _isSavingNow;

  late final SheetController groupItemController;

  /// The development deal: ONE row — company, quotation, stamps. On a demo
  /// controller it is the prototype's one-person row ([partySheetColumns]).
  late final SheetController clientVendorController;

  /// The people at the deal's company, one row each (live sheet only). Their
  /// details save to the company; their "Dealt with" ticks save to the part.
  late final SheetController peopleController;

  /// Which company [peopleController] currently lists, or null when it lists
  /// nobody yet. Until it matches the deal's company the ticks are unknown, and
  /// a save must say nothing about them rather than clear them.
  int? _peopleFor;

  /// The company the table was last listed for, known or not. Separate from
  /// [_peopleFor] so a company whose people have not loaded yet is listed
  /// once, not again on every notification the deal sheet makes.
  int? _peopleRequestedFor;

  /// What the table was last listed from. A reload that would list the same
  /// people is skipped — replacing identical rows rebuilds the cell being
  /// typed into, which is what made the field flicker.
  String? _peopleSignature;

  /// Ticks from a loaded part, applied when its company's people arrive.
  Set<int> _loadedTicks = const {};
  int? _loadedTicksFor;

  bool _isExternal = true;
  String _activeSection = 'group_item';
  bool _isEditing = false;
  /// The id the legacy whole-sheet [saveItem] last wrote. The item sheet
  /// commits row by row and reads its part off the cursor row instead.
  int? _savedItemId;
  String? _savedCreatedAt;
  String _statusBarMessage =
      'Ready. Use Enter / Tab to traverse cells, Alt+↓ for dropdowns, Ctrl+S to save.';

  bool get isExternal => _isExternal;
  String get activeSection => _activeSection;
  bool get isEditing => _isEditing;
  bool get isSaved => savedItemId != null;

  /// The part the sheet is on: the cursor row's. Everything below the table
  /// — the deal, dies, machines, route, raw sheet — follows it, so selecting
  /// another row moves them all onto that row's part. It used to be one id
  /// for the whole screen, set by the last save, so the sections stayed on
  /// whichever part was saved last while the cursor sat on another.
  int? get savedItemId => groupItemController.draft.entityId ?? _savedItemId;
  String? get savedCreatedAt => _savedCreatedAt;
  String get statusBarMessage => _statusBarMessage;

  void setExternal(bool value) {
    _isExternal = value;
    _statusBarMessage = value
        ? 'Client / Vendor section enabled for external party part.'
        : 'Part set to Self. Client / Vendor draft preserved in memory.';
    notifyListeners();
  }

  void setActiveSection(String section) {
    _activeSection = section;
    notifyListeners();
  }

  void setEditing(bool editing) {
    _isEditing = editing;
    notifyListeners();
  }

  void setStatusMessage(String message) {
    _statusBarMessage = message;
    notifyListeners();
  }

  void _initControllers() {
    // -------------------------------------------------------------------------
    // 1. Group Item Sheet
    // -------------------------------------------------------------------------
    // Every column says what it feeds. Without `bindsTo` a cell is keyed by
    // `columnId` alone, so a binding has nothing to map and the save writes an
    // item with no name — which is what this sheet would have done, because
    // these ten columns declared no bindings at all until now.
    final groupCols = itemSheetColumns;

    final groupOptions = [
      // Groups
      const ColumnOption(id: 10, columnId: 1, label: 'Switch Action'),
      const ColumnOption(id: 11, columnId: 1, label: 'Cutout'),
      const ColumnOption(id: 12, columnId: 1, label: 'Double Pole'),
      const ColumnOption(id: 13, columnId: 1, label: 'Socket'),
      const ColumnOption(id: 14, columnId: 1, label: 'Others'),
      // Types under Switch Action (10)
      const ColumnOption(
        id: 101,
        columnId: 2,
        parentOptionId: 10,
        label: 'Dolly',
      ),
      const ColumnOption(
        id: 102,
        columnId: 2,
        parentOptionId: 10,
        label: 'Rocker',
      ),
      const ColumnOption(
        id: 103,
        columnId: 2,
        parentOptionId: 10,
        label: 'Italya',
      ),
      const ColumnOption(
        id: 104,
        columnId: 2,
        parentOptionId: 10,
        label: 'Ram Ban',
      ),
      // Part Names under Dolly (101)
      const ColumnOption(
        id: 201,
        columnId: 3,
        parentOptionId: 101,
        label: 'Patti',
      ),
      const ColumnOption(
        id: 202,
        columnId: 3,
        parentOptionId: 101,
        label: 'Dabbi',
      ),
      const ColumnOption(
        id: 203,
        columnId: 3,
        parentOptionId: 101,
        label: 'Threading Patti',
      ),
      // Part Names under Rocker (102)
      const ColumnOption(
        id: 204,
        columnId: 3,
        parentOptionId: 102,
        label: 'Patti',
      ),
      // Alloys (Primary Group)
      const ColumnOption(id: 301, columnId: 6, label: 'Brass'),
      const ColumnOption(id: 302, columnId: 6, label: 'Aluminium'),
      const ColumnOption(id: 303, columnId: 6, label: 'Copper'),
      const ColumnOption(id: 304, columnId: 6, label: 'P-Bronze'),
      const ColumnOption(id: 305, columnId: 6, label: 'Mild Steel'),
      const ColumnOption(id: 306, columnId: 6, label: 'EN9'),
      // Finish (Primary Group)
      const ColumnOption(id: 401, columnId: 8, label: 'Nickel'),
      const ColumnOption(id: 402, columnId: 8, label: 'Chrome'),
      const ColumnOption(id: 403, columnId: 8, label: 'Brass Polish'),
      const ColumnOption(id: 404, columnId: 8, label: 'Zinc'),
      const ColumnOption(id: 405, columnId: 8, label: 'Gold'),
    ];

    final groupInitialDraft = SheetDraft(
      sheetKey: 'item',
      values: {
        1: const CellValue(
          columnId: 1,
          optionId: 10,
          optionLabel: 'Switch Action',
        ),
        2: const CellValue(columnId: 2, optionId: 101, optionLabel: 'Dolly'),
        3: const CellValue(columnId: 3, optionId: 201, optionLabel: 'Patti'),
        4: const CellValue(columnId: 4, intValue: 48, mode: ValueMode.auto),
        5: const CellValue(
          columnId: 5,
          textValue: 'SADP48',
          mode: ValueMode.auto,
        ),
        6: const CellValue(columnId: 6, optionId: 301, optionLabel: 'Brass'),
        7: const CellValue(columnId: 7, textValue: '22 Gauge'),
        8: const CellValue(columnId: 8, optionId: 401, optionLabel: 'Nickel'),
        9: const CellValue(columnId: 9, textValue: 'Set on save'),
        10: const CellValue(columnId: 10, textValue: 'Set on save'),
      },
    );

    groupItemController = SheetController(
      sheetDef: SheetDef(
        id: 1,
        key: 'item',
        title: 'Group Item',
        columns: groupCols,
      ),
      initialDraft: demoData ? groupInitialDraft : null,
      options: demoData ? groupOptions : null,
      counters: demoData
          ? {
              'Switch Action › Dolly › Patti': 47,
              'Switch Action › Rocker › Patti': 9,
            }
          : null,
      existingPaths: demoData ? {'switch action › dolly › switch body'} : null,
      existingCodes: demoData ? {'SADP47'} : null,
    );

    // -------------------------------------------------------------------------
    // 2. Client / Vendor Sheet
    // -------------------------------------------------------------------------
    // The live sheet splits the deal from the people; the prototype's single
    // one-person row survives only for the PM screen and the demo vectors.
    final partyCols = demoData ? partySheetColumns : dealSheetColumns;

    final parties = [
      const Party(
        id: 1,
        name: 'Gold Medal',
        type: 'client',
        gstin: '27AABCU9603R1ZM',
      ),
      const Party(
        id: 2,
        name: 'Anchor',
        type: 'client',
        gstin: '27AAACA1234B1ZK',
      ),
      const Party(
        id: 3,
        name: 'Vardhaman',
        type: 'vendor',
        gstin: '27AABCV5555C1ZL',
      ),
      const Party(
        id: 4,
        name: 'Ashok Dies',
        type: 'contractor',
        gstin: '27AABCA7777D1ZM',
      ),
    ];

    final contacts = [
      const Contact(
        id: 11,
        partyId: 1,
        name: 'Kissan Jain',
        designation: 'Director',
        phone: '9865656560',
        email: 'kissan@goldmedal.in',
      ),
      const Contact(
        id: 12,
        partyId: 1,
        name: 'Pravin Shah',
        designation: 'Production Head',
        phone: '9820054321',
        email: 'pravin@goldmedal.in',
      ),
      const Contact(
        id: 13,
        partyId: 2,
        name: 'Kapil Shah',
        designation: 'Purchase Head',
        phone: '9820012345',
        email: 'kapil@anchor.com',
      ),
      const Contact(
        id: 14,
        partyId: 3,
        name: 'Mukesh Vardhan',
        designation: 'Proprietor',
        phone: '9821098765',
        email: 'mukesh@vardhaman.in',
      ),
    ];

    final partyInitialDraft = SheetDraft(
      sheetKey: 'item_party',
      values: {
        20: const CellValue(columnId: 20, refId: 1, optionLabel: 'Gold Medal'),
        21: const CellValue(
          columnId: 21,
          refId: 11,
          optionLabel: 'Kissan Jain',
        ),
        22: const CellValue(columnId: 22, textValue: 'Director'),
        23: const CellValue(columnId: 23, textValue: '9865656560'),
        24: const CellValue(columnId: 24, textValue: 'kissan@goldmedal.in'),
        25: const CellValue(
          columnId: 25,
          intValue: 8500000,
          textValue: '85,000',
        ),
        28: const CellValue(
          columnId: 28,
          intValue: 5200000,
          textValue: '52,000',
        ),
        26: const CellValue(columnId: 26, textValue: 'Set on save'),
        27: const CellValue(columnId: 27, textValue: 'Set on save'),
      },
    );

    clientVendorController = SheetController(
      sheetDef: SheetDef(
        id: 2,
        key: 'item_party',
        title: 'Client / Vendor',
        columns: partyCols,
      ),
      initialDraft: demoData ? partyInitialDraft : null,
      parties: demoData ? parties : null,
      contacts: demoData ? contacts : null,
    )..canAddRows = false;

    peopleController = SheetController(
      sheetDef: SheetDef(
        id: 3,
        key: 'item_people',
        title: 'People',
        columns: peopleSheetColumns,
      ),
    );

    // A company has as many people as it has, so the contact picker can add
    // one. Wired from the binding because a cell cannot see it — the same
    // reason `onRowLeft` is a callback rather than a lookup.
    final writer = binding;
    if (writer != null) {
      clientVendorController.onAddContact = writer.addContact;
    }

    // The deal on screen starts as the first row's.
    _claimDeal(groupItemController.draft);
    groupItemController.addListener(_onRowsChanged);
    groupItemController.onPickExisting = _pickExisting;
    clientVendorController.addListener(_onDealChanged);
    peopleController.addListener(_onChildChanged);
  }

  void _onChildChanged() {
    notifyListeners();
  }

  void _onRowsChanged() {
    _syncDealToCursor();
    notifyListeners();
  }

  // --- which part the deal is ------------------------------------------------

  /// The row the deal on screen belongs to, and the part it was for. A deal
  /// is a part's — who it was developed for — so it changes with the row.
  Object? _dealRowKey;
  int? _dealPartId;

  /// The row a save is writing right now, so the deal only rides on its own
  /// part's save.
  Object? _savingRowKey;

  /// Where the deal's own row sits, or null when it is not on the sheet.
  int? get dealRow {
    final key = _dealRowKey;
    if (key == null) return null;
    final at = groupItemController.indexOfRowKey(key);
    return at < 0 ? null : at;
  }

  void _claimDeal(SheetDraft draft) {
    _dealRowKey = draft.rowKey;
    _dealPartId = draft.entityId;
  }

  /// Puts the cursor row's part's deal on screen when the cursor has moved to
  /// another part. A deal typed and not yet saved is never dropped or carried
  /// to the wrong part: it stays, belonging to its row, until that row's save
  /// writes it ([commitRow] marks it clean and calls this again).
  void _syncDealToCursor({bool force = false}) {
    final writer = binding;
    if (writer == null) return;
    final draft = groupItemController.draft;
    if (identical(draft.rowKey, _dealRowKey) &&
        draft.entityId == _dealPartId) {
      return;
    }
    if (!force && _dealDirty && dealRow != null) {
      _statusBarMessage =
          'The Client / Vendor changes belong to row ${dealRow! + 1} — they '
          'are written when that row saves.';
      return;
    }
    _claimDeal(draft);
    final id = draft.entityId;
    final entity = id == null ? null : writer.entityById(id);
    final deal = entity == null ? null : writer.dealOf(entity);
    if (deal == null) {
      // A saved part with no outside party opens with the section off; a new
      // row starts as the screen does, ready for one.
      _isExternal = id == null;
      _resetDeal();
    } else {
      _isExternal = true;
      _applyDeal(deal);
    }
  }

  /// A Part Name picked that is an existing part loads THAT part into the row
  /// — it is an edit of it, not a new part named after it (which the sheet
  /// refuses as a duplicate). Already on another row, the cursor goes there
  /// instead of the part being on the sheet twice.
  bool _pickExisting(int row, ColumnDef column, ColumnOption option) {
    final writer = binding;
    if (writer == null || column.bindsTo != SheetBindsTo.name) return false;
    final entity = writer.entityById(option.id);
    if (entity == null) return false;
    final sheet = groupItemController;
    if (row < 0 || row >= sheet.rowCount) return false;
    if (sheet.draftAt(row).entityId == option.id) return false;

    for (var other = 0; other < sheet.rowCount; other += 1) {
      if (other == row || sheet.draftAt(other).entityId != option.id) continue;
      // Leave nothing half-typed behind: a row that only held the pick goes.
      final picked = sheet.draftAt(row);
      sheet.selectRow(other);
      final at = sheet.indexOfDraft(picked);
      if (at >= 0 && picked.entityId == null && sheet.isRowBlank(at)) {
        sheet.removeRow(at);
      }
      _statusBarMessage = 'That part is already on row ${sheet.row + 1}.';
      notifyListeners();
      return true;
    }

    final loaded = writer.draftForId(option.id);
    if (loaded == null) return false;
    sheet.replaceRowAt(row, loaded);
    sheet.setRowLocked(row, false);
    if (sheet.row != row) sheet.selectRow(row);
    // What was typed for a new part does not become this part's deal.
    _syncDealToCursor(force: true);
    _statusBarMessage =
        'Opened ${_codeOf(entity) ?? 'that part'} on row ${row + 1} — edits '
        'save to it.';
    notifyListeners();
    return true;
  }

  // --- the deal and its people ----------------------------------------------

  /// Adds a company to the master by name — from the Company dropdown, so a
  /// part for a new customer does not need a trip to the Clients screen — and
  /// reloads the pickers so it is there to pick.
  Future<Party?> addParty(String name) async {
    final writer = binding;
    if (writer == null) return null;
    final party = await writer.addParty(name);
    if (party == null) {
      _statusBarMessage = writer.lastError ?? 'Could not add that company.';
      notifyListeners();
      return null;
    }
    await loadReferenceData();
    _statusBarMessage = 'Added ${party.name} to the clients master.';
    notifyListeners();
    return party;
  }

  /// Saves one person line to the company — that row's own Save. True when it
  /// landed (or there was nothing to write); the row is then closed until its
  /// Edit.
  Future<bool> savePersonRow(int row) async {
    final writer = binding;
    final party = dealPartyId;
    if (writer == null || party == null) return false;
    if (row < 0 || row >= peopleController.rowCount) return false;
    final draft = peopleController.draftAt(row);
    if (peopleController.isRowBlank(row)) return false;
    // A second click while the first is in flight would add the person twice.
    if (_savingPeople.contains(draft)) return false;
    if (!peopleController.validateRow(row)) {
      _statusBarMessage =
          peopleController.firstErrorOn(row) ??
          'That person needs attention before they can be saved.';
      notifyListeners();
      return false;
    }
    if (draft.entityId != null && !draft.isDirtySinceSave) {
      peopleController.setRowLocked(row, true);
      return true;
    }
    final sent = Map.of(draft.values);
    _savingPeople.add(draft);
    notifyListeners();
    final int? id;
    try {
      id = await writer.savePerson(party, draft);
    } finally {
      _savingPeople.remove(draft);
    }
    if (id == null) {
      _statusBarMessage = writer.lastError ?? 'That person did not save.';
      notifyListeners();
      return false;
    }
    final at = peopleController.indexOfDraft(draft);
    if (at >= 0) peopleController.markRowSaved(at, id, sent: sent);
    await writer.peopleSaved();
    _peopleFor = party;
    _statusBarMessage = at >= 0
        ? 'Saved ${_personName(at)} to $dealPartyName.'
        : 'Saved to $dealPartyName.';
    notifyListeners();
    return true;
  }

  /// People rows whose save is in flight, by draft.
  final Set<SheetDraft> _savingPeople = Set.identity();

  /// Whether [row]'s person is being saved right now — its Save is disabled.
  bool isSavingPerson(int row) =>
      row >= 0 &&
      row < peopleController.rowCount &&
      _savingPeople.contains(peopleController.draftAt(row));

  String _personName(int row) {
    final column = peopleController.sheetDef.columnBoundTo(
      SheetBindsTo.personName,
    );
    final value = column == null
        ? null
        : peopleController.draftAt(row).get(column.id);
    final name = (value?.textValue ?? '').trim();
    return name.isEmpty ? 'that person' : name;
  }

  /// Rows whose part was deleted or archived somewhere else, with why. Such a
  /// row stays as it was — it is what the user was looking at — but locked,
  /// and says so: it used to sit there looking saved and editable.
  final Map<SheetDraft, String> _goneRows = Map.identity();

  /// Whether [row]'s part is gone from the catalogue.
  bool isRowGone(int row) =>
      row >= 0 &&
      row < groupItemController.rowCount &&
      _goneRows.containsKey(groupItemController.draftAt(row));

  /// Re-reads saved, closed item rows from [entities] after they changed
  /// somewhere else — another window, another person. Rows open for editing,
  /// or holding unsaved changes, are left exactly as they are.
  void refreshLockedRows(List<Object?> entities) {
    final writer = binding;
    if (writer == null || entities.isEmpty) return;
    _markGoneRows(entities);
    _followDeal(entities);
    final sheet = groupItemController;
    // Which entities the sheet shows, found in one pass — this runs on every
    // provider notification, and scanning the whole catalogue per row was
    // rows × items each time.
    final wanted = <int>{
      for (var row = 0; row < sheet.rowCount; row += 1)
        if (sheet.draftAt(row).entityId != null) sheet.draftAt(row).entityId!,
    };
    if (wanted.isEmpty) return;
    final byId = <int, int>{};
    for (
      var i = 0;
      i < entities.length && byId.length < wanted.length;
      i += 1
    ) {
      final id = _idOf(entities[i]);
      if (id != null && wanted.contains(id)) byId.putIfAbsent(id, () => i);
    }
    for (var row = 0; row < sheet.rowCount; row += 1) {
      final draft = sheet.draftAt(row);
      final id = draft.entityId;
      if (id == null || !sheet.isRowLocked(row) || draft.isDirtySinceSave) {
        continue;
      }
      final at = byId[id];
      if (at == null) continue;
      // Sliced from [entities] rather than wrapped in a new literal: the
      // binding is typed (List<ItemDefinition>), and `sublist` keeps the
      // incoming list's element type where `[fresh]` would not.
      final fresh = entities.sublist(at, at + 1);
      final rows = writer.toDrafts(fresh);
      if (rows.isEmpty) continue;
      if (_sameValues(rows.first, draft)) continue;
      sheet.replaceRowAt(row, rows.first);
    }
  }

  void _markGoneRows(List<Object?> entities) {
    final sheet = groupItemController;
    final live = <int, Object?>{
      for (final entity in entities)
        if (_idOf(entity) != null) _idOf(entity)!: entity,
    };
    var changed = false;
    for (var row = 0; row < sheet.rowCount; row += 1) {
      final draft = sheet.draftAt(row);
      final id = draft.entityId;
      if (id == null) continue;
      final entity = live[id];
      final reason = entity == null
          ? 'This part has been deleted. Nothing here can be saved to it.'
          : (_isArchivedOf(entity)
                ? 'This part is archived. Restore it on the Items screen to '
                      'edit it here.'
                : null);
      if (reason == null) {
        changed |= _goneRows.remove(draft) != null;
        continue;
      }
      if (_goneRows[draft] == reason) continue;
      _goneRows[draft] = reason;
      sheet.setRowLocked(row, true);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Puts the part's stored deal back on screen when it changed somewhere
  /// else and nothing here is waiting to be saved. The deal was read once, at
  /// open, so a quotation or company changed in another window never showed
  /// — and the next save here wrote the old one back.
  void _followDeal(List<Object?> entities) {
    final writer = binding;
    final partId = _dealPartId;
    if (writer == null || partId == null || !_isExternal) return;
    if (clientVendorController.draft.isDirtySinceSave || _peopleDirty) return;
    final entity = entities.where((e) => _idOf(e) == partId).firstOrNull;
    if (entity == null) return;
    final deal = writer.dealOf(entity);
    if (deal == null) return;
    final ticksSame = setEquals(deal.ticked, _loadedTicks);
    if (ticksSame && _sameValues(deal.deal, clientVendorController.draft)) {
      return;
    }
    _applyDeal(deal);
    notifyListeners();
  }

  /// [deal] on screen, its people listed with its ticks.
  void _applyDeal(({SheetDraft deal, Set<int> ticked}) deal) {
    _loadedTicks = deal.ticked;
    final partyColumn = clientVendorController.sheetDef.columnBoundTo(
      SheetBindsTo.developedForParty,
    );
    _loadedTicksFor = partyColumn == null
        ? null
        : deal.deal.get(partyColumn.id)?.refId;
    clientVendorController.loadRecords([deal.deal]);
    clientVendorController.draft.markClean();
    // The same company with different ticks: re-list its people with them.
    final party = dealPartyId;
    if (party != null && party == _peopleRequestedFor && !_peopleInProgress) {
      _peopleSignature = null;
      _loadPeople(party, ticked: _loadedTicks);
    }
  }

  static bool _isArchivedOf(Object? record) {
    try {
      return (record as dynamic).isArchived == true;
    } catch (_) {
      return false;
    }
  }

  static bool _sameValues(SheetDraft a, SheetDraft b) {
    if (a.values.length != b.values.length) return false;
    for (final entry in a.values.entries) {
      final other = b.values[entry.key];
      if (other == null) return false;
      if (other.textValue != entry.value.textValue ||
          other.optionLabel != entry.value.optionLabel ||
          other.intValue != entry.value.intValue) {
        return false;
      }
    }
    return true;
  }

  /// Empties the deal and the people table on screen — the bin on the Client
  /// / Vendor section, for a part not saved yet (a saved one is cleared on
  /// the server and reloaded).
  void clearDeal() {
    _resetDeal();
    _statusBarMessage = 'Cleared who this part was developed for.';
    notifyListeners();
  }

  /// The part's deal was cleared on the server: empty the section and turn it
  /// off, touching nothing else. Reloading the whole sheet from the one saved
  /// part did this before, and threw away every other row's unsaved work.
  void dealClearedOnServer() {
    _resetDeal();
    _isExternal = false;
    _statusBarMessage = 'Cleared who this part was developed for.';
    notifyListeners();
  }

  void _resetDeal() {
    clientVendorController.loadRecords(const []);
    _loadedTicks = const {};
    _loadedTicksFor = null;
    _loadPeople(null);
  }

  /// The company the deal names, or null.
  int? get dealPartyId {
    final column = clientVendorController.sheetDef.columnBoundTo(
      SheetBindsTo.developedForParty,
    );
    return column == null
        ? null
        : clientVendorController.draft.get(column.id)?.refId;
  }

  String get dealPartyName {
    final column = clientVendorController.sheetDef.columnBoundTo(
      SheetBindsTo.developedForParty,
    );
    return column == null
        ? ''
        : (clientVendorController.draft.get(column.id)?.optionLabel ?? '');
  }

  /// Whether the people table belongs to the company the deal names.
  bool get peopleLoaded => _peopleFor != null && _peopleFor == dealPartyId;

  /// The deal row a save writes, or null when the part is not for an outside
  /// party — in which case the part says nothing and keeps what it had.
  SheetDraft? dealDraftForSave() =>
      _isExternal && _dealRidesOnThisSave ? clientVendorController.draft : null;

  /// Whether the save running now is the deal's own part's. Outside a row
  /// save (the legacy whole-sheet [saveItem]) the deal rides as it always did.
  bool get _dealRidesOnThisSave =>
      _savingRowKey == null || identical(_savingRowKey, _dealRowKey);

  /// The people ticked on the deal, or null to say nothing — when the part is
  /// not external, or the table has not loaded this company's people yet.
  List<int>? dealContactIdsForSave() {
    if (!_isExternal || !peopleLoaded || !_dealRidesOnThisSave) return null;
    return _tickedIds();
  }

  List<int> _tickedIds() {
    final tick = peopleController.sheetDef.columnBoundTo(
      SheetBindsTo.personDealtWith,
    );
    if (tick == null) return const [];
    return [
      for (final draft in peopleController.drafts)
        if (draft.entityId != null && draft.get(tick.id)?.intValue == 1)
          draft.entityId!,
    ];
  }

  void _onDealChanged() {
    final party = dealPartyId;
    if (party != _peopleRequestedFor) {
      // A different company means different people. The old company's ticks
      // cannot carry over — they would name strangers.
      _loadPeople(
        party,
        ticked: party != null && party == _loadedTicksFor
            ? _loadedTicks
            : const {},
      );
    }
    notifyListeners();
  }

  /// Lists [party]'s people, with [ticked] marked. Null empties the table.
  void _loadPeople(int? party, {Set<int> ticked = const {}}) {
    final writer = binding;
    _peopleRequestedFor = party;
    if (party == null || writer == null) {
      _peopleFor = null;
      _peopleSignature = null;
      peopleController.loadRecords(const []);
      return;
    }
    final rows = writer.peopleRows(party, ticked: ticked);
    final signature = _signatureOf(party, rows);
    if (signature == _peopleSignature) {
      // Same people as already listed: leave the rows (and the cursor) alone,
      // but note it if the company's record has now arrived.
      if (writer.knowsParty(party)) _peopleFor = party;
      return;
    }
    _peopleSignature = signature;
    // Before the clients master has loaded there is nobody to list — and that
    // is not the same as "this company has nobody", so the table is not yet
    // this company's and the ticks stay unknown.
    final known = writer.knowsParty(party);
    _peopleFor = known ? party : null;
    peopleController.loadRecords(rows);
  }

  static String _signatureOf(int party, List<SheetDraft> rows) {
    final out = StringBuffer('$party|');
    for (final row in rows) {
      out.write('${row.entityId}:');
      final ids = row.values.keys.toList()..sort();
      for (final id in ids) {
        final v = row.values[id]!;
        out.write('$id=${v.textValue}/${v.intValue}/${v.optionLabel};');
      }
      out.write('|');
    }
    return out.toString();
  }

  /// Whether the table holds a row somebody added here and has not saved —
  /// even an empty one they are about to type into. Re-listing would throw it
  /// away from under the cursor.
  bool get _peopleInProgress {
    for (var row = 0; row < peopleController.rowCount; row += 1) {
      final draft = peopleController.draftAt(row);
      if (draft.entityId == null && peopleController.rowCount > 1) return true;
      if (draft.entityId == null && draft.isDirtySinceSave) return true;
    }
    return false;
  }

  /// Whether anything in the people table has been typed and not yet saved.
  bool get _peopleDirty {
    for (var row = 0; row < peopleController.rowCount; row += 1) {
      final draft = peopleController.draftAt(row);
      if (draft.isDirtySinceSave && !peopleController.isRowBlank(row)) {
        return true;
      }
    }
    return false;
  }

  /// Whether the deal or its people changed since the last full save — in
  /// which case parts already written need writing again to carry it.
  bool get _dealDirty =>
      _isExternal &&
      (clientVendorController.draft.isDirtySinceSave || _peopleDirty);

  /// Writes every typed or changed person to the company. True when nothing
  /// is left unsaved.
  ///
  /// People are company records, so they save before the part that ticks
  /// them — a tick on a person who does not exist yet has no id to send.
  Future<bool> _flushPeople() async {
    final writer = binding;
    final party = dealPartyId;
    if (writer == null || party == null || !_isExternal) return true;
    if (!_peopleDirty) return true;

    if (!peopleController.validateAll()) {
      _statusBarMessage =
          'A person at $dealPartyName needs attention before this can be saved.';
      notifyListeners();
      return false;
    }

    var wrote = false;
    final pending = [
      for (var row = 0; row < peopleController.rowCount; row += 1)
        if (!peopleController.isRowBlank(row) &&
            (peopleController.draftAt(row).entityId == null ||
                peopleController.draftAt(row).isDirtySinceSave))
          peopleController.draftAt(row),
    ];
    for (final draft in pending) {
      // Its own Save is already writing it.
      if (_savingPeople.contains(draft)) continue;
      final sent = Map.of(draft.values);
      _savingPeople.add(draft);
      final int? id;
      try {
        id = await writer.savePerson(party, draft);
      } finally {
        _savingPeople.remove(draft);
      }
      if (id == null) {
        _statusBarMessage = writer.lastError ?? 'A person did not save.';
        notifyListeners();
        if (wrote) await writer.peopleSaved();
        return false;
      }
      wrote = true;
      final at = peopleController.indexOfDraft(draft);
      if (at >= 0) peopleController.markRowSaved(at, id, sent: sent);
    }
    if (wrote) await writer.peopleSaved();
    // The table is this company's now, whatever it showed before.
    _peopleFor = party;
    return true;
  }

  /// Fills the party sheet from a contact.
  ///
  /// Was four `updateValue` calls on the literal column ids 21–24. Now
  /// delegates to [SheetController.applyContact], which keys off `bindsTo` —
  /// so this and the cell's own dropdown do the same thing, instead of the
  /// dropdown writing the name alone and leaving the rest blank.
  void pickContact(Contact contact) {
    final column = clientVendorController.sheetDef.columnBoundTo(
      SheetBindsTo.developedForContact,
    );
    if (column == null) return;
    clientVendorController.applyContact(column.id, contact);
    _statusBarMessage =
        'Filled from ${contact.name}’s record. You can change it.';
    notifyListeners();
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Set when the masters change while a load is already running.
  bool _reloadWanted = false;

  /// Fills the pickers from the real masters.
  ///
  /// Separate from construction because a sheet opens before its providers
  /// have loaded — the reference data has to be able to arrive late. Safe to
  /// call again when the masters change under the screen.
  Future<void> loadReferenceData() async {
    final writer = binding;
    if (writer == null) return;

    if (_isLoading) {
      // Coalesce rather than drop. Returning early here would discard the
      // newer masters: the call that is in flight is already reading stale
      // providers, so the data it brings back is the data this call was made
      // because of being out of date.
      _reloadWanted = true;
      return;
    }

    _isLoading = true;
    notifyListeners();

    // finally: one exception from a provider left _isLoading true for good,
    // and every later reload then only set _reloadWanted and returned.
    try {
      do {
        _reloadWanted = false;
        final data = await writer.referenceData();
        if (_disposed) return;
        groupItemController.applyReferenceData(data);
        // The party sheet shares the reference data: its pickers are the parties
        // and contacts, and it has no codes or counters of its own.
        clientVendorController.applyReferenceData(data);
        // The masters may have just brought the company's people. Re-list them
        // unless something has been typed there — keeping whatever is ticked.
        final party = dealPartyId;
        if (party != null && !_peopleDirty && !_peopleInProgress) {
          _loadPeople(
            party,
            ticked: peopleLoaded
                ? _tickedIds().toSet()
                : (party == _loadedTicksFor ? _loadedTicks : const {}),
          );
        }
      } while (_reloadWanted);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Opens existing records for editing.
  ///
  /// Goes through [SheetController.loadRecords] rather than `replaceRows`
  /// because these rows are the records that `existingCodes` was built from —
  /// loaded any other way, a part reads as colliding with itself.
  void loadItems(List<Object?> entities) {
    final writer = binding;
    if (writer == null || entities.isEmpty) return;

    final rows = writer.toDrafts(entities);
    if (rows.isEmpty) return;

    groupItemController.loadRecords(rows);

    // The deal on screen is the first row's part's. A part with no
    // outside party opens with the section off rather than offering a blank
    // deal that a save would then write.
    final deal = writer.dealOf(entities.first);
    if (deal == null) {
      _isExternal = false;
      // Not left holding the previous part's deal: ticking External again
      // would otherwise offer it, and a save would write it back.
      _resetDeal();
    } else {
      _isExternal = true;
      _applyDeal(deal);
    }

    _claimDeal(groupItemController.draftAt(0));
    _statusBarMessage = entities.length == 1
        ? 'Opened ${_codeOf(entities.first) ?? 'that part'} for editing.'
        : 'Opened ${entities.length} parts for editing.';
    notifyListeners();
  }

  /// What happened to a row the last time it was committed — keyed by the
  /// row's draft, not its index, so removing a row above does not hand its
  /// error to whichever row moves into its place.
  final Map<SheetDraft, String> _rowErrors = Map.identity();

  /// The refusal on [row], or null when it has none.
  String? rowError(int row) {
    if (row < 0 || row >= groupItemController.rowCount) return null;
    final draft = groupItemController.draftAt(row);
    return _goneRows[draft] ?? _rowErrors[draft];
  }

  /// Refusals on rows still on the sheet.
  int get _refusedCount {
    _rowErrors.removeWhere(
      (draft, _) => groupItemController.indexOfDraft(draft) < 0,
    );
    return _rowErrors.length;
  }

  /// Rows that tried to commit while another save was running. They are
  /// written once it finishes, rather than dropped with no error and a plain
  /// save icon that never saved.
  final Set<SheetDraft> _queued = Set.identity();

  /// Every item id this sitting has written.
  Set<int> get savedItemIds => {
    for (final row in groupItemController.savedRows)
      ?groupItemController.draftAt(row).entityId,
  };

  /// Rows already written, by index.
  Set<int> get savedRows => groupItemController.savedRows;

  /// Writes ONE row and records what happened to it.
  ///
  /// The unit the sheet commits in. A row is written when it is complete and
  /// the cursor leaves it, so fifty parts are fifty independent writes and a
  /// bad row in the middle costs only that row — which is the whole reason the
  /// batching version was replaced.
  ///
  /// Answers false for a row that was not written, including a blank one. A
  /// blank row is not a failure and records no error.
  Future<bool> commitRow(int row) async {
    final writer = binding;
    if (writer == null) return false;
    if (row < 0 || row >= groupItemController.rowCount) return false;

    final draft = groupItemController.draftAt(row);
    if (groupItemController.isRowBlank(row)) {
      _rowErrors.remove(draft);
      return false;
    }

    // Already written and untouched since — nothing to do. An edited row IS
    // committed again, which `saveRow` turns into an update because the draft
    // carries its entityId. A changed deal writes its own part again — only
    // its own: the deal is a part's, not the sheet's.
    final ownsDeal = identical(draft.rowKey, _dealRowKey);
    if (draft.entityId != null &&
        !draft.isDirtySinceSave &&
        !(ownsDeal && _dealDirty)) {
      _rowErrors.remove(draft);
      return false;
    }

    if (_isSavingNow) {
      _queued.add(draft);
      _statusBarMessage = 'Still saving the last one — row ${row + 1} is next.';
      notifyListeners();
      return false;
    }

    if (!groupItemController.validateRow(row)) {
      _rowErrors[draft] =
          groupItemController.firstErrorOn(row) ??
          'This row needs attention before it can be saved.';
      notifyListeners();
      return false;
    }

    // The deal rides on its part, so a bad quotation must stop the part
    // rather than be read as "no quotation" and clear the stored one.
    if (ownsDeal &&
        _isExternal &&
        clientVendorController.draft.isDirtySinceSave &&
        !clientVendorController.validateRow(0)) {
      _rowErrors[draft] =
          clientVendorController.firstErrorOn(0) ??
          'The Client / Vendor section needs attention first.';
      _statusBarMessage = _rowErrors[draft]!;
      notifyListeners();
      return false;
    }

    _isSavingNow = true;
    notifyListeners();

    Object? result;
    final sent = Map.of(draft.values);
    final dealSent = ownsDeal && _dealDirty;
    try {
      if (ownsDeal && !await _flushPeople()) {
        _rowErrors[draft] = _statusBarMessage;
        return false;
      }
      _savingRowKey = draft.rowKey;
      result = await writer.saveRow(draft);
    } catch (error) {
      _rowErrors[draft] = 'That row did not save: $error';
      _statusBarMessage = _rowErrors[draft]!;
      return false;
    } finally {
      _savingRowKey = null;
      _isSavingNow = false;
      notifyListeners();
      _drainQueue();
    }

    // Looked up again: the row may have moved, or gone, while it saved.
    final at = groupItemController.indexOfDraft(draft);

    if (result == null) {
      // Everything typed stays. Clearing on failure throws away the work, and
      // the write is NEVER retried on its own: a response lost after the server
      // committed would become a second part.
      _rowErrors[draft] = writer.lastError ?? 'That row did not save.';
      _statusBarMessage = _rowErrors[draft]!;
      notifyListeners();
      return false;
    }

    _rowErrors.remove(draft);
    _lastCommittedRow = at >= 0 ? at : null;
    final id = _idOf(result);
    final stamps = _stampsOf(result);
    if (identical(draft.rowKey, _dealRowKey)) {
      // The deal is this part's now, and written — unless it was typed into
      // again while the save ran.
      _dealPartId = id ?? _dealPartId;
      if (dealSent) clientVendorController.draft.markClean();
    }
    if (id != null && at >= 0) {
      groupItemController.markRowSaved(
        at,
        id,
        partCode: _codeOf(result),
        createdDate: stamps.date,
        createdTime: stamps.time,
        sent: sent,
      );
    }

    // The cursor may have moved on while this saved; a deal that waited for
    // this row can now give way to the cursor row's.
    _syncDealToCursor();
    final code = _codeOf(result);
    final label = at >= 0 ? 'row ${at + 1}' : 'a removed row';
    _statusBarMessage = code == null
        ? 'Saved $label as item #$id.'
        : 'Saved $label as $code (item #$id).';
    notifyListeners();
    return true;
  }

  int? _lastCommittedRow;

  /// Where the row the last successful [commitRow] wrote sits now, or null
  /// when it was removed while saving. The index a caller passed in may no
  /// longer be it.
  int? get lastCommittedRow => _lastCommittedRow;

  /// Commits the rows that were held back while a save ran.
  void _drainQueue() {
    if (_queued.isEmpty || _disposed) return;
    final next = _queued.first;
    _queued.remove(next);
    final at = groupItemController.indexOfDraft(next);
    if (at < 0) {
      _drainQueue();
      return;
    }
    // After the current call stack: the save that just finished is still
    // unwinding, and its own bookkeeping must land first.
    Future<void>.microtask(() async {
      if (_disposed) return;
      final index = groupItemController.indexOfDraft(next);
      if (index >= 0) await commitRow(index);
    });
  }

  /// Commits every row that is ready, and reports what landed.
  ///
  /// What the Save button does. Rows that refuse keep their error and the rest
  /// still go — one typo does not stall forty-four good rows.
  Future<int> commitAllRows() async {
    var written = 0;
    for (var row = 0; row < groupItemController.rowCount; row += 1) {
      if (await commitRow(row)) written += 1;
    }

    final refused = _refusedCount;
    final totalSaved = savedItemIds.length;
    if (written == 0 && refused == 0) {
      _statusBarMessage = totalSaved > 0
          ? '$totalSaved saved.'
          : 'There is nothing filled in to save.';
    } else {
      _statusBarMessage = refused == 0
          ? '${totalSaved > 0 ? totalSaved : written} saved.'
          : '$written saved, $refused need attention.';
    }
    notifyListeners();
    return written;
  }

  /// Whether leaving now would lose something: a row not written, an edit
  /// not written, or a deal change not yet carried to the parts.
  bool get hasUnsavedWork => !_everyRowLanded || _dealDirty;

  bool get _everyRowLanded {
    for (var row = 0; row < groupItemController.rowCount; row += 1) {
      if (groupItemController.isRowBlank(row)) continue;
      final draft = groupItemController.draftAt(row);
      if (draft.entityId == null || draft.isDirtySinceSave) return false;
    }
    return _queued.isEmpty;
  }

  /// Writes every row of the sheet.
  ///
  /// Was synchronous and wrote nothing: it validated, assigned the literal id
  /// `5012`, stamped two hand-formatted strings into cells and returned true.
  /// Everything below the validation is now the binding's, and the id, the part
  /// code and the stamps come back from the saved record.
  Future<bool> saveItem() async {
    if (_isSavingNow) {
      _statusBarMessage = 'Still saving the last one.';
      notifyListeners();
      return false;
    }

    final groupValid = groupItemController.validateAll();
    final clientValid = !_isExternal || clientVendorController.validateAll();

    if (!groupValid || !clientValid) {
      // Every row, not just the selected one — a save writes them all.
      // Say WHERE. The sections scroll, so "7 cells need attention" sent people
      // hunting through four of them for cells they had never touched.
      final partErrors = groupItemController.errorCount;
      final dealErrors = _isExternal ? clientVendorController.errorCount : 0;
      final where = <String>[
        if (partErrors > 0) '$partErrors in Item Master',
        if (dealErrors > 0) '$dealErrors in Client / Vendor',
      ];
      _statusBarMessage =
          '${partErrors + dealErrors} cells need attention before this item '
          'can be saved — ${where.join(', ')}.';
      notifyListeners();
      return false;
    }

    final writer = binding;
    if (writer == null) {
      // No writer means nothing was written, and that has to be said. A save
      // that did not happen must not look identical to one that did.
      _statusBarMessage = 'Nothing was saved: this sheet has no item service.';
      notifyListeners();
      return false;
    }

    _isSavingNow = true;
    notifyListeners();

    final List<Object?>? saved;
    try {
      if (!await _flushPeople()) return false;
      saved = await writer.save(groupItemController.drafts);
    } finally {
      _isSavingNow = false;
      notifyListeners();
    }

    if (saved == null || saved.isEmpty) {
      _statusBarMessage = writer.lastError ?? 'That save did not go through.';
      notifyListeners();
      return false;
    }

    _applySavedRecord(saved.first);
    notifyListeners();
    return true;
  }

  /// Takes the id, the code and the stamps from what the server actually
  /// stored, rather than inventing them.
  void _applySavedRecord(Object? record) {
    final stamps = _stampsOf(record);
    _savedItemId = _idOf(record);
    _savedCreatedAt = '${stamps.date} ${stamps.time}';

    groupItemController.updateValue(
      9,
      CellValue(columnId: 9, textValue: stamps.date),
      row: 0,
    );
    groupItemController.updateValue(
      10,
      CellValue(columnId: 10, textValue: stamps.time),
      row: 0,
    );
    if (_isExternal) {
      clientVendorController.updateValue(
        26,
        CellValue(columnId: 26, textValue: stamps.date),
      );
      clientVendorController.updateValue(
        27,
        CellValue(columnId: 27, textValue: stamps.time),
      );
    }

    final code =
        _codeOf(record) ?? groupItemController.draft.get(5)?.textValue ?? '';
    _statusBarMessage = _savedItemId == null
        ? 'Saved $code.'
        : 'Saved item #$_savedItemId as $code on ${stamps.date} at ${stamps.time}.';
  }

  /// The sheet layer must not import the items feature — a second entity would
  /// then need a second import here. The record is read through the small
  /// surface a saved thing is expected to have.
  static int? _idOf(Object? record) {
    try {
      return (record as dynamic).id as int?;
    } catch (_) {
      return null;
    }
  }

  static String? _codeOf(Object? record) {
    try {
      final code = (record as dynamic).partCode as String?;
      return (code == null || code.trim().isEmpty) ? null : code;
    } catch (_) {
      return null;
    }
  }

  static ({String date, String time}) _stampsOf(Object? record) {
    DateTime at;
    try {
      at = ((record as dynamic).createdAt as DateTime).toLocal();
    } catch (_) {
      at = DateTime.now();
    }
    final date =
        '${at.day.toString().padLeft(2, '0')}/'
        '${at.month.toString().padLeft(2, '0')}/'
        '${at.year.toString().substring(2)}';
    final time =
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    return (date: date, time: time);
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _queued.clear();
    groupItemController.removeListener(_onChildChanged);
    clientVendorController.removeListener(_onDealChanged);
    peopleController.removeListener(_onChildChanged);
    groupItemController.dispose();
    clientVendorController.dispose();
    peopleController.dispose();
    super.dispose();
  }
}
