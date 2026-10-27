import 'package:core_erp/core/widgets/length_unit_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The number-and-unit field: the unit is the searchable dropdown every other
/// pick on the sheet uses, and with suggestions the number is one too.
void main() {
  Future<List<String>> pump(
    WidgetTester tester, {
    List<String>? suggestions,
    TextEditingController? controller,
  }) async {
    final picked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: LengthUnitField(
              fieldKey: const ValueKey<String>('size'),
              unitKey: const ValueKey<String>('unit'),
              controller: controller ?? TextEditingController(),
              unitSymbol: 'mm',
              suggestions: suggestions,
              onUnitChanged: picked.add,
            ),
          ),
        ),
      ),
    );
    return picked;
  }

  testWidgets('the unit is found by typing its name', (tester) async {
    final picked = await pump(tester);

    await tester.tap(find.byKey(const ValueKey<String>('unit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'inch');
    await tester.pumpAndSettle();
    await tester.tap(find.text('in').last);
    await tester.pumpAndSettle();

    expect(picked, <String>['in']);
  });

  testWidgets('sizes used before are offered, and a new one is taken', (
    tester,
  ) async {
    final controller = TextEditingController();
    await pump(tester, suggestions: <String>['94.5'], controller: controller);

    await tester.tap(find.byKey(const ValueKey<String>('size')));
    await tester.pumpAndSettle();
    expect(find.text('94.5'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '12.7');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use "12.7"'));
    await tester.pumpAndSettle();

    expect(controller.text, '12.7');
  });
}
