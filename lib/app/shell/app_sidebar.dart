import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'navigation_provider.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key, this.compact = false, this.onItemSelected});

  final bool compact;
  final ValueChanged<String>? onItemSelected;

  @override
  Widget build(BuildContext context) {
    final isAndroid = !kIsWeb && Platform.isAndroid;
    final selectedKey = context.select<NavigationProvider, String>(
      (navigation) => navigation.selectedKey,
    );

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
                if (!compact) ...[
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
            compact: compact,
            children: [
              _SidebarItemData(
                'dashboard',
                'Dashboard',
                Icons.dashboard_outlined,
              ),
              _SidebarItemData(
                'inventory',
                'Inventory',
                Icons.inventory_2_outlined,
              ),
              _SidebarItemData(
                'inventory_scan',
                isAndroid ? 'Inventory Scan' : 'Inventory Scan (Android only)',
                Icons.qr_code_scanner_outlined,
              ),
              _SidebarItemData(
                'production_pipelines',
                'Production Pipelines',
                Icons.account_tree_outlined,
              ),
            ],
            selectedKey: selectedKey,
            onSelected: (key) {
              onItemSelected?.call(key);
              if (onItemSelected == null) {
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
  });

  final String title;
  final List<_SidebarItemData> children;
  final String selectedKey;
  final ValueChanged<String> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact)
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
        ...children.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
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
