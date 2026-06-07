import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/item_asset.dart';
import 'package:paper/app/shell/navigation_provider.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/domain/item_inputs.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/units/data/repositories/unit_repository.dart';
import 'package:core_erp/features/units/domain/unit_definition.dart';
import 'package:core_erp/features/units/domain/unit_inputs.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:paper/features/production/providers/production_provider.dart';
import 'package:paper/features/production/providers/production_run_provider.dart';
import 'package:paper/features/production/providers/pipeline_editor_provider.dart';
import 'package:paper/features/production/screens/floor_view_screen.dart';
import 'package:paper/features/production/screens/pipeline_builder_screen.dart';
import 'package:paper/features/production/screens/pipelines_screen.dart';
import 'package:paper/features/production_pipelines/data/default_pipeline_templates.dart';
import 'package:paper/features/production_pipelines/data/repositories/pipeline_run_repository.dart';
import 'package:paper/features/production_pipelines/domain/material_flow.dart';
import 'package:paper/features/production_pipelines/domain/node_run_status.dart';
import 'package:paper/features/production_pipelines/domain/pipeline_run.dart';
import 'package:paper/features/production_pipelines/domain/pipeline_template.dart';
import 'package:paper/features/production_pipelines/domain/process_node.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/inventory/domain/material_record.dart';
import '../../widget_test.dart';

