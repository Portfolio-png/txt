import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/domain/item_inputs.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/items/presentation/providers/item_form_sections_provider.dart';
import 'package:core_erp/features/items/presentation/screens/items_screen.dart';
import 'package:core_erp/features/units/data/repositories/unit_repository.dart';
import 'package:core_erp/features/units/domain/unit_definition.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:core_erp/core/services/user_preferences_service.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:core_erp/features/clients/data/repositories/client_repository.dart';
import 'package:core_erp/features/clients/domain/client_definition.dart';
import 'package:core_erp/features/clients/presentation/providers/clients_provider.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/domain/material_record.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/materials/data/material_repository.dart';
import 'package:core_erp/features/materials/domain/material_definition.dart';
import 'package:core_erp/features/materials/presentation/providers/materials_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// A value's Code is what a variant is named and searched by once naming-by-code
/// is on. A half-coded tree quietly falls back to value names, so two items end
/// up disagreeing about what a code means. The editor refuses the save instead,
/// and says which property is at fault.

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

final _group = GroupDefinition(
  id: 10,
  name: 'Finish Goods',
  groupStructure: 'hierarchical',
  parentGroupId: null,
  unitId: 1,
  isArchived: false,
  usageCount: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

ItemVariationNodeDefinition _node({
  required int id,
  required ItemVariationNodeKind kind,
  required String name,
  String code = '',
  List<ItemVariationNodeDefinition> children = const [],
}) {
  return ItemVariationNodeDefinition(
    id: id,
    itemId: 100,
    parentNodeId: null,
    kind: kind,
    name: name,
    code: code,
    displayName: '',
    position: 0,
    isArchived: false,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    children: children,
  );
}

/// "Socket Amp" holds 6 Amp (coded) and 16 Amp (not coded).
final _item = ItemDefinition(
  id: 100,
  name: 'Socket',
  displayName: 'Socket',
  alias: '',
  groupId: _group.id,
  unitId: _unit.id,
  quantity: 0,
  namingFormat: const <String>[],
  usageCount: 0,
  isArchived: false,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  variationTree: <ItemVariationNodeDefinition>[
    _node(
      id: 1,
      kind: ItemVariationNodeKind.property,
      name: 'Socket Amp',
      children: <ItemVariationNodeDefinition>[
        _node(id: 2, kind: ItemVariationNodeKind.value, name: '6 Amp', code: 'A6'),
        _node(id: 3, kind: ItemVariationNodeKind.value, name: '16 Amp'),
      ],
    ),
  ],
);

class _FakeItemRepository implements ItemRepository {
  UpdateItemInput? lastUpdate;

  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async => <ItemDefinition>[_item];

  @override
  Future<ItemDefinition> updateItem(UpdateItemInput input) async {
    lastUpdate = input;
    return _item;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGroupRepository implements GroupRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async =>
      <GroupDefinition>[_group];

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

class _FakeClientRepository implements ClientRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<ClientDefinition>> getClients() async =>
      const <ClientDefinition>[];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMaterialRepository implements MaterialRepository {
  @override
  Future<List<MaterialDefinition>> list({bool includeArchived = false}) async =>
      const <MaterialDefinition>[];

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
  Future<_FakeItemRepository> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1700, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final itemRepo = _FakeItemRepository();
    final itemsProvider = ItemsProvider(repository: itemRepo);
    final groupsProvider = GroupsProvider(repository: _FakeGroupRepository());
    final unitsProvider = UnitsProvider(repository: _FakeUnitRepository());
    await itemsProvider.initialize();
    await groupsProvider.initialize();
    await unitsProvider.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ItemsProvider>.value(value: itemsProvider),
          ChangeNotifierProvider<GroupsProvider>.value(value: groupsProvider),
          ChangeNotifierProvider<UnitsProvider>.value(value: unitsProvider),
          ChangeNotifierProvider<InventoryProvider>(
            create: (_) =>
                InventoryProvider(repository: _FakeInventoryRepository()),
          ),
          ChangeNotifierProvider<ClientsProvider>(
            create: (_) => ClientsProvider(repository: _FakeClientRepository()),
          ),
          ChangeNotifierProvider<MaterialsProvider>(
            create: (_) =>
                MaterialsProvider(repository: _FakeMaterialRepository()),
          ),
          ChangeNotifierProvider<AuthProvider>(
            create: (_) => AuthProvider(baseUrl: '', demoMode: true),
          ),
          ChangeNotifierProvider<ItemFormSectionsProvider>(
            create: (_) => ItemFormSectionsProvider(
              service: UserPreferencesService(
                baseUrl: '',
                useMockResponses: true,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => ItemsScreen.openEditor(context, item: _item),
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
    return itemRepo;
  }

  testWidgets('a value with no Code is refused, and the property is named', (
    tester,
  ) async {
    final repo = await open(tester);

    // Said under the property itself, before anyone presses anything.
    expect(
      find.textContaining('Every value needs a Code'),
      findsWidgets,
      reason: 'the tree marks the property whose values are not coded',
    );

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(
      repo.lastUpdate,
      isNull,
      reason: 'a half-coded tree must not reach the repository',
    );
    expect(
      find.textContaining('Socket Amp'),
      findsWidgets,
      reason: 'the refusal names the property at fault',
    );
  });
}
