import 'package:core_erp/core/widgets/app_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'challan_staging_screen.dart';
import 'inventory_stock_screen.dart';
import 'module_placeholder_screen.dart';
import 'orders_list_screen.dart';
import 'purchase_challan_screens.dart';

/// App shell: a persistent bottom navigation bar over five tabs, each backed by
/// its own [Navigator] inside an [IndexedStack].
///
/// The per-tab navigators are what make "keep the bottom bar while you work"
/// possible: deep screens (e.g. the Purchase wizard) push onto their tab's
/// navigator, so they render *inside* the shell with the bar still visible
/// instead of covering it. And because IndexedStack keeps every tab mounted,
/// switching away from an in-progress flow and back resumes it exactly where it
/// was — you can start a challan, jump to Inventory to check stock, and return
/// without losing anything.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  // Production and Jobs live in the desktop `paper` package and are not wired
  // into the mobile app yet, so they show a placeholder for now.
  static const List<Widget> _roots = [
    ChallanStagingScreen(),
    ChallanTabScreen(),
    OrdersListScreen(),
    InventoryStockScreen(),
    ModulePlaceholderScreen(title: 'Production', icon: Icons.precision_manufacturing_outlined),
  ];

  late final List<GlobalKey<NavigatorState>> _navKeys =
      List.generate(_roots.length, (_) => GlobalKey<NavigatorState>());

  void _onDestinationSelected(int index) {
    if (index == _currentIndex) {
      // Re-tapping the active tab steps back one route via maybePop, which
      // respects a guarded screen's PopScope — so a wizard steps a form back or
      // asks to discard rather than being popped to root and silently lost.
      _navKeys[index].currentState?.maybePop();
      return;
    }
    setState(() => _currentIndex = index);
  }

  // Back routes into the active tab first (so a deep flow steps back within the
  // shell), then falls back to the first tab, and only then exits the app.
  // Uses maybePop, not pop, so a route that guards back — the wizard steps
  // through its forms and confirms before discarding — keeps that control
  // instead of being torn off the stack whole.
  void _handleBack() {
    final nav = _navKeys[_currentIndex].currentState;
    if (nav != null && nav.canPop()) {
      nav.maybePop();
    } else if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Factory Server'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (context) => const AppSettingsDialog(),
                );
              },
            ),
          ],
        ),
        body: IndexedStack(
          index: _currentIndex,
          children: [
            for (var i = 0; i < _roots.length; i++)
              Navigator(
                key: _navKeys[i],
                onGenerateRoute: (settings) => MaterialPageRoute(
                  settings: settings,
                  builder: (_) => _roots[i],
                ),
              ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          onDestinationSelected: _onDestinationSelected,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.qr_code_scanner),
              label: 'Scan Area',
            ),
            NavigationDestination(
              icon: Icon(Icons.edit_document),
              label: 'Challan',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Order',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: 'Inventory',
            ),
            NavigationDestination(
              icon: Icon(Icons.precision_manufacturing_outlined),
              selectedIcon: Icon(Icons.precision_manufacturing),
              label: 'Production',
            ),
          ],
        ),
      ),
    );
  }
}
