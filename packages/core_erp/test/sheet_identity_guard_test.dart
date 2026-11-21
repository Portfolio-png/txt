import 'package:core_erp/sheet/sheet.dart';
import 'package:core_erp/sheet/sheet_engine.dart';
import 'package:flutter_test/flutter_test.dart';

// The guard: a saved part's Alloy or Thickness changed on the sheet is a
// different part — same group and name, its own part number — so it is asked
// about rather than saved over the part that was opened.

const _alloy = 6;
const _thickness = 7;

class _Record {
  _Record(this.id);
  final int id;
  final String partCode = '';
  final DateTime createdAt = DateTime(2026, 11, 21, 10, 5);
}

class _Binding extends SheetBinding<Object?> {
  _Binding(this.stored);

  /// The opened part as it is on file.
  final SheetDraft stored;
  final List<SheetDraft> written = [];
  final List<List<SheetDraft>> savedAll = [];

  @override
  String? get lastError => null;

  @override
  Future<List<Object?>?> save(List<SheetDraft> rows) async {
    savedAll.add(rows);
    return [_Record(5)];
  }

  @override
  List<SheetDraft> toDrafts(List<Object?> entities) => const [];

  @override
  SheetDraft? draftForId(int id) => id == 5 ? stored : null;

  /// Part #5 was developed for a client, Gold Medal (id 77).
  @override
  Object? entityById(int id) => id == 5 ? 'part-5' : null;

  @override
  ({SheetDraft deal, Set<int> ticked})? dealOf(Object? entity) {
    if (entity != 'part-5') return null;
    final party = dealSheetColumns.firstWhere((c) => c.bindsTo == SheetBindsTo.developedForParty).id;
    return (
      deal: SheetDraft(sheetKey: 'item_party', values: {
        party: CellValue(columnId: party, refId: 77, optionLabel: 'Gold Medal', textValue: 'Gold Medal'),
      }),
      ticked: const <int>{},
    );
  }

  /// What the controller would send as the deal, read at the moment of a row
  /// save — as the real binding reads it.
  SheetDraft? Function()? dealAtSave;
  final List<SheetDraft?> dealsSent = [];

  @override
  Future<Object?> saveRow(SheetDraft row) async {
    dealsSent.add(dealAtSave?.call());
    written.add(row);
    return _Record(5);
  }
}

/// A sheet whose row 0 is part #5, opened and edited. [storedAlloy] /
/// [storedThickness] say what the part has on file; the row keeps the
/// fixture's values, which then read as the edit.
({ItemMasterController ctrl, _Binding writer, String rowAlloy, String rowThickness}) _opened({
  String? storedAlloy,
  String? storedThickness,
}) {
  final probe = ItemMasterController(binding: _Binding(SheetDraft(sheetKey: 'item')), demoData: true);
  final seed = probe.groupItemController.draftAt(0);
  final rowAlloy = SheetEngine.cellLabel(seed, _alloy);
  final rowThickness = SheetEngine.cellLabel(seed, _thickness);
  probe.dispose();

  final stored = SheetDraft(sheetKey: 'item', entityId: 5, values: seed.values);
  if (storedAlloy != null) stored.set(_alloy, CellValue(columnId: _alloy, textValue: storedAlloy));
  if (storedThickness != null) stored.set(_thickness, CellValue(columnId: _thickness, textValue: storedThickness));
  final writer = _Binding(stored);
  final ctrl = ItemMasterController(binding: writer, demoData: true);
  ctrl.setExternal(false);
  // Opened as it is on file, then edited back to the fixture's values — the
  // order a worker does it in, so what the row "was" is the stored part.
  final sheet = ctrl.groupItemController;
  sheet.replaceRowAt(0, SheetDraft(sheetKey: 'item', entityId: 5, values: stored.values));
  for (final column in const [_alloy, _thickness]) {
    final typed = seed.get(column);
    if (typed != null) sheet.updateValue(column, typed, row: 0);
  }
  sheet.draftAt(0).markDirty();
  return (ctrl: ctrl, writer: writer, rowAlloy: rowAlloy, rowThickness: rowThickness);
}

