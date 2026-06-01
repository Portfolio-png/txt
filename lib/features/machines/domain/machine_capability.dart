
class MachineCapability {
  const MachineCapability({
    required this.id,
    required this.processType,
    required this.inputMaterialBarcode,
    required this.inputMaterialName,
    required this.inputUnitId,
    required this.inputUnitLabel,
    required this.outputMaterialBarcode,
    required this.outputMaterialName,
    required this.outputUnitId,
    required this.outputUnitLabel,
    this.dieId,
    this.dieName,
    this.expectedYieldRatio,
    this.conversionFactor,
    this.durationPerUnit,
  });

  final String id;
  final String processType;
  final String inputMaterialBarcode;
  final String inputMaterialName;
  final int inputUnitId;
  final String inputUnitLabel;
  final String outputMaterialBarcode;
  final String outputMaterialName;
  final int outputUnitId;
  final String outputUnitLabel;
  final String? dieId;
  final String? dieName;
  final double? expectedYieldRatio;
  final double? conversionFactor;
  final double? durationPerUnit;

  factory MachineCapability.fromJson(Map<String, dynamic> json) {
    return MachineCapability(
      id: json['id'] as String? ?? '',
      processType: json['processType'] as String? ?? '',
      inputMaterialBarcode: json['inputMaterialBarcode'] as String? ?? '',
      inputMaterialName: json['inputMaterialName'] as String? ?? '',
      inputUnitId: json['inputUnitId'] as int? ?? 0,
      inputUnitLabel: json['inputUnitLabel'] as String? ?? '',
      outputMaterialBarcode: json['outputMaterialBarcode'] as String? ?? '',
      outputMaterialName: json['outputMaterialName'] as String? ?? '',
      outputUnitId: json['outputUnitId'] as int? ?? 0,
      outputUnitLabel: json['outputUnitLabel'] as String? ?? '',
      dieId: json['dieId'] as String?,
      dieName: json['dieName'] as String?,
      expectedYieldRatio: (json['expectedYieldRatio'] as num?)?.toDouble(),
      conversionFactor: (json['conversionFactor'] as num?)?.toDouble(),
      durationPerUnit: (json['durationPerUnit'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'processType': processType,
      'inputMaterialBarcode': inputMaterialBarcode,
      'inputMaterialName': inputMaterialName,
      'inputUnitId': inputUnitId,
      'inputUnitLabel': inputUnitLabel,
      'outputMaterialBarcode': outputMaterialBarcode,
      'outputMaterialName': outputMaterialName,
      'outputUnitId': outputUnitId,
      'outputUnitLabel': outputUnitLabel,
      'dieId': dieId,
      'dieName': dieName,
      'expectedYieldRatio': expectedYieldRatio,
      'conversionFactor': conversionFactor,
      'durationPerUnit': durationPerUnit,
    };
  }

  MachineCapability copyWith({
    String? id,
    String? processType,
    String? inputMaterialBarcode,
    String? inputMaterialName,
    int? inputUnitId,
    String? inputUnitLabel,
    String? outputMaterialBarcode,
    String? outputMaterialName,
    int? outputUnitId,
    String? outputUnitLabel,
    String? dieId,
    String? dieName,
    double? expectedYieldRatio,
    double? conversionFactor,
    double? durationPerUnit,
  }) {
    return MachineCapability(
      id: id ?? this.id,
      processType: processType ?? this.processType,
      inputMaterialBarcode: inputMaterialBarcode ?? this.inputMaterialBarcode,
      inputMaterialName: inputMaterialName ?? this.inputMaterialName,
      inputUnitId: inputUnitId ?? this.inputUnitId,
      inputUnitLabel: inputUnitLabel ?? this.inputUnitLabel,
      outputMaterialBarcode: outputMaterialBarcode ?? this.outputMaterialBarcode,
      outputMaterialName: outputMaterialName ?? this.outputMaterialName,
      outputUnitId: outputUnitId ?? this.outputUnitId,
      outputUnitLabel: outputUnitLabel ?? this.outputUnitLabel,
      dieId: dieId ?? this.dieId,
      dieName: dieName ?? this.dieName,
      expectedYieldRatio: expectedYieldRatio ?? this.expectedYieldRatio,
      conversionFactor: conversionFactor ?? this.conversionFactor,
      durationPerUnit: durationPerUnit ?? this.durationPerUnit,
    );
  }
}
