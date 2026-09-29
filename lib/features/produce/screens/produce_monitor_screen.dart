import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../production/domain/models/floor_view_models.dart';
import '../../production/providers/batch_flow_provider.dart';
import '../../production/providers/production_provider.dart';
import '../../production/providers/production_run_provider.dart';
import '../../production/widgets/floor_node_terminal.dart';
import '../../production/widgets/inventory_sidebar.dart';
import '../../production/widgets/monitor_action_console.dart';
import '../../production/widgets/monitor_header.dart';
import '../../production/widgets/multi_pipeline_canvas.dart';
import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/pipeline_run.dart';
import '../../production_pipelines/domain/pipeline_template.dart';
import '../data/produce_inventory_repository.dart';
import '../data/produce_sandbox_repository.dart';

/// The live monitor as Produce runs it: the real header, canvas, node terminal,
/// action console and stock sidebar, rebased onto the sandbox.
///
/// The screen's own provider scope is the whole trick. Everything below it
/// resolves [PipelineRunRepository] to [ProduceSandboxRepository] (in memory)
/// and [InventoryRepository] to [ProduceInventoryRepository] (reads real stock,
/// refuses to move it), and gets fresh production providers with no buffer
/// committer — so deploying, assigning stock, moving lots, reconciling a stage
/// and completing a run all work on screen and write nothing anywhere.
class ProduceMonitorScreen extends StatefulWidget {
  const ProduceMonitorScreen({
    super.key,
    required this.run,
    required this.template,
  });

  final PipelineRun run;
  final PipelineTemplate template;

  @override
  State<ProduceMonitorScreen> createState() => _ProduceMonitorScreenState();
}

class _ProduceMonitorScreenState extends State<ProduceMonitorScreen> {
  /// Stamped rather than [ProductionProvider.loadTemplate]'d: loadTemplate
  /// clones the template under a fresh id, which the canvas then cannot match
  /// back to the run's templateId. The order fields are copied so the header
  /// reads right, but never linkedOrderId — that is what drives the real order
  /// lifecycle writes, which a preview has no business making.
  late final ProductionProvider _production = ProductionProvider(
    template: widget.template.copyWith(
      linkedOrderNo: widget.run.orderNo,
      linkedClientName: widget.run.clientName,
    ),
  );

  late final ProductionRunProvider _runProvider = ProductionRunProvider(
    persistActiveRun: false,
  )..initializeIdleRun(widget.run.id);

  late final BatchFlowProvider _batchFlow = BatchFlowProvider();

  @override
  void dispose() {
    _production.dispose();
    _runProvider.dispose();
    _batchFlow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final realInventory = context.read<InventoryRepository>();

    return MultiProvider(
      providers: [
        Provider<PipelineRunRepository>.value(
          value: ProduceSandboxRepository.instance,
        ),
        Provider<InventoryRepository>.value(
          value: ProduceInventoryRepository(realInventory),
        ),
        ChangeNotifierProvider<ProductionProvider>.value(value: _production),
        ChangeNotifierProvider<ProductionRunProvider>.value(value: _runProvider),
        ChangeNotifierProvider<BatchFlowProvider>.value(value: _batchFlow),
      ],
      child: const _ProduceMonitorContent(),
    );
  }
}

class _ProduceMonitorContent extends StatefulWidget {
  const _ProduceMonitorContent();

  @override
  State<_ProduceMonitorContent> createState() => _ProduceMonitorContentState();
}

class _ProduceMonitorContentState extends State<_ProduceMonitorContent> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final productionProvider = Provider.of<ProductionProvider>(context);
    final node = productionProvider.selectedNode;
    final runProvider = Provider.of<ProductionRunProvider>(context, listen: false);
    if (node != null && runProvider.stageId != node.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<ProductionRunProvider>().setActiveStage(node.id);
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
        child: Column(
          children: [
            const _PreviewBanner(),
            Expanded(
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
                                const Positioned.fill(
                                  child: MultiPipelineCanvas(),
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
          ],
        ),
      ),
    );
  }
}

/// Says plainly what the screen is, and gives the pushed route a way back.
class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFEF3C7),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            tooltip: 'Back to Produce',
            color: const Color(0xFF92400E),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.science_outlined, size: 16, color: Color(0xFF92400E)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Produce preview — this monitor runs on sample data. Nothing you '
              'do here is saved, and no stock is moved.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF92400E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
