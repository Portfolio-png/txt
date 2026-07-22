import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../domain/auth_user.dart';
import '../providers/auth_provider.dart';

// Top-level module order (mirrors the nav bar); masters nest under a group.
const List<String> _topModuleOrder = [
  'orders',
  'inventory',
  'challans',
  'production',
  'jobs',
  'action_center',
];
const List<String> _mastersModuleOrder = [
  'people',
  'clients',
  'vendors',
  'items',
  'units',
  'machines',
  'dies',
  'pipelines',
];
const List<String> _ops = ['create', 'read', 'update', 'delete'];
const Map<String, String> _opLabels = {
  'create': 'Create',
  'read': 'View',
  'update': 'Update',
  'delete': 'Delete',
};

// Legacy / reserved keys never shown in the editor.
const Set<String> _hiddenKeys = {
  'config.read',
  'config.write',
  'users.create_admin',
};

/// An expandable CRUD permission grid: each module renders as a row with
/// Create, View, Update, and Delete columns. Tri-state group rows (Masters)
/// and module-level "All" checkboxes allow rapid toggling. An "Advanced" section
/// reveals fine-grained split keys under each module.
class PermissionTree extends StatefulWidget {
  const PermissionTree({
    super.key,
    required this.descriptors,
    required this.toggles,
    required this.onChanged,
  });

  final List<PermissionDescriptor> descriptors;
  final Map<String, bool> toggles; // mutated in place
  final VoidCallback onChanged;

  @override
  State<PermissionTree> createState() => _PermissionTreeState();
}

class _PermissionTreeState extends State<PermissionTree> {
  final Set<String> _expanded = {};

  Map<String, bool> get _t => widget.toggles;

  bool _isActorAuthorized(String key, AuthProvider auth) {
    if (auth.user?.isSuperAdmin == true) return true;
    return auth.can(key);
  }

  bool? _tri(List<String> keys) {
    if (keys.isEmpty) return false;
    var on = 0;
    for (final k in keys) {
      if (_t[k] == true) on++;
    }
    if (on == 0) return false;
    if (on == keys.length) return true;
    return null; // some on → indeterminate
  }

  void _setAll(List<String> keys, bool value, AuthProvider auth) {
    setState(() {
      for (final k in keys) {
        if (_isActorAuthorized(k, auth)) {
          _t[k] = value;
        }
      }
    });
    widget.onChanged();
  }

  void _setOne(String key, bool value, AuthProvider auth) {
    if (!_isActorAuthorized(key, auth)) return;
    setState(() => _t[key] = value);
    widget.onChanged();
  }

  bool _isExpanded(String id) => _expanded.contains(id);
  void _toggleExpand(String id) => setState(() {
        if (!_expanded.remove(id)) _expanded.add(id);
      });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final byModuleCoarse = <String, Map<String, PermissionDescriptor>>{};
    final byModuleFine = <String, List<PermissionDescriptor>>{};
    final labels = <String, String>{};
    final caps = <PermissionDescriptor>[];

    for (final d in widget.descriptors) {
      if (d.isModule && d.module != null && d.op != null) {
        byModuleCoarse.putIfAbsent(d.module!, () => {})[d.op!] = d;
        labels[d.module!] = d.moduleLabel ?? d.module!;
      } else if (d.category == 'fine' && d.module != null) {
        byModuleFine.putIfAbsent(d.module!, () => []).add(d);
        labels[d.module!] = d.moduleLabel ?? d.module!;
      } else if (d.category == 'capability' && !_hiddenKeys.contains(d.key)) {
        caps.add(d);
      }
    }

