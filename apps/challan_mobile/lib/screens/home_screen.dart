import 'package:core_erp/core/widgets/app_settings_dialog.dart';
import 'package:flutter/material.dart';

import 'package:core_erp/app/dashboard/views/dashboard_screen.dart';

import 'package:core_erp/features/auth/presentation/screens/user_management_screen.dart';

import 'challan_staging_screen.dart';
import 'inventory_stock_screen.dart';
import 'module_placeholder_screen.dart';
import 'orders_list_screen.dart';
import 'purchase_challan_screens.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();

  // Production and Jobs live in the desktop `paper` package and are not wired
  // into the mobile app yet, so they show a placeholder for now.
  final List<Widget> _screens = const [
    ChallanStagingScreen(),
    ChallanTabScreen(),
    OrdersListScreen(),
    InventoryStockScreen(),
    ModulePlaceholderScreen(title: 'Production', icon: Icons.precision_manufacturing_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Staging',
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
    );
  }
}
