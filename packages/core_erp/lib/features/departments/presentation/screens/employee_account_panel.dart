import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/widgets/permissions_editor.dart';
import '../../../auth/presentation/widgets/track_panel.dart';
import '../../domain/employee_definition.dart';
import '../providers/departments_provider.dart';

/// The "Account & Access" pane shown when the profile avatar in the employee
/// editor is tapped. It absorbs everything that used to live on the Users tab —
/// create login, PIN, reset password, sessions, permissions (incl. desktop /
/// mobile access), activate/deactivate, delete — but keyed on the person's
/// linked login (`employee.login.userId`) instead of a standalone account list.
class EmployeeAccountPanel extends StatelessWidget {
  const EmployeeAccountPanel({super.key, required this.employeeId});

  final int employeeId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DepartmentsProvider>();
    final emp = provider.employeeById(employeeId);
    if (emp == null) {
      return const _InfoCard(
        icon: Icons.save_outlined,
        title: 'Save this person first',
        message:
            'Their basic details need to be saved before a login can be managed.',
      );
    }
    if (emp.employmentType != 'in-house') {
      return const _InfoCard(
        icon: Icons.badge_outlined,
        title: 'Freelancers don’t hold a login',
        message:
            'Only in-house people can have an account. Switch the employment '
            'type to In-house to enable a login.',
      );
    }
    if (emp.login == null) {
      return _CreateLoginCard(emp: emp);
    }
    return _AccountControls(emp: emp);
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ErpDialogSectionCard(
      title: 'Account & Access',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: SoftErpTheme.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: SoftErpTheme.textPrimary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateLoginCard extends StatefulWidget {
  const _CreateLoginCard({required this.emp});

  final EmployeeDefinition emp;

  @override
  State<_CreateLoginCard> createState() => _CreateLoginCardState();
}

class _CreateLoginCardState extends State<_CreateLoginCard> {
  late final TextEditingController _emailCtrl = TextEditingController(
    text: widget.emp.email,
  );
  final _passCtrl = TextEditingController();
  String _role = 'user';

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      showGlobalToast('Enter an email for the login.', kind: AppToastKind.error);
      return;
    }
    if (_passCtrl.text.trim().length < 8) {
      showGlobalToast(
        'Use a temporary password of at least 8 characters.',
        kind: AppToastKind.error,
      );
      return;
    }
    final provider = context.read<DepartmentsProvider>();
    final ok = await provider.createEmployeeLogin(
      widget.emp.id,
      email: email,
      password: _passCtrl.text,
      role: _role,
    );
    if (!mounted) return;
    showGlobalToast(
      ok
          ? 'Login created and linked.'
          : (provider.errorMessage ?? 'Could not create login.'),
      kind: ok ? AppToastKind.success : AppToastKind.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DepartmentsProvider>();
    // Only a super admin can mint an admin; an admin only creates staff.
    final isSuperAdmin = context.watch<AuthProvider>().isSuperAdmin;
    final code = _ddmm(widget.emp.dateOfBirth);
    return ErpDialogSectionCard(
      title: 'Create login',
      subtitle:
          'Give ${widget.emp.name} a login so they can sign in on desktop or '
          'mobile. Their profile stays connected to this record.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LabeledField(controller: _emailCtrl, label: 'Email'),
          const SizedBox(height: 14),
          _LabeledField(
            controller: _passCtrl,
            label: 'Temporary password',
            obscure: true,
          ),
          const SizedBox(height: 14),
          if (isSuperAdmin)
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: _fieldDecoration('Access level'),
              items: const [
                DropdownMenuItem(value: 'user', child: Text('Staff')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
              ],
              onChanged: (v) => setState(() => _role = v ?? 'user'),
            )
          else
            InputDecorator(
              decoration: _fieldDecoration('Access level'),
              child: const Text(
                'Staff',
                style: TextStyle(fontSize: 14, color: SoftErpTheme.textPrimary),
              ),
            ),
          if (code != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.pin_outlined,
                  size: 16,
                  color: SoftErpTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Mobile PIN will be $code (day + month of date of birth).',
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Create login',
              icon: Icons.person_add_alt_1_outlined,
              isLoading: provider.isSaving,
              onPressed: _create,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountControls extends StatefulWidget {
  const _AccountControls({required this.emp});

  final EmployeeDefinition emp;

  @override
  State<_AccountControls> createState() => _AccountControlsState();
}

class _AccountControlsState extends State<_AccountControls> {
  bool? _desktopAccess;
  bool? _mobileAccess;
  List<String> _presetNames = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadAccessFlags();
  }

  /// Best-effort read of the login.desktop / login.mobile permission state and
  /// the assigned preset (named role) names for the header. Silent if the
  /// actor can't manage permissions.
  Future<void> _loadAccessFlags() async {
    final auth = context.read<AuthProvider>();
    final userId = widget.emp.login?.userId;
    if (userId == null || !auth.can('users.manage_permissions')) return;
    await auth.ensurePermissionCatalog();
    final states = await auth.getUserPermissions(userId);
    final assigned = await auth.getUserPermissionTemplateIds(userId);
    if (!mounted || states.isEmpty) return;
    bool? desktop;
    bool? mobile;
    for (final s in states) {
      if (s.key == 'login.desktop') desktop = s.allowed;
      if (s.key == 'login.mobile') mobile = s.allowed;
    }
    final names = auth.permissionTemplates
        .where((t) => assigned.contains(t.id))
        .map((t) => t.name)
        .toList(growable: false);
    setState(() {
      _desktopAccess = desktop;
      _mobileAccess = mobile;
      _presetNames = names;
    });
  }

  /// The role label to show for this account: super admins/admins show their
  /// role; staff show their assigned preset (named role), or 'Staff' if none.
  String _roleLabel(String rawRole) {
    if (rawRole == 'super_admin') return 'Super Admin';
    if (rawRole == 'admin') return 'Admin';
    return _presetNames.isNotEmpty ? _presetNames.join(', ') : 'Staff';
  }

  Future<void> _guard(Future<bool> Function() action, String okMessage) async {
    setState(() => _busy = true);
    final ok = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    final auth = context.read<AuthProvider>();
    showGlobalToast(
      ok ? okMessage : (auth.errorMessage ?? 'Something went wrong.'),
      kind: ok ? AppToastKind.success : AppToastKind.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<DepartmentsProvider>();
    final login = widget.emp.login!;
    final userId = login.userId;
    final isActive = login.isActive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ErpDialogSectionCard(
          title: 'Account',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: SoftErpTheme.accentSoft,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.verified_user_outlined,
                      color: SoftErpTheme.accentDark,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          login.email.isEmpty ? '(no email)' : login.email,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: SoftErpTheme.textPrimary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _roleLabel(login.role),
                          style: const TextStyle(
                            color: SoftErpTheme.textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SoftStatusPill(
                    label: isActive ? 'ACTIVE' : 'DISABLED',
                    background: isActive
                        ? SoftErpTheme.successBg
                        : const Color(0xFFFDECEC),
                    textColor: isActive
                        ? SoftErpTheme.successText
                        : const Color(0xFF8A2E2E),
                    borderColor: isActive
                        ? SoftErpTheme.successBg
                        : const Color(0xFFF3C0C0),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (login.loginCode.isNotEmpty)
                    _MetaChip(
                      icon: Icons.pin_outlined,
                      label: 'PIN ${login.loginCode}',
                    ),
                  if (_desktopAccess == true)
                    const _MetaChip(
                      icon: Icons.desktop_windows_outlined,
                      label: 'Desktop Access',
                    ),
                  if (_mobileAccess == true)
                    const _MetaChip(
                      icon: Icons.smartphone_outlined,
                      label: 'Mobile Access',
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ErpDialogSectionCard(
          title: 'Manage',
          child: Column(
            children: [
              _ActionRow(
                icon: Icons.key_outlined,
                label: 'Reset password',
                subtitle: 'Set a new sign-in password.',
                onTap: auth.can('users.manage_permissions')
                    ? () => _showResetPassword(context, userId, widget.emp.name)
                    : null,
              ),
              _ActionRow(
                icon: Icons.devices_other_outlined,
                label: 'Sessions',
                subtitle: 'See where they’re signed in and revoke access.',
                onTap: auth.can('sessions.manage')
                    ? () => _showSessions(context, userId, widget.emp.name)
                    : null,
              ),
              _ActionRow(
                icon: Icons.tune_outlined,
                label: 'Permissions & access',
                subtitle: 'Edit permissions, incl. desktop / mobile access.',
                onTap: auth.can('users.manage_permissions')
                    ? () async {
                        await showPermissionsEditor(
                          context,
                          userId: userId,
                          displayName: widget.emp.name,
                        );
                        _loadAccessFlags();
                      }
                    : null,
              ),
              _ActionRow(
                icon: isActive
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline,
                label: isActive ? 'Deactivate login' : 'Activate login',
                subtitle: isActive
                    ? 'Block sign-in without deleting the account.'
                    : 'Allow this person to sign in again.',
                onTap: auth.can('users.update_status') && !_busy
                    ? () => _guard(
                        () =>
                            auth.setUserActive(userId: userId, active: !isActive),
                        isActive ? 'Login deactivated.' : 'Login activated.',
                      )
                    : null,
              ),
              _ActionRow(
                icon: Icons.link_off_outlined,
                label: 'Unlink login',
                subtitle: 'Detach the account from this person (account kept).',
                onTap: !provider.isSaving
                    ? () => _guard(
                        () => provider.unlinkEmployeeLogin(widget.emp.id),
                        'Login unlinked (the account was kept).',
                      )
                    : null,
              ),
              _ActionRow(
                icon: Icons.delete_forever_outlined,
                label: 'Delete account',
                subtitle: 'Permanently remove the login. This cannot be undone.',
                danger: true,
                onTap: auth.can('users.manage_permissions')
                    ? () => _confirmDeleteAccount(
                        context,
                        userId,
                        widget.emp.id,
                        widget.emp.name,
                      )
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ErpDialogSectionCard(
          title: 'Track',
          subtitle:
              'Everything ${widget.emp.name} has changed across the app.',
          child: TrackPanel.actor(actorUserId: userId, showHeader: false),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Account action dialogs — ported from the (now-removed) Users tab, keyed on
// the person's linked userId.
// ---------------------------------------------------------------------------

Future<void> _showResetPassword(
  BuildContext context,
  int userId,
  String name,
) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Reset password for $name'),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'New password'),
          obscureText: true,
          validator: (value) => (value == null || value.trim().length < 8)
              ? 'Use at least 8 characters.'
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            if (!formKey.currentState!.validate()) return;
            final auth = dialogContext.read<AuthProvider>();
            final ok = await auth.resetPassword(
              userId: userId,
              password: controller.text,
            );
            if (dialogContext.mounted && ok) Navigator.of(dialogContext).pop();
            showGlobalToast(
              ok ? 'Password reset.' : (auth.errorMessage ?? 'Reset failed.'),
              kind: ok ? AppToastKind.success : AppToastKind.error,
            );
          },
          child: const Text('Reset'),
        ),
      ],
    ),
  );
  controller.dispose();
}

Future<void> _showSessions(
  BuildContext context,
  int userId,
  String name,
) async {
  final auth = context.read<AuthProvider>();
  final sessions = await auth.getUserSessions(userId);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Sessions for $name'),
      content: SizedBox(
        width: 560,
        child: sessions.isEmpty
            ? const Text('No sessions found.')
            : ListView(
                shrinkWrap: true,
                children: sessions
                    .map(
                      (session) => ListTile(
                        dense: true,
                        title: Text(session.isActive ? 'Active' : 'Revoked'),
                        subtitle: Text(
                          '${session.ipAddress.isEmpty ? 'Unknown IP' : session.ipAddress}'
                          ' • '
                          '${session.userAgent.isEmpty ? 'Unknown agent' : session.userAgent}',
                        ),
                        trailing: Text(
                          session.createdAt
                              .toLocal()
                              .toString()
                              .split('.')
                              .first,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
        FilledButton.tonal(
          onPressed: () async {
            final ok = await auth.revokeAllUserSessions(userId);
            if (dialogContext.mounted && ok) Navigator.of(dialogContext).pop();
            showGlobalToast(
              ok
                  ? 'All sessions revoked.'
                  : (auth.errorMessage ?? 'Could not revoke sessions.'),
              kind: ok ? AppToastKind.success : AppToastKind.error,
            );
          },
          child: const Text('Revoke all'),
        ),
      ],
    ),
  );
}

Future<void> _confirmDeleteAccount(
  BuildContext context,
  int userId,
  int employeeId,
  String name,
) async {
  bool override = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (c, setLocal) => AlertDialog(
        title: Text('Delete login for $name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This permanently deletes the login account. The person record '
              'stays; only their ability to sign in is removed. A backup is '
              'taken. This can break dependencies.',
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              title: const Text('Confirm permanent deletion'),
              value: override,
              onChanged: (v) => setLocal(() => override = v ?? false),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: override
                ? () async {
                    final auth = dialogContext.read<AuthProvider>();
                    final departments = dialogContext
                        .read<DepartmentsProvider>();
                    final ok = await auth.deleteUser(
                      userId: userId,
                      override: override,
                    );
                    if (ok) {
                      // Clear the dangling link so the profile reflects it.
                      await departments.unlinkEmployeeLogin(employeeId);
                    }
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    showGlobalToast(
                      ok
                          ? 'Login account deleted.'
                          : (auth.errorMessage ?? 'Delete failed.'),
                      kind: ok ? AppToastKind.success : AppToastKind.error,
                    );
                  }
                : null,
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete account'),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Small shared widgets
// ---------------------------------------------------------------------------

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = danger ? const Color(0xFFD64545) : SoftErpTheme.textPrimary;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, size: 20, color: danger ? color : SoftErpTheme.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: SoftErpTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (enabled)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: SoftErpTheme.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5FA),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: SoftErpTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.controller,
    required this.label,
    this.obscure = false,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: _fieldDecoration(label),
    );
  }
}

InputDecoration _fieldDecoration(String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: const Color(0xFFF9FAFB),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
    ),
  );
}

/// The DDMM login code (day + month of DOB), or null if the DOB isn't set.
String? _ddmm(String dob) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(dob.trim());
  return m == null ? null : '${m.group(3)}${m.group(2)}';
}
