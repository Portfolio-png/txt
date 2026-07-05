import 'package:flutter/material.dart';

import 'challan_mobile_editor_screen.dart';
import 'challan_staging_screen.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const ChallanStagingScreen(),
    const ChallanMobileEditorScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Live Staging',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_document),
            label: 'Full Editor',
          ),
        ],
      ),
    );
  }
}
