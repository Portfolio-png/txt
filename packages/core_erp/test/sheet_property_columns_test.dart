import 'package:core_erp/core/network/sitting_scope.dart';
import 'package:core_erp/core/services/socket_service.dart';
import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/data/sheet_property_repository.dart';
import 'package:core_erp/features/items/domain/sheet_property.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/domain/item_inputs.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/items/presentation/providers/sheet_properties_provider.dart';
import 'package:core_erp/features/items/presentation/screens/item_master_sheet_screen.dart';
import 'package:core_erp/features/items/presentation/widgets/part_rows_form.dart';
import 'package:core_erp/sheet/sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // Whole-item saves and the editor read the part fresh from the server
  // (B42). Here the server is this fake's own list.
  @override
  Future<ItemDefinition?> getItemFresh(int id) async {
    for (final item in await getItems()) {
      if (item.id == id) return item;
    }
    return null;
  }
  _Items([List<ItemDefinition> items = const []]) : items = [...items];

  final List<ItemDefinition> items;

  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async => items;

  final List<UpdateItemInput> updated = [];
  final List<CreateItemInput> created = [];

  @override
  Future<ItemDefinition> createItem(CreateItemInput input) async {
    created.add(input);
    // As the server answers: the part as made, its properties with it.
    final made = _partFrom(900 + created.length, input);
    items.add(made);
    return made;
  }

  @override
  Future<ItemDefinition> updateItem(UpdateItemInput input) async {
    updated.add(input);
    return items.firstWhere((i) => i.id == input.id);
  }

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

/// The part a create makes: its name, group and properties as sent.
ItemDefinition _partFrom(int id, CreateItemInput input) {
  var next = id * 100;
  ItemVariationNodeDefinition node(ItemVariationNodeInput n, int? parent) {
    final me = next++;
    return ItemVariationNodeDefinition(
      id: me,
      itemId: id,
      parentNodeId: parent,
      kind: n.kind,
      name: n.name,
      displayName: n.name,
      position: 0,
      children: [for (final c in n.children) node(c, me)],
      isArchived: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  }

  return ItemDefinition(
    id: id,
    name: input.name,
    alias: '',
    displayName: input.name,
    quantity: 0,
    groupId: input.groupId,
    unitId: input.unitId,
    isArchived: false,
    usageCount: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    variationTree: [for (final n in input.variationTree) node(n, null)],
  );
}

/// A saved part whose Plating is [plating] — or whose [property] is.
ItemDefinition _partPlated(int id, String plating, {String property = 'Plating'}) {
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
      node(id * 10, ItemVariationNodeKind.property, property, children: [
        node(id * 10 + 1, ItemVariationNodeKind.value, plating, parent: id * 10),
      ]),
    ],
  );
}

/// The first part line's box for the column named [label] — by name, not by
/// id: Grade and Hardness are on every sheet now, so a column added here is
/// no longer the first after the fixed ones.
Finder _cellOf(WidgetTester tester, String label) {
  final sheet = tester.widget<PartRowsForm>(find.byType(PartRowsForm)).sheet;
  final column = sheet.sheetDef.columns.firstWhere((c) => c.label == label);
  return find.byKey(ValueKey('cell_item_0_${column.id}'));
}

/// Grade is on every sheet (owner, 2026-11-27): a test needing its options
/// gives them to the one there, rather than making a second.
Future<void> _gradeOptions(List<String> options) async {
  final repo = ApiSheetPropertyRepository(useMockResponses: true);
  final grade = (await repo.list()).firstWhere((p) => p.key == 'grade');
  await repo.update(grade.id, options: options);
}

