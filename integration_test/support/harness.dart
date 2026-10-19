import 'package:flutter/material.dart';
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
/// is 800x600 — so without this the Express pill is not on screen at all.
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
    await tester.pump(const Duration(milliseconds: 100));
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

/// Every piece of text currently rendered, for a failure message.
///
/// Worth the lines: without it a timeout says only what was NOT found, and the
/// next move is a ten-minute guess. With it the failure names the screen the
/// app was actually on.
String visibleText(WidgetTester tester, {int limit = 50}) {
  final seen = <String>[];
  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
    final trimmed = text.trim();
    if (trimmed.isEmpty || seen.contains(trimmed)) continue;
    seen.add(trimmed);
    if (seen.length >= limit) break;
  }
  return seen.isEmpty ? '(no text at all)' : seen.join(' | ');
}

/// Pumps until [finder] matches nothing — a dialog closing, a spinner going.
Future<void> pumpUntilGone(
  WidgetTester tester,
  FinderBase<Element> finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder to go away.');
}

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

  // The shell is up when the sidebar's Express pill exists. Generous, because
  // this covers activation, a real login round trip and the first provider
  // fan-out.
  await pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('sidebar_express_wizard')),
    timeout: const Duration(seconds: 90),
    reason: 'the app should reach AppShell with the sidebar drawn',
  );
}

/// Opens the Express window and waits for it.
///
/// `openExpress` awaits `CreationLineupStore().load()` before `showDialog`, so
/// the window is one async hop behind the tap.
Future<void> openExpress(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('sidebar_express_wizard')));
  await pumpUntil(
    tester,
    find.text('Express entry'),
    reason: 'tapping the Express pill should open the creation window',
  );
}

/// Call once per test file.
IntegrationTestWidgetsFlutterBinding ensureBinding() =>
    IntegrationTestWidgetsFlutterBinding.ensureInitialized();
