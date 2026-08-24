import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/domain/item_inputs.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/items/presentation/screens/items_screen.dart';
import 'package:core_erp/features/units/domain/unit_definition.dart';
import 'package:core_erp/features/units/data/repositories/unit_repository.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:core_erp/features/items/presentation/providers/item_form_sections_provider.dart';
import 'package:core_erp/core/services/user_preferences_service.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/domain/material_record.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// A spawned variant is filed under its base item's group, but it can be moved
/// out on its own — the variant editor carries a real Group field. What matters
/// is that the pick reaches the save: a field that changes the dropdown and
/// then sends the old group is worse than no field at all.

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

GroupDefinition _group(int id, String name, {String structure = 'hierarchical'}) {
  return GroupDefinition(
    id: id,
    name: name,
    groupStructure: structure,
    parentGroupId: null,
    unitId: 1,
    isArchived: false,
    usageCount: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

final _finishGoods = _group(10, 'Finish Goods');
final _scrap = _group(11, 'Scrap');
final _set = _group(12, 'Socket Family', structure: 'combination');

final _variant = ItemDefinition(
  id: 100,
  name: '16 Amp Copper Socket',
  displayName: '16 Amp Copper Socket',
  alias: '',
  groupId: _finishGoods.id,
  unitId: _unit.id,
  baseItemId: 99,
  quantity: 0,
  namingFormat: const <String>[],
  variationTree: const <ItemVariationNodeDefinition>[],
  usageCount: 0,
  isArchived: false,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

final _base = ItemDefinition(
  id: 99,
  name: 'Socket',
  displayName: 'Socket',
  alias: '',
  groupId: _finishGoods.id,
  unitId: _unit.id,
  quantity: 0,
  namingFormat: const <String>[],
  variationTree: const <ItemVariationNodeDefinition>[],
  usageCount: 0,
  isArchived: false,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class _FakeItemRepository implements ItemRepository {
  UpdateItemInput? lastUpdate;

  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async => <ItemDefinition>[
    _base,
    _variant,
  ];

  @override
  Future<ItemDefinition> updateItem(UpdateItemInput input) async {
    lastUpdate = input;
    return _variant;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGroupRepository implements GroupRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async =>
      <GroupDefinition>[_finishGoods, _scrap, _set];

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

class _FakeUnitRepository implements UnitRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<UnitDefinition>> getUnits() async => <UnitDefinition>[_unit];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<_FakeItemRepository> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
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
                  onPressed: () =>
                      ItemsScreen.openEditor(context, item: _variant),
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

  testWidgets('a variant can be moved to another group on its own', (
    tester,
  ) async {
    final repo = await open(tester);

    // The trimmed variant editor, with the group as a real field.
    expect(find.text('Edit Basic Item'), findsOneWidget);
    expect(find.textContaining('Finish Goods'), findsWidgets);

    await tester.tap(find.textContaining('Finish Goods').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scrap').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(repo.lastUpdate, isNotNull, reason: 'the save must reach the repo');
    expect(
      repo.lastUpdate!.groupId,
      _scrap.id,
      reason: 'the group picked in the field is the group that is saved',
    );
    expect(
      repo.lastUpdate!.baseItemId,
      _base.id,
      reason: 'moving a variant must not detach it from its base',
    );
  });

  testWidgets('closing on an unsaved group change asks before losing it', (
    tester,
  ) async {
    final repo = await open(tester);

    await tester.tap(find.textContaining('Finish Goods').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scrap').last);
    await tester.pumpAndSettle();

    // Save is at the foot of a long form; closing from the header used to throw
    // the edit away without a word, which reads exactly like it did not save.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    expect(repo.lastUpdate, isNull, reason: 'nothing saved yet');

    // Backing out of the prompt keeps the editor open with the edit intact.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Basic Item'), findsOneWidget);

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(repo.lastUpdate?.groupId, _scrap.id);
  });
}
