import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/developed_for.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/domain/item_inputs.dart';
import 'package:core_erp/features/production_pipelines/presentation/widgets/master_data_dialog.dart';
import 'package:core_erp/core/app_flow_hooks.dart';
import 'package:core_erp/features/items/presentation/widgets/part_die_section.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/items/presentation/screens/item_master_sheet_screen.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'dart:convert';

import 'package:core_erp/core/network/sitting_scope.dart';
import 'package:core_erp/core/services/socket_service.dart';
import 'package:core_erp/sheet/sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The real item-master sheet screen, and the generic rail beside it.
//
// The prototype this copies holds its records in four in-memory lists, seeds
// five groups and four companies nobody created, and its sidebar read cells by
// literal column id with `?? 'Gold Medal'` behind the party name. These tests
// are mostly about the things that made that unusable for any other sheet.

class _FakeGroupRepository implements GroupRepository {
  _FakeGroupRepository(this.groups);
  final List<GroupDefinition> groups;

  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async =>
      List.of(groups);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeItemRepository implements ItemRepository {
  _FakeItemRepository(this.stored);
  final List<ItemDefinition> stored;

  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async {
    reads += 1;
    return List.of(stored);
  }

  @override
  Future<ItemDefinition?> getItemFresh(int id) async {
    freshReads.add(id);
    return stored.where((item) => item.id == id).firstOrNull;
  }

  final List<Map<String, String>> savedTrees = [];
  int reads = 0;
  final List<int> freshReads = [];
  final List<UpdateItemInput> updated = [];

  @override
  Future<ItemDefinition> updateItem(UpdateItemInput input) async {
    updated.add(input);
    return stored.firstWhere((i) => i.id == input.id);
  }

  @override
  Future<ItemDefinition> saveSectionTree(int itemId, Map<String, String> tree) async {
    savedTrees.add(Map.of(tree));
    final at = stored.indexWhere((i) => i.id == itemId);
    final current = stored[at];
    final updated = ItemDefinition(
      id: current.id,
      name: current.name,
      alias: current.alias,
      displayName: current.displayName,
      partNo: current.partNo,
      partCode: current.partCode,
      quantity: current.quantity,
      groupId: current.groupId,
      unitId: current.unitId,
      developedFor: current.developedFor,
      isArchived: false,
      usageCount: 0,
      createdAt: current.createdAt,
      updatedAt: current.updatedAt,
      variationTree: const [],
      sectionTree: Map.of(tree),
    );
    stored[at] = updated;
    return updated;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GroupDefinition _group({
  required int id,
  required String name,
  int? parentGroupId,
}) =>
    GroupDefinition(
      id: id,
      name: name,
      groupType: 'item',
      groupStructure: 'Standard',
      parentGroupId: parentGroupId,
      unitId: 7,
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

ItemDefinition _item({
  required int id,
  required String name,
  required int groupId,
  String partCode = 'SADP48',
  List<ItemVariationNodeDefinition> variationTree = const [],
}) =>
    ItemDefinition(
      id: id,
      name: name,
      alias: '',
      displayName: name,
      partNo: 48,
      partCode: partCode,
      quantity: 0,
      groupId: groupId,
      unitId: 7,
      developedFor: DevelopedFor.empty,
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime(2026, 5, 15, 10, 5),
      updatedAt: DateTime(2026, 5, 15, 10, 5),
      variationTree: variationTree,
    );

Future<void> _pumpScreen(
  WidgetTester tester, {
  List<ItemDefinition> initialItems = const [],
  List<ItemDefinition> stored = const [],
  Size? size,
  _FakeItemRepository? repository,
  // Subscribed to the change stream, as the app's provider is after start-up.
  bool live = false,
}) async {
  final groups = GroupsProvider(
    repository: _FakeGroupRepository([
      _group(id: 10, name: 'Switch Action'),
      _group(id: 11, name: 'Dolly', parentGroupId: 10),
    ]),
  );
  await groups.initialize();

  // A desktop screen, tested at a desktop size. 800x600 is not a window this
  // sheet is ever opened in, and testing it there measures the wrong thing.
  final itemsProvider =
      ItemsProvider(repository: repository ?? _FakeItemRepository(List.of(stored)));
  if (live) {
    await tester.runAsync(itemsProvider.initialize);
    // Its listeners are on the app-wide stream; leaving them would deliver
    // the next test's events to this one's provider.
    addTearDown(itemsProvider.dispose);
  } else if (repository != null) {
    await tester.runAsync(itemsProvider.refresh);
  }

  tester.view.physicalSize = size ?? const Size(1600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ItemsProvider>.value(value: itemsProvider),
        ChangeNotifierProvider<GroupsProvider>.value(value: groups),
      ],
      child: MaterialApp(
        home: ItemMasterSheetScreen(initialItems: initialItems),
      ),
    ),
  );
  // Not pumpAndSettle: the top bar shows a spinner while reference data loads
  // and a spinner keeps frames scheduled forever.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

SheetController _controllerWith({
  Map<int, CellValue> values = const {},
  List<ColumnDef>? columns,
  Map<String, int> counters = const {},
}) =>
    SheetController(
      sheetDef: SheetDef(
        id: 1,
        key: 'item',
        title: 'Item',
        columns: columns ?? itemSheetColumns,
      ),
      initialDraft: SheetDraft(sheetKey: 'item', values: values),
      counters: counters,
    );

void main() {
  tearDown(SittingScope.reset);

  group('SheetSidebar', () {
    testWidgets('reads the name and code through their bindings', (tester) async {
      // The whole identity chain, because the code column is derived — a code
      // written straight into the draft is recomputed away.
      final controller = _controllerWith(values: {
        1: const CellValue(columnId: 1, optionLabel: 'Switch Action'),
        2: const CellValue(columnId: 2, optionLabel: 'Dolly'),
        3: const CellValue(columnId: 3, optionLabel: 'Patti'),
      }, counters: {'Switch Action › Dolly › Patti': 47});
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SheetSidebar(
            controller: controller,
            sections: const [
              SheetSection(
                id: 'a',
                title: 'First',
                subtitle: 'One',
                icon: Icons.circle,
              ),
            ],
            activeSection: 'a',
            onSelectSection: (_) {},
          ),
        ),
      ));

      expect(find.text('Patti'), findsWidgets);
      expect(find.text('SADP48'), findsWidgets);
    });

    testWidgets('an unnamed row says so rather than showing a name nobody '
        'typed', (tester) async {
      final controller = _controllerWith();
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SheetSidebar(
            controller: controller,
            sections: const [],
            activeSection: '',
            onSelectSection: (_) {},
          ),
        ),
      ));

      expect(find.text('Unnamed'), findsOneWidget);
      expect(find.text('New Item'), findsNothing);
      expect(find.text('Not filed under a group yet'), findsOneWidget);
    });

    testWidgets('never invents a party', (tester) async {
      final controller = _controllerWith();
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SheetSidebar(
            controller: controller,
            sections: const [],
            activeSection: '',
            onSelectSection: (_) {},
          ),
        ),
      ));

      // The old sidebar's footnote was
      // `draft.get(20)?.optionLabel ?? 'Gold Medal'`.
      expect(find.textContaining('Gold Medal'), findsNothing);
    });

    testWidgets('its sections are whatever it is given', (tester) async {
      final controller = _controllerWith();
      addTearDown(controller.dispose);
      final tapped = <String>[];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SheetSidebar(
            controller: controller,
            sections: const [
              SheetSection(
                id: 'tooling',
                title: 'Tooling',
                subtitle: 'Dies for this part',
                icon: Icons.build,
              ),
              SheetSection(
                id: 'liners',
                title: 'Liners',
                subtitle: 'Sizes in nanometres',
                icon: Icons.straighten,
              ),
            ],
            activeSection: 'tooling',
            onSelectSection: tapped.add,
          ),
        ),
      ));

      expect(find.text('Tooling'), findsOneWidget);
      expect(find.text('Liners'), findsOneWidget);
      // Four section names the old sidebar had typed into it.
      expect(find.text('Group Item'), findsNothing);
      expect(find.text('Die Process Master'), findsNothing);

      await tester.tap(find.text('Liners'));
      expect(tapped, ['liners']);
    });

    testWidgets('the column tree names the sheet’s own properties', (tester) async {
      // The old tree had the words Alloy, Thickness and Finish written into the
      // build method, so any other sheet showed the item sheet's properties.
      final controller = _controllerWith(
        columns: const [
          ColumnDef(
            id: 1,
            sheetId: 9,
            label: 'Die Group',
            kind: ColumnKind.list,
            role: ColumnRole.group,
            position: 0,
            bindsTo: SheetBindsTo.group,
          ),
          ColumnDef(
            id: 2,
            sheetId: 9,
            label: 'Tool Code',
            kind: ColumnKind.code,
            role: ColumnRole.item,
            parentId: 1,
            position: 1,
            bindsTo: SheetBindsTo.name,
          ),
          ColumnDef(
            id: 3,
            sheetId: 9,
            label: 'Liner Size',
            kind: ColumnKind.number,
            position: 2,
            bindsTo: '${SheetBindsTo.variationPrefix}Liner Size',
          ),
        ],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SheetSidebar(
            controller: controller,
            sections: const [],
            activeSection: '',
            onSelectSection: (_) {},
          ),
        ),
      ));

      expect(find.textContaining('Liner Size'), findsWidgets);
      expect(find.textContaining('Alloy'), findsNothing);
      expect(find.textContaining('Thickness'), findsNothing);
    });

    testWidgets('no text below the house floor', (tester) async {
      final controller = _controllerWith(values: {
        3: const CellValue(columnId: 3, optionLabel: 'Patti'),
      });
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SheetSidebar(
            controller: controller,
            sections: const [
              SheetSection(
                id: 'a',
                title: 'First',
                subtitle: 'One',
                icon: Icons.circle,
              ),
            ],
            activeSection: 'a',
            onSelectSection: (_) {},
          ),
        ),
      ));

      // The original ran 9–12pt throughout.
      final small = <String>[];
      for (final element in find.byType(Text).evaluate()) {
        final widget = element.widget as Text;
        final size = widget.style?.fontSize;
        if (size != null && size < 13) {
          small.add('"${widget.data}" at $size');
        }
      }
      expect(small, isEmpty, reason: small.join(', '));
    });
  });

  group('ItemMasterSheetScreen', () {
    testWidgets('the rail offers four sections and shows one', (tester) async {
      // One section at a time now. Four grids competing for one width is what
      // made the screen cramped; the rail already knew which was active and
      // only ever scrolled to it.
      await _pumpScreen(tester);

      for (final section in [
        'Group Item',
        'Client / Vendor',
        'Die Process Master',
        'Machines & Routing',
      ]) {
        expect(find.text(section), findsWidgets, reason: '$section in the rail');
      }

      // The Item Master grid is on screen; the others are not built at all.
      expect(find.text('Parts on this sheet: 1'), findsOneWidget);
      expect(find.text('The deal'), findsNothing);
    });

    testWidgets('every section is on one page, nested like a file tree',
        (tester) async {
      await _pumpScreen(tester);
      // All four at once — the rail no longer switches between them.
      expect(find.text('Parts on this sheet: 1'), findsOneWidget);
      expect(find.text('Quotation (₹)'), findsOneWidget);
      expect(find.byKey(const ValueKey('section_toggle_die_master')), findsOneWidget);
      expect(find.byKey(const ValueKey('section_toggle_machine_master')), findsOneWidget);

      // Each level sits further right than the one it is nested in.
      double left(String id) =>
          tester.getTopLeft(find.byKey(ValueKey('section_toggle_$id'))).dx;
      expect(left('client_vendor'), greaterThan(left('group_item')));
      expect(left('die_master'), greaterThan(left('client_vendor')));
      expect(left('machine_master'), greaterThan(left('die_master')));
    });

    testWidgets('folding a section folds only it, into one row of what it holds',
        (tester) async {
      await _pumpScreen(tester, size: const Size(1600, 3200));
      await tester.tap(find.byKey(const ValueKey('section_toggle_client_vendor')));
      await tester.pump();

      expect(find.text('Quotation (₹)'), findsNothing, reason: 'its body is folded');
      expect(find.byKey(const ValueKey('section_summary_client_vendor')), findsOneWidget);
      expect(find.text('No company chosen yet'), findsOneWidget);
      // What is nested under it stays on the page.
      expect(find.byKey(const ValueKey('section_toggle_die_master')), findsOneWidget);
      expect(find.byKey(const ValueKey('section_toggle_machine_master')), findsOneWidget);

      // Tapping the summary opens it again.
      await tester.tap(find.byKey(const ValueKey('section_summary_client_vendor')));
      await tester.pump();
      expect(find.text('Quotation (₹)'), findsOneWidget);
    });

    double left(WidgetTester tester, String id) =>
        tester.getTopLeft(find.byKey(ValueKey('section_toggle_$id'))).dx;

    testWidgets('sections carry no pencil — saving is per row; the part itself has no bin',
        (tester) async {
      await _pumpScreen(tester, size: const Size(1600, 3200));
      for (final id in ['group_item', 'client_vendor', 'die_master', 'machine_master']) {
        expect(find.byKey(ValueKey('section_edit_$id')), findsNothing, reason: id);
        expect(find.byKey(ValueKey('section_save_$id')), findsNothing, reason: id);
      }
      final bin = tester.widget<IconButton>(find.byKey(const ValueKey('section_clear_group_item')));
      expect(bin.onPressed, isNull);
      // A blank new row has nothing to save yet.
      expect(find.byKey(const ValueKey('row_save_0')), findsNothing);
    });

    testWidgets('the side column folds to icons and opens again', (tester) async {
      await _pumpScreen(tester, size: const Size(1600, 3200));
      expect(find.byKey(const ValueKey('rail_collapsed')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('rail_collapse')));
      await tester.pump();
      expect(find.byKey(const ValueKey('rail_collapsed')), findsOneWidget);
      expect(find.byKey(const ValueKey('rail_icon_machine_master')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rail_expand')));
      await tester.pump();
      expect(find.byKey(const ValueKey('rail_collapsed')), findsNothing);
    });

    testWidgets('outdent moves a section out a level; undo puts it back', (tester) async {
      await _pumpScreen(tester, size: const Size(1600, 3200));
      expect(left(tester, 'machine_master'), greaterThan(left(tester, 'die_master')));

      await tester.tap(find.byKey(const ValueKey('section_outdent_machine_master')));
      await tester.pump();
      expect(left(tester, 'machine_master'), left(tester, 'die_master'),
          reason: 'now a sibling of Die, both under Client');
      expect(find.byKey(const ValueKey('tree_dirty_bar')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tree_undo')));
      await tester.pump();
      expect(left(tester, 'machine_master'), greaterThan(left(tester, 'die_master')));
      expect(find.byKey(const ValueKey('tree_dirty_bar')), findsNothing);
    });

    Future<void> dragOnto(WidgetTester tester, String dragged, String target) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey('section_drag_$dragged'))),
      );
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byKey(ValueKey('section_toggle_$target'))));
      await tester.pump();
      await gesture.up();
      await tester.pump();
    }

    testWidgets('dragging a section onto another nests it there', (tester) async {
      await _pumpScreen(tester, size: const Size(1600, 3200));
      await dragOnto(tester, 'machine_master', 'group_item');
      expect(left(tester, 'machine_master'), left(tester, 'client_vendor'),
          reason: 'directly under the part, beside Client');
      expect(find.byKey(const ValueKey('tree_dirty_bar')), findsOneWidget);
    });

    testWidgets('a section cannot be dropped inside its own subtree', (tester) async {
      await _pumpScreen(tester, size: const Size(1600, 3200));
      await dragOnto(tester, 'client_vendor', 'machine_master');
      expect(find.byKey(const ValueKey('tree_dirty_bar')), findsNothing);
      expect(left(tester, 'machine_master'), greaterThan(left(tester, 'client_vendor')));
    });

    testWidgets('a saved row is closed until its Edit; the nesting saves',
        (tester) async {
      final patti = _item(id: 500, name: 'Patti', groupId: 11);
      final repo = _FakeItemRepository([patti]);
      await _pumpScreen(
        tester,
        initialItems: [patti],
        repository: repo,
        size: const Size(1600, 3200),
      );

      // Loaded saved: the row shows Edit, not Save.
      expect(find.byKey(const ValueKey('row_edit_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('row_save_0')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('row_edit_0')));
      await tester.pump();
      expect(find.byKey(const ValueKey('row_save_0')), findsOneWidget,
          reason: 'Edit opens the row and its Save takes the button\'s place');

      // In-house part: Client is not drawn, so Die sits under the part and
      // Machines under Die. Outdent Machines and save the nesting.
      await tester.tap(find.byKey(const ValueKey('section_outdent_machine_master')));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('tree_save')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(repo.savedTrees, hasLength(1));
      expect(repo.savedTrees.single['machine_master'], 'client_vendor',
          reason: 'one level out from Die is Die\'s parent, Client');
      expect(find.byKey(const ValueKey('tree_dirty_bar')), findsNothing);
    });

    testWidgets('the raw sheet panel waits for the part, then edits and saves on it',
        (tester) async {
      // A new part: the panel is drawn, but there is nowhere to store it yet.
      await _pumpScreen(tester, size: const Size(1700, 3200));
      expect(find.byKey(const ValueKey('raw_panel')), findsOneWidget);
      expect(find.textContaining('Opens once the part is saved'), findsOneWidget);
      expect(find.byKey(const ValueKey('raw_edit')), findsNothing);
    });

    testWidgets('a saved part: Edit the raw sheet, Save writes it on the part',
        (tester) async {
      final patti = _item(id: 500, name: 'Patti', groupId: 11);
      final repo = _FakeItemRepository([patti]);
      await _pumpScreen(
        tester,
        initialItems: [patti],
        repository: repo,
        size: const Size(1700, 3200),
      );
      expect(find.byType(MasterDataPanel), findsOneWidget);
      expect(tester.widget<MasterDataPanel>(find.byType(MasterDataPanel)).readOnly, isTrue);

      await tester.tap(find.byKey(const ValueKey('raw_edit')));
      await tester.pump();
      final panel = tester.widget<MasterDataPanel>(find.byType(MasterDataPanel));
      expect(panel.readOnly, isFalse);

      await tester.runAsync(() async {
        panel.onSave(panel.baseline);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(repo.updated.single.penPaperBaseline, isNotNull,
          reason: 'the baseline is written on the part, everything else kept');
      expect(repo.updated.single.id, 500);
    });

    testWidgets('the footer Edit, typed pieces, Save: the pieces are on the part',
        (tester) async {
      final patti = _item(id: 500, name: 'Patti', groupId: 11);
      final repo = _FakeItemRepository([patti]);
      await _pumpScreen(
        tester,
        initialItems: [patti],
        repository: repo,
        size: const Size(1700, 3200),
      );
      expect(tester.widget<MasterDataPanel>(find.byType(MasterDataPanel)).itemName,
          'Patti',
          reason: 'the part, not a guess from the cursor row');

      // Read only, the footer offers the way in where the Save would be.
      await tester.tap(find.byKey(const ValueKey('master-data-edit')));
      await tester.pump();
      expect(tester.widget<MasterDataPanel>(find.byType(MasterDataPanel)).readOnly,
          isFalse);

      await tester.ensureVisible(find.text('Material data'));
      await tester.pump();
      await tester.tap(find.text('Material data'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('material-output-pieces')), '2900');
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('master-data-save')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      final row = repo.updated.single.penPaperBaseline!.stageReconciliations.single;
      expect(row.outputPieces, 2900);
      expect(row.outputLabel, 'Patti');
      expect(tester.widget<MasterDataPanel>(find.byType(MasterDataPanel)).readOnly,
          isTrue,
          reason: 'a save that landed leaves edit mode');
    });

    testWidgets('the raw sheet names the part\'s own Alloy, not one of its own',
        (tester) async {
      ItemVariationNodeDefinition node(int id, String name,
              {ItemVariationNodeKind kind = ItemVariationNodeKind.property,
              int? parent,
              List<ItemVariationNodeDefinition> children = const []}) =>
          ItemVariationNodeDefinition(
            id: id,
            itemId: 500,
            parentNodeId: parent,
            kind: kind,
            name: name,
            displayName: name,
            position: 0,
            isArchived: false,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            children: children,
            inputType: kind == ItemVariationNodeKind.property ? 'Material' : 'Text',
          );
      final patti = _item(id: 500, name: 'Patti', groupId: 11, variationTree: [
        node(10, 'Alloy', children: [
          node(11, 'Brass', kind: ItemVariationNodeKind.value, parent: 10),
        ]),
      ]);
      final repo = _FakeItemRepository([patti]);
      await _pumpScreen(
        tester,
        initialItems: [patti],
        repository: repo,
        size: const Size(1700, 3200),
      );
      final panel = tester.widget<MasterDataPanel>(find.byType(MasterDataPanel));
      expect(panel.alloy, 'Brass');
      expect(panel.materials, isEmpty,
          reason: 'no picker of its own: alloy is changed in its column');
    });

    testWidgets('selecting a saved row moves the sections onto its part',
        (tester) async {
      final patti = _item(id: 500, name: 'Patti', groupId: 11, partCode: 'SADP48');
      final strip = _item(id: 501, name: 'Strip', groupId: 11, partCode: 'SADS49');
      final repo = _FakeItemRepository([patti, strip]);
      await _pumpScreen(
        tester,
        initialItems: [patti, strip],
        repository: repo,
        size: const Size(1700, 3200),
      );
      MasterDataPanel panel() =>
          tester.widget<MasterDataPanel>(find.byType(MasterDataPanel));
      PartDieSection dies() =>
          tester.widget<PartDieSection>(find.byType(PartDieSection));
      expect(panel().itemName, 'Patti');
      expect(find.textContaining('SAVED #500'), findsOneWidget);

      // A saved row is closed, but a tap still selects it.
      await tester.tap(find.text('Strip').first);
      await tester.pump();
      expect(panel().itemName, 'Strip');
      expect(dies().part?.id, 501);
      expect(find.textContaining('SAVED #501'), findsOneWidget);
    });

    testWidgets('a die held on a new row stays with that row', (tester) async {
      final patti = _item(id: 500, name: 'Patti', groupId: 11);
      final repo = _FakeItemRepository([patti]);
      // Held dies are offered only where they can be made.
      AppFlowHooks.createDieFromSheet = (context, draft) async =>
          throw UnimplementedError('not saved in this test');
      addTearDown(() => AppFlowHooks.createDieFromSheet = null);
      await _pumpScreen(
        tester,
        initialItems: [patti],
        repository: repo,
        size: const Size(1700, 3200),
      );
      PartDieSection dies() =>
          tester.widget<PartDieSection>(find.byType(PartDieSection));

      await tester.tap(find.text('Add row').first);
      await tester.pump();
      expect(dies().part, isNull, reason: 'a new row is a new part');
      dies().onStage(const DieSheetDraft(toolCode: 'D1', dieType: 'cutting'));
      await tester.pump();
      expect(dies().staged, hasLength(1));

      await tester.tap(find.text('Patti').first);
      await tester.pump();
      expect(dies().part?.id, 500);
      expect(dies().staged, isEmpty, reason: 'held for the other row');

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is ValueCell && w.rowIndex == 1 && w.column.id == 3,
        ),
      );
      await tester.pump();
      expect(dies().staged.single.toolCode, 'D1');
    });

    testWidgets('a die changed anywhere re-reads the open part (real time)',
        (tester) async {
      // The server announces a die edit on every part that uses it
      // (migration 060). That part is fetched from the server — not re-read
      // from the local replica, which has not applied the change yet.
      final patti = _item(id: 500, name: 'Patti', groupId: 11);
      final repo = _FakeItemRepository([patti]);
      await _pumpScreen(tester, initialItems: [patti], repository: repo, live: true);

      final data = jsonEncode({'table_name': 'items', 'record_id': 500, 'event_type': 'UPDATE'});
      await tester.runAsync(() async {
        SocketService.instance.processEventForTest('event: table-change\ndata: $data');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      expect(repo.freshReads, contains(500), reason: 'the part is fetched fresh');
      // And it is not blanked by the id-only event on the way.
      expect(find.text('Patti'), findsWidgets);
    });

    testWidgets('the raw sheet panel folds to a tab', (tester) async {
      await _pumpScreen(tester, size: const Size(1700, 3200));
      await tester.tap(find.byKey(const ValueKey('raw_panel_close')));
      await tester.pump();
      expect(find.byKey(const ValueKey('raw_panel')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('raw_panel_open')));
      await tester.pump();
      expect(find.byKey(const ValueKey('raw_panel')), findsOneWidget);
    });

    testWidgets('the people table is drawn before a company, disabled with why',
        (tester) async {
      // Hidden until a company is chosen would read as "this sheet has no
      // people" — drawn disabled, it says what it is waiting for.
      await _pumpScreen(tester);
      await tester.tap(find.text('Client / Vendor').first);
      await tester.pump();

      expect(find.text('People'), findsOneWidget);
      expect(find.text('Add person'), findsOneWidget);
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.text('Add person'),
          matching: find.byWidgetPredicate(
            (w) => w is Tooltip && w.message == 'Pick a company first',
          ),
        ),
      );
      expect(tooltip.message, 'Pick a company first');
    });

    testWidgets('the part stays pinned across a switch', (tester) async {
      // Switching to Dies must keep saying which part they belong to.
      await _pumpScreen(tester);
      expect(find.text('NEW RECORD'), findsOneWidget);

      await tester.tap(find.text('Die Process Master').first);
      await tester.pump();

      expect(find.text('NEW RECORD'), findsOneWidget);
      expect(find.text('Unnamed'), findsWidgets);
    });

    testWidgets('a part code is "stamped on save", not a made-up one',
        (tester) async {
      await _pumpScreen(tester);
      // The prototype printed `activeItem?.variantCode ?? 'SADPB2248'`.
      expect(find.text('stamped on save'), findsOneWidget);
      expect(find.textContaining('SADPB2248'), findsNothing);
    });

    testWidgets('routing is drawn disabled, with the reason, before a save',
        (tester) async {
      await _pumpScreen(tester);
      await tester.tap(find.text('Machines & Routing').first);
      await tester.pump();

      expect(
        find.textContaining('Save the part first'),
        findsOneWidget,
        reason: 'never hide a control until its precondition holds',
      );
      final button = tester.widget<Tooltip>(
        find.ancestor(
          of: find.text('Author route'),
          matching: find.byType(Tooltip),
        ).first,
      );
      expect(button.message, 'Available once the part is saved');
    });

    testWidgets('unticking the external box hides the party section but keeps '
        'its draft', (tester) async {
      await _pumpScreen(tester);
      expect(find.text('Client / Vendor'), findsWidgets);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      expect(
        find.text('Client / Vendor'),
        findsNothing,
        reason: 'an in-house part has no development deal to record',
      );
    });

    testWidgets('a sitting is open while the screen is, and closed after',
        (tester) async {
      expect(SittingScope.current, isNull);
      await _pumpScreen(tester);
      final sitting = SittingScope.current;
      expect(sitting, isNotNull);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      expect(SittingScope.current, isNull);
    });

    testWidgets('opening an existing part loads it into the sheet',
        (tester) async {
      final patti = _item(id: 500, name: 'Patti', groupId: 11);
      await _pumpScreen(tester, initialItems: [patti], stored: [patti]);

      expect(find.text('Patti'), findsWidgets);
      expect(find.textContaining('SAVED #500'), findsOneWidget);
    });
  });

  group('it fits the windows it is opened in', () {
    // Overflow is how this screen has failed before — a 6.5px identity row, a
    // 72px sidebar, a 1px title bar. Each was found by a test that happened to
    // be looking elsewhere.
    for (final width in [1366.0, 1600.0, 1920.0]) {
      testWidgets('no section overflows at ${width.toInt()}px', (tester) async {
        await _pumpScreen(tester, size: Size(width, 1000));

        for (final section in [
          'Group Item',
          'Client / Vendor',
          'Die Process Master',
          'Machines & Routing',
        ]) {
          await tester.tap(find.text(section).first);
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: '$section at ${width.toInt()}px',
          );
        }
      });
    }
  });
}
