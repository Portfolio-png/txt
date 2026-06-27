class GroupDefinition {
  const GroupDefinition({
    required this.id,
    required this.name,
    this.groupType = 'item',
    this.groupStructure = 'hierarchical',
    this.description = '',
    required this.parentGroupId,
    this.unitId,
    required this.isArchived,
    required this.usageCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String groupType;

  /// 'hierarchical' (nestable, the default) or 'combination' (a flat group that
  /// holds a curated list of item variants). See Enhancement 2.
  final String groupStructure;

  /// Optional free-text description, primarily used by combination groups.
  final String description;
  final int? parentGroupId;
  final int? unitId;
  final bool isArchived;
  final int usageCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isUsed => usageCount > 0;

  /// Whether this is a flat combination group (vs a nestable hierarchical one).
  bool get isCombination => groupStructure == 'combination';
}
