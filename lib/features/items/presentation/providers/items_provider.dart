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

  void clearError() {
    if (_errorMessage == null) {
      return;
    }
    _errorMessage = null;
    notifyListeners();
  }

  static String normalizeValue(String value) => _normalize(value);

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

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
