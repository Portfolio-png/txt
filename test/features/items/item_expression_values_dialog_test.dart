import 'package:core_erp/features/items/domain/item_expression.dart';
import 'package:core_erp/features/items/presentation/widgets/item_expression_values_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Map<int, String>?> _open(
  WidgetTester tester,
  ItemExpressionPlan plan, {
  List<String> materials = const ['Brass', 'Aluminium'],
}) async {
  tester.view.physicalSize = const Size(900, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  Map<int, String>? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await ItemExpressionValuesDialog.open(
                context,
                plan: plan,
                materialNames: materials,
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('asks once per declared property, typed appropriately', (
    tester,
  ) async {
    await _open(tester, ItemExpression.parse('Sheet + number + material'));

    expect(find.text('2 values to fill in'), findsOneWidget);
    // Named from their input types, and each labelled with that type.
    expect(find.text('Measurement'), findsOneWidget);
    expect(find.text('Material'), findsWidgets);
    expect(find.text('Numeric'), findsOneWidget);
    // The number is typed; the material is picked.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('will not confirm until every blank is answered', (tester) async {
    await _open(tester, ItemExpression.parse('Sheet + number + material'));

    ElevatedButton confirm() => tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Confirm values'),
    );
    expect(confirm().onPressed, isNull, reason: 'nothing filled in yet');

    await tester.enterText(find.byType(TextField), '120');
    await tester.pumpAndSettle();
    expect(confirm().onPressed, isNull, reason: 'material still unanswered');

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brass').last);
    await tester.pumpAndSettle();
    expect(confirm().onPressed, isNotNull);
  });

  testWidgets('collected values fold back into the plan', (tester) async {
    final plan = ItemExpression.parse('Sheet + number + material');
    final result = await _open(tester, plan);
    expect(result, isNull, reason: 'not confirmed yet');

    await tester.enterText(find.byType(TextField), '120');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brass').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm values'));
    await tester.pumpAndSettle();

    // The dialog reports by segment index; folding it back completes the plan.
    final completed = ItemExpression.applyCollectedValues(plan, {
      1: '120',
      2: 'Brass',
    });
    final values = completed.valueSegments.toList();
    expect(values[0].kind, SegmentKind.newProperty);
    expect(values[0].value, '120');
    expect(values[0].inputType, 'Numeric');
    expect(values[1].value, 'Brass');
    expect(values[1].inputType, 'Material');
    // Bound values are untouched by the fold.
    expect(completed.headText, 'Sheet');
  });

  testWidgets('no material master falls back to typing, not a dead end', (
    tester,
  ) async {
    await _open(
      tester,
      ItemExpression.parse('Sheet + material'),
      materials: const <String>[],
    );

    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gauge offers the SWG range', (tester) async {
    await _open(tester, ItemExpression.parse('Sheet + gauge'));
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();

    // The menu only builds what fits, so the top of the range proves it is
    // the SWG list; the range itself is asserted on the source.
    expect(find.text('SWG 1'), findsOneWidget);
    expect(find.text('SWG 2'), findsOneWidget);
    expect(ItemExpression.swgValues.first, '1');
    expect(ItemExpression.swgValues.last, '40');
    expect(ItemExpression.swgValues, hasLength(40));
    expect(tester.takeException(), isNull);
  });
}
