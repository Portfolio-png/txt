import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_section_title.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../groups/presentation/providers/groups_provider.dart';
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

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSectionTitle(
                title: 'Items',
                subtitle:
                    'Manage sellable catalog items with recursive property and value inheritance.',
                trailing: AppButton(
                  label: 'Add Item',
                  icon: Icons.add,
                  isLoading: items.isSaving,
                  onPressed:
                      groups.activeGroups.isEmpty || units.activeUnits.isEmpty
                      ? null
                      : () => _openItemEditor(context),
                ),
              ),
              const SizedBox(height: 20),
              const _ItemsToolbar(),
              if (items.errorMessage != null) ...[
                const SizedBox(height: 12),
                _ItemsMessageBanner(
                  message: items.errorMessage!,
                  isError: true,
                ),
              ],
              const SizedBox(height: 20),
              Expanded(
                child: items.filteredItems.isEmpty
                    ? const AppEmptyState(
                        title: 'No items found',
                        message:
                            'Create an item like Bottle - 100, then build recursive property branches such as Color -> Black -> Finish -> Matte.',
                        icon: Icons.inventory_outlined,
                      )
                    : _ItemsTable(items: items.filteredItems),
              ),
            ],
          ),
        );
      },
    );
  }

  static Future<ItemDefinition?> openEditor(
    BuildContext context, {
    ItemDefinition? item,
  }) {
    final isNarrow = MediaQuery.of(context).size.width < 1100;
    final body = _ItemEditorSheet(item: item);
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
          constraints: const BoxConstraints(maxWidth: 1040),
          child: body,
        ),
      ),
    );
  }

  static Future<ItemDefinition?> _openItemEditor(
    BuildContext context, {
    ItemDefinition? item,
  }) {
    return openEditor(context, item: item);
  }
}

