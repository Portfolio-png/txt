import 'barcode_input.dart';
import 'node_run_status.dart';
import 'run_overrides.dart';

class PipelineRun {
  const PipelineRun({
    required this.id,
    required this.templateId,
    required this.templateVersion,
    required this.name,
    required this.status,
    required this.overrides,
    required this.nodeStatuses,
    required this.attachedBarcodeInputs,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
  });

  final String id;
  final String templateId;
  final int templateVersion;
  final String name;
  final String status;
  final RunOverrides overrides;
  final Map<String, NodeRunStatus> nodeStatuses;
  final Map<String, List<BarcodeInput>> attachedBarcodeInputs;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  factory PipelineRun.fromJson(Map<String, dynamic> json) {
    return PipelineRun(
      id: json['id'] as String? ?? '',
      templateId: json['templateId'] as String? ?? '',
      templateVersion: json['templateVersion'] as int? ?? 1,
      name: json['name'] as String? ?? '',
      status: json['status'] as String? ?? 'planned',
      overrides: RunOverrides.fromJson(
        json['overrides'] as Map<String, dynamic>?,
      ),
      nodeStatuses: Map<String, NodeRunStatus>.fromEntries(
        (json['nodeStatuses'] as Map<String, dynamic>? ?? const {}).entries.map(
          (entry) =>
              MapEntry(entry.key, parseNodeRunStatus(entry.value as String?)),
        ),
      ),
      attachedBarcodeInputs: Map<String, List<BarcodeInput>>.fromEntries(
        (json['attachedBarcodeInputs'] as Map<String, dynamic>? ?? const {})
            .entries
            .map(
              (entry) => MapEntry(
                entry.key,
                (entry.value as List<dynamic>? ?? const [])
                    .map(
                      (item) =>
                          BarcodeInput.fromJson(item as Map<String, dynamic>),
                    )
                    .toList(growable: false),
              ),
            ),
      ),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
      completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
    );
  }

  PipelineRun copyWith({
    String? id,
    String? templateId,
    int? templateVersion,
    String? name,
    String? status,
    RunOverrides? overrides,
    Map<String, NodeRunStatus>? nodeStatuses,
    Map<String, List<BarcodeInput>>? attachedBarcodeInputs,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return PipelineRun(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      templateVersion: templateVersion ?? this.templateVersion,
      name: name ?? this.name,
      status: status ?? this.status,
      overrides: overrides ?? this.overrides,
      nodeStatuses: nodeStatuses ?? this.nodeStatuses,
      attachedBarcodeInputs:
          attachedBarcodeInputs ?? this.attachedBarcodeInputs,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'templateId': templateId,
      'templateVersion': templateVersion,
      'name': name,
      'status': status,
      'overrides': overrides.toJson(),
      'nodeStatuses': nodeStatuses.map(
        (key, value) => MapEntry(key, value.value),
      ),
      'attachedBarcodeInputs': attachedBarcodeInputs.map(
        (key, value) => MapEntry(
          key,
          value.map((item) => item.toJson()).toList(growable: false),
        ),
      ),
      'createdAt': createdAt.toIso8601String(),
      'startedAt': startedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
    };
  }
}
