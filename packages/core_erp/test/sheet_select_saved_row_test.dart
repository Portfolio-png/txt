import 'package:core_erp/sheet/sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A saved row is closed — no picker, no typing — until its Edit. It used to be
// closed to taps as well, so the only way onto a saved part was to open it for
// editing; now a tap selects it (and the sections below follow), and it stays
// closed.

SheetDef _sheet() => SheetDef(
  id: 1,
  key: 'test',
  title: 'Test Sheet',
  columns: const [
    ColumnDef(
      id: 1,
      sheetId: 1,
      label: 'Part Name',
      kind: ColumnKind.text,
      position: 0,
    ),
  ],
);

Future<SheetController> _pump(WidgetTester tester) async {
  final controller = SheetController(
    sheetDef: _sheet(),
    initialDrafts: [
      SheetDraft(
        sheetKey: 'test',
        values: {1: const CellValue(columnId: 1, textValue: 'Patti')},
      ),
      SheetDraft(
        sheetKey: 'test',
        values: {1: const CellValue(columnId: 1, textValue: 'Dolly')},
      ),
    ],
  );
  addTearDown(controller.dispose);
  controller.setRowLocked(0, true);
  controller.setRowLocked(1, true);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => MiniTable(
            title: 'Test',
            tableGroup: TableGroup.groupItem,
            columns: controller.sheetDef.columns,
            sheetDef: controller.sheetDef,
            controller: controller,
            selectedRowIndex: controller.row,
            rowStatusBuilder: (row) => Text('g$row'),
          ),
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  testWidgets('a tap on a saved row selects it and leaves it closed', (
    tester,
  ) async {
    final controller = await _pump(tester);
    expect(controller.row, 0);

    await tester.tap(find.text('Dolly'));
    await tester.pump();
    expect(controller.row, 1);
    expect(controller.isRowLocked(1), isTrue, reason: 'editing needs its Edit');
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the gutter selects its row too', (tester) async {
    final controller = await _pump(tester);
    await tester.tap(find.text('g1'));
    await tester.pump();
    expect(controller.row, 1);
  });

  test('a row keeps its key when its save hands it an id', () {
    final controller = SheetController(sheetDef: _sheet());
    addTearDown(controller.dispose);
    final key = controller.draft.rowKey;
    controller.markRowSaved(0, 42);
    expect(controller.draft.entityId, 42);
    expect(identical(controller.draft.rowKey, key), isTrue);
    controller.replaceRowAt(0, SheetDraft(sheetKey: 'test', entityId: 7));
    expect(identical(controller.draft.rowKey, key), isTrue);
    expect(controller.indexOfRowKey(key), 0);
  });
}
