import 'material_flow.dart';
import 'process_node.dart';

enum PipelineTemplateStatus { draft, active, archived }

class PipelineTemplate {
  const PipelineTemplate({
    required this.id,
    this.factoryId,
    this.shopFloorId,
    required this.name,
    required this.description,
    required this.stageLabels,
    required this.laneLabels,
    required this.nodes,
    required this.flows,
    this.inputMaterial = '',
    this.outputMaterial = '',
    this.status = PipelineTemplateStatus.draft,
    this.linkedOrderId,
    this.linkedOrderNo,
    this.linkedClientName,
  });

  final String id;
  final String? factoryId;
  final String? shopFloorId;
  final String name;
  final String description;
  final List<String> stageLabels;
  final List<String> laneLabels;
  final List<ProcessNode> nodes;
  final List<MaterialFlow> flows;
  final String inputMaterial;
  final String outputMaterial;
  final PipelineTemplateStatus status;
  final int? linkedOrderId;
  final String? linkedOrderNo;
  final String? linkedClientName;

  List<ProcessNode> get stages => nodes;

  factory PipelineTemplate.fromJson(Map<String, dynamic> json) {
    return PipelineTemplate(
      id: json['id'] as String? ?? '',
      factoryId: json['factoryId'] as String? ?? json['factory_id'] as String?,
      shopFloorId:
          json['shopFloorId'] as String? ?? json['shop_floor_id'] as String?,
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
      inputMaterial: json['inputMaterial'] as String? ?? '',
      outputMaterial: json['outputMaterial'] as String? ?? '',
      status: PipelineTemplateStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => PipelineTemplateStatus.draft,
      ),
      linkedOrderId: json['linkedOrderId'] as int?,
      linkedOrderNo: json['linkedOrderNo'] as String?,
      linkedClientName: json['linkedClientName'] as String?,
    );
  }

  PipelineTemplate copyWith({
    String? id,
    String? factoryId,
    String? shopFloorId,
    String? name,
    String? description,
    List<String>? stageLabels,
    List<String>? laneLabels,
    List<ProcessNode>? nodes,
    List<MaterialFlow>? flows,
    String? inputMaterial,
    String? outputMaterial,
    PipelineTemplateStatus? status,
    int? linkedOrderId,
    String? linkedOrderNo,
    String? linkedClientName,
  }) {
    return PipelineTemplate(
      id: id ?? this.id,
      factoryId: factoryId ?? this.factoryId,
      shopFloorId: shopFloorId ?? this.shopFloorId,
      name: name ?? this.name,
      description: description ?? this.description,
      stageLabels: stageLabels ?? this.stageLabels,
      laneLabels: laneLabels ?? this.laneLabels,
      nodes: nodes ?? this.nodes,
      flows: flows ?? this.flows,
      inputMaterial: inputMaterial ?? this.inputMaterial,
      outputMaterial: outputMaterial ?? this.outputMaterial,
      status: status ?? this.status,
      linkedOrderId: linkedOrderId ?? this.linkedOrderId,
      linkedOrderNo: linkedOrderNo ?? this.linkedOrderNo,
      linkedClientName: linkedClientName ?? this.linkedClientName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'factoryId': factoryId,
      'shopFloorId': shopFloorId,
      'name': name,
      'description': description,
      'stageLabels': stageLabels,
      'laneLabels': laneLabels,
      'nodes': nodes.map((node) => node.toJson()).toList(),
      'flows': flows.map((flow) => flow.toJson()).toList(),
      'inputMaterial': inputMaterial,
      'outputMaterial': outputMaterial,
      'status': status.name,
      'linkedOrderId': linkedOrderId,
      'linkedOrderNo': linkedOrderNo,
      'linkedClientName': linkedClientName,
    };
  }
}
