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
  Future<Object?> saveRow(SheetDraft row) async {
    written.add(row);
    return _Record(5);
  }

  @override
  List<SheetDraft> toDrafts(List<Object?> entities) => const [];

  @override
  SheetDraft? draftForId(int id) => id == 5 ? stored : null;
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
  ctrl.groupItemController.replaceRowAt(0, SheetDraft(sheetKey: 'item', entityId: 5, values: seed.values));
  // Opening a part places it clean; the edit is what makes it dirty.
  ctrl.groupItemController.draftAt(0).markDirty();
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
}
