import 'package:core_erp/core/services/user_preferences_service.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:core_erp/features/clients/data/repositories/client_repository.dart';
import 'package:core_erp/features/clients/domain/client_definition.dart';
import 'package:core_erp/features/clients/presentation/providers/clients_provider.dart';
import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/domain/inventory_set_definition.dart';
import 'package:core_erp/features/inventory/domain/inventory_control_tower.dart';
import 'package:core_erp/features/inventory/domain/material_record.dart';
import 'package:core_erp/features/inventory/domain/variation_stock_record.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/items/data/models/item_api_models.dart';
import 'package:core_erp/features/items/data/repositories/api_item_repository.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/core/utils/stamp_format.dart';
import 'package:core_erp/features/items/domain/developed_for.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/domain/item_inputs.dart';
import 'package:core_erp/features/items/domain/part_code.dart';
import 'package:core_erp/features/items/presentation/providers/item_form_sections_provider.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/items/presentation/screens/items_screen.dart';
import 'package:core_erp/features/materials/data/material_repository.dart';
import 'package:core_erp/features/materials/domain/material_definition.dart';
import 'package:core_erp/features/materials/presentation/providers/materials_provider.dart';
import 'package:core_erp/features/units/data/repositories/unit_repository.dart';
import 'package:core_erp/features/units/domain/unit_definition.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// A part is corrected in this form or nowhere — the wizard only stamps it at
/// birth. What matters here is that the editor can say "clear it", which an
/// absent key cannot, and that on a create it speaks about identity only when
/// somebody actually typed it: the server stamps a new part when neither key
/// arrives, so an untouched pair has to send nothing at all.

