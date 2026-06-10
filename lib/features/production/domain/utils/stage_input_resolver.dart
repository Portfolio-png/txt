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
  if (own.isNotEmpty || node.processType == 'Input') {
    return own;
  }
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
    if (upstream != null && upstream.processType == 'Input') {
      final inherited = run.attachedBarcodeInputs[upstream.id] ?? const [];
      if (inherited.isNotEmpty) {
        return inherited;
      }
    }
  }
  return const [];
}
