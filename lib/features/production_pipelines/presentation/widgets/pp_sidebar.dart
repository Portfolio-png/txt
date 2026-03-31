import 'package:flutter/material.dart';

class PPSidebar extends StatelessWidget {
  const PPSidebar({
    super.key,
    required this.selectedKey,
    required this.onTap,
    required this.compact,
  });

  final String selectedKey;
  final ValueChanged<String> onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sectionStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: const Color(0xFFC3C3C3),
      fontSize: 14,
    );

    return Container(
      color: const Color(0xFF13161F),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 16, 10, 16),
        children: [
          _CompanyTile(compact: compact),
          const SizedBox(height: 20),
          Text('Options', style: sectionStyle),
          const SizedBox(height: 8),
          ..._options.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: _SidebarNavItem(
                compact: compact,
                item: item,
                isActive: selectedKey == item.key,
                onTap: () => onTap(item.key),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Configurators', style: sectionStyle),
          const SizedBox(height: 8),
          ..._configurators.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: _SidebarNavItem(
                compact: compact,
                item: item,
                isActive: selectedKey == item.key,
                onTap: () => onTap(item.key),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanyTile extends StatelessWidget {
  const _CompanyTile({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 63,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 12,
            backgroundColor: Color(0xFF9D9BE9),
            child: Icon(Icons.person, size: 15, color: Colors.black),
          ),
          if (!compact) ...[
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Shree Ganesh\nMetal Works',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFFE6E6E6),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 1.1,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFFB4B4B4)),
          ],
        ],
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.item,
    required this.isActive,
    required this.onTap,
    required this.compact,
  });

  final _SidebarItem item;
  final bool isActive;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bgColor = isActive
        ? const Color(0xFF6049E3)
        : const Color(0xFF13161F);
    final fgColor = isActive ? Colors.white : const Color(0xFFE3E3E3);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Container(
          height: 39,
          padding: EdgeInsets.fromLTRB(compact ? 8 : 12, 10, 16, 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: [
              Icon(item.icon, size: 19, color: fgColor),
              if (!compact) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fgColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
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

class _SidebarItem {
  const _SidebarItem(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}

const List<_SidebarItem> _options = [
  _SidebarItem('dashboard', 'Dashboard', Icons.dashboard_outlined),
  _SidebarItem('invoices', 'Invoices', Icons.receipt_long_outlined),
  _SidebarItem('inventory', 'Inventory', Icons.inventory_2_outlined),
  _SidebarItem('reports', 'Reports', Icons.bar_chart_outlined),
  _SidebarItem('gst', 'Gst', Icons.assignment_outlined),
  _SidebarItem('books', 'Books', Icons.menu_book_outlined),
];

const List<_SidebarItem> _configurators = [
  _SidebarItem('config_gst', 'Gst', Icons.settings_outlined),
  _SidebarItem(
    'production_pipelines',
    'Production Pipelines',
    Icons.apps_outlined,
  ),
  _SidebarItem('config_books', 'Books', Icons.book_outlined),
];
