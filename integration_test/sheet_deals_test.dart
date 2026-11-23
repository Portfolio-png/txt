import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

// One part, two companies, each with its own quotation — through the real UI,
// against the real server, landing in a real database (2026-11-24).
//
// `scripts/e2e-ui.sh sheet_deals` runs this and then reads item_deals back out
// of SQLite: two rows for the part, in order, with their quotations. The rows
// are the assertion that matters; this file asserts the UI could make them.

const _seededGroup = 'Primary Group';
const _newPart = 'E2E Deals Part';

/// Distinct per run, so a kept database never offers last run's company.
final _stamp = DateTime.now().millisecondsSinceEpoch % 100000;
final _first = 'E2E Deals Gold $_stamp';
final _second = 'E2E Deals Silver $_stamp';

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(finder.first);
  await tester.pump();
}

Future<void> _typeInto(WidgetTester tester, String key, String text) async {
  final keyed = find.byKey(ValueKey<String>(key));
  await pumpUntil(tester, keyed, reason: '$key should be on screen');
  final field = tester.widget(keyed.first) is TextField
      ? keyed.first
      : find.descendant(of: keyed.first, matching: find.byType(TextField)).first;
  await tester.ensureVisible(field);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.enterText(field, text);
  await tester.pump();
}

/// Names a new company on the open tab, and its quotation.
Future<void> _company(WidgetTester tester, String name, String quotation) async {
  await _tapVisible(tester, find.byKey(const ValueKey<String>('deal_company_tap')));
  await pumpUntil(tester, find.byType(TextField), reason: 'the company search should open');
  await tester.enterText(find.byType(TextField).last, name);
  final add = find.textContaining('Add company');
  await pumpUntil(tester, add, reason: 'a new company should be offered');
  await tester.tap(add.last);
  await pumpUntil(tester, find.text(name), reason: 'the new company should be chosen');
  await _typeInto(tester, 'deal_quotation', quotation);
}

void main() {
  ensureBinding();

  testWidgets('a part saved with two companies, each with its quotation', (tester) async {
    await bootApp(tester);
    await openItemSheet(tester);

    await pickInCell(tester, column: 1, label: _seededGroup);
    await typeNewInCell(tester, column: 3, value: _newPart);

    // Developed For opens folded.
    final toggle = find.byKey(const ValueKey<String>('section_toggle_client_vendor'));
    await _tapVisible(tester, toggle);
    await pumpUntil(
      tester,
      find.byKey(const ValueKey<String>('deal_company_tap')),
      reason: 'Developed For should open',
    );

    await _company(tester, _first, '45000');
    await _tapVisible(tester, find.byKey(const ValueKey<String>('company_add')));
    await pumpUntil(
      tester,
      find.byKey(const ValueKey<String>('company_tab_1')),
      reason: '+ should open a second company tab',
    );
    await _company(tester, _second, '52000');

    dumpVisibleText(tester, 'E2E before saving the part with two companies');
    await tester.tap(find.byKey(const ValueKey<String>('save_item_sheet_btn')));
    await pumpUntil(
      tester,
      find.textContaining('SAVED #'),
      reason: 'the part should save with both companies',
    );
    // Both tabs are still there after the save, each named.
    expect(find.text(_first), findsWidgets);
    expect(find.text(_second), findsWidgets);
    // ignore: avoid_print
    print('E2E_DEALS first=$_first second=$_second');
  });
}
