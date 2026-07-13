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

  final selectedValueIds = valueNodeIds.toSet();
  final propIdToValue = <int, String>{};

  void extractValues(ItemVariationNodeDefinition prop) {
    final subProps = prop.activeChildren.where(
      (n) => n.kind == ItemVariationNodeKind.property,
    );
    if (subProps.isNotEmpty) {
      for (final sp in subProps) extractValues(sp);
      return;
    }

    final selectedValue = prop.activeChildren
        .where((n) => n.kind == ItemVariationNodeKind.value)
        .where((n) => selectedValueIds.contains(n.id))
        .firstOrNull;

    if (selectedValue == null) return;

    final valName = selectedValue.name.trim().isEmpty
        ? selectedValue.displayName.trim()
        : selectedValue.name.trim();
    propIdToValue[prop.id] = valName;

    final nextProps = selectedValue.activeChildren.where(
      (n) => n.kind == ItemVariationNodeKind.property,
    );
    for (final np in nextProps) {
      extractValues(np);
    }
  }

  for (final root in item.topLevelProperties) {
    extractValues(root);
  }

  String getCombinedValue(
    ItemVariationNodeDefinition prop,
    bool isDetailed,
    bool isDimensions,
  ) {
    final subProps = prop.activeChildren.where(
      (n) => n.kind == ItemVariationNodeKind.property,
    );
    if (subProps.isNotEmpty) {
      final childVals = <String>[];
      for (final sp in subProps) {
        final val = getCombinedValue(sp, isDetailed, isDimensions);
        if (val.isNotEmpty) childVals.add(val);
      }
      if (childVals.isEmpty) return '';
      if (isDimensions) return childVals.join(' x ');
      return childVals.join(isDetailed ? ', ' : ' ');
    }

    final val = propIdToValue[prop.id];
    if (val == null || val.isEmpty) return '';
    return isDetailed ? '${prop.name.trim()}: $val' : val;
  }

  final topProps = item.topLevelProperties;
  final parts = <String>[];

  final isDetailed = item.namingFormat.contains('__format:detailed');
  final isDimensions = item.namingFormat.contains('__format:dimensions');
  if (item.namingFormat.isNotEmpty) {
    for (final token in item.namingFormat) {
      if (token == 'name') {
        parts.add(itemName);
      } else if (token.startsWith('prop_')) {
        final idx = int.tryParse(token.substring(5));
        if (idx != null && idx >= 0 && idx < topProps.length) {
          final prop = topProps[idx];
          final combinedValue = getCombinedValue(
            prop,
            isDetailed,
            isDimensions,
          );
          if (combinedValue.isNotEmpty) {
            parts.add(combinedValue);
          }
        }
      }
    }
  } else {
    parts.add(itemName);
    for (final root in item.topLevelProperties) {
      final combinedValue = getCombinedValue(root, isDetailed, isDimensions);
      if (combinedValue.isNotEmpty) {
        parts.add(combinedValue);
      }
    }
  }

  if (isDimensions) {
    final nameIndex = parts.indexOf(itemName);
    if (nameIndex != -1) {
      final variations = List<String>.from(parts)..removeAt(nameIndex);
      if (variations.isNotEmpty) {
        return '$itemName ${variations.join(' x ')}';
      }
    } else if (parts.isNotEmpty) {
      return parts.join(' x ');
    }
  }

  return parts.join(isDetailed ? ', ' : ' ');
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

  void walk(
    List<ItemVariationNodeDefinition> nodes,
    List<ItemVariationNodeDefinition> pathNodes,
  ) {
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
