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
}
