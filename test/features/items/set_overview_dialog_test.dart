import 'package:core_erp/features/inventory/domain/inventory_set_definition.dart';
import 'package:core_erp/features/items/data/repositories/api_item_repository.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/items/presentation/widgets/set_overview_dialog.dart';
import 'package:core_erp/features/production_pipelines/domain/pipeline_stage_node.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Serves a fixed item master and pipeline roster; the repository underneath is
/// the mock one and is never reached.
class _FakeItemsProvider extends ItemsProvider {
  _FakeItemsProvider({required this.fakeItems, required this.stageNodes})
    : super(repository: ApiItemRepository());

  final List<ItemDefinition> fakeItems;
  final Map<String, List<PipelineStageNode>> stageNodes;

  @override
  List<ItemDefinition> get items => fakeItems;

  @override
  Future<Map<String, List<PipelineStageNode>>> fetchPipelineStageNodes() async {
    return stageNodes;
  }
}

ItemDefinition _item({
  required int id,
  required String name,
  String? pipelineId,
  String? pipelineName,
  List<ItemMachineLink> machines = const <ItemMachineLink>[],
  List<ItemDieLink> dies = const <ItemDieLink>[],
}) {
  final now = DateTime(2026, 9, 7);
  return ItemDefinition(
    id: id,
    name: name,
    alias: '',
    displayName: name,
    quantity: 0,
    groupId: 1,
    unitId: 1,
    isArchived: false,
    usageCount: 0,
    createdAt: now,
    updatedAt: now,
    variationTree: const [],
    defaultPipelineId: pipelineId,
    defaultPipelineName: pipelineName,
    machines: machines,
    dies: dies,
  );
}

InventorySetLineDefinition _line({
  required int itemId,
  required int quantity,
  required String itemName,
  String variation = '',
  int position = 0,
}) {
  return InventorySetLineDefinition(
    id: itemId,
    itemId: itemId,
    variationLeafNodeId: 0,
    quantity: quantity,
    position: position,
    itemName: itemName,
    itemDisplayName: itemName,
    variationPathLabel: variation,
    variationPathNodeIds: const <int>[],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required InventorySetDefinition set,
  required List<ItemDefinition> items,
  Map<String, List<PipelineStageNode>> stageNodes =
      const <String, List<PipelineStageNode>>{},
  Size size = const Size(1200, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<ItemsProvider>.value(
      value: _FakeItemsProvider(fakeItems: items, stageNodes: stageNodes),
      child: MaterialApp(home: Scaffold(body: SetOverviewDialog(set: set))),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final set = InventorySetDefinition(
    id: 7,
    name: 'Starter Pack',
    totalItemCount: 5,
    createdAt: DateTime(2026, 9, 1),
    updatedAt: DateTime(2026, 9, 1),
    lines: [
      _line(itemId: 1, quantity: 2, itemName: 'Cone 90mm', variation: 'Red'),
      _line(itemId: 2, quantity: 3, itemName: 'Handle', position: 1),
    ],
  );

  testWidgets('rolls machines and dies up across members, once each', (
    tester,
  ) async {
    await _pump(
      tester,
      set: set,
      items: [
        _item(
          id: 1,
          name: 'Cone 90mm',
          pipelineId: 'p1',
          pipelineName: 'Cone Line',
          machines: const [
            ItemMachineLink(id: 'm1', name: 'Punch', assetId: 'PN-07'),
          ],
          dies: const [ItemDieLink(id: 'd1', toolCode: 'D-C90')],
        ),
        // Shares PN-07 with the first member — it must appear once in the
        // rollup, and once against each member that uses it.
        _item(
          id: 2,
          name: 'Handle',
          pipelineId: 'p1',
          pipelineName: 'Cone Line',
          machines: const [
            ItemMachineLink(id: 'm1', name: 'Punch', assetId: 'PN-07'),
          ],
          dies: const [ItemDieLink(id: 'd2', toolCode: 'D-HDL')],
        ),
      ],
    );

    expect(find.text('Starter Pack'), findsOneWidget);
    expect(
      find.text('2 items · 5 pieces per set · 1 pipeline'),
      findsOneWidget,
    );

    // Two columns until a pipeline is chosen.
    expect(find.text('Members'), findsOneWidget);
    expect(find.text('Pipelines'), findsOneWidget);
    expect(find.text('Machines'), findsNothing);
    expect(find.text('Dies'), findsNothing);

    expect(find.text('×2'), findsOneWidget);
    expect(find.text('×3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('choosing a pipeline opens its machine and die columns', (
    tester,
  ) async {
    await _pump(
      tester,
      set: set,
      items: [
        _item(
          id: 1,
          name: 'Cone 90mm',
          pipelineId: 'p1',
          pipelineName: 'Cone Line',
          machines: const [
            ItemMachineLink(id: 'm1', name: 'Punch', assetId: 'PN-07'),
          ],
          dies: const [ItemDieLink(id: 'd1', toolCode: 'D-C90')],
        ),
        _item(
          id: 2,
          name: 'Handle',
          pipelineId: 'p1',
          pipelineName: 'Cone Line',
          machines: const [
            ItemMachineLink(id: 'm1', name: 'Punch', assetId: 'PN-07'),
          ],
          dies: const [ItemDieLink(id: 'd2', toolCode: 'D-HDL')],
        ),
      ],
    );

    expect(find.text('Machines'), findsNothing);
    // Once open, "Cone Line" also captions the two new columns, so the tap
    // targets the card itself.
    final pipelineCard = find.text('Cone Line').first;
    await tester.tap(pipelineCard);
    await tester.pumpAndSettle();

    expect(find.text('Machines'), findsOneWidget);
    expect(find.text('Dies'), findsOneWidget);
    // Both members share PN-07, so it lands in the column once.
    expect(find.text('PN-07 · Punch'), findsOneWidget);
    expect(find.text('D-C90'), findsOneWidget);
    expect(find.text('D-HDL'), findsOneWidget);

    // Tapping again closes the drill-down.
    await tester.tap(pipelineCard);
    await tester.pumpAndSettle();
    expect(find.text('Machines'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picks machines and dies up from the pipeline too', (
    tester,
  ) async {
    await _pump(
      tester,
      set: set,
      items: [
        _item(id: 1, name: 'Cone 90mm', pipelineId: 'p1', pipelineName: 'Cone Line'),
        _item(id: 2, name: 'Handle'),
      ],
      stageNodes: const {
        'p1': [
          PipelineStageNode(
            id: 'n1',
            name: 'Punching',
            machine: 'Handpress',
            dieCode: 'D-C90',
          ),
        ],
      },
    );

    await tester.tap(find.text('Cone Line'));
    await tester.pumpAndSettle();

    // Neither item carries links, so these can only have come from the node.
    expect(find.text('Handpress'), findsWidgets);
    expect(find.text('D-C90'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('says so when a member is gone, and stays usable', (
    tester,
  ) async {
    await _pump(tester, set: set, items: [_item(id: 1, name: 'Cone 90mm')]);

    expect(find.text('This item is no longer in the master.'), findsOneWidget);
    // Nothing has a pipeline, so the members gather under one stated bucket
    // rather than the board looking empty.
    expect(find.text('No pipeline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out on a narrow window without overflowing', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(680, 900),
      set: set,
      items: [
        _item(
          id: 1,
          name: 'Cone 90mm',
          pipelineName: 'Cone Line',
          machines: const [
            ItemMachineLink(id: 'm1', name: 'Punch', assetId: 'PN-07'),
          ],
        ),
        _item(id: 2, name: 'Handle'),
      ],
    );

    expect(find.text('Starter Pack'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
