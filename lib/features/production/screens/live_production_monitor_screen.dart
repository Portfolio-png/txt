import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/production_provider.dart';
import '../providers/production_run_provider.dart';


import '../domain/models/floor_view_models.dart';
import '../widgets/monitor_header.dart';
import '../widgets/pipeline_canvas.dart';
import '../widgets/monitor_action_console.dart';
import '../widgets/floor_node_terminal.dart';

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
    );
  }
}
