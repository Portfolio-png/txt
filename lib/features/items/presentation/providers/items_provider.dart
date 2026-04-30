import 'package:flutter/material.dart';

import '../../data/repositories/item_repository.dart';
import '../../domain/item_definition.dart';
import '../../domain/item_inputs.dart';

enum ItemStatusFilter { active, archived, all }

enum ItemDuplicateWarning {
  none,
  sameGroupAndQuantity,
  emptyNodeName,
  invalidTreeStructure,
  duplicateSiblingName,
}

class ItemDuplicateCheck {
  const ItemDuplicateCheck({
    required this.blockingDuplicate,
    required this.warning,
  });

  final bool blockingDuplicate;
  final ItemDuplicateWarning warning;
}

class QuickCreateVariationValueResult {
  const QuickCreateVariationValueResult({
    required this.item,
    required this.createdValueNode,
    required this.selectedValueNodeIds,
  });

  final ItemDefinition item;
  final ItemVariationNodeDefinition createdValueNode;
  final List<int> selectedValueNodeIds;
}

class ItemsProvider extends ChangeNotifier {
  ItemsProvider({required ItemRepository repository})
    : _repository = repository;

  final ItemRepository _repository;

  List<ItemDefinition> _items = const [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  String _searchQuery = '';
  ItemStatusFilter _statusFilter = ItemStatusFilter.active;
  bool _initialized = false;

  List<ItemDefinition> get items => _items;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;
  ItemStatusFilter get statusFilter => _statusFilter;

  List<ItemDefinition> get filteredItems {
    final query = _normalize(_searchQuery);
    return _items
        .where((item) {
          final matchesStatus = switch (_statusFilter) {
            ItemStatusFilter.active => !item.isArchived,
            ItemStatusFilter.archived => item.isArchived,
            ItemStatusFilter.all => true,
          };
          if (!matchesStatus) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          final treeText = _treeSearchText(item.variationTree);
          return _normalize(item.name).contains(query) ||
              _normalize(item.alias).contains(query) ||
              _normalize(item.displayName).contains(query) ||
              item.quantity.toString().contains(query) ||
              _normalize(treeText).contains(query);
        })
        .toList(growable: false);
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    await refresh();
  }

  Future<void> refresh() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.init();
      final items = await _repository.getItems();
      items.sort((a, b) {
        if (a.isArchived != b.isArchived) {
          return a.isArchived ? 1 : -1;
        }
        final groupCompare = a.groupId.compareTo(b.groupId);
        if (groupCompare != 0) {
          return groupCompare;
        }
        final nameCompare = a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        );
        if (nameCompare != 0) {
          return nameCompare;
        }
        return a.quantity.compareTo(b.quantity);
      });
      _items = items;
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSearchQuery(String value) {
    _searchQuery = value;
    notifyListeners();
  }

  void setStatusFilter(ItemStatusFilter value) {
    _statusFilter = value;
    notifyListeners();
  }

  ItemDuplicateCheck checkDuplicate({
    required String name,
    required double? quantity,
    required int? groupId,
    required List<ItemVariationNodeInput> variationTree,
    int? excludeId,
  }) {
    final normalizedName = _normalize(name);
    if (groupId != null &&
        quantity != null &&
        _items.any(
          (item) =>
              item.id != excludeId &&
              item.groupId == groupId &&
              item.quantity == quantity &&
              _normalize(item.name) == normalizedName,
        )) {
      return const ItemDuplicateCheck(
        blockingDuplicate: true,
        warning: ItemDuplicateWarning.sameGroupAndQuantity,
      );
    }

    for (final node in variationTree) {
      final result = _validateNode(
        node,
        expectedKind: ItemVariationNodeKind.property,
        siblings: variationTree,
      );
      if (result != ItemDuplicateWarning.none) {
        return ItemDuplicateCheck(blockingDuplicate: true, warning: result);
      }
    }

    return const ItemDuplicateCheck(
      blockingDuplicate: false,
      warning: ItemDuplicateWarning.none,
    );
  }

