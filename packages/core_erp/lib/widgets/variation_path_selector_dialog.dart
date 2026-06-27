import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/soft_erp_theme.dart';
import '../core/widgets/app_button.dart';
import '../core/widgets/searchable_select.dart';
import '../features/items/domain/item_definition.dart';
import '../features/items/presentation/providers/items_provider.dart';
import '../features/units/domain/unit_definition.dart';
import '../features/units/presentation/providers/units_provider.dart';

class VariationStep {
  const VariationStep({
    required this.property,
    required this.values,
    required this.selectedValueId,
  });

  final ItemVariationNodeDefinition property;
  final List<ItemVariationNodeDefinition> values;
  final int? selectedValueId;
}

class VariationPathSelectionResult {
  const VariationPathSelectionResult({
    required this.item,
    required this.rootPropertyId,
    required this.valueNodeIds,
    required this.leaf,
  });

  final ItemDefinition item;
  final int? rootPropertyId;
  final List<int> valueNodeIds;
  final ItemVariationNodeDefinition? leaf;
}

typedef VariationValueCreator =
    Future<QuickCreateVariationValueResult?> Function({
      required ItemDefinition item,
      required int propertyNodeId,
      required String propertyLabel,
      required String valueName,
      int? unitId,
    });

class VariationPathSelectorDialog extends StatefulWidget {
  const VariationPathSelectorDialog({
    super.key,
    required this.item,
    required this.initialRootPropertyId,
    required this.initialValueNodeIds,
    this.onCreateValue,
    this.readOnly = false,
  });

  final ItemDefinition item;
  final int? initialRootPropertyId;
  final List<int> initialValueNodeIds;
  final VariationValueCreator? onCreateValue;
  final bool readOnly;

  @override
  State<VariationPathSelectorDialog> createState() =>
      _VariationPathSelectorDialogState();
}

