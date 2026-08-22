import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../groups/domain/group_definition.dart';
import '../../../groups/presentation/providers/groups_provider.dart';
import '../../../items/domain/item_definition.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../domain/auth_user.dart';
import '../providers/auth_provider.dart';

const Map<String, String> _opLabels = {
  'create': 'Create',
  'read': 'View',
  'update': 'Update',
  'delete': 'Delete',
};

// Legacy / reserved keys never shown in the editor.
const Set<String> _hiddenKeys = {'config.read'};

// Map un-categorized capability keys to their logical parent modules.
const Map<String, String> _capabilityToModule = {
  'orders.approve': 'orders',
  'inventory.reconcile': 'inventory',
  'inventory.request_delete': 'inventory',
  'delete_requests.review': 'action_center',
  'users.read': 'people',
  'users.create_user': 'people',
  'users.create_admin': 'people',
  'users.update_status': 'people',
  'users.reset_password': 'people',
  'users.manage_permissions': 'people',
  'sessions.manage': 'people',
  'audit.read': 'people',
};

const Map<String, IconData> _moduleIcons = {
  'orders': Icons.shopping_bag_outlined,
  'inventory': Icons.inventory_2_outlined,
  'challans': Icons.local_shipping_outlined,
  'production': Icons.precision_manufacturing_outlined,
  'jobs': Icons.assignment_outlined,
  'action_center': Icons.notifications_active_outlined,
  'people': Icons.people_alt_outlined,
  'clients': Icons.business_outlined,
  'vendors': Icons.storefront_outlined,
  'items': Icons.category_outlined,
  'units': Icons.square_foot_outlined,
  'machines': Icons.build_outlined,
  'dies': Icons.grid_view_outlined,
  'pipelines': Icons.account_tree_outlined,
};

