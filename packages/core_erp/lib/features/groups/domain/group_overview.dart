import 'package:flutter/foundation.dart';

import 'group_definition.dart';

/// One item as it appears in a group's view.
@immutable
class GroupOverviewItem {
  const GroupOverviewItem({
    required this.itemId,
    required this.name,
    this.photoUrl = '',
    this.unitName = '',
    this.quantity = 0,
    this.orderCount = 0,
    this.orderQuantity = 0,
    this.isVariant = false,
    this.baseItemId,
    this.hasPipeline = false,
    this.hasBaseline = false,
  });

  factory GroupOverviewItem.fromJson(Map<String, dynamic> json) {
    return GroupOverviewItem(
      itemId: (json['itemId'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      photoUrl: json['photoUrl']?.toString() ?? '',
      unitName: json['unitName']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      orderCount: (json['orderCount'] as num?)?.toInt() ?? 0,
      orderQuantity: (json['orderQuantity'] as num?)?.toInt() ?? 0,
      isVariant: json['isVariant'] == true,
      baseItemId: (json['baseItemId'] as num?)?.toInt(),
      hasPipeline: json['hasPipeline'] == true,
      hasBaseline: json['hasBaseline'] == true,
    );
  }

  final int itemId;
  final String name;
  final String photoUrl;
  final String unitName;
  final int quantity;

  /// Order lines this item appears on — the ranking the list is sorted by.
  final int orderCount;
  final int orderQuantity;

  /// A variant of another item rather than an item in its own right.
  final bool isVariant;

  /// The item this is a variant of, null when it is an item in its own right.
  /// Needed to nest a variant under its own base rather than lumping all
  /// variants together.
  final int? baseItemId;
  final bool hasPipeline;
  final bool hasBaseline;

  bool get hasPhoto => photoUrl.trim().isNotEmpty;
  bool get isOrdered => orderCount > 0;
}

/// A property every item in the group carries, and where it came from.
@immutable
class GroupProperty {
  const GroupProperty({
    required this.propertyKey,
    required this.displayName,
    this.inputType = 'text',
    this.mandatory = false,
    this.unitSymbol = '',
    this.sourceGroupId = 0,
    this.sourceGroupName = '',
  });

  factory GroupProperty.fromJson(Map<String, dynamic> json) {
    return GroupProperty(
      propertyKey: json['propertyKey']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      inputType: json['inputType']?.toString() ?? 'text',
      mandatory: json['mandatory'] == true,
      unitSymbol: json['unitSymbol']?.toString() ?? '',
      sourceGroupId: (json['sourceGroupId'] as num?)?.toInt() ?? 0,
      sourceGroupName: json['sourceGroupName']?.toString() ?? '',
    );
  }

  final String propertyKey;
  final String displayName;
  final String inputType;
  final bool mandatory;
  final String unitSymbol;
  final int sourceGroupId;
  final String sourceGroupName;

  /// Whether an ancestor put this property here rather than the group itself.
  bool inheritedBy(int groupId) =>
      sourceGroupId != 0 && sourceGroupId != groupId;
}

/// A child group, with enough to decide whether to open it.
@immutable
class GroupChild {
  const GroupChild({
    required this.groupId,
    required this.name,
    this.structure = 'hierarchical',
    this.itemCount = 0,
  });

  factory GroupChild.fromJson(Map<String, dynamic> json) {
    return GroupChild(
      groupId: (json['groupId'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      structure: json['structure']?.toString() ?? 'hierarchical',
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
    );
  }

  final int groupId;
  final String name;
  final String structure;
  final int itemCount;
}

/// What the items say about the group, which its own fields cannot.
///
/// Every figure is counted from the item list it ships with, so the header can
/// never disagree with the rows beneath it.
@immutable
class GroupSummary {
  const GroupSummary({
    this.itemCount = 0,
    this.orderedItemCount = 0,
    this.orderLineCount = 0,
    this.variantCount = 0,
    this.withPhotoCount = 0,
    this.withPipelineCount = 0,
    this.withBaselineCount = 0,
    this.units = const <String>[],
  });

  factory GroupSummary.fromJson(Map<String, dynamic> json) {
    return GroupSummary(
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      orderedItemCount: (json['orderedItemCount'] as num?)?.toInt() ?? 0,
      orderLineCount: (json['orderLineCount'] as num?)?.toInt() ?? 0,
      variantCount: (json['variantCount'] as num?)?.toInt() ?? 0,
      withPhotoCount: (json['withPhotoCount'] as num?)?.toInt() ?? 0,
      withPipelineCount: (json['withPipelineCount'] as num?)?.toInt() ?? 0,
      withBaselineCount: (json['withBaselineCount'] as num?)?.toInt() ?? 0,
      units: (json['units'] as List<dynamic>? ?? const <dynamic>[])
          .map((unit) => unit.toString())
          .toList(growable: false),
    );
  }

  final int itemCount;
  final int orderedItemCount;
  final int orderLineCount;
  final int variantCount;
  final int withPhotoCount;
  final int withPipelineCount;
  final int withBaselineCount;
  final List<String> units;

  bool get isEmpty => itemCount == 0;
}

/// Where a group's items come from — the distinction that makes a combination
/// group different from every other kind.
enum GroupItemSource {
  /// Filed under this group. Moving an item out means changing its group.
  owned,

  /// Gathered here by hand. The items live in their own groups; this one is a
  /// deliberate selection across them.
  curated;

  static GroupItemSource parse(String? raw) =>
      raw == 'curated' ? GroupItemSource.curated : GroupItemSource.owned;

  String get label => switch (this) {
    GroupItemSource.owned => 'Items filed under this group',
    GroupItemSource.curated => 'Items gathered into this group',
  };

  String get explanation => switch (this) {
    GroupItemSource.owned =>
      'Every item whose group is this one. An item belongs to exactly one.',
    GroupItemSource.curated =>
      'A combination group: these items keep their own groups and are '
          'gathered here as a set.',
  };
}

/// Everything a group is, in one read.
@immutable
class GroupOverview {
  const GroupOverview({
    required this.group,
    this.items = const <GroupOverviewItem>[],
    this.children = const <GroupChild>[],
    this.properties = const <GroupProperty>[],
    this.lineage = const <GroupChild>[],
    this.summary = const GroupSummary(),
    this.itemSource = GroupItemSource.owned,
  });

  factory GroupOverview.fromJson(
    Map<String, dynamic> json,
    GroupDefinition group,
  ) {
    List<T> listOf<T>(String key, T Function(Map<String, dynamic>) build) {
      return (json[key] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((row) => build(row.cast<String, dynamic>()))
          .toList(growable: false);
    }

    return GroupOverview(
      group: group,
      items: listOf('items', GroupOverviewItem.fromJson),
      children: listOf('children', GroupChild.fromJson),
      properties: listOf('properties', GroupProperty.fromJson),
      lineage: listOf('lineage', (row) => GroupChild.fromJson(row)),
      summary: GroupSummary.fromJson(
        (json['summary'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      itemSource: GroupItemSource.parse(json['itemSource']?.toString()),
    );
  }

  final GroupDefinition group;
  final List<GroupOverviewItem> items;
  final List<GroupChild> children;
  final List<GroupProperty> properties;

  /// This group and its ancestors, oldest first — the chain the properties are
  /// inherited down.
  final List<GroupChild> lineage;
  final GroupSummary summary;
  final GroupItemSource itemSource;

  /// Properties this group defines itself, as against ones it inherits.
  List<GroupProperty> get ownProperties => properties
      .where((property) => !property.inheritedBy(group.id))
      .toList(growable: false);

  List<GroupProperty> get inheritedProperties => properties
      .where((property) => property.inheritedBy(group.id))
      .toList(growable: false);

  /// The lineage without this group itself, which is the part worth drawing as
  /// a breadcrumb.
  List<GroupChild> get ancestors => lineage
      .where((entry) => entry.groupId != group.id)
      .toList(growable: false);
}
