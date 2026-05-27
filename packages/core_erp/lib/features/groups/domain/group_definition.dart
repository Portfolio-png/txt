class GroupDefinition {
  const GroupDefinition({
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

  bool get isUsed => usageCount > 0;
}
