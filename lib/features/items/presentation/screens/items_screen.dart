import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_section_title.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../../core/widgets/soft_master_data.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../../groups/domain/group_definition.dart';
import '../../../groups/presentation/screens/groups_screen.dart';
import '../../../groups/presentation/providers/groups_provider.dart';
import '../../../units/presentation/screens/units_screen.dart';
import '../../../units/presentation/providers/units_provider.dart';
import '../../domain/item_definition.dart';
import '../../domain/item_inputs.dart';
import '../providers/items_provider.dart';

class ItemsScreen extends StatelessWidget {
  const ItemsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer3<ItemsProvider, GroupsProvider, UnitsProvider>(
      builder: (context, items, groups, units, _) {
        if ((items.isLoading && items.items.isEmpty) ||
            (groups.isLoading && groups.groups.isEmpty) ||
            (units.isLoading && units.units.isEmpty)) {
          return const Center(child: CircularProgressIndicator());
        }

        return SoftMasterDataPage(
          title: 'Items',
          subtitle:
              'Manage sellable catalog items with recursive property and value inheritance.',
          action: AppButton(
            label: 'Add Item',
            icon: Icons.add,
            isLoading: items.isSaving,
            onPressed: groups.activeGroups.isEmpty || units.activeUnits.isEmpty
                ? null
                : () => _openItemEditor(context),
          ),
          toolbar: const _ItemsToolbar(),
          messages: [
            if (items.errorMessage != null)
              _ItemsMessageBanner(message: items.errorMessage!, isError: true),
          ],
          body: items.filteredItems.isEmpty
              ? const AppEmptyState(
                  title: 'No items found',
                  message:
                      'Create an item like Bottle - 100, then build recursive property branches such as Color -> Black -> Finish -> Matte.',
                  icon: Icons.inventory_outlined,
                )
              : _ItemsTable(items: items.filteredItems),
        );
      },
    );
  }

  static Future<ItemDefinition?> openEditor(
    BuildContext context, {
    ItemDefinition? item,
    String initialName = '',
  }) {
    final isNarrow = MediaQuery.of(context).size.width < 980;
    final body = _ItemEditorSheet(item: item, initialName: initialName);
    if (isNarrow) {
      return showModalBottomSheet<ItemDefinition?>(
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

    return showDialog<ItemDefinition?>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1380),
          child: body,
        ),
      ),
    );
  }

  static Future<ItemDefinition?> _openItemEditor(
    BuildContext context, {
    ItemDefinition? item,
    String initialName = '',
  }) {
    return openEditor(context, item: item, initialName: initialName);
  }
}

class _ItemsToolbar extends StatelessWidget {
  const _ItemsToolbar();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ItemsProvider>();
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    return SoftMasterToolbar(
      children: [
        if (!isDesktop)
          SoftMasterSearchField(
            hintText: 'Search items, properties, values, or leaf nodes',
            onChanged: provider.setSearchQuery,
          ),
        SoftSegmentedFilter<ItemStatusFilter>(
          selected: provider.statusFilter,
          onChanged: provider.setStatusFilter,
          options: const [
            SoftSegmentOption<ItemStatusFilter>(
              value: ItemStatusFilter.active,
              label: 'Active',
            ),
            SoftSegmentOption<ItemStatusFilter>(
              value: ItemStatusFilter.archived,
              label: 'Archived',
            ),
            SoftSegmentOption<ItemStatusFilter>(
              value: ItemStatusFilter.all,
              label: 'All',
            ),
          ],
        ),
      ],
    );
  }
}

class _ItemsTable extends StatelessWidget {
  const _ItemsTable({required this.items});

  final List<ItemDefinition> items;

