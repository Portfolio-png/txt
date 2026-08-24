import '../../items/domain/item_form_sections.dart';
import 'group_cover.dart';

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
    this.coverItems = const <GroupCoverItem>[],
    this.itemCount = 0,
    this.coverBasis = GroupCoverBasis.empty,
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

  /// The items whose photos make up this group's card, best first. Empty unless
  /// the covers were asked for — the table view does not need them.
  final List<GroupCoverItem> coverItems;

  /// Why those items and not others.
  final GroupCoverBasis coverBasis;

  /// Live items in this group. Distinct from [usageCount], which also counts
  /// child groups and linked materials.
  final int itemCount;
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
