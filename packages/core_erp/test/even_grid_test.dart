import 'package:core_erp/core/widgets/even_grid.dart';
import 'package:core_erp/features/items/presentation/widgets/part_rows_form.dart';
import 'package:core_erp/sheet/item_sheet_columns.dart';
import 'package:core_erp/sheet/sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ColumnDef _property(int id, String name, int position) => ColumnDef(
      id: id,
      sheetId: 1,
      label: name,
      kind: ColumnKind.list,
      position: position,
      bindsTo: SheetBindsTo.variation(name),
    );

List<List<String?>> _labels(List<ColumnDef> columns) => [
      for (final row in PartRowsForm.lineGrid(
        SheetDef(id: 1, key: 'item', title: 'Item', columns: columns),
      ))
        [for (final c in row) c?.label],
    ];

void main() {
  group('a part line', () {
    // User, 2026-11-25: alloy, thickness, grade and hardness on the second
    // line, and the part code at the end.
    test('reads the identity, then every property with Part Code last', () {
      expect(
        _labels([
          ...itemSheetColumns,
          _property(40, 'Grade', 9),
          _property(41, 'Hardness', 10),
        ]),
        [
          ['Group', 'Type', 'Part Name', 'Part No'],
          ['Alloy', 'Thickness', 'Grade', 'Hardness', 'Part Code'],
        ],
      );
    });

    test('with no properties the second line is the code alone', () {
      final noProperties = itemSheetColumns
          .where((c) => !SheetBindsTo.isVariation(c.bindsTo))
          .toList();
      expect(_labels(noProperties), [
        ['Group', 'Type', 'Part Name', 'Part No'],
        ['Part Code'],
      ]);
    });

    test('more properties stay on the second line, still before the code', () {
      expect(
        _labels([
          ...itemSheetColumns,
          _property(40, 'Grade', 9),
          _property(41, 'Hardness', 10),
          _property(42, 'Finish', 11),
        ]),
        [
          ['Group', 'Type', 'Part Name', 'Part No'],
          ['Alloy', 'Thickness', 'Grade', 'Hardness', 'Finish', 'Part Code'],
        ],
      );
    });

    test('is visited by Tab in the order it reads', () {
      final def = SheetDef(
        id: 1,
        key: 'item',
        title: 'Item',
        columns: [
          ...itemSheetColumns,
          _property(40, 'Grade', 9),
          _property(41, 'Hardness', 10),
        ],
      );
      expect(
        [for (final c in PartRowsForm.lineColumns(def)) c.label],
        ['Group', 'Type', 'Part Name', 'Part No', 'Alloy', 'Thickness', 'Grade', 'Hardness', 'Part Code'],
      );
    });
  });

  group('EvenGrid', () {
    Future<void> pumpGrid(WidgetTester tester, double width) => tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: EvenGrid(
                  columns: 4,
                  minColumnWidth: 100,
                  children: [
                    for (var i = 0; i < 8; i += 1)
                      _Counter(key: ValueKey('box_$i'), height: i == 2 ? 50 : 40),
                  ],
                ),
              ),
            ),
          ),
        );

    Rect box(WidgetTester tester, int i) => tester.getRect(find.byKey(ValueKey('box_$i')));

    testWidgets('lays four even columns out where they fit', (tester) async {
      await pumpGrid(tester, 430);
      expect(box(tester, 1).left, 110);
      expect(box(tester, 3).left, 330);
      expect(box(tester, 0).width, 100);
      // A row is as tall as its tallest; the boxes sit on its bottom edge.
      expect(box(tester, 0).bottom, 50);
      expect(box(tester, 4).left, 0);
      expect(box(tester, 4).top, 58);
    });

    testWidgets('folds to two in the same order, keeping each child', (tester) async {
      await pumpGrid(tester, 430);
      await tester.tap(find.byKey(const ValueKey('box_5')));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);

      await pumpGrid(tester, 300);
      expect(box(tester, 1).left, 155);
      expect(box(tester, 2).left, 0, reason: 'C starts the second row');
      expect(box(tester, 4).left, 0);
      expect(box(tester, 0).width, 145);
      expect(find.text('1'), findsOneWidget, reason: 'resizing rebuilt nothing');
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter({super.key, required this.height});

  final double height;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => setState(() => _taps += 1),
        child: SizedBox(height: widget.height, child: Text('$_taps')),
      );
}
