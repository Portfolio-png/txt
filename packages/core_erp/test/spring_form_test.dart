import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/domain/group_overview.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/groups/presentation/widgets/group_view_dialog.dart';
import 'package:core_erp/features/raw_materials/data/rivet_repository.dart';
import 'package:core_erp/features/raw_materials/data/spring_repository.dart';
import 'package:core_erp/features/raw_materials/domain/rivet.dart';
import 'package:core_erp/features/raw_materials/domain/spring.dart';
import 'package:core_erp/features/raw_materials/presentation/item_kind_switcher.dart';
import 'package:core_erp/features/raw_materials/presentation/spring_drawing.dart';
import 'package:core_erp/features/raw_materials/presentation/spring_form_dialog.dart';
import 'package:core_erp/features/vendors/data/repositories/vendor_repository.dart';
import 'package:core_erp/features/vendors/domain/vendor_definition.dart';
import 'package:core_erp/features/vendors/presentation/providers/vendors_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Raw Materials › Springs, from the owner's drawing (2026-11-25): Coil Length
/// 114, Coil Number 6, Coil Hook Double Hook → "Double Hook Spring 114 X 6".

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
    _vendor(1, 'Coil Works', raw: true),
  ];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SpringDefinition _saved(SpringInput input, int id) => SpringDefinition(
  itemId: id,
  name: springName(
    kind: input.kind,
    springType: input.springType,
    sizes: input.sizes,
    wireGauge: input.wireGauge,
    wireGrade: input.wireGrade,
    format: input.nameFormat,
  ),
  code: input.code,
  kind: input.kind,
  springType: input.springType,
  sizes: Map.of(input.sizes),
  wireGauge: input.wireGauge,
  wireGrade: input.wireGrade,
  nameFormat: input.nameFormat,
  vendors: input.vendors,
);

SpringInput _drawingInput({String code = '', String gauge = ''}) => SpringInput(
  kind: SpringKind.doubleHook,
  springType: '',
  sizes: const <SpringSize, String>{SpringSize.coilLength: '114', SpringSize.coilNumber: '6'},
  wireGauge: gauge,
  wireGrade: '',
  code: code,
  nameFormat: defaultSpringNameFormat(SpringKind.doubleHook),
  vendors: const <RivetVendorPrice>[],
);

class _FakeSpringRepository implements SpringRepository {
  final List<SpringInput> created = <SpringInput>[];
  final List<(int, SpringInput)> updated = <(int, SpringInput)>[];
  SpringApiException? refuse;
  List<SpringDefinition> springs = <SpringDefinition>[];

  @override
  Future<List<SpringDefinition>> list() async => springs;

  @override
  Future<SpringDefinition?> get(int itemId) async {
    for (final s in springs) {
      if (s.itemId == itemId) return s;
    }
    return null;
  }

  @override
  Future<SpringDefinition> create(SpringInput input) async {
    if (refuse != null) throw refuse!;
    created.add(input);
    return _saved(input, 71);
  }

  @override
  Future<SpringDefinition> update(int itemId, SpringInput input) async {
    updated.add((itemId, input));
    return _saved(input, itemId);
  }
}

