import 'package:core_erp/features/groups/presentation/screens/creation_sessions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:core_erp/features/items/data/services/item_link_options_service.dart';
import 'package:core_erp/features/links/data/entity_link_service.dart';
import 'package:core_erp/features/clients/data/repositories/client_repository.dart';
import 'package:core_erp/features/clients/domain/client_definition.dart';
import 'package:core_erp/features/clients/presentation/providers/clients_provider.dart';
import 'package:core_erp/core/services/user_preferences_service.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/items/presentation/providers/item_form_sections_provider.dart';
import 'package:core_erp/features/materials/data/material_repository.dart';
import 'package:core_erp/features/materials/domain/material_definition.dart';
import 'package:core_erp/features/materials/presentation/providers/materials_provider.dart';
import 'package:core_erp/core/app_flow_hooks.dart';
import 'package:core_erp/features/groups/data/repositories/api_group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/domain/group_inputs.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/groups/presentation/screens/component_creation_screen.dart';
import 'package:core_erp/features/items/data/repositories/api_item_repository.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/domain/item_inputs.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/units/data/repositories/api_unit_repository.dart';
import 'package:core_erp/features/units/domain/unit_definition.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

final _now = DateTime(2026, 9, 24);

ItemDefinition _item({
  required int id,
  required String name,
  required int groupId,
  required int unitId,
  String alias = '',
  List<ItemDieLink> dies = const [],
}) {
  return ItemDefinition(
    id: id,
    name: name,
    alias: alias,
    displayName: name,
    quantity: 0,
    groupId: groupId,
    unitId: unitId,
    isArchived: false,
    usageCount: 0,
    createdAt: _now,
    updatedAt: _now,
    variationTree: const [],
    dies: dies,
  );
}

class _FakeItemsProvider extends ItemsProvider {
  _FakeItemsProvider() : super(repository: ApiItemRepository());

  final List<ItemDefinition> fakeItems = [];
  final List<CreateItemInput> created = [];
  final List<String> updated = [];
  final List<String> linkCalls = [];

  @override
  List<ItemDefinition> get items => fakeItems;

  @override
  Future<void> initialize() async {}

  @override
  Future<ItemDefinition?> createItem(CreateItemInput input) async {
    created.add(input);
    final item = _item(
      id: 100 + fakeItems.length,
      name: input.name,
      alias: input.alias,
      groupId: input.groupId,
      unitId: input.unitId,
    );
    fakeItems.add(item);
    notifyListeners();
    return item;
  }

  @override
  Future<ItemDefinition?> updateItem(UpdateItemInput input) async {
    updated.add('${input.id}:${input.name}');
    return fakeItems.where((item) => item.id == input.id).firstOrNull;
  }

  @override
  Future<ItemDefinition?> setItemLinks(
    int itemId, {
    List<String>? machineIds,
    List<String>? dieIds,
  }) async {
    linkCalls.add('$itemId:${dieIds?.join(',')}');
    final index = fakeItems.indexWhere((item) => item.id == itemId);
    final old = fakeItems[index];
    fakeItems[index] = _item(
      id: old.id,
      name: old.name,
      groupId: old.groupId,
      unitId: old.unitId,
      dies: [
        for (final id in dieIds ?? const <String>[])
          ItemDieLink(id: id, toolCode: 'TD-$id'),
      ],
    );
    notifyListeners();
    return fakeItems[index];
  }
}

class _FakeUnitsProvider extends UnitsProvider {
  _FakeUnitsProvider() : super(repository: ApiUnitRepository());

  @override
  Future<void> initialize() async {}

  @override
  List<UnitDefinition> get activeUnits => units;

  // The editor picks from `units`, the wizard's view column reads
  // `activeUnits`; a real save needs both.
  @override
  List<UnitDefinition> get units => [
    _unit(1, 'Kilogram', 'kg'),
    _unit(2, 'Pieces', 'pcs'),
  ];

  static UnitDefinition _unit(int id, String name, String symbol) =>
      UnitDefinition(
        id: id,
        name: name,
        symbol: symbol,
        notes: '',
        unitGroupId: null,
        unitGroupName: null,
        conversionFactor: 1,
        conversionBaseUnitId: null,
        conversionBaseUnitName: null,
        conversionType: 'linear',
        precision: null,
        unitGroupDimension: null,
        unitGroupBaseUnitId: null,
        isArchived: false,
        usageCount: 0,
        createdAt: _now,
        updatedAt: _now,
      );
}

class _FakeGroupsProvider extends GroupsProvider {
  _FakeGroupsProvider() : super(repository: ApiGroupRepository());

  final List<CreateGroupInput> created = [];

  @override
  Future<void> initialize() async {}

  @override
  List<GroupDefinition> get groups => [
    GroupDefinition(
      id: 7,
      name: 'Finished Goods',
      groupStructure: 'hierarchical',
      parentGroupId: null,
      isArchived: false,
      usageCount: 0,
      createdAt: _now,
      updatedAt: _now,
    ),
  ];

