import '../../items/domain/item_form_sections.dart';

class CreateGroupInput {
  const CreateGroupInput({
    required this.name,
    this.groupType = 'item',
    this.groupStructure = 'hierarchical',
    this.description = '',
    this.unitId,
    this.parentGroupId,
    this.itemFormSections,
  });

  final String name;
  final String groupType;

  /// 'hierarchical' or 'combination' (Enhancement 2).
  final String groupStructure;
  final String description;
  final int? parentGroupId;
  final int? unitId;

  /// Per-group override of the item-form section layout. Null leaves whatever
  /// is stored alone (and, for a new group, means no override).
  final ItemFormSections? itemFormSections;
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
    this.itemFormSections,
  });

  final int id;
  final String name;
  final String groupType;
  final String groupStructure;
  final String description;
  final int? parentGroupId;
  final int? unitId;

  /// Per-group override of the item-form section layout. Null leaves whatever
  /// is stored alone (and, for a new group, means no override).
  final ItemFormSections? itemFormSections;
}
