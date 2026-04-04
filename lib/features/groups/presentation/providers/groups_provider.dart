import 'package:flutter/material.dart';

import '../../data/repositories/group_repository.dart';
import '../../domain/group_definition.dart';
import '../../domain/group_inputs.dart';

enum GroupStatusFilter { active, archived, all }

enum GroupDuplicateWarning { none, sameParent }

class GroupDuplicateCheck {
  const GroupDuplicateCheck({
    required this.blockingDuplicate,
    required this.warning,
  });

  final bool blockingDuplicate;
  final GroupDuplicateWarning warning;
}

class GroupsProvider extends ChangeNotifier {
  GroupsProvider({required GroupRepository repository})
    : _repository = repository;

  final GroupRepository _repository;

  List<GroupDefinition> _groups = const [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  String _searchQuery = '';
  GroupStatusFilter _statusFilter = GroupStatusFilter.active;
  bool _initialized = false;

  List<GroupDefinition> get groups => _groups;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;
  GroupStatusFilter get statusFilter => _statusFilter;

  List<GroupDefinition> get filteredGroups {
    final query = _normalize(_searchQuery);
    return _groups
        .where((group) {
          final matchesStatus = switch (_statusFilter) {
            GroupStatusFilter.active => !group.isArchived,
            GroupStatusFilter.archived => group.isArchived,
            GroupStatusFilter.all => true,
          };
          if (!matchesStatus) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return _normalize(group.name).contains(query) ||
              _normalize(
                parentNameFor(group.parentGroupId) ?? '',
              ).contains(query);
        })
        .toList(growable: false);
  }

  List<GroupDefinition> get activeGroups =>
      _groups.where((group) => !group.isArchived).toList(growable: false);

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
      final groups = await _repository.getGroups();
      final namesById = <int, String>{
        for (final group in groups) group.id: group.name,
      };
      groups.sort((a, b) {
        if (a.isArchived != b.isArchived) {
          return a.isArchived ? 1 : -1;
        }
        final parentA = namesById[a.parentGroupId] ?? '';
        final parentB = namesById[b.parentGroupId] ?? '';
        final parentCompare = parentA.toLowerCase().compareTo(
          parentB.toLowerCase(),
        );
        if (parentCompare != 0) {
          return parentCompare;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      _groups = groups;
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

  void setStatusFilter(GroupStatusFilter value) {
    _statusFilter = value;
    notifyListeners();
  }

  GroupDefinition? findById(int? id) {
    if (id == null) {
      return null;
    }
    return _groups.where((group) => group.id == id).firstOrNull;
  }

  String? parentNameFor(int? id) => findById(id)?.name;

  List<GroupDefinition> availableParentsFor({int? excludeGroupId}) {
    final blockedIds = excludeGroupId == null
        ? const <int>{}
        : {excludeGroupId, ...descendantIdsOf(excludeGroupId)};
    return activeGroups
        .where((group) => !blockedIds.contains(group.id))
        .toList(growable: false);
  }

  Set<int> descendantIdsOf(int groupId) {
    final descendants = <int>{};
    final pending = <int>[groupId];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      final children = _groups
          .where((group) => group.parentGroupId == current)
          .map((group) => group.id)
          .where((id) => descendants.add(id))
          .toList(growable: false);
      pending.addAll(children);
    }
    return descendants;
  }

  bool wouldCreateCycle({required int groupId, required int? parentGroupId}) {
    if (parentGroupId == null) {
      return false;
    }
    if (parentGroupId == groupId) {
      return true;
    }
    return descendantIdsOf(groupId).contains(parentGroupId);
  }

  bool hasActiveChildren(int groupId) {
    return _groups.any(
      (group) => group.parentGroupId == groupId && !group.isArchived,
    );
  }

  GroupDuplicateCheck checkDuplicate({
    required String name,
    required int? parentGroupId,
    int? excludeId,
  }) {
    final normalizedName = _normalize(name);
    final duplicate = _groups.any(
      (group) =>
          group.id != excludeId &&
          group.parentGroupId == parentGroupId &&
          _normalize(group.name) == normalizedName,
    );
    if (duplicate) {
      return const GroupDuplicateCheck(
        blockingDuplicate: true,
        warning: GroupDuplicateWarning.sameParent,
      );
    }
    return const GroupDuplicateCheck(
      blockingDuplicate: false,
      warning: GroupDuplicateWarning.none,
    );
  }

  Future<GroupDefinition?> createGroup(CreateGroupInput input) async {
    return _save(() => _repository.createGroup(input));
  }

  Future<GroupDefinition?> updateGroup(UpdateGroupInput input) async {
    return _save(() => _repository.updateGroup(input));
  }

  Future<GroupDefinition?> archiveGroup(int id) async {
    return _save(() => _repository.archiveGroup(id));
  }

  Future<GroupDefinition?> restoreGroup(int id) async {
    return _save(() => _repository.restoreGroup(id));
  }

  Future<GroupDefinition?> _save(
    Future<GroupDefinition> Function() action,
  ) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await action();
      await refresh();
      return _groups.where((group) => group.id == updated.id).firstOrNull ??
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

  static String _normalize(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
