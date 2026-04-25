import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/soft_erp_theme.dart';
import '../../core/widgets/soft_primitives.dart';
import '../../features/groups/presentation/screens/groups_screen.dart';
import '../../features/auth/presentation/screens/user_management_screen.dart';
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

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final FocusNode _shellFocusNode = FocusNode(debugLabel: 'app_shell');
  bool _isOpeningNewOrder = false;

  bool get _isDesktopPlatform =>
      kIsWeb || Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _shellFocusNode.hasFocus) {
        return;
      }
      _shellFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _shellFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _shellFocusNode,
      autofocus: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 900;
          final sidebarWidth = constraints.maxWidth < 1280 ? 270.0 : 286.0;

          return Scaffold(
            backgroundColor: Colors.transparent,
            drawer: isMobile
                ? Drawer(width: 236, child: _ShellDrawerContent())
                : null,
            appBar: isMobile
                ? AppBar(
                    backgroundColor: SoftErpTheme.shellSurface,
                    foregroundColor: SoftErpTheme.textPrimary,
                    title: const Text('Paper ERP'),
                  )
                : null,
            body: SafeArea(
              top: !isMobile,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFE8E8F0), Color(0xFFA7B9F9)],
                  ),
                ),
                child: Column(
                  children: [
                    if (!isMobile) const AppTopBar(),
                    Expanded(
                      child: Row(
                        children: [
                          if (!isMobile)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(30, 10, 10, 22),
                              child: SizedBox(
                                width: sidebarWidth,
                                child: const AppSidebar(compact: false),
                              ),
                            ),
                          Expanded(
                            child: _DesktopContentFrame(
                              enabled: _isDesktopPlatform,
                              child: const _ShellContentSwitcher(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    return _handleShellKeyEvent(event) == KeyEventResult.handled;
  }

  KeyEventResult _handleShellKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final isControlPressed = HardwareKeyboard.instance.isControlPressed;
    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
    final usesCommandModifier = isControlPressed || isMetaPressed;
    if (!usesCommandModifier) {
      return KeyEventResult.ignored;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.tab:
        context.read<NavigationProvider>().selectRelativeSidebarItem(
          reverse: HardwareKeyboard.instance.isShiftPressed,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyN:
        _openNewOrderFromShortcut(context);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyF:
        context.read<NavigationProvider>().focusTopStripSearch();
        return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _openNewOrderFromShortcut(BuildContext context) {
    if (_isOpeningNewOrder) {
      return;
    }

    _isOpeningNewOrder = true;
    OrdersScreen.openEditor(context).whenComplete(() {
      _isOpeningNewOrder = false;
    });
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
        final skipTransition = context
            .read<NavigationProvider>()
            .consumeSkipNextContentTransition();
        return AnimatedSwitcher(
          duration: skipTransition
              ? Duration.zero
              : const Duration(milliseconds: 180),
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
              'user_management' => const UserManagementScreen(),
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SoftSurface(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: SoftErpTheme.accent),
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
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SoftErpTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
