import 'package:core_erp/core/services/quit_guard.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

// Quitting with unsaved work on the item sheet, in the real macOS app: the
// quit goes through the app delegate, which asks the app once. A second quit
// while "Leave with unsaved work?" is up used to go straight through —
// Flutter's own handler had already marked the app as quitting — and the
// work was lost. Here it is ignored: the app is still running to be checked.

void main() {
  ensureBinding();

  testWidgets('a second quit while the leave question is up does not quit', (tester) async {
    // main() installs it; the harness pumps the app without running main().
    QuitGuard.install();
    await bootApp(tester);
    await openItemSheet(tester);
    await typeNewInCell(tester, column: 3, value: 'E2E Quit Part');
    await tester.pump(const Duration(milliseconds: 300));

    final question = find.text('Leave with unsaved work?');
    await tester.runAsync(QuitGuard.debugRequestQuit);
    await pumpUntil(tester, question, reason: 'a quit with unsaved work asks first');

    // The second quit — Cmd+Q again, or the red button again.
    await tester.runAsync(QuitGuard.debugRequestQuit);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(question, findsOneWidget, reason: 'still asking, once — the app did not quit');

    await tester.tap(find.text('Keep editing'));
    await pumpUntilGone(tester, question, timeout: const Duration(seconds: 5));
    expect(find.text('E2E Quit Part'), findsWidgets, reason: 'the typing is still there');

    // And asked again later, it asks again — the guard is not stuck.
    await tester.runAsync(QuitGuard.debugRequestQuit);
    await pumpUntil(tester, question, reason: 'a later quit asks again');
    await tester.tap(find.text('Keep editing'));
    await pumpUntilGone(tester, question, timeout: const Duration(seconds: 5));
  });
}
