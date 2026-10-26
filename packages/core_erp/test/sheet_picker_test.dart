import 'package:core_erp/sheet/sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The cell picker, which had two row-awareness leaks left after rows arrived.
//
// Phase 1 moved rows into the controller and gave writes a `row:`. The options
// popup was missed on both counts: it read the PARENT cell off `draft` (the
// selected row) and wrote party and contact picks with no row at all.
//
// Reachable because selection has two sources. `MiniTable` syncs the
// controller's cursor when a cell is tapped, but a host can also pass
// `rowDrafts` + `selectedRowIndex` and drive selection itself — which the PM
// prototype does, from its row switcher, without ever calling `selectRow`. The
// cell then renders as selected on row N while the controller's cursor is
// still on row 0, so the popup filtered by the wrong row's Group. These tests
// are set up in that shape.

SheetDef _sheet() => SheetDef(
  id: 1,
  key: 'item',
  title: 'Item',
  columns: const [
    ColumnDef(
      id: 1,
      sheetId: 1,
      label: 'Group',
      kind: ColumnKind.list,
      role: ColumnRole.group,
      position: 0,
      bindsTo: SheetBindsTo.group,
    ),
    ColumnDef(
      id: 2,
      sheetId: 1,
      label: 'Type',
      kind: ColumnKind.list,
      parentId: 1,
      position: 1,
      bindsTo: SheetBindsTo.set,
    ),
    ColumnDef(
      id: 3,
      sheetId: 1,
      label: 'Part Name',
      kind: ColumnKind.list,
      role: ColumnRole.item,
      parentId: 2,
      position: 2,
      bindsTo: SheetBindsTo.name,
    ),
  ],
);

/// Two groups, each with its own Type of the same shape — so filtering by the
/// wrong row's parent shows the wrong Types rather than none.
const _options = [
  ColumnOption(id: 10, columnId: 1, label: 'Switch Action'),
  ColumnOption(id: 11, columnId: 1, label: 'Cutout'),
  ColumnOption(id: 101, columnId: 2, parentOptionId: 10, label: 'Dolly'),
  ColumnOption(id: 102, columnId: 2, parentOptionId: 11, label: 'Plate'),
];

/// [selectedRow] is the HOST's selection, passed the way the PM prototype
/// passes it. The controller's own cursor stays where it was.
Future<SheetController> _pumpTable(
  WidgetTester tester, {
  int selectedRow = 0,
}) async {
  final controller = SheetController(
    sheetDef: _sheet(),
    options: _options,
    initialDrafts: [
      SheetDraft(
        sheetKey: 'item',
        values: {
          1: const CellValue(
            columnId: 1,
            optionId: 10,
            optionLabel: 'Switch Action',
          ),
        },
      ),
      SheetDraft(
        sheetKey: 'item',
        values: {
          1: const CellValue(columnId: 1, optionId: 11, optionLabel: 'Cutout'),
        },
      ),
    ],
  );
  addTearDown(controller.dispose);

  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: _Table(
          controller: controller,
          hostDrafts: true,
          selectedRow: selectedRow,
        ),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

/// Opens the picker on a cell.
///
/// Taps the cell's INNER tap target, not the keyed cell itself. A list cell
/// nests two: the outer one moves the controller's cursor, the inner one opens
/// the picker — and a tap at the keyed cell's centre lands on the outer, which
/// would sync the cursor and hide the very thing under test. A list cell draws
/// the inner one only once its row is selected.
Future<void> _openPicker(WidgetTester tester, String cellKey) async {
  final inner = find.descendant(
    of: find.byKey(ValueKey<String>(cellKey)),
    matching: find.byType(InkWell),
  );
  expect(
    inner,
    findsOneWidget,
    reason: 'a selected list cell should have an inner tap target',
  );
  await tester.tap(inner);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

SheetDef _partySheet() => SheetDef(
  id: 2,
  key: 'item_party',
  title: 'Party',
  columns: partySheetColumns,
);

const _parties = [
  Party(id: 1, name: 'Gold Medal', type: 'client'),
  Party(id: 2, name: 'Anchor', type: 'client'),
];

const _contacts = [
  Contact(
    id: 11,
    partyId: 1,
    name: 'Kissan Jain',
    designation: 'Director',
    phone: '9865656560',
    email: 'kissan@goldmedal.in',
  ),
  Contact(
    id: 13,
    partyId: 2,
    name: 'Kapil Shah',
    designation: 'Purchase Head',
    phone: '9820012345',
    email: 'kapil@anchor.com',
  ),
];

Future<SheetController> _pumpPartyTable(WidgetTester tester) async {
  final controller = SheetController(
    sheetDef: _partySheet(),
    parties: _parties,
    contacts: _contacts,
    initialDraft: SheetDraft(
      sheetKey: 'item_party',
      values: {
        20: const CellValue(columnId: 20, refId: 1, optionLabel: 'Gold Medal'),
      },
    ),
  );
  addTearDown(controller.dispose);

  tester.view.physicalSize = const Size(1800, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: _Table(controller: controller)),
    ),
  );
  await tester.pump();
  return controller;
}

