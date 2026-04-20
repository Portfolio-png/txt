import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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

  static const List<_SidebarItemData> _moduleItems = <_SidebarItemData>[
    _SidebarItemData('dashboard', 'Dashboard', Icons.dashboard_outlined),
    _SidebarItemData('orders', 'Orders', Icons.receipt_long_outlined),
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

  void _selectKey(String key) {
    widget.onItemSelected?.call(key);
    if (widget.onItemSelected == null) {
      context.read<NavigationProvider>().select(key);
    }
    if (kConfiguratorNavigationKeys.contains(key) && !_isConfiguratorExpanded) {
      setState(() {
        _isConfiguratorExpanded = true;
      });
    }
  }

  void _requestFocus(String key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _focusNodeFor(key).requestFocus();
    });
  }

  void _moveSidebarFocus({
    required List<String> visibleKeys,
    required String selectedKey,
    required bool reverse,
  }) {
    if (visibleKeys.isEmpty) {
      return;
    }

    final currentIndex = visibleKeys.indexWhere(_isKeyFocused);
    final fallbackKey = visibleKeys.contains(selectedKey)
        ? selectedKey
        : visibleKeys.first;

    if (currentIndex == -1) {
      _requestFocus(fallbackKey);
      return;
    }

    final delta = reverse ? -1 : 1;
    final nextIndex =
        (currentIndex + delta + visibleKeys.length) % visibleKeys.length;
    _requestFocus(visibleKeys[nextIndex]);
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

    _selectKey(nextKey);
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
    if (!_focusScopeNode.hasFocus) {
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

    _moveSidebarFocus(
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
    final isConfiguratorSelected =
        selectedKey == 'configurator' ||
        const {
          'configurator_clients',
          'configurator_vendors',
          'configurator_items',
          'configurator_groups',
          'configurator_units',
        }.contains(selectedKey);
    final isConfiguratorExpanded =
        _isConfiguratorExpanded ||
        kConfiguratorNavigationKeys.contains(selectedKey);

    return Container(
      color: const Color(0xFF13161F),
      child: FocusScope(
        node: _focusScopeNode,
        child: Focus(
          onKeyEvent: (node, event) => _handleSidebarKeyEvent(
            event: event,
            selectedKey: selectedKey,
            isConfiguratorExpanded: isConfiguratorExpanded,
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 18),
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(0xFF6C63FF),
                      child: Icon(
                        Icons.factory_outlined,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    if (!widget.compact) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Paper ERP',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _SidebarSection(
                title: 'Modules',
                compact: widget.compact,
                children: _moduleItems,
                selectedKey: selectedKey,
                onSelected: _selectKey,
                focusNodeForKey: _focusNodeFor,
              ),
              const SizedBox(height: 18),
              _SidebarSection(
                title: 'Configurator',
                compact: widget.compact,
                children: _configuratorItems,
                selectedKey: selectedKey,
                isExpandable: true,
                isExpanded: isConfiguratorExpanded,
                isParentSelected: isConfiguratorSelected,
                onExpansionToggle: () {
                  setState(() {
                    _isConfiguratorExpanded = !_isConfiguratorExpanded;
                  });
                },
                onHeaderTap: () {
                  _selectKey('configurator');
                  _requestFocus('configurator');
                },
                onSelected: _selectKey,
                focusNodeForKey: _focusNodeFor,
              ),
              if (canManageUsers) ...[
                const SizedBox(height: 18),
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
    this.onHeaderTap,
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
  final VoidCallback? onHeaderTap;
  final FocusNode Function(String key) focusNodeForKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact && !isExpandable)
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF9CA3AF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (isExpandable)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _SidebarExpandableHeader(
              title: title,
              compact: compact,
              isExpanded: isExpanded,
              isSelected: isParentSelected,
              focusNode: focusNodeForKey('configurator'),
              onTap: onHeaderTap ?? onExpansionToggle ?? () {},
              onChevronTap: onExpansionToggle ?? () {},
            ),
          ),
        if (!isExpandable || isExpanded)
          ...children.map(
            (item) => Padding(
              padding: EdgeInsets.only(
                bottom: 6,
                left: isExpandable && !compact ? 16 : 0,
              ),
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
        final hasFocus = focusNode.hasFocus;
        final foreground = isSelected || hasFocus
            ? Colors.white
            : const Color(0xFFE5E7EB);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey<String>('sidebar_tile_configurator'),
            focusNode: focusNode,
            canRequestFocus: true,
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              focusNode.requestFocus();
              onTap();
            },
            child: Container(
              height: 44,
              padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF6C63FF)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected || hasFocus
                      ? const Color(0xFF6C63FF)
                      : const Color(0xFF20242F),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.tune_outlined, color: foreground, size: 18),
                  if (!compact) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onChevronTap,
                      splashRadius: 18,
                      icon: Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: foreground,
                        size: 18,
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
  });

  final _SidebarItemData item;
  final bool isSelected;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, child) {
        final hasFocus = focusNode.hasFocus;
        final foreground = isSelected || hasFocus
            ? Colors.white
            : const Color(0xFFE5E7EB);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey<String>('sidebar_tile_${item.key}'),
            focusNode: focusNode,
            canRequestFocus: true,
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              focusNode.requestFocus();
              onTap();
            },
            child: Container(
              height: 44,
              padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF6C63FF)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected || hasFocus
                      ? const Color(0xFF6C63FF)
                      : const Color(0xFF20242F),
                ),
              ),
              child: Row(
                children: [
                  Icon(item.icon, color: foreground, size: 18),
                  if (!compact) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.label,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w600,
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
