import 'group_property_draft.dart';

class EffectiveGroupSchema {
  const EffectiveGroupSchema({
    required this.groupId,
    this.propertyDrafts = const <GroupPropertyDraft>[],
    this.retiredPropertyDrafts = const <GroupPropertyDraft>[],
    this.discardedPropertyKeys = const <String>[],
    this.lineageGroupIds = const <int>[],
    this.lineageGroupNames = const <String>[],
  });

  final int groupId;
  final List<GroupPropertyDraft> propertyDrafts;

  /// Fields the group no longer asks for but whose values items still hold.
  /// Retained and hidden rather than deleted.
  final List<GroupPropertyDraft> retiredPropertyDrafts;
  final List<String> discardedPropertyKeys;
  final List<int> lineageGroupIds;
  final List<String> lineageGroupNames;
}
