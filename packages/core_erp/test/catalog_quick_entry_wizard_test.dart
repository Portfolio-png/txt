import 'package:core_erp/features/clients/data/repositories/client_repository.dart';
import 'package:core_erp/features/clients/domain/client_definition.dart';
import 'package:core_erp/features/clients/presentation/providers/clients_provider.dart';
import 'package:core_erp/core/app_flow_hooks.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/features/items/domain/developed_for.dart';
import 'package:core_erp/features/items/presentation/widgets/developed_for_form.dart';
import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/domain/group_inputs.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/domain/inventory_control_tower.dart';
import 'package:core_erp/features/inventory/domain/inventory_set_definition.dart';
import 'package:core_erp/features/inventory/domain/set_membership.dart';
import 'package:core_erp/features/inventory/domain/material_record.dart';
import 'package:core_erp/features/inventory/domain/variation_stock_record.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/data/repositories/api_item_repository.dart';
import 'package:core_erp/features/items/domain/item_inputs.dart';
import 'package:core_erp/features/items/domain/part_code.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/items/presentation/widgets/catalog_quick_entry_dialog.dart';
import 'package:core_erp/features/units/data/repositories/unit_repository.dart';
import 'package:core_erp/features/units/domain/unit_definition.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The quick-entry wizard: three cascading columns, a tick per row, and one
/// rule that is not like the others — a set cannot exist without a line, so a
/// ticked set name is a draft until the first item joins it.
///
/// What these pin down is the write side. The set save is a full replace, so the
/// two ways to get it wrong are both silent: specifying the group on a merge
/// re-files the set, and omitting the photo clears it.

