import '../../../production_pipelines/domain/barcode_input.dart';
import '../../../production_pipelines/domain/pipeline_run.dart';
import '../../../production_pipelines/domain/pipeline_template.dart';
import '../../../production_pipelines/domain/process_node.dart';

/// Inputs allotted to a stage. Stock assigned to the pipeline's Input
/// endpoint automatically defines the input of the stage it feeds, so a
/// stage without an assignment of its own inherits the stock attached to
/// its directly-upstream Input endpoint.
List<BarcodeInput> effectiveStageInputs({
  required PipelineRun? run,
  required ProcessNode node,
  required PipelineTemplate template,
}) {
  if (run == null) {
    return const [];
  }
  final own = run.attachedBarcodeInputs[node.id] ?? const [];
  if (own.isNotEmpty) {
    return own;
  }
  if (node.processType == 'Input') {
    return own;
  }

  final resolvedInputs = <BarcodeInput>[];
  for (final flow in template.flows) {
    if (flow.toNodeId != node.id) {
      continue;
    }
    ProcessNode? upstream;
    for (final candidate in template.nodes) {
      if (candidate.id == flow.fromNodeId) {
        upstream = candidate;
        break;
      }
    }
    if (upstream != null) {
      final upstreamInputs = effectiveStageInputs(
        run: run,
        node: upstream,
        template: template,
      );

      if (upstreamInputs.isEmpty) continue;

      final metrics = run.nodeMetrics[upstream.id] ?? const {};
      final outputQty = (metrics['output'] as num?)?.toDouble();

      if (outputQty != null) {
        double totalUpstreamQty = 0;
        for (final input in upstreamInputs) {
          totalUpstreamQty += input.quantity ?? 0;
        }

        for (final input in upstreamInputs) {
          double newQty;
          if (totalUpstreamQty > 0) {
            newQty = (input.quantity ?? 0) * (outputQty / totalUpstreamQty);
          } else {
            newQty = outputQty / upstreamInputs.length;
          }
          resolvedInputs.add(BarcodeInput(
            barcode: input.barcode,
            materialName: input.materialName,
            materialType: input.materialType,
            scanCount: input.scanCount,
            quantity: newQty,
            unit: input.unit,
          ));
        }
      } else {
        resolvedInputs.addAll(upstreamInputs);
      }
    }
  }
  return resolvedInputs;
}
