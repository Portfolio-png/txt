import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'bento_grid_layout.dart';
import 'bento_card.dart';
import 'bento/component_items_card.dart';
import 'bento/component_workflow_cards.dart';
import 'group_type_icons.dart';

import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../groups/domain/group_definition.dart';
import '../../../groups/domain/group_inputs.dart';
import '../../../groups/presentation/providers/groups_provider.dart';
import '../../../inventory/domain/material_inputs.dart';
import '../../../inventory/domain/material_record.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../items/domain/item_definition.dart';
import '../../../items/domain/item_form_sections.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../../items/presentation/widgets/item_form_sections_dialog.dart';
import '../group_picker_field.dart';

enum FocusedCard { none, details, sections, items, pipelines, machines, dies }

class ComponentGroupEditorDialog extends StatefulWidget {
  const ComponentGroupEditorDialog({
    super.key,
    this.group,
    this.initialName = '',
  });

  final GroupDefinition? group;
  final String initialName;

  static Future<GroupDefinition?> open(
    BuildContext context, {
    GroupDefinition? group,
    String initialName = '',
  }) {
    final body = SubmitFormShortcuts(
      child: ComponentGroupEditorDialog(group: group, initialName: initialName),
    );
    final isNarrow = MediaQuery.of(context).size.width < 900;
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
        insetPadding: const EdgeInsets.all(24),
        backgroundColor: Colors.transparent,
        child: body,
      ),
    );
  }

  @override
  State<ComponentGroupEditorDialog> createState() =>
      _ComponentGroupEditorDialogState();
}

