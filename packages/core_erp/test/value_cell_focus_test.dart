import 'package:core_erp/sheet/sheet.dart';
import 'package:core_erp/sheet/widgets/value_cell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A sheet cell takes focus when the cursor ARRIVES at it — never merely
// because the screen rebuilt. It used to re-request focus on every rebuild, so
// once the item sheet shared a page with ordinary text fields, each keystroke
// in one of them rebuilt the screen and the sheet's cursor cell snatched focus
// back after a single letter.

void main() {
  testWidgets('typing elsewhere is not interrupted by the sheet cursor cell',
      (tester) async {
    final sheet = SheetDef(id: 1, key: 'item', title: 'Item', columns: itemSheetColumns);
    final controller = SheetController(sheetDef: sheet);
    final nameColumn = sheet.columnBoundTo(SheetBindsTo.name)!;
    final other = TextEditingController();
    addTearDown(other.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Column(
            children: [
              SizedBox(
                height: 60,
                child: ValueCell(
                  column: nameColumn,
                  sheetDef: sheet,
                  controller: controller,
                  width: 200,
                  isSelected: true,
                ),
              ),
              TextField(
                key: const ValueKey('elsewhere'),
                controller: other,
                // Every keystroke rebuilds the sheet, as the screen does.
                onChanged: (_) => controller.updateValue(
                  nameColumn.id,
                  CellValue(columnId: nameColumn.id),
                ),
              ),
            ],
          ),
        ),
      ),
    ));

    // The sheet's cursor is on the cell: it takes focus once, on arrival.
    controller.focusCell(nameColumn.id, isHeader: false, row: 0);
    await tester.pump();

    // Somebody clicks into another field and types three letters.
    await tester.tap(find.byKey(const ValueKey('elsewhere')));
    await tester.pump();
    for (final text in ['k', 'ks', 'ksh']) {
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ));
      await tester.pump();
    }

    final field = tester.widget<EditableText>(find.descendant(
      of: find.byKey(const ValueKey('elsewhere')),
      matching: find.byType(EditableText),
    ));
    expect(field.focusNode.hasFocus, isTrue, reason: 'the cell must not take focus back');
    expect(other.text, 'ksh');
  });

  testWidgets('a locked (saved) row shows its value and takes no input', (tester) async {
    final sheet = SheetDef(id: 1, key: 'item', title: 'Item', columns: itemSheetColumns);
    final nameColumn = sheet.columnBoundTo(SheetBindsTo.name)!;
    final controller = SheetController(
      sheetDef: sheet,
      initialDraft: SheetDraft(sheetKey: 'item', entityId: 9, values: {
        nameColumn.id: CellValue(columnId: nameColumn.id, optionLabel: 'Patti'),
      }),
    )..setRowLocked(0, true);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => ValueCell(
            column: nameColumn,
            sheetDef: sheet,
            controller: controller,
            width: 200,
            isSelected: true,
          ),
        ),
      ),
    ));
    expect(find.text('Patti'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing, reason: 'nothing to type into');
    expect(find.byType(IgnorePointer), findsWidgets);

    controller.setRowLocked(0, false);
    await tester.pump();
    expect(find.byType(IgnorePointer).evaluate().where((e) => (e.widget as IgnorePointer).ignoring), isEmpty);
  });
}
