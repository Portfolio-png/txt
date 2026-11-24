import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

// Enter, Enter, Enter as fast as a hand can (user, 2026-11-24: "when I do
// very fast enter enter … app crashes"). The real app against the real
// server: a part typed, then bursts of Enter with no frame between some of
// them, across the part line, its save prompt and the sections after it.
// A native crash kills this process, so getting to the end is the check.

final _stamp = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
final _part = 'E2E Storm Part $_stamp';

Finder _search() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      (key.value == 'option_picker_search' || key.value == 'searchable_select_search');
});

Future<void> _pickByTyping(WidgetTester tester, String text) async {
  if (_search().evaluate().isEmpty) {
    final first = text.substring(0, 1).toLowerCase();
    await tester.sendKeyEvent(
      LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + first.codeUnitAt(0) - 'a'.codeUnitAt(0)),
      character: first,
    );
    await tester.pump(const Duration(milliseconds: 200));
  }
  await pumpUntil(tester, _search(), reason: 'the dropdown should be open');
  await tester.enterText(_search(), text);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await waitForPickerClosed(tester);
}

/// [count] Enters: pairs with no frame between them, then a frame of
/// [gapMs] — a person drumming the key.
Future<void> _storm(WidgetTester tester, int count, {int gapMs = 16}) async {
  for (var i = 0; i < count; i += 1) {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    if (i.isOdd) await tester.pump(Duration(milliseconds: gapMs));
  }
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  ensureBinding();

  testWidgets('Enter drummed fast through the sheet does not bring the app down',
      (tester) async {
    await bootApp(tester);
    await openItemSheet(tester);
    await tester.pump(const Duration(milliseconds: 300));

    await _pickByTyping(tester, 'Primary Group');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await pumpUntil(tester, _search(), reason: 'Tab onto Type should open its list');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await pumpUntil(tester, _search(), reason: 'and on to Part Name');
    await _pickByTyping(tester, _part);

    // Through the part line, its "Save part 1?" and on.
    for (final gap in [16, 4, 1, 30, 1]) {
      await _storm(tester, 24, gapMs: gap);
      // ignore: avoid_print
      print('E2E storm: burst at ${gap}ms survived; saved=${find.textContaining('SAVED #').evaluate().isNotEmpty}');
    }
    // Ctrl+Enter (save and add another) in the middle of it too.
    for (var i = 0; i < 6; i += 1) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _storm(tester, 10, gapMs: 1);
    }
    await tester.pump(const Duration(seconds: 2));
    dumpVisibleText(tester, 'E2E storm, after');
    expect(tester.takeException(), isNull);
  });
}