  @override
  GroupDefinition? findById(int? id) =>
      groups.where((group) => group.id == id).firstOrNull;

  @override
  Future<GroupDefinition?> createGroup(CreateGroupInput input) async {
    created.add(input);
    return GroupDefinition(
      id: 9,
      name: input.name,
      groupStructure: input.groupStructure,
      parentGroupId: null,
      isArchived: false,
      usageCount: 0,
      createdAt: _now,
      updatedAt: _now,
    );
  }
}

/// Stands in for the item workflow window: one field and a save button.
Widget _fakeItemEditor(
  BuildContext context, {
  required int? groupId,
  required ItemDefinition? item,
  required ValueChanged<ItemDefinition?> onClosed,
}) => _FakeItemEditor(groupId: groupId, item: item, onClosed: onClosed);

class _FakeItemEditor extends StatefulWidget {
  const _FakeItemEditor({
    required this.groupId,
    required this.item,
    required this.onClosed,
  });

  final int? groupId;
  final ItemDefinition? item;
  final ValueChanged<ItemDefinition?> onClosed;

  @override
  State<_FakeItemEditor> createState() => _FakeItemEditorState();
}

class _FakeItemEditorState extends State<_FakeItemEditor> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(key: const ValueKey('fake_item_name'), controller: _name),
        TextButton(
          onPressed: () async {
            final saved = await context.read<ItemsProvider>().createItem(
              CreateItemInput(
                name: _name.text,
                displayName: _name.text,
                groupId: widget.groupId ?? 1,
                unitId: 1,
              ),
            );
            widget.onClosed(saved);
          },
          child: const Text('Fake save item'),
        ),
      ],
    );
  }
}

/// A factory with no dies or machines registered yet.
class _NoToolingService extends ItemLinkOptionsService {
  _NoToolingService() : super(baseUrl: '');

  @override
  Future<List<ItemLinkOption>> fetchMachines() async => const [];

  @override
  Future<List<ItemLinkOption>> fetchDies() async => const [];
}

class _FakeClientRepository implements ClientRepository {
  @override
  Future<void> init() async {}

  @override
  Future<List<ClientDefinition>> getClients() async =>
      const <ClientDefinition>[];

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
  @override
  Future<void> init() async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeItemsProvider items;
  late _FakeGroupsProvider groups;
  var dieCount = 0;

  setUp(() {
    items = _FakeItemsProvider();
    groups = _FakeGroupsProvider();
    dieCount = 0;
    // Stands in for the app's full die editor.
    AppFlowHooks.dieEditor = (context, {required onSaved, required onCancel}) =>
        Center(
          child: TextButton(
            onPressed: () {
              final id = 'die-${++dieCount}';
              onSaved(CreatedRecord(id: id, title: 'Die $dieCount'));
            },
            child: const Text('Fake save die'),
          ),
        );
  });

  tearDown(() => AppFlowHooks.dieEditor = null);

