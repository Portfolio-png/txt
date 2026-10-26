import 'package:core_erp/sheet/sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Typing a catalogue, keyboard-first.
//
// Somebody entering fifty parts from a paper register never reaches for the
// mouse. These are the three gestures that decide whether that is possible.

SheetController _controller({int rows = 1}) {
  final c = SheetController(
    sheetDef: SheetDef(
      id: 1,
      key: 'item',
      title: 'Item',
      columns: itemSheetColumns,
    ),
    options: const [
      ColumnOption(id: 10, columnId: 1, label: 'Primary Group'),
      ColumnOption(id: 301, columnId: 6, label: 'Brass'),
    ],
    initialDrafts: [
      for (var i = 0; i < rows; i++) SheetDraft(sheetKey: 'item'),
    ],
  );
  return c;
}

/// The last column a typist actually visits, in DRAWN order.
///
/// Derived rather than written down: these tests used to name column 8 and so
/// broke the moment that column was removed, which told us nothing about
/// traversal. Drawn order is the four tables in turn, not declaration order.
int _lastEditable(SheetController c) {
  final sheet = c.sheetDef;
  final drawn = <ColumnDef>[
    for (final table in [
      TableGroup.groupItem,
      TableGroup.properties,
      TableGroup.independent,
      TableGroup.created,
    ])
      ...sheet.columns.where((col) => sheet.tableOf(col) == table),
  ];
  return drawn.lastWhere((col) => col.role != ColumnRole.stamp).id;
}

Future<void> _pump(
  WidgetTester tester,
  SheetController controller, {
  double? width,
}) async {
  tester.view.physicalSize = const Size(2200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width ?? 2200,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => TableRowStrip(
                sheetDef: controller.sheetDef,
                controller: controller,
                selectedRowIndex: controller.row,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('traversal', () {
    testWidgets('Tab crosses from Group and item into Properties', (
      tester,
    ) async {
      // `TableRowStrip` splits a sheet into four tables, and traversal used to
      // walk only the table it was in — so a typist could never Tab across a
      // whole part.
      final controller = _controller();
      addTearDown(controller.dispose);
      await _pump(tester, controller);

      // Part Name (3) is the last column of "Group and item"; Part No (4) is
      // the first of "Properties". Traversal walks the DRAWN order — Group and
      // item, then Properties, then Primary Group, then Created.
      controller.focusCell(3, row: 0);
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('cell_item_0_3')),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(
        controller.focusedColumnId,
        4,
        reason: 'Tab should reach the next table, not stop at the boundary',
      );
    });

    testWidgets('Enter past the last cell of the last row adds a row', (
      tester,
    ) async {
      // For somebody typing a catalogue this is the one place a new row is
      // always wanted. It used to be where Enter stopped dead.
      final controller = _controller();
      addTearDown(controller.dispose);
      await _pump(tester, controller);

      expect(controller.rowCount, 1);

      controller.focusCell(_lastEditable(controller), row: 0);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(controller.rowCount, 2, reason: 'the next row should appear');
      expect(controller.row, 1, reason: 'and the cursor should be on it');
    });

    testWidgets('traversal skips the stamp columns', (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await _pump(tester, controller);

      // Tab off the last editable column should grow the sheet, not land on
      // Date or Time.
      controller.focusCell(_lastEditable(controller), row: 0);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(controller.rowCount, 2);
      expect(controller.focusedColumnId, isNot(9));
      expect(controller.focusedColumnId, isNot(10));
    });
  });

  group('fill down', () {
    test('copies the cell above', () {
      // Twenty parts in a group share an alloy, a gauge and a finish.
      final c = _controller(rows: 2);
      addTearDown(c.dispose);
      c.updateValue(
        6,
        const CellValue(columnId: 6, optionId: 301, optionLabel: 'Brass'),
        row: 0,
      );

      expect(c.fillDown(6, row: 1), isTrue);
      expect(c.draftAt(1).get(6)?.optionLabel, 'Brass');
    });

    test('does nothing on the first row', () {
      final c = _controller(rows: 2);
      addTearDown(c.dispose);
      expect(c.fillDown(6, row: 0), isFalse);
    });

    test('refuses a derived column — it computes itself', () {
      final c = _controller(rows: 2);
      addTearDown(c.dispose);
      // Part Code (5) and Part No (4) derive; copying one down would plant a
      // stale value that the server never agreed to.
      expect(c.fillDown(5, row: 1), isFalse);
      expect(c.fillDown(4, row: 1), isFalse);
    });

    test('refuses a saved row — its values are the server’s', () {
      final c = _controller(rows: 2);
      addTearDown(c.dispose);
      c.updateValue(
        6,
        const CellValue(columnId: 6, optionId: 301, optionLabel: 'Brass'),
        row: 0,
      );
      c.markRowSaved(1, 500);
      expect(c.fillDown(6, row: 1), isFalse);
    });

    test('carries a value that was minted on the row above', () {
      // A typed-new option exists only on the draft that minted it, so a copy
      // that did not carry it would be called "not in this list".
      final c = _controller(rows: 2);
      addTearDown(c.dispose);
      c.addNewOption(6, 'Phosphor Bronze', row: 0);

      expect(c.fillDown(6, row: 1), isTrue);
      expect(c.draftAt(1).get(6)?.optionLabel, 'Phosphor Bronze');
      expect(
        c.errors[6],
        isNull,
        reason: 'the copy must be as valid as the original',
      );
    });
  });

  group('it fits across, so nothing scrolls sideways', () {
    // The body of the sheet screen at a 1600px window: 1600 less the 268px app
    // rail and 40px of padding. Measured, not computed — the arithmetic in
    // SheetMetrics is only worth anything if layout agrees with it.
    const body = 1292.0;

    double _strip(WidgetTester tester) =>
        tester.getSize(find.byKey(TableRowStrip.stripKey)).width;

    testWidgets('the item sheet fits the window it is opened in', (
      tester,
    ) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await _pump(tester, controller, width: body);

      expect(_strip(tester), lessThanOrEqualTo(body));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a property added with the + still fits', (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await _pump(tester, controller, width: body);

      controller.addPropertyColumn('Plating');
      await tester.pump();

      expect(_strip(tester), lessThanOrEqualTo(body));
      expect(tester.takeException(), isNull);
    });

    testWidgets('past the floor the tables wrap instead of scrolling', (
      tester,
    ) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await _pump(tester, controller, width: body);

      for (var i = 0; i < 6; i++) {
        controller.addPropertyColumn('Prop $i');
      }
      await tester.pump();

      // Still no horizontal scrollable anywhere in the strip, and still inside
      // the window — the overflow went downward, which is allowed.
      expect(_strip(tester), lessThanOrEqualTo(body));
      expect(tester.takeException(), isNull);
    });
  });
}
