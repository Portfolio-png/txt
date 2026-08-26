import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/group_picker_field.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// There were seven group pickers and no two agreed. Two rules were being
/// broken outright — one picker offered archived groups, another was filtered
/// by the Groups screen's search box — and only one showed that groups nest.
///
/// These are the rules the shared picker exists to hold. Asserted against the
/// option builder rather than through a widget, because the bugs were all in
/// *which groups were offered*, not in how the field was drawn.

GroupDefinition _group(
  int id,
  String name, {
  int? parentGroupId,
  String structure = 'hierarchical',
  bool isArchived = false,
  String groupType = 'item',
}) {
  return GroupDefinition(
    id: id,
    name: name,
    groupType: groupType,
    groupStructure: structure,
    parentGroupId: parentGroupId,
    unitId: 1,
    isArchived: isArchived,
    usageCount: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

// Primary Group > Finish Goods > Sockets, plus a set, an archived group, and a
// machine group that has no business appearing in an item picker.
final _all = <GroupDefinition>[
  _group(1, 'Primary Group'),
  _group(2, 'Finish Goods', parentGroupId: 1),
  _group(3, 'Sockets', parentGroupId: 2),
  _group(4, 'Socket Family', parentGroupId: 2, structure: 'combination'),
  _group(5, 'Retired Line', parentGroupId: 1, isArchived: true),
  _group(6, 'Press Shop', groupType: 'machine'),
];

class _FakeGroupRepository implements GroupRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async =>
      _all;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<GroupsProvider> provider() async {
  final p = GroupsProvider(repository: _FakeGroupRepository());
  await p.initialize();
  return p;
}

List<String> names(List<(GroupDefinition, int)> entries) =>
    entries.map((e) => e.$1.name).toList();

void main() {
  test('options come out in tree order, with the depth each sits at', () async {
    final p = await provider();
    final entries = GroupPickerField.optionsFor(p);

    expect(
      names(entries),
      // Siblings sort alphabetically among themselves — "socket family" before
      // "sockets", the space sorting ahead of the 's'.
      ['Primary Group', 'Finish Goods', 'Socket Family', 'Sockets'],
      reason: 'a child follows its parent rather than sorting beside it',
    );
    expect(entries.map((e) => e.$2).toList(), [0, 1, 2, 2]);
  });

  test('archived groups are never offered', () async {
    final p = await provider();
    expect(names(GroupPickerField.optionsFor(p)), isNot(contains('Retired Line')));
  });

  test('except the one already selected', () async {
    // Hiding a record's current group would leave the field blank and re-file
    // the record on the next save — worse than showing a group that is closed.
    final p = await provider();
    final entries = GroupPickerField.optionsFor(p, keepSelected: 5);
    expect(names(entries), contains('Retired Line'));
  });

  test('the search box on the Groups screen does not narrow a picker', () async {
    // This was a real defect: the picker read `filteredGroupsByType`, so with
    // "socket" typed into the Groups screen the only parents on offer were ones
    // matching "socket".
    final p = await provider();
    final before = names(GroupPickerField.optionsFor(p));
    p.setSearchQuery('socket');
    expect(names(GroupPickerField.optionsFor(p)), before);
  });

  test('scope decides whether sets are offered', () async {
    final p = await provider();
    expect(
      names(GroupPickerField.optionsFor(p, scope: GroupPickerScope.filable)),
      contains('Socket Family'),
      reason: 'an item can live under a set',
    );
    expect(
      names(
        GroupPickerField.optionsFor(p, scope: GroupPickerScope.hierarchical),
      ),
      isNot(contains('Socket Family')),
      reason: 'a set inside a set is not a tree anyone reads',
    );
  });

  test('a picker only offers its own type of group', () async {
    final p = await provider();
    expect(names(GroupPickerField.optionsFor(p)), isNot(contains('Press Shop')));
    expect(
      names(GroupPickerField.optionsFor(p, groupType: 'machine')),
      ['Press Shop'],
    );
  });

  test('a group is not offered as its own parent, nor its descendants', () async {
    final p = await provider();
    final entries = GroupPickerField.optionsFor(
      p,
      scope: GroupPickerScope.hierarchical,
      excludeGroupId: 2,
      excludeDescendants: true,
    );
    expect(names(entries), ['Primary Group']);
  });

  test('a group whose parent is hidden still appears, as a root', () async {
    // Otherwise excluding one group would silently take its children with it.
    final p = await provider();
    final entries = GroupPickerField.optionsFor(
      p,
      scope: GroupPickerScope.hierarchical,
      excludeGroupId: 2,
    );
    final sockets = entries.where((e) => e.$1.name == 'Sockets').single;
    expect(sockets.$2, 0, reason: 'orphaned by the exclusion, so drawn at root');
  });

  test('the label indents by depth and marks a set', () async {
    final p = await provider();
    final entries = GroupPickerField.optionsFor(p);
    final byName = {for (final e in entries) e.$1.name: e};

    expect(GroupPickerField.labelFor(byName['Primary Group']!.$1, 0),
        'Primary Group');
    expect(GroupPickerField.labelFor(byName['Finish Goods']!.$1, 1),
        '└ Finish Goods');
    expect(
      GroupPickerField.labelFor(byName['Socket Family']!.$1, 2),
      contains('· Set'),
    );
  });

  test('search text carries the lineage, so a parent finds its children', () async {
    final p = await provider();
    final sockets = _all.firstWhere((g) => g.name == 'Sockets');
    final text = GroupPickerField.searchTextFor(p, sockets);
    expect(text, contains('Primary Group'));
    expect(text, contains('Finish Goods'));
    expect(text, contains('Sockets'));
  });
}
