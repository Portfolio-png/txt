import 'package:core_erp/core/network/sitting_scope.dart';
import 'package:core_erp/core/services/socket_service.dart';
import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/data/sheet_property_repository.dart';
import 'package:core_erp/features/items/domain/sheet_property.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/items/presentation/providers/sheet_properties_provider.dart';
import 'package:core_erp/features/items/presentation/screens/item_master_sheet_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The item sheet's own property columns: added with "+", each with a list of
// options, kept for everyone until removed. They lived only in the sheet's
// memory before — Plating was gone the next time the sheet opened.

class _Groups implements GroupRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async => [
        GroupDefinition(
          id: 10,
          name: 'Switch Action',
          groupStructure: 'hierarchical',
          parentGroupId: null,
          unitId: 7,
          isArchived: false,
          usageCount: 0,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Items implements ItemRepository {
  _Items([this.items = const []]);

  final List<ItemDefinition> items;

  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async => items;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The demo store, but its first [failures] lists throw — a window whose
/// first read of the columns did not get through (a 401 before sign-in
/// landed, a dropped request).
class _FlakyRepository extends ApiSheetPropertyRepository {
  _FlakyRepository({this.failures = 1}) : super(useMockResponses: true);

  int failures;

  @override
  Future<List<SheetProperty>> list() async {
    if (failures > 0) {
      failures -= 1;
      throw const SheetPropertyException('Could not load the sheet columns.');
    }
    return super.list();
  }
}

/// A saved part whose Plating is [plating].
ItemDefinition _partPlated(int id, String plating) {
  ItemVariationNodeDefinition node(
    int nodeId,
    ItemVariationNodeKind kind,
    String name, {
    int? parent,
    List<ItemVariationNodeDefinition> children = const [],
  }) =>
      ItemVariationNodeDefinition(
        id: nodeId,
        itemId: id,
        parentNodeId: parent,
        kind: kind,
        name: name,
        displayName: name,
        position: 0,
        children: children,
        isArchived: false,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
  return ItemDefinition(
    id: id,
    name: 'Bracket $id',
    alias: '',
    displayName: 'Bracket $id',
    quantity: 0,
    groupId: 10,
    unitId: 7,
    isArchived: false,
    usageCount: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    variationTree: [
      node(id * 10, ItemVariationNodeKind.property, 'Plating', children: [
        node(id * 10 + 1, ItemVariationNodeKind.value, plating, parent: id * 10),
      ]),
    ],
  );
}

Future<SheetPropertiesProvider> _pump(
  WidgetTester tester, {
  SheetPropertyRepository? repository,
  List<ItemDefinition> parts = const [],
}) async {
  final groups = GroupsProvider(repository: _Groups());
  await groups.initialize();
  final props = SheetPropertiesProvider(
    repository: repository ?? ApiSheetPropertyRepository(useMockResponses: true),
  );
  addTearDown(props.dispose);
  final items = ItemsProvider(repository: _Items(parts));
  if (parts.isNotEmpty) await items.initialize();

  tester.view.physicalSize = const Size(1700, 1100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ItemsProvider>.value(value: items),
        ChangeNotifierProvider<GroupsProvider>.value(value: groups),
        ChangeNotifierProvider<SheetPropertiesProvider>.value(value: props),
      ],
      child: const MaterialApp(home: ItemMasterSheetScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  return props;
}

void main() {
  setUp(ApiSheetPropertyRepository.debugResetMockStore);
  tearDown(SittingScope.reset);

  testWidgets('a column saved earlier is on the sheet when it opens',
      (tester) async {
    await ApiSheetPropertyRepository(useMockResponses: true)
        .create(name: 'Plating', kind: 'text', options: const ['Nickel', 'Chrome']);

    await _pump(tester);
    expect(find.text('Plating'), findsWidgets);
  });

  testWidgets('adding one saves it, with its options, for everyone',
      (tester) async {
    final props = await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('mini_table_add_properties_item')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('property_name')), 'Plating');
    await tester.tap(find.text('Free text'));
    await tester.pump();
    final option = find.byKey(const ValueKey('property_option'));
    await tester.enterText(option, 'Nickel');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    // Pasted with commas, and a duplicate ignoring case.
    await tester.enterText(option, 'Chrome, nickel');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('property_submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final saved = props.byKey('plating');
    expect(saved, isNotNull);
    expect(saved!.kind, 'text');
    expect(saved.options, ['Nickel', 'Chrome']);
    expect(find.text('Plating'), findsWidgets);
  });

  testWidgets('a column added after the first load failed is still drawn',
      (tester) async {
    // It used to be saved for everyone and drawn nowhere: the sheet skipped
    // every stored column until a load had succeeded, and said nothing.
    final props = await _pump(tester, repository: _FlakyRepository());
    expect(props.isLoaded, isFalse);
    expect(find.textContaining('did not load'), findsOneWidget,
        reason: 'a failed load is said, not swallowed');

    await tester.tap(find.byKey(const ValueKey('mini_table_add_properties_item')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('property_name')), 'Coating');
    await tester.pump(); // Add is enabled once a name is in
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('property_submit')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(props.byKey('coating'), isNotNull);
    expect(find.text('Coating'), findsWidgets);
    expect(props.isLoaded, isTrue, reason: 'the add caught the window up');
  });

  testWidgets('a change elsewhere retries a failed first load', (tester) async {
    await ApiSheetPropertyRepository(useMockResponses: true)
        .create(name: 'Plating', kind: 'list');
    final props = await _pump(tester, repository: _FlakyRepository());
    expect(find.text('Plating'), findsNothing);

    await tester.runAsync(() async {
      SocketService.instance.processEventForTest(
        'event: table-change\n'
        'data: {"table_name":"item_sheet_properties","record_id":1,"event_type":"UPDATE"}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(props.isLoaded, isTrue);
    expect(find.text('Plating'), findsWidgets);
  });

  testWidgets('an unloaded list never takes a column off the sheet',
      (tester) async {
    // Every read fails: the column added here is the only one this window
    // knows, and a failed refresh must not read as "it was removed".
    final props = await _pump(tester, repository: _FlakyRepository(failures: 9));

    await tester.tap(find.byKey(const ValueKey('mini_table_add_properties_item')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('property_name')), 'Temper');
    await tester.pump(); // Add is enabled once a name is in
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('property_submit')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await props.refresh();
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(props.isLoaded, isFalse);
    expect(props.byKey('temper'), isNotNull);
    expect(find.text('Temper'), findsWidgets);
  });

  testWidgets('a column removed in another window leaves this one',
      (tester) async {
    await ApiSheetPropertyRepository(useMockResponses: true)
        .create(name: 'Temper', kind: 'list');
    final props = await _pump(tester);
    expect(find.text('Temper'), findsWidgets);

    await tester.runAsync(() async {
      await ApiSheetPropertyRepository(useMockResponses: true)
          .remove(props.byKey('temper')!.id);
      await props.refresh();
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Temper'), findsNothing);
  });

  testWidgets('a value typed into the column joins its list for everyone',
      (tester) async {
    await ApiSheetPropertyRepository(useMockResponses: true)
        .create(name: 'Plating', kind: 'text', options: const ['Nickel']);
    final props = await _pump(tester);

    // Plating is the first column after the ten fixed ones.
    await tester.tap(find.byKey(const ValueKey('cell_item_0_11')));
    await tester.pumpAndSettle();
    // The saved option is offered.
    expect(find.text('Nickel'), findsWidgets);
    await tester.enterText(find.byType(TextField).last, 'Gold');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(props.byKey('plating')!.options, ['Nickel', 'Gold']);
  });

  testWidgets('a value in the list is deleted from its dropdown, after asking',
      (tester) async {
    await ApiSheetPropertyRepository(useMockResponses: true)
        .create(name: 'Plating', kind: 'text', options: const ['Nickel', 'Gold']);
    final props = await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('cell_item_0_11')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sheet_option_delete_Gold')));
    await tester.pumpAndSettle();
    expect(find.textContaining('leaves the Plating list'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(props.byKey('plating')!.options, ['Nickel']);
    expect(find.text('Gold'), findsNothing, reason: 'gone from the open list');
    expect(find.text('Nickel'), findsWidgets);
  });

  testWidgets('a value a saved part carries cannot be deleted, and says so',
      (tester) async {
    await ApiSheetPropertyRepository(useMockResponses: true)
        .create(name: 'Plating', kind: 'text', options: const ['Nickel', 'Gold']);
    final props = await _pump(
      tester,
      parts: [_partPlated(1, 'Nickel'), _partPlated(2, 'nickel')],
    );

    await tester.tap(find.byKey(const ValueKey('cell_item_0_11')));
    await tester.pumpAndSettle();
    final held = tester.widget<IconButton>(
      find.byKey(const ValueKey('sheet_option_delete_Nickel')),
    );
    expect(held.onPressed, isNull, reason: 'drawn disabled, not hidden');
    expect(held.tooltip, 'On 2 saved parts — change them first');
    final free = tester.widget<IconButton>(
      find.byKey(const ValueKey('sheet_option_delete_Gold')),
    );
    expect(free.onPressed, isNotNull);
    expect(props.byKey('plating')!.options, ['Nickel', 'Gold']);
  });

  testWidgets('removing a saved column asks first, and Cancel keeps it',
      (tester) async {
    await ApiSheetPropertyRepository(useMockResponses: true)
        .create(name: 'Temper', kind: 'list');
    final props = await _pump(tester);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    Future<void> openRemove() async {
      // The menu shows on hover.
      await mouse.moveTo(tester.getCenter(find.text('Temper').first));
      await tester.pumpAndSettle();
      final menu = find.descendant(
        of: find.ancestor(
          of: find.text('Temper').first,
          matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == 'HeaderCell'),
        ),
        matching: find.byIcon(Icons.more_vert_rounded),
      );
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove column'));
      await tester.pumpAndSettle();
    }

    await openRemove();
    expect(find.textContaining('goes for everyone'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(props.byKey('temper'), isNotNull);
    expect(find.text('Temper'), findsWidgets);

    await openRemove();
    // The dialog's button — the sheet has a row "Remove" of its own.
    await tester.tap(find.text('Remove').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(props.byKey('temper'), isNull);
    expect(find.text('Temper'), findsNothing);
  });
}
