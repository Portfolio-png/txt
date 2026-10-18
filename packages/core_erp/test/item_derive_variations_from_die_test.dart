import 'package:core_erp/core/services/user_preferences_service.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:core_erp/features/clients/data/repositories/client_repository.dart';
import 'package:core_erp/features/clients/presentation/providers/clients_provider.dart';
import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/providers/item_form_sections_provider.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/items/presentation/screens/items_screen.dart';
import 'package:core_erp/features/materials/data/material_repository.dart';
import 'package:core_erp/features/materials/presentation/providers/materials_provider.dart';
import 'package:core_erp/features/units/data/repositories/unit_repository.dart';
import 'package:core_erp/features/units/domain/unit_definition.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:core_erp/features/variations/data/variation_tree_service.dart';
import 'package:core_erp/features/variations/domain/variation_node.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

UnitDefinition _unit(int id, String name, String symbol) => UnitDefinition(
  id: id,
  name: name,
  symbol: symbol,
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
  name: 'Sheet Parts',
  groupType: 'item',
  groupStructure: 'hierarchical',
  parentGroupId: null,
  unitId: 1,
  isArchived: false,
  usageCount: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class _FakeUnitRepository implements UnitRepository {
  final List<UnitDefinition> units = [_unit(1, 'Piece', 'pc')];
  @override
  Future<void> init() async {}
  @override
  Future<List<UnitDefinition>> getUnits() async => List.of(units);
  @override
  Future<List<ConversionPoint>> getGaugePoints() async => const [];
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeItemRepository implements ItemRepository {
  @override
  Future<void> init() async {}
  @override
  Future<List<ItemDefinition>> getItems() async => const [];
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGroupRepository implements GroupRepository {
  @override
  Future<void> init() async {}
  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async => [_group];
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInventoryRepository implements InventoryRepository {
  @override
  Future<void> init() async {}
  @override
  Future<void> seedIfEmpty() async {}
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClientRepository implements ClientRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMaterialRepository implements MaterialRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('deriving variations from die imports properties and values into item', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1700, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final variationService = VariationTreeService(baseUrl: '', useMockResponses: true);
    // Seed die 1 with Cavity and Gauge variation properties
    await variationService.save('die', '1', [
      VariationNode(
        kind: 'property',
        name: 'Cavity',
        children: [
          VariationNode(kind: 'value', name: '2', code: 'C2'),
          VariationNode(kind: 'value', name: '4', code: 'C4'),
        ],
      ),
      VariationNode(
        kind: 'property',
        name: 'Gauge',
        inputType: 'Gauge',
      ),
    ]);

    final itemWithDie = ItemDefinition(
      id: 50,
      name: 'Stamping Blank',
      alias: '',
      displayName: 'Stamping Blank',
      quantity: 0,
      groupId: 10,
      unitId: 1,
      usageCount: 0,
      isArchived: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      variationTree: const [],
      dies: const [ItemDieLink(id: 'die-1', toolCode: 'DIE-01')],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<VariationTreeService>.value(value: variationService),
          ChangeNotifierProvider<ItemsProvider>(
            create: (_) => ItemsProvider(repository: _FakeItemRepository()),
          ),
          ChangeNotifierProvider<GroupsProvider>(
            create: (_) => GroupsProvider(repository: _FakeGroupRepository()),
          ),
          ChangeNotifierProvider<UnitsProvider>(
            create: (_) => UnitsProvider(repository: _FakeUnitRepository()),
          ),
          ChangeNotifierProvider<InventoryProvider>(
            create: (_) => InventoryProvider(repository: _FakeInventoryRepository()),
          ),
          ChangeNotifierProvider<ClientsProvider>(
            create: (_) => ClientsProvider(repository: _FakeClientRepository()),
          ),
          ChangeNotifierProvider<MaterialsProvider>(
            create: (_) => MaterialsProvider(repository: _FakeMaterialRepository()),
          ),
          ChangeNotifierProvider<AuthProvider>(
            create: (_) => AuthProvider(baseUrl: '', demoMode: true),
          ),
          ChangeNotifierProvider<ItemFormSectionsProvider>(
            create: (_) => ItemFormSectionsProvider(
              service: UserPreferencesService(baseUrl: '', useMockResponses: true),
            ),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => ItemsScreen.openEditor(context, item: itemWithDie),
                  child: const Text('Open item editor'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open editor
    await tester.tap(find.text('Open item editor'));
    await tester.pumpAndSettle();

    // Derive from Die button should be visible because die-1 is attached
    final deriveButton = find.byKey(const ValueKey('items_derive_variations_die'));
    expect(deriveButton, findsOneWidget);

    // Tap Derive from Die
    await tester.tap(deriveButton);
    await tester.pumpAndSettle();

    // Verify properties and values imported
    expect(find.text('Cavity'), findsWidgets);
    expect(find.text('Gauge'), findsWidgets);
    expect(find.textContaining('2'), findsWidgets);
    expect(find.textContaining('4'), findsWidgets);
  });
}
