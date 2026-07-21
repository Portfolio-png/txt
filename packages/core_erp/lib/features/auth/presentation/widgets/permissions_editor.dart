import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../domain/auth_user.dart';
import '../providers/auth_provider.dart';

const List<String> _moduleOrder = [
  'orders',
  'inventory',
  'masters',
  'production',
  'jobs',
  'challans',
  'people',
  'action_center',
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

/// A module × CRUD grid + a capabilities section, driven by [toggles].
/// Reused by the per-user permissions editor and the preset editor.
class PermissionMatrix extends StatelessWidget {
  const PermissionMatrix({
    super.key,
    required this.descriptors,
    required this.toggles,
    required this.onChanged,
  });

  final List<PermissionDescriptor> descriptors;
  final Map<String, bool> toggles;
  final void Function(String key, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final byModule = <String, Map<String, PermissionDescriptor>>{};
    final byModuleLabel = <String, String>{};
    final caps = <PermissionDescriptor>[];
    for (final d in descriptors) {
      if (d.isModule && d.module != null && d.op != null) {
        byModule.putIfAbsent(d.module!, () => {})[d.op!] = d;
        byModuleLabel[d.module!] = d.moduleLabel ?? d.module!;
      } else if (!d.isModule && !_hiddenKeys.contains(d.key)) {
        caps.add(d);
      }
    }
    final modules = [
      ..._moduleOrder.where(byModule.containsKey),
      ...byModule.keys.where((m) => !_moduleOrder.contains(m)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Modules'),
        const SizedBox(height: 6),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(),
            1: FixedColumnWidth(62),
            2: FixedColumnWidth(62),
            3: FixedColumnWidth(62),
            4: FixedColumnWidth(62),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                const SizedBox.shrink(),
                for (final op in _ops)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      _opLabels[op]!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: SoftErpTheme.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
            for (final m in modules)
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      byModuleLabel[m] ?? m,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: SoftErpTheme.textPrimary,
                      ),
                    ),
                  ),
                  for (final op in _ops)
                    _cell(byModule[m]?[op]),
                ],
              ),
          ],
        ),
        if (caps.isNotEmpty) ...[
          const SizedBox(height: 16),
          const _SectionLabel('Capabilities'),
          const SizedBox(height: 2),
          for (final c in caps)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: toggles[c.key] ?? false,
              onChanged: (v) => onChanged(c.key, v == true),
              title: Text(c.label, style: const TextStyle(fontSize: 13)),
              subtitle: c.description.isEmpty
                  ? null
                  : Text(c.description, style: const TextStyle(fontSize: 11.5)),
            ),
        ],
      ],
    );
  }

  Widget _cell(PermissionDescriptor? d) {
    if (d == null) return const SizedBox.shrink();
    return Checkbox(
      value: toggles[d.key] ?? false,
      onChanged: (v) => onChanged(d.key, v == true),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                  Row(
                    children: [
                      const Expanded(child: _SectionLabel('Presets (named roles)')),
                      TextButton.icon(
                        onPressed: () => showPresetManager(dialogContext),
                        icon: const Icon(Icons.tune, size: 16),
                        label: const Text('Manage'),
                      ),
                    ],
                  ),
                  if (templates.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'No presets yet. Use Manage to create a named role.',
                        style: TextStyle(
                          fontSize: 12,
                          color: SoftErpTheme.textSecondary,
                        ),
                      ),
                    ),
                  for (final t in templates)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: assignedTemplates.contains(t.id),
                      onChanged: (v) => setLocal(() {
                        if (v == true) {
                          assignedTemplates.add(t.id);
                        } else {
                          assignedTemplates.remove(t.id);
                        }
                      }),
                      title: Text(
                        t.isSystemDefault ? '${t.name} · built-in' : t.name,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: t.description.isEmpty
                          ? null
                          : Text(t.description,
                              style: const TextStyle(fontSize: 11.5)),
                    ),
                  const Divider(height: 24),
                  const Text(
                    'Fine-tune access for just this person (overrides presets):',
                    style: TextStyle(
                      fontSize: 12,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  PermissionMatrix(
                    descriptors: descriptors,
                    toggles: toggles,
                    onChanged: (key, value) => setLocal(() => toggles[key] = value),
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
                PermissionMatrix(
                  descriptors: descriptors,
                  toggles: toggles,
                  onChanged: (key, value) => setLocal(() => toggles[key] = value),
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
