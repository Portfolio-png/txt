import 'package:flutter/material.dart';

class NavigationProvider extends ChangeNotifier {
  NavigationProvider({String initialKey = 'inventory'})
    : _selectedKey = initialKey;

  String _selectedKey;

  String get selectedKey => _selectedKey;

  void select(String key) {
    if (_selectedKey == key) {
      return;
    }

    _selectedKey = key;
    notifyListeners();
  }
}