final _unit = UnitDefinition(
  id: 1,
  name: 'pieces',
  symbol: 'pcs',
  notes: '',
  unitGroupId: null,
  unitGroupName: null,
  conversionFactor: 1,
  conversionBaseUnitId: null,
  conversionBaseUnitName: null,
  conversionType: 'linear',
  precision: 2,
  unitGroupDimension: null,
  unitGroupBaseUnitId: null,
  isArchived: false,
  usageCount: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

GroupDefinition _group(int id, String name) => GroupDefinition(
  id: id,
  name: name,
  groupType: 'item',
  groupStructure: 'hierarchical',
  parentGroupId: null,
  unitId: 1,
  isArchived: false,
  usageCount: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

final _goldMadel = ClientDefinition(
  id: 7,
  name: 'Gold Madel Industries',
  alias: 'Gold Madel',
  gstNumber: '',
  address: '',
  isArchived: false,
  usageCount: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  contactName: 'Kissan Jain',
  designation: 'Director',
  phone: '986565656',
  email: 'kissan@goldmadel.example',
);

final _developedForGoldMadel = DevelopedFor(
  kind: DevelopedForKind.client,
  clientId: _goldMadel.id,
  clientName: _goldMadel.name,
  companyName: _goldMadel.name,
  contactName: 'Kissan Jain',
  designation: 'Director',
  phone: '986565656',
  email: 'kissan@goldmadel.example',
  at: DateTime.utc(2026, 5, 15, 4, 35),
  quotationAmount: 85000,
);

final _switchAction = _group(10, 'Switch Action');
final _steelAngle = _group(11, 'Steel Angle');

final _patti = ItemDefinition(
  id: 100,
  name: 'Patti',
  displayName: 'Patti',
  alias: '',
  groupId: _switchAction.id,
  unitId: _unit.id,
  quantity: 0,
  partNo: 48,
  partCode: 'SADP48',
  developedFor: _developedForGoldMadel,
  namingFormat: const <String>[],
  variationTree: const <ItemVariationNodeDefinition>[],
  usageCount: 0,
  isArchived: false,
  createdAt: DateTime(2026, 5, 15, 10, 5),
  updatedAt: DateTime(2026, 5, 15, 10, 5),
);

final _unstamped = ItemDefinition(
  id: 101,
  name: 'Older Part',
  displayName: 'Older Part',
  alias: '',
  groupId: _switchAction.id,
  unitId: _unit.id,
  quantity: 0,
  namingFormat: const <String>[],
  variationTree: const <ItemVariationNodeDefinition>[],
  usageCount: 0,
  isArchived: false,
  createdAt: DateTime(2026, 5, 15, 10, 5),
  updatedAt: DateTime(2026, 5, 15, 10, 5),
);

class _FakeItemRepository implements ItemRepository {
  UpdateItemInput? lastUpdate;
  CreateItemInput? lastCreate;
  List<ItemSetMembership> membership = const <ItemSetMembership>[];
  bool clashOnUpdate = false;

  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async => <ItemDefinition>[
    _patti,
    _unstamped,
  ];

  @override
  Future<List<ItemSetMembership>> itemSets(int itemId) async => membership;

  @override
  Future<ItemDefinition> updateItem(UpdateItemInput input) async {
    lastUpdate = input;
    if (clashOnUpdate) {
      throw ItemApiException(
        'Part code "${input.partCode}" is already used by "Dabbi" in this group.',
        statusCode: 409,
        code: 'part_code_duplicate',
      );
    }
    return _patti;
  }

  @override
  Future<ItemDefinition> createItem(CreateItemInput input) async {
    lastCreate = input;
    return _patti;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGroupRepository implements GroupRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async =>
      <GroupDefinition>[_switchAction, _steelAngle];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUnitRepository implements UnitRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<UnitDefinition>> getUnits() async => <UnitDefinition>[_unit];

  @override
  Future<List<ConversionPoint>> getGaugePoints() async =>
      const <ConversionPoint>[];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClientRepository implements ClientRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<ClientDefinition>> getClients() async => <ClientDefinition>[
    _goldMadel,
  ];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMaterialRepository implements MaterialRepository {
  @override
  Future<List<MaterialDefinition>> list({bool includeArchived = false}) async =>
      const <MaterialDefinition>[];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInventoryRepository implements InventoryRepository {
  _FakeInventoryRepository([List<InventorySetDefinition>? sets])
    : _sets = List<InventorySetDefinition>.of(
        sets ?? const <InventorySetDefinition>[],
      );

  final List<InventorySetDefinition> _sets;
  final List<SaveInventorySetInput> saved = <SaveInventorySetInput>[];
  final List<int> deleted = <int>[];

  @override
  Future<void> init() async {}

  @override
  Future<void> seedIfEmpty() async {}

  @override
  Future<List<MaterialRecord>> getMaterials() async => const <MaterialRecord>[];

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
      List<InventorySetDefinition>.of(_sets);

  @override
  Future<InventorySetDefinition> saveSet(SaveInventorySetInput input) async {
    saved.add(input);
    return _sets.firstWhere((set) => set.id == input.id);
  }

  @override
  Future<void> deleteSet(int setId) async {
    deleted.add(setId);
    _sets.removeWhere((set) => set.id == setId);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

InventorySetDefinition _set(
  int id,
  String name, {
  int? groupId,
  String? groupName,
  String? photoUrl,
  List<InventorySetLineDefinition> lines = const <InventorySetLineDefinition>[],
}) => InventorySetDefinition(
  id: id,
  name: name,
  totalItemCount: lines.fold(0, (sum, line) => sum + line.quantity),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  lines: lines,
  groupId: groupId,
  groupName: groupName,
  photoUrl: photoUrl,
);

InventorySetLineDefinition _line(int itemId, {int quantity = 1, int position = 0}) =>
    InventorySetLineDefinition(
      id: itemId,
      itemId: itemId,
      variationLeafNodeId: 0,
      quantity: quantity,
      position: position,
      itemName: 'Item $itemId',
      itemDisplayName: 'Item $itemId',
      variationPathLabel: '',
      variationPathNodeIds: const <int>[],
    );

_FakeInventoryRepository? _lastInventoryRepo;

Future<_FakeItemRepository> _open(
  WidgetTester tester, {
  ItemDefinition? item = const _Unset(),
  List<ItemSetMembership> membership = const <ItemSetMembership>[],
  List<InventorySetDefinition> sets = const <InventorySetDefinition>[],
}) async {
  tester.view.physicalSize = const Size(1700, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final itemRepo = _FakeItemRepository()..membership = membership;
  final itemsProvider = ItemsProvider(repository: itemRepo);
  final groupsProvider = GroupsProvider(repository: _FakeGroupRepository());
  final unitsProvider = UnitsProvider(repository: _FakeUnitRepository());
  await itemsProvider.initialize();
  await groupsProvider.initialize();
  await unitsProvider.initialize();

  final opened = item is _Unset ? _patti : item;

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ItemsProvider>.value(value: itemsProvider),
        ChangeNotifierProvider<GroupsProvider>.value(value: groupsProvider),
        ChangeNotifierProvider<UnitsProvider>.value(value: unitsProvider),
        ChangeNotifierProvider<InventoryProvider>(
          create: (_) => InventoryProvider(
            repository: _lastInventoryRepo = _FakeInventoryRepository(sets),
          ),
        ),
        ChangeNotifierProvider<ClientsProvider>(
          create: (_) => ClientsProvider(repository: _FakeClientRepository()),
        ),
        ChangeNotifierProvider<MaterialsProvider>(
          create: (_) =>
              MaterialsProvider(repository: _FakeMaterialRepository()),
        ),
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(baseUrl: '', demoMode: true),
        ),
        ChangeNotifierProvider<ItemFormSectionsProvider>(
          create: (_) => ItemFormSectionsProvider(
            service: UserPreferencesService(
              baseUrl: '',
              useMockResponses: true,
            ),
          ),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => ItemsScreen.openEditor(
                  context,
                  item: opened,
                  initialGroupId: opened == null ? _switchAction.id : null,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return itemRepo;
}

/// Lets a test pass `item: null` and still have a default of "the Patti".
class _Unset implements ItemDefinition {
  const _Unset();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('placeholder');
}

Finder _field(String key) => find.byKey(ValueKey<String>(key));

String _textIn(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(_field(key)).controller!.text;

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save Changes'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save Changes'));
  await tester.pumpAndSettle();
}

void main() {
  _developedForTests();

  testWidgets('the part fields show what the part carries', (tester) async {
    await _open(tester);

    expect(_textIn(tester, 'item-part-no'), '48');
    expect(_textIn(tester, 'item-part-code'), 'SADP48');
    expect(find.textContaining('Stamped 15/05/2026'), findsOneWidget);
  });

  testWidgets('a part that predates the stamp says so, rather than dating it', (
    tester,
  ) async {
    await _open(tester, item: _unstamped);

    expect(_textIn(tester, 'item-part-no'), isEmpty);
    expect(find.text('Not stamped yet'), findsOneWidget);
    expect(find.textContaining('Stamped 15/05'), findsNothing);
  });

  testWidgets('an edit reaches the repository, speaking about identity', (
    tester,
  ) async {
    final repo = await _open(tester);

    await tester.enterText(_field('item-part-code'), 'legacy7');
    await tester.pumpAndSettle();
    await _save(tester);

    final input = repo.lastUpdate;
    expect(input, isNotNull, reason: 'the save must reach the repo');
    expect(input!.partIdentitySpecified, isTrue);
    // Uppercased in the field, so the box agrees with what will be stored.
    expect(input.partCode, 'LEGACY7');
    expect(input.partNo, 48);
  });

  testWidgets('clearing both sends them as empty, which is how you clear', (
    tester,
  ) async {
    final repo = await _open(tester);

    await tester.enterText(_field('item-part-no'), '');
    await tester.enterText(_field('item-part-code'), '');
    await tester.pumpAndSettle();
    await _save(tester);

    final input = repo.lastUpdate!;
    expect(input.partNo, isNull);
    expect(input.partCode, '');

    // Asserted on the wire, not on the input: an absent key means "preserve",
    // so a flag that died at this boundary would turn "clear" into "leave it".
    final json = UpdateItemRequest.fromInput(input).toJson();
    expect(json.containsKey('partNo'), isTrue);
    expect(json['partNo'], isNull);
    expect(json['partCode'], '');
  });

  testWidgets('an untouched create says nothing, so the server stamps it', (
    tester,
  ) async {
    final repo = await _open(tester, item: null);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Base Name').first,
      'Brand New Part',
    );
    await tester.pumpAndSettle();
    // A new item needs its unit picked before it can be saved.
    await tester.tap(find.text('Unit').last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('pieces').last);
    await tester.pumpAndSettle();
    // "Create Item" is the dialog's heading as well as its button.
    final createButton = find.descendant(
      of: find.byType(AppButton),
      matching: find.text('Create Item'),
    );
    await tester.ensureVisible(createButton);
    await tester.pumpAndSettle();
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    final input = repo.lastCreate;
    expect(input, isNotNull, reason: 'the create must reach the repo');
    // The server only stamps a part when NEITHER key arrives.
    final json = CreateItemRequest.fromInput(input!).toJson();
    expect(json.containsKey('partNo'), isFalse);
    expect(json.containsKey('partCode'), isFalse);
  });

  testWidgets('a code typed on a create is the code that lands', (
    tester,
  ) async {
    // The fields render and accept input on a create — the stamp line even
    // promises "Date and time stamped on save" — but the create branch used to
    // read neither controller, so whatever was typed was silently dropped and
    // the server derived something else. A field that takes input and throws it
    // away is worse than no field.
    final repo = await _open(tester, item: null);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Base Name').first,
      'Brand New Part',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unit').last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('pieces').last);
    await tester.pumpAndSettle();

    await tester.enterText(_field('item-part-no'), '7');
    await tester.enterText(_field('item-part-code'), 'swap7');
    await tester.pumpAndSettle();

    final createButton = find.descendant(
      of: find.byType(AppButton),
      matching: find.text('Create Item'),
    );
    await tester.ensureVisible(createButton);
    await tester.pumpAndSettle();
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    final input = repo.lastCreate;
    expect(input, isNotNull, reason: 'the create must reach the repo');
    expect(input!.partNo, 7);
    // Uppercased in the field, so the box agrees with what will be stored.
    expect(input.partCode, 'SWAP7');

    // And it survives the wire: both keys present means "I am telling you",
    // which is what stops the server deriving its own.
    final json = CreateItemRequest.fromInput(input).toJson();
    expect(json['partNo'], 7);
    expect(json['partCode'], 'SWAP7');
  });

  testWidgets('a part no alone still reaches the create', (tester) async {
    // Half-stated identity is still stated: the person gave a number, so the
    // server must not quietly stamp a different one over it.
    final repo = await _open(tester, item: null);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Base Name').first,
      'Half Stated',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unit').last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('pieces').last);
    await tester.pumpAndSettle();

    await tester.enterText(_field('item-part-no'), '12');
    await tester.pumpAndSettle();

    final createButton = find.descendant(
      of: find.byType(AppButton),
      matching: find.text('Create Item'),
    );
    await tester.ensureVisible(createButton);
    await tester.pumpAndSettle();
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    final json = CreateItemRequest.fromInput(repo.lastCreate!).toJson();
    expect(json['partNo'], 12);
    expect(
      json.containsKey('partCode'),
      isFalse,
      reason: 'an empty code must be absent, never an empty string',
    );
  });

  testWidgets('moving the part to another group re-derives its code', (
    tester,
  ) async {
    await _open(tester);

    await tester.tap(find.textContaining('Switch Action').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Steel Angle').last);
    await tester.pumpAndSettle();

    // The letters follow the group; the number it was issued does not.
    expect(_textIn(tester, 'item-part-code'), 'SAP48');
  });

  testWidgets('a code the user typed survives a group change', (tester) async {
    await _open(tester);

    await tester.enterText(_field('item-part-code'), 'MINE-1');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Switch Action').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Steel Angle').last);
    await tester.pumpAndSettle();

    expect(_textIn(tester, 'item-part-code'), 'MINE-1');
  });

  testWidgets('with the part in two sets the code is left alone, and says why', (
    tester,
  ) async {
    await _open(
      tester,
      membership: <ItemSetMembership>[
        const ItemSetMembership(
          lineId: 1,
          setId: 1,
          setName: 'Dolly',
          quantity: 1,
          variationLeafNodeId: 0,
          variationPathLabel: 'Base item',
          setLineCount: 3,
        ),
        const ItemSetMembership(
          lineId: 2,
          setId: 2,
          setName: 'Rocker',
          quantity: 2,
          variationLeafNodeId: 0,
          variationPathLabel: 'Base item',
          setLineCount: 2,
        ),
      ],
    );

    expect(find.textContaining('In 2 sets'), findsOneWidget);

    await tester.tap(find.textContaining('Switch Action').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Steel Angle').last);
    await tester.pumpAndSettle();

    expect(
      _textIn(tester, 'item-part-code'),
      'SADP48',
      reason: 'with several sets there is no fact about which lends its letter',
    );
  });

  // --- the editor's chrome ---------------------------------------------------

  testWidgets('the title and the buttons stay put while the form scrolls', (
    tester,
  ) async {
    // Deliberately short, so the body has somewhere to scroll to.
    tester.view.physicalSize = const Size(1400, 700);
    await _open(tester);

    final saveBefore = tester.getRect(find.text('Save Changes'));
    final titleBefore = tester.getRect(find.text('Edit Item'));

    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.text('Save Changes')),
      saveBefore,
      reason: 'the footer is a sibling of the scroll view, not inside it',
    );
    expect(tester.getRect(find.text('Edit Item')), titleBefore);
  });

  testWidgets('a refusal is visible without scrolling back up', (tester) async {
    tester.view.physicalSize = const Size(1400, 700);
    final repo = await _open(tester);
    repo.clashOnUpdate = true;

    await tester.enterText(_field('item-part-code'), 'TAKEN9');
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    // The banner sits above the scrolling body, so the reason is on screen
    // wherever the user happens to be in a long form.
    expect(
      find.textContaining('already used by "Dabbi"'),
      findsOneWidget,
    );
  });

  // --- the Sets card ---------------------------------------------------------

  testWidgets('the card lists one row per line, labelling another group\'s set', (
    tester,
  ) async {
    await _open(
      tester,
      membership: <ItemSetMembership>[
        const ItemSetMembership(
          lineId: 1,
          setId: 1,
          setName: 'Dolly',
          quantity: 2,
          variationLeafNodeId: 0,
          variationPathLabel: 'Base item',
          setLineCount: 3,
          groupId: 10,
          groupName: 'Switch Action',
        ),
        const ItemSetMembership(
          lineId: 2,
          setId: 2,
          setName: 'Angle Kit',
          quantity: 1,
          variationLeafNodeId: 0,
          variationPathLabel: 'Base item',
          setLineCount: 4,
          groupId: 11,
          groupName: 'Steel Angle',
        ),
      ],
    );

    expect(find.text('Dolly'), findsOneWidget);
    expect(find.text('Angle Kit'), findsOneWidget);
    // A set filed elsewhere says so; one of this part's own does not need to.
    expect(find.text('in Steel Angle'), findsOneWidget);
    expect(find.text('Changes here save immediately.'), findsOneWidget);
  });

  testWidgets('taking the part out keeps the photo and never re-files the set', (
    tester,
  ) async {
    await _open(
      tester,
      membership: <ItemSetMembership>[
        const ItemSetMembership(
          lineId: 1,
          setId: 1,
          setName: 'Dolly',
          quantity: 1,
          variationLeafNodeId: 0,
          variationPathLabel: 'Base item',
          setLineCount: 2,
          groupId: 10,
        ),
      ],
      sets: <InventorySetDefinition>[
        _set(
          1,
          'Dolly',
          groupId: 10,
          photoUrl: 'https://example.test/dolly.png',
          lines: <InventorySetLineDefinition>[
            _line(_patti.id, position: 0),
            _line(500, position: 1),
          ],
        ),
      ],
    );

    await tester.tap(find.byTooltip('Take out of Dolly'));
    await tester.pumpAndSettle();

    final saved = _lastInventoryRepo!.saved;
    expect(saved, hasLength(1));
    expect(saved.single.id, 1);
    // The two silent failure modes of a full-replace save.
    expect(saved.single.photoUrl, 'https://example.test/dolly.png');
    expect(saved.single.groupIdSpecified, isFalse);
    expect(saved.single.lines, hasLength(1));
    expect(saved.single.lines.single.itemId, 500);
    expect(saved.single.lines.single.position, 0);
  });

  testWidgets('a changed quantity writes that line and nothing else', (
    tester,
  ) async {
    await _open(
      tester,
      membership: <ItemSetMembership>[
        const ItemSetMembership(
          lineId: 1,
          setId: 1,
          setName: 'Dolly',
          quantity: 1,
          variationLeafNodeId: 0,
          variationPathLabel: 'Base item',
          setLineCount: 2,
          groupId: 10,
        ),
      ],
      sets: <InventorySetDefinition>[
        _set(
          1,
          'Dolly',
          groupId: 10,
          lines: <InventorySetLineDefinition>[
            _line(_patti.id, position: 0),
            _line(500, quantity: 4, position: 1),
          ],
        ),
      ],
    );

    await tester.enterText(find.byKey(const ValueKey<String>('set-qty-1-0')), '6');
    // Commits on Enter or on blur, not on every keystroke — each commit is a
    // write.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final saved = _lastInventoryRepo!.saved;
    expect(saved, hasLength(1));
    expect(saved.single.lines.firstWhere((l) => l.itemId == _patti.id).quantity, 6);
    expect(saved.single.lines.firstWhere((l) => l.itemId == 500).quantity, 4);
    expect(saved.single.lines.map((l) => l.position), <int>[0, 1]);
  });

  testWidgets('the only line in a set cannot be removed, it has to be deleted', (
    tester,
  ) async {
    await _open(
      tester,
      membership: <ItemSetMembership>[
        const ItemSetMembership(
          lineId: 1,
          setId: 1,
          setName: 'Dolly',
          quantity: 1,
          variationLeafNodeId: 0,
          variationPathLabel: 'Base item',
          // The set holds nothing else, and the server refuses an empty set.
          setLineCount: 1,
          groupId: 10,
        ),
      ],
      sets: <InventorySetDefinition>[
        _set(1, 'Dolly', groupId: 10, lines: <InventorySetLineDefinition>[
          _line(_patti.id),
        ]),
      ],
    );

    expect(find.byTooltip('Take out of Dolly'), findsNothing);
    expect(
      find.byTooltip(
        'This part is the only thing in Dolly, and a set cannot be empty. '
        'Delete the set instead.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a membership write does not make the form dirty', (tester) async {
    await _open(
      tester,
      membership: <ItemSetMembership>[
        const ItemSetMembership(
          lineId: 1,
          setId: 1,
          setName: 'Dolly',
          quantity: 1,
          variationLeafNodeId: 0,
          variationPathLabel: 'Base item',
          setLineCount: 2,
          groupId: 10,
        ),
      ],
      sets: <InventorySetDefinition>[
        _set(1, 'Dolly', groupId: 10, lines: <InventorySetLineDefinition>[
          _line(_patti.id, position: 0),
          _line(500, position: 1),
        ]),
      ],
    );

    await tester.tap(find.byTooltip('Take out of Dolly'));
    await tester.pumpAndSettle();

    // It is already saved, so closing must not offer to discard it — and
    // discarding could not undo it anyway.
    // By tooltip: `byIcon(Icons.close_rounded).first` matched the Sets card's
    // own remove button, so this assertion used to pass without ever closing
    // the editor.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
  });

  testWidgets('two fast taps on remove issue one write, not two', (tester) async {
    await _open(
      tester,
      membership: <ItemSetMembership>[
        const ItemSetMembership(
          lineId: 1,
          setId: 1,
          setName: 'Dolly',
          quantity: 1,
          variationLeafNodeId: 0,
          variationPathLabel: 'Base item',
          setLineCount: 3,
          groupId: 10,
        ),
      ],
      sets: <InventorySetDefinition>[
        _set(1, 'Dolly', groupId: 10, lines: <InventorySetLineDefinition>[
          _line(_patti.id, position: 0),
          _line(500, position: 1),
          _line(501, position: 2),
        ]),
      ],
    );

    // Without the in-flight guard both would compute from the same snapshot
    // and the second would undo the first.
    await tester.tap(find.byTooltip('Take out of Dolly'));
    await tester.tap(find.byTooltip('Take out of Dolly'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(_lastInventoryRepo!.saved, hasLength(1));
  });

  testWidgets('the card waits for the first save of a brand new part', (
    tester,
  ) async {
    await _open(tester, item: null);

    // A set line needs a real item id, so there is nothing to show yet.
    expect(find.text('Sets'), findsNothing);
  });

  testWidgets('a taken code marks the field and keeps the rest of the edit', (
    tester,
  ) async {
    final repo = await _open(tester);
    repo.clashOnUpdate = true;

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Base Name').first,
      'Renamed Patti',
    );
    await tester.enterText(_field('item-part-code'), 'TAKEN9');
    await tester.pumpAndSettle();
    await _save(tester);

    expect(
      find.text('Another part in this group already has this code.'),
      findsOneWidget,
    );
    // Nothing was written, so the rename is still in the form.
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Base Name').first,
          )
          .controller!
          .text,
      'Renamed Patti',
    );
  });
}

/// --- Developed For ---------------------------------------------------------
///
/// The same subject as the part identity above: an absent key means "preserve",
/// so the only thing that can clear a block is a block. These guard the three
/// ways it could go missing — the editor not carrying it, the editor not being
/// able to clear it, and a preserving save dropping it on the floor.
void _developedForTests() {
  testWidgets('the card shows who the part was developed for', (tester) async {
    await _open(tester);

    expect(find.text('Developed For'), findsOneWidget);
    // The person is read from the client, so this is the client's contact and
    // not anything stored on the part.
    expect(find.text('Gold Madel Industries'), findsWidgets);
    expect(find.text('Kissan Jain'), findsOneWidget);
    expect(find.text('Director'), findsOneWidget);
    // The stamp renders as a local wall clock, and the figure as rupees.
    expect(find.text(partStampDate(_developedForGoldMadel.at!)), findsOneWidget);
    expect(find.text('85000'), findsOneWidget);
  });

  testWidgets('a save that touches nothing else still carries the block', (
    tester,
  ) async {
    final repo = await _open(tester);

    await tester.enterText(_field('item-part-code'), 'SADP49');
    await tester.pumpAndSettle();
    await _save(tester);

    final input = repo.lastUpdate!;
    expect(input.developedFor, isNotNull);
    expect(input.developedFor!.kind, DevelopedForKind.client);
    expect(input.developedFor!.clientId, _goldMadel.id);
    expect(input.developedFor!.quotationAmount, 85000);

    // And it survives the wire, where an omitted key would mean "preserve" —
    // which is harmless here but would hide a real break in the clear path.
    final json = UpdateItemRequest.fromInput(input).toJson();
    expect(json['developedFor'], isNotNull);
    expect((json['developedFor'] as Map)['clientId'], _goldMadel.id);
  });

  testWidgets('switching to Self sends nulls, which is how it is cleared', (
    tester,
  ) async {
    final repo = await _open(tester);

    await tester.ensureVisible(find.text('Self'));
    await tester.tap(find.text('Self'));
    await tester.pumpAndSettle();
    await _save(tester);

    final block = repo.lastUpdate!.developedFor!;
    expect(block.kind, DevelopedForKind.self);
    expect(block.clientId, isNull);
    expect(block.subContractorId, isNull);

    final json = UpdateItemRequest.fromInput(repo.lastUpdate!).toJson();
    final wire = json['developedFor'] as Map;
    expect(wire['kind'], 'self');
    expect(wire['clientId'], isNull);
    // The legacy single field is omitted rather than sent as null: it would
    // otherwise be a second, disagreeing answer about the same columns.
    expect(json.containsKey('developedForClientId'), isFalse);
  });

  testWidgets('a part developed for nobody shows the card empty, not missing', (
    tester,
  ) async {
    await _open(tester, item: _unstamped);

    expect(find.text('Developed For'), findsOneWidget);
    expect(find.text('For'), findsOneWidget);
    // Nothing is picked, so there is no party row and no quotation to fill in
    // until a kind is chosen.
    expect(find.text('Nobody picked yet'), findsNothing);
  });

  test('a preserving save keeps the block', () async {
    // The regression class _preservingInput's own comment is about: this input
    // is rebuilt wholesale, and anything that falls out of it is written away.
    final repo = _FakeItemRepository();
    final provider = ItemsProvider(repository: repo);
    await provider.initialize();

    await provider.setItemPipeline(_patti.id, 'pipeline-7');

    final input = repo.lastUpdate!;
    expect(input.defaultPipelineId, 'pipeline-7');
    expect(input.developedFor, _developedForGoldMadel);
    expect(input.partCode, 'SADP48', reason: 'the neighbour it sits beside');
  });
}
