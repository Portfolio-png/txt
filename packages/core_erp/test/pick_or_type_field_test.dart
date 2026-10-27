import 'package:core_erp/core/widgets/pick_or_type_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A dropdown of the answers already used that also takes a new one, writing
// either into the form's controller.

Future<TextEditingController> _pump(
  WidgetTester tester, {
  List<String> options = const ['Mayank', 'Jay Shanti'],
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Center(
            child: SizedBox(
              width: 280,
              child: PickOrTypeField(
                fieldKey: const ValueKey('make'),
                controller: controller,
                label: 'Machine Make',
                options: options,
                onChanged: () => setState(() {}),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  testWidgets('offers what was used before, and picks it', (tester) async {
    final controller = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('make')));
    await tester.pumpAndSettle();
    expect(find.text('Mayank'), findsOneWidget);
    expect(find.text('Jay Shanti'), findsOneWidget);

    await tester.tap(find.text('Jay Shanti'));
    await tester.pumpAndSettle();
    expect(controller.text, 'Jay Shanti');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('make')),
        matching: find.text('Jay Shanti'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('takes a new answer, and does not offer one already listed',
      (tester) async {
    final controller = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('make')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'mayank');
    await tester.pumpAndSettle();
    expect(find.text('Use "mayank"'), findsNothing, reason: 'already a choice');

    await tester.enterText(find.byType(TextField).last, 'Kirloskar');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use "Kirloskar"'));
    await tester.pumpAndSettle();
    expect(controller.text, 'Kirloskar');
  });

  testWidgets('shows a value the form already holds', (tester) async {
    await _pump(tester, initial: 'Fanuc', options: const []);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('make')),
        matching: find.text('Fanuc'),
      ),
      findsOneWidget,
    );
  });
}
