import 'package:flutter/foundation.dart';

/// Bridges the shell's Ctrl+N shortcut to the inventory screen's
/// toggle-aware "create" action (groups / items / sets / job work).
/// The screen registers its callback while mounted; the shell invokes it.
class InventoryCreateCommandProvider extends ChangeNotifier {
  VoidCallback? _onCreate;

  void registerCreate(VoidCallback callback) => _onCreate = callback;

  void unregisterCreate(VoidCallback callback) {
    if (_onCreate == callback) _onCreate = null;
  }

  void create() => _onCreate?.call();
}
