import 'package:core_erp/features/clients/domain/party_contact.dart';
import 'package:core_erp/features/items/domain/developed_for.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/widgets/item_report.dart';
import 'package:core_erp/features/process_routes/domain/part_route.dart';
import 'package:core_erp/features/production_pipelines/domain/pen_paper_baseline.dart';
import 'package:core_erp/features/production_pipelines/presentation/widgets/raw_sheet_review.dart';
import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/item_asset.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/items/presentation/widgets/item_detail_panel.dart';
import 'package:core_erp/features/units/data/repositories/unit_repository.dart';
import 'package:core_erp/features/units/domain/unit_definition.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The item report: everything entered for a part on the item sheet, as text.

class _Items implements ItemRepository {
  _Items(this.item);
  final ItemDefinition item;
  final List<int> fresh = [];

  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async => [item];

  @override
  Future<ItemDefinition?> getItemFresh(int id) async {
    fresh.add(id);
    return item;
  }

  @override
  Future<List<ItemAsset>> getItemAssets(int itemId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Groups implements GroupRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async => [
        for (final (id, name, parent) in const [
          (10, 'Primary Group', null),
          (11, 'Brackets', 10),
        ])
          GroupDefinition(
            id: id,
            name: name,
            groupType: 'item',
            groupStructure: 'Standard',
            parentGroupId: parent,
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

class _Units implements UnitRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<UnitDefinition>> getUnits() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ItemVariationNodeDefinition _property(int id, String name, String value) =>
    ItemVariationNodeDefinition(
      id: id,
      itemId: 500,
      parentNodeId: null,
      kind: ItemVariationNodeKind.property,
      name: name,
      displayName: name,
      position: 0,
      isArchived: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      children: [
        ItemVariationNodeDefinition(
          id: id * 10,
          itemId: 500,
          parentNodeId: id,
          kind: ItemVariationNodeKind.value,
          name: value,
          displayName: value,
          position: 0,
          isArchived: false,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          children: const [],
        ),
      ],
    );

ItemDefinition _part({
  DevelopedFor developedFor = DevelopedFor.empty,
  List<ItemDieLink> dies = const [],
  List<ItemMachineLink> machines = const [],
  List<ItemVariationNodeDefinition> variationTree = const [],
  PenPaperBaseline? baseline,
}) =>
    ItemDefinition(
      id: 500,
      name: 'Patti',
      alias: '',
      displayName: 'Patti',
      partNo: 1,
      partCode: 'PGBP1',
      quantity: 0,
      groupId: 11,
      unitId: 7,
      developedFor: developedFor,
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime.utc(2026, 11, 3, 9, 15),
      updatedAt: DateTime.utc(2026, 11, 3, 9, 15),
      variationTree: variationTree,
      dies: dies,
      machines: machines,
      penPaperBaseline: baseline,
    );

/// Every line, "Section | label | value", so a test reads like the report.
List<String> _lines(List<RawSheetReviewSection> sections) => [
      for (final section in sections)
        for (final (label, value) in section.rows) '${section.title} | $label | $value',
    ];

void main() {
  test('a full part: name and code, company, people, dies, machines, route, raw sheet', () {
    final part = _part(
      variationTree: [
        _property(1, 'Alloy', 'MS'),
        _property(2, 'Thickness', '23 Gauge'),
        _property(3, 'temper', 'H2'),
      ],
      developedFor: DevelopedFor(
        kind: DevelopedForKind.client,
        clientId: 7,
        companyName: 'Gold Medal',
        quotationAmount: 45000,
        at: DateTime.utc(2026, 11, 3, 9, 15),
        contacts: const [
          PartyContact(
            id: 1,
            name: 'Ravi Shah',
            designation: 'Purchase Manager',
            phone: '9820012345',
            email: 'ravi@example.com',
          ),
        ],
      ),
      dies: [
        ItemDieLink(
          id: 'd1',
          toolCode: 'CDPGBP1',
          dieType: 'cutting',
          madeBy: 'Shree Tools',
          linerSizeNm: 500000,
          noOfSet: 2,
          storeArea: 'A',
          rackNo: '3',
        ),
      ],
      machines: const [
        ItemMachineLink(
          id: 'm1',
          name: 'Press one',
          assetId: 'EP-1',
          machineType: 'Power press',
          capacityKind: 'rated',
          capacityKgf: 100000,
        ),
      ],
      baseline: const PenPaperBaseline(
        sheetWidthInches: 48,
        sheetHeightInches: 96,
        vendorName: 'Tata',
        materialName: 'MS',
        notes: '',
        stageReconciliations: [
          PenPaperStageReconciliation(
            stageId: 'whole',
            stageName: 'Whole pipeline',
            inputKg: 24.5,
            outputKg: 21.25,
            outputPieces: 2900,
            recordScrap: false,
            recordRejection: false,
            recordWeightLoss: false,
          ),
        ],
      ),
    );
    final lines = _lines(itemReportSections(
      item: part,
      groupPath: 'Primary Group › Brackets',
      propertyLabels: const {'temper': 'Temper'},
      routes: [
        const PartRoute(
          id: 1,
          partId: 500,
          version: 1,
          status: RouteStatus.active,
          name: 'Primary Group Brackets Patti PGBP1 pipeline',
          steps: [
            RouteStep(stageId: 1, seq: 1, stageCode: 'die', stageName: 'Die'),
            RouteStep(stageId: 2, seq: 2, stageCode: 'shearing', stageName: 'Shearing'),
          ],
        ),
      ],
      documents: const ['GST certificate'],
    ));

    expect(lines, containsAll([
      'Part | Part | Patti',
      'Part | Part code | PGBP1',
      'Part | Filed under | Primary Group › Brackets',
      'Part | Alloy | MS',
      'Part | Thickness | 23 Gauge',
      'Part | Temper | H2',
      'Company | Made for | Gold Medal',
      'Company | Dealt with | Ravi Shah · Purchase Manager · 9820012345 · ravi@example.com',
      'Company | Documents | GST certificate',
      'Dies |  | CDPGBP1',
      'Dies | Made by | Shree Tools',
      'Dies | Sets | 2',
      'Machines |  | EP-1',
      'Machines | Type | Power press',
      'Route (pipeline) | Pipeline | Primary Group Brackets Patti PGBP1 pipeline',
      'Route (pipeline) | Stages | Die → Shearing',
      'Sheet | Vendor | Tata',
    ]));
    expect(lines.any((line) => line.startsWith('Company | Quotation |')), isTrue);
    expect(lines.where((line) => line.startsWith('Part |')).length,
        greaterThan(5),
        reason: "the raw sheet's own Part heading is not repeated");
    expect(itemReportHeading(part), startsWith('Patti — PGBP1 · saved '));
  });

  test('a part with nothing else says so, in words', () {
    final lines = _lines(itemReportSections(item: _part()));
    expect(lines, containsAll([
      'Company | Made for | No company recorded',
      'Dies |  | No dies on this part',
      'Machines |  | No machines on this part',
      'Route (pipeline) |  | No route yet',
      'Raw sheet |  | No raw sheet recorded',
    ]));
  });

  test('a part made for ourselves says so', () {
    final lines = _lines(itemReportSections(
      item: _part(developedFor: const DevelopedFor(kind: DevelopedForKind.self)),
    ));
    expect(lines, contains('Company | Made for | Ourselves (in-house)'));
  });

  test('weights nobody typed are not printed as data', () {
    // fromJson fills an empty record with three made-up stages.
    final made = PenPaperBaseline.fromJson(const {'sheetWidthInches': 48});
    final lines = _lines(itemReportSections(item: _part(baseline: made)));
    expect(lines.where((line) => line.contains('100 kg')), isEmpty);
    expect(lines, contains('Material in and out |  | Not recorded'));
    expect(lines.where((line) => line.contains('Recorded from sample')), isEmpty);
  });

  test('the model\'s sample note is not printed as somebody\'s note', () {
    final saved = PenPaperBaseline(
      sheetWidthInches: 48,
      sheetHeightInches: 96,
      stageReconciliations: [
        PenPaperStageReconciliation(
          stageId: 'whole',
          stageName: 'Whole pipeline',
          inputKg: 24.5,
          outputKg: 21.25,
          notes: const PenPaperBaseline().notes,
        ),
      ],
    );
    final lines = _lines(itemReportSections(item: _part(baseline: saved)));
    expect(lines.where((line) => line.contains('Recorded from sample')), isEmpty);
    expect(lines, contains('Material in and out | Weight in | 24.5 kg'));
  });

  testWidgets('clicking a part opens on its report, read fresh from the server',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final part = _part(variationTree: [_property(1, 'Alloy', 'MS')]);
    final repo = _Items(part);
    final items = ItemsProvider(repository: repo);
    await tester.runAsync(items.refresh);
    final groups = GroupsProvider(repository: _Groups());
    await groups.initialize();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ItemsProvider>.value(value: items),
        ChangeNotifierProvider<GroupsProvider>.value(value: groups),
        ChangeNotifierProvider<UnitsProvider>(
          create: (_) => UnitsProvider(repository: _Units()),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showItemDetailPanel(context, item: part),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(const ValueKey('item_report')), findsOneWidget,
        reason: 'the report is what a click opens');
    expect(repo.fresh, contains(500), reason: 'read from the server, not the replica');
    expect(find.textContaining('Patti — PGBP1 · saved '), findsOneWidget);
    expect(find.text('Primary Group › Brackets'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Item Specifications'), findsOneWidget);
  });
}
