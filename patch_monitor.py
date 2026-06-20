import sys

with open('lib/features/production/screens/live_production_monitor_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace PipelineCanvas import
content = content.replace("import '../widgets/pipeline_canvas.dart';", "import '../widgets/multi_pipeline_canvas.dart';")

# Replace PipelineCanvas usage
old_canvas = """                          Positioned.fill(
                            child: PipelineCanvas(
                              template: provider.template,
                              selectedNodeId: provider.selectedNodeId,
                              onNodeSelected: (id) => provider.selectNode(id),
                              onNodeDoubleTap: (id) =>
                                  runProvider.openStageActions(id),
                            ),
                          ),"""

new_canvas = """                          const Positioned.fill(
                            child: MultiPipelineCanvas(),
                          ),"""

content = content.replace(old_canvas, new_canvas)

# Remove the run fetching logic from _initializeRun since MultiPipelineCanvas handles it now
old_init = """  Future<void> _initializeRun() async {
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
  }"""

new_init = """  Future<void> _initializeRun() async {
    // Run fetching logic moved to MultiPipelineCanvas
    // This is kept here for backwards compatibility if needed, but MultiPipelineCanvas will set the active run
  }"""

content = content.replace(old_init, new_init)

with open('lib/features/production/screens/live_production_monitor_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("patched")
