import 'package:core_erp/features/items/data/services/item_link_options_service.dart';
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
  List<UnitDefinition> get activeUnits => [
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
  required ValueChanged<ItemDefinition?> onClosed,
}) => _FakeItemEditor(groupId: groupId, onClosed: onClosed);

class _FakeItemEditor extends StatefulWidget {
  const _FakeItemEditor({required this.groupId, required this.onClosed});

  final int? groupId;
  final ValueChanged<ItemDefinition?> onClosed;

  @override
  State<_FakeItemEditor> createState() => _FakeItemEditorState();
}

class _FakeItemEditorState extends State<_FakeItemEditor> {
  final _name = TextEditingController();

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
    await tester.tap(find.byKey(const ValueKey('creation_item_100')));
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
}
