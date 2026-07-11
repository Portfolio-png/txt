import '../../domain/group_definition.dart';
import '../../domain/group_inputs.dart';

abstract class GroupRepository {
  Future<void> init();

  Future<List<GroupDefinition>> getGroups();

  Future<GroupDefinition> createGroup(CreateGroupInput input);

  Future<GroupDefinition> updateGroup(UpdateGroupInput input);

  Future<void> deleteGroup(int id);

  /// Bulk-assigns [itemIds] to the combination group [groupId]. Returns the
  /// number of newly added memberships (already-present items are skipped).
  /// Does not modify the items' primary hierarchical group.
  Future<int> assignItemsToGroup(int groupId, List<int> itemIds);
}
