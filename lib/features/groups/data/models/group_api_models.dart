import '../../domain/group_definition.dart';
import '../../domain/group_inputs.dart';

class GroupDto {
  const GroupDto({
    required this.id,
    required this.name,
    required this.parentGroupId,
    required this.unitId,
    required this.isArchived,
    required this.usageCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final int? parentGroupId;
  final int unitId;
  final bool isArchived;
  final int usageCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory GroupDto.fromJson(Map<String, dynamic> json) {
    return GroupDto(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      parentGroupId: json['parentGroupId'] as int?,
      unitId: json['unitId'] as int? ?? 0,
      isArchived: json['isArchived'] as bool? ?? false,
      usageCount: json['usageCount'] as int? ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  GroupDefinition toDomain() {
    return GroupDefinition(
      id: id,
      name: name,
      parentGroupId: parentGroupId,
      unitId: unitId,
      isArchived: isArchived,
      usageCount: usageCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class GroupResponse {
  const GroupResponse({required this.success, this.group, this.error});

  final bool success;
  final GroupDto? group;
  final String? error;

  factory GroupResponse.fromJson(Map<String, dynamic> json) {
    return GroupResponse(
      success: json['success'] as bool? ?? false,
      group: json['group'] == null
          ? null
          : GroupDto.fromJson(json['group'] as Map<String, dynamic>),
      error: json['error'] as String?,
    );
  }
}

class GroupsListResponse {
  const GroupsListResponse({required this.success, required this.groups});

  final bool success;
  final List<GroupDto> groups;

  factory GroupsListResponse.fromJson(Map<String, dynamic> json) {
    return GroupsListResponse(
      success: json['success'] as bool? ?? false,
      groups: (json['groups'] as List<dynamic>? ?? const [])
          .map((item) => GroupDto.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class CreateGroupRequest {
  const CreateGroupRequest({
    required this.name,
    required this.parentGroupId,
    required this.unitId,
  });

  final String name;
  final int? parentGroupId;
  final int unitId;

  factory CreateGroupRequest.fromInput(CreateGroupInput input) {
    return CreateGroupRequest(
      name: input.name,
      parentGroupId: input.parentGroupId,
      unitId: input.unitId,
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'parentGroupId': parentGroupId, 'unitId': unitId};
  }
}

class UpdateGroupRequest {
  const UpdateGroupRequest({
    required this.name,
    required this.parentGroupId,
    required this.unitId,
  });

  final String name;
  final int? parentGroupId;
  final int unitId;

  factory UpdateGroupRequest.fromInput(UpdateGroupInput input) {
    return UpdateGroupRequest(
      name: input.name,
      parentGroupId: input.parentGroupId,
      unitId: input.unitId,
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'parentGroupId': parentGroupId, 'unitId': unitId};
  }
}
