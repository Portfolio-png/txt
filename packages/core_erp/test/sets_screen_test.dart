import 'package:core_erp/core/widgets/soft_master_data.dart';
import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/inventory/data/repositories/api_inventory_repository.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/domain/inventory_control_tower.dart';
import 'package:core_erp/features/inventory/domain/inventory_set_definition.dart';
import 'package:core_erp/features/inventory/domain/material_record.dart';
import 'package:core_erp/features/inventory/domain/variation_stock_record.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/inventory/presentation/screens/sets_screen.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The Item Sets master.
///
/// This list used to be a view inside the items master, reachable only from a
/// segmented control. It had no search, no row actions, and it mixed the sets
/// production mints for itself in among the ones people build by hand — so a
/// floor with twenty runs behind it showed twenty sets nobody had made.
///
/// What is worth guarding here is the regroup write. The save is a full
/// replace, which means a regroup has to carry the photo (the server writes
/// `photo_url` on every update) and send `expectedVersion` (or it overwrites
/// whoever else was in the set), while being the one write that is *allowed* to
/// speak about the group at all.

GroupDefinition _group(int id, String name, {int? parentGroupId}) {
  return GroupDefinition(
    id: id,
    name: name,
    groupType: 'item',
    groupStructure: 'hierarchical',
    parentGroupId: parentGroupId,
    unitId: 1,
    isArchived: false,
    usageCount: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

final _groups = <GroupDefinition>[
  _group(1, 'Ash Trays'),
  _group(2, 'Round', parentGroupId: 1),
];

InventorySetLineDefinition _line({
  required int id,
  required int itemId,
  required String name,
  int quantity = 1,
}) {
  return InventorySetLineDefinition(
    id: id,
    itemId: itemId,
    variationLeafNodeId: 0,
    quantity: quantity,
    position: 0,
    itemName: name,
    itemDisplayName: name,
    variationPathLabel: 'Base item',
    variationPathNodeIds: const <int>[],
  );
}

/// A set somebody defined, filed under a group, with a photo.
final _definedSet = InventorySetDefinition(
  id: 7,
  name: 'Bathroom Kit',
  totalItemCount: 3,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  groupId: 2,
  groupName: 'Round',
  photoUrl: 'https://example.test/kit.png',
  version: 4,
  lines: <InventorySetLineDefinition>[
    _line(id: 1, itemId: 11, name: 'Angle Patti', quantity: 2),
    _line(id: 2, itemId: 12, name: 'Lid'),
  ],
);

/// A second defined set, so a search has something to exclude.
final _otherSet = InventorySetDefinition(
  id: 8,
  name: 'Kitchen Kit',
  totalItemCount: 1,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  lines: <InventorySetLineDefinition>[
    _line(id: 3, itemId: 13, name: 'Tap'),
  ],
);

/// What an assembly run minted for itself.
final _producedSet = InventorySetDefinition(
  id: 9,
  name: 'Temporary · Assembly · run-42',
  totalItemCount: 1,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  isTemporary: true,
  originRunId: 'run-42',
  originNodeId: 'node-1',
  lines: <InventorySetLineDefinition>[
    _line(id: 4, itemId: 14, name: 'Shell'),
  ],
);

class _FakeGroupRepository implements GroupRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async =>
      _groups;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeItemRepository implements ItemRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async => const <ItemDefinition>[];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CapturingInventoryRepository implements InventoryRepository {
  _CapturingInventoryRepository(this.serverSets);

  List<InventorySetDefinition> serverSets;
  final List<SaveInventorySetInput> saved = <SaveInventorySetInput>[];
  final List<int> deleted = <int>[];

  /// Refuse the next save the way a 409 does.
  bool refuseAsConflict = false;

  @override
  Future<void> init() async {}

  @override
  Future<void> seedIfEmpty() async {}

  @override
  Future<List<MaterialRecord>> getAllMaterials() async =>
      const <MaterialRecord>[];

  @override
  Future<List<VariationStockRecord>> getVariationStock() async =>
      const <VariationStockRecord>[];

  @override
  Future<InventoryHealthSnapshot> getInventoryHealth() async =>
      const InventoryHealthSnapshot();

  @override
  Future<List<InventorySetDefinition>> getSets() async => serverSets;

  @override
  Future<InventorySetDefinition> saveSet(SaveInventorySetInput input) async {
    saved.add(input);
    if (refuseAsConflict) {
      throw InventoryApiException(
        '"${input.name}" changed since you opened it. Reload it and make '
        "your change again — saving now would replace someone else's edit.",
        code: 'set_changed',
        statusCode: 409,
      );
    }
    return InventorySetDefinition(
      id: input.id ?? 99,
      name: input.name,
      totalItemCount: 1,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      lines: const <InventorySetLineDefinition>[],
      groupId: input.groupId,
      photoUrl: input.photoUrl,
      version: (input.expectedVersion ?? 0) + 1,
    );
  }

  @override
  Future<void> deleteSet(int setId) async {
    deleted.add(setId);
    serverSets = serverSets
        .where((set) => set.id != setId)
        .toList(growable: false);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_CapturingInventoryRepository> _pumpSets(
  WidgetTester tester, {
  List<InventorySetDefinition>? sets,
}) async {
  tester.view.physicalSize = const Size(1700, 1300);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repository = _CapturingInventoryRepository(
    sets ?? <InventorySetDefinition>[_definedSet, _otherSet, _producedSet],
  );
  final groupsProvider = GroupsProvider(repository: _FakeGroupRepository());
  await groupsProvider.initialize();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<InventoryProvider>.value(
          value: InventoryProvider(repository: repository),
        ),
        ChangeNotifierProvider<ItemsProvider>.value(
          value: ItemsProvider(repository: _FakeItemRepository()),
        ),
        ChangeNotifierProvider<GroupsProvider>.value(value: groupsProvider),
      ],
      child: const MaterialApp(home: SetsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

Future<void> _tapAction(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(SoftActionLink, label);
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  group('the sets master', () {
    testWidgets('opens on the sets somebody defined', (tester) async {
      await _pumpSets(tester);

      expect(find.text('Bathroom Kit'), findsOneWidget);
      expect(find.text('Kitchen Kit'), findsOneWidget);
      // Run output is not catalogue. It used to sit in this list unmarked.
      expect(find.text('Temporary · Assembly · run-42'), findsNothing);
      // And the group a set is filed under reads off the set itself.
      expect(find.text('Round'), findsOneWidget);
    });

    testWidgets('production sets are there when asked for, and marked', (
      tester,
    ) async {
      await _pumpSets(tester);

      await tester.tap(find.text('From production'));
      await tester.pumpAndSettle();

      expect(find.text('Temporary · Assembly · run-42'), findsOneWidget);
      expect(find.text('Bathroom Kit'), findsNothing);
      expect(find.text('From production'), findsWidgets);
    });

    testWidgets('a produced set cannot be edited or refiled, and says why', (
      tester,
    ) async {
      await _pumpSets(tester, sets: <InventorySetDefinition>[_producedSet]);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      // Drawn, not hidden — otherwise a missing permission and a missing
      // feature look the same.
      final edit = find.widgetWithText(SoftActionLink, 'Edit');
      expect(edit, findsOneWidget);
      expect(tester.widget<SoftActionLink>(edit).onTap, isNull);
      expect(
        find.byTooltip(
          'This set is what a production run made. Its composition is a '
          'record, so it cannot be edited.',
        ),
        findsOneWidget,
      );
    });
  });

  group('searching a set', () {
    testWidgets('finds it by an item inside it, not just by its name', (
      tester,
    ) async {
      await _pumpSets(tester);
      final inventory = _inventoryOf(tester);

      // Nobody remembers what the kit is called; they remember what is in it.
      inventory.setSetsQuery('angle patti');
      await tester.pumpAndSettle();

      expect(find.text('Bathroom Kit'), findsOneWidget);
      expect(find.text('Kitchen Kit'), findsNothing);
    });

    testWidgets('an empty result says the search looked inside', (
      tester,
    ) async {
      await _pumpSets(tester);
      _inventoryOf(tester).setSetsQuery('nothing like this');
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing matches'), findsOneWidget);
      expect(
        find.textContaining('the items inside them'),
        findsOneWidget,
        reason: 'otherwise this reads as "there are no sets"',
      );
    });
  });

  group('refiling a set', () {
    testWidgets('carries the photo and the version, and says the group', (
      tester,
    ) async {
      final repository = await _pumpSets(tester);

      await _tapAction(tester, 'Regroup');
      expect(find.text('File "Bathroom Kit"'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('sets-regroup-field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ash Trays').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(InkWell, 'File set').first);
      await tester.pumpAndSettle();

      expect(repository.saved, hasLength(1));
      final save = repository.saved.single;
      expect(save.id, _definedSet.id);
      expect(save.groupIdSpecified, isTrue, reason: 'this write means to');
      expect(save.groupId, 1);
      expect(
        save.photoUrl,
        'https://example.test/kit.png',
        reason: 'the server writes photo_url on every update',
      );
      expect(
        save.expectedVersion,
        _definedSet.version,
        reason: 'or it would overwrite whoever else is in the set',
      );
      // A full replace: the lines have to travel even though only the group
      // was being changed.
      expect(save.lines, hasLength(2));
      expect(save.lines.first.quantity, 2);
    });

    testWidgets('a refused save is reported and not retried', (tester) async {
      final repository = await _pumpSets(tester);
      repository.refuseAsConflict = true;

      await _tapAction(tester, 'Regroup');
      await tester.tap(
        find.byKey(const ValueKey<String>('sets-regroup-field')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ash Trays').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(InkWell, 'File set').first);
      await tester.pumpAndSettle();

      expect(
        repository.saved,
        hasLength(1),
        reason: 'a conflict is answered by telling the user, never by writing '
            'again',
      );
      expect(find.textContaining('changed since you opened it'), findsOneWidget);
    });
  });

  group('deleting a set', () {
    testWidgets('says plainly that it cannot be undone', (tester) async {
      final repository = await _pumpSets(tester);

      await _tapAction(tester, 'Delete');

      // Unlike a group or an item, a deleted set does not land in the Action
      // Center — the row and its lines go for good.
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      expect(find.textContaining('Action Center'), findsOneWidget);
      expect(repository.deleted, isEmpty, reason: 'not until it is confirmed');

      await tester.tap(find.widgetWithText(FilledButton, 'Delete set'));
      await tester.pumpAndSettle();
      expect(repository.deleted, <int>[_definedSet.id]);
    });
  });
}

InventoryProvider _inventoryOf(WidgetTester tester) {
  return Provider.of<InventoryProvider>(
    tester.element(find.byType(SetsScreen)),
    listen: false,
  );
}
