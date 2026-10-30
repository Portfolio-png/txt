import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paper/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the real app against a real backend.
///
/// Everything else in this repo's tests substitutes a provider or a repository.
/// This directory does not: the app boots, logs in over HTTP, and writes to a
/// SQLite file that `scripts/e2e-ui.sh` then reads back. That script is the
/// only sanctioned way to run these — they need a server on the port that
/// `PAPER_API_BASE_URL` names, and they will fail without one.
///
/// **Never call `pumpAndSettle` in here.** `_AuthGate` shows a spinner while it
/// resolves activation and auth, and an indefinite animation keeps a frame
/// scheduled forever, so `pumpAndSettle` runs to its timeout and throws. There
/// are eight `Timer.periodic`s in the app besides, two on the boot path. Use
/// [pumpUntil], which pumps on a fixed cadence and asks a question between
/// frames instead of waiting for the app to go quiet — it never will.

/// A desktop window. `AppShell` treats anything under 900 logical pixels as
/// mobile and moves the sidebar into a `Drawer`, and the default macOS window
/// is 800x600 — so without this the Masters header's pill is not on screen at
/// all.
const Size kDesktopWindow = Size(1600, 1100);

/// Pumps until [finder] matches, or gives up and says what it was waiting for.
///
/// The cadence is deliberate: real HTTP is happening (13 provider
/// `initialize()` calls fire in a post-frame callback after auth), so the
/// answer arrives when the network says so rather than when the framework
/// settles.
Future<void> pumpUntil(
  WidgetTester tester,
  FinderBase<Element> finder, {
  Duration timeout = const Duration(seconds: 60),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  var pumps = 0;
  while (DateTime.now().isBefore(deadline)) {
    await _tick(tester, finder);
    pumps += 1;
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure(
    'Timed out after ${timeout.inSeconds}s and $pumps pumps waiting for '
    '$finder${reason == null ? '' : ' — $reason'}.\n'
    'If the app is still on a spinner, the backend is probably not up on the '
    'port PAPER_API_BASE_URL names. Run these through scripts/e2e-ui.sh.\n'
    'A single pump taking the whole timeout usually means the UI is blocked, '
    'not that the finder is wrong.\n'
    'On screen now: ${visibleText(tester)}',
  );
}

/// Prints every piece of text on screen, a few per line.
///
/// In chunks because `debugPrint` truncates a long single line — which is why
/// the one-string version of this diagnostic kept appearing to stop at the
/// sidebar, and cost two wrong hypotheses before anyone noticed the dump was
/// cut rather than the screen being empty.
void dumpVisibleText(WidgetTester tester, String label, {int perLine = 8}) {
  final seen = <String>[];
  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    final text = (widget.data ?? widget.textSpan?.toPlainText() ?? '').trim();
    if (text.isEmpty || seen.contains(text)) continue;
    seen.add(text);
  }
  debugPrint('$label: ${seen.length} distinct strings on screen');
  for (var i = 0; i < seen.length; i += perLine) {
    final slice = seen.skip(i).take(perLine).join(' | ');
    debugPrint('  [$i] $slice');
  }
}

/// Every piece of text currently rendered, for a failure message.
///
/// Worth the lines: without it a timeout says only what was NOT found, and the
/// next move is a ten-minute guess. With it the failure names the screen the
/// app was actually on.
String visibleText(WidgetTester tester, {int limit = 250}) {
  final seen = <String>[];
  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
    final trimmed = text.trim();
    if (trimmed.isEmpty || seen.contains(trimmed)) continue;
    seen.add(trimmed);
    if (seen.length >= limit) break;
  }
  if (seen.isEmpty) return '(no text at all)';
  final truncated = seen.length >= limit;
  return seen.join(' | ') + (truncated ? ' …(truncated at $limit)' : '');
}

/// Saves what the app is drawing as `<name>.png` when the run asks for it
/// (`E2E_SHOTS=1 scripts/e2e-ui.sh …`), and prints where.
///
/// Into the app's own temp directory: the macOS app is sandboxed, so that is
/// the one place it can write without an entitlement.
///
/// A widget test renders text in the Ahem test font, so it cannot show what a
/// screen looks like; this is the one place the real fonts, real data and real
/// layout are all present. Off unless asked for, so a normal run writes nothing.
Future<void> snapshot(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('E2E_SHOTS')) return;
  final dir = '${Directory.systemTemp.path}/paper-e2e-shots';
  await tester.pump(const Duration(milliseconds: 300));
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(view.paintBounds);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$dir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
    debugPrint('SNAPSHOT $name -> ${file.path}');
  });
}