  @override
  Widget build(BuildContext context) {
    return SoftMasterTable(
      minWidth: 1120,
      columns: const [
        SoftTableColumn('Item', flex: 2),
        SoftTableColumn('Qty / Unit', flex: 2),
        SoftTableColumn('Group', flex: 2),
        SoftTableColumn('Tree Summary', flex: 3),
        SoftTableColumn('Status', flex: 1),
        SoftTableColumn('Actions', flex: 2),
      ],
      itemCount: items.length,
      rowBuilder: (context, index) => _ItemRow(item: items[index]),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final ItemDefinition item;

  @override
  Widget build(BuildContext context) {
    final groupsProvider = context.watch<GroupsProvider>();
    final unitsProvider = context.watch<UnitsProvider>();
    final itemsProvider = context.watch<ItemsProvider>();
    final groupName = groupsProvider.findById(item.groupId)?.name ?? 'Unknown';
    final unitLabel =
        unitsProvider.units
            .where((unit) => unit.id == item.unitId)
            .firstOrNull
            ?.displayLabel ??
        'Unknown';
    final propertySummary = item.topLevelProperties.isEmpty
        ? 'No properties'
        : item.topLevelProperties.map((node) => node.name).join(', ');
    final leafSummary = item.leafVariationNodes.isEmpty
        ? 'No orderable leaves'
        : '${item.leafVariationNodes.length} orderable leaf${item.leafVariationNodes.length == 1 ? '' : 's'}';

    return SoftMasterRow(
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SoftInlineText(item.displayName, weight: FontWeight.w700),
              if (item.alias.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                SoftInlineText(item.alias, color: SoftErpTheme.textSecondary),
              ],
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: SoftInlineText(
            '${_formatQuantity(item.quantity)} / $unitLabel',
          ),
        ),
        Expanded(flex: 2, child: SoftInlineText(groupName)),
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SoftInlineText(propertySummary),
              const SizedBox(height: 4),
              SoftInlineText(leafSummary, color: SoftErpTheme.textSecondary),
            ],
          ),
        ),
        Expanded(
          flex: 1,
          child: SoftStatusPill(
            label: item.isArchived ? 'Archived' : 'Active',
            background: item.isArchived
                ? const Color(0xFFF3F4F6)
                : const Color(0xFFECFDF5),
            textColor: item.isArchived
                ? const Color(0xFF6B7280)
                : const Color(0xFF0F766E),
            borderColor: item.isArchived
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
                label: 'Open',
                onTap: () => ItemsScreen.openEditor(context, item: item),
              ),
              if (!item.isUsed)
                SoftActionLink(
                  label: item.isArchived ? 'Restore' : 'Archive',
                  onTap: itemsProvider.isSaving
                      ? null
                      : () {
                          if (item.isArchived) {
                            itemsProvider.restoreItem(item.id);
                          } else {
                            itemsProvider.archiveItem(item.id);
                          }
                        },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NodeDraft {
  _NodeDraft({
    this.id,
    required this.kind,
    required this.parent,
    String name = '',
    String code = '',
    String displayName = '',
    this.detailsExpanded = false,
    this.isNameEditing = false,
    this.displayNameTouched = false,
    List<_NodeDraft>? children,
  }) : nameController = TextEditingController(text: name),
       codeController = TextEditingController(text: code),
       displayNameController = TextEditingController(text: displayName),
       children = children ?? <_NodeDraft>[];

  final int? id;
  final ItemVariationNodeKind kind;
  _NodeDraft? parent;
  final TextEditingController nameController;
  final TextEditingController codeController;
  final TextEditingController displayNameController;
  bool detailsExpanded;
  bool isNameEditing;
  bool displayNameTouched;
  final List<_NodeDraft> children;

  bool get isLeafValue =>
      kind == ItemVariationNodeKind.value && children.isEmpty;

  void dispose() {
    nameController.dispose();
    codeController.dispose();
    displayNameController.dispose();
    for (final child in children) {
      child.dispose();
    }
  }
}

class _ItemEditorSheet extends StatefulWidget {
  const _ItemEditorSheet({this.item, this.initialName = ''});

  final ItemDefinition? item;
  final String initialName;

  @override
  State<_ItemEditorSheet> createState() => _ItemEditorSheetState();
}

class _ItemEditorSheetState extends State<_ItemEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _aliasController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _quantityController;
  final List<_NodeDraft> _rootNodes = [];
  final ScrollController _variationTreeScrollController = ScrollController();
  int? _selectedGroupId;
  int? _selectedUnitId;
  bool _displayNameTouched = false;
  bool _syncingDisplayName = false;
  List<String> _namingFormat = [];
  String? _localError;

  bool get _isReadOnly => widget.item?.isUsed ?? false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.item?.name ?? widget.initialName,
    );
    _aliasController = TextEditingController(text: widget.item?.alias ?? '');
    _displayNameController = TextEditingController(
      text: widget.item?.displayName ?? '',
    );
    _quantityController = TextEditingController(
      text: widget.item == null ? '' : _formatQuantity(widget.item!.quantity),
    );
    _selectedGroupId = widget.item?.groupId;
    _selectedUnitId = widget.item?.unitId;
    _namingFormat = widget.item?.namingFormat.toList() ?? [];
    _displayNameTouched = (widget.item?.displayName ?? '').trim().isNotEmpty;

    _nameController.addListener(_handlePrimaryChange);
    _aliasController.addListener(_handlePrimaryChange);
    _displayNameController.addListener(() {
      if (_syncingDisplayName) {
        return;
      }
      _displayNameTouched = true;
      _handleChange();
    });

    for (final node
        in widget.item?.variationTree ??
            const <ItemVariationNodeDefinition>[]) {
      _rootNodes.add(_draftFromNode(node, null));
    }

    _syncPrimaryDisplayName();
    _syncLeafDisplayNames();
  }

  _NodeDraft _draftFromNode(
    ItemVariationNodeDefinition node,
    _NodeDraft? parent,
  ) {
    final draft = _NodeDraft(
      id: node.id,
      kind: node.kind,
      parent: parent,
      name: node.name,
      code: node.code,
      displayName: node.displayName,
      detailsExpanded: false,
      isNameEditing: false,
      displayNameTouched: node.displayName.trim().isNotEmpty,
    );
    draft.nameController.addListener(() {
      _syncLeafDisplayNames();
      _handleChange();
    });
    draft.codeController.addListener(() {
      _syncLeafDisplayNames();
      _handleChange();
    });
    draft.displayNameController.addListener(() {
      if (_syncingDisplayName) {
        return;
      }
      draft.displayNameTouched = true;
      _handleChange();
    });
    for (final child in node.children) {
      draft.children.add(_draftFromNode(child, draft));
    }
    return draft;
  }

