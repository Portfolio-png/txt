enum GroupPropertySourceType { manual, inheritedItem, inheritedGroup }

enum GroupPropertyState { active, unlinked, overridden }

class GroupPropertySource {
  const GroupPropertySource({required this.itemId, this.itemName});

  final int itemId;
  final String? itemName;
}

class GroupPropertyDraft {
  const GroupPropertyDraft({
    required this.name,
    required this.inputType,
    required this.mandatory,
    this.propertyKey,
    this.unitId,
    this.unitSymbol,
    this.unitLabel,
    this.sourceType = GroupPropertySourceType.manual,
    this.state = GroupPropertyState.active,
    this.sources = const <GroupPropertySource>[],
    this.sourceGroupId,
    this.sourceGroupName,
    this.overrideLocked = false,
    this.hasTypeConflict = false,
    this.coverageCount = 0,
    this.selectedItemCountAtResolution = 0,
    this.resolutionSource,
  });

  final String name;
  final String inputType;
  final bool mandatory;
  final String? propertyKey;
  final int? unitId;
  final String? unitSymbol;
  final String? unitLabel;
  final GroupPropertySourceType sourceType;
  final GroupPropertyState state;
  final List<GroupPropertySource> sources;
  final int? sourceGroupId;
  final String? sourceGroupName;
  final bool overrideLocked;
  final bool hasTypeConflict;
  final int coverageCount;
  final int selectedItemCountAtResolution;
  final String? resolutionSource;

  GroupPropertyDraft copyWith({
    String? name,
    String? inputType,
    bool? mandatory,
    String? propertyKey,
    int? unitId,
    String? unitSymbol,
    String? unitLabel,
    GroupPropertySourceType? sourceType,
    GroupPropertyState? state,
    List<GroupPropertySource>? sources,
    int? sourceGroupId,
    String? sourceGroupName,
    bool? overrideLocked,
    bool? hasTypeConflict,
    int? coverageCount,
    int? selectedItemCountAtResolution,
    String? resolutionSource,
  }) {
    return GroupPropertyDraft(
      name: name ?? this.name,
      inputType: inputType ?? this.inputType,
      mandatory: mandatory ?? this.mandatory,
      propertyKey: propertyKey ?? this.propertyKey,
      unitId: unitId ?? this.unitId,
      unitSymbol: unitSymbol ?? this.unitSymbol,
      unitLabel: unitLabel ?? this.unitLabel,
      sourceType: sourceType ?? this.sourceType,
      state: state ?? this.state,
      sources: sources ?? this.sources,
      sourceGroupId: sourceGroupId ?? this.sourceGroupId,
      sourceGroupName: sourceGroupName ?? this.sourceGroupName,
      overrideLocked: overrideLocked ?? this.overrideLocked,
      hasTypeConflict: hasTypeConflict ?? this.hasTypeConflict,
      coverageCount: coverageCount ?? this.coverageCount,
      selectedItemCountAtResolution:
          selectedItemCountAtResolution ?? this.selectedItemCountAtResolution,
      resolutionSource: resolutionSource ?? this.resolutionSource,
    );
  }
}
