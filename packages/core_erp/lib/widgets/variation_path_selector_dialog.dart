import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/soft_erp_theme.dart';
import '../core/widgets/app_button.dart';
import '../core/widgets/searchable_select.dart';
import '../features/items/domain/item_definition.dart';
import '../features/items/presentation/providers/items_provider.dart';

class VariationStep {
  const VariationStep({
    required this.property,
    required this.values,
    required this.selectedValueId,
    this.groupName,
  });

  final ItemVariationNodeDefinition property;
  final List<ItemVariationNodeDefinition> values;
  final int? selectedValueId;
  final String? groupName;
}

class VariationPathSelectionResult {
  const VariationPathSelectionResult({
    required this.item,
    required this.rootPropertyId,
    required this.valueNodeIds,
    required this.leaf,
    this.customVariationValues = const {},
  });

  final ItemDefinition item;
  final int? rootPropertyId;
  final List<int> valueNodeIds;
  final Map<int, String> customVariationValues;
  final ItemVariationNodeDefinition? leaf;
}

typedef VariationValueCreator =
    Future<QuickCreateVariationValueResult?> Function({
      required ItemDefinition item,
      required int propertyNodeId,
      required String propertyLabel,
      required String valueName,
    });

class VariationPathSelectorWidget extends StatefulWidget {
  const VariationPathSelectorWidget({
    super.key,
    required this.item,
    required this.initialRootPropertyId,
    required this.initialValueNodeIds,
    this.initialCustomVariationValues = const {},
    this.onCreateValue,
    this.readOnly = false,
    this.showHeaderAndFooter = false,
    this.useTilesForValues = false,
    this.onChanged,
    this.onComplete,
    this.onCancel,
  });

  final ItemDefinition item;
  final int? initialRootPropertyId;
  final List<int> initialValueNodeIds;
  final Map<int, String> initialCustomVariationValues;
  final VariationValueCreator? onCreateValue;
  final bool readOnly;
  final bool showHeaderAndFooter;
  final bool useTilesForValues;
  final ValueChanged<VariationPathSelectionResult>? onChanged;
  final ValueChanged<VariationPathSelectionResult>? onComplete;
  final VoidCallback? onCancel;

  @override
  State<VariationPathSelectorWidget> createState() =>
      _VariationPathSelectorWidgetState();
}

