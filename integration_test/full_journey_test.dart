import 'dart:convert';

import 'package:core_erp/core/widgets/mini_photo.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

// The whole item sheet, through the real app, against the real server:
// a part with its alloy and gauge, the company and a person it was made for,
// a die and a machine, a route, the raw sheet with its material figures, and a
// photo on the part, the company, the person, the die and the machine — one of
// them then deleted. Then the sheet is left and the part opened again from
// the Items screen, and what was entered must still be there.
//
// Every step is timed and printed as `JOURNEY step=<name> ms=<n>`; times are
// reported, not judged. `scripts/e2e-ui.sh full_journey` runs this, keeps the
// database, and prints every row the run wrote.

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

final _stamp = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
final _part = 'E2E UI Patti $_stamp';
final _company = 'E2E UI Company $_stamp';
final _person = 'E2E UI Ravi $_stamp';
final _vendor = 'E2E UI Supplier $_stamp';
final _machineType = 'E2E Press $_stamp';

final _timings = <String, int>{};

Future<T> _step<T>(String name, Future<T> Function() body) async {
  final watch = Stopwatch()..start();
  try {
    return await body();
  } finally {
    watch.stop();
    _timings[name] = watch.elapsedMilliseconds;
    // ignore: avoid_print
    print('JOURNEY step=${name.replaceAll(' ', '_')} ms=${watch.elapsedMilliseconds}');
  }
}

/// A key that starts with [prefix] and is not the not-yet-saved placeholder.
Finder _keyed(String prefix) => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      key.value.startsWith(prefix) &&
      !key.value.endsWith('-none');
});

/// Scrolls the raw material panel until [key] is built. The panel is a lazy
/// list, so a field scrolled out of it does not exist to be found.
Future<void> _revealInPanel(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey<String>(key));
  if (target.evaluate().isNotEmpty) return;
  // The vertical list — the step bar above it scrolls sideways.
  final panel = find.descendant(
    of: find.byKey(const ValueKey<String>('raw_panel')),
    matching: find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    ),
  );
  for (final delta in [-300.0, 300.0]) {
    try {
      await tester.scrollUntilVisible(target, delta, scrollable: panel.first, maxScrolls: 20);
      return;
    } on StateError {
      // Not that way; try the other direction.
    } on TestFailure {
      // Not that way; try the other direction.
    }
  }
}

/// The text field [key] names — the key is on the field itself in some
/// forms and on a wrapper around it in others.
Future<void> _typeInto(WidgetTester tester, String key, String text) async {
  final keyed = find.byKey(ValueKey<String>(key));
  await pumpUntil(tester, keyed, timeout: const Duration(seconds: 15), reason: '$key should be on screen');
  final field = tester.widget(keyed.first) is TextField
      ? keyed.first
      : find.descendant(of: keyed.first, matching: find.byType(TextField)).first;
  await tester.ensureVisible(field);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.enterText(field, text);
  await tester.pump();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(finder.first);
  await tester.pump();
}