class _ComponentGroupEditorDialogState
    extends State<ComponentGroupEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _nameFocus = FocusNode();

  int? _selectedParentGroupId;
  GroupDefinition? _workflowGroup;
  ItemFormSections _componentFormSections = const ItemFormSections();
  FocusedCard _focusedCard = FocusedCard.details;
  int? _selectedItemId;
  MaterialRecord? _linkedMaterial;
  bool _didHydrateExisting = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.group?.name ?? widget.initialName;
    _descriptionController.text = widget.group?.description ?? '';
    _componentFormSections =
        widget.group?.itemFormSections ?? const ItemFormSections();
    _selectedParentGroupId = widget.group?.parentGroupId;
    _workflowGroup = widget.group;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didHydrateExisting || widget.group == null) {
      return;
    }
    _didHydrateExisting = true;
    Future<void>.microtask(_hydrateExisting);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _hydrateExisting() async {
    final group = widget.group;
    if (group == null || !mounted) {
      return;
    }

    final inventory = context.read<InventoryProvider>();
    final linkedMaterial = inventory.materials
        .where((record) => record.linkedGroupId == group.id && record.isParent)
        .firstOrNull;
    setState(() {
      _linkedMaterial = linkedMaterial;
    });
  }

  Widget _buildParentGroupField() {
    return KeyedSubtree(
      key: const ValueKey<String>('groups-parent-field'),
      child: GroupPickerField(
        tapTargetKey: const ValueKey<String>('masters-group-parent'),
        value: _selectedParentGroupId,
        onChanged: (value) => setState(() => _selectedParentGroupId = value),
        scope: GroupPickerScope.hierarchical,
        groupType: 'component',
        decoration: _selectDecoration(label: 'Parent Group'),
        dialogTitle: 'Parent Group',
        nullOptionLabel: 'Primary',
        excludeGroupId: widget.group?.id,
        excludeDescendantsOfSelf: true,
      ),
    );
  }

  InputDecoration _selectDecoration({required String label}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        fontFamily: 'Inter',
        color: Color(0xFF6B7280),
        fontSize: 14,
      ),
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  Widget buildSummary(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Inter',
        color: Color(0xFF6B7280),
        fontSize: 13,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Future<void> _submit(
    BuildContext context, {
    bool closeOnSuccess = true,
  }) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final groupsProvider = context.read<GroupsProvider>();
    final inventoryProvider = context.read<InventoryProvider>();
    final itemsProvider = context.read<ItemsProvider>();

    GroupDefinition? savedGroup;

    if (widget.group == null) {
      // Created as a group outright, not as an inventory parent material.
      // That path only writes a group when the request carries a unit id, and
      // a component deliberately has none — its items each carry their own —
      // so it made a stray material and no group at all, which is what the
      // "could not be marked as a component" notice was reporting.
      savedGroup = await groupsProvider.createGroup(
        CreateGroupInput(
          name: _nameController.text.trim(),
          groupType: 'item',
          groupStructure: 'component',
          description: _descriptionController.text.trim(),
          parentGroupId: _selectedParentGroupId,
          itemFormSections: _componentFormSections,
        ),
      );
      if (savedGroup == null || groupsProvider.errorMessage != null) {
        return;
      }
      await itemsProvider.refresh();
      if (itemsProvider.errorMessage != null) {
        return;
      }
    } else {
      final group = widget.group!;
      savedGroup = await groupsProvider.updateGroup(
        UpdateGroupInput(
          id: group.id,
          name: _nameController.text.trim(),
          groupType: group.groupType,
          groupStructure: 'component',
          description: _descriptionController.text.trim(),
          itemFormSections: _componentFormSections,
          parentGroupId: _selectedParentGroupId,
          unitId: group.unitId,
        ),
      );
      if (savedGroup == null || groupsProvider.errorMessage != null) {
        return;
      }

      if (_linkedMaterial != null) {
        await inventoryProvider.updateMaterial(
          UpdateMaterialInput(
            barcode: _linkedMaterial!.barcode,
            name: _nameController.text.trim(),
            type: _linkedMaterial!.type.trim().isEmpty
                ? 'Group'
                : _linkedMaterial!.type,
            grade: _linkedMaterial!.grade,
            thickness: _linkedMaterial!.thickness,
            supplier: _linkedMaterial!.supplier,
            location: _linkedMaterial!.location,
            unitId: group.unitId,
            unit: _linkedMaterial!.unit,
            notes: _descriptionController.text.trim(),
          ),
        );
        if (inventoryProvider.errorMessage != null) {
          return;
        }
      }

      await groupsProvider.refresh();
      if (groupsProvider.errorMessage != null) {
        return;
      }
      await itemsProvider.refresh();
      if (itemsProvider.errorMessage != null) {
        return;
      }
      savedGroup = groupsProvider.findById(group.id) ?? savedGroup;
    }

    if (!context.mounted ||
        groupsProvider.errorMessage != null ||
        itemsProvider.errorMessage != null ||
        inventoryProvider.errorMessage != null) {
      return;
    }
    showAppToast(
      context,
      widget.group != null ? 'Group saved' : 'Group created',
      kind: AppToastKind.success,
    );
    if (closeOnSuccess) {
      Navigator.of(context).pop(savedGroup);
    } else {
      setState(() {
        _workflowGroup = savedGroup;
        if (widget.group == null) _focusedCard = FocusedCard.sections;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GroupsProvider>();
    final itemsProvider = context.watch<ItemsProvider>();
    final isSavedComponent = _workflowGroup != null;

    ItemDefinition? selectedItem;
    if (_selectedItemId != null) {
      selectedItem = itemsProvider.items
          .where((i) => i.id == _selectedItemId)
          .firstOrNull;
    } else if (_workflowGroup != null) {
      final members = itemsProvider.items
          .where(
            (item) => item.groupId == _workflowGroup!.id && !item.isArchived,
          )
          .toList(growable: false);
      if (members.length == 1) {
        selectedItem = members.first;
        _selectedItemId = selectedItem.id;
      }
    }

    final nameField = TextFormField(
      controller: _nameController,
      focusNode: _nameFocus,
      textInputAction: TextInputAction.next,
      style: const TextStyle(
        fontFamily: 'Inter',
        color: Color(0xFF111827),
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      decoration: _selectDecoration(
        label: 'Component Name',
      ).copyWith(hintText: 'e.g. Lower Assembly'),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Enter a name';
        }
        return null;
      },
      onChanged: (_) => setState(() {}),
    );

    final descriptionField = TextFormField(
      controller: _descriptionController,
      textInputAction: TextInputAction.done,
      maxLines: 3,
      minLines: 1,
      style: const TextStyle(
        fontFamily: 'Inter',
        color: Color(0xFF111827),
        fontSize: 14,
      ),
      decoration: _selectDecoration(label: 'Description'),
    );

    final detailsCard = BentoCard(
      title: 'Component Details',
      isFocused: _focusedCard == FocusedCard.details,
      isContext:
          _focusedCard != FocusedCard.none &&
          _focusedCard != FocusedCard.details,
      onTap: () => setState(() => _focusedCard = FocusedCard.details),
      summary: buildSummary(
        _nameController.text.isEmpty ? 'Not started' : _nameController.text,
      ),
      headerActions: GroupTypeIcons(
        isComponent: true,
        isCombination: false,
        onTypeChanged: (bool _, bool __) {}, // Read-only in component dialog
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          nameField,
          const SizedBox(height: 14),
          descriptionField,
          const SizedBox(height: 14),
          _buildParentGroupField(),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: provider.isSaving
                  ? null
                  : () => _submit(context, closeOnSuccess: false),
              child: Text(isSavedComponent ? 'Save' : 'Save Details'),
            ),
          ),
        ],
      ),
    );

    // The box fills the inset the dialog leaves it, in both directions. It
    // used to be capped at 1000 wide while its height ran the full screen,
    // which left a tall narrow sheet holding a landscape grid.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox.expand(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE2E2E2)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.group == null
                                  ? 'Create Component'
                                  : 'Edit Component',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                color: Color(0xFF111827),
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'A sub-assembly whose items each carry their own pipeline, machines and dies.',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: Color(0xFF6B7280),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close,
                          color: Color(0xFF9CA3AF),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: BentoGridDialogLayout(
                    focusedCard: _focusedCard,
                    detailsCard: detailsCard,
                    sectionsCard: BentoCard(
                      title: 'Item Sections',
                      isFocused: _focusedCard == FocusedCard.sections,
                      isContext:
                          _focusedCard != FocusedCard.none &&
                          _focusedCard != FocusedCard.sections,
                      onTap: isSavedComponent
                          ? () => setState(
                              () => _focusedCard = FocusedCard.sections,
                            )
                          : () => showAppToast(
                              context,
                              'Save the component first.',
                              kind: AppToastKind.info,
                            ),
                      summary: buildSummary('Configured'),
                      child: isSavedComponent
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Items created under this component group use these sections, '
                                      'overriding each user’s own default.',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        color: Color(0xFF6B7280),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    ItemFormSectionsEditor(
                                      value: _componentFormSections,
                                      onChanged: (updated) => setState(
                                        () => _componentFormSections = updated,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: ElevatedButton(
                                    onPressed: provider.isSaving
                                        ? null
                                        : () => setState(
                                            () => _focusedCard =
                                                FocusedCard.items,
                                          ),
                                    child: const Text('Next: Items'),
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                    itemsCard: BentoCard(
                      title: 'Component Items',
                      isFocused: _focusedCard == FocusedCard.items,
                      isContext:
                          _focusedCard != FocusedCard.none &&
                          _focusedCard != FocusedCard.items,
                      onTap: isSavedComponent
                          ? () =>
                                setState(() => _focusedCard = FocusedCard.items)
                          : () => showAppToast(
                              context,
                              'Save the component first.',
                              kind: AppToastKind.info,
                            ),
                      summary: buildSummary(
                        isSavedComponent ? 'Manage items' : 'Not saved',
                      ),
                      child: isSavedComponent
                          ? ComponentItemsCard(
                              component: _workflowGroup!,
                              selectedItemId: _selectedItemId,
                              onSelect: (id) =>
                                  setState(() => _selectedItemId = id),
                              onSave: () => setState(
                                () => _focusedCard = FocusedCard.pipelines,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    pipelinesCard: BentoCard(
                      title: 'Pipeline',
                      isFocused: _focusedCard == FocusedCard.pipelines,
                      isContext:
                          _focusedCard != FocusedCard.none &&
                          _focusedCard != FocusedCard.pipelines,
                      onTap: selectedItem != null
                          ? () => setState(
                              () => _focusedCard = FocusedCard.pipelines,
                            )
                          : () => showAppToast(
                              context,
                              'Select an item first.',
                              kind: AppToastKind.info,
                            ),
                      summary: buildSummary(
                        selectedItem?.defaultPipelineName ?? 'None',
                      ),
                      child: selectedItem != null
                          ? ComponentPipelinesCard(
                              item: selectedItem,
                              onSave: () => setState(
                                () => _focusedCard = FocusedCard.machines,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    machinesCard: BentoCard(
                      title: 'Machines',
                      isFocused: _focusedCard == FocusedCard.machines,
                      isContext:
                          _focusedCard != FocusedCard.none &&
                          _focusedCard != FocusedCard.machines,
                      onTap: selectedItem != null
                          ? () => setState(
                              () => _focusedCard = FocusedCard.machines,
                            )
                          : () => showAppToast(
                              context,
                              'Select an item first.',
                              kind: AppToastKind.info,
                            ),
                      summary: buildSummary(
                        selectedItem != null && selectedItem.machines.isNotEmpty
                            ? selectedItem.machines
                                  .map((e) => e.name)
                                  .join(', ')
                            : 'None',
                      ),
                      child: selectedItem != null
                          ? ComponentMachinesCard(
                              item: selectedItem,
                              onSave: () => setState(
                                () => _focusedCard = FocusedCard.dies,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    diesCard: BentoCard(
                      title: 'Dies',
                      isFocused: _focusedCard == FocusedCard.dies,
                      isContext:
                          _focusedCard != FocusedCard.none &&
                          _focusedCard != FocusedCard.dies,
                      onTap: selectedItem != null
                          ? () =>
                                setState(() => _focusedCard = FocusedCard.dies)
                          : () => showAppToast(
                              context,
                              'Select an item first.',
                              kind: AppToastKind.info,
                            ),
                      summary: buildSummary(
                        selectedItem != null && selectedItem.dies.isNotEmpty
                            ? selectedItem.dies
                                  .map((e) => e.toolCode)
                                  .join(', ')
                            : 'None',
                      ),
                      child: selectedItem != null
                          ? ComponentDiesCard(
                              item: selectedItem,
                              onSave: () => setState(
                                () => _focusedCard = FocusedCard.none,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
                Container(
                  height: 61,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFFE2E2E2))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFDDDDDD)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: const Text(
                          'Close',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: Color(0xFF484848),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: provider.isSaving
                            ? null
                            : () => _submit(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF6049E3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: provider.isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save & Close',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
