import 'package:flutter/material.dart';

import '../../core/widgets/searchable_select.dart';
import '../../features/items/domain/item_definition.dart';

class ExactItemVariationReference {
  const ExactItemVariationReference({
    required this.itemId,
    required this.variationLeafNodeId,
    required this.itemLabel,
    required this.variationPathLabel,
    this.stockLabel,
  });

  final int itemId;
  final int variationLeafNodeId;
  final String itemLabel;
  final String variationPathLabel;
  final String? stockLabel;

  String get key => '$itemId::$variationLeafNodeId';
  String get optionLabel {
    if (variationPathLabel.isEmpty) {
      return itemLabel;
    }
    if (variationPathLabel.startsWith(itemLabel)) {
      return variationPathLabel;
    }
    return '$itemLabel • $variationPathLabel';
  }
  String get searchText => '$itemLabel $variationPathLabel ${stockLabel ?? ''}';
}

String _buildNamingFormatLabel(ItemDefinition item, List<int> valueNodeIds) {
  final itemName = item.displayName.trim().isEmpty
      ? item.name
      : item.displayName;
  if (valueNodeIds.isEmpty) {
    return itemName;
  }

  // Build a map: propertyId -> selected value name, walking the tree
  final selectedValueIds = valueNodeIds.toSet();
  // Map property node id -> selected value name
  final propIdToValue = <int, String>{};
  for (final root in item.topLevelProperties) {
    ItemVariationNodeDefinition currentProperty = root;
    while (true) {
      final selectedValue = currentProperty.activeChildren
          .where((n) => n.kind == ItemVariationNodeKind.value)
          .where((n) => selectedValueIds.contains(n.id))
          .firstOrNull;
      if (selectedValue == null) break;
      final valName = selectedValue.name.trim().isEmpty
          ? selectedValue.displayName.trim()
          : selectedValue.name.trim();
      propIdToValue[currentProperty.id] = valName;
      final nextProp = selectedValue.activeChildren
          .where((n) => n.kind == ItemVariationNodeKind.property)
          .firstOrNull;
      if (nextProp == null) break;
      currentProperty = nextProp;
    }
  }

  final topProps = item.topLevelProperties;
  final parts = <String>[];

  // If naming format is specified, follow it
  if (item.namingFormat.isNotEmpty) {
    for (final token in item.namingFormat) {
      if (token == 'name') {
        parts.add(itemName);
      } else if (token.startsWith('prop_')) {
        final idx = int.tryParse(token.substring(5));
        if (idx != null && idx >= 0 && idx < topProps.length) {
          final value = propIdToValue[topProps[idx].id];
          if (value != null && value.isNotEmpty) {
            parts.add(value);
          }
        }
      }
    }
  }

  // Fallback: item name + all selected values in tree order
  if (parts.isEmpty) {
    parts.add(itemName);
    parts.addAll(propIdToValue.values.where((v) => v.isNotEmpty));
  }

  return parts.join(' ');
}

List<ExactItemVariationReference> buildExactItemVariationReferences(
  List<ItemDefinition> items,
) {
  final references = <ExactItemVariationReference>[];
  for (final item in items.where((item) => !item.isArchived)) {
    final roots = item.variationTree.where((node) => !node.isArchived).toList();
    if (roots.isEmpty) {
      references.add(
        ExactItemVariationReference(
          itemId: item.id,
          variationLeafNodeId: 0,
          itemLabel: item.displayName,
          variationPathLabel: '',
        ),
      );
      continue;
    }
    references.addAll(_leafSelections(item));
  }
  return references;
}

List<ExactItemVariationReference> _leafSelections(ItemDefinition item) {
  final references = <ExactItemVariationReference>[];
  
  void walk(List<ItemVariationNodeDefinition> nodes, List<ItemVariationNodeDefinition> pathNodes) {
    for (final node in nodes.where((node) => !node.isArchived)) {
      if (node.kind == ItemVariationNodeKind.value) {
        final nextPathNodes = [...pathNodes, node];
        final nextChildren = node.children
            .where((child) => !child.isArchived)
            .toList(growable: false);
        final childProperties = nextChildren
            .where((child) => child.kind == ItemVariationNodeKind.property)
            .toList(growable: false);
        if (childProperties.isEmpty) {
          final valueNodeIds = nextPathNodes.map((n) => n.id).toList();
          references.add(
            ExactItemVariationReference(
              itemId: item.id,
              variationLeafNodeId: node.id,
              itemLabel: item.displayName,
              variationPathLabel: _buildNamingFormatLabel(item, valueNodeIds),
            ),
          );
        }
        for (final property in childProperties) {
          walk(property.children, [...nextPathNodes, property]);
        }
      } else {
        walk(node.children, pathNodes);
      }
    }
  }

  walk(item.variationTree, const <ItemVariationNodeDefinition>[]);
  return references;
}

class ExactItemVariationSelectField extends StatelessWidget {
  const ExactItemVariationSelectField({
    super.key,
    required this.value,
    required this.references,
    required this.fieldKey,
    required this.enabled,
    required this.onChanged,
    this.labelText = 'Item + Variation',
    this.dialogTitle = 'Select Item Variation',
    this.searchHintText = 'Search item or variation path',
  });

  final String? value;
  final List<ExactItemVariationReference> references;
  final Key fieldKey;
  final bool enabled;
  final ValueChanged<ExactItemVariationReference?> onChanged;
  final String labelText;
  final String dialogTitle;
  final String searchHintText;

  @override
  Widget build(BuildContext context) {
    final referenceByKey = {
      for (final reference in references) reference.key: reference,
    };
    return SearchableSelectField<String?>(
      tapTargetKey: fieldKey,
      value: value,
      dialogTitle: dialogTitle,
      searchHintText: searchHintText,
      decoration: InputDecoration(
        labelText: labelText,
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      options: references
          .map(
            (reference) => SearchableSelectOption<String?>(
              value: reference.key,
              label: reference.optionLabel,
              searchText: reference.searchText,
            ),
          )
          .toList(growable: false),
      fieldEnabled: enabled,
      onChanged: (selectedKey) {
        onChanged(selectedKey == null ? null : referenceByKey[selectedKey]);
      },
    );
  }
}
