import 'package:flutter/material.dart';
import 'package:core_erp/core/navigation/app_navigation.dart';

const List<String> kSidebarNavigationOrder = <String>[
  'dashboard',
  'orders',
  'delivery_challans',
  'inventory',
  'configurator',
  'configurator_clients',
  'configurator_vendors',
  'configurator_items',
  'configurator_groups',
  'configurator_units',
  'user_management',
];

const Set<String> kConfiguratorNavigationKeys = <String>{
  'configurator',
  'configurator_clients',
  'configurator_vendors',
  'configurator_items',
  'configurator_groups',
  'configurator_units',
};

const List<String> kPrimaryTabNavigationKeys = <String>[
  'dashboard',
  'orders',
  'delivery_challans',
  'inventory',
  'configurator',
];

int primaryTabIndexForKey(String key) {
  return switch (key) {
    'dashboard' => 0,
    'orders' => 1,
    'delivery_challans' || 'challan_invoice_report' => 2,
    'inventory' || 'inventory_scan' => 3,
    _ when kConfiguratorNavigationKeys.contains(key) => 4,
    _ => -1,
  };
}

String? primaryTabKeyForIndex(int index) {
  return switch (index) {
    0 => 'dashboard',
    1 => 'orders',
    2 => 'delivery_challans',
    3 => 'inventory',
    4 => 'configurator',
    _ => null,
  };
}

class NavigationProvider extends ChangeNotifier implements AppNavigation {
  NavigationProvider({String initialKey = 'delivery_challans'})
    : _selectedKey = initialKey;

  String _selectedKey;
  int _topStripSearchTextRevision = 0;
  String _pendingTopStripSearchText = '';
  final FocusNode topStripSearchFocusNode = FocusNode(
    debugLabel: 'top_strip_search',
  );

  String get selectedKey => _selectedKey;
  int get currentTabIndex => primaryTabIndexForKey(_selectedKey);
  int get topStripSearchTextRevision => _topStripSearchTextRevision;
  bool _skipNextContentTransition = false;

  @override
  void select(String key, {bool skipTransition = false}) {
    if (_selectedKey == key) {
      return;
    }
    if (skipTransition) {
      _skipNextContentTransition = true;
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
    select(kSidebarNavigationOrder[nextIndex], skipTransition: true);
  }

  void setTab(int index, {bool skipTransition = false}) {
    final key = primaryTabKeyForIndex(index);
    if (key == null) {
      return;
    }
    select(key, skipTransition: skipTransition);
  }

  bool consumeSkipNextContentTransition() {
    final shouldSkip = _skipNextContentTransition;
    _skipNextContentTransition = false;
    return shouldSkip;
  }

  void focusTopStripSearch() {
    topStripSearchFocusNode.requestFocus();
  }

  void typeIntoTopStripSearch(String text) {
    if (text.isEmpty) {
      focusTopStripSearch();
      return;
    }
    _pendingTopStripSearchText += text;
    _topStripSearchTextRevision += 1;
    focusTopStripSearch();
    notifyListeners();
  }

  String consumePendingTopStripSearchText() {
    final text = _pendingTopStripSearchText;
    _pendingTopStripSearchText = '';
    return text;
  }

  @override
  void dispose() {
    topStripSearchFocusNode.dispose();
    super.dispose();
  }
}