  _NodeDraft _newDraft(ItemVariationNodeKind kind, _NodeDraft? parent) {
    final draft = _NodeDraft(
      kind: kind,
      parent: parent,
      detailsExpanded: false,
      isNameEditing: false,
    );
    draft.nameController.addListener(() {
      _syncLeafDisplayNames();
      _handleChange();
    });
    draft.codeController.addListener(() {
      _syncLeafDisplayNames();
      _handleChange();
    });
    draft.displayNameController.addListener(() {
      if (_syncingDisplayName) {
        return;
      }
      draft.displayNameTouched = true;
      _handleChange();
    });
    return draft;
  }

  void _handlePrimaryChange() {
    _syncPrimaryDisplayName();
    _handleChange();
  }

  void _handleChange() {
    if (mounted) {
      setState(() {});
    }
  }

  void _syncPrimaryDisplayName() {
    if (_displayNameTouched) {
      return;
    }
    final generated = _generateItemDisplayName(
      _nameController.text,
      _aliasController.text,
    );
    if (_displayNameController.text != generated) {
      _syncingDisplayName = true;
      _displayNameController.text = generated;
      _displayNameController.selection = TextSelection.collapsed(
        offset: _displayNameController.text.length,
      );
      _syncingDisplayName = false;
    }
  }

