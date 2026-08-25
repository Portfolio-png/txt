import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/group_type_style.dart';
import 'package:flutter_test/flutter_test.dart';

/// The colour is only worth anything if it is the same colour everywhere. The
/// picker teaches it, the lists rely on it — one drifting surface and the whole
/// association is gone, so the mapping is pinned rather than trusted.

GroupDefinition group(String structure) => GroupDefinition(
  id: 1,
  name: 'G',
  groupStructure: structure,
  parentGroupId: null,
  unitId: 1,
  isArchived: false,
  usageCount: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  test('each kind of group has its own colour', () {
    final folders = <int>{
      GroupTypeStyle.hierarchical.folder.toARGB32(),
      GroupTypeStyle.component.folder.toARGB32(),
      GroupTypeStyle.combination.folder.toARGB32(),
    };
    expect(
      folders.length,
      3,
      reason: 'two kinds sharing a colour is the same as having none',
    );
  });

  test('a stored structure string resolves to its style', () {
    expect(
      GroupTypeStyle.forStructure('hierarchical'),
      same(GroupTypeStyle.hierarchical),
    );
    expect(
      GroupTypeStyle.forStructure('component'),
      same(GroupTypeStyle.component),
    );
    expect(
      GroupTypeStyle.forStructure('combination'),
      same(GroupTypeStyle.combination),
    );
  });

  test('an unknown or missing structure reads as an item group', () {
    // The column defaults to 'hierarchical', and a row written before the
    // column existed has nothing in it — neither should be drawn as a set.
    expect(GroupTypeStyle.forStructure(null), same(GroupTypeStyle.hierarchical));
    expect(GroupTypeStyle.forStructure(''), same(GroupTypeStyle.hierarchical));
    expect(
      GroupTypeStyle.forStructure('something-new'),
      same(GroupTypeStyle.hierarchical),
    );
  });

  test('a group resolves through the same mapping as a bare string', () {
    for (final structure in ['hierarchical', 'component', 'combination']) {
      expect(
        GroupTypeStyle.of(group(structure)),
        same(GroupTypeStyle.forStructure(structure)),
      );
    }
  });

  test('a combination group does not open — it is a set, not a container', () {
    expect(
      GroupTypeStyle.combination.iconFor(expanded: true),
      GroupTypeStyle.combination.iconFor(),
    );
    expect(
      GroupTypeStyle.hierarchical.iconFor(expanded: true),
      isNot(GroupTypeStyle.hierarchical.iconFor()),
    );
  });
}
