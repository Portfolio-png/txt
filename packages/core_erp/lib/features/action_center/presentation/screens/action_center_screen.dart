import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/navigation/app_navigation.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/soft_master_data.dart';
import '../../../auth/domain/auth_user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/action_center_models.dart';
import '../providers/action_center_provider.dart';

enum _AcView { requests, issues, trash }

/// Maps the table that owns a broken reference to the sidebar nav key of the
/// screen where the user can fix it (the "Resolve" action). Tables with no
/// dedicated editor screen are omitted (Resolve is hidden for them).
const Map<String, String> _ownerNavKeys = {
  'items': 'configurator_items',
  'groups': 'configurator_groups',
  'order_items': 'orders',
  'delivery_challans': 'delivery_challans',
  'inventory_movements': 'inventory',
};

class ActionCenterScreen extends StatefulWidget {
  const ActionCenterScreen({super.key});

  @override
  State<ActionCenterScreen> createState() => _ActionCenterScreenState();
}

class _ActionCenterScreenState extends State<ActionCenterScreen> {
  _AcView _view = _AcView.issues;

  @override
  void initState() {
    super.initState();
    // Refresh every time the screen opens so data is never stale across sessions.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ActionCenterProvider>().refresh();
      // Pending delete requests live on AuthProvider; pull just that queue.
      context.read<AuthProvider>().refreshDeleteRequests();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ActionCenterProvider, AuthProvider>(
      builder: (context, provider, auth, _) {
        final canReview = auth.can('delete_requests.review');
        // Non-reviewers never see the Requests segment; keep them on a valid tab.
        if (!canReview && _view == _AcView.requests) {
          _view = _AcView.issues;
        }
        return SoftMasterDataPage(
          title: 'Action Center',
          subtitle:
              'Review pending delete requests, recover deleted records from the trash, and resolve broken references left behind by hard deletes.',
          action: AppButton(
            label: 'Refresh',
            icon: Icons.refresh,
            isLoading: provider.isLoading,
            onPressed: () {
              provider.refresh();
              auth.refreshDeleteRequests();
            },
          ),
          toolbar: SoftMasterToolbar(
            children: [
              SoftSegmentedFilter<_AcView>(
                selected: _view,
                onChanged: (value) => setState(() => _view = value),
                options: [
                  if (canReview)
                    SoftSegmentOption(
                      value: _AcView.requests,
                      label: 'Delete Requests',
                      count: auth.deleteRequests.length,
                    ),
                  SoftSegmentOption(
                    value: _AcView.issues,
                    label: 'Issues',
                    count: provider.issues.length,
                  ),
                  SoftSegmentOption(
                    value: _AcView.trash,
                    label: 'Trash Bin',
                    count: provider.trash.length,
                  ),
                ],
              ),
              if (_view == _AcView.issues && provider.issues.isNotEmpty)
                _CountPill(
                  errors: provider.errorCount,
                  warnings: provider.warningCount,
                ),
            ],
          ),
          messages: [
            if (provider.errorMessage != null)
              _Banner(message: provider.errorMessage!),
            if (auth.errorMessage != null && _view == _AcView.requests)
              _Banner(message: auth.errorMessage!),
          ],
          body: _buildBody(context, provider, auth),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    ActionCenterProvider provider,
    AuthProvider auth,
  ) {
    if (provider.isLoading && !provider.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    switch (_view) {
      case _AcView.requests:
        return _buildRequests(context, auth);
      case _AcView.issues:
        return _buildIssues(context, provider);
      case _AcView.trash:
        return _buildTrash(context, provider);
    }
  }

  Widget _buildRequests(BuildContext context, AuthProvider auth) {
    final requests = auth.deleteRequests;
    if (requests.isEmpty) {
      return const AppEmptyState(
        icon: Icons.task_alt_outlined,
        title: 'No pending delete requests',
        message:
            'When someone requests a deletion that needs approval, it '
            'shows up here for review.',
      );
    }
    return ListView.separated(
      itemCount: requests.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final request = requests[index];
        return _DeleteRequestCard(
          request: request,
          onApprove: () => _review(context, auth, request, approve: true),
          onReject: () => _review(context, auth, request, approve: false),
        );
      },
    );
  }

  Future<void> _review(
    BuildContext context,
    AuthProvider auth,
    DeleteRequest request, {
    required bool approve,
  }) async {
    final note = await _promptReviewNote(context, approve: approve);
    if (note == null) return; // cancelled
    if (!context.mounted) return;
    final ok = await auth.reviewDeleteRequest(
      request.id,
      approve: approve,
      reviewedNote: note,
    );
    if (!context.mounted) return;
    showGlobalToast(
      ok
          ? (approve
                ? 'Approved deletion of ${request.entityLabel}.'
                : 'Rejected deletion of ${request.entityLabel}.')
          : (auth.errorMessage ?? 'Could not update the request.'),
      kind: ok ? AppToastKind.success : AppToastKind.error,
    );
  }

  Future<String?> _promptReviewNote(
    BuildContext context, {
    required bool approve,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(approve ? 'Approve deletion' : 'Reject deletion'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'Optional note kept on the request for tracking.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(approve ? 'Approve' : 'Reject'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildIssues(BuildContext context, ActionCenterProvider provider) {
    if (provider.issues.isEmpty) {
      return const AppEmptyState(
        icon: Icons.verified_outlined,
        title: 'No broken references',
        message: 'Every record points to something that still exists.',
      );
    }
    return ListView.separated(
      itemCount: provider.issues.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final issue = provider.issues[index];
        return _IssueCard(
          issue: issue,
          restoring: provider.isRestoring(issue.brokenTable, issue.brokenId),
          onRevert: () => _revert(context, provider, issue),
          onResolve: _ownerNavKeys.containsKey(issue.ownerTable)
              ? () => _resolve(context, issue)
              : null,
        );
      },
    );
  }

  Widget _buildTrash(BuildContext context, ActionCenterProvider provider) {
    if (provider.trash.isEmpty) {
      return const AppEmptyState(
        icon: Icons.delete_outline,
        title: 'Trash is empty',
        message: 'Deleted records will appear here and can be restored.',
      );
    }
    return ListView.separated(
      itemCount: provider.trash.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final record = provider.trash[index];
        return _TrashCard(
          record: record,
          restoring: provider.isRestoring(record.tableName, record.recordId),
          onRestore: () => _restore(
            context,
            provider,
            record.tableName,
            record.recordId,
            record.label,
          ),
        );
      },
    );
  }

  Future<void> _revert(
    BuildContext context,
    ActionCenterProvider provider,
    ActionCenterIssue issue,
  ) async {
    final ok = await provider.restore(issue.brokenTable, issue.brokenId);
    if (!context.mounted) return;
    showGlobalToast(
      ok
          ? 'Restored ${issue.brokenLabel}.'
          : (provider.errorMessage ?? 'Could not restore the record.'),
      kind: ok ? AppToastKind.success : AppToastKind.error,
    );
  }

  Future<void> _restore(
    BuildContext context,
    ActionCenterProvider provider,
    String tableName,
    int recordId,
    String label,
  ) async {
    final ok = await provider.restore(tableName, recordId);
    if (!context.mounted) return;
    showGlobalToast(
      ok
          ? 'Restored $label.'
          : (provider.errorMessage ?? 'Could not restore the record.'),
      kind: ok ? AppToastKind.success : AppToastKind.error,
    );
  }

  void _resolve(BuildContext context, ActionCenterIssue issue) {
    final navKey = _ownerNavKeys[issue.ownerTable];
    if (navKey == null) return;
    context.read<AppNavigation>().select(navKey);
  }
}

class _IssueCard extends StatelessWidget {
  const _IssueCard({
    required this.issue,
    required this.restoring,
    required this.onRevert,
    this.onResolve,
  });

  final ActionCenterIssue issue;
  final bool restoring;
  final VoidCallback onRevert;
  final VoidCallback? onResolve;

  @override
  Widget build(BuildContext context) {
    final color = issue.isError
        ? const Color(0xFFD64545)
        : const Color(0xFFB8860B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        children: [
          Icon(
            issue.isError ? Icons.error_outline : Icons.warning_amber_rounded,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SoftInlineText(issue.ownerLabel, weight: FontWeight.w700),
                const SizedBox(height: 3),
                Text(
                  'References a missing ${issue.brokenLabel} (via ${issue.brokenField})',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (onResolve != null) ...[
            SoftActionLink(label: 'Resolve', onTap: onResolve),
            const SizedBox(width: 8),
          ],
          restoring
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : SoftActionLink(label: 'Revert', onTap: onRevert),
        ],
      ),
    );
  }
}

class _TrashCard extends StatelessWidget {
  const _TrashCard({
    required this.record,
    required this.restoring,
    required this.onRestore,
  });

  final TrashedRecord record;
  final bool restoring;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.restore_from_trash_outlined,
            color: SoftErpTheme.textSecondary,
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SoftInlineText(record.label, weight: FontWeight.w700),
                const SizedBox(height: 3),
                Text(
                  '${record.tableName} · deleted by ${record.deletedBy}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          restoring
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : SoftActionLink(label: 'Restore', onTap: onRestore),
        ],
      ),
    );
  }
}

class _DeleteRequestCard extends StatelessWidget {
  const _DeleteRequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  final DeleteRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final requester = request.requestedByName.trim().isEmpty
        ? 'Someone'
        : request.requestedByName.trim();
    final parts = <String>[
      'Requested by $requester',
      if (request.entityType.trim().isNotEmpty) request.entityType.trim(),
      if (request.reason.trim().isNotEmpty) request.reason.trim(),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.delete_forever_outlined,
            color: Color(0xFFD64545),
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SoftInlineText(request.entityLabel, weight: FontWeight.w700),
                const SizedBox(height: 3),
                Text(
                  parts.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SoftActionLink(label: 'Reject', onTap: onReject),
          const SizedBox(width: 8),
          SoftActionLink(label: 'Approve', onTap: onApprove),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.errors, required this.warnings});

  final int errors;
  final int warnings;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$errors error${errors == 1 ? '' : 's'} · $warnings warning${warnings == 1 ? '' : 's'}',
      style: const TextStyle(
        color: SoftErpTheme.textSecondary,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF3C0C0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFD64545), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF8A2E2E),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
