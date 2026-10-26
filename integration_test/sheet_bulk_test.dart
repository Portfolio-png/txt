import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

// Three parts in one sitting — the thing the sheet exists for, and the case
// that had never once been exercised.
//
// Every test and the whole route journey save a SINGLE part, which is why the
// batching save could discard rows it had already written to the server and
// nothing noticed. Rows now commit one at a time, so this drives three of them
// and `scripts/e2e-ui.sh` then counts what actually landed in SQLite.

const _seededGroup = 'Primary Group';

/// Distinctive, so the SQL check downstream cannot match a seeded row.
const _names = ['E2E Bulk One', 'E2E Bulk Two', 'E2E Bulk Three'];

void main() {
  ensureBinding();

  testWidgets('three parts are entered and committed in one sitting',
      (tester) async {
    await bootApp(tester);
    await openItemSheet(tester);

    // The party sheet's Company Name and Client Name are required columns, so
    // leaving "developed for an external party" ticked demands a client before
    // any part can be saved. This journey is a catalogue, not a deal.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();

    for (var row = 0; row < _names.length; row += 1) {
      if (row > 0) {
        // A new row, the way a typist gets one.
        final addRow = find.text('Add row');
        await tester.ensureVisible(addRow);
        await tester.pump();
        await tester.tap(addRow);
        await tester.pump(const Duration(milliseconds: 250));
      }

      dumpVisibleText(tester, 'E2E bulk before row $row');
      await pickInCell(tester, column: 1, row: row, label: _seededGroup);
      await typeNewInCell(tester, column: 3, row: row, value: _names[row]);
    }

    dumpVisibleText(tester, 'E2E bulk before save');

    await tester.tap(find.byKey(const ValueKey<String>('save_item_sheet_btn')));

    // Every row reports its own fate now, so the status says how many landed
    // rather than naming one id.
    await pumpUntil(
      tester,
      find.textContaining('3 saved'),
      reason: 'all three rows should commit',
    );

    // Pressing Save again must not file them a second time. A saved row that
    // has not been touched since is skipped outright; the SQL check in
    // scripts/e2e-ui.sh is what proves the catalogue holds three, not six.
    await tester.tap(find.byKey(const ValueKey<String>('save_item_sheet_btn')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('6 saved'), findsNothing);
  });
}
