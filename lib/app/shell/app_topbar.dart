import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/soft_erp_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/soft_primitives.dart';
import '../../features/auth/domain/auth_user.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/clients/presentation/providers/clients_provider.dart';
import '../../features/groups/presentation/providers/groups_provider.dart';
import '../../features/inventory/presentation/providers/inventory_provider.dart';
import '../../features/items/presentation/providers/items_provider.dart';
import '../../features/orders/presentation/providers/orders_provider.dart';
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
      final provider = context.watch<InventoryProvider>();
      return ShellTopStripConfig(
        search: ShellTopStripSearchConfig(
          placeholder: 'Search groups, items, barcode, supplier, or notes',
          initialValue: provider.searchQuery,
          onChanged: provider.setSearchQuery,
        ),
        actions: [
          ShellTopStripAction(
            label: 'Open Scan',
            icon: Icons.qr_code_scanner_outlined,
            onPressed: () {
              context.read<NavigationProvider>().select('inventory_scan');
            },
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
    case 'user_management':
      return ShellTopStripConfig(
        title: 'User Management',
        actions: [
          ShellTopStripAction(
            label: 'Sign out',
            icon: Icons.logout,
            onPressed: () => context.read<AuthProvider>().logoutRemote(),
          ),
        ],
      );
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
    final currentUser = context.select<AuthProvider, AuthUser?>(
      (auth) => auth.user,
    );
    final searchConfig = config.search == null
        ? const ShellTopStripSearchConfig(
            placeholder: 'Search',
            initialValue: '',
            onChanged: _noopSearch,
          )
        : ShellTopStripSearchConfig(
            placeholder: 'Search',
            initialValue: config.search!.initialValue,
            onChanged: config.search!.onChanged,
            layoutMode: ShellTopStripSearchLayoutMode.centered,
            maxWidth: config.search!.maxWidth,
          );

    return Container(
      height: 78,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final compact = width < 1240;
          final brandWidth = compact ? 250.0 : 300.0;
          final profileWidth = compact ? 66.0 : 206.0;
          final searchMaxWidth = compact ? 500.0 : 715.0;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: brandWidth, child: const _TopStripCompanyBrand()),
              const SizedBox(width: 18),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: searchMaxWidth),
                    child: _ShellTopStripSearchField(search: searchConfig),
                  ),
                ),
              ),
              if (config.actions.isNotEmpty) ...[
                const SizedBox(width: 10),
                _TopStripActions(actions: config.actions),
              ],
              const SizedBox(width: 14),
              SizedBox(
                width: profileWidth,
                child: _TopStripProfileCard(user: currentUser),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TopStripCompanyBrand extends StatelessWidget {
  const _TopStripCompanyBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
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
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Shree Ganesh Metal Works',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: SoftErpTheme.textPrimary,
              fontWeight: FontWeight.w500,
              fontSize: 16,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}

void _noopSearch(String _) {}

class _ShellTopStripSearchField extends StatefulWidget {
  const _ShellTopStripSearchField({required this.search});

  final ShellTopStripSearchConfig search;

  @override
  State<_ShellTopStripSearchField> createState() =>
      _ShellTopStripSearchFieldState();
}

class _ShellTopStripSearchFieldState extends State<_ShellTopStripSearchField> {
  late final TextEditingController _controller;
  FocusNode? _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.search.initialValue);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextFocusNode = context
        .read<NavigationProvider>()
        .topStripSearchFocusNode;
    if (_focusNode == nextFocusNode) {
      return;
    }
    _focusNode?.removeListener(_handleFocusChanged);
    _focusNode = nextFocusNode;
    _focusNode?.addListener(_handleFocusChanged);
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
    _focusNode?.removeListener(_handleFocusChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (_focusNode?.hasFocus ?? false) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey<String>('shell_top_strip_search_field'),
      focusNode: _focusNode,
      controller: _controller,
      onChanged: widget.search.onChanged,
      decoration: InputDecoration(
        hintText: widget.search.placeholder,
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 18,
          color: SoftErpTheme.textSecondary,
        ),
        filled: true,
        fillColor: const Color(0xCCFFFFFF),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: const BorderSide(color: SoftErpTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: const BorderSide(color: SoftErpTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: const BorderSide(color: SoftErpTheme.accent),
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
    return SoftPill(
      label: action.label,
      onTap: action.onPressed,
      background: isSelected
          ? const Color(0xFFEAF8EE)
          : SoftErpTheme.cardSurface,
      borderColor: isSelected ? const Color(0xFF9DD8A4) : SoftErpTheme.border,
      foreground: SoftErpTheme.textPrimary,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: isToggle ? 6 : 8),
      leading: action.icon == null
          ? null
          : Icon(action.icon, size: 16, color: SoftErpTheme.textSecondary),
    );
  }
}

class _TopStripProfileCard extends StatelessWidget {
  const _TopStripProfileCard({required this.user});

  final AuthUser? user;

  @override
  Widget build(BuildContext context) {
    final name = user?.name.trim().isNotEmpty == true
        ? user!.name.trim()
        : 'Your Name';
    final role = user == null ? 'Senior Manager' : _roleLabel(user!.role);
    final initials = name
        .split(RegExp(r'\s+'))
        .where((segment) => segment.isNotEmpty)
        .take(2)
        .map((segment) => segment[0].toUpperCase())
        .join();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 190;
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: compact ? 5 : 6,
            ),
            decoration: BoxDecoration(
              color: const Color(0x6EFFFFFF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x40FFFFFF)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: compact ? 14 : 16,
                  backgroundColor: const Color(0xFFD9DCEC),
                  child: Text(
                    initials.isEmpty ? 'U' : initials,
                    style: TextStyle(
                      color: SoftErpTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 11 : 12,
                    ),
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: SoftErpTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          role,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: SoftErpTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _roleLabel(String role) {
    if (role.trim().isEmpty) {
      return 'Senior Manager';
    }
    final normalized = role.trim().toLowerCase();
    if (normalized == 'super_admin' || normalized == 'admin') {
      return 'Senior Manager';
    }
    return role
        .split('_')
        .where((segment) => segment.isNotEmpty)
        .map(
          (segment) =>
              '${segment[0].toUpperCase()}${segment.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}
