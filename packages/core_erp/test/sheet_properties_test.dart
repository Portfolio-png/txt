import 'package:core_erp/sheet/sheet.dart';
import 'package:flutter_test/flutter_test.dart';

// Properties ARE the variation tree, and the part code is built from them.
//
// Two rules that have to hold together: a shop can add whatever top-level
// property it likes, and the code at the end of the row folds every one of
// them in. A property that did not reach the code would be a column that
// changes nothing — the most confusing possible outcome of pressing +.

SheetController _sheet() => SheetController(
      sheetDef: SheetDef(
        id: 1,
        key: 'item',
        title: 'Item',
        columns: itemSheetColumns,
      ),
      options: const [ColumnOption(id: 10, columnId: 1, label: 'Switch Action')],
      counters: {'Switch Action › Patti': 47},
      initialDraft: SheetDraft(sheetKey: 'item', values: {
        1: const CellValue(
          columnId: 1,
          optionId: 10,
          optionLabel: 'Switch Action',
        ),
        3: const CellValue(columnId: 3, optionLabel: 'Patti', isNew: true),
      }),
    );

String? _code(SheetController c) {
  final column = c.sheetDef.columnBoundTo(SheetBindsTo.partCode)!;
  return c.draft.get(column.id)?.textValue;
}

void main() {
  group('the part code is built from the properties', () {
    test('every top-level property contributes', () {
      final c = _sheet();
      addTearDown(c.dispose);

      c.updateValue(
        6,
        const CellValue(columnId: 6, optionLabel: 'Brass'),
      );
      c.updateValue(
        7,
        const CellValue(columnId: 7, optionLabel: '22 Gauge'),
      );

      // A third property, added the way the + adds one — the two the sheet
      // ships with would not show that an ARBITRARY property reaches the code,
      // which is the thing being claimed.
      c.addPropertyColumn('Finish');
      final finish =
          c.sheetDef.columns.firstWhere((col) => col.label == 'Finish');
      c.updateValue(
        finish.id,
        CellValue(columnId: finish.id, optionLabel: 'Nickel'),
      );

      // SA P (Switch Action › Patti) + B 22G N + 48.
      expect(_code(c), 'SAPB22GN48');
    });

    test('the gauges that matter stay apart', () {
      final a = _sheet();
      final b = _sheet();
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      a.updateValue(7, const CellValue(columnId: 7, optionLabel: '22 Gauge'));
      b.updateValue(7, const CellValue(columnId: 7, optionLabel: '24 Gauge'));

      expect(_code(a), isNot(_code(b)));
      expect(_code(a), contains('22G'));
      expect(_code(b), contains('24G'));
    });

    test('an empty property contributes nothing', () {
      final c = _sheet();
      addTearDown(c.dispose);
      c.updateValue(6, const CellValue(columnId: 6, optionLabel: 'Brass'));
      expect(_code(c), 'SAPB48');
    });

    test('a part with no properties keeps the bare trunk', () {
      final c = _sheet();
      addTearDown(c.dispose);
      expect(_code(c), 'SAP48');
    });

    test('with no group path there is no code, properties or not', () {
      // A bare running number is not a part code, and neither is a string of
      // property letters with nothing to attach them to.
      final c = SheetController(
        sheetDef: SheetDef(
          id: 1,
          key: 'item',
          title: 'Item',
          columns: itemSheetColumns,
        ),
        initialDraft: SheetDraft(sheetKey: 'item', values: {
          6: const CellValue(columnId: 6, optionLabel: 'Brass'),
        }),
      );
      addTearDown(c.dispose);
      expect(_code(c), '');
    });
  });

  group('adding a property', () {
    test('it binds into the variation tree', () {
      // A column with no `bindsTo` is a cell that goes nowhere: typed into,
      // saved, and absent from the part.
      final c = _sheet();
      addTearDown(c.dispose);

      c.addPropertyColumn('Plating');
      final added =
          c.sheetDef.columns.firstWhere((col) => col.label == 'Plating');

      expect(added.bindsTo, 'variation:Plating');
      expect(c.sheetDef.variationColumns.map((col) => col.label),
          contains('Plating'));
    });

    test('it lands BEFORE the part code, so the code folds it in', () {
      final c = _sheet();
      addTearDown(c.dispose);

      c.addPropertyColumn('Plating');
      final added =
          c.sheetDef.columns.firstWhere((col) => col.label == 'Plating');
      final code = c.sheetDef.columnBoundTo(SheetBindsTo.partCode)!;

      expect(added.position, lessThan(code.position));

      c.updateValue(
        added.id,
        CellValue(columnId: added.id, optionLabel: 'Satin'),
      );
      expect(_code(c), 'SAPS48', reason: 'S for Satin, folded into the code');
    });

    test('it stays before the stamps', () {
      final c = _sheet();
      addTearDown(c.dispose);
      c.addPropertyColumn('Plating');

      final added =
          c.sheetDef.columns.firstWhere((col) => col.label == 'Plating');
      for (final stamp in c.sheetDef.columns.where((col) => col.isStamp)) {
        expect(added.position, lessThan(stamp.position));
      }
    });

    test('an unnamed property is not added', () {
      final c = _sheet();
      addTearDown(c.dispose);
      final before = c.sheetDef.columns.length;
      c.addPropertyColumn('   ');
      expect(c.sheetDef.columns, hasLength(before));
    });
  });
}
