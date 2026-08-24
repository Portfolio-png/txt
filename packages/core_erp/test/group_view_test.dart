import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/domain/group_overview.dart';
import 'package:flutter_test/flutter_test.dart';

/// The group view answers "what is this group". Its two load-bearing ideas are
/// that a property knows which group in the lineage put it there, and that a
/// combination group's items come from somewhere different from every other
/// kind of group's.
void main() {
  GroupDefinition definition({
    int id = 10,
    String structure = 'hierarchical',
    String type = 'item',
  }) {
    return GroupDefinition(
      id: id,
      name: 'Sockets',
      groupType: type,
      groupStructure: structure,
      parentGroupId: null,
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  }

  GroupProperty property(String key, {int source = 10}) {
    return GroupProperty(
      propertyKey: key,
      displayName: key,
      sourceGroupId: source,
      sourceGroupName: source == 10 ? 'Sockets' : 'Primary Group',
    );
  }

  group('properties', () {
    test('a property knows whether it was inherited', () {
      expect(property('amps', source: 10).inheritedBy(10), isFalse);
      expect(property('colour', source: 4).inheritedBy(10), isTrue);
      // A property with no source is this group's own, not an orphan.
      expect(property('x', source: 0).inheritedBy(10), isFalse);
    });

    test('the view splits its own properties from what it inherits', () {
      final overview = GroupOverview(
        group: definition(),
        properties: <GroupProperty>[
          property('amps'),
          property('colour', source: 4),
          property('finish', source: 4),
        ],
      );
      expect(overview.ownProperties.map((p) => p.propertyKey), <String>[
        'amps',
      ]);
      expect(overview.inheritedProperties.map((p) => p.propertyKey), <String>[
        'colour',
        'finish',
      ]);
    });
  });

  group('lineage', () {
    test('the breadcrumb is the lineage without this group itself', () {
      final overview = GroupOverview(
        group: definition(),
        lineage: const <GroupChild>[
          GroupChild(groupId: 4, name: 'Primary Group'),
          GroupChild(groupId: 10, name: 'Sockets'),
        ],
      );
      // The group being viewed is the title, not a crumb pointing at itself.
      expect(overview.ancestors.map((a) => a.name), <String>['Primary Group']);
    });

    test('a top-level group has no crumbs at all', () {
      final overview = GroupOverview(
        group: definition(),
        lineage: const <GroupChild>[GroupChild(groupId: 10, name: 'Sockets')],
      );
      expect(overview.ancestors, isEmpty);
    });
  });

  group('where the items come from', () {
    test('a combination group curates; everything else owns', () {
      expect(GroupItemSource.parse('curated'), GroupItemSource.curated);
      expect(GroupItemSource.parse('owned'), GroupItemSource.owned);
      // An unknown value must not silently become "curated", which would make
      // a normal group read its items from the wrong table.
      expect(GroupItemSource.parse(null), GroupItemSource.owned);
      expect(GroupItemSource.parse('nonsense'), GroupItemSource.owned);
    });

    test('each source explains itself in the view', () {
      expect(GroupItemSource.curated.label, contains('gathered'));
      expect(GroupItemSource.curated.explanation, contains('combination'));
      expect(GroupItemSource.owned.label, contains('filed'));
      expect(
        GroupItemSource.owned.explanation,
        contains('exactly one'),
        reason: 'an item belongs to one group; a curated set is different',
      );
    });
  });

  group('parsing', () {
    test('an overview reads back everything the endpoint sends', () {
      final overview = GroupOverview.fromJson(<String, dynamic>{
        'itemSource': 'curated',
        'items': <dynamic>[
          <String, dynamic>{
            'itemId': 7,
            'name': 'Anchor Socket',
            'unitName': 'Nos',
            'orderCount': 3,
            'isVariant': true,
            'hasPipeline': true,
            'hasBaseline': false,
          },
        ],
        'children': <dynamic>[
          <String, dynamic>{'groupId': 11, 'name': 'Modular', 'itemCount': 4},
        ],
        'properties': <dynamic>[
          <String, dynamic>{
            'propertyKey': 'amps',
            'displayName': 'Amps',
            'unitSymbol': 'A',
            'mandatory': true,
            'sourceGroupId': 4,
            'sourceGroupName': 'Primary Group',
          },
        ],
        'lineage': <dynamic>[
          <String, dynamic>{'groupId': 4, 'name': 'Primary Group'},
        ],
        'summary': <String, dynamic>{
          'itemCount': 1,
          'orderedItemCount': 1,
          'orderLineCount': 3,
          'variantCount': 1,
          'units': <dynamic>['Nos'],
        },
      }, definition());

      expect(overview.itemSource, GroupItemSource.curated);
      expect(overview.items.single.name, 'Anchor Socket');
      expect(overview.items.single.isVariant, isTrue);
      expect(overview.items.single.isOrdered, isTrue);
      expect(overview.children.single.itemCount, 4);
      expect(overview.properties.single.displayName, 'Amps');
      expect(overview.properties.single.unitSymbol, 'A');
      expect(overview.inheritedProperties, hasLength(1));
      expect(overview.summary.orderLineCount, 3);
      expect(overview.summary.units, <String>['Nos']);
    });

    test('an empty payload is an empty group, not an exception', () {
      final overview = GroupOverview.fromJson(
        <String, dynamic>{},
        definition(),
      );
      expect(overview.items, isEmpty);
      expect(overview.properties, isEmpty);
      expect(overview.children, isEmpty);
      expect(overview.summary.isEmpty, isTrue);
      expect(overview.itemSource, GroupItemSource.owned);
    });
  });
}
