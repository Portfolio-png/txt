import 'package:flutter/material.dart';

import 'barcode_input.dart';

class ProcessNode {
  const ProcessNode({
    required this.id,
    required this.name,
    required this.processType,
    required this.stageIndex,
    required this.laneIndex,
    required this.inputs,
    required this.outputs,
    required this.machine,
    required this.durationHours,
    required this.status,
    required this.isIntermediate,
    this.scannedInputs = const [],
  });

  final String id;
  final String name;
  final String processType;
  final int stageIndex;
  final int laneIndex;
  final List<String> inputs;
  final List<String> outputs;
  final String machine;
  final double durationHours;
  final String status;
  final bool isIntermediate;
  final List<BarcodeInput> scannedInputs;

  factory ProcessNode.fromJson(Map<String, dynamic> json) {
    return ProcessNode(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      processType: json['processType'] as String? ?? '',
      stageIndex: json['stageIndex'] as int? ?? 0,
      laneIndex: json['laneIndex'] as int? ?? 0,
      inputs: List<String>.from(json['inputs'] as List<dynamic>? ?? const []),
      outputs: List<String>.from(json['outputs'] as List<dynamic>? ?? const []),
      machine: json['machine'] as String? ?? '',
      durationHours: (json['durationHours'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? 'Queued',
      isIntermediate: json['isIntermediate'] as bool? ?? false,
      scannedInputs: (json['scannedInputs'] as List<dynamic>? ?? const [])
          .map((item) => BarcodeInput.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  ProcessNode copyWith({
    String? id,
    String? name,
    String? processType,
    int? stageIndex,
    int? laneIndex,
    List<String>? inputs,
    List<String>? outputs,
    String? machine,
    double? durationHours,
    String? status,
    bool? isIntermediate,
    List<BarcodeInput>? scannedInputs,
  }) {
    return ProcessNode(
      id: id ?? this.id,
      name: name ?? this.name,
      processType: processType ?? this.processType,
      stageIndex: stageIndex ?? this.stageIndex,
      laneIndex: laneIndex ?? this.laneIndex,
      inputs: inputs ?? this.inputs,
      outputs: outputs ?? this.outputs,
      machine: machine ?? this.machine,
      durationHours: durationHours ?? this.durationHours,
      status: status ?? this.status,
      isIntermediate: isIntermediate ?? this.isIntermediate,
      scannedInputs: scannedInputs ?? this.scannedInputs,
    );
  }

  Color get statusColor {
    switch (status.toLowerCase()) {
      case 'ready':
        return const Color(0xFF16A34A);
      case 'blocked':
        return const Color(0xFFDC2626);
      case 'active':
        return const Color(0xFF2563EB);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'processType': processType,
      'stageIndex': stageIndex,
      'laneIndex': laneIndex,
      'inputs': inputs,
      'outputs': outputs,
      'machine': machine,
      'durationHours': durationHours,
      'status': status,
      'isIntermediate': isIntermediate,
      'scannedInputs': scannedInputs.map((item) => item.toJson()).toList(),
    };
  }
}
