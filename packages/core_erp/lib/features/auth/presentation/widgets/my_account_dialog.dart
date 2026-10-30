import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/utils/stamp_format.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../domain/auth_user.dart';
import '../providers/auth_provider.dart';
import 'account_access_widgets.dart';
import 'permissions_editor.dart';
import 'track_panel.dart';

/// Your own Account & Access, from the profile chip.
///
/// The same panel People shows for a person — the Account card, Manage, Track
/// — about the one signed in, and with the actions that make sense on
/// yourself: change your password (with the current one), see and sign out
/// your sessions, see what you may do. The actions only another admin can take
/// (deactivate, unlink, delete) stay in the list, disabled, saying so — the
/// server refuses them on yourself anyway.
class MyAccountDialog extends StatelessWidget {
  const MyAccountDialog({super.key});

  static Future<void> open(BuildContext context) => showErpFormDialog<void>(
        context,
        maxWidth: 960,
        maxHeight: 900,
        child: const MyAccountDialog(),
      );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    void close() => Navigator.of(context).maybePop();
    if (user == null) {
      return ErpFormScaffold(
        title: 'Account & Access',
        onClose: close,
        body: const Text('Sign in to see your account.'),
        footer: Align(
          alignment: Alignment.centerRight,
          child: AppButton(label: 'Done', onPressed: close),
        ),
      );
    }
    return ErpFormScaffold(
      onClose: close,
      leading: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: SoftErpTheme.accentSoft,
          border: Border.all(color: SoftErpTheme.borderStrong, width: 2),
        ),
        child: const Icon(Icons.person, color: SoftErpTheme.accentDark, size: 27),
      ),
      title: 'Account & Access',
      subtitle: 'Manage your login, access, and security.',
      body: _MyAccountBody(user: user),
      footer: Align(
        alignment: Alignment.centerRight,
        child: AppButton(key: const ValueKey<String>('my-account-done'), label: 'Done', onPressed: close),
      ),
    );
  }
}

class _MyAccountBody extends StatelessWidget {
  const _MyAccountBody({required this.user});

  final AuthUser user;

  static const String _onlyAnotherAdmin = 'Another admin does this — you can\'t';

  @override
  Widget build(BuildContext context) {
    final pin = user.mobilePin?.trim() ?? '';
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
                          user.email.isEmpty ? '(no email)' : user.email,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: SoftErpTheme.textPrimary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${user.name.isEmpty ? 'You' : user.name} · ${_roleLabel(user.role)}',
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
                    label: user.isActive ? 'ACTIVE' : 'DISABLED',
                    background: user.isActive ? SoftErpTheme.successBg : SoftErpTheme.dangerBg,
                    textColor: user.isActive ? SoftErpTheme.successText : SoftErpTheme.dangerText,
                    borderColor: user.isActive ? SoftErpTheme.successBg : SoftErpTheme.dangerBg,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (pin.isNotEmpty) AccountMetaChip(icon: Icons.pin_outlined, label: 'PIN $pin'),
                  if (user.can('login.desktop'))
                    const AccountMetaChip(icon: Icons.desktop_windows_outlined, label: 'Desktop Access'),
                  if (user.can('login.mobile'))
                    const AccountMetaChip(icon: Icons.smartphone_outlined, label: 'Mobile Access'),
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
              AccountActionRow(
                key: const ValueKey<String>('my-account-password'),
                icon: Icons.key_outlined,
                label: 'Change password',
                subtitle: 'Set a new sign-in password, with your current one.',
                onTap: () => _showChangePassword(context),
              ),
              AccountActionRow(
                key: const ValueKey<String>('my-account-sessions'),
                icon: Icons.devices_other_outlined,
                label: 'Sessions',
                subtitle: 'See where you’re signed in and sign other devices out.',
                onTap: () => _showMySessions(context),
              ),
              AccountActionRow(
                key: const ValueKey<String>('my-account-permissions'),
                icon: Icons.tune_outlined,
                label: 'Permissions & access',
                subtitle: 'What you can do, incl. desktop / mobile access.',
                onTap: () => _showMyPermissions(context, user),
              ),
              const AccountActionRow(
                icon: Icons.pause_circle_outline,
                label: 'Deactivate login',
                subtitle: 'Block sign-in without deleting the account.',
                onTap: null,
                disabledReason: '$_onlyAnotherAdmin deactivate your own login.',
              ),
              const AccountActionRow(
                icon: Icons.link_off_outlined,
                label: 'Unlink login',
                subtitle: 'Detach the account from its person (account kept).',
                onTap: null,
                disabledReason: '$_onlyAnotherAdmin unlink your own login.',
              ),
              const AccountActionRow(
                icon: Icons.delete_forever_outlined,
                label: 'Delete account',
                subtitle: 'Permanently remove the login. This cannot be undone.',
                danger: true,
                onTap: null,
                disabledReason: '$_onlyAnotherAdmin delete your own account.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ErpDialogSectionCard(
          title: 'Track',
          subtitle: 'Everything you have changed across the app.',
          child: TrackPanel.actor(actorUserId: user.id, showHeader: false),
        ),
      ],
    );
  }
}

String _roleLabel(String role) => switch (role) {
      'super_admin' => 'Super Admin',
      'admin' => 'Admin',
      _ => 'Staff',
    };

String _humanize(String key) {
  final words = key.replaceAll('_', ' ').replaceAll('.', ' ').trim();
  if (words.isEmpty) return key;
  return words[0].toUpperCase() + words.substring(1);
}

