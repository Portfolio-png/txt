import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../features/groups/presentation/screens/groups_screen.dart';
import '../../features/inventory/presentation/screens/inventory_screen.dart';
import '../../features/inventory/presentation/screens/material_scan_screen.dart';
import '../../features/items/presentation/screens/items_screen.dart';
import '../../features/clients/presentation/screens/clients_screen.dart';
import '../../features/orders/presentation/screens/orders_screen.dart';
import '../../features/pm/presentation/screens/pm_screen.dart';
import '../../features/production_pipelines/presentation/screens/production_pipelines_screen.dart';
import '../../features/units/presentation/screens/units_screen.dart';
import 'app_sidebar.dart';
import 'app_topbar.dart';
import 'navigation_provider.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  bool get _isDesktopPlatform =>
      kIsWeb || Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.tab, control: true): () =>
            context.read<NavigationProvider>().selectRelativeSidebarItem(),
        const SingleActivator(
          LogicalKeyboardKey.tab,
          control: true,
          shift: true,
        ): () => context.read<NavigationProvider>().selectRelativeSidebarItem(
          reverse: true,
        ),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 900;
            const sidebarWidth = 272.0;

            return Scaffold(
              backgroundColor: const Color(0xFFF4F5F9),
              drawer: isMobile
                  ? Drawer(width: 260, child: _ShellDrawerContent())
                  : null,
              appBar: isMobile
                  ? AppBar(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      title: const Text('Paper ERP'),
                    )
                  : null,
              body: SafeArea(
                top: !isMobile,
                child: Row(
                  children: [
                    if (!isMobile)
                      SizedBox(
                        width: sidebarWidth,
                        child: const AppSidebar(compact: false),
                      ),
                    Expanded(
                      child: _DesktopContentFrame(
                        enabled: _isDesktopPlatform,
                        child: Column(
                          children: [
                            if (!isMobile) const AppTopBar(),
                            const Expanded(child: _ShellContentSwitcher()),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DesktopContentFrame extends StatelessWidget {
  const _DesktopContentFrame({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth = 900.0;
        final width = constraints.maxWidth < minWidth
            ? minWidth
            : constraints.maxWidth;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: constraints.maxWidth < minWidth
              ? const ClampingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 900),
            child: SizedBox(width: width, child: child),
          ),
        );
      },
    );
  }
}

class _ShellDrawerContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppSidebar(
      compact: false,
      onItemSelected: (key) {
        context.read<NavigationProvider>().select(key);
        Navigator.of(context).pop();
      },
    );
  }
}

class _ShellContentSwitcher extends StatelessWidget {
  const _ShellContentSwitcher();

  @override
  Widget build(BuildContext context) {
    return Selector<NavigationProvider, String>(
      selector: (_, navigation) => navigation.selectedKey,
      builder: (context, key, _) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeOut,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              fit: StackFit.expand,
              children: [
                ...previousChildren,
                ...[currentChild].nonNulls,
              ],
            );
          },
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: KeyedSubtree(
            key: ValueKey<String>(key),
            child: switch (key) {
              'inventory' => const InventoryScreen(),
              'inventory_scan' => const MaterialScanScreen(),
              'production_pipelines' => const ProductionPipelinesScreen(),
              'pm' => const PMScreen(),
              'orders' => const OrdersScreen(),
              'configurator' => const _ModulePlaceholder(
                title: 'Configurator',
                description:
                    'Choose a master-data section from the sidebar to manage configuration records.',
                icon: Icons.tune_outlined,
              ),
              'configurator_clients' => const ClientsScreen(),
              'configurator_vendors' => const _ModulePlaceholder(
                title: 'Vendors',
                description:
                    'Vendor master data will appear here inside Configurator.',
                icon: Icons.storefront_outlined,
              ),
              'configurator_items' => const ItemsScreen(),
              'configurator_groups' => const GroupsScreen(),
              'configurator_units' => const UnitsScreen(),
              _ => const _ModulePlaceholder(
                title: 'Dashboard',
                description:
                    'The shell is ready. Inventory and Production are live, and dashboard widgets can be added into this slot next.',
                icon: Icons.dashboard_customize_outlined,
              ),
            },
          ),
        );
      },
    );
  }
}

class _ModulePlaceholder extends StatelessWidget {
  const _ModulePlaceholder({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE6E8F0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: const Color(0xFF6C63FF)),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}
