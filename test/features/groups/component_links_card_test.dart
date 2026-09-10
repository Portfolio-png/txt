import 'package:core_erp/features/groups/presentation/widgets/bento/component_workflow_cards.dart';
import 'package:core_erp/features/items/data/repositories/api_item_repository.dart';
import 'package:core_erp/features/items/data/services/item_link_options_service.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeItemsProvider extends ItemsProvider {
  _FakeItemsProvider({this.refuseSave = false})
    : super(repository: ApiItemRepository());

  /// Stands in for a save the provider turns down — another one already in
  /// flight, or the write failing outright.
  final bool refuseSave;

  final List<List<String>> machineWrites = [];

  @override
  String? get errorMessage => refuseSave ? 'Another save is running.' : null;

  @override
  Future<ItemDefinition?> setItemLinks(
    int itemId, {
    List<String>? machineIds,
    List<String>? dieIds,
  }) async {
    if (machineIds != null) machineWrites.add(machineIds);
    return refuseSave ? null : _item();
  }
}

ItemDefinition _item({List<ItemMachineLink> machines = const []}) {
  final now = DateTime(2026, 9, 9);
  return ItemDefinition(
    id: 1,
    name: 'Body Casting',
    alias: '',
    displayName: 'Body Casting',
    quantity: 0,
    groupId: 9,
    unitId: 1,
    isArchived: false,
    usageCount: 0,
    createdAt: now,
    updatedAt: now,
    variationTree: const [],
    machines: machines,
    dies: const [],
  );
}

Future<_FakeItemsProvider> _pump(
  WidgetTester tester, {
  List<ItemMachineLink> machines = const [],
  bool refuseSave = false,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final items = _FakeItemsProvider(refuseSave: refuseSave);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ItemsProvider>.value(value: items),
        Provider<ItemLinkOptionsService>.value(
          value: ItemLinkOptionsService(baseUrl: '', useMockResponses: true),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: ComponentMachinesCard(
              item: _item(machines: machines),
              onSave: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return items;
}

void main() {
  testWidgets('an empty card says so and offers the way in', (tester) async {
    await _pump(tester);

    expect(find.text('No machines attached yet.'), findsOneWidget);
    expect(find.text('Add machine'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an attached machine reads with its asset id', (tester) async {
    await _pump(
      tester,
      machines: const [
        ItemMachineLink(id: '1', name: 'Press A', assetId: 'MC-001'),
      ],
    );

    expect(find.text('Press A'), findsOneWidget);
    expect(find.text('MC-001'), findsOneWidget);
    expect(find.text('No machines attached yet.'), findsNothing);
  });

  testWidgets('picking one attaches it, keeping what is already on', (
    tester,
  ) async {
    final items = await _pump(
      tester,
      machines: const [
        ItemMachineLink(id: '1', name: 'Press A', assetId: 'MC-001'),
      ],
    );

    await tester.tap(find.text('Add machine'));
    await tester.pumpAndSettle();

    // What is attached is not offered again.
    expect(find.text('Press A · MC-001'), findsNothing);
    await tester.tap(find.text('Press B · MC-002'));
    await tester.pumpAndSettle();

    expect(items.machineWrites, [
      ['1', '2'],
    ]);
    // A save that lands says nothing.
    expect(find.textContaining('Could not save'), findsNothing);
  });

  testWidgets('detaching writes the shorter list', (tester) async {
    final items = await _pump(
      tester,
      machines: const [
        ItemMachineLink(id: '1', name: 'Press A', assetId: 'MC-001'),
        ItemMachineLink(id: '2', name: 'Press B', assetId: 'MC-002'),
      ],
    );

    await tester.tap(find.byTooltip('Detach').first);
    await tester.pumpAndSettle();

    expect(items.machineWrites, [
      ['2'],
    ]);
  });

  testWidgets('a save that does not land says why', (tester) async {
    await _pump(tester, refuseSave: true);

    await tester.tap(find.text('Add machine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Press A · MC-001'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Another save is running.'), findsOneWidget);
  });
}
