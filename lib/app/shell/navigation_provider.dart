import 'package:flutter/material.dart';
import 'package:core_erp/core/navigation/app_navigation.dart';
import 'package:core_erp/core/services/config_service.dart';

/// Ctrl+Tab's walk, in the sidebar's own order. Every key here has a tile:
/// this used to list Telemetry and Machine Groups (no tile, so Ctrl+Tab landed
/// on screens the sidebar cannot show) and leave out People entirely.
const List<String> kSidebarNavigationOrder = <String>[
  'dashboard',
  'orders',
  'delivery_challans',
  'inventory',
  'production',
  'insights',
  'jobs',
  'pm',
  'action_center',
  'configurator_employees',
  'configurator_clients',
  'configurator_vendors',
  'configurator_items',
  'configurator_groups',
  'configurator_sets',
  'configurator_units',
  'configurator_materials',
  'configurator_machines',
  'configurator_dies',
  'production_pipelines',
];

const Set<String> kConfiguratorNavigationKeys = <String>{
  'configurator',
  'configurator_employees',
  'configurator_clients',
  'configurator_vendors',
  'configurator_items',
  'configurator_groups',
  'configurator_sets',
  'configurator_units',
  'configurator_materials',
  'configurator_machines',
  'configurator_machine_groups',
  'configurator_dies',
  'production_pipelines',
};

const List<String> kPrimaryTabNavigationKeys = <String>[
  'dashboard',
  'orders',
  'delivery_challans',
  'inventory',
  'production',
  'insights',
  'jobs',
  'telemetry',
  'pm',
  'configurator',
];

int primaryTabIndexForKey(String key) {
  return switch (key) {
    'dashboard' => 0,
    'orders' => 1,
    'delivery_challans' || 'challan_invoice_report' => 2,
    'inventory' || 'inventory_scan' => 3,
    'production' => 4,
    'insights' => 5,
    'jobs' => 6,
    'telemetry' => 7,
    'pm' => 8,
    _ when kConfiguratorNavigationKeys.contains(key) => 9,
    _ => -1,
  };
}

String? primaryTabKeyForIndex(int index) {
  return switch (index) {
    0 => 'dashboard',
    1 => 'orders',
    2 => 'delivery_challans',
    3 => 'inventory',
    4 => 'production',
    5 => 'insights',
    6 => 'jobs',
    7 => 'telemetry',
    8 => 'pm',
    9 => 'configurator',
    _ => null,
  };
}

class NavigationProvider extends ChangeNotifier implements AppNavigation {
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
  bool _isSidebarVisible = true;
  bool get isSidebarVisible => _isSidebarVisible;

  void toggleSidebar() {
    _isSidebarVisible = !_isSidebarVisible;
    notifyListeners();
  }

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
    const order = kSidebarNavigationOrder;
    final currentIndex = order.indexOf(_selectedKey);
    final safeCurrentIndex = currentIndex == -1 ? 0 : currentIndex;
    final delta = reverse ? -1 : 1;
    // Skips what this workspace has switched off, the way the sidebar hides
    // it — landing there showed the Dashboard under a tile nobody could see.
    for (var step = 1; step <= order.length; step += 1) {
      final key =
          order[(safeCurrentIndex + delta * step + order.length * step) %
              order.length];
      if (ConfigService.instance.isNavKeyAllowed(key)) {
        select(key, skipTransition: true);
        return;
      }
    }
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