// ---------------------------------------------------------------------------
// Change password — your own, so the current one is asked for.
// ---------------------------------------------------------------------------

Future<void> _showChangePassword(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );

/// A widget rather than a builder because of its text controllers: a dialog
/// keeps rebuilding through its exit transition, so controllers disposed on
/// the line after `await showDialog` were used after disposal. Owned here,
/// they live exactly as long as the route.
class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  String? _problem;
  bool _saving = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_current.text.isEmpty || _next.text.isEmpty) {
      setState(() => _problem = 'Fill in your current password and the new one.');
      return;
    }
    if (_next.text != _again.text) {
      setState(() => _problem = 'The two new passwords are not the same.');
      return;
    }
    setState(() {
      _saving = true;
      _problem = null;
    });
    final auth = context.read<AuthProvider>();
    final ok = await auth.changeOwnPassword(
      currentPassword: _current.text,
      newPassword: _next.text,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _saving = false;
        _problem = auth.errorMessage ?? 'The password was not changed.';
      });
      return;
    }
    Navigator.of(context).pop();
    showGlobalToast(
      'Password changed. Your other devices were signed out.',
      kind: AppToastKind.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Your other devices are signed out when it changes; this one stays signed in.',
              style: TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey<String>('my-password-current'),
              controller: _current,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey<String>('my-password-new'),
              controller: _next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey<String>('my-password-again'),
              controller: _again,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password again'),
              onSubmitted: (_) => _saving ? null : _save(),
            ),
            if (_problem != null) ...[
              const SizedBox(height: 12),
              Text(
                _problem!,
                key: const ValueKey<String>('my-password-problem'),
                style: const TextStyle(fontSize: 14, color: SoftErpTheme.dangerText),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('my-password-save'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Change password'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Your sessions — where you are signed in, and signing others out.
// ---------------------------------------------------------------------------

Future<void> _showMySessions(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  var loaded = await auth.loadMySessions();
  if (!context.mounted) return;
  if (loaded == null) {
    showGlobalToast(auth.errorMessage ?? 'Could not load your sessions.', kind: AppToastKind.error);
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final list = loaded!;
        final live = [for (final s in list.sessions) if (s.isActive) s];
        final others = [for (final s in live) if (s.id != list.currentId) s];

        Future<void> signOut(Iterable<AuthSession> which) async {
          var failed = false;
          for (final session in which) {
            failed |= !await auth.revokeOwnSession(session.id);
          }
          final fresh = await auth.loadMySessions();
          if (!dialogContext.mounted) return;
          setState(() => loaded = fresh ?? loaded);
          showGlobalToast(
            failed ? (auth.errorMessage ?? 'Some sessions were not signed out.') : 'Signed out.',
            kind: failed ? AppToastKind.error : AppToastKind.success,
          );
        }

        return AlertDialog(
          title: const Text('Your sessions'),
          content: SizedBox(
            width: 560,
            child: live.isEmpty
                ? const Text('No active sessions.')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final session in live)
                        ListTile(
                          key: ValueKey<String>('my-session-${session.id}'),
                          leading: Icon(
                            session.clientPlatform == 'mobile'
                                ? Icons.smartphone_outlined
                                : Icons.desktop_windows_outlined,
                            color: SoftErpTheme.textSecondary,
                          ),
                          title: Text(
                            '${session.clientPlatform == 'mobile' ? 'Phone' : 'Desktop'}'
                            '${session.id == list.currentId ? ' · this device' : ''}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            'Signed in ${partStamp(session.createdAt)} · '
                            '${session.ipAddress.isEmpty ? 'unknown address' : session.ipAddress}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          trailing: session.id == list.currentId
                              ? null
                              : TextButton(
                                  key: ValueKey<String>('my-session-signout-${session.id}'),
                                  onPressed: () => signOut([session]),
                                  child: const Text('Sign out'),
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
            FilledButton.tonal(
              key: const ValueKey<String>('my-sessions-signout-others'),
              onPressed: others.isEmpty ? null : () => signOut(others),
              child: const Text('Sign out all others'),
            ),
          ],
        );
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// What you can do — read-only; an admin changes it.
// ---------------------------------------------------------------------------

Future<void> _showMyPermissions(BuildContext context, AuthUser user) {
  final groups = <String, List<String>>{};
  if (user.role != 'super_admin') {
    for (final key in user.permissions) {
      final dot = key.indexOf('.');
      if (dot <= 0) continue;
      final module = key.substring(0, dot);
      final rest = key.substring(dot + 1);
      (groups[module] ??= []).add(permissionOpLabels[rest] ?? _humanize(rest));
    }
  }
  final modules = groups.keys.toList()..sort();
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Your permissions & access'),
      content: SizedBox(
        width: 520,
        child: user.role == 'super_admin'
            ? const Text(
                'Everything — you are the super admin.',
                style: TextStyle(fontSize: 15),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'An admin changes these from People → your account.',
                    style: TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  if (modules.isEmpty)
                    const Text('No permissions yet.', style: TextStyle(fontSize: 15))
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final module in modules)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text.rich(
                                TextSpan(children: [
                                  TextSpan(
                                    text: '${_humanize(module)}  ',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  TextSpan(
                                    text: groups[module]!.join(' · '),
                                    style: const TextStyle(color: SoftErpTheme.textSecondary),
                                  ),
                                ]),
                                style: const TextStyle(fontSize: 15),
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
    ),
  );
}
