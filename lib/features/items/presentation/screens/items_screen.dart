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
import '../../../inventory/domain/group_property_draft.dart' as governance;
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../units/presentation/screens/units_screen.dart';
import '../../../units/presentation/providers/units_provider.dart';
import '../../domain/item_definition.dart';
import '../../domain/item_inputs.dart';
import '../providers/items_provider.dart';
import '../widgets/item_card.dart';
import '../widgets/item_detail_panel.dart';

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key});

  static Future<ItemDefinition?> openEditor(
    BuildContext context, {
    ItemDefinition? item,
    String initialName = '',
    int? initialGroupId,
  }) {
    final isNarrow = MediaQuery.of(context).size.width < 980;
    final body = _ItemEditorSheet(
      item: item,
      initialName: initialName,
      initialGroupId: initialGroupId,
    );
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

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  bool _isGridView = false;
  double _cardWidth = 200;
  double _cardHeight = 250;

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
            onPressed: () => ItemsScreen.openEditor(context),
          ),
          toolbar: _ItemsToolbar(
            isGridView: _isGridView,
            cardWidth: _cardWidth,
            cardHeight: _cardHeight,
            onToggleView: () {
              setState(() {
                _isGridView = !_isGridView;
              });
            },
            onCardWidthChanged: (value) {
              setState(() {
                _cardWidth = value;
              });
            },
            onCardHeightChanged: (value) {
              setState(() {
                _cardHeight = value;
              });
            },
          ),
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
              : _isGridView
              ? _ItemsGrid(
                  items: items.filteredItems,
                  cardWidth: _cardWidth,
                  cardHeight: _cardHeight,
                )
              : _ItemsTable(items: items.filteredItems),
        );
      },
    );
  }
}

class _ItemsToolbar extends StatelessWidget {
  const _ItemsToolbar({
    required this.isGridView,
    required this.cardWidth,
    required this.cardHeight,
    required this.onToggleView,
    required this.onCardWidthChanged,
    required this.onCardHeightChanged,
  });

  final bool isGridView;
  final double cardWidth;
  final double cardHeight;
  final VoidCallback onToggleView;
  final ValueChanged<double> onCardWidthChanged;
  final ValueChanged<double> onCardHeightChanged;

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
        _ItemsViewToggleButton(isGridView: isGridView, onTap: onToggleView),
        if (isGridView)
          _ItemsGridSizeControls(
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            onCardWidthChanged: onCardWidthChanged,
            onCardHeightChanged: onCardHeightChanged,
          ),
      ],
    );
  }
}

class _ItemsGridSizeControls extends StatelessWidget {
  const _ItemsGridSizeControls({
    required this.cardWidth,
    required this.cardHeight,
    required this.onCardWidthChanged,
    required this.onCardHeightChanged,
  });

  final double cardWidth;
  final double cardHeight;
  final ValueChanged<double> onCardWidthChanged;
  final ValueChanged<double> onCardHeightChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('items-grid-size-controls'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _ItemsGridSlider(
            sliderKey: const ValueKey<String>('items-card-width-slider'),
            icon: Icons.horizontal_distribute_rounded,
            value: cardWidth,
            min: 120,
            max: 400,
            onChanged: onCardWidthChanged,
          ),
          _ItemsGridSlider(
            sliderKey: const ValueKey<String>('items-card-height-slider'),
            icon: Icons.vertical_distribute_rounded,
            value: cardHeight,
            min: 150,
            max: 500,
            onChanged: onCardHeightChanged,
          ),
        ],
      ),
    );
  }
}

class _ItemsGridSlider extends StatelessWidget {
  const _ItemsGridSlider({
    required this.sliderKey,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final Key sliderKey;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: SoftErpTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFFE4C17C),
                thumbColor: const Color(0xFFE4C17C),
                overlayColor: const Color(0xFFE4C17C).withValues(alpha: 0.18),
                inactiveTrackColor: const Color(0xFFE9E7DF),
                trackHeight: 2.5,
              ),
              child: Slider.adaptive(
                key: sliderKey,
                value: value,
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemsViewToggleButton extends StatelessWidget {
  const _ItemsViewToggleButton({required this.isGridView, required this.onTap});

  final bool isGridView;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey<String>('items-view-toggle-button'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: SoftErpTheme.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SoftErpTheme.border),
            boxShadow: SoftErpTheme.insetShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isGridView
                    ? Icons.view_headline_rounded
                    : Icons.grid_view_rounded,
                size: 18,
                color: SoftErpTheme.textPrimary,
              ),
              const SizedBox(width: 10),
              Text(
                isGridView ? 'List View' : 'Card View',
                style: const TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
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
        SoftTableColumn('Unit', flex: 2),
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

class _ItemsGrid extends StatelessWidget {
  const _ItemsGrid({
    required this.items,
    required this.cardWidth,
    required this.cardHeight,
  });

  final List<ItemDefinition> items;
  final double cardWidth;
  final double cardHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final spacing = width >= 1200 ? 18.0 : 14.0;

        return GridView.builder(
          key: const ValueKey<String>('items-grid-view'),
          padding: const EdgeInsets.only(bottom: 12),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: cardWidth,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: cardWidth / cardHeight,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) => _GridItemCard(item: items[index]),
        );
      },
    );
  }
}