class _VariationPathSelectorDialogState
    extends State<VariationPathSelectorDialog> {
  late ItemDefinition _item;
  late int? _selectedRootPropertyId;
  late List<int> _selectedValueNodeIds;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _selectedRootPropertyId = widget.initialRootPropertyId;
    _selectedValueNodeIds = List<int>.from(widget.initialValueNodeIds);
    if (_selectedRootPropertyId == null &&
        _item.topLevelProperties.length == 1) {
      _selectedRootPropertyId = _item.topLevelProperties.first.id;
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

    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Variation Path',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _item.displayName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: SoftErpTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
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
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SoftErpTheme.cardSurfaceAlt,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: SoftErpTheme.border),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (
                      var stepIndex = 0;
                      stepIndex < steps.length;
                      stepIndex++
                    ) ...[
                      _buildStepRow(
                        title: _variationStepTitle(steps[stepIndex]),
                        isComplete: steps[stepIndex].selectedValueId != null,
                        child: _buildStepField(steps[stepIndex]),
                      ),
                      if (stepIndex != steps.length - 1)
                        const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 10,
            children: [
              AppButton(
                label: widget.readOnly ? 'Close' : 'Cancel',
                variant: AppButtonVariant.secondary,
                onPressed: () => Navigator.of(context).pop(),
              ),
              if (!widget.readOnly)
                AppButton(
                  label: 'Apply Path',
                  onPressed: selectedLeaf == null ? null : _submit,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepField(VariationStep step) {
    final fieldKey = ValueKey<String>(
      'orders-variation-step-${step.property.id}',
    );
    return SearchableSelectField<int>(
      key: fieldKey,
      tapTargetKey: fieldKey,
      value: step.selectedValueId,
      fieldEnabled: !widget.readOnly,
      decoration: const InputDecoration(
        hintText: 'Select value',
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      dialogTitle: step.property.name.trim().isEmpty
          ? 'Variation Value'
          : step.property.name.trim(),
      searchHintText: 'Search value',
      createOptionLabelBuilder: widget.readOnly || widget.onCreateValue == null
          ? null
          : (query) => 'Create value "$query"',
      onCreateOption: widget.readOnly || widget.onCreateValue == null
          ? null
          : (query) async {
              var valueName = query;
              int? unitId;
              // Enhancement 3 — measurable properties capture a quantity + unit
              // before the value is created (stored as e.g. "100 g").
              if (step.property.isMeasurable) {
                final measured = await _promptMeasurableValue(step, query);
                if (!mounted || measured == null) {
                  return null;
                }
                valueName = measured.name;
                unitId = measured.unitId;
              }
              final result = await widget.onCreateValue!(
                item: _item,
                propertyNodeId: step.property.id,
                propertyLabel: step.property.name.trim().isEmpty
                    ? 'Property ${step.property.id}'
                    : step.property.name.trim(),
                valueName: valueName,
                unitId: unitId,
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
              return SearchableSelectOption<int>(
                value: result.createdValueNode.id,
                label: result.createdValueNode.name.trim().isEmpty
                    ? result.createdValueNode.displayName
                    : result.createdValueNode.name.trim(),
              );
            },
      options: step.values
          .map(
            (value) => SearchableSelectOption<int>(
              value: value.id,
              label: value.name.trim().isEmpty
                  ? value.displayName
                  : value.name.trim(),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        setState(() {
          _replaceSelectionUnderProperty(
            step.property,
            value == null ? const <int>[] : <int>[value],
          );
        });
      },
    );
  }

  /// Prompts for a quantity + unit for a measurable property and returns the
  /// composed value name (e.g. "100 g") with the chosen unit id.
  Future<({String name, int? unitId})?> _promptMeasurableValue(
    VariationStep step,
    String initialQuery,
  ) async {
    final allUnits = context.read<UnitsProvider>().activeUnits;
    final allowed = step.property.allowedUnitIds;
    final units = allowed.isEmpty
        ? allUnits
        : allUnits
              .where((unit) => allowed.contains(unit.id))
              .toList(growable: false);
    return showDialog<({String name, int? unitId})>(
      context: context,
      builder: (dialogContext) => _MeasurableValuePrompt(
        propertyLabel: step.property.name.trim().isEmpty
            ? 'value'
            : step.property.name.trim(),
        initialQuantity: initialQuery,
        units: units,
      ),
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

  Widget _buildStepRow({
    required String title,
    required bool isComplete,
    required Widget child,
  }) {
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
                ),
              ),
              if (!isComplete) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.error_outline_rounded,
                  size: 14,
                  color: Color(0xFFEF4444),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
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
    var currentProperty = rootProperty;
    while (true) {
      final values = currentProperty.activeChildren
          .where((node) => node.kind == ItemVariationNodeKind.value)
          .toList(growable: false);
      final selectedValue = values
          .where((node) => _selectedValueNodeIds.contains(node.id))
          .firstOrNull;
      steps.add(
        VariationStep(
          property: currentProperty,
          values: values,
          selectedValueId: selectedValue?.id,
        ),
      );
      final nextProperty = selectedValue?.activeChildren
          .where((node) => node.kind == ItemVariationNodeKind.property)
          .firstOrNull;
      if (nextProperty == null) {
        break;
      }
      currentProperty = nextProperty;
    }
    return steps;
  }

  ItemVariationNodeDefinition? _resolveLeafFromSelection() {
    if (_item.topLevelProperties.isEmpty || _selectedValueNodeIds.isEmpty) {
      return null;
    }
    final terminalValues = <ItemVariationNodeDefinition>[];
    for (final rootProperty in _item.topLevelProperties) {
      ItemVariationNodeDefinition currentProperty = rootProperty;
      while (true) {
        final currentValue = currentProperty.activeChildren
            .where((node) => node.kind == ItemVariationNodeKind.value)
            .where((node) => _selectedValueNodeIds.contains(node.id))
            .firstOrNull;
        if (currentValue == null) {
          return null;
        }
        final nextProperty = currentValue.activeChildren
            .where((node) => node.kind == ItemVariationNodeKind.property)
            .firstOrNull;
        if (nextProperty == null) {
          if (!currentValue.isLeafValue) {
            return null;
          }
          terminalValues.add(currentValue);
          break;
        }
        currentProperty = nextProperty;
      }
    }
    return terminalValues.isEmpty ? null : terminalValues.first;
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

  void _submit() {
    final leaf = _resolveLeafFromSelection();
    Navigator.of(context).pop(
      VariationPathSelectionResult(
        item: _item,
        rootPropertyId: null,
        valueNodeIds: List<int>.from(_selectedValueNodeIds),
        leaf: leaf,
      ),
    );
  }
}

/// Quantity + unit capture for a measurable property value (Enhancement 3).
class _MeasurableValuePrompt extends StatefulWidget {
  const _MeasurableValuePrompt({
    required this.propertyLabel,
    required this.initialQuantity,
    required this.units,
  });

  final String propertyLabel;
  final String initialQuantity;
  final List<UnitDefinition> units;

  @override
  State<_MeasurableValuePrompt> createState() => _MeasurableValuePromptState();
}

class _MeasurableValuePromptState extends State<_MeasurableValuePrompt> {
  late final TextEditingController _quantityController;
  int? _unitId;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-fill the quantity if the user already typed a number.
    final trimmed = widget.initialQuantity.trim();
    _quantityController = TextEditingController(
      text: double.tryParse(trimmed) != null ? trimmed : '',
    );
    if (widget.units.length == 1) {
      _unitId = widget.units.first.id;
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  void _confirm() {
    final quantity = _quantityController.text.trim();
    if (quantity.isEmpty) {
      setState(() => _error = 'Enter a quantity.');
      return;
    }
    if (_unitId == null) {
      setState(() => _error = 'Select a unit.');
      return;
    }
    final unit = widget.units.where((u) => u.id == _unitId).firstOrNull;
    final symbol = unit == null || unit.symbol.trim().isEmpty
        ? (unit?.name ?? '')
        : unit.symbol.trim();
    final name = symbol.isEmpty ? quantity : '$quantity $symbol';
    Navigator.of(context).pop((name: name, unitId: _unitId));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add ${widget.propertyLabel}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _quantityController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Quantity',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _confirm(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _unitId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Unit',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final unit in widget.units)
                DropdownMenuItem<int>(
                  value: unit.id,
                  child: Text(
                    unit.symbol.trim().isEmpty
                        ? unit.name
                        : '${unit.name} (${unit.symbol})',
                  ),
                ),
            ],
            onChanged: (value) => setState(() {
              _unitId = value;
              _error = null;
            }),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _confirm, child: const Text('Add')),
      ],
    );
  }
}

extension _FirstOrNullUnits on Iterable<UnitDefinition> {
  UnitDefinition? get firstOrNull => isEmpty ? null : first;
}
