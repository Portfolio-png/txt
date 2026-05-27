import 'group_property_draft.dart';

enum GroupUnitState { active, detached }

class GroupUnitGovernance {
  const GroupUnitGovernance({
    required this.unitId,
    this.state = GroupUnitState.active,
    this.isPrimary = false,
  });

  final int unitId;
  final GroupUnitState state;
  final bool isPrimary;
}

class GroupUiPreferences {
  const GroupUiPreferences({
    this.commonOnlyMode = true,
    this.showPartialMatches = true,
  });

  final bool commonOnlyMode;
  final bool showPartialMatches;
}

class MaterialGroupConfiguration {
  const MaterialGroupConfiguration({
    this.inheritanceEnabled = false,
    this.selectedItemIds = const <int>[],
    this.propertyDrafts = const <GroupPropertyDraft>[],
    this.discardedPropertyKeys = const <String>[],
    this.unitGovernance = const <GroupUnitGovernance>[],
    this.uiPreferences = const GroupUiPreferences(),
  });

  final bool inheritanceEnabled;
  final List<int> selectedItemIds;
  final List<GroupPropertyDraft> propertyDrafts;
  final List<String> discardedPropertyKeys;
  final List<GroupUnitGovernance> unitGovernance;
  final GroupUiPreferences uiPreferences;
}
