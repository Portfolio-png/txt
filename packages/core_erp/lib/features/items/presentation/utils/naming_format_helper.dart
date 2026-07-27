import '../../domain/item_definition.dart';

class NamingFormatHelper {
  static String buildLabelForLeaf(
    ItemDefinition item,
    int leafNodeId, [
    Map<int, String> customVariationValues = const {},
    bool includeMissingPropertyPlaceholders = false,
  ]) {
    final path = _valuePathForLeaf(item.variationTree, leafNodeId);
    return buildNamingFormatLabel(
      item,
      path,
      customVariationValues,
      includeMissingPropertyPlaceholders,
    );
  }

  /// Builds a display label using the item's naming format order.
  /// Format tokens: 'name' = item base name, 'prop_N' = Nth top-level
  /// property's selected value, '[Property]' = selected value for that property.
  static String buildNamingFormatLabel(
    ItemDefinition item,
    List<int> valueNodeIds, [
    Map<int, String> customVariationValues = const {},
    bool includeMissingPropertyPlaceholders = false,
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
          final valName = customVariationValues[currentProperty.id];
          if (valName != null &&
              valName.trim().isNotEmpty &&
              (selectedValueIds.contains(tempId) ||
                  !propIdToValue.containsKey(currentProperty.id))) {
            propIdToValue[currentProperty.id] = valName.trim();
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
            } else if (includeMissingPropertyPlaceholders) {
              parts.add(_missingPropertyLabel(topProps[idx]));
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
          } else if (includeMissingPropertyPlaceholders && property != null) {
            parts.add(_missingPropertyLabel(property));
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

  /// Canonical label for a selected variation path, following the item's
  /// naming format order ('name' / 'prop_N' tokens, '__format:detailed' /
  /// '__format:dimensions' flags). Values only — property names appear only
  /// when the item is flagged detailed. With [includeItemName] false the
  /// item name is left out entirely (used for `variationPathLabel`, which is
  /// displayed next to the item name).
  static String buildVariationSelectionLabel(
    ItemDefinition item,
    List<int> valueNodeIds, [
    Map<int, String> customVariationValues = const {},
    bool includeItemName = true,
  ]) {
    final itemName = item.displayName.trim().isEmpty
        ? item.name
        : item.displayName;
    if (valueNodeIds.isEmpty) {
      return includeItemName ? itemName : '';
    }

    final selectedValueIds = valueNodeIds.toSet();
    final propIdToValue = <int, String>{};

    void extractValues(ItemVariationNodeDefinition prop) {
      final subProps = prop.activeChildren.where(
        (n) => n.kind == ItemVariationNodeKind.property,
      );
      if (subProps.isNotEmpty) {
        for (final sp in subProps) {
          extractValues(sp);
        }
        return;
      }

      final selectedValue = prop.activeChildren
          .where((n) => n.kind == ItemVariationNodeKind.value)
          .where((n) => selectedValueIds.contains(n.id))
          .firstOrNull;

      if (selectedValue == null) {
        final tempId = -prop.id;
        if (selectedValueIds.contains(tempId)) {
          final valName = customVariationValues[prop.id];
          if (valName != null) {
            propIdToValue[prop.id] = valName;
          }
        }
        return;
      }

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
      final base = isDetailed ? '${prop.name.trim()}: $val' : val;

      // Descend through the SELECTED value's own child properties (e.g.
      // type=sheet → size) so nested values reach the name. Sibling child
      // values combine with ' x ' in the Dimensions format ("sheet 14 x 48").
      final selectedValue = prop.activeChildren
          .where((n) => n.kind == ItemVariationNodeKind.value)
          .where((n) => selectedValueIds.contains(n.id))
          .firstOrNull;
      if (selectedValue == null) return base;
      final nested = <String>[];
      for (final np in selectedValue.activeChildren.where(
        (n) => n.kind == ItemVariationNodeKind.property,
      )) {
        final v = getCombinedValue(np, isDetailed, isDimensions);
        if (v.isNotEmpty) nested.add(v);
      }
      if (nested.isEmpty) return base;
      final joined = nested.join(
        isDimensions
            ? ' x '
            : isDetailed
            ? ', '
            : ' ',
      );
      return '$base $joined';
    }

    final topProps = item.topLevelProperties;
    final parts = <String>[];

    final isDetailed = item.namingFormat.contains('__format:detailed');
    final isDimensions = item.namingFormat.contains('__format:dimensions');
    if (item.namingFormat.isNotEmpty) {
      for (final token in item.namingFormat) {
        if (token == 'name') {
          if (includeItemName) {
            parts.add(itemName);
          }
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
      if (includeItemName) {
        parts.add(itemName);
      }
      for (final root in item.topLevelProperties) {
        final combinedValue = getCombinedValue(root, isDetailed, isDimensions);
        if (combinedValue.isNotEmpty) {
          parts.add(combinedValue);
        }
      }
    }

    // The Dimensions format scopes ' x ' to nested value groups (handled in
    // getCombinedValue); top-level parts always join with plain spaces.
    return parts.join(isDetailed ? ', ' : ' ');
  }

  static String _missingPropertyLabel(ItemVariationNodeDefinition property) {
    final propertyName = property.displayName.trim().isEmpty
        ? property.name.trim()
        : property.displayName.trim();
    return propertyName.isEmpty
        ? 'variation not recorded'
        : '$propertyName not recorded';
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
