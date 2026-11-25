import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/domain/group_overview.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/groups/presentation/widgets/group_view_dialog.dart';
import 'package:core_erp/features/raw_materials/data/rivet_repository.dart';
import 'package:core_erp/features/raw_materials/domain/rivet.dart';
import 'package:core_erp/features/raw_materials/presentation/item_kind_switcher.dart';
import 'package:core_erp/features/raw_materials/presentation/rivet_drawing.dart';
import 'package:core_erp/features/raw_materials/presentation/rivet_form_dialog.dart';
import 'package:core_erp/features/vendors/data/repositories/vendor_repository.dart';
import 'package:core_erp/features/vendors/domain/vendor_definition.dart';
import 'package:core_erp/features/vendors/presentation/providers/vendors_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Raw Materials › Rivets: the Add rivet button, and the form built on the
/// owner's drawing — Bimetal, Head OD 3.5, Head Diameter 1.3, Shank Diameter
/// 2.0, Shank Length 2.0, Silver Layer 0.25, Flat →
///   Bimetal Rivet 3.5 X 1.3 / 2.0 X 2.0 Flat (0.25)

VendorDefinition _vendor(int id, String name, {bool raw = false}) => VendorDefinition(
  id: id,
  name: name,
  alias: '',
  gstNumber: '',
  address: '',
  contactName: '',
  phone: '',
  email: '',
  isArchived: false,
  usageCount: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  suppliesRawMaterial: raw,
);

class _FakeVendorRepository implements VendorRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<VendorDefinition>> getVendors() async => <VendorDefinition>[
    _vendor(1, 'Shree Rivets', raw: true),
    _vendor(2, 'Office Supplies'),
  ];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRivetRepository implements RivetRepository {
  final List<RivetInput> created = <RivetInput>[];
  RivetApiException? refuse;
  List<RivetDefinition> rivets = <RivetDefinition>[];

  @override
  Future<List<RivetDefinition>> list() async => rivets;

  final List<(int, RivetInput)> updated = <(int, RivetInput)>[];

  @override
  Future<RivetDefinition?> get(int itemId) async {
    for (final rivet in rivets) {
      if (rivet.itemId == itemId) return rivet;
    }
    return null;
  }

  @override
  Future<RivetDefinition> create(RivetInput input) async {
    if (refuse != null) throw refuse!;
    created.add(input);
    return _saved(input, 41);
  }

  @override
  Future<RivetDefinition> update(int itemId, RivetInput input) async {
    updated.add((itemId, input));
    return _saved(input, itemId);
  }
}

RivetDefinition _saved(RivetInput input, int id) => RivetDefinition(
  itemId: id,
  name: rivetName(
    rivetType: input.rivetType,
    headType: input.headType,
    dimensions: input.dimensions,
  ),
  code: input.code,
  rivetType: input.rivetType,
  headType: input.headType,
  dimensions: <RivetDimension, RivetLength?>{
    for (final dim in RivetDimension.values)
      dim: (input.dimensions[dim] ?? '').isEmpty
          ? null
          : RivetLength(mm: input.dimensions[dim]!, nm: 0),
  },
  vendors: input.vendors,
);

class _FakeGroupRepository implements GroupRepository {
  _FakeGroupRepository(this.overview);

  final GroupOverview overview;

  @override
  Future<GroupOverview> getGroupOverview(int groupId) async => overview;

  @override
  Future<void> init() async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GroupDefinition _group(String name, {String? systemKey}) => GroupDefinition(
  id: 7,
  name: name,
  parentGroupId: 5,
  isArchived: false,
  usageCount: 0,
  systemKey: systemKey,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Future<void> _pump(
  WidgetTester tester,
  _FakeRivetRepository rivets, {
  required Widget Function(BuildContext context) button,
  GroupOverview? overview,
}) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final vendors = VendorsProvider(repository: _FakeVendorRepository());
  await vendors.refresh();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<RivetRepository>.value(value: rivets),
        ChangeNotifierProvider<VendorsProvider>.value(value: vendors),
        if (overview != null)
          ChangeNotifierProvider<GroupsProvider>(
            create: (_) => GroupsProvider(repository: _FakeGroupRepository(overview)),
          ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(body: Center(child: button(context))),
        ),
      ),
    ),
  );
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(ValueKey<String>(key)), text);
  await tester.pump();
}

