import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../items/domain/item_definition.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../domain/group_definition.dart';
import '../providers/groups_provider.dart';

/// Sentinel dropdown value meaning "delete this item" (group ids are positive).
const int _kDeleteChoice = -1;

/// Confirmation flow for deleting a group. Lists the group's items, lets the
/// user relocate each to another same-type group or delete the order-free
/// ones, then deletes the (now empty) group.
///
/// ponytail: items are processed one API call each; fine for the handful a
/// group holds. Batch endpoint if a group ever holds hundreds.
class DeleteGroupDialog extends StatefulWidget {
  const DeleteGroupDialog({super.key, required this.group});

  final GroupDefinition group;

  /// Returns true if the group was deleted.
  static Future<bool> open(BuildContext context, GroupDefinition group) async {
    final result = await showErpFormDialog<bool>(
      context,
      maxWidth: 720,
      maxHeight: 760,
      child: DeleteGroupDialog(group: group),
    );
    return result ?? false;
  }

  @override
  State<DeleteGroupDialog> createState() => _DeleteGroupDialogState();
}

class _DeleteGroupDialogState extends State<DeleteGroupDialog> {
  // itemId -> chosen target group id, or _kDeleteChoice, or null (unresolved).
  final Map<int, int?> _choice = <int, int?>{};
  bool _isBusy = false;
  String? _progress;

  @override
  void initState() {
    super.initState();
    final items = _groupItems();
    for (final item in items) {
      // Free items default to delete; in-use items must be relocated (unset).
      _choice[item.id] = item.usageCount > 0 ? null : _kDeleteChoice;
    }
  }

  List<ItemDefinition> _groupItems() {
    final items = context.read<ItemsProvider>().items
        .where((item) => item.groupId == widget.group.id)
        .toList(growable: false);
    items.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return items;
  }

  List<GroupDefinition> _targetGroups() {
    return context
        .read<GroupsProvider>()
        .groups
        .where((g) =>
            g.groupType == widget.group.groupType &&
            g.id != widget.group.id &&
            !g.isArchived)
        .toList(growable: false)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  bool get _canConfirm {
    // Every in-use item must have a relocation target picked.
    return _choice.values.every((value) => value != null);
  }

  Future<void> _confirm() async {
    if (_isBusy) return;
    final items = _groupItems();
    final itemsProvider = context.read<ItemsProvider>();
    final groupsProvider = context.read<GroupsProvider>();

    setState(() => _isBusy = true);
    try {
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        final choice = _choice[item.id];
        setState(() => _progress = 'Processing ${i + 1}/${items.length}…');
        if (choice == _kDeleteChoice) {
          final ok = await itemsProvider.deleteItem(item.id);
          if (!ok) {
            _fail('Could not delete "${item.displayName}": '
                '${itemsProvider.errorMessage ?? 'unknown error'}');
            return;
          }
        } else if (choice != null) {
          final moved = await itemsProvider.reassignItemGroup(item.id, choice);
          if (moved == null) {
            _fail('Could not relocate "${item.displayName}": '
                '${itemsProvider.errorMessage ?? 'unknown error'}');
            return;
          }
        }
      }

      setState(() => _progress = 'Deleting group…');
      final deleted = await groupsProvider.deleteGroup(widget.group.id);
      if (!deleted) {
        _fail(groupsProvider.errorMessage ?? 'Could not delete group.');
        return;
      }

      if (!mounted) return;
      showAppToast(context, 'Group deleted', kind: AppToastKind.success);
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _progress = null);
    showAppToast(context, message, kind: AppToastKind.error);
  }

  @override
  Widget build(BuildContext context) {
    final items = _groupItems();
    final targets = _targetGroups();
    final inUseCount = items.where((i) => i.usageCount > 0).length;
    final blockedNoTarget = inUseCount > 0 && targets.isEmpty;

    return ErpFormScaffold(
      title: 'Delete group "${widget.group.name}"',
      subtitle: items.isEmpty
          ? 'This group has no items and can be deleted.'
          : 'Decide what happens to each item, then delete the group. '
              'Items used in orders/challans/inventory can only be relocated.',
      errorBanner: blockedNoTarget
          ? ErpFormMessageBanner(
              message:
                  'Some items are in use and there is no other ${widget.group.groupType} '
                  'group to relocate them to. Create one first.',
            )
          : null,
      body: items.isEmpty
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BulkActions(
                  targets: targets,
                  onDeleteAllUnused: _isBusy ? null : _deleteAllUnused,
                  onRelocateAll: _isBusy ? null : _relocateAllTo,
                ),
                const SizedBox(height: 12),
                for (final item in items) ...[
                  _ItemRow(
                    item: item,
                    targets: targets,
                    choice: _choice[item.id],
                    enabled: !_isBusy,
                    onChanged: (value) =>
                        setState(() => _choice[item.id] = value),
                  ),
                  const Divider(height: 1),
                ],
              ],
            ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_progress != null) ...[
            Expanded(
              child: Text(
                _progress!,
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
            ),
          ],
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: _isBusy ? null : () => Navigator.of(context).pop(false),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: 'Delete group',
            icon: Icons.delete_outline_rounded,
            isLoading: _isBusy,
            onPressed: (_canConfirm && !blockedNoTarget) ? _confirm : null,
          ),
        ],
      ),
    );
  }

  void _deleteAllUnused() {
    setState(() {
      for (final item in _groupItems()) {
        if (item.usageCount == 0) {
          _choice[item.id] = _kDeleteChoice;
        }
      }
    });
  }

  void _relocateAllTo(int groupId) {
    setState(() {
      for (final item in _groupItems()) {
        _choice[item.id] = groupId;
      }
    });
  }
}

class _BulkActions extends StatelessWidget {
  const _BulkActions({
    required this.targets,
    required this.onDeleteAllUnused,
    required this.onRelocateAll,
  });

  final List<GroupDefinition> targets;
  final VoidCallback? onDeleteAllUnused;
  final ValueChanged<int>? onRelocateAll;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (targets.isNotEmpty)
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<int>(
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Relocate all items to…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final g in targets)
                  DropdownMenuItem(value: g.id, child: Text(g.name)),
              ],
              onChanged: onRelocateAll == null
                  ? null
                  : (value) {
                      if (value != null) onRelocateAll!(value);
                    },
            ),
          ),
        TextButton.icon(
          onPressed: onDeleteAllUnused,
          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
          label: const Text('Delete all unused'),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.targets,
    required this.choice,
    required this.enabled,
    required this.onChanged,
  });

  final ItemDefinition item;
  final List<GroupDefinition> targets;
  final int? choice;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final inUse = item.usageCount > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (inUse)
                  Text(
                    'In use (${item.usageCount}) · relocate only',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFB45309),
                    ),
                  )
                else
                  const Text(
                    'Not used · can be deleted',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 240,
            child: DropdownButtonFormField<int>(
              // Re-create when the choice changes externally (bulk actions) so
              // the displayed value stays in sync with _choice.
              key: ValueKey('item-${item.id}-$choice'),
              isExpanded: true,
              initialValue: choice,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: 'Choose…',
              ),
              items: [
                if (!inUse)
                  const DropdownMenuItem(
                    value: _kDeleteChoice,
                    child: Text('Delete permanently'),
                  ),
                for (final g in targets)
                  DropdownMenuItem(
                    value: g.id,
                    child: Text('Move to ${g.name}'),
                  ),
              ],
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ],
      ),
    );
  }
}
