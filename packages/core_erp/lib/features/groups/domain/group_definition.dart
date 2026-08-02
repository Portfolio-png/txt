import '../../items/domain/item_form_sections.dart';

class GroupDefinition {
  const GroupDefinition({
    required this.id,
    required this.name,
    this.groupType = 'item',
    this.groupStructure = 'hierarchical',
    this.description = '',
    this.itemFormSections,
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

  /// One of:
  /// - `hierarchical` — an item group: nestable, with a parent, unit and
  ///   properties. The default, labelled "Item Group" in the UI.
  /// - `combination` — a flat group holding a curated list of item variants.
  /// - `component` — nestable like an item group, for components and
  ///   sub-assemblies rather than saleable items.
  ///
  /// See Enhancement 2.
  final String groupStructure;

  /// Optional free-text description, primarily used by combination groups.
  final String description;
  final int? parentGroupId;
  final int? unitId;

  /// Section layout that items in this group use instead of the creating user's
  /// own default. Null when the group has no override.
  final ItemFormSections? itemFormSections;
  final bool isArchived;
  final int usageCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isUsed => usageCount > 0;

  /// Whether this is a flat combination group (vs a nestable item or component
  /// group).
  bool get isCombination => groupStructure == 'combination';

  /// Whether this group holds components / sub-assemblies. Structurally
  /// identical to an item group — the distinction is intent.
  bool get isComponent => groupStructure == 'component';
}
