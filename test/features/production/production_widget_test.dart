import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper/features/production/providers/production_provider.dart';
import 'package:paper/features/production/providers/production_run_provider.dart';
import 'package:paper/features/production/providers/pipeline_editor_provider.dart';
import 'package:paper/features/production/screens/floor_view_screen.dart';
import 'package:paper/features/production/screens/pipeline_builder_screen.dart';
import 'package:paper/features/production_pipelines/domain/material_flow.dart';
import 'package:paper/features/production_pipelines/domain/pipeline_template.dart';
import 'package:paper/features/production_pipelines/domain/process_node.dart';
import 'package:provider/provider.dart';

void main() {
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
        child: const PipelineBuilderScreen(shopFloorId: 'floor-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Demo Fabrication Pipeline'), findsOneWidget);
    expect(
      find.text(
        'Route builder: drag stages across the floor sequence, click a node to edit.',
      ),
      findsOneWidget,
    );
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
        child: const PipelineBuilderScreen(shopFloorId: 'floor-1'),
      ),
    );
    await tester.pumpAndSettle();

    final initialCount = editor.template.nodes.length;
    await tester.tap(find.text('Add Node'));
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
        child: const PipelineBuilderScreen(shopFloorId: 'floor-1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Details'));
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

  testWidgets('builder control panel adds stage lane and connected next step', (
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
        child: const PipelineBuilderScreen(shopFloorId: 'floor-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pipeline Control'), findsOneWidget);

    await tester.tap(find.text('Add Stage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Lane'));
    await tester.pumpAndSettle();

    expect(editor.template.stageLabels.length, 3);
    expect(editor.template.laneLabels.length, 2);

    await tester.tap(find.text('Add Next Step'));
    await tester.pumpAndSettle();

    expect(editor.template.nodes.length, 2);
    expect(editor.template.flows.length, 1);
    expect(editor.template.flows.single.fromNodeId, 'node-cut');
    expect(
      editor.template.flows.single.toNodeId,
      editor.template.nodes.last.id,
    );
  });

  testWidgets('builder control panel edits selected node inline', (
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
        child: const PipelineBuilderScreen(shopFloorId: 'floor-1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Node Name'),
      'Precision Laser Cut',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Action'),
      'Laser profiling',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Inputs'),
      'Sheet, Nesting Program',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Outputs'),
      'Profiled Blank',
    );
    final applyButton = find.ancestor(
      of: find.text('Apply Node Changes'),
      matching: find.byType(InkWell),
    );
    await tester.ensureVisible(applyButton);
    await tester.tap(applyButton);
    await tester.pumpAndSettle();

    final updated = editor.template.nodes.first;
    expect(updated.name, 'Precision Laser Cut');
    expect(updated.processType, 'Laser profiling');
    expect(updated.inputs, ['Sheet', 'Nesting Program']);
    expect(updated.outputs, ['Profiled Blank']);
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
    expect(find.text('Saved shop-floor pipelines'), findsOneWidget);
    expect(find.textContaining('3 stations'), findsWidgets);
  });
}

class _ProductionHarness extends StatelessWidget {
  const _ProductionHarness({
    required this.provider,
    required this.editor,
    required this.child,
  });

  final ProductionProvider provider;
  final PipelineEditorProvider editor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ProductionProvider>.value(value: provider),
        ChangeNotifierProvider<ProductionRunProvider>(
          create: (_) => ProductionRunProvider(),
        ),
        ChangeNotifierProvider<PipelineEditorProvider>.value(value: editor),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
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
