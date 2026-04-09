import 'package:flutter/material.dart';

const List<String> kSidebarNavigationOrder = <String>[
  'dashboard',
  'orders',
  'inventory',
  'production_pipelines',
  'pm',
  'configurator',
  'configurator_clients',
  'configurator_vendors',
  'configurator_items',
  'configurator_groups',
  'configurator_units',
];

const Set<String> kConfiguratorNavigationKeys = <String>{
  'configurator',
  'configurator_clients',
  'configurator_vendors',
  'configurator_items',
  'configurator_groups',
  'configurator_units',
};

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

  void selectRelativeSidebarItem({bool reverse = false}) {
    final currentIndex = kSidebarNavigationOrder.indexOf(_selectedKey);
    final safeCurrentIndex = currentIndex == -1 ? 0 : currentIndex;
    final delta = reverse ? -1 : 1;
    final nextIndex =
        (safeCurrentIndex + delta + kSidebarNavigationOrder.length) %
        kSidebarNavigationOrder.length;
    select(kSidebarNavigationOrder[nextIndex]);
  }
}
