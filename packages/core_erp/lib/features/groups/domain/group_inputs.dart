class CreateGroupInput {
  const CreateGroupInput({
    required this.name,
    this.groupType = 'item',
    this.groupStructure = 'hierarchical',
    this.description = '',
    this.unitId,
    this.parentGroupId,
  });

  final String name;
  final String groupType;

  /// 'hierarchical' or 'combination' (Enhancement 2).
  final String groupStructure;
  final String description;
  final int? parentGroupId;
  final int? unitId;
}

class UpdateGroupInput {
  const UpdateGroupInput({
    required this.id,
    required this.name,
    this.groupType = 'item',
    this.groupStructure = 'hierarchical',
    this.description = '',
    this.unitId,
    this.parentGroupId,
  });

  final int id;
  final String name;
  final String groupType;
  final String groupStructure;
  final String description;
  final int? parentGroupId;
  final int? unitId;
}
