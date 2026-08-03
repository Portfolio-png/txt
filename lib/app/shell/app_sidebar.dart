import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:core_erp/core/services/config_service.dart';
import 'package:core_erp/core/widgets/app_toast.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:showcaseview/showcaseview.dart';

import 'package:core_erp/app/preferences/preferences_provider.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:core_erp/features/clients/presentation/providers/clients_provider.dart';
import 'package:core_erp/features/delivery_challans/presentation/providers/delivery_challan_provider.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/items/presentation/widgets/item_form_sections_dialog.dart';
import 'package:core_erp/features/orders/presentation/providers/orders_provider.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:core_erp/features/vendors/presentation/providers/vendors_provider.dart';
import 'navigation_provider.dart';

class AppSidebar extends StatefulWidget {
  const AppSidebar({
    super.key,
    this.compact = false,
    this.onItemSelected,
    this.transparentBackground = false,
    this.ordersShowcaseKey,
  });

  final bool compact;
  final ValueChanged<String>? onItemSelected;
  final bool transparentBackground;
  final GlobalKey? ordersShowcaseKey;

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  bool _isConfiguratorExpanded = true;
  final FocusScopeNode _focusScopeNode = FocusScopeNode(
    debugLabel: 'app_sidebar_scope',
  );
  final Map<String, FocusNode> _focusNodes = <String, FocusNode>{};
  bool _isHovered = false;

  static const List<_SidebarItemData> _moduleItems = <_SidebarItemData>[
    _SidebarItemData('dashboard', 'Dashboard', Icons.dashboard_outlined),
    _SidebarItemData('orders', 'Orders', Icons.receipt_long_outlined),
    _SidebarItemData(
      'delivery_challans',
      'Challans',
      Icons.description_outlined,
    ),
    _SidebarItemData('inventory', 'Inventory', Icons.inventory_2_outlined),
    _SidebarItemData(
      'production',
      'Production',
      Icons.precision_manufacturing_outlined,
    ),
    _SidebarItemData('jobs', 'Jobs', Icons.engineering_outlined),
    _SidebarItemData(
      'action_center',
      'Action Center',
      Icons.restore_from_trash_outlined,
    ),
  ];

  static const List<_SidebarItemData> _configuratorItems = <_SidebarItemData>[
    _SidebarItemData('configurator_employees', 'People', Icons.badge_outlined),
    _SidebarItemData('configurator_clients', 'Clients', Icons.groups_outlined),
    _SidebarItemData(
      'configurator_vendors',
      'Vendors',
      Icons.storefront_outlined,
    ),
    _SidebarItemData('configurator_items', 'Items', Icons.inventory_outlined),
    _SidebarItemData('configurator_units', 'Units', Icons.straighten_outlined),
    _SidebarItemData(
      'configurator_machines',
      'Machines',
      Icons.precision_manufacturing_outlined,
    ),
    _SidebarItemData('configurator_dies', 'Dies', Icons.build_circle_outlined),
    _SidebarItemData(
      'production_pipelines',
      'Pipelines',
      Icons.account_tree_outlined,
    ),
  ];

  @override
  void dispose() {
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    _focusScopeNode.dispose();
    super.dispose();
  }

  FocusNode _focusNodeFor(String key) {
    return _focusNodes.putIfAbsent(
      key,
      () => FocusNode(debugLabel: 'sidebar_$key'),
    );
  }

  List<String> _visibleSidebarKeys({required bool isConfiguratorExpanded}) {
    final mastersOn = ConfigService.instance.isModuleEnabled('masters');
    return <String>[
      ..._moduleItems.where((item) => ConfigService.instance.isModuleEnabled(item.key)).map((item) => item.key),
      if (mastersOn) 'configurator',
      if (mastersOn && isConfiguratorExpanded) ..._configuratorItems.map((item) => item.key),
    ];
  }

