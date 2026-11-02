import 'package:core_erp/sheet/sheet.dart';
import 'package:flutter_test/flutter_test.dart';

// A new part used to open with Group and Part Name already outlined in red —
// required, and empty, before anybody had typed anything. Every error still
// counts (a save refuses on all of them); "X is required" is only DRAWN once
// the cell has been left or the row has been saved once.

SheetDef _sheet() => SheetDef(
      id: 1,
      key: 'test',
      title: 'Test Sheet',
      columns: const [
        ColumnDef(
          id: 1,
          sheetId: 1,
          label: 'Group',
          kind: ColumnKind.list,
          role: ColumnRole.group,
          position: 0,
        ),
        ColumnDef(
          id: 2,
          sheetId: 1,
          label: 'Part Name',
          kind: ColumnKind.text,
          role: ColumnRole.item,
          position: 1,
        ),
      ],
    );

SheetController _controller({int rows = 1}) => SheetController(
      sheetDef: _sheet(),
      initialDrafts: [
        for (var i = 0; i < rows; i += 1) SheetDraft(sheetKey: 'test'),
      ],
    );

void main() {
  test('a pristine row counts its missing cells but draws none of them', () {
    final sheet = _controller();
    expect(sheet.errors.keys, containsAll(<int>[1, 2]));
    expect(sheet.visibleErrors(), isEmpty);
  });

  test('a cell that was left empty is drawn as missing; the others wait', () {
    final sheet = _controller();
    sheet.markTouched(2);
    expect(sheet.visibleErrors().keys, [2]);
    expect(sheet.visibleErrors()[2]!.code, 'required');
  });

  test('a save attempt shows every missing cell on that row only', () {
    final sheet = _controller(rows: 2);
    expect(sheet.validateRow(0), isFalse);
    expect(sheet.visibleErrors(row: 0).keys, containsAll(<int>[1, 2]));
    expect(sheet.visibleErrors(row: 1), isEmpty);

    expect(sheet.validateAll(), isFalse);
    expect(sheet.visibleErrors(row: 1).keys, containsAll(<int>[1, 2]));
  });

  test('a filled cell has nothing to show, touched or not', () {
    final sheet = _controller();
    sheet.updateTextValue(2, 'Patti');
    sheet.markTouched(2);
    expect(sheet.visibleErrors().containsKey(2), isFalse);
  });
}
