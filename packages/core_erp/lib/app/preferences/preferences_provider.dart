import 'package:flutter/foundation.dart';

class PreferencesProvider extends ChangeNotifier {
  bool _maintainStocks = true;
  bool _enableTrading = true;
  bool _enableManufacturing = true;
  bool _enableServiceMode = true;

  bool get maintainStocks => _maintainStocks;
  bool get enableTrading => _enableTrading;
  bool get enableManufacturing => _enableManufacturing;
  bool get enableServiceMode => _enableServiceMode;

  void toggleMaintainStocks(bool value) {
    if (_maintainStocks == value) {
      return;
    }
    _maintainStocks = value;
    notifyListeners();
  }

  void toggleTrading(bool value) {
    if (_enableTrading == value) {
      return;
    }
    _enableTrading = value;
    notifyListeners();
  }

  void toggleManufacturing(bool value) {
    if (_enableManufacturing == value) {
      return;
    }
    _enableManufacturing = value;
    notifyListeners();
  }

  void toggleServiceMode(bool value) {
    if (_enableServiceMode == value) {
      return;
    }
    _enableServiceMode = value;
    notifyListeners();
  }
}