String _preview(WidgetTester tester) => tester
    .widget<SelectableText>(find.byKey(const ValueKey<String>('rivet-name-preview')))
    .data!;

void main() {
  test('the name rule matches the drawing', () {
    expect(
      rivetName(
        rivetType: 'Bimetal',
        headType: RivetHeadType.flat,
        dimensions: const <RivetDimension, String>{
          RivetDimension.headOd: '3.5',
          RivetDimension.headDia: '1.3',
          RivetDimension.shankDia: '2.0',
          RivetDimension.shankLength: '2.0',
          RivetDimension.silverLayer: '0.25',
        },
      ),
      'Bimetal Rivet 3.5 X 1.3 / 2.0 X 2.0 Flat (0.25)',
    );
    expect(isValidMillimetres('2.0'), isTrue);
    expect(isValidMillimetres('0'), isFalse);
    expect(isValidMillimetres('2,0'), isFalse);
    expect(isValidPrice('0.035'), isTrue);
    expect(isValidPrice('12,50'), isFalse);
  });

  testWidgets('the form: drawing, name as you type, F/R, vendor with price', (
    tester,
  ) async {
    final rivets = _FakeRivetRepository();
    RivetDefinition? saved;
    await _pump(
      tester,
      rivets,
      button: (context) => ElevatedButton(
        onPressed: () async => saved = await RivetFormDialog.open(context),
        child: const Text('open'),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(RivetDrawing), findsOneWidget);
    expect(find.text('Add rivet'), findsWidgets);
    // The three types are a choice, not something typed.
    for (final type in rivetTypes) {
      expect(find.byKey(ValueKey<String>('rivet-type-$type')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey<String>('rivet-type-Bimetal')));
    await tester.pump();
    await _type(tester, 'rivet-headOd', '3.5');
    await _type(tester, 'rivet-headDia', '1.3');
    await _type(tester, 'rivet-shankDia', '2.0');
    await _type(tester, 'rivet-shankLength', '2.0');
    await _type(tester, 'rivet-silverLayer', '0.25');
    await _type(tester, 'rivet-code', 'BR-35');
    expect(_preview(tester), 'Bimetal Rivet 3.5 X 1.3 / 2.0 X 2.0 Flat (0.25)');

    // R is round: the drawing and the name follow.
    await tester.tap(find.text('R — Round'));
    await tester.pump();
    expect(_preview(tester), 'Bimetal Rivet 3.5 X 1.3 / 2.0 X 2.0 Round (0.25)');
    expect(tester.widget<RivetDrawing>(find.byType(RivetDrawing)).headType, RivetHeadType.round);
    await tester.tap(find.text('F — Flat'));
    await tester.pump();

    // A vendor, with the price they quote per 1000.
    await tester.tap(find.byKey(const ValueKey<String>('rivet-add-vendor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('rivet-vendor-0')));
    await tester.pumpAndSettle();
    expect(find.text('Raw material supplier'), findsOneWidget, reason: 'suppliers are marked');
    await tester.tap(find.text('Shree Rivets').last);
    await tester.pumpAndSettle();
    await _type(tester, 'rivet-price-0', '32.50');

    await tester.tap(find.byKey(const ValueKey<String>('rivet-save')));
    await tester.pumpAndSettle();

    expect(rivets.created, hasLength(1));
    final sent = rivets.created.single.toJson();
    expect(sent['rivetType'], 'Bimetal');
    expect(sent['headType'], 'F');
    expect(sent['headOd'], '3.5');
    expect(sent['silverLayer'], '0.25');
    expect(sent['code'], 'BR-35');
    expect(sent['vendors'], <Map<String, dynamic>>[
      <String, dynamic>{'vendorId': 1, 'price': '32.50', 'basis': 'thousand'},
    ]);
    expect(saved?.name, 'Bimetal Rivet 3.5 X 1.3 / 2.0 X 2.0 Flat (0.25)');
    expect(find.byType(RivetFormDialog), findsNothing, reason: 'closed on save');
  });

  testWidgets('a missing dimension is named, and nothing is sent', (tester) async {
    final rivets = _FakeRivetRepository();
    await _pump(
      tester,
      rivets,
      button: (context) => ElevatedButton(
        onPressed: () => RivetFormDialog.open(context),
        child: const Text('open'),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // No type picked: says so.
    await tester.tap(find.byKey(const ValueKey<String>('rivet-save')));
    await tester.pumpAndSettle();
    expect(find.text('Pick the rivet type'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('rivet-type-Bimetal')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('rivet-save')));
    await tester.pumpAndSettle();
    expect(find.text('Head OD is needed'), findsOneWidget);
    expect(
      find.text('Silver Layer is needed'),
      findsOneWidget,
      reason: 'a bimetal rivet is the one with the silver layer',
    );
    expect(rivets.created, isEmpty);
  });

  testWidgets('the same rivet twice: says so, and opens the one that exists', (
    tester,
  ) async {
    final rivets = _FakeRivetRepository();
    final existing = RivetDefinition(
      itemId: 9,
      name: 'Copper Rivet 3.5 X 1.3 / 2.0 X 2.0 Flat',
      code: 'OLD-1',
      rivetType: 'Copper',
      headType: RivetHeadType.flat,
      dimensions: const <RivetDimension, RivetLength?>{
        RivetDimension.headOd: RivetLength(mm: '3.5', nm: 3500000),
        RivetDimension.headDia: RivetLength(mm: '1.3', nm: 1300000),
        RivetDimension.shankDia: RivetLength(mm: '2.0', nm: 2000000),
        RivetDimension.shankLength: RivetLength(mm: '2.0', nm: 2000000),
      },
      vendors: const <RivetVendorPrice>[],
    );
    rivets.refuse = RivetApiException(
      'This rivet already exists: Copper Rivet 3.5 X 1.3 / 2.0 X 2.0 Flat.',
      code: 'rivet_exists',
      existing: existing,
    );
    await _pump(
      tester,
      rivets,
      button: (context) => ElevatedButton(
        onPressed: () => RivetFormDialog.open(context),
        child: const Text('open'),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('rivet-type-Copper')));
    await tester.pump();
    await _type(tester, 'rivet-headOd', '3.5');
    await _type(tester, 'rivet-headDia', '1.3');
    await _type(tester, 'rivet-shankDia', '2');
    await _type(tester, 'rivet-shankLength', '2.0');
    await tester.tap(find.byKey(const ValueKey<String>('rivet-save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('already exists'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('rivet-open-existing')));
    await tester.pumpAndSettle();
    expect(find.text('Edit rivet'), findsOneWidget);
    expect(find.text('OLD-1'), findsOneWidget, reason: 'its code is filled in');
  });

  testWidgets('Copper and Aluminium have no silver layer', (tester) async {
    await _pump(
      tester,
      _FakeRivetRepository(),
      button: (context) => ElevatedButton(
        onPressed: () => RivetFormDialog.open(context),
        child: const Text('open'),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('rivet-type-Bimetal')));
    await tester.pump();
    await _type(tester, 'rivet-silverLayer', '0.25');

    await tester.tap(find.byKey(const ValueKey<String>('rivet-type-Copper')));
    await tester.pump();
    final silver = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('rivet-silverLayer')),
        matching: find.byType(TextField),
      ),
    );
    expect(silver.enabled, isFalse, reason: 'drawn disabled, not hidden');
    expect(silver.controller!.text, isEmpty, reason: 'cleared');
    expect(find.text('Only a bimetal rivet has one'), findsOneWidget);
    expect(tester.widget<RivetDrawing>(find.byType(RivetDrawing)).rivetType, 'Copper');
    expect(_preview(tester), endsWith('Flat'), reason: 'no (…) in the name');

    await tester.tap(find.byKey(const ValueKey<String>('rivet-type-Aluminium')));
    await tester.pump();
    expect(_preview(tester), startsWith('Aluminium Rivet'));
  });

  group('the item editor rail: Item, Rivet, Spring', () {
    RivetDefinition bimetal(int id) => _saved(
      const RivetInput(
        rivetType: 'Bimetal',
        headType: RivetHeadType.flat,
        dimensions: <RivetDimension, String>{
          RivetDimension.headOd: '3.5',
          RivetDimension.headDia: '1.3',
          RivetDimension.shankDia: '2.1',
          RivetDimension.shankLength: '2.0',
          RivetDimension.silverLayer: '2.0',
        },
        code: 'BR-1',
        vendors: <RivetVendorPrice>[],
      ),
      id,
    );

    Future<List<RivetDefinition>> host(
      WidgetTester tester,
      _FakeRivetRepository rivets, {
      int? itemId,
      bool isRivet = false,
    }) async {
      final saved = <RivetDefinition>[];
      await _pump(
        tester,
        rivets,
        button: (context) => SizedBox(
          width: 1500,
          height: 1000,
          child: ItemKindSwitcher(
            itemEditor: const Text('THE ITEM EDITOR'),
            itemId: itemId,
            isRivet: isRivet,
            onClose: () {},
            onRivetSaved: saved.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return saved;
    }

    bool tappable(WidgetTester tester, ItemKind kind) =>
        tester.widget<InkWell>(find.byKey(ValueKey<String>('item-kind-${kind.name}'))).onTap != null;

    testWidgets('a rivet opens on its drawing form, filled in', (tester) async {
      final rivets = _FakeRivetRepository()..rivets = <RivetDefinition>[bimetal(697)];
      await host(tester, rivets, itemId: 697, isRivet: true);

      expect(find.byType(RivetFormDialog), findsOneWidget);
      expect(find.text('Edit rivet'), findsOneWidget);
      expect(find.text('BR-1'), findsOneWidget, reason: 'its code, loaded');
      expect(find.text('THE ITEM EDITOR'), findsNothing);
      expect(tappable(tester, ItemKind.item), isTrue);
      expect(tappable(tester, ItemKind.spring), isFalse, reason: 'a rivet is not a spring');
      expect(find.byTooltip('Only an item in Raw Materials › Springs is a spring.'), findsOneWidget);
    });

    testWidgets('switching to Item and back keeps what was typed', (tester) async {
      final rivets = _FakeRivetRepository()..rivets = <RivetDefinition>[bimetal(697)];
      await host(tester, rivets, itemId: 697, isRivet: true);
      await _type(tester, 'rivet-code', 'BR-77');

      await tester.tap(find.byKey(const ValueKey<String>('item-kind-item')));
      await tester.pumpAndSettle();
      expect(find.text('THE ITEM EDITOR'), findsOneWidget);
      expect(find.byType(RivetDrawing), findsNothing);

      await tester.tap(find.byKey(const ValueKey<String>('item-kind-rivet')));
      await tester.pumpAndSettle();
      expect(find.text('BR-77'), findsOneWidget);
    });

    testWidgets('any other item opens on Item; Rivet is drawn disabled, with why', (tester) async {
      await host(tester, _FakeRivetRepository(), itemId: 60);
      expect(find.text('THE ITEM EDITOR'), findsOneWidget);
      expect(tappable(tester, ItemKind.rivet), isFalse);
      expect(find.byTooltip('Only an item in Raw Materials › Rivets is a rivet.'), findsOneWidget);
    });

    testWidgets('a new item can be made a rivet', (tester) async {
      await host(tester, _FakeRivetRepository());
      expect(tappable(tester, ItemKind.rivet), isTrue);
      await tester.tap(find.byKey(const ValueKey<String>('item-kind-rivet')));
      await tester.pumpAndSettle();
      expect(find.text('Add rivet'), findsWidgets);
    });

    testWidgets('an item filed under Rivets with no spec gets one, on itself', (tester) async {
      final rivets = _FakeRivetRepository();
      final saved = await host(tester, rivets, itemId: 88, isRivet: true);
      expect(find.text('Edit rivet'), findsOneWidget, reason: 'not "Add": this item exists');
      await tester.tap(find.byKey(const ValueKey<String>('rivet-type-Copper')));
      await tester.pump();
      await _type(tester, 'rivet-headOd', '3.5');
      await _type(tester, 'rivet-headDia', '1.3');
      await _type(tester, 'rivet-shankDia', '2.0');
      await _type(tester, 'rivet-shankLength', '2.0');
      await tester.tap(find.byKey(const ValueKey<String>('rivet-save')));
      await tester.pumpAndSettle();
      expect(rivets.created, isEmpty, reason: 'no second rivet');
      expect(rivets.updated.single.$1, 88);
      expect(saved.single.itemId, 88);
    });
  });

  group('the group window', () {
    GroupOverview overviewOf(GroupDefinition group) => GroupOverview(
      group: group,
      itemSource: GroupItemSource.owned,
      items: const <GroupOverviewItem>[],
      children: const <GroupChild>[],
      properties: const <GroupProperty>[],
      lineage: const <GroupChild>[],
      summary: const GroupSummary(
        itemCount: 0,
        orderedItemCount: 0,
        orderLineCount: 0,
        variantCount: 0,
        withPipelineCount: 0,
        units: <String>[],
      ),
    );

    testWidgets('Rivets has Add rivet and lists its rivets', (tester) async {
      final rivets = _FakeRivetRepository()
        ..rivets = <RivetDefinition>[
          _saved(
            const RivetInput(
              rivetType: 'Bimetal',
              headType: RivetHeadType.flat,
              dimensions: <RivetDimension, String>{
                RivetDimension.headOd: '3.5',
                RivetDimension.headDia: '1.3',
                RivetDimension.shankDia: '2.0',
                RivetDimension.shankLength: '2.0',
                RivetDimension.silverLayer: '0.25',
              },
              code: 'BR-35',
              vendors: <RivetVendorPrice>[],
            ),
            41,
          ),
        ];
      final group = _group('Rivets', systemKey: rivetsGroupSystemKey);
      await _pump(
        tester,
        rivets,
        overview: overviewOf(group),
        button: (context) => ElevatedButton(
          onPressed: () => showGroupViewDialog(context, group: group),
          child: const Text('open'),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('group-add-rivet')), findsOneWidget);
      expect(find.text('Bimetal Rivet 3.5 X 1.3 / 2.0 X 2.0 Flat (0.25)'), findsOneWidget);
      expect(find.text('Code BR-35'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('group-add-rivet')));
      await tester.pumpAndSettle();
      expect(find.byType(RivetFormDialog), findsOneWidget);
    });

    testWidgets('any other group has no rivet button', (tester) async {
      final group = _group('Rivet stock');
      await _pump(
        tester,
        _FakeRivetRepository(),
        overview: overviewOf(group),
        button: (context) => ElevatedButton(
          onPressed: () => showGroupViewDialog(context, group: group),
          child: const Text('open'),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('group-add-rivet')),
        findsNothing,
        reason: 'keyed on the system key, not on a name that says rivet',
      );
    });
  });
}
