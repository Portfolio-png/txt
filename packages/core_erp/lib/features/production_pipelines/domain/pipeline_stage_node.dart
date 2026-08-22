import 'package:flutter/foundation.dart';

/// One process node on a pipeline, in the order material passes through it.
///
/// Stage-by-stage Master Data is recorded per node, so the rows are titled from
/// the nodes themselves rather than from the board's column labels. A column
/// label names a position on the canvas ("Stage 2"); a node names the work
/// ("Piercing"), which is what someone reconciling weights is looking for. The
/// [id] rides along so a row stays attached to its node across a rename.
@immutable
class PipelineStageNode {
  const PipelineStageNode({
    required this.id,
    required this.name,
    this.stageIndex = 0,
    this.laneIndex = 0,
  });

  factory PipelineStageNode.fromJson(Map<String, dynamic> json, int fallback) {
    final rawName = json['name']?.toString().trim() ?? '';
    final processType = json['processType']?.toString().trim() ?? '';
    return PipelineStageNode(
      id: json['id']?.toString() ?? 'stage-${fallback + 1}',
      // A node with no name of its own still has to read as something, so its
      // process type stands in before the positional last resort.
      name: rawName.isNotEmpty
          ? rawName
          : (processType.isNotEmpty ? processType : 'Stage ${fallback + 1}'),
      stageIndex: (json['stageIndex'] as num?)?.toInt() ?? fallback,
      laneIndex: (json['laneIndex'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String name;
  final int stageIndex;
  final int laneIndex;

  /// Reading order: down the stages, then across the lanes within a stage.
  static int compare(PipelineStageNode a, PipelineStageNode b) {
    final byStage = a.stageIndex.compareTo(b.stageIndex);
    return byStage != 0 ? byStage : a.laneIndex.compareTo(b.laneIndex);
  }

  /// Parses a template's `nodes` payload into reading order.
  static List<PipelineStageNode> listFromJson(List<dynamic>? nodes) {
    if (nodes == null || nodes.isEmpty) return const <PipelineStageNode>[];
    final parsed = <PipelineStageNode>[];
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node is! Map) continue;
      parsed.add(PipelineStageNode.fromJson(node.cast<String, dynamic>(), i));
    }
    parsed.sort(compare);
    return List<PipelineStageNode>.unmodifiable(parsed);
  }

  @override
  bool operator ==(Object other) =>
      other is PipelineStageNode &&
      other.id == id &&
      other.name == name &&
      other.stageIndex == stageIndex &&
      other.laneIndex == laneIndex;

  @override
  int get hashCode => Object.hash(id, name, stageIndex, laneIndex);
}
