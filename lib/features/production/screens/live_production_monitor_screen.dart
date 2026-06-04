import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/production_provider.dart';
import '../providers/production_run_provider.dart';


import '../widgets/monitor_header.dart';
import '../widgets/pipeline_canvas.dart';
import '../widgets/monitor_action_console.dart';

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

    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          MonitorHeader(provider: provider),
          const SizedBox(height: 24),
          Expanded(
            child: PipelineCanvas(
              template: provider.template,
              selectedNodeId: provider.selectedNodeId,
              onNodeSelected: (id) => provider.selectNode(id),
            ),
          ),
          const SizedBox(height: 24),
          RemoteActionConsole(provider: provider),
        ],
      ),
    );
  }
}
