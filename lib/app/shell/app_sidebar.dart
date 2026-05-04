import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/soft_erp_theme.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import 'navigation_provider.dart';

class AppSidebar extends StatefulWidget {
  const AppSidebar({super.key, this.compact = false, this.onItemSelected});

  final bool compact;
  final ValueChanged<String>? onItemSelected;

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
      'Delivery Challan',
      Icons.description_outlined,
    ),
    _SidebarItemData('inventory', 'Inventory', Icons.inventory_2_outlined),
    _SidebarItemData(
      'production_pipelines',
      'Production',
      Icons.account_tree_outlined,
    ),
    _SidebarItemData('pm', 'PM', Icons.widgets_outlined),
  ];

  static const List<_SidebarItemData> _configuratorItems = <_SidebarItemData>[
    _SidebarItemData('configurator_clients', 'Clients', Icons.groups_outlined),
    _SidebarItemData(
      'configurator_vendors',
      'Vendors',
      Icons.storefront_outlined,
    ),
    _SidebarItemData('configurator_items', 'Items', Icons.inventory_outlined),
    _SidebarItemData('configurator_groups', 'Groups', Icons.grid_view_outlined),
    _SidebarItemData('configurator_units', 'Units', Icons.straighten_outlined),
  ];

  static const List<_SidebarItemData> _adminItems = <_SidebarItemData>[
    _SidebarItemData(
      'user_management',
      'Users',
      Icons.admin_panel_settings_outlined,
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
    final auth = context.read<AuthProvider>();
    return <String>[
      ..._moduleItems.map((item) => item.key),
      'configurator',
      if (isConfiguratorExpanded) ..._configuratorItems.map((item) => item.key),
      if (auth.canAccessUserManagement) ..._adminItems.map((item) => item.key),
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
    final canManageUsers = context.select<AuthProvider, bool>(
      (auth) => auth.canAccessUserManagement,
    );
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
            color: _isHovered
                ? Colors.white
                : Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(widget.compact ? 18 : 34),
            boxShadow: SoftErpTheme.subtleShadow,
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
                                children: _moduleItems,
                                selectedKey: selectedKey,
                                onSelected: _selectKey,
                                focusNodeForKey: _focusNodeFor,
                              ),
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
                              if (canManageUsers) ...[
                                const SizedBox(height: 10),
                                _SidebarSection(
                                  title: 'Admin',
                                  compact: widget.compact,
                                  children: _adminItems,
                                  selectedKey: selectedKey,
                                  onSelected: _selectKey,
                                  focusNodeForKey: _focusNodeFor,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (!widget.compact) ...[
                        const SizedBox(height: 8),
                        Container(
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

  static const Color _drawerColor = Color(0xFFEFEFF2);
  static const Color _drawerTabColor = Colors.white;

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
                                  isSelected: entry.value.key == selectedKey,
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
          (item) => Padding(
            padding: EdgeInsets.only(bottom: tileSpacing),
            child: _SidebarTile(
              item: item,
              compact: compact,
              isSelected: item.key == selectedKey,
              focusNode: focusNodeForKey(item.key),
              onTap: () => onSelected(item.key),
            ),
          ),
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
              onTap();
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
        final hasFocus = focusNode.hasFocus;
        final foreground = isSelected || hasFocus
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
