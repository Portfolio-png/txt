import '../../domain/group_definition.dart';
import '../../domain/group_overview.dart';
import '../../domain/group_inputs.dart';

abstract class GroupRepository {
  Future<void> init();

  /// [withCovers] also fetches the items each group's card is made of. Off by
  /// default: the table view never draws them and is fetched far more often.
  Future<List<GroupDefinition>> getGroups({bool withCovers = false});

  /// Everything a group is: its items, its children, the properties its items
  /// inherit, and where in its lineage each of those came from.
  Future<GroupOverview> getGroupOverview(int groupId);

  Future<GroupDefinition> createGroup(CreateGroupInput input);

  Future<GroupDefinition> updateGroup(UpdateGroupInput input);

  Future<void> deleteGroup(int id);

  /// Bulk-assigns [itemIds] to the combination group [groupId]. Returns the
  /// number of newly added memberships (already-present items are skipped).
  /// Does not modify the items' primary hierarchical group.
  Future<int> assignItemsToGroup(int groupId, List<int> itemIds);
}
