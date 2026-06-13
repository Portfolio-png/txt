import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:core_erp/core/navigation/app_navigation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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
import '../../features/machines/presentation/screens/machine_telemetry_screen.dart';
import '../../features/production/widgets/start_production_dialog.dart';
import '../../features/production/screens/live_production_monitor_screen.dart';
import '../../features/production/providers/production_provider.dart';
import '../../features/production/providers/production_run_provider.dart';
import '../../features/production_pipelines/data/repositories/pipeline_run_repository.dart';
import 'package:core_erp/features/orders/domain/order_entry.dart'; // for OrderStatus
import 'package:collection/collection.dart';
import '../../features/production/screens/pipelines_screen.dart';
import '../../features/production/screens/pipeline_builder_screen.dart';
import '../../features/production/providers/pipeline_editor_provider.dart';
import '../../features/production/domain/default_floor_context.dart';
import 'package:core_erp/core/widgets/searchable_select.dart';

import 'app_sidebar.dart';
import 'app_topbar.dart';
import 'navigation_provider.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  bool get _isDesktopPlatform =>
      kIsWeb || Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    final navProvider = context.watch<NavigationProvider>();
    final isSidebarVisible = navProvider.isSidebarVisible;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile =
            constraints.maxWidth < _ShellLayoutMetrics.mobileBreakpoint;
        final compact =
            constraints.maxWidth < _ShellLayoutMetrics.compactBreakpoint;
        final sidebarWidth = compact
            ? _ShellLayoutMetrics.compactSidebarWidth
            : _ShellLayoutMetrics.sidebarWidth;

        final actualSidebarWidth = isSidebarVisible ? sidebarWidth : 0.0;
        final actualLeftInset = isSidebarVisible
            ? _ShellLayoutMetrics.sidebarLeftInset
            : 0.0;
        final actualRightGap = isSidebarVisible
            ? _ShellLayoutMetrics.sidebarRightGap
            : 0.0;
        final totalSidebarSpace =
            actualSidebarWidth + actualLeftInset + actualRightGap;

        return PaperShortcutManager(
          child: MouseRegion(
            onHover: (e) => GlobalMouseTracker.position.value = e.position,
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
                            height: 78,
                            child: ClipRect(
                              child: OverflowBox(
                                minHeight: 0,
                                maxHeight: 78,
                                alignment: Alignment.topCenter,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 250,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      width: totalSidebarSpace,
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
                                  width: totalSidebarSpace,
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
                    if (!isSidebarVisible && !isMobile)
                      Positioned(
                        top: 28,
                        left: 0,
                        child: _FloatingSidebarHandle(
                          isLeft: true,
                          icon: Icons.menu_rounded,
                          onTap: () => context.read<NavigationProvider>().toggleSidebar(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ));
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
        const SingleActivator(LogicalKeyboardKey.digit6, control: true): () =>
            navProvider.setTab(5),
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
        const SingleActivator(LogicalKeyboardKey.keyQ, control: true): () {
          _showQuickCreateMenu(context);
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

  void _showQuickCreateMenu(BuildContext context) {
    final offset = GlobalMouseTracker.position.value;
    final relativeRect = Rect.fromLTWH(offset.dx, offset.dy, 0, 0);

    showSearchableSelectDialog<String>(
      context: context,
      anchorRect: relativeRect,
      title: 'Create new', 
      searchHintText: 'Search...',
      options: const [
        SearchableSelectOption(value: 'order', label: 'new order'),
        SearchableSelectOption(value: 'item', label: 'new item'),
        SearchableSelectOption(value: 'client', label: 'new client'),
        SearchableSelectOption(value: 'vendor', label: 'new vendor'),
        SearchableSelectOption(value: 'machine', label: 'new machine', highlightColor: Color(0xFFE4C17C)),
        SearchableSelectOption(value: 'receipt_challan', label: 'new receipt challan', highlightColor: Color(0xFFE84A5F)),
        SearchableSelectOption(value: 'die', label: 'new die', highlightColor: Color(0xFFB0B3B8)),
        SearchableSelectOption(value: 'pipeline', label: 'new pipeline', highlightColor: Color(0xFF43B047)),
      ],
    ).then((option) {
      if (option == null) return;
      switch (option.value) {
        case 'order': 
          _handleCreateOrder(context); 
          break;
        case 'item':
          _runModalShortcut(() => ItemsScreen.openEditor(context, onCreatePipeline: () => _handleCreatePipeline(context)));
          break;
        case 'client': 
          _runModalShortcut(() => ClientsScreen.openEditor(context)); 
          break;
        case 'vendor': 
          _runModalShortcut(() => VendorsScreen.openEditor(context)); 
          break;
        case 'machine': 
          _runModalShortcut(() async => MachinesScreen.openMachineEditor(context)); 
          break;
        case 'receipt_challan': 
          _handleCreateReceptionChallan(context); 
          break;
        case 'die': 
          _runModalShortcut(() async => DiesScreen.openDieEditor(context)); 
          break;
        case 'pipeline': 
          _handleCreatePipeline(context); 
          break;
      }
    });
  }
}

Future<void> _handleCreatePipeline(BuildContext context) async {
  final template = await PipelinesScreen.openCreateDialog(context);
  if (template != null && context.mounted) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (builderContext) => ChangeNotifierProvider(
          create: (_) => PipelineEditorProvider(template: template),
          child: PipelineBuilderScreen(
            factoryId: defaultProductionFactoryId,
            shopFloorId: defaultProductionShopFloorId,
            onBack: () => Navigator.of(builderContext).pop(),
          ),
        ),
      ),
    );
  }
}

class GlobalMouseTracker {
  static final ValueNotifier<Offset> position = ValueNotifier(Offset.zero);
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
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          maxWidth: double.infinity,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SoftErpTheme.accentGradient,
            ),
            child: Center(
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFF3F5FE),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 180,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'Sarvadnya Udyog Private Limited',
                maxLines: 1,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: SoftErpTheme.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                  height: 1.0,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Collapse navbar',
            icon: const Icon(Icons.menu_open_rounded, size: 20),
            color: SoftErpTheme.textSecondary,
            onPressed: () => context.read<NavigationProvider>().toggleSidebar(),
          ),
        ],
          ),
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
  Widget build(BuildContext outerContext) {
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
              'production' => const ProductionPipelinesScreen(
                embeddedInShell: true,
                mode: ProductionPipelinesScreenMode.production,
              ),
              'production_pipelines' => const ProductionPipelinesScreen(
                embeddedInShell: true,
                mode: ProductionPipelinesScreenMode.manage,
              ),
              'pm' => const PMScreen(),
              'telemetry' => const MachineTelemetryScreen(),
              'orders' => OrdersScreen(
                onGoToProduction: (screenContext, orderGroup, [preselectedItem]) async {
                  final stableContext = outerContext;
                  final created = await showStartProductionDialog(stableContext, orderGroup, preselectedItem: preselectedItem);
                  if (created == true && screenContext.mounted) {
                    screenContext.read<AppNavigation>().select('production');
                  }
                },
                getProductionStatus: (orderGroup) async {
                  final repo = outerContext.read<PipelineRunRepository>();
                  final runs = await repo.getRunsForOrder(orderGroup.orderNo);
                  final assignedItemIds = runs.map((r) => r.orderItemId).whereType<int>().toSet();

                  int activeTimelineIndex = orderGroup.overallStatus == OrderStatus.draft ? 0 : 0;
                  if (runs.isNotEmpty) {
                    final allItemsAssigned = assignedItemIds.length == orderGroup.items.length;
                    final anyActive = runs.any((r) => r.status == 'active' || r.nodeStatuses.values.any((s) => s.name == 'active' || s.name == 'done'));
                    final allCompleted = allItemsAssigned && runs.every((r) => r.status == 'completed');

                    if (allCompleted) {
                      activeTimelineIndex = 4;
                    } else if (anyActive) {
                      activeTimelineIndex = 3;
                    } else if (allItemsAssigned) {
                      activeTimelineIndex = 2;
                    } else {
                      activeTimelineIndex = 1;
                    }
                  }

                  return (assignedItemIds: assignedItemIds, activeTimelineIndex: activeTimelineIndex);
                },
                onShowPipeline: (screenContext, orderGroup, item) async {
                  final stableContext = outerContext;
                  final repo = stableContext.read<PipelineRunRepository>();
                  final runs = await repo.getRunsForOrder(orderGroup.orderNo);
                  final run = runs.firstWhereOrNull((r) => r.orderItemId == item.id);
                  if (run != null) {
                    final templates = await repo.getTemplates();
                    final template = templates.firstWhereOrNull((t) => t.id == run.templateId);
                    if (template != null) {
                      if (!stableContext.mounted) return;
                      stableContext.read<ProductionProvider>().loadTemplate(
                        template,
                        orderId: run.orderItemId,
                        orderNo: run.orderNo,
                        clientName: run.clientName,
                      );
                      stableContext.read<ProductionRunProvider>().initializeIdleRun(run.id);
                      Navigator.of(stableContext).push(
                        MaterialPageRoute(builder: (_) => const LiveProductionMonitorScreen()),
                      );
                      return;
                    }
                  }
                  // Fallback: just go to the production tab
                  if (!screenContext.mounted) return;
                  screenContext.read<AppNavigation>().select('production');
                },
              ),
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
              'configurator_items' => ItemsScreen(initialTab: 0, onCreatePipeline: () => _handleCreatePipeline(outerContext)),
              'configurator_groups' => ItemsScreen(initialTab: 1, onCreatePipeline: () => _handleCreatePipeline(outerContext)),
              'configurator_units' => const UnitsScreen(),
              'configurator_machines' => const MachinesScreen(initialTab: 0),
              'configurator_machine_groups' => const MachinesScreen(
                initialTab: 1,
              ),
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

class _FloatingSidebarHandle extends StatelessWidget {
  const _FloatingSidebarHandle({
    required this.isLeft,
    required this.icon,
    required this.onTap,
  });

  final bool isLeft;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: const Color(0x33000000),
      borderRadius: isLeft
          ? const BorderRadius.horizontal(right: Radius.circular(12))
          : const BorderRadius.horizontal(left: Radius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: isLeft
            ? const BorderRadius.horizontal(right: Radius.circular(12))
            : const BorderRadius.horizontal(left: Radius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Icon(icon, size: 20, color: SoftErpTheme.textPrimary),
        ),
      ),
    );
  }
}
