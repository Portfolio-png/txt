import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_section_title.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../units/domain/unit_definition.dart';
import '../../../units/presentation/providers/units_provider.dart';
import '../../../units/presentation/screens/units_screen.dart';
import '../../domain/group_definition.dart';
import '../../domain/group_inputs.dart';
import '../providers/groups_provider.dart';

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

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSectionTitle(
                title: 'Groups',
                subtitle:
                    'Create hierarchical groups and map each one to a reusable unit from Configurator Units.',
                trailing: AppButton(
                  label: 'Add Group',
                  icon: Icons.add,
                  isLoading: groups.isSaving,
                  onPressed: units.activeUnits.isEmpty
                      ? null
                      : () => _openGroupEditor(context),
                ),
              ),
              const SizedBox(height: 20),
              _GroupsToolbar(),
              if (units.activeUnits.isEmpty) ...[
                const SizedBox(height: 12),
                const _GroupsMessageBanner(
                  message:
                      'Create at least one active unit before adding groups.',
                  isError: true,
                ),
              ],
              if (groups.errorMessage != null) ...[
                const SizedBox(height: 12),
                _GroupsMessageBanner(
                  message: groups.errorMessage!,
                  isError: true,
                ),
              ],
              const SizedBox(height: 20),
              Expanded(
                child: groups.filteredGroups.isEmpty
                    ? const AppEmptyState(
                        title: 'No groups found',
                        message:
                            'Create a top-level group like Paper, then add child groups beneath it as needed.',
                        icon: Icons.grid_view_outlined,
                      )
                    : _GroupsTable(groups: groups.filteredGroups),
              ),
            ],
          ),
        );
      },
    );
  }

  static Future<GroupDefinition?> openEditor(
    BuildContext context, {
    GroupDefinition? group,
    String initialName = '',
  }) {
    final isNarrow = MediaQuery.of(context).size.width < 900;
    final body = _GroupEditorSheet(group: group, initialName: initialName);
    if (isNarrow) {
      return showModalBottomSheet<GroupDefinition?>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: body,
        ),
      );
    }

    return showDialog<GroupDefinition?>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: body,
        ),
      ),
    );
  }

  static Future<GroupDefinition?> _openGroupEditor(
    BuildContext context, {
    GroupDefinition? group,
    String initialName = '',
  }) {
    return openEditor(context, group: group, initialName: initialName);
  }
}

