import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/inventory/data/repositories/api_inventory_repository.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/domain/inventory_control_tower.dart';
import 'package:core_erp/features/inventory/domain/material_record.dart';
import 'package:core_erp/features/inventory/domain/variation_stock_record.dart';
import 'package:core_erp/features/inventory/domain/inventory_set_definition.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/inventory/presentation/widgets/inventory_set_editor_dialog.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The set editor is the only screen that files a set under a group, and it is
/// the one that has to get the tri-state right: it owns the whole form, so
/// every save it makes speaks about the group — including a save that clears
/// it. The path that must NOT speak about the group is the "add spawned items
/// to a set" one in the items master, which builds its own input.

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
  _CapturingInventoryRepository([this.serverCopy]);

  final List<SaveInventorySetInput> saved = <SaveInventorySetInput>[];

  /// The set as the server holds it. A save whose `expectedVersion` does not
  /// match it is refused, the way the real one refuses.
  InventorySetDefinition? serverCopy;

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
      throw UnimplementedError();

  @override
  Future<List<InventorySetDefinition>> getSets() async =>
      serverCopy == null
      ? const <InventorySetDefinition>[]
      : <InventorySetDefinition>[serverCopy!];

  @override
  Future<InventorySetDefinition> saveSet(SaveInventorySetInput input) async {
    saved.add(input);
    final current = serverCopy;
    if (current != null &&
        input.expectedVersion != null &&
        input.expectedVersion != current.version) {
      throw InventoryApiException(
        '"${current.name}" changed since you opened it. Reload it and make '
        "your change again — saving now would replace someone else's edit.",
        code: 'set_changed',
        statusCode: 409,
      );
    }
    return InventorySetDefinition(
      id: input.id ?? 1,
      name: input.name,
      totalItemCount: 1,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      lines: const <InventorySetLineDefinition>[],
      groupId: input.groupId,
      version: (current?.version ?? 0) + 1,
    );
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _filedSet = InventorySetDefinition(
  id: 7,
  name: 'Bathroom Kit',
  totalItemCount: 2,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  groupId: 2,
  groupName: 'Round',
  lines: const <InventorySetLineDefinition>[
    InventorySetLineDefinition(
      id: 1,
      itemId: 11,
      variationLeafNodeId: 21,
      quantity: 2,
      position: 0,
      itemName: 'Ash Tray',
      itemDisplayName: 'Ash Tray',
      variationPathLabel: 'Round · Brass',
      variationPathNodeIds: <int>[21],
    ),
  ],
);

/// The same set, as somebody else has since saved it.
final _newerCopy = InventorySetDefinition(
  id: _filedSet.id,
  name: "Someone Else's Kit",
  totalItemCount: 1,
  createdAt: _filedSet.createdAt,
  updatedAt: DateTime(2026, 2),
  groupId: 1,
  groupName: 'Ash Trays',
  version: 3,
  lines: const <InventorySetLineDefinition>[
    InventorySetLineDefinition(
      id: 2,
      itemId: 12,
      variationLeafNodeId: 22,
      quantity: 5,
      position: 0,
      itemName: 'Lid',
      itemDisplayName: 'Lid',
      variationPathLabel: 'Plain',
      variationPathNodeIds: <int>[22],
    ),
  ],
);

Future<_CapturingInventoryRepository> _pumpEditor(
  WidgetTester tester, {
  required InventorySetDefinition set,
  InventorySetDefinition? serverCopy,
}) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final inventoryRepository = _CapturingInventoryRepository(serverCopy ?? set);
  final groupsProvider = GroupsProvider(repository: _FakeGroupRepository());
  await groupsProvider.initialize();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<InventoryProvider>.value(
          value: InventoryProvider(repository: inventoryRepository),
        ),
        ChangeNotifierProvider<ItemsProvider>.value(
          value: ItemsProvider(repository: _FakeItemRepository()),
        ),
        ChangeNotifierProvider<GroupsProvider>.value(value: groupsProvider),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: InventorySetEditorDialog(setDefinition: set),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return inventoryRepository;
}

