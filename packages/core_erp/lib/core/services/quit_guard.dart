import 'dart:ui' show AppExitResponse;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The desktop app's answer to "may it quit?".
///
/// On macOS the app delegate asks over `paper/quit` before every quit — Cmd+Q,
/// the menu, the window's close button — and ignores further quits while the
/// question is open. The answer is the framework's own: every
/// [AppLifecycleListener.onExitRequested] is asked, so a screen holding
/// unsaved work keeps its "Leave with unsaved work?" question.
abstract final class QuitGuard {
  static const MethodChannel channel = MethodChannel('paper/quit');

  /// Call once, after the binding is initialised.
  static void install() {
    channel.setMethodCallHandler((call) async {
      if (call.method != 'requestQuit') {
        throw MissingPluginException('paper/quit has no ${call.method}');
      }
      final answer = await WidgetsBinding.instance.handleRequestAppExit();
      return answer == AppExitResponse.cancel ? 'cancel' : 'exit';
    });
  }

  /// Sends a quit request as the menu would — for integration tests, in a
  /// debug build only.
  @visibleForTesting
  static Future<void> debugRequestQuit() => channel.invokeMethod<void>('debugRequestQuit');
}
