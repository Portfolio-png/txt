import 'group_property_draft.dart';

class EffectiveGroupSchema {
  const EffectiveGroupSchema({
    required this.groupId,
    this.propertyDrafts = const <GroupPropertyDraft>[],
    this.discardedPropertyKeys = const <String>[],
    this.lineageGroupIds = const <int>[],
    this.lineageGroupNames = const <String>[],
  });

  final int groupId;
  final List<GroupPropertyDraft> propertyDrafts;
  final List<String> discardedPropertyKeys;
  final List<int> lineageGroupIds;
  final List<String> lineageGroupNames;
}
