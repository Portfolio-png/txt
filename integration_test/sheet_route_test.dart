import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

// A part entered on the item sheet, then routed — through the real UI, against
// the real server, landing in a real database.
//
// This was `express_route_test.dart`, which drove the Express bench. Express
// and the Factory Sheet wizard were two doors onto one in-memory prototype and
// both are gone; the Masters header now carries a single Sheet pill onto the
// real screen, so the flow under test changed shape: a route attaches to a
// part, and on this screen the part is made first.
//
// `scripts/e2e-ui.sh` runs this and then reads the rows back out of SQLite.
// The rows are the assertion that matters; what this file asserts is that the
// UI could be driven to produce them.

/// A group from the checked-in demo seed (`reseedDemoData`), so the Group
/// picker has something real in it.
///
/// The seed's item groups are flat — Primary Group, Raw Materials, Scrap, with
/// no children — so the sheet's Type column stays empty and the part files
/// straight under the Group. That is the supported shape, not a gap in the
/// test: `_resolveGroupId` files under the deepest level named.
const _seededGroup = 'Primary Group';

/// What this run files. Distinctive so the SQLite check cannot match a seeded
/// row by accident.
const _newPart = 'E2E Sheet Part';

void main() {
  ensureBinding();

  testWidgets('a part is entered on the sheet and then routed',
      (tester) async {
    await bootApp(tester);
    await openItemSheet(tester);

    // "Developed for an external party" is ticked by default, and the party
    // sheet's Company Name and Client Name are required columns — so leaving
    // it on demands a client before any part can be saved. This journey is a
    // part and its route, not a development deal.
    // The tick is in the Developed For card, below the part lines.
    final external = find.byKey(const ValueKey<String>('developed_for_external'));
    await Scrollable.ensureVisible(tester.element(external), alignment: 0.5);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(external);
    await tester.pump();

    // Column ids are the item sheet's own: 1 Group, 3 Part Name. Named here
    // rather than threaded through the helper because this test is about this
    // sheet.
    await pickInCell(tester, column: 1, label: _seededGroup);
    await typeNewInCell(tester, column: 3, value: _newPart);

    // The identity strip derives the code from the group path and the running
    // number, so it stops saying "assigned on save" once the path is filled.
    expect(
      find.text('assigned on save'),
      findsNothing,
      reason: 'a filled group path should derive a part code',
    );

    dumpVisibleText(tester, 'E2E before saving the part');
    await tester.tap(find.byKey(const ValueKey<String>('save_item_sheet_btn')));

    // The sidebar badge carries the id the server gave back, so SAVED means the
    // POST returned a row rather than that the button was pressed.
    await pumpUntil(
      tester,
      find.textContaining('SAVED #'),
      reason: 'the saved part should carry the id the server assigned',
    );

    // Routing is its own section, under Machines. Every section is on one
    // page, nested like a file tree; the rail (the first match — the
    // section's own heading is the second) scrolls to it.
    await tester.tap(find.text('Routing').first);
    await pumpUntil(
      tester,
      find.text('Author route'),
      reason: 'the Routing section should be open',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Author route'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Author route'));
    await pumpUntil(
      tester,
      find.byKey(const ValueKey<String>('route_add_step')),
      reason: 'the route panel should open pointed at the part just saved',
    );

    // Add step appends the first stage still available, so four taps give
    // Die, Shearing, Cutting, Riveting. This is the Classic lens:
    // `routes.listLens` is false, and a debug binary reads dev_config rather
    // than the server, so the palette is not what is on screen.
    for (var i = 0; i < 4; i += 1) {
      final addStep = find.byKey(const ValueKey<String>('route_add_step'));
      await tester.ensureVisible(addStep);
      await tester.pump();
      await tester.tap(addStep);
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('Die'), findsWidgets);

    dumpVisibleText(tester, 'E2E before saving the route');
    await tester.ensureVisible(find.text('Save route'));
    await tester.pump();
    await tester.tap(find.text('Save route'));

    await pumpUntil(
      tester,
      find.textContaining(' pipeline v'),
      reason: 'the saved route should be reported back on the sheet',
    );
  });
}
