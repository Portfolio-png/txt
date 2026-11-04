import 'package:core_erp/features/items/presentation/widgets/part_rows_form.dart';
import 'package:core_erp/sheet/sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// A part line's dropdown, picked from with the keyboard, then changed. After
// the first pick a field thought its list was still open — the flag was set
// on open and never cleared — so neither a click nor a key opened it again.

void main() {
  testWidgets('a dropdown picked by keyboard opens again on a click', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sheet = SheetController(
      sheetDef: SheetDef(id: 1, key: 'item', title: 'Item', columns: itemSheetColumns),
      options: const [
        ColumnOption(id: 10, columnId: 1, label: 'Primary Group'),
        ColumnOption(id: 11, columnId: 1, label: 'Raw Materials'),
      ],
    );
    addTearDown(sheet.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PartRowsForm(
            sheet: sheet,
            onAddPart: () {},
            actionBuilder: (_) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    final group = find.byKey(const ValueKey<String>('cell_item_0_1'));
    final picker = find.textContaining('Type to filter');

    // Opened, filtered and picked with the keyboard.
    await tester.tap(group);
    await tester.pumpAndSettle();
    expect(picker, findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Primary');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picker, findsNothing);
    expect(sheet.draftAt(0).get(1)?.optionLabel, 'Primary Group');

    // And changed with a click.
    await tester.tap(group);
    await tester.pumpAndSettle();
    expect(picker, findsOneWidget, reason: 'the list opens again');
    await tester.tap(find.text('Raw Materials').last);
    await tester.pumpAndSettle();
    expect(sheet.draftAt(0).get(1)?.optionLabel, 'Raw Materials');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
