import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

// A property column added with the Properties "+" is on the sheet the moment
// Add is pressed — through the real UI, against the real server.
//
// It was saved on the server and never drawn: the sheet ignored every stored
// column whenever the first load of them had not succeeded, and said nothing.
// `scripts/e2e-ui.sh` reads the row back out of SQLite afterwards.

/// Distinctive, so the SQLite check cannot match anything seeded.
const _newColumn = 'E2E Finish';

void main() {
  ensureBinding();

  testWidgets('a property column added with + is on the sheet at once',
      (tester) async {
    await bootApp(tester);
    await openItemSheet(tester);

    final plus = find.byKey(const ValueKey<String>('mini_table_add_properties_item'));
    await pumpUntil(tester, plus, reason: 'the Properties table should offer +');
    await tester.ensureVisible(plus);
    await tester.pump();
    await tester.tap(plus);
    await pumpUntil(
      tester,
      find.byKey(const ValueKey<String>('property_name')),
      reason: '+ should open the Add a property dialog',
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('property_name')),
      _newColumn,
    );
    await tester.tap(find.text('Free text'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey<String>('property_option')),
      'Matte',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('property_submit')));

    await pumpUntilGone(
      tester,
      find.byKey(const ValueKey<String>('property_name')),
    );
    dumpVisibleText(tester, 'E2E after adding a property column');
    await pumpUntil(
      tester,
      find.text(_newColumn),
      reason: 'the new column should be drawn in Properties without a reload',
    );
    expect(find.textContaining('did not load'), findsNothing);
  });
}
