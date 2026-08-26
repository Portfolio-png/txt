import 'package:core_erp/core/widgets/soft_master_data.dart';
import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/domain/group_overview.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/items/presentation/screens/items_screen.dart';
import 'package:core_erp/features/items/presentation/widgets/item_detail_panel.dart';
import 'package:core_erp/features/units/data/repositories/unit_repository.dart';
import 'package:core_erp/features/units/domain/unit_definition.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Another screen hands an item over; the items screen has to land on it.
///
/// The groups tree sends the user here with the item named. Arriving meant
/// nothing happened unless the table was showing — a card view, the Sets view
/// or an active search all swallowed the request — and even then the group
/// only unfolded, leaving the item somewhere in a list with nothing to say
/// which row it was.

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

GroupDefinition _group(int id, String name, {int itemCount = 0}) {
  return GroupDefinition(
    id: id,
    name: name,
    groupStructure: 'hierarchical',
    parentGroupId: null,
    unitId: 1,
    itemCount: itemCount,
    isArchived: false,
    usageCount: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

final _sockets = _group(3, 'Sockets', itemCount: 1);
final _plugs = _group(4, 'Plugs', itemCount: 1);

ItemDefinition _item(int id, String name, {int? baseItemId, int? groupId}) {
  return ItemDefinition(
    id: id,
    name: name,
    displayName: name,
    alias: '',
    groupId: groupId ?? _sockets.id,
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
final _plug = _item(60, 'Plug Top', groupId: _plugs.id);

class _FakeGroupRepository implements GroupRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async =>
      <GroupDefinition>[_sockets, _plugs];

  @override
  Future<GroupOverview> getGroupOverview(int groupId) async =>
      GroupOverview(group: _sockets);

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
    _plug,
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
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<ItemsProvider> open(
    WidgetTester tester, {
    bool startOnSets = false,
  }) async {
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
        child: MaterialApp(home: ItemsScreen(initialSetsView: startOnSets)),
      ),
    );
    await tester.pumpAndSettle();
    return itemsProvider;
  }

  Iterable<SoftMasterRow> highlightedRows(WidgetTester tester) => tester
      .widgetList<SoftMasterRow>(find.byType(SoftMasterRow))
      .where((row) => row.isHighlighted);

  testWidgets('a reveal unfolds to the item, lights it and opens its details', (
    tester,
  ) async {
    final items = await open(tester);

    // Collapsed: the groups are there, the items inside them are not.
    expect(find.text('Sockets'), findsOneWidget);
    expect(find.text('Socket Earthing'), findsNothing);

    items.revealItem(_variantA.id);
    await tester.pumpAndSettle();

    // The request is spent — a rebuild must not re-open rows the user closes.
    expect(items.pendingRevealItemId, isNull);

    // Group and base item unfolded, so the variant's row is on screen...
    expect(find.text('Socket Earthing'), findsWidgets);
    expect(find.text('Socket Earthing 6 Amp'), findsWidgets);
    // ...and it is the one row lit up.
    final lit = highlightedRows(tester).toList();
    expect(lit.length, 1, reason: 'exactly the revealed row is highlighted');

    // And its details are open without another click.
    expect(find.byType(ItemDetailPanel), findsOneWidget);
  });

  testWidgets('a reveal leaves Sets and drops a search that hides the item', (
    tester,
  ) async {
    final items = await open(tester, startOnSets: true);
    items.setSearchQuery('nothing matches this');
    await tester.pumpAndSettle();
    expect(find.text('Sockets'), findsNothing);

    items.revealItem(_plug.id);
    await tester.pumpAndSettle();

    expect(items.searchQuery, '', reason: 'the search was hiding the item');
    expect(find.text('Plug Top'), findsWidgets);
    expect(highlightedRows(tester).length, 1);
    expect(find.byType(ItemDetailPanel), findsOneWidget);
  });

  testWidgets('a reveal for an item that is gone says so and does nothing', (
    tester,
  ) async {
    final items = await open(tester);

    items.revealItem(999);
    await tester.pumpAndSettle();

    expect(items.pendingRevealItemId, isNull);
    expect(highlightedRows(tester), isEmpty);
    expect(find.byType(ItemDetailPanel), findsNothing);
    expect(find.text('That item is no longer in the list.'), findsOneWidget);
  });
}
