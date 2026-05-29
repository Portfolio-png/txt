import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/production_provider.dart';
import '../providers/production_run_provider.dart';
import '../../production_pipelines/domain/process_node.dart';

import '../widgets/monitor_header.dart';
import '../widgets/monitor_flow.dart';
import '../widgets/monitor_metrics_panel.dart';
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
    final node = provider.selectedNode;

    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          MonitorHeader(provider: provider),
          const SizedBox(height: 24),
          MonitorPipelineFlow(provider: provider),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 12,
                  child: _RoutingSpecsPanel(node: node, provider: provider),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 10,
                  child: LiveMetricsPanel(provider: provider),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          RemoteActionConsole(provider: provider),
        ],
      ),
    );
  }
}

class _RoutingSpecsPanel extends StatelessWidget {
  const _RoutingSpecsPanel({required this.node, required this.provider});

  final ProcessNode? node;
  final ProductionProvider provider;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ACTIVE ROUTING SPECS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            node?.name ?? 'No node selected',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 2.5,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              children: [
                _SpecCard(
                  icon: Icons.precision_manufacturing,
                  label: 'TARGET MACHINE',
                  value: node?.machine ?? '--',
                ),
                _SpecCard(
                  icon: Icons.conveyor_belt,
                  label: 'TOOLING / DIE',
                  value: node?.dieId ?? '--',
                ),
                _SpecCard(
                  icon: Icons.input,
                  label: 'INLET MATERIAL',
                  value: node?.inputs.isNotEmpty == true ? node!.inputs.first : '--',
                ),
                _SpecCard(
                  icon: Icons.output,
                  label: 'OUTLET MATERIAL',
                  value: node?.outputs.isNotEmpty == true ? node!.outputs.first : '--',
                ),
              ],
            ),
          ),
          if (node != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PROCESS ACTION',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    node!.processType,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SpecCard extends StatelessWidget {
  const _SpecCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Icon(icon, color: const Color(0xFF2563EB), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
