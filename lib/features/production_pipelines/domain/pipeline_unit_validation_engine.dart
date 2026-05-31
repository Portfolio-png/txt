import 'package:core_erp/features/units/domain/unit_definition.dart';

import 'material_flow.dart';
import 'pipeline_template.dart';
import 'process_node.dart';

enum PipelineUnitIssueKind {
  missingMetadata,
  unitConversion,
  materialTransform,
}

class PipelineUnitIssue {
  const PipelineUnitIssue({
    required this.kind,
    required this.flow,
    required this.source,
    required this.target,
    required this.message,
    this.multiplier,
  });

  final PipelineUnitIssueKind kind;
  final MaterialFlow flow;
  final ProcessNode source;
  final ProcessNode target;
  final String message;
  final double? multiplier;

  bool get insertsBridge =>
      kind == PipelineUnitIssueKind.unitConversion ||
      kind == PipelineUnitIssueKind.materialTransform;
}

class PipelineUnitValidationResult {
  const PipelineUnitValidationResult({required this.issues});

  final List<PipelineUnitIssue> issues;

  bool get hasWarnings => issues.isNotEmpty;

  List<PipelineUnitIssue> get bridgeIssues =>
      issues.where((issue) => issue.insertsBridge).toList(growable: false);
}

class PipelineUnitValidationEngine {
  const PipelineUnitValidationEngine();

  PipelineUnitValidationResult validate(
    PipelineTemplate template,
    List<UnitDefinition> units,
  ) {
    final nodesById = {for (final node in template.nodes) node.id: node};
    final unitsById = {for (final unit in units) unit.id: unit};
    final issues = <PipelineUnitIssue>[];

    for (final flow in template.flows) {
      final source = nodesById[flow.fromNodeId];
      final target = nodesById[flow.toNodeId];
      if (source == null || target == null) {
        continue;
      }

      final sourceItem = source.outputItem;
      final targetItem = target.inputItem;
      if (sourceItem == null || targetItem == null) {
        issues.add(
          PipelineUnitIssue(
            kind: PipelineUnitIssueKind.missingMetadata,
            flow: flow,
            source: source,
            target: target,
            message:
                'Assign output item on ${source.name} and input item on ${target.name}.',
          ),
        );
        continue;
      }

      final sourceUnit = unitsById[sourceItem.unitId];
      final targetUnit = unitsById[targetItem.unitId];
      if (sourceUnit == null || targetUnit == null) {
        issues.add(
          PipelineUnitIssue(
            kind: PipelineUnitIssueKind.missingMetadata,
            flow: flow,
            source: source,
            target: target,
            message:
                'Unit metadata is missing for ${sourceItem.itemName} or ${targetItem.itemName}.',
          ),
        );
        continue;
      }

      if (sourceUnit.id == targetUnit.id) {
        continue;
      }

      final sourceGroupId = sourceUnit.unitGroupId;
      final targetGroupId = targetUnit.unitGroupId;
      if (sourceGroupId != null && sourceGroupId == targetGroupId) {
        issues.add(
          PipelineUnitIssue(
            kind: PipelineUnitIssueKind.unitConversion,
            flow: flow,
            source: source,
            target: target,
            multiplier:
                sourceUnit.conversionFactor / targetUnit.conversionFactor,
            message:
                'Convert ${sourceUnit.symbol} to ${targetUnit.symbol} before ${target.name}.',
          ),
        );
        continue;
      }

      issues.add(
        PipelineUnitIssue(
          kind: PipelineUnitIssueKind.materialTransform,
          flow: flow,
          source: source,
          target: target,
          message:
              'Define a material transform from ${sourceItem.itemName} to ${targetItem.itemName}.',
        ),
      );
    }

    return PipelineUnitValidationResult(issues: issues);
  }
}