class _NoRivets implements RivetRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
  id: 8,
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
  _FakeSpringRepository springs, {
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
        Provider<SpringRepository>.value(value: springs),
        Provider<RivetRepository>.value(value: _NoRivets()),
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
    .widget<SelectableText>(find.byKey(const ValueKey<String>('spring-name-preview')))
    .data!;

Future<void> _openForm(WidgetTester tester, _FakeSpringRepository springs) async {
  await _pump(
    tester,
    springs,
    button: (context) => ElevatedButton(
      onPressed: () => SpringFormDialog.open(context),
      child: const Text('open'),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  test('the name rule matches the drawing, and follows a naming format', () {
    final sizes = <SpringSize, String>{SpringSize.coilLength: '114', SpringSize.coilNumber: '6'};
    expect(
      springName(
        kind: SpringKind.doubleHook,
        springType: '',
        sizes: sizes,
        wireGauge: '22 SWG',
        wireGrade: '',
        format: defaultSpringNameFormat(SpringKind.doubleHook),
      ),
      'Double Hook Spring 114 X 6',
    );
    expect(
      springName(
        kind: SpringKind.doubleHook,
        springType: '',
        sizes: sizes,
        wireGauge: '22 SWG',
        wireGrade: '',
        format: const <NameToken>[
          NameToken('coilLength'),
          NameToken('coilNumber', NameSeparator.times),
          NameToken('wireGauge', NameSeparator.minus),
          NameToken('kind', NameSeparator.plus),
          NameToken('springType'),
        ],
      ),
      '114 X 6 - 22 SWG + Double Hook',
      reason: 'an empty block (no type) is left out with its separator',
    );
    expect(isValidCoilNumber('6.5'), isFalse);
    expect(coilIdUnderOd('8.0', '9'), isFalse);
  });

  testWidgets('the form: kind, type, sizes, a name arranged with blocks', (tester) async {
    final springs = _FakeSpringRepository();
    await _openForm(tester, springs);

    expect(find.byType(SpringDrawing), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('spring-type-5 A Steel')));
    await tester.pump();
    await _type(tester, 'spring-coilLength', '114');
    await _type(tester, 'spring-coilNumber', '6');
    await _type(tester, 'spring-wireGauge', '22 SWG');
    expect(_preview(tester), 'Double Hook Spring 114 X 6', reason: 'the default format');

    // Wire Gauge into the name, joined by "-".
    await tester.ensureVisible(find.byKey(const ValueKey<String>('name-add-wireGauge')));
    await tester.tap(find.byKey(const ValueKey<String>('name-add-wireGauge')));
    await tester.pump();
    expect(_preview(tester), 'Double Hook Spring 114 X 6 22 SWG');
    await tester.tap(find.byKey(const ValueKey<String>('name-sep-wireGauge')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('name-sep-option-minus')).last);
    await tester.pumpAndSettle();
    expect(_preview(tester), 'Double Hook Spring 114 X 6 - 22 SWG');
    // The type in too, moved to the front.
    await tester.tap(find.byKey(const ValueKey<String>('name-add-springType')));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const ValueKey<String>('name-left-springType')));
      await tester.pump();
    }
    expect(_preview(tester), '5 A Steel Double Hook Spring 114 X 6 - 22 SWG');
    expect(
      tester.widget<IconButton>(find.byKey(const ValueKey<String>('name-left-springType'))).onPressed,
      isNull,
      reason: 'first already',
    );

    await tester.tap(find.byKey(const ValueKey<String>('spring-save')));
    await tester.pumpAndSettle();
    final sent = springs.created.single.toJson();
    expect(sent['kind'], 'Double Hook');
    expect(sent['springType'], '5 A Steel');
    expect(sent['coilLength'], '114');
    expect(sent['wireGauge'], '22 SWG');
    expect(sent.containsKey('freeLength'), isFalse, reason: 'only the kind\'s own sizes');
    expect((sent['nameFormat'] as List).map((t) => '${t['block']}${t['sep']}').toList(), [
      'springType ', 'kind ', 'spring ', 'coilLength ', 'coilNumberx', 'wireGauge-',
    ]);
  });

  testWidgets('a conical spring has its own sizes and drawing', (tester) async {
    final springs = _FakeSpringRepository();
    await _openForm(tester, springs);
    await tester.tap(find.byKey(const ValueKey<String>('spring-kind-conical')));
    await tester.pump();
    expect(tester.widget<SpringDrawing>(find.byType(SpringDrawing)).kind, SpringKind.conical);
    expect(find.byKey(const ValueKey<String>('spring-coilLength')), findsNothing);
    expect(find.byKey(const ValueKey<String>('spring-wireGauge')), findsNothing, reason: 'its wire is a diameter');
    await _type(tester, 'spring-freeLength', '20');
    await _type(tester, 'spring-totalCoils', '5');
    await _type(tester, 'spring-largeOd', '6');
    await _type(tester, 'spring-smallOd', '12');
    expect(_preview(tester), 'Conical Spring 20 X 5', reason: 'its default format follows the kind');
    await tester.tap(find.byKey(const ValueKey<String>('spring-save')));
    await tester.pumpAndSettle();
    expect(find.text('Smaller than Large OD'), findsOneWidget);
    expect(springs.created, isEmpty);
  });

  testWidgets('what the name needs is required', (tester) async {
    final springs = _FakeSpringRepository();
    await _openForm(tester, springs);
    await _type(tester, 'spring-coilOd', '8');
    await _type(tester, 'spring-coilId', '9');
    await tester.tap(find.byKey(const ValueKey<String>('spring-save')));
    await tester.pumpAndSettle();
    expect(find.text('Coil Length is needed'), findsOneWidget);
    expect(find.text('Coil Number is needed'), findsOneWidget);
    expect(find.text('Smaller than Coil OD'), findsOneWidget);
    expect(springs.created, isEmpty);
  });

  testWidgets('the same spring twice: says so, and opens the one that exists', (tester) async {
    final springs = _FakeSpringRepository();
    springs.refuse = SpringApiException(
      'This spring already exists: Double Hook Spring 114 X 6.',
      code: 'spring_exists',
      existing: _saved(_drawingInput(code: 'OLD-SP'), 9),
    );
    await _openForm(tester, springs);
    await _type(tester, 'spring-coilLength', '114');
    await _type(tester, 'spring-coilNumber', '6');
    await tester.tap(find.byKey(const ValueKey<String>('spring-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('already exists'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('spring-open-existing')));
    await tester.pumpAndSettle();
    expect(find.text('Edit spring'), findsOneWidget);
    expect(find.text('OLD-SP'), findsOneWidget);
  });

  testWidgets('the Springs window has Add spring and lists its springs', (tester) async {
    final springs = _FakeSpringRepository()
      ..springs = <SpringDefinition>[_saved(_drawingInput(code: 'SP-114', gauge: '22 SWG'), 71)];
    final group = _group('Springs', systemKey: springsGroupSystemKey);
    await _pump(
      tester,
      springs,
      overview: GroupOverview(group: group),
      button: (context) => ElevatedButton(
        onPressed: () => showGroupViewDialog(context, group: group),
        child: const Text('open'),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Double Hook Spring 114 X 6'), findsOneWidget);
    expect(find.text('Code SP-114'), findsOneWidget);
    expect(find.text('6 coils'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('group-add-rivet')), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('group-add-spring')));
    await tester.pumpAndSettle();
    expect(find.byType(SpringFormDialog), findsOneWidget);
  });

  testWidgets('the editor rail: a spring opens on Spring', (tester) async {
    final springs = _FakeSpringRepository()
      ..springs = <SpringDefinition>[_saved(_drawingInput(code: 'SP-114'), 71)];
    await _pump(
      tester,
      springs,
      button: (context) => SizedBox(
        width: 1500,
        height: 1000,
        child: ItemKindSwitcher(
          itemEditor: const Text('THE ITEM EDITOR'),
          itemId: 71,
          isRivet: false,
          isSpring: true,
          onClose: () {},
          onRivetSaved: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SpringFormDialog), findsOneWidget);
    expect(find.text('Edit spring'), findsOneWidget);
    expect(find.text('SP-114'), findsOneWidget);
    InkWell entry(ItemKind kind) =>
        tester.widget<InkWell>(find.byKey(ValueKey<String>('item-kind-${kind.name}')));
    expect(entry(ItemKind.rivet).onTap, isNull, reason: 'a spring is not a rivet');
    expect(entry(ItemKind.item).onTap, isNotNull);
  });
}
