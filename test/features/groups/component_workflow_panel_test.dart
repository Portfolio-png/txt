import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/widgets/component_workflow_panel.dart';
import 'package:core_erp/features/items/data/repositories/api_item_repository.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeItemsProvider extends ItemsProvider {
  _FakeItemsProvider(this.fakeItems) : super(repository: ApiItemRepository());

  final List<ItemDefinition> fakeItems;

  /// Records what the panel asked for, so an action can be asserted without a
  /// repository behind it.
  final List<String> calls = [];

  @override
  List<ItemDefinition> get items => fakeItems;

  @override
  Future<ItemDefinition?> setItemPipeline(int itemId, String? pipelineId) async {
    calls.add('pipeline:$itemId:${pipelineId ?? 'cleared'}');
    return fakeItems.firstWhere((item) => item.id == itemId);
  }

  @override
  Future<List<Map<String, String>>> fetchPipelineTemplates() async =>
      const [
        {'id': 'p1', 'name': 'Cone Line'},
      ];
}

ItemDefinition _item({
  required int id,
  required String name,
  required int groupId,
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
    groupId: groupId,
    unitId: 1,
    isArchived: false,
    usageCount: 0,
    createdAt: now,
    updatedAt: now,
    variationTree: const [],
    defaultPipelineId: pipelineName == null ? null : 'p1',
    defaultPipelineName: pipelineName,
    machines: machines,
    dies: dies,
  );
}

final _component = GroupDefinition(
  id: 9,
  name: 'Valve Body',
  groupStructure: 'component',
  parentGroupId: null,
  isArchived: false,
  usageCount: 0,
  createdAt: DateTime(2026, 9, 1),
  updatedAt: DateTime(2026, 9, 1),
);

Future<void> _pump(WidgetTester tester, List<ItemDefinition> items) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<ItemsProvider>.value(
      value: _FakeItemsProvider(items),
      child: MaterialApp(
        home: Scaffold(
          body: ComponentWorkflowPanel(component: _component),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // The panel's step wizard (Group → item → pipeline → machines → dies) was
  // taken out with Express; six tests that walked it are gone with it. What
  // is left is what the panel still does.

  testWidgets('an unrouted item is called out rather than looking finished', (
    tester,
  ) async {
    await _pump(tester, [_item(id: 2, name: 'Stem', groupId: 9)]);

    expect(find.text('No pipeline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty component offers the field, not buttons', (
    tester,
  ) async {
    await _pump(tester, const <ItemDefinition>[]);

    // One way in: the field itself, with results inline beneath it.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Add existing'), findsNothing);
    expect(find.text('New item'), findsNothing);
    expect(
      find.text('Search for an item, or type a name to create one.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing filters inline and offers to create what is missing', (
    tester,
  ) async {
    await _pump(tester, [
      _item(id: 3, name: 'Anchor Socket 10A', groupId: 4),
      _item(id: 4, name: 'Anchor Socket 20A', groupId: 4),
    ]);

    // Nothing is offered until something is typed.
    expect(find.text('Anchor Socket 10A'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Anchor Socket 10A');
    await tester.pumpAndSettle();
    // Twice: the field's own text, and the one candidate it matched.
    expect(find.text('Anchor Socket 10A'), findsNWidgets(2));
    expect(find.text('Anchor Socket 20A'), findsNothing);
    // An exact match needs no create row.
    expect(find.textContaining('Create item'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Brass Ferrule');
    await tester.pumpAndSettle();
    expect(find.text('Create item "Brass Ferrule"'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
