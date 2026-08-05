import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/feature_flags.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import 'delete_group_dialog.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../groups/domain/group_definition.dart';
import '../../../groups/domain/group_inputs.dart';
import '../../../groups/presentation/providers/groups_provider.dart';
import '../../../inventory/domain/create_parent_material_input.dart';
import '../../../inventory/domain/effective_group_schema.dart';
import '../../../inventory/domain/group_property_draft.dart' as governance;
import '../../../inventory/domain/material_group_configuration.dart'
    show GroupUiPreferences, GroupUnitGovernance;
import '../../../inventory/domain/material_inputs.dart';
import '../../../inventory/domain/material_record.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../items/domain/item_definition.dart';
import '../../../items/domain/item_form_sections.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../../items/presentation/widgets/item_form_sections_dialog.dart';
import '../../../units/presentation/providers/units_provider.dart';
import '../../../units/presentation/screens/units_screen.dart';

class StructuredGroupEditorDialog extends StatefulWidget {
  const StructuredGroupEditorDialog({
    super.key,
    this.group,
    this.groupType = 'item',
    this.initialName = '',
    this.createMode = StructuredGroupEditorCreateMode.groupsOnly,
  });

  final GroupDefinition? group;
  final String groupType;
  final String initialName;
  final StructuredGroupEditorCreateMode createMode;

  static Future<GroupDefinition?> open(
    BuildContext context, {
    GroupDefinition? group,
    String groupType = 'item',
    String initialName = '',
    StructuredGroupEditorCreateMode createMode =
        StructuredGroupEditorCreateMode.groupsOnly,
  }) {
    final body = SubmitFormShortcuts(
      child: StructuredGroupEditorDialog(
        group: group,
        groupType: groupType,
        initialName: initialName,
        createMode: createMode,
      ),
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
  State<StructuredGroupEditorDialog> createState() =>
      _StructuredGroupEditorDialogState();
}

enum StructuredGroupEditorCreateMode { groupsOnly, inventoryBacked }

class _StructuredGroupEditorDialogState
    extends State<StructuredGroupEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _propertyController = TextEditingController();
  final _descriptionController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _propertyFocus = FocusNode();

  /// 'hierarchical' (an item group: nestable, the default), 'component' (same
  /// structure, for sub-assemblies) or 'combination' (flat variant set).
  /// See Enhancement 2.1.
  String _groupStructure = 'hierarchical';

  int? _selectedUnitId;
  int? _selectedParentGroupId;
  final Set<int> _selectedSeedItemIds = <int>{};
  EffectiveGroupSchema? _inheritedSchema;

  /// This group's own effective schema, used only for its retired fields.
  EffectiveGroupSchema? _ownSchema;
  bool _isLoadingInheritedSchema = false;
  bool _didHydrateExisting = false;
  MaterialRecord? _linkedMaterial;
  final Map<String, governance.GroupPropertyDraft> _seedPropertyCatalog =
      <String, governance.GroupPropertyDraft>{};
  final Map<String, governance.GroupPropertyDraft> _manualPropertyDrafts =
      <String, governance.GroupPropertyDraft>{};
  final Set<String> _disabledSeedPropertyKeys = <String>{};
  final Set<String> _discardedInheritedPropertyKeys = <String>{};

  bool get _isEditMode => widget.group != null;
  bool get _isLegacyUnlinkedEdit => _isEditMode && _linkedMaterial == null;

  /// Whether the hierarchical/combination structure toggle is offered. Only on
  /// item-group creation, behind the catalog/inventory enhancement flag.
  bool get _combinationToggleVisible =>
      !_isEditMode &&
      widget.groupType == 'item' &&
      FeatureFlags.isEnabled(FeatureKeys.catalogInventoryEnhancements);

  bool get _isCombination => _groupStructure == 'combination';

  /// Component groups share every field and code path with item groups; only
  /// the stored structure and the labelling differ.
  bool get _isComponent => _groupStructure == 'component';

  /// The section override this component group will carry. Seeded from the
  /// group being edited, or from the app defaults for a new one.
  ItemFormSections _componentFormSections = const ItemFormSections();

  /// Only sent for components — switching back to Item or Combination must not
  /// leave a stale override behind.
  ItemFormSections? get _formSectionsToSave =>
      _isComponent ? _componentFormSections : null;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.group?.name ?? widget.initialName;
    _descriptionController.text = widget.group?.description ?? '';
    _groupStructure = widget.group?.groupStructure ?? 'hierarchical';
    _componentFormSections =
        widget.group?.itemFormSections ?? const ItemFormSections();
    _selectedParentGroupId = widget.group?.parentGroupId;
    _selectedUnitId = widget.group?.unitId;
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
    _propertyController.dispose();
    _descriptionController.dispose();
    _nameFocus.dispose();
    _propertyFocus.dispose();
    super.dispose();
  }

