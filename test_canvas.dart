import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:paper/features/production/widgets/pipeline_canvas.dart';
import 'package:paper/features/production_pipelines/domain/pipeline_template.dart';
import 'package:paper/features/production_pipelines/domain/process_node.dart';
import 'package:paper/features/production_pipelines/domain/material_flow.dart';
import 'package:paper/features/production/providers/production_run_provider.dart';
import 'package:paper/features/production_pipelines/data/repositories/pipeline_run_repository.dart';
import 'package:paper/features/production_pipelines/data/repositories/mock_pipeline_run_repository.dart';

void main() {
  testWidgets('builds PipelineCanvas with flows', (tester) async {
    final template = PipelineTemplate(
      id: '1', name: 'Test', 
      nodes: [
        ProcessNode.fromJson({
          'id': 'node1', 'name': 'Node 1', 'stageIndex': 0, 'laneIndex': 0, 'inputs': [], 'outputs': [], 'durationHours': 1.0, 'machine': '', 'status': 'active', 'isIntermediate': false, 'hasMachineAssignment': true, 'machineAssignmentLabel': '', 'factoryId': '', 'machineIds': [],
        }),
        ProcessNode.fromJson({
          'id': 'node2', 'name': 'Node 2', 'stageIndex': 1, 'laneIndex': 0, 'inputs': [], 'outputs': [], 'durationHours': 1.0, 'machine': '', 'status': 'active', 'isIntermediate': false, 'hasMachineAssignment': true, 'machineAssignmentLabel': '', 'factoryId': '', 'machineIds': [],
        }),
      ], 
      flows: [
        MaterialFlow.fromJson({
          'id': 'flow1', 'fromNodeId': 'node1', 'toNodeId': 'node2', 'materialId': 'mat1', 'quantity': 10, 'isReversed': false, 'status': 'active',
        }),
      ], 
      stageLabels: ['Stage 1', 'Stage 2'], laneLabels: [], description: '', status: PipelineTemplateStatus.draft, 
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProductionRunProvider>(create: (_) => ProductionRunProvider()),
          Provider<PipelineRunRepository>(create: (_) => MockPipelineRunRepository(inventoryRepository: MockInventoryRepository())),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PipelineCanvas(
              template: template,
              selectedNodeId: null,
              onNodeSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byType(PipelineCanvas), findsOneWidget);
  });
}

class MockInventoryRepository implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
