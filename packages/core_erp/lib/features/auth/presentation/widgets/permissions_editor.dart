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

/// An expandable permission tree (old-Windows-installer style): each module
/// from the nav expands to its CRUD checkboxes; the masters nest under a
/// "Masters" group. Parent rows are tri-state (all / some / none) and toggle
/// their whole subtree. A capabilities section follows. Reused by the per-user
/// editor and the preset editor.
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

  void _setAll(List<String> keys, bool value) {
    setState(() {
      for (final k in keys) {
        _t[k] = value;
      }
    });
    widget.onChanged();
  }

  void _setOne(String key, bool value) {
    setState(() => _t[key] = value);
    widget.onChanged();
  }

  bool _isExpanded(String id) => _expanded.contains(id);
  void _toggleExpand(String id) => setState(() {
        if (!_expanded.remove(id)) _expanded.add(id);
      });

  @override
  Widget build(BuildContext context) {
    final byModule = <String, Map<String, PermissionDescriptor>>{};
    final labels = <String, String>{};
    final caps = <PermissionDescriptor>[];
    for (final d in widget.descriptors) {
      if (d.isModule && d.module != null && d.op != null) {
        byModule.putIfAbsent(d.module!, () => {})[d.op!] = d;
        labels[d.module!] = d.moduleLabel ?? d.module!;
      } else if (!d.isModule && !_hiddenKeys.contains(d.key)) {
        caps.add(d);
      }
    }
    final topModules = [
      ..._topModuleOrder.where(byModule.containsKey),
      ...byModule.keys.where((m) =>
          !_topModuleOrder.contains(m) && !_mastersModuleOrder.contains(m)),
    ];
    final masterModules =
        _mastersModuleOrder.where(byModule.containsKey).toList();

    final rows = <TableRow>[_headerRow()];
    for (final m in topModules) {
      rows.add(_moduleRow(labels[m] ?? m, byModule[m]!, indent: 4));
    }
    if (masterModules.isNotEmpty) {
      rows.add(_groupRow('Masters', masterModules, byModule));
      if (_isExpanded('group:Masters')) {
        for (final m in masterModules) {
          rows.add(_moduleRow(labels[m] ?? m, byModule[m]!, indent: 30));
        }
      }
    }

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
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: rows,
        ),
        if (caps.isNotEmpty) ...[
          const SizedBox(height: 14),
          const _SectionLabel('Capabilities'),
          for (final c in caps)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _t[c.key] ?? false,
              onChanged: (v) => _setOne(c.key, v == true),
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
      ],
    );
  }

  TableRow _moduleRow(
    String label,
    Map<String, PermissionDescriptor> ops, {
    double indent = 0,
  }) {
    return TableRow(
      children: [
        _triCell([for (final d in ops.values) d.key]),
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
        for (final op in _ops) _cell(ops[op]),
      ],
    );
  }

  TableRow _groupRow(
    String group,
    List<String> members,
    Map<String, Map<String, PermissionDescriptor>> byModule,
  ) {
    final expanded = _isExpanded('group:$group');
    return TableRow(
      children: [
        _triCell([
          for (final m in members)
            for (final d in byModule[m]!.values) d.key,
        ]),
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
          ]),
      ],
    );
  }

  Widget _cell(PermissionDescriptor? d) {
    if (d == null) return const SizedBox.shrink();
    return Center(
      child: Checkbox(
        value: _t[d.key] ?? false,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: (v) => _setOne(d.key, v == true),
      ),
    );
  }

  Widget _triCell(List<String> keys) {
    if (keys.isEmpty) return const SizedBox.shrink();
    final tri = _tri(keys);
    return Center(
      child: Checkbox(
        tristate: true,
        value: tri,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: (_) => _setAll(keys, tri != true),
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

/// Per-record (row-level) grants for one person: pick a module, search its
/// actual records, and grant View/Update/Delete on individual ones — on top of
/// the module grid ("can see all, edit only these").
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

/// Per-user permissions editor: assign named presets + a module CRUD grid of
/// per-user overrides. Replaces the old flat permission-key checklist.
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
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Primary / default way: the module × CRUD grid.
                  const _SectionLabel('Module permissions'),
                  const SizedBox(height: 4),
                  const Text(
                    'Columns are Create · View · Update · Delete. Tick exactly '
                    'what this person can do.',
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
                  // Deeper granularity: per-record grants for this person.
                  _RecordGrantsSection(
                    grants: recordGrants,
                    onChanged: () => setLocal(() {}),
                  ),
                  const Divider(height: 24),
                  // Secondary: presets are just a shortcut that fills the grid.
                  Row(
                    children: [
                      const Expanded(
                        child: _SectionLabel('Shortcut · apply a preset'),
                      ),
                      TextButton.icon(
                        onPressed: () => showPresetManager(dialogContext),
                        icon: const Icon(Icons.tune, size: 16),
                        label: const Text('Manage'),
                      ),
                    ],
                  ),
                  if (templates.isEmpty)
                    const Text(
                      'No presets yet. Use Manage to create a named role.',
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
                                  ? '${t.name} · built-in'
                                  : t.name,
                            ),
                            selected: assignedTemplates.contains(t.id),
                            onSelected: (sel) => setLocal(() {
                              if (sel) {
                                assignedTemplates.add(t.id);
                                for (final k in t.permissions) {
                                  toggles[k] = true; // stamp the grid above
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
                    'A preset just fills the grid above — tweak any box after.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: SoftErpTheme.textSecondary,
                    ),
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
                // Persist per-record grants alongside the module grid.
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