  ItemDuplicateWarning _validateNode(
    ItemVariationNodeInput node, {
    required ItemVariationNodeKind expectedKind,
    required List<ItemVariationNodeInput> siblings,
  }) {
    final normalizedName = _normalize(node.name);
    if (normalizedName.isEmpty) {
      return ItemDuplicateWarning.emptyNodeName;
    }
    if (node.kind != expectedKind) {
      return ItemDuplicateWarning.invalidTreeStructure;
    }
    if (siblings
            .where((entry) => _normalize(entry.name) == normalizedName)
            .length >
        1) {
      return ItemDuplicateWarning.duplicateSiblingName;
    }
    final nextKind = node.kind == ItemVariationNodeKind.property
        ? ItemVariationNodeKind.value
        : ItemVariationNodeKind.property;
    for (final child in node.children) {
      final result = _validateNode(
        child,
        expectedKind: nextKind,
        siblings: node.children,
      );
      if (result != ItemDuplicateWarning.none) {
        return result;
      }
    }
    return ItemDuplicateWarning.none;
  }

  Future<ItemDefinition?> createItem(CreateItemInput input) async {
    return _save(() => _repository.createItem(input));
  }

  Future<ItemDefinition?> updateItem(UpdateItemInput input) async {
    return _save(() => _repository.updateItem(input));
  }

  Future<QuickCreateVariationValueResult?> appendVariationValue({
    required int itemId,
    required int propertyNodeId,
    required String valueName,
  }) async {
    final current = _items.where((item) => item.id == itemId).firstOrNull;
    final trimmedValueName = valueName.trim();
    if (current == null) {
      _errorMessage = 'Item not found.';
      notifyListeners();
      return null;
    }
    if (trimmedValueName.isEmpty) {
      _errorMessage = 'Variation value name is required.';
      notifyListeners();
      return null;
    }
    final propertyPathSegments = _nodePathSegmentsById(
      current.variationTree,
      propertyNodeId,
    );
    if (propertyPathSegments.isEmpty) {
      _errorMessage = 'Variation property not found.';
      notifyListeners();
      return null;
    }

    final mutation = _appendVariationValueToTree(
      current.variationTree.map(_toInput).toList(growable: false),
      propertyNodeId: propertyNodeId,
      valueName: trimmedValueName,
      valuePath: const <String>[],
    );
    if (!mutation.inserted) {
      _errorMessage = 'Variation property not found.';
      notifyListeners();
      return null;
    }

    return _saveQuickCreateVariationValue(
      () => _repository.updateItem(
        UpdateItemInput(
          id: current.id,
          name: current.name,
          alias: current.alias,
          displayName: current.displayName,
          quantity: current.quantity,
          groupId: current.groupId,
          unitId: current.unitId,
          variationTree: mutation.nodes,
        ),
      ),
      propertyNodeId: propertyNodeId,
      valueName: trimmedValueName,
      propertyPathSegments: propertyPathSegments,
    );
  }

  Future<ItemDefinition?> archiveItem(int id) async {
    return _save(() => _repository.archiveItem(id));
  }

  Future<ItemDefinition?> restoreItem(int id) async {
    return _save(() => _repository.restoreItem(id));
  }