class _VariationPathSelectorWidgetState
    extends State<VariationPathSelectorWidget> {
  late ItemDefinition _item;
  late int? _selectedRootPropertyId;
  late List<int> _selectedValueNodeIds;
  final Map<int, String> _customVariationValues = {};

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _selectedRootPropertyId = widget.initialRootPropertyId;
    _selectedValueNodeIds = List<int>.from(widget.initialValueNodeIds);
    _customVariationValues.addAll(widget.initialCustomVariationValues);
    if (_selectedRootPropertyId == null &&
        _item.topLevelProperties.length == 1) {
      _selectedRootPropertyId = _item.topLevelProperties.first.id;
    }
  }

  @override
  void didUpdateWidget(covariant VariationPathSelectorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item != oldWidget.item) {
      setState(() {
        _item = widget.item;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _allVariationSteps();
    final selectedLeaf = _resolveLeafFromSelection();
    final totalSelectableSteps = steps.length;
    final selectedStepCount = steps
        .where((step) => step.selectedValueId != null)
        .length;

    final isTablet = MediaQuery.of(context).size.width >= 600;
    return Padding(
      padding: EdgeInsets.all(widget.showHeaderAndFooter ? 22 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showHeaderAndFooter) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose Variety',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: isTablet ? 22.0 : 18.0,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _item.displayName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: SoftErpTheme.textSecondary,
                          fontSize: isTablet ? 16.0 : 14.0,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 16.0 : 12.0,
                    vertical: isTablet ? 10.0 : 7.0,
                  ),
                  decoration: BoxDecoration(
                    color: SoftErpTheme.accentSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$selectedStepCount out of $totalSelectableSteps selected',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: SoftErpTheme.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: isTablet ? 14.0 : 12.0,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => widget.onCancel?.call(),
                  icon: Icon(Icons.close_rounded, size: isTablet ? 28.0 : 24.0),
                ),
              ],
            ),
          ],
          if (widget.showHeaderAndFooter) const SizedBox(height: 20),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: widget.showHeaderAndFooter
                  ? const EdgeInsets.all(16)
                  : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: widget.showHeaderAndFooter
                    ? SoftErpTheme.cardSurfaceAlt
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                border: widget.showHeaderAndFooter
                    ? Border.all(color: SoftErpTheme.border)
                    : null,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ..._buildStepsList(steps),
                  ],
                ),
              ),
            ),
          ),
          if (widget.showHeaderAndFooter) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? 20.0 : 16.0,
                vertical: isTablet ? 18.0 : 14.0,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: SoftErpTheme.border),
              ),
              child: Text(
                selectedLeaf == null
                    ? 'Complete the path by selecting each property.'
                    : _selectionSummaryLabel(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selectedLeaf == null
                      ? SoftErpTheme.textSecondary
                      : SoftErpTheme.textPrimary,
                  fontWeight: selectedLeaf == null
                      ? FontWeight.w500
                      : FontWeight.w700,
                  fontSize: isTablet ? 16.0 : 14.0,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (!widget.readOnly) ...[
                  AppButton(
                    label: 'Base',
                    variant: AppButtonVariant.secondary,
                    onPressed: _selectBasePath,
                  ),
                  const SizedBox(width: 10),
                ],
                AppButton(
                  label: widget.readOnly ? 'Close' : 'Cancel',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => widget.onCancel?.call(),
                ),
                const Spacer(),
                if (!widget.readOnly)
                  AppButton(
                    label: 'Apply',
                    onPressed: selectedLeaf == null ? null : _submit,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepField(VariationStep step) {
    final isTablet = MediaQuery.of(context).size.width >= 600;
    final fieldKey = ValueKey<String>(
      'orders-variation-step-${step.property.id}',
    );

    String propertyKey(String name) =>
        name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    final key = propertyKey(step.property.name);
    final schemaEntry = _item.propertySchema
        .where((e) => propertyKey(e.propertyKey) == key)
        .firstOrNull;
    final isNumeric = schemaEntry?.inputType == 'Numeric';

    if (isNumeric) {
      final existingVal =
          _customVariationValues[step.property.id] ??
          (step.selectedValueId != null && step.selectedValueId! > 0
              ? step.values
                        .where((v) => v.id == step.selectedValueId)
                        .firstOrNull
                        ?.name ??
                    ''
              : '');
      return TextFormField(
        key: fieldKey,
        initialValue: existingVal,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        enabled: !widget.readOnly,
        decoration: InputDecoration(
          hintText: 'Enter numeric value',
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: isTablet ? 18.0 : 14.0,
            vertical: isTablet ? 16.0 : 12.0,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
        onChanged: (val) {
          final text = val.trim();
          if (text.isEmpty) {
            _customVariationValues.remove(step.property.id);
            _replaceSelectionUnderProperty(step.property, const <int>[]);
          } else {
            _customVariationValues[step.property.id] = text;
            _replaceSelectionUnderProperty(step.property, <int>[
              -step.property.id,
            ]);
          }
          setState(() {});
          _notifyChanges();
        },
      );
    }

    if (widget.useTilesForValues && !isNumeric) {
      final options = [
        ...step.values.map(
          (value) => SearchableSelectOption<int>(
            value: value.id,
            label: value.name.trim().isEmpty
                ? value.displayName
                : value.name.trim(),
          ),
        ),
        if (step.selectedValueId != null &&
            step.selectedValueId! < 0 &&
            step.selectedValueId == -step.property.id)
          SearchableSelectOption<int>(
            value: -step.property.id,
            label: _customVariationValues[step.property.id] ?? 'Custom',
          ),
      ];

      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 2.5,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: options.length,
        itemBuilder: (context, index) {
          final option = options[index];
          final isSelected = step.selectedValueId == option.value;
          return InkWell(
            onTap: widget.readOnly
                ? null
                : () {
                    setState(() {
                      _replaceSelectionUnderProperty(
                        step.property,
                        <int>[option.value],
                      );
                    });
                    _notifyChanges();
                  },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? SoftErpTheme.accentSoft
                    : SoftErpTheme.shellSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? SoftErpTheme.accent
                      : SoftErpTheme.border,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Text(
                option.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected
                      ? SoftErpTheme.accent
                      : SoftErpTheme.textPrimary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          );
        },
      );
    }

    return SearchableSelectField<int>(
      key: fieldKey,
      tapTargetKey: fieldKey,
      value: step.selectedValueId,
      fieldEnabled: !widget.readOnly,
      decoration: InputDecoration(
        hintText: 'Select value',
        hintStyle: TextStyle(fontSize: isTablet ? 16.0 : 14.0),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: isTablet ? 18.0 : 14.0,
          vertical: isTablet ? 16.0 : 12.0,
        ),
      ),
      dialogTitle: step.property.name.trim().isEmpty
          ? 'Variation Value'
          : step.property.name.trim(),
      searchHintText: 'Search value',
      createOptionLabelBuilder: widget.readOnly || widget.onCreateValue == null
          ? null
          : (query) => 'Create value "$query"',
      secondaryCreateOptionLabelBuilder: widget.readOnly
          ? null
          : (query) => 'Enter custom value "$query"',
      onSecondaryCreateOption: widget.readOnly
          ? null
          : (query) async {
              final text = query.trim();
              _customVariationValues[step.property.id] = text;
              setState(() {
                _replaceSelectionUnderProperty(step.property, <int>[
                  -step.property.id,
                ]);
              });
              _notifyChanges();
              return SearchableSelectOption<int>(
                value: -step.property.id,
                label: text,
              );
            },
      onCreateOption: widget.readOnly || widget.onCreateValue == null
          ? null
          : (query) async {
              var valueName = query;
              final result = await widget.onCreateValue!(
                item: _item,
                propertyNodeId: step.property.id,
                propertyLabel: step.property.name.trim().isEmpty
                    ? 'Property ${step.property.id}'
                    : step.property.name.trim(),
                valueName: valueName,
              );
              if (!mounted || result == null) {
                return null;
              }
              setState(() {
                _item = result.item;
                final refreshedProperty = _findNodeById(
                  result.item.variationTree,
                  step.property.id,
                );
                _replaceSelectionUnderProperty(
                  refreshedProperty ?? step.property,
                  result.selectedValueNodeIds,
                );
              });
              _notifyChanges();
              return SearchableSelectOption<int>(
                value: result.createdValueNode.id,
                label: result.createdValueNode.name.trim().isEmpty
                    ? result.createdValueNode.displayName
                    : result.createdValueNode.name.trim(),
              );
            },
      options: [
        ...step.values.map(
          (value) => SearchableSelectOption<int>(
            value: value.id,
            label: value.name.trim().isEmpty
                ? value.displayName
                : value.name.trim(),
          ),
        ),
        if (step.selectedValueId != null &&
            step.selectedValueId! < 0 &&
            step.selectedValueId == -step.property.id)
          SearchableSelectOption<int>(
            value: -step.property.id,
            label: _customVariationValues[step.property.id] ?? 'Custom',
          ),
      ],
      onChanged: (value) {
        setState(() {
          _replaceSelectionUnderProperty(
            step.property,
            value == null ? const <int>[] : <int>[value],
          );
        });
        _notifyChanges();
      },
    );
  }

  List<VariationStep> _allVariationSteps() {
    return _item.topLevelProperties
        .expand(_variationSteps)
        .toList(growable: false);
  }

  String _variationStepTitle(VariationStep step) {
    final name = step.property.name.trim();
    return name.isEmpty ? 'Property ${step.property.id}' : name;
  }
  List<Widget> _buildStepsList(List<VariationStep> steps) {
    if (steps.isEmpty) return const [];
    
    final groups = <String?, List<VariationStep>>{};
    for (final step in steps) {
      groups.putIfAbsent(step.groupName, () => []).add(step);
    }
    
    final widgets = <Widget>[];
    var isFirstGroup = true;
    for (final groupEntry in groups.entries) {
      final groupName = groupEntry.key;
      final groupSteps = groupEntry.value;
      
      if (groupName != null) {
        widgets.add(
          Padding(
            padding: EdgeInsets.only(
              top: isFirstGroup ? 0 : 16,
              bottom: 8,
              left: 4,
            ),
            child: Text(
              groupName,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: SoftErpTheme.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
      isFirstGroup = false;

      if (widget.useTilesForValues) {
        for (var i = 0; i < groupSteps.length; i += 2) {
          final step1 = groupSteps[i];
          final step2 = i + 1 < groupSteps.length ? groupSteps[i + 1] : null;
          
          widgets.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildStepRow(
                    title: _variationStepTitle(step1),
                    isComplete: step1.selectedValueId != null,
                    child: _buildStepField(step1),
                  ),
                ),
                if (step2 != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStepRow(
                      title: _variationStepTitle(step2),
                      isComplete: step2.selectedValueId != null,
                      child: _buildStepField(step2),
                    ),
                  ),
                ] else ...[
                  const SizedBox(width: 12),
                  const Spacer(),
                ]
              ],
            )
          );
          if (i + 2 < groupSteps.length || groupEntry.key != groups.keys.last) {
            widgets.add(const SizedBox(height: 12));
          }
        }
      } else {
        for (var i = 0; i < groupSteps.length; i++) {
          final step = groupSteps[i];
          widgets.add(
            _buildStepRow(
              title: _variationStepTitle(step),
              isComplete: step.selectedValueId != null,
              child: _buildStepField(step),
            )
          );
          if (i != groupSteps.length - 1 || groupEntry.key != groups.keys.last) {
            widgets.add(const SizedBox(height: 12));
          }
        }
      }
    }
    
    if (widgets.isNotEmpty && widgets.last is SizedBox) {
      widgets.removeLast();
    }
    
    return widgets;
  }


  Widget _buildStepRow({
    required String title,
    required bool isComplete,
    required Widget child,
  }) {
    final isTablet = MediaQuery.of(context).size.width >= 600;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isComplete ? SoftErpTheme.border : const Color(0xFFFCA5A5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SoftErpTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: isTablet ? 16.0 : 14.0,
                ),
              ),
              if (!isComplete) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.error_outline_rounded,
                  size: isTablet ? 16.0 : 14.0,
                  color: const Color(0xFFEF4444),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isTablet ? 500.0 : 360.0),
            child: child,
          ),
        ],
      ),
    );
  }

  List<VariationStep> _variationSteps(
    ItemVariationNodeDefinition? rootProperty,
  ) {
    if (rootProperty == null) {
      return const <VariationStep>[];
    }
    final steps = <VariationStep>[];

    void traverse(ItemVariationNodeDefinition prop, [String? currentGroupName]) {
      final subProps = prop.activeChildren
          .where((node) => node.kind == ItemVariationNodeKind.property)
          .toList(growable: false);
      if (subProps.isNotEmpty) {
        // Property group
        final groupName = currentGroupName ?? prop.name.trim();
        for (final sp in subProps) {
          traverse(sp, groupName.isEmpty ? prop.displayName : groupName);
        }
      } else {
        // Leaf property
        final values = prop.activeChildren
            .where((node) => node.kind == ItemVariationNodeKind.value)
            .toList(growable: false);
        final selectedValue = values
            .where((node) => _selectedValueNodeIds.contains(node.id))
            .firstOrNull;

        final tempId = -prop.id;
        final hasTempSelection = _selectedValueNodeIds.contains(tempId);
        final activeSelectedId =
            selectedValue?.id ?? (hasTempSelection ? tempId : null);

        steps.add(
          VariationStep(
            property: prop,
            values: values,
            selectedValueId: activeSelectedId,
            groupName: currentGroupName,
          ),
        );

        if (hasTempSelection && selectedValue == null) {
          return; // Custom value doesn't have child properties
        }

        final nextProps =
            selectedValue?.activeChildren
                .where((node) => node.kind == ItemVariationNodeKind.property)
                .toList() ??
            [];
        for (final np in nextProps) {
          traverse(np);
        }
      }
    }

    traverse(rootProperty);
    return steps;
  }

  ItemVariationNodeDefinition? _resolveLeafFromSelection() {
    if (_item.topLevelProperties.isEmpty || _selectedValueNodeIds.isEmpty) {
      return null;
    }
    final terminalValues = <ItemVariationNodeDefinition>[];

    void findLeaf(ItemVariationNodeDefinition prop) {
      final subProps = prop.activeChildren.where(
        (n) => n.kind == ItemVariationNodeKind.property,
      );
      if (subProps.isNotEmpty) {
        for (final sp in subProps) findLeaf(sp);
        return;
      }

      final currentValue = prop.activeChildren
          .where((node) => node.kind == ItemVariationNodeKind.value)
          .where((node) => _selectedValueNodeIds.contains(node.id))
          .firstOrNull;

      if (currentValue == null) {
        final tempId = -prop.id;
        if (_selectedValueNodeIds.contains(tempId)) {
          terminalValues.add(
            ItemVariationNodeDefinition(
              id: tempId,
              itemId: _item.id,
              parentNodeId: prop.id,
              kind: ItemVariationNodeKind.value,
              name: _customVariationValues[prop.id] ?? 'Custom',
              displayName: _customVariationValues[prop.id] ?? 'Custom',
              position: 0,
              isArchived: false,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              children: const [],
            ),
          );
        }
        return;
      }

      final nextProps = currentValue.activeChildren
          .where((n) => n.kind == ItemVariationNodeKind.property)
          .toList();
      if (nextProps.isEmpty) {
        terminalValues.add(currentValue);
      } else {
        for (final np in nextProps) findLeaf(np);
      }
    }

    for (final rootProperty in _item.topLevelProperties) {
      findLeaf(rootProperty);
    }
    return terminalValues.isEmpty ? null : terminalValues.last;
  }

  void _replaceSelectionUnderProperty(
    ItemVariationNodeDefinition property,
    List<int> selectedValueIds,
  ) {
    final blockedValueIds = _valueIdsUnder(property);
    final nextValueNodeIds = <int>[];
    for (final id in <int>[
      ..._selectedValueNodeIds.where((id) => !blockedValueIds.contains(id)),
      ...selectedValueIds,
    ]) {
      if (!nextValueNodeIds.contains(id)) {
        nextValueNodeIds.add(id);
      }
    }
    _selectedValueNodeIds = nextValueNodeIds;
  }

  Set<int> _valueIdsUnder(ItemVariationNodeDefinition node) {
    final ids = <int>{};
    void visit(ItemVariationNodeDefinition current) {
      if (current.kind == ItemVariationNodeKind.value) {
        ids.add(current.id);
      } else if (current.kind == ItemVariationNodeKind.property) {
        ids.add(-current.id);
      }
      for (final child in current.children) {
        visit(child);
      }
    }

    visit(node);
    return ids;
  }

  ItemVariationNodeDefinition? _findNodeById(
    List<ItemVariationNodeDefinition> nodes,
    int id,
  ) {
    for (final node in nodes) {
      if (node.id == id) {
        return node;
      }
      final child = _findNodeById(node.children, id);
      if (child != null) {
        return child;
      }
    }
    return null;
  }

  String _selectionSummaryLabel() {
    final segments = <String>[];
    for (final step in _allVariationSteps()) {
      final selectedValue = step.values
          .where((value) => value.id == step.selectedValueId)
          .firstOrNull;
      if (selectedValue == null) {
        final tempId = -step.property.id;
        if (step.selectedValueId == tempId) {
          final val = _customVariationValues[step.property.id] ?? 'Custom';
          final propertyName = step.property.name.trim();
          segments.add(propertyName.isEmpty ? val : '$propertyName: $val');
        }
        continue;
      }
      final propertyName = step.property.name.trim();
      final valueName = selectedValue.name.trim().isEmpty
          ? selectedValue.displayName.trim()
          : selectedValue.name.trim();
      if (propertyName.isEmpty && valueName.isEmpty) {
        continue;
      }
      segments.add(
        valueName.isEmpty ? propertyName : '$propertyName: $valueName',
      );
    }
    return segments.isEmpty ? _item.displayName : segments.join(' / ');
  }

  void _notifyChanges() {
    final leaf = _resolveLeafFromSelection();
    widget.onChanged?.call(
      VariationPathSelectionResult(
        item: _item,
        rootPropertyId: _selectedRootPropertyId,
        valueNodeIds: List<int>.from(_selectedValueNodeIds),
        customVariationValues: Map.from(_customVariationValues),
        leaf: leaf,
      ),
    );
  }

  void _selectBasePath() {
    setState(() {
      _selectedValueNodeIds.clear();
      _customVariationValues.clear();

      void traverse(ItemVariationNodeDefinition prop) {
        final subProps = prop.activeChildren
            .where((n) => n.kind == ItemVariationNodeKind.property);
        if (subProps.isNotEmpty) {
          for (final sp in subProps) {
            traverse(sp);
          }
        } else {
          final values = prop.activeChildren
              .where((n) => n.kind == ItemVariationNodeKind.value)
              .toList(growable: false);
          if (values.isNotEmpty) {
            final firstValue = values.first;
            _selectedValueNodeIds.add(firstValue.id);
            final nextProps = firstValue.activeChildren
                .where((n) => n.kind == ItemVariationNodeKind.property);
            for (final np in nextProps) {
              traverse(np);
            }
          }
        }
      }

      for (final prop in _item.topLevelProperties) {
        traverse(prop);
      }
    });
    _notifyChanges();
  }

  void _submit() {
    final leaf = _resolveLeafFromSelection();
    widget.onComplete?.call(
      VariationPathSelectionResult(
        item: _item,
        rootPropertyId: _selectedRootPropertyId,
        valueNodeIds: List<int>.from(_selectedValueNodeIds),
        customVariationValues: Map.from(_customVariationValues),
        leaf: leaf,
      ),
    );
  }
}