  void _selectKey(String key, {bool skipTransition = false}) {
    widget.onItemSelected?.call(key);
    if (widget.onItemSelected == null) {
      context.read<NavigationProvider>().select(
        key,
        skipTransition: skipTransition,
      );
    }
    if (kConfiguratorNavigationKeys.contains(key) && !_isConfiguratorExpanded) {
      setState(() {
        _isConfiguratorExpanded = true;
      });
    }
  }

  void _requestFocus(String key) {
    if (!mounted) {
      return;
    }
    _focusNodeFor(key).requestFocus();
  }

  void _selectRelativeSidebarItem({
    required List<String> visibleKeys,
    required String selectedKey,
    required bool reverse,
  }) {
    if (visibleKeys.isEmpty) {
      return;
    }

    final selectedIndex = visibleKeys.indexOf(selectedKey);
    final currentIndex = selectedIndex == -1
        ? visibleKeys.indexWhere(_isKeyFocused)
        : selectedIndex;
    final safeCurrentIndex = currentIndex == -1 ? 0 : currentIndex;
    final delta = reverse ? -1 : 1;
    final nextIndex =
        (safeCurrentIndex + delta + visibleKeys.length) % visibleKeys.length;
    final nextKey = visibleKeys[nextIndex];

    _selectKey(nextKey, skipTransition: true);
    _requestFocus(nextKey);
  }

  bool _isKeyFocused(String key) => _focusNodeFor(key).hasFocus;

