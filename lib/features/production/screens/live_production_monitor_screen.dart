import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/production_provider.dart';
import '../providers/production_run_provider.dart';
import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';


import '../domain/models/floor_view_models.dart';
import '../widgets/monitor_header.dart';
import '../widgets/pipeline_canvas.dart';
import '../widgets/monitor_action_console.dart';
import '../widgets/floor_node_terminal.dart';
import '../widgets/inventory_sidebar.dart';

class LiveProductionMonitorScreen extends StatelessWidget {
  const LiveProductionMonitorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LiveMonitorContent();
  }
}

class _LiveMonitorContent extends StatefulWidget {
  const _LiveMonitorContent();

  @override
  State<_LiveMonitorContent> createState() => _LiveMonitorContentState();
}

class _LiveMonitorContentState extends State<_LiveMonitorContent> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeRun();
      }
    });
  }

  Future<void> _initializeRun() async {
    final productionProvider = context.read<ProductionProvider>();
    final runProvider = context.read<ProductionRunProvider>();
    final repo = context.read<PipelineRunRepository>();

    if (runProvider.runId != null) return;

    final template = productionProvider.template;
    final orderNo = productionProvider.linkedOrderNo;
    final orderItemId = productionProvider.linkedOrderId;

    if (orderNo != null) {
      try {
        final existingRuns = await repo.getRunsForOrder(orderNo);
        final activeRun = existingRuns
            .where((r) => r.templateId == template.id && r.status != 'completed')
            .firstOrNull;
        if (activeRun != null) {
          runProvider.initializeIdleRun(activeRun.id);
          return;
        }
      } catch (e) {
        debugPrint('Error fetching existing runs: $e');
      }
    }

    try {
      final newRun = await repo.createRun(
        template.id,
        orderNo: orderNo,
        orderItemId: orderItemId,
      );
      runProvider.initializeIdleRun(newRun.id);
    } catch (e) {
      try {
        await repo.createTemplate(template);
        final newRun = await repo.createRun(
          template.id,
          orderNo: orderNo,
          orderItemId: orderItemId,
        );
        runProvider.initializeIdleRun(newRun.id);
      } catch (err) {
        debugPrint('Failed to auto-create run: $err');
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final productionProvider = Provider.of<ProductionProvider>(context);
    final node = productionProvider.selectedNode;
    final runProvider = Provider.of<ProductionRunProvider>(context, listen: false);
    if (node != null && runProvider.stageId != node.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<ProductionRunProvider>().updateExpectedAssets(
            stageId: node.id,
            machineId: node.machine,
            dieId: node.dieId,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductionProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    MonitorHeader(provider: provider),
                    const SizedBox(height: 24),
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: PipelineCanvas(
                              template: provider.template,
                              selectedNodeId: provider.selectedNodeId,
                              onNodeSelected: (id) => provider.selectNode(id),
                            ),
                          ),
                          if (provider.selectedNode != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: FloorNodeTerminal(
                                node: provider.selectedNode!,
                                tokens: FloorOpsTokens.factoryMap,
                                onClose: () => provider.clearNodeSelection(),
                                startedAt: provider.nodeStartedAt,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    RemoteActionConsole(provider: provider),
                  ],
                ),
              ),
            ),
            const InventorySidebar(),
          ],
        ),
      ),
    );
  }
}
