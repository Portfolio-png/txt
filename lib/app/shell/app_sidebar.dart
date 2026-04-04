import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

  @override
  Widget build(BuildContext context) {
    final selectedKey = context.select<NavigationProvider, String>(
      (navigation) => navigation.selectedKey,
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

    return Container(
      color: const Color(0xFF13161F),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 18),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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
            children: [
              _SidebarItemData(
                'dashboard',
                'Dashboard',
                Icons.dashboard_outlined,
              ),
              _SidebarItemData('orders', 'Orders', Icons.receipt_long_outlined),
              _SidebarItemData(
                'inventory',
                'Inventory',
                Icons.inventory_2_outlined,
              ),
              _SidebarItemData(
                'production_pipelines',
                'Production',
                Icons.account_tree_outlined,
              ),
            ],
            selectedKey: selectedKey,
            onSelected: (key) {
              widget.onItemSelected?.call(key);
              if (widget.onItemSelected == null) {
                context.read<NavigationProvider>().select(key);
              }
            },
          ),
          const SizedBox(height: 18),
          _SidebarSection(
            title: 'Configurator',
            compact: widget.compact,
            children: [
              _SidebarItemData(
                'configurator_clients',
                'Clients',
                Icons.groups_outlined,
              ),
              _SidebarItemData(
                'configurator_vendors',
                'Vendors',
                Icons.storefront_outlined,
              ),
              _SidebarItemData(
                'configurator_items',
                'Items',
                Icons.inventory_outlined,
              ),
              _SidebarItemData(
                'configurator_groups',
                'Groups',
                Icons.grid_view_outlined,
              ),
              _SidebarItemData(
                'configurator_units',
                'Units',
                Icons.straighten_outlined,
              ),
            ],
            selectedKey: selectedKey,
            isExpandable: true,
            isExpanded: _isConfiguratorExpanded,
            isParentSelected: isConfiguratorSelected,
            onExpansionToggle: () {
              setState(() {
                _isConfiguratorExpanded = !_isConfiguratorExpanded;
              });
            },
            onHeaderTap: () {
              widget.onItemSelected?.call('configurator');
              if (widget.onItemSelected == null) {
                context.read<NavigationProvider>().select('configurator');
              }
              setState(() {
                _isConfiguratorExpanded = true;
              });
            },
            onSelected: (key) {
              widget.onItemSelected?.call(key);
              if (widget.onItemSelected == null) {
                context.read<NavigationProvider>().select(key);
              }
            },
          ),
        ],
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
    required this.onTap,
    required this.onChevronTap,
  });

  final String title;
  final bool compact;
  final bool isExpanded;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onChevronTap;

  @override
  Widget build(BuildContext context) {
    final foreground = isSelected ? Colors.white : const Color(0xFFE5E7EB);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF6C63FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
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
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.compact,
  });

  final _SidebarItemData item;
  final bool isSelected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final foreground = isSelected ? Colors.white : const Color(0xFFE5E7EB);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF6C63FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
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
  }
}

class _SidebarItemData {
  const _SidebarItemData(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}