    final topModules = [
      ..._topModuleOrder.where(byModuleCoarse.containsKey),
      ...byModuleCoarse.keys.where((m) =>
          !_topModuleOrder.contains(m) && !_mastersModuleOrder.contains(m)),
    ];
    final masterModules =
        _mastersModuleOrder.where(byModuleCoarse.containsKey).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Table(
          columnWidths: const {
            0: FixedColumnWidth(46),
            1: FlexColumnWidth(),
            2: FixedColumnWidth(56),
            3: FixedColumnWidth(56),
            4: FixedColumnWidth(56),
            5: FixedColumnWidth(56),
            6: FixedColumnWidth(36),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            _headerRow(),
            for (final m in topModules) ...[
              _moduleRow(labels[m] ?? m, m, byModuleCoarse[m]!, byModuleFine[m] ?? const [], auth, indent: 4),
              if (_isExpanded('fine:$m') && (byModuleFine[m]?.isNotEmpty ?? false))
                _fineDetailsRow(m, byModuleFine[m]!, auth, indent: 24),
            ],
            if (masterModules.isNotEmpty) ...[
              _groupRow('Masters', masterModules, byModuleCoarse, auth),
              if (_isExpanded('group:Masters'))
                for (final m in masterModules) ...[
                  _moduleRow(labels[m] ?? m, m, byModuleCoarse[m]!, byModuleFine[m] ?? const [], auth, indent: 28),
                  if (_isExpanded('fine:$m') && (byModuleFine[m]?.isNotEmpty ?? false))
                    _fineDetailsRow(m, byModuleFine[m]!, auth, indent: 44),
                ],
            ],
          ],
        ),
        if (caps.isNotEmpty) ...[
          const SizedBox(height: 16),
          const _SectionLabel('Capabilities'),
          const SizedBox(height: 4),
          for (final c in caps)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _t[c.key] ?? false,
              enabled: _isActorAuthorized(c.key, auth),
              onChanged: (v) => _setOne(c.key, v == true, auth),
              title: Text(c.label, style: const TextStyle(fontSize: 13)),
              subtitle: c.description.isEmpty
                  ? null
                  : Text(c.description, style: const TextStyle(fontSize: 11.5)),
            ),
        ],
      ],
    );
  }

  TableRow _headerRow() {
    return TableRow(
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text(
            'All',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: SoftErpTheme.textSecondary,
            ),
          ),
        ),
        const SizedBox.shrink(),
        for (final op in _ops)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _opLabels[op]!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ),
        const SizedBox.shrink(),
      ],
    );
  }

  TableRow _moduleRow(
    String label,
    String moduleKey,
    Map<String, PermissionDescriptor> ops,
    List<PermissionDescriptor> fineKeys,
    AuthProvider auth, {
    double indent = 0,
  }) {
    final allKeys = [
      ...ops.values.map((d) => d.key),
      ...fineKeys.map((d) => d.key),
    ];
    final hasFine = fineKeys.isNotEmpty;
    final fineExpanded = _isExpanded('fine:$moduleKey');

    return TableRow(
      children: [
        _triCell(allKeys, auth),
        Padding(
          padding: EdgeInsets.only(left: indent, top: 4, bottom: 4),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: SoftErpTheme.textPrimary,
            ),
          ),
        ),
        for (final op in _ops)
          _coarseCell(ops[op], fineKeys.where((f) => f.parentOp == op).map((f) => f.key).toList(), auth),
        hasFine
            ? IconButton(
                icon: Icon(
                  fineExpanded ? Icons.tune : Icons.tune_outlined,
                  size: 16,
                  color: fineExpanded ? SoftErpTheme.accent : SoftErpTheme.textSecondary,
                ),
                tooltip: fineExpanded ? 'Hide fine keys' : 'Advanced permissions',
                visualDensity: VisualDensity.compact,
                onPressed: () => _toggleExpand('fine:$moduleKey'),
              )
            : const SizedBox.shrink(),
      ],
    );
  }

  TableRow _fineDetailsRow(
    String moduleKey,
    List<PermissionDescriptor> fineKeys,
    AuthProvider auth, {
    double indent = 24,
  }) {
    return TableRow(
      children: [
        const SizedBox.shrink(),
        Container(
          margin: EdgeInsets.only(left: indent, top: 2, bottom: 6, right: 8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: SoftErpTheme.shellSurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'FINE-GRAINED OVERRIDES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              for (final f in fineKeys)
                CheckboxListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _t[f.key] ?? (_t[f.parentKey] == true),
                  enabled: _isActorAuthorized(f.key, auth),
                  onChanged: (v) => _setOne(f.key, v == true, auth),
                  title: Text(f.label, style: const TextStyle(fontSize: 12)),
                  subtitle: f.description.isEmpty
                      ? null
                      : Text(f.description, style: const TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ),
        const SizedBox.shrink(),
        const SizedBox.shrink(),
        const SizedBox.shrink(),
        const SizedBox.shrink(),
        const SizedBox.shrink(),
      ],
    );
  }

  TableRow _groupRow(
    String group,
    List<String> members,
    Map<String, Map<String, PermissionDescriptor>> byModule,
    AuthProvider auth,
  ) {
    final expanded = _isExpanded('group:$group');
    return TableRow(
      children: [
        _triCell([
          for (final m in members)
            for (final d in byModule[m]!.values) d.key,
        ], auth),
        InkWell(
          onTap: () => _toggleExpand('group:$group'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.chevron_right_rounded,
                  size: 20,
                  color: SoftErpTheme.textSecondary,
                ),
                Text(
                  group,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        for (final op in _ops)
          _triCell([
            for (final m in members)
              if (byModule[m]?[op] != null) byModule[m]![op]!.key,
          ], auth),
        const SizedBox.shrink(),
      ],
    );
  }

  Widget _coarseCell(PermissionDescriptor? d, List<String> childFineKeys, AuthProvider auth) {
    if (d == null) return const SizedBox.shrink();
    final isAuthorized = _isActorAuthorized(d.key, auth);

    // If there are fine keys, evaluate if all fine keys match the coarse key
    bool? triValue = _t[d.key] ?? false;
    if (childFineKeys.isNotEmpty && _t[d.key] == true) {
      var offFine = 0;
      for (final fk in childFineKeys) {
        if (_t[fk] == false) offFine++;
      }
      if (offFine > 0) {
        triValue = null; // Indeterminate when some fine key is denied
      }
    }

    return Center(
      child: Checkbox(
        tristate: childFineKeys.isNotEmpty,
        value: triValue,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: isAuthorized ? (v) => _setOne(d.key, v == true, auth) : null,
      ),
    );
  }

  Widget _triCell(List<String> keys, AuthProvider auth) {
    if (keys.isEmpty) return const SizedBox.shrink();
    final tri = _tri(keys);
    final anyAuthorized = keys.any((k) => _isActorAuthorized(k, auth));
    return Center(
      child: Checkbox(
        tristate: true,
        value: tri,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: anyAuthorized ? (_) => _setAll(keys, tri != true, auth) : null,
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
    final opts = await context
        .read<AuthProvider>()
        .getRecordOptions(_module, query: _searchCtrl.text);
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
                          child: Text(o.label,
                              style: const TextStyle(fontSize: 13)),
                        ),
                        for (final op in _recordOps)
                          Center(
                            child: Checkbox(
                              value: widget.grants
                                  .containsKey('$_module:${o.id}:$op'),
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

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setLocal) {
        final templates = dialogContext.watch<AuthProvider>().permissionTemplates;
        return AlertDialog(
          title: Text('Permissions · $displayName'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Primary / default: the CRUD grid.
                  const _SectionLabel('Module CRUD Grid'),
                  const SizedBox(height: 4),
                  const Text(
                    'Columns are Create · View · Update · Delete. Use "All" to toggle a row, '
                    'or tap the tune icon to expand fine-grained overrides.',
                    style: TextStyle(
                      fontSize: 12,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  PermissionTree(
                    descriptors: descriptors,
                    toggles: toggles,
                    onChanged: () => setLocal(() {}),
                  ),
                  const Divider(height: 24),
                  // Presets chip row below grid.
                  Row(
                    children: [
                      const Expanded(
                        child: _SectionLabel('Preset Shortcuts'),
                      ),
                      TextButton.icon(
                        onPressed: () => _saveCurrentAsPresetDialog(dialogContext, toggles),
                        icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                        label: const Text('Save as preset'),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: () => showPresetManager(dialogContext),
                        icon: const Icon(Icons.tune, size: 16),
                        label: const Text('Manage presets'),
                      ),
                    ],
                  ),
                  if (templates.isEmpty)
                    const Text(
                      'No presets yet. Apply built-in roles or save current grid as a preset.',
                      style: TextStyle(
                        fontSize: 12,
                        color: SoftErpTheme.textSecondary,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in templates)
                          FilterChip(
                            label: Text(
                              t.isSystemDefault
                                  ? '${t.name} (Built-in)'
                                  : t.name,
                            ),
                            selected: assignedTemplates.contains(t.id),
                            onSelected: (sel) => setLocal(() {
                              if (sel) {
                                assignedTemplates.add(t.id);
                                for (final k in t.permissions) {
                                  toggles[k] = true;
                                }
                              } else {
                                assignedTemplates.remove(t.id);
                              }
                            }),
                          ),
                      ],
                    ),
                  const SizedBox(height: 4),
                  const Text(
                    'Applying a preset fills the grid client-side. You can tweak individual cells before saving.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                  const Divider(height: 24),
                  // Deeper granularity: per-record grants for this person.
                  _RecordGrantsSection(
                    grants: recordGrants,
                    onChanged: () => setLocal(() {}),
                  ),
                ],
              ),
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
                    .map((s) => UserPermissionState(
                          key: s.key,
                          allowed: toggles[s.key] ?? s.allowed,
                          source: s.source,
                        ))
                    .toList(growable: false);
                final ok = await auth.updateUserPermissions(
                  userId: userId,
                  states: nextStates,
                );
                await auth.updateUserRecordPermissions(
                  userId,
                  recordGrants.values
                      .map((g) => {
                            'entityType': g.entityType,
                            'entityId': g.entityId,
                            'op': g.op,
                          })
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
              decoration: const InputDecoration(labelText: 'Description (optional)'),
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
              ok ? 'Preset created.' : (auth.errorMessage ?? 'Failed to create preset.'),
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
                                  ? const Text('locked',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: SoftErpTheme.textSecondary))
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Edit',
                                          icon: const Icon(Icons.edit_outlined,
                                              size: 18),
                                          onPressed: () => _showPresetEditor(
                                              dialogContext,
                                              template: t),
                                        ),
                                        IconButton(
                                          tooltip: 'Delete',
                                          icon: const Icon(Icons.delete_outline,
                                              size: 18, color: Color(0xFFD64545)),
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

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setLocal) => AlertDialog(
        title: Text(template == null ? 'New preset' : 'Edit ${template.name}'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Role name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Description (optional)'),
                ),
                const SizedBox(height: 14),
                PermissionTree(
                  descriptors: descriptors,
                  toggles: toggles,
                  onChanged: () => setLocal(() {}),
                ),
              ],
            ),
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
                showGlobalToast('A name is required.', kind: AppToastKind.error);
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
