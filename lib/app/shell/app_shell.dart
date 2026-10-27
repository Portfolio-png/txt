import 'dart:async';
import 'package:core_erp/features/orders/presentation/providers/orders_provider.dart';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:core_erp/core/app_flow_hooks.dart';
import 'package:core_erp/core/navigation/app_navigation.dart';
import 'package:core_erp/core/services/config_service.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/features/search/presentation/widgets/global_search_overlay.dart';
import 'package:core_erp/features/search/presentation/providers/search_provider.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/soft_primitives.dart';
import 'package:core_erp/app/reports/views/challan_invoice_reconciliation_screen.dart';
import 'package:core_erp/app/dashboard/views/dashboard_screen.dart';
import 'package:core_erp/features/action_center/presentation/screens/action_center_screen.dart';
import 'package:core_erp/features/delivery_challans/domain/delivery_challan.dart';
import 'package:core_erp/features/delivery_challans/presentation/providers/challan_editor_command_provider.dart';
import 'package:core_erp/features/delivery_challans/presentation/screens/delivery_challan_screen.dart';
import 'package:core_erp/features/departments/presentation/screens/departments_screen.dart';
import 'package:core_erp/features/departments/presentation/screens/department_editor_dialog.dart';
import 'package:core_erp/features/inventory/presentation/screens/inventory_screen.dart';
import 'package:core_erp/features/inventory/presentation/screens/material_scan_screen.dart';
import 'package:core_erp/features/items/presentation/screens/items_screen.dart';
import 'package:core_erp/features/items/presentation/widgets/item_inspector_panel.dart';
import 'package:core_erp/features/clients/presentation/screens/clients_screen.dart';
import 'package:core_erp/features/groups/presentation/screens/groups_screen.dart';
import 'package:core_erp/features/inventory/presentation/screens/sets_screen.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_create_command_provider.dart';
import 'package:core_erp/features/orders/presentation/screens/orders_screen.dart';
import '../../features/jobs/presentation/screens/jobs_screen.dart';
import '../../features/jobs/presentation/widgets/freelancer_barcode_listener.dart';
import '../../features/pm/presentation/screens/pm_screen.dart';
import 'package:core_erp/features/materials/presentation/screens/materials_screen.dart';
import 'package:core_erp/features/units/presentation/screens/units_screen.dart';
import 'package:core_erp/features/vendors/presentation/screens/vendors_screen.dart';
import '../../features/machines/presentation/screens/machine_list_screen.dart';
import '../../features/dies/domain/die.dart';
import '../../features/machines/domain/machine.dart';
import '../../features/machines/domain/machine_capability.dart';
import '../../features/machines/presentation/providers/machine_provider.dart';
import '../../features/dies/presentation/providers/die_provider.dart';
import '../../features/dies/presentation/screens/die_list_screen.dart';
import '../../features/dies/presentation/widgets/die_inspector_panel.dart';
import '../../features/machines/presentation/widgets/machine_inspector_panel.dart';
import '../../features/dies/presentation/screens/die_form_screen.dart';
import '../../features/machines/presentation/screens/machine_form_screen.dart';
import '../../features/production_pipelines/presentation/screens/production_pipelines_screen.dart';
import '../../features/machines/presentation/screens/machine_telemetry_screen.dart';
import '../../features/production/widgets/start_production_dialog.dart';
import '../../features/production/screens/live_production_monitor_screen.dart';
import '../../features/production/screens/production_runs_screen.dart';
import '../../features/production/screens/challan_insights_dashboard.dart';
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

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey _ordersKey = GlobalKey();
  bool _tutorialChecked = false;

  bool get _isDesktopPlatform =>
      kIsWeb || Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  Future<void> _checkAndShowTutorial(BuildContext showcaseContext) async {
    final prefs = await SharedPreferences.getInstance();
    final showTutorial = prefs.getBool('show_sandbox_tutorial') ?? true;
    if (showTutorial) {
      if (mounted) {
        ShowCaseWidget.of(showcaseContext).startShowCase([_ordersKey]);
        await prefs.setBool('show_sandbox_tutorial', false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      builder: (showcaseContext) {
        if (!_tutorialChecked) {
          _tutorialChecked = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkAndShowTutorial(showcaseContext);
          });
        }

        // Only the one flag: watching the whole provider rebuilt the shell,
        // the Scaffold and the sidebar on every notify — including each
        // keystroke typed into the top-strip search.
        final isSidebarVisible = showcaseContext.select<NavigationProvider, bool>(
          (nav) => nav.isSidebarVisible,
        );

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

            final shell = FreelancerBarcodeListener(
              child: PaperShortcutManager(
                child: MouseRegion(
                  onHover: (e) =>
                      GlobalMouseTracker.position.value = e.position,
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            AnimatedContainer(
                                              duration: const Duration(
                                                milliseconds: 250,
                                              ),
                                              curve: Curves.easeOutCubic,
                                              width: totalSidebarSpace,
                                              child: const Padding(
                                                padding: EdgeInsets.fromLTRB(
                                                  _ShellLayoutMetrics
                                                      .brandLeftInset,
                                                  _ShellLayoutMetrics
                                                      .brandTopInset,
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
                                          duration: const Duration(
                                            milliseconds: 250,
                                          ),
                                          curve: Curves.easeOutCubic,
                                          width: totalSidebarSpace,
                                          child: ClipRect(
                                            child: OverflowBox(
                                              minWidth: 0,
                                              maxWidth:
                                                  sidebarWidth +
                                                  _ShellLayoutMetrics
                                                      .sidebarLeftInset +
                                                  _ShellLayoutMetrics
                                                      .sidebarRightGap,
                                              alignment: Alignment.topLeft,
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      _ShellLayoutMetrics
                                                          .sidebarLeftInset,
                                                      _ShellLayoutMetrics
                                                          .sidebarTopGap,
                                                      _ShellLayoutMetrics
                                                          .sidebarRightGap,
                                                      _ShellLayoutMetrics
                                                          .sidebarBottomInset,
                                                    ),
                                                child: SizedBox(
                                                  width: sidebarWidth,
                                                  child: AppSidebar(
                                                    compact: false,
                                                    ordersShowcaseKey:
                                                        _ordersKey,
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
                                  onTap: () => context
                                      .read<NavigationProvider>()
                                      .toggleSidebar(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            return Stack(children: [shell, const GlobalSearchOverlay()]);
          },
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
    _registerAppFlowHooks();
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
    final navProvider = context.read<NavigationProvider>();
    final currentTab = context.select<NavigationProvider, int>(
      (nav) => nav.currentTabIndex,
    );

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          context.read<SearchProvider>().toggleOverlay();
        },
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () {
          context.read<SearchProvider>().toggleOverlay();
        },
        // Scan. The gun needs no shortcut — it types wherever it is pointed —
        // but a code read off a smudged label by eye has to be typed somewhere.
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
          context.read<SearchProvider>().openBarcodeLookup();
        },
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () {
          context.read<SearchProvider>().openBarcodeLookup();
        },
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
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            _handleCreateForScreen(context),
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
    // The shell's own root focus node is the only "nothing is focused" state.
    // Any other focus owner — text fields in dialogs/popouts, the top-strip
    // search — must keep its own keystrokes instead of routing them to search.
    // ponytail: identity check beats walking the element tree for EditableText,
    // which missed fields in inline popouts and ate their digits.
    return primaryFocus != null && primaryFocus != _focusNode;
  }

  void _handleCreateForScreen(BuildContext context) {
    final key = context.read<NavigationProvider>().selectedKey;
    switch (key) {
      case 'orders':
        _handleCreateOrder(context);
      case 'delivery_challans':
        _handleCreateDeliveryChallan(context);
      case 'inventory':
        context.read<InventoryCreateCommandProvider>().create();
      case 'production':
      case 'production_pipelines':
        _handleCreatePipeline(context);
      case 'configurator_employees':
        _runModalShortcut(() => DepartmentEditorDialog.open(context));
      case 'configurator_clients':
        _runModalShortcut(() => ClientsScreen.openEditor(context));
      case 'configurator_vendors':
        _runModalShortcut(() => VendorsScreen.openEditor(context));
      case 'configurator_items':
        _runModalShortcut(
          () => ItemsScreen.openEditor(
            context,
            onCreatePipeline: () => _handleCreatePipeline(context),
          ),
        );
      case 'configurator_groups':
        _runModalShortcut(() => GroupsScreen.openEditor(context));
      case 'configurator_sets':
        _runModalShortcut(() => SetsScreen.openEditor(context));
      case 'configurator_units':
        _runModalShortcut(() async => UnitsScreen.openEditor(context));
      case 'configurator_materials':
        _runModalShortcut(
          () async => MaterialsScreen.openMaterialEditor(context),
        );
      case 'configurator_machines':
      case 'configurator_machine_groups':
        _runModalShortcut(
          () async => MachinesScreen.openMachineEditor(context),
        );
      case 'configurator_dies':
        _runModalShortcut(() async => DiesScreen.openDieEditor(context));
    }
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
    if (!mounted ||
        _isModalActive(context) ||
        _focusNode.hasFocus ||
        _isEditableFocusActive()) {
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
        SearchableSelectOption(
          value: 'machine',
          label: 'new machine',
          highlightColor: Color(0xFFE4C17C),
        ),
        SearchableSelectOption(
          value: 'receipt_challan',
          label: 'new receipt challan',
          highlightColor: Color(0xFFE84A5F),
        ),
        SearchableSelectOption(
          value: 'die',
          label: 'new die',
          highlightColor: Color(0xFFB0B3B8),
        ),
        SearchableSelectOption(
          value: 'pipeline',
          label: 'new pipeline',
          highlightColor: Color(0xFF43B047),
        ),
      ],
    ).then((option) {
      if (!context.mounted || option == null) return;
      switch (option.value) {
        case 'order':
          _handleCreateOrder(context);
          break;
        case 'item':
          _runModalShortcut(
            () => ItemsScreen.openEditor(
              context,
              onCreatePipeline: () => _handleCreatePipeline(context),
            ),
          );
          break;
        case 'client':
          _runModalShortcut(() => ClientsScreen.openEditor(context));
          break;
        case 'vendor':
          _runModalShortcut(() => VendorsScreen.openEditor(context));
          break;
        case 'machine':
          _runModalShortcut(
            () async => MachinesScreen.openMachineEditor(context),
          );
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

/// Lets shared dialogs in core_erp reach the pipeline builder, which lives
/// here. Registered once, at the first shell build.
void _registerAppFlowHooks() {
  AppFlowHooks.createPipeline ??= _handleCreatePipeline;
  AppFlowHooks.createMachine ??= (context) async =>
      await MachinesScreen.openMachineEditor(context) != null;
  AppFlowHooks.createDie ??= (context) async =>
      await DiesScreen.openDieEditor(context) != null;
  // Read-only inspectors for the ecosystem ribbon. They live here because
  // `Die` and `Machine` do — core_erp can name a die from the link graph but
  // cannot describe one. Unregistered would mean a die chip simply does not
  // open, which is this seam's degrade.
  AppFlowHooks.dieInspector ??= (context, dieId) =>
      DieInspectorPanel(dieId: dieId);
  AppFlowHooks.machineInspector ??= (context, machineId) =>
      MachineInspectorPanel(machineId: machineId);
  AppFlowHooks.itemInspector ??= (context, itemId) =>
      ItemInspectorPanel(itemId: itemId);
  // NOTE: `dieEditor` and `machineEditor` have no reader at the moment. Their
  // only consumer was `creation_wizard_kinds.dart`, which went with Express.
  // They are kept rather than swept because the item sheet's Die Process
  // Master and Machines & Routing sections are what will read them next, and
  // these eight lines would only be written again. Registered-but-unread is
  // not live wiring — do not take their presence as evidence a section works.
  AppFlowHooks.dieEditor ??= (context, {required onSaved, required onCancel}) =>
      DieEditorSheet(
        onSaved: (die) => onSaved(
          CreatedRecord(id: die.id, title: die.name, subtitle: die.toolCode),
        ),
        onCancel: onCancel,
      );
  // The wizard's die sheet. It writes through DiesProvider rather than
  // posting itself, so a die made beside a part turns up on the Dies screen
  // without a reload — and so the named 409 for a taken code is already
  // parsed by the time core_erp sees it.
  AppFlowHooks.createDieFromSheet ??= (context, draft) async {
    final provider = context.read<DiesProvider>();
    // The Dies screen may never have been opened in this session.
    await provider.initialize();
    final now = DateTime.now();
    // One call for both: the route is an upsert, and a die being corrected
    // from beside its part is the same write as one being made there.
    final existing = draft.dieId == null
        ? null
        : provider.dies.where((die) => die.id == draft.dieId).firstOrNull;
    final saved = await provider.createDie(
      Die(
        id: draft.dieId ?? '',
        // Die.name is derived from producedPartNumbers on the way back, so a
        // die with nothing there reads as blank throughout the master. This is
        // naming, not a second link — which part a die makes is item_dies.
        name: existing?.name ??
            (draft.partCode.isEmpty ? draft.toolCode : draft.partCode),
        toolCode: draft.toolCode,
        // Carried, not defaulted: a die corrected from the wizard must not
        // lose the photos, notes and machine list the Dies screen gave it.
        photoUrls: existing?.photoUrls ?? const <String>[],
        operationalNotes: existing?.operationalNotes ?? '',
        compatibleMachineGroupIds:
            existing?.compatibleMachineGroupIds ?? const <int>[],
        numberOfCavities: existing?.numberOfCavities,
        strokeCount: existing?.strokeCount,
        maxStrokes: existing?.maxStrokes,
        strokesPerPiece: existing?.strokesPerPiece,
        setupMinutes: existing?.setupMinutes,
        reportNotes: existing?.reportNotes ?? '',
        physicalSpecs: existing?.physicalSpecs ?? const <CustomProperty>[],
        clientId: existing?.clientId,
        storageLocation: existing?.storageLocation,
        dieType: draft.dieType,
        // Both sent: the upsert stores what it is given, so leaving these at
        // their defaults would refuse a typed type and unlink the maker.
        dieTypeLabel: draft.dieTypeLabel,
        madeBy: draft.madeBy,
        dieMakerId: draft.dieMakerId,
        poAt: draft.poAt,
        dateInAt: draft.dateInAt,
        linerSizeNm: draft.linerSizeNm,
        linerSizeUnit: draft.linerSizeUnit,
        noOfSet: draft.noOfSet,
        storeArea: draft.storeArea,
        rackNo: draft.rackNo,
        status: existing?.status ?? DieStatus.ready,
        ownership: existing?.ownership ?? DieOwnership.inHouse,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
    if (saved == null) {
      return DieCreateOutcome.failed(
        message: provider.errorMessage ?? 'The die could not be made.',
        code: provider.errorCode,
        suggestedToolCode: provider.suggestedToolCode,
      );
    }
    return DieCreateOutcome.created(
      CreatedRecord(
        id: saved.id,
        title: saved.toolCode,
        subtitle: saved.madeBy,
      ),
    );
  };
  AppFlowHooks.dieSheetSuggestions ??= (context) async {
    final provider = context.read<DiesProvider>();
    await provider.initialize();
    // Newest first: the last person to cut a die is the likeliest next one.
    final dies = provider.dies.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    List<String> distinct(String Function(Die) read) {
      final seen = <String>{};
      final values = <String>[];
      for (final die in dies) {
        final value = read(die).trim();
        if (value.isEmpty || !seen.add(value.toLowerCase())) continue;
        values.add(value);
      }
      return values;
    }

    final typedSeen = <String>{};
    return DieSheetSuggestions(
      madeBy: distinct((d) => d.madeBy),
      storeAreas: distinct((d) => d.storeArea),
      rackNos: distinct((d) => d.rackNo),
      noOfSets: distinct((d) => d.noOfSet?.toString() ?? ''),
      linerSizesNm: [
        for (final size in distinct((d) => d.linerSizeNm?.toString() ?? ''))
          int.parse(size),
      ],
      typedTypes: [
        for (final die in dies)
          if (die.dieTypeLabel.trim().isNotEmpty &&
              typedSeen.add(die.dieType.trim()))
            (slug: die.dieType.trim(), label: die.dieTypeLabel.trim()),
      ],
      toolCodes: {
        for (final die in dies)
          if (die.toolCode.trim().isNotEmpty) die.toolCode.trim().toUpperCase(),
      },
    );
  };
  // The wizard's machine sheet. It writes through MachinesProvider rather
  // than posting itself, so a machine entered beside a part turns up on the
  // Machines screen without a reload — and so the named 409 for a taken
  // number is already parsed by the time core_erp sees it.
  AppFlowHooks.createMachineFromSheet ??= (context, draft) async {
    final provider = context.read<MachinesProvider>();
    // The Machines screen may never have been opened in this session.
    await provider.initialize();
    final now = DateTime.now();
    // One call for both: the route is an upsert, and a machine corrected from
    // beside its part is the same write as one added there.
    final existing = draft.machineId == null
        ? null
        : provider.machines
              .where((machine) => machine.id == draft.machineId)
              .firstOrNull;
    final saved = await provider.createMachine(
      Machine(
        id: draft.machineId ?? '',
        name: draft.name,
        assetId: draft.assetId,
        groupId: draft.groupId,
        machineMake: draft.machineMake,
        manufacturedYear: draft.manufacturedYear,
        feederMake: draft.feederMake,
        runningHours: draft.runningHours,
        strokesPerMinute: draft.strokesPerMinute,
        capacityKind: draft.capacityKind,
        capacityKgf: draft.capacityKgf,
        dieFeedType: draft.dieFeedType,
        // Carried, not defaulted: a machine corrected from the wizard must not
        // lose the photo, notes, capabilities and report figures the Machines
        // screen gave it.
        barcode: existing?.barcode ?? '',
        primaryPhotoUrl: existing?.primaryPhotoUrl ?? '',
        makeModel: existing?.makeModel ?? '',
        serialNumber: existing?.serialNumber ?? '',
        location: existing?.location,
        installationDate: existing?.installationDate,
        reportOutputPerHour: existing?.reportOutputPerHour,
        setupMinutes: existing?.setupMinutes,
        laborCount: existing?.laborCount,
        powerKw: existing?.powerKw,
        reportNotes: existing?.reportNotes ?? '',
        customProperties: existing?.customProperties ?? const <CustomProperty>[],
        capabilities: existing?.capabilities ?? const <MachineCapability>[],
        status: existing?.status ?? MachineStatus.active,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
    if (saved == null) {
      return MachineCreateOutcome.failed(
        message: provider.errorMessage ?? 'The machine could not be saved.',
        code: provider.errorCode,
        suggestedAssetId: provider.suggestedAssetId,
      );
    }
    return MachineCreateOutcome.created(
      CreatedRecord(
        id: saved.id,
        title: saved.assetId,
        subtitle: saved.machineMake,
      ),
    );
  };
  AppFlowHooks.machineSheetSuggestions ??= (context) async {
    final provider = context.read<MachinesProvider>();
    await provider.initialize();
    // Newest first, so the answer someone gave most recently is offered first.
    final machines = provider.machines.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    List<String> distinct(String Function(Machine) read) {
      final seen = <String>{};
      final names = <String>[];
      for (final machine in machines) {
        final value = read(machine).trim();
        if (value.isEmpty || !seen.add(value.toLowerCase())) continue;
        names.add(value);
      }
      return names;
    }

    final capacities = <int>{};
    for (final machine in machines) {
      final kgf = machine.capacityKgf;
      if (kgf != null && kgf > 0) capacities.add(kgf);
    }
    return MachineSheetSuggestions(
      makes: distinct((machine) => machine.machineMake),
      feederMakes: distinct((machine) => machine.feederMake),
      dieFeedTypes: distinct((machine) => machine.dieFeedType),
      names: distinct((machine) => machine.name),
      years: distinct((machine) => '${machine.manufacturedYear ?? ''}'),
      runningHours: distinct((machine) => '${machine.runningHours ?? ''}'),
      strokesPerMinute:
          distinct((machine) => '${machine.strokesPerMinute ?? ''}'),
      capacitiesKgf: capacities.toList(),
    );
  };
  // Unread today — see the note on `dieEditor` above.
  AppFlowHooks.machineEditor ??=
      (context, {required onSaved, required onCancel}) => MachineEditorSheet(
        onSaved: (machine) => onSaved(
          CreatedRecord(
            id: machine.id,
            title: machine.name,
            subtitle: machine.assetId,
          ),
        ),
        onCancel: onCancel,
      );
}

Future<String?> _handleCreatePipeline(BuildContext context) async {
  final template = await PipelinesScreen.openCreateDialog(context);
  if (template != null && context.mounted) {
    try {
      final repo = context.read<PipelineRunRepository>();
      final saved = await repo.createTemplate(template);
      return saved.id;
    } catch (e) {
      debugPrint('Failed to save pipeline on the fly: $e');
    }
  }
  return null;
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
                onPressed: () =>
                    context.read<NavigationProvider>().toggleSidebar(),
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
        // Backstop: a disabled module must not render even if it became the
        // selected key (default landing, Ctrl+digit, cross-navigation). Falls
        // back to the always-on dashboard.
        final allowed = ConfigService.instance.isNavKeyAllowed(key);
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
            key: ValueKey<String>(allowed ? key : 'dashboard'),
            child: !allowed
                ? const DashboardScreen()
                : switch (key) {
                    'inventory' => const InventoryScreen(),
                    'inventory_scan' => const MaterialScanScreen(),
                    'production' => const ProductionPipelinesScreen(
                      embeddedInShell: true,
                      mode: ProductionPipelinesScreenMode.production,
                    ),
                    'insights' => const ProductionRunsScreen(
                      initialTab: 'insights',
                      showTabs: false,
                    ),
                    'production_pipelines' => const ProductionPipelinesScreen(
                      embeddedInShell: true,
                      mode: ProductionPipelinesScreenMode.manage,
                    ),
                    'jobs' => const JobsScreen(),
                    'pm' => const PMScreen(),
                    'telemetry' => const MachineTelemetryScreen(),
                    'orders' => OrdersScreen(
                      onGoToProduction: (screenContext, orderGroup, [preselectedItem]) async {
                        final stableContext = outerContext;
                        final created = await showStartProductionDialog(
                          stableContext,
                          orderGroup,
                          preselectedItem: preselectedItem,
                        );
                        if (created == true && screenContext.mounted) {
                          // Attaching a run changes the order's derived status and
                          // moves it into the "In production" row of insights. The
                          // server emits nothing the client listens to, so refresh
                          // here or the order book stays stale until something else
                          // happens to reload it.
                          unawaited(
                            screenContext.read<OrdersProvider>().refresh(),
                          );
                          screenContext.read<AppNavigation>().select(
                            'production',
                          );
                        }
                      },
                      getProductionStatus: (orderGroup) async {
                        final repo = outerContext.read<PipelineRunRepository>();
                        final runs = await repo.getRunsForOrder(
                          orderGroup.orderNo,
                        );
                        final assignedItemIds = runs
                            .map((r) => r.orderItemId)
                            .whereType<int>()
                            .toSet();

                        int activeTimelineIndex =
                            orderGroup.overallStatus == OrderStatus.draft
                            ? 0
                            : 0;
                        if (runs.isNotEmpty) {
                          final allItemsAssigned =
                              assignedItemIds.length == orderGroup.items.length;
                          final anyActive = runs.any(
                            (r) =>
                                r.status == 'active' ||
                                r.nodeStatuses.values.any(
                                  (s) => s.name == 'active' || s.name == 'done',
                                ),
                          );
                          final allCompleted =
                              allItemsAssigned &&
                              runs.every((r) => r.status == 'completed');

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

                        return (
                          assignedItemIds: assignedItemIds,
                          activeTimelineIndex: activeTimelineIndex,
                        );
                      },
                      onShowPipeline: (screenContext, orderGroup, item) async {
                        final stableContext = outerContext;
                        final repo = stableContext
                            .read<PipelineRunRepository>();
                        final runs = await repo.getRunsForOrder(
                          orderGroup.orderNo,
                        );
                        final run = runs.firstWhereOrNull(
                          (r) => r.orderItemId == item.id,
                        );
                        if (run != null) {
                          final templates = await repo.getTemplates();
                          final template = templates.firstWhereOrNull(
                            (t) => t.id == run.templateId,
                          );
                          if (template != null) {
                            if (!stableContext.mounted) return;
                            stableContext
                                .read<ProductionProvider>()
                                .loadTemplate(
                                  template,
                                  orderId: run.orderItemId,
                                  orderNo: run.orderNo,
                                  clientName: run.clientName,
                                );
                            stableContext
                                .read<ProductionRunProvider>()
                                .initializeIdleRun(run.id);
                            Navigator.of(stableContext).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const LiveProductionMonitorScreen(),
                              ),
                            );
                            return;
                          }
                        }
                        // Fallback: just go to the production tab
                        if (!screenContext.mounted) return;
                        screenContext.read<AppNavigation>().select(
                          'production',
                        );
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
                    'configurator_employees' => const DepartmentsScreen(),
                    'configurator_clients' => const ClientsScreen(),
                    'configurator_vendors' => const VendorsScreen(),
                    'configurator_items' => ItemsScreen(
                      onCreatePipeline: () =>
                          _handleCreatePipeline(outerContext),
                    ),
                    'configurator_groups' => const GroupsScreen(),
                    'configurator_sets' => const SetsScreen(),
                    'configurator_units' => const UnitsScreen(),
                    'configurator_materials' => const MaterialsScreen(),
                    'configurator_machines' => const MachinesScreen(
                      initialTab: 0,
                    ),
                    'configurator_machine_groups' => const MachinesScreen(
                      initialTab: 1,
                    ),
                    'configurator_dies' => const DiesScreen(),
                    'action_center' => const ActionCenterScreen(),
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
