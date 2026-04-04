import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/app_button.dart';
import '../../features/clients/presentation/providers/clients_provider.dart';
import '../../features/groups/presentation/providers/groups_provider.dart';
import '../../features/inventory/presentation/screens/inventory_screen.dart';
import '../../features/items/presentation/providers/items_provider.dart';
import '../../features/orders/presentation/providers/orders_provider.dart';
import '../../features/orders/presentation/screens/orders_screen.dart';
import '../../features/units/presentation/providers/units_provider.dart';
import 'navigation_provider.dart';

enum ShellTopStripSearchLayoutMode { centered, leading, expanded }

enum ShellTopStripActionStyle { button, chip, toggle }

class ShellTopStripSearchConfig {
  const ShellTopStripSearchConfig({
    required this.placeholder,
    required this.initialValue,
    required this.onChanged,
    this.layoutMode = ShellTopStripSearchLayoutMode.centered,
    this.maxWidth = 420,
  });

  final String placeholder;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final ShellTopStripSearchLayoutMode layoutMode;
  final double maxWidth;
}

class ShellTopStripAction {
  const ShellTopStripAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = ShellTopStripActionStyle.button,
    this.isSelected = false,
    this.isPrimary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ShellTopStripActionStyle style;
  final bool isSelected;
  final bool isPrimary;
}

class ShellTopStripConfig {
  const ShellTopStripConfig({
    this.title,
    this.leadingBuilder,
    this.search,
    this.actions = const <ShellTopStripAction>[],
  });

  final String? title;
  final WidgetBuilder? leadingBuilder;
  final ShellTopStripSearchConfig? search;
  final List<ShellTopStripAction> actions;
}

ShellTopStripConfig resolveTopStrip(String selectedKey, BuildContext context) {
  switch (selectedKey) {
    case 'orders':
      final provider = context.watch<OrdersProvider>();
      return ShellTopStripConfig(
        search: ShellTopStripSearchConfig(
          placeholder: 'Search orders, clients, PO, items, or status',
          initialValue: provider.searchQuery,
          onChanged: provider.setSearchQuery,
        ),
        actions: [
          ShellTopStripAction(
            label: 'New Order',
            icon: Icons.add,
            isPrimary: true,
            onPressed: () => OrdersScreen.openEditor(context),
          ),
        ],
      );
    case 'configurator_clients':
      final provider = context.watch<ClientsProvider>();
      return ShellTopStripConfig(
        search: ShellTopStripSearchConfig(
          placeholder: 'Search clients, alias, GST, or address',
          initialValue: provider.searchQuery,
          onChanged: provider.setSearchQuery,
        ),
      );
    case 'configurator_items':
      final provider = context.watch<ItemsProvider>();
      return ShellTopStripConfig(
        search: ShellTopStripSearchConfig(
          placeholder: 'Search items, properties, values, or leaf paths',
          initialValue: provider.searchQuery,
          onChanged: provider.setSearchQuery,
        ),
      );
    case 'configurator_groups':
      final provider = context.watch<GroupsProvider>();
      return ShellTopStripConfig(
        search: ShellTopStripSearchConfig(
          placeholder: 'Search groups or parent groups',
          initialValue: provider.searchQuery,
          onChanged: provider.setSearchQuery,
        ),
      );
    case 'configurator_units':
      final provider = context.watch<UnitsProvider>();
      return ShellTopStripConfig(
        search: ShellTopStripSearchConfig(
          placeholder: 'Search units or symbols',
          initialValue: provider.searchQuery,
          onChanged: provider.setSearchQuery,
        ),
      );
    case 'inventory':
      return ShellTopStripConfig(
        title: 'Inventory',
        actions: [
          ShellTopStripAction(
            label: 'Open Scan',
            icon: Icons.qr_code_scanner_outlined,
            onPressed: () {
              context.read<NavigationProvider>().select('inventory_scan');
            },
          ),
          ShellTopStripAction(
            label: 'Add New Big Sheet',
            icon: Icons.add,
            isPrimary: true,
            onPressed: () => InventoryScreen.openAddMaterialForm(context),
          ),
        ],
      );
    case 'inventory_scan':
      return const ShellTopStripConfig(title: 'Material Scan');
    case 'production_pipelines':
      return const ShellTopStripConfig(title: 'Production Pipelines');
    case 'configurator':
      return const ShellTopStripConfig(title: 'Configurator');
    case 'configurator_vendors':
      return const ShellTopStripConfig(title: 'Vendors');
    default:
      return const ShellTopStripConfig(title: 'Dashboard');
  }
}

