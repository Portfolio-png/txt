import 'package:core_erp/core/network/sitting_scope.dart';
import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/data/sheet_property_repository.dart';
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
  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<SheetPropertiesProvider> _pump(WidgetTester tester) async {
  final groups = GroupsProvider(repository: _Groups());
  await groups.initialize();
  final props = SheetPropertiesProvider(
    repository: ApiSheetPropertyRepository(useMockResponses: true),
  );
  addTearDown(props.dispose);

  tester.view.physicalSize = const Size(1700, 1100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ItemsProvider>.value(
          value: ItemsProvider(repository: _Items()),
        ),
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