void main() {
  test('the fixture has an alloy and a thickness to change', () {
    final s = _opened();
    addTearDown(s.ctrl.dispose);
    expect(s.rowAlloy, isNotEmpty);
    expect(s.rowThickness, isNotEmpty);
  });

  test('an opened part whose alloy changed is asked about; Cancel writes nothing', () async {
    final s = _opened(storedAlloy: 'Titanium Gr 9');
    addTearDown(s.ctrl.dispose);
    final asked = <IdentityChange>[];
    s.ctrl.confirmIdentityChange = (change) async {
      asked.add(change);
      return IdentityChangeChoice.cancel;
    };

    expect(await s.ctrl.commitRow(0), isFalse);
    expect(asked, hasLength(1));
    expect(asked.single.cells.single.label, 'Alloy');
    expect(asked.single.cells.single.from, 'Titanium Gr 9');
    expect(asked.single.cells.single.to, s.rowAlloy);
    expect(s.writer.written, isEmpty, reason: 'the part on file is untouched');
    expect(s.ctrl.statusBarMessage, contains('the part on file is unchanged'));
    expect(s.ctrl.groupItemController.draftAt(0).isDirtySinceSave, isTrue, reason: 'what was typed stays');
  });

  test('"Change this part" saves it onto the opened part', () async {
    final s = _opened(storedThickness: '9.9');
    addTearDown(s.ctrl.dispose);
    s.ctrl.confirmIdentityChange = (change) async {
      expect(change.cells.single.label, 'Thickness');
      return IdentityChangeChoice.changeThisPart;
    };
    expect(await s.ctrl.commitRow(0), isTrue);
    expect(s.writer.written.single.entityId, 5);
  });

  test('nothing is asked when alloy and thickness are as filed — "1.20" is "1.2"', () async {
    final s = _opened();
    addTearDown(s.ctrl.dispose);
    var asked = 0;
    s.ctrl.confirmIdentityChange = (_) async {
      asked += 1;
      return IdentityChangeChoice.cancel;
    };
    expect(await s.ctrl.commitRow(0), isTrue);
    expect(asked, 0);
    expect(SheetEngine.identityValue('1.20'), SheetEngine.identityValue('1.2'));
    expect(SheetEngine.identityValue(' 18  SWG '), '18 swg');
    expect(SheetEngine.identityValue('10'), '10', reason: 'not "1"');
    expect(SheetEngine.identityValue('0.50'), '0.5');
  });

  test('a new row is never asked: it has no identity on file yet', () async {
    final s = _opened(storedAlloy: 'Titanium Gr 9');
    addTearDown(s.ctrl.dispose);
    final sheet = s.ctrl.groupItemController;
    sheet.replaceRowAt(0, SheetDraft(sheetKey: 'item', values: sheet.draftAt(0).values));
    sheet.draftAt(0).markDirty();
    var asked = 0;
    s.ctrl.confirmIdentityChange = (_) async {
      asked += 1;
      return IdentityChangeChoice.cancel;
    };
    await s.ctrl.commitRow(0);
    expect(asked, 0);
  });

  test('the whole-sheet save asks too, and Cancel stops it', () async {
    final s = _opened(storedAlloy: 'Titanium Gr 9');
    addTearDown(s.ctrl.dispose);
    s.ctrl.confirmIdentityChange = (_) async => IdentityChangeChoice.cancel;
    expect(await s.ctrl.saveItem(), isFalse);
    expect(s.writer.savedAll, isEmpty);
  });

  group('B: same group and name, another alloy or thickness, is another part', () {
    test('"Make a new part" leaves the opened part alone and saves a new one from the row', () async {
      final s = _opened(storedAlloy: 'Titanium Gr 9');
      addTearDown(s.ctrl.dispose);
      final sheet = s.ctrl.groupItemController;
      final rowKey = sheet.draftAt(0).rowKey;
      s.ctrl.confirmIdentityChange = (_) async => IdentityChangeChoice.makeNewPart;

      expect(await s.ctrl.commitRow(0), isTrue);
      final sent = s.writer.written.single;
      expect(sent.entityId, isNull, reason: 'a new part, not an update of #5');
      expect(SheetEngine.cellLabel(sent, _alloy), s.rowAlloy, reason: 'with the alloy typed');
      // The old part's stamps are not the new part's. (Its number and code
      // cells are re-derived as a preview; the server numbers it per name.)
      for (final column in sheet.sheetDef.columns.where((c) => c.isStamp)) {
        expect(SheetEngine.cellLabel(sent, column.id), isEmpty, reason: '${column.label} is set when it is made');
      }
      expect(identical(sent.rowKey, rowKey), isTrue, reason: 'same row: held dies and machines go with it');
    });

    test('an edit that repeats a part already on file is refused on the sheet, before anything is asked', () async {
      final s = _opened(storedAlloy: 'Titanium Gr 9');
      addTearDown(s.ctrl.dispose);
      final sheet = s.ctrl.groupItemController;
      final name = sheet.sheetDef.columnBoundTo(SheetBindsTo.name)!;
      // A sibling on file with exactly the alloy and thickness the row now has.
      final siblingKey = SheetEngine.identityKeyOf(sheet.sheetDef, sheet.draftAt(0), name.id);
      sheet.applyReferenceData(SheetReferenceData(options: sheet.options, existingPaths: {siblingKey}));
      var asked = 0;
      s.ctrl.confirmIdentityChange = (_) async {
        asked += 1;
        return IdentityChangeChoice.makeNewPart;
      };

      expect(await s.ctrl.commitRow(0), isFalse);
      expect(s.writer.written, isEmpty);
      expect(asked, 0, reason: 'a duplicate is refused outright; there is nothing to choose');
      expect(sheet.firstErrorOn(0), contains('already exists'));
      expect(sheet.firstErrorOn(0), contains('Alloy'));
    });

    test('two rows, one name, different alloys: neither is a duplicate; same alloy and thickness is', () {
      final probe = ItemMasterController(binding: null, demoData: true);
      addTearDown(probe.dispose);
      final sheet = probe.groupItemController.sheetDef;
      final row = probe.groupItemController.draftAt(0);
      final name = sheet.columnBoundTo(SheetBindsTo.name)!;
      final key = SheetEngine.identityKeyOf(sheet, row, name.id);
      final other = SheetDraft(sheetKey: 'item', values: row.values)
        ..set(_alloy, const CellValue(columnId: _alloy, textValue: 'Titanium Gr 9'));
      final otherKey = SheetEngine.identityKeyOf(sheet, other, name.id);
      expect(otherKey, isNot(key));

      Map<int, ValidationError> errorsWith(Set<String> taken, SheetDraft draft) =>
          SheetEngine.validate(sheet, draft, allOptions: probe.groupItemController.options, existingPaths: taken);
      expect(errorsWith({key}, other)[name.id]?.code, isNot('duplicate_item'));
      expect(errorsWith({key}, row)[name.id]?.code, 'duplicate_item');
      expect(errorsWith({key}, row)[name.id]?.message, contains('Alloy'));
      expect(SheetEngine.identityKey('A › Washer', ['', '']), 'a › washer', reason: 'no alloy or thickness: keyed as before');
    });

    test('a reload while an opened part is being edited does not erase a sibling\'s key', () {
      final s = _opened();
      addTearDown(s.ctrl.dispose);
      final sheet = s.ctrl.groupItemController;
      final name = sheet.sheetDef.columnBoundTo(SheetBindsTo.name)!;
      final asOpened = SheetEngine.identityKeyOf(sheet.sheetDef, sheet.draftAt(0), name.id);
      // Edited to a sibling's alloy...
      sheet.updateValue(_alloy, const CellValue(columnId: _alloy, textValue: 'Titanium Gr 9'), row: 0);
      final sibling = SheetEngine.identityKeyOf(sheet.sheetDef, sheet.draftAt(0), name.id);
      // ...and the reference data reloads: the sibling's key is taken, as is
      // the opened part's own (which is withdrawn for its own row).
      sheet.applyReferenceData(SheetReferenceData(options: sheet.options, existingPaths: {asOpened, sibling}));
      expect(sheet.errorsForRow(0)[name.id]?.code, 'duplicate_item',
          reason: 'the edit repeats the sibling; withdrawing the edited key used to hide that');
    });
  });

  test('"Make a new part" does not carry the opened part\'s Developed For: it is a whole new part', () async {
    final s = _opened(storedAlloy: 'Titanium Gr 9');
    addTearDown(s.ctrl.dispose);
    final party = dealSheetColumns.firstWhere((c) => c.bindsTo == SheetBindsTo.developedForParty).id;
    expect(s.ctrl.clientVendorController.draft.get(party)?.refId, 77, reason: 'opened with its deal on screen');
    // And the deal edited before the choice: an unsaved edit stays with its
    // row, so this is the case where the old part's deal would ride along.
    final quote = dealSheetColumns.firstWhere((c) => c.bindsTo == SheetBindsTo.developedForQuotation).id;
    s.ctrl.clientVendorController.updateValue(quote, CellValue(columnId: quote, textValue: '5000', intValue: 5000));
    s.writer.dealAtSave = s.ctrl.dealDraftForSave;
    s.ctrl.confirmIdentityChange = (_) async => IdentityChangeChoice.makeNewPart;

    // Without the reset the edited deal stayed on the row: the save either
    // carried the old part's client and quotation onto the new part, or (as
    // here, the deal being incomplete) was refused over it.
    expect(await s.ctrl.commitRow(0), isTrue);
    expect(s.writer.written.single.entityId, isNull);
    final dealSent = s.writer.dealsSent.single;
    expect(dealSent?.get(party)?.refId, isNull, reason: 'Gold Medal was the old part\'s client, not the new one\'s');
    expect(dealSent?.get(quote)?.textValue ?? '', isEmpty, reason: 'nor its quotation, edited or not');
  });

  test('"Change this part" keeps the opened part\'s Developed For', () async {
    final s = _opened(storedAlloy: 'Titanium Gr 9');
    addTearDown(s.ctrl.dispose);
    final party = dealSheetColumns.firstWhere((c) => c.bindsTo == SheetBindsTo.developedForParty).id;
    s.writer.dealAtSave = s.ctrl.dealDraftForSave;
    s.ctrl.confirmIdentityChange = (_) async => IdentityChangeChoice.changeThisPart;
    expect(await s.ctrl.commitRow(0), isTrue);
    expect(s.writer.dealsSent.single?.get(party)?.refId, 77);
  });
}