/// Group definitions for super-clubbing related modules into unified Domain Suites.
class _DomainSuite {
  const _DomainSuite({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.modules,
    required this.accentColor,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> modules;
  final Color accentColor;
}

const List<_DomainSuite> _domainSuites = [
  _DomainSuite(
    id: 'logistics',
    title: 'Fulfillment, Orders & Logistics',
    subtitle: 'Challans, customer orders, action center & reconciliations',
    icon: Icons.local_shipping_outlined,
    modules: ['challans', 'orders', 'action_center'],
    accentColor: Color(0xFF2563EB), // Blue
  ),
  _DomainSuite(
    id: 'inventory',
    title: 'Inventory & Catalog Masters',
    subtitle: 'Stock positions, items, variation dimensions & unit conversions',
    icon: Icons.inventory_2_outlined,
    modules: ['inventory', 'items', 'units'],
    accentColor: Color(0xFF059669), // Emerald Green
  ),
  _DomainSuite(
    id: 'manufacturing',
    title: 'Shop Floor & Manufacturing',
    subtitle: 'Production runs, work order jobs, machinery, dies & pipelines',
    icon: Icons.precision_manufacturing_outlined,
    modules: ['production', 'jobs', 'machines', 'dies', 'pipelines'],
    accentColor: Color(0xFFD97706), // Amber
  ),
  _DomainSuite(
    id: 'people_security',
    title: 'People, Accounts & Security',
    subtitle:
        'Employee directory, clients, vendors, password resets & permissions',
    icon: Icons.people_alt_outlined,
    modules: ['people', 'clients', 'vendors'],
    accentColor: Color(0xFF7C3AED), // Purple
  ),
];

/// An expandable horizontal card-based permission tree:
/// Super-clubs modules into Domain Suites, provides live security risk analysis,
/// instant search filtering, and displays hierarchical graph trees from View -> Actions -> Capabilities.
class PermissionTree extends StatefulWidget {
  const PermissionTree({
    super.key,
    required this.descriptors,
    required this.toggles,
    this.grants,
    required this.onChanged,
  });

  final List<PermissionDescriptor> descriptors;
  final Map<String, bool> toggles; // mutated in place
  final Map<String, RecordGrant>? grants;
  final VoidCallback onChanged;

  @override
  State<PermissionTree> createState() => _PermissionTreeState();
}

class _PermissionTreeState extends State<PermissionTree> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  final Set<String> _collapsedSuites = {};

  Map<String, bool> get _t => widget.toggles;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _isActorAuthorized(String key, AuthProvider auth) {
    if (auth.user?.isSuperAdmin == true) return true;
    return auth.can(key);
  }

  void _setOne(
    String key,
    bool value,
    AuthProvider auth, {
    String? moduleKey,
    String? op,
  }) {
    if (!_isActorAuthorized(key, auth)) return;

    setState(() {
      _t[key] = value;

      // Smart Hierarchical Dependency Logic:
      // 1. If any derived action/capability is turned ON, 'read' (View) must also be turned ON.
      if (value && moduleKey != null && op != 'read') {
        final readKey = '$moduleKey.read';
        if (_t.containsKey(readKey) || key.startsWith('$moduleKey.')) {
          _t[readKey] = true;
        }
      }

      // 2. If 'read' (View) is turned OFF, all child keys under that module are turned OFF.
      if (!value && moduleKey != null && op == 'read') {
        for (final k in _t.keys.toList()) {
          if (k.startsWith('$moduleKey.') ||
              _capabilityToModule[k] == moduleKey) {
            _t[k] = false;
          }
        }
      }
    });

    widget.onChanged();
  }

  void _quickSetSuite(List<String> allKeys, String mode, AuthProvider auth) {
    setState(() {
      for (final k in allKeys) {
        if (!_isActorAuthorized(k, auth)) continue;
        if (mode == 'full') {
          _t[k] = true;
        } else if (mode == 'view_only') {
          _t[k] = k.endsWith('.read');
        } else if (mode == 'clear') {
          _t[k] = false;
        }
      }
    });
    widget.onChanged();
  }

  /// Calculates real-time security risk profile based on current active toggles.
  ({String label, Color color, IconData icon, String explanation})
  _calculateRiskProfile() {
    final activeCount = _t.values.where((v) => v).length;
    if (activeCount == 0) {
      return (
        label: 'No Access',
        color: Colors.grey.shade600,
        icon: Icons.block_outlined,
        explanation: 'Account has zero permissions assigned.',
      );
    }

    final hasHighRiskPrivileges =
        _t['users.manage_permissions'] == true ||
        _t['users.reset_password'] == true ||
        _t['delete_requests.review'] == true ||
        _t['users.update_status'] == true;

    if (hasHighRiskPrivileges) {
      return (
        label: 'High Administrative Risk',
        color: const Color(0xFFDC2626), // Red
        icon: Icons.gavel_outlined,
        explanation:
            'Includes account security, password resets, or system governance access.',
      );
    }

    final hasDelete = _t.keys.any(
      (k) => k.endsWith('.delete') && _t[k] == true,
    );
    final hasUpdateOrCreate = _t.keys.any(
      (k) => (k.endsWith('.update') || k.endsWith('.create')) && _t[k] == true,
    );

    if (hasDelete || hasUpdateOrCreate) {
      return (
        label: 'Full Operational Rights',
        color: const Color(0xFFD97706), // Amber
        icon: Icons.edit_note_outlined,
        explanation: 'Can modify or delete ERP operational records.',
      );
    }

    return (
      label: 'Guarded / View-Only',
      color: const Color(0xFF059669), // Green
      icon: Icons.shield_outlined,
      explanation: 'Read-only inspection access without data mutation rights.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final byModuleCoarse = <String, Map<String, PermissionDescriptor>>{};
    final byModuleFine = <String, List<PermissionDescriptor>>{};
    final byModuleCaps = <String, List<PermissionDescriptor>>{};
    final labels = <String, String>{};

    for (final d in widget.descriptors) {
      if (d.module == null || _hiddenKeys.contains(d.key)) continue;

      final module = d.module!;
      labels[module] = d.moduleLabel ?? module;

      if (d.isModule && d.op != null) {
        byModuleCoarse.putIfAbsent(module, () => {})[d.op!] = d;
      } else if (d.category == 'fine') {
        final keyEnding = d.key.split('.').last;
        if (['create', 'read', 'update', 'delete'].contains(keyEnding) ||
            d.op != null) {
          final op = d.op ?? keyEnding;
          byModuleCoarse.putIfAbsent(module, () => {}).putIfAbsent(op, () => d);
        } else {
          byModuleFine.putIfAbsent(module, () => []).add(d);
        }
      } else if (d.category == 'capability') {
        final targetModule = _capabilityToModule[d.key] ?? module;
        byModuleCaps.putIfAbsent(targetModule, () => []).add(d);
      }
    }

    final risk = _calculateRiskProfile();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Live Security Risk & Quick Search Header Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SoftErpTheme.shellSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(risk.icon, size: 20, color: risk.color),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Access Risk Profile: ',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: SoftErpTheme.textSecondary,
                            ),
                          ),
                          Text(
                            risk.label,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: risk.color,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        risk.explanation,
                        style: const TextStyle(
                          fontSize: 11,
                          color: SoftErpTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Search Permission Field
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Search permissions…',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        prefixIcon: const Icon(Icons.search, size: 16),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 14),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Colors.black.withValues(alpha: 0.15),
                          ),
                        ),
                      ),
                      onChanged: (q) =>
                          setState(() => _searchQuery = q.trim().toLowerCase()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Domain Suite Cards (Super-Clubbed Groups)
        for (final suite in _domainSuites)
          _buildDomainSuiteCard(
            suite,
            byModuleCoarse,
            byModuleFine,
            byModuleCaps,
            labels,
            auth,
          ),
      ],
    );
  }

  Widget _buildDomainSuiteCard(
    _DomainSuite suite,
    Map<String, Map<String, PermissionDescriptor>> byModuleCoarse,
    Map<String, List<PermissionDescriptor>> byModuleFine,
    Map<String, List<PermissionDescriptor>> byModuleCaps,
    Map<String, String> labels,
    AuthProvider auth,
  ) {
    // Collect all keys in this domain suite
    final suiteKeys = <String>[];
    final activeModulesInSuite = suite.modules
        .where((m) => byModuleCoarse.containsKey(m))
        .toList();

    for (final m in activeModulesInSuite) {
      suiteKeys.addAll((byModuleCoarse[m] ?? {}).values.map((d) => d.key));
      suiteKeys.addAll((byModuleFine[m] ?? []).map((d) => d.key));
      suiteKeys.addAll((byModuleCaps[m] ?? []).map((d) => d.key));
    }

    // Check search filter match
    if (_searchQuery.isNotEmpty) {
      final matchesSearch =
          suiteKeys.any((k) => k.toLowerCase().contains(_searchQuery)) ||
          suite.title.toLowerCase().contains(_searchQuery) ||
          activeModulesInSuite.any(
            (m) => (labels[m] ?? m).toLowerCase().contains(_searchQuery),
          );
      if (!matchesSearch) return const SizedBox.shrink();
    }

    final activeCount = suiteKeys.where((k) => _t[k] == true).length;
    final totalCount = suiteKeys.length;
    final isCollapsed = _collapsedSuites.contains(suite.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: activeCount > 0
              ? suite.accentColor.withValues(alpha: 0.4)
              : Colors.black.withValues(alpha: 0.08),
          width: activeCount > 0 ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Suite Super-Card Header
          InkWell(
            onTap: () => setState(() {
              if (!_collapsedSuites.remove(suite.id))
                _collapsedSuites.add(suite.id);
            }),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: activeCount > 0
                    ? suite.accentColor.withValues(alpha: 0.05)
                    : SoftErpTheme.shellSurface,
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(11),
                  bottom: Radius.circular(isCollapsed ? 11 : 0),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: suite.accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(suite.icon, size: 20, color: suite.accentColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              suite.title,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: SoftErpTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: activeCount > 0
                                    ? suite.accentColor.withValues(alpha: 0.15)
                                    : Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$activeCount / $totalCount active',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: activeCount > 0
                                      ? suite.accentColor
                                      : SoftErpTheme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          suite.subtitle,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: SoftErpTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Suite Quick Actions
                  _quickButton(
                    'Full Suite',
                    () => _quickSetSuite(suiteKeys, 'full', auth),
                  ),
                  const SizedBox(width: 4),
                  _quickButton(
                    'View Only',
                    () => _quickSetSuite(suiteKeys, 'view_only', auth),
                  ),
                  const SizedBox(width: 4),
                  _quickButton(
                    'Clear',
                    () => _quickSetSuite(suiteKeys, 'clear', auth),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isCollapsed
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    color: SoftErpTheme.textSecondary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          if (!isCollapsed) ...[
            const Divider(height: 1, thickness: 1),
            // Nested Clubbed Modules CRUD Grid View
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _buildSuiteTableHeader(
                    activeModulesInSuite,
                    byModuleCoarse,
                    auth,
                  ),
                  for (final m in activeModulesInSuite)
                    _buildNestedModuleNode(
                      m,
                      labels[m] ?? m,
                      byModuleCoarse[m] ?? const {},
                      byModuleFine[m] ?? const [],
                      byModuleCaps[m] ?? const [],
                      suite.accentColor,
                      auth,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _toggleSuiteColumn(
    List<String> modules,
    Map<String, Map<String, PermissionDescriptor>> byModuleCoarse,
    String? targetOp,
    AuthProvider auth,
  ) {
    final targetKeys = <String>[];
    for (final m in modules) {
      final coarseMap = byModuleCoarse[m];
      if (coarseMap != null) {
        if (targetOp != null) {
          final d = coarseMap[targetOp];
          if (d != null) targetKeys.add(d.key);
        } else {
          targetKeys.addAll(coarseMap.values.map((d) => d.key));
        }
      }
    }

    if (targetKeys.isEmpty) return;

    final allOn = targetKeys.every((k) => _t[k] == true);
    setState(() {
      for (final k in targetKeys) {
        if (_isActorAuthorized(k, auth)) {
          _t[k] = !allOn;
        }
      }
    });
    widget.onChanged();
  }

  bool? _getModuleAllState(Map<String, PermissionDescriptor> coarseOps) {
    if (coarseOps.isEmpty) return false;
    final onCount = coarseOps.values.where((d) => _t[d.key] == true).length;
    if (onCount == coarseOps.length) return true;
    if (onCount > 0) return null;
    return false;
  }

  void _toggleModuleAll(
    Map<String, PermissionDescriptor> coarseOps,
    bool turnOn,
    AuthProvider auth,
  ) {
    setState(() {
      for (final d in coarseOps.values) {
        if (_isActorAuthorized(d.key, auth)) {
          _t[d.key] = turnOn;
        }
      }
    });
    widget.onChanged();
  }

  Widget _buildSuiteTableHeader(
    List<String> activeModulesInSuite,
    Map<String, Map<String, PermissionDescriptor>> byModuleCoarse,
    AuthProvider auth,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 140,
            child: Text(
              'Module Name',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Tooltip(
              message: 'Toggle all CRUD permissions across suite',
              child: InkWell(
                onTap: () => _toggleSuiteColumn(
                  activeModulesInSuite,
                  byModuleCoarse,
                  null,
                  auth,
                ),
                borderRadius: BorderRadius.circular(4),
                child: const Center(
                  child: Text(
                    'All',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: SoftErpTheme.accent,
                    ),
                  ),
                ),
              ),
            ),
          ),
          for (final op in ['create', 'read', 'update', 'delete'])
            SizedBox(
              width: 44,
              child: Tooltip(
                message: 'Toggle ${_opLabels[op]} column across suite',
                child: InkWell(
                  onTap: () => _toggleSuiteColumn(
                    activeModulesInSuite,
                    byModuleCoarse,
                    op,
                    auth,
                  ),
                  borderRadius: BorderRadius.circular(4),
                  child: Center(
                    child: Text(
                      _opLabels[op] ?? op,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: SoftErpTheme.accent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Capabilities & Overrides',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpColumnCheckbox(
    Map<String, PermissionDescriptor> coarseOps,
    String op,
    String moduleKey,
    Color themeColor,
    AuthProvider auth,
  ) {
    final d = coarseOps[op];
    if (d == null) {
      return const SizedBox(
        width: 44,
        child: Center(
          child: Text('-', style: TextStyle(color: Colors.grey, fontSize: 11)),
        ),
      );
    }

    final isOn = _t[d.key] == true;
    final canEdit = _isActorAuthorized(d.key, auth);

    return SizedBox(
      width: 44,
      child: Center(
        child: SizedBox(
          height: 18,
          width: 18,
          child: Checkbox(
            value: isOn,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            activeColor: themeColor,
            onChanged: canEdit
                ? (v) => _setOne(
                    d.key,
                    v == true,
                    auth,
                    moduleKey: moduleKey,
                    op: op,
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildNestedModuleNode(
    String moduleKey,
    String label,
    Map<String, PermissionDescriptor> coarseOps,
    List<PermissionDescriptor> fineKeys,
    List<PermissionDescriptor> caps,
    Color themeColor,
    AuthProvider auth,
  ) {
    final icon = _moduleIcons[moduleKey] ?? Icons.grid_view_outlined;
    final allState = _getModuleAllState(coarseOps);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: SoftErpTheme.shellSurface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 1. Module Icon & Name Column (Width 140)
              SizedBox(
                width: 140,
                child: Row(
                  children: [
                    Icon(icon, size: 15, color: themeColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: SoftErpTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // 2. All Checkbox (Width 38)
              SizedBox(
                width: 38,
                child: Center(
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: Checkbox(
                      tristate: true,
                      value: allState,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      activeColor: themeColor,
                      onChanged: (v) =>
                          _toggleModuleAll(coarseOps, v == true, auth),
                    ),
                  ),
                ),
              ),

              // 3. Create Checkbox (Width 44)
              _buildOpColumnCheckbox(
                coarseOps,
                'create',
                moduleKey,
                themeColor,
                auth,
              ),

              // 4. View Checkbox (Width 44)
              _buildOpColumnCheckbox(
                coarseOps,
                'read',
                moduleKey,
                themeColor,
                auth,
              ),

              // 5. Update Checkbox (Width 44)
              _buildOpColumnCheckbox(
                coarseOps,
                'update',
                moduleKey,
                themeColor,
                auth,
              ),

              // 6. Delete Checkbox (Width 44)
              _buildOpColumnCheckbox(
                coarseOps,
                'delete',
                moduleKey,
                themeColor,
                auth,
              ),

              const SizedBox(width: 12),

              // 7. Capabilities & Fine Overrides (Expanded)
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final f in fineKeys)
                      _buildCapabilityChip(
                        f,
                        moduleKey,
                        true,
                        themeColor,
                        auth,
                      ),
                    for (final c in caps)
                      _buildCapabilityChip(
                        c,
                        moduleKey,
                        true,
                        themeColor,
                        auth,
                      ),
                  ],
                ),
              ),
            ],
          ),

          // 8. Specific Record Level Permissions (Hierarchical Groups -> Items, Clients, Vendors, etc.)
          if (widget.grants != null &&
              _recordModules.containsKey(moduleKey)) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _ModuleRecordGrantsTree(
                moduleKey: moduleKey,
                grants: widget.grants!,
                onChanged: widget.onChanged,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _quickButton(String label, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: SoftErpTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildCapabilityChip(
    PermissionDescriptor d,
    String? moduleKey,
    bool isReadOn,
    Color themeColor,
    AuthProvider auth,
  ) {
    final isOn = _t[d.key] ?? false;
    final canEdit = _isActorAuthorized(d.key, auth);
    final isEnabled = isReadOn && canEdit;

    return Opacity(
      opacity: isReadOn ? 1.0 : 0.45,
      child: Tooltip(
        message: d.description.isNotEmpty ? d.description : d.label,
        child: InkWell(
          onTap: isEnabled
              ? () => _setOne(d.key, !isOn, auth, moduleKey: moduleKey)
              : null,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isOn && isReadOn
                  ? themeColor.withValues(alpha: 0.12)
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isOn && isReadOn ? themeColor : Colors.grey.shade300,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.star_outline,
                  size: 13,
                  color: isOn && isReadOn ? themeColor : Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Text(
                  d.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isOn && isReadOn
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: isOn && isReadOn
                        ? themeColor
                        : SoftErpTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  height: 18,
                  width: 18,
                  child: Checkbox(
                    value: isOn && isReadOn,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    activeColor: themeColor,
                    onChanged: isEnabled
                        ? (v) => _setOne(
                            d.key,
                            v == true,
                            auth,
                            moduleKey: moduleKey,
                          )
                        : null,
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: SoftErpTheme.textSecondary,
      ),
    );
  }
}

// Modules that support per-record grants (must match backend RECORD_OPTION_SOURCES).
const Map<String, String> _recordModules = {
  'orders': 'Orders',
  'inventory': 'Inventory',
  'challans': 'Delivery Challans',
  'items': 'Items',
  'clients': 'Clients',
  'vendors': 'Vendors',
  'units': 'Units',
  'machines': 'Machines',
  'dies': 'Dies',
  'pipelines': 'Pipelines',
  'people': 'People',
};
const List<String> _recordOps = ['read', 'update', 'delete'];
const Map<String, String> _recordOpLabels = {
  'read': 'View',
  'update': 'Update',
  'delete': 'Delete',
};

/// Per-record (row-level) grants for one person.
class _RecordGrantsSection extends StatefulWidget {
  const _RecordGrantsSection({required this.grants, required this.onChanged});

  final Map<String, RecordGrant> grants; // keyed by RecordGrant.key, mutated
  final VoidCallback onChanged;

  @override
  State<_RecordGrantsSection> createState() => _RecordGrantsSectionState();
}

class _RecordGrantsSectionState extends State<_RecordGrantsSection> {
  String _module = 'items';
  final _searchCtrl = TextEditingController();
  List<RecordOption> _options = const [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final opts = await context.read<AuthProvider>().getRecordOptions(
      _module,
      query: _searchCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _options = opts;
      _loading = false;
    });
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _fetch);
  }

  void _toggle(String entityId, String op, String label, bool on) {
    final key = '$_module:$entityId:$op';
    setState(() {
      if (on) {
        widget.grants[key] = RecordGrant(
          entityType: _module,
          entityId: entityId,
          op: op,
          label: label,
        );
      } else {
        widget.grants.remove(key);
      }
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final grants = widget.grants.values.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Specific records (this person only)'),
        const SizedBox(height: 4),
        const Text(
          'Grant View / Update / Delete on individual records, on top of the '
          'module grid — e.g. "can see all items, edit only these".',
          style: TextStyle(fontSize: 12, color: SoftErpTheme.textSecondary),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                initialValue: _module,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Module',
                  isDense: true,
                ),
                items: [
                  for (final e in _recordModules.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _module = v);
                    _fetch();
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  hintText: 'Search records…',
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_options.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No records found.',
              style: TextStyle(fontSize: 12, color: SoftErpTheme.textSecondary),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(),
                  1: FixedColumnWidth(56),
                  2: FixedColumnWidth(56),
                  3: FixedColumnWidth(56),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    children: [
                      const SizedBox.shrink(),
                      for (final op in _recordOps)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            _recordOpLabels[op]!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: SoftErpTheme.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  for (final o in _options)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            o.label,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        for (final op in _recordOps)
                          Center(
                            child: Checkbox(
                              value: widget.grants.containsKey(
                                '$_module:${o.id}:$op',
                              ),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onChanged: (v) =>
                                  _toggle(o.id, op, o.label, v == true),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        if (grants.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Granted records (${grants.length})',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: SoftErpTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final g in grants)
                InputChip(
                  label: Text(
                    '${g.label} · ${_recordOpLabels[g.op] ?? g.op}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  onDeleted: () {
                    setState(() => widget.grants.remove(g.key));
                    widget.onChanged();
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Renders live-synced record-level permissions nested directly under a module node.
/// Displays hierarchical Groups -> Items structure for inventory & items, and live options for other modules.
class _ModuleRecordGrantsTree extends StatefulWidget {
  const _ModuleRecordGrantsTree({
    required this.moduleKey,
    required this.grants,
    required this.onChanged,
  });

  final String moduleKey;
  final Map<String, RecordGrant> grants;
  final VoidCallback onChanged;

  @override
  State<_ModuleRecordGrantsTree> createState() =>
      _ModuleRecordGrantsTreeState();
}

class _ModuleRecordGrantsTreeState extends State<_ModuleRecordGrantsTree> {
  bool _expanded = false;
  List<RecordOption> _asyncOptions = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.moduleKey != 'items' && widget.moduleKey != 'inventory') {
      _loadAsyncOptions();
    }
  }

  Future<void> _loadAsyncOptions() async {
    setState(() => _loading = true);
    final opts = await context.read<AuthProvider>().getRecordOptions(
      widget.moduleKey,
    );
    if (!mounted) return;
    setState(() {
      _asyncOptions = opts;
      _loading = false;
    });
  }

  void _toggleGrant(
    String entityType,
    String entityId,
    String op,
    String label,
    bool on,
  ) {
    final key = '$entityType:$entityId:$op';
    setState(() {
      if (on) {
        widget.grants[key] = RecordGrant(
          entityType: entityType,
          entityId: entityId,
          op: op,
          label: label,
        );
      } else {
        widget.grants.remove(key);
      }
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final moduleKey = widget.moduleKey;
    final grants = widget.grants;

    // Active grants count for this module
    final activeCount = grants.values
        .where(
          (g) =>
              g.entityType == moduleKey ||
              (moduleKey == 'items' && g.entityType == 'groups') ||
              (moduleKey == 'inventory' &&
                  (g.entityType == 'items' || g.entityType == 'groups')),
        )
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                  size: 18,
                  color: SoftErpTheme.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Specific Record Permissions',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: activeCount > 0
                        ? SoftErpTheme.accent
                        : SoftErpTheme.textSecondary,
                  ),
                ),
                if (activeCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: SoftErpTheme.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$activeCount active grants',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: SoftErpTheme.accent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        if (_expanded) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: (moduleKey == 'items' || moduleKey == 'inventory')
                ? _buildItemsHierarchy(context)
                : _buildAsyncOptionsTree(),
          ),
        ],
      ],
    );
  }

  Widget _buildItemsHierarchy(BuildContext context) {
    final groupsProv = context.watch<GroupsProvider>();
    final itemsProv = context.watch<ItemsProvider>();

    final groups = groupsProv.groups;
    final allItems = itemsProv.items;

    final ungrouped = allItems
        .where((i) => !groups.any((g) => g.id == i.groupId))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTableHeader(),
        const SizedBox(height: 6),
        if (groups.isEmpty && allItems.isEmpty)
          const Text(
            'No inventory groups or items found.',
            style: TextStyle(fontSize: 11, color: SoftErpTheme.textSecondary),
          ),
        for (final g in groups) ...[
          _buildGroupRow(g, allItems.where((i) => i.groupId == g.id).toList()),
          const SizedBox(height: 4),
        ],
        if (ungrouped.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Ungrouped Items',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ),
          for (final item in ungrouped) _buildItemRow(item),
        ],
      ],
    );
  }

  Widget _buildGroupRow(
    GroupDefinition group,
    List<ItemDefinition> groupItems,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.folder_outlined,
                size: 14,
                color: Color(0xFF059669),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  group.name,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _buildOpCheckboxes('groups', '${group.id}', group.name),
            ],
          ),
          if (groupItems.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                children: [for (final item in groupItems) _buildItemRow(item)],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemRow(ItemDefinition item) {
    final title = item.displayName.isNotEmpty
        ? item.displayName
        : 'Item #${item.id}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(
            Icons.category_outlined,
            size: 13,
            color: SoftErpTheme.textSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 11,
                color: SoftErpTheme.textPrimary,
              ),
            ),
          ),
          _buildOpCheckboxes('items', '${item.id}', title),
        ],
      ),
    );
  }

  Widget _buildAsyncOptionsTree() {
    if (_loading) {
      return const SizedBox(
        height: 24,
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text(
              'Loading live records...',
              style: TextStyle(fontSize: 11, color: SoftErpTheme.textSecondary),
            ),
          ],
        ),
      );
    }
    if (_asyncOptions.isEmpty) {
      return const Text(
        'No records found for this module.',
        style: TextStyle(fontSize: 11, color: SoftErpTheme.textSecondary),
      );
    }
    return Column(
      children: [
        _buildTableHeader(),
        const SizedBox(height: 4),
        for (final opt in _asyncOptions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    opt.label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: SoftErpTheme.textPrimary,
                    ),
                  ),
                ),
                _buildOpCheckboxes(widget.moduleKey, opt.id, opt.label),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Record Name',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ),
          for (final op in _recordOps)
            SizedBox(
              width: 44,
              child: Text(
                _recordOpLabels[op] ?? op,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOpCheckboxes(String entityType, String entityId, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final op in _recordOps)
          SizedBox(
            width: 44,
            child: Center(
              child: SizedBox(
                height: 18,
                width: 18,
                child: Checkbox(
                  value: widget.grants.containsKey('$entityType:$entityId:$op'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) =>
                      _toggleGrant(entityType, entityId, op, label, v == true),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Per-user permissions editor.
Future<void> showPermissionsEditor(
  BuildContext context, {
  required int userId,
  required String displayName,
}) async {
  final auth = context.read<AuthProvider>();
  await auth.ensurePermissionCatalog();
  final states = await auth.getUserPermissions(userId);
  final assigned = await auth.getUserPermissionTemplateIds(userId);
  final recordGrantList = await auth.getUserRecordPermissions(userId);
  if (!context.mounted) return;
  final descriptors = auth.permissionDescriptors;
  if (descriptors.isEmpty || states.isEmpty) {
    showGlobalToast(
      auth.errorMessage ?? 'No editable permissions were returned.',
      kind: AppToastKind.error,
    );
    return;
  }
  final toggles = <String, bool>{for (final s in states) s.key: s.allowed};
  final assignedTemplates = <int>{...assigned};
  final recordGrants = <String, RecordGrant>{
    for (final g in recordGrantList) g.key: g,
  };

  String selectedPlatformView = 'desktop'; // 'desktop' | 'mobile'

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setLocal) {
        final templates = dialogContext
            .watch<AuthProvider>()
            .permissionTemplates;
        final auth = dialogContext.watch<AuthProvider>();
        final isDesktopAllowed = toggles['login.desktop'] ?? false;
        final isMobileAllowed = toggles['login.mobile'] ?? false;

        return AlertDialog(
          title: Row(
            children: [
              Text('Permissions & Platform Access · $displayName'),
              const Spacer(),
              // Overall security badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: SoftErpTheme.shellSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isDesktopAllowed && isMobileAllowed
                          ? Icons.devices
                          : (isDesktopAllowed
                                ? Icons.desktop_windows
                                : (isMobileAllowed
                                      ? Icons.phone_android
                                      : Icons.portable_wifi_off)),
                      size: 14,
                      color: SoftErpTheme.accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isDesktopAllowed && isMobileAllowed
                          ? 'Desktop + Mobile'
                          : (isDesktopAllowed
                                ? 'Desktop Only'
                                : (isMobileAllowed
                                      ? 'Mobile Only'
                                      : 'No Access Enabled')),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: SoftErpTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 920,
            height: 600,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // LEFT SIDEBAR (PLATFORM CONTROL & PRESETS PANEL)
                SizedBox(
                  width: 260,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionLabel('Select Platform'),
                        const SizedBox(height: 8),

                        // Desktop Platform Selection Card
                        _sidebarPlatformCard(
                          title: 'Desktop ERP',
                          subtitle: 'Web & Desktop App',
                          isSelected: selectedPlatformView == 'desktop',
                          isAllowed: isDesktopAllowed,
                          color: const Color(0xFF2563EB),
                          onTap: () =>
                              setLocal(() => selectedPlatformView = 'desktop'),
                          onToggleLogin: (v) =>
                              setLocal(() => toggles['login.desktop'] = v),
                        ),

                        const SizedBox(height: 10),

                        // Mobile Platform Selection Card
                        _sidebarPlatformCard(
                          title: 'Mobile App',
                          subtitle: 'Challan Mobile Worker',
                          isSelected: selectedPlatformView == 'mobile',
                          isAllowed: isMobileAllowed,
                          color: const Color(0xFF7C3AED),
                          onTap: () =>
                              setLocal(() => selectedPlatformView = 'mobile'),
                          onToggleLogin: (v) =>
                              setLocal(() => toggles['login.mobile'] = v),
                        ),

                        const Divider(height: 24),

                        // Preset Shortcuts Section in Sidebar
                        const _SectionLabel('Preset Roles'),
                        const SizedBox(height: 8),
                        if (templates.isEmpty)
                          const Text(
                            'No custom presets created yet.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: SoftErpTheme.textSecondary,
                            ),
                          )
                        else
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final t in templates)
                                ActionChip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(
                                    t.isSystemDefault
                                        ? '${t.name} (Role)'
                                        : t.name,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onPressed: () => setLocal(() {
                                    assignedTemplates.add(t.id);
                                    for (final k in t.permissions) {
                                      toggles[k] = true;
                                    }
                                  }),
                                ),
                            ],
                          ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () => _saveCurrentAsPresetDialog(
                                  dialogContext,
                                  toggles,
                                ),
                                icon: const Icon(
                                  Icons.bookmark_add_outlined,
                                  size: 14,
                                ),
                                label: const Text(
                                  'Save Preset',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Manage Presets',
                              icon: const Icon(Icons.tune, size: 16),
                              onPressed: () => showPresetManager(dialogContext),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const VerticalDivider(width: 24, thickness: 1),

                // RIGHT CONTENT PANE (HORIZONTAL Split Main View)
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (selectedPlatformView == 'desktop') ...[
                          // DESKTOP ERP PERMISSIONS MAIN VIEW
                          Row(
                            children: [
                              const Icon(
                                Icons.desktop_windows,
                                size: 18,
                                color: Color(0xFF2563EB),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Desktop & Web ERP Permissions Matrix',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: SoftErpTheme.textPrimary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                isDesktopAllowed
                                    ? 'Desktop Login Enabled'
                                    : 'Desktop Login Disabled',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isDesktopAllowed
                                      ? Colors.green.shade800
                                      : Colors.red.shade800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          PermissionTree(
                            descriptors: descriptors,
                            toggles: toggles,
                            grants: recordGrants,
                            onChanged: () => setLocal(() {}),
                          ),
                        ] else ...[
                          // MOBILE APP PERMISSIONS MAIN VIEW
                          Row(
                            children: [
                              const Icon(
                                Icons.phone_android,
                                size: 18,
                                color: Color(0xFF7C3AED),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Challan Mobile App Permissions Matrix',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: SoftErpTheme.textPrimary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                isMobileAllowed
                                    ? 'Mobile PIN Login Enabled'
                                    : 'Mobile PIN Login Disabled',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isMobileAllowed
                                      ? Colors.purple.shade800
                                      : Colors.red.shade800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Mobile Worker Presets
                          const _SectionLabel('Mobile Worker Quick Presets'),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _mobilePresetChip(
                                label: 'Delivery / Field Worker',
                                onTap: () => setLocal(() {
                                  toggles['login.mobile'] = true;
                                  toggles['challans.read'] = true;
                                  toggles['challans.create'] = true;
                                  toggles['challans.update'] = true;
                                  toggles['challans.reconcile'] = true;
                                  toggles['orders.read'] = true;
                                }),
                              ),
                              const SizedBox(width: 6),
                              _mobilePresetChip(
                                label: 'Warehouse Stock Clerk',
                                onTap: () => setLocal(() {
                                  toggles['login.mobile'] = true;
                                  toggles['inventory.read'] = true;
                                  toggles['items.read'] = true;
                                  toggles['units.read'] = true;
                                  toggles['challans.read'] = true;
                                }),
                              ),
                              const SizedBox(width: 6),
                              _mobilePresetChip(
                                label: 'Block Mobile Access',
                                color: Colors.red.shade700,
                                onTap: () => setLocal(() {
                                  toggles['login.mobile'] = false;
                                }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Dedicated Mobile App Permissions Matrix (CRUD TABLE GRID)
                          Opacity(
                            opacity: isMobileAllowed ? 1.0 : 0.45,
                            child: PermissionTree(
                              descriptors: descriptors
                                  .where(
                                    (d) => [
                                      'challans',
                                      'inventory',
                                      'orders',
                                      'action_center',
                                      'items',
                                    ].contains(d.module),
                                  )
                                  .toList(),
                              toggles: toggles,
                              grants: recordGrants,
                              onChanged: () => setLocal(() {}),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final ok1 = await auth.updateUserPermissionTemplates(
                  userId: userId,
                  templateIds: assignedTemplates.toList(growable: false),
                );
                if (!ok1) return;
                final nextStates = states
                    .map(
                      (s) => UserPermissionState(
                        key: s.key,
                        allowed: toggles[s.key] ?? s.allowed,
                        source: s.source,
                      ),
                    )
                    .toList(growable: false);
                final ok = await auth.updateUserPermissions(
                  userId: userId,
                  states: nextStates,
                );
                await auth.updateUserRecordPermissions(
                  userId,
                  recordGrants.values
                      .map(
                        (g) => {
                          'entityType': g.entityType,
                          'entityId': g.entityId,
                          'op': g.op,
                        },
                      )
                      .toList(growable: false),
                );
                if (dialogContext.mounted && ok) {
                  Navigator.of(dialogContext).pop();
                }
                showGlobalToast(
                  ok
                      ? 'Permissions updated.'
                      : (auth.errorMessage ?? 'Could not save permissions.'),
                  kind: ok ? AppToastKind.success : AppToastKind.error,
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> _saveCurrentAsPresetDialog(
  BuildContext context,
  Map<String, bool> toggles,
) async {
  final auth = context.read<AuthProvider>();
  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Save Current Grid as Preset'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Preset Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) return;
            final activeKeys = toggles.entries
                .where((e) => e.value)
                .map((e) => e.key)
                .toList(growable: false);
            final ok = await auth.createPermissionPreset(
              name: name,
              description: descCtrl.text.trim(),
              permissions: activeKeys,
            );
            if (dialogContext.mounted && ok) {
              Navigator.of(dialogContext).pop();
            }
            showGlobalToast(
              ok
                  ? 'Preset created.'
                  : (auth.errorMessage ?? 'Failed to create preset.'),
              kind: ok ? AppToastKind.success : AppToastKind.error,
            );
          },
          child: const Text('Save Preset'),
        ),
      ],
    ),
  );
  nameCtrl.dispose();
  descCtrl.dispose();
}

/// Lists named presets and lets an admin create / edit / delete them.
Future<void> showPresetManager(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  await auth.ensurePermissionCatalog();
  await auth.reloadPermissionTemplates();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final templates = dialogContext.watch<AuthProvider>().permissionTemplates;
      return AlertDialog(
        title: const Text('Named roles (presets)'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => _showPresetEditor(dialogContext),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New preset'),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: templates.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text('No presets yet.'),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final t in templates)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(t.name),
                              subtitle: Text(
                                t.isSystemDefault
                                    ? 'Built-in · ${t.permissions.length} permissions'
                                    : '${t.permissions.length} permissions',
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              trailing: t.isSystemDefault
                                  ? const Text(
                                      'locked',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: SoftErpTheme.textSecondary,
                                      ),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Edit',
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            size: 18,
                                          ),
                                          onPressed: () => _showPresetEditor(
                                            dialogContext,
                                            template: t,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Delete',
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                            color: Color(0xFFD64545),
                                          ),
                                          onPressed: () async {
                                            final ok = await auth
                                                .deletePermissionPreset(t.id);
                                            showGlobalToast(
                                              ok
                                                  ? 'Preset deleted.'
                                                  : (auth.errorMessage ??
                                                        'Delete failed.'),
                                              kind: ok
                                                  ? AppToastKind.success
                                                  : AppToastKind.error,
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

Future<void> _showPresetEditor(
  BuildContext context, {
  PermissionTemplate? template,
}) async {
  final auth = context.read<AuthProvider>();
  final descriptors = auth.permissionDescriptors;
  final nameCtrl = TextEditingController(text: template?.name ?? '');
  final descCtrl = TextEditingController(text: template?.description ?? '');
  final toggles = <String, bool>{
    for (final key in template?.permissions ?? const <String>[]) key: true,
  };
  String selectedPlatformView = 'desktop';

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setLocal) => AlertDialog(
        title: Text(template == null ? 'New preset' : 'Edit ${template.name}'),
        content: SizedBox(
          width: 920,
          height: 620,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Role name',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // LEFT SIDEBAR (PLATFORM CONTROL)
                    SizedBox(
                      width: 260,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionLabel('Select Platform'),
                            const SizedBox(height: 8),
                            _sidebarPlatformCard(
                              title: 'Desktop ERP',
                              subtitle: 'Web & Desktop App',
                              isSelected: selectedPlatformView == 'desktop',
                              isAllowed: toggles['login.desktop'] ?? false,
                              color: const Color(0xFF2563EB),
                              onTap: () => setLocal(
                                () => selectedPlatformView = 'desktop',
                              ),
                              onToggleLogin: (v) =>
                                  setLocal(() => toggles['login.desktop'] = v),
                            ),
                            const SizedBox(height: 10),
                            _sidebarPlatformCard(
                              title: 'Mobile App',
                              subtitle: 'Challan Mobile Worker',
                              isSelected: selectedPlatformView == 'mobile',
                              isAllowed: toggles['login.mobile'] ?? false,
                              color: const Color(0xFF7C3AED),
                              onTap: () => setLocal(
                                () => selectedPlatformView = 'mobile',
                              ),
                              onToggleLogin: (v) =>
                                  setLocal(() => toggles['login.mobile'] = v),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 24, thickness: 1),
                    // RIGHT CONTENT PANE
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (selectedPlatformView == 'desktop') ...[
                              Row(
                                children: [
                                  const Icon(
                                    Icons.desktop_windows,
                                    size: 18,
                                    color: Color(0xFF2563EB),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Desktop & Web ERP Permissions Matrix',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: SoftErpTheme.textPrimary,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    (toggles['login.desktop'] ?? false)
                                        ? 'Desktop Login Enabled'
                                        : 'Desktop Login Disabled',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: (toggles['login.desktop'] ?? false)
                                          ? Colors.green.shade800
                                          : Colors.red.shade800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              PermissionTree(
                                descriptors: descriptors,
                                toggles: toggles,
                                onChanged: () => setLocal(() {}),
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  const Icon(
                                    Icons.phone_android,
                                    size: 18,
                                    color: Color(0xFF7C3AED),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Challan Mobile App Permissions Matrix',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: SoftErpTheme.textPrimary,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    (toggles['login.mobile'] ?? false)
                                        ? 'Mobile PIN Login Enabled'
                                        : 'Mobile PIN Login Disabled',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: (toggles['login.mobile'] ?? false)
                                          ? Colors.purple.shade800
                                          : Colors.red.shade800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Opacity(
                                opacity: (toggles['login.mobile'] ?? false)
                                    ? 1.0
                                    : 0.45,
                                child: PermissionTree(
                                  descriptors: descriptors
                                      .where(
                                        (d) => [
                                          'challans',
                                          'inventory',
                                          'orders',
                                          'action_center',
                                          'items',
                                        ].contains(d.module),
                                      )
                                      .toList(),
                                  toggles: toggles,
                                  onChanged: () => setLocal(() {}),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) {
                showGlobalToast(
                  'A name is required.',
                  kind: AppToastKind.error,
                );
                return;
              }
              final keys = toggles.entries
                  .where((e) => e.value)
                  .map((e) => e.key)
                  .toList(growable: false);
              final ok = template == null
                  ? await auth.createPermissionPreset(
                      name: name,
                      description: descCtrl.text.trim(),
                      permissions: keys,
                    )
                  : await auth.updatePermissionPreset(
                      id: template.id,
                      name: name,
                      description: descCtrl.text.trim(),
                      permissions: keys,
                    );
              if (dialogContext.mounted && ok) {
                Navigator.of(dialogContext).pop();
              }
              showGlobalToast(
                ok
                    ? 'Preset saved.'
                    : (auth.errorMessage ?? 'Could not save preset.'),
                kind: ok ? AppToastKind.success : AppToastKind.error,
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  nameCtrl.dispose();
  descCtrl.dispose();
}

Widget _mobilePresetChip({
  required String label,
  required VoidCallback onTap,
  Color? color,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (color ?? SoftErpTheme.accent).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: (color ?? SoftErpTheme.accent).withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color ?? SoftErpTheme.accent,
        ),
      ),
    ),
  );
}

Widget _sidebarPlatformCard({
  required String title,
  required String subtitle,
  required bool isSelected,
  required bool isAllowed,
  required Color color,
  required VoidCallback onTap,
  required ValueChanged<bool> onToggleLogin,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected
            ? color.withValues(alpha: 0.08)
            : SoftErpTheme.shellSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? color : Colors.black.withValues(alpha: 0.1),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? color : SoftErpTheme.textPrimary,
                  ),
                ),
              ),
              Switch(
                value: isAllowed,
                onChanged: onToggleLogin,
                activeThumbColor: color,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: SoftErpTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isAllowed ? Colors.green.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isAllowed ? Colors.green.shade300 : Colors.grey.shade300,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isAllowed ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  isAllowed ? 'Login Allowed' : 'Login Blocked',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isAllowed
                        ? Colors.green.shade800
                        : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