class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final selectedKey = context.select<NavigationProvider, String>(
      (navigation) => navigation.selectedKey,
    );
    final config = resolveTopStrip(selectedKey, context);
    final hasLeading = config.leadingBuilder != null || config.title != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF4F6FA),
        border: Border(bottom: BorderSide(color: Color(0xFFE7E7EF))),
      ),
      child: Row(
        children: [
          if (hasLeading) Expanded(child: _TopStripLeading(config: config)),
          if (!hasLeading && config.search == null && config.actions.isNotEmpty)
            const Spacer(),
          if (config.search != null) ...[
            const SizedBox(width: 16),
            _TopStripSearchSlot(search: config.search!),
          ],
          if (config.actions.isNotEmpty) ...[
            const SizedBox(width: 16),
            _TopStripActions(actions: config.actions),
          ],
        ],
      ),
    );
  }
}

class _TopStripLeading extends StatelessWidget {
  const _TopStripLeading({required this.config});

  final ShellTopStripConfig config;

  @override
  Widget build(BuildContext context) {
    if (config.leadingBuilder != null) {
      return config.leadingBuilder!(context);
    }
    if (config.title == null) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        config.title!,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1F2937),
        ),
      ),
    );
  }
}

class _TopStripSearchSlot extends StatelessWidget {
  const _TopStripSearchSlot({required this.search});

  final ShellTopStripSearchConfig search;

  @override
  Widget build(BuildContext context) {
    final searchField = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: search.maxWidth),
      child: _ShellTopStripSearchField(search: search),
    );

    return switch (search.layoutMode) {
      ShellTopStripSearchLayoutMode.leading => searchField,
      ShellTopStripSearchLayoutMode.expanded => Expanded(child: searchField),
      ShellTopStripSearchLayoutMode.centered => Expanded(
        child: Align(alignment: Alignment.center, child: searchField),
      ),
    };
  }
}

class _ShellTopStripSearchField extends StatefulWidget {
  const _ShellTopStripSearchField({required this.search});

  final ShellTopStripSearchConfig search;

  @override
  State<_ShellTopStripSearchField> createState() =>
      _ShellTopStripSearchFieldState();
}

class _ShellTopStripSearchFieldState extends State<_ShellTopStripSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.search.initialValue);
  }

  @override
  void didUpdateWidget(covariant _ShellTopStripSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.search.initialValue) {
      _controller.value = TextEditingValue(
        text: widget.search.initialValue,
        selection: TextSelection.collapsed(
          offset: widget.search.initialValue.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey<String>('shell_top_strip_search_field'),
      controller: _controller,
      onChanged: widget.search.onChanged,
      decoration: InputDecoration(
        hintText: widget.search.placeholder,
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD7E6FB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD7E6FB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF8AB5F8)),
        ),
      ),
    );
  }
}

class _TopStripActions extends StatelessWidget {
  const _TopStripActions({required this.actions});

  final List<ShellTopStripAction> actions;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actions.map(_buildAction).toList(growable: false),
    );
  }

  Widget _buildAction(ShellTopStripAction action) {
    return switch (action.style) {
      ShellTopStripActionStyle.button => AppButton(
        label: action.label,
        icon: action.icon,
        onPressed: action.onPressed,
        variant: action.isPrimary
            ? AppButtonVariant.primary
            : AppButtonVariant.secondary,
      ),
      ShellTopStripActionStyle.chip => _TopStripChipAction(action: action),
      ShellTopStripActionStyle.toggle => _TopStripChipAction(
        action: action,
        isToggle: true,
      ),
    };
  }
}

class _TopStripChipAction extends StatelessWidget {
  const _TopStripChipAction({required this.action, this.isToggle = false});

  final ShellTopStripAction action;
  final bool isToggle;

  @override
  Widget build(BuildContext context) {
    final isSelected = action.isSelected;
    return InkWell(
      onTap: action.onPressed,
      borderRadius: BorderRadius.circular(isToggle ? 14 : 18),
      child: Container(
        height: isToggle ? 28 : 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE9F7EA) : Colors.white,
          borderRadius: BorderRadius.circular(isToggle ? 14 : 18),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF9DD8A4)
                : const Color(0xFFD8DCE8),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (action.icon != null) ...[
              Icon(action.icon, size: 16, color: const Color(0xFF394150)),
              const SizedBox(width: 8),
            ],
            Text(
              action.label,
              style: const TextStyle(
                color: Color(0xFF394150),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
