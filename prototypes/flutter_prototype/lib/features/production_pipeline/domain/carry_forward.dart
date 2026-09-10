import '../../sheet_planning/domain/sheet_plan.dart';
import 'pipeline_template.dart';
import 'process_node.dart';

class Carry {
  final int intakeQty;
  final int yieldQty;
  final double yieldPct;
  final double processScrapKg;
  final String? scrapItemName;

  const Carry({
    required this.intakeQty,
    required this.yieldQty,
    required this.yieldPct,
    required this.processScrapKg,
    this.scrapItemName,
  });
}

Map<String, Carry> computePipelineCarry(PipelineTemplate template) {
  final Map<String, Carry> carries = {};

  for (final node in template.nodes) {
    if (node.processType == 'Input') {
      carries[node.id] = const Carry(
        intakeQty: 1,
        yieldQty: 1,
        yieldPct: 100.0,
        processScrapKg: 0.0,
      );
      continue;
    }

    if (node.sheetPlan != null) {
      final plan = node.sheetPlan!;
      final count = pieceCount(plan);
      final weight = calculateWeight(plan);
      carries[node.id] = Carry(
        intakeQty: node.intakeQty,
        yieldQty: count,
        yieldPct: weight.yieldPercent,
        processScrapKg: weight.scrapKg,
        scrapItemName: node.firstOf(AllocKind.scrap),
      );
    } else {
      // 1:1 conversion or assembly pass-through
      final prevFlow = template.flows.cast<PipelineFlow?>().firstWhere(
            (f) => f?.toNodeId == node.id,
            orElse: () => null,
          );
      final prevYield = prevFlow != null && carries.containsKey(prevFlow.fromNodeId)
          ? carries[prevFlow.fromNodeId]!.yieldQty
          : 72;

      carries[node.id] = Carry(
        intakeQty: prevYield,
        yieldQty: prevYield,
        yieldPct: 100.0,
        processScrapKg: 0.0,
      );
    }
  }

  return carries;
}