/// Pumps until [finder] matches nothing — a dialog closing, a spinner going.
Future<void> pumpUntilGone(
  WidgetTester tester,
  FinderBase<Element> finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await _tick(tester, finder);
    if (finder.evaluate().isEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder to go away.');
}

/// One 100ms pump, timed, with a watchdog for a window that gets no frames.
///
/// A healthy pump returns in about 100–150ms. A pump the OS starves never
/// returns at all — `LiveTestWidgetsFlutterBinding.pump` waits for a frame
/// that is not coming — and the run used to sit there until a finder timed
/// out, reading like an app bug (an 18-minute step, a toast that "never went
/// away", one 60s pump). So a slow pump says how slow and what state the app
/// was in, and one that blocks for [_starvedAfter] fails the run as
/// HOST STARVED, which scripts/e2e-ui.sh reports as its own exit code.
Future<void> _tick(WidgetTester tester, FinderBase<Element> waitingFor) async {
  final watch = Stopwatch()..start();
  final starved = Completer<void>();
  final alarm = Timer(_starvedAfter, starved.complete);
  try {
    await Future.any<void>([
      tester.pump(const Duration(milliseconds: 100)),
      starved.future,
    ]);
  } finally {
    alarm.cancel();
  }
  final ms = watch.elapsedMilliseconds;
  final state = 'lifecycle=${SchedulerBinding.instance.lifecycleState} '
      'framesEnabled=${SchedulerBinding.instance.framesEnabled}';
  if (starved.isCompleted) {
    debugPrint('E2E_VERDICT=HOST_STARVED ms=$ms $state');
    throw TestFailure(
      'HOST STARVED — the test window got no frame for ${ms ~/ 1000}s '
      '($state) while waiting for $waitingFor. Not an app failure: the OS '
      'stopped drawing this window.',
    );
  }
  if (ms > 500) debugPrint('E2E_PUMPSTAT ms=$ms $state wait=$waitingFor');
}

const Duration _starvedAfter = Duration(seconds: 10);

/// Boots the app and waits until the shell is up.
///
/// Builds [MyApp] directly rather than calling `main()`: `main()` wraps
/// `runApp` in `SentryFlutter.init(appRunner:)`, which a test has no reason to
/// inherit, and `MyApp`'s constructor is already public and injectable.
///
/// Auto-login does the signing in — it is on by default and posts
/// `super@paper.local` / `Paper@12345`, which is exactly the account the
/// backend's `bootstrapSuperAdminIfNeeded` creates. That is a real HTTP login
/// against the real server, which is the part worth testing; the form itself
/// has no widget keys and is left for its own test.
Future<void> bootApp(WidgetTester tester) async {
  // The showcase tutorial opens over everything on first run and swallows the
  // first taps. It self-disables after one run, which would make this test
  // pass on the second attempt and fail on a clean machine.
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('show_sandbox_tutorial', false);

  tester.view.physicalSize = kDesktopWindow;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const MyApp());

  // The shell is up when the sidebar's Sheet pill exists. Generous, because
  // this covers activation, a real login round trip and the first provider
  // fan-out.
  await pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('sidebar_item_sheet')),
    timeout: const Duration(seconds: 90),
    reason: 'the app should reach AppShell with the sidebar drawn',
  );
}

/// Opens the item sheet from the Masters header and waits for it.
///
/// This was `openExpress`, which tapped `sidebar_express_wizard` and waited for
/// the text "Express entry". Express and the Factory Sheet wizard were two
/// doors onto one in-memory prototype and both are gone; the Masters header now
/// carries a single Sheet pill onto the real screen.
///
/// Waits on the save button's key rather than any text: the breadcrumb and the
/// section headings are wording, and wording is the first thing to change.
Future<void> openItemSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('sidebar_item_sheet')));
  await pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('save_item_sheet_btn')),
    reason: 'tapping the Sheet pill should open the item master sheet',
  );
}

/// Call once per test file.
IntegrationTestWidgetsFlutterBinding ensureBinding() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('E2E_ALLOW_HIDDEN')) _keepFramesOn(binding);
  return binding;
}

