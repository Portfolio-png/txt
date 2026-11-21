import 'package:core_erp/sheet/sheet.dart';
import 'package:core_erp/sheet/sheet_engine.dart';
import 'package:flutter_test/flutter_test.dart';

// Picking an existing Part Name on a row being entered (B): the name alone no
// longer says which part — two Pattis differ in alloy or thickness — so the
// pick is the NAME, and a part is opened only when the row's alloy and
// thickness are that part's too.
//
// The report: with a Patti on row 1, picking "Patti" on a new row to make a
// second one moved the cursor to row 1 and left the new row with no name;
// leaving it then said "Part Name is required."

const _alloy = 6;
const _thickness = 7;

class _Record {
  _Record(this.id);
  final int id;
  final String partCode = '';
  final DateTime createdAt = DateTime(2026, 11, 21, 10, 5);
}

class _Binding extends SheetBinding<Object?> {
  _Binding(this.id, this.stored);

  /// The part on file, under the id its Part Name option carries.
  final int id;
  final SheetDraft stored;
  final List<SheetDraft> written = [];

  @override
  String? get lastError => null;
  @override
  Future<List<Object?>?> save(List<SheetDraft> rows) async => null;
  @override
  Future<Object?> saveRow(SheetDraft row) async {
    written.add(row);
    return _Record(900);
  }

  @override
  List<SheetDraft> toDrafts(List<Object?> entities) => const [];
  @override
  SheetDraft? draftForId(int id) => id == this.id
      ? SheetDraft(sheetKey: 'item', entityId: id, values: stored.values)
      : null;
  @override
  Object? entityById(int id) => id == this.id ? 'part-$id' : null;
}

/// The demo sheet, its Part Name option standing for a part on file that is
/// MS 1.2.
({ItemMasterController ctrl, _Binding writer, ColumnOption nameOption, int nameColumn, SheetDraft seed}) _sheet() {
  final probe = ItemMasterController(binding: null, demoData: true);
  final seed = probe.groupItemController.draftAt(0).clone();
  final nameColumn = probe.groupItemController.sheetDef.columnBoundTo(SheetBindsTo.name)!.id;
  final nameOption = probe.groupItemController.options.firstWhere((o) => o.id == seed.get(nameColumn)!.optionId);
  probe.dispose();

  final stored = SheetDraft(sheetKey: 'item', values: seed.values)
    ..set(_alloy, const CellValue(columnId: _alloy, textValue: 'MS'))
    ..set(_thickness, const CellValue(columnId: _thickness, textValue: '1.2'));
  final writer = _Binding(nameOption.id, stored);
  final ctrl = ItemMasterController(binding: writer, demoData: true);
  ctrl.setExternal(false);
  return (ctrl: ctrl, writer: writer, nameOption: nameOption, nameColumn: nameColumn, seed: seed);
}

/// A row being entered: the fixture's group and type, the given alloy and
/// thickness, and no name yet.
SheetDraft _newRow(SheetDraft seed, int nameColumn, String alloy, String thickness) {
  final row = seed.clone();
  row.clear(nameColumn);
  row.set(_alloy, CellValue(columnId: _alloy, textValue: alloy));
  row.set(_thickness, CellValue(columnId: _thickness, textValue: thickness));
  return row;
}

void main() {
  test('the report: a second Patti in SS 1.5 keeps its name and its row, and saves as a new part', () async {
    final s = _sheet();
    addTearDown(s.ctrl.dispose);
    final sheet = s.ctrl.groupItemController;
    // Row 1 holds the Patti on file (MS 1.2); row 2 is the new one.
    sheet.replaceRowAt(0, s.writer.draftForId(s.nameOption.id)!);
    sheet.addRow(draft: _newRow(s.seed, s.nameColumn, 'SS', '1.5'));
    sheet.selectRow(1);

    sheet.setOption(s.nameColumn, s.nameOption, row: 1);

    expect(sheet.row, 1, reason: 'the cursor stays on the new row');
    expect(sheet.draftAt(1).entityId, isNull, reason: 'not the Patti on file');
    expect(SheetEngine.cellLabel(sheet.draftAt(1), s.nameColumn), s.nameOption.label, reason: 'the name stays');
    expect(s.ctrl.statusBarMessage, isNot(contains('already on row')));
    expect(sheet.errorsForRow(1)[s.nameColumn]?.message ?? '', isNot(contains('is required')));

    expect(await s.ctrl.commitRow(1), isTrue, reason: s.ctrl.statusBarMessage);
    expect(s.writer.written.single.entityId, isNull, reason: 'saved as a new part');
  });

  test('the same alloy and thickness IS that part: the cursor goes to the row it is on', () {
    final s = _sheet();
    addTearDown(s.ctrl.dispose);
    final sheet = s.ctrl.groupItemController;
    sheet.replaceRowAt(0, s.writer.draftForId(s.nameOption.id)!);
    sheet.addRow(draft: _newRow(s.seed, s.nameColumn, 'ms', '1.20'));
    sheet.selectRow(1);

    sheet.setOption(s.nameColumn, s.nameOption, row: 1);
    expect(sheet.row, 0);
    expect(s.ctrl.statusBarMessage, contains('already on row 1'));
  });

  test('picked with no alloy or thickness yet: just the name; filling them in to match opens the part', () {
    final s = _sheet();
    addTearDown(s.ctrl.dispose);
    final sheet = s.ctrl.groupItemController;
    sheet.replaceRowAt(0, _newRow(s.seed, s.nameColumn, '', ''));

    sheet.setOption(s.nameColumn, s.nameOption, row: 0);
    expect(sheet.draftAt(0).entityId, isNull, reason: 'a name alone does not say which Patti');

    sheet.updateValue(_alloy, const CellValue(columnId: _alloy, textValue: 'MS'), row: 0);
    expect(sheet.draftAt(0).entityId, isNull, reason: 'thickness still open');
    sheet.updateValue(_thickness, const CellValue(columnId: _thickness, textValue: '1.2'), row: 0);
    expect(sheet.draftAt(0).entityId, s.nameOption.id, reason: 'group, type, name, alloy and thickness all match: that part');
    expect(s.ctrl.statusBarMessage, contains('edits save to it'));
  });

  test('another thickness filled in instead: it stays a new part', () {
    final s = _sheet();
    addTearDown(s.ctrl.dispose);
    final sheet = s.ctrl.groupItemController;
    sheet.replaceRowAt(0, _newRow(s.seed, s.nameColumn, '', ''));
    sheet.setOption(s.nameColumn, s.nameOption, row: 0);
    sheet.updateValue(_alloy, const CellValue(columnId: _alloy, textValue: 'MS'), row: 0);
    sheet.updateValue(_thickness, const CellValue(columnId: _thickness, textValue: '2.0'), row: 0);
    expect(sheet.draftAt(0).entityId, isNull);
  });
}
