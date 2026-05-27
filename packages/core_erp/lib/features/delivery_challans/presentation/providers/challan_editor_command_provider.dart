import 'package:flutter/foundation.dart';

class ChallanEditorCommandProvider extends ChangeNotifier {
  VoidCallback? _openOrdersPanel;

  bool get canOpenOrdersPanel => _openOrdersPanel != null;

  void registerOrdersPanelOpener(VoidCallback callback) {
    _openOrdersPanel = callback;
  }

  void unregisterOrdersPanelOpener(VoidCallback callback) {
    if (_openOrdersPanel != callback) {
      return;
    }
    _openOrdersPanel = null;
  }

  void openOrdersFetchSlidingPanel() {
    _openOrdersPanel?.call();
  }
}