class VariationPathSelectorDialog extends StatelessWidget {
  const VariationPathSelectorDialog({
    super.key,
    required this.item,
    required this.initialRootPropertyId,
    required this.initialValueNodeIds,
    this.initialCustomVariationValues = const {},
    this.onCreateValue,
    this.readOnly = false,
    this.useTilesForValues = false,
  });

  final ItemDefinition item;
  final int? initialRootPropertyId;
  final List<int> initialValueNodeIds;
  final Map<int, String> initialCustomVariationValues;
  final VariationValueCreator? onCreateValue;
  final bool readOnly;
  final bool useTilesForValues;

  @override
  Widget build(BuildContext context) {
    return Consumer<ItemsProvider>(
      builder: (context, provider, _) {
        final currentItem = provider.items.where((i) => i.id == item.id).firstOrNull ?? item;

        return VariationPathSelectorWidget(
          item: currentItem,
          initialRootPropertyId: initialRootPropertyId,
          initialValueNodeIds: initialValueNodeIds,
          initialCustomVariationValues: initialCustomVariationValues,
          onCreateValue: onCreateValue,
          readOnly: readOnly,
          useTilesForValues: useTilesForValues,
          showHeaderAndFooter: true,
          onComplete: (result) => Navigator.of(context).pop(result),
          onCancel: () => Navigator.of(context).pop(),
        );
      },
    );
  }
}