UnitDefinition _unit(int id, String name, {bool isArchived = false}) {
  return UnitDefinition(
    id: id,
    name: name,
    symbol: name.substring(0, 2),
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
    isArchived: isArchived,
    usageCount: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

final _pieces = _unit(1, 'Pieces');
final _kilos = _unit(2, 'Kilogram');
final _retiredUnit = _unit(3, 'Retired', isArchived: true);

GroupDefinition _group(
  int id,
  String name, {
  int? parentGroupId,
  int? unitId = 1,
  bool isArchived = false,
  String structure = 'hierarchical',
  String groupType = 'item',
}) {
  return GroupDefinition(
    id: id,
    name: name,
    groupType: groupType,
    groupStructure: structure,
    parentGroupId: parentGroupId,
    unitId: unitId,
    isArchived: isArchived,
    usageCount: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

final _primary = _group(1, 'Primary Group');
final _ashTrays = _group(10, 'Ash Trays', parentGroupId: 1, unitId: 2);
final _scrap = _group(11, 'Scrap', parentGroupId: 1);
final _retiredGroup = _group(
  12,
  'Retired Line',
  parentGroupId: 1,
  isArchived: true,
);

ItemDefinition _item(
  int id,
  String name, {
  required int groupId,
  bool isArchived = false,
  int? partNo,
  String partCode = '',
  DateTime? createdAt,
  List<ItemVariationNodeDefinition> tree =
      const <ItemVariationNodeDefinition>[],
}) {
  return ItemDefinition(
    id: id,
    name: name,
    displayName: name,
    alias: '',
    partNo: partNo,
    partCode: partCode,
    groupId: groupId,
    unitId: 1,
    quantity: 0,
    namingFormat: const <String>[],
    variationTree: tree,
    usageCount: 0,
    isArchived: isArchived,
    createdAt: createdAt ?? DateTime(2026, 5, 15, 10, 5),
    updatedAt: DateTime(2026, 5, 15, 10, 5),
  );
}

ItemVariationNodeDefinition _node(
  int id, {
  required int itemId,
  required ItemVariationNodeKind kind,
  int? parentNodeId,
  List<ItemVariationNodeDefinition> children =
      const <ItemVariationNodeDefinition>[],
}) {
  return ItemVariationNodeDefinition(
    id: id,
    itemId: itemId,
    parentNodeId: parentNodeId,
    kind: kind,
    name: 'n$id',
    code: '',
    displayName: 'n$id',
    position: 0,
    isArchived: false,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    children: children,
  );
}

InventorySetDefinition _set(
  int id,
  String name, {
  int? groupId,
  String? groupName,
  bool isTemporary = false,
  String? photoUrl,
  List<InventorySetLineDefinition> lines = const <InventorySetLineDefinition>[],
}) {
  return InventorySetDefinition(
    id: id,
    name: name,
    totalItemCount: lines.fold(0, (sum, line) => sum + line.quantity),
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    lines: lines,
    isTemporary: isTemporary,
    groupId: groupId,
    groupName: groupName,
    photoUrl: photoUrl,
  );
}

InventorySetLineDefinition _line(int itemId, String name, {int quantity = 1}) {
  return InventorySetLineDefinition(
    id: itemId,
    itemId: itemId,
    variationLeafNodeId: 0,
    quantity: quantity,
    position: 0,
    itemName: name,
    itemDisplayName: name,
    variationPathLabel: '',
    variationPathNodeIds: const <int>[],
  );
}

class _FakeGroupRepository implements GroupRepository {
  _FakeGroupRepository(this._groups);

  final List<GroupDefinition> _groups;
  final List<CreateGroupInput> created = <CreateGroupInput>[];
  bool throwOnCreate = false;

  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async =>
      // A growable copy: the providers sort what the repository hands back.
      List<GroupDefinition>.of(_groups);

  @override
  Future<GroupDefinition> createGroup(CreateGroupInput input) async {
    created.add(input);
    if (throwOnCreate) throw Exception('A group with that name exists here.');
    final made = _group(
      900 + created.length,
      input.name,
      parentGroupId: input.parentGroupId,
      unitId: input.unitId,
    );
    _groups.add(made);
    return made;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeItemRepository implements ItemRepository {
  _FakeItemRepository(this._items);

  final List<ItemDefinition> _items;
  final List<CreateItemInput> created = <CreateItemInput>[];
  final List<UpdateItemInput> updated = <UpdateItemInput>[];
  bool throwOnCreate = false;
  bool throwOnUpdate = false;

  /// Refuse the next create the way the server refuses a code another part
  /// took between the suggestion and the tick.
  bool clashOnCreate = false;

  /// What the stand-in server says the next part should be called. The real
  /// one derives it; here it is handed over so a test can pin what the dialog
  /// does with the answer rather than re-testing the rule.
  int nextNo = 48;
  String nextCode = 'SADP48';
  final List<String> identityAsks = <String>[];

  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async =>
      List<ItemDefinition>.of(_items);

  @override
  Future<PartIdentitySuggestion> nextPartIdentity({
    required int groupId,
    int? setId,
    bool setPending = false,
    String setName = '',
    String name = '',
  }) async {
    identityAsks.add(
      '$groupId/${setId ?? '-'}/${setPending ? 'pending:$setName' : '-'}/$name',
    );
    return PartIdentitySuggestion(
      partNo: nextNo,
      partCode: nextCode,
      scope: setPending
          ? 'pending-set'
          : (setId == null ? 'group-unfiled' : 'set'),
    );
  }

  @override
  Future<ItemDefinition> createItem(CreateItemInput input) async {
    created.add(input);
    if (clashOnCreate) {
      throw ItemApiException(
        'Part code "${input.partCode}" is already used by "Patti" in this group.',
        statusCode: 409,
        code: 'part_code_duplicate',
      );
    }
    if (throwOnCreate) {
      throw ItemApiException('Item rejected.', statusCode: 500);
    }
    final made = _item(
      800 + created.length,
      input.name,
      groupId: input.groupId,
      partNo: input.partNo,
      partCode: input.partCode ?? '',
    );
    _items.add(made);
    return made;
  }

  /// What the dies and machines on a part look like once they are linked,
  /// keyed by id — standing in for the join the server does on the way back.
  final Map<String, ItemDieLink> dieRows = <String, ItemDieLink>{};
  final Map<String, ItemMachineLink> machineRows = <String, ItemMachineLink>{};

  @override
  Future<ItemDefinition> updateItem(UpdateItemInput input) async {
    updated.add(input);
    if (throwOnUpdate) {
      throw ItemApiException('Item rejected.', statusCode: 500);
    }
    final index = _items.indexWhere((item) => item.id == input.id);
    final current = _items[index];
    final next =
        _item(
              current.id,
              input.name,
              groupId: input.groupId,
              partNo: input.partNo ?? current.partNo,
              partCode: input.partCode ?? current.partCode,
            )
            .copyWithDevelopedFor(input.developedFor ?? current.developedFor)
            // The real read joins the die rows back onto the item; this stands in
            // for that, so a part can be seen holding more than one.
            .copyWithDies(
              input.dieIds
                  .map(
                    (id) =>
                        dieRows[id] ?? ItemDieLink(id: id, toolCode: 'DIE-$id'),
                  )
                  .toList(growable: false),
            )
            .copyWithMachines(
              input.machineIds
                  .map(
                    (id) =>
                        machineRows[id] ??
                        ItemMachineLink(id: id, name: 'MACH-$id', assetId: id),
                  )
                  .toList(growable: false),
            );
    _items[index] = next;
    return next;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// `ItemDefinition` has no copyWith, and this fake only needs one field of it.
extension on ItemDefinition {
  ItemDefinition copyWithMachines(List<ItemMachineLink> machines) =>
      ItemDefinition(
        id: id,
        name: name,
        displayName: displayName,
        alias: alias,
        partNo: partNo,
        partCode: partCode,
        groupId: groupId,
        unitId: unitId,
        quantity: quantity,
        namingFormat: namingFormat,
        variationTree: variationTree,
        usageCount: usageCount,
        isArchived: isArchived,
        createdAt: createdAt,
        updatedAt: updatedAt,
        developedFor: developedFor,
        dies: dies,
        machines: machines,
      );

  ItemDefinition copyWithDies(List<ItemDieLink> dies) => ItemDefinition(
    id: id,
    name: name,
    displayName: displayName,
    alias: alias,
    partNo: partNo,
    partCode: partCode,
    groupId: groupId,
    unitId: unitId,
    quantity: quantity,
    namingFormat: namingFormat,
    variationTree: variationTree,
    usageCount: usageCount,
    isArchived: isArchived,
    createdAt: createdAt,
    updatedAt: updatedAt,
    developedFor: developedFor,
    dies: dies,
    machines: machines,
  );

  ItemDefinition copyWithDevelopedFor(DevelopedFor developedFor) =>
      ItemDefinition(
        id: id,
        name: name,
        displayName: displayName,
        alias: alias,
        partNo: partNo,
        partCode: partCode,
        groupId: groupId,
        unitId: unitId,
        quantity: quantity,
        namingFormat: namingFormat,
        variationTree: variationTree,
        usageCount: usageCount,
        isArchived: isArchived,
        createdAt: createdAt,
        updatedAt: updatedAt,
        developedFor: developedFor,
        dies: dies,
        machines: machines,
      );
}

class _CapturingInventoryRepository implements InventoryRepository {
  _CapturingInventoryRepository(this._sets);

  final List<InventorySetDefinition> _sets;
  final List<SaveInventorySetInput> saved = <SaveInventorySetInput>[];
  bool throwOnSave = false;

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
      List<InventorySetDefinition>.of(_sets);

  @override
  Future<InventorySetDefinition> saveSet(SaveInventorySetInput input) async {
    saved.add(input);
    if (throwOnSave) throw Exception('Set rejected.');
    final made = _set(
      input.id ?? 700 + saved.length,
      input.name,
      groupId: input.groupIdSpecified
          ? input.groupId
          : _sets.where((s) => s.id == input.id).firstOrNull?.groupId,
      photoUrl: input.photoUrl.isEmpty ? null : input.photoUrl,
      lines: input.lines
          .map((line) => _line(line.itemId, line.itemDisplayName))
          .toList(growable: false),
    );
    _sets.removeWhere((s) => s.id == made.id);
    _sets.add(made);
    return made;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUnitRepository implements UnitRepository {
  _FakeUnitRepository(this._units);

  final List<UnitDefinition> _units;

  @override
  Future<void> init() async {}

  @override
  Future<List<UnitDefinition>> getUnits() async =>
      List<UnitDefinition>.of(_units);

  @override
  Future<List<ConversionPoint>> getGaugePoints() async =>
      const <ConversionPoint>[];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Two clients for the Developed For form to pick between, each with its own
/// contact, so a test can tell which one a part was stamped with.
ClientDefinition _client(
  int id,
  String name, {
  String contactName = '',
  String designation = '',
  String phone = '',
}) => ClientDefinition(
  id: id,
  name: name,
  alias: '',
  gstNumber: '',
  address: '',
  isArchived: false,
  usageCount: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  contactName: contactName,
  designation: designation,
  phone: phone,
);

final _goldMadel = _client(
  7,
  'Gold Madel Industries',
  contactName: 'Kissan Jain',
  designation: 'Director',
  phone: '986565656',
);
final _sunrise = _client(8, 'Sunrise Retail', contactName: 'Asha Rao');

class _FakeClientRepository implements ClientRepository {
  _FakeClientRepository(this._clients);

  final List<ClientDefinition> _clients;
  final List<Object?> writes = <Object?>[];

  @override
  Future<void> init() async {}

  @override
  Future<List<ClientDefinition>> getClients() async =>
      List<ClientDefinition>.of(_clients);

  @override
  noSuchMethod(Invocation invocation) {
    // Any write at all is worth noticing here: this feature's whole claim is
    // that a tick is ONE call, about the part.
    writes.add(invocation.memberName);
    return super.noSuchMethod(invocation);
  }
}

class _Harness {
  _Harness({
    required this.groupRepo,
    required this.itemRepo,
    required this.inventoryRepo,
    required this.clientRepo,
    required this.groups,
    required this.items,
    required this.inventory,
  });

  final _FakeGroupRepository groupRepo;
  final _FakeItemRepository itemRepo;
  final _CapturingInventoryRepository inventoryRepo;
  final _FakeClientRepository clientRepo;
  final GroupsProvider groups;
  final ItemsProvider items;
  final InventoryProvider inventory;
}

Future<_Harness> _pumpWizard(
  WidgetTester tester, {
  List<GroupDefinition>? groups,
  List<ItemDefinition>? items,
  List<InventorySetDefinition>? sets,
  List<UnitDefinition>? units,
  Size size = const Size(1600, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final groupRepo = _FakeGroupRepository(
    List<GroupDefinition>.from(
      groups ?? <GroupDefinition>[_primary, _ashTrays, _scrap],
    ),
  );
  final itemRepo = _FakeItemRepository(
    List<ItemDefinition>.from(items ?? const <ItemDefinition>[]),
  );
  final inventoryRepo = _CapturingInventoryRepository(
    List<InventorySetDefinition>.from(sets ?? const <InventorySetDefinition>[]),
  );
  final unitRepo = _FakeUnitRepository(
    List<UnitDefinition>.from(units ?? <UnitDefinition>[_pieces, _kilos]),
  );
  final clientRepo = _FakeClientRepository(<ClientDefinition>[
    _goldMadel,
    _sunrise,
  ]);

  final groupsProvider = GroupsProvider(repository: groupRepo);
  final itemsProvider = ItemsProvider(repository: itemRepo);
  final unitsProvider = UnitsProvider(repository: unitRepo);
  final inventoryProvider = InventoryProvider(repository: inventoryRepo);
  final clientsProvider = ClientsProvider(repository: clientRepo);
  await groupsProvider.initialize();
  await itemsProvider.initialize();
  await unitsProvider.initialize();
  await clientsProvider.initialize();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<GroupsProvider>.value(value: groupsProvider),
        ChangeNotifierProvider<ItemsProvider>.value(value: itemsProvider),
        ChangeNotifierProvider<UnitsProvider>.value(value: unitsProvider),
        ChangeNotifierProvider<InventoryProvider>.value(
          value: inventoryProvider,
        ),
        ChangeNotifierProvider<ClientsProvider>.value(value: clientsProvider),
      ],
      child: const MaterialApp(home: Scaffold(body: CatalogQuickEntryDialog())),
    ),
  );
  await tester.pumpAndSettle();

  return _Harness(
    groupRepo: groupRepo,
    itemRepo: itemRepo,
    inventoryRepo: inventoryRepo,
    clientRepo: clientRepo,
    groups: groupsProvider,
    items: itemsProvider,
    inventory: inventoryProvider,
  );
}

/// --- driving the dropdowns -------------------------------------------------
///
/// The three Miller columns are three searchable dropdowns now. These helpers
/// keep the old vocabulary — pick a row, type a name, tick it — so a test says
/// what it is about rather than how a picker opens.

/// The part's own fields live in the Part section; group and set are created
/// from inside their pickers and have no field of their own on the screen.
Finder _field(String slug) => find.byKey(
  ValueKey<String>('quick-entry-${slug == 'item' ? 'part-name' : slug}-field'),
);

String _textIn(WidgetTester tester, String slug) =>
    tester.widget<TextField>(_field(slug)).controller!.text;

const Map<String, String> _pickerKeys = <String, String>{
  'group': 'quick-entry-group-field',
  'set': 'quick-entry-set-field',
  'part': 'quick-entry-part-field',
};

const Map<String, String> _pickerHints = <String, String>{
  'group': 'Search or type a new group',
  'set': 'Search or type a new set',
  'part': 'Search or type a new part',
};

Finder _picker(String slug) => find.byKey(ValueKey<String>(_pickerKeys[slug]!));

Finder _pickerSearch(String slug) =>
    find.widgetWithText(TextField, _pickerHints[slug]!);

Future<void> _openPicker(WidgetTester tester, String slug) async {
  await tester.tap(_picker(slug));
  await tester.pumpAndSettle();
}

Future<void> _closePicker(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

/// Types into whichever picker owns this slug, leaving it open so the create
/// row can be ticked. For the part it is the staged-name field on the screen
/// itself, which is where a part is actually made.
Future<void> _type(WidgetTester tester, String slug, String text) async {
  if (!_pickerKeys.containsKey(slug)) {
    await tester.ensureVisible(_field(slug));
    await tester.pumpAndSettle();
    await tester.enterText(_field(slug), text);
    await tester.pumpAndSettle();
    return;
  }
  if (_pickerSearch(slug).evaluate().isEmpty) await _openPicker(tester, slug);
  await tester.enterText(_pickerSearch(slug), text);
  await tester.pumpAndSettle();
}

const Map<String, String> _createLabels = <String, String>{
  'group': 'Create group',
  'set': 'Name a new set',
};

/// Commits what [_type] typed: the picker's create row, or the Part section's
/// own Create button.
Future<void> _tick(WidgetTester tester, String slug) async {
  if (!_pickerKeys.containsKey(slug)) {
    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('quick-entry-create-part')),
    );
    return;
  }
  await tester.tap(find.textContaining(_createLabels[slug]!).first);
  await tester.pumpAndSettle();
}

/// Whether the create row is on offer at all — it is suppressed when what was
/// typed cannot be created, and the panel says why instead.
bool _canTick(WidgetTester tester, String slug) =>
    find.textContaining(_createLabels[slug]!).evaluate().isNotEmpty;

/// Picks an existing row by name, from whichever of the three offers it.
///
/// The old columns let a test say `_selectRow('Ash Trays')` without naming the
/// column; keeping that is what lets most of these tests read unchanged.
/// The option list of the picker that is open — scoped to the dialog holding
/// [slug]'s search box, because the made-just-now rail is a ListView too and
/// stays in the tree behind it.
Finder _openOptions(String slug) => find.descendant(
  of: find
      .ancestor(of: _pickerSearch(slug), matching: find.byType(Material))
      .first,
  matching: find.byType(ListView),
);

Future<void> _selectRow(WidgetTester tester, String label) async {
  for (final slug in const ['group', 'set', 'part']) {
    final field = _picker(slug);
    if (field.evaluate().isEmpty) continue;
    // A picker with nothing above it answered is not enabled and will not
    // open; skipping it is how this helper walks group → set → part.
    final opened = tester.any(
      find.descendant(of: field, matching: find.byType(InkWell)),
    );
    if (!opened) continue;
    await _openPicker(tester, slug);
    final option = find.descendant(
      of: _openOptions(slug),
      matching: find.textContaining(label),
    );
    if (option.evaluate().isEmpty) {
      await _closePicker(tester);
      continue;
    }
    await tester.tap(option.first);
    await tester.pumpAndSettle();
    return;
  }
  fail('no dropdown offered "$label"');
}

/// Files the selected part into the set in play.
Finder _fileIntoSetButton() =>
    find.byKey(const ValueKey<String>('quick-entry-file-into-set'));

Future<void> _addToSet(WidgetTester tester, String label) async {
  await _selectRow(tester, label);
  await _tapVisible(tester, _fileIntoSetButton());
}

void main() {
  _developedForWizardTests();
  _selectedPartTests();
  _madeListTests();
  _dieSectionTests();
  _manyDiesTests();
  _machineSectionTests();
  _stagedCreateTests();

  testWidgets('a group tick nests under the selection and inherits its unit', (
    tester,
  ) async {
    final harness = await _pumpWizard(tester);

    await _selectRow(tester, 'Ash Trays');
    await _type(tester, 'group', 'Round');
    await _tick(tester, 'group');

    expect(harness.groupRepo.created, hasLength(1));
    final input = harness.groupRepo.created.single;
    expect(input.name, 'Round');
    expect(input.parentGroupId, _ashTrays.id);
    // Ash Trays counts in kilos, so a group inside it starts there too.
    expect(input.unitId, _kilos.id);
    expect(input.groupStructure, 'hierarchical');
    // The new group becomes the selection, so the columns re-cascade onto it.
    expect(find.text('Goes into Round'), findsOneWidget);
  });

  testWidgets('column 2 lists only the selected group\'s own real sets', (
    tester,
  ) async {
    await _pumpWizard(
      tester,
      sets: <InventorySetDefinition>[
        _set(1, 'Bathroom Kit', groupId: _ashTrays.id),
        _set(2, 'Scrap Bundle', groupId: _scrap.id),
        _set(3, 'Run Output', groupId: _ashTrays.id, isTemporary: true),
        _set(4, 'Loose Kit'),
      ],
    );

    await _selectRow(tester, 'Ash Trays');
    // Unfiled sets are counted where the column used to name them, rather than
    // being invisible.
    expect(find.textContaining('1 ungrouped set'), findsOneWidget);

    await _openPicker(tester, 'set');
    expect(find.text('Bathroom Kit'), findsOneWidget);
    expect(find.text('Scrap Bundle'), findsNothing);
    expect(
      find.text('Run Output'),
      findsNothing,
      reason: 'run output is not hand-edited here',
    );
    expect(find.text('Loose Kit'), findsNothing);
  });

  testWidgets('a ticked set name writes nothing and reads as pending', (
    tester,
  ) async {
    final harness = await _pumpWizard(tester);

    await _selectRow(tester, 'Ash Trays');
    await _type(tester, 'set', 'Bathroom Kit');
    await _tick(tester, 'set');

    expect(harness.inventoryRepo.saved, isEmpty);
    expect(find.textContaining('is not created yet'), findsOneWidget);
    expect(find.textContaining('add a part to create it'), findsOneWidget);
  });

  testWidgets('the first item tick is what creates the set', (tester) async {
    final harness = await _pumpWizard(tester);

    await _selectRow(tester, 'Ash Trays');
    await _type(tester, 'set', 'Bathroom Kit');
    await _tick(tester, 'set');
    await _type(tester, 'item', 'Lid');
    await _tick(tester, 'item');

    expect(harness.itemRepo.created.single.name, 'Lid');
    expect(harness.itemRepo.created.single.groupId, _ashTrays.id);

    expect(harness.inventoryRepo.saved, hasLength(1));
    final save = harness.inventoryRepo.saved.single;
    expect(save.id, isNull);
    expect(save.name, 'Bathroom Kit');
    // A create owns the group question outright.
    expect(save.groupIdSpecified, isTrue);
    expect(save.groupId, _ashTrays.id);
    expect(save.lines, hasLength(1));
    expect(save.lines.single.variationLeafNodeId, 0);
    expect(save.lines.single.quantity, 1);

    expect(find.textContaining('is not created yet'), findsNothing);
  });

  testWidgets(
    'a second item merges without re-filing the set or losing its photo',
    (tester) async {
      final harness = await _pumpWizard(
        tester,
        sets: <InventorySetDefinition>[
          _set(
            5,
            'Bathroom Kit',
            groupId: _ashTrays.id,
            groupName: 'Ash Trays',
            photoUrl: 'https://example.test/kit.png',
            lines: <InventorySetLineDefinition>[_line(42, 'Cone 90mm')],
          ),
        ],
        items: <ItemDefinition>[_item(42, 'Cone 90mm', groupId: _ashTrays.id)],
      );

      await _selectRow(tester, 'Ash Trays');
      await _selectRow(tester, 'Bathroom Kit');
      await _type(tester, 'item', 'Lid');
      await _tick(tester, 'item');

      expect(harness.inventoryRepo.saved, hasLength(1));
      final save = harness.inventoryRepo.saved.single;
      expect(save.id, 5);
      // The two silent failure modes of a full-replace save.
      expect(
        save.groupIdSpecified,
        isFalse,
        reason:
            'a merge must not speak about the group, or it re-files the set',
      );
      expect(
        save.photoUrl,
        'https://example.test/kit.png',
        reason: 'the server writes photo_url on every update',
      );
      expect(save.lines, hasLength(2));
      expect(save.lines.map((line) => line.position), <int>[0, 1]);
    },
  );

  testWidgets('an item ticked with no set selected is just an item', (
    tester,
  ) async {
    final harness = await _pumpWizard(tester);

    await _selectRow(tester, 'Ash Trays');
    await _type(tester, 'item', 'Lid');
    await _tick(tester, 'item');

    expect(harness.itemRepo.created, hasLength(1));
    expect(harness.inventoryRepo.saved, isEmpty);
  });

  testWidgets('switching group drops the set selection', (tester) async {
    final harness = await _pumpWizard(
      tester,
      sets: <InventorySetDefinition>[
        _set(5, 'Bathroom Kit', groupId: _ashTrays.id),
      ],
    );

    await _selectRow(tester, 'Ash Trays');
    await _selectRow(tester, 'Bathroom Kit');
    await _selectRow(tester, 'Scrap');
    await _type(tester, 'item', 'Offcut');
    await _tick(tester, 'item');

    expect(harness.itemRepo.created.single.groupId, _scrap.id);
    expect(
      harness.inventoryRepo.saved,
      isEmpty,
      reason: 'nothing on the server would refuse the cross-group line',
    );
  });

  testWidgets('a failed item create keeps the typing and the draft', (
    tester,
  ) async {
    final harness = await _pumpWizard(tester);
    harness.itemRepo.throwOnCreate = true;

    await _selectRow(tester, 'Ash Trays');
    await _type(tester, 'set', 'Bathroom Kit');
    await _tick(tester, 'set');
    await _type(tester, 'item', 'Lid');
    await _tick(tester, 'item');

    expect(harness.inventoryRepo.saved, isEmpty);
    expect(find.textContaining('is not created yet'), findsOneWidget);
    expect(
      _textIn(tester, 'item'),
      'Lid',
      reason: 'clearing the row on failure throws away the typing',
    );
    expect(find.textContaining('Item rejected.'), findsOneWidget);
  });

  testWidgets('a failed set create says the item was still made', (
    tester,
  ) async {
    final harness = await _pumpWizard(tester);
    harness.inventoryRepo.throwOnSave = true;

    await _selectRow(tester, 'Ash Trays');
    await _type(tester, 'set', 'Bathroom Kit');
    await _tick(tester, 'set');
    await _type(tester, 'item', 'Lid');
    await _tick(tester, 'item');

    expect(harness.itemRepo.created, hasLength(1));
    expect(
      find.textContaining('is not created yet'),
      findsOneWidget,
      reason: 'the draft survives',
    );
    expect(find.textContaining('Created "Lid"'), findsOneWidget);
    expect(find.textContaining('Bathroom Kit'), findsWidgets);
  });

  testWidgets('an existing item can be appended instead of retyped', (
    tester,
  ) async {
    final harness = await _pumpWizard(
      tester,
      sets: <InventorySetDefinition>[
        _set(5, 'Bathroom Kit', groupId: _ashTrays.id),
      ],
      items: <ItemDefinition>[_item(42, 'Cone 90mm', groupId: _ashTrays.id)],
    );

    await _selectRow(tester, 'Ash Trays');
    await _selectRow(tester, 'Bathroom Kit');
    // Tapping the row selects the part for Developed For; filing it into the
    // set is the explicit + beside it.
    await _addToSet(tester, 'Cone 90mm');

    expect(harness.itemRepo.created, isEmpty, reason: 'it exists already');
    expect(harness.inventoryRepo.saved, hasLength(1));
    expect(harness.inventoryRepo.saved.single.lines.single.itemId, 42);
  });

  testWidgets('an item with variations cannot be filed at leaf zero', (
    tester,
  ) async {
    final withTree = _item(
      43,
      'Socket',
      groupId: _ashTrays.id,
      tree: <ItemVariationNodeDefinition>[
        _node(
          1,
          itemId: 43,
          kind: ItemVariationNodeKind.property,
          children: <ItemVariationNodeDefinition>[
            _node(
              2,
              itemId: 43,
              parentNodeId: 1,
              kind: ItemVariationNodeKind.value,
            ),
          ],
        ),
      ],
    );
    final harness = await _pumpWizard(
      tester,
      sets: <InventorySetDefinition>[
        _set(5, 'Bathroom Kit', groupId: _ashTrays.id),
      ],
      items: <ItemDefinition>[withTree],
    );

    expect(canFileAtLeafZero(withTree), isFalse);

    await _selectRow(tester, 'Ash Trays');
    await _selectRow(tester, 'Bathroom Kit');
    // Selecting it is allowed — it has a Developed For like any part.
    await _selectRow(tester, 'Socket');

    // The File button is drawn, and refuses with a reason rather than
    // disappearing.
    expect(tester.widget<AppButton>(_fileIntoSetButton()).onPressed, isNull);
    expect(
      tester
          .widget<Tooltip>(
            find
                .ancestor(
                  of: _fileIntoSetButton(),
                  matching: find.byType(Tooltip),
                )
                .first,
          )
          .message,
      contains('has variations'),
    );
    expect(
      harness.inventoryRepo.saved,
      isEmpty,
      reason: 'selecting a part never files it anywhere',
    );
    // And the row said why before it was ever picked.
    await _openPicker(tester, 'part');
    expect(find.textContaining('has variations'), findsOneWidget);
  });

  testWidgets('a duplicate set name leaves the tick disabled', (tester) async {
    await _pumpWizard(
      tester,
      sets: <InventorySetDefinition>[
        _set(5, 'Bathroom Kit', groupId: _ashTrays.id),
      ],
    );

    await _selectRow(tester, 'Ash Trays');
    await _type(tester, 'set', 'bathroom kit');

    expect(
      _canTick(tester, 'set'),
      isFalse,
      reason: 'nothing on the server refuses a duplicate set name',
    );
    expect(find.textContaining('already filed here'), findsOneWidget);
  });

  testWidgets('a duplicate group name is refused before it is sent', (
    tester,
  ) async {
    final harness = await _pumpWizard(tester);

    await _selectRow(tester, 'Ash Trays');
    await _type(tester, 'group', 'Scrap');
    // Scrap is a sibling under Primary Group, not under Ash Trays, so nesting
    // makes this legal; flipping to top level is what clashes.
    await tester.tap(find.textContaining('under Ash Trays'));
    await tester.pumpAndSettle();
    await _tick(tester, 'group');

    expect(harness.groupRepo.created, isEmpty);
    expect(find.textContaining('already exists there'), findsOneWidget);
  });

  testWidgets('archived groups, units and items are never offered', (
    tester,
  ) async {
    final harness = await _pumpWizard(
      tester,
      groups: <GroupDefinition>[_primary, _ashTrays, _scrap, _retiredGroup],
      units: <UnitDefinition>[_pieces, _kilos, _retiredUnit],
      items: <ItemDefinition>[
        _item(50, 'Live Lid', groupId: _ashTrays.id),
        _item(51, 'Dead Lid', groupId: _ashTrays.id, isArchived: true),
      ],
    );

    expect(find.textContaining('Retired Line'), findsNothing);

    await _selectRow(tester, 'Ash Trays');
    await _openPicker(tester, 'part');
    expect(find.text('Live Lid'), findsOneWidget);
    expect(find.text('Dead Lid'), findsNothing);
    await _closePicker(tester);

    // An archived unit is never offered, and never seeded either — the row
    // seeds from the same list it offers.
    await _type(tester, 'item', 'Lid');
    await _tick(tester, 'item');
    expect(harness.itemRepo.created.single.unitId, isNot(_retiredUnit.id));
    expect(find.textContaining('Retired'), findsNothing);
  });

  testWidgets('Esc clears the row being typed before it closes anything', (
    tester,
  ) async {
    await _pumpWizard(tester);

    await _selectRow(tester, 'Ash Trays');
    await _type(tester, 'item', 'Lid');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(_textIn(tester, 'item'), isEmpty);
    expect(
      find.byType(CatalogQuickEntryDialog),
      findsOneWidget,
      reason:
          'the first Esc meant "cancel this row", not "discard the session"',
    );
  });

  testWidgets('Enter in the name field ticks that row', (tester) async {
    final harness = await _pumpWizard(tester);

    await _selectRow(tester, 'Ash Trays');
    await _type(tester, 'item', 'Lid');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(harness.itemRepo.created, hasLength(1));
  });

  testWidgets(
    'the dropdowns hold at three widths, never under a LayoutBuilder',
    (tester) async {
      for (final size in <Size>[
        const Size(1600, 1400),
        const Size(1000, 1200),
        const Size(820, 1400),
      ]) {
        await _pumpWizard(tester, size: size);
        for (final slug in const ['group', 'set', 'part']) {
          expect(
            _picker(slug),
            findsOneWidget,
            reason: 'the $slug dropdown is there at ${size.width}',
          );
        }
        // These are overlay-bearing lists, which is the hazard: the assert does
        // not reproduce in a widget test, so the guard has to be structural.
        expect(
          find.ancestor(
            of: _picker('group'),
            matching: find.byType(LayoutBuilder),
          ),
          findsNothing,
        );
      }
    },
  );

  // --- part identity ---------------------------------------------------------

  testWidgets('the part no and code fill in, and the tick sends them', (
    tester,
  ) async {
    final harness = await _pumpWizard(tester);

    await _selectRow(tester, 'Ash Trays');
    await _type(tester, 'item', 'Patti');
    await tester.pumpAndSettle();

    expect(_textIn(tester, 'item-part-no'), '48');
    expect(_textIn(tester, 'item-part-code'), isNotEmpty);

    await _tick(tester, 'item');

    final input = harness.itemRepo.created.single;
    expect(input.partNo, 48);
    expect(input.partCode, isNotEmpty);
  });

  testWidgets('the code is only a hint until the part has a name', (
    tester,
  ) async {
    final harness = await _pumpWizard(tester);
    harness.itemRepo.nextCode = 'SAD48';

    await _selectRow(tester, 'Ash Trays');
    await tester.pumpAndSettle();

    // Derived, shown, and deliberately not a value: a code nobody typed must
    // not be tickable, and touching the field must not pin it.
    expect(_textIn(tester, 'item-part-code'), isEmpty);
    final field = tester.widget<TextField>(_field('item-part-code'));
    expect(field.decoration!.hintText, 'SAD48');
  });

  testWidgets('editing the number re-derives the code', (tester) async {
    await _pumpWizard(tester);

    await _selectRow(tester, 'Ash Trays');
    await _type(tester, 'item', 'Patti');
    await _type(tester, 'item-part-no', '50');

    // One letter per word of the group and the name, then the number.
    expect(_textIn(tester, 'item-part-code'), 'ATP50');
  });

  testWidgets('editing the code pins it against a later name change', (
    tester,
  ) async {
    await _pumpWizard(tester);

    await _selectRow(tester, 'Ash Trays');
    await _type(tester, 'item', 'Patti');
    await _type(tester, 'item-part-code', 'LEGACY-7');
    await _type(tester, 'item', 'Patti Long');

    expect(
      _textIn(tester, 'item-part-code'),
      'LEGACY-7',
      reason: 'a code someone typed is theirs, not the wizard\'s to rewrite',
    );
  });

  testWidgets('changing the set asks again for the number in that scope', (
    tester,
  ) async {
    final harness = await _pumpWizard(
      tester,
      sets: <InventorySetDefinition>[
        _set(5, 'Bathroom Kit', groupId: _ashTrays.id),
      ],
    );

    await _selectRow(tester, 'Ash Trays');
    harness.itemRepo.identityAsks.clear();
    await _selectRow(tester, 'Bathroom Kit');
    await tester.pumpAndSettle();

    expect(
      harness.itemRepo.identityAsks.any((ask) => ask.contains('/5/')),
      isTrue,
      reason: '48 of Dolly is not 48 of Chakri',
    );
  });

  testWidgets('a ticked set name asks for the number of an empty scope', (
    tester,
  ) async {
    final harness = await _pumpWizard(tester);

    await _selectRow(tester, 'Ash Trays');
    harness.itemRepo.identityAsks.clear();
    await _type(tester, 'set', 'Bathroom Kit');
    await _tick(tester, 'set');
    await tester.pumpAndSettle();

    expect(
      harness.itemRepo.identityAsks.any(
        (ask) => ask.contains('pending:Bathroom Kit'),
      ),
      isTrue,
      reason:
          'a set that is only named holds nothing, so this part is its first — '
          'and its name has to travel, because nothing can look a draft up',
    );
  });

  testWidgets('a taken part code offers a fresh one instead of retrying', (
    tester,
  ) async {
    final harness = await _pumpWizard(tester);
    harness.itemRepo.clashOnCreate = true;

    await _selectRow(tester, 'Ash Trays');
    await _type(tester, 'item', 'Patti');
    harness.itemRepo.nextNo = 49;
    harness.itemRepo.nextCode = 'ATP49';
    await _tick(tester, 'item');
    await tester.pumpAndSettle();

    expect(
      harness.itemRepo.created,
      hasLength(1),
      reason: 'a silent retry after a 409 is how two parts get created',
    );
    expect(_textIn(tester, 'item-part-no'), '49');
    expect(find.textContaining('already used'), findsOneWidget);
  });

  testWidgets('identity resets to automatic after a successful tick', (
    tester,
  ) async {
    final harness = await _pumpWizard(tester);

    await _selectRow(tester, 'Ash Trays');
    await _type(tester, 'item', 'Patti');
    await _type(tester, 'item-part-code', 'PINNED1');
    harness.itemRepo.nextNo = 49;
    harness.itemRepo.nextCode = 'ATP49';
    await _tick(tester, 'item');
    await tester.pumpAndSettle();

    expect(harness.itemRepo.created.single.partCode, 'PINNED1');
    // The screen stays on the part just made, so the next one starts here.
    await _selectRow(tester, 'New part…');
    // The pin belonged to that part, not to the sheet.
    expect(_textIn(tester, 'item-part-no'), '49');
    expect(_textIn(tester, 'item-part-code'), isEmpty);
  });

  testWidgets('a listed part shows its code and the day it was stamped', (
    tester,
  ) async {
    await _pumpWizard(
      tester,
      items: <ItemDefinition>[
        _item(
          42,
          'Cone 90mm',
          groupId: _ashTrays.id,
          partNo: 12,
          partCode: 'ATC12',
          createdAt: DateTime(2026, 5, 15, 10, 5),
        ),
        _item(43, 'Plain Lid', groupId: _ashTrays.id),
      ],
    );

    await _selectRow(tester, 'Ash Trays');
    await _openPicker(tester, 'part');

    expect(find.textContaining('ATC12 · 15/05/2026'), findsOneWidget);
    // A part with no code shows no separator standing where one would be.
    expect(find.textContaining('· 15/05/2026'), findsOneWidget);
    expect(find.text('15/05/2026'), findsOneWidget);
  });

  testWidgets('a row that cannot be filed still says why', (tester) async {
    final withTree = _item(
      43,
      'Socket',
      groupId: _ashTrays.id,
      partCode: 'ATS9',
      tree: <ItemVariationNodeDefinition>[
        _node(
          1,
          itemId: 43,
          kind: ItemVariationNodeKind.property,
          children: <ItemVariationNodeDefinition>[
            _node(
              2,
              itemId: 43,
              parentNodeId: 1,
              kind: ItemVariationNodeKind.value,
            ),
          ],
        ),
      ],
    );
    await _pumpWizard(
      tester,
      sets: <InventorySetDefinition>[
        _set(5, 'Bathroom Kit', groupId: _ashTrays.id),
      ],
      items: <ItemDefinition>[withTree],
    );

    await _selectRow(tester, 'Ash Trays');
    await _selectRow(tester, 'Bathroom Kit');
    await _openPicker(tester, 'part');

    // The subtitle is the only place the user learns why the row cannot be
    // filed, so the identity line never takes its place.
    expect(
      find.textContaining('has variations — add it from the set editor'),
      findsOneWidget,
    );
  });

  // mergeSetLines and its siblings now live in set_membership_test.dart,
  // beside the rules themselves.
}

/// --- Developed For ---------------------------------------------------------
///
/// The wizard's claim is that a part is created complete, in one call: where
/// it goes and who it is for are filled in on one screen, and the tick writes
/// all of it at once. A part that already exists is edited in the same panel
/// and saved on its own.

/// Taps something that may be below the fold — the sections scroll as one now,
/// so Developed For is often off-screen when a test reaches for it.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

/// Picks a client in the Developed For form: For → Client, then the party.
Future<void> _pickClient(WidgetTester tester, String name) async {
  await _tapVisible(tester, find.text('Client'));
  await _tapVisible(tester, find.widgetWithText(AppButton, 'Pick'));
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void _developedForWizardTests() {
  testWidgets('the columns and Developed For are both on screen at once', (
    tester,
  ) async {
    await _pumpWizard(tester);

    // Where the part goes, what it is, and who it is for — one screen, no
    // fold and no columns. That is what the dropdowns bought.
    expect(_picker('group'), findsOneWidget);
    expect(_picker('set'), findsOneWidget);
    expect(_picker('part'), findsOneWidget);
    expect(find.text('New part'), findsOneWidget);
    expect(find.text('Developed For · next part'), findsOneWidget);
    expect(find.byType(DevelopedForForm), findsOneWidget);
    expect(_field('item'), findsOneWidget);
    // And a record of what has been made, which is what the columns used to be
    // for.
    expect(find.text('Made just now'), findsOneWidget);

    await _selectRow(tester, 'Ash Trays');
    expect(_picker('part'), findsOneWidget);
    expect(find.text('Developed For · next part'), findsOneWidget);
    // And one line says where a tick lands.
    expect(find.text('Goes into Ash Trays'), findsOneWidget);
  });

  testWidgets('a tick carries the block, in the one call that makes the part', (
    tester,
  ) async {
    final harness = await _pumpWizard(tester);

    await _selectRow(tester, 'Ash Trays');
    await _pickClient(tester, 'Gold Madel Industries');

    // The person is read off the client, so the form shows it without the
    // part having been saved yet.
    expect(find.text('Kissan Jain'), findsOneWidget);
    expect(find.text('Director'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, '₹ ').first,
      '85000',
    );
    await tester.pumpAndSettle();
    await _type(tester, 'item', 'Lid');
    await _tick(tester, 'item');

    expect(harness.itemRepo.created, hasLength(1));
    final block = harness.itemRepo.created.single.developedFor;
    expect(block, isNotNull);
    expect(block!.kind, DevelopedForKind.client);
    expect(block.clientId, _goldMadel.id);
    expect(block.quotationAmount, 85000);

    // One call, about the part. Nothing was written to the client to record
    // that it now has a part developed for it.
    expect(harness.clientRepo.writes, isEmpty);
    expect(harness.inventoryRepo.saved, isEmpty, reason: 'no set is in play');
  });

  testWidgets('the form stays filled, and a changed party splits the run', (
    tester,
  ) async {
    final harness = await _pumpWizard(tester);

    await _selectRow(tester, 'Ash Trays');
    await _pickClient(tester, 'Gold Madel Industries');

    await _type(tester, 'item', 'Lid');
    await _tick(tester, 'item');
    // The screen stays on the part just made, so the next one starts from
    // "New part…" — and the draft is still filled when it gets there.
    await _selectRow(tester, 'New part…');
    await _type(tester, 'item', 'Base');
    await _tick(tester, 'item');

    // Then the party changes on the draft, and only the parts made afterwards
    // follow it.
    await _selectRow(tester, 'New part…');
    await _tapVisible(tester, find.widgetWithText(AppButton, 'Change'));
    await tester.tap(find.text('Sunrise Retail').last);
    await tester.pumpAndSettle();
    await _type(tester, 'item', 'Clip');
    await _tick(tester, 'item');

    expect(harness.itemRepo.created, hasLength(3));
    expect(harness.itemRepo.created[0].developedFor!.clientId, _goldMadel.id);
    expect(harness.itemRepo.created[1].developedFor!.clientId, _goldMadel.id);
    expect(harness.itemRepo.created[2].developedFor!.clientId, _sunrise.id);
    // Three parts, three calls — never a second write per part to attach the
    // block afterwards.
    expect(harness.clientRepo.writes, isEmpty);
  });

  testWidgets('saying nothing sends nothing, so the column is left alone', (
    tester,
  ) async {
    final harness = await _pumpWizard(tester);

    await _selectRow(tester, 'Ash Trays');
    await _type(tester, 'item', 'Lid');
    await _tick(tester, 'item');

    // Null, not an empty block: an empty block is "developed for nobody", and
    // nobody said that.
    expect(harness.itemRepo.created.single.developedFor, isNull);
  });
}

/// --- editing a part that already exists ------------------------------------
///
/// "After this whole thing for items is done I can click on that item and go
/// on for developed for." The panel below the columns edits one of two
/// different things and has to say which: the next part to be ticked, or the
/// part that was clicked. Getting that wrong would mean looking at an old part
/// quietly rewrote what the next tick stamps.
void _selectedPartTests() {
  testWidgets('clicking a part points the panel at it, and back again', (
    tester,
  ) async {
    await _pumpWizard(
      tester,
      items: <ItemDefinition>[_item(42, 'Cone 90mm', groupId: _ashTrays.id)],
    );

    await _selectRow(tester, 'Ash Trays');
    expect(find.text('Developed For · next part'), findsOneWidget);

    await _selectRow(tester, 'Cone 90mm');
    expect(find.text('Developed For · Cone 90mm'), findsOneWidget);
    expect(find.text('Developed For · next part'), findsNothing);
    // The Part section names it too, so a Save is never about an unnamed part.
    expect(find.text('Part · Cone 90mm'), findsOneWidget);
  });

  testWidgets('a selected part never disturbs what the next tick stamps', (
    tester,
  ) async {
    final harness = await _pumpWizard(
      tester,
      items: <ItemDefinition>[_item(42, 'Cone 90mm', groupId: _ashTrays.id)],
    );

    await _selectRow(tester, 'Ash Trays');
    await _pickClient(tester, 'Gold Madel Industries');

    // Walk over to an existing part, change its kind, then come back and tick.
    await _selectRow(tester, 'Cone 90mm');
    await _tapVisible(tester, find.text('Self'));
    await _selectRow(tester, 'New part…');

    await _type(tester, 'item', 'Lid');
    await _tick(tester, 'item');

    expect(harness.itemRepo.created, hasLength(1));
    final block = harness.itemRepo.created.single.developedFor;
    expect(block, isNotNull);
    expect(block!.kind, DevelopedForKind.client);
    expect(block.clientId, _goldMadel.id);
    // And the poke at the other part was staged only — nothing was written.
    expect(harness.itemRepo.updated, isEmpty);
  });

  testWidgets('Save writes the block once and keeps the rest of the part', (
    tester,
  ) async {
    final harness = await _pumpWizard(
      tester,
      items: <ItemDefinition>[
        _item(
          42,
          'Cone 90mm',
          groupId: _ashTrays.id,
          partNo: 9,
          partCode: 'ATC9',
        ),
      ],
    );

    await _selectRow(tester, 'Ash Trays');
    await _selectRow(tester, 'Cone 90mm');

    // Nothing has changed, so there is nothing to save.
    expect(_saveButton(), findsNothing);

    await _pickClient(tester, 'Gold Madel Industries');
    expect(_saveButton(), findsOneWidget);
    await _tapVisible(tester, _saveButton());

    expect(harness.itemRepo.updated, hasLength(1));
    final input = harness.itemRepo.updated.single;
    expect(input.id, 42);
    expect(input.developedFor!.kind, DevelopedForKind.client);
    expect(input.developedFor!.clientId, _goldMadel.id);
    // One PATCH, carrying everything the part already had.
    expect(input.name, 'Cone 90mm');
    expect(input.partNo, 9);
    expect(input.partCode, 'ATC9');
    expect(harness.itemRepo.created, isEmpty);

    // Spent: the part carries it now, so the panel stops offering to save it.
    expect(_saveButton(), findsNothing);
    expect(find.text('Developed For · Cone 90mm'), findsOneWidget);
  });

  testWidgets('Cancel throws the edit away and writes nothing', (tester) async {
    final harness = await _pumpWizard(
      tester,
      items: <ItemDefinition>[_item(42, 'Cone 90mm', groupId: _ashTrays.id)],
    );

    await _selectRow(tester, 'Ash Trays');
    await _selectRow(tester, 'Cone 90mm');
    await _pickClient(tester, 'Gold Madel Industries');
    expect(find.text('Gold Madel Industries'), findsWidgets);

    await _tapVisible(tester, find.text('Cancel'));

    expect(harness.itemRepo.updated, isEmpty);
    expect(_saveButton(), findsNothing);
    // Back to what the part actually carries, which is nothing.
    expect(find.text('Gold Madel Industries'), findsNothing);
  });

  testWidgets('a kind with nobody picked cannot be saved', (tester) async {
    final harness = await _pumpWizard(
      tester,
      items: <ItemDefinition>[_item(42, 'Cone 90mm', groupId: _ashTrays.id)],
    );

    await _selectRow(tester, 'Ash Trays');
    await _selectRow(tester, 'Cone 90mm');
    // Client, but no client — the same refusal the server gives with a 400.
    await tester.tap(find.text('Client'));
    await tester.pumpAndSettle();

    expect(_saveButton(), findsOneWidget);
    expect(tester.widget<AppButton>(_saveButton()).onPressed, isNull);
    await _tapVisible(tester, _saveButton());
    expect(harness.itemRepo.updated, isEmpty);
  });
}

Finder _saveButton() =>
    find.byKey(const ValueKey<String>('quick-entry-developed-for-save'));

/// --- the made-just-now list ------------------------------------------------
///
/// Dropping the columns dropped the only place that said what exists and what
/// you have just done. This list is what replaced it, so it has to be right
/// about the scope each part was made in — a row that restores a scope that
/// never existed would number the next part wrongly.
void _madeListTests() {
  Finder madeRow(int itemId) =>
      find.byKey(ValueKey<String>('quick-entry-made-row-$itemId'));

  testWidgets('one row per part, naming the group it went into', (
    tester,
  ) async {
    await _pumpWizard(tester);

    expect(find.text('Made just now'), findsOneWidget);
    expect(find.textContaining('Nothing yet'), findsOneWidget);

    await _selectRow(tester, 'Ash Trays');
    await _type(tester, 'item', 'Lid');
    await _tick(tester, 'item');

    expect(madeRow(801), findsOneWidget);
    expect(find.textContaining('Ash Trays › Lid'), findsOneWidget);
    expect(find.textContaining('Nothing yet'), findsNothing);

    await _selectRow(tester, 'New part…');
    await _type(tester, 'item', 'Base');
    await _tick(tester, 'item');
    expect(madeRow(802), findsOneWidget);
    // Newest first: the one just made is the one you are most likely to want.
    final rows = tester.widgetList(find.byType(InkWell)).length;
    expect(rows, greaterThan(0));
  });

  testWidgets('a row goes back to its part AND the scope it was made in', (
    tester,
  ) async {
    await _pumpWizard(
      tester,
      sets: <InventorySetDefinition>[
        _set(5, 'Bathroom Kit', groupId: _ashTrays.id),
      ],
    );

    await _selectRow(tester, 'Ash Trays');
    await _selectRow(tester, 'Bathroom Kit');
    await _type(tester, 'item', 'Lid');
    await _tick(tester, 'item');

    // Walk away: another group, no set.
    await _selectRow(tester, 'Scrap');
    expect(find.text('Goes into Scrap'), findsOneWidget);

    await _tapVisible(tester, madeRow(801));

    // The part is selected and so is everything above it, or the next part
    // number would be computed in a scope nobody is looking at.
    expect(find.text('Part · Lid'), findsOneWidget);
    expect(find.text('Developed For · Lid'), findsOneWidget);
    expect(
      find.text('Goes into Ash Trays · line of Bathroom Kit'),
      findsOneWidget,
    );
  });

  testWidgets('a row made into a named set takes the real set once it exists', (
    tester,
  ) async {
    final harness = await _pumpWizard(tester);

    await _selectRow(tester, 'Ash Trays');
    await _type(tester, 'set', 'Bathroom Kit');
    await _tick(tester, 'set');
    await _type(tester, 'item', 'Lid');
    await _tick(tester, 'item');

    // The set exists now, and the row names it.
    expect(harness.inventoryRepo.saved, hasLength(1));
    expect(
      find.textContaining('Ash Trays › Bathroom Kit › Lid'),
      findsOneWidget,
    );

    // And going back through it restores the set that was created, not the
    // draft that no longer exists.
    await _selectRow(tester, 'Scrap');
    await _tapVisible(tester, madeRow(801));
    expect(
      find.text('Goes into Ash Trays · line of Bathroom Kit'),
      findsOneWidget,
    );
    expect(find.textContaining('is not created yet'), findsNothing);
  });
}

/// --- the die sheet ---------------------------------------------------------
///
/// A die made here is a row in the dies master, linked to the part. The write
/// goes through an AppFlowHooks seam because `Die` lives in the app, not in
/// this package — so these tests stub the seam and watch what it is handed.
void _dieSectionTests() {
  group('the die sheet', () {
    late List<DieSheetDraft> drafts;
    late DieCreateOutcome outcome;

    setUp(() {
      drafts = <DieSheetDraft>[];
      outcome = const DieCreateOutcome.created(
        CreatedRecord(id: '77', title: 'CDSADP48'),
      );
      // Static hooks leak between tests silently, so every one that sets them
      // takes them down again.
      AppFlowHooks.createDieFromSheet = (context, draft) async {
        drafts.add(draft);
        return outcome;
      };
      AppFlowHooks.dieMadeByNames = (context) async => <String>['Atul Mestry'];
    });

    tearDown(() {
      AppFlowHooks.createDieFromSheet = null;
      AppFlowHooks.dieMadeByNames = null;
    });

    Finder dieField(String slug) =>
        find.byKey(ValueKey<String>('quick-entry-die-$slug-field'));
    Finder addDie() =>
        find.byKey(const ValueKey<String>('quick-entry-add-die'));

    /// Makes a part and selects it, which is what the Die section needs.
    Future<_Harness> partOnScreen(WidgetTester tester) async {
      final harness = await _pumpWizard(tester);
      await _selectRow(tester, 'Ash Trays');
      await _type(tester, 'item', 'Patti');
      await _tick(tester, 'item');
      await _selectRow(tester, 'Patti');
      return harness;
    }

    testWidgets('the section is open before the part exists', (tester) async {
      await _pumpWizard(tester);

      // No gate: the whole part is filled in on one screen and written by one
      // press, rather than saved halfway through a thought.
      await tester.ensureVisible(find.textContaining('Dies · '));
      expect(find.textContaining('held until you create the part'), findsOneWidget);
      expect(addDie(), findsOneWidget);
      expect(
        find.descendant(of: addDie(), matching: find.text('Hold die')),
        findsOneWidget,
      );
    });

    testWidgets(
      'the code is built from the type and the part, and re-derives',
      (tester) async {
        await partOnScreen(tester);

        await _tapVisible(tester, find.text('Cutting'));
        expect(_textIn(tester, 'die-code'), 'CDATP48');

        // The type is what the initials come from, so changing it changes them.
        await _tapVisible(tester, find.text('Bending'));
        expect(_textIn(tester, 'die-code'), 'BDATP48');
      },
    );

    testWidgets('a code typed over is pinned against a later type change', (
      tester,
    ) async {
      await partOnScreen(tester);

      await _tapVisible(tester, find.text('Cutting'));
      await tester.enterText(dieField('code'), 'SPECIAL-1');
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('Bending'));

      expect(_textIn(tester, 'die-code'), 'SPECIAL-1');
      expect(find.textContaining('Typed over'), findsOneWidget);
    });

    testWidgets('Add die hands the sheet over once, then links it to the part', (
      tester,
    ) async {
      final harness = await partOnScreen(tester);

      await _tapVisible(tester, find.text('Cutting'));
      await tester.enterText(dieField('made-by'), 'Atul Mestry');
      await tester.enterText(dieField('liner'), '94.50');
      await tester.enterText(dieField('sets'), '1');
      await tester.enterText(dieField('area'), 'F206');
      await tester.enterText(dieField('rack'), '23-4');
      await tester.pumpAndSettle();
      await _tapVisible(tester, addDie());

      expect(drafts, hasLength(1));
      final draft = drafts.single;
      expect(draft.toolCode, 'CDATP48');
      expect(draft.dieType, 'cutting');
      expect(draft.madeBy, 'Atul Mestry');
      // 94.50 mm in whole nanometres, which is what the units contract asks for.
      expect(draft.linerSizeNm, 94500000);
      expect(draft.linerSizeUnit, 'mm');
      expect(draft.noOfSet, 1);
      expect(draft.storeArea, 'F206');
      expect(draft.rackNo, '23-4');
      expect(draft.partCode, 'ATP48');

      // And then the part was told about it — one update, carrying die ids.
      expect(harness.itemRepo.updated, hasLength(1));
      expect(harness.itemRepo.updated.single.dieIds, contains('77'));
      expect(find.textContaining('is on this part'), findsOneWidget);
    });

    testWidgets('a taken code offers a free one and does not write again', (
      tester,
    ) async {
      await partOnScreen(tester);
      outcome = const DieCreateOutcome.failed(
        message: 'Die code "CDSADP48" is already used by die #3.',
        code: 'die_tool_code_duplicate',
        suggestedToolCode: 'CDSADP48-2',
      );

      await _tapVisible(tester, find.text('Cutting'));
      await _tapVisible(tester, addDie());

      expect(drafts, hasLength(1), reason: 'refused once, never retried');
      // The offer is in the field, pinned, so ticking again sends the free one.
      expect(_textIn(tester, 'die-code'), 'CDSADP48-2');
      expect(find.textContaining('already used by die'), findsOneWidget);
    });

    testWidgets('a die that could not be linked is attached, never remade', (
      tester,
    ) async {
      final harness = await partOnScreen(tester);
      harness.itemRepo.throwOnUpdate = true;

      await _tapVisible(tester, find.text('Cutting'));
      await _tapVisible(tester, addDie());

      expect(drafts, hasLength(1));
      expect(find.textContaining('could not be attached'), findsOneWidget);
      // The button says what it will do now, and it is not "make another die".
      expect(
        find.descendant(of: addDie(), matching: find.text('Attach the die')),
        findsOneWidget,
      );

      harness.itemRepo.throwOnUpdate = false;
      await _tapVisible(tester, addDie());

      expect(drafts, hasLength(1), reason: 'the die already exists');
      expect(harness.itemRepo.updated.last.dieIds, contains('77'));
    });

    testWidgets('a liner size that is not a whole nanometre is refused', (
      tester,
    ) async {
      await partOnScreen(tester);

      await _tapVisible(tester, find.text('Cutting'));
      await tester.enterText(dieField('liner'), 'wide');
      await tester.pumpAndSettle();
      await _tapVisible(tester, addDie());

      expect(
        drafts,
        isEmpty,
        reason: 'nothing is written on a bad measurement',
      );
      expect(find.text('Not a measurement'), findsOneWidget);
    });

    testWidgets('without the hook the section offers nothing', (tester) async {
      AppFlowHooks.createDieFromSheet = null;
      await _pumpWizard(tester);

      await tester.ensureVisible(find.textContaining('Dies · '));
      expect(find.textContaining('cannot be made from here'), findsOneWidget);
      expect(addDie(), findsNothing);
    });

    testWidgets('Done is the only primary button, so Cmd+Enter cannot write', (
      tester,
    ) async {
      await partOnScreen(tester);
      await _tapVisible(tester, find.text('Cutting'));

      final primaries = tester
          .widgetList<AppButton>(find.byType(AppButton))
          .where((button) => button.variant == AppButtonVariant.primary)
          .toList();
      expect(
        primaries.map((button) => button.label),
        ['Done'],
        reason:
            'SubmitFormShortcuts fires the last enabled primary in the tree',
      );
    });
  });
}

/// --- more than one die -----------------------------------------------------
///
/// A part holds as many dies as it needs — a cutting die and a bending die, or
/// two of a kind. So the section is a list first and a form second: the list
/// says what tells them apart, tapping one corrects it, and taking one off the
/// part leaves the tool alone.
void _manyDiesTests() {
  group('more than one die', () {
    late List<DieSheetDraft> drafts;
    late int nextDieId;

    setUp(() {
      drafts = <DieSheetDraft>[];
      nextDieId = 70;
      AppFlowHooks.createDieFromSheet = (context, draft) async {
        drafts.add(draft);
        return DieCreateOutcome.created(
          CreatedRecord(
            id: draft.dieId ?? '${nextDieId++}',
            title: draft.toolCode,
          ),
        );
      };
      AppFlowHooks.dieMadeByNames = (context) async => const <String>[];
    });

    tearDown(() {
      AppFlowHooks.createDieFromSheet = null;
      AppFlowHooks.dieMadeByNames = null;
    });

    Finder dieRow(String id) =>
        find.byKey(ValueKey<String>('quick-entry-die-row-$id'));
    Finder addDie() =>
        find.byKey(const ValueKey<String>('quick-entry-add-die'));

    /// A part with one cutting die already on it.
    Future<_Harness> partWithADie(WidgetTester tester) async {
      final harness = await _pumpWizard(
        tester,
        items: <ItemDefinition>[
          _item(42, 'Patti', groupId: _ashTrays.id, partCode: 'ATP48'),
        ],
      );
      harness.itemRepo.dieRows['70'] = ItemDieLink(
        id: '70',
        toolCode: 'CDATP48',
        dieType: 'cutting',
        madeBy: 'Atul Mestry',
        linerSizeNm: 94500000,
        noOfSet: 1,
        storeArea: 'F206',
        rackNo: '23-4',
      );
      await _selectRow(tester, 'Ash Trays');
      await _selectRow(tester, 'Patti');
      await _tapVisible(tester, find.text('Cutting'));
      await _tapVisible(tester, addDie());
      return harness;
    }

    testWidgets('a second die goes on beside the first, not over it', (
      tester,
    ) async {
      final harness = await partWithADie(tester);
      harness.itemRepo.dieRows['71'] = const ItemDieLink(
        id: '71',
        toolCode: 'BDATP48',
        dieType: 'bending',
        madeBy: 'Suresh Amb',
      );

      expect(dieRow('70'), findsOneWidget);
      // What tells them apart, not just the code.
      expect(find.textContaining('Cutting · Atul Mestry'), findsOneWidget);
      expect(find.textContaining('F206 · Rack 23-4'), findsOneWidget);

      await _tapVisible(tester, find.text('Bending'));
      await _tapVisible(tester, addDie());

      expect(drafts, hasLength(2));
      expect(drafts[1].toolCode, 'BDATP48');
      // The link carries BOTH: it is a full replace, so a bare [newId] would
      // drop the die that was already there.
      expect(harness.itemRepo.updated.last.dieIds, containsAll(['70', '71']));
      expect(dieRow('70'), findsOneWidget);
      expect(dieRow('71'), findsOneWidget);
    });

    testWidgets('a second die of the same kind takes the next free code', (
      tester,
    ) async {
      await partWithADie(tester);

      // The type stays picked between dies, so the sheet is already on Cutting:
      // the first one took CDATP48 and the next one is offered before anything
      // is sent, not after a refusal.
      expect(_textIn(tester, 'die-code'), 'CDATP48-2');
    });

    testWidgets('tapping a die loads it into the sheet, and Save updates it', (
      tester,
    ) async {
      final harness = await partWithADie(tester);

      await _tapVisible(tester, dieRow('70'));

      // The sheet is that die now, and says so.
      expect(find.text('Dies · ATP48 · CDATP48'), findsOneWidget);
      expect(_textIn(tester, 'die-code'), 'CDATP48');
      expect(_textIn(tester, 'die-made-by'), 'Atul Mestry');
      expect(_textIn(tester, 'die-liner'), '94.5');
      expect(_textIn(tester, 'die-area'), 'F206');
      expect(
        find.descendant(of: addDie(), matching: find.text('Save die')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('quick-entry-die-made-by-field')),
        'Suresh Amb',
      );
      await tester.pumpAndSettle();
      final updatesBefore = harness.itemRepo.updated.length;
      await _tapVisible(tester, addDie());

      // One write, naming the die — not a second die, and not a second link.
      expect(drafts, hasLength(2));
      expect(drafts.last.dieId, '70');
      expect(drafts.last.madeBy, 'Suresh Amb');
      expect(
        harness.itemRepo.updated.length,
        updatesBefore,
        reason: 'the die is already on the part',
      );
    });

    testWidgets('Cancel leaves the die alone and goes back to a blank sheet', (
      tester,
    ) async {
      await partWithADie(tester);

      await _tapVisible(tester, dieRow('70'));
      await tester.enterText(
        find.byKey(const ValueKey<String>('quick-entry-die-made-by-field')),
        'Nobody',
      );
      await tester.pumpAndSettle();
      await _tapVisible(
        tester,
        find.byKey(const ValueKey<String>('quick-entry-die-cancel')),
      );

      expect(drafts, hasLength(1), reason: 'nothing was written');
      expect(find.text('Dies · ATP48 · new'), findsOneWidget);
      expect(
        find.descendant(of: addDie(), matching: find.text('Add die')),
        findsOneWidget,
      );
    });

    testWidgets('taking a die off the part leaves it in the master', (
      tester,
    ) async {
      final harness = await partWithADie(tester);

      await _tapVisible(
        tester,
        find.descendant(of: dieRow('70'), matching: find.byType(IconButton)),
      );

      // One update, with that die gone from the list — and no delete anywhere.
      expect(harness.itemRepo.updated.last.dieIds, isEmpty);
      expect(dieRow('70'), findsNothing);
      expect(find.textContaining('still in the dies master'), findsOneWidget);
      expect(drafts, hasLength(1), reason: 'unlinking writes no die');
    });
  });
}

/// --- the machine sheet -----------------------------------------------------
///
/// The fourth sheet, and the same shape as the Die: a part runs on as many
/// machines as it needs, each a row in the machines master, listed with what
/// tells them apart.
void _machineSectionTests() {
  group('the machine sheet', () {
    late List<MachineSheetDraft> drafts;
    late int nextMachineId;

    setUp(() {
      drafts = <MachineSheetDraft>[];
      nextMachineId = 90;
      AppFlowHooks.createMachineFromSheet = (context, draft) async {
        drafts.add(draft);
        return MachineCreateOutcome.created(
          CreatedRecord(
            id: draft.machineId ?? '${nextMachineId++}',
            title: draft.assetId,
          ),
        );
      };
      AppFlowHooks.machineSheetSuggestions = (context) async =>
          const MachineSheetSuggestions(makes: <String>['Mayank']);
    });

    tearDown(() {
      AppFlowHooks.createMachineFromSheet = null;
      AppFlowHooks.machineSheetSuggestions = null;
    });

    Finder machineField(String slug) =>
        find.byKey(ValueKey<String>('quick-entry-machine-$slug-field'));
    Finder addMachine() =>
        find.byKey(const ValueKey<String>('quick-entry-add-machine'));
    Finder machineRow(String id) =>
        find.byKey(ValueKey<String>('quick-entry-machine-row-$id'));

    /// A part on screen, with a machine type to pick.
    Future<_Harness> partReady(WidgetTester tester) async {
      final harness = await _pumpWizard(
        tester,
        groups: <GroupDefinition>[
          _primary,
          _ashTrays,
          _scrap,
          _group(60, 'Power Press', groupType: 'machine'),
        ],
        items: <ItemDefinition>[
          _item(42, 'Patti', groupId: _ashTrays.id, partCode: 'ATP48'),
        ],
      );
      await _selectRow(tester, 'Ash Trays');
      await _selectRow(tester, 'Patti');
      return harness;
    }

    Future<void> pickType(WidgetTester tester, String name) async {
      await _tapVisible(
        tester,
        find.byKey(const ValueKey<String>('quick-entry-machine-type-field')),
      );
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    testWidgets('the section is open before the part exists', (tester) async {
      await _pumpWizard(tester);

      await tester.ensureVisible(find.textContaining('Machines · '));
      expect(
        find.textContaining('held until you create the part'),
        findsWidgets,
      );
      expect(addMachine(), findsOneWidget);
      expect(
        find.descendant(of: addMachine(), matching: find.text('Hold machine')),
        findsOneWidget,
      );
    });

    testWidgets('the number is built from the type and counts up', (
      tester,
    ) async {
      await partReady(tester);

      await pickType(tester, 'Power Press');
      // The first press of its type on this part.
      expect(_textIn(tester, 'machine-no'), 'PP-1');
    });

    testWidgets('a number typed over is pinned against a later type change', (
      tester,
    ) async {
      await partReady(tester);

      await pickType(tester, 'Power Press');
      await tester.enterText(machineField('no'), 'LATHE-7');
      await tester.pumpAndSettle();
      expect(_textIn(tester, 'machine-no'), 'LATHE-7');
      expect(find.textContaining('Typed over'), findsOneWidget);
    });

    testWidgets('Add hands the sheet over once, then links it to the part', (
      tester,
    ) async {
      final harness = await partReady(tester);

      await pickType(tester, 'Power Press');
      await tester.enterText(machineField('make'), 'Mayank');
      await tester.enterText(machineField('dom'), '2011');
      await tester.enterText(machineField('hours'), '5001');
      await tester.enterText(machineField('strokes'), '110');
      await tester.enterText(machineField('capacity'), '35');
      await tester.enterText(machineField('feeder'), 'Jay Shanti');
      await tester.enterText(machineField('feed'), 'Progressive');
      await tester.pumpAndSettle();
      await _tapVisible(tester, addMachine());

      expect(drafts, hasLength(1));
      final draft = drafts.single;
      expect(draft.assetId, 'PP-1');
      expect(draft.groupId, 60);
      expect(draft.machineMake, 'Mayank');
      expect(draft.manufacturedYear, 2011);
      expect(draft.runningHours, 5001);
      expect(draft.strokesPerMinute, 110);
      // 35 Ton in whole kilograms-force, which is what the units contract asks
      // for.
      expect(draft.capacityKind, 'rated');
      expect(draft.capacityKgf, 35000);
      expect(draft.feederMake, 'Jay Shanti');
      expect(draft.dieFeedType, 'Progressive');
      // A machine with no name of its own is known by its number.
      expect(draft.name, 'PP-1');

      expect(harness.itemRepo.updated, hasLength(1));
      expect(harness.itemRepo.updated.single.machineIds, contains('90'));
      // Naming machines leaves the dies alone — setItemLinks replaces only the
      // list it is given.
      expect(harness.itemRepo.updated.single.dieIds, isEmpty);
      expect(find.textContaining('is on this part'), findsOneWidget);
    });

    testWidgets('free hand is sent as its own answer, with no figure', (
      tester,
    ) async {
      await partReady(tester);

      await pickType(tester, 'Power Press');
      await tester.enterText(machineField('capacity'), '35');
      await tester.pumpAndSettle();
      await _tapVisible(
        tester,
        find.byKey(const ValueKey<String>('quick-entry-machine-free-hand')),
      );
      await _tapVisible(tester, addMachine());

      expect(drafts.single.capacityKind, 'free_hand');
      // The figure left in the box does not ride along: the two would be two
      // answers to one question.
      expect(drafts.single.capacityKgf, isNull);
    });

    testWidgets('a capacity that is not a whole kgf is refused', (
      tester,
    ) async {
      await partReady(tester);

      await pickType(tester, 'Power Press');
      await tester.enterText(machineField('capacity'), 'heavy');
      await tester.pumpAndSettle();
      await _tapVisible(tester, addMachine());

      expect(drafts, isEmpty, reason: 'nothing is written on a bad capacity');
      expect(find.text('Not a capacity'), findsOneWidget);
    });

    testWidgets('a taken number offers a free one and does not write again', (
      tester,
    ) async {
      await partReady(tester);
      AppFlowHooks.createMachineFromSheet = (context, draft) async {
        drafts.add(draft);
        return const MachineCreateOutcome.failed(
          message: 'Machine No "PP-1" is already used by machine #3.',
          code: 'machine_asset_id_duplicate',
          suggestedAssetId: 'PP-2',
        );
      };

      await pickType(tester, 'Power Press');
      await _tapVisible(tester, addMachine());

      expect(drafts, hasLength(1), reason: 'refused once, never retried');
      expect(_textIn(tester, 'machine-no'), 'PP-2');
      expect(find.textContaining('already used by machine'), findsOneWidget);
    });

    testWidgets('a machine that could not be linked is attached, never remade', (
      tester,
    ) async {
      final harness = await partReady(tester);
      harness.itemRepo.throwOnUpdate = true;

      await pickType(tester, 'Power Press');
      await _tapVisible(tester, addMachine());

      expect(drafts, hasLength(1));
      expect(find.textContaining('could not be attached'), findsOneWidget);
      expect(
        find.descendant(
          of: addMachine(),
          matching: find.text('Attach the machine'),
        ),
        findsOneWidget,
      );

      harness.itemRepo.throwOnUpdate = false;
      await _tapVisible(tester, addMachine());

      expect(drafts, hasLength(1), reason: 'the machine already exists');
      expect(harness.itemRepo.updated.last.machineIds, contains('90'));
    });

    testWidgets('without the hook the section offers nothing', (tester) async {
      AppFlowHooks.createMachineFromSheet = null;
      await _pumpWizard(tester);

      await tester.ensureVisible(find.textContaining('Machines · '));
      expect(find.textContaining('cannot be added from here'), findsOneWidget);
      expect(addMachine(), findsNothing);
    });

    testWidgets('a part runs on more than one, and one can be taken off', (
      tester,
    ) async {
      final harness = await partReady(tester);
      harness.itemRepo.machineRows['90'] = const ItemMachineLink(
        id: '90',
        name: 'PP-1',
        assetId: 'PP-1',
        groupId: 60,
        machineType: 'Power Press',
        machineMake: 'Mayank',
        capacityKind: 'rated',
        capacityKgf: 35000,
        strokesPerMinute: 110,
      );
      harness.itemRepo.machineRows['91'] = const ItemMachineLink(
        id: '91',
        name: 'PM-1',
        assetId: 'PM-1',
        groupId: 61,
        machineType: 'Punching M',
        machineMake: 'SKA',
      );

      await pickType(tester, 'Power Press');
      await _tapVisible(tester, addMachine());

      // What tells them apart, not just the number.
      expect(machineRow('90'), findsOneWidget);
      expect(
        find.textContaining('Power Press · Mayank · 35 Ton · 110/min'),
        findsOneWidget,
      );

      await _tapVisible(tester, addMachine());
      expect(drafts, hasLength(2));
      // The link carries BOTH: it is a full replace, so a bare [newId] would
      // drop the machine that was already there.
      expect(
        harness.itemRepo.updated.last.machineIds,
        containsAll(['90', '91']),
      );

      // Tapping one loads it in to be corrected.
      await _tapVisible(tester, machineRow('90'));
      expect(find.text('Machines · ATP48 · PP-1'), findsOneWidget);
      expect(_textIn(tester, 'machine-make'), 'Mayank');
      expect(
        find.descendant(of: addMachine(), matching: find.text('Save machine')),
        findsOneWidget,
      );
      await _tapVisible(tester, addMachine());
      expect(drafts.last.machineId, '90');

      // And the ✕ takes it off the part without touching the machine.
      await _tapVisible(
        tester,
        find.descendant(of: machineRow('91'), matching: find.byType(IconButton)),
      );
      expect(harness.itemRepo.updated.last.machineIds, isNot(contains('91')));
      expect(find.textContaining('still in the machines master'), findsOneWidget);
    });
  });
}

/// --- filling the whole part before it exists -------------------------------
///
/// The complaint this answers: the Die and Machine sections used to refuse to
/// open until the part was saved, so entering one part meant saving halfway
/// through a thought, hunting the row in Made just now and tapping it. Now
/// everything is filled in on one screen and one press writes the lot.
void _stagedCreateTests() {
  group('held until the part is made', () {
    late List<DieSheetDraft> dieDrafts;
    late List<MachineSheetDraft> machineDrafts;
    late bool refuseDies;

    setUp(() {
      dieDrafts = <DieSheetDraft>[];
      machineDrafts = <MachineSheetDraft>[];
      refuseDies = false;
      AppFlowHooks.createDieFromSheet = (context, draft) async {
        dieDrafts.add(draft);
        if (refuseDies) {
          return const DieCreateOutcome.failed(message: 'The toolroom said no.');
        }
        return DieCreateOutcome.created(
          CreatedRecord(id: 'die-${dieDrafts.length}', title: draft.toolCode),
        );
      };
      AppFlowHooks.createMachineFromSheet = (context, draft) async {
        machineDrafts.add(draft);
        return MachineCreateOutcome.created(
          CreatedRecord(
            id: 'machine-${machineDrafts.length}',
            title: draft.assetId,
          ),
        );
      };
      AppFlowHooks.dieMadeByNames = (context) async => const <String>[];
      AppFlowHooks.machineSheetSuggestions = (context) async =>
          const MachineSheetSuggestions();
    });

    tearDown(() {
      AppFlowHooks.createDieFromSheet = null;
      AppFlowHooks.createMachineFromSheet = null;
      AppFlowHooks.dieMadeByNames = null;
      AppFlowHooks.machineSheetSuggestions = null;
    });

    Finder addDie() => find.byKey(const ValueKey<String>('quick-entry-add-die'));
    Finder addMachine() =>
        find.byKey(const ValueKey<String>('quick-entry-add-machine'));

    /// A group picked and a part name typed — nothing written.
    Future<_Harness> readyToHold(WidgetTester tester) async {
      final harness = await _pumpWizard(
        tester,
        groups: <GroupDefinition>[
          _primary,
          _ashTrays,
          _scrap,
          _group(60, 'Power Press', groupType: 'machine'),
        ],
      );
      await _selectRow(tester, 'Ash Trays');
      await _type(tester, 'item', 'Patti');
      return harness;
    }

    Future<void> holdDie(WidgetTester tester, String type) async {
      await _tapVisible(tester, find.text(type));
      await _tapVisible(tester, addDie());
    }

    testWidgets('holding a die writes nothing until the part is made', (
      tester,
    ) async {
      final harness = await readyToHold(tester);

      await holdDie(tester, 'Cutting');

      // Nothing was written — not the die, and above all not the part.
      expect(dieDrafts, isEmpty);
      expect(harness.itemRepo.created, isEmpty);
      // And the row says so rather than looking saved.
      expect(find.textContaining('held until the part is made'), findsWidgets);
      expect(find.text('CDATP48'), findsOneWidget);
    });

    testWidgets('a second die of a kind takes the next code while held', (
      tester,
    ) async {
      await readyToHold(tester);

      await holdDie(tester, 'Cutting');
      // The type repeats down the sheet, so the next die is ready to add — and
      // the first held one took CDATP48, so the sheet has already moved on
      // before anything has been sent anywhere.
      expect(_textIn(tester, 'die-code'), 'CDATP48-2');

      await _tapVisible(tester, addDie());
      expect(dieDrafts, isEmpty);
      expect(find.text('CDATP48'), findsOneWidget);
      expect(find.text('CDATP48-2'), findsWidgets);
    });

    testWidgets('Create part writes the part, then the lot, then one link', (
      tester,
    ) async {
      final harness = await readyToHold(tester);

      await holdDie(tester, 'Cutting');
      await holdDie(tester, 'Bending');
      await _tapVisible(
        tester,
        find.byKey(const ValueKey<String>('quick-entry-machine-type-field')),
      );
      await tester.tap(find.text('Power Press').last);
      await tester.pumpAndSettle();
      await _tapVisible(tester, addMachine());

      expect(dieDrafts, isEmpty, reason: 'still held');
      expect(machineDrafts, isEmpty, reason: 'still held');

      await _tick(tester, 'item');

      // The part first, then everything that was waiting on it.
      expect(harness.itemRepo.created, hasLength(1));
      expect(dieDrafts, hasLength(2));
      expect(machineDrafts, hasLength(1));
      // Each die carries the part's REAL code, not the suggestion it was
      // held against.
      expect(dieDrafts.every((d) => d.partCode == 'ATP48'), isTrue);

      // One link call carrying both lists: each is a full replace, so two
      // calls would have the second undo the first.
      expect(harness.itemRepo.updated, hasLength(1));
      final link = harness.itemRepo.updated.single;
      expect(link.dieIds, containsAll(['die-1', 'die-2']));
      expect(link.machineIds, contains('machine-1'));
    });

    testWidgets('the part just made is what the screen then shows', (
      tester,
    ) async {
      await readyToHold(tester);
      await holdDie(tester, 'Cutting');
      await _tick(tester, 'item');

      // No save-then-hunt-then-tap: the part is already in front of you, so a
      // third die is one more Add.
      expect(find.text('Part · Patti'), findsOneWidget);
      expect(find.text('Developed For · Patti'), findsOneWidget);
      expect(find.textContaining('Dies · ATP48'), findsOneWidget);
      expect(
        find.descendant(of: addDie(), matching: find.text('Add die')),
        findsOneWidget,
        reason: 'it writes immediately now that the part exists',
      );
    });

    testWidgets('a refused die leaves the part made and the rest still held', (
      tester,
    ) async {
      final harness = await readyToHold(tester);
      await holdDie(tester, 'Cutting');
      await holdDie(tester, 'Bending');
      refuseDies = true;

      await _tick(tester, 'item');

      // The part exists; the dies do not, and nobody is left guessing.
      expect(harness.itemRepo.created, hasLength(1));
      expect(find.textContaining('was not made'), findsOneWidget);
      expect(find.textContaining('still held'), findsOneWidget);
      // It stopped at the first refusal rather than hammering the rest.
      expect(dieDrafts, hasLength(1));
      // Still held — and the rows no longer claim to be waiting on a part
      // that now exists.
      expect(find.textContaining('held — not written yet'), findsNWidgets(2));
      expect(find.textContaining('held until the part is made'), findsNothing);
    });

    testWidgets('a held machine counts the other held ones', (tester) async {
      await readyToHold(tester);

      Future<void> holdPress() async {
        await _tapVisible(
          tester,
          find.byKey(const ValueKey<String>('quick-entry-machine-type-field')),
        );
        await tester.tap(find.text('Power Press').last);
        await tester.pumpAndSettle();
        await _tapVisible(tester, addMachine());
      }

      await holdPress();
      expect(find.text('PP-1'), findsOneWidget);
      await holdPress();

      // Two presses waiting on the same part are two machines, so the second
      // cannot be offered the number the first is holding.
      expect(machineDrafts, isEmpty);
      expect(find.text('PP-2'), findsWidgets);
    });

    testWidgets('a die refused mid-flush is written once, not twice', (
      tester,
    ) async {
      final harness = await readyToHold(tester);
      await holdDie(tester, 'Cutting');
      await holdDie(tester, 'Bending');
      refuseDies = true;
      await _tick(tester, 'item');

      // The part is made and the toolroom is answering again. The held row is
      // tapped back into the sheet and saved — the ordinary path now that the
      // part exists.
      refuseDies = false;
      await _tapVisible(
        tester,
        find.byKey(const ValueKey<String>('quick-entry-staged-die-0')),
      );
      await _tapVisible(tester, addDie());

      // Written once. And it has stopped being held, so it cannot be made a
      // second time for whatever part is created next.
      expect(dieDrafts.where((d) => d.toolCode == 'CDATP48'), hasLength(2));
      expect(find.textContaining('held — not written yet'), findsOneWidget);
      expect(find.text('CDATP48'), findsOneWidget);
    });

    testWidgets('closing with something held asks first', (tester) async {
      await readyToHold(tester);
      await holdDie(tester, 'Cutting');

      await _tapVisible(tester, find.widgetWithText(AppButton, 'Done'));

      // A held die is as invisible and as losable as a named set.
      expect(find.textContaining('Discard 1 die'), findsOneWidget);
      expect(find.textContaining('Nothing has been written'), findsOneWidget);
    });
  });
}
