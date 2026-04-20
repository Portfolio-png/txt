import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/auth_user.dart';
import '../providers/auth_provider.dart';

String? _passwordPolicyValidator(String? value, {String email = ''}) {
  final password = (value ?? '').trim();
  if (password.length < 10) {
    return AuthProvider.passwordPolicyMessage;
  }
  if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
      !RegExp(r'[0-9]').hasMatch(password)) {
    return AuthProvider.passwordPolicyMessage;
  }
  final prefix = email.trim().toLowerCase().split('@').first;
  if (prefix.length >= 3 && password.toLowerCase().contains(prefix)) {
    return AuthProvider.passwordPolicyMessage;
  }
  final weak = <String>{
    'password',
    'password123',
    '123456',
    '12345678',
    '123456789',
    'qwerty',
    'qwerty123',
    'admin',
    'admin123',
    'paper',
    'paper123',
    'letmein',
  };
  if (weak.contains(password.toLowerCase())) {
    return AuthProvider.passwordPolicyMessage;
  }
  return null;
}

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().loadManagementData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.canAccessUserManagement) {
      return const Center(child: Text('You do not have access to this area.'));
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'User Management',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: auth.isLoading
                  ? null
                  : () => auth.loadManagementData(),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: auth.can('users.create_user')
                  ? () => _openCreateUserDialog(context, admin: false)
                  : null,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('New User'),
            ),
            if (auth.can('users.create_admin')) ...[
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: () => _openCreateUserDialog(context, admin: true),
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('New Admin'),
              ),
            ],
          ],
        ),
        if (auth.errorMessage != null) ...[
          const SizedBox(height: 16),
          _InlineError(message: auth.errorMessage!),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Search users',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => context
                    .read<AuthProvider>()
                    .updateUserFilters(query: value),
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                initialValue: auth.userRoleFilter.isEmpty
                    ? ''
                    : auth.userRoleFilter,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('All Roles')),
                  DropdownMenuItem(
                    value: 'super_admin',
                    child: Text('Super Admin'),
                  ),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  DropdownMenuItem(value: 'user', child: Text('User')),
                ],
                onChanged: (value) => context
                    .read<AuthProvider>()
                    .updateUserFilters(role: value ?? ''),
              ),
            ),
            if (auth.can('delete_requests.review'))
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  initialValue: auth.deleteStatusFilter,
                  decoration: const InputDecoration(
                    labelText: 'Delete Requests',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(
                      value: 'approved',
                      child: Text('Approved'),
                    ),
                    DropdownMenuItem(
                      value: 'rejected',
                      child: Text('Rejected'),
                    ),
                  ],
                  onChanged: (value) => context
                      .read<AuthProvider>()
                      .updateDeleteRequestFilter(value ?? 'pending'),
                ),
              ),
            if (auth.can('audit.read'))
              SizedBox(
                width: 240,
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Security Event Type',
                    hintText: 'login_success, password_reset...',
                  ),
                  onChanged: (value) =>
                      context.read<AuthProvider>().updateEventTypeFilter(value),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (auth.can('users.read')) ...[
          _Section(
            title:
                'Accounts (${auth.users.length}/${auth.usersTotal}${auth.usersHasMore ? '+' : ''})',
            child: auth.users.isEmpty
                ? const _EmptyBlock('No users loaded yet.')
                : Column(
                    children: auth.users
                        .map((user) => _UserRow(user: user))
                        .toList(growable: false),
                  ),
          ),
          const SizedBox(height: 20),
        ],
        if (auth.can('delete_requests.review')) ...[
          _Section(
            title:
                'Delete Requests (${auth.deleteRequests.length}/${auth.deleteRequestsTotal}${auth.deleteRequestsHasMore ? '+' : ''})',
            child: auth.deleteRequests.isEmpty
                ? const _EmptyBlock('No delete requests for this filter.')
                : Column(
                    children: auth.deleteRequests
                        .map((request) => _DeleteRequestRow(request: request))
                        .toList(growable: false),
                  ),
          ),
          const SizedBox(height: 20),
        ],
        if (auth.can('audit.read'))
          _Section(
            title:
                'Security Activity (${auth.authEvents.length}/${auth.authEventsTotal}${auth.authEventsHasMore ? '+' : ''})',
            child: auth.authEvents.isEmpty
                ? const _EmptyBlock('No security events yet.')
                : Column(
                    children: auth.authEvents
                        .map(
                          (event) => ListTile(
                            dense: true,
                            title: Text(event.eventType.replaceAll('_', ' ')),
                            subtitle: Text(
                              '${event.actorUserName.ifEmpty('System')} -> ${event.targetUserName.ifEmpty('-')}',
                            ),
                            trailing: Text(
                              _timeLabel(event.createdAt),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
          ),
      ],
    );
  }

  String _timeLabel(DateTime value) {
    final local = value.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hh:$mm';
  }

  Future<void> _openCreateUserDialog(
    BuildContext context, {
    required bool admin,
  }) async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(admin ? 'Register admin' : 'Register user'),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a name.'
                      : null,
                ),
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter an email.'
                      : null,
                ),
                TextFormField(
                  controller: passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  validator: (value) => _passwordPolicyValidator(
                    value,
                    email: emailController.text,
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
              if (!formKey.currentState!.validate()) {
                return;
              }
              final ok = await context.read<AuthProvider>().createUser(
                name: nameController.text,
                email: emailController.text,
                password: passwordController.text,
                admin: admin,
              );
              if (ok && dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canManageTarget =
        user.id != auth.user?.id && (auth.isSuperAdmin || user.role == 'user');
    final canResetPassword =
        canManageTarget && auth.can('users.reset_password');
    final canToggleStatus = canManageTarget && auth.can('users.update_status');
    final canSeeSessions = canManageTarget && auth.can('sessions.manage');
    final canEditPermissions =
        canManageTarget &&
        auth.can('users.manage_permissions') &&
        user.role != 'super_admin';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: CircleAvatar(
        child: Icon(user.role == 'user' ? Icons.person : Icons.shield),
      ),
      title: Text(user.name),
      subtitle: Text('${user.email} • ${user.role}'),
      trailing: Wrap(
        spacing: 8,
        children: [
          Chip(
            label: Text(user.isActive ? 'Active' : 'Inactive'),
            backgroundColor: user.isActive
                ? const Color(0xFFE7F8EF)
                : const Color(0xFFFEECEC),
          ),
          OutlinedButton(
            onPressed: canResetPassword
                ? () => _resetPassword(context, user)
                : null,
            child: const Text('Reset password'),
          ),
          OutlinedButton(
            onPressed: canSeeSessions
                ? () => _openSessions(context, user)
                : null,
            child: const Text('Sessions'),
          ),
          OutlinedButton(
            onPressed: canEditPermissions
                ? () => _openPermissions(context, user)
                : null,
            child: const Text('Permissions'),
          ),
          OutlinedButton(
            onPressed: canToggleStatus
                ? () => auth.setUserActive(
                    userId: user.id,
                    active: !user.isActive,
                  )
                : null,
            child: Text(user.isActive ? 'Deactivate' : 'Activate'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetPassword(BuildContext context, AuthUser user) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Reset password for ${user.name}'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'New password'),
            obscureText: true,
            validator: (value) =>
                _passwordPolicyValidator(value, email: user.email),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) {
                return;
              }
              final ok = await context.read<AuthProvider>().resetPassword(
                userId: user.id,
                password: controller.text,
              );
              if (ok && dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _openSessions(BuildContext context, AuthUser user) async {
    final sessions = await context.read<AuthProvider>().getUserSessions(
      user.id,
    );
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Sessions for ${user.name}'),
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
                            '${session.ipAddress.ifEmpty('Unknown IP')} • ${session.userAgent.ifEmpty('Unknown agent')}',
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
              final ok = await context
                  .read<AuthProvider>()
                  .revokeAllUserSessions(user.id);
              if (ok && dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Revoke all'),
          ),
        ],
      ),
    );
  }

  Future<void> _openPermissions(BuildContext context, AuthUser user) async {
    final auth = context.read<AuthProvider>();
    final states = await auth.getUserPermissions(user.id);
    final selectedTemplateIds = await auth.getUserPermissionTemplateIds(
      user.id,
    );
    if (!context.mounted) {
      return;
    }
    final catalog = auth.permissionDescriptors;
    final templates = auth.permissionTemplates;
    if (catalog.isEmpty || states.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            auth.errorMessage ?? 'No editable permissions were returned.',
          ),
        ),
      );
      return;
    }
    final sortedStates = [...states]..sort((a, b) => a.key.compareTo(b.key));
    final toggles = <String, bool>{
      for (final state in sortedStates) state.key: state.allowed,
    };
    final assignedTemplates = <int>{...selectedTemplateIds};
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
          title: Text('Permissions for ${user.name}'),
          content: SizedBox(
            width: 600,
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 4, 4, 10),
                  child: Text(
                    'Permission Templates',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                ...templates.map((template) {
                  return CheckboxListTile(
                    value: assignedTemplates.contains(template.id),
                    onChanged: (value) {
                      setStateDialog(() {
                        if (value == true) {
                          assignedTemplates.add(template.id);
                        } else {
                          assignedTemplates.remove(template.id);
                        }
                      });
                    },
                    title: Text(template.name),
                    subtitle: Text(template.description),
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                }),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 6, 4, 10),
                  child: Text(
                    'Advanced Permission Overrides',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                ...sortedStates.map((state) {
                  PermissionDescriptor? descriptor;
                  for (final item in catalog) {
                    if (item.key == state.key) {
                      descriptor = item;
                      break;
                    }
                  }
                  return CheckboxListTile(
                    value: toggles[state.key] ?? false,
                    onChanged: (value) {
                      setStateDialog(() {
                        toggles[state.key] = value == true;
                      });
                    },
                    title: Text(descriptor?.label ?? state.key),
                    subtitle: Text(descriptor?.description ?? state.key),
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                }),
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
                final templatesSaved = await auth.updateUserPermissionTemplates(
                  userId: user.id,
                  templateIds: assignedTemplates.toList(growable: false),
                );
                if (!templatesSaved) {
                  return;
                }
                final nextStates = sortedStates
                    .map(
                      (state) => UserPermissionState(
                        key: state.key,
                        allowed: toggles[state.key] ?? state.allowed,
                        source: state.source,
                      ),
                    )
                    .toList(growable: false);
                final ok = await auth.updateUserPermissions(
                  userId: user.id,
                  states: nextStates,
                );
                if (ok && dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteRequestRow extends StatelessWidget {
  const _DeleteRequestRow({required this.request});

  final DeleteRequest request;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final isPending = request.status == 'pending';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: const CircleAvatar(child: Icon(Icons.delete_outline)),
      title: Text(
        request.entityLabel.isEmpty ? request.entityId : request.entityLabel,
      ),
      subtitle: Text(
        isPending
            ? 'Requested by ${request.requestedByName.ifEmpty('Unknown')} • ${request.reason.ifEmpty('No reason provided')}'
            : 'Requested by ${request.requestedByName.ifEmpty('Unknown')} • ${request.status} by ${request.reviewedByName.ifEmpty('Unknown')} • ${request.reviewedNote.ifEmpty('No note')}',
      ),
      trailing: Wrap(
        spacing: 8,
        children: [
          if (isPending) ...[
            OutlinedButton(
              onPressed: () => _review(context, auth, approve: false),
              child: const Text('Reject'),
            ),
            FilledButton(
              onPressed: () => _review(context, auth, approve: true),
              child: const Text('Approve'),
            ),
          ] else
            Chip(label: Text(request.status.toUpperCase())),
        ],
      ),
    );
  }

  Future<void> _review(
    BuildContext context,
    AuthProvider auth, {
    required bool approve,
  }) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          approve ? 'Approve delete request' : 'Reject delete request',
        ),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reviewer note',
            hintText: 'Optional note for audit history.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (ok != true) {
      controller.dispose();
      return;
    }
    await auth.reviewDeleteRequest(
      request.id,
      approve: approve,
      reviewedNote: controller.text,
    );
    controller.dispose();
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE1E5ED)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const Divider(height: 1),
          child,
        ],
      ),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Text(message, style: const TextStyle(color: Color(0xFF6B7280))),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEECEC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFFB42318))),
    );
  }
}

extension _StringFallback on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
