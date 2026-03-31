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

  factory PipelineTemplate.fromJson(Map<String, dynamic> json) {
    return PipelineTemplate(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      stageLabels: List<String>.from(
        json['stageLabels'] as List<dynamic>? ?? const [],
      ),
      laneLabels: List<String>.from(
        json['laneLabels'] as List<dynamic>? ?? const [],
      ),
      nodes: (json['nodes'] as List<dynamic>? ?? const [])
          .map((item) => ProcessNode.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      flows: (json['flows'] as List<dynamic>? ?? const [])
          .map((item) => MaterialFlow.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'stageLabels': stageLabels,
      'laneLabels': laneLabels,
      'nodes': nodes.map((node) => node.toJson()).toList(),
      'flows': flows.map((flow) => flow.toJson()).toList(),
    };
  }
}