class _GridItemCard extends StatelessWidget {
  const _GridItemCard({required this.item});

  final ItemDefinition item;

  @override
  Widget build(BuildContext context) {
    return ItemCard(
      item: item,
      onTap: () => showItemDetailPanel(
        context,
        item: item,
        onEdit: () => ItemsScreen.openEditor(context, item: item),
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
        : '${item.leafVariationNodes.length} orderable leaf${item.leafVariationNodes.length == 1 ? '' : 's'}';

    return SoftMasterRow(
      onTap: () => showItemDetailPanel(
        context,
        item: item,
        onEdit: () => ItemsScreen.openEditor(context, item: item),
      ),
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
        Expanded(flex: 2, child: SoftInlineText(unitLabel)),
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
                label: 'Edit',
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
  bool inheritedFromGroup = false;
  bool inheritedMandatory = false;
  String? inheritedPropertyKey;
  int? inheritedSourceGroupId;
  String? inheritedSourceGroupName;
  final List<_NodeDraft> children;

  bool get isLeafValue =>
      kind == ItemVariationNodeKind.value && children.isEmpty;

  bool get isLockedInheritedProperty =>
      inheritedFromGroup && kind == ItemVariationNodeKind.property;

  void dispose() {
    nameController.dispose();
    codeController.dispose();
    displayNameController.dispose();
    for (final child in children) {
      child.dispose();
    }
  }
}

class _UnitConversionDraft {
  _UnitConversionDraft({required this.unitId, double unitsPerPrimary = 1})
    : factorController = TextEditingController(
        text: _formatUnitConversionFactor(unitsPerPrimary),
      );

  final int unitId;
  final TextEditingController factorController;

  double get unitsPerPrimary =>
      double.tryParse(factorController.text.trim()) ?? 1.0;

  void dispose() {
    factorController.dispose();
  }
}

String _formatUnitConversionFactor(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}

class _ItemEditorSheet extends StatefulWidget {
  const _ItemEditorSheet({
    this.item,
    this.initialName = '',
    this.initialGroupId,
  });

  final ItemDefinition? item;
  final String initialName;
  final int? initialGroupId;

  @override
  State<_ItemEditorSheet> createState() => _ItemEditorSheetState();
}

class _ItemEditorSheetState extends State<_ItemEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _aliasController;
  late final TextEditingController _displayNameController;
  final List<_NodeDraft> _rootNodes = [];
  final ScrollController _variationTreeScrollController = ScrollController();
  int? _selectedGroupId;
  int? _selectedUnitId;
  bool _displayNameTouched = false;
  bool _syncingDisplayName = false;
  List<String> _namingFormat = [];
  String? _localError;
  final List<_UnitConversionDraft> _secondaryUnitConversions = [];
  final Set<String> _promotedPropertyKeys = <String>{};
  bool _isLoadingGroupSchema = false;

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
    _selectedGroupId = widget.item?.groupId ?? widget.initialGroupId;
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
    _hydrateExistingGroupBackedNodes();
    for (final conversion in widget.item?.unitConversions ?? const []) {
      final draft = _UnitConversionDraft(
        unitId: conversion.unitId,
        unitsPerPrimary: conversion.factorToPrimary <= 0
            ? 1
            : 1 / conversion.factorToPrimary,
      );
      draft.factorController.addListener(_handleChange);
      _secondaryUnitConversions.add(draft);
    }

    _syncPrimaryDisplayName();
    _syncLeafDisplayNames();
    if (_selectedGroupId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadInheritedSchemaForGroup(_selectedGroupId!);
      });
    }
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

  List<int> get _orderedUnitIds => [
    ...?(_selectedUnitId == null ? null : <int>[_selectedUnitId!]),
    ..._secondaryUnitConversions.map((draft) => draft.unitId),
  ];

  void _rebuildUnitOrderFrom(
    List<int> orderedUnitIds,
    Map<int, double> unitsPerOldPrimary,
  ) {
    for (final draft in _secondaryUnitConversions) {
      draft.dispose();
    }
    _secondaryUnitConversions.clear();
    _selectedUnitId = orderedUnitIds.isEmpty ? null : orderedUnitIds.first;
    if (_selectedUnitId == null) {
      return;
    }
    final newPrimaryUnitsPerOldPrimary =
        unitsPerOldPrimary[_selectedUnitId!] ?? 1;
    for (final unitId in orderedUnitIds.skip(1)) {
      final unitsPerPrimary =
          (unitsPerOldPrimary[unitId] ?? 1) / newPrimaryUnitsPerOldPrimary;
      final draft = _UnitConversionDraft(
        unitId: unitId,
        unitsPerPrimary: unitsPerPrimary,
      );
      draft.factorController.addListener(_handleChange);
      _secondaryUnitConversions.add(draft);
    }
  }

  void _reorderUnits(int oldIndex, int newIndex) {
    final orderedUnitIds = _orderedUnitIds.toList(growable: true);
    if (orderedUnitIds.length < 2) {
      return;
    }
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    if (oldIndex < 0 ||
        oldIndex >= orderedUnitIds.length ||
        newIndex < 0 ||
        newIndex >= orderedUnitIds.length) {
      return;
    }
    final unitsPerOldPrimary = <int, double>{
      ...?(_selectedUnitId == null ? null : <int, double>{_selectedUnitId!: 1}),
      for (final draft in _secondaryUnitConversions)
        draft.unitId: draft.unitsPerPrimary,
    };
    final moved = orderedUnitIds.removeAt(oldIndex);
    orderedUnitIds.insert(newIndex, moved);
    _rebuildUnitOrderFrom(orderedUnitIds, unitsPerOldPrimary);
  }

  String _propertyKey(String value) => value.trim().toLowerCase();

  String _propertyKeyForNode(_NodeDraft node) =>
      _propertyKey(node.inheritedPropertyKey ?? node.nameController.text);

  void _hydrateExistingGroupBackedNodes() {
    for (final node in _rootNodes) {
      if (node.kind != ItemVariationNodeKind.property) {
        continue;
      }
      final schemaEntry = _propertySchemaForNode(node);
      if (schemaEntry == null || schemaEntry.sourceType != 'inherited_group') {
        continue;
      }
      node.inheritedFromGroup = true;
      node.inheritedMandatory = schemaEntry.mandatory;
      node.inheritedPropertyKey = schemaEntry.propertyKey;
      node.inheritedSourceGroupId = schemaEntry.sourceGroupId;
      node.inheritedSourceGroupName = schemaEntry.sourceGroupName;
    }
  }

  void _resetInheritedFlags() {
    for (final node in _rootNodes) {
      if (node.kind != ItemVariationNodeKind.property) {
        continue;
      }
      node.inheritedFromGroup = false;
      node.inheritedMandatory = false;
      node.inheritedPropertyKey = null;
      node.inheritedSourceGroupId = null;
      node.inheritedSourceGroupName = null;
    }
  }

  void _applyEffectiveSchemaToRootNodes(
    List<governance.GroupPropertyDraft> propertyDrafts,
  ) {
    _resetInheritedFlags();
    final draftsByKey = <String, governance.GroupPropertyDraft>{
      for (final draft in propertyDrafts)
        _propertyKey(draft.propertyKey ?? draft.name): draft,
    };
    final matchedKeys = <String>{};
    for (final node in _rootNodes) {
      if (node.kind != ItemVariationNodeKind.property) {
        continue;
      }
      final key = _propertyKeyForNode(node);
      final draft = draftsByKey[key];
      if (draft == null) {
        continue;
      }
      matchedKeys.add(key);
      node.inheritedFromGroup = true;
      node.inheritedMandatory = draft.mandatory;
      node.inheritedPropertyKey = draft.propertyKey ?? key;
      node.inheritedSourceGroupId = draft.sourceGroupId;
      node.inheritedSourceGroupName = draft.sourceGroupName;
      if (node.nameController.text.trim().isEmpty) {
        node.nameController.text = draft.name;
      }
    }
    for (final entry in draftsByKey.entries) {
      if (matchedKeys.contains(entry.key)) {
        continue;
      }
      final node = _newDraft(ItemVariationNodeKind.property, null);
      node.nameController.text = entry.value.name;
      node.inheritedFromGroup = true;
      node.inheritedMandatory = entry.value.mandatory;
      node.inheritedPropertyKey = entry.value.propertyKey ?? entry.key;
      node.inheritedSourceGroupId = entry.value.sourceGroupId;
      node.inheritedSourceGroupName = entry.value.sourceGroupName;
      _rootNodes.add(node);
    }
  }

  Future<void> _loadInheritedSchemaForGroup(int groupId) async {
    setState(() {
      _isLoadingGroupSchema = true;
      _localError = null;
    });
    final schema = await context.read<InventoryProvider>().loadEffectiveSchema(
      groupId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoadingGroupSchema = false;
      if (schema != null) {
        _applyEffectiveSchemaToRootNodes(schema.propertyDrafts);
      }
    });
  }