  Future<void> pumpDialog(
    WidgetTester tester, {
    GroupDefinition? component,
    bool itemsOnly = false,
    bool realItemEditor = false,
    ItemLinkOptionsService? linkOptions,
    EntityLinkService? linkService,
  }) async {
    tester.view.physicalSize = const Size(1800, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ItemsProvider>.value(value: items),
          ChangeNotifierProvider<UnitsProvider>.value(
            value: _FakeUnitsProvider(),
          ),
          ChangeNotifierProvider<GroupsProvider>.value(value: groups),
          if (linkOptions != null)
            Provider<ItemLinkOptionsService>.value(value: linkOptions),
          ChangeNotifierProvider<InventoryProvider>(
            create: (_) =>
                InventoryProvider(repository: _FakeInventoryRepository()),
          ),
          ChangeNotifierProvider<MaterialsProvider>(
            create: (_) =>
                MaterialsProvider(repository: _FakeMaterialRepository()),
          ),
          ChangeNotifierProvider<ClientsProvider>(
            create: (_) => ClientsProvider(repository: _FakeClientRepository()),
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
          home: Scaffold(
            body: ComponentCreationDialog(
              component: component,
              itemEditorBuilder: realItemEditor ? null : _fakeItemEditor,
              itemsOnly: itemsOnly,
              linkService: linkService,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> addItem(WidgetTester tester, String name) async {
    await tester.enterText(find.byKey(const ValueKey('fake_item_name')), name);
    await tester.tap(find.text('Fake save item'));
    await tester.pumpAndSettle();
  }

  testWidgets('Add Item opens straight on the item editor, no component', (
    tester,
  ) async {
    await pumpDialog(tester, itemsOnly: true);
    expect(find.text('Item creation'), findsOneWidget);
    expect(find.text('Name the component'), findsNothing);

    await addItem(tester, 'Cone Top');
    expect(groups.created, isEmpty);
    expect(find.text('Cone Top'), findsOneWidget);
    // Only what was added in this window is listed.
    expect(find.byKey(const ValueKey('creation_item_100')), findsOneWidget);
  });

  testWidgets('one item after another: the form resets, no leave prompt', (
    tester,
  ) async {
    await pumpDialog(tester, itemsOnly: true, realItemEditor: true);
    await tester.pumpAndSettle();

    Future<void> save(String name, {bool pickGroup = true}) async {
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Base Name').first,
        name,
      );
      await tester.pumpAndSettle();
      if (pickGroup) {
        await tester.tap(find.byKey(const ValueKey('items-group-field')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Finished Goods').last);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('items-unit-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Kilogram').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Item').last);
      await tester.pumpAndSettle();
    }

    await save('Cone Top');
    // A save that worked must not ask about leaving unsaved work.
    expect(find.text('Leave without saving?'), findsNothing);
    expect(items.created.map((input) => input.name), ['Cone Top']);
    // The form comes back empty, ready for the next one.
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Base Name').first,
          )
          .controller
          ?.text,
      isEmpty,
    );

    // The group carries over, so a run of items does not re-pick it.
    await save('Cone Base', pickGroup: false);
    expect(items.created.map((input) => input.name), ['Cone Top', 'Cone Base']);
    expect(items.created.map((input) => input.groupId), [7, 7]);
    expect(find.text('Leave without saving?'), findsNothing);

    // A saved one comes back into the real form, filled in.
    await tester.tap(find.byKey(const ValueKey('creation_item_100')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('creation_editing_bar')), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Base Name').first,
          )
          .controller
          ?.text,
      'Cone Top',
    );
  });

  testWidgets(
    'a saved item reopens in the same window, and + starts a new one',
    (tester) async {
      await pumpDialog(tester, itemsOnly: true);
      await addItem(tester, 'Cone Top');
      await addItem(tester, 'Cone Base');

      // Tapping a saved item loads it back into the middle column.
      await tester.tap(find.byKey(const ValueKey('creation_item_100')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('creation_editing_bar')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('fake_item_name')))
            .controller
            ?.text,
        'Cone Top',
      );

      // The + beside the list gets a blank form back.
      await tester.tap(find.byKey(const ValueKey('creation_new_item')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('creation_editing_bar')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('fake_item_name')))
            .controller
            ?.text,
        isEmpty,
      );

      // Item can be taken out of the lineup and fetched back from +.
      await tester.tap(find.byKey(const ValueKey('creation_remove_item')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('creation_add_kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('creation_add_kind_item')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fake_item_name')), findsOneWidget);
    },
  );

  testWidgets('a second item form opens beside the first, both kept', (
    tester,
  ) async {
    await pumpDialog(tester, itemsOnly: true);
    // Both forms stay mounted; only the open one is on screen.
    final allNames = find.byKey(
      const ValueKey('fake_item_name'),
      skipOffstage: false,
    );
    List<String?> texts() => tester
        .widgetList<TextField>(allNames)
        .map((field) => field.controller?.text)
        .toList();

    await tester.enterText(
      find.byKey(const ValueKey('fake_item_name')),
      'Cone Top',
    );
    await tester.pump();

    // The Item tile's own + opens a second form beside it.
    await tester.tap(find.byKey(const ValueKey('creation_another_item')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('creation_kind_item'), skipOffstage: false),
      findsNWidgets(2),
    );
    expect(texts(), ['Cone Top', '']);

    await tester.enterText(
      find.byKey(const ValueKey('fake_item_name')),
      'Cone Base',
    );
    await tester.pump();

    // Back to the first: what was typed there survived the trip.
    await tester.tap(find.byKey(const ValueKey('creation_kind_item')).first);
    await tester.pumpAndSettle();
    expect(texts(), ['Cone Top', 'Cone Base']);

    // Saving one clears only that form.
    await tester.tap(find.text('Fake save item'));
    await tester.pumpAndSettle();
    expect(items.created.map((input) => input.name), ['Cone Top']);
    expect(texts(), ['', 'Cone Base']);
  });