/// A MiniTable that rebuilds when the controller notifies.
///
/// The real screen does this through `setState` on a controller listener. A
/// bare MiniTable does not listen, so without it a `notifyListeners` moves the
/// cursor and nothing on screen follows — including the keyboard focus that the
/// cursor is supposed to carry.
class _Table extends StatelessWidget {
  const _Table({
    required this.controller,
    this.hostDrafts = false,
    this.selectedRow = 0,
  });

  final SheetController controller;
  final bool hostDrafts;
  final int selectedRow;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => MiniTable(
          title: controller.sheetDef.title,
          tableGroup: TableGroup.groupItem,
          columns: controller.sheetDef.columns,
          sheetDef: controller.sheetDef,
          controller: controller,
          rowDrafts: hostDrafts
              ? [for (final draft in controller.drafts) draft.values]
              : const [],
          selectedRowIndex: selectedRow,
        ),
      ),
    );
  }
}

void main() {
  testWidgets('a picker on an unselected row offers that row’s own options', (
    tester,
  ) async {
    final controller = await _pumpTable(tester, selectedRow: 1);

    // The host says row 1; the controller's cursor is still on row 0. Row 1's
    // Group is Cutout, so its Type picker must offer Plate — not Dolly, which
    // belongs under row 0's Switch Action.
    expect(controller.row, 0, reason: 'the cursor was never synced');
    await _openPicker(tester, 'cell_item_1_2');

    expect(
      find.text('Plate'),
      findsOneWidget,
      reason: 'the picker should filter by row 1’s Group',
    );
    expect(
      find.text('Dolly'),
      findsNothing,
      reason: 'Dolly belongs under Switch Action, which is row 0’s Group',
    );
  });

  testWidgets('the picked option lands on the row that was tapped', (
    tester,
  ) async {
    final controller = await _pumpTable(tester, selectedRow: 1);

    await _openPicker(tester, 'cell_item_1_2');
    await tester.tap(find.text('Plate'));
    await tester.pump();

    expect(controller.draftAt(1).get(2)?.optionLabel, 'Plate');
    expect(
      controller.draftAt(0).get(2),
      isNull,
      reason: 'row 0 was never touched',
    );
  });

  testWidgets('tapping anywhere in a selected list cell opens its picker', (
    tester,
  ) async {
    // The content sat as a loose child of a Stack, so it was 20px tall at the
    // top of a 46px cell — and the picker's tap target is inside it. The lower
    // 26px, more than half the cell, only re-selected the row, so clicking the
    // middle of a cell looked like a dead control.
    await _pumpTable(tester);

    final cell = find.byKey(const ValueKey<String>('cell_item_0_1'));
    final inner = find.descendant(of: cell, matching: find.byType(InkWell));
    final cellRect = tester.getRect(cell);
    final innerRect = tester.getRect(inner.first);
    expect(
      innerRect.height,
      greaterThan(cellRect.height - 4),
      reason: 'the tap target should cover the cell, not just its text',
    );

    await tester.tap(cell);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Select Group'), findsOneWidget);
  });

  testWidgets('adding a new option keeps the case that was typed', (
    tester,
  ) async {
    // The add-new tile used the lowercased match query as the value, so a part
    // typed "Test Bracket" was filed as "test bracket" — and the tile showed
    // the lowercase back. Pressing Enter in the same field filed the original,
    // so the two routes disagreed.
    final controller = await _pumpTable(tester);

    await _openPicker(tester, 'cell_item_0_3');
    await tester.enterText(find.byType(TextField).last, 'Test Bracket');
    await tester.pump();

    expect(
      find.textContaining('Add "Test Bracket"'),
      findsOneWidget,
      reason: 'the tile should echo what was typed, not a lowercased copy',
    );

    await tester.tap(find.textContaining('Add "Test Bracket"'));
    await tester.pump();

    expect(controller.draftAt(0).get(3)?.optionLabel, 'Test Bracket');
  });

  testWidgets('pressing Enter and tapping the tile agree', (tester) async {
    final controller = await _pumpTable(tester);

    await _openPicker(tester, 'cell_item_0_3');
    await tester.enterText(find.byType(TextField).last, 'Test Bracket');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(controller.draftAt(0).get(3)?.optionLabel, 'Test Bracket');
  });

  testWidgets('options arriving while the dropdown is open show up in it', (
    tester,
  ) async {
    // The sheet was built with a snapshot of the options, so reference data
    // that landed a moment after it opened left it empty until it was closed
    // and reopened — and landing late is the normal case, because the screen
    // opens before the masters have loaded.
    final controller = SheetController(
      sheetDef: _sheet(),
      initialDrafts: [SheetDraft(sheetKey: 'item')],
    );
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: _Table(controller: controller)),
      ),
    );
    await tester.pump();

    await _openPicker(tester, 'cell_item_0_1');
    expect(find.text('Select Group'), findsOneWidget);
    expect(find.text('Primary Group'), findsNothing);

    controller.applyReferenceData(
      const SheetReferenceData(
        options: [ColumnOption(id: 10, columnId: 1, label: 'Primary Group')],
      ),
    );
    await tester.pump();

    expect(
      find.text('Primary Group'),
      findsOneWidget,
      reason: 'the open dropdown should follow the controller',
    );
  });

  testWidgets('an empty dropdown says why — parent first', (tester) async {
    // A fresh sheet: no Group chosen, so the Type picker has no parent to
    // hang off.
    final controller = SheetController(
      sheetDef: _sheet(),
      options: _options,
      initialDrafts: [SheetDraft(sheetKey: 'item')],
    );
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: _Table(controller: controller)),
      ),
    );
    await tester.pump();

    await _openPicker(tester, 'cell_item_0_2');
    expect(
      find.textContaining('Pick a Group first'),
      findsOneWidget,
      reason: 'blank space reads as a broken control',
    );
  });

  testWidgets('an empty dropdown says why — nothing entered yet', (
    tester,
  ) async {
    final controller = SheetController(
      sheetDef: _sheet(),
      options: const [
        ColumnOption(id: 10, columnId: 1, label: 'Primary Group'),
      ],
      initialDrafts: [
        SheetDraft(
          sheetKey: 'item',
          values: {
            1: const CellValue(
              columnId: 1,
              optionId: 10,
              optionLabel: 'Primary Group',
            ),
          },
        ),
      ],
    );
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: _Table(controller: controller)),
      ),
    );
    await tester.pump();

    // Group is chosen, so the Type picker has a parent — there are simply no
    // Types under it.
    await _openPicker(tester, 'cell_item_0_2');
    expect(find.textContaining('Nothing here yet'), findsOneWidget);
  });

  testWidgets('Alt+down opens the dropdown the status bar promises', (
    tester,
  ) async {
    // "Alt+↓ for dropdowns" has been in the status bar since the sheet was
    // written, and nothing handled the key.
    final controller = await _pumpTable(tester);

    // Focus the Group cell the way traversal does, without opening anything.
    controller.focusCell(1, row: 0);
    await tester.pump();
    expect(find.text('Select Group'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Select Group'), findsOneWidget);
  });

  group('the contact dropdown', () {
    testWidgets('offers only the chosen party’s people', (tester) async {
      // Was every contact the sheet knew, whatever company was picked — so a
      // part could be given a contact at a firm it was not developed for.
      await _pumpPartyTable(tester);

      await _openPicker(tester, 'cell_item_party_0_21');
      expect(find.text('Kissan Jain'), findsOneWidget);
      expect(
        find.text('Kapil Shah'),
        findsNothing,
        reason: 'Kapil is at Anchor; Gold Medal is the party on this row',
      );
    });

    testWidgets('picking one fills designation, phone and email', (
      tester,
    ) async {
      // The cell wrote the name with `updateValue` and left the three
      // projection columns blank. `pickContact`, the one method that filled
      // them, had no caller in the app.
      final controller = await _pumpPartyTable(tester);

      await _openPicker(tester, 'cell_item_party_0_21');
      await tester.tap(find.text('Kissan Jain'));
      await tester.pump();

      final sheet = controller.sheetDef;
      String? at(String binds) =>
          controller.draft.get(sheet.columnBoundTo(binds)!.id)?.textValue;

      expect(controller.draft.get(21)?.optionLabel, 'Kissan Jain');
      expect(at(SheetBindsTo.developedForDesignation), 'Director');
      expect(at(SheetBindsTo.developedForPhone), '9865656560');
      expect(at(SheetBindsTo.developedForEmail), 'kissan@goldmedal.in');
    });
  });
}