void main() {
  testWidgets('the editor shows the group the set is already filed under', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpEditor(tester, set: _filedSet);

    expect(find.text('Group'), findsOneWidget);
    expect(
      // The picker indents an option by its depth in the tree, so the label is
      // not a bare name.
      find.textContaining('Round'),
      findsWidgets,
      reason: 'the field is seeded with the group the set carries',
    );
  });

  testWidgets('saving keeps the group and says so explicitly', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repository = await _pumpEditor(tester, set: _filedSet);

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(repository.saved, hasLength(1));
    final input = repository.saved.single;
    expect(
      input.groupIdSpecified,
      isTrue,
      reason: 'the editor owns the whole form, so it always speaks about the group',
    );
    expect(input.groupId, 2);
  });

  testWidgets('a set with no group saves as ungrouped, not as untouched', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final unfiled = InventorySetDefinition(
      id: _filedSet.id,
      name: _filedSet.name,
      totalItemCount: _filedSet.totalItemCount,
      createdAt: _filedSet.createdAt,
      updatedAt: _filedSet.updatedAt,
      lines: _filedSet.lines,
    );
    final repository = await _pumpEditor(tester, set: unfiled);

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(repository.saved, hasLength(1));
    expect(repository.saved.single.groupIdSpecified, isTrue);
    expect(repository.saved.single.groupId, isNull);
  });

  // --- the set moved on while it was open -----------------------------------

  /// Types into the name field, which is what makes the form "touched" — after
  /// which a silent re-seed would be throwing away the user's work, so the
  /// editor asks instead.
  Future<void> typeSomething(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Bathroom Kit'),
      'My Kit',
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a refused save offers to reload and does not close', (
    tester,
  ) async {
    final repo = await _pumpEditor(tester, set: _filedSet);
    await typeSomething(tester);
    // Now somebody else saves it.
    repo.serverCopy = _newerCopy;

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(repo.saved, hasLength(1), reason: 'it tried once');
    expect(
      repo.saved.single.expectedVersion,
      0,
      reason: 'with the version it opened at',
    );
    expect(find.textContaining('changed while you had it open'), findsOneWidget);
    expect(
      find.textContaining('discards everything you have typed'),
      findsOneWidget,
    );
    // Still up: nothing was saved and nothing was lost.
    expect(find.byType(InventorySetEditorDialog), findsOneWidget);
  });

  testWidgets('keeping my edits leaves it open and still refusing', (
    tester,
  ) async {
    final repo = await _pumpEditor(tester, set: _filedSet);
    await typeSomething(tester);
    repo.serverCopy = _newerCopy;

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep my edits'));
    await tester.pumpAndSettle();

    // The typing is still there, and the token has not moved — so a second
    // attempt is refused again. No silent retry, no quiet re-versioning.
    expect(find.widgetWithText(TextFormField, 'My Kit'), findsOneWidget);
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(repo.saved, hasLength(2));
    expect(repo.saved.last.expectedVersion, 0);
    expect(find.byType(InventorySetEditorDialog), findsOneWidget);
  });

  testWidgets('discarding reloads the server copy and then saves', (
    tester,
  ) async {
    final repo = await _pumpEditor(tester, set: _filedSet);
    await typeSomething(tester);
    repo.serverCopy = _newerCopy;

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard and reload'));
    await tester.pumpAndSettle();

    // The form now shows what the server holds, name and all — the typing is
    // gone, which the prompt said it would be.
    expect(
      find.widgetWithText(TextFormField, "Someone Else's Kit"),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, 'My Kit'), findsNothing);

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(
      repo.saved.last.expectedVersion,
      _newerCopy.version,
      reason: 'the reloaded version is what the next save carries',
    );
  });

  testWidgets('a set that moved before anything was typed re-seeds silently', (
    tester,
  ) async {
    await _pumpEditor(tester, set: _filedSet, serverCopy: _newerCopy);

    // Nothing was typed, so there is nothing to ask about: the open-time
    // re-read just takes the newer copy.
    expect(find.textContaining('changed while you had it open'), findsNothing);
    expect(
      find.widgetWithText(TextFormField, "Someone Else's Kit"),
      findsOneWidget,
    );
  });
}
