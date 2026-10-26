import 'package:core_erp/sheet/sheet.dart';
import 'package:flutter_test/flutter_test.dart';

// Rows, which the sheet engine did not have.
//
// It held ONE `SheetDraft` per controller, `final`. The widgets rendered extra
// rows from a `rowDrafts` list passed in from outside, but every write landed
// on that single shared draft whatever row had been clicked — so typing in a
// cell and then selecting another row silently discarded the edit, and nothing
// anywhere could notice.
//
// These tests drive `SheetController` directly rather than through
// `ItemMasterController`'s hardcoded fixtures, so they say something about the
// engine rather than about one screen's demo data.

/// A minimal two-column sheet: a Group list and a free-text Part Name.
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
          position: 1,
        ),
      ],
    );

SheetController _controller({int rows = 1}) {
  return SheetController(
    sheetDef: _sheet(),
    initialDrafts: [
      for (var i = 0; i < rows; i += 1) SheetDraft(sheetKey: 'test'),
    ],
  );
}

void main() {
  group('leaving a row', () {
    SheetController make() => SheetController(
          sheetDef: SheetDef(
            id: 1,
            key: 'item',
            title: 'Item',
            columns: itemSheetColumns,
          ),
          initialDrafts: [SheetDraft(sheetKey: 'item')],
        );

    test('Add row reports the row it left', () {
      // The cursor leaves a row by three routes and a host hooked to only the
      // first silently skipped the other two — visible in an e2e run where the
      // first row still read NEW RECORD after Add row had moved on from it.
      final c = make();
      addTearDown(c.dispose);
      final left = <int>[];
      c.onRowLeft = left.add;

      c.addRow();
      expect(left, [0]);
      expect(c.row, 1);
    });

    test('clicking another row reports it', () {
      final c = make();
      addTearDown(c.dispose);
      c.addRow();
      final left = <int>[];
      c.onRowLeft = left.add;

      c.selectRow(0);
      expect(left, [1]);
    });

    test('Tab or Enter running into the next row reports it', () {
      final c = make();
      addTearDown(c.dispose);
      c.addRow();
      c.selectRow(0);
      final left = <int>[];
      c.onRowLeft = left.add;

      // What traversal does at the end of a row.
      c.focusCell(1, row: 1);
      expect(left, [0]);
    });

    test('staying on the same row reports nothing', () {
      final c = make();
      addTearDown(c.dispose);
      final left = <int>[];
      c.onRowLeft = left.add;

      c.selectRow(0);
      c.focusCell(3, row: 0);
      expect(left, isEmpty);
    });
  });

  group('rows', () {
    test('a controller always has at least one row', () {
      final c = SheetController(sheetDef: _sheet());
      expect(c.rowCount, 1);
      expect(c.row, 0);
      // And an empty list does not produce a rowless sheet with nowhere to type.
      final empty = SheetController(sheetDef: _sheet(), initialDrafts: const []);
      expect(empty.rowCount, 1);
    });

    test('editing one row leaves the others alone', () {
      // The whole reason this exists.
      final c = _controller(rows: 3);

      c.selectRow(0);
      c.updateTextValue(2, 'Patti');
      c.selectRow(1);
      c.updateTextValue(2, 'Dabbi');
      c.selectRow(2);
      c.updateTextValue(2, 'Threading Patti');

      expect(c.draftAt(0).get(2)?.textValue, 'Patti');
      expect(c.draftAt(1).get(2)?.textValue, 'Dabbi');
      expect(c.draftAt(2).get(2)?.textValue, 'Threading Patti');
    });

    test('switching rows preserves what was typed in each', () {
      final c = _controller(rows: 2);
      c.selectRow(0);
      c.updateTextValue(2, 'Patti');
      c.selectRow(1);
      expect(c.draft.get(2), isNull, reason: 'row 1 was never typed in');
      c.selectRow(0);
      expect(
        c.draft.get(2)?.textValue,
        'Patti',
        reason: 'going back to a row must not have lost its edit',
      );
    });

    test('a write can name its row without moving the cursor', () {
      final c = _controller(rows: 2);
      c.selectRow(0);
      c.updateTextValue(2, 'Dabbi', row: 1);
      expect(c.row, 0, reason: 'naming a row is not selecting it');
      expect(c.draftAt(1).get(2)?.textValue, 'Dabbi');
      expect(c.draftAt(0).get(2), isNull);
    });

    test('draft still means the selected row, so old readers keep working', () {
      final c = _controller(rows: 2);
      c.selectRow(1);
      c.updateTextValue(2, 'Dabbi');
      expect(c.draft.get(2)?.textValue, 'Dabbi');
      expect(identical(c.draft, c.draftAt(1)), isTrue);
    });

    test('adding a row selects it; removing keeps the cursor in range', () {
      final c = _controller(rows: 1);
      final added = c.addRow();
      expect(added, 1);
      expect(c.rowCount, 2);
      expect(c.row, 1);

      c.removeRow(1);
      expect(c.rowCount, 1);
      expect(c.row, 0, reason: 'the cursor cannot point past the last row');
    });

    test('the last row is never removed', () {
      final c = _controller(rows: 1);
      c.removeRow(0);
      expect(c.rowCount, 1, reason: 'a sheet with no rows has nowhere to type');
    });

    test('the cursor is one pair, set together', () {
      // Row and column used to live in different objects — the column on the
      // controller, the row on the parent widget — so nothing could say which
      // cell was active in one move.
      final c = _controller(rows: 2);
      c.focusCell(2, row: 1);
      expect(c.row, 1);
      expect(c.focusedColumnId, 2);
    });

    test('replaceRows loads a whole sheet and keeps the cursor in range', () {
      final c = _controller(rows: 3);
      c.selectRow(2);
      c.replaceRows([SheetDraft(sheetKey: 'test')]);
      expect(c.rowCount, 1);
      expect(c.row, 0);
    });
  });

  group('validation per row', () {
    test('errors answer for the selected row, and count across all of them', () {
      // Group is a required role column, so a blank one is an error on every
      // row that leaves it blank.
      final c = _controller(rows: 2);
      expect(c.errorCount, greaterThan(0));

      c.selectRow(0);
      final rowZero = c.errors;
      c.selectRow(1);
      expect(c.errors.keys, rowZero.keys, reason: 'both rows fail the same way');

      expect(c.errorsForRow(0).isNotEmpty, isTrue);
      expect(c.errorsForRow(1).isNotEmpty, isTrue);
    });

    test('validateAll refuses while ANY row is bad, not just the selected one', () {
      final c = _controller(rows: 2);
      expect(c.validateAll(), isFalse);
      expect(
        c.errorCount,
        greaterThanOrEqualTo(2),
        reason: 'a save writes every row, so every row has to be clean',
      );
    });

    test('removing a column clears it from every row, not just the current one',
        () {
      final c = _controller(rows: 2);
      c.updateTextValue(2, 'Patti', row: 0);
      c.updateTextValue(2, 'Dabbi', row: 1);

      c.removeColumn(2);

      expect(c.draftAt(0).get(2), isNull);
      expect(
        c.draftAt(1).get(2),
        isNull,
        reason: 'the column is gone from the sheet, so it is gone from all rows',
      );
    });
  });
}