  Future<void> _hydrateExisting() async {
    final group = widget.group;
    if (group == null || !mounted) {
      return;
    }

    final inventory = context.read<InventoryProvider>();
    final items = _activeItems();
    final linkedMaterial = inventory.materials
        .where((record) => record.linkedGroupId == group.id && record.isParent)
        .firstOrNull;
    setState(() {
      _linkedMaterial = linkedMaterial;
      _isLoadingInheritedSchema = group.parentGroupId != null;
    });

    final ownSchema = await inventory.loadEffectiveSchema(group.id);
    if (!mounted || widget.group?.id != group.id) {
      return;
    }
    setState(() => _ownSchema = ownSchema);

    if (group.parentGroupId != null) {
      final schema = await inventory.loadEffectiveSchema(group.parentGroupId!);
      if (!mounted || widget.group?.id != group.id) {
        return;
      }
      setState(() {
        _inheritedSchema = schema;
        _isLoadingInheritedSchema = false;
      });
    } else if (mounted) {
      setState(() {
        _isLoadingInheritedSchema = false;
      });
    }

    if (linkedMaterial == null) {
      return;
    }
    final configuration = await inventory.loadGroupConfiguration(
      linkedMaterial.barcode,
    );
    if (!mounted || configuration == null) {
      return;
    }

    final enabledSeedKeys = configuration.propertyDrafts
        .where(
          (draft) =>
              draft.sourceType ==
              governance.GroupPropertySourceType.inheritedItem,
        )
        .map((draft) => _propertyKey(draft.propertyKey ?? draft.name))
        .toSet();

    setState(() {
      _selectedSeedItemIds
        ..clear()
        ..addAll(configuration.selectedItemIds);
      _manualPropertyDrafts
        ..clear()
        ..addEntries(
          configuration.propertyDrafts
              .where(
                (draft) =>
                    draft.sourceType ==
                    governance.GroupPropertySourceType.manual,
              )
              .map(
                (draft) => MapEntry(
                  _propertyKey(draft.propertyKey ?? draft.name),
                  draft,
                ),
              ),
        );
      _discardedInheritedPropertyKeys
        ..clear()
        ..addAll(configuration.discardedPropertyKeys.map(_propertyKey));
      _rebuildSeedPropertyCatalog(items);
      _disabledSeedPropertyKeys
        ..clear()
        ..addAll(
          _seedPropertyCatalog.keys.where(
            (key) => !enabledSeedKeys.contains(key),
          ),
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final groupsProvider = context.watch<GroupsProvider>();
    final itemsProvider = context.watch<ItemsProvider>();
    final groups = groupsProvider
        .filteredGroupsByType(widget.groupType)
        .toList(growable: false);
    final units = context.watch<UnitsProvider>().includedUnitsFor(null, 'inventory');
    final items = _activeItems();
    final saveError =
        groupsProvider.errorMessage ??
        itemsProvider.errorMessage ??
        provider.errorMessage;
    final selectedUnit = units
        .where((unit) => unit.id == _selectedUnitId)
        .firstOrNull;
    final selectedParentGroup = groups
        .where((group) => group.id == _selectedParentGroupId)
        .firstOrNull;
    final selectedSeedItems = items
        .where((item) => _selectedSeedItemIds.contains(item.id))
        .toList(growable: false);
    final inheritedDrafts = _activeInheritedPropertyDrafts();
    final seedDrafts = _enabledSeedPropertyDrafts();
    final manualDrafts = _manualPropertyDrafts.values.toList(growable: false);
    final supportsStructuredGovernance =
        widget.createMode == StructuredGroupEditorCreateMode.inventoryBacked ||
        (_isEditMode && _linkedMaterial != null);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 1140,
        height: 700,
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Container(
                height: 76,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: const BoxDecoration(
                  color: Color(0xFFFBFBFB),
                  border: Border(bottom: BorderSide(color: Color(0xFFE7EBF0))),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isEditMode ? 'Edit Group' : 'Create Group',
                            style: _inventoryInterStyle(
                              color: const Color(0xFF111827),
                              size: 22,
                              weight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            supportsStructuredGovernance
                                ? 'Define the group, assign its unit, and optionally seed it with items or properties.'
                                : 'Define the group, assign its parent, and set the master unit.',
                            style: _inventoryInterStyle(
                              color: const Color(0xFF6B7280),
                              size: 13,
                              weight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              if (saveError != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    border: Border.all(color: const Color(0xFFFECACA)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    saveError,
                    style: _inventorySegoeStyle(
                      color: const Color(0xFF991B1B),
                      size: 13,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 940;
                    final detailsCard = _CreateGroupSurfaceCard(
                      title: 'Group Details',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _CreateGroupField(
                            label: 'Group Name',
                            child: TextFormField(
                              controller: _nameController,
                              focusNode: _nameFocus,
                              decoration: const InputDecoration(
                                hintText: 'Enter group name',
                                border: InputBorder.none,
                                isCollapsed: true,
                              ),
                              style: _inventorySegoeStyle(
                                color: const Color(0xFF3F3F3F),
                                size: 14,
                                weight: FontWeight.w400,
                              ),
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          if (_combinationToggleVisible) ...[
                            const SizedBox(height: 16),
                            _buildStructureToggle(),
                          ],
                          if (_isCombination) ...[
                            const SizedBox(height: 16),
                            _CreateGroupField(
                              label: 'Description (optional)',
                              child: TextFormField(
                                controller: _descriptionController,
                                minLines: 1,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  hintText: 'What variants does this set hold?',
                                  border: InputBorder.none,
                                  isCollapsed: true,
                                ),
                                style: _inventorySegoeStyle(
                                  color: const Color(0xFF3F3F3F),
                                  size: 14,
                                  weight: FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                          if (!_isCombination) ...[
                            const SizedBox(height: 16),
                            KeyedSubtree(
                              key: const ValueKey<String>(
                                'groups-parent-field',
                              ),
                              child: SearchableSelectField<int?>(
                                tapTargetKey: const ValueKey<String>(
                                  'masters-group-parent',
                                ),
                                value:
                                    groups.any(
                                      (group) =>
                                          group.id == _selectedParentGroupId,
                                    )
                                    ? _selectedParentGroupId
                                    : null,
                                decoration: _selectDecoration(
                                  label: 'Parent Group',
                                ),
                                dialogTitle: 'Parent Group',
                                searchHintText: 'Search group',
                                options: [
                                  const SearchableSelectOption<int?>(
                                    value: null,
                                    label: 'Primary',
                                  ),
                                  // Hide the group itself and everything under
                                  // it: the server rejects those with a 409, so
                                  // offering them only produces a dead end.
                                  ...groups
                                      .where(
                                        (group) =>
                                            group.id != widget.group?.id &&
                                            !_wouldCreateCycle(
                                              groupsProvider,
                                              group.id,
                                            ),
                                      )
                                      .map(
                                        (group) => SearchableSelectOption<int?>(
                                          value: group.id,
                                          label: group.name,
                                        ),
                                      ),
                                ],
                                onChanged: _setSelectedParentGroup,
                              ),
                            ),
                            const SizedBox(height: 16),
                            KeyedSubtree(
                              key: const ValueKey<String>('groups-unit-field'),
                              child: SearchableSelectField<int>(
                                tapTargetKey: const ValueKey<String>(
                                  'masters-group-unit',
                                ),
                                value:
                                    units.any(
                                      (unit) => unit.id == _selectedUnitId,
                                    )
                                    ? _selectedUnitId
                                    : selectedUnit?.id,
                                decoration: _selectDecoration(
                                  label: 'Group Unit',
                                ),
                                dialogTitle: 'Group Unit',
                                searchHintText: 'Search unit',
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
                                createOptionLabelBuilder: (query) =>
                                    'Create unit "$query"',
                                options: units
                                    .map(
                                      (unit) => SearchableSelectOption<int>(
                                        value: unit.id,
                                        label: unit.displayLabel,
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedUnitId = value;
                                  });
                                },
                                validator: (value) =>
                                    value == null &&
                                        widget.groupType != 'machine'
                                    ? 'Required'
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _PropertyChip(
                                    label: _nameController.text.trim().isEmpty
                                        ? 'Name pending'
                                        : _nameController.text.trim(),
                                    onRemove: () {},
                                    removable: false,
                                  ),
                                  _PropertyChip(
                                    label: selectedParentGroup == null
                                        ? 'Primary parent'
                                        : 'Under: ${selectedParentGroup.name}',
                                    onRemove: () {},
                                    removable: false,
                                  ),
                                  _PropertyChip(
                                    label: selectedUnit == null
                                        ? 'Unit pending'
                                        : 'Unit: ${selectedUnit.displayLabel}',
                                    onRemove: () {},
                                    removable: false,
                                  ),
                                ],
                              ),
                            ),
                          ], // end if (!_isCombination)
                        ],
                      ),
                    );

                    final compositionBody = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isLegacyUnlinkedEdit) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFFDE68A),
                              ),
                            ),
                            child: Text(
                              'This legacy group has no linked inventory record yet. Structure and properties are read-only in this edit.',
                              style: _inventoryInterStyle(
                                color: const Color(0xFF92400E),
                                size: 12,
                                weight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        AbsorbPointer(
                          absorbing: _isLegacyUnlinkedEdit,
                          child: Opacity(
                            opacity: _isLegacyUnlinkedEdit ? 0.55 : 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SearchableSelectField<int?>(
                                  tapTargetKey: const ValueKey<String>(
                                    'masters-group-seed-items',
                                  ),
                                  value: null,
                                  decoration: _selectDecoration(
                                    label: 'Seed Items',
                                    helper:
                                        'Optional. Reuse structured properties from one or more existing items.',
                                  ),
                                  dialogTitle: 'Add Seed Item',
                                  searchHintText: 'Search item',
                                  options: [
                                    const SearchableSelectOption<int?>(
                                      value: null,
                                      label: 'No seed item',
                                    ),
                                    ...items.map(
                                      (item) => SearchableSelectOption<int?>(
                                        value: item.id,
                                        label: item.displayName.trim().isEmpty
                                            ? item.name
                                            : item.displayName,
                                        searchText:
                                            '${item.name} ${item.alias} ${item.displayName}',
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    _addSelectedSeedItem(value, items);
                                  },
                                ),
                                if (selectedSeedItems.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final item in selectedSeedItems)
                                        _PropertyChip(
                                          label: item.displayName.trim().isEmpty
                                              ? item.name
                                              : item.displayName,
                                          badge: 'Seed',
                                          tone: _PropertyChipTone.seed,
                                          onRemove: () =>
                                              _removeSelectedSeedItem(
                                                item.id,
                                                items,
                                              ),
                                        ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 18),
                                if (_isLoadingInheritedSchema) ...[
                                  Row(
                                    children: [
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Loading inherited properties...',
                                        style: _inventoryInterStyle(
                                          color: const Color(0xFF64748B),
                                          size: 13,
                                          weight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                if (_retiredDrafts.isNotEmpty) ...[
                                  Text(
                                    'Retained (hidden)',
                                    style: _inventoryInterStyle(
                                      color: const Color(0xFF334155),
                                      size: 14,
                                      weight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'This group no longer asks for these, but '
                                    'items created earlier still hold their '
                                    'values. Add a property back with the same '
                                    'name to start collecting it again.',
                                    style: _inventoryInterStyle(
                                      color: const Color(0xFF6B7280),
                                      size: 12,
                                      weight: FontWeight.w400,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        for (final draft in _retiredDrafts)
                                          _PropertyChip(
                                            label: draft.name,
                                            badge: 'hidden',
                                            onRemove: () {},
                                            removable: false,
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                if (inheritedDrafts.isNotEmpty ||
                                    _discardedInheritedPropertyKeys
                                        .isNotEmpty) ...[
                                  Text(
                                    'Inherited Properties',
                                    style: _inventoryInterStyle(
                                      color: const Color(0xFF334155),
                                      size: 14,
                                      weight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        ...(_inheritedSchema?.propertyDrafts ??
                                                const <
                                                  governance.GroupPropertyDraft
                                                >[])
                                            .map(
                                              (
                                                draft,
                                              ) => _SeedPropertyToggleChip(
                                                label: draft.name,
                                                badge: 'Inherited',
                                                enabled:
                                                    !_discardedInheritedPropertyKeys
                                                        .contains(
                                                          _propertyKey(
                                                            draft.propertyKey ??
                                                                draft.name,
                                                          ),
                                                        ),
                                                onChanged: (enabled) {
                                                  setState(() {
                                                    final key = _propertyKey(
                                                      draft.propertyKey ??
                                                          draft.name,
                                                    );
                                                    if (enabled) {
                                                      _discardedInheritedPropertyKeys
                                                          .remove(key);
                                                    } else {
                                                      _discardedInheritedPropertyKeys
                                                          .add(key);
                                                    }
                                                  });
                                                },
                                              ),
                                            ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                ],
                                Text(
                                  'Properties',
                                  style: _inventoryInterStyle(
                                    color: const Color(0xFF334155),
                                    size: 14,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: _CreateGroupField(
                                        label: 'Add Property',
                                        child: TextFormField(
                                          controller: _propertyController,
                                          focusNode: _propertyFocus,
                                          decoration: const InputDecoration(
                                            hintText:
                                                'e.g. Material, Size, Color',
                                            border: InputBorder.none,
                                            isCollapsed: true,
                                          ),
                                          style: _inventorySegoeStyle(
                                            color: const Color(0xFF3F3F3F),
                                            size: 14,
                                            weight: FontWeight.w400,
                                          ),
                                          // Enter adds the property and keeps
                                          // the cursor here for rapid entry;
                                          // Tab moves focus on as usual.
                                          onFieldSubmitted: (_) {
                                            _addPropertyChip();
                                            WidgetsBinding.instance
                                                .addPostFrameCallback((_) {
                                                  if (mounted) {
                                                    _propertyFocus
                                                        .requestFocus();
                                                  }
                                                });
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      height: 40,
                                      child: OutlinedButton(
                                        onPressed: _addPropertyChip,
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(
                                            color: Color(0xFFDDDDDD),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              48,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          '+ Add',
                                          style: _inventoryInterStyle(
                                            color: const Color(0xFF484848),
                                            size: 14,
                                            weight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Container(
                                  width: double.infinity,
                                  constraints: const BoxConstraints(
                                    minHeight: 140,
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child:
                                      seedDrafts.isEmpty &&
                                          manualDrafts.isEmpty &&
                                          inheritedDrafts.isEmpty
                                      ? Text(
                                          selectedSeedItems.isEmpty
                                              ? 'No properties added yet. Pick a seed item or add properties manually.'
                                              : 'No properties added yet. These seed items have no structured properties.',
                                          style: _inventoryInterStyle(
                                            color: const Color(0xFF94A3B8),
                                            size: 13,
                                            weight: FontWeight.w400,
                                          ),
                                        )
                                      : Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            ..._seedPropertyCatalog.values.map(
                                              (
                                                draft,
                                              ) => _SeedPropertyToggleChip(
                                                label: draft.name,
                                                badge: 'Seeded',
                                                enabled:
                                                    !_disabledSeedPropertyKeys
                                                        .contains(
                                                          _propertyKey(
                                                            draft.propertyKey ??
                                                                draft.name,
                                                          ),
                                                        ),
                                                onChanged: (enabled) {
                                                  setState(() {
                                                    final key = _propertyKey(
                                                      draft.propertyKey ??
                                                          draft.name,
                                                    );
                                                    if (enabled) {
                                                      _disabledSeedPropertyKeys
                                                          .remove(key);
                                                    } else {
                                                      _disabledSeedPropertyKeys
                                                          .add(key);
                                                    }
                                                  });
                                                },
                                              ),
                                            ),
                                            ...manualDrafts.map(
                                              (draft) => _PropertyChip(
                                                label: draft.name,
                                                tone: _PropertyChipTone.manual,
                                                onRemove: () {
                                                  setState(() {
                                                    _manualPropertyDrafts
                                                        .remove(
                                                          _propertyKey(
                                                            draft.propertyKey ??
                                                                draft.name,
                                                          ),
                                                        );
                                                  });
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );

                    // Combination groups are flat variant sets and components
                    // inherit their structure from the item form, so neither
                    // gets a structure/properties panel.
                    final compositionCard =
                        supportsStructuredGovernance &&
                            !_isCombination &&
                            !_isComponent
                        ? _CreateGroupSurfaceCard(
                            title: 'Structure & Properties',
                            child: compositionBody,
                          )
                        : null;

                    // Components take the second column instead, so the dialog
                    // stays two-column rather than collapsing into one tall
                    // stack.
                    final sideCard =
                        compositionCard ??
                        (_isComponent
                            ? _CreateGroupSurfaceCard(
                                title: 'Item Form Sections',
                                child: _ComponentFormSectionsPanel(
                                  sections: _componentFormSections,
                                  onChanged: (updated) => setState(
                                    () => _componentFormSections = updated,
                                  ),
                                ),
                              )
                            : null);

                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                      child: isCompact
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                detailsCard,
                                if (sideCard != null) ...[
                                  const SizedBox(height: 18),
                                  sideCard,
                                ],
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: detailsCard),
                                if (sideCard != null) ...[
                                  const SizedBox(width: 18),
                                  Expanded(child: sideCard),
                                ],
                              ],
                            ),
                    );
                  },
                ),
              ),
              Container(
                height: 61,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE2E2E2))),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_isEditMode) ...[
                      TextButton.icon(
                        onPressed: provider.isSaving
                            ? null
                            : () => _handleDelete(context),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: Color(0xFFDC2626),
                        ),
                        label: Text(
                          'Delete group',
                          style: _inventoryInterStyle(
                            color: const Color(0xFFDC2626),
                            size: 14,
                            weight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Spacer(),
                    ],
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFDDDDDD)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: _inventoryInterStyle(
                          color: const Color(0xFF484848),
                          size: 14,
                          weight: FontWeight.w500,
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                      child: provider.isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              'Save',
                              style: _inventoryInterStyle(
                                color: Colors.white,
                                size: 14,
                                weight: FontWeight.w500,
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
    );
  }

  /// Fields this group used to ask for and no longer does, but whose values
  /// items still hold. Shown read-only so the retained data is visible.
  ///
  /// Read from this group's own effective schema — [_inheritedSchema] is the
  /// *parent's*, whose retired fields are not this group's business.
  List<governance.GroupPropertyDraft> get _retiredDrafts =>
      _ownSchema?.retiredPropertyDrafts ??
      const <governance.GroupPropertyDraft>[];

  /// Whether picking [candidateParentId] as this group's parent would put it
  /// under one of its own descendants. Always false while creating, since a new
  /// group has no descendants yet.
  bool _wouldCreateCycle(GroupsProvider groupsProvider, int candidateParentId) {
    final editingId = widget.group?.id;
    if (editingId == null) {
      return false;
    }
    return groupsProvider.wouldCreateCycle(
      groupId: editingId,
      parentGroupId: candidateParentId,
    );
  }

  /// Radio toggle that selects the group structure (Enhancement 2.1).
  Widget _buildStructureToggle() {
    return _CreateGroupField(
      label: 'Group Type',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StructureOptionTile(
            title: 'Item Group',
            selected: _groupStructure == 'hierarchical',
            onTap: () => setState(() => _groupStructure = 'hierarchical'),
          ),
          const SizedBox(height: 8),
          _StructureOptionTile(
            title: 'Component',
            selected: _isComponent,
            onTap: () => setState(() => _groupStructure = 'component'),
          ),
          const SizedBox(height: 8),
          _StructureOptionTile(
            title: 'Combination Group',
            selected: _isCombination,
            onTap: () => setState(() => _groupStructure = 'combination'),
          ),
        ],
      ),
    );
  }

  /// Persists a flat combination group. Parent, unit and structured properties
  /// do not apply, so this bypasses the inventory-backed material path.
  Future<void> _submitCombinationGroup(BuildContext context) async {
    final groupsProvider = context.read<GroupsProvider>();
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    GroupDefinition? saved;
    if (_isEditMode) {
      saved = await groupsProvider.updateGroup(
        UpdateGroupInput(
          id: widget.group!.id,
          name: name,
          groupType: widget.groupType,
          groupStructure: 'combination',
          description: description,
        ),
      );
    } else {
      saved = await groupsProvider.createGroup(
        CreateGroupInput(
          name: name,
          groupType: widget.groupType,
          groupStructure: 'combination',
          description: description,
        ),
      );
    }
    if (saved == null || groupsProvider.errorMessage != null) {
      return;
    }
    saved = groupsProvider.findById(saved.id) ?? saved;
    if (!context.mounted) {
      return;
    }
    showAppToast(
      context,
      _isEditMode ? 'Combination group updated' : 'Combination group created',
      kind: AppToastKind.success,
    );
    Navigator.of(context).pop(saved);
  }

  Future<void> _handleDelete(BuildContext context) async {
    final group = widget.group;
    if (group == null) return;
    final deleted = await DeleteGroupDialog.open(context, group);
    if (deleted && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_isCombination) {
      await _submitCombinationGroup(context);
      return;
    }
    if (_selectedUnitId == null && widget.groupType != 'machine') {
      showAppSnack(
        const SnackBar(content: Text('Select a group unit before saving.')),
      );
      return;
    }

    final groupsProvider = context.read<GroupsProvider>();
    final unitsProvider = context.read<UnitsProvider>();
    final itemsProvider = context.read<ItemsProvider>();
    final inventoryProvider = context.read<InventoryProvider>();
    final selectedUnit = unitsProvider.units
        .where((unit) => unit.id == _selectedUnitId)
        .firstOrNull;
    final items = _activeItems();
    final selectedSeedItems = items
        .where((item) => _selectedSeedItemIds.contains(item.id))
        .toList(growable: false);
    final inheritedDrafts = _activeInheritedPropertyDrafts();
    final propertyDrafts = _combinedStructuredDrafts();
    final notes = <String>[
      if (_selectedParentGroupId != null)
        'Parent Group: ${groupsProvider.parentNameFor(_selectedParentGroupId) ?? 'Unknown'}',
      if (_selectedParentGroupId == null) 'Parent Group: Primary',
      if (selectedSeedItems.isNotEmpty)
        'Seed Items: ${selectedSeedItems.map((item) => item.displayName.trim().isEmpty ? item.name : item.displayName).join(', ')}',
    ].join('\n');

    GroupDefinition? savedGroup;

    if (!_isEditMode) {
      if (widget.createMode == StructuredGroupEditorCreateMode.groupsOnly) {
        savedGroup = await groupsProvider.createGroup(
          CreateGroupInput(
            name: _nameController.text.trim(),
            groupType: widget.groupType,
            groupStructure: _groupStructure,
            itemFormSections: _formSectionsToSave,
            parentGroupId: _selectedParentGroupId,
            unitId: _selectedUnitId,
          ),
        );
        if (savedGroup == null || groupsProvider.errorMessage != null) {
          return;
        }
        await groupsProvider.refresh();
        if (groupsProvider.errorMessage != null) {
          return;
        }
        await itemsProvider.refresh();
        if (itemsProvider.errorMessage != null) {
          return;
        }
        savedGroup = groupsProvider.findById(savedGroup.id) ?? savedGroup;
        if (!context.mounted) {
          return;
        }
        showAppToast(context, 'Group created', kind: AppToastKind.success);
        Navigator.of(context).pop(savedGroup);
        return;
      }

      // Snapshot the ids so the row the material route creates can be found by
      // difference. Matching on parent/unit does not work: the server re-parents
      // a null parent onto Primary Group, so the created row never matches the
      // null the form submitted.
      final groupIdsBeforeCreate = groupsProvider.groups
          .map((group) => group.id)
          .toSet();

      await inventoryProvider.addParentMaterial(
        CreateParentMaterialInput(
          name: _nameController.text.trim(),
          type: 'Group',
          grade: '',
          thickness: '',
          supplier: '',
          parentGroupId: _selectedParentGroupId,
          unitId: _selectedUnitId,
          unit: selectedUnit?.displayLabel ?? 'Pieces',
          groupMode: _selectedParentGroupId == null
              ? 'standalone_group'
              : 'nested_group',
          inheritanceEnabled:
              inheritedDrafts.isNotEmpty ||
              selectedSeedItems.isNotEmpty ||
              _discardedInheritedPropertyKeys.isNotEmpty,
          selectedItemIds: _selectedSeedItemIds.toList(growable: false),
          propertyDrafts: propertyDrafts,
          discardedPropertyKeys: _discardedInheritedPropertyKeys.toList(
            growable: false,
          ),
          notes: notes,
          numberOfChildren: selectedSeedItems.length,
        ),
      );
      if (inventoryProvider.errorMessage != null) {
        return;
      }
      await groupsProvider.refresh();
      if (groupsProvider.errorMessage != null) {
        return;
      }
      await itemsProvider.refresh();
      if (itemsProvider.errorMessage != null) {
        return;
      }
      final matchingGroups = groupsProvider
          .filteredGroupsByType(widget.groupType)
          .where(
            (group) =>
                group.name.trim().toLowerCase() ==
                _nameController.text.trim().toLowerCase(),
          )
          .toList(growable: false);
      // Prefer a row that did not exist before this save; fall back to the
      // newest name match if the refresh raced.
      savedGroup =
          matchingGroups
              .where((group) => !groupIdsBeforeCreate.contains(group.id))
              .lastOrNull ??
          matchingGroups.lastOrNull;

      // The inventory-backed create goes through the material route, which has
      // no notion of group structure — stamp it afterwards so a component group
      // created here doesn't come back as a plain item group.
      if (_isComponent) {
        if (savedGroup == null) {
          // The name/parent/unit re-lookup above is the only handle we get on
          // the row the material route created. Losing it used to drop the
          // component structure and its section layout in silence.
          showAppSnack(
            const SnackBar(
              content: Text(
                'Group created, but it could not be marked as a component. '
                'Open it and set the type again.',
              ),
            ),
          );
        } else if (!savedGroup.isComponent ||
            savedGroup.itemFormSections == null) {
          final restructured = await groupsProvider.updateGroup(
            UpdateGroupInput(
              id: savedGroup.id,
              name: savedGroup.name,
              groupType: savedGroup.groupType,
              groupStructure: 'component',
              itemFormSections: _componentFormSections,
              parentGroupId: savedGroup.parentGroupId,
              unitId: savedGroup.unitId,
            ),
          );
          if (restructured != null && groupsProvider.errorMessage == null) {
            savedGroup = restructured;
          } else {
            showAppSnack(
              SnackBar(
                content: Text(
                  groupsProvider.errorMessage ??
                      'Group created, but its component settings did not save.',
                ),
              ),
            );
          }
        }
      }
    } else {
      final group = widget.group!;
      savedGroup = await groupsProvider.updateGroup(
        UpdateGroupInput(
          id: group.id,
          name: _nameController.text.trim(),
          groupType: group.groupType,
          // Hydrated from the group in initState; without it an edit would
          // silently reset a component group back to a plain item group.
          groupStructure: _groupStructure,
          itemFormSections: _formSectionsToSave,
          parentGroupId: _selectedParentGroupId,
          unitId: _selectedUnitId,
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
            unitId: _selectedUnitId,
            unit: selectedUnit?.displayLabel ?? _linkedMaterial!.unit,
            notes: notes,
          ),
        );
        if (inventoryProvider.errorMessage != null) {
          return;
        }
        await inventoryProvider.updateGroupConfiguration(
          _linkedMaterial!.barcode,
          inheritanceEnabled:
              inheritedDrafts.isNotEmpty ||
              selectedSeedItems.isNotEmpty ||
              _discardedInheritedPropertyKeys.isNotEmpty,
          selectedItemIds: _selectedSeedItemIds.toList(growable: false),
          propertyDrafts: propertyDrafts,
          unitGovernance: const <GroupUnitGovernance>[],
          uiPreferences: const GroupUiPreferences(),
          discardedPropertyKeys: _discardedInheritedPropertyKeys.toList(
            growable: false,
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
        savedGroup == null ||
        groupsProvider.errorMessage != null ||
        itemsProvider.errorMessage != null ||
        inventoryProvider.errorMessage != null) {
      return;
    }
    showAppToast(
      context,
      _isEditMode ? 'Group saved' : 'Group created',
      kind: AppToastKind.success,
    );
    Navigator.of(context).pop(savedGroup);
  }

  void _addPropertyChip() {
    final value = _propertyController.text.trim();
    if (value.isEmpty) {
      return;
    }
    final existingKeys = {
      ..._manualPropertyDrafts.keys,
      ..._enabledSeedPropertyDrafts().map(
        (draft) => _propertyKey(draft.propertyKey ?? draft.name),
      ),
      ..._activeInheritedPropertyDrafts().map(
        (draft) => _propertyKey(draft.propertyKey ?? draft.name),
      ),
    };
    if (existingKeys.contains(_propertyKey(value))) {
      _propertyController.clear();
      return;
    }
    setState(() {
      final key = _propertyKey(value);
      _manualPropertyDrafts[key] = governance.GroupPropertyDraft(
        name: value,
        propertyKey: key,
        inputType: 'Text',
        mandatory: false,
        sourceType: governance.GroupPropertySourceType.manual,
        state: governance.GroupPropertyState.active,
      );
      _propertyController.clear();
    });
  }

  Future<void> _setSelectedParentGroup(int? value) async {
    setState(() {
      _selectedParentGroupId = value;
      _discardedInheritedPropertyKeys.clear();
      _inheritedSchema = null;
      _isLoadingInheritedSchema = value != null;
    });
    if (value == null) {
      return;
    }
    final schema = await context.read<InventoryProvider>().loadEffectiveSchema(
      value,
    );
    if (!mounted || _selectedParentGroupId != value) {
      return;
    }
    setState(() {
      _inheritedSchema = schema;
      _discardedInheritedPropertyKeys.clear();
      _isLoadingInheritedSchema = false;
    });
  }

  void _addSelectedSeedItem(int? value, List<ItemDefinition> items) {
    if (value == null || _selectedSeedItemIds.contains(value)) {
      return;
    }
    setState(() {
      _selectedSeedItemIds.add(value);
      _disabledSeedPropertyKeys.clear();
      _rebuildSeedPropertyCatalog(items);
    });
  }

  void _removeSelectedSeedItem(int itemId, List<ItemDefinition> items) {
    setState(() {
      _selectedSeedItemIds.remove(itemId);
      _disabledSeedPropertyKeys.clear();
      _rebuildSeedPropertyCatalog(items);
    });
  }

  void _rebuildSeedPropertyCatalog(List<ItemDefinition> items) {
    final seedDrafts = _seedPropertyDraftsForItems(
      items
          .where((item) => _selectedSeedItemIds.contains(item.id))
          .toList(growable: false),
    );
    _seedPropertyCatalog
      ..clear()
      ..addEntries(
        seedDrafts.map(
          (draft) =>
              MapEntry(_propertyKey(draft.propertyKey ?? draft.name), draft),
        ),
      );
  }

  List<governance.GroupPropertyDraft> _seedPropertyDraftsForItems(
    List<ItemDefinition> items,
  ) {
    if (items.isEmpty) {
      return const <governance.GroupPropertyDraft>[];
    }
    final propertySources = <String, Set<String>>{};
    final propertySourceIds = <String, Set<int>>{};
    final propertyTypes = <String, String>{};
    final propertyTypeSet = <String, Set<String>>{};
    final propertyDisplayNames = <String, String>{};
    final propertyMandatory = <String, bool>{};
    final propertyUnitIds = <String, int?>{};
    final propertyUnitSymbols = <String, String?>{};
    final propertyUnitLabels = <String, String?>{};

    for (final item in items) {
      final sourceItemLabel = item.displayName.trim().isEmpty
          ? item.name
          : item.displayName;
      if (item.propertySchema.isNotEmpty) {
        for (final property in item.propertySchema) {
          final propertyName = property.displayName.trim();
          if (propertyName.isEmpty) {
            continue;
          }
          final key = _propertyKey(
            property.propertyKey.isEmpty ? propertyName : property.propertyKey,
          );
          propertyDisplayNames[key] = propertyName;
          propertySources
              .putIfAbsent(key, () => <String>{})
              .add(sourceItemLabel);
          propertySourceIds.putIfAbsent(key, () => <int>{}).add(item.id);
          propertyTypes[key] = property.inputType;
          propertyTypeSet
              .putIfAbsent(key, () => <String>{})
              .add(property.inputType);
          propertyMandatory[key] =
              (propertyMandatory[key] ?? false) || property.mandatory;
          propertyUnitIds[key] = property.unitId;
          propertyUnitSymbols[key] = property.unitSymbol;
          propertyUnitLabels[key] = property.unitLabel;
        }
        continue;
      }
      for (final property in item.topLevelProperties) {
        final propertyName = property.displayName.trim().isEmpty
            ? property.name.trim()
            : property.displayName.trim();
        if (propertyName.isEmpty) {
          continue;
        }
        final key = _propertyKey(propertyName);
        propertyDisplayNames[key] = propertyName;
        propertySources.putIfAbsent(key, () => <String>{}).add(sourceItemLabel);
        propertySourceIds.putIfAbsent(key, () => <int>{}).add(item.id);
        final inferredType = property.activeChildren.isNotEmpty
            ? 'Dropdown'
            : 'Text';
        propertyTypes[key] = inferredType;
        propertyTypeSet.putIfAbsent(key, () => <String>{}).add(inferredType);
      }
    }

    return propertySources.entries
        .map((entry) {
          final key = entry.key;
          final sourceNames = entry.value.toList(growable: false)..sort();
          final sourceIds = (propertySourceIds[key] ?? <int>{}).toList(
            growable: false,
          )..sort();
          final hasTypeConflict = (propertyTypeSet[key]?.length ?? 0) > 1;
          return governance.GroupPropertyDraft(
            name: propertyDisplayNames[key] ?? _titleCaseFromKey(key),
            propertyKey: key,
            inputType: hasTypeConflict
                ? 'Text'
                : (propertyTypes[key] ?? 'Text'),
            mandatory: propertyMandatory[key] ?? false,
            unitId: propertyUnitIds[key],
            unitSymbol: propertyUnitSymbols[key],
            unitLabel: propertyUnitLabels[key],
            sourceType: governance.GroupPropertySourceType.inheritedItem,
            state: governance.GroupPropertyState.active,
            hasTypeConflict: hasTypeConflict,
            coverageCount: sourceIds.length,
            selectedItemCountAtResolution: items.length,
            resolutionSource: hasTypeConflict
                ? 'conflict_default_text'
                : 'seeded_from_items',
            sources: sourceIds
                .asMap()
                .entries
                .map(
                  (source) => governance.GroupPropertySource(
                    itemId: source.value,
                    itemName: source.key < sourceNames.length
                        ? sourceNames[source.key]
                        : null,
                  ),
                )
                .toList(growable: false),
          );
        })
        .toList(growable: false);
  }

  List<governance.GroupPropertyDraft> _enabledSeedPropertyDrafts() {
    return _seedPropertyCatalog.values
        .where(
          (draft) => !_disabledSeedPropertyKeys.contains(
            _propertyKey(draft.propertyKey ?? draft.name),
          ),
        )
        .toList(growable: false);
  }

  List<governance.GroupPropertyDraft> _activeInheritedPropertyDrafts() {
    return (_inheritedSchema?.propertyDrafts ??
            const <governance.GroupPropertyDraft>[])
        .where(
          (draft) => !_discardedInheritedPropertyKeys.contains(
            _propertyKey(draft.propertyKey ?? draft.name),
          ),
        )
        .toList(growable: false);
  }

  List<governance.GroupPropertyDraft> _combinedStructuredDrafts() {
    final combined = <String, governance.GroupPropertyDraft>{};
    for (final draft in _activeInheritedPropertyDrafts()) {
      combined[_propertyKey(draft.propertyKey ?? draft.name)] = draft;
    }
    for (final draft in _enabledSeedPropertyDrafts()) {
      combined[_propertyKey(draft.propertyKey ?? draft.name)] = draft;
    }
    for (final draft in _manualPropertyDrafts.values) {
      combined[_propertyKey(draft.propertyKey ?? draft.name)] = draft;
    }
    return combined.values.toList(growable: false);
  }

  List<ItemDefinition> _activeItems() {
    return context.read<ItemsProvider>().items.toList(growable: false);
  }

  String _propertyKey(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  String _titleCaseFromKey(String key) {
    return key
        .split(RegExp(r'[\s_-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}

InputDecoration _selectDecoration({
  required String label,
  String? helper,
}) {
  return InputDecoration(
    labelText: label,
    helperText: helper,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD8E0EA)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD8E0EA)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF6049E3)),
    ),
    helperStyle: _inventoryInterStyle(
      color: const Color(0xFF6B7280),
      size: 12,
      weight: FontWeight.w400,
    ),
  );
}

/// Right-hand pane for component groups: the same toggles as Settings → Item
/// Creation, but authoring this group's own override.
///
/// Items created under this group use these sections instead of whatever the
/// creating user's account-wide default happens to be.
class _ComponentFormSectionsPanel extends StatelessWidget {
  const _ComponentFormSectionsPanel({
    required this.sections,
    required this.onChanged,
  });

  final ItemFormSections sections;
  final ValueChanged<ItemFormSections> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Items created under this component group use these sections, '
          'overriding each user’s own default.',
          style: _inventoryInterStyle(
            color: const Color(0xFF6B7280),
            size: 12,
            weight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 14),
        ItemFormSectionsEditor(value: sections, onChanged: onChanged),
      ],
    );
  }
}

class _CreateGroupSurfaceCard extends StatelessWidget {
  const _CreateGroupSurfaceCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: _inventoryInterStyle(
              color: const Color(0xFF111827),
              size: 18,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _CreateGroupField extends StatelessWidget {
  const _CreateGroupField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD8E0EA)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD8E0EA)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF6049E3)),
        ),
        floatingLabelStyle: _inventorySegoeStyle(
          color: const Color(0xFF6B7280),
          size: 12,
          weight: FontWeight.w400,
        ),
      ),
      child: child,
    );
  }
}

/// Selectable radio-style tile used by the group-structure toggle.
class _StructureOptionTile extends StatelessWidget {
  const _StructureOptionTile({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF3F0FF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF6049E3) : const Color(0xFFD8E0EA),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selected
                  ? const Color(0xFF6049E3)
                  : const Color(0xFF9CA3AF),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: _inventoryInterStyle(
                  color: const Color(0xFF111827),
                  size: 14,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PropertyChipTone { neutral, seed, manual }

class _PropertyChip extends StatelessWidget {
  const _PropertyChip({
    required this.label,
    required this.onRemove,
    this.badge,
    this.tone = _PropertyChipTone.neutral,
    this.removable = true,
  });

  final String label;
  final String? badge;
  final VoidCallback onRemove;
  final _PropertyChipTone tone;
  final bool removable;

  @override
  Widget build(BuildContext context) {
    final background = switch (tone) {
      _PropertyChipTone.neutral => const Color(0xFFF8FAFC),
      _PropertyChipTone.seed => const Color(0xFFEEF2FF),
      _PropertyChipTone.manual => const Color(0xFFF5F3FF),
    };
    final border = switch (tone) {
      _PropertyChipTone.neutral => const Color(0xFFD8E0EA),
      _PropertyChipTone.seed => const Color(0xFFC7D2FE),
      _PropertyChipTone.manual => const Color(0xFFD8B4FE),
    };
    final textColor = switch (tone) {
      _PropertyChipTone.neutral => const Color(0xFF334155),
      _PropertyChipTone.seed => const Color(0xFF4338CA),
      _PropertyChipTone.manual => const Color(0xFF7C3AED),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: _inventoryInterStyle(
              color: textColor,
              size: 13,
              weight: FontWeight.w600,
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badge!,
                style: _inventoryInterStyle(
                  color: textColor,
                  size: 11,
                  weight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (removable) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onRemove,
              child: Icon(Icons.close_rounded, size: 16, color: textColor),
            ),
          ],
        ],
      ),
    );
  }
}

class _SeedPropertyToggleChip extends StatelessWidget {
  const _SeedPropertyToggleChip({
    required this.label,
    required this.enabled,
    required this.onChanged,
    this.badge,
  });

  final String label;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!enabled),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFFEEF2FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: enabled ? const Color(0xFFC7D2FE) : const Color(0xFFD8E0EA),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: _inventoryInterStyle(
                color: enabled
                    ? const Color(0xFF4338CA)
                    : const Color(0xFF64748B),
                size: 13,
                weight: FontWeight.w600,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Text(
                badge!,
                style: _inventoryInterStyle(
                  color: enabled
                      ? const Color(0xFF4338CA)
                      : const Color(0xFF94A3B8),
                  size: 11,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

TextStyle _inventoryInterStyle({
  required Color color,
  required double size,
  required FontWeight weight,
  double height = 1.2,
}) {
  return TextStyle(
    fontFamily: 'Inter',
    color: color,
    fontSize: size,
    fontWeight: weight,
    height: height,
  );
}

TextStyle _inventorySegoeStyle({
  required Color color,
  required double size,
  required FontWeight weight,
  double height = 1.2,
}) {
  return TextStyle(
    fontFamily: 'Segoe UI',
    color: color,
    fontSize: size,
    fontWeight: weight,
    height: height,
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
