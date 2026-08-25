import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/domain/group_inputs.dart';
import 'package:core_erp/features/groups/domain/group_overview.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/groups/presentation/widgets/group_view_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The view itself: does opening a group actually show what the group is.

class _FakeGroupRepository implements GroupRepository {
  _FakeGroupRepository(this.overview);

  final GroupOverview overview;
  int loads = 0;

  @override
  Future<GroupOverview> getGroupOverview(int groupId) async {
    loads += 1;
    return overview;
  }

  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async =>
      <GroupDefinition>[overview.group];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  GroupDefinition definition({
    String structure = 'hierarchical',
    String description = '',
  }) {
    return GroupDefinition(
      id: 10,
      name: 'Electrical Fittings',
      groupStructure: structure,
      description: description,
      parentGroupId: 4,
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  }

  GroupOverview overviewFor(
    GroupDefinition group, {
    GroupItemSource source = GroupItemSource.owned,
    List<GroupOverviewItem>? items,
  }) {
    return GroupOverview(
      group: group,
      itemSource: source,
      items: items ?? const <GroupOverviewItem>[
        GroupOverviewItem(
          itemId: 1,
          name: 'Anchor Roma Socket 10A',
          unitName: 'Nos',
          orderCount: 3,
          hasPipeline: true,
        ),
        GroupOverviewItem(
          itemId: 2,
          name: 'Philips LED Bulb',
          unitName: 'Nos',
          isVariant: true,
        ),
      ],
      children: const <GroupChild>[
        GroupChild(groupId: 11, name: 'Modular', itemCount: 4),
      ],
      properties: const <GroupProperty>[
        GroupProperty(
          propertyKey: 'amps',
          displayName: 'Amps',
          unitSymbol: 'A',
          sourceGroupId: 10,
          sourceGroupName: 'Electrical Fittings',
        ),
        GroupProperty(
          propertyKey: 'colour',
          displayName: 'Colour',
          sourceGroupId: 4,
          sourceGroupName: 'Primary Group',
        ),
      ],
      lineage: const <GroupChild>[
        GroupChild(groupId: 4, name: 'Primary Group'),
        GroupChild(groupId: 10, name: 'Electrical Fittings'),
      ],
      summary: const GroupSummary(
        itemCount: 2,
        orderedItemCount: 1,
        orderLineCount: 3,
        variantCount: 1,
        withPipelineCount: 1,
        units: <String>['Nos'],
      ),
    );
  }

  Future<_FakeGroupRepository> open(
    WidgetTester tester, {
    GroupDefinition? group,
    GroupItemSource source = GroupItemSource.owned,
    Future<void> Function(GroupDefinition)? onEdit,
    List<GroupOverviewItem>? items,
  }) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final target = group ?? definition();
    final repository = _FakeGroupRepository(
      overviewFor(target, source: source, items: items),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<GroupsProvider>(
        create: (_) => GroupsProvider(repository: repository),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showGroupViewDialog(
                    context,
                    group: target,
                    onEdit: onEdit,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return repository;
  }

  // Variants are filed in the same group as the item they come from, so
  // without nesting they sit beside their own base as if they were peers.
  const nestingItems = <GroupOverviewItem>[
    GroupOverviewItem(itemId: 1, name: 'Socket Earthing', orderCount: 3),
    GroupOverviewItem(
      itemId: 2,
      name: 'Socket Earthing 6 Amp Brass',
      isVariant: true,
      baseItemId: 1,
    ),
    GroupOverviewItem(
      itemId: 3,
      name: 'Socket Earthing 16 Amp Brass',
      isVariant: true,
      baseItemId: 1,
    ),
    // Its base item lives in another group, so there is nothing here to nest
    // it under.
    GroupOverviewItem(
      itemId: 4,
      name: 'Orphan Variant',
      isVariant: true,
      baseItemId: 99,
    ),
  ];

  testWidgets('a group shows its items, with variants folded under them', (
    tester,
  ) async {
    await open(tester, items: nestingItems);

    // The base item and the stray are the group's own reading of itself.
    expect(find.text('Socket Earthing'), findsOneWidget);
    expect(find.text('Orphan Variant'), findsOneWidget);

    // Its own variants are counted but folded away.
    expect(find.text('2 variants'), findsOneWidget);
    expect(find.text('Socket Earthing 6 Amp Brass'), findsNothing);
    expect(find.text('Socket Earthing 16 Amp Brass'), findsNothing);

    await tester.tap(find.text('2 variants'));
    await tester.pumpAndSettle();

    expect(find.text('Socket Earthing 6 Amp Brass'), findsOneWidget);
    expect(find.text('Socket Earthing 16 Amp Brass'), findsOneWidget);

    await tester.tap(find.text('2 variants'));
    await tester.pumpAndSettle();
    expect(find.text('Socket Earthing 6 Amp Brass'), findsNothing);
  });

  testWidgets('a variant with no base item here is not hidden', (tester) async {
    await open(tester, items: nestingItems);

    // Nothing to fold it under, so it keeps the word that says what it is.
    expect(find.textContaining('Variant'), findsWidgets);
    expect(find.text('Orphan Variant'), findsOneWidget);
  });

  testWidgets('opening a group shows what it is, not how to edit it', (
    tester,
  ) async {
    final repository = await open(tester);
    expect(repository.loads, 1);

    expect(find.text('Electrical Fittings'), findsWidgets);
    // What kind of group it is, said plainly.
    expect(find.text('Item group'), findsOneWidget);
    // Where it sits.
    expect(find.text('Primary Group'), findsWidgets);
    // What is in it.
    expect(find.text('Anchor Roma Socket 10A'), findsOneWidget);
    expect(find.text('Philips LED Bulb'), findsOneWidget);
    // And what the items add up to. Fact labels are set uppercase.
    expect(find.text('ITEMS'), findsOneWidget);
    expect(find.text('2'), findsWidgets, reason: 'two items');
    expect(find.text('ORDER LINES'), findsOneWidget);
    expect(find.text('3'), findsWidgets, reason: 'across three order lines');
    // A fact with nothing to say is left out rather than shown as a zero.
    expect(find.text('MASTER DATA'), findsNothing);
  });

  testWidgets('a combination group says its items are gathered, not filed', (
    tester,
  ) async {
    await open(
      tester,
      group: definition(structure: 'combination'),
      source: GroupItemSource.curated,
    );
    expect(find.text('Combination group'), findsOneWidget);
    expect(find.textContaining('gathered into this group'), findsOneWidget);
    expect(find.textContaining('filed under this group'), findsNothing);
  });

  testWidgets('a plain group says its items are filed under it', (
    tester,
  ) async {
    await open(tester);
    expect(find.textContaining('filed under this group'), findsOneWidget);
    expect(find.textContaining('gathered into this group'), findsNothing);
  });

  testWidgets('an inherited property is marked as inherited', (tester) async {
    await open(tester);
    // Both properties show; only the inherited one names another group.
    expect(find.text('Amps (A)'), findsOneWidget);
    expect(find.text('Colour'), findsOneWidget);
    expect(find.textContaining('1 inherited'), findsOneWidget);
  });

  testWidgets('editing is available but is not what a click does', (
    tester,
  ) async {
    var edited = false;
    await open(tester, onEdit: (_) async => edited = true);

    // The view opened; the editor did not.
    expect(edited, isFalse);
    expect(find.text('Edit Group'), findsOneWidget);

    await tester.tap(find.text('Edit Group'));
    await tester.pumpAndSettle();
    expect(edited, isTrue, reason: 'editing is one button away');
  });

  testWidgets('the panel shows what is in the group, not the tree around it', (
    tester,
  ) async {
    await open(tester);

    // The panel answers "what is in this group". Its contents are the point.
    expect(find.text('Items filed under this group'), findsOneWidget);
    expect(find.text('Anchor Roma Socket 10A'), findsOneWidget);

    // The shape of the tree is the main screen's job — the groups list nests
    // groups as groups and opens the last one onto its items. Repeating it here
    // put the same structure in two places, drawn two different ways.
    expect(find.text('Where this group sits'), findsNothing);

    // The lineage is still one line in the header, which is a position rather
    // than a second copy of the tree.
    expect(find.textContaining('Primary Group'), findsWidgets);
  });
}
