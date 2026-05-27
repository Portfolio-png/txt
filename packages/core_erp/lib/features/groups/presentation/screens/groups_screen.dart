import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/soft_master_data.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../../units/domain/unit_definition.dart';
import '../../../units/presentation/providers/units_provider.dart';
import '../../domain/group_definition.dart';
import '../providers/groups_provider.dart';
import '../widgets/structured_group_editor_dialog.dart';

class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<GroupsProvider, UnitsProvider>(
      builder: (context, groups, units, _) {
        if ((groups.isLoading && groups.groups.isEmpty) ||
            (units.isLoading && units.units.isEmpty)) {
          return const Center(child: CircularProgressIndicator());
        }

        return SoftMasterDataPage(
          title: 'Groups',
          subtitle:
              'Create hierarchical groups and map each one to a reusable unit from Configurator Units.',
          action: AppButton(
            label: 'Add Group',
            icon: Icons.add,
            isLoading: groups.isSaving,
            onPressed: () => openEditor(context),
          ),
          toolbar: const _GroupsToolbar(),
          messages: [
            if (groups.errorMessage != null)
              _GroupsMessageBanner(
                message: groups.errorMessage!,
                isError: true,
              ),
          ],
          body: groups.filteredGroups.isEmpty
              ? const AppEmptyState(
                  title: 'No groups found',
                  message:
                      'Create a top-level group like Paper, then add child groups beneath it as needed.',
                  icon: Icons.grid_view_outlined,
                )
              : _GroupsTable(groups: groups.filteredGroups),
        );
      },
    );
  }

  static Future<GroupDefinition?> openEditor(
    BuildContext context, {
    GroupDefinition? group,
    String initialName = '',
  }) {
    return StructuredGroupEditorDialog.open(
      context,
      group: group,
      initialName: initialName,
      createMode: StructuredGroupEditorCreateMode.groupsOnly,
    );
  }
}

class _GroupsToolbar extends StatelessWidget {
  const _GroupsToolbar();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GroupsProvider>();
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    return SoftMasterToolbar(
      children: [
        if (!isDesktop)
          SoftMasterSearchField(
            width: 300,
            hintText: 'Search groups or parent groups',
            onChanged: provider.setSearchQuery,
          ),
        SoftSegmentedFilter<GroupStatusFilter>(
          selected: provider.statusFilter,
          onChanged: provider.setStatusFilter,
          options: const [
            SoftSegmentOption<GroupStatusFilter>(
              value: GroupStatusFilter.active,
              label: 'Active',
            ),
            SoftSegmentOption<GroupStatusFilter>(
              value: GroupStatusFilter.archived,
              label: 'Archived',
            ),
            SoftSegmentOption<GroupStatusFilter>(
              value: GroupStatusFilter.all,
              label: 'All',
            ),
          ],
        ),
      ],
    );
  }
}

class _GroupsTable extends StatelessWidget {
  const _GroupsTable({required this.groups});

  final List<GroupDefinition> groups;

  @override
  Widget build(BuildContext context) {
    return SoftMasterTable(
      minWidth: 980,
      columns: const [
        SoftTableColumn('Name', flex: 3),
        SoftTableColumn('Parent Group', flex: 2),
        SoftTableColumn('Unit', flex: 2),
        SoftTableColumn('Status', flex: 1),
        SoftTableColumn('Actions', flex: 2),
      ],
      itemCount: groups.length,
      rowBuilder: (context, index) => _GroupRow(group: groups[index]),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group});

  final GroupDefinition group;

  @override
  Widget build(BuildContext context) {
    final groupsProvider = context.watch<GroupsProvider>();
    final unitsProvider = context.watch<UnitsProvider>();
    final parentName =
        groupsProvider.parentNameFor(group.parentGroupId) ?? 'Primary Group';
    final unitName =
        _unitLabel(unitsProvider.units, group.unitId) ?? 'Unknown unit';

    return SoftMasterRow(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SoftInlineText(group.name, weight: FontWeight.w700),
              if (group.usageCount > 0) ...[
                const SizedBox(height: 4),
                SoftInlineText(
                  'Used in ${group.usageCount} records',
                  color: SoftErpTheme.textSecondary,
                ),
              ],
            ],
          ),
        ),
        Expanded(flex: 2, child: SoftInlineText(parentName)),
        Expanded(flex: 2, child: SoftInlineText(unitName)),
        Expanded(
          flex: 1,
          child: SoftStatusPill(
            label: group.isArchived ? 'Archived' : 'Active',
            background: group.isArchived
                ? const Color(0xFFF3F4F6)
                : const Color(0xFFECFDF5),
            textColor: group.isArchived
                ? const Color(0xFF6B7280)
                : const Color(0xFF0F766E),
            borderColor: group.isArchived
                ? const Color(0xFFE5E7EB)
                : const Color(0xFFBFEAD8),
          ),
        ),
        Expanded(
          flex: 2,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SoftActionLink(
                label: 'Edit',
                onTap: () => GroupsScreen.openEditor(context, group: group),
              ),
              SoftActionLink(
                label: group.isArchived ? 'Restore' : 'Archive',
                onTap: groupsProvider.isSaving
                    ? null
                    : () {
                        if (group.isArchived) {
                          groupsProvider.restoreGroup(group.id);
                        } else {
                          groupsProvider.archiveGroup(group.id);
                        }
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }

  String? _unitLabel(List<UnitDefinition> units, int unitId) {
    final unit = units.where((entry) => entry.id == unitId).firstOrNull;
    return unit?.displayLabel;
  }
}

class _GroupsMessageBanner extends StatelessWidget {
  const _GroupsMessageBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0),
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isError ? const Color(0xFFB91C1C) : const Color(0xFF065F46),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