  testWidgets('the title bar lists recent sittings and puts one back', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpDialog(tester, itemsOnly: true);

    // A sitting: an item, then a die made for it.
    await addItem(tester, 'Cone Top');
    await tester.tap(find.byKey(const ValueKey('creation_kind_die')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fake save die'));
    await tester.pumpAndSettle();

    // It shows in the title bar's recents, as one combination.
    await tester.tap(find.byKey(const ValueKey('creation_recents_field')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cone Top · Die 1'), findsOneWidget);
    expect(find.textContaining('2 saved'), findsOneWidget);

    // Typing narrows it; a miss empties the list.
    await tester.enterText(
      find.byKey(const ValueKey('creation_recents_field')),
      'nothing like this',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Cone Top · Die 1'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('creation_recents_field')),
      'cone',
    );
    await tester.pumpAndSettle();

    // Picking it brings that combination back: both records, both tiles.
    await tester.tap(find.textContaining('Cone Top · Die 1'));
    await tester.pumpAndSettle();
    expect(find.text('Cone Top'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('creation_kind_item'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('creation_kind_die'), skipOffstage: false),
      findsOneWidget,
    );
    // Machine was not part of that sitting, so its tile is gone.
    expect(
      find.byKey(const ValueKey('creation_kind_machine'), skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('tiles come off down to one, taking their + buttons with them', (
    tester,
  ) async {
    await pumpDialog(tester, itemsOnly: true);
    await tester.tap(find.byKey(const ValueKey('creation_remove_die')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('creation_remove_machine')));
    await tester.pump();

    expect(find.byKey(const ValueKey('creation_kind_die')), findsNothing);
    expect(find.byKey(const ValueKey('creation_kind_machine')), findsNothing);
    // The last tile stays.
    final remove = tester.widget<IconButton>(
      find.byKey(const ValueKey('creation_remove_item')),
    );
    expect(remove.onPressed, isNull);

    // An item-only wizard offers no + Die / + Machine under its items.
    await addItem(tester, 'Cone Top');
    await tester.tap(find.byKey(const ValueKey('creation_item_100')));
    await tester.pump();
    expect(find.byKey(const ValueKey('creation_add_die_100')), findsNothing);
    expect(
      find.byKey(const ValueKey('creation_add_machine_100')),
      findsNothing,
    );
  });

  testWidgets(
    '+ brings a form in; the top tile is what the last column shows',
    (tester) async {
      await pumpDialog(tester, itemsOnly: true);
      await tester.tap(find.byKey(const ValueKey('creation_remove_die')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('creation_add_kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('creation_add_kind_die')));
      await tester.pumpAndSettle();
      // Added and opened in the middle.
      expect(find.text('Fake save die'), findsOneWidget);

      // Drag Die above Item: the view column now lists dies.
      final handle = find.byKey(const ValueKey('creation_drag_die'));
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, -40));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Dies you add show up here.'), findsOneWidget);

      // Tiles on the left, the view they drive on the right.
      expect(
        tester.getCenter(find.byKey(const ValueKey('creation_kind_die'))).dx,
        lessThan(tester.getCenter(find.text('Dies you add show up here.')).dx),
      );

      // A save in the middle lands in the view column at once.
      await tester.tap(find.text('Fake save die'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('creation_record_die_die-1')),
        findsOneWidget,
      );
      expect(find.text('Die 1'), findsOneWidget);
    },
  );

  testWidgets('the item editor\'s steps sit under the Item tile', (
    tester,
  ) async {
    await pumpDialog(tester, itemsOnly: true, realItemEditor: true);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('creation_step_Details')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('creation_step_Variations')),
      findsOneWidget,
    );
    // The editor's own header and step chips give way to the tile.
    expect(find.text('Create Item'), findsNothing);

    // The form is split into pages; one shows at a time.
    expect(find.text('Item Details'), findsOneWidget);
    expect(find.text('Item Photo'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('creation_step_Files')));
    await tester.pumpAndSettle();
    expect(find.text('Item Details'), findsNothing);
    // Files is one page: photo, CAD and attachments together.
    expect(find.text('Item Photo'), findsOneWidget);
    expect(find.text('CAD File'), findsOneWidget);
    expect(find.text('Additional Files'), findsOneWidget);

    // Variations is one tab, and the naming format rides along with it.
    await tester.tap(find.byKey(const ValueKey('creation_step_Variations')));
    await tester.pumpAndSettle();
    expect(find.text('Variation Tree'), findsOneWidget);
    expect(find.text('Naming Format'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('creation_step_Properties')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('creation_step_Naming')), findsNothing);

    // Details, then Variations, then the rest.
    double top(String step) =>
        tester.getTopLeft(find.byKey(ValueKey('creation_step_$step'))).dy;
    expect(top('Details'), lessThan(top('Variations')));
    expect(top('Variations'), lessThan(top('Files')));

    // Typing shows the item in the view column straight away.
    await tester.tap(find.byKey(const ValueKey('creation_step_Details')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Item Name').first,
      'Cone Top',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('creation_draft_item')), findsOneWidget);

    // A trip to the die editor keeps what was typed, and a sub-tab opens
    // the item page directly from there.
    await tester.tap(find.byKey(const ValueKey('creation_kind_die')));
    await tester.pumpAndSettle();
    expect(find.text('Fake save die'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('creation_step_Files')));
    await tester.pumpAndSettle();
    expect(find.text('Item Photo'), findsOneWidget);
    expect(find.text('Fake save die'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('creation_step_Details')));
    await tester.pumpAndSettle();
    expect(find.text('Cone Top'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('creation_expand_item')));
    await tester.pump();
    expect(find.byKey(const ValueKey('creation_step_Details')), findsNothing);
  });

  testWidgets('no Pipeline page until a die or machine is registered', (
    tester,
  ) async {
    await pumpDialog(tester, itemsOnly: true, realItemEditor: true);
    await tester.pumpAndSettle();
    // Unknown (no service to ask): the pipeline stays, inside Master data.
    expect(find.byKey(const ValueKey('creation_step_Pipeline')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('creation_step_Master data')));
    await tester.pumpAndSettle();
    expect(find.text('Default Pipeline'), findsOneWidget);
    expect(find.text('Master Data'), findsOneWidget);

    await pumpDialog(
      tester,
      itemsOnly: true,
      realItemEditor: true,
      linkOptions: _NoToolingService(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('creation_step_Master data')));
    await tester.pumpAndSettle();
    expect(find.text('Default Pipeline'), findsNothing);
    expect(find.text('Master Data'), findsOneWidget);
  });

  testWidgets('naming the component puts it in the header, in capitals', (
    tester,
  ) async {
    await pumpDialog(tester);
    expect(find.text('Name the component'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('creation_component_title')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const ValueKey('creation_name_field')),
      'Cone Assembly',
    );
    await tester.pump();
    await tester.tap(find.text('Create component'));
    await tester.pumpAndSettle();

    expect(groups.created.single.groupStructure, 'component');
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('creation_component_title')))
          .data,
      'CONE ASSEMBLY',
    );
    // The item editor takes over the middle, aimed at the new group.
    await addItem(tester, 'Cone Top');
    expect(items.created.single.groupId, 9);
    expect(find.text('Cone Top'), findsOneWidget);
  });

  testWidgets('+ Die under an item opens the die editor aimed at that item', (
    tester,
  ) async {
    await pumpDialog(tester);
    await tester.enterText(
      find.byKey(const ValueKey('creation_name_field')),
      'Cone Assembly',
    );
    await tester.pump();
    await tester.tap(find.text('Create component'));
    await tester.pumpAndSettle();
    await addItem(tester, 'Cone Top');

    expect(find.byKey(const ValueKey('creation_add_die_100')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('creation_expand_item_100')));
    await tester.pump();
    expect(find.text('No dies or machines yet.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('creation_add_die_100')));
    await tester.pump();
    expect(find.byKey(const ValueKey('creation_target_bar')), findsOneWidget);

    await tester.tap(find.text('Fake save die'));
    await tester.pumpAndSettle();
    expect(items.linkCalls, ['100:die-1']);
    expect(find.text('TD-die-1'), findsOneWidget);

    // Still aimed at the same item, so the next die goes under it too.
    await tester.tap(find.text('Fake save die'));
    await tester.pumpAndSettle();
    expect(items.linkCalls.last, '100:die-1,die-2');
  });

  testWidgets('the item view shows code, unit and variation tree', (
    tester,
  ) async {
    ItemVariationNodeDefinition node(
      int id,
      ItemVariationNodeKind kind,
      String name, [
      List<ItemVariationNodeDefinition> children = const [],
    ]) => ItemVariationNodeDefinition(
      id: id,
      itemId: 50,
      parentNodeId: null,
      kind: kind,
      name: name,
      displayName: name,
      position: id,
      isArchived: false,
      createdAt: _now,
      updatedAt: _now,
      children: children,
    );

    items.fakeItems.add(
      ItemDefinition(
        id: 50,
        name: 'Cone Shell',
        alias: 'CS-01',
        displayName: 'Cone Shell',
        quantity: 0,
        groupId: 9,
        unitId: 1,
        isArchived: false,
        usageCount: 0,
        createdAt: _now,
        updatedAt: _now,
        variationTree: [
          node(1, ItemVariationNodeKind.property, 'Thickness', [
            node(2, ItemVariationNodeKind.value, '0.5'),
            node(3, ItemVariationNodeKind.value, '0.8'),
          ]),
        ],
      ),
    );

    await pumpDialog(
      tester,
      component: GroupDefinition(
        id: 9,
        name: 'Cone Assembly',
        groupStructure: 'component',
        parentGroupId: null,
        isArchived: false,
        usageCount: 0,
        createdAt: _now,
        updatedAt: _now,
      ),
    );

    expect(find.text('CONE ASSEMBLY'), findsOneWidget);
    expect(find.text('CS-01'), findsOneWidget);
    expect(find.text('kg'), findsOneWidget);
    expect(
      find.textContaining('0.5 · 0.8', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('the link column branches off the lineup once a tile has saved', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      itemsOnly: true,
      linkService: EntityLinkService(baseUrl: '', useMockResponses: true),
    );
    await tester.pumpAndSettle();

    // The link button is on the row from the start, so the gesture announces
    // itself — but disabled, because there is no record yet to link to, and it
    // says so rather than failing on a click.
    final linkButton = find.byKey(const ValueKey('creation_link_item'));
    expect(linkButton, findsOneWidget);
    expect(
      tester.widget<IconButton>(linkButton).onPressed,
      isNull,
      reason: 'nothing saved yet, so there is nothing to link to',
    );
    expect(
      tester.widget<IconButton>(linkButton).tooltip,
      contains('Save this item first'),
    );
    expect(find.byKey(const ValueKey('creation_link_branch')), findsNothing);
    expect(find.byKey(const ValueKey('creation_new_item')), findsOneWidget);

    await addItem(tester, 'Hinge Plate');
    await tester.pumpAndSettle();

    // The tile now stands for the item, so the button comes alive — but the
    // columns stay away until there is a chain in them to read. The button is
    // the way in, not an empty column.
    expect(tester.widget<IconButton>(linkButton).onPressed, isNotNull);
    expect(find.byKey(const ValueKey('creation_link_branch')), findsNothing);
    expect(find.byKey(const ValueKey('creation_new_item')), findsOneWidget);
  });

  testWidgets('the row link button links anything to anything', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      itemsOnly: true,
      linkService: EntityLinkService(baseUrl: '', useMockResponses: true),
    );
    await tester.pumpAndSettle();
    await addItem(tester, 'Hinge Plate');
    await tester.pumpAndSettle();

    // The same menu the columns' + opens: every master, so an item takes an
    // item as readily as a die or a machine.
    await tester.tap(find.byKey(const ValueKey('creation_link_item')));
    await tester.pumpAndSettle();
    for (final master in ['item', 'die', 'machine']) {
      expect(
        find.byKey(ValueKey('link_attach_master_$master')),
        findsOneWidget,
        reason: 'the row menu offers $master',
      );
    }

    await tester.tap(find.byKey(const ValueKey('link_attach_master_die')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('link_row_die:1')));
    await tester.pumpAndSettle();

    // Linked from the row, and NOW the columns have something to show.
    expect(find.byKey(const ValueKey('creation_link_branch')), findsOneWidget);
    expect(find.byKey(const ValueKey('link_row_die:1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('link_columns_add_item:100')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a saved tile dragged sideways links to the selected one', (
    tester,
  ) async {
    // Ids the demo graph can put a name to, so the link shows as DIE-100
    // rather than as an orphan.
    AppFlowHooks.dieEditor = (context, {required onSaved, required onCancel}) =>
        Center(
          child: TextButton(
            onPressed: () =>
                onSaved(const CreatedRecord(id: '1', title: 'DIE-100')),
            child: const Text('Fake save die'),
          ),
        );

    await pumpDialog(
      tester,
      linkService: EntityLinkService(baseUrl: '', useMockResponses: true),
      component: GroupDefinition(
        id: 9,
        name: 'Cone Assembly',
        groupStructure: 'component',
        parentGroupId: null,
        isArchived: false,
        usageCount: 0,
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    await tester.pumpAndSettle();

    // An item in the Item tile, then a die in the Die tile: both tiles now
    // stand for something.
    await addItem(tester, 'Hinge Plate');
    await tester.tap(find.byKey(const ValueKey('creation_kind_die')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fake save die'));
    await tester.pumpAndSettle();

    // Back on the item, so it is the one a drop links to.
    await tester.tap(find.byKey(const ValueKey('creation_kind_item')));
    await tester.pumpAndSettle();
    // Nothing linked yet, so no columns are up — the drag itself is what
    // opens the place to let go.
    expect(find.byKey(const ValueKey('creation_link_branch')), findsNothing);

    final die = find.byKey(const ValueKey('creation_kind_die'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(die));
    await tester.pumpAndSettle();

    // Grabbed on the label. The row's right-hand end is buttons now — the
    // tile's centre lands on the link button, and the gesture never reaches
    // the Draggable behind it.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    final dieRect = tester.getRect(die);
    final grab = Offset(dieRect.left + 72, dieRect.center.dy);
    final gesture = await tester.startGesture(grab);
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final branch = find.byKey(const ValueKey('creation_link_branch'));
    expect(branch, findsOneWidget, reason: 'the drag opened the drop zone');
    await gesture.moveTo(tester.getCenter(branch));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('link_row_die:1')),
      findsOneWidget,
      reason: 'the dropped tile is linked to whatever the lineup has selected',
    );

    await tester.pump(const Duration(seconds: 4)); // let the toast expire
  });

  testWidgets('the workspace puts nothing inside a layout callback', (
    tester,
  ) async {
    // Regression guard, structural because the symptom would not reproduce
    // here. The workspace decided whether the 1.1 column fits inside a
    // LayoutBuilder wrapped around its whole row, which put the lineup's
    // ReorderableListView inside a layout callback. Rebuilding those items
    // during layout reactivates each one's global key, and that carries their
    // tooltips' OverlayPortals with it — which marks the overlay dirty while
    // a _RenderLayoutBuilder is mid-performLayout, and Flutter asserts:
    // "A _RenderLayoutBuilder was mutated in _RenderLayoutBuilder.performLayout".
    //
    // The rule is that the lineup must not sit under a layout callback. The
    // enforceable version is the stricter one: this workspace introduces no
    // LayoutBuilder at all, and reads the window's width as a dependency
    // instead. If you need to measure here, measure around something that
    // does not contain the lineup — do not just delete this test.
    await pumpDialog(
      tester,
      itemsOnly: true,
      linkService: EntityLinkService(baseUrl: '', useMockResponses: true),
    );
    await tester.pumpAndSettle();
    await addItem(tester, 'Hinge Plate');
    await tester.pumpAndSettle();

    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ComponentCreationWorkspace),
        matching: find.byType(LayoutBuilder),
      ),
      findsNothing,
    );
  });

  testWidgets('the branch gives way when the window is too narrow for it', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      itemsOnly: true,
      linkService: EntityLinkService(baseUrl: '', useMockResponses: true),
    );
    await tester.pumpAndSettle();
    await addItem(tester, 'Hinge Plate');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('creation_link_item')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('link_attach_master_die')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('link_row_die:1')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('creation_link_columns')), findsOneWidget);

    // Too narrow to hold even one readable column: the whole strip stands
    // down, and the reference tile has the row to itself again.
    tester.view.physicalSize = const Size(1000, 1100);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('creation_link_branch')), findsNothing);
    expect(find.byKey(const ValueKey('creation_new_item')), findsOneWidget);

    // And comes back when there is room again.
    tester.view.physicalSize = const Size(1800, 1100);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('creation_link_columns')), findsOneWidget);
  });

  testWidgets('a drag opens the branch even before a tile is selected', (
    tester,
  ) async {
    // The column rises on the gesture, not on the drop, so the place to let go
    // is on screen before the pointer gets there. Here the selected tile has
    // saved nothing, so the branch is shut until the drag starts.
    AppFlowHooks.dieEditor = (context, {required onSaved, required onCancel}) =>
        Center(
          child: TextButton(
            onPressed: () =>
                onSaved(const CreatedRecord(id: '1', title: 'DIE-100')),
            child: const Text('Fake save die'),
          ),
        );

    await pumpDialog(
      tester,
      itemsOnly: true,
      linkService: EntityLinkService(baseUrl: '', useMockResponses: true),
    );
    await tester.pumpAndSettle();

    // A die on the Die tile, then back to the Item tile, which has saved
    // nothing — so the branch is shut when the drag begins.
    await tester.tap(find.byKey(const ValueKey('creation_kind_die')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fake save die'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('creation_kind_item')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('creation_link_columns')), findsNothing);

    // Hover the tile first, as a pointer must to grab it: that reveals its
    // ×/+ buttons and puts their tooltips' overlay portals in play, which is
    // what the reactivation carried through layout.
    final die = find.byKey(const ValueKey('creation_kind_die'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(die));
    await tester.pumpAndSettle();
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('creation_another_die'))),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Grabbed on the label. The row's right-hand end is buttons now — the
    // tile's centre lands on the link button, and the gesture never reaches
    // the Draggable behind it.
    final dieRect = tester.getRect(die);
    final gesture = await tester.startGesture(
      Offset(dieRect.left + 72, dieRect.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.moveBy(const Offset(90, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('creation_link_hint')),
      findsOneWidget,
      reason: 'the branch opens and says why it has nothing to show yet',
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('two columns: the second opens on a pick, with its own +', (
    tester,
  ) async {
    // The chain the window exists to make: an item, its dies, and what one of
    // those dies runs on — all read without walking anywhere.
    final service = EntityLinkService(baseUrl: '', useMockResponses: true);
    await service.link(
      fromType: 'item',
      fromId: '100',
      toType: 'die',
      toId: '1',
    );
    await service.link(
      fromType: 'die',
      fromId: '1',
      toType: 'machine',
      toId: '1',
    );

    await pumpDialog(tester, itemsOnly: true, linkService: service);
    await tester.pumpAndSettle();
    await addItem(tester, 'Hinge Plate');
    await tester.pumpAndSettle();

    // The item already has a die, so the columns open on their own.
    // 1.1 is the item's links. 1.2 stands open before anything is picked in
    // it, saying what would fill it rather than being absent.
    expect(
      find.byKey(const ValueKey('link_columns_add_item:100')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('link_row_die:1')), findsOneWidget);
    expect(find.text('Nothing picked'), findsOneWidget);

    // Picking the die fills 1.2 with what IT is linked to — and that column
    // carries its own + at the foot, so a machine can be attached to the die
    // from here without leaving the item behind.
    await tester.tap(find.byKey(const ValueKey('link_row_die:1')));
    await tester.pumpAndSettle();
    expect(find.text('Nothing picked'), findsNothing);
    expect(find.byKey(const ValueKey('link_row_machine:1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('link_columns_add_die:1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('link_columns_add_item:100')),
      findsOneWidget,
      reason: 'the first column keeps its + too',
    );
  });

  testWidgets('the chevron shuts the columns away and brings them back', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      itemsOnly: true,
      linkService: EntityLinkService(baseUrl: '', useMockResponses: true),
    );
    await tester.pumpAndSettle();
    await addItem(tester, 'Hinge Plate');
    await tester.pumpAndSettle();

    // Give it something to show, so there are columns to shut away.
    await tester.tap(find.byKey(const ValueKey('creation_link_item')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('link_attach_master_die')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('link_row_die:1')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));

    final strip = find.byKey(const ValueKey('creation_link_branch'));
    final editor = find.byKey(const ValueKey('fake_item_name'));
    final openWidth = tester.getSize(strip).width;
    final openEditor = tester.getSize(editor).width;
    expect(openWidth, greaterThan(500), reason: 'two columns are open');
    expect(find.byKey(const ValueKey('creation_new_item')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('creation_branch_chevron')));
    await tester.pumpAndSettle();

    // Shut down to the rail, and the reference tile takes the space back.
    expect(tester.getSize(strip).width, lessThan(60));
    expect(find.byKey(const ValueKey('creation_new_item')), findsOneWidget);
    expect(tester.getSize(editor).width, greaterThan(openEditor));

    // The rail is what brings them back — a chevron inside the columns would
    // have gone away with them.
    await tester.tap(find.byKey(const ValueKey('creation_branch_chevron')));
    await tester.pumpAndSettle();
    expect(tester.getSize(strip).width, openWidth);
    expect(find.byKey(const ValueKey('creation_new_item')), findsNothing);
  });

  testWidgets('two columns and the real editor both fit a 1710pt laptop', (
    tester,
  ) async {
    // The size this is actually used at. A 1760pt budget fits two columns and
    // leaves the editor enough; a 1710pt one does not, and the first version
    // of this answered by silently dropping to one column — invisibly, so
    // there was no way to tell the second column was missing rather than
    // broken. The second version kept two and squeezed the editor until the
    // real item form overflowed its own fields. Neither failed loudly.
    tester.view.physicalSize = const Size(1710, 1070);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final service = EntityLinkService(baseUrl: '', useMockResponses: true);
    await service.link(
      fromType: 'item',
      fromId: '50',
      toType: 'die',
      toId: '1',
    );
    items.fakeItems.add(
      ItemDefinition(
        id: 50,
        name: 'Cone Shell',
        alias: 'CS-01',
        displayName: 'Cone Shell',
        quantity: 0,
        groupId: 9,
        unitId: 1,
        isArchived: false,
        usageCount: 0,
        createdAt: _now,
        updatedAt: _now,
        variationTree: const [],
      ),
    );

    await pumpDialog(
      tester,
      realItemEditor: true,
      linkService: service,
      component: GroupDefinition(
        id: 9,
        name: 'Cone Assembly',
        groupStructure: 'component',
        parentGroupId: null,
        isArchived: false,
        usageCount: 0,
        createdAt: _now,
        updatedAt: _now,
      ),
    );
    await tester.pumpAndSettle();

    // Open the item that already has a die, so the columns have a chain.
    await tester.tap(find.byKey(const ValueKey('creation_item_50')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('creation_link_branch')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('creation_branch_chevron')),
      findsOneWidget,
    );

    // Two columns' worth of strip, and the real editor laid out without
    // overflowing — which is what pumpAndSettle would have thrown on.
    expect(tester.getSize(find.byKey(const ValueKey('creation_link_branch')))
        .width, greaterThan(600));
    final thrown = tester.takeException();
    // ignore: avoid_print
    if (thrown != null) print('OVERFLOW-DUMP: $thrown');
    expect(thrown, isNull);
  });

  testWidgets('without a link service no column branches off the lineup', (
    tester,
  ) async {
    // A host that has not wired the link API degrades to the lineup it had,
    // rather than showing an empty column — the same rule the editor hooks
    // follow.
    await pumpDialog(tester, itemsOnly: true);
    await addItem(tester, 'Hinge Plate');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('creation_link_columns')), findsNothing);
    expect(find.byKey(const ValueKey('creation_new_item')), findsOneWidget);
  });

  testWidgets('creating component transitions to real item editor', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      itemsOnly: false,
      realItemEditor: true,
      linkService: EntityLinkService(baseUrl: '', useMockResponses: true),
    );
    await tester.pumpAndSettle();

    // Enter name
    await tester.enterText(
      find.byKey(const ValueKey('creation_name_field')),
      'Cone Assembly',
    );
    await tester.pump();
    await tester.tap(find.text('Create component'));
    await tester.pumpAndSettle();
  });
}





