import 'package:core_erp/features/items/domain/item_expression.dart';
import 'package:core_erp/features/items/presentation/widgets/item_expression_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, ItemExpressionPlan plan) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 900, child: ItemExpressionView(plan: plan)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders item, bound values and the separators', (tester) async {
    await _pump(
      tester,
      ItemExpression.parse(
        'Bulb + Red + 60',
        itemId: 5,
        existingProperties: const [
          ExpressionProperty(id: 11, name: 'Colour'),
          ExpressionProperty(id: 12, name: 'Wattage', inputType: 'Numeric'),
        ],
      ),
    );

    expect(find.textContaining('Bulb'), findsOneWidget);
    expect(find.textContaining('Colour'), findsOneWidget);
    expect(find.textContaining('Red'), findsOneWidget);
    expect(find.textContaining('Wattage'), findsOneWidget);
    // Two separators between three segments.
    expect(find.text('+'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('separates reuse from the two kinds of creation', (tester) async {
    await _pump(
      tester,
      ItemExpression.parse(
        'Bulb + Red + Teal + Brass',
        itemId: 5,
        existingProperties: const [
          ExpressionProperty(
            id: 11,
            name: 'Colour',
            values: [ExpressionValue(id: 101, name: 'Red')],
          ),
          ExpressionProperty(id: 12, name: 'Finish'),
        ],
      ),
    );

    // Red already exists on Colour, so it is ticked and writes nothing.
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    // Teal is a new value on Finish, and Brass has no property at all — both
    // create something, so both carry the marker.
    expect(find.byIcon(Icons.add_circle_outline), findsNWidgets(2));
    expect(find.textContaining('Detail'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty expression invites input instead of rendering junk', (
    tester,
  ) async {
    await _pump(tester, ItemExpression.parse(''));
    expect(find.text('Type an item name, then + a value.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long line wraps rather than overflowing', (tester) async {
    tester.view.physicalSize = const Size(420, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      ItemExpression.parse('Sheet + Brass + 120 + gauge + material + Blue'),
    );
    expect(tester.takeException(), isNull);
  });
}
