import 'process_node.dart';

class PipelineFlow {
  final String fromNodeId;
  final String toNodeId;

  const PipelineFlow({
    required this.fromNodeId,
    required this.toNodeId,
  });

  PipelineFlow copyWith({String? fromNodeId, String? toNodeId}) =>
      PipelineFlow(
        fromNodeId: fromNodeId ?? this.fromNodeId,
        toNodeId: toNodeId ?? this.toNodeId,
      );
}

class PipelineTemplate {
  final String id;
  final String name;
  final List<String> stageLabels;
  final List<ProcessNode> nodes;
  final List<PipelineFlow> flows;

  const PipelineTemplate({
    required this.id,
    required this.name,
    this.stageLabels = const [],
    required this.nodes,
    required this.flows,
  });

  PipelineTemplate copyWith({
    String? id,
    String? name,
    List<String>? stageLabels,
    List<ProcessNode>? nodes,
    List<PipelineFlow>? flows,
  }) {
    return PipelineTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      stageLabels: stageLabels ?? this.stageLabels,
      nodes: nodes ?? this.nodes,
      flows: flows ?? this.flows,
    );
  }
}

class PipelineRun {
  final String id;
  final String orderNo;
  final String clientName;
  final String templateId;
  final String createdAt;
  final Map<String, String> nodeStatuses;

  const PipelineRun({
    required this.id,
    required this.orderNo,
    required this.clientName,
    required this.templateId,
    required this.createdAt,
    this.nodeStatuses = const {},
  });
}
