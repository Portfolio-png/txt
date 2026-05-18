import 'package:flutter/material.dart';

const List<String> kSidebarNavigationOrder = <String>[
  'dashboard',
  'orders',
  'delivery_challans',
  'inventory',
  'production_pipelines',
  'pm',
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
  'production_pipelines',
  'pm',
  'configurator',
];

int primaryTabIndexForKey(String key) {
  return switch (key) {
    'dashboard' => 0,
    'orders' => 1,
    'delivery_challans' => 2,
    'inventory' || 'inventory_scan' => 3,
    'production_pipelines' => 4,
    'pm' => 5,
    _ when kConfiguratorNavigationKeys.contains(key) => 6,
    _ => -1,
  };
}

String? primaryTabKeyForIndex(int index) {
  return switch (index) {
    0 => 'dashboard',
    1 => 'orders',
    2 => 'delivery_challans',
    3 => 'inventory',
    4 => 'production_pipelines',
    5 => 'pm',
    6 => 'configurator',
    _ => null,
  };
}

class NavigationProvider extends ChangeNotifier {
  NavigationProvider({String initialKey = 'inventory'})
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
