import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/soft_erp_theme.dart';
import '../../core/widgets/soft_primitives.dart';
import '../../features/groups/presentation/screens/groups_screen.dart';
import '../../features/auth/presentation/screens/user_management_screen.dart';
import '../../features/delivery_challans/presentation/screens/delivery_challan_screen.dart';
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
          final isMobile =
              constraints.maxWidth < _ShellLayoutMetrics.mobileBreakpoint;
          final compact =
              constraints.maxWidth < _ShellLayoutMetrics.compactBreakpoint;
          final sidebarWidth = compact
              ? _ShellLayoutMetrics.compactSidebarWidth
              : _ShellLayoutMetrics.sidebarWidth;

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
                    if (!isMobile)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width:
                                sidebarWidth +
                                _ShellLayoutMetrics.sidebarLeftInset +
                                _ShellLayoutMetrics.sidebarRightGap,
                            child: const Padding(
                              padding: EdgeInsets.fromLTRB(
                                _ShellLayoutMetrics.brandLeftInset,
                                _ShellLayoutMetrics.brandTopInset,
                                0,
                                0,
                              ),
                              child: _ShellCompanyBrand(),
                            ),
                          ),
                          const Expanded(child: AppTopBar()),
                        ],
                      ),
                    Expanded(
                      child: Row(
                        children: [
                          if (!isMobile)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                _ShellLayoutMetrics.sidebarLeftInset,
                                _ShellLayoutMetrics.sidebarTopGap,
                                _ShellLayoutMetrics.sidebarRightGap,
                                _ShellLayoutMetrics.sidebarBottomInset,
                              ),
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
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
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
      final character = event.character;
      if (_shouldRouteTypingToSearch(event, character)) {
        context.read<NavigationProvider>().typeIntoTopStripSearch(character!);
        return KeyEventResult.handled;
      }
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

  bool _shouldRouteTypingToSearch(KeyDownEvent event, String? character) {
    if (character == null || character.isEmpty) {
      return false;
    }
    if (HardwareKeyboard.instance.isAltPressed) {
      return false;
    }
    if (event.logicalKey == LogicalKeyboardKey.space) {
      return false;
    }
    if (character.runes.length != 1) {
      return false;
    }
    final codeUnit = character.runes.single;
    if (codeUnit < 0x20 || codeUnit == 0x7F) {
      return false;
    }
    if (_isEditableFocusActive()) {
      return false;
    }
    return true;
  }

  bool _isEditableFocusActive() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus ==
        context.read<NavigationProvider>().topStripSearchFocusNode) {
      return true;
    }

    final focusedContext = primaryFocus?.context;
    if (focusedContext == null) {
      return false;
    }
    if (focusedContext.widget is EditableText) {
      return true;
    }
    var editableFound = focusedContext.widget is EditableText;
    focusedContext.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        editableFound = true;
        return false;
      }
      return true;
    });
    return editableFound;
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

class _ShellLayoutMetrics {
  const _ShellLayoutMetrics._();

  static const double mobileBreakpoint = 900;
  static const double compactBreakpoint = 1240;
  static const double compactSidebarWidth = 250;
  static const double sidebarWidth = 286;
  static const double sidebarLeftInset = 30;
  static const double sidebarRightGap = 10;
  static const double sidebarTopGap = 10;
  static const double sidebarBottomInset = 22;
  static const double brandLeftInset = 20;
  static const double brandTopInset = 21.5;
  static const double desktopContentMinWidth = 900;
}

class _ShellCompanyBrand extends StatelessWidget {
  const _ShellCompanyBrand();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 49,
      child: Row(
        children: [
          Container(
            width: 49,
            height: 49,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SoftErpTheme.accentGradient,
            ),
            child: Center(
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFF3F5FE),
                ),
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              'Sarvodaya Udyog',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: SoftErpTheme.textPrimary,
                fontWeight: FontWeight.w500,
                fontSize: 16,
                height: 1.0,
              ),
            ),
          ),
        ],
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
        const minWidth = _ShellLayoutMetrics.desktopContentMinWidth;
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
              'delivery_challans' => const DeliveryChallanScreen(),
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