class _GroupsToolbar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GroupsProvider>();
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!isDesktop)
          SizedBox(
            width: 280,
            child: TextField(
              onChanged: provider.setSearchQuery,
              decoration: InputDecoration(
                hintText: 'Search groups or parent groups',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
                ),
              ),
            ),
          ),
        SegmentedButton<GroupStatusFilter>(
          segments: const [
            ButtonSegment<GroupStatusFilter>(
              value: GroupStatusFilter.active,
              label: Text('Active'),
            ),
            ButtonSegment<GroupStatusFilter>(
              value: GroupStatusFilter.archived,
              label: Text('Archived'),
            ),
            ButtonSegment<GroupStatusFilter>(
              value: GroupStatusFilter.all,
              label: Text('All'),
            ),
          ],
          selected: {provider.statusFilter},
          onSelectionChanged: (selection) {
            provider.setStatusFilter(selection.first);
          },
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
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7F0))),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: _HeaderText('Name')),
                Expanded(flex: 2, child: _HeaderText('Parent Group')),
                Expanded(flex: 2, child: _HeaderText('Unit')),
                Expanded(flex: 1, child: _HeaderText('Status')),
                Expanded(flex: 2, child: _HeaderText('Actions')),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: groups.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: Color(0xFFF1F2F7)),
              itemBuilder: (context, index) => _GroupRow(group: groups[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderText extends StatelessWidget {
  const _HeaderText(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: const Color(0xFF6B7280),
        fontWeight: FontWeight.w700,
      ),
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
        groupsProvider.parentNameFor(group.parentGroupId) ?? 'Top level';
    final unitName =
        _unitLabel(unitsProvider.units, group.unitId) ?? 'Unknown unit';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (group.usageCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Used in ${group.usageCount} records',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(flex: 2, child: Text(parentName)),
          Expanded(flex: 2, child: Text(unitName)),
          Expanded(
            flex: 1,
            child: _StatusChip(
              label: group.isArchived ? 'Archived' : 'Active',
              color: group.isArchived
                  ? const Color(0xFF9CA3AF)
                  : const Color(0xFF0F766E),
              background: group.isArchived
                  ? const Color(0xFFF3F4F6)
                  : const Color(0xFFECFDF5),
            ),
          ),
          Expanded(
            flex: 2,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ActionLink(
                  label: group.isUsed ? 'View' : 'Edit',
                  onTap: () => GroupsScreen.openEditor(context, group: group),
                ),
                _ActionLink(
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
      ),
    );
  }

  String? _unitLabel(List<UnitDefinition> units, int unitId) {
    final unit = units.where((entry) => entry.id == unitId).firstOrNull;
    return unit?.displayLabel;
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ActionLink extends StatelessWidget {
  const _ActionLink({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF6C63FF),
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}

class _GroupEditorSheet extends StatefulWidget {
  const _GroupEditorSheet({this.group, this.initialName = ''});

  final GroupDefinition? group;
  final String initialName;

  @override
  State<_GroupEditorSheet> createState() => _GroupEditorSheetState();
}

class _GroupEditorSheetState extends State<_GroupEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  int? _selectedParentId;
  int? _selectedUnitId;
  String? _localError;

  bool get _isReadOnly => widget.group?.isUsed ?? false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.group?.name ?? widget.initialName,
    );
    _selectedParentId = widget.group?.parentGroupId;
    _selectedUnitId = widget.group?.unitId;
    _nameController.addListener(_handleChange);
  }

  void _handleChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_handleChange);
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupsProvider = context.watch<GroupsProvider>();
    final unitsProvider = context.watch<UnitsProvider>();
    final title = widget.group == null
        ? 'Create Group'
        : _isReadOnly
        ? 'View Group'
        : 'Edit Group';
    final availableParents = groupsProvider.availableParentsFor(
      excludeGroupId: widget.group?.id,
    );
    final availableUnits = unitsProvider.activeUnits;
    final selectedUnit = unitsProvider.units
        .where((unit) => unit.id == _selectedUnitId)
        .firstOrNull;
    final duplicate = groupsProvider.checkDuplicate(
      name: _nameController.text,
      parentGroupId: _selectedParentId,
      excludeId: widget.group?.id,
    );

    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppSectionTitle(
                          title: title,
                          subtitle: _isReadOnly
                              ? 'This group is already in use, so its details are locked.'
                              : 'Define the group name, place it in the hierarchy, and assign the unit it should use.',
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  if (_localError != null) ...[
                    const SizedBox(height: 12),
                    _GroupsMessageBanner(message: _localError!, isError: true),
                  ],
                  if (groupsProvider.errorMessage != null &&
                      groupsProvider.isSaving == false) ...[
                    const SizedBox(height: 12),
                    _GroupsMessageBanner(
                      message: groupsProvider.errorMessage!,
                      isError: true,
                    ),
                  ],
                  const SizedBox(height: 16),
                  _GroupTextField(
                    controller: _nameController,
                    label: 'Group name',
                    helper:
                        'Shown in Configurator and linked transaction forms',
                    readOnly: _isReadOnly,
                  ),
                  const SizedBox(height: 12),
                  SearchableSelectField<int?>(
                    tapTargetKey: const ValueKey<String>('groups-parent-field'),
                    value:
                        availableParents.any(
                          (group) => group.id == _selectedParentId,
                        )
                        ? _selectedParentId
                        : null,
                    decoration: _fieldDecoration(
                      label: 'Parent group',
                      helper: 'Optional. Leave empty for top-level groups',
                    ),
                    dialogTitle: 'Parent group',
                    searchHintText: 'Search parent group',
                    fieldEnabled: !_isReadOnly,
                    options: [
                      const SearchableSelectOption<int?>(
                        value: null,
                        label: 'Top level',
                      ),
                      ...availableParents.map(
                        (group) => SearchableSelectOption<int?>(
                          value: group.id,
                          label: group.name,
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedParentId = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  SearchableSelectField<int>(
                    tapTargetKey: const ValueKey<String>('groups-unit-field'),
                    value:
                        availableUnits.any((unit) => unit.id == _selectedUnitId)
                        ? _selectedUnitId
                        : selectedUnit?.id,
                    decoration: _fieldDecoration(
                      label: 'Unit of group',
                      helper: 'Required. Comes from active Configurator Units',
                    ),
                    dialogTitle: 'Unit of group',
                    searchHintText: 'Search unit',
                    fieldEnabled: !_isReadOnly,
                    onCreateOption: (query) async {
                      final created = await UnitsScreen.openEditor(
                        context,
                        initialName: query,
                      );
                      if (!context.mounted || created == null) {
                        return null;
                      }
                      return SearchableSelectOption<int>(
                        value: created.id,
                        label: created.displayLabel,
                      );
                    },
                    createOptionLabelBuilder: (query) => 'Create unit "$query"',
                    options: [
                      ...availableUnits.map(
                        (unit) => SearchableSelectOption<int>(
                          value: unit.id,
                          label: unit.displayLabel,
                        ),
                      ),
                      if (selectedUnit != null &&
                          availableUnits.every(
                            (unit) => unit.id != selectedUnit.id,
                          ))
                        SearchableSelectOption<int>(
                          value: selectedUnit.id,
                          label: '${selectedUnit.displayLabel} (archived)',
                        ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedUnitId = value;
                      });
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _PreviewCard(
                    name: _nameController.text.trim(),
                    parentName: groupsProvider.parentNameFor(_selectedParentId),
                    unitLabel: unitsProvider.units
                        .where((unit) => unit.id == _selectedUnitId)
                        .firstOrNull
                        ?.displayLabel,
                  ),
                  const SizedBox(height: 16),
                  _WarningText(
                    warning: duplicate.warning,
                    hasCycle:
                        widget.group != null &&
                        groupsProvider.wouldCreateCycle(
                          groupId: widget.group!.id,
                          parentGroupId: _selectedParentId,
                        ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (!_isReadOnly)
                        AppButton(
                          label: widget.group == null
                              ? 'Create Group'
                              : 'Save Changes',
                          isLoading: groupsProvider.isSaving,
                          onPressed: () => _submit(context),
                        ),
                      if (widget.group != null)
                        AppButton(
                          label: widget.group!.isArchived
                              ? 'Restore'
                              : 'Archive',
                          variant: AppButtonVariant.secondary,
                          isLoading: groupsProvider.isSaving,
                          onPressed: () async {
                            final result = widget.group!.isArchived
                                ? await groupsProvider.restoreGroup(
                                    widget.group!.id,
                                  )
                                : await groupsProvider.archiveGroup(
                                    widget.group!.id,
                                  );
                            if (context.mounted && result != null) {
                              Navigator.of(context).pop(result);
                            }
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    if (_isReadOnly) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final groupsProvider = context.read<GroupsProvider>();
    final unitsProvider = context.read<UnitsProvider>();
    if (_selectedUnitId == null ||
        !unitsProvider.activeUnits.any((unit) => unit.id == _selectedUnitId)) {
      setState(() {
        _localError = 'Select an active unit for this group.';
      });
      return;
    }
    if (widget.group != null &&
        groupsProvider.wouldCreateCycle(
          groupId: widget.group!.id,
          parentGroupId: _selectedParentId,
        )) {
      setState(() {
        _localError =
            'A group cannot move under itself or one of its descendants.';
      });
      return;
    }

    final duplicate = groupsProvider.checkDuplicate(
      name: _nameController.text,
      parentGroupId: _selectedParentId,
      excludeId: widget.group?.id,
    );
    if (duplicate.blockingDuplicate) {
      setState(() {
        _localError =
            'A group with the same name already exists under that parent.';
      });
      return;
    }

    setState(() {
      _localError = null;
    });

    final result = widget.group == null
        ? await groupsProvider.createGroup(
            CreateGroupInput(
              name: _nameController.text.trim(),
              parentGroupId: _selectedParentId,
              unitId: _selectedUnitId!,
            ),
          )
        : await groupsProvider.updateGroup(
            UpdateGroupInput(
              id: widget.group!.id,
              name: _nameController.text.trim(),
              parentGroupId: _selectedParentId,
              unitId: _selectedUnitId!,
            ),
          );

    if (context.mounted && result != null) {
      Navigator.of(context).pop(result);
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String helper,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      filled: true,
      fillColor: _isReadOnly
          ? const Color(0xFFF3F4F6)
          : const Color(0xFFF9FAFB),
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
}

class _GroupTextField extends StatelessWidget {
  const _GroupTextField({
    required this.controller,
    required this.label,
    required this.helper,
    required this.readOnly,
  });

  final TextEditingController controller;
  final String label;
  final String helper;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        filled: true,
        fillColor: readOnly ? const Color(0xFFF3F4F6) : const Color(0xFFF9FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
        ),
      ),
      validator: (value) {
        if ((value ?? '').trim().isEmpty) {
          return 'Required';
        }
        return null;
      },
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.name,
    required this.parentName,
    required this.unitLabel,
  });

  final String name;
  final String? parentName;
  final String? unitLabel;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preview',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _PreviewChip(label: name.isEmpty ? 'Unnamed group' : name),
              _PreviewChip(
                label: parentName == null ? 'Top level' : 'Parent: $parentName',
              ),
              _PreviewChip(
                label: unitLabel == null ? 'Unit pending' : 'Unit: $unitLabel',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label),
    );
  }
}

class _WarningText extends StatelessWidget {
  const _WarningText({required this.warning, required this.hasCycle});

  final GroupDuplicateWarning warning;
  final bool hasCycle;

  @override
  Widget build(BuildContext context) {
    final text = switch (warning) {
      GroupDuplicateWarning.sameParent =>
        'A group with this name already exists under the selected parent.',
      GroupDuplicateWarning.none =>
        hasCycle
            ? 'This parent selection would create a cycle in the hierarchy.'
            : '',
    };
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: const Color(0xFFB45309)),
    );
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
