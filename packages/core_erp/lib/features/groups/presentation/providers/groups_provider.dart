import 'package:flutter/material.dart';

import '../../../../core/services/socket_service.dart';
import '../../data/repositories/group_repository.dart';
import '../../domain/group_definition.dart';
import '../../domain/group_overview.dart';
import '../../domain/group_inputs.dart';

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

  bool _initialized = false;

  List<GroupDefinition> get groups => _groups;
  // Hierarchical item groups only. Combination groups (Enhancement 2) are a flat
  // variant-set construct and are intentionally excluded here so existing
  // hierarchical tree/selector UIs behave exactly as before; use
  // [combinationGroups] for those.
  List<GroupDefinition> get itemGroups =>
      _groups.where((g) => g.groupType == 'item' && !g.isCombination).toList();

  /// Active combination groups (flat variant sets).
  List<GroupDefinition> get combinationGroups =>
      _groups.where((g) => g.groupType == 'item' && g.isCombination).toList();

  /// Every group an item can be filed under — hierarchical and combination
  /// alike.
  ///
  /// Separate from [itemGroups] on purpose: the tree pickers, the scrap
  /// destination and the inventory selectors all want hierarchical groups only,
  /// and folding combinations into that list would change all of them. This is
  /// for the one question "where does this item live", where a combination
  /// group is a legitimate answer — an item filed under one shows up in its
  /// overview alongside the members curated into it.
  List<GroupDefinition> get filableItemGroups =>
      _groups.where((g) => g.groupType == 'item').toList();
  List<GroupDefinition> get machineGroups =>
      _groups.where((g) => g.groupType == 'machine').toList();
  List<GroupDefinition> get dieGroups =>
      _groups.where((g) => g.groupType == 'die').toList();
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;

  List<GroupDefinition> get filteredGroups {
    final query = _normalize(_searchQuery);
    return _groups
        .where((group) {
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

  List<GroupDefinition> filteredGroupsByType(String groupType) {
    return filteredGroups
        .where((g) => g.groupType == groupType)
        .toList(growable: false);
  }

  List<GroupDefinition> get activeGroups => _groups.toList(growable: false);

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _subscribeToChanges();
    await refresh();
  }

  bool _subscribed = false;

  /// Groups carried no realtime signal at all, so a group another user created,
  /// renamed, deleted or filled stayed invisible here until a reload. With two
  /// or three people filing variants at once that is the difference between a
  /// shared catalogue and three diverging ones.
  ///
  /// One coarse signal, deliberately: the group list is small and a refresh is
  /// a single query, so a per-shape event would buy nothing and could go stale
  /// in ways a refetch cannot.
  void _subscribeToChanges() {
    if (_subscribed) return;
    _subscribed = true;
    SocketService.instance.on('groups_changed', (_) => refresh());
    // The stream can be suspended (desktop App Nap) and drop events silently;
    // this is the signal every other provider already resyncs on.
    SocketService.instance.on('realtime:reconnected', (_) => refresh());
  }

  /// Whether the card view has been opened, and so whether covers are wanted.
  ///
  /// Sticky once set: switching back to the table does not throw away covers
  /// already in hand, and switching to cards again should not have to refetch.
  bool _wantsCovers = false;

  bool get hasCovers => _wantsCovers;

  /// Ask for the items each group's card is made of, fetching them if this is
  /// the first time they have been wanted.
  Future<void> ensureCovers() async {
    if (_wantsCovers) return;
    _wantsCovers = true;
    await refresh();
  }

  /// Read one group in full, for the group view.
  ///
  /// Not cached: a group's items change from elsewhere in the app, and a view
  /// showing a stale item list is worse than one that takes a moment.
  Future<GroupOverview?> loadOverview(int groupId) async {
    try {
      return await _repository.getGroupOverview(groupId);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> refresh() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.init();
      final groups = await _repository.getGroups(withCovers: _wantsCovers);
      final namesById = <int, String>{
        for (final group in groups) group.id: group.name,
      };
      groups.sort((a, b) {
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
    return _groups.any((group) => group.parentGroupId == groupId);
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

  /// Bulk-assigns [itemIds] to combination group [groupId] (dual membership;
  /// does not change the items' primary group). Returns the number newly added,
  /// or `null` if the call failed (see [errorMessage]).
  Future<int?> assignItemsToCombinationGroup({
    required int groupId,
    required List<int> itemIds,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final assigned = await _repository.assignItemsToGroup(groupId, itemIds);
      await refresh();
      return assigned;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<GroupDefinition?> updateGroup(UpdateGroupInput input) async {
    return _save(() => _repository.updateGroup(input));
  }

  Future<bool> deleteGroup(int id) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.deleteGroup(id);
      await refresh();
      return true;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
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
