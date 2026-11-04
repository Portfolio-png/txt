import 'package:core_erp/core/widgets/even_grid.dart';
import 'package:core_erp/features/items/presentation/widgets/part_rows_form.dart';
import 'package:core_erp/sheet/sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A part line with its photo shown big: beside the fields, a square exactly
// as tall as they are, with Save and × under it. The other lines keep their
// small photo above Save.

SheetController _sheet() => SheetController(
  sheetDef: SheetDef(id: 1, key: 'item', title: 'Item', columns: itemSheetColumns),
  initialDrafts: [SheetDraft(sheetKey: 'item'), SheetDraft(sheetKey: 'item')],
);

Future<SheetController> _pump(
  WidgetTester tester, {
  int? showcaseRow,
  double width = 1400,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final sheet = _sheet();
  addTearDown(sheet.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PartRowsForm(
            sheet: sheet,
            onAddPart: () {},
            actionBuilder: (row) => TextButton(
              key: ValueKey<String>('action_$row'),
              onPressed: () {},
              child: const Text('Save part'),
            ),
            photoBuilder: (row) => SizedBox(
              key: ValueKey<String>('small_photo_$row'),
              width: 48,
              height: 48,
            ),
            showcaseRow: showcaseRow,
            showcasePhotoBuilder: (row, side) => ColoredBox(
              key: ValueKey<String>('big_photo_$row'),
              color: Colors.black,
              child: SizedBox(width: side, height: side),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return sheet;
}

void main() {
  testWidgets('the showcased line\'s photo is a square as tall as its fields', (
    tester,
  ) async {
    await _pump(tester, showcaseRow: 0);
    expect(tester.takeException(), isNull);

    final photo = tester.getRect(find.byKey(const ValueKey<String>('big_photo_0')));
    final fields = tester.getRect(find.byType(EvenGrid).first);
    expect(photo.width, closeTo(photo.height, 0.5), reason: 'a square');
    expect(photo.height, closeTo(fields.height, 0.5), reason: 'as tall as the fields');
    expect(photo.top, closeTo(fields.top, 0.5), reason: 'level with them');
    expect(photo.left, greaterThan(fields.right), reason: 'beside them, on the right');

    // Save and × are under the photo, not beside the fields.
    final save = tester.getRect(find.byKey(const ValueKey<String>('action_0')));
    expect(save.top, greaterThan(photo.bottom));
    expect(find.byKey(const ValueKey<String>('small_photo_0')), findsNothing);

    // The other line is as it was.
    expect(find.byKey(const ValueKey<String>('small_photo_1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('big_photo_1')), findsNothing);
  });

  testWidgets('with no line showcased, every line keeps its small photo', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey<String>('small_photo_0')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('small_photo_1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('big_photo_0')), findsNothing);
  });

  testWidgets('on a narrow window the fields fold and the photo still fits', (
    tester,
  ) async {
    await _pump(tester, showcaseRow: 0, width: 760);
    expect(tester.takeException(), isNull);
    final photo = tester.getRect(find.byKey(const ValueKey<String>('big_photo_0')));
    final fields = tester.getRect(find.byType(EvenGrid).first);
    expect(photo.width, closeTo(photo.height, 0.5));
    expect(photo.width, lessThanOrEqualTo(760 * 0.38 + 0.5), reason: 'it never crowds the fields out');
    expect(photo.left, greaterThan(fields.right));
  });
}
