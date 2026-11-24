import 'package:core_erp/features/items/domain/developed_for.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/features/items/presentation/widgets/catalog_quick_entry_dialog.dart';
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
import 'package:core_erp/features/inventory/presentation/screens/inventory_screen.dart';
import 'package:core_erp/app/preferences/preferences_provider.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_create_command_provider.dart';
import 'package:core_erp/features/items/presentation/widgets/item_detail_panel.dart';
import 'package:core_erp/features/units/data/repositories/unit_repository.dart';
import 'package:core_erp/features/units/domain/unit_definition.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Inventory shows item groups and sets, nothing else (user, 2026-11-24):
/// machine and die types are groups too, and each came up as an empty
/// inventory folder.

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

GroupDefinition _group(int id, String name, {int itemCount = 0, String groupType = 'item'}) {
  return GroupDefinition(
    id: id,
    name: name,
    groupType: groupType,
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
final _presses = _group(9, 'Power Press Type', groupType: 'machine');

ItemDefinition _item(
  int id,
  String name, {
  int? baseItemId,
  int? groupId,
  DevelopedFor developedFor = DevelopedFor.empty,
}) {
  return ItemDefinition(
    id: id,
    name: name,
    displayName: name,
    alias: '',
    groupId: groupId ?? _sockets.id,
    unitId: _unit.id,
    baseItemId: baseItemId,
    developedFor: developedFor,
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
final _variantA = _item(
  51,
  'Socket Earthing 6 Amp',
  baseItemId: 50,
  developedFor: DevelopedFor(
    kind: DevelopedForKind.client,
    clientId: 7,
    clientName: 'Gold Madel Industries',
    companyName: 'Gold Madel Industries',
    contactName: 'Kissan Jain',
    designation: 'Director',
    phone: '986565656',
    email: 'kissan@goldmadel.example',
    at: DateTime.utc(2026, 5, 15, 4, 35),
    quotationAmount: 85000,
  ),
);
// Developed in-house: a recorded answer, and a different one from the blank
// the Plug Top carries.
final _selfMade = _item(
  52,
  'Socket Earthing 16 Amp',
  baseItemId: 50,
  developedFor: const DevelopedFor(kind: DevelopedForKind.self),
);
final _plug = _item(60, 'Plug Top', groupId: _plugs.id);

class _FakeGroupRepository implements GroupRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async =>
      <GroupDefinition>[_sockets, _plugs, _presses];

  @override
  Future<GroupOverview> getGroupOverview(int groupId) async =>
      GroupOverview(group: _sockets);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeItemRepository implements ItemRepository {

  // Whole-item saves and the editor read the part fresh from the server
  // (B42). Here the server is this fake's own list.
  @override
  Future<ItemDefinition?> getItemFresh(int id) async {
    for (final item in await getItems()) {
      if (item.id == id) return item;
    }
    return null;
  }
  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async => <ItemDefinition>[
    _leafItem,
    _variantA,
    _selfMade,
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

Future<void> _openInventory(WidgetTester tester) async {
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
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(baseUrl: '', demoMode: true),
        ),
        ChangeNotifierProvider<PreferencesProvider>(
          create: (_) => PreferencesProvider(),
        ),
        ChangeNotifierProvider<InventoryCreateCommandProvider>(
          create: (_) => InventoryCreateCommandProvider(),
        ),
        ChangeNotifierProvider<InventoryProvider>(
          create: (_) =>
              InventoryProvider(repository: _FakeInventoryRepository()),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
    ),
  );
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('inventory lists item groups, not machine or die types', (tester) async {
    await _openInventory(tester);
    expect(find.text('Sockets'), findsWidgets, reason: 'an item group');
    expect(find.text('Plugs'), findsWidgets, reason: 'an item group');
    expect(find.text('Power Press Type'), findsNothing, reason: 'a machine type');
  });
}