/// Keeps the scheduler drawing while the test window is covered.
///
/// The macOS engine reports a covered or hidden window as
/// `AppLifecycleState.hidden`, and the scheduler then turns frames off
/// (`SchedulerBinding.handleAppLifecycleStateChanged`). The live test binding's
/// `pump` waits for a frame, so every pump after that blocked until the window
/// was uncovered — which, on a Mac someone is using, could be never. A test
/// is never "in the background", so hidden, paused and detached are dropped
/// and resumed/inactive pass through. `E2E_ALLOW_HIDDEN=true` turns this off,
/// to show the watchdog catching what it prevents.
void _keepFramesOn(IntegrationTestWidgetsFlutterBinding binding) {
  void apply(AppLifecycleState state) =>
      // ignore: invalid_use_of_protected_member
      binding.handleAppLifecycleStateChanged(state);

  SystemChannels.lifecycle.setMessageHandler((message) async {
    switch (message) {
      case 'AppLifecycleState.resumed':
        apply(AppLifecycleState.resumed);
      case 'AppLifecycleState.inactive':
        apply(AppLifecycleState.inactive);
    }
    return null;
  });
  // The window may already have been covered when the binding read its
  // initial state.
  final now = binding.lifecycleState;
  if (now == AppLifecycleState.hidden || now == AppLifecycleState.paused) {
    apply(AppLifecycleState.resumed);
  }
}

/// Waits until no cell picker is open.
///
/// The picker is a route with a modal barrier, and the barrier ABSORBS
/// pointers while it dismisses. Tapping the next cell during that window hits
/// the barrier instead and the tap is silently lost — which is how three rows
/// came out with the third one's group never set.
bool _pickerIsOpen() =>
    find.textContaining('Type to filter').evaluate().isNotEmpty;

Future<void> waitForPickerClosed(WidgetTester tester) async {
  for (var i = 0; i < 60; i += 1) {
    if (!_pickerIsOpen()) {
      // Two more frames for the barrier itself to leave the tree.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  throw TestFailure('a cell picker never closed');
}

/// Closes whatever picker is open, so a helper starts from a known state.
///
/// Belt and braces: a picker left open covers the next cell, the tap lands on
/// it instead, and the step that follows waits for a dropdown that was never
/// asked for — which reads as a hang rather than a missed tap.
Future<void> dismissAnyPicker(WidgetTester tester) async {
  if (!_pickerIsOpen()) return;
  final close = find.byIcon(Icons.close_rounded);
  if (close.evaluate().isNotEmpty) {
    await tester.tap(close.last);
  } else {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  }
  await waitForPickerClosed(tester);
}

/// Taps a cell by its (sheet, row, column) key and picks [label] from the
/// picker it opens.
Future<void> pickInCell(
  WidgetTester tester, {
  required int column,
  required String label,
  int row = 0,
  String sheet = 'item',
}) async {
  await dismissAnyPicker(tester);
  await tester.ensureVisible(
    find.byKey(ValueKey<String>('cell_${sheet}_${row}_$column')),
  );
  await tester.pump();
  await tester.tap(find.byKey(ValueKey<String>('cell_${sheet}_${row}_$column')));

  // Scoped to the picker's own rows. Once an earlier row holds the same label,
  // a bare text finder also matches that CELL, and `.last` is then as likely
  // to tap a cell as the option.
  final option = find.widgetWithText(ListTile, label);
  await pumpUntil(
    tester,
    option,
    reason: 'the picker should offer "$label"',
  );
  await tester.tap(option.last);
  await waitForPickerClosed(tester);
}

/// Taps a cell and types a value the picker does not have, taking the
/// add-new tile.
Future<void> typeNewInCell(
  WidgetTester tester, {
  required int column,
  required String value,
  int row = 0,
  String sheet = 'item',
}) async {
  await dismissAnyPicker(tester);
  await tester.ensureVisible(
    find.byKey(ValueKey<String>('cell_${sheet}_${row}_$column')),
  );
  await tester.pump();
  await tester.tap(find.byKey(ValueKey<String>('cell_${sheet}_${row}_$column')));
  await pumpUntil(
    tester,
    find.byType(TextField),
    reason: 'the picker should open with its search field',
  );
  await tester.enterText(find.byType(TextField).last, value);
  await pumpUntil(
    tester,
    find.textContaining('Add "$value"'),
    reason: 'typing a value the picker does not have should offer to add it',
  );
  await tester.tap(find.textContaining('Add "$value"'));
  await waitForPickerClosed(tester);
}
