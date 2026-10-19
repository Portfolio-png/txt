import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

// The thing this harness was built for: a route authored through the real UI,
// against the real server, landing in a real database.
//
// Everything about process routing was previously proven by widget tests
// against fake providers and backend tests against temp databases. Neither
// shows that the Route card can be reached and used in the running app — a
// widget test substitutes the provider that would have failed.
//
// `scripts/e2e-ui.sh` runs this and then reads the rows back out of SQLite.
// The rows are the assertion that matters; what this file asserts is that the
// UI could be driven to produce them.

/// The first part in the checked-in demo seed (`reseedDemoData`).
///
/// Named rather than searched for: the seed is deterministic and this is the
/// first row, so it is on screen without scrolling the picker — thirteen items
/// do not all fit, and the row this test wants must not be below the fold.
const _seededPart = 'Anchor Roma Classic Switch 10A 1-Way';

void main() {
  ensureBinding();

  testWidgets('a route is authored on the Express bench and saved',
      (tester) async {
    await bootApp(tester);
    await openExpress(tester);

    // The bench opens empty — `bootApp` starts from blank preferences, so
    // there is no remembered lineup and the chooser is in the middle.
    await pumpUntil(
      tester,
      find.byKey(const ValueKey<String>('creation_choose_route')),
      reason: 'the empty bench chooser should offer every kind, Route among them',
    );
    await tester.tap(find.byKey(const ValueKey<String>('creation_choose_route')));

    // A route belongs to a part, so the card opens on its part picker and
    // cannot be saved before one is chosen.
    await pumpUntil(
      tester,
      find.byKey(const ValueKey<String>('route_part_field')),
      reason: 'the Route card should open on its part picker',
    );
    await tester.tap(find.byKey(const ValueKey<String>('route_part_field')));
    await pumpUntil(
      tester,
      find.text(_seededPart),
      reason: 'the picker should list the seeded parts',
    );
    await tester.tap(find.text(_seededPart).last);

    // Back on the card. Add step appends the first stage still available, so
    // four taps give Die, Shearing, Cutting, Riveting. This is the Classic
    // lens: `routes.listLens` is false, and a debug binary reads dev_config
    // rather than the server, so the palette is not what is on screen.
    await pumpUntil(
      tester,
      find.byKey(const ValueKey<String>('route_add_step')),
      reason: 'the stage editor should be on screen once a part is chosen',
    );
    for (var i = 0; i < 4; i += 1) {
      await tester.tap(find.byKey(const ValueKey<String>('route_add_step')));
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('Die'), findsWidgets);

    await tester.tap(find.text('Save route'));

    // The window lists what it made, so a record means the POST came back and
    // the route is on the server. scripts/e2e-ui.sh then proves it in SQLite.
    await pumpUntil(
      tester,
      find.textContaining('route v1'),
      reason: 'the saved route should be listed as made in this sitting',
    );
  });
}
