import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/features/auth/domain/auth_user.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/soft_primitives.dart';
import 'package:core_erp/app/reports/views/challan_invoice_reconciliation_screen.dart';
import 'package:core_erp/app/dashboard/views/dashboard_screen.dart';
import 'package:core_erp/features/auth/presentation/screens/user_management_screen.dart';
import 'package:core_erp/features/delivery_challans/domain/delivery_challan.dart';
import 'package:core_erp/features/delivery_challans/presentation/providers/challan_editor_command_provider.dart';
import 'package:core_erp/features/delivery_challans/presentation/screens/delivery_challan_screen.dart';
import 'package:core_erp/features/inventory/presentation/screens/inventory_screen.dart';
import 'package:core_erp/features/inventory/presentation/screens/material_scan_screen.dart';
import 'package:core_erp/features/items/presentation/screens/items_screen.dart';
import 'package:core_erp/features/clients/presentation/screens/clients_screen.dart';
import 'package:core_erp/features/orders/presentation/screens/orders_screen.dart';
import '../../features/pm/presentation/screens/pm_screen.dart';
import 'package:core_erp/features/units/presentation/screens/units_screen.dart';
import 'package:core_erp/features/vendors/presentation/screens/vendors_screen.dart';
import '../../features/machines/presentation/screens/machine_list_screen.dart';
import '../../features/dies/presentation/screens/die_list_screen.dart';
import '../../features/production_pipelines/presentation/screens/production_pipelines_screen.dart';
import 'app_sidebar.dart';
import 'app_topbar.dart';
import 'navigation_provider.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  bool get _isDesktopPlatform =>
      kIsWeb || Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    final selectedKey = context.select<NavigationProvider, String>(
      (navigation) => navigation.selectedKey,
    );
    final isProduction = selectedKey == 'production_pipelines';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile =
            constraints.maxWidth < _ShellLayoutMetrics.mobileBreakpoint;
        final compact =
            constraints.maxWidth < _ShellLayoutMetrics.compactBreakpoint;
        final sidebarWidth = compact
            ? _ShellLayoutMetrics.compactSidebarWidth
            : _ShellLayoutMetrics.sidebarWidth;

        return PaperShortcutManager(
          child: Scaffold(
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
                child: Stack(
                  children: [
                    Column(
                      children: [
                        if (!isMobile)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutCubic,
                            height: isProduction ? 0 : 78,
                            child: ClipRect(
                              child: OverflowBox(
                                minHeight: 0,
                                maxHeight: 78,
                                alignment: Alignment.topCenter,
                                child: Row(
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
                                    Expanded(
                                      child: isProduction
                                          ? const SizedBox.shrink()
                                          : const AppTopBar(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Row(
                            children: [
                              if (!isMobile)
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOutCubic,
                                  width: isProduction
                                      ? 0
                                      : sidebarWidth +
                                            _ShellLayoutMetrics
                                                .sidebarLeftInset +
                                            _ShellLayoutMetrics.sidebarRightGap,
                                  child: ClipRect(
                                    child: OverflowBox(
                                      minWidth: 0,
                                      maxWidth:
                                          sidebarWidth +
                                          _ShellLayoutMetrics.sidebarLeftInset +
                                          _ShellLayoutMetrics.sidebarRightGap,
                                      alignment: Alignment.topLeft,
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          _ShellLayoutMetrics.sidebarLeftInset,
                                          _ShellLayoutMetrics.sidebarTopGap,
                                          _ShellLayoutMetrics.sidebarRightGap,
                                          _ShellLayoutMetrics
                                              .sidebarBottomInset,
                                        ),
                                        child: SizedBox(
                                          width: sidebarWidth,
                                          child: const AppSidebar(
                                            compact: false,
                                          ),
                                        ),
                                      ),
                                    ),
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
                    if (!isMobile && isProduction)
                      const Positioned(
                        left: 16,
                        top: 16,
                        child: _ProductionOverlayControl(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class PaperShortcutManager extends StatefulWidget {
  const PaperShortcutManager({super.key, required this.child});

  final Widget child;

  @override
  State<PaperShortcutManager> createState() => _PaperShortcutManagerState();
}

class _PaperShortcutManagerState extends State<PaperShortcutManager> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'paper_shortcut_manager');
  bool _isModalShortcutPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestShellFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navProvider = context.watch<NavigationProvider>();
    final currentTab = navProvider.currentTabIndex;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            navProvider.setTab(0),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            navProvider.setTab(1),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
            navProvider.setTab(2),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true): () =>
            navProvider.setTab(3),
        const SingleActivator(LogicalKeyboardKey.digit5, control: true): () =>
            navProvider.setTab(4),
        const SingleActivator(LogicalKeyboardKey.tab, control: true): () =>
            navProvider.selectRelativeSidebarItem(),
        const SingleActivator(
          LogicalKeyboardKey.tab,
          control: true,
          shift: true,
        ): () =>
            navProvider.selectRelativeSidebarItem(reverse: true),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            navProvider.focusTopStripSearch,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
          if (currentTab == 1) {
            _handleCreateOrder(context);
            return;
          }
          if (currentTab == 2) {
            _handleCreateDeliveryChallan(context);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () {
          if (currentTab == 2) {
            context
                .read<ChallanEditorCommandProvider>()
                .openOrdersFetchSlidingPanel();
          }
        },
        const SingleActivator(
          LogicalKeyboardKey.keyN,
          control: true,
          alt: true,
        ): () {
          if (currentTab == 2) {
            _handleCreateReceptionChallan(context);
          }
        },
        const SingleActivator(LogicalKeyboardKey.f8): () {
          if (currentTab == 2) {
            _handleCreateDeliveryChallan(context);
          }
        },
        const SingleActivator(LogicalKeyboardKey.f9): () {
          if (currentTab == 2) {
            _handleCreateReceptionChallan(context);
          }
        },
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        includeSemantics: false,
        onKeyEvent: _handleShellKeyEvent,
        child: widget.child,
      ),
    );
  }

  KeyEventResult _handleShellKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (_shouldHandleDashboardHome(event)) {
      context.read<NavigationProvider>().setTab(0);
      return KeyEventResult.handled;
    }

    final character = event.character;
    if (_shouldRouteTypingToSearch(event, character)) {
      context.read<NavigationProvider>().typeIntoTopStripSearch(character!);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  bool _shouldHandleDashboardHome(KeyDownEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.home) {
      return false;
    }
    if (HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isShiftPressed) {
      return false;
    }
    if (_isEditableFocusActive()) {
      return false;
    }
    return true;
  }

  bool _shouldRouteTypingToSearch(KeyDownEvent event, String? character) {
    if (character == null || character.isEmpty) {
      return false;
    }
    if (HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
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
    var editableFound = false;
    focusedContext.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        editableFound = true;
        return false;
      }
      return true;
    });
    return editableFound;
  }

  Future<void> _handleCreateOrder(BuildContext context) {
    return _runModalShortcut(() => OrdersScreen.openEditor(context));
  }

  Future<void> _handleCreateDeliveryChallan(BuildContext context) {
    return _runModalShortcut(
      () =>
          ChallanScreen.openEditor(context, initialType: ChallanType.delivery),
    );
  }

  Future<void> _handleCreateReceptionChallan(BuildContext context) {
    return _runModalShortcut(() => ChallanScreen.openReceptionEditor(context));
  }

  Future<void> _runModalShortcut(Future<void> Function() openModal) async {
    if (_isModalShortcutPending || _isModalActive(context)) {
      return;
    }

    _isModalShortcutPending = true;
    try {
      await openModal();
    } finally {
      _isModalShortcutPending = false;
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _requestShellFocus();
        });
      }
    }
  }

  bool _isModalActive(BuildContext context) {
    final route = ModalRoute.of(context);
    return route != null && !route.isCurrent;
  }

  void _requestShellFocus() {
    if (!mounted || _isModalActive(context) || _focusNode.hasFocus) {
      return;
    }
    _focusNode.requestFocus();
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
              'Sarvadnya Udyog Private Limited',
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
              'production_pipelines' => const ProductionPipelinesScreen(
                embeddedInShell: true,
              ),
              'pm' => const PMScreen(),
              'orders' => const OrdersScreen(),
              'delivery_challans' => const ChallanScreen(),
              'challan_invoice_report' =>
                const ChallanInvoiceReconciliationScreen(),
              'configurator' => const _ModulePlaceholder(
                title: 'Configurator',
                description:
                    'Choose a master-data section from the sidebar to manage configuration records.',
                icon: Icons.tune_outlined,
              ),
              'configurator_clients' => const ClientsScreen(),
              'configurator_vendors' => const VendorsScreen(),
              'configurator_items' => const ItemsScreen(initialTab: 0),
              'configurator_groups' => const ItemsScreen(initialTab: 1),
              'configurator_units' => const UnitsScreen(),
              'configurator_machines' => const MachinesScreen(initialTab: 0),
              'configurator_machine_groups' => const MachinesScreen(initialTab: 1),
              'configurator_dies' => const DiesScreen(),
              'user_management' => const UserManagementScreen(),
              _ => const DashboardScreen(),
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

void _noopSearch(String _) {}

class _ProductionOverlayControl extends StatefulWidget {
  const _ProductionOverlayControl();

  @override
  State<_ProductionOverlayControl> createState() =>
      _ProductionOverlayControlState();
}

class _ProductionOverlayControlState extends State<_ProductionOverlayControl> {
  bool _isHovered = false;
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final currentUser = context.select<AuthProvider, AuthUser?>(
      (auth) => auth.user,
    );
    final selectedKey = context.select<NavigationProvider, String>(
      (navigation) => navigation.selectedKey,
    );
    final config = resolveTopStrip(selectedKey, context);
    final searchConfig =
        config.search ??
        const ShellTopStripSearchConfig(
          placeholder: 'Search',
          initialValue: '',
          onChanged: _noopSearch,
        );

    final mediaHeight = MediaQuery.sizeOf(context).height;
    final panelHeight = (mediaHeight - 32).clamp(56.0, double.infinity);
    final isOpen = _isHovered || _isExpanded;

    return TapRegion(
      onTapOutside: (event) {
        setState(() {
          _isExpanded = false;
        });
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: isOpen ? 340 : 56,
          height: isOpen ? panelHeight : 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isOpen ? 24 : 28),
            boxShadow: isOpen
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 24,
                      spreadRadius: 4,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : SoftErpTheme.subtleShadow,
            border: Border.all(
              color: Colors.white.withValues(alpha: isOpen ? 0.35 : 0.2),
              width: 1.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(isOpen ? 24 : 28),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: isOpen ? 16 : 8,
                sigmaY: isOpen ? 16 : 8,
              ),
              child: Container(
                color: Colors.white.withValues(alpha: isOpen ? 0.35 : 0.15),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: isOpen
                      ? _buildFullPanel(context, currentUser, searchConfig)
                      : _buildCollapsedButton(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedButton() {
    return InkWell(
      key: const ValueKey('collapsed'),
      onTap: () {
        setState(() {
          _isExpanded = !_isExpanded;
        });
      },
      borderRadius: BorderRadius.circular(28),
      child: const Center(
        child: Icon(
          Icons.menu_open_rounded,
          color: SoftErpTheme.textPrimary,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildFullPanel(
    BuildContext context,
    AuthUser? currentUser,
    ShellTopStripSearchConfig searchConfig,
  ) {
    return Padding(
      key: const ValueKey('expanded'),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(
                  Icons.menu_open_rounded,
                  color: SoftErpTheme.textPrimary,
                  size: 24,
                ),
                onPressed: () {
                  setState(() {
                    _isExpanded = false;
                    _isHovered = false;
                  });
                },
              ),
              const SizedBox(width: 8),
              Expanded(child: ShellTopStripSearchField(search: searchConfig)),
              const SizedBox(width: 10),
              SizedBox(
                width: 66,
                child: TopStripProfileCard(user: currentUser),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          const Expanded(
            child: AppSidebar(compact: false, transparentBackground: true),
          ),
        ],
      ),
    );
  }
}
