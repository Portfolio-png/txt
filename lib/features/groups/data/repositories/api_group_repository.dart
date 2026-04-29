import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/group_definition.dart';
import '../../domain/group_inputs.dart';
import '../models/group_api_models.dart';
import 'group_repository.dart';

class ApiGroupRepository implements GroupRepository {
  ApiGroupRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
    this.useMockResponses = true,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  static final List<GroupDefinition> _mockGroups = <GroupDefinition>[];
  static int _mockNextId = 1;
  static bool _mockSeeded = false;

  static void debugResetMockStore() {
    _mockGroups.clear();
    _mockNextId = 1;
    _mockSeeded = false;
  }

  @override
  Future<void> init() async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
    }
  }

  @override
  Future<List<GroupDefinition>> getGroups() async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      return List<GroupDefinition>.from(_mockGroups);
    }

    final uri = Uri.parse('$baseUrl/api/groups');
    final response = await _client.get(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = GroupsListResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success) {
      throw GroupApiException(
        payload['error'] as String? ?? 'Failed to fetch groups.',
      );
    }
    return parsed.groups
        .map((group) => group.toDomain())
        .toList(growable: false);
  }

  @override
  Future<GroupDefinition> createGroup(CreateGroupInput input) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      _validateCreateOrUpdate(
        name: input.name,
        parentGroupId: input.parentGroupId,
      );
      final now = DateTime.now();
      final group = GroupDefinition(
        id: _mockNextId++,
        name: input.name.trim(),
        parentGroupId: input.parentGroupId,
        unitId: input.unitId,
        isArchived: false,
        usageCount: 0,
        createdAt: now,
        updatedAt: now,
      );
      _mockGroups.add(group);
      return group;
    }

    final uri = Uri.parse('$baseUrl/api/groups');
    final request = CreateGroupRequest.fromInput(input);
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = GroupResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.group == null) {
      throw GroupApiException(parsed.error ?? 'Failed to create group.');
    }
    return parsed.group!.toDomain();
  }

  @override
  Future<GroupDefinition> updateGroup(UpdateGroupInput input) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final index = _mockGroups.indexWhere((group) => group.id == input.id);
      if (index == -1) {
        throw GroupApiException('Group not found.');
      }
      final current = _mockGroups[index];
      if (current.isUsed) {
        throw GroupApiException('Used groups cannot be edited.');
      }
      _validateCreateOrUpdate(
        id: input.id,
        name: input.name,
        parentGroupId: input.parentGroupId,
      );
      final updated = GroupDefinition(
        id: current.id,
        name: input.name.trim(),
        parentGroupId: input.parentGroupId,
        unitId: input.unitId,
        isArchived: current.isArchived,
        usageCount: current.usageCount,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
      );
      _mockGroups[index] = updated;
      return updated;
    }

    final uri = Uri.parse('$baseUrl/api/groups/${input.id}');
    final request = UpdateGroupRequest.fromInput(input);
    final response = await _client.patch(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    final payload = _decodeJsonObject(response.body);
    final parsed = GroupResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.group == null) {
      throw GroupApiException(parsed.error ?? 'Failed to update group.');
    }
    return parsed.group!.toDomain();
  }

  @override
  Future<GroupDefinition> archiveGroup(int id) async {
    return _updateArchiveState(id, archive: true);
  }

  @override
  Future<GroupDefinition> restoreGroup(int id) async {
    return _updateArchiveState(id, archive: false);
  }

  Future<GroupDefinition> _updateArchiveState(
    int id, {
    required bool archive,
  }) async {
    if (useMockResponses) {
      _seedMockStoreIfNeeded();
      final index = _mockGroups.indexWhere((group) => group.id == id);
      if (index == -1) {
        throw GroupApiException('Group not found.');
      }
      final current = _mockGroups[index];
      if (archive &&
          _mockGroups.any(
            (group) => group.parentGroupId == id && !group.isArchived,
          )) {
        throw GroupApiException(
          'This group has active child groups. Reassign or archive them first.',
        );
      }
      final updated = GroupDefinition(
        id: current.id,
        name: current.name,
        parentGroupId: current.parentGroupId,
        unitId: current.unitId,
        isArchived: archive,
        usageCount: current.usageCount,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
      );
      _mockGroups[index] = updated;
      return updated;
    }

    final path = archive ? 'archive' : 'restore';
    final uri = Uri.parse('$baseUrl/api/groups/$id/$path');
    final response = await _client.patch(uri);
    final payload = _decodeJsonObject(response.body);
    final parsed = GroupResponse.fromJson(payload);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !parsed.success ||
        parsed.group == null) {
      throw GroupApiException(parsed.error ?? 'Failed to update group status.');
    }
    return parsed.group!.toDomain();
  }

  void _validateCreateOrUpdate({
    int? id,
    required String name,
    required int? parentGroupId,
  }) {
    final normalizedName = _normalize(name);
    if (normalizedName.isEmpty) {
      throw GroupApiException('Group name is required.');
    }
    if (id != null && parentGroupId == id) {
      throw GroupApiException('A group cannot be its own parent.');
    }
    if (parentGroupId != null) {
      final parent = _mockGroups
          .where((group) => group.id == parentGroupId)
          .firstOrNull;
      if (parent == null || parent.isArchived) {
        throw GroupApiException('Selected parent group is not available.');
      }
      if (id != null &&
          _isDescendant(candidateParentId: parentGroupId, groupId: id)) {
        throw GroupApiException(
          'A group cannot move under its own descendant.',
        );
      }
    }
    final duplicate = _mockGroups.any(
      (group) =>
          group.id != id &&
          group.parentGroupId == parentGroupId &&
          _normalize(group.name) == normalizedName,
    );
    if (duplicate) {
      throw GroupApiException(
        'A group with the same name already exists here.',
      );
    }
  }

  bool _isDescendant({required int candidateParentId, required int groupId}) {
    var currentId = candidateParentId;
    while (true) {
      if (currentId == groupId) {
        return true;
      }
      final current = _mockGroups
          .where((group) => group.id == currentId)
          .firstOrNull;
      final nextId = current?.parentGroupId;
      if (nextId == null) {
        return false;
      }
      currentId = nextId;
    }
  }

  void _seedMockStoreIfNeeded() {
    if (_mockSeeded) {
      return;
    }
    _mockSeeded = true;
    final now = DateTime.now();
    _mockGroups
      ..clear()
      ..addAll([
        GroupDefinition(
          id: _mockNextId++,
          name: 'Chemicals',
          parentGroupId: null,
          unitId: 1,
          isArchived: false,
          usageCount: 3,
          createdAt: now,
          updatedAt: now,
        ),
        GroupDefinition(
          id: _mockNextId++,
          name: 'Adhesives',
          parentGroupId: 1,
          unitId: 1,
          isArchived: false,
          usageCount: 2,
          createdAt: now,
          updatedAt: now,
        ),
        GroupDefinition(
          id: _mockNextId++,
          name: 'Solvents',
          parentGroupId: 1,
          unitId: 1,
          isArchived: false,
          usageCount: 1,
          createdAt: now,
          updatedAt: now,
        ),
        GroupDefinition(
          id: _mockNextId++,
          name: 'Inks',
          parentGroupId: 1,
          unitId: 1,
          isArchived: false,
          usageCount: 1,
          createdAt: now,
          updatedAt: now,
        ),
        GroupDefinition(
          id: _mockNextId++,
          name: 'Legacy Group',
          parentGroupId: null,
          unitId: 1,
          isArchived: true,
          usageCount: 0,
          createdAt: now,
          updatedAt: now,
        ),
      ]);
  }

  Map<String, dynamic> _decodeJsonObject(String body) {
    if (body.isEmpty) {
      return const {'success': false, 'error': 'Empty response from server.'};
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {
        'success': false,
        'error': 'Unexpected response format from server.',
      };
    } on FormatException {
      return {
        'success': false,
        'error': body.trim().isEmpty
            ? 'Unexpected response from server.'
            : body.trim(),
      };
    }
  }

  static String _normalize(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }
}

class GroupApiException implements Exception {
  const GroupApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
