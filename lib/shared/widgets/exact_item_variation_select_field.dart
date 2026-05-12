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
  String get optionLabel => variationPathLabel.isEmpty
      ? itemLabel
      : '$itemLabel • $variationPathLabel';
  String get searchText => '$itemLabel $variationPathLabel ${stockLabel ?? ''}';
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
  void walk(List<ItemVariationNodeDefinition> nodes, List<String> segments) {
    for (final node in nodes.where((node) => !node.isArchived)) {
      if (node.kind == ItemVariationNodeKind.value) {
        final nextSegments = [...segments, node.displayName];
        final nextChildren = node.children
            .where((child) => !child.isArchived)
            .toList(growable: false);
        final childProperties = nextChildren
            .where((child) => child.kind == ItemVariationNodeKind.property)
            .toList(growable: false);
        if (childProperties.isEmpty) {
          references.add(
            ExactItemVariationReference(
              itemId: item.id,
              variationLeafNodeId: node.id,
              itemLabel: item.displayName,
              variationPathLabel: nextSegments.join(' | '),
            ),
          );
        }
        for (final property in childProperties) {
          walk(property.children, nextSegments);
        }
      } else {
        walk(node.children, segments);
      }
    }
  }

  walk(item.variationTree, const <String>[]);
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