  Future<void> _handleGroupChanged(int? value) async {
    setState(() {
      _selectedGroupId = value;
      _localError = null;
    });
    if (value == null) {
      setState(_resetInheritedFlags);
      return;
    }
    await _loadInheritedSchemaForGroup(value);
  }

  bool _isMandatoryInheritedPropertySatisfied(_NodeDraft node) {
    if (!node.inheritedFromGroup || !node.inheritedMandatory) {
      return true;
    }
    for (final child in node.children) {
      if (child.kind == ItemVariationNodeKind.value &&
          child.nameController.text.trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  String _groupInventoryBarcode(int groupId) {
    final linked = context
        .read<InventoryProvider>()
        .materials
        .where((record) => record.linkedGroupId == groupId)
        .firstOrNull;
    return linked?.barcode ?? 'GROUP-MASTER-$groupId';
  }

  ItemPropertySchemaEntry? _propertySchemaForNode(_NodeDraft node) {
    final key = _propertyKeyForNode(node);
    if (key.isEmpty) {
      return null;
    }
    return widget.item?.propertySchema
        .where((entry) => _propertyKey(entry.propertyKey) == key)
        .firstOrNull;
  }

  List<_TreeMetaPillSpec> _propertyMetaPillsForNode(_NodeDraft node) {
    if (node.kind != ItemVariationNodeKind.property) {
      return const <_TreeMetaPillSpec>[];
    }
    final propertyKey = _propertyKey(node.nameController.text);
    final schemaEntry = _propertySchemaForNode(node);
    final pills = <_TreeMetaPillSpec>[];
    if (node.inheritedFromGroup) {
      pills.add(
        const _TreeMetaPillSpec(
          label: 'Group schema',
          tone: _TreeMetaPillTone.inherited,
        ),
      );
      if (node.inheritedMandatory) {
        pills.add(
          const _TreeMetaPillSpec(
            label: 'Required',
            tone: _TreeMetaPillTone.required,
          ),
        );
      }
    } else if (schemaEntry != null) {
      switch (schemaEntry.sourceType) {
        case 'inherited_group':
          pills.add(
            _TreeMetaPillSpec(
              label: 'Group schema',
              tone: _TreeMetaPillTone.inherited,
            ),
          );
        case 'inherited_item':
          pills.add(
            _TreeMetaPillSpec(
              label: 'Inherited',
              tone: _TreeMetaPillTone.seeded,
            ),
          );
        default:
          pills.add(
            _TreeMetaPillSpec(
              label: 'Item local',
              tone: _TreeMetaPillTone.manual,
            ),
          );
      }
    } else {
      pills.add(
        _TreeMetaPillSpec(label: 'Item local', tone: _TreeMetaPillTone.manual),
      );
    }
    if (_promotedPropertyKeys.contains(propertyKey) &&
        !node.inheritedFromGroup &&
        schemaEntry?.sourceType != 'inherited_group') {
      pills.add(
        _TreeMetaPillSpec(label: 'Promoted', tone: _TreeMetaPillTone.promoted),
      );
    }
    return pills;
  }

  Future<void> _promotePropertyToGroup(_NodeDraft node) async {
    final groupId = _selectedGroupId;
    final propertyName = node.nameController.text.trim();
    if (groupId == null) {
      setState(() {
        _localError = 'Select a group before promoting a property.';
      });
      return;
    }
    if (node.kind != ItemVariationNodeKind.property || propertyName.isEmpty) {
      return;
    }
    final inventoryProvider = context.read<InventoryProvider>();
    final groupsProvider = context.read<GroupsProvider>();
    final itemsProvider = context.read<ItemsProvider>();
    final barcode = _groupInventoryBarcode(groupId);
    final configuration = await inventoryProvider.loadGroupConfiguration(
      barcode,
    );
    if (!mounted || configuration == null) {
      return;
    }
    final propertyKey = _propertyKey(propertyName);
    final schemaEntry = _propertySchemaForNode(node);
    final group = groupsProvider.findById(groupId);
    final nextDraft = governance.GroupPropertyDraft(
      name: propertyName,
      propertyKey: propertyKey,
      inputType: schemaEntry?.inputType ?? 'Text',
      mandatory: schemaEntry?.mandatory ?? false,
      unitId: schemaEntry?.unitId,
      unitSymbol: schemaEntry?.unitSymbol,
      unitLabel: schemaEntry?.unitLabel,
      sourceType: governance.GroupPropertySourceType.manual,
      state: governance.GroupPropertyState.active,
      sourceGroupId: groupId,
      sourceGroupName: group?.name,
    );
    final nextDrafts = [
      ...configuration.propertyDrafts.where(
        (draft) => _propertyKey(draft.propertyKey ?? draft.name) != propertyKey,
      ),
      nextDraft,
    ];
    final nextDiscarded = configuration.discardedPropertyKeys
        .where((key) => _propertyKey(key) != propertyKey)
        .toList(growable: false);
    await inventoryProvider.updateGroupConfiguration(
      barcode,
      inheritanceEnabled: configuration.inheritanceEnabled,
      selectedItemIds: configuration.selectedItemIds,
      propertyDrafts: nextDrafts,
      unitGovernance: configuration.unitGovernance,
      uiPreferences: configuration.uiPreferences,
      discardedPropertyKeys: nextDiscarded,
    );
    if (!mounted) {
      return;
    }
    if (inventoryProvider.errorMessage == null) {
      setState(() {
        _promotedPropertyKeys.add(propertyKey);
      });
      await groupsProvider.refresh();
      await itemsProvider.refresh();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Promoted "$propertyName" to group schema.')),
      );
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
    _variationTreeScrollController.dispose();
    for (final node in _rootNodes) {
      node.dispose();
    }
    for (final conv in _secondaryUnitConversions) {
      conv.dispose();
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
      groupId: _selectedGroupId,
      variationTree: _variationTreeInputs,
      excludeId: widget.item?.id,
    );
    final availableGroups = groupsProvider.activeGroups;
    final selectedGroup = groupsProvider.findById(_selectedGroupId);
    final availableUnits = unitsProvider.units
        .where((u) => !u.isArchived)
        .toList(growable: false);
    final selectedUnit = availableUnits
        .where((unit) => unit.id == _selectedUnitId)
        .firstOrNull;
    final primaryUnitSymbol = selectedUnit?.symbol ?? selectedUnit?.name ?? '';
    final alreadySelectedUnitIds = {
      ...(_selectedUnitId == null ? const <int>[] : <int>[_selectedUnitId!]),
      ..._secondaryUnitConversions.map((c) => c.unitId),
    };
    final addableUnits = unitsProvider.units
        .where((u) => !u.isArchived && !alreadySelectedUnitIds.contains(u.id))
        .toList(growable: false);
    final detailsSection = _SectionCard(
      title: 'Item Details',
      child: Column(
        children: [
          _formRow(
            children: [
              _responsiveFieldPair(
                first: _buildTextField(
                  controller: _nameController,
                  label: 'Name',
                  helper: 'Base commercial item name',
                  readOnly: _isReadOnly,
                ),
                second: _buildTextField(
                  controller: _aliasController,
                  label: 'Alias',
                  helper: 'Optional alternate label',
                  readOnly: _isReadOnly,
                  required: false,
                ),
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
                  helper: 'Use the group to classify the item.',
                ),
                dialogTitle: 'Group',
                searchHintText: 'Search group',
                fieldEnabled: !_isReadOnly,
                onCreateOption: (query) async {
                  final created = await GroupsScreen.openEditor(
                    context,
                    initialName: query,
                  );
                  if (!context.mounted || created == null) {
                    return null;
                  }
                  await context.read<GroupsProvider>().refresh();
                  if (!context.mounted) {
                    return null;
                  }
                  final refreshedGroupsProvider = context
                      .read<GroupsProvider>();
                  await _handleGroupChanged(created.id);
                  return SearchableSelectOption<int>(
                    value: created.id,
                    label: _groupOptionLabel(created, refreshedGroupsProvider),
                    searchText: _groupOptionSearchText(
                      created,
                      refreshedGroupsProvider,
                    ),
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
                onChanged: (value) => _handleGroupChanged(value),
                validator: (value) => value == null ? 'Required' : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _formRow(
            children: [
              SearchableSelectField<int>(
                tapTargetKey: const ValueKey<String>('items-unit-field'),
                value: null,
                decoration: _fieldDecoration(
                  label: selectedUnit == null ? 'Unit' : 'Add another unit',
                  helper:
                      'Select units for this item. Each selection appears below.',
                ),
                dialogTitle: selectedUnit == null ? 'Unit' : 'Add another unit',
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
                  await context.read<UnitsProvider>().refresh();
                  if (!context.mounted) {
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
                  ...addableUnits.map(
                    (unit) => SearchableSelectOption<int>(
                      value: unit.id,
                      label: unit.displayLabel,
                    ),
                  ),
                ],
                onChanged: (value) => setState(() {
                  if (value == null) {
                    return;
                  }
                  _localError = null;
                  if (_selectedUnitId == null) {
                    _selectedUnitId = value;
                    return;
                  }
                  final exists = _secondaryUnitConversions.any(
                    (draft) => draft.unitId == value,
                  );
                  if (exists || value == _selectedUnitId) {
                    return;
                  }
                  final draft = _UnitConversionDraft(unitId: value);
                  draft.factorController.addListener(_handleChange);
                  _secondaryUnitConversions.add(draft);
                }),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (selectedUnit != null)
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                height: 54,
                child: ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  shrinkWrap: true,
                  proxyDecorator: (child, index, animation) {
                    return Material(color: Colors.transparent, child: child);
                  },
                  itemCount: _orderedUnitIds.length,
                  onReorder: _isReadOnly
                      ? (oldIndex, newIndex) {}
                      : (oldIndex, newIndex) =>
                            setState(() => _reorderUnits(oldIndex, newIndex)),
                  itemBuilder: (context, index) {
                    final unitId = _orderedUnitIds[index];
                    final unit = unitsProvider.findById(unitId);
                    return Padding(
                      key: ValueKey<String>('unit-bubble-$unitId'),
                      padding: EdgeInsets.only(
                        right: index == _orderedUnitIds.length - 1 ? 0 : 10,
                      ),
                      child: ReorderableDelayedDragStartListener(
                        index: index,
                        enabled: !_isReadOnly,
                        child: _UnitSelectionBubble(
                          label: unit?.displayLabel ?? 'Unit #$unitId',
                          onRemove: _isReadOnly
                              ? null
                              : () => setState(() {
                                  if (unitId == _selectedUnitId) {
                                    _selectedUnitId = null;
                                    for (final draft
                                        in _secondaryUnitConversions) {
                                      draft.dispose();
                                    }
                                    _secondaryUnitConversions.clear();
                                    return;
                                  }
                                  final draft = _secondaryUnitConversions
                                      .firstWhere(
                                        (entry) => entry.unitId == unitId,
                                      );
                                  _secondaryUnitConversions.remove(draft);
                                  draft.dispose();
                                }),
                        ),
                      ),
                    );
                  },
                ),
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Select a unit first.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey[400]),
              ),
            ),
          if (selectedUnit != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Arrange the unit bubbles to choose the base unit. Define how 1 ${selectedUnit.displayLabel} converts to the units on the right.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              ),
            ),
          ],
          if (_isLoadingGroupSchema) ...[
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
          if (_secondaryUnitConversions.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < _secondaryUnitConversions.length; i++) ...[
              _UnitConversionRow(
                draft: _secondaryUnitConversions[i],
                baseUnitSymbol: primaryUnitSymbol,
                unitLabel:
                    unitsProvider
                        .findById(_secondaryUnitConversions[i].unitId)
                        ?.displayLabel ??
                    '?',
                unitSymbol:
                    unitsProvider
                        .findById(_secondaryUnitConversions[i].unitId)
                        ?.symbol ??
                    '?',
                onRemove: () => setState(() {
                  _secondaryUnitConversions.removeAt(i).dispose();
                }),
              ),
              if (i != _secondaryUnitConversions.length - 1)
                const SizedBox(height: 8),
            ],
          ],
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
                          metaPills: _propertyMetaPillsForNode(
                            _rootNodes[index],
                          ),
                          onToggleBranch: () =>
                              _toggleNodeDetails(_rootNodes[index]),
                          onEnableNameEditing:
                              _rootNodes[index].isLockedInheritedProperty
                              ? null
                              : () => _setNodeNameEditing(
                                  _rootNodes[index],
                                  true,
                                ),
                          onFinishNameEditing:
                              _rootNodes[index].isLockedInheritedProperty
                              ? null
                              : () => _setNodeNameEditing(
                                  _rootNodes[index],
                                  false,
                                ),
                          onAddProperty:
                              _rootNodes[index].kind ==
                                  ItemVariationNodeKind.value
                              ? () => _addChildProperty(_rootNodes[index])
                              : null,
                          onPromoteToGroup:
                              _rootNodes[index].kind ==
                                      ItemVariationNodeKind.property &&
                                  _selectedGroupId != null &&
                                  !_isReadOnly &&
                                  !_rootNodes[index].isLockedInheritedProperty
                              ? () => _promotePropertyToGroup(_rootNodes[index])
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
                          onRemove: _rootNodes[index].isLockedInheritedProperty
                              ? null
                              : () => _removeNode(_rootNodes, index),
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
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.grey[600]),
                              ),
                              const SizedBox(height: 12),
                              if (_activeNamingFormat.isEmpty)
                                const Text(
                                  'Add properties to configure naming format.',
                                )
                              else
                                SizedBox(
                                  height: 42,
                                  child: ReorderableListView(
                                    scrollDirection: Axis.horizontal,
                                    proxyDecorator: (child, index, animation) {
                                      return Material(
                                        color: Colors.transparent,
                                        child: child,
                                      );
                                    },
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
                                    buildDefaultDragHandles: false,
                                    children: [
                                      ..._activeNamingFormat.asMap().entries.map(
                                        (entry) {
                                          final index = entry.key;
                                          final token = entry.value;
                                          return ReorderableDragStartListener(
                                            key: ValueKey(token),
                                            index: index,
                                            child: Container(
                                              margin: const EdgeInsets.only(
                                                right: 8,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF1F5F9),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: const Color(
                                                    0xFFE2E8F0,
                                                  ),
                                                ),
                                              ),
                                              alignment: Alignment.center,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    _getDisplayNameForToken(
                                                      token,
                                                    ),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: const Color(
                                                            0xFF334155,
                                                          ),
                                                        ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  const Icon(
                                                    Icons
                                                        .drag_indicator_rounded,
                                                    size: 16,
                                                    color: Color(0xFF94A3B8),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
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
      metaPills: _propertyMetaPillsForNode(child),
      onToggleBranch: () => _toggleNodeDetails(child),
      onEnableNameEditing: child.isLockedInheritedProperty
          ? null
          : () => _setNodeNameEditing(child, true),
      onFinishNameEditing: child.isLockedInheritedProperty
          ? null
          : () => _setNodeNameEditing(child, false),
      onAddProperty: child.kind == ItemVariationNodeKind.value
          ? () => _addChildProperty(child)
          : null,
      onPromoteToGroup:
          child.kind == ItemVariationNodeKind.property &&
              _selectedGroupId != null &&
              !_isReadOnly &&
              !child.isLockedInheritedProperty
          ? () => _promotePropertyToGroup(child)
          : null,
      onAddValue: child.kind == ItemVariationNodeKind.property
          ? () => _addChildValue(child)
          : null,
      onMoveUp: index == 0 ? null : () => _moveNode(siblings, index, index - 1),
      onMoveDown: index == siblings.length - 1
          ? null
          : () => _moveNode(siblings, index, index + 1),
      onRemove: child.isLockedInheritedProperty
          ? null
          : () => _removeNode(siblings, index),
      buildChildEditor: _buildChildEditor,
    );
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
    if (node.isLockedInheritedProperty) {
      return;
    }
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
    if (siblings[index].isLockedInheritedProperty) {
      return;
    }
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

    if (_selectedGroupId == null || _selectedUnitId == null) {
      setState(() {
        _localError = 'Select both a group and a unit.';
      });
      return;
    }
    for (final conversion in _secondaryUnitConversions) {
      if (conversion.unitsPerPrimary <= 0) {
        setState(() {
          _localError =
              'Every secondary unit conversion must be greater than 0.';
        });
        return;
      }
    }
    for (final node in _rootNodes) {
      if (!_isMandatoryInheritedPropertySatisfied(node)) {
        final propertyName = node.nameController.text.trim().isEmpty
            ? 'Unnamed Property'
            : node.nameController.text.trim();
        setState(() {
          _localError =
              'Provide at least one value for required property "$propertyName".';
        });
        return;
      }
    }

    final itemsProvider = context.read<ItemsProvider>();
    final duplicate = itemsProvider.checkDuplicate(
      name: _nameController.text,
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
              groupId: _selectedGroupId!,
              unitId: _selectedUnitId!,
              unitConversions: _secondaryUnitConversions
                  .map(
                    (draft) => ItemUnitConversionInput(
                      unitId: draft.unitId,
                      factorToPrimary: 1 / draft.unitsPerPrimary,
                    ),
                  )
                  .toList(growable: false),
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
              groupId: _selectedGroupId!,
              unitId: _selectedUnitId!,
              unitConversions: _secondaryUnitConversions
                  .map(
                    (draft) => ItemUnitConversionInput(
                      unitId: draft.unitId,
                      factorToPrimary: 1 / draft.unitsPerPrimary,
                    ),
                  )
                  .toList(growable: false),
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

  Widget _responsiveFieldPair({required Widget first, required Widget second}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(children: [first, const SizedBox(height: 12), second]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
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
      return group.name;
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
    final pathValueNames = <String>[];

    _NodeDraft? current = leaf;
    while (current != null) {
      if (current.kind == ItemVariationNodeKind.value &&
          current.parent != null &&
          current.parent!.kind == ItemVariationNodeKind.property) {
        final propNode = current.parent!;
        final valueName = current.nameController.text.trim();
        if (valueName.isNotEmpty) {
          pathValueNames.insert(0, valueName);
        }
        final propIndex = _rootNodes.indexOf(propNode);
        if (propIndex != -1 && valueName.isNotEmpty) {
          pathValues['prop_$propIndex'] = valueName;
        }
      }
      current = current.parent;
    }

    final segments = <String>[];
    for (final token in _activeNamingFormat) {
      if (token == 'name') {
        continue;
      }
      if (pathValues.containsKey(token)) {
        segments.add(pathValues[token]!);
      }
    }
    for (final value in pathValueNames) {
      if (value.isNotEmpty && !segments.contains(value)) {
        segments.add(value);
      }
    }
    return segments.join(' ');
  }

  String _duplicateMessage(ItemDuplicateWarning warning) {
    return switch (warning) {
      ItemDuplicateWarning.none => '',
      ItemDuplicateWarning.sameGroup =>
        'An item with this name already exists in the selected group.',
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
    required this.metaPills,
    required this.onToggleBranch,
    required this.onEnableNameEditing,
    required this.onFinishNameEditing,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
    required this.buildChildEditor,
    this.onAddProperty,
    this.onPromoteToGroup,
    this.onAddValue,
  });

  final _NodeDraft draft;
  final int depth;
  final bool readOnly;
  final String summaryLabel;
  final List<_TreeMetaPillSpec> metaPills;
  final VoidCallback onToggleBranch;
  final VoidCallback? onEnableNameEditing;
  final VoidCallback? onFinishNameEditing;
  final VoidCallback? onAddProperty;
  final VoidCallback? onPromoteToGroup;
  final VoidCallback? onAddValue;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onRemove;
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
                                onSubmitted: (_) => onFinishNameEditing?.call(),
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
                                onSubmitted: (_) => onFinishNameEditing?.call(),
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
                    if (metaPills.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            for (final pill in metaPills)
                              _TreeMetaPill(label: pill.label, tone: pill.tone),
                          ],
                        ),
                      ),
                    ],
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
                      if (onPromoteToGroup != null)
                        _TreeActionButton(
                          tooltip: 'Promote to group',
                          icon: Icons.upload_rounded,
                          onPressed: onPromoteToGroup,
                        ),
                      if (onEnableNameEditing != null)
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
                      if (onRemove != null)
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

enum _TreeMetaPillTone { manual, seeded, inherited, promoted, required }

class _TreeMetaPillSpec {
  const _TreeMetaPillSpec({required this.label, required this.tone});

  final String label;
  final _TreeMetaPillTone tone;
}

class _TreeMetaPill extends StatelessWidget {
  const _TreeMetaPill({required this.label, required this.tone});

  final String label;
  final _TreeMetaPillTone tone;

  (Color background, Color border, Color foreground) _colors() {
    return switch (tone) {
      _TreeMetaPillTone.manual => (
        const Color(0xFFF8FAFC),
        const Color(0xFFE2E8F0),
        const Color(0xFF475569),
      ),
      _TreeMetaPillTone.seeded => (
        const Color(0xFFEEF4FF),
        const Color(0xFFC7D2FE),
        const Color(0xFF4F46E5),
      ),
      _TreeMetaPillTone.inherited => (
        const Color(0xFFECFDF5),
        const Color(0xFFBBF7D0),
        const Color(0xFF15803D),
      ),
      _TreeMetaPillTone.promoted => (
        const Color(0xFFF5F3FF),
        const Color(0xFFC4B5FD),
        const Color(0xFF6D28D9),
      ),
      _TreeMetaPillTone.required => (
        const Color(0xFFFEF3C7),
        const Color(0xFFFCD34D),
        const Color(0xFFB45309),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (background, border, foreground) = _colors();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
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

class _UnitSelectionBubble extends StatelessWidget {
  const _UnitSelectionBubble({required this.label, this.onRemove});

  final String label;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFFF3F4F6);
    const borderColor = Color(0xFFE2E8F0);
    const textColor = Color(0xFF334155);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 6),
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(0.5),
                child: Icon(
                  Icons.close_rounded,
                  size: 13,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ],
      ),
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
      ItemDuplicateWarning.sameGroup =>
        'An item with this name already exists in the selected group.',
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

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _UnitConversionRow extends StatelessWidget {
  const _UnitConversionRow({
    required this.draft,
    required this.baseUnitSymbol,
    required this.unitLabel,
    required this.unitSymbol,
    required this.onRemove,
  });

  final _UnitConversionDraft draft;
  final String baseUnitSymbol;
  final String unitLabel;
  final String unitSymbol;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Text(
              '1 $baseUnitSymbol',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF334155),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '=',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF94A3B8),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: TextFormField(
              controller: draft.factorController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1F2937),
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFDCE2F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFDCE2F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF6366F1)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            unitSymbol,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF6366F1),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: onRemove,
            tooltip: 'Remove $unitLabel',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: const Icon(
              Icons.close_rounded,
              size: 16,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}