  KeyEventResult _handleSidebarKeyEvent({
    required KeyEvent event,
    required String selectedKey,
    required bool isConfiguratorExpanded,
  }) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored;
    }

    final visibleKeys = _visibleSidebarKeys(
      isConfiguratorExpanded: isConfiguratorExpanded,
    );
    final isReverse = HardwareKeyboard.instance.isShiftPressed;
    if (HardwareKeyboard.instance.isControlPressed) {
      _selectRelativeSidebarItem(
        visibleKeys: visibleKeys,
        selectedKey: selectedKey,
        reverse: isReverse,
      );
      return KeyEventResult.handled;
    }

    _selectRelativeSidebarItem(
      visibleKeys: visibleKeys,
      selectedKey: selectedKey,
      reverse: isReverse,
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final selectedKey = context.select<NavigationProvider, String>(
      (navigation) => navigation.selectedKey,
    );
    // Settings & Preferences exposes destructive Workspace Data Controls
    // (Clear Data / Reset + Reseed), so keep it out of a staff member's sidebar.
    final canOpenSettings = context.select<AuthProvider, bool>(
      (auth) => auth.can('config.write'),
    );
    final mastersOn = ConfigService.instance.isModuleEnabled('masters');
    final isConfiguratorExpanded = _isConfiguratorExpanded;

    return FocusScope(
      node: _focusScopeNode,
      onKeyEvent: (node, event) => _handleSidebarKeyEvent(
        event: event,
        selectedKey: selectedKey,
        isConfiguratorExpanded: isConfiguratorExpanded,
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          decoration: BoxDecoration(
            color: widget.transparentBackground
                ? Colors.transparent
                : (_isHovered
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.8)),
            borderRadius: BorderRadius.circular(widget.compact ? 18 : 34),
            boxShadow: widget.transparentBackground
                ? const <BoxShadow>[]
                : SoftErpTheme.subtleShadow,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              widget.compact ? 10 : 14,
              widget.compact ? 12 : 16,
              widget.compact ? 10 : 14,
              widget.compact ? 12 : 14,
            ),
            child: Column(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              _SidebarSection(
                                title: 'Modules',
                                compact: widget.compact,
                                children: _moduleItems.where((item) => ConfigService.instance.isModuleEnabled(item.key)).toList(),
                                selectedKey: selectedKey,
                                onSelected: _selectKey,
                                focusNodeForKey: _focusNodeFor,
                                ordersShowcaseKey: widget.ordersShowcaseKey,
                              ),
                              if (mastersOn) ...[
                                const SizedBox(height: 10),
                                _SidebarSection(
                                  title: 'Configurator',
                                  compact: widget.compact,
                                  children: _configuratorItems,
                                  selectedKey: selectedKey,
                                  isExpandable: true,
                                  isExpanded: isConfiguratorExpanded,
                                  isParentSelected: false,
                                  onExpansionToggle: () {
                                    setState(() {
                                      _isConfiguratorExpanded =
                                          !_isConfiguratorExpanded;
                                    });
                                  },
                                  onSelected: _selectKey,
                                  focusNodeForKey: _focusNodeFor,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (!widget.compact && canOpenSettings) ...[
                        const SizedBox(height: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(30),
                          onTap: () async {
                            await showDialog<void>(
                              context: context,
                              builder: (dialogContext) =>
                                  const _SettingsPreferencesDialog(),
                            );
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDFDFF),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              'Settings &\nPreferences',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: SoftErpTheme.textPrimary,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13.5,
                                    height: 1.2,
                                  ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarSection extends StatelessWidget {
  const _SidebarSection({
    required this.title,
    required this.children,
    required this.selectedKey,
    required this.onSelected,
    required this.compact,
    this.isExpandable = false,
    this.isExpanded = true,
    this.isParentSelected = false,
    this.onExpansionToggle,
    required this.focusNodeForKey,
    this.ordersShowcaseKey,
  });

  final String title;
  final List<_SidebarItemData> children;
  final String selectedKey;
  final ValueChanged<String> onSelected;
  final bool compact;
  final bool isExpandable;
  final bool isExpanded;
  final bool isParentSelected;
  final VoidCallback? onExpansionToggle;
  final FocusNode Function(String key) focusNodeForKey;
  final GlobalKey? ordersShowcaseKey;

  static const Color _drawerColor = Color(0xFFEFEFF2);
  static const Color _drawerTabColor = Colors.white;

  bool _matchesSelectedKey(String itemKey) {
    return itemKey == selectedKey;
  }

  @override
  Widget build(BuildContext context) {
    final tileSpacing = compact ? 7.0 : 11.0;
    if (isExpandable) {
      final drawerRadius = BorderRadius.circular(compact ? 18 : 29);

      return AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.all(isExpanded ? (compact ? 6 : 8) : 0),
        decoration: BoxDecoration(
          color: isExpanded ? _drawerColor : Colors.transparent,
          borderRadius: drawerRadius,
          boxShadow: isExpanded
              ? const [
                  BoxShadow(
                    color: Color(0x10201C32),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ]
              : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SidebarExpandableHeader(
              title: title,
              compact: compact,
              isExpanded: isExpanded,
              isSelected: isParentSelected,
              focusNode: focusNodeForKey('configurator'),
              onTap: onExpansionToggle ?? () {},
              onChevronTap: onExpansionToggle ?? () {},
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              reverseDuration: const Duration(milliseconds: 240),
              transitionBuilder: (child, animation) {
                final heightAnimation = animation.drive(
                  CurveTween(curve: Curves.easeInOutCubic),
                );
                final fadeAnimation = animation.drive(
                  CurveTween(
                    curve: const Interval(
                      0.18,
                      1.0,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                );
                final slideAnimation = animation.drive(
                  Tween<Offset>(
                    begin: const Offset(0, -0.035),
                    end: Offset.zero,
                  ).chain(CurveTween(curve: Curves.easeOutCubic)),
                );

                return ClipRect(
                  child: SizeTransition(
                    sizeFactor: heightAnimation,
                    axisAlignment: -1,
                    child: FadeTransition(
                      opacity: fadeAnimation,
                      child: SlideTransition(
                        position: slideAnimation,
                        child: child,
                      ),
                    ),
                  ),
                );
              },
              child: isExpanded
                  ? Padding(
                      key: ValueKey<String>('sidebar_${title}_expanded'),
                      padding: EdgeInsets.only(top: compact ? 6 : 8),
                      child: Column(
                        children: children
                            .asMap()
                            .entries
                            .map(
                              (entry) => Padding(
                                padding: EdgeInsets.only(
                                  bottom: entry.key == children.length - 1
                                      ? 0
                                      : tileSpacing,
                                ),
                                child: _SidebarTile(
                                  item: entry.value,
                                  compact: compact,
                                  isSelected: _matchesSelectedKey(
                                    entry.value.key,
                                  ),
                                  inactiveColor: _drawerTabColor,
                                  focusNode: focusNodeForKey(entry.value.key),
                                  onTap: () => onSelected(entry.value.key),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    )
                  : const SizedBox(
                      key: ValueKey<String>('sidebar_expandable_collapsed'),
                      width: double.infinity,
                    ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact && !isExpandable && title == 'Admin')
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8, top: 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: SoftErpTheme.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: compact ? 10.5 : 11.5,
              ),
            ),
          ),
        ...children.map(
          (item) {
            Widget tile = _SidebarTile(
              item: item,
              compact: compact,
              isSelected: _matchesSelectedKey(item.key),
              focusNode: focusNodeForKey(item.key),
              onTap: () => onSelected(item.key),
            );
            if (item.key == 'orders' && ordersShowcaseKey != null) {
              tile = Showcase(
                key: ordersShowcaseKey!,
                description: 'Manage and update client order statuses dynamically from the orders menu!',
                child: tile,
              );
            }
            return Padding(
              padding: EdgeInsets.only(bottom: tileSpacing),
              child: tile,
            );
          }
        ),
      ],
    );
  }
}

class _SidebarExpandableHeader extends StatelessWidget {
  const _SidebarExpandableHeader({
    required this.title,
    required this.compact,
    required this.isExpanded,
    required this.isSelected,
    required this.focusNode,
    required this.onTap,
    required this.onChevronTap,
  });

  final String title;
  final bool compact;
  final bool isExpanded;
  final bool isSelected;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback onChevronTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, child) {
        final viewportWidth = MediaQuery.sizeOf(context).width;
        final labelSize = compact
            ? 12.5
            : viewportWidth < 1240
            ? 14.5
            : 16.0;
        final foreground = isSelected ? Colors.white : SoftErpTheme.textPrimary;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey<String>('sidebar_tile_configurator'),
            focusNode: focusNode,
            canRequestFocus: true,
            borderRadius: BorderRadius.circular(compact ? 16 : 34),
            onTap: () {
              focusNode.requestFocus();
              onChevronTap();
            },
            child: Container(
              height: compact ? 42 : 56,
              padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20),
              decoration: BoxDecoration(
                color: isSelected ? null : const Color(0xFFEFEFF2),
                gradient: isSelected ? SoftErpTheme.accentGradient : null,
                borderRadius: BorderRadius.circular(compact ? 16 : 34),
                boxShadow: isSelected ? SoftErpTheme.subtleShadow : const [],
              ),
              child: Row(
                children: [
                  if (compact)
                    Icon(Icons.tune_outlined, color: foreground, size: 18),
                  if (!compact) ...[
                    Expanded(
                      child: Text(
                        title == 'Configurator' ? 'Masters' : title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w500,
                          fontSize: labelSize,
                        ),
                      ),
                    ),
                    GestureDetector(
                      key: const ValueKey<String>(
                        'sidebar_configurator_chevron',
                      ),
                      behavior: HitTestBehavior.opaque,
                      onTap: onChevronTap,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0x33FFFFFF)
                              : const Color(0xFFE3E6FB),
                          shape: BoxShape.circle,
                        ),
                        child: AnimatedRotation(
                          turns: isExpanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: foreground,
                            size: 17,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SettingsPreferencesDialog extends StatefulWidget {
  const _SettingsPreferencesDialog();

  @override
  State<_SettingsPreferencesDialog> createState() =>
      _SettingsPreferencesDialogState();
}

/// Panes listed in the settings sidebar, in display order.
enum _SettingsPane { itemCreation, modules, workspaceData }

class _SettingsNavItem {
  const _SettingsNavItem({
    required this.pane,
    required this.label,
    required this.icon,
    required this.tint,
    this.keywords = const <String>[],
  });

  final _SettingsPane pane;
  final String label;
  final IconData icon;
  final Color tint;

  /// Extra terms the sidebar search matches on, so "stock" finds Modules and
  /// "reset" finds Workspace Data even though neither word is in the label.
  final List<String> keywords;

  bool matches(String query) {
    if (query.isEmpty) {
      return true;
    }
    return label.toLowerCase().contains(query) ||
        keywords.any((keyword) => keyword.contains(query));
  }
}

class _SettingsPreferencesDialogState
    extends State<_SettingsPreferencesDialog> {
  bool _isResetting = false;
  _SettingsPane _selectedPane = _SettingsPane.itemCreation;
  final TextEditingController _searchController = TextEditingController();

  /// Grouped exactly like macOS System Settings: separated blocks of rows
  /// rather than one long list.
  static const List<List<_SettingsNavItem>> _navGroups =
      <List<_SettingsNavItem>>[
        <_SettingsNavItem>[
          _SettingsNavItem(
            pane: _SettingsPane.itemCreation,
            label: 'Item Creation',
            icon: Icons.inventory_2_outlined,
            tint: Color(0xFF3B82F6),
            keywords: <String>[
              'item',
              'sections',
              'form',
              'image',
              'cad',
              'files',
              'variation',
              'machine',
              'die',
              'pipeline',
            ],
          ),
        ],
        <_SettingsNavItem>[
          _SettingsNavItem(
            pane: _SettingsPane.modules,
            label: 'Modules',
            icon: Icons.tune_rounded,
            tint: Color(0xFF8B5CF6),
            keywords: <String>[
              'stock',
              'trading',
              'manufacturing',
              'service',
              'job work',
              'preferences',
            ],
          ),
        ],
        <_SettingsNavItem>[
          _SettingsNavItem(
            pane: _SettingsPane.workspaceData,
            label: 'Workspace Data',
            icon: Icons.storage_rounded,
            tint: Color(0xFFEF4444),
            keywords: <String>[
              'seed',
              'demo',
              'clear',
              'reset',
              'factory',
              'scenario',
            ],
          ),
        ],
      ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<List<_SettingsNavItem>> get _visibleNavGroups {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _navGroups;
    }
    return _navGroups
        .map(
          (group) =>
              group.where((item) => item.matches(query)).toList(growable: false),
        )
        .where((group) => group.isNotEmpty)
        .toList(growable: false);
  }


  Future<void> _handleClear() async {
    setState(() {
      _isResetting = true;
    });
    final auth = context.read<AuthProvider>();
    final success = await auth.clearBackendDatabase();
    if (!mounted) {
      return;
    }
    if (!success) {
      setState(() {
        _isResetting = false;
      });
      showAppSnack(
        SnackBar(
          content: Text(
            auth.errorMessage ?? 'Failed to clear backend database.',
          ),
        ),
      );
      return;
    }

    await Future.wait<void>(<Future<void>>[
      context.read<GroupsProvider>().refresh(),
      context.read<UnitsProvider>().refresh(),
      context.read<ClientsProvider>().refresh(),
      context.read<VendorsProvider>().refresh(),
      context.read<ItemsProvider>().refresh(),
      context.read<OrdersProvider>().refresh(),
      context.read<InventoryProvider>().refresh(),
      context.read<DeliveryChallanProvider>().refresh(),
    ]);

    if (!mounted) {
      return;
    }
    setState(() {
      _isResetting = false;
    });
    showAppSnack(
      const SnackBar(content: Text('Backend database cleared successfully.')),
    );
  }

  Future<void> _handleFactoryReset() async {
    setState(() {
      _isResetting = true;
    });
    final auth = context.read<AuthProvider>();
    final success = await auth.factoryResetDatabase();
    if (!mounted) {
      return;
    }
    if (!success) {
      setState(() {
        _isResetting = false;
      });
      showAppSnack(
        SnackBar(
          content: Text(
            auth.errorMessage ?? 'Failed to factory reset database.',
          ),
        ),
      );
      return;
    }
    
    // Force logout since the user account was likely deleted.
    auth.logout();
    
    if (!mounted) return;
    
    showAppSnack(
      const SnackBar(content: Text('Factory reset complete. Please log in again.')),
    );
  }

  Future<void> _handleResetAndReseed(String scenarioId) async {
    setState(() {
      _isResetting = true;
    });
    final auth = context.read<AuthProvider>();
    final success = await auth.resetDemoData(scenarioId: scenarioId);
    if (!mounted) {
      return;
    }
    if (!success) {
      setState(() {
        _isResetting = false;
      });
      showAppSnack(
        SnackBar(
          content: Text(auth.errorMessage ?? 'Failed to reset demo data.'),
        ),
      );
      return;
    }

    await Future.wait<void>(<Future<void>>[
      context.read<GroupsProvider>().refresh(),
      context.read<UnitsProvider>().refresh(),
      context.read<ClientsProvider>().refresh(),
      context.read<VendorsProvider>().refresh(),
      context.read<ItemsProvider>().refresh(),
      context.read<OrdersProvider>().refresh(),
      context.read<InventoryProvider>().refresh(),
      context.read<DeliveryChallanProvider>().refresh(),
    ]);

    if (!mounted) {
      return;
    }
    setState(() {
      _isResetting = false;
    });
    showAppSnack(
      const SnackBar(
        content: Text('Demo data reset and reseeded successfully.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(920.0, math.max(360.0, screenSize.width - 64));
    final dialogHeight = math.min(624.0, math.max(420.0, screenSize.height - 96));
    final isNarrow = dialogWidth < 640;

    return Dialog(
      backgroundColor: SoftErpTheme.cardSurface,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: isNarrow ? 208 : 244, child: _buildSidebar()),
            const VerticalDivider(width: 1, color: SoftErpTheme.border),
            Expanded(child: _buildDetailPane()),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    final groups = _visibleNavGroups;
    return Container(
      color: SoftErpTheme.sectionSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                fontSize: 13,
                color: SoftErpTheme.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: SoftErpTheme.textSecondary,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 17,
                  color: SoftErpTheme.textSecondary,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 34,
                ),
                filled: true,
                fillColor: SoftErpTheme.cardSurface,
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: SoftErpTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: SoftErpTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: SoftErpTheme.accent),
                ),
              ),
            ),
          ),
          Expanded(
            child: groups.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'No settings match your search.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: SoftErpTheme.textSecondary,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(10, 2, 10, 16),
                    itemCount: groups.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, groupIndex) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final item in groups[groupIndex])
                            _SettingsNavRow(
                              item: item,
                              isSelected: _selectedPane == item.pane,
                              onTap: () =>
                                  setState(() => _selectedPane = item.pane),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailPane() {
    final activeItem = _navGroups
        .expand((group) => group)
        .firstWhere((item) => item.pane == _selectedPane);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  activeItem.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: _isResetting
                    ? null
                    : () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.close_rounded,
                  size: 19,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsPaneHeader(
                  icon: activeItem.icon,
                  tint: activeItem.tint,
                  title: activeItem.label,
                  description: _paneDescription(_selectedPane),
                ),
                const SizedBox(height: 18),
                ..._paneContent(_selectedPane),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _paneDescription(_SettingsPane pane) {
    switch (pane) {
      case _SettingsPane.itemCreation:
        return 'Choose which sections the item form shows when you create or '
            'edit an item.';
      case _SettingsPane.modules:
        return 'Turn workspace capabilities on or off to match how this '
            'factory actually runs.';
      case _SettingsPane.workspaceData:
        return 'Rebuild a demo workspace or wipe operational data. Users, '
            'sessions, permissions and audit data stay intact.';
    }
  }

  List<Widget> _paneContent(_SettingsPane pane) {
    switch (pane) {
      case _SettingsPane.itemCreation:
        return _buildItemCreationPane();
      case _SettingsPane.modules:
        return _buildModulesPane();
      case _SettingsPane.workspaceData:
        return _buildWorkspaceDataPane();
    }
  }

  List<Widget> _buildItemCreationPane() {
    return const <Widget>[
      Padding(
        padding: EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          'FORM SECTIONS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: SoftErpTheme.textSecondary,
          ),
        ),
      ),
      Padding(
        padding: EdgeInsets.only(left: 4, bottom: 12),
        child: Text(
          'Choose what the item form asks for. Applies to every new item you '
          'create, on every screen, for your account only.',
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: SoftErpTheme.textSecondary,
          ),
        ),
      ),
      ItemFormSectionsEditor(),
    ];
  }

  List<Widget> _buildModulesPane() {
    return <Widget>[
      Consumer<PreferencesProvider>(
        builder: (context, preferences, _) {
          return _SettingsGroup(
            children: <Widget>[
              _SettingsRow(
                icon: Icons.inventory_outlined,
                iconTint: const Color(0xFF8B5CF6),
                title: 'Maintain Stocks',
                subtitle:
                    'Turn off for typewriter challans that print documents '
                    'without touching inventory.',
                trailing: Switch.adaptive(
                  value: preferences.maintainStocks,
                  onChanged: preferences.toggleMaintainStocks,
                ),
              ),
              _SettingsRow(
                icon: Icons.swap_horiz_rounded,
                iconTint: const Color(0xFF6366F1),
                title: 'Trading Mode',
                subtitle:
                    'Enable direct buy/sell flow and standard '
                    'retail/wholesale inventory stock.',
                trailing: Switch.adaptive(
                  value: preferences.enableTrading,
                  onChanged: preferences.toggleTrading,
                ),
              ),
              _SettingsRow(
                icon: Icons.precision_manufacturing_outlined,
                iconTint: const Color(0xFFF59E0B),
                title: 'Manufacturing Mode',
                subtitle:
                    'Enable linkage to production runs, tracking raw material '
                    'vs. finished goods.',
                trailing: Switch.adaptive(
                  value: preferences.enableManufacturing,
                  onChanged: preferences.toggleManufacturing,
                ),
              ),
              _SettingsRow(
                icon: Icons.handyman_outlined,
                iconTint: const Color(0xFF10B981),
                title: 'Service (Job Work) Mode',
                subtitle:
                    'Enable customer-owned stock receipt (Inward), '
                    'printing/processing, and return.',
                trailing: Switch.adaptive(
                  value: preferences.enableServiceMode,
                  onChanged: preferences.toggleServiceMode,
                ),
              ),
            ],
          );
        },
      ),
    ];
  }

  List<Widget> _buildWorkspaceDataPane() {
    Widget seedButton(String scenarioId) {
      return OutlinedButton(
        onPressed: _isResetting
            ? null
            : () => _handleResetAndReseed(scenarioId),
        style: OutlinedButton.styleFrom(
          foregroundColor: SoftErpTheme.accent,
          side: const BorderSide(color: SoftErpTheme.accent),
          minimumSize: const Size(88, 34),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
          ),
        ),
        child: Text(_isResetting ? 'Working…' : 'Seed'),
      );
    }

    return <Widget>[
      _SettingsGroup(
        title: 'Demo Scenarios',
        children: <Widget>[
          _SettingsRow(
            icon: Icons.bolt_outlined,
            iconTint: const Color(0xFFF59E0B),
            title: 'Electrical',
            subtitle: 'Reset and reseed the default electrical workspace.',
            trailing: seedButton('default'),
          ),
          _SettingsRow(
            icon: Icons.factory_outlined,
            iconTint: const Color(0xFF6366F1),
            title: 'Manufacturing',
            subtitle: 'Reset and reseed a manufacturing workspace.',
            trailing: seedButton('manufacturing'),
          ),
          _SettingsRow(
            icon: Icons.smartphone_outlined,
            iconTint: const Color(0xFF0EA5E9),
            title: 'Mobiles',
            subtitle: 'Reset and reseed a mobiles trading workspace.',
            trailing: seedButton('mobiles'),
          ),
        ],
      ),
      const SizedBox(height: 18),
      _SettingsGroup(
        title: 'Danger Zone',
        children: <Widget>[
          _SettingsRow(
            icon: Icons.cleaning_services_outlined,
            iconTint: const Color(0xFFEF4444),
            title: 'Clear Data',
            subtitle: 'Leaves only the minimum app baseline in place.',
            trailing: FilledButton(
              onPressed: _isResetting ? null : _handleClear,
              style: FilledButton.styleFrom(
                backgroundColor: SoftErpTheme.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(88, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              child: Text(_isResetting ? 'Working…' : 'Clear'),
            ),
          ),
          _SettingsRow(
            icon: Icons.restart_alt_rounded,
            iconTint: const Color(0xFFB91C1C),
            title: 'Factory Reset',
            subtitle:
                'Wipes everything including user accounts. You will be '
                'logged out.',
            trailing: FilledButton(
              onPressed: _isResetting ? null : _handleFactoryReset,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                minimumSize: const Size(88, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              child: Text(_isResetting ? 'Working…' : 'Reset'),
            ),
          ),
        ],
      ),
    ];
  }
}

/// One row in the settings sidebar: macOS-style colored icon tile + label.
class _SettingsNavRow extends StatelessWidget {
  const _SettingsNavRow({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final _SettingsNavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: isSelected ? SoftErpTheme.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                _SettingsIconTile(icon: item.icon, tint: item.tint, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? SoftErpTheme.accent
                          : SoftErpTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded square icon chip used by both the sidebar and the detail rows.
class _SettingsIconTile extends StatelessWidget {
  const _SettingsIconTile({
    required this.icon,
    required this.tint,
    this.size = 28,
  });

  final IconData icon;
  final Color tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(size * 0.26),
      ),
      child: Icon(icon, size: size * 0.62, color: Colors.white),
    );
  }
}

/// The big icon + title + blurb block at the top of a detail pane.
class _SettingsPaneHeader extends StatelessWidget {
  const _SettingsPaneHeader({
    required this.icon,
    required this.tint,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        children: [
          _SettingsIconTile(icon: icon, tint: tint, size: 46),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: SoftErpTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: SoftErpTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A macOS-style grouped card: rows stacked inside one rounded surface with
/// hairline dividers between them, under an optional uppercase caption.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children, this.title});

  final List<Widget> children;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        rows.add(
          const Divider(
            height: 1,
            thickness: 1,
            indent: 54,
            color: SoftErpTheme.border,
          ),
        );
      }
      rows.add(children[index]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title!.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ),
        ],
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: SoftErpTheme.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SoftErpTheme.border),
          ),
          child: Column(children: rows),
        ),
      ],
    );
  }
}

/// One row inside a [_SettingsGroup]: icon, title, blurb, and the control that
/// acts on it (a switch or a button).
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.iconTint,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final Color iconTint;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _SettingsIconTile(icon: icon, tint: iconTint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.isSelected,
    required this.focusNode,
    required this.onTap,
    required this.compact,
    this.inactiveColor = const Color(0xFFEFEFF2),
  });

  final _SidebarItemData item;
  final bool isSelected;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final bool compact;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, child) {
        final viewportWidth = MediaQuery.sizeOf(context).width;
        final labelSize = compact
            ? 12.5
            : viewportWidth < 1240
            ? 14.5
            : 16.0;
        final foreground = isSelected
            ? Colors.white
            : SoftErpTheme.textPrimary;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey<String>('sidebar_tile_${item.key}'),
            focusNode: focusNode,
            canRequestFocus: true,
            borderRadius: BorderRadius.circular(compact ? 16 : 34),
            onTap: () {
              focusNode.requestFocus();
              onTap();
            },
            child: Container(
              height: compact ? 42 : 56,
              padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20),
              decoration: BoxDecoration(
                color: isSelected ? null : inactiveColor,
                gradient: isSelected ? SoftErpTheme.accentGradient : null,
                borderRadius: BorderRadius.circular(compact ? 16 : 34),
                boxShadow: isSelected ? SoftErpTheme.subtleShadow : const [],
              ),
              child: Row(
                children: [
                  if (compact) Icon(item.icon, color: foreground, size: 18),
                  if (!compact) ...[
                    Expanded(
                      child: Text(
                        item.label,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w500,
                          fontSize: labelSize,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SidebarItemData {
  const _SidebarItemData(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}
