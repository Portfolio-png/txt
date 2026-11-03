import 'package:flutter/services.dart';

/// The printable character a key press types, or null — for a closed
/// dropdown that opens its search on the first letter typed at it.
///
/// Null with Ctrl, Cmd or Alt held (those are shortcuts), for control
/// characters, and for a space (which opens the list without typing).
String? typedCharacter(KeyEvent event) {
  if (event is! KeyDownEvent) return null;
  final keyboard = HardwareKeyboard.instance;
  if (keyboard.isControlPressed || keyboard.isMetaPressed || keyboard.isAltPressed) {
    return null;
  }
  final character = event.character;
  if (character == null || character.isEmpty || character == ' ') return null;
  final code = character.codeUnitAt(0);
  if (code < 0x20 || code == 0x7F) return null;
  return character;
}