void main() {
  test('sheet metal process template keeps the requested floor context', () {
    expect(sheetMetalPipelineTemplate.factoryId, '1');
    expect(sheetMetalPipelineTemplate.shopFloorId, '1');
    expect(sheetMetalPipelineTemplate.stageLabels, [
      'Input Stage',
      'Blank Cutting',
      'Piercing',
      'Bending',
      'Drilling',
      'Packaging',
    ]);
    expect(sheetMetalPipelineTemplate.nodes.map((node) => node.machine), [
      'Input Stage',
      'Blank Cutting',
      'Handpress',
      'PP',
      'Drill Machine',
      'Packaging',
    ]);
    expect(sheetMetalPipelineTemplate.flows.length, 5);
  });

  test('process node persists optional machine group assignment', () {
    final node = _testTemplate().nodes.single.copyWith(
      machineGroupId: 2,
      machineGroupName: 'Press Brake Group',
    );

    final restored = ProcessNode.fromJson(node.toJson());
    final legacy = ProcessNode.fromJson({
      'id': 'legacy',
      'name': 'Legacy Node',
      'processType': 'Action',
      'stageIndex': 0,
      'laneIndex': 0,
      'inputs': const <String>[],
      'outputs': const <String>[],
      'machine': '',
      'dieId': '',
      'durationHours': 1,
      'status': 'Ready',
      'isIntermediate': false,
    });

    expect(restored.machineGroupId, 2);
    expect(restored.machineGroupName, 'Press Brake Group');
    expect(restored.hasMachineAssignment, isTrue);
    expect(legacy.machineGroupId, isNull);
    expect(legacy.machineGroupName, isNull);
  });

  testWidgets('builder renders the current graph editor surface', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final provider = ProductionProvider.seeded();
    final editor = PipelineEditorProvider(template: _testTemplate());
    addTearDown(provider.dispose);
    addTearDown(editor.dispose);

    await tester.pumpWidget(
      _ProductionHarness(
        provider: provider,
        editor: editor,
        child: const PipelineBuilderScreen(
          factoryId: 'default',
          shopFloorId: 'floor-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Demo Fabrication Pipeline'), findsOneWidget);
    expect(find.text('Pipeline Control'), findsOneWidget);
    expect(find.text('Laser Cut'), findsWidgets);
  });

  testWidgets('builder add node action updates the editor provider', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final provider = ProductionProvider.seeded();
    final editor = PipelineEditorProvider(template: _testTemplate());
    addTearDown(provider.dispose);
    addTearDown(editor.dispose);

    await tester.pumpWidget(
      _ProductionHarness(
        provider: provider,
        editor: editor,
        child: const PipelineBuilderScreen(
          factoryId: 'default',
          shopFloorId: 'floor-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final initialCount = editor.template.nodes.length;
    await tester.tap(find.text('Add Step'));
    await tester.pumpAndSettle();

    expect(editor.template.nodes.length, initialCount + 1);
    expect(find.text('Process ${initialCount + 1}'), findsWidgets);
  });

  testWidgets('builder details action updates pipeline metadata', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final provider = ProductionProvider.seeded();
    final editor = PipelineEditorProvider(template: _testTemplate());
    addTearDown(provider.dispose);
    addTearDown(editor.dispose);

    await tester.pumpWidget(
      _ProductionHarness(
        provider: provider,
        editor: editor,
        child: const PipelineBuilderScreen(
          factoryId: 'default',
          shopFloorId: 'floor-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Details'));
    await tester.pumpAndSettle();

    expect(find.text('Pipeline Details'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Pipeline Name'),
      'Precision Forming Line',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Short Description'),
      'High priority production route',
    );
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(editor.template.name, 'Precision Forming Line');
    expect(editor.template.description, 'High priority production route');
    expect(find.text('Precision Forming Line'), findsOneWidget);
  });

  testWidgets('builder details popup selects item masters for materials', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final provider = ProductionProvider.seeded();
    final editor = PipelineEditorProvider(template: _testTemplate());
    addTearDown(provider.dispose);
    addTearDown(editor.dispose);

    await tester.pumpWidget(
      _ProductionHarness(
        provider: provider,
        editor: editor,
        child: const PipelineBuilderScreen(
          factoryId: 'default',
          shopFloorId: 'floor-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Details'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('pipeline-details-input-material-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sheet Metal (kg)').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('pipeline-details-output-material-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blank Profile (g)').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(editor.template.inputMaterial, 'Sheet Metal');
    expect(editor.template.outputMaterial, 'Blank Profile');
  });

  testWidgets('pipeline create dialog uses searchable item master pickers', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final provider = ProductionProvider.seeded();
    final editor = PipelineEditorProvider(template: _testTemplate());
    addTearDown(provider.dispose);
    addTearDown(editor.dispose);

    await tester.pumpWidget(
      _ProductionHarness(
        provider: provider,
        editor: editor,
        pipelineRunRepository: _FakePipelineRunRepository(),
        child: const PipelinesScreen(shopFloorId: 'floor-1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Pipeline'));
    await tester.pumpAndSettle();

    expect(find.text('Create New Pipeline'), findsOneWidget);
    expect(find.text('Sheet Metal (kg)'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('create-pipeline-input-item-field')),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextField, 'Search item master'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Search item master'),
      'Custom Resin',
    );
    await tester.pumpAndSettle();

    expect(find.text('Create item "Custom Resin"'), findsOneWidget);
  });

  testWidgets('production pipelines screen is run only for saved routes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final provider = ProductionProvider.seeded();
    final editor = PipelineEditorProvider(template: _testTemplate());
    addTearDown(provider.dispose);
    addTearDown(editor.dispose);

    final activeTemplate = _mappedFloorTemplate().copyWith(
      name: 'Active Production Route',
      status: PipelineTemplateStatus.active,
    );
    final draftTemplate = _testTemplate().copyWith(
      id: 'draft-production-route',
      name: 'Draft Production Route',
      status: PipelineTemplateStatus.draft,
    );
    final archivedTemplate = _testTemplate().copyWith(
      id: 'archived-production-route',
      name: 'Archived Production Route',
      status: PipelineTemplateStatus.archived,
    );

    await tester.pumpWidget(
      _ProductionHarness(
        provider: provider,
        editor: editor,
        pipelineRunRepository: _FakePipelineRunRepository(
          seedTemplates: [activeTemplate, draftTemplate, archivedTemplate],
        ),
        child: const PipelinesScreen(
          shopFloorId: 'floor-1',
          mode: PipelinesScreenMode.production,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Production'), findsOneWidget);
    expect(find.text('Active Production Route'), findsOneWidget);
    expect(find.text('Draft Production Route'), findsOneWidget);
    expect(find.text('Archived Production Route'), findsNothing);
    expect(find.text('New Pipeline'), findsNothing);
    expect(find.text('Create Pipeline'), findsNothing);
    expect(find.byTooltip('Edit pipeline'), findsNothing);
    expect(find.byTooltip('Duplicate Pipeline'), findsNothing);
    expect(find.text('Run'), findsNWidgets(2));
  });

  testWidgets('builder header adds connected next step', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final provider = ProductionProvider.seeded();
    final editor = PipelineEditorProvider(template: _testTemplate());
    addTearDown(provider.dispose);
    addTearDown(editor.dispose);

    await tester.pumpWidget(
      _ProductionHarness(
        provider: provider,
        editor: editor,
        child: const PipelineBuilderScreen(
          factoryId: 'default',
          shopFloorId: 'floor-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pipeline Control'), findsOneWidget);

    await tester.tap(find.text('Add Step'));
    await tester.pumpAndSettle();

    expect(editor.template.nodes.length, 2);
    expect(editor.template.flows.length, 1);
    expect(editor.template.flows.single.fromNodeId, 'node-cut');
    expect(
      editor.template.flows.single.toNodeId,
      editor.template.nodes.last.id,
    );
  });

  test('editor canvas actions duplicate and disconnect selected node', () {
    final editor = PipelineEditorProvider(template: _mappedFloorTemplate());
    addTearDown(editor.dispose);

    editor.selectNode('mapped-form');
    editor.duplicateSelectedNode();

    expect(editor.template.nodes.length, 4);
    expect(editor.selectedNode?.name, 'Brake Form Copy');

    editor.selectNode('mapped-form');
    editor.disconnectSelectedNode();

    expect(
      editor.template.flows.any(
        (flow) =>
            flow.fromNodeId == 'mapped-form' || flow.toNodeId == 'mapped-form',
      ),
      isFalse,
    );
  });

  test('editor deletes node and auto-heals sequential flows', () {
    final editor = PipelineEditorProvider(template: _mappedFloorTemplate());
    addTearDown(editor.dispose);

    // Initial state: mapped-cut -> mapped-form -> mapped-qa
    expect(editor.template.nodes.length, 3);
    expect(editor.template.flows.length, 2);

    editor.selectNode('mapped-form');
    editor.deleteSelectedNode();

    // After deleting mapped-form, it should auto-heal by connecting mapped-cut directly to mapped-qa
    expect(editor.template.nodes.length, 2);
    expect(editor.template.flows.length, 1);
    expect(editor.template.flows.first.fromNodeId, 'mapped-cut');
    expect(editor.template.flows.first.toNodeId, 'mapped-qa');
    expect(editor.template.flows.first.materialName, 'Blank');
  });

  testWidgets('builder sidebar shows selected node summary only', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final provider = ProductionProvider.seeded();
    final editor = PipelineEditorProvider(template: _testTemplate());
    addTearDown(provider.dispose);
    addTearDown(editor.dispose);

    await tester.pumpWidget(
      _ProductionHarness(
        provider: provider,
        editor: editor,
        child: const PipelineBuilderScreen(
          factoryId: 'default',
          shopFloorId: 'floor-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Laser Cut'), findsWidgets);
    expect(find.text('Machine Group'), findsOneWidget);
    expect(find.text('LC-01'), findsWidgets);
    expect(find.text('Apply Node Changes'), findsNothing);
    expect(find.textContaining('Use the floating toolbar'), findsOneWidget);
  });

  testWidgets('builder pins input and output stages while middle scrolls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final provider = ProductionProvider.seeded();
    final editor = PipelineEditorProvider(template: _pinnedEndpointTemplate());
    addTearDown(provider.dispose);
    addTearDown(editor.dispose);

    await tester.pumpWidget(
      _ProductionHarness(
        provider: provider,
        editor: editor,
        child: const PipelineBuilderScreen(
          factoryId: 'default',
          shopFloorId: 'floor-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final inputFinder = find.byKey(
      const ValueKey('pipeline-pinned-input-stage'),
    );
    final outputFinder = find.byKey(
      const ValueKey('pipeline-pinned-output-stage'),
    );
    final middleFinder = find.byKey(
      const ValueKey('pipeline-middle-stage-scroll'),
    );

    expect(inputFinder, findsOneWidget);
    expect(outputFinder, findsOneWidget);
    expect(middleFinder, findsOneWidget);

    final inputTop = tester.getTopLeft(inputFinder).dy;
    final outputTop = tester.getTopLeft(outputFinder).dy;

    await tester.drag(middleFinder, const Offset(0, -260));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(inputFinder).dy, moreOrLessEquals(inputTop));
    expect(tester.getTopLeft(outputFinder).dy, moreOrLessEquals(outputTop));
  });

  testWidgets('builder keeps default inserted process node white', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final provider = ProductionProvider.seeded();
    final editor = PipelineEditorProvider(
      template: _defaultInsertedProcessTemplate(),
    );
    addTearDown(provider.dispose);
    addTearDown(editor.dispose);

    await tester.pumpWidget(
      _ProductionHarness(
        provider: provider,
        editor: editor,
        child: const PipelineBuilderScreen(
          factoryId: 'default',
          shopFloorId: 'floor-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Default Inserted Process'), findsWidgets);

    final hasEndpointFill = tester
        .widgetList<Container>(find.byType(Container))
        .any((container) {
          final decoration = container.decoration;
          return decoration is BoxDecoration &&
              (decoration.color == const Color(0xFFDBEAFE) ||
                  decoration.color == const Color(0xFFD1FAE5));
        });
    expect(hasEndpointFill, isFalse);
  });

  testWidgets('builder edit dialog assigns input and output item masters', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final provider = ProductionProvider.seeded();
    final editor = PipelineEditorProvider(template: _testTemplate());
    addTearDown(provider.dispose);
    addTearDown(editor.dispose);

    await tester.pumpWidget(
      _ProductionHarness(
        provider: provider,
        editor: editor,
        child: const PipelineBuilderScreen(
          factoryId: 'default',
          shopFloorId: 'floor-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Laser Cut').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pipeline-node-input-item')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sheet Metal (kg)').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pipeline-node-output-item')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blank Profile (g)').last);
    await tester.pumpAndSettle();

    final node = editor.template.nodes.singleWhere(
      (node) => node.id == 'node-cut',
    );
    expect(node.inputItem?.itemName, 'Sheet Metal');
    expect(node.outputItem?.itemName, 'Blank Profile');
    expect(node.inputs, ['Sheet Metal']);
    expect(node.outputs, ['Blank Profile']);
    expect(find.text('Apply Node Changes'), findsNothing);
  });

  testWidgets('builder assigns machine group to selected process', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final provider = ProductionProvider.seeded();
    final editor = PipelineEditorProvider(template: _testTemplate());
    addTearDown(provider.dispose);
    addTearDown(editor.dispose);

    await tester.pumpWidget(
      _ProductionHarness(
        provider: provider,
        editor: editor,
        child: const PipelineBuilderScreen(
          factoryId: 'default',
          shopFloorId: 'floor-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Laser Cut').first);
    await tester.pumpAndSettle();

    final nodeFinder = find.byKey(
      const ValueKey('pipeline-node-machine-group'),
    );
    await tester.ensureVisible(nodeFinder);
    await tester.pumpAndSettle();

    await tester.tap(nodeFinder);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Kraft').last);
    await tester.tap(find.text('Kraft').last);
    await tester.pumpAndSettle();

    final node = editor.template.nodes.singleWhere(
      (node) => node.id == 'node-cut',
    );
    expect(node.machineGroupId, 2);
    expect(node.machineGroupName, 'Kraft');
    expect(find.text('Kraft'), findsWidgets);
  });

  testWidgets('floor map renders saved pipeline templates as live routes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));

    await tester.pumpWidget(
      MaterialApp(
        home: FloorViewScreen(pipelineTemplates: [_mappedFloorTemplate()]),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Mapped Finishing Route'), findsWidgets);
    expect(find.text('Saved floor pipelines'), findsOneWidget);
    expect(find.textContaining('3 stations'), findsWidgets);
  });
}

class _ProductionHarness extends StatelessWidget {
  const _ProductionHarness({
    required this.provider,
    required this.editor,
    required this.child,
    this.pipelineRunRepository,
  });

  final ProductionProvider provider;
  final PipelineEditorProvider editor;
  final Widget child;
  final PipelineRunRepository? pipelineRunRepository;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ProductionProvider>.value(value: provider),
        ChangeNotifierProvider<ProductionRunProvider>(
          create: (_) => ProductionRunProvider(),
        ),
        ChangeNotifierProvider<PipelineEditorProvider>.value(value: editor),
        ChangeNotifierProvider<NavigationProvider>(
          create: (_) => NavigationProvider(),
        ),
        Provider<PipelineRunRepository>.value(
          value: pipelineRunRepository ?? _FakePipelineRunRepository(),
        ),
        ChangeNotifierProvider<UnitsProvider>(
          create: (_) => UnitsProvider(
            repository: _FakeUnitRepository(_unitDefinitions()),
          ),
        ),
        ChangeNotifierProvider<GroupsProvider>(
          create: (_) => GroupsProvider(repository: FakeGroupRepository()),
        ),
        ChangeNotifierProvider<ItemsProvider>(
          create: (_) =>
              ItemsProvider(repository: _FakeItemRepository(_itemMasters())),
        ),
        ChangeNotifierProvider<InventoryProvider>(
          create: (_) => InventoryProvider(
            repository: FakeInventoryRepository(
              seedMaterials: [
                MaterialRecord(
                  id: 1,
                  barcode: 'Sheet Metal',
                  name: 'Sheet Metal',
                  type: 'Raw Material',
                  grade: 'A1',
                  thickness: '1.2 mm',
                  supplier: 'Seed Supplier',
                  unitId: 1,
                  unit: 'kg',
                  createdAt: DateTime(2026),
                  kind: 'parent',
                  parentBarcode: null,
                  numberOfChildren: 0,
                  linkedChildBarcodes: const [],
                  scanCount: 0,
                  linkedItemId: 1,
                ),
                MaterialRecord(
                  id: 2,
                  barcode: 'Blank Profile',
                  name: 'Blank Profile',
                  type: 'Raw Material',
                  grade: 'A1',
                  thickness: '1.2 mm',
                  supplier: 'Seed Supplier',
                  unitId: 2,
                  unit: 'g',
                  createdAt: DateTime(2026),
                  kind: 'parent',
                  parentBarcode: null,
                  numberOfChildren: 0,
                  linkedChildBarcodes: const [],
                  scanCount: 0,
                  linkedItemId: 2,
                ),
              ],
            ),
          )..initialize(),
        ),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }
}

class _FakePipelineRunRepository implements PipelineRunRepository {
  _FakePipelineRunRepository({List<PipelineTemplate> seedTemplates = const []})
    : _templates = List<PipelineTemplate>.from(seedTemplates);

  final List<PipelineTemplate> _templates;

  @override
  Future<List<PipelineTemplate>> getTemplates() async =>
      List<PipelineTemplate>.from(_templates);

  @override
  Future<PipelineTemplate> createTemplate(PipelineTemplate template) async {
    _templates.add(template);
    return template;
  }

  @override
  Future<PipelineTemplate> updateTemplate(PipelineTemplate template) async {
    final index = _templates.indexWhere((item) => item.id == template.id);
    if (index == -1) {
      _templates.add(template);
    } else {
      _templates[index] = template;
    }
    return template;
  }

  @override
  Future<PipelineTemplate?> getTemplate(String id) async {
    for (final template in _templates) {
      if (template.id == id) {
        return template;
      }
    }
    return null;
  }

  @override
  Future<List<PipelineRun>> getRuns({String? templateId}) async => const [];

  @override
  Future<PipelineRun> createRun(String templateId, {String? name, int? orderItemId, String? orderNo}) {
    throw UnimplementedError();
  }

  @override
  Future<List<PipelineRun>> getRunsForOrder(String orderNo) async => const [];

  @override
  Future<PipelineRun?> getRun(String id) async => null;

  @override
  Future<PipelineRun> updateNodeStatus({
    required String runId,
    required String nodeId,
    required NodeRunStatus status,
    double? actualDurationHours,
    int? batchQuantity,
    String? machineOverride,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<PipelineRun> attachBarcodeToRunNode({
    required String runId,
    required String nodeId,
    required String barcode,
  }) {
    throw UnimplementedError();
  }
}

PipelineTemplate _testTemplate() {
  return const PipelineTemplate(
    id: 'tpl-test',
    shopFloorId: 'floor-1',
    name: 'Demo Fabrication Pipeline',
    description: 'Widget-test pipeline',
    stageLabels: ['Cut', 'Form'],
    laneLabels: ['Main'],
    nodes: [
      ProcessNode(
        id: 'node-cut',
        name: 'Laser Cut',
        processType: 'Cutting',
        stageIndex: 0,
        laneIndex: 0,
        inputs: ['Sheet'],
        outputs: ['Blank'],
        machine: 'LC-01',
        dieId: '',
        durationHours: 1,
        status: 'Ready',
        isIntermediate: false,
      ),
    ],
    flows: [],
  );
}

PipelineTemplate _mappedFloorTemplate() {
  return const PipelineTemplate(
    id: 'mapped-route',
    shopFloorId: 'floor-1',
    name: 'Mapped Finishing Route',
    description: 'Saved pipeline rendered on the floor map',
    stageLabels: ['Cut', 'Form', 'QA'],
    laneLabels: ['Main'],
    nodes: [
      ProcessNode(
        id: 'mapped-cut',
        name: 'Laser Nesting',
        processType: 'Cutting',
        stageIndex: 0,
        laneIndex: 0,
        inputs: ['Sheet'],
        outputs: ['Blank'],
        machine: 'LC-01',
        dieId: '',
        durationHours: 1,
        status: 'Active',
        isIntermediate: false,
      ),
      ProcessNode(
        id: 'mapped-form',
        name: 'Brake Form',
        processType: 'Forming',
        stageIndex: 1,
        laneIndex: 0,
        inputs: ['Blank'],
        outputs: ['Formed Part'],
        machine: 'PB-02',
        dieId: '',
        durationHours: 1,
        status: 'Waiting',
        isIntermediate: false,
      ),
      ProcessNode(
        id: 'mapped-qa',
        name: 'QA Gate',
        processType: 'Inspection',
        stageIndex: 2,
        laneIndex: 0,
        inputs: ['Formed Part'],
        outputs: ['Released Part'],
        machine: 'QA-01',
        dieId: '',
        durationHours: 1,
        status: 'Ready',
        isIntermediate: false,
      ),
    ],
    flows: [
      MaterialFlow(
        id: 'flow-cut-form',
        fromNodeId: 'mapped-cut',
        toNodeId: 'mapped-form',
        materialName: 'Blank',
      ),
      MaterialFlow(
        id: 'flow-form-qa',
        fromNodeId: 'mapped-form',
        toNodeId: 'mapped-qa',
        materialName: 'Formed Part',
      ),
    ],
  );
}

PipelineTemplate _pinnedEndpointTemplate() {
  final nodes = List<ProcessNode>.generate(12, (index) {
    final isInput = index == 0;
    final isOutput = index == 11;
    return ProcessNode(
      id: 'pinned-node-$index',
      name: isInput
          ? 'Input Stage'
          : isOutput
          ? 'Output Stage'
          : 'Process Stage ${index + 1}',
      processType: isInput
          ? 'Input'
          : isOutput
          ? 'Output'
          : 'Process',
      stageIndex: index,
      laneIndex: 0,
      inputs: const ['Material'],
      outputs: const ['Material'],
      machine: 'MC-${index + 1}',
      dieId: '',
      durationHours: 1,
      status: 'Ready',
      isIntermediate: false,
    );
  });

  return PipelineTemplate(
    id: 'tpl-pinned-endpoints',
    shopFloorId: 'floor-1',
    name: 'Pinned Endpoint Pipeline',
    description: 'Pipeline with fixed endpoint stages',
    stageLabels: List<String>.generate(12, (index) {
      if (index == 0) {
        return 'Input';
      }
      if (index == 11) {
        return 'Output';
      }
      return 'Stage ${index + 1}';
    }),
    laneLabels: const ['Main'],
    nodes: nodes,
    flows: List<MaterialFlow>.generate(
      11,
      (index) => MaterialFlow(
        id: 'pinned-flow-$index',
        fromNodeId: 'pinned-node-$index',
        toNodeId: 'pinned-node-${index + 1}',
        materialName: 'Material',
      ),
    ),
  );
}

PipelineTemplate _defaultInsertedProcessTemplate() {
  return const PipelineTemplate(
    id: 'tpl-default-inserted-process',
    shopFloorId: 'floor-1',
    name: 'Default Inserted Process Pipeline',
    description: 'Normal inserted process node with default IO text',
    stageLabels: ['Process'],
    laneLabels: ['Main'],
    nodes: [
      ProcessNode(
        id: 'default-inserted-process',
        name: 'Default Inserted Process',
        processType: 'Action',
        stageIndex: 0,
        laneIndex: 0,
        inputs: ['Input'],
        outputs: ['Output'],
        machine: 'MC-NEW',
        dieId: '',
        durationHours: 1,
        status: 'Ready',
        isIntermediate: false,
      ),
    ],
    flows: [],
  );
}

class _FakeUnitRepository implements UnitRepository {
  const _FakeUnitRepository(this.seedUnits);

  final List<UnitDefinition> seedUnits;

  @override
  Future<void> init() async {}

  @override
  Future<List<UnitDefinition>> getUnits() async =>
      List<UnitDefinition>.from(seedUnits);

  @override
  Future<UnitDefinition> createUnit(CreateUnitInput input) {
    throw UnimplementedError();
  }

  @override
  Future<UnitDefinition> updateUnit(UpdateUnitInput input) {
    throw UnimplementedError();
  }

  @override
  Future<UnitDefinition> archiveUnit(int id) {
    throw UnimplementedError();
  }

  @override
  Future<UnitDefinition> restoreUnit(int id) {
    throw UnimplementedError();
  }
}

class _FakeItemRepository implements ItemRepository {
  const _FakeItemRepository(this.seedItems);

  final List<ItemDefinition> seedItems;

  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async =>
      List<ItemDefinition>.from(seedItems);

  @override
  Future<ItemDefinition> createItem(CreateItemInput input) {
    throw UnimplementedError();
  }

  @override
  Future<ItemDefinition> updateItem(UpdateItemInput input) {
    throw UnimplementedError();
  }

  @override
  Future<ItemDefinition> archiveItem(int id) {
    throw UnimplementedError();
  }

  @override
  Future<ItemDefinition> restoreItem(int id) {
    throw UnimplementedError();
  }

  @override
  Future<List<ItemAsset>> getItemAssets(int itemId) async => const [];

  @override
  Future<ItemAssetUploadIntent> createAssetUploadIntent(
    ItemAssetUploadIntentInput input,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<ItemAsset> completeAssetUpload(CompleteItemAssetUploadInput input) {
    throw UnimplementedError();
  }

  @override
  Future<ItemAsset> setPrimaryAsset(int assetId) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteAsset(int assetId) {
    throw UnimplementedError();
  }
}

List<UnitDefinition> _unitDefinitions() {
  final now = DateTime(2026);
  return [
    UnitDefinition(
      id: 1,
      name: 'Kilogram',
      symbol: 'kg',
      notes: '',
      unitGroupId: 1,
      unitGroupName: 'Mass',
      conversionFactor: 1,
      conversionBaseUnitId: null,
      conversionBaseUnitName: null,
      isArchived: false,
      usageCount: 0,
      createdAt: now,
      updatedAt: now,
    ),
    UnitDefinition(
      id: 2,
      name: 'Gram',
      symbol: 'g',
      notes: '',
      unitGroupId: 1,
      unitGroupName: 'Mass',
      conversionFactor: 0.001,
      conversionBaseUnitId: 1,
      conversionBaseUnitName: 'Kilogram',
      isArchived: false,
      usageCount: 0,
      createdAt: now,
      updatedAt: now,
    ),
  ];
}

List<ItemDefinition> _itemMasters() {
  final now = DateTime(2026);
  return [
    ItemDefinition(
      id: 1,
      name: 'Sheet Metal',
      alias: '',
      displayName: 'Sheet Metal',
      quantity: 0,
      groupId: 1,
      unitId: 1,
      isArchived: false,
      usageCount: 0,
      createdAt: now,
      updatedAt: now,
      variationTree: const [],
    ),
    ItemDefinition(
      id: 2,
      name: 'Blank Profile',
      alias: '',
      displayName: 'Blank Profile',
      quantity: 0,
      groupId: 1,
      unitId: 2,
      isArchived: false,
      usageCount: 0,
      createdAt: now,
      updatedAt: now,
      variationTree: const [],
    ),
  ];
}