class _ItemsToolbar extends StatelessWidget {
  const _ItemsToolbar();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ItemsProvider>();
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        if (!isDesktop)
          SizedBox(
            width: 360,
            child: TextField(
              onChanged: provider.setSearchQuery,
              decoration: InputDecoration(
                hintText: 'Search items, properties, values, or leaf paths',
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
        SegmentedButton<ItemStatusFilter>(
          segments: const [
            ButtonSegment<ItemStatusFilter>(
              value: ItemStatusFilter.active,
              label: Text('Active'),
            ),
            ButtonSegment<ItemStatusFilter>(
              value: ItemStatusFilter.archived,
              label: Text('Archived'),
            ),
            ButtonSegment<ItemStatusFilter>(
              value: ItemStatusFilter.all,
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

class _ItemsTable extends StatelessWidget {
  const _ItemsTable({required this.items});

  final List<ItemDefinition> items;

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
                Expanded(flex: 2, child: _HeaderText('Item')),
                Expanded(flex: 2, child: _HeaderText('Qty / Unit')),
                Expanded(flex: 2, child: _HeaderText('Group')),
                Expanded(flex: 3, child: _HeaderText('Tree Summary')),
                Expanded(flex: 1, child: _HeaderText('Status')),
                Expanded(flex: 2, child: _HeaderText('Actions')),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: Color(0xFFF1F2F7)),
              itemBuilder: (context, index) => _ItemRow(item: items[index]),
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
        : '${item.leafVariationNodes.length} orderable path${item.leafVariationNodes.length == 1 ? '' : 's'}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayName,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (item.alias.trim().isNotEmpty)
                  Text(
                    item.alias,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6B7280),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('${_formatQuantity(item.quantity)} / $unitLabel'),
          ),
          Expanded(flex: 2, child: Text(groupName)),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(propertySummary),
                const SizedBox(height: 4),
                Text(
                  leafSummary,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(item.isArchived ? 'Archived' : 'Active'),
          ),
          Expanded(
            flex: 2,
            child: Wrap(
              spacing: 8,
              children: [
                AppButton(
                  label: 'Open',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => ItemsScreen.openEditor(context, item: item),
                ),
                if (!item.isUsed)
                  AppButton(
                    label: item.isArchived ? 'Restore' : 'Archive',
                    variant: AppButtonVariant.secondary,
                    isLoading: itemsProvider.isSaving,
                    onPressed: () {
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
      ),
    );
  }
}

class _NodeDraft {
  _NodeDraft({
    this.id,
    required this.kind,
    required this.parent,
    String name = '',
    String displayName = '',
    this.displayNameTouched = false,
    List<_NodeDraft>? children,
  }) : nameController = TextEditingController(text: name),
       displayNameController = TextEditingController(text: displayName),
       children = children ?? <_NodeDraft>[];

  final int? id;
  final ItemVariationNodeKind kind;
  _NodeDraft? parent;
  final TextEditingController nameController;
  final TextEditingController displayNameController;
  bool displayNameTouched;
  final List<_NodeDraft> children;

  bool get isLeafValue =>
      kind == ItemVariationNodeKind.value && children.isEmpty;

  void dispose() {
    nameController.dispose();
    displayNameController.dispose();
    for (final child in children) {
      child.dispose();
    }
  }
}

class _ItemEditorSheet extends StatefulWidget {
  const _ItemEditorSheet({this.item});

  final ItemDefinition? item;

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
  int? _selectedGroupId;
  int? _selectedUnitId;
  bool _displayNameTouched = false;
  bool _syncingDisplayName = false;
  String? _localError;

  bool get _isReadOnly => widget.item?.isUsed ?? false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item?.name ?? '');
    _aliasController = TextEditingController(text: widget.item?.alias ?? '');
    _displayNameController = TextEditingController(
      text: widget.item?.displayName ?? '',
    );
    _quantityController = TextEditingController(
      text: widget.item == null ? '' : _formatQuantity(widget.item!.quantity),
    );
    _selectedGroupId = widget.item?.groupId;
    _selectedUnitId = widget.item?.unitId;
    _displayNameTouched = (widget.item?.displayName ?? '').trim().isNotEmpty;

    _nameController.addListener(_handlePrimaryChange);
    _aliasController.addListener(_handlePrimaryChange);
    _quantityController.addListener(_handlePrimaryChange);
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
      displayName: node.displayName,
      displayNameTouched: node.displayName.trim().isNotEmpty,
    );
    draft.nameController.addListener(() {
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
    final draft = _NodeDraft(kind: kind, parent: parent);
    draft.nameController.addListener(() {
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
    final quantity = double.tryParse(_quantityController.text.trim());
    if (quantity == null || quantity <= 0) {
      return;
    }
    final generated = _generateItemDisplayName(
      _nameController.text,
      _aliasController.text,
      quantity,
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
      quantity: double.tryParse(_quantityController.text.trim()),
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
                  _SectionCard(
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
                            _buildTextField(
                              controller: _aliasController,
                              label: 'Alias',
                              helper: 'Optional alternate label',
                              readOnly: _isReadOnly,
                              required: false,
                            ),
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
                            _buildTextField(
                              controller: _quantityController,
                              label: 'Quantity',
                              helper: 'Stored on the item',
                              readOnly: _isReadOnly,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                            ),
                            SearchableSelectField<int>(
                              tapTargetKey: const ValueKey<String>(
                                'items-unit-field',
                              ),
                              value:
                                  availableUnits.any(
                                    (unit) => unit.id == _selectedUnitId,
                                  )
                                  ? _selectedUnitId
                                  : selectedUnit?.id,
                              decoration: _fieldDecoration(
                                label: 'Unit',
                                helper: selectedGroup == null
                                    ? 'Inherited by the variation tree'
                                    : 'Only units compatible with the selected group are available',
                              ),
                              dialogTitle: 'Unit',
                              searchHintText: 'Search unit',
                              fieldEnabled: !_isReadOnly,
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
                                    label:
                                        '${selectedUnit.displayLabel} (archived)',
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _selectedUnitId = value),
                              validator: (value) =>
                                  value == null ? 'Required' : null,
                            ),
                            SearchableSelectField<int>(
                              tapTargetKey: const ValueKey<String>(
                                'items-group-field',
                              ),
                              value:
                                  availableGroups.any(
                                    (group) => group.id == _selectedGroupId,
                                  )
                                  ? _selectedGroupId
                                  : selectedGroup?.id,
                              decoration: _fieldDecoration(
                                label: 'Group',
                                helper: 'Required catalog group',
                              ),
                              dialogTitle: 'Group',
                              searchHintText: 'Search group',
                              fieldEnabled: !_isReadOnly,
                              options: [
                                ...availableGroups.map(
                                  (group) => SearchableSelectOption<int>(
                                    value: group.id,
                                    label: group.name,
                                  ),
                                ),
                                if (selectedGroup != null &&
                                    availableGroups.every(
                                      (group) => group.id != selectedGroup.id,
                                    ))
                                  SearchableSelectOption<int>(
                                    value: selectedGroup.id,
                                    label: '${selectedGroup.name} (archived)',
                                  ),
                              ],
                              onChanged: (value) => setState(() {
                                _selectedGroupId = value;
                                final group = groupsProvider.findById(value);
                                if (!unitsProvider.areUnitsCompatible(
                                  group?.unitId,
                                  _selectedUnitId,
                                )) {
                                  _selectedUnitId = null;
                                }
                              }),
                              validator: (value) =>
                                  value == null ? 'Required' : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _PreviewCard(
                          displayName: _displayNameController.text.trim(),
                          quantity: double.tryParse(
                            _quantityController.text.trim(),
                          ),
                          unitLabel: selectedUnit?.displayLabel,
                          propertyCount: _rootNodes.length,
                          leafCount: _leafDrafts.length,
                        ),
                        const SizedBox(height: 12),
                        _WarningText(warning: duplicate.warning),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
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
                                'Start with a property node like Color, Size, or Material.',
                            isError: false,
                          )
                        : Column(
                            children: [
                              for (
                                var index = 0;
                                index < _rootNodes.length;
                                index++
                              ) ...[
                                _TreeNodeEditor(
                                  draft: _rootNodes[index],
                                  depth: 0,
                                  index: index,
                                  siblingCount: _rootNodes.length,
                                  readOnly: _isReadOnly,
                                  onAddProperty: () =>
                                      _addChildProperty(_rootNodes[index]),
                                  onAddValue: () =>
                                      _addChildValue(_rootNodes[index]),
                                  onMoveUp: index == 0
                                      ? null
                                      : () => _moveNode(
                                          _rootNodes,
                                          index,
                                          index - 1,
                                        ),
                                  onMoveDown: index == _rootNodes.length - 1
                                      ? null
                                      : () => _moveNode(
                                          _rootNodes,
                                          index,
                                          index + 1,
                                        ),
                                  onRemove: () =>
                                      _removeNode(_rootNodes, index),
                                  fieldDecoration: _fieldDecoration,
                                  buildChildEditor: _buildChildEditor,
                                ),
                                if (index != _rootNodes.length - 1)
                                  const SizedBox(height: 12),
                              ],
                            ],
                          ),
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
      index: index,
      siblingCount: siblings.length,
      readOnly: _isReadOnly,
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
      fieldDecoration: _fieldDecoration,
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

  ItemVariationNodeInput _toInput(_NodeDraft node, int? parentNodeId) {
    return ItemVariationNodeInput(
      id: node.id,
      parentNodeId: parentNodeId,
      kind: node.kind,
      name: node.nameController.text.trim(),
      displayName: node.isLeafValue
          ? node.displayNameController.text.trim()
          : '',
      children: node.children
          .map((child) => _toInput(child, node.id))
          .toList(growable: false),
    );
  }

  void _addTopLevelProperty() {
    setState(() {
      _rootNodes.add(_newDraft(ItemVariationNodeKind.property, null));
      _syncLeafDisplayNames();
    });
  }

  void _addChildProperty(_NodeDraft parent) {
    setState(() {
      final child = _newDraft(ItemVariationNodeKind.property, parent);
      parent.children.add(child);
      _syncLeafDisplayNames();
    });
  }

  void _addChildValue(_NodeDraft parent) {
    setState(() {
      final child = _newDraft(ItemVariationNodeKind.value, parent);
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

    final quantity = double.tryParse(_quantityController.text.trim());
    if (quantity == null || quantity <= 0) {
      setState(() {
        _localError = 'Enter a valid decimal quantity greater than zero.';
      });
      return;
    }
    if (_selectedGroupId == null || _selectedUnitId == null) {
      setState(() {
        _localError = 'Select both a group and a unit.';
      });
      return;
    }

    final itemsProvider = context.read<ItemsProvider>();
    final duplicate = itemsProvider.checkDuplicate(
      name: _nameController.text,
      quantity: quantity,
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
              quantity: quantity,
              groupId: _selectedGroupId!,
              unitId: _selectedUnitId!,
              variationTree: _variationTreeInputs,
            ),
          )
        : await itemsProvider.updateItem(
            UpdateItemInput(
              id: widget.item!.id,
              name: _nameController.text.trim(),
              alias: _aliasController.text.trim(),
              displayName: _displayNameController.text.trim(),
              quantity: quantity,
              groupId: _selectedGroupId!,
              unitId: _selectedUnitId!,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              Expanded(child: children[index]),
              if (index != children.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
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

  String _generateItemDisplayName(String name, String alias, double quantity) {
    final base = [
      name.trim(),
      alias.trim(),
    ].where((entry) => entry.isNotEmpty).join(' / ');
    if (base.isEmpty) {
      return _formatQuantity(quantity);
    }
    return '$base - ${_formatQuantity(quantity)}';
  }

  String _generateLeafDisplayName(_NodeDraft leaf) {
    final segments = <String>[];
    _NodeDraft? current = leaf;
    while (current != null) {
      if (current.kind == ItemVariationNodeKind.value &&
          current.parent != null &&
          current.parent!.kind == ItemVariationNodeKind.property) {
        final valueName = current.nameController.text.trim();
        if (valueName.isNotEmpty) {
          segments.insert(0, valueName);
        }
      }
      current = current.parent;
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
    required this.index,
    required this.siblingCount,
    required this.readOnly,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
    required this.fieldDecoration,
    required this.buildChildEditor,
    this.onAddProperty,
    this.onAddValue,
  });

  final _NodeDraft draft;
  final int depth;
  final int index;
  final int siblingCount;
  final bool readOnly;
  final VoidCallback? onAddProperty;
  final VoidCallback? onAddValue;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onRemove;
  final InputDecoration Function({
    required String label,
    required String helper,
  })
  fieldDecoration;
  final Widget Function(_NodeDraft child, int depth, List<_NodeDraft> siblings)
  buildChildEditor;

  @override
  Widget build(BuildContext context) {
    final title = draft.kind == ItemVariationNodeKind.property
        ? 'Property'
        : 'Value';
    return Container(
      margin: EdgeInsets.only(left: depth * 20),
      child: AppCard(
        backgroundColor: depth.isEven ? const Color(0xFFFBFCFF) : Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$title ${index + 1}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!readOnly) ...[
                  IconButton(
                    onPressed: onMoveUp,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    onPressed: onMoveDown,
                    icon: const Icon(Icons.arrow_downward),
                  ),
                  IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
            TextFormField(
              controller: draft.nameController,
              readOnly: readOnly,
              decoration: fieldDecoration(
                label: draft.kind == ItemVariationNodeKind.property
                    ? 'Property Name'
                    : 'Value Name',
                helper: draft.kind == ItemVariationNodeKind.property
                    ? 'Example: Color, Finish, Material'
                    : 'Example: Black, Matte, PET',
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Required';
                }
                return null;
              },
            ),
            if (draft.isLeafValue) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: draft.displayNameController,
                readOnly: readOnly,
                decoration: fieldDecoration(
                  label: 'Leaf Display Name',
                  helper: 'Auto-generated from the full path, but editable',
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Required';
                  }
                  return null;
                },
              ),
            ],
            if (!readOnly) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onAddValue != null)
                    AppButton(
                      label: 'Add Value',
                      icon: Icons.add,
                      variant: AppButtonVariant.secondary,
                      onPressed: onAddValue,
                    ),
                  if (onAddProperty != null)
                    AppButton(
                      label: 'Add Property',
                      icon: Icons.account_tree_outlined,
                      variant: AppButtonVariant.secondary,
                      onPressed: onAddProperty,
                    ),
                ],
              ),
            ],
            if (draft.children.isNotEmpty) ...[
              const SizedBox(height: 12),
              Column(
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
                      const SizedBox(height: 12),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
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
    required this.quantity,
    required this.unitLabel,
    required this.propertyCount,
    required this.leafCount,
  });

  final String displayName;
  final double? quantity;
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
            label: quantity == null
                ? 'Quantity pending'
                : _formatQuantity(quantity!),
          ),
          _PreviewChip(
            label: unitLabel == null ? 'Unit pending' : 'Unit: $unitLabel',
          ),
          _PreviewChip(label: 'Top properties: $propertyCount'),
          _PreviewChip(label: 'Leaf paths: $leafCount'),
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