  Future<ItemDefinition?> _save(
    Future<ItemDefinition> Function() action,
  ) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await action();
      await refresh();
      return _items.where((item) => item.id == updated.id).firstOrNull ??
          updated;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<QuickCreateVariationValueResult?> _saveQuickCreateVariationValue(
    Future<ItemDefinition> Function() action, {
    required int propertyNodeId,
    required String valueName,
    required List<String> propertyPathSegments,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await action();
      await refresh();
      final refreshed =
          _items.where((item) => item.id == updated.id).firstOrNull ?? updated;
      final propertyNode =
          _findNodeById(refreshed.variationTree, propertyNodeId) ??
          _findNodeByPathSegments(
            refreshed.variationTree,
            propertyPathSegments,
          );
      final createdValueNode = propertyNode?.activeChildren
          .where((node) => node.kind == ItemVariationNodeKind.value)
          .where((node) => _normalize(node.name) == _normalize(valueName))
          .firstOrNull;
      if (createdValueNode == null) {
        throw StateError('Created variation value was not found after saving.');
      }
      return QuickCreateVariationValueResult(
        item: refreshed,
        createdValueNode: createdValueNode,
        selectedValueNodeIds: _valueNodePathIdsForNode(
          refreshed.variationTree,
          createdValueNode.id,
        ),
      );
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }
    _errorMessage = null;
    notifyListeners();
  }

  static String normalizeValue(String value) => _normalize(value);

  ItemVariationNodeInput _toInput(ItemVariationNodeDefinition node) {
    return ItemVariationNodeInput(
      id: node.id,
      parentNodeId: node.parentNodeId,
      kind: node.kind,
      name: node.name,
      displayName: node.displayName,
      children: node.children.map(_toInput).toList(growable: false),
    );
  }

  _VariationTreeMutation _appendVariationValueToTree(
    List<ItemVariationNodeInput> nodes, {
    required int propertyNodeId,
    required String valueName,
    required List<String> valuePath,
  }) {
    var inserted = false;
    final nextNodes = <ItemVariationNodeInput>[];

    for (final node in nodes) {
      final nextValuePath = node.kind == ItemVariationNodeKind.value
          ? <String>[...valuePath, node.name.trim()]
          : valuePath;
      if (node.id == propertyNodeId) {
        if (node.kind != ItemVariationNodeKind.property) {
          throw StateError(
            'Variation values can only be added under properties.',
          );
        }
        final duplicateExists = node.children
            .where((child) => child.kind == ItemVariationNodeKind.value)
            .any((child) => _normalize(child.name) == _normalize(valueName));
        if (duplicateExists) {
          throw StateError('A value with this name already exists.');
        }
        final referenceValue = node.children
            .where((child) => child.kind == ItemVariationNodeKind.value)
            .where((child) => child.children.isNotEmpty)
            .firstOrNull;
        final nextPath = <String>[...valuePath, valueName];
        final clonedChildren = referenceValue == null
            ? const <ItemVariationNodeInput>[]
            : _cloneBranchForQuickCreate(
                referenceValue.children,
                valuePath: nextPath,
              );
        nextNodes.add(
          ItemVariationNodeInput(
            id: node.id,
            parentNodeId: node.parentNodeId,
            kind: node.kind,
            name: node.name,
            displayName: '',
            children: <ItemVariationNodeInput>[
              ...node.children,
              ItemVariationNodeInput(
                kind: ItemVariationNodeKind.value,
                name: valueName,
                displayName: clonedChildren.isEmpty
                    ? _generateLeafDisplayName(nextPath)
                    : '',
                children: clonedChildren,
              ),
            ],
          ),
        );
        inserted = true;
        continue;
      }

      final mutation = _appendVariationValueToTree(
        node.children,
        propertyNodeId: propertyNodeId,
        valueName: valueName,
        valuePath: nextValuePath,
      );
      if (mutation.inserted) {
        inserted = true;
      }
      nextNodes.add(
        ItemVariationNodeInput(
          id: node.id,
          parentNodeId: node.parentNodeId,
          kind: node.kind,
          name: node.name,
          displayName: node.displayName,
          children: mutation.nodes,
        ),
      );
    }

    return _VariationTreeMutation(nodes: nextNodes, inserted: inserted);
  }

