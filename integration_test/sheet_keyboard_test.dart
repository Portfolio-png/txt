import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

// The item sheet from the keyboard, in the real app against the real server:
// a part, its company and a person, entered with Tab, typing, Enter and the
// save prompts — no clicks. `scripts/e2e-ui.sh sheet_keyboard` then checks
// what landed in SQLite.

final _stamp = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
final _part = 'E2E Key Part $_stamp';
final _company = 'E2E Key Company $_stamp';
final _person = 'E2E Key Ravi $_stamp';

/// The key of the field holding focus: `cell_item_0_3`, `deal_company`, …
String? _focused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  String? found;
  bool visit(Element element) {
    final key = element.widget.key;
    if (key is ValueKey<String> &&
        (key.value.startsWith('cell_item_') ||
            key.value.startsWith('deal_') ||
            key.value.startsWith('quick-entry-'))) {
      found = key.value;
      return false;
    }
    return true;
  }

  if (context is Element) visit(context);
  context.visitAncestorElements(visit);
  return found;
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key, {String? character}) async {
  await tester.sendKeyEvent(key, character: character);
  await tester.pump(const Duration(milliseconds: 200));
}

/// Types at a closed dropdown — its first letter opens it — then the whole
/// text into its search, and Enter takes the best row.
Future<void> _pickByTyping(WidgetTester tester, String text) async {
  final first = text.substring(0, 1).toLowerCase();
  await _key(
    tester,
    LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + first.codeUnitAt(0) - 'a'.codeUnitAt(0)),
    character: first,
  );
  final search = find.byType(TextField).last;
  await pumpUntil(tester, search, reason: 'a letter should open the dropdown');
  await tester.enterText(search, text);
  await tester.pump(const Duration(milliseconds: 200));
  await _key(tester, LogicalKeyboardKey.enter);
  await waitForPickerClosed(tester);
}

/// Tab until [prompt] asks, then Enter (its Save).
Future<void> _tabToPromptAndSave(WidgetTester tester, String prompt) async {
  for (var i = 0; i < 14 && find.text(prompt).evaluate().isEmpty; i += 1) {
    await _key(tester, LogicalKeyboardKey.tab);
  }
  await pumpUntil(tester, find.text(prompt), reason: 'Tab past the last field should ask "$prompt"');
  await _key(tester, LogicalKeyboardKey.enter);
}

void main() {
  ensureBinding();

  testWidgets('a part, its company and a person, by keyboard alone',
      (tester) async {
    await bootApp(tester);
    await openItemSheet(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_focused(), 'cell_item_0_1', reason: 'the sheet opens on Group');

    // --- the part line ----------------------------------------------------
    await _pickByTyping(tester, 'Primary Group');
    await _key(tester, LogicalKeyboardKey.tab); // Type: left empty
    await _key(tester, LogicalKeyboardKey.tab); // Part Name
    expect(_focused(), 'cell_item_0_3');
    await _pickByTyping(tester, _part);
    dumpVisibleText(tester, 'E2E keyboard, part line typed');
    await _tabToPromptAndSave(tester, 'Save part 1?');
    await pumpUntil(tester, find.textContaining('SAVED #'), reason: 'the part should save');

    // --- the company ---------------------------------------------------------
    await pumpUntil(
      tester,
      find.byWidgetPredicate((_) => _focused() == 'deal_company'),
      reason: 'after the part, Tab goes on to the company',
    );
    await _pickByTyping(tester, _company);
    await pumpUntil(tester, find.text(_company), reason: 'the company should be added and chosen');
    await _key(tester, LogicalKeyboardKey.tab);
    expect(_focused(), 'deal_quotation');
    await tester.enterText(find.byKey(const ValueKey<String>('deal_quotation')), '45000');
    await tester.pump(const Duration(milliseconds: 200));
    await _tabToPromptAndSave(tester, 'Save $_company?');
    await pumpUntil(tester, find.byKey(const ValueKey<String>('deal_edit')),
        reason: 'the company line should save and close');

    // --- a person ------------------------------------------------------------
    final name = find.byKey(const ValueKey<String>('deal_person_0_person.name'));
    await pumpUntil(tester, name, reason: 'a person row should be offered');
    await pumpUntil(
      tester,
      find.byWidgetPredicate((_) => _focused() == 'deal_person_0_person.name'),
      reason: 'after the company, Tab goes on to its first person',
    );
    await tester.enterText(name, _person);
    await _key(tester, LogicalKeyboardKey.tab);
    await _pickByTyping(tester, 'Purchase Manager');
    await _key(tester, LogicalKeyboardKey.tab);
    await tester.enterText(
      find.byKey(const ValueKey<String>('deal_person_0_person.phone')),
      '9820012345',
    );
    await _key(tester, LogicalKeyboardKey.tab);
    await tester.enterText(
      find.byKey(const ValueKey<String>('deal_person_0_person.email')),
      'ravi.$_stamp@example.com',
    );
    await _tabToPromptAndSave(tester, 'Save $_person?');
    await pumpUntil(tester, find.byKey(const ValueKey<String>('deal_person_0_edit')),
        reason: 'the person should save to the company');

    dumpVisibleText(tester, 'E2E keyboard, done');
  });
}
