import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

// The harness proving itself.
//
// Nothing else in integration_test/ is worth writing until this passes: it is
// the first time in this project's history that the real app has been started
// against a real backend by a test. If it goes red, the problem is the boot
// path or the server, not whatever feature the next test is about.
//
// Run through scripts/e2e-ui.sh, which starts a backend on a throwaway
// database first. On its own this will time out on a spinner.
void main() {
  ensureBinding();

  // ONE test, deliberately. Booting the whole app twice in one process means
  // the first teardown's in-flight HTTP — thirteen providers initialize
  // concurrently after auth — lands while the second boot is running, and
  // reports as a failure of whichever test happens to be on screen.
  testWidgets('boots, signs in against the real server, and opens the item sheet',
      (tester) async {
    await bootApp(tester);

    // Reaching the pill means activation was skipped, auto-login's HTTP round
    // trip succeeded, and AppShell laid out wide enough to draw the sidebar
    // inline rather than hiding it in a Drawer.
    expect(
      find.byKey(const ValueKey<String>('sidebar_item_sheet')),
      findsOneWidget,
    );

    await openItemSheet(tester);
    expect(find.text('Item Master'), findsOneWidget);
  });
}
