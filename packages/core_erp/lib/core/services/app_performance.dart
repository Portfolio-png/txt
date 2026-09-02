import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether to spend frames on decoration.
///
/// Every row in every list was drawing a fade (`FadeTransition` → `saveLayer`),
/// a slide, a hover shadow with a 12px blur, and its own 700ms entrance
/// animation with its own `AnimationController`. On a machine with a GPU none of
/// that costs anything worth measuring. On one without — an office i3 with
/// integrated graphics, which is what this software is actually installed on —
/// Flutter rasterises in software, and `saveLayer` and shadow blur are the two
/// most expensive things it can be asked to do. Doing both for every visible row
/// on every scroll frame is what makes a list feel heavy on hardware that should
/// have no trouble with it.
///
/// Reduced effects keeps the layout, the colours and the hover feedback, and
/// drops the parts that cost a rasterisation pass: no fade, no slide, no
/// entrance controller, flat borders instead of blurred shadows.
///
/// It follows the operating system first. A machine set to "reduce motion"
/// already told us what it wants, and honouring that is free.
class AppPerformance {
  AppPerformance._();

  static const String _prefKey = 'reduced_effects';

  /// Null until loaded, then the user's explicit choice. Kept as a notifier so
  /// a change repaints the lists without an app restart.
  static final ValueNotifier<bool> reducedEffects = ValueNotifier<bool>(false);

  static bool _loaded = false;

  /// Reads the stored preference. Safe to call more than once.
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      reducedEffects.value = prefs.getBool(_prefKey) ?? false;
    } catch (_) {
      // A preference that cannot be read is not a reason to fail to start.
    }
  }

  static Future<void> setReducedEffects(bool value) async {
    reducedEffects.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (_) {
      // The setting still applies for this session even if it cannot be saved.
    }
  }

  /// Whether this build should skip decorative work.
  ///
  /// True when the user asked for it, or when the platform is set to reduce
  /// motion — an accessibility setting that means the same thing here and costs
  /// nothing to respect.
  static bool of(BuildContext context) {
    if (reducedEffects.value) return true;
    final media = MediaQuery.maybeOf(context);
    return media?.disableAnimations ?? false;
  }
}
