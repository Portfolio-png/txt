class CreateGroupInput {
  const CreateGroupInput({
    required this.name,
    required this.unitId,
    this.parentGroupId,
  });

  final String name;
  final int? parentGroupId;
  final int unitId;
}

class UpdateGroupInput {
  const UpdateGroupInput({
    required this.id,
    required this.name,
    required this.unitId,
    this.parentGroupId,
  });

  final int id;
  final String name;
  final int? parentGroupId;
  final int unitId;
}
