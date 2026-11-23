import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Sent to a field that Tab has just moved onto. A dropdown opens its list;
/// anything else (a text box) has no handler and ignores it.
///
/// Sent only by a keyboard flow (the item sheet's [SheetStep]) going forward
/// — not by a click, not by focus coming back after a pick, not by Shift+Tab —
/// so a list never reopens by itself after it closes.
class OpenDropdownIntent extends Intent {
  const OpenDropdownIntent();
}

/// Tab (or Shift+Tab) pressed inside an open list: the list closes, keeping
/// what the field had, and the field asks whatever holds it to move on — the
/// same as Tab on the closed field would.
class TabOutIntent extends Intent {
  const TabOutIntent({required this.from, this.back = false});

  /// The field the list belonged to. Named rather than read from the focus
  /// manager: focus asked for a moment ago has not landed yet.
  final FocusNode from;
  final bool back;
}

/// Moves on from [field] after its list closed on Tab: the keyboard flow
/// holding it when there is one, else plain focus traversal.
void tabOutFrom(FocusNode field, {required bool back}) {
  final context = field.context;
  if (context == null) return;
  // An Enter that moved on is spent: the next one starts a new pair.
  EnterTwice.reset();
  if (Actions.maybeInvoke(context, TabOutIntent(from: field, back: back)) != null) return;
  back ? field.previousFocus() : field.nextFocus();
}


/// Enter pressed straight after another Enter means "next", as Tab does
/// (user, 2026-11-24): the first picks or confirms, the second moves on.
/// "Straight after" is within [window] with no other key between.
///
/// Every key is seen through one [HardwareKeyboard] handler. It may run
/// before or after the focused widget's own handler, so the Enter being
/// handled is told apart from the one before it by identity, not by order.
abstract final class EnterTwice {
  static const Duration window = Duration(milliseconds: 1500);

  static KeyEvent? _last;
  static KeyEvent? _beforeLast;

  /// Starts watching the keyboard — called as a sheet opens. Taken off and
  /// put back, so it is on exactly once even where the keyboard's handlers
  /// were reset in between (each widget test does that).
  static void ensureInstalled() {
    HardwareKeyboard.instance
      ..removeHandler(_record)
      ..addHandler(_record);
  }

  static bool isEnter(KeyEvent event) =>
      event.logicalKey == LogicalKeyboardKey.enter ||
      event.logicalKey == LogicalKeyboardKey.numpadEnter;

  static bool _record(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    if (isEnter(event) && !keyboard.isControlPressed && !keyboard.isMetaPressed) {
      if (!identical(_last, event)) {
        _beforeLast = _last;
        _last = event;
      }
    } else if (!_isModifier(event.logicalKey)) {
      reset();
    }
    return false;
  }

  static bool _isModifier(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight;

  /// Whether [event], an Enter, follows another Enter closely enough to mean
  /// "next".
  static bool isSecond(KeyEvent event) {
    if (!isEnter(event)) return false;
    // Already recorded (the handler ran first): compare with the one before.
    final previous = identical(_last, event) ? _beforeLast : _last;
    if (previous == null) return false;
    final gap = event.timeStamp - previous.timeStamp;
    return gap >= Duration.zero && gap <= window;
  }

  /// Forgets the last Enter, so the next one is a first again.
  static void reset() {
    _last = null;
    _beforeLast = null;
  }
}
