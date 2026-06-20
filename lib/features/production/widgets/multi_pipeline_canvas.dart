import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/pipeline_run.dart';
import '../../production_pipelines/domain/pipeline_template.dart';
import '../providers/production_provider.dart';
import '../providers/production_run_provider.dart';
import 'pipeline_run_row.dart';

class MultiPipelineCanvas extends StatefulWidget {
  const MultiPipelineCanvas({super.key});

  @override
  State<MultiPipelineCanvas> createState() => _MultiPipelineCanvasState();
}

class _MultiPipelineCanvasState extends State<MultiPipelineCanvas> {
  int _lastRefreshCount = -1;
  Future<void>? _fetchFuture;
  List<PipelineRun> _runs = [];
  Map<String, PipelineTemplate> _templates = {};

  @override
  Widget build(BuildContext context) {
    final runProvider = context.watch<ProductionRunProvider>();
    final prodProvider = context.watch<ProductionProvider>();

    if (runProvider.refreshCount != _lastRefreshCount) {
      _lastRefreshCount = runProvider.refreshCount;
      _fetchFuture = _fetchData(prodProvider);
    }

    return FutureBuilder<void>(
      future: _fetchFuture,
      builder: (context, snapshot) {
        if (_runs.isEmpty && snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (_runs.isEmpty) {
          return const Center(
            child: Text(
              'No pipelines active for this order.',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: _runs.length,
          itemBuilder: (context, index) {
            final run = _runs[index];
            final template = _templates[run.templateId];
            if (template == null) return const SizedBox.shrink();

            final isRunSelected = runProvider.runId == run.id;
            final selectedNodeId = isRunSelected ? prodProvider.selectedNodeId : null;

            return PipelineRunRow(
              run: run,
              template: template,
              selectedNodeId: selectedNodeId,
              onNodeSelected: (nodeId) {
                if (runProvider.runId != run.id) {
                  runProvider.initializeIdleRun(run.id);
                }
                prodProvider.selectNode(nodeId);
                runProvider.setActiveStage(nodeId);
              },
              onNodeDoubleTap: (nodeId) {
                if (runProvider.runId != run.id) {
                  runProvider.initializeIdleRun(run.id);
                }
                prodProvider.selectNode(nodeId);
                runProvider.openStageActions(nodeId);
              },
            );
          },
        );
      },
    );
  }

  Future<void> _fetchData(ProductionProvider provider) async {
    final repo = context.read<PipelineRunRepository>();
    final orderNo = provider.linkedOrderNo;
    
    if (orderNo == null) {
      if (provider.template != null) {
        // Fallback for non-order context: just show the default template
        if (context.read<ProductionRunProvider>().runId != null) {
           final runId = context.read<ProductionRunProvider>().runId!;
           final run = await repo.getRun(runId);
           if (run != null) {
             _runs = [run];
             _templates = { provider.template.id: provider.template };
           }
        }
      }
      return;
    }

    try {
      final existingRuns = await repo.getRunsForOrder(orderNo);
      
      // If we don't have any runs but we have an order item ID and a template, auto-create one
      if (existingRuns.isEmpty && provider.linkedOrderId != null && provider.template != null) {
         try {
           final newRun = await repo.createRun(
             provider.template.id,
             orderNo: orderNo,
             orderItemId: provider.linkedOrderId,
           );
           existingRuns.add(newRun);
         } catch(e) {
           debugPrint('Auto create run failed: $e');
         }
      }

      _runs = existingRuns;
      
      for (final r in _runs) {
        if (!_templates.containsKey(r.templateId)) {
           final t = await repo.getTemplate(r.templateId);
           if (t != null) _templates[r.templateId] = t;
        }
      }

      if (mounted) {
         // Auto-select the first run if none is active
         final currentRunId = context.read<ProductionRunProvider>().runId;
         if (currentRunId == null && _runs.isNotEmpty) {
            context.read<ProductionRunProvider>().initializeIdleRun(_runs.first.id);
         }
      }
    } catch (e) {
      debugPrint('Failed to fetch order runs: $e');
    }
  }
}