Future<SheetPropertiesProvider> _pump(
  WidgetTester tester, {
  SheetPropertyRepository? repository,
  List<ItemDefinition> parts = const [],
  List<ItemDefinition> open = const [],
  _Items? itemRepo,
}) async {
  final groups = GroupsProvider(repository: _Groups());
  await groups.initialize();
  final props = SheetPropertiesProvider(
    repository: repository ?? ApiSheetPropertyRepository(useMockResponses: true),
  );
  addTearDown(props.dispose);
  final items = ItemsProvider(repository: itemRepo ?? _Items(parts));
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
      child: MaterialApp(home: ItemMasterSheetScreen(initialItems: open)),
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

  testWidgets('Grade and Hardness are on every sheet, and cannot be deleted',
      (tester) async {
    // Owner, 2026-11-27: "give hardness and grade in item master". The
    // server makes both at boot and after a wipe; the demo store mirrors it.
    final props = await _pump(tester);
    expect(props.byKey('grade')?.isDefault, isTrue);
    expect(props.byKey('hardness')?.isDefault, isTrue);
    expect(find.text('Grade'), findsWidgets);
    expect(find.text('Hardness'), findsWidgets);

    // Their lists are edited like any column's; the columns stay.
    final why = 'Grade is on every part sheet — it cannot be deleted';
    expect(find.byTooltip(why), findsWidgets);
    expect(find.byTooltip('Edit Grade'), findsWidgets);
    final delete = tester.widget<IconButton>(
      find.descendant(of: find.byTooltip(why).first, matching: find.byType(IconButton)),
    );
    expect(delete.onPressed, isNull, reason: 'drawn, disabled, saying why');
  });

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

    await tester.tap(_cellOf(tester, 'Plating'));
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

    await tester.tap(_cellOf(tester, 'Plating'));
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

    await tester.tap(_cellOf(tester, 'Plating'));
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

  testWidgets('a property is a heading with Edit and Delete; Edit asks first',
      (tester) async {
    await ApiSheetPropertyRepository(useMockResponses: true)
        .create(name: 'Temper', kind: 'list');
    await _pump(tester);

    // Built into every part sheet: both drawn, neither pressable, and why.
    final alloyEdit = find.byTooltip('Alloy is built into every part sheet');
    expect(alloyEdit, findsWidgets);

    await tester.tap(find.byTooltip('Edit Temper').first);
    await tester.pumpAndSettle();
    expect(find.text('Edit Temper?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Options for Temper'), findsNothing,
        reason: 'Cancel changes nothing');

    await tester.tap(find.byTooltip('Edit Temper').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Edit').last);
    await tester.pumpAndSettle();
    expect(find.text('Options for Temper'), findsOneWidget);
  });

  testWidgets('removing a saved column asks first, and Cancel keeps it',
      (tester) async {
    await ApiSheetPropertyRepository(useMockResponses: true)
        .create(name: 'Temper', kind: 'list');
    final props = await _pump(tester);

    Future<void> openRemove() async {
      // A property's Delete sits beside its heading, over its box.
      await tester.tap(find.byTooltip('Delete Temper').first);
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

  // The report (2026-11-24): a part saved, opened again with Edit, Hardness
  // added with "+" — and its Grade was gone, from the sheet and from the save.
  testWidgets('adding a property to a saved part keeps its other properties', (tester) async {
    await _gradeOptions(const ['1st', '2nd']);
    final part = _partPlated(500, '2nd', property: 'Grade');
    final repo = _Items([part]);
    await _pump(tester, parts: [part], open: [part], itemRepo: repo);
    expect(find.text('2nd'), findsWidgets, reason: 'Grade as saved');

    await tester.tap(find.byKey(const ValueKey('row_edit_0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mini_table_add_properties_item')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('property_name')), 'Hardness');
    await tester.tap(find.text('Free text'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('property_submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Hardness'), findsWidgets, reason: 'the new column');
    expect(find.text('Grade'), findsWidgets, reason: 'Grade stays');
    expect(find.text('2nd'), findsWidgets, reason: 'and so does its value');

    // A hardness typed for the part.
    final sheet = tester.widget<PartRowsForm>(find.byType(PartRowsForm)).sheet;
    final hardness = sheet.sheetDef.columnBoundTo(SheetBindsTo.variation('Hardness'))!;
    sheet.updateValue(
      hardness.id,
      CellValue(columnId: hardness.id, optionLabel: 'Hard', isNew: true),
      row: 0,
    );
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('row_save_0')));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();
    if (find.byKey(const Key('identity_change_this_part')).evaluate().isNotEmpty) {
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('identity_change_this_part')));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pump();
    }
    final sent = repo.updated.lastOrNull;
    expect(sent, isNotNull, reason: 'the edit was saved');
    final names = sent!.variationTree.map((n) => n.name).toList();
    expect(names, contains('Grade'), reason: 'the save keeps Grade');
  });

  testWidgets('"Make a new part" after adding a property keeps the other properties', (tester) async {
    await _gradeOptions(const ['1st', '2nd']);
    final part = _partPlated(500, '2nd', property: 'Grade');
    final repo = _Items([part]);
    await _pump(tester, parts: [part], open: [part], itemRepo: repo);
    await tester.tap(find.byKey(const ValueKey('row_edit_0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mini_table_add_properties_item')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('property_name')), 'Hardness');
    await tester.tap(find.text('Free text'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('property_submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final sheet = tester.widget<PartRowsForm>(find.byType(PartRowsForm)).sheet;
    final hardness = sheet.sheetDef.columnBoundTo(SheetBindsTo.variation('Hardness'))!;
    sheet.updateValue(hardness.id, CellValue(columnId: hardness.id, optionLabel: 'Hard', isNew: true), row: 0);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('row_save_0')));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('identity_make_new_part')));
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });
    await tester.pump();
    expect(repo.created, hasLength(1), reason: 'a new part');
    final names = repo.created.single.variationTree.map((n) => n.name).toList();
    expect(names, containsAll(['Grade', 'Hardness']), reason: 'the new part keeps Grade');
  });

  testWidgets('a part made with Ctrl+Enter, opened again, keeps Grade when Hardness is added', (tester) async {
    await _gradeOptions(const ['1st', '2nd']);
    final repo = _Items();
    await _pump(tester, itemRepo: repo);
    final sheet = tester.widget<PartRowsForm>(find.byType(PartRowsForm)).sheet;
    final def = sheet.sheetDef;
    final group = def.groupColumn!;
    final trunk = sheet.options.firstWhere((o) => o.columnId == group.id);
    sheet.updateValue(group.id, CellValue(columnId: group.id, optionId: trunk.id, optionLabel: trunk.label));
    final name = def.itemColumn!;
    sheet.updateValue(name.id, CellValue(columnId: name.id, optionLabel: 'Ctrl Patti', isNew: true));
    final grade = def.columnBoundTo(SheetBindsTo.variation('Grade'))!;
    sheet.updateValue(grade.id, CellValue(columnId: grade.id, optionLabel: '2nd'));
    await tester.pump();

    // Ctrl+Enter: the part line's own "save and add another".
    final step = tester
        .widgetList<SheetStep>(find.byType(SheetStep, skipOffstage: false))
        .firstWhere((w) => w.id == PartRowsForm.stepId(sheet.draftAt(0).rowKey));
    await tester.runAsync(() async {
      await step.actions.saveAndAddAnother!();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.created, hasLength(1));
    if (find.byType(Dialog).evaluate().isNotEmpty) {
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
    }

    // Back to it, Edit, Hardness added and filled, saved.
    sheet.selectRow(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('row_edit_0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mini_table_add_properties_item')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('property_name')), 'Hardness');
    await tester.tap(find.text('Free text'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('property_submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final hardness = sheet.sheetDef.columnBoundTo(SheetBindsTo.variation('Hardness'))!;
    sheet.updateValue(hardness.id, CellValue(columnId: hardness.id, optionLabel: 'Hard', isNew: true), row: 0);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('row_save_0')));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();
    if (find.byKey(const Key('identity_change_this_part')).evaluate().isNotEmpty) {
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('identity_change_this_part')));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pump();
    }
    expect(repo.updated.last.variationTree.map((n) => n.name), containsAll(['Grade', 'Hardness']));
  });
}