  List<ItemVariationNodeInput> _cloneBranchForQuickCreate(
    List<ItemVariationNodeInput> nodes, {
    required List<String> valuePath,
  }) {
    return nodes
        .map((node) {
          if (node.kind == ItemVariationNodeKind.property) {
            return ItemVariationNodeInput(
              kind: node.kind,
              name: node.name,
              children: _cloneBranchForQuickCreate(
                node.children,
                valuePath: valuePath,
              ),
            );
          }
          final nextValuePath = <String>[...valuePath, node.name.trim()];
          final clonedChildren = _cloneBranchForQuickCreate(
            node.children,
            valuePath: nextValuePath,
          );
          return ItemVariationNodeInput(
            kind: node.kind,
            name: node.name,
            displayName: clonedChildren.isEmpty
                ? _generateLeafDisplayName(nextValuePath)
                : '',
            children: clonedChildren,
          );
        })
        .toList(growable: false);
  }

  ItemVariationNodeDefinition? _findNodeById(
    List<ItemVariationNodeDefinition> nodes,
    int nodeId,
  ) {
    for (final node in nodes) {
      if (node.id == nodeId) {
        return node;
      }
      final child = _findNodeById(node.children, nodeId);
      if (child != null) {
        return child;
      }
    }
    return null;
  }

  List<String> _nodePathSegmentsById(
    List<ItemVariationNodeDefinition> nodes,
    int nodeId,
  ) {
    final path = <ItemVariationNodeDefinition>[];

    bool visit(
      ItemVariationNodeDefinition node,
      List<ItemVariationNodeDefinition> current,
    ) {
      final next = <ItemVariationNodeDefinition>[...current, node];
      if (node.id == nodeId) {
        path
          ..clear()
          ..addAll(next);
        return true;
      }
      for (final child in node.children) {
        if (visit(child, next)) {
          return true;
        }
      }
      return false;
    }

    for (final node in nodes) {
      if (visit(node, const <ItemVariationNodeDefinition>[])) {
        break;
      }
    }

    return path
        .map((node) => node.name.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
  }

  ItemVariationNodeDefinition? _findNodeByPathSegments(
    List<ItemVariationNodeDefinition> nodes,
    List<String> pathSegments,
  ) {
    if (pathSegments.isEmpty) {
      return null;
    }

    ItemVariationNodeDefinition? current;
    Iterable<ItemVariationNodeDefinition> scope = nodes.where(
      (node) => !node.isArchived,
    );

    for (final segment in pathSegments) {
      current = scope
          .where((node) => _normalize(node.name) == _normalize(segment))
          .firstOrNull;
      if (current == null) {
        return null;
      }
      scope = current.activeChildren;
    }

    return current;
  }

  List<int> _valueNodePathIdsForNode(
    List<ItemVariationNodeDefinition> nodes,
    int nodeId,
  ) {
    final path = <ItemVariationNodeDefinition>[];

    bool visit(
      ItemVariationNodeDefinition node,
      List<ItemVariationNodeDefinition> current,
    ) {
      final next = <ItemVariationNodeDefinition>[...current, node];
      if (node.id == nodeId) {
        path
          ..clear()
          ..addAll(next);
        return true;
      }
      for (final child in node.children) {
        if (visit(child, next)) {
          return true;
        }
      }
      return false;
    }

    for (final node in nodes) {
      if (visit(node, const <ItemVariationNodeDefinition>[])) {
        break;
      }
    }

    return path
        .where((node) => node.kind == ItemVariationNodeKind.value)
        .map((node) => node.id)
        .toList(growable: false);
  }

  String _generateLeafDisplayName(List<String> valuePath) {
    return valuePath
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .join(' ');
  }

  static String _treeSearchText(List<ItemVariationNodeDefinition> nodes) {
    final parts = <String>[];

    void visit(ItemVariationNodeDefinition node) {
      parts.add(node.name);
      parts.add(node.displayName);
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final node in nodes) {
      visit(node);
    }
    return parts.join(' ');
  }

  static String _normalize(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }
}

class _VariationTreeMutation {
  const _VariationTreeMutation({required this.nodes, required this.inserted});

  final List<ItemVariationNodeInput> nodes;
  final bool inserted;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
