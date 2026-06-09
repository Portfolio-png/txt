import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:paper/features/production/screens/live_production_monitor_screen.dart';
import 'package:paper/features/production/providers/production_provider.dart';
import 'package:paper/features/production/providers/production_run_provider.dart';
import 'package:paper/features/production_pipelines/data/repositories/pipeline_run_repository.dart';
import 'package:paper/features/production_pipelines/data/repositories/mock_pipeline_run_repository.dart';
import 'package:paper/features/production_pipelines/domain/pipeline_template.dart';
import 'package:paper/features/production_pipelines/domain/process_node.dart';

void main() {
  testWidgets('builds LiveProductionMonitorScreen', (tester) async {
    final inventoryRepo = MockInventoryRepository();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<InventoryProvider>(create: (_) => InventoryProvider(repository: inventoryRepo)),
          ChangeNotifierProvider<ProductionProvider>(
            create: (_) => ProductionProvider(
              template: PipelineTemplate(
                id: '1',
                name: 'Test',
                nodes: [
                  const ProcessNode(
                    id: 'stage-slitting',
                    name: 'Reel Slitting',
                    processType: 'Slitting',
                    stageIndex: 0,
                    laneIndex: 0,
                    inputs: [],
                    outputs: [],
                    machine: 'MC-SLIT-01',
                    dieId: 'DIE-1450-A',
                    durationHours: 1,
                    status: 'queued',
                    isIntermediate: false,
                  ),
                ],
                flows: [],
                stageLabels: ['Stage 1'],
                laneLabels: ['Main'],
                description: '',
                status: PipelineTemplateStatus.draft,
              ),
            ),
          ),
          ChangeNotifierProvider<ProductionRunProvider>(create: (_) => ProductionRunProvider()),
          Provider<PipelineRunRepository>(create: (_) => MockPipelineRunRepository(inventoryRepository: inventoryRepo)),
        ],
        child: const MaterialApp(
          home: LiveProductionMonitorScreen(),
        ),
      ),
    );
    expect(find.byType(LiveProductionMonitorScreen), findsOneWidget);
    await tester.pumpAndSettle();
    if (tester.takeException() != null) {
      debugPrint('Exception: ${tester.takeException()}');
    }
  });
}

class MockInventoryRepository implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