  void _syncLeafDisplayNames() {
    void visit(_NodeDraft node) {
      if (node.isLeafValue && !node.displayNameTouched) {
        final generated = _generateLeafDisplayName(node);
        if (node.displayNameController.text != generated) {
          _syncingDisplayName = true;
          node.displayNameController.text = generated;
          node.displayNameController.selection = TextSelection.collapsed(
            offset: node.displayNameController.text.length,
          );
          _syncingDisplayName = false;
        }
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final node in _rootNodes) {
      visit(node);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _aliasController.dispose();
    _displayNameController.dispose();
    _quantityController.dispose();
    _variationTreeScrollController.dispose();
    for (final node in _rootNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemsProvider = context.watch<ItemsProvider>();
    final groupsProvider = context.watch<GroupsProvider>();
    final unitsProvider = context.watch<UnitsProvider>();
    final duplicate = itemsProvider.checkDuplicate(
      name: _nameController.text,
      quantity: widget.item?.quantity ?? 0.0,
      groupId: _selectedGroupId,
      variationTree: _variationTreeInputs,
      excludeId: widget.item?.id,
    );
    final availableGroups = groupsProvider.activeGroups;
    final selectedGroup = groupsProvider.findById(_selectedGroupId);
    final availableUnits = unitsProvider.compatibleActiveUnitsForGroupUnitId(
      selectedGroup?.unitId,
    );
    final selectedUnit = unitsProvider.units
        .where((unit) => unit.id == _selectedUnitId)
        .firstOrNull;
    final detailsSection = _SectionCard(
      title: 'Item Details',
      child: Column(
        children: [
          _formRow(
            children: [
              _buildTextField(
                controller: _nameController,
                label: 'Name',
                helper: 'Base commercial item name',
                readOnly: _isReadOnly,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _formRow(
            children: [
              _buildTextField(
                controller: _aliasController,
                label: 'Alias',
                helper: 'Optional alternate label',
                readOnly: _isReadOnly,
                required: false,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _formRow(
            children: [
              _buildTextField(
                controller: _displayNameController,
                label: 'Display Name',
                helper: 'Editable generated label',
                readOnly: _isReadOnly,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _formRow(
            children: [
              SearchableSelectField<int>(
                tapTargetKey: const ValueKey<String>('items-group-field'),
                value:
                    availableGroups.any((group) => group.id == _selectedGroupId)
                    ? _selectedGroupId
                    : selectedGroup?.id,
                decoration: _fieldDecoration(
                  label: 'Group',
                  helper: 'Choose the group first. Unit options depend on it.',
                ),
                dialogTitle: 'Group',
                searchHintText: 'Search group',
                fieldEnabled: !_isReadOnly,
                onCreateOption: (query) async {
                  final created = await GroupsScreen.openEditor(
                    context,
                    initialName: query,
                  );
                  if (!mounted || created == null) {
                    return null;
                  }
                  return SearchableSelectOption<int>(
                    value: created.id,
                    label: _groupOptionLabel(created, groupsProvider),
                    searchText: _groupOptionSearchText(created, groupsProvider),
                  );
                },
                createOptionLabelBuilder: (query) => 'Create group "$query"',
                options: [
                  ...availableGroups.map(
                    (group) => SearchableSelectOption<int>(
                      value: group.id,
                      label: _groupOptionLabel(group, groupsProvider),
                      searchText: _groupOptionSearchText(group, groupsProvider),
                    ),
                  ),
                  if (selectedGroup != null &&
                      availableGroups.every(
                        (group) => group.id != selectedGroup.id,
                      ))
                    SearchableSelectOption<int>(
                      value: selectedGroup.id,
                      label:
                          '${_groupOptionLabel(selectedGroup, groupsProvider)} (archived)',
                      searchText: _groupOptionSearchText(
                        selectedGroup,
                        groupsProvider,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _selectedGroupId = value;
                  final group = groupsProvider.findById(value);
                  if (group == null) {
                    _selectedUnitId = null;
                    return;
                  }
                  if (!unitsProvider.areUnitsCompatible(
                    group.unitId,
                    _selectedUnitId,
                  )) {
                    _selectedUnitId = group.unitId;
                  }
                }),
                validator: (value) => value == null ? 'Required' : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _formRow(
            children: [
              SearchableSelectField<int>(
                tapTargetKey: const ValueKey<String>('items-unit-field'),
                value: availableUnits.any((unit) => unit.id == _selectedUnitId)
                    ? _selectedUnitId
                    : selectedUnit?.id,
                decoration: _fieldDecoration(
                  label: 'Unit',
                  helper: selectedGroup == null
                      ? 'Select a group first. Units are filtered by that group.'
                      : 'Only units compatible with the selected group are available.',
                ),
                dialogTitle: 'Unit',
                searchHintText: 'Search unit',
                fieldEnabled: !_isReadOnly && selectedGroup != null,
                onCreateOption: selectedGroup == null
                    ? null
                    : (query) async {
                        final groupBaseUnit = unitsProvider.findById(
                          selectedGroup.unitId,
                        );
                        final created = await UnitsScreen.openEditor(
                          context,
                          initialName: query,
                          initialGroupName:
                              groupBaseUnit?.unitGroupName ??
                              groupBaseUnit?.name ??
                              '',
                          initialConversionBaseUnitId: groupBaseUnit?.id,
                        );
                        if (!mounted || created == null) {
                          return null;
                        }
                        if (!unitsProvider.areUnitsCompatible(
                          selectedGroup.unitId,
                          created.id,
                        )) {
                          setState(() {
                            _localError =
                                'The created unit is not compatible with the selected group.';
                          });
                          return null;
                        }
                        setState(() {
                          _localError = null;
                        });
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
                onChanged: (value) => setState(() {
                  _localError = null;
                  _selectedUnitId = value;
                }),
                validator: (value) => value == null ? 'Required' : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PreviewCard(
            displayName: _displayNameController.text.trim(),
            unitLabel: selectedUnit?.displayLabel,
            propertyCount: _rootNodes.length,
            leafCount: _leafDrafts.length,
          ),
          const SizedBox(height: 12),
          _WarningText(warning: duplicate.warning),
        ],
      ),
    );
    final variationTreeSection = _SectionCard(
      title: 'Variation Tree',
      action: _isReadOnly
          ? null
          : AppButton(
              label: 'Add Top-Level Property',
              icon: Icons.add,
              variant: AppButtonVariant.secondary,
              onPressed: _addTopLevelProperty,
            ),
      child: _rootNodes.isEmpty
          ? const _ItemsMessageBanner(
              message:
                  'Start your variation tree with a property like Color, Size, or Material.',
              isError: false,
            )
          : Container(
              constraints: const BoxConstraints(maxHeight: 460),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFDCE2F0)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Scrollbar(
                controller: _variationTreeScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _variationTreeScrollController,
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < _rootNodes.length;
                        index++
                      ) ...[
                        _TreeNodeEditor(
                          draft: _rootNodes[index],
                          depth: 0,
                          readOnly: _isReadOnly,
                          summaryLabel: _summaryLabelForNode(_rootNodes[index]),
                          onToggleBranch: () =>
                              _toggleNodeDetails(_rootNodes[index]),
                          onEnableNameEditing: () =>
                              _setNodeNameEditing(_rootNodes[index], true),
                          onFinishNameEditing: () =>
                              _setNodeNameEditing(_rootNodes[index], false),
                          onAddProperty:
                              _rootNodes[index].kind ==
                                  ItemVariationNodeKind.value
                              ? () => _addChildProperty(_rootNodes[index])
                              : null,
                          onAddValue:
                              _rootNodes[index].kind ==
                                  ItemVariationNodeKind.property
                              ? () => _addChildValue(_rootNodes[index])
                              : null,
                          onMoveUp: index == 0
                              ? null
                              : () => _moveNode(_rootNodes, index, index - 1),
                          onMoveDown: index == _rootNodes.length - 1
                              ? null
                              : () => _moveNode(_rootNodes, index, index + 1),
                          onRemove: () => _removeNode(_rootNodes, index),
                          buildChildEditor: _buildChildEditor,
                        ),
                        if (index != _rootNodes.length - 1)
                          const SizedBox(height: 4),
                      ],
                    ],
                  ),
                ),
              ),
            ),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppSectionTitle(
                          title: widget.item == null
                              ? 'Create Item'
                              : _isReadOnly
                              ? 'View Item'
                              : 'Edit Item',
                          subtitle:
                              'Build recursive property and value branches directly inside the item.',
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
                    _ItemsMessageBanner(message: _localError!, isError: true),
                  ],
                  if (itemsProvider.errorMessage != null &&
                      !itemsProvider.isSaving) ...[
                    const SizedBox(height: 12),
                    _ItemsMessageBanner(
                      message: itemsProvider.errorMessage!,
                      isError: true,
                    ),
                  ],
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wideComposer = constraints.maxWidth >= 1140;
                      final namingFormatSection = _SectionCard(
                        title: 'Naming Format',
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFDCE2F0)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Drag and drop properties to set the variation display name sequence.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                              ),
                              const SizedBox(height: 12),
                              if (_activeNamingFormat.isEmpty)
                                const Text('Add properties to configure naming format.')
                              else
                                ReorderableListView(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  onReorder: (oldIndex, newIndex) {
                                    setState(() {
                                      if (newIndex > oldIndex) {
                                        newIndex -= 1;
                                      }
                                      final format = _activeNamingFormat;
                                      final item = format.removeAt(oldIndex);
                                      format.insert(newIndex, item);
                                      _namingFormat = format;
                                      // Reset displayNameTouched on ALL leaf
                                      // value nodes (not just root nodes) so
                                      // _syncLeafDisplayNames regenerates them.
                                      void resetLeaves(_NodeDraft node) {
                                        if (node.isLeafValue) {
                                          node.displayNameTouched = false;
                                        }
                                        for (final child in node.children) {
                                          resetLeaves(child);
                                        }
                                      }
                                      for (final node in _rootNodes) {
                                        resetLeaves(node);
                                      }
                                      _syncLeafDisplayNames();
                                    });
                                  },
                                  children: [
                                    for (final token in _activeNamingFormat)
                                      Container(
                                        key: ValueKey(token),
                                        margin: const EdgeInsets.only(bottom: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[100],
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.grey[300]!),
                                        ),
                                        child: ListTile(
                                          dense: true,
                                          title: Text(
                                            _getDisplayNameForToken(token),
                                            style: const TextStyle(fontWeight: FontWeight.w500),
                                          ),
                                          trailing: const Icon(Icons.drag_handle, color: Colors.grey),
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );

                      if (wideComposer) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 5, child: detailsSection),
                            const SizedBox(width: 18),
                            Expanded(
                              flex: 6,
                              child: Column(
                                children: [
                                  variationTreeSection,
                                  const SizedBox(height: 16),
                                  namingFormatSection,
                                ],
                              ),
                            ),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          detailsSection,
                          const SizedBox(height: 16),
                          variationTreeSection,
                          const SizedBox(height: 16),
                          namingFormatSection,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (!_isReadOnly)
                        AppButton(
                          label: widget.item == null
                              ? 'Create Item'
                              : 'Save Changes',
                          isLoading: itemsProvider.isSaving,
                          onPressed: () => _submit(context),
                        ),
                      if (widget.item != null)
                        AppButton(
                          label: widget.item!.isArchived
                              ? 'Restore'
                              : 'Archive',
                          variant: AppButtonVariant.secondary,
                          isLoading: itemsProvider.isSaving,
                          onPressed: () async {
                            final result = widget.item!.isArchived
                                ? await itemsProvider.restoreItem(
                                    widget.item!.id,
                                  )
                                : await itemsProvider.archiveItem(
                                    widget.item!.id,
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

  Widget _buildChildEditor(
    _NodeDraft child,
    int depth,
    List<_NodeDraft> siblings,
  ) {
    final index = siblings.indexOf(child);
    return _TreeNodeEditor(
      draft: child,
      depth: depth,
      readOnly: _isReadOnly,
      summaryLabel: _summaryLabelForNode(child),
      onToggleBranch: () => _toggleNodeDetails(child),
      onEnableNameEditing: () => _setNodeNameEditing(child, true),
      onFinishNameEditing: () => _setNodeNameEditing(child, false),
      onAddProperty: child.kind == ItemVariationNodeKind.value
          ? () => _addChildProperty(child)
          : null,
      onAddValue: child.kind == ItemVariationNodeKind.property
          ? () => _addChildValue(child)
          : null,
      onMoveUp: index == 0 ? null : () => _moveNode(siblings, index, index - 1),
      onMoveDown: index == siblings.length - 1
          ? null
          : () => _moveNode(siblings, index, index + 1),
      onRemove: () => _removeNode(siblings, index),
      buildChildEditor: _buildChildEditor,
    );
  }

  List<_NodeDraft> get _leafDrafts {
    final leaves = <_NodeDraft>[];
    void visit(_NodeDraft node) {
      if (node.isLeafValue) {
        leaves.add(node);
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final node in _rootNodes) {
      visit(node);
    }
    return leaves;
  }

  List<ItemVariationNodeInput> get _variationTreeInputs =>
      _rootNodes.map((node) => _toInput(node, null)).toList(growable: false);

  List<String> get _availableNamingTokens {
    final tokens = <String>['name'];
    for (var i = 0; i < _rootNodes.length; i++) {
      if (_rootNodes[i].kind == ItemVariationNodeKind.property) {
        tokens.add('prop_$i');
      }
    }
    return tokens;
  }

  List<String> get _activeNamingFormat {
    final available = _availableNamingTokens;
    final format = _namingFormat.where((t) => available.contains(t)).toList();
    for (final token in available) {
      if (!format.contains(token)) {
        format.add(token);
      }
    }
    return format;
  }

  String _getDisplayNameForToken(String token) {
    if (token == 'name') {
      return 'Item Name';
    }
    if (token.startsWith('prop_')) {
      final index = int.tryParse(token.substring(5));
      if (index != null && index >= 0 && index < _rootNodes.length) {
        final name = _rootNodes[index].nameController.text.trim();
        return name.isNotEmpty ? name : 'Unnamed Property';
      }
    }
    return token;
  }

  ItemVariationNodeInput _toInput(_NodeDraft node, int? parentNodeId) {
    return ItemVariationNodeInput(
      id: node.id,
      parentNodeId: parentNodeId,
      kind: node.kind,
      name: node.nameController.text.trim(),
      code: node.codeController.text.trim(),
      displayName: node.isLeafValue
          ? node.displayNameController.text.trim()
          : '',
      children: node.children
          .map((child) => _toInput(child, node.id))
          .toList(growable: false),
    );
  }

  String _summaryLabelForNode(_NodeDraft node) {
    if (node.isLeafValue) {
      final leafLabel = node.displayNameController.text.trim();
      return leafLabel.isEmpty ? _generateLeafDisplayName(node) : leafLabel;
    }
    final name = node.nameController.text.trim();
    final code = node.codeController.text.trim();
    if (name.isNotEmpty) {
      return code.isNotEmpty ? '$name [$code]' : name;
    }
    return node.kind == ItemVariationNodeKind.property
        ? 'Unnamed Property'
        : 'Unnamed Value';
  }

  void _toggleNodeDetails(_NodeDraft node) {
    setState(() {
      node.detailsExpanded = !node.detailsExpanded;
    });
  }

  void _setNodeNameEditing(_NodeDraft node, bool editing) {
    setState(() {
      node.isNameEditing = editing;
      if (editing) {
        node.detailsExpanded = true;
      }
    });
  }

  void _setTreeEditingState(
    List<_NodeDraft> nodes, {
    required bool detailsExpanded,
    required bool isNameEditing,
  }) {
    for (final node in nodes) {
      node.detailsExpanded = detailsExpanded;
      node.isNameEditing = isNameEditing;
      _setTreeEditingState(
        node.children,
        detailsExpanded: detailsExpanded,
        isNameEditing: isNameEditing,
      );
    }
  }

  void _addTopLevelProperty() {
    setState(() {
      _localError = null;
      _setTreeEditingState(
        _rootNodes,
        detailsExpanded: false,
        isNameEditing: false,
      );
      final draft = _newDraft(ItemVariationNodeKind.property, null);
      draft.isNameEditing = true;
      draft.detailsExpanded = true;
      _rootNodes.add(draft);
      _syncLeafDisplayNames();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_variationTreeScrollController.hasClients) {
        return;
      }
      _variationTreeScrollController.animateTo(
        _variationTreeScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _addChildProperty(_NodeDraft parent) {
    if (parent.kind != ItemVariationNodeKind.value) {
      setState(() {
        _localError =
            'A property can only be added under a value node. Top-level entries must start as properties.';
      });
      return;
    }
    setState(() {
      _localError = null;
      final child = _newDraft(ItemVariationNodeKind.property, parent);
      parent.detailsExpanded = true;
      child.isNameEditing = true;
      parent.children.add(child);
      _syncLeafDisplayNames();
    });
  }

  void _addChildValue(_NodeDraft parent) {
    if (parent.kind != ItemVariationNodeKind.property) {
      setState(() {
        _localError = 'A value can only be added under a property node.';
      });
      return;
    }
    setState(() {
      _localError = null;
      final child = _newDraft(ItemVariationNodeKind.value, parent);
      parent.detailsExpanded = true;
      child.isNameEditing = true;
      parent.children.add(child);
      _syncLeafDisplayNames();
    });
  }

  void _moveNode(List<_NodeDraft> siblings, int from, int to) {
    setState(() {
      final node = siblings.removeAt(from);
      siblings.insert(to, node);
      _syncLeafDisplayNames();
    });
  }

  void _removeNode(List<_NodeDraft> siblings, int index) {
    setState(() {
      final node = siblings.removeAt(index);
      node.dispose();
      _syncLeafDisplayNames();
    });
  }

  Future<void> _submit(BuildContext context) async {
    if (_isReadOnly) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final parsedQuantity = widget.item?.quantity ?? 0.0;
    if (_selectedGroupId == null || _selectedUnitId == null) {
      setState(() {
        _localError = 'Select both a group and a unit.';
      });
      return;
    }

    final itemsProvider = context.read<ItemsProvider>();
    final duplicate = itemsProvider.checkDuplicate(
      name: _nameController.text,
      quantity: parsedQuantity,
      groupId: _selectedGroupId,
      variationTree: _variationTreeInputs,
      excludeId: widget.item?.id,
    );
    if (duplicate.blockingDuplicate) {
      setState(() {
        _localError = _duplicateMessage(duplicate.warning);
      });
      return;
    }

    setState(() {
      _localError = null;
    });

    final result = widget.item == null
        ? await itemsProvider.createItem(
            CreateItemInput(
              name: _nameController.text.trim(),
              alias: _aliasController.text.trim(),
              displayName: _displayNameController.text.trim(),
              quantity: parsedQuantity,
              groupId: _selectedGroupId!,
              unitId: _selectedUnitId!,
              namingFormat: _activeNamingFormat,
              variationTree: _variationTreeInputs,
            ),
          )
        : await itemsProvider.updateItem(
            UpdateItemInput(
              id: widget.item!.id,
              name: _nameController.text.trim(),
              alias: _aliasController.text.trim(),
              displayName: _displayNameController.text.trim(),
              quantity: parsedQuantity,
              groupId: _selectedGroupId!,
              unitId: _selectedUnitId!,
              namingFormat: _activeNamingFormat,
              variationTree: _variationTreeInputs,
            ),
          );

    if (context.mounted && result != null) {
      Navigator.of(context).pop(result);
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String helper,
    required bool readOnly,
    bool required = true,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      decoration: _fieldDecoration(label: label, helper: helper),
      validator: (value) {
        if (!required) {
          return null;
        }
        if ((value ?? '').trim().isEmpty) {
          return 'Required';
        }
        return null;
      },
    );
  }

  Widget _formRow({required List<Widget> children}) {
    return Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index != children.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
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

  String _generateItemDisplayName(String name, String alias) {
    return [
      name.trim(),
      alias.trim(),
    ].where((entry) => entry.isNotEmpty).join(' / ');
  }

  String _groupOptionLabel(
    GroupDefinition group,
    GroupsProvider groupsProvider,
  ) {
    final primaryGroup = _primaryGroupFor(group, groupsProvider);
    if (primaryGroup.id == group.id) {
      return '${group.name} • Primary group';
    }
    return '${group.name} • Primary: ${primaryGroup.name}';
  }

  String _groupOptionSearchText(
    GroupDefinition group,
    GroupsProvider groupsProvider,
  ) {
    final primaryGroup = _primaryGroupFor(group, groupsProvider);
    return '${group.name} ${primaryGroup.name}';
  }

  GroupDefinition _primaryGroupFor(
    GroupDefinition group,
    GroupsProvider groupsProvider,
  ) {
    var current = group;
    final visited = <int>{current.id};
    while (current.parentGroupId != null) {
      final parent = groupsProvider.findById(current.parentGroupId);
      if (parent == null || !visited.add(parent.id)) {
        break;
      }
      current = parent;
    }
    return current;
  }

  String _generateLeafDisplayName(_NodeDraft leaf) {
    final pathValues = <String, String>{};

    // Always include the item name for the 'name' token
    final itemName = _nameController.text.trim();
    if (itemName.isNotEmpty) {
      pathValues['name'] = itemName;
    }

    _NodeDraft? current = leaf;
    while (current != null) {
      if (current.kind == ItemVariationNodeKind.value &&
          current.parent != null &&
          current.parent!.kind == ItemVariationNodeKind.property) {
        final propNode = current.parent!;
        final valueName = current.nameController.text.trim();
        final propIndex = _rootNodes.indexOf(propNode);
        if (propIndex != -1 && valueName.isNotEmpty) {
          pathValues['prop_$propIndex'] = valueName;
        }
      }
      current = current.parent;
    }

    final segments = <String>[];
    for (final token in _activeNamingFormat) {
      if (pathValues.containsKey(token)) {
        segments.add(pathValues[token]!);
      }
    }
    return segments.join(' ');
  }

  String _duplicateMessage(ItemDuplicateWarning warning) {
    return switch (warning) {
      ItemDuplicateWarning.none => '',
      ItemDuplicateWarning.sameGroupAndQuantity =>
        'An item with the same name and quantity already exists in the selected group.',
      ItemDuplicateWarning.emptyNodeName =>
        'Every property and value node needs a name.',
      ItemDuplicateWarning.invalidTreeStructure =>
        'The tree must alternate property groups and values.',
      ItemDuplicateWarning.duplicateSiblingName =>
        'Sibling nodes under the same parent must have unique names.',
    };
  }
}

class _TreeNodeEditor extends StatelessWidget {
  const _TreeNodeEditor({
    required this.draft,
    required this.depth,
    required this.readOnly,
    required this.summaryLabel,
    required this.onToggleBranch,
    required this.onEnableNameEditing,
    required this.onFinishNameEditing,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
    required this.buildChildEditor,
    this.onAddProperty,
    this.onAddValue,
  });

  final _NodeDraft draft;
  final int depth;
  final bool readOnly;
  final String summaryLabel;
  final VoidCallback onToggleBranch;
  final VoidCallback onEnableNameEditing;
  final VoidCallback onFinishNameEditing;
  final VoidCallback? onAddProperty;
  final VoidCallback? onAddValue;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onRemove;
  final Widget Function(_NodeDraft child, int depth, List<_NodeDraft> siblings)
  buildChildEditor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isProperty = draft.kind == ItemVariationNodeKind.property;
    final hasChildren = draft.children.isNotEmpty;
    final canExpand = hasChildren;
    final nodeType = isProperty ? 'Property' : 'Value';
    final icon = isProperty ? Icons.tune : Icons.circle;
    final iconSize = isProperty ? 18.0 : 10.0;
    final branchColor = theme.dividerColor.withValues(alpha: 0.55);
    final rowHighlight = draft.detailsExpanded
        ? theme.colorScheme.primary.withValues(alpha: 0.08)
        : Colors.transparent;
    final textColor = draft.nameController.text.trim().isEmpty
        ? theme.colorScheme.error
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: depth * 20.0),
          child: Material(
            color: rowHighlight,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: canExpand ? onToggleBranch : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    SizedBox(
                      width: 20,
                      child: canExpand
                          ? Icon(
                              draft.detailsExpanded
                                  ? Icons.expand_more
                                  : Icons.chevron_right,
                              size: 18,
                            )
                          : const SizedBox.shrink(),
                    ),
                    Icon(icon, size: iconSize),
                    const SizedBox(width: 8),
                    if (draft.isNameEditing && !readOnly)
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: draft.nameController,
                                autofocus: true,
                                onEditingComplete: onFinishNameEditing,
                                onSubmitted: (_) => onFinishNameEditing(),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: isProperty
                                      ? 'Property name'
                                      : 'Value name',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: draft.codeController,
                                onEditingComplete: onFinishNameEditing,
                                onSubmitted: (_) => onFinishNameEditing(),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: 'Code (Optional)',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Expanded(
                        child: MouseRegion(
                          cursor: readOnly
                              ? MouseCursor.defer
                              : SystemMouseCursors.text,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: readOnly ? null : onEnableNameEditing,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                summaryLabel,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: textColor,
                                  fontWeight: isProperty
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    _NodeTypePill(label: nodeType),
                    if (!readOnly) ...[
                      const SizedBox(width: 4),
                      if (onAddValue != null)
                        _TreeActionButton(
                          tooltip: 'Add value',
                          icon: Icons.add,
                          onPressed: onAddValue,
                        ),
                      if (onAddProperty != null)
                        _TreeActionButton(
                          tooltip: 'Add property',
                          icon: Icons.account_tree_outlined,
                          onPressed: onAddProperty,
                        ),
                      _TreeActionButton(
                        tooltip: 'Edit name',
                        icon: Icons.edit_outlined,
                        onPressed: onEnableNameEditing,
                      ),
                      _TreeActionButton(
                        tooltip: 'Move up',
                        icon: Icons.arrow_upward,
                        onPressed: onMoveUp,
                      ),
                      _TreeActionButton(
                        tooltip: 'Move down',
                        icon: Icons.arrow_downward,
                        onPressed: onMoveDown,
                      ),
                      _TreeActionButton(
                        tooltip: 'Remove',
                        icon: Icons.delete_outline,
                        onPressed: onRemove,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (hasChildren && draft.detailsExpanded)
          Padding(
            padding: EdgeInsets.only(left: depth * 20.0 + 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: branchColor, width: 1)),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 10, top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (
                      var childIndex = 0;
                      childIndex < draft.children.length;
                      childIndex++
                    ) ...[
                      buildChildEditor(
                        draft.children[childIndex],
                        depth + 1,
                        draft.children,
                      ),
                      if (childIndex != draft.children.length - 1)
                        const SizedBox(height: 2),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NodeTypePill extends StatelessWidget {
  const _NodeTypePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.72),
        ),
      ),
    );
  }
}

class _TreeActionButton extends StatelessWidget {
  const _TreeActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1F2937),
                  ),
                ),
              ),
              action ?? const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.displayName,
    required this.unitLabel,
    required this.propertyCount,
    required this.leafCount,
  });

  final String displayName;
  final String? unitLabel;
  final int propertyCount;
  final int leafCount;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      backgroundColor: const Color(0xFFF8FAFC),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _PreviewChip(
            label: displayName.isEmpty ? 'Display name pending' : displayName,
          ),
          _PreviewChip(
            label: unitLabel == null ? 'Unit pending' : 'Unit: $unitLabel',
          ),
          _PreviewChip(label: 'Top properties: $propertyCount'),
          _PreviewChip(label: 'Leaf nodes: $leafCount'),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(label),
    );
  }
}

class _WarningText extends StatelessWidget {
  const _WarningText({required this.warning});

  final ItemDuplicateWarning warning;

  @override
  Widget build(BuildContext context) {
    final message = switch (warning) {
      ItemDuplicateWarning.none => '',
      ItemDuplicateWarning.sameGroupAndQuantity =>
        'An item with this name and quantity already exists in the selected group.',
      ItemDuplicateWarning.emptyNodeName =>
        'Every property and value node needs a name.',
      ItemDuplicateWarning.invalidTreeStructure =>
        'The tree must alternate property groups and values.',
      ItemDuplicateWarning.duplicateSiblingName =>
        'Sibling names under the same parent must be unique.',
    };
    if (message.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(
      message,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: const Color(0xFFB45309),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ItemsMessageBanner extends StatelessWidget {
  const _ItemsMessageBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: isError ? const Color(0xFFB91C1C) : const Color(0xFF475569),
        ),
      ),
    );
  }
}

String _formatQuantity(double quantity) {
  if (quantity == quantity.roundToDouble()) {
    return quantity.toStringAsFixed(0);
  }
  return quantity.toString();
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
