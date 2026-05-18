import 'package:flutter/foundation.dart';

class PreferencesProvider extends ChangeNotifier {
  bool _maintainStocks = true;

  bool get maintainStocks => _maintainStocks;

  void toggleMaintainStocks(bool value) {
    if (_maintainStocks == value) {
      return;
    }
    _maintainStocks = value;
    notifyListeners();
  }
}
