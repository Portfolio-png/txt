import '../../domain/item_definition.dart';

class NamingFormatHelper {
  static String buildLabelForLeaf(
    ItemDefinition item,
    int leafNodeId, [
    Map<int, String> customVariationValues = const {},
  ]) {
    final path = _valuePathForLeaf(item.variationTree, leafNodeId);
    return buildNamingFormatLabel(item, path, customVariationValues);
  }

  /// Builds a display label using the item's naming format order.
  /// Format tokens: 'name' = item base name, 'prop_N' = Nth top-level
  /// property's selected value, '[Property]' = selected value for that property.
  static String buildNamingFormatLabel(
    ItemDefinition item,
    List<int> valueNodeIds, [
    Map<int, String> customVariationValues = const {},
  ]) {
    final itemName = item.displayName.trim().isEmpty
        ? item.name
        : item.displayName;
    if (valueNodeIds.isEmpty) {
      return itemName;
    }

    // Build a map: propertyId -> selected value name, walking the tree
    final selectedValueIds = valueNodeIds.toSet();
    final propIdToValue = <int, String>{};

    for (final root in item.topLevelProperties) {
      ItemVariationNodeDefinition currentProperty = root;
      while (true) {
        final selectedValue = currentProperty.activeChildren
            .where((n) => n.kind == ItemVariationNodeKind.value)
            .where((n) => selectedValueIds.contains(n.id))
            .firstOrNull;

        if (selectedValue == null) {
          final tempId = -currentProperty.id;
          if (selectedValueIds.contains(tempId)) {
            final valName = customVariationValues[currentProperty.id];
            if (valName != null) {
              propIdToValue[currentProperty.id] = valName;
            }
          }
          break;
        }

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
        } else if (token.startsWith('[') && token.endsWith(']')) {
          final propertyName = token.substring(1, token.length - 1).trim();
          final property = _activeProperties(topProps)
              .where(
                (prop) =>
                    prop.name.trim() == propertyName ||
                    prop.displayName.trim() == propertyName,
              )
              .firstOrNull;
          final value = property == null ? null : propIdToValue[property.id];
          if (value != null && value.isNotEmpty) {
            parts.add(value);
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

  static List<int> _valuePathForLeaf(
    List<ItemVariationNodeDefinition> nodes,
    int leafNodeId, [
    List<int> currentPath = const [],
  ]) {
    for (final node in nodes) {
      final nextPath = node.kind == ItemVariationNodeKind.value
          ? [...currentPath, node.id]
          : currentPath;
      if (node.kind == ItemVariationNodeKind.value &&
          node.id == leafNodeId &&
          node.activeChildren.isEmpty) {
        return nextPath;
      }
      final nested = _valuePathForLeaf(
        node.activeChildren,
        leafNodeId,
        nextPath,
      );
      if (nested.isNotEmpty) {
        return nested;
      }
    }
    return const <int>[];
  }

  static List<ItemVariationNodeDefinition> _activeProperties(
    List<ItemVariationNodeDefinition> nodes,
  ) {
    final result = <ItemVariationNodeDefinition>[];
    void visit(ItemVariationNodeDefinition node) {
      if (node.kind == ItemVariationNodeKind.property) {
        result.add(node);
      }
      for (final child in node.activeChildren) {
        visit(child);
      }
    }

    for (final node in nodes) {
      visit(node);
    }
    return result;
  }
}
