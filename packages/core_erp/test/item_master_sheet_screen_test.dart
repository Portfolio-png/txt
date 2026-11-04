import 'dart:ui' show AppExitResponse;

import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/core/utils/stamp_format.dart';
import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/developed_for.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/domain/item_inputs.dart';
import 'package:core_erp/features/production_pipelines/presentation/widgets/master_data_dialog.dart';
import 'package:core_erp/core/app_flow_hooks.dart';
import 'package:core_erp/core/services/entity_photos.dart';
import 'package:core_erp/features/items/presentation/widgets/part_die_section.dart';
import 'package:core_erp/features/items/presentation/widgets/part_machine_section.dart';
import 'package:core_erp/features/items/presentation/widgets/deal_people_form.dart';
import 'package:core_erp/features/items/presentation/widgets/part_rows_form.dart';
import 'package:core_erp/features/process_routes/data/process_route_service.dart';
import 'package:core_erp/features/process_routes/domain/part_route.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/items/presentation/screens/item_master_sheet_screen.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'dart:convert';

import 'package:core_erp/core/network/sitting_scope.dart';
import 'package:core_erp/core/services/socket_service.dart';
import 'package:core_erp/sheet/sheet.dart';
import 'package:core_erp/core/widgets/pick_or_type_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// Refuses every save that links dies — a link that does not go through.
  bool refuseDieLinks = false;

  @override
  Future<ItemDefinition> updateItem(UpdateItemInput input) async {
    if (refuseDieLinks && input.dieIds.isNotEmpty) {
      throw Exception('link refused');
    }
    updated.add(input);
    return stored.firstWhere((i) => i.id == input.id);
  }

  final List<CreateItemInput> created = [];

  @override
  Future<ItemDefinition> createItem(CreateItemInput input) async {
    created.add(input);
    final made = _item(
      id: 900 + created.length,
      name: input.name,
      groupId: input.groupId,
    );
    stored.add(made);
    return made;
  }

  @override
  Future<ItemDefinition> saveSectionTree(
    int itemId,
    Map<String, String> tree,
  ) async {
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
}) => GroupDefinition(
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
  List<ItemDieLink> dies = const [],
  List<ItemMachineLink> machines = const [],
  DevelopedFor developedFor = DevelopedFor.empty,
}) => ItemDefinition(
  id: id,
  name: name,
  alias: '',
  displayName: name,
  partNo: 48,
  partCode: partCode,
  quantity: 0,
  groupId: groupId,
  unitId: 7,
  developedFor: developedFor,
  isArchived: false,
  usageCount: 0,
  createdAt: DateTime(2026, 5, 15, 10, 5),
  updatedAt: DateTime(2026, 5, 15, 10, 5),
  variationTree: variationTree,
  dies: dies,
  machines: machines,
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  List<ItemDefinition> initialItems = const [],
  List<ItemDefinition> stored = const [],
  Size? size,
  _FakeItemRepository? repository,
  // Subscribed to the change stream, as the app's provider is after start-up.
  bool live = false,
  ProcessRouteService? routes,
  EntityPhotosProvider? photos,
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
  final itemsProvider = ItemsProvider(
    repository: repository ?? _FakeItemRepository(List.of(stored)),
  );
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
        if (routes != null) Provider<ProcessRouteService>.value(value: routes),
        if (photos != null)
          ChangeNotifierProvider<EntityPhotosProvider>.value(value: photos),
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
}) => SheetController(
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
    testWidgets('reads the name and code through their bindings', (
      tester,
    ) async {
      // The whole identity chain, because the code column is derived — a code
      // written straight into the draft is recomputed away.
      final controller = _controllerWith(
        values: {
          1: const CellValue(columnId: 1, optionLabel: 'Switch Action'),
          2: const CellValue(columnId: 2, optionLabel: 'Dolly'),
          3: const CellValue(columnId: 3, optionLabel: 'Patti'),
        },
        counters: {'Switch Action › Dolly › Patti': 47},
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );

      expect(find.text('Patti'), findsWidgets);
      expect(find.text('SADP48'), findsWidgets);
    });

    testWidgets('showIdentity: false leaves the naming to the host', (
      tester,
    ) async {
      // The item sheet pins the part above its content, so the rail naming it
      // too said it twice. The flag existed from the start and was never read.
      final controller = _controllerWith(
        values: {
          1: const CellValue(columnId: 1, optionLabel: 'Switch Action'),
          2: const CellValue(columnId: 2, optionLabel: 'Dolly'),
          3: const CellValue(columnId: 3, optionLabel: 'Patti'),
        },
        counters: {'Switch Action › Dolly › Patti': 47},
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SheetSidebar(
              controller: controller,
              sections: const [],
              activeSection: '',
              onSelectSection: (_) {},
              showIdentity: false,
            ),
          ),
        ),
      );

      expect(find.text('SECTIONS'), findsOneWidget);
      expect(find.text('Patti'), findsNothing);
      expect(find.text('SADP48'), findsNothing);
    });

    testWidgets('an unnamed row says so rather than showing a name nobody '
        'typed', (tester) async {
      final controller = _controllerWith();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SheetSidebar(
              controller: controller,
              sections: const [],
              activeSection: '',
              onSelectSection: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Unnamed'), findsOneWidget);
      expect(find.text('New Item'), findsNothing);
      expect(find.text('Not filed under a group yet'), findsOneWidget);
    });

    testWidgets('never invents a party', (tester) async {
      final controller = _controllerWith();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SheetSidebar(
              controller: controller,
              sections: const [],
              activeSection: '',
              onSelectSection: (_) {},
            ),
          ),
        ),
      );

      // The old sidebar's footnote was
      // `draft.get(20)?.optionLabel ?? 'Gold Medal'`.
      expect(find.textContaining('Gold Medal'), findsNothing);
    });

    testWidgets('its sections are whatever it is given', (tester) async {
      final controller = _controllerWith();
      addTearDown(controller.dispose);
      final tapped = <String>[];

      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );

      expect(find.text('Tooling'), findsOneWidget);
      expect(find.text('Liners'), findsOneWidget);
      // Four section names the old sidebar had typed into it.
      expect(find.text('Group Item'), findsNothing);
      expect(find.text('Die Process Master'), findsNothing);

      await tester.tap(find.text('Liners'));
      expect(tapped, ['liners']);
    });

    testWidgets('the column tree names the sheet’s own properties', (
      tester,
    ) async {
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

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SheetSidebar(
              controller: controller,
              sections: const [],
              activeSection: '',
              onSelectSection: (_) {},
            ),
          ),
        ),
      );

      expect(find.textContaining('Liner Size'), findsWidgets);
      expect(find.textContaining('Alloy'), findsNothing);
      expect(find.textContaining('Thickness'), findsNothing);
    });

    testWidgets('no text below the house floor', (tester) async {
      final controller = _controllerWith(
        values: {3: const CellValue(columnId: 3, optionLabel: 'Patti')},
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );

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
        'Item Master',
        'Client',
        'Die Process Master',
        'Machines & Routing',
      ]) {
        expect(
          find.text(section),
          findsWidgets,
          reason: '$section in the rail',
        );
      }

      // The Item Master grid is on screen; the others are not built at all.
      expect(find.text('Parts on this sheet: 1'), findsOneWidget);
      expect(find.text('The deal'), findsNothing);
    });

    testWidgets('every section is on one page, nested like a file tree', (
      tester,
    ) async {
      await _pumpScreen(tester);
      // All four at once — the rail no longer switches between them.
      expect(find.text('Parts on this sheet: 1'), findsOneWidget);
      expect(find.text('Quotation (₹)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('section_toggle_die_master')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('section_toggle_machine_master')),
        findsOneWidget,
      );

      // Each level sits further right than the one it is nested in.
      double left(String id) =>
          tester.getTopLeft(find.byKey(ValueKey('section_toggle_$id'))).dx;
      expect(left('client_vendor'), greaterThan(left('group_item')));
      expect(left('die_master'), greaterThan(left('client_vendor')));
      expect(left('machine_master'), greaterThan(left('die_master')));
    });

    testWidgets(
      'folding a section folds only it, into one row of what it holds',
      (tester) async {
        await _pumpScreen(tester, size: const Size(1600, 3200));
        await tester.tap(
          find.byKey(const ValueKey('section_toggle_client_vendor')),
        );
        await tester.pump();

        expect(
          find.text('Quotation (₹)'),
          findsNothing,
          reason: 'its body is folded',
        );
        expect(
          find.byKey(const ValueKey('section_summary_client_vendor')),
          findsOneWidget,
        );
        expect(find.text('No company chosen yet'), findsOneWidget);
        // What is nested under it stays on the page.
        expect(
          find.byKey(const ValueKey('section_toggle_die_master')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('section_toggle_machine_master')),
          findsOneWidget,
        );

        // Tapping the summary opens it again.
        await tester.tap(
          find.byKey(const ValueKey('section_summary_client_vendor')),
        );
        await tester.pump();
        expect(find.text('Quotation (₹)'), findsOneWidget);
      },
    );

    testWidgets(
      'the breadcrumb names the open part, and its deal says when it was recorded',
      (tester) async {
        final at = DateTime.utc(2026, 11, 3, 9, 15);
        final patti = _item(
          id: 500,
          name: 'Patti',
          groupId: 11,
          developedFor: DevelopedFor(
            kind: DevelopedForKind.client,
            clientId: 5,
            companyName: 'Gold Medal',
            at: at,
          ),
        );
        await _pumpScreen(
          tester,
          initialItems: [patti],
          repository: _FakeItemRepository([patti]),
          size: const Size(1700, 3200),
        );
        expect(
          find.text('Patti · SADP48'),
          findsOneWidget,
          reason: 'a saved part used to read "New part"',
        );
        expect(find.text('New part'), findsNothing);
        expect(find.textContaining(partStamp(at)), findsWidgets);
        expect(
          find.textContaining('Set on save'),
          findsNothing,
          reason: 'the deal is saved, so it has a stamp',
        );
      },
    );

    testWidgets(
      'a part line\'s dropdown: type to search, Enter picks, focus stays',
      (tester) async {
        await _pumpScreen(tester, size: const Size(1700, 3200));
        final sheet = tester
            .widget<PartRowsForm>(find.byType(PartRowsForm))
            .sheet;
        sheet.focusCell(1, row: 0);
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.keyS, character: 's');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.text('Select Group'),
          findsOneWidget,
          reason: 'the letter opened it',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final group = sheet.draftAt(0).get(1);
        expect(group?.optionLabel, 'Switch Action');
        expect(
          group?.isNew,
          isFalse,
          reason: 'an existing group, not a new one',
        );

        // Typed in full and Enter: still the one that exists, not a duplicate.
        sheet.focusCell(1, row: 0);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(find.byType(TextField).last, 'switch action');
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump(const Duration(milliseconds: 300));
        expect(sheet.draftAt(0).get(1)?.isNew, isFalse);
        expect(
          sheet.options.where(
            (o) => o.columnId == 1 && o.label.toLowerCase() == 'switch action',
          ),
          hasLength(1),
          reason: 'Enter on an existing name used to file a second one',
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'a die typed and not held survives a fold, and the leave warning names it',
      (tester) async {
        await _pumpScreen(tester, size: const Size(1700, 3200));
        final before = tester.state(find.byType(PartDieSection));

        // Folding used to dispose the section, and the typed die with it.
        await tester.tap(
          find.byKey(const ValueKey('section_toggle_die_master')),
        );
        await tester.pump();
        expect(
          find.byType(PartDieSection, skipOffstage: false),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('section_summary_die_master')),
        );
        await tester.pump();
        expect(tester.state(find.byType(PartDieSection)), same(before));

        // The section says a die is half typed; leaving names it.
        tester
            .widget<PartDieSection>(find.byType(PartDieSection))
            .onDirtyChanged!(true);
        tester
            .widget<PartMachineSection>(find.byType(PartMachineSection))
            .onDirtyChanged!(true);
        await tester.pump();
        await tester.tap(find.byTooltip('Back').first);
        await tester.pump();
        await tester.pump();
        expect(find.text('Leave with unsaved work?'), findsOneWidget);
        expect(find.textContaining('a die being typed'), findsOneWidget);
        expect(find.textContaining('a machine being typed'), findsOneWidget);
      },
    );

    testWidgets('an edited raw sheet folded away is kept, not thrown out', (
      tester,
    ) async {
      final patti = _item(id: 500, name: 'Patti', groupId: 11);
      await _pumpScreen(
        tester,
        initialItems: [patti],
        repository: _FakeItemRepository([patti]),
        size: const Size(1700, 3200),
      );
      await tester.tap(find.byKey(const ValueKey('master-data-edit')));
      await tester.pump();
      final before = tester.state(find.byType(MasterDataPanel));

      await tester.tap(find.byKey(const ValueKey('raw_panel_close')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('raw_panel')),
        findsNothing,
        reason: 'folded, as far as anyone can see',
      );
      expect(
        find.byType(MasterDataPanel, skipOffstage: false),
        findsOneWidget,
        reason: 'but still holding what was typed',
      );

      await tester.tap(find.byKey(const ValueKey('raw_panel_open')));
      await tester.pump();
      expect(tester.state(find.byType(MasterDataPanel)), same(before));
    });

    testWidgets('a part with no thickness does not wipe the raw sheet\'s own', (
      tester,
    ) async {
      final patti = _item(id: 500, name: 'Patti', groupId: 11);
      await _pumpScreen(
        tester,
        initialItems: [patti],
        repository: _FakeItemRepository([patti]),
        size: const Size(1700, 3200),
      );
      final panel = tester.widget<MasterDataPanel>(
        find.byType(MasterDataPanel),
      );
      expect(
        panel.thickness,
        isNull,
        reason: "'' told the panel the part's thickness is 0",
      );
    });

    testWidgets(
      'a folded die or machine line says what was filled, with when',
      (tester) async {
        // "1 die: JDHH1" said there was a die and nothing about it.
        final ordered = DateTime(2026, 10, 2, 9, 30);
        final arrived = DateTime(2026, 10, 9, 16, 15);
        final patti = _item(
          id: 500,
          name: 'Patti',
          groupId: 11,
          dies: [
            ItemDieLink(
              id: '31',
              toolCode: 'CDPGESP1',
              dieType: 'cutting',
              madeBy: 'Ashok Dies',
              poAt: ordered,
              dateInAt: arrived,
              noOfSet: 2,
              rackNo: 'R-12',
            ),
          ],
          machines: const [
            ItemMachineLink(
              id: '41',
              name: 'Press 1',
              assetId: 'PP-7',
              machineMake: 'Kirloskar',
            ),
          ],
        );
        await _pumpScreen(
          tester,
          initialItems: [patti],
          repository: _FakeItemRepository([patti]),
          size: const Size(1700, 3200),
        );
        for (final id in ['die_master', 'machine_master']) {
          await tester.tap(find.byKey(ValueKey('section_toggle_$id')));
          await tester.pump();
        }

        String line(String id) => tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(ValueKey('section_summary_$id')),
                matching: find.byType(Text),
              ),
            )
            .textSpan!
            .toPlainText();

        expect(
          line('die_master'),
          allOf(
            startsWith('CDPGESP1'),
            contains('Type Cutting'),
            contains('Made by Ashok Dies'),
            contains('Ordered ${partStamp(ordered)}'),
            contains('Arrived ${partStamp(arrived)}'),
            contains('Sets 2'),
            contains('Kept Rack R-12'),
          ),
        );
        expect(
          line('machine_master'),
          allOf(
            startsWith('PP-7'),
            contains('Name Press 1'),
            contains('Make Kirloskar'),
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );

    double left(WidgetTester tester, String id) =>
        tester.getTopLeft(find.byKey(ValueKey('section_toggle_$id'))).dx;

    testWidgets(
      'sections carry no pencil — saving is per row; the part itself has no bin',
      (tester) async {
        await _pumpScreen(tester, size: const Size(1600, 3200));
        for (final id in [
          'group_item',
          'client_vendor',
          'die_master',
          'machine_master',
        ]) {
          expect(
            find.byKey(ValueKey('section_edit_$id')),
            findsNothing,
            reason: id,
          );
          expect(
            find.byKey(ValueKey('section_save_$id')),
            findsNothing,
            reason: id,
          );
        }
        // Never pressable on the part itself, so not drawn: the part is retired
        // with Archive part in the top bar.
        expect(
          find.byKey(const ValueKey('section_clear_group_item')),
          findsNothing,
        );
        // A blank new row has nothing to save yet: drawn, disabled, saying why.
        final save = tester.widget<AppButton>(
          find.byKey(const ValueKey('row_save_0')),
        );
        expect(save.onPressed, isNull);
        expect(find.byTooltip('Type a part name first'), findsOneWidget);
      },
    );

    testWidgets('the side column folds to icons and opens again', (
      tester,
    ) async {
      await _pumpScreen(tester, size: const Size(1600, 3200));
      expect(find.byKey(const ValueKey('rail_collapsed')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('rail_collapse')));
      await tester.pump();
      expect(find.byKey(const ValueKey('rail_collapsed')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('rail_icon_machine_master')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('rail_expand')));
      await tester.pump();
      expect(find.byKey(const ValueKey('rail_collapsed')), findsNothing);
    });

    testWidgets('outdent moves a section out a level; undo puts it back', (
      tester,
    ) async {
      await _pumpScreen(tester, size: const Size(1600, 3200));
      expect(
        left(tester, 'machine_master'),
        greaterThan(left(tester, 'die_master')),
      );

      await tester.tap(
        find.byKey(const ValueKey('section_outdent_machine_master')),
      );
      await tester.pump();
      expect(
        left(tester, 'machine_master'),
        left(tester, 'die_master'),
        reason: 'now a sibling of Die, both under Client',
      );
      expect(find.byKey(const ValueKey('tree_dirty_bar')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tree_undo')));
      await tester.pump();
      expect(
        left(tester, 'machine_master'),
        greaterThan(left(tester, 'die_master')),
      );
      expect(find.byKey(const ValueKey('tree_dirty_bar')), findsNothing);
    });

    Future<void> dragOnto(
      WidgetTester tester,
      String dragged,
      String target,
    ) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey('section_drag_$dragged'))),
      );
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(
        tester.getCenter(find.byKey(ValueKey('section_toggle_$target'))),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();
    }

    testWidgets('dragging a section onto another nests it there', (
      tester,
    ) async {
      await _pumpScreen(tester, size: const Size(1600, 3200));
      await dragOnto(tester, 'machine_master', 'group_item');
      expect(
        left(tester, 'machine_master'),
        left(tester, 'client_vendor'),
        reason: 'directly under the part, beside Client',
      );
      expect(find.byKey(const ValueKey('tree_dirty_bar')), findsOneWidget);
    });

    testWidgets('a section cannot be dropped inside its own subtree', (
      tester,
    ) async {
      await _pumpScreen(tester, size: const Size(1600, 3200));
      await dragOnto(tester, 'client_vendor', 'machine_master');
      expect(find.byKey(const ValueKey('tree_dirty_bar')), findsNothing);
      expect(
        left(tester, 'machine_master'),
        greaterThan(left(tester, 'client_vendor')),
      );
    });

    testWidgets('a saved row is closed until its Edit; the nesting saves', (
      tester,
    ) async {
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
      expect(
        find.byKey(const ValueKey('row_save_0')),
        findsOneWidget,
        reason: 'Edit opens the row and its Save takes the button\'s place',
      );

      // In-house part: Client is not drawn, so Die sits under the part and
      // Machines under Die. Outdent Machines and save the nesting.
      await tester.tap(
        find.byKey(const ValueKey('section_outdent_machine_master')),
      );
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('tree_save')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(repo.savedTrees, hasLength(1));
      expect(
        repo.savedTrees.single['machine_master'],
        'client_vendor',
        reason: 'one level out from Die is Die\'s parent, Client',
      );
      expect(find.byKey(const ValueKey('tree_dirty_bar')), findsNothing);
    });

    testWidgets(
      'the raw sheet panel waits for the part, then edits and saves on it',
      (tester) async {
        // A new part: the panel is drawn, but there is nowhere to store it yet.
        await _pumpScreen(tester, size: const Size(1700, 3200));
        expect(find.byKey(const ValueKey('raw_panel')), findsOneWidget);
        expect(
          find.textContaining('Save the part to plan its raw sheet'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('master-data-edit')), findsNothing);
      },
    );

    testWidgets(
      'a saved part: Edit the raw sheet, Save writes it on the part',
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
        expect(
          tester.widget<MasterDataPanel>(find.byType(MasterDataPanel)).readOnly,
          isTrue,
        );

        await tester.tap(find.byKey(const ValueKey('master-data-edit')));
        await tester.pump();
        final panel = tester.widget<MasterDataPanel>(
          find.byType(MasterDataPanel),
        );
        expect(panel.readOnly, isFalse);

        await tester.runAsync(() async {
          panel.onSave(panel.baseline);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
        expect(
          repo.updated.single.penPaperBaseline,
          isNotNull,
          reason: 'the baseline is written on the part, everything else kept',
        );
        expect(repo.updated.single.id, 500);
      },
    );

    testWidgets('an edited raw sheet says it is unsaved, until its own Save', (
      tester,
    ) async {
      final patti = _item(id: 500, name: 'Patti', groupId: 11);
      final repo = _FakeItemRepository([patti]);
      await _pumpScreen(
        tester,
        initialItems: [patti],
        repository: repo,
        size: const Size(1700, 3200),
      );
      expect(find.byKey(const ValueKey('raw_unsaved')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('master-data-edit')));
      await tester.pump();
      final panel = tester.widget<MasterDataPanel>(
        find.byType(MasterDataPanel),
      );
      expect(find.text('Save raw sheet'), findsOneWidget);

      // The panel reports a working copy that differs from the record.
      panel.onDirtyChanged!(true);
      await tester.pump();
      expect(find.byKey(const ValueKey('raw_unsaved')), findsOneWidget);

      await tester.runAsync(() async {
        panel.onSave(panel.baseline);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(
        find.byKey(const ValueKey('raw_unsaved')),
        findsNothing,
        reason: 'saved, and out of edit mode',
      );
    });

    testWidgets(
      'the raw sheet panel runs on the part\'s route — the route is its pipeline',
      (tester) async {
        final patti = _item(id: 500, name: 'Patti', groupId: 11);
        final routes = ProcessRouteService(baseUrl: '', useMockResponses: true);
        await routes.save(500, const [
          RouteStep(stageId: 1, seq: 1, stageCode: 'die', stageName: 'Die'),
          RouteStep(
            stageId: 2,
            seq: 2,
            stageCode: 'shearing',
            stageName: 'Shearing',
          ),
        ]);
        await _pumpScreen(
          tester,
          initialItems: [patti],
          repository: _FakeItemRepository([patti]),
          size: const Size(1700, 3200),
          routes: routes,
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();

        final panel = tester.widget<MasterDataPanel>(
          find.byType(MasterDataPanel),
        );
        expect(panel.pipelineId, startsWith('route:'));
        // The offline mock names no pipeline, so the title falls back to
        // "Route"; the server's derived name is read in part_route_test.
        expect(panel.pipelineName, 'Route v1');
        expect(panel.stageNodes.map((node) => node.name), ['Die', 'Shearing']);
      },
    );

    testWidgets(
      'an unrouted part says to author a route, not to pick a pipeline',
      (tester) async {
        final patti = _item(id: 500, name: 'Patti', groupId: 11);
        await _pumpScreen(
          tester,
          initialItems: [patti],
          repository: _FakeItemRepository([patti]),
          size: const Size(1700, 3200),
          routes: ProcessRouteService(baseUrl: '', useMockResponses: true),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();

        final panel = tester.widget<MasterDataPanel>(
          find.byType(MasterDataPanel),
        );
        expect(panel.pipelineId, isNull);
        expect(panel.unattachedHint, contains('Author route'));
      },
    );

    testWidgets(
      'the footer Edit, typed pieces, Save: the pieces are on the part',
      (tester) async {
        final patti = _item(id: 500, name: 'Patti', groupId: 11);
        final repo = _FakeItemRepository([patti]);
        await _pumpScreen(
          tester,
          initialItems: [patti],
          repository: repo,
          size: const Size(1700, 3200),
        );
        expect(
          tester.widget<MasterDataPanel>(find.byType(MasterDataPanel)).itemName,
          'Patti',
          reason: 'the part, not a guess from the cursor row',
        );

        // Read only, the footer offers the way in where the Save would be.
        await tester.tap(find.byKey(const ValueKey('master-data-edit')));
        await tester.pump();
        expect(
          tester.widget<MasterDataPanel>(find.byType(MasterDataPanel)).readOnly,
          isFalse,
        );

        await tester.ensureVisible(find.text('Material data'));
        await tester.pump();
        await tester.tap(find.text('Material data'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('material-output-pieces')),
          '2900',
        );
        await tester.pump();

        await tester.runAsync(() async {
          await tester.tap(find.byKey(const ValueKey('master-data-save')));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
        final row =
            repo.updated.single.penPaperBaseline!.stageReconciliations.single;
        expect(row.outputPieces, 2900);
        expect(row.outputLabel, 'Patti');
        expect(
          tester.widget<MasterDataPanel>(find.byType(MasterDataPanel)).readOnly,
          isTrue,
          reason: 'a save that landed leaves edit mode',
        );
      },
    );

    testWidgets(
      'the raw sheet names the part\'s own Alloy, not one of its own',
      (tester) async {
        ItemVariationNodeDefinition node(
          int id,
          String name, {
          ItemVariationNodeKind kind = ItemVariationNodeKind.property,
          int? parent,
          List<ItemVariationNodeDefinition> children = const [],
        }) => ItemVariationNodeDefinition(
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
          inputType: kind == ItemVariationNodeKind.property
              ? 'Material'
              : 'Text',
        );
        final patti = _item(
          id: 500,
          name: 'Patti',
          groupId: 11,
          variationTree: [
            node(
              10,
              'Alloy',
              children: [
                node(
                  11,
                  'Brass',
                  kind: ItemVariationNodeKind.value,
                  parent: 10,
                ),
              ],
            ),
          ],
        );
        final repo = _FakeItemRepository([patti]);
        await _pumpScreen(
          tester,
          initialItems: [patti],
          repository: repo,
          size: const Size(1700, 3200),
        );
        final panel = tester.widget<MasterDataPanel>(
          find.byType(MasterDataPanel),
        );
        expect(panel.alloy, 'Brass');
        expect(
          panel.materials,
          isEmpty,
          reason: 'no picker of its own: alloy is changed in its column',
        );
      },
    );

    testWidgets(
      'a property can be cleared on its line, and the save takes it off',
      (tester) async {
        final patti = _item(
          id: 500,
          name: 'Patti',
          groupId: 11,
          variationTree: [
            ItemVariationNodeDefinition(
              id: 10,
              itemId: 500,
              parentNodeId: null,
              kind: ItemVariationNodeKind.property,
              name: 'Alloy',
              displayName: 'Alloy',
              inputType: 'Material',
              position: 0,
              isArchived: false,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
              children: [
                ItemVariationNodeDefinition(
                  id: 11,
                  itemId: 500,
                  parentNodeId: 10,
                  kind: ItemVariationNodeKind.value,
                  name: 'Brass',
                  displayName: 'Brass',
                  position: 0,
                  isArchived: false,
                  createdAt: DateTime(2026),
                  updatedAt: DateTime(2026),
                  children: const [],
                ),
              ],
            ),
          ],
        );
        final repo = _FakeItemRepository([patti]);
        await _pumpScreen(
          tester,
          initialItems: [patti],
          repository: repo,
          size: const Size(1700, 3200),
        );
        expect(
          find.byKey(const ValueKey('property_clear_6_0')),
          findsNothing,
          reason: 'a saved line is read only until its Edit',
        );
        await tester.tap(find.byKey(const ValueKey('row_edit_0')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('property_clear_6_0')));
        await tester.pump();

        await tester.runAsync(() async {
          await tester.tap(find.byKey(const ValueKey('row_save_0')));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
        expect(
          repo.updated.last.variationTree,
          isEmpty,
          reason: 'the cleared Alloy comes off the part',
        );
      },
    );

    testWidgets(
      'the raw panel\'s thickness is the part\'s Thickness cell, both '
      'ways, and saves with the plan',
      (tester) async {
        ItemVariationNodeDefinition node(
          int id,
          String name, {
          ItemVariationNodeKind kind = ItemVariationNodeKind.property,
          int? parent,
          List<ItemVariationNodeDefinition> children = const [],
        }) => ItemVariationNodeDefinition(
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
          inputType: kind == ItemVariationNodeKind.property ? 'Gauge' : 'Text',
        );
        final patti = _item(
          id: 500,
          name: 'Patti',
          groupId: 11,
          variationTree: [
            node(
              10,
              'Thickness',
              children: [
                node(
                  11,
                  '18 Gauge',
                  kind: ItemVariationNodeKind.value,
                  parent: 10,
                ),
              ],
            ),
          ],
        );
        final repo = _FakeItemRepository([patti]);
        await _pumpScreen(
          tester,
          initialItems: [patti],
          repository: repo,
          size: const Size(1700, 3200),
        );
        MasterDataPanel panel() =>
            tester.widget<MasterDataPanel>(find.byType(MasterDataPanel));
        expect(panel().thickness, '18 Gauge');
        expect(panel().grade, '', reason: 'no Grade column on this sheet yet');

        await tester.tap(find.byKey(const ValueKey('master-data-edit')));
        await tester.pump();
        // Typed in the panel: the part's cell takes it, in its own words.
        panel().onThicknessChanged!('1.2 mm');
        await tester.pump();
        expect(panel().thickness, '1.2 mm');
        // A gauge is the gauge option itself.
        panel().onThicknessChanged!('20 Gauge');
        await tester.pump();
        expect(panel().thickness, '20 Gauge');

        await tester.runAsync(() async {
          await tester.tap(find.byKey(const ValueKey('master-data-save')));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
        // The row went first, carrying the new thickness; then the plan.
        final rowSave = repo.updated.firstWhere(
          (input) => input.variationTree.isNotEmpty,
        );
        final thickness = rowSave.variationTree
            .firstWhere((n) => n.name == 'Thickness')
            .children
            .single
            .name;
        expect(thickness, '20 Gauge');
        expect(repo.updated.last.penPaperBaseline, isNotNull);
      },
    );

    testWidgets('selecting a saved row moves the sections onto its part', (
      tester,
    ) async {
      final patti = _item(
        id: 500,
        name: 'Patti',
        groupId: 11,
        partCode: 'SADP48',
      );
      final strip = _item(
        id: 501,
        name: 'Strip',
        groupId: 11,
        partCode: 'SADS49',
      );
      final repo = _FakeItemRepository([patti, strip]);
      await _pumpScreen(
        tester,
        initialItems: [patti, strip],
        repository: repo,
        size: const Size(1700, 3200),
      );
      // Rolled up while the part line has the cursor: there, not drawn.
      MasterDataPanel panel() => tester.widget<MasterDataPanel>(
        find.byType(MasterDataPanel, skipOffstage: false),
      );
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

      await tester.tap(find.text('Add part').first);
      await tester.pump();
      expect(dies().part, isNull, reason: 'a new row is a new part');
      dies().onStage(const DieSheetDraft(toolCode: 'D1', dieType: 'cutting'));
      await tester.pump();
      expect(dies().staged, hasLength(1));

      await tester.tap(find.text('Patti').first);
      await tester.pump();
      expect(dies().part?.id, 500);
      expect(dies().staged, isEmpty, reason: 'held for the other row');

      await tester.tap(find.byKey(const ValueKey('cell_item_1_3')));
      await tester.pump();
      expect(dies().staged.single.toolCode, 'D1');
    });

    testWidgets('a held die made but not attached stays held, and says so', (
      tester,
    ) async {
      var made = 0;
      AppFlowHooks.createDieFromSheet = (context, draft) async {
        made += 1;
        return DieCreateOutcome.created(
          CreatedRecord(id: 'die-$made', title: draft.toolCode),
        );
      };
      addTearDown(() => AppFlowHooks.createDieFromSheet = null);
      final repo = _FakeItemRepository([])..refuseDieLinks = true;
      await _pumpScreen(tester, repository: repo, size: const Size(1700, 3200));
      final sheet = tester
          .widget<PartRowsForm>(find.byType(PartRowsForm))
          .sheet;
      final def = sheet.sheetDef;
      final group = def.groupColumn!;
      final trunk = sheet.options.firstWhere((o) => o.columnId == group.id);
      sheet.updateValue(
        group.id,
        CellValue(
          columnId: group.id,
          optionId: trunk.id,
          optionLabel: trunk.label,
        ),
      );
      final type = def.columns.firstWhere((c) => c.parentId == group.id);
      final kind = sheet.options.firstWhere(
        (o) => o.columnId == type.id && o.parentOptionId == trunk.id,
      );
      sheet.updateValue(
        type.id,
        CellValue(
          columnId: type.id,
          optionId: kind.id,
          optionLabel: kind.label,
        ),
      );
      final name = def.itemColumn!;
      sheet.updateValue(
        name.id,
        CellValue(columnId: name.id, optionLabel: 'Lid', isNew: true),
      );
      tester
          .widget<PartDieSection>(find.byType(PartDieSection))
          .onStage(const DieSheetDraft(toolCode: 'D1', dieType: 'cutting'));
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('row_save_0')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump();

      expect(repo.created, hasLength(1), reason: 'the part saved');
      expect(made, 1, reason: 'the die was made');
      expect(find.textContaining('made but not attached'), findsOneWidget);
      PartDieSection dies() =>
          tester.widget<PartDieSection>(find.byType(PartDieSection));
      expect(
        dies().staged.single.toolCode,
        'D1',
        reason: 'still held, so the leave warning still names it',
      );

      // Save part again — the held die's own row carries it — links the die
      // already made, without making a second one.
      repo.refuseDieLinks = false;
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('die_held_save_0')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump();
      expect(made, 1, reason: 'not made a second time');
      expect(repo.updated.last.dieIds, ['die-1']);
      expect(dies().staged, isEmpty);
    });

    testWidgets(
      'a blank line goes at once; one holding a die asks, and takes it',
      (tester) async {
        AppFlowHooks.createDieFromSheet = (context, draft) async =>
            throw UnimplementedError('not saved in this test');
        addTearDown(() => AppFlowHooks.createDieFromSheet = null);
        await _pumpScreen(tester, size: const Size(1700, 3200));
        final sheet = tester
            .widget<PartRowsForm>(find.byType(PartRowsForm))
            .sheet;

        // A blank second line: removed without a question.
        await tester.tap(find.text('Add part').first);
        await tester.pump();
        expect(sheet.rowCount, 2);
        await tester.tap(find.byKey(const ValueKey('row_remove_1')));
        await tester.pump();
        expect(find.byType(AlertDialog), findsNothing);
        expect(sheet.rowCount, 1);

        // A second line holding a die: asked first.
        await tester.tap(find.text('Add part').first);
        await tester.pump();
        PartDieSection dies() =>
            tester.widget<PartDieSection>(find.byType(PartDieSection));
        dies().onStage(const DieSheetDraft(toolCode: 'D1', dieType: 'cutting'));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('row_remove_1')));
        await tester.pumpAndSettle();
        expect(find.text('Remove part 2?'), findsOneWidget);
        expect(find.textContaining('1 die waiting for it'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(sheet.rowCount, 2, reason: 'Cancel keeps the line');
        expect(dies().staged, hasLength(1), reason: 'and its die');

        await tester.tap(find.byKey(const ValueKey('row_remove_1')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
        await tester.pumpAndSettle();
        expect(sheet.rowCount, 1);

        // Nothing is left held for a line that is gone.
        await tester.tap(find.byTooltip('Back').first);
        await tester.pumpAndSettle();
        expect(find.text('Leave with unsaved work?'), findsNothing);
      },
    );

    testWidgets(
      'picking a part already on the sheet keeps a line that holds a die',
      (tester) async {
        AppFlowHooks.createDieFromSheet = (context, draft) async =>
            throw UnimplementedError('not saved in this test');
        addTearDown(() => AppFlowHooks.createDieFromSheet = null);
        final patti = _item(id: 500, name: 'Patti', groupId: 11);
        await _pumpScreen(
          tester,
          initialItems: [patti],
          repository: _FakeItemRepository([patti]),
          size: const Size(1700, 3200),
        );
        final sheet = tester
            .widget<PartRowsForm>(find.byType(PartRowsForm))
            .sheet;
        await tester.tap(find.text('Add part').first);
        await tester.pump();
        tester
            .widget<PartDieSection>(find.byType(PartDieSection))
            .onStage(const DieSheetDraft(toolCode: 'D1', dieType: 'cutting'));
        await tester.pump();

        final name = sheet.sheetDef.itemColumn!;
        final existing = sheet.options.firstWhere(
          (o) => o.columnId == name.id && o.label == 'Patti',
        );
        sheet.setOption(name.id, existing, row: 1);
        await tester.pump();

        expect(
          sheet.row,
          0,
          reason: 'the cursor goes to the part already here',
        );
        expect(
          sheet.rowCount,
          2,
          reason: 'the line holding a die is not dropped',
        );
      },
    );

    testWidgets('quitting the app asks, as Back does, when work is unsaved', (
      tester,
    ) async {
      await _pumpScreen(tester, size: const Size(1700, 3200));

      // Nothing typed: the app may quit, and nobody is asked.
      expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
      expect(find.text('Leave with unsaved work?'), findsNothing);

      tester
          .widget<PartDieSection>(find.byType(PartDieSection))
          .onDirtyChanged!(true);
      await tester.pump();

      Future<AppExitResponse> ask(String choice) async {
        final answer = tester.binding.handleRequestAppExit();
        await tester.pumpAndSettle();
        expect(find.text('Leave with unsaved work?'), findsOneWidget);
        await tester.tap(find.text(choice));
        await tester.pumpAndSettle();
        return answer;
      }

      expect(await ask('Keep editing'), AppExitResponse.cancel);
      expect(await ask('Discard'), AppExitResponse.exit);
    });

    testWidgets('a held die\'s row carries the part\'s own Save part', (
      tester,
    ) async {
      AppFlowHooks.createDieFromSheet = (context, draft) async =>
          throw UnimplementedError('not saved in this test');
      addTearDown(() => AppFlowHooks.createDieFromSheet = null);
      await _pumpScreen(tester, size: const Size(1700, 3200));
      final strip = tester.widget<PartRowsForm>(find.byType(PartRowsForm));
      final sheet = strip.sheet;
      final def = strip.sheet.sheetDef;

      tester
          .widget<PartDieSection>(find.byType(PartDieSection))
          .onStage(const DieSheetDraft(toolCode: 'D1', dieType: 'cutting'));
      await tester.pump();
      AppButton heldSave() => tester.widget<AppButton>(
        find.byKey(const ValueKey('die_held_save_0')),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('die_held_save_0')),
          matching: find.text('Save part'),
        ),
        findsOneWidget,
      );
      expect(heldSave().onPressed, isNull, reason: 'the part has no name yet');
      expect(
        find.text('Saves with the part'),
        findsNothing,
        reason: 'the button takes the note\'s place',
      );

      // The same rule as the part row's Save: on once its cells are filled.
      final group = def.groupColumn!;
      final trunk = sheet.options.firstWhere((o) => o.columnId == group.id);
      sheet.updateValue(
        group.id,
        CellValue(
          columnId: group.id,
          optionId: trunk.id,
          optionLabel: trunk.label,
        ),
      );
      final type = def.columns.firstWhere((c) => c.parentId == group.id);
      final kind = sheet.options.firstWhere(
        (o) => o.columnId == type.id && o.parentOptionId == trunk.id,
      );
      sheet.updateValue(
        type.id,
        CellValue(
          columnId: type.id,
          optionId: kind.id,
          optionLabel: kind.label,
        ),
      );
      final name = def.itemColumn!;
      sheet.updateValue(
        name.id,
        CellValue(columnId: name.id, optionLabel: 'Patti', isNew: true),
      );
      await tester.pump();
      expect(heldSave().onPressed, isNotNull);
      expect(
        tester
            .widget<AppButton>(find.byKey(const ValueKey('row_save_0')))
            .onPressed,
        isNotNull,
      );
      expect(
        find.byTooltip('Save the part, and this die with it'),
        findsOneWidget,
      );
    });

    testWidgets(
      'each saved part row has a photo; a new row waits for its save',
      (tester) async {
        final photos = EntityPhotosProvider(
          repository: EntityPhotoRepository(
            baseUrl: '',
            useMockResponses: true,
          ),
        );
        addTearDown(photos.dispose);
        final patti = _item(id: 500, name: 'Patti', groupId: 11);
        await _pumpScreen(
          tester,
          initialItems: [patti],
          repository: _FakeItemRepository([patti]),
          size: const Size(1700, 3200),
          photos: photos,
        );
        expect(
          find.byKey(const ValueKey<String>('photo-item-500')),
          findsOneWidget,
        );

        // A click opens the part's gallery: its views, up to five.
        await tester.tap(find.byKey(const ValueKey<String>('photo-item-500')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byKey(const ValueKey<String>('part_photo_gallery')),
          findsOneWidget,
        );
        expect(find.text('Photos of Patti'), findsOneWidget);
        expect(find.text('0 of 5'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey<String>('gallery_close')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byKey(const ValueKey<String>('part_photo_gallery')),
          findsNothing,
        );

        await tester.tap(find.text('Add part').first);
        await tester.pump();
        expect(
          find.byTooltip('Save the part to add its photos'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'raw material open: the photo is big on the line; rolled up: the photos fill the right column',
      (tester) async {
        final photos = EntityPhotosProvider(
          repository: _GalleryRepository(const [
            PartPhoto(
              id: 1,
              thumbUrl: 'http://x/t1.jpg',
              viewUrl: 'http://x/v1.jpg',
              isPrimary: true,
              position: 1,
            ),
          ]),
        );
        addTearDown(photos.dispose);
        final patti = _item(id: 500, name: 'Patti', groupId: 11);
        await _pumpScreen(
          tester,
          initialItems: [patti],
          repository: _FakeItemRepository([patti]),
          size: const Size(1700, 3200),
          photos: photos,
        );
        await tester.pump(const Duration(milliseconds: 50));
        double lineSide() => tester
            .getSize(find.byKey(const ValueKey<String>('photo-item-500')).first)
            .width;

        expect(
          find.byKey(const ValueKey('part_showcase_photo_0')),
          findsOneWidget,
        );
        expect(lineSide(), greaterThan(120));
        expect(find.byType(MasterDataPanel), findsOneWidget);

        // Into the line: the photo stays on it, big, and raw material stays open.
        final sheet = tester
            .widget<PartRowsForm>(find.byType(PartRowsForm))
            .sheet;
        sheet.focusCell(
          PartRowsForm.lineColumns(sheet.sheetDef).first.id,
          row: 0,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          find.byKey(const ValueKey('part_showcase_photo_0')),
          findsOneWidget,
        );
        expect(lineSide(), greaterThan(120));
        expect(find.byType(MasterDataPanel), findsOneWidget);
        expect(
          find.byKey(const ValueKey('part_photos_section')),
          findsNothing,
          reason: 'never both in the right column',
        );

        // Raw material rolled up: the photos fill the right column, the line
        // keeps a small one.
        await tester.tap(find.byKey(const ValueKey('raw_roll')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(MasterDataPanel), findsNothing);
        expect(
          find.byType(MasterDataPanel, skipOffstage: false),
          findsOneWidget,
          reason: 'kept, not drawn',
        );
        expect(
          find.byKey(const ValueKey('part_photos_section')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('part_photos_thumb_1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('part_showcase_photo_0')),
          findsNothing,
        );
        expect(lineSide(), 48);

        // Down again: the photos go back to the line, big.
        await tester.tap(find.byKey(const ValueKey('raw_roll')));
        await tester.pump();
        expect(find.byType(MasterDataPanel), findsOneWidget);
        expect(find.byKey(const ValueKey('part_photos_section')), findsNothing);
        expect(
          find.byKey(const ValueKey('part_showcase_photo_0')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'the die and machine forms\' headings sit in their sections\' title bars',
      (tester) async {
        final patti = _item(id: 500, name: 'Patti', groupId: 11);
        await _pumpScreen(
          tester,
          initialItems: [patti],
          repository: _FakeItemRepository([patti]),
          size: const Size(1700, 3200),
        );
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump();
        for (final (key, title, section, start) in [
          (
            'die_heading',
            'Die Process Master',
            'die_master',
            'New die for part code: ',
          ),
          (
            'machine_heading',
            'Machines & Routing',
            'machine_master',
            'New machine for part code: ',
          ),
        ]) {
          final heading = find.byKey(ValueKey<String>(key));
          expect(
            heading,
            findsOneWidget,
            reason: '$title shows its form\'s heading',
          );
          final chip = tester.widget<Text>(
            find.descendant(of: heading, matching: find.byType(Text)),
          );
          expect(
            chip.textSpan!.toPlainText(),
            startsWith(start),
            reason: 'a chip, as the part code is',
          );
          expect(
            find.textContaining(start, findRichText: true),
            findsOneWidget,
            reason: 'drawn once, not also in the form',
          );
          // The section's own title bar: its fold button is in it.
          final bar = tester.getCenter(
            find.byKey(ValueKey<String>('section_toggle_$section')),
          );
          expect(
            tester.getCenter(heading).dy,
            closeTo(bar.dy, 6),
            reason: 'in the $title title bar',
          );
          expect(tester.getCenter(heading).dx, greaterThan(bar.dx));
          // Lined up under Item Master's "Part code" chip, right edge on
          // right edge — not ragged against each bar's own buttons.
          final partCode = find
              .ancestor(
                of: find.text('Part code: '),
                matching: find.byType(Container),
              )
              .first;
          expect(
            tester.getTopRight(heading).dx,
            closeTo(tester.getTopRight(partCode).dx, 1),
            reason: '$title under the part code',
          );
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a new part\'s photos say they come with its save', (
      tester,
    ) async {
      final photos = EntityPhotosProvider(
        repository: EntityPhotoRepository(baseUrl: '', useMockResponses: true),
      );
      addTearDown(photos.dispose);
      await _pumpScreen(tester, size: const Size(1700, 3200), photos: photos);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('part_showcase_photo_0')),
          matching: find.byTooltip('Save the part to add its photos'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('raw edits not saved are never rolled away by the part line', (
      tester,
    ) async {
      final patti = _item(id: 500, name: 'Patti', groupId: 11);
      await _pumpScreen(
        tester,
        initialItems: [patti],
        repository: _FakeItemRepository([patti]),
        size: const Size(1700, 3200),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey('master-data-edit')));
      await tester.pump();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('sheet-width')),
          matching: find.byType(EditableText),
        ),
        '48',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('raw_unsaved')), findsOneWidget);

      final sheet = tester
          .widget<PartRowsForm>(find.byType(PartRowsForm))
          .sheet;
      sheet.focusCell(
        PartRowsForm.lineColumns(sheet.sheetDef).first.id,
        row: 0,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.byType(MasterDataPanel),
        findsOneWidget,
        reason: 'what was typed stays in view',
      );
    });

    testWidgets(
      'part code appears before time&date stamp, and camera photo sits above save',
      (tester) async {
        final photos = EntityPhotosProvider(
          repository: EntityPhotoRepository(
            baseUrl: '',
            useMockResponses: true,
          ),
        );
        addTearDown(photos.dispose);
        await _pumpScreen(
          tester,
          repository: _FakeItemRepository([]),
          size: const Size(1700, 3200),
          photos: photos,
        );
        // 1. Part code chip is placed before the time & date stamp
        final codeChip = tester.getRect(find.textContaining('Part code:'));
        final stampChip = tester.getRect(
          find.byKey(const ValueKey('part_heading_stamp')),
        );
        expect(
          codeChip.bottom <= stampChip.top || codeChip.right <= stampChip.left,
          isTrue,
          reason: 'Part code is ordered before time&date stamp',
        );

        // 2. Camera photo button sits above the Save part button
        final photo = tester.getRect(
          find.byKey(const ValueKey('photo-item-none')),
        );
        final save = tester.getRect(find.byKey(const ValueKey('row_save_0')));
        expect(
          photo.bottom,
          lessThan(save.top),
          reason: 'Camera photo is positioned above save part',
        );
        expect(
          photo.left,
          lessThanOrEqualTo(save.left + 5),
          reason: 'Camera photo aligns with save part',
        );
      },
    );

    testWidgets('each die and machine on the part has its photo', (
      tester,
    ) async {
      // The lists show only where dies and machines can be made.
      AppFlowHooks.createDieFromSheet = (context, draft) async =>
          throw UnimplementedError();
      AppFlowHooks.createMachineFromSheet = (context, draft) async =>
          throw UnimplementedError();
      addTearDown(() {
        AppFlowHooks.createDieFromSheet = null;
        AppFlowHooks.createMachineFromSheet = null;
      });
      final photos = EntityPhotosProvider(
        repository: EntityPhotoRepository(baseUrl: '', useMockResponses: true),
      );
      addTearDown(photos.dispose);
      final patti = _item(
        id: 500,
        name: 'Patti',
        groupId: 11,
        dies: const [ItemDieLink(id: '31', toolCode: 'PGESP1')],
        machines: const [ItemMachineLink(id: '41', name: 'Press 1')],
      );
      await _pumpScreen(
        tester,
        initialItems: [patti],
        repository: _FakeItemRepository([patti]),
        size: const Size(1700, 3200),
        photos: photos,
      );
      expect(
        find.byKey(const ValueKey<String>('photo-die-31')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('photo-machine-41')),
        findsOneWidget,
      );
      // A bare camera at the start of the row went unnoticed; the empty slot
      // says what it is for.
      for (final key in ['photo-die-31', 'photo-machine-41']) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey<String>(key)),
            matching: find.text('Photo'),
          ),
          findsOneWidget,
          reason: '$key should be labelled',
        );
      }
      // Edited as a part line and a person are: an Edit said in words.
      for (final row in [
        'quick-entry-die-row-31',
        'quick-entry-machine-row-41',
      ]) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey<String>(row)),
            matching: find.widgetWithText(OutlinedButton, 'Edit'),
          ),
          findsOneWidget,
          reason: '$row should carry the same Edit as a part line',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the photo gutter fits a 1366px window', (tester) async {
      final photos = EntityPhotosProvider(
        repository: EntityPhotoRepository(baseUrl: '', useMockResponses: true),
      );
      addTearDown(photos.dispose);
      final patti = _item(id: 500, name: 'Patti', groupId: 11);
      await _pumpScreen(
        tester,
        initialItems: [patti],
        repository: _FakeItemRepository([patti]),
        size: const Size(1366, 900),
        photos: photos,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a die changed anywhere re-reads the open part (real time)', (
      tester,
    ) async {
      // The server announces a die edit on every part that uses it
      // (migration 060). That part is fetched from the server — not re-read
      // from the local replica, which has not applied the change yet.
      final patti = _item(id: 500, name: 'Patti', groupId: 11);
      final repo = _FakeItemRepository([patti]);
      await _pumpScreen(
        tester,
        initialItems: [patti],
        repository: repo,
        live: true,
      );

      final data = jsonEncode({
        'table_name': 'items',
        'record_id': 500,
        'event_type': 'UPDATE',
      });
      await tester.runAsync(() async {
        SocketService.instance.processEventForTest(
          'event: table-change\ndata: $data',
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      expect(
        repo.freshReads,
        contains(500),
        reason: 'the part is fetched fresh',
      );
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

    testWidgets(
      'the people table is drawn before a company, disabled with why',
      (tester) async {
        // Hidden until a company is chosen would read as "this sheet has no
        // people" — drawn disabled, it says what it is waiting for.
        await _pumpScreen(tester);
        await tester.tap(find.text('Client').first);
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
      },
    );

    testWidgets('the part stays pinned across a switch', (tester) async {
      // Switching to Dies must keep saying which part they belong to.
      await _pumpScreen(tester);
      expect(find.text('NEW RECORD'), findsOneWidget);

      await tester.tap(find.text('Die Process Master').first);
      await tester.pump();

      expect(find.text('NEW RECORD'), findsOneWidget);
      expect(find.text('Unnamed'), findsWidgets);
    });

    testWidgets('a part code is "assigned on save", not a made-up one', (
      tester,
    ) async {
      await _pumpScreen(tester);
      // The prototype printed `activeItem?.variantCode ?? 'SADPB2248'`.
      expect(find.text('assigned on save'), findsOneWidget);
      expect(find.textContaining('SADPB2248'), findsNothing);
    });

    testWidgets(
      'Author route opens before a save, and says the part comes next',
      (tester) async {
        await _pumpScreen(tester);
        await tester.tap(find.text('Machines & Routing').first);
        await tester.pump();

        expect(
          find.textContaining('Save the part to attach a route'),
          findsOneWidget,
        );
        final button = tester.widget<AppButton>(
          find
              .ancestor(
                of: find.text('Author route'),
                matching: find.byType(AppButton),
              )
              .first,
        );
        expect(
          button.onPressed,
          isNotNull,
          reason:
              'stages can be laid out first; the part attaches when it is saved',
        );
      },
    );

    testWidgets('unticking the external box hides the party section but keeps '
        'its draft', (tester) async {
      await _pumpScreen(tester);
      expect(find.text('Client'), findsWidgets);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      expect(
        find.text('Client'),
        findsNothing,
        reason: 'an in-house part has no development deal to record',
      );
    });

    testWidgets('a sitting is open while the screen is, and closed after', (
      tester,
    ) async {
      expect(SittingScope.current, isNull);
      await _pumpScreen(tester);
      final sitting = SittingScope.current;
      expect(sitting, isNotNull);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      expect(SittingScope.current, isNull);
    });

    testWidgets('opening an existing part loads it into the sheet', (
      tester,
    ) async {
      final patti = _item(id: 500, name: 'Patti', groupId: 11);
      await _pumpScreen(tester, initialItems: [patti], stored: [patti]);

      expect(find.text('Patti'), findsWidgets);
      expect(find.textContaining('SAVED #500'), findsOneWidget);
    });

    testWidgets(
      'the row\'s one Save sits at its end and waits for the required cells',
      (tester) async {
        await _pumpScreen(tester, size: const Size(1600, 3200));
        AppButton save() =>
            tester.widget<AppButton>(find.byKey(const ValueKey('row_save_0')));
        final strip = tester.widget<PartRowsForm>(find.byType(PartRowsForm));
        final sheet = strip.sheet;
        final def = strip.sheet.sheetDef;

        // One Save per row: the gutter carries status, not a second button.
        expect(find.byKey(const ValueKey('row_save_0')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('row_save_0')),
            matching: find.text('Save part'),
          ),
          findsOneWidget,
        );
        expect(save().onPressed, isNull);

        // A name but no group: still disabled, and it says what is missing.
        final name = def.itemColumn!;
        sheet.updateValue(
          name.id,
          CellValue(columnId: name.id, optionLabel: 'Patti', isNew: true),
        );
        await tester.pump();
        expect(save().onPressed, isNull);
        final missing = sheet.errorsForRow(0).values.first.message;
        expect(find.byTooltip(missing), findsOneWidget);

        // The company line's Save waits for the same part.
        final form = tester.widget<DealPeopleForm>(find.byType(DealPeopleForm));
        final partyColumn = form.controller.clientVendorController.sheetDef
            .columnBoundTo(SheetBindsTo.developedForParty)!;
        form.controller.clientVendorController.updateValue(
          partyColumn.id,
          CellValue(
            columnId: partyColumn.id,
            refId: 5,
            optionLabel: 'Gold Medal',
          ),
        );
        await tester.pump();
        AppButton dealSave() =>
            tester.widget<AppButton>(find.byKey(const ValueKey('deal_save')));
        expect(
          dealSave().onPressed,
          isNull,
          reason: 'the part row still misses a required cell',
        );

        // Fill the group and its type: both Saves come on.
        final group = def.groupColumn!;
        final trunk = sheet.options.firstWhere((o) => o.columnId == group.id);
        sheet.updateValue(
          group.id,
          CellValue(
            columnId: group.id,
            optionId: trunk.id,
            optionLabel: trunk.label,
          ),
        );
        // Type sits between them: Part Name asks for it first.
        final type = def.columns.firstWhere((c) => c.parentId == group.id);
        final kind = sheet.options.firstWhere(
          (o) => o.columnId == type.id && o.parentOptionId == trunk.id,
        );
        sheet.updateValue(
          type.id,
          CellValue(
            columnId: type.id,
            optionId: kind.id,
            optionLabel: kind.label,
          ),
        );
        await tester.pump();
        expect(sheet.errorsForRow(0), isEmpty);
        expect(save().onPressed, isNotNull);
        expect(dealSave().onPressed, isNotNull);
      },
    );

    testWidgets(
      'a saved row\'s end button is Edit, and Edit turns it back into Save',
      (tester) async {
        final patti = _item(id: 500, name: 'Patti', groupId: 11);
        final repo = _FakeItemRepository([patti]);
        await _pumpScreen(tester, initialItems: [patti], repository: repo);

        expect(
          find.byKey(const ValueKey('row_saved_0')),
          findsOneWidget,
          reason: 'the gutter says it is saved',
        );
        final edit = find.byKey(const ValueKey('row_edit_0'));
        expect(edit, findsOneWidget);
        expect(find.byKey(const ValueKey('row_save_0')), findsNothing);

        await tester.tap(edit);
        await tester.pump();
        final save = tester.widget<AppButton>(
          find.byKey(const ValueKey('row_save_0')),
        );
        expect(save.onPressed, isNotNull);
        expect(find.byTooltip('Save the changes to this part'), findsOneWidget);
      },
    );

    testWidgets('a part deleted elsewhere offers no Edit, and says why', (
      tester,
    ) async {
      // Made for a client, so the company line (and its controller) is drawn.
      final patti = _item(
        id: 500,
        name: 'Patti',
        groupId: 11,
        developedFor: const DevelopedFor(
          kind: DevelopedForKind.client,
          clientId: 5,
          companyName: 'Gold Medal',
        ),
      );
      final repo = _FakeItemRepository([patti]);
      await _pumpScreen(
        tester,
        initialItems: [patti],
        repository: repo,
        size: const Size(1600, 3200),
      );
      final controller = tester
          .widget<DealPeopleForm>(
            find.byType(DealPeopleForm, skipOffstage: false),
          )
          .controller;

      controller.refreshLockedRows([
        _item(id: 501, name: 'Dabbi', groupId: 11),
      ]);
      await tester.pump();

      expect(find.byKey(const ValueKey('row_gone_0')), findsOneWidget);
      final edit = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('row_edit_0')),
      );
      expect(edit.onPressed, isNull);
      expect(find.byTooltip(controller.rowError(0)!), findsWidgets);
    });
  });

  group('the keyboard: Tab through what is typed, then a save prompt', () {
    final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

    /// The key of the field (or form) holding focus: `cell_item_0_3`,
    /// `deal_company`, `deal_quotation`, …
    bool focusIn(Key key) {
      final context = FocusManager.instance.primaryFocus?.context;
      if (context == null) return false;
      var found = false;
      context.visitAncestorElements((element) {
        if (element.widget.key == key) found = true;
        return !found;
      });
      return found;
    }

    bool focusInRaw() => focusIn(const ValueKey('raw_step'));
    bool focusInRouting() => focusIn(const ValueKey('routing_step'));

    String? focusedField() {
      final context = FocusManager.instance.primaryFocus?.context;
      if (context == null) return null;
      String? found;
      bool visit(Element element) {
        final key = element.widget.key;
        if (key is ValueKey<String> &&
            (key.value.startsWith('cell_item_') ||
                key.value.startsWith('thickness_unit_') ||
                key.value.startsWith('deal_') ||
                key.value.startsWith('quick-entry-'))) {
          found = key.value;
          return false;
        }
        return true;
      }

      if (context is Element) visit(context);
      context.visitAncestorElements(visit);
      return found;
    }

    /// A dropdown's list is open (its search box is on screen).
    bool listOpen() =>
        find
            .byKey(const ValueKey<String>('option_picker_search'))
            .evaluate()
            .isNotEmpty ||
        find
            .byKey(const ValueKey<String>('searchable_select_search'))
            .evaluate()
            .isNotEmpty;

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<SheetController> openNew(
      WidgetTester tester, {
      _FakeItemRepository? repo,
    }) async {
      await _pumpScreen(
        tester,
        repository: repo ?? _FakeItemRepository([]),
        size: const Size(1700, 3200),
      );
      await tester.pump(const Duration(milliseconds: 50));
      return tester.widget<PartRowsForm>(find.byType(PartRowsForm)).sheet;
    }

    void fillLine(SheetController sheet, {int row = 0, String name = 'Lid'}) {
      final def = sheet.sheetDef;
      final group = def.groupColumn!;
      final trunk = sheet.options.firstWhere((o) => o.columnId == group.id);
      sheet.updateValue(
        group.id,
        CellValue(
          columnId: group.id,
          optionId: trunk.id,
          optionLabel: trunk.label,
        ),
        row: row,
      );
      final type = def.columns.firstWhere((c) => c.parentId == group.id);
      final kind = sheet.options.firstWhere(
        (o) => o.columnId == type.id && o.parentOptionId == trunk.id,
      );
      sheet.updateValue(
        type.id,
        CellValue(
          columnId: type.id,
          optionId: kind.id,
          optionLabel: kind.label,
        ),
        row: row,
      );
      final nameColumn = def.itemColumn!;
      sheet.updateValue(
        nameColumn.id,
        CellValue(columnId: nameColumn.id, optionLabel: name, isNew: true),
        row: row,
      );
    }

    List<String> lineKeys(SheetController sheet, {int row = 0}) => [
      for (final column in PartRowsForm.lineColumns(sheet.sheetDef))
        'cell_item_${row}_${column.id}',
    ];

    testWidgets(
      'the sheet opens on Group, and Tab visits the line\'s fields only',
      (tester) async {
        final sheet = await openNew(tester);
        // Thickness is a number and its unit: two stops.
        final thickness = sheet.sheetDef.columns.firstWhere(
          (c) => c.kind == ColumnKind.gauge,
        );
        final keys = [
          for (final key in lineKeys(sheet)) ...[
            key,
            if (key == 'cell_item_0_${thickness.id}') 'thickness_unit_0',
          ],
        ];
        expect(
          focusedField(),
          keys.first,
          reason: 'the keyboard starts on Group',
        );
        expect(listOpen(), isFalse, reason: 'opening the sheet opens no list');
        // A dropdown Tab lands on opens, and Tab in its list goes on: the fields
        // are recorded as focus passes through them.
        final visited = <String>[keys.first];
        void record() {
          final field = focusedField();
          if (field != null && visited.last != field) visited.add(field);
        }

        FocusManager.instance.addListener(record);
        addTearDown(() => FocusManager.instance.removeListener(record));
        for (var i = 1; i < keys.length; i += 1) {
          await press(tester, LogicalKeyboardKey.tab);
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(
          visited,
          keys,
          reason: 'no photo, Auto pill, property icon, Save or × in between',
        );
      },
      variant: desktop,
    );

    testWidgets(
      'the line is four even columns, and the heading says when the part was made',
      (tester) async {
        // Wide enough for four: a narrower line reads two at a time (EvenGrid).
        await _pumpScreen(
          tester,
          repository: _FakeItemRepository([]),
          size: const Size(2400, 1600),
        );
        await tester.pump(const Duration(milliseconds: 50));
        final sheet = tester
            .widget<PartRowsForm>(find.byType(PartRowsForm))
            .sheet;
        final def = sheet.sheetDef;
        Rect cell(String binds) => tester.getRect(
          find.byKey(ValueKey('cell_item_0_${def.columnBoundTo(binds)!.id}')),
        );
        final group = cell(SheetBindsTo.group);
        final code = cell(SheetBindsTo.partCode);
        final alloy = cell(SheetBindsTo.variation('Alloy'));
        final number = cell(SheetBindsTo.partNo);
        expect(cell(SheetBindsTo.set).bottom, group.bottom);
        expect(cell(SheetBindsTo.name).bottom, group.bottom);
        expect(
          code.bottom,
          group.bottom,
          reason: 'Part Code ends the first row',
        );
        expect(alloy.left, group.left, reason: 'Alloy is under Group');
        expect(number.left, code.left, reason: 'Part No is under Part Code');
        expect(
          number.bottom,
          alloy.bottom,
          reason: 'Part No ends the second row',
        );
        expect(alloy.width, group.width);
        expect(code.width, group.width);

        // Not saved yet: the heading shows the time now, for the save to stamp.
        final stamp = find.byKey(const ValueKey('part_heading_stamp'));
        expect(
          find.descendant(
            of: stamp,
            matching: find.text(partStampDate(DateTime.now())),
          ),
          findsOneWidget,
        );

        sheet.markRowSaved(
          0,
          42,
          createdDate: '15/05/2026',
          createdTime: '10.05 AM',
        );
        await tester.pump();
        expect(
          find.descendant(of: stamp, matching: find.text('15/05/2026')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: stamp, matching: find.text('10.05 AM')),
          findsOneWidget,
        );
      },
      variant: desktop,
    );

    testWidgets(
      'a dropdown Tab lands on opens; Tab in it keeps the value and goes on',
      (tester) async {
        final sheet = await openNew(tester);
        fillLine(sheet);
        await tester.pump();
        final columns = PartRowsForm.lineColumns(sheet.sheetDef);
        final type = sheet.sheetDef.columns.firstWhere(
          (c) => c.parentId == sheet.sheetDef.groupColumn!.id,
        );
        final typeBefore = sheet.draftAt(0).get(type.id)?.optionId;
        expect(typeBefore, isNotNull);

        // Group (focused as the sheet opens) → Tab → Type, open.
        await press(tester, LogicalKeyboardKey.tab);
        await tester.pump(const Duration(milliseconds: 300));
        expect(listOpen(), isTrue, reason: 'Tab onto Type opens its list');

        // A bare Enter keeps what the line has, rather than taking the first row.
        await press(tester, LogicalKeyboardKey.enter);
        await tester.pump(const Duration(milliseconds: 300));
        expect(listOpen(), isFalse);
        expect(sheet.draftAt(0).get(type.id)?.optionId, typeBefore);
        expect(
          focusedField(),
          'cell_item_0_${type.id}',
          reason: 'the pick keeps focus on the box',
        );
        // Focus coming back after a pick does not reopen it.
        await tester.pump(const Duration(milliseconds: 300));
        expect(listOpen(), isFalse);

        // Tab from the closed box: the next box opens; Tab in its list closes
        // it as it was and goes on to the one after.
        await press(tester, LogicalKeyboardKey.tab);
        await tester.pump(const Duration(milliseconds: 300));
        expect(listOpen(), isTrue, reason: 'Part Name opens on arrival');
        await press(tester, LogicalKeyboardKey.tab);
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          sheet.draftAt(0).get(sheet.sheetDef.itemColumn!.id)?.optionLabel,
          'Lid',
        );
        expect(focusedField(), 'cell_item_0_${columns[3].id}');

        // Shift+Tab walks back past a dropdown without opening it.
        if (listOpen()) {
          await press(tester, LogicalKeyboardKey.escape);
          await tester.pump(const Duration(milliseconds: 300));
        }
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await press(tester, LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump(const Duration(milliseconds: 300));
        expect(focusedField(), 'cell_item_0_${sheet.sheetDef.itemColumn!.id}');
        expect(listOpen(), isFalse, reason: 'going back opens nothing');
      },
      variant: desktop,
    );

    testWidgets(
      'Tab past the last field asks; Save writes the line and goes on to client',
      (tester) async {
        final repo = _FakeItemRepository([]);
        final sheet = await openNew(tester, repo: repo);
        fillLine(sheet);
        await tester.pump();
        sheet.focusCell(
          PartRowsForm.lineColumns(sheet.sheetDef).last.id,
          row: 0,
        );
        await tester.pump();
        await press(tester, LogicalKeyboardKey.tab);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Save part 1?'), findsOneWidget);

        await tester.runAsync(() async {
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(repo.created, hasLength(1), reason: 'Save wrote the part');
        expect(
          focusedField(),
          'deal_company',
          reason: 'and the keyboard went to client',
        );
      },
      variant: desktop,
    );

    testWidgets(
      'Tab sequence is item master -> client -> die -> machines -> routing -> raw material',
      (tester) async {
        AppFlowHooks.createDieFromSheet = (context, draft) async =>
            const DieCreateOutcome.created(
              CreatedRecord(id: '31', title: 'Die 31'),
            );
        AppFlowHooks.createMachineFromSheet = (context, draft) async =>
            const MachineCreateOutcome.created(
              CreatedRecord(id: '41', title: 'Machine 41'),
            );
        addTearDown(() {
          AppFlowHooks.createDieFromSheet = null;
          AppFlowHooks.createMachineFromSheet = null;
        });

        final repo = _FakeItemRepository([]);
        final sheet = await openNew(tester, repo: repo);
        fillLine(sheet);
        await tester.pump();
        sheet.focusCell(
          PartRowsForm.lineColumns(sheet.sheetDef).last.id,
          row: 0,
        );
        await tester.pump();
        await press(tester, LogicalKeyboardKey.tab);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Save part 1?'), findsOneWidget);

        await tester.runAsync(() async {
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // 1. After saving item master, Tab goes to Client (NOT raw material)
        expect(focusedField(), 'deal_company');

        // 2. Client -> Die Process Master
        await press(tester, LogicalKeyboardKey.tab);
        await tester.pump(const Duration(milliseconds: 300));
        if (listOpen()) {
          await press(tester, LogicalKeyboardKey.tab);
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(focusedField(), 'deal_quotation');
        for (
          var i = 0;
          i < 10 && focusedField() != 'quick-entry-die-type';
          i += 1
        ) {
          await press(tester, LogicalKeyboardKey.tab);
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(focusedField(), 'quick-entry-die-type');

        // 3. Die Process Master -> Machines
        for (
          var i = 0;
          i < 15 && focusedField() != 'quick-entry-die-date-in-field';
          i += 1
        ) {
          await press(tester, LogicalKeyboardKey.tab);
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(focusedField(), 'quick-entry-die-date-in-field');

        // Tab from last die field arrives at Machine Type (dropdown opens on arrival)
        await press(tester, LogicalKeyboardKey.tab);
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          listOpen(),
          isTrue,
          reason: 'Machine Type dropdown opens on arrival',
        );
        await press(tester, LogicalKeyboardKey.escape);
        await tester.pump(const Duration(milliseconds: 200));
        expect(focusedField(), 'quick-entry-machine-type-field');

        // 4. Machines -> Routing
        for (var i = 0; i < 20 && !focusInRouting(); i += 1) {
          await press(tester, LogicalKeyboardKey.tab);
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(
          focusInRouting(),
          isTrue,
          reason: 'Tab reaches routing after machines',
        );

        // 5. Routing -> Raw material
        for (var i = 0; i < 15 && !focusInRaw(); i += 1) {
          await press(tester, LogicalKeyboardKey.tab);
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(
          focusInRaw(),
          isTrue,
          reason: 'Tab reaches raw material after routing',
        );
      },
      variant: desktop,
    );

    testWidgets('Discard empties a new line; Esc stays on it', (tester) async {
      final sheet = await openNew(tester);
      fillLine(sheet);
      final last = PartRowsForm.lineColumns(sheet.sheetDef).last.id;
      sheet.focusCell(last, row: 0);
      await tester.pump();

      await press(tester, LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Save part 1?'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Save part 1?'), findsNothing);
      expect(focusedField(), 'cell_item_0_$last', reason: 'Esc keeps typing');

      await press(tester, LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('step_discard')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(sheet.isRowBlank(0), isTrue, reason: 'Discard put the line back');
      expect(focusedField(), 'deal_company');
    }, variant: desktop);

    testWidgets('an unchanged saved line is passed without asking', (
      tester,
    ) async {
      final patti = _item(id: 500, name: 'Patti', groupId: 11);
      await _pumpScreen(
        tester,
        initialItems: [patti],
        repository: _FakeItemRepository([patti]),
        size: const Size(1700, 3200),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final sheet = tester
          .widget<PartRowsForm>(find.byType(PartRowsForm))
          .sheet;
      sheet.focusCell(PartRowsForm.lineColumns(sheet.sheetDef).last.id, row: 0);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('step_save_dialog')), findsNothing);
      for (
        var i = 0;
        i < 20 && find.textContaining('End of the sheet').evaluate().isEmpty;
        i += 1
      ) {
        await press(tester, LogicalKeyboardKey.tab);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.textContaining('End of the sheet'), findsOneWidget);
    }, variant: desktop);

    testWidgets('Enter on a saved line opens it for editing', (tester) async {
      final patti = _item(id: 500, name: 'Patti', groupId: 11);
      await _pumpScreen(
        tester,
        initialItems: [patti],
        repository: _FakeItemRepository([patti]),
        size: const Size(1700, 3200),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final sheet = tester
          .widget<PartRowsForm>(find.byType(PartRowsForm))
          .sheet;
      expect(sheet.isRowLocked(0), isTrue);
      sheet.focusCell(
        PartRowsForm.lineColumns(sheet.sheetDef).first.id,
        row: 0,
      );
      await tester.pump();
      await press(tester, LogicalKeyboardKey.enter);
      expect(sheet.isRowLocked(0), isFalse);
    }, variant: desktop);

    testWidgets('Ctrl+Enter saves the line and opens the next one', (
      tester,
    ) async {
      final repo = _FakeItemRepository([]);
      final sheet = await openNew(tester, repo: repo);
      fillLine(sheet);
      sheet.focusCell(PartRowsForm.lineColumns(sheet.sheetDef)[2].id, row: 0);
      await tester.pump();
      await tester.runAsync(() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.created, hasLength(1));
      expect(sheet.rowCount, 2);
      expect(
        focusedField(),
        lineKeys(sheet, row: 1).first,
        reason: 'on the new line\'s Group',
      );
    }, variant: desktop);

    testWidgets(
      'a pick by keyboard leaves focus on the box, and Tab reaches the prompt',
      (tester) async {
        final sheet = await openNew(tester);
        expect(focusedField(), lineKeys(sheet).first);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS, character: 's');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(sheet.draftAt(0).get(1)?.optionLabel, 'Switch Action');
        expect(
          focusedField(),
          lineKeys(sheet).first,
          reason: 'back on Group after the pick',
        );
        final seen = <String?>[];
        for (
          var i = 0;
          i < 12 &&
              find.byKey(const ValueKey('step_save_dialog')).evaluate().isEmpty;
          i += 1
        ) {
          await press(tester, LogicalKeyboardKey.tab);
          await tester.pump(const Duration(milliseconds: 100));
          seen.add(focusedField());
        }
        expect(
          find.byKey(const ValueKey('step_save_dialog')),
          findsOneWidget,
          reason: 'went $seen',
        );
      },
      variant: desktop,
    );

    testWidgets(
      'a new part name added by keyboard, then Tab on to the prompt',
      (tester) async {
        final sheet = await openNew(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS, character: 's');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump(const Duration(milliseconds: 300));
        await press(tester, LogicalKeyboardKey.tab);
        await press(tester, LogicalKeyboardKey.tab);
        expect(focusedField(), lineKeys(sheet)[2]);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyL, character: 'l');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(find.byType(TextField).last, 'Lid Ninety');
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump(const Duration(milliseconds: 300));
        expect(sheet.draftAt(0).get(3)?.optionLabel, 'Lid Ninety');
        final seen = <String?>[];
        for (
          var i = 0;
          i < 12 &&
              find.byKey(const ValueKey('step_save_dialog')).evaluate().isEmpty;
          i += 1
        ) {
          await press(tester, LogicalKeyboardKey.tab);
          await tester.pump(const Duration(milliseconds: 100));
          seen.add(focusedField());
        }
        expect(
          find.byKey(const ValueKey('step_save_dialog')),
          findsOneWidget,
          reason: 'went $seen',
        );
      },
      variant: desktop,
    );

    testWidgets(
      'a number typed in Thickness is a gauge; the unit beside it changes that',
      (tester) async {
        final sheet = await openNew(tester);
        final thickness = sheet.sheetDef.columns.firstWhere(
          (c) => c.kind == ColumnKind.gauge,
        );
        final box = find.descendant(
          of: find.byKey(ValueKey('cell_item_0_${thickness.id}')),
          matching: find.byType(TextField),
        );
        await tester.enterText(box, '23');
        await tester.pump();
        expect(sheet.draftAt(0).get(thickness.id)?.optionLabel, '23 Gauge');

        // mm from the unit beside it: the number stays, the unit says what it is.
        await tester.tap(find.byKey(const ValueKey('thickness_unit_0')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, 'mm');
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(sheet.draftAt(0).get(thickness.id)?.optionLabel, '23 mm');

        await tester.enterText(box, '1.2');
        await tester.pump();
        expect(sheet.draftAt(0).get(thickness.id)?.optionLabel, '1.2 mm');
      },
      variant: desktop,
    );

    testWidgets('Shift+Tab goes back without asking', (tester) async {
      final sheet = await openNew(tester);
      fillLine(sheet);
      final keys = lineKeys(sheet);
      sheet.focusCell(PartRowsForm.lineColumns(sheet.sheetDef)[1].id, row: 0);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await press(tester, LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(focusedField(), keys.first);
      expect(find.byKey(const ValueKey('step_save_dialog')), findsNothing);
    }, variant: desktop);

    testWidgets('the company line: Company, Quotation, then its prompt', (
      tester,
    ) async {
      await openNew(tester);
      final form = tester.widget<DealPeopleForm>(find.byType(DealPeopleForm));
      final party = form.controller.clientVendorController.sheetDef
          .columnBoundTo(SheetBindsTo.developedForParty)!;
      form.controller.clientVendorController.updateValue(
        party.id,
        CellValue(columnId: party.id, refId: 5, optionLabel: 'Gold Medal'),
      );
      await tester.pump();
      // Into the company step from the part line's end.
      form.flow!.focusStep(DealPeopleForm.companyStep);
      await tester.pump();
      await tester.pump();
      expect(focusedField(), 'deal_company');
      await press(tester, LogicalKeyboardKey.tab);
      expect(focusedField(), 'deal_quotation');
      await press(tester, LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Save Gold Medal?'), findsOneWidget);
      // The part line is blank, so its Save is held back, and says why.
      expect(find.textContaining('cannot be saved yet'), findsOneWidget);
    }, variant: desktop);
  });

  group('the parts are lines, drawn like the people', () {
    testWidgets('no table headings, and no Date or Time to type', (
      tester,
    ) async {
      await _pumpScreen(tester, size: const Size(1600, 3200));
      for (final heading in [
        'Group and item',
        'Created',
        'Action',
        'Save / Edit',
      ]) {
        expect(find.text(heading), findsNothing, reason: heading);
      }
      final form = tester.widget<PartRowsForm>(find.byType(PartRowsForm));
      final stamps = form.sheet.sheetDef.columns.where((c) => c.isStamp);
      expect(stamps, isNotEmpty);
      for (final stamp in stamps) {
        expect(
          find.byKey(ValueKey('cell_item_0_${stamp.id}')),
          findsNothing,
          reason: '${stamp.label} is filled in by the save',
        );
      }
      // The line ends in its own Save, then the × — inside the part's line,
      // right of every field, however the fields wrap.
      final line = tester.getRect(find.byKey(const ValueKey('part_line_0')));
      final save = tester.getRect(find.byKey(const ValueKey('row_save_0')));
      final remove = tester.getRect(find.byKey(const ValueKey('row_remove_0')));
      expect(line.contains(save.center), isTrue);
      for (final column in form.sheet.sheetDef.columns.where(
        (c) => !c.isStamp,
      )) {
        final field = find.byKey(ValueKey('cell_item_0_${column.id}'));
        expect(
          tester.getRect(field).right,
          lessThanOrEqualTo(save.left),
          reason: column.label,
        );
      }
      expect(remove.left, greaterThanOrEqualTo(save.right));
    });

    testWidgets('a field opens the sheet\'s own picker and takes the pick', (
      tester,
    ) async {
      await _pumpScreen(tester, size: const Size(1600, 3200));
      await tester.tap(find.byKey(const ValueKey('cell_item_0_1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('Type to filter'), findsOneWidget);
      await tester.tap(find.text('Switch Action').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cell_item_0_1')),
          matching: find.text('Switch Action'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a saved line is read only and cannot be removed', (
      tester,
    ) async {
      final patti = _item(id: 500, name: 'Patti', groupId: 11);
      await _pumpScreen(
        tester,
        initialItems: [patti],
        repository: _FakeItemRepository([patti]),
        size: const Size(1600, 3200),
      );
      final form = tester.widget<PartRowsForm>(find.byType(PartRowsForm));
      final partNo = form.sheet.sheetDef.columns.firstWhere(
        (c) => c.bindsTo == SheetBindsTo.partNo,
      );
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(ValueKey('cell_item_0_${partNo.id}')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.readOnly, isTrue);
      final remove = tester.widget<IconButton>(
        find.byKey(const ValueKey('row_remove_0')),
      );
      expect(remove.onPressed, isNull);
      expect(
        find.byTooltip('Saved parts stay in the catalogue — use Archive part'),
        findsOneWidget,
      );
    });

    testWidgets(
      'a die typed on a new line does not follow the cursor to a saved part',
      (tester) async {
        final patti = _item(id: 500, name: 'Patti', groupId: 11);
        AppFlowHooks.createDieFromSheet = (context, draft) async =>
            throw UnimplementedError('not saved in this test');
        addTearDown(() => AppFlowHooks.createDieFromSheet = null);
        await _pumpScreen(
          tester,
          initialItems: [patti],
          repository: _FakeItemRepository([patti]),
          size: const Size(1700, 3200),
        );
        PartDieSection dies() =>
            tester.widget<PartDieSection>(find.byType(PartDieSection));
        // No. of Sets: measured per die, so it is what makes the form "typed".
        TextEditingController sets() => tester
            .widget<PickOrTypeField>(
              find.ancestor(
                of: find.byKey(
                  const ValueKey<String>('quick-entry-die-sets-field'),
                  skipOffstage: false,
                ),
                matching: find.byType(PickOrTypeField, skipOffstage: false),
              ),
            )
            .controller;

        await tester.tap(find.text('Add part').first);
        await tester.pump();
        expect(dies().part, isNull);
        sets().text = '4';
        await tester.pump();

        // Onto the saved part's line: that is not the new line being saved.
        await tester.tap(find.text('Patti').first);
        await tester.pump();
        expect(dies().part?.id, 500);
        expect(
          sets().text,
          isEmpty,
          reason: 'what was typed for the new line stays off Patti',
        );
      },
    );

    testWidgets('a refused line is said in the app\'s toast, not drawn red', (
      tester,
    ) async {
      await _pumpScreen(tester, size: const Size(1600, 3200));
      final sheet = tester
          .widget<PartRowsForm>(find.byType(PartRowsForm))
          .sheet;
      final name = sheet.sheetDef.itemColumn!;
      sheet.updateValue(
        name.id,
        CellValue(columnId: name.id, optionLabel: 'Patti', isNew: true),
      );
      sheet.addRow();
      await tester.pump();
      // Leaving the line writes it, and it is refused: no Group.
      await tester.runAsync(() async {
        sheet.selectRow(1);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('Part 1:'), findsOneWidget);
      // Nothing on the line is outlined red.
      final decorators = tester.widgetList<InputDecorator>(
        find.descendant(
          of: find.byKey(const ValueKey('part_line_0')),
          matching: find.byType(InputDecorator),
        ),
      );
      expect(decorators.every((d) => d.decoration.errorText == null), isTrue);
      await tester.pump(const Duration(seconds: 4));
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
          'Item Master',
          'Client',
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

/// A part's gallery, as the server would answer it.
class _GalleryRepository extends EntityPhotoRepository {
  _GalleryRepository(this.photos) : super(baseUrl: '', useMockResponses: true);

  final List<PartPhoto> photos;

  @override
  Future<List<PartPhoto>> partPhotos(String itemId) async => photos;
}
