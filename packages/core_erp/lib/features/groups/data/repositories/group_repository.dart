import '../../domain/group_definition.dart';
import '../../domain/group_inputs.dart';

abstract class GroupRepository {
  Future<void> init();

  Future<List<GroupDefinition>> getGroups();

  Future<GroupDefinition> createGroup(CreateGroupInput input);

  Future<GroupDefinition> updateGroup(UpdateGroupInput input);

  Future<GroupDefinition> archiveGroup(int id);

  Future<GroupDefinition> restoreGroup(int id);
}
