import 'material_flow.dart';
import 'process_node.dart';

class PipelineTemplate {
  const PipelineTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.stageLabels,
    required this.laneLabels,
    required this.nodes,
    required this.flows,
  });

  final String id;
  final String name;
  final String description;
  final List<String> stageLabels;
  final List<String> laneLabels;
  final List<ProcessNode> nodes;
  final List<MaterialFlow> flows;

  PipelineTemplate copyWith({
    String? id,
    String? name,
    String? description,
    List<String>? stageLabels,
    List<String>? laneLabels,
    List<ProcessNode>? nodes,
    List<MaterialFlow>? flows,
  }) {
    return PipelineTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      stageLabels: stageLabels ?? this.stageLabels,
      laneLabels: laneLabels ?? this.laneLabels,
      nodes: nodes ?? this.nodes,
      flows: flows ?? this.flows,
    );
  }
}
