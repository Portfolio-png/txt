import 'package:core_erp/core/widgets/fit_to_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A form field sized to what it holds: short answers make short boxes that
// sit side by side, and a box grows as it is typed into.

void main() {
  testWidgets('a field is as wide as its text, and grows as it is typed into',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Wrap(children: [
          FitToText(
            key: const ValueKey('fit'),
            controller: controller,
            texts: const ['D.O.M.'],
            minWidth: 120,
            maxWidth: 420,
            child: TextField(controller: controller),
          ),
        ]),
      ),
    ));

    final empty = tester.getSize(find.byKey(const ValueKey('fit'))).width;
    expect(empty, lessThan(800 / 2), reason: 'not a page-wide bar');

    controller.text = 'A rather long machine maker name';
    await tester.pump();
    final typed = tester.getSize(find.byKey(const ValueKey('fit'))).width;
    expect(typed, greaterThan(empty));
    expect(typed, lessThanOrEqualTo(420), reason: 'held to its maximum');
  });
}
