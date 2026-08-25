import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/domain/group_overview.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/groups/presentation/screens/groups_screen.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/domain/material_record.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/units/data/repositories/unit_repository.dart';
import 'package:core_erp/features/units/domain/unit_definition.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The groups screen is a tree, and a click has to unfold it.
///
/// Clicking a row used to open the detail panel instead, which meant the
/// nesting existed but could never be seen — the one thing the screen is for.
/// Reading a group is the second gesture now, not the first.

final _unit = UnitDefinition(
  id: 1,
  name: 'gross',
  symbol: 'gr',
  notes: '',
  unitGroupId: null,
  unitGroupName: null,
  conversionFactor: 1,
  conversionBaseUnitId: null,
  conversionBaseUnitName: null,
  conversionType: 'linear',
  precision: 2,
  unitGroupDimension: null,
  unitGroupBaseUnitId: null,
  isArchived: false,
  usageCount: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

GroupDefinition _group(
  int id,
  String name, {
  int? parentGroupId,
  int itemCount = 0,
}) {
  return GroupDefinition(
    id: id,
    name: name,
    groupStructure: 'hierarchical',
    parentGroupId: parentGroupId,
    unitId: 1,
    itemCount: itemCount,
    isArchived: false,
    usageCount: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

// Primary Group > Finish Goods > Sockets, with an item at the deepest level.
final _primary = _group(1, 'Primary Group');
final _finishGoods = _group(2, 'Finish Goods', parentGroupId: 1);
final _sockets = _group(3, 'Sockets', parentGroupId: 2, itemCount: 1);

ItemDefinition _item(int id, String name, {int? baseItemId}) {
  return ItemDefinition(
    id: id,
    name: name,
    displayName: name,
    alias: '',
    groupId: _sockets.id,
    unitId: _unit.id,
    baseItemId: baseItemId,
    quantity: 0,
    namingFormat: const <String>[],
    variationTree: const <ItemVariationNodeDefinition>[],
    usageCount: 0,
    isArchived: false,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

final _leafItem = _item(50, 'Socket Earthing');
final _variantA = _item(51, 'Socket Earthing 6 Amp', baseItemId: 50);
final _variantB = _item(52, 'Socket Earthing 16 Amp', baseItemId: 50);

class _FakeGroupRepository implements GroupRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async =>
      <GroupDefinition>[_primary, _finishGoods, _sockets];

  @override
  Future<GroupOverview> getGroupOverview(int groupId) async =>
      GroupOverview(group: _primary);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeItemRepository implements ItemRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async => <ItemDefinition>[
    _leafItem,
    _variantA,
    _variantB,
  ];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUnitRepository implements UnitRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<UnitDefinition>> getUnits() async => <UnitDefinition>[_unit];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInventoryRepository implements InventoryRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<MaterialRecord>> getMaterials() async => const <MaterialRecord>[];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<ItemsProvider> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1700, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final groupsProvider = GroupsProvider(repository: _FakeGroupRepository());
    final itemsProvider = ItemsProvider(repository: _FakeItemRepository());
    final unitsProvider = UnitsProvider(repository: _FakeUnitRepository());
    await groupsProvider.initialize();
    await itemsProvider.initialize();
    await unitsProvider.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GroupsProvider>.value(value: groupsProvider),
          ChangeNotifierProvider<ItemsProvider>.value(value: itemsProvider),
          ChangeNotifierProvider<UnitsProvider>.value(value: unitsProvider),
          ChangeNotifierProvider<InventoryProvider>(
            create: (_) =>
                InventoryProvider(repository: _FakeInventoryRepository()),
          ),
        ],
        child: const MaterialApp(home: GroupsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return itemsProvider;
  }

  /// Unfolding must be immediate, so the row carries no `onDoubleTap` — a
  /// widget answering to both holds the single tap until the double-tap window
  /// closes. A plain tap and one frame is all it should take.
  Future<void> click(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('clicking a group unfolds the groups nested inside it', (
    tester,
  ) async {
    await open(tester);

    // Collapsed, the screen is the roots only — a child is not loose in the
    // list beside its parent.
    expect(find.text('Primary Group'), findsOneWidget);
    expect(find.text('Finish Goods'), findsNothing);
    expect(find.text('Sockets'), findsNothing);

    await click(tester, 'Primary Group');
    expect(
      find.text('Finish Goods'),
      findsOneWidget,
      reason: 'a click unfolds the group rather than opening a panel over it',
    );
    // One level at a time: the grandchild waits for its own parent to open.
    expect(find.text('Sockets'), findsNothing);

    await click(tester, 'Finish Goods');
    expect(find.text('Sockets'), findsOneWidget);

    // Groups all the way down, and the items only at the end of the chain.
    expect(find.text('Socket Earthing'), findsNothing);
    await click(tester, 'Sockets');
    expect(
      find.text('Socket Earthing'),
      findsOneWidget,
      reason: 'the last group in the chain opens onto what is filed in it',
    );
    // The item is there; its variants are not spilled out beside it.
    expect(
      find.text('Socket Earthing 6 Amp'),
      findsNothing,
      reason: 'variants stay folded inside the item until it is asked to open',
    );

    // And it folds back up.
    await click(tester, 'Primary Group');
    expect(find.text('Finish Goods'), findsNothing);
    expect(find.text('Socket Earthing'), findsNothing);
  });

  testWidgets('the tree stops at the item and hands variants over', (
    tester,
  ) async {
    await open(tester);
    await click(tester, 'Primary Group');
    await click(tester, 'Finish Goods');
    await click(tester, 'Sockets');

    // The item says how many variants hang off it rather than listing them
    // into a view whose job is structure.
    expect(find.text('Socket Earthing'), findsOneWidget);
    expect(find.text('2 variants'), findsOneWidget);
    expect(find.text('Open in Items'), findsOneWidget);
    expect(find.text('Socket Earthing 6 Amp'), findsNothing);
    expect(find.text('Socket Earthing 16 Amp'), findsNothing);
  });

  testWidgets('clicking an item asks the items screen to open on it', (
    tester,
  ) async {
    final itemsProvider = await open(tester);
    await click(tester, 'Primary Group');
    await click(tester, 'Finish Goods');
    await click(tester, 'Sockets');

    await click(tester, 'Socket Earthing');

    // Clicking hands over rather than unfolding here: the request names the
    // item, so the items list arrives already open on it instead of collapsed.
    expect(itemsProvider.pendingRevealItemId, _leafItem.id);

    // Still no variants in the tree — the click went somewhere, it did not
    // quietly grow a second items view inside the groups screen.
    expect(find.text('Socket Earthing 6 Amp'), findsNothing);
  });

  testWidgets('a second click on the same row opens it', (tester) async {
    await open(tester);

    // First click unfolds, and does so without waiting on a double-tap window.
    await tester.tap(find.text('Primary Group'));
    await tester.pump();
    expect(
      find.text('Finish Goods'),
      findsOneWidget,
      reason: 'unfolding is the primary gesture and must not be held up',
    );

    // A second click landing quickly on the same row opens the panel.
    await tester.tap(find.text('Primary Group'));
    await tester.pumpAndSettle();
    expect(find.text('Item group'), findsOneWidget);
    expect(find.text('Edit Group'), findsOneWidget);
  });

  testWidgets('a click far apart from the last one is not a double click', (
    tester,
  ) async {
    await open(tester);

    await click(tester, 'Primary Group');
    expect(find.text('Finish Goods'), findsOneWidget);

    // Long enough after that it reads as a fresh click: it folds back up rather
    // than opening the panel. Real time, not pumped time — the gap between two
    // clicks is a fact about the person clicking, so it is measured against the
    // wall clock and a pumped frame would not move it.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await click(tester, 'Primary Group');
    expect(find.text('Finish Goods'), findsNothing);
    expect(find.text('Edit Group'), findsNothing);
  });
}