/// Picks [label] in a sheet cell: taps until the picker is really open (a tap
/// can land while the last picker's barrier is still leaving), then filters to
/// the option rather than hoping it is on screen.
Future<void> _pickCell(
  WidgetTester tester, {
  required int column,
  required String label,
  int row = 0,
}) async {
  await dismissAnyPicker(tester);
  final cell = find.byKey(ValueKey<String>('cell_item_${row}_$column'));
  final open = find.textContaining('Type to filter');
  for (var attempt = 0; attempt < 4 && open.evaluate().isEmpty; attempt += 1) {
    await tester.ensureVisible(cell);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(cell, warnIfMissed: false);
    for (var i = 0; i < 15 && open.evaluate().isEmpty; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  if (open.evaluate().isEmpty) {
    dumpVisibleText(tester, 'E2E picker for column $column did not open');
    throw TestFailure('the picker for column $column never opened');
  }
  await tester.enterText(find.byType(TextField).last, label);
  final option = find.widgetWithText(ListTile, label);
  await pumpUntil(tester, option, timeout: const Duration(seconds: 15), reason: 'the picker should offer "$label"');
  await tester.tap(option.last);
  await waitForPickerClosed(tester);
}

/// A pick-or-type field: tap it, type, take "Use".
Future<void> _pickOrType(
  WidgetTester tester,
  Finder field,
  String value,
) async {
  // Its own search box, not just any text field: typing into the last field
  // on screen when the picker had not opened overwrote the email instead.
  final search = find.byWidgetPredicate(
    (w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Search or type'),
  );
  for (var attempt = 0; attempt < 4 && search.evaluate().isEmpty; attempt += 1) {
    await _tapVisible(tester, field);
    for (var i = 0; i < 15 && search.evaluate().isEmpty; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  if (search.evaluate().isEmpty) {
    dumpVisibleText(tester, 'E2E picker for "$value" did not open');
    throw TestFailure('the picker for "$value" never opened');
  }
  await tester.enterText(search.last, value);
  // A value said before is an option already; a new one is offered as "Use".
  final use = find.textContaining('Use "$value"');
  // An existing value is an option row (an InkWell), not a ListTile; the
  // search box holds the same text, so it is matched inside a row only.
  final known = find.descendant(of: find.byType(InkWell), matching: find.text(value));
  for (var i = 0; i < 100; i += 1) {
    if (use.evaluate().isNotEmpty || known.evaluate().isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (use.evaluate().isEmpty && known.evaluate().isEmpty) {
    dumpVisibleText(tester, 'E2E nothing offered for "$value"');
    throw TestFailure('typing "$value" offered nothing to pick');
  }
  await tester.tap(use.evaluate().isNotEmpty ? use.last : known.last);
  await tester.pump(const Duration(milliseconds: 300));
}

/// Uploads the stubbed picture through the thumbnail [prefix] names.
Future<void> _uploadPhoto(WidgetTester tester, String prefix) async {
  await pumpUntil(tester, _keyed(prefix), reason: 'a $prefix thumbnail should be drawn');
  await _tapVisible(tester, _keyed(prefix));
  await pumpUntil(
    tester,
    find.text('Photo saved.'),
    reason: 'the $prefix photo should upload and complete',
  );
}

/// The confirmation fades on its own; waited out between steps, untimed, so
/// the next upload's "Photo saved." is its own.
Future<void> _letToastGo(WidgetTester tester) =>
    pumpUntilGone(tester, find.text('Photo saved.'), timeout: const Duration(seconds: 10));

void main() {
  ensureBinding();

  testWidgets('the whole item sheet is filled, saved, and still there on reopening', (
    tester,
  ) async {
    MiniPhoto.debugPickFile = () async =>
        XFile.fromData(_png, name: 'e2e.png', mimeType: 'image/png');
    addTearDown(() => MiniPhoto.debugPickFile = null);

    await _step('boot and open the sheet', () async {
      await bootApp(tester);
      await openItemSheet(tester);
    });

    // --- the part's own row ---------------------------------------------------
    await _step('fill the part row', () async {
      await pickInCell(tester, column: 1, label: 'Primary Group');
      await typeNewInCell(tester, column: 3, value: _part);
      await _pickCell(tester, column: 6, label: 'MS');
      await _pickCell(tester, column: 7, label: '23 Gauge');
    });

    // --- who it was developed for ---------------------------------------------
    await _step('choose the company', () async {
      await _tapVisible(tester, find.byKey(const ValueKey<String>('deal_company_tap')));
      await pumpUntil(tester, find.byType(TextField), reason: 'the company search should open');
      await tester.enterText(find.byType(TextField).last, _company);
      final add = find.textContaining('Add company');
      await pumpUntil(tester, add, reason: 'a new company should be offered');
      await tester.tap(add.last);
      await pumpUntil(tester, find.text(_company), reason: 'the new company should be chosen');
      await _typeInto(tester, 'deal_quotation', '45000');
      await tester.pump();
    });

    await _step('add a person at the company', () async {
      final nameField = find.byKey(const ValueKey<String>('deal_person_0_person.name'));
      if (nameField.evaluate().isEmpty) {
        await _tapVisible(tester, find.byKey(const ValueKey<String>('deal_add_person')));
        await pumpUntil(tester, nameField, reason: 'a person row should open');
      }
      await _typeInto(tester, 'deal_person_0_person.name', _person);
      await _typeInto(tester, 'deal_person_0_person.phone', '9820012345');
      await _typeInto(tester, 'deal_person_0_person.email', 'ravi.$_stamp@example.com');
      await _pickOrType(
        tester,
        find.byKey(const ValueKey<String>('deal_person_0_person.designation')),
        'Purchase Manager',
      );
      await _tapVisible(tester, find.byKey(const ValueKey<String>('deal_person_0_tick')));
      await _tapVisible(tester, find.byKey(const ValueKey<String>('deal_person_0_save')));
      await pumpUntil(
        tester,
        find.byKey(const ValueKey<String>('deal_person_0_edit')),
        reason: 'the person should save to the company',
      );
    });

    late final String partId;
    await _step('save the part', () async {
      await _tapVisible(tester, find.byKey(const ValueKey<String>('row_save_0')));
      await pumpUntil(
        tester,
        find.textContaining('SAVED #'),
        reason: 'the part should save with its deal',
      );
      final badge = tester.widget<Text>(find.textContaining('SAVED #').first);
      partId = RegExp(r'#(\d+)').firstMatch(badge.data ?? '')!.group(1)!;
    });

    // --- dies and machines ----------------------------------------------------
    await _step('add a die', () async {
      final section = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'PartDieSection',
      );
      final cutting = find.descendant(of: section, matching: find.text('Cutting'));
      await _tapVisible(tester, cutting);
      await _tapVisible(tester, find.byKey(const ValueKey<String>('quick-entry-add-die')));
      await pumpUntil(
        tester,
        _keyed('quick-entry-die-row-'),
        reason: 'the die should be made and linked to the part',
      );
    });

    await _step('add a machine', () async {
      await _tapVisible(
        tester,
        find.byKey(const ValueKey<String>('quick-entry-machine-type-field')),
      );
      await pumpUntil(tester, find.byType(TextField), reason: 'the type search should open');
      await tester.enterText(find.byType(TextField).last, _machineType);
      final add = find.textContaining('Add type');
      await pumpUntil(tester, add, reason: 'a new machine type should be offered');
      await tester.tap(add.last);
      await tester.pump(const Duration(milliseconds: 500));
      await _tapVisible(tester, find.byKey(const ValueKey<String>('quick-entry-add-machine')));
      await pumpUntil(
        tester,
        _keyed('quick-entry-machine-row-'),
        reason: 'the machine should be made and linked to the part',
      );
    });

    // --- photos ----------------------------------------------------------------
    await _step('upload the part photo', () => _uploadPhoto(tester, 'photo-item-'));
    await _letToastGo(tester);
    await _step('upload the company logo', () => _uploadPhoto(tester, 'photo-client-'));
    await _letToastGo(tester);
    await _step('upload the person photo', () => _uploadPhoto(tester, 'photo-party_contact-'));
    await _letToastGo(tester);
    await _step('upload the die photo', () => _uploadPhoto(tester, 'photo-die-'));
    await _letToastGo(tester);
    await _step('upload the machine photo', () => _uploadPhoto(tester, 'photo-machine-'));
    await _letToastGo(tester);

    await _step('delete the person photo', () async {
      await _tapVisible(tester, _keyed('photo-party_contact-'));
      await pumpUntil(
        tester,
        find.byKey(const ValueKey<String>('photo-remove')),
        reason: 'the photo should open with Remove',
      );
      await tester.tap(find.byKey(const ValueKey<String>('photo-remove')));
      await pumpUntil(tester, find.text('Photo removed.'), reason: 'the photo should go');
    });

    // --- route -----------------------------------------------------------------
    await _step('author the route', () async {
      await tester.tap(find.text('Machines & Routing').first);
      await pumpUntil(tester, find.text('Author route'), reason: 'routing should open');
      await _tapVisible(tester, find.text('Author route'));
      await pumpUntil(
        tester,
        find.byKey(const ValueKey<String>('route_add_step')),
        reason: 'the route panel should open on the saved part',
      );
      for (var i = 0; i < 4; i += 1) {
        await _tapVisible(tester, find.byKey(const ValueKey<String>('route_add_step')));
        await tester.pump(const Duration(milliseconds: 250));
      }
      await _tapVisible(tester, find.text('Save route'));
      await pumpUntil(tester, find.textContaining('Route saved for'), reason: 'the route should save');
    });

    // --- raw sheet ---------------------------------------------------------------
    await _step('fill and save the raw sheet', () async {
      await _tapVisible(tester, find.byKey(const ValueKey<String>('raw_edit')));
      await tester.pump(const Duration(milliseconds: 300));
      await _revealInPanel(tester, 'sheet-width');
      await _typeInto(tester, 'sheet-width', '48');
      await _revealInPanel(tester, 'sheet-length');
      await _typeInto(tester, 'sheet-length', '96');
      await tester.pump();

      await _revealInPanel(tester, 'sheet-vendor');
      await _tapVisible(tester, find.byKey(const ValueKey<String>('sheet-vendor')));
      await pumpUntil(tester, find.byType(TextField), reason: 'the vendor search should open');
      await tester.enterText(find.byType(TextField).last, _vendor);
      final addVendor = find.textContaining('Add vendor');
      await pumpUntil(tester, addVendor, reason: 'a new vendor should be offered');
      await tester.tap(addVendor.last);
      await pumpUntil(tester, find.text(_vendor), reason: 'the vendor should be chosen');

      await _revealInPanel(tester, 'master-data-save');
      await _tapVisible(tester, find.text('Material data'));
      await pumpUntil(
        tester,
        find.byKey(const ValueKey<String>('material-input-kg')),
        reason: 'material data should open',
      );
      await _typeInto(tester, 'material-input-kg', '24.5');
      await tester.pump();
      await _typeInto(tester, 'material-output-kg', '21.25');
      await tester.pump();
      await _typeInto(tester, 'material-output-pieces', '2900');
      await tester.pump();
      await _revealInPanel(tester, 'master-data-save');
      await _tapVisible(tester, find.byKey(const ValueKey<String>('master-data-save')));
      await pumpUntil(
        tester,
        find.textContaining('Raw material saved on'),
        reason: 'the raw sheet should save on the part',
      );
    });

    dumpVisibleText(tester, 'E2E journey, everything entered');

    // --- retention: leave, come back through the Items screen -----------------
    await _step('leave and reopen the part', () async {
      await tester.tap(find.byTooltip('Back').first);
      await tester.pump(const Duration(milliseconds: 500));
      final save = find.byKey(const ValueKey<String>('leave_save'));
      if (save.evaluate().isNotEmpty) {
        await tester.tap(save);
        await tester.pump(const Duration(milliseconds: 500));
      }
      await pumpUntil(
        tester,
        find.byKey(const ValueKey<String>('sidebar_item_sheet')),
        reason: 'leaving the sheet should land back in the shell',
      );
      // A blank sheet, and the saved part picked by name: that loads the
      // whole part — its row, deal, dies, machines, raw sheet — back in.
      await openItemSheet(tester);
      await _pickCell(tester, column: 1, label: 'Primary Group');
      await _pickCell(tester, column: 3, label: _part);
      await pumpUntil(
        tester,
        find.textContaining('SAVED #$partId'),
        reason: 'picking the saved part should open it',
      );
    });

    await _step('check everything came back', () async {
      Future<void> stillThere(Finder finder, String what) =>
          pumpUntil(tester, finder, timeout: const Duration(seconds: 20), reason: '$what should be retained');
      await stillThere(find.text(_part), 'the part name');
      await stillThere(find.text('MS'), 'the alloy');
      await stillThere(find.text('23 Gauge'), 'the thickness');
      await stillThere(find.text(_company), 'the company');
      await stillThere(find.textContaining(_person), 'the person');
      await stillThere(_keyed('quick-entry-die-row-'), 'the die');
      await stillThere(_keyed('quick-entry-machine-row-'), 'the machine');
      await stillThere(find.textContaining(_vendor), 'the raw sheet vendor');
      await stillThere(find.byTooltip('Open part photo'), 'the part photo');
      await stillThere(find.byTooltip('Open company logo'), 'the company logo');
    });

    dumpVisibleText(tester, 'E2E journey, after reopening');

    // The reopened part, section by section, as the app draws it.
    await snapshot(tester, 'sheet_item');
    for (final (section, name) in const [
      ('Client / Vendor', 'sheet_client'),
      ('Die Process Master', 'sheet_die'),
      ('Machines & Routing', 'sheet_machine'),
    ]) {
      await tester.tap(find.text(section).first);
      await tester.pump(const Duration(milliseconds: 600));
      await snapshot(tester, name);
    }
    final total = _timings.values.fold<int>(0, (a, b) => a + b);
    // ignore: avoid_print
    print('JOURNEY total ms=$total part=$partId');
  });
}
